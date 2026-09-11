namespace Lumoria.Application {

    public enum InstallKind {
        FULL,
        ACTION,
        REDIST,
        SCRIPT
    }

    public enum InstallStatus {
        PENDING,
        RUNNING,
        SUCCEEDED,
        FAILED,
        CANCELLED
    }

    public class InstallSession : Object {
        public string id { get; private set; }
        public InstallKind kind { get; set; default = InstallKind.FULL; }
        public InstallStatus status { get; set; default = InstallStatus.PENDING; }
        public string prefix_id { get; set; default = ""; }
        public string label { get; set; default = ""; }
        public double fraction { get; set; default = 0; }
        public string step { get; set; default = ""; }
        public string message { get; set; default = ""; }
        public string log_path { get; set; default = ""; }
        public bool created_prefix { get; set; default = false; }
        public Cancellable cancellable { get; default = new Cancellable (); }
        public Runtime.InstallProgress progress { get; default = new Runtime.InstallProgress (); }

        public signal void changed ();
        public signal void finished (bool success);

        private bool finished_emitted = false;

        public bool is_active {
            get { return status == InstallStatus.PENDING || status == InstallStatus.RUNNING; }
        }

        public void emit_finished (bool success) {
            if (finished_emitted) return;
            finished_emitted = true;
            finished (success);
        }

        construct {
            id = "%08x".printf ((uint32) Random.next_int ());
            progress.step_changed.connect ((desc) => {
                Idle.add (() => {
                    step = desc;
                    if (status == InstallStatus.PENDING) status = InstallStatus.RUNNING;
                    changed ();
                    return false;
                });
            });
            progress.progress_changed.connect ((frac) => {
                Idle.add (() => {
                    fraction = frac;
                    if (status == InstallStatus.PENDING) status = InstallStatus.RUNNING;
                    changed ();
                    return false;
                });
            });
            progress.log_ready.connect ((path) => {
                Idle.add (() => {
                    log_path = path;
                    changed ();
                    return false;
                });
            });
            progress.install_finished.connect ((success, user_message) => {
                Idle.add (() => {
                    if (cancellable.is_cancelled ()) {
                        status = InstallStatus.CANCELLED;
                    } else if (success) {
                        status = InstallStatus.SUCCEEDED;
                    } else {
                        status = InstallStatus.FAILED;
                        var text = user_message.make_valid ().strip ();
                        message = text != "" ? text : _("See the log for details.");
                    }
                    changed ();
                    emit_finished (success);
                    return false;
                });
            });
        }

        public void cancel () {
            if (!is_active || cancellable.is_cancelled ()) return;
            cancellable.cancel ();
            step = _("Cancelling...");
            changed ();
        }
    }

    public class InstallService : Object {
        public signal void session_started (InstallSession session);
        public signal void session_finished (InstallSession session, bool success);

        private Context ctx;
        public InstallSession? active { get; private set; }

        public InstallService (Context ctx) {
            this.ctx = ctx;
        }

        public InstallSession install (Models.PrefixEntry entry, bool created_prefix) {
            var session = make_session (InstallKind.FULL, entry, _("Installing %s").printf (entry.display_name ()));
            session.created_prefix = created_prefix;
            try {
                PrefixService.reject_prefixes_root (entry.resolved_path ());
            } catch (Error e) {
                fail_immediately (session, user_error (e));
                return session;
            }
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                fail_immediately (session, _("Install blocked in gamescope"));
                return session;
            }
            start (session, entry, (session, work) => {
                Runtime.run_full_install (Runtime.InstallOptions.from_prefix (work), session.progress, session.cancellable);
            });
            return session;
        }

        public void run_action_now (
            Models.PrefixEntry entry,
            string action_id,
            Runtime.InstallProgress? progress = null,
            Models.ManifestAction? spec = null
        ) throws Error {
            if (!ctx.try_begin (ExclusiveKind.INSTALL)) {
                throw new LumoriaError.BUSY (ctx.exclusive_busy_message ());
            }
            try {
                Runtime.run_manifest_action (
                    entry, ctx.runner_manifests, ctx.launcher_manifests, action_id,
                    progress ?? new Runtime.InstallProgress (), null, spec
                );
                ctx.prefixes.save ();
            } finally {
                ctx.end_session (ExclusiveKind.INSTALL);
            }
        }

        public InstallSession run_action (
            Models.PrefixEntry entry,
            string action_id,
            Models.ManifestAction? spec = null
        ) {
            return start_kind (InstallKind.ACTION, entry, _("Running action"), (session, work) => {
                Runtime.run_manifest_action (
                    work, ctx.runner_manifests, ctx.launcher_manifests, action_id,
                    session.progress, session.cancellable, spec
                );
            });
        }

        public InstallSession run_redist (Models.PrefixEntry entry, string redist_id) {
            return start_kind (InstallKind.REDIST, entry, _("Installing package"), (session, work) => {
                Runtime.run_redist_install (work, ctx.runner_manifests, redist_id, session.progress, session.cancellable);
            });
        }

        public InstallSession? rerun_script (Models.PrefixEntry entry, string instance_id) {
            var found = Runtime.load_post_install (entry, instance_id);
            if (found == null) {
                ctx.show_toast (_("Post-install script not found."));
                return null;
            }
            if (!found.spec.reinstallable) {
                ctx.show_toast (_("This script cannot be rerun."));
                return null;
            }
            return start_kind (InstallKind.SCRIPT, entry, _("Running script"), (session, work) => {
                Runtime.run_post_install_script (work, instance_id, session.progress, session.cancellable);
            });
        }

        /* Runs on the worker with the session and a private copy of the prefix; the live entry is only touched on main. */
        private delegate void InstallWork (InstallSession session, Models.PrefixEntry scratch) throws Error;

        private InstallSession start_kind (
            InstallKind kind,
            Models.PrefixEntry entry,
            string label,
            owned InstallWork work
        ) {
            var session = make_session (kind, entry, label);
            start (session, entry, (owned) work);
            return session;
        }

        private InstallSession make_session (InstallKind kind, Models.PrefixEntry entry, string label) {
            var session = new InstallSession ();
            session.kind = kind;
            session.prefix_id = entry.id;
            session.label = label;
            return session;
        }

        private void fail_immediately (InstallSession session, string message) {
            session.message = message;
            session.status = InstallStatus.FAILED;
            session_started (session);
            Idle.add (() => {
                session.changed ();
                session.emit_finished (false);
                if (active == session) active = null;
                session_finished (session, false);
                return false;
            });
        }

        private void start (InstallSession session, Models.PrefixEntry entry, owned InstallWork work) {
            if (!ctx.try_begin (ExclusiveKind.INSTALL)) {
                fail_immediately (session, ctx.exclusive_busy_message ());
                return;
            }
            try {
                Models.ManifestRepository.shared ().require_valid ();
            } catch (Error e) {
                ctx.end_session (ExclusiveKind.INSTALL);
                fail_immediately (session, user_error (e));
                return;
            }
            /* The worker mutates scratch; the live entry only takes it on success (or for scripts), otherwise it is restored from baseline. */
            var scratch = entry.snapshot ();
            var baseline = entry.snapshot ();
            active = session;
            ctx.state.set_busy (session.label);
            session_started (session);
            session.finished.connect ((success) => {
                if (active == session) active = null;
                ctx.state.clear_busy ();
                ctx.end_session (ExclusiveKind.INSTALL);
                ctx.runtime.flush_persist ();
                var installed = ctx.registry.by_id (session.prefix_id);
                var keep_result = success || session.kind == InstallKind.SCRIPT;
                if (installed != null) installed.apply_runtime_state (keep_result ? scratch : baseline);
                try {
                    ctx.prefixes.save ();
                } catch (Error e) {
                    warning ("Failed to save prefix after install: %s", e.message);
                    ctx.show_toast (user_error (e));
                }
                var cache = Utils.StorageCache.instance ();
                if (keep_result) {
                    cache.invalidate (Utils.StorageCategory.RUNNERS);
                    cache.invalidate (Utils.StorageCategory.COMPONENTS);
                    cache.invalidate (Utils.StorageCategory.CACHE_RUNNERS);
                    cache.invalidate (Utils.StorageCategory.CACHE_COMPONENTS);
                    cache.invalidate (Utils.StorageCategory.CACHE_INSTALLER);
                    cache.invalidate (Utils.StorageCategory.CACHE_REDIST);
                }
                if (installed != null) {
                    cache.refresh_prefix (installed);
                    ctx.actions.invalidate (installed.id);
                    ctx.actions.refresh_remotes (installed);
                }
                session_finished (session, success);
            });
            Utils.run_background ("install-session", () => {
                work (session, scratch);
            }, (error) => {
                if (error == null) return;
                if (session.status != InstallStatus.PENDING && session.status != InstallStatus.RUNNING) return;
                session.message = user_error (error);
                session.status = session.cancellable.is_cancelled ()
                    ? InstallStatus.CANCELLED
                    : InstallStatus.FAILED;
                session.changed ();
                session.emit_finished (false);
            });
        }
    }
}
