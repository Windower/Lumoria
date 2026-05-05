namespace Lumoria.Runtime {

    public class InstallOptions : Object {
        public string prefix_path { get; set; default = ""; }
        public string runner_id { get; set; default = ""; }
        public string runner_version { get; set; default = "latest"; }
        public string variant_id { get; set; default = ""; }
        public string wine_arch { get; set; default = ""; }
        public string wine_debug { get; set; default = ""; }
        public bool? wine_wayland = null;
        public string launcher_id { get; set; default = ""; }
        public string post_install_spec_path { get; set; default = ""; }
        public string post_install_spec_uri { get; set; default = ""; }
        public Models.PrefixEntry? prefix_entry { get; set; default = null; }
    }

    public class InstallProgress : Object {
        public signal void step_changed (string description);
        public signal void progress_changed (double fraction);
        public signal void log_message (string message);
        public signal void install_finished (bool success, string message);
    }

    private class StepReporter : Object {
        public int total { get; private set; }
        public InstallProgress progress { get; private set; }
        public RuntimeLog logger { get; private set; }
        public Cancellable? cancellable { get; private set; }
        public int idx { get; private set; }

        public StepReporter (
            int total,
            InstallProgress progress,
            RuntimeLog logger,
            Cancellable? cancellable
        ) {
            this.total = total;
            this.progress = progress;
            this.logger = logger;
            this.cancellable = cancellable;
            this.idx = 0;
        }

        public void label (string text) throws IOError {
            advance ();
            emit_progress (text);
        }

        public void run_step (
            Models.InstallStep step,
            Gee.HashMap<string, string> vars,
            WinePaths paths,
            WineEnv env,
            bool ignore_when = false
        ) throws Error {
            advance ();
            emit_progress (step.description);
            logger.step (idx, total, step.description, step.step_type);
            var step_env = step.env.size > 0 ? env.copy () : env;
            if (step.env.size > 0) apply_env_rules (step_env, step.env, vars);
            run_install_step (step, vars, paths, step_env, logger, cancellable, ignore_when);
        }

        public void run_download (Models.DownloadItem dl, Gee.HashMap<string, string> vars) throws Error {
            advance ();
            ensure_download_item (dl, expand_path (dl.url, vars), expand_path (dl.dest, vars), idx, total, progress, logger);
        }

        public DownloadProgress download_progress_cb () {
            var sig = progress;
            int total_steps = total;
            int slot = idx;
            return (downloaded, total_bytes) => {
                if (total_bytes <= 0) return;
                var base_p = (double) (slot - 1) / total_steps;
                var range = 1.0 / total_steps;
                sig.progress_changed (base_p + (double) downloaded / (double) total_bytes * range);
            };
        }

        private void advance () throws IOError {
            check_cancelled (cancellable);
            idx++;
        }

        private void emit_progress (string text) {
            progress.step_changed ("(%d/%d) %s".printf (idx, total, text));
            progress.progress_changed ((double) (idx - 1) / total);
        }
    }

    private class ResolvedRedistSet : Object {
        public Gee.ArrayList<Models.RedistSpec> specs { get; private set; }
        public Gee.ArrayList<Models.InstallStep> code_steps { get; private set; }
        public Gee.ArrayList<Models.DownloadItem> downloads { get; private set; }
        public int step_count { get; private set; }

        public ResolvedRedistSet () {
            specs = new Gee.ArrayList<Models.RedistSpec> ();
            code_steps = new Gee.ArrayList<Models.InstallStep> ();
            downloads = new Gee.ArrayList<Models.DownloadItem> ();
            step_count = 0;
        }

        public static ResolvedRedistSet resolve (
            Gee.Iterable<string> redist_ids,
            Gee.Map<string, Models.RedistSpec> all
        ) {
            var set = new ResolvedRedistSet ();
            var deferred = new Gee.ArrayList<Models.RedistSpec> ();
            var seen = new Gee.HashSet<string> ();
            resolve_into (set, deferred, redist_ids, all, seen);
            foreach (var spec in deferred) {
                set.specs.add (spec);
                set.downloads.add_all (spec.downloads);
                set.step_count += spec.downloads.size + spec.steps.size;
            }
            return set;
        }

        private static void resolve_into (
            ResolvedRedistSet set,
            Gee.ArrayList<Models.RedistSpec> deferred,
            Gee.Iterable<string> redist_ids,
            Gee.Map<string, Models.RedistSpec> all,
            Gee.HashSet<string> seen
        ) {
            foreach (var rid in redist_ids) {
                if (!seen.add (rid)) continue;
                if (all.has_key (rid)) {
                    var spec = all[rid];
                    if (spec.redists.size > 0)
                        resolve_into (set, deferred, spec.redists, all, seen);
                    if (spec.defer) {
                        deferred.add (spec);
                    } else {
                        set.specs.add (spec);
                        set.downloads.add_all (spec.downloads);
                        set.step_count += spec.downloads.size + spec.steps.size;
                    }
                } else {
                    var step = new Models.InstallStep ();
                    step.step_type = "redist";
                    step.command = rid;
                    step.description = builtin_redist_label (rid);
                    set.code_steps.add (step);
                    set.step_count++;
                }
            }
        }
    }

    private class InstallPhase : Object {
        public Gee.ArrayList<Models.DownloadItem> downloads { get; private set; }
        public Gee.ArrayList<Models.InstallStep> steps { get; private set; }
        public ResolvedRedistSet redists { get; private set; }
        public Gee.HashMap<string, string> vars { get; private set; }
        public Models.PrefixEntry? prefix_entry { get; private set; }
        public bool reinstall_mode { get; private set; }

        public InstallPhase (
            Gee.ArrayList<Models.DownloadItem> downloads,
            Gee.ArrayList<Models.InstallStep> steps,
            ResolvedRedistSet redists,
            Gee.HashMap<string, string> vars,
            Models.PrefixEntry? prefix_entry = null,
            bool reinstall_mode = false
        ) {
            this.downloads = downloads;
            this.steps = steps;
            this.redists = redists;
            this.vars = vars;
            this.prefix_entry = prefix_entry;
            this.reinstall_mode = reinstall_mode;
        }

        public int step_count {
            get {
                int count = redists.step_count;
                foreach (var dl in downloads) {
                    if (dl.when == null || dl.when.evaluate (vars)) count++;
                }
                foreach (var step in steps) {
                    if (step.when == null || step.when.evaluate (vars)) count++;
                }
                return count;
            }
        }

        public void run_downloads (StepReporter rep, string phase_banner) throws Error {
            rep.logger.phase (phase_banner);
            foreach (var dl in redists.downloads) {
                if (dl.when != null && !dl.when.evaluate (vars)) continue;
                rep.run_download (dl, vars);
            }
            foreach (var dl in downloads) {
                if (dl.when != null && !dl.when.evaluate (vars)) continue;
                rep.run_download (dl, vars);
            }
        }

        public void run_steps (
            StepReporter rep,
            WinePaths paths,
            WineEnv env,
            string? phase_banner
        ) throws Error {
            if (phase_banner != null) rep.logger.phase (phase_banner);
            foreach (var spec in redists.specs) {
                if (spec.defer) continue;
                run_redist_spec (rep, spec, paths, env);
            }
            foreach (var step in redists.code_steps) {
                rep.run_step (step, vars, paths, env);
                mark_redist_installed (prefix_entry, step.command);
            }
            foreach (var step in steps) rep.run_step (step, vars, paths, env);
            // Deferred specs run AFTER installer steps but still while wineserver
            // is alive: dropping native DLLs after wineserver -k lets the next
            // wine bootstrap reinitialize the prefix and clobber them.
            foreach (var spec in redists.specs) {
                if (!spec.defer) continue;
                run_redist_spec (rep, spec, paths, env);
            }
        }

        private void run_redist_spec (
            StepReporter rep,
            Models.RedistSpec spec,
            WinePaths paths,
            WineEnv env
        ) throws Error {
            rep.logger.banner (spec.display_label ());
            var redist_env = spec.env.size > 0 ? env.copy () : env;
            if (spec.env.size > 0) apply_env_rules (redist_env, spec.env, vars);
            bool spec_force = reinstall_mode && spec.reinstallable;
            foreach (var step in spec.steps) {
                rep.run_step (step, vars, paths, redist_env, spec_force && step.idempotent);
            }
            mark_redist_installed (prefix_entry, spec.id);
        }
    }

    private void mark_redist_installed (Models.PrefixEntry? entry, string redist_id) {
        if (entry == null || redist_id == "") return;
        if (entry.installed_redists.contains (redist_id)) return;
        entry.installed_redists.add (redist_id);
    }

    public void run_full_install (
        InstallOptions opts,
        InstallProgress progress,
        Cancellable? cancellable
    ) {
        var logger = RuntimeLog.for_install (opts.prefix_path, (msg) => {
            progress.log_message (msg);
        });

        try {
            write_install_header (logger, opts);

            var installer_spec = Models.InstallerSpec.load_from_resource ();
            var launcher = find_launcher_spec (opts.launcher_id);
            var post_install_spec = opts.post_install_spec_path != ""
                ? Models.PostInstallSpec.load_from_file (opts.post_install_spec_path)
                : null;

            var all_redists = Models.RedistSpec.load_all_from_resource ();
            var launcher_redists = ResolvedRedistSet.resolve (
                merged_redist_ids (installer_spec.redists, launcher),
                all_redists
            );
            var post_redists = post_install_spec != null
                ? ResolvedRedistSet.resolve (post_install_spec.redists, all_redists)
                : new ResolvedRedistSet ();

            const int FIXED_STEPS = 5;
            int total_steps = FIXED_STEPS
                + installer_spec.downloads.size + installer_spec.steps.size
                + (launcher != null ? launcher.downloads.size + launcher.steps.size : 0)
                + launcher_redists.step_count
                + (post_install_spec != null
                    ? 1 + post_install_spec.downloads.size + post_install_spec.steps.size + post_redists.step_count
                    : 0);

            var rep = new StepReporter (total_steps, progress, logger, cancellable);

            rep.label ("Preparing runner\u2026");
            var runner_spec = Models.RunnerSpec.find_or_default (
                Models.RunnerSpec.filter_for_host (Models.RunnerSpec.load_all_from_resource ()),
                opts.runner_id
            );
            logger.emit_line ("Using runner: %s %s\n".printf (
                runner_spec.display_label (),
                Utils.Preferences.resolve_version (opts.runner_id, opts.runner_version)
            ));

            rep.label ("Downloading %s\u2026".printf (runner_spec.display_label ()));
            var prefix_entry = opts.prefix_entry ?? Models.PrefixRegistry
                .load (Utils.prefix_registry_path ())
                .by_path (opts.prefix_path);
            var runtime = prepare_wine_runtime (
                runner_spec, opts.variant_id, opts.runner_version,
                opts.prefix_path, opts.wine_arch,
                opts.prefix_entry != null ? opts.prefix_entry.sync_mode : "",
                opts.wine_debug, opts.wine_wayland,
                prefix_entry != null ? prefix_entry.runtime_env_vars : null,
                rep.download_progress_cb (),
                logger
            );
            log_runtime_paths (logger, runtime);

            var pfx_path = runtime.prefix_path;
            var paths = runtime.paths;
            var env = runtime.env;

            var installer_vars = make_install_vars (pfx_path, "installer", installer_spec.id, installer_spec.variables);
            inject_redist_vars (installer_vars, launcher_redists);
            inject_prefix_context (installer_vars, runtime, prefix_entry, logger);
            apply_env_rules (env, installer_spec.env, installer_vars);

            var launcher_vars = launcher != null
                ? make_install_vars (pfx_path, "launchers", launcher.id, launcher.variables)
                : null;
            if (launcher_vars != null) {
                inject_redist_vars (launcher_vars, launcher_redists);
                inject_prefix_context (launcher_vars, runtime, prefix_entry, logger);
                apply_env_rules (env, launcher.env, launcher_vars);
            }

            var post_install_vars = post_install_spec != null
                ? build_post_install_vars (
                    pfx_path,
                    ensure_cache_subdir ("post-install", post_install_spec.id),
                    installer_spec, launcher, post_install_spec
                )
                : null;
            if (post_install_vars != null) {
                inject_redist_vars (post_install_vars, post_redists);
                inject_prefix_context (post_install_vars, runtime, prefix_entry, logger);
                apply_env_rules (env, post_install_spec.env, post_install_vars);
            }

            var installer_phase = new InstallPhase (
                installer_spec.downloads, installer_spec.steps,
                new ResolvedRedistSet (), installer_vars, prefix_entry
            );
            var launcher_phase = launcher != null
                ? new InstallPhase (
                    launcher.downloads, launcher.steps,
                    launcher_redists, launcher_vars, prefix_entry
                )
                : null;
            var post_phase = post_install_spec != null
                ? new InstallPhase (
                    post_install_spec.downloads, post_install_spec.steps,
                    post_redists, post_install_vars, prefix_entry
                )
                : null;

            installer_phase.run_downloads (rep, "Downloading installer artifacts");
            if (launcher_phase != null) {
                launcher_phase.run_downloads (rep, "Downloading launcher artifacts");
            }
            if (post_phase != null) {
                post_phase.run_downloads (rep, "Downloading post install artifacts");
            }

            rep.label ("Predownloading enabled components\u2026");
            logger.banner ("Predownloading enabled components");
            predownload_enabled_components (null, logger);

            rep.label ("Creating wine prefix\u2026");
            guard_against_existing_prefix (pfx_path);
            logger.banner ("Creating wine prefix");
            create_wine_prefix (paths, env, logger, cancellable);
            logger.emit_line ("Wine prefix created at: %s\n\n".printf (pfx_path));

            resolve_computed_vars (installer_vars, paths, env, logger);
            Utils.resolve_var_references (installer_vars);
            if (launcher_vars != null) {
                resolve_computed_vars (launcher_vars, paths, env, logger);
                Utils.resolve_var_references (launcher_vars);
            }
            if (post_install_vars != null) {
                resolve_computed_vars (post_install_vars, paths, env, logger);
                Utils.resolve_var_references (post_install_vars);
            }
            log_install_vars (logger, installer_vars);

            rep.label ("Applying components\u2026");
            logger.banner ("Applying enabled components");
            var component_warning = apply_components_with_warning (paths, env, prefix_entry, pfx_path, logger);

            installer_phase.run_steps (rep, paths, env, "Run installer steps");
            if (launcher_phase != null) {
                logger.banner ("Setting up launcher: %s".printf (launcher.display_label ()));
                launcher_phase.run_steps (rep, paths, env, null);
            }
            if (post_phase != null) {
                run_post_install (post_phase, rep, paths, env, post_install_spec, opts, prefix_entry, logger);
            }

            shutdown_wineserver (paths, env, logger);
            progress.progress_changed (1.0);
            announce_install_finished (progress, logger, component_warning);
        } catch (IOError.CANCELLED e) {
            announce_install_failure (progress, logger, "INSTALL CANCELLED", "Installation cancelled.", e.message);
        } catch (Error e) {
            announce_install_failure (progress, logger, "INSTALL FAILED", e.message, e.message);
        } finally {
            logger.close ();
        }
    }

    public void run_spec_action (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        string action_id,
        InstallProgress progress,
        Cancellable? cancellable
    ) {
        var logger = RuntimeLog.for_install (entry.resolved_path (), (msg) => {
            progress.log_message (msg);
        });

        try {
            var action = find_spec_action (entry, launcher_specs, action_id);
            if (action == null) {
                throw new IOError.FAILED ("Spec action not found: %s", action_id);
            }

            logger.banner ("Lumoria Action Log", false);
            logger.emit_line ("Prefix: %s\n".printf (entry.resolved_path ()));
            logger.emit_line ("Action: %s\n\n".printf (action.display_label ()));

            var action_redists = ResolvedRedistSet.resolve (
                action.redists, Models.RedistSpec.load_all_from_resource ()
            );
            int total_steps = 1 + action.downloads.size + action.steps.size + action_redists.step_count;
            var rep = new StepReporter (total_steps, progress, logger, cancellable);

            rep.label ("Preparing action\u2026");
            var runner_spec = Models.RunnerSpec.find_or_default (runner_specs, entry.runner_id);
            var runtime = prepare_wine_runtime (
                runner_spec, entry.variant_id, entry.runner_version,
                entry.path, entry.wine_arch,
                entry.sync_mode, entry.wine_debug, entry.wine_wayland,
                entry.runtime_env_vars, null, logger
            );

            var cache_root = ensure_cache_subdir (Path.build_filename ("actions", entry.id), action.id);
            var vars = build_action_vars (runtime.prefix_path, cache_root, entry, launcher_specs, action);
            vars["ARCH"] = runtime.wine_arch;
            vars["REGION"] = entry.region;
            apply_env_rules (runtime.env, action.env, vars);
            resolve_computed_vars (vars, runtime.paths, runtime.env, logger);
            Utils.resolve_var_references (vars);

            var phase = new InstallPhase (
                action.downloads, action.steps, action_redists, vars, entry
            );
            phase.run_downloads (rep, "Downloading action artifacts");
            phase.run_steps (rep, runtime.paths, runtime.env, "Run action steps");

            shutdown_wineserver (runtime.paths, runtime.env, logger);
            progress.progress_changed (1.0);
            logger.banner ("Action completed successfully");
            progress.install_finished (true, "Action complete.");
        } catch (IOError.CANCELLED e) {
            announce_install_failure (progress, logger, "ACTION CANCELLED", "Action cancelled.", e.message);
        } catch (Error e) {
            announce_install_failure (progress, logger, "ACTION FAILED", e.message, e.message);
        } finally {
            logger.close ();
        }
    }

    public void run_redist_install (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        string redist_id,
        InstallProgress progress,
        Cancellable? cancellable
    ) {
        var logger = RuntimeLog.for_install (entry.resolved_path (), (msg) => {
            progress.log_message (msg);
        });

        try {
            logger.banner ("Lumoria Redist Install", false);
            logger.emit_line ("Prefix: %s\n".printf (entry.resolved_path ()));
            logger.emit_line ("Redist: %s\n\n".printf (redist_id));

            var all_redists = Models.RedistSpec.load_all_from_resource ();
            var ids = new Gee.ArrayList<string> ();
            ids.add (redist_id);
            var resolved = ResolvedRedistSet.resolve (ids, all_redists);

            int total_steps = 1 + resolved.step_count;
            var rep = new StepReporter (total_steps, progress, logger, cancellable);

            rep.label ("Preparing runner\u2026");
            var runner_spec = Models.RunnerSpec.find_or_default (runner_specs, entry.runner_id);
            var runtime = prepare_wine_runtime (
                runner_spec, entry.variant_id, entry.runner_version,
                entry.path, entry.wine_arch,
                entry.sync_mode, entry.wine_debug, entry.wine_wayland,
                entry.runtime_env_vars, null, logger
            );

            var cache_root = ensure_cache_subdir ("redist", redist_id);
            var vars = build_prefix_vars (runtime.prefix_path, cache_root, null);
            vars["ARCH"] = runtime.wine_arch;
            vars["REGION"] = entry.region;
            resolve_computed_vars (vars, runtime.paths, runtime.env, logger);
            Utils.resolve_var_references (vars);

            var phase = new InstallPhase (
                new Gee.ArrayList<Models.DownloadItem> (),
                new Gee.ArrayList<Models.InstallStep> (),
                resolved, vars, entry, true
            );
            phase.run_downloads (rep, "Downloading redist artifacts");
            phase.run_steps (rep, runtime.paths, runtime.env, "Installing redist");

            shutdown_wineserver (runtime.paths, runtime.env, logger);
            progress.progress_changed (1.0);
            logger.banner ("Redist install completed successfully");
            progress.install_finished (true, "Install complete.");
        } catch (IOError.CANCELLED e) {
            announce_install_failure (progress, logger, "INSTALL CANCELLED", "Install cancelled.", e.message);
        } catch (Error e) {
            announce_install_failure (progress, logger, "INSTALL FAILED", e.message, e.message);
        } finally {
            logger.close ();
        }
    }

    private void write_install_header (RuntimeLog logger, InstallOptions opts) {
        logger.banner ("Lumoria Install Log", false);
        logger.emit_line ("Prefix: %s\n".printf (opts.prefix_path));
        logger.emit_line ("Runner: %s variant=%s version=%s\n".printf (
            opts.runner_id, opts.variant_id, opts.runner_version
        ));
        if (logger.is_disk_enabled ()) {
            logger.emit_line ("Log file: %s\n".printf (logger.log_path));
        }
        logger.emit_line ("\n");
    }

    private Models.LauncherSpec? find_launcher_spec (string launcher_id) {
        if (launcher_id == "") return null;
        foreach (var ls in Models.LauncherSpec.load_all_from_resource ()) {
            if (ls.id == launcher_id) return ls;
        }
        return null;
    }

    private Gee.ArrayList<string> merged_redist_ids (
        Gee.ArrayList<string> installer_redists,
        Models.LauncherSpec? launcher
    ) {
        var merged = new Gee.ArrayList<string> ();
        merged.add_all (installer_redists);
        if (launcher != null) merged.add_all (launcher.redists);
        return merged;
    }

    private string ensure_cache_subdir (string category, string id) {
        var path = Path.build_filename (Utils.cache_dir (), category, id);
        Utils.ensure_dir (path);
        return path;
    }

    private Gee.HashMap<string, string> make_install_vars (
        string pfx_path,
        string category,
        string id,
        Gee.HashMap<string, string> spec_vars
    ) {
        return build_prefix_vars (pfx_path, ensure_cache_subdir (category, id), spec_vars);
    }

    private void inject_redist_vars (Gee.HashMap<string, string> vars, ResolvedRedistSet redists) {
        foreach (var spec in redists.specs) {
            vars["REDIST_%s".printf (spec.id)] = "1";
        }
        foreach (var step in redists.code_steps) {
            vars["REDIST_%s".printf (step.command)] = "1";
        }
    }

    private void log_runtime_paths (RuntimeLog logger, WineRuntime runtime) {
        logger.emit_line ("Runner extracted to: %s\n".printf (runtime.extract_result.extracted_to));
        logger.emit_line ("Wine binary: %s\n".printf (runtime.paths.wine));
        logger.emit_line ("Wineboot: via wine wineboot\n");
        logger.emit_line ("Wineserver: %s\n".printf (runtime.paths.wineserver));
        logger.emit_line ("Runner root: %s\n\n".printf (runtime.paths.root));
    }

    private void log_install_vars (RuntimeLog logger, Gee.HashMap<string, string> vars) {
        logger.emit_line ("Installer variables:\n");
        foreach (var e in vars.entries) {
            logger.emit_line ("  %s = %s\n".printf (e.key, e.value));
        }
        logger.emit_line ("\n");
    }

    private void guard_against_existing_prefix (string pfx_path) throws Error {
        if (FileUtils.test (Path.build_filename (pfx_path, "drive_c"), FileTest.EXISTS)) {
            throw new IOError.FAILED (
                "A Wine prefix already exists at:\n%s\n\nRemove it first or choose a different path.",
                pfx_path
            );
        }
    }

    private string? apply_components_with_warning (
        WinePaths paths,
        WineEnv env,
        Models.PrefixEntry? prefix_entry,
        string pfx_path,
        RuntimeLog logger
    ) {
        try {
            var comp_result = apply_enabled_components (paths, pfx_path, prefix_entry, null, logger);
            foreach (var ov in comp_result.dll_overrides.entries) {
                env.add_dll_override (ov.key, ov.value);
            }
            seed_component_env_defaults (prefix_entry, pfx_path, logger);
            apply_env_overrides (env, Utils.Preferences.instance ().get_runtime_env_vars ());
            if (prefix_entry != null) {
                apply_env_overrides (env, prefix_entry.runtime_env_vars);
            }
            return null;
        } catch (Error e) {
            logger.typed (LogType.WARN, "Component application failed: %s".printf (e.message));
            return "Component setup failed: %s".printf (e.message);
        }
    }

    private void seed_component_env_defaults (
        Models.PrefixEntry? entry,
        string pfx_path,
        RuntimeLog logger
    ) {
        if (entry == null) return;
        var defaults = resolve_component_env_defaults (pfx_path, entry);
        if (defaults.size == 0) return;
        foreach (var ce in defaults.entries) {
            if (!entry.runtime_env_vars.has_key (ce.key)) {
                entry.runtime_env_vars[ce.key] = ce.value;
            }
        }
        var reg = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
        reg.update_entry (entry);
        reg.save (Utils.prefix_registry_path ());
        logger.emit_line ("Seeded %d component env default(s) into prefix runtime_env_vars\n".printf (defaults.size));
    }

    private void run_post_install (
        InstallPhase phase,
        StepReporter rep,
        WinePaths paths,
        WineEnv env,
        Models.PostInstallSpec spec,
        InstallOptions opts,
        Models.PrefixEntry? prefix_entry,
        RuntimeLog logger
    ) throws Error {
        string backup_path = "";
        try {
            logger.banner ("Post install: %s".printf (spec.display_label ()));
            rep.label ("Backing up post install spec\u2026");
            backup_path = backup_post_install_spec (opts.prefix_path, opts.post_install_spec_path, spec);
            logger.typed (LogType.COPY, "%s -> %s".printf (opts.post_install_spec_path, backup_path));

            phase.run_steps (rep, paths, env, null);

            update_post_install_metadata (
                prefix_entry, spec,
                opts.post_install_spec_path, opts.post_install_spec_uri,
                backup_path, "success", logger
            );
        } catch (Error e) {
            update_post_install_metadata (
                prefix_entry, spec,
                opts.post_install_spec_path, opts.post_install_spec_uri,
                backup_path, "failed", logger
            );
            throw e;
        }
    }

    private void announce_install_finished (
        InstallProgress progress,
        RuntimeLog logger,
        string? component_warning
    ) {
        if (component_warning != null) {
            logger.banner ("Install completed with warnings");
            progress.install_finished (true, "Install complete with warnings.\n%s".printf (component_warning));
        } else {
            logger.banner ("Install completed successfully");
            progress.install_finished (true, "Install complete.");
        }
    }

    private void announce_install_failure (
        InstallProgress progress,
        RuntimeLog logger,
        string banner_title,
        string user_message,
        string log_message
    ) {
        logger.banner (banner_title);
        logger.emit_line ("%s\n".printf (log_message));
        progress.install_finished (false, user_message);
    }

    private void ensure_download_item (
        Models.DownloadItem dl,
        string url,
        string dest,
        int step_idx,
        int total_steps,
        InstallProgress progress,
        RuntimeLog logger
    ) throws Error {
        Utils.ensure_dir (Path.get_dirname (dest));
        progress.step_changed ("(%d/%d) Downloading %s\u2026".printf (step_idx, total_steps, dl.id));

        if (download_item_is_valid (dl, dest, logger)) {
            progress.progress_changed ((double) step_idx / total_steps);
            logger.typed (LogType.CACHED, dest);
            return;
        }

        var s_base = (double) (step_idx - 1) / total_steps;
        var s_range = 1.0 / total_steps;
        logger.emit_line ("Downloading: %s\n  -> %s\n".printf (url, dest));
        Utils.ensure_downloaded_file (
            url,
            dest,
            0,
            dl.sha256,
            dl.id,
            (downloaded, total) => {
                if (total > 0) {
                    progress.progress_changed (s_base + (double) downloaded / (double) total * s_range);
                }
            }
        );
        logger.typed (LogType.DONE, dl.id);
    }

    private bool download_item_is_valid (Models.DownloadItem dl, string path, RuntimeLog logger) {
        if (!FileUtils.test (path, FileTest.EXISTS)) return false;

        if (dl.sha256 == "") {
            logger.typed (LogType.WARN, "%s has no checksum; using size-only cache validation".printf (dl.id));
        }

        var valid = Utils.validate_downloaded_file (path, 0, dl.sha256, dl.id);
        if (!valid && FileUtils.test (path, FileTest.EXISTS)) {
            FileUtils.remove (path);
        }
        return valid;
    }

    private void run_install_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable = null,
        bool ignore_when = false
    ) throws Error {
        check_cancelled (cancellable);

        if (!ignore_when && step.when != null && !step.when.evaluate (vars)) {
            logger.typed (LogType.SKIP, "when clause not met, skipping: %s".printf (step.description));
            return;
        }

        switch (step.step_type) {
            case "task":
                if (step.command == "create_prefix") {
                    var pfx = vars.has_key ("PREFIX") ? vars["PREFIX"] : "";
                    var drive_c = pfx != "" ? Path.build_filename (pfx, "drive_c") : "";
                    if (drive_c != "" && FileUtils.test (drive_c, FileTest.EXISTS)) {
                        logger.typed (LogType.SKIP, "wine prefix already exists: %s".printf (pfx));
                        break;
                    }
                    create_wine_prefix (paths, env, logger, cancellable);
                } else {
                    throw new IOError.FAILED ("Unknown task: %s", step.command);
                }
                break;

            case "wineexec":
                run_wineexec_step (step, vars, paths, env, logger, cancellable);
                break;

            case "copy":
                var src = expand_path (step.src, vars);
                var dst = expand_path (step.dst, vars);
                logger.typed (LogType.COPY, "%s -> %s".printf (src, dst));
                Utils.copy_path (src, dst, null);
                break;

            case "rename":
                run_rename_step (step, vars, logger);
                break;

            case "delete":
                run_delete_step (step, vars, logger);
                break;

            case "write":
                run_write_step (step, vars, logger);
                break;

            case "xml_upsert":
                run_xml_upsert_step (step, vars, logger);
                break;

            case "text_upsert":
                run_text_upsert_step (step, vars, logger);
                break;

            case "link":
                run_link_step (step, vars, logger);
                break;

            case "redist":
                var redist_opts = build_redist_options (
                    vars.has_key ("PREFIX") ? vars["PREFIX"] : "",
                    paths,
                    env,
                    cancellable
                );
                install_redist (step.command, redist_opts, logger);
                break;

            case "extract":
                var src = expand_path (step.src, vars);
                var dst = expand_path (step.dst, vars);
                logger.typed (LogType.EXTRACT, "%s -> %s".printf (src, dst));
                Utils.extract_archive (src, dst);
                verify_step_paths (step.verify_paths, vars);
                break;

            case "extract_multi":
                run_extract_multi_step (step, vars, logger);
                break;

            case "fonts":
                install_fonts_step (step, vars, paths, env, logger, cancellable);
                break;

            case "font_replacement":
                install_font_replacements (step, vars, paths, env, cancellable, logger);
                break;

            case "cabextract":
                var cab_src = expand_path (step.src, vars);
                var cab_filter = step.args.size > 0 ? step.args[0] : "";
                var cab_dst = expand_path (step.dst, vars);
                if (!FileUtils.test (cab_src, FileTest.EXISTS) || Utils.file_size_or_zero (cab_src) <= 0) {
                    throw new IOError.FAILED ("cabextract source missing or empty: %s", cab_src);
                }
                logger.typed (LogType.CABEXTRACT, "%s -> %s".printf (Path.get_basename (cab_src), cab_dst));
                cabextract_file (cab_src, cab_filter, cab_dst, logger);
                break;

            case "dll_override":
                logger.typed (LogType.DLL_OVERRIDE, "%s=%s".printf (step.command, step.mode));
                set_dll_override (
                    build_redist_options (
                        vars.has_key ("PREFIX") ? vars["PREFIX"] : "",
                        paths, env, cancellable
                    ),
                    step.command, step.mode, logger
                );
                break;

            case "git":
                run_git_step (step, vars, logger);
                break;

            case "set_component_override":
                run_set_component_override_step (step, vars, logger);
                break;

            default:
                throw new IOError.FAILED ("Unknown install step type: %s", step.step_type);
        }
    }

    private void run_write_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        var content = Utils.expand_vars (step.content, vars);
        Utils.ensure_dir (Path.get_dirname (dst));
        FileUtils.set_contents (dst, content);
        logger.typed (LogType.COPY, "wrote %s".printf (dst));
        verify_step_paths (step.verify_paths, vars);
    }

    private void run_delete_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var targets = new Gee.ArrayList<string> ();
        if (step.dst != "") targets.add (expand_path (step.dst, vars));
        foreach (var raw in step.args) targets.add (expand_path (raw, vars));
        if (targets.size == 0) {
            throw new IOError.FAILED ("delete requires dst or args");
        }
        foreach (var target in targets) {
            if (!FileUtils.test (target, FileTest.EXISTS) && !FileUtils.test (target, FileTest.IS_SYMLINK)) {
                logger.typed (LogType.SKIP, "delete: %s not present".printf (target));
                continue;
            }
            if (FileUtils.test (target, FileTest.IS_DIR)) {
                Utils.remove_recursive (target);
            } else if (FileUtils.remove (target) != 0) {
                throw new IOError.FAILED ("delete: failed to remove %s", target);
            }
            logger.typed (LogType.COPY, "deleted %s".printf (target));
        }
    }

    private void run_rename_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var src = expand_path (step.src, vars);
        var dst = expand_path (step.dst, vars);
        if (src == "" || dst == "") {
            throw new IOError.FAILED ("rename requires src and dst");
        }
        if (!FileUtils.test (src, FileTest.EXISTS)) {
            if (step.idempotent && FileUtils.test (dst, FileTest.EXISTS)) {
                logger.typed (LogType.SKIP, "rename: target already present %s".printf (dst));
                return;
            }
            throw new IOError.FAILED ("rename source missing: %s", src);
        }
        Utils.ensure_dir (Path.get_dirname (dst));
        if (FileUtils.test (dst, FileTest.EXISTS) || FileUtils.test (dst, FileTest.IS_SYMLINK)) {
            if (step.overwrite_existing) {
                if (FileUtils.remove (dst) != 0) {
                    throw new IOError.FAILED ("rename: failed to remove existing target %s", dst);
                }
            } else {
                throw new IOError.FAILED ("rename target exists: %s", dst);
            }
        }
        if (FileUtils.rename (src, dst) != 0) {
            throw new IOError.FAILED ("rename failed: %s -> %s", src, dst);
        }
        logger.typed (LogType.COPY, "renamed %s -> %s".printf (src, dst));
        verify_step_paths (step.verify_paths, vars);
    }

    private void run_set_component_override_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var component_id = step.command.strip ();
        var mode = step.mode.strip ().down ();
        if (component_id == "") {
            throw new IOError.FAILED ("set_component_override requires command=component id");
        }
        if (mode == "") mode = "inherit";
        bool? enabled = null;
        switch (mode) {
            case "enable":
            case "enabled":
            case "true":
            case "on":
                enabled = true;
                break;
            case "disable":
            case "disabled":
            case "false":
            case "off":
                enabled = false;
                break;
            case "inherit":
            case "default":
                enabled = null;
                break;
            default:
                throw new IOError.FAILED ("set_component_override invalid mode: %s", step.mode);
        }

        var pfx_path = vars.has_key ("PREFIX") ? vars["PREFIX"] : "";
        if (pfx_path == "") {
            throw new IOError.FAILED ("set_component_override requires PREFIX in vars");
        }

        var reg_path = Utils.prefix_registry_path ();
        var reg = Models.PrefixRegistry.load (reg_path);
        Models.PrefixEntry? target = null;
        foreach (var p in reg.prefixes) {
            if (install_prefix_path (p.path) == pfx_path) {
                target = p;
                break;
            }
        }
        if (target == null) {
            throw new IOError.FAILED ("set_component_override: prefix not found for %s", pfx_path);
        }

        if (enabled == null) {
            if (target.runtime_component_overrides.has_key (component_id)) {
                var ov = target.runtime_component_overrides[component_id];
                ov.enabled = null;
                if (ov.version == "" && ov.system_env.size == 0) {
                    target.runtime_component_overrides.unset (component_id);
                } else {
                    target.runtime_component_overrides[component_id] = ov;
                }
            }
        } else {
            Models.RuntimeComponentOverride ov;
            if (target.runtime_component_overrides.has_key (component_id)) {
                ov = target.runtime_component_overrides[component_id];
            } else {
                ov = new Models.RuntimeComponentOverride ();
            }
            ov.enabled = enabled;
            target.runtime_component_overrides[component_id] = ov;
        }
        reg.update_entry (target);
        if (!reg.save (reg_path)) {
            throw new IOError.FAILED ("set_component_override: failed saving prefix registry");
        }
        logger.typed (
            LogType.COMPONENT,
            "set_component_override: %s=%s for %s".printf (
                component_id,
                enabled == null ? "inherit" : ((bool) enabled ? "enabled" : "disabled"),
                target.display_name ()
            )
        );
    }

    private void run_text_upsert_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        Utils.ensure_dir (Path.get_dirname (dst));

        string existing = "";
        if (FileUtils.test (dst, FileTest.EXISTS)) {
            FileUtils.get_contents (dst, out existing);
        }

        var content = Utils.expand_vars (step.content, vars);
        if (content == "") {
            content = build_text_block_from_args (step.args, vars);
        }
        if (content == "") {
            throw new IOError.FAILED ("text_upsert requires content or args");
        }

        var normalized_existing = normalize_text_block (existing);
        var normalized_content = normalize_text_block (content);
        if (normalized_existing.contains (normalized_content)) {
            logger.typed (LogType.SKIP, "text already exists in %s".printf (dst));
            verify_step_paths (step.verify_paths, vars);
            return;
        }

        var newline = detect_newline_style (existing);
        string output;
        if (step.mode == "append") {
            output = ensure_trailing_newline (normalize_newlines (existing), newline)
                + ensure_trailing_newline (normalize_newlines (content), newline);
        } else {
            output = ensure_trailing_newline (normalize_newlines (content), newline)
                + ensure_trailing_newline (normalize_newlines (existing), newline);
        }

        FileUtils.set_contents (dst, output);
        logger.typed (LogType.COPY, "upserted text in %s".printf (dst));
        verify_step_paths (step.verify_paths, vars);
    }

    private string build_text_block_from_args (
        Gee.ArrayList<string> args,
        Gee.HashMap<string, string> vars
    ) {
        var lines = new Gee.ArrayList<string> ();
        foreach (var arg in args) {
            lines.add (Utils.expand_vars (arg, vars));
        }
        if (lines.size == 0) return "";
        return string.joinv ("\n", Utils.arraylist_to_strv (lines));
    }

    private string normalize_text_block (string value) {
        return normalize_newlines (value).strip ();
    }

    private string normalize_newlines (string value) {
        return value.replace ("\r\n", "\n").replace ("\r", "\n");
    }

    private string detect_newline_style (string existing) {
        if (existing.contains ("\r\n")) return "\r\n";
        return "\r\n";
    }

    private string ensure_trailing_newline (string value, string newline) {
        if (value == "") return "";
        var normalized = normalize_newlines (value);
        if (!normalized.has_suffix ("\n")) normalized += "\n";
        return normalized.replace ("\n", newline);
    }

    private void run_xml_upsert_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        var root_name = step.root.strip ();
        var element_name = step.element.strip ();
        if (root_name == "" || element_name == "") {
            throw new IOError.FAILED ("xml_upsert requires root and element");
        }

        Utils.ensure_dir (Path.get_dirname (dst));

        Xml.Doc* doc;
        Xml.Node* root;
        if (FileUtils.test (dst, FileTest.EXISTS)) {
            doc = Xml.Parser.parse_file (dst);
            if (doc == null) {
                throw new IOError.FAILED ("Failed to parse XML file: %s", dst);
            }
            root = doc->get_root_element ();
            if (root == null) {
                throw new IOError.FAILED ("XML file has no root element: %s", dst);
            }
            if (root->name != root_name) {
                throw new IOError.FAILED ("XML root mismatch in %s: expected %s, got %s", dst, root_name, root->name);
            }
        } else {
            doc = new Xml.Doc ("1.0");
            root = doc->new_node (null, root_name);
            doc->set_root_element (root);
        }

        var target = find_matching_xml_child (root, element_name, step.match, vars);
        if (target == null) {
            if (!step.create_if_missing) {
                throw new IOError.FAILED ("XML element not found: %s", element_name);
            }
            target = root->new_child (null, element_name, null);
            foreach (var entry in step.match.entries) {
                target->set_prop (entry.key, Utils.expand_vars (entry.value, vars));
            }
        }

        foreach (var entry in step.children.entries) {
            var value = Utils.expand_vars (entry.value, vars);
            var child = find_xml_element_child (target, entry.key);
            if (child == null) {
                target->new_text_child (null, entry.key, value);
            } else if (step.overwrite_existing) {
                child->set_content (value);
            }
        }

        if (doc->save_format_file (dst, 1) < 0) {
            throw new IOError.FAILED ("Failed to write XML file: %s", dst);
        }
        logger.typed (LogType.COPY, "updated XML %s".printf (dst));
        verify_step_paths (step.verify_paths, vars);
    }

    private Xml.Node* find_matching_xml_child (
        Xml.Node* root,
        string element_name,
        Gee.HashMap<string, string> match,
        Gee.HashMap<string, string> vars
    ) {
        for (Xml.Node* child = root->children; child != null; child = child->next) {
            if (child->type != Xml.ElementType.ELEMENT_NODE || child->name != element_name) continue;
            bool matched = true;
            foreach (var entry in match.entries) {
                var expected = Utils.expand_vars (entry.value, vars);
                var actual = child->get_prop (entry.key);
                if (actual == null || actual != expected) {
                    matched = false;
                    break;
                }
            }
            if (matched) return child;
        }
        return null;
    }

    private Xml.Node* find_xml_element_child (Xml.Node* parent, string name) {
        for (Xml.Node* child = parent->children; child != null; child = child->next) {
            if (child->type == Xml.ElementType.ELEMENT_NODE && child->name == name) return child;
        }
        return null;
    }

    private void run_wineexec_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var raw_exe = expand_path (step.command, vars);
        bool is_builtin_command = is_builtin_wine_command (raw_exe);
        bool is_msiexec = raw_exe == "msiexec";
        string? host_exe = null;
        var exe = raw_exe;
        if (!is_builtin_command) {
            host_exe = normalize_wineexec_host_path (raw_exe, vars);
            exe = wine_arg_path (vars["PREFIX"], host_exe);
        }
        var expanded_args = new Gee.ArrayList<string> ();
        for (int i = 0; i < step.args.size; i++) {
            expanded_args.add (expand_path (step.args[i], vars));
        }
        if (is_msiexec && !has_msiexec_logging_flag (expanded_args) && logger.is_disk_enabled ()) {
            var msi_log_path = create_msiexec_log_path (step, vars);
            expanded_args.add ("/l*v");
            expanded_args.add (msi_log_path);
            logger.typed (LogType.WINEEXEC, "msi_log=%s".printf (msi_log_path));
        }
        var args = new string[expanded_args.size + 1];
        args[0] = exe;
        for (int i = 0; i < expanded_args.size; i++) {
            args[i + 1] = expanded_args[i];
        }
        var working = step.working_dir != ""
            ? normalize_wineexec_host_path (expand_path (step.working_dir, vars), vars)
            : null;

        logger.typed (LogType.WINEEXEC, "exe=%s".printf (raw_exe));
        if (host_exe != null) {
            logger.typed (LogType.WINEEXEC, "resolved_exe=%s".printf (host_exe));
        }
        for (int i = 0; i < expanded_args.size; i++) {
            logger.typed (LogType.WINEEXEC, "arg[%d]=%s".printf (i, expanded_args[i]));
        }
        if (working != null) logger.typed (LogType.WINEEXEC, "cwd=%s".printf (working));

        if (!is_builtin_command) {
            if (host_exe == null || !FileUtils.test (host_exe, FileTest.EXISTS)) {
                throw new IOError.FAILED ("wineexec: exe not found on host: %s", host_exe ?? raw_exe);
            }
        }
        validate_wineexec_file_args (args, logger);

        try {
            run_wine_command (paths.wine, args, env, working, logger, cancellable);
        } catch (Error e) {
            if (e is IOError.CANCELLED) throw e;
            bool all_verified = verify_paths_with_logging (step.verify_paths, vars, logger);
            if (!all_verified && is_msiexec) {
                logger.typed (LogType.WARN, "msiexec failed; retrying once after wineserver shutdown");
                shutdown_wineserver (paths, env, logger);
                Thread.usleep (750000);
                try {
                    run_wine_command (paths.wine, args, env, working, logger, cancellable);
                    all_verified = verify_paths_with_logging (step.verify_paths, vars, logger);
                } catch (Error retry_e) {
                    if (retry_e is IOError.CANCELLED) throw retry_e;
                    all_verified = verify_paths_with_logging (step.verify_paths, vars, logger);
                    if (!all_verified) throw retry_e;
                    logger.typed (LogType.WARN, "retry failed (exit non-zero) but verify_paths all exist, continuing");
                    return;
                }
            }
            if (!all_verified) throw e;
            logger.typed (LogType.WARN, "command failed (exit non-zero) but verify_paths all exist, continuing");
        }
    }

    private void validate_wineexec_file_args (string[] args, RuntimeLog logger) throws Error {
        foreach (var arg in args) {
            if (arg == null || !arg.has_prefix ("/")) continue;
            if (!arg.has_suffix (".msi") && !arg.has_suffix (".exe") && !arg.has_suffix (".reg")) continue;
            if (FileUtils.test (arg, FileTest.EXISTS)) continue;

            logger.typed (LogType.ERROR, "file argument does not exist: %s".printf (arg));
            var parent = Path.get_dirname (arg);
            if (FileUtils.test (parent, FileTest.IS_DIR)) {
                logger.typed (LogType.DEBUG, "contents of %s:".printf (parent));
                try {
                    var dir = Dir.open (parent);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        logger.emit_line ("  %s\n".printf (name));
                    }
                } catch (FileError fe) {
                    logger.emit_line ("  (could not list: %s)\n".printf (fe.message));
                }
            } else {
                logger.typed (LogType.DEBUG, "parent directory does not exist: %s".printf (parent));
            }
            throw new IOError.FAILED ("wineexec: file argument not found: %s", arg);
        }
    }

    private void run_link_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        Utils.ensure_dir (dst);
        var mode = step.mode != "" ? step.mode : "symlink";
        foreach (var raw in step.args) {
            var src = expand_path (raw, vars);
            var name = Path.get_basename (src);
            var target = Path.build_filename (dst, name);
            if (FileUtils.test (target, FileTest.EXISTS) || FileUtils.test (target, FileTest.IS_SYMLINK)) {
                logger.typed (LogType.LINK, "%s already exists, replacing".printf (target));
                FileUtils.remove (target);
            }
            var src_exists = FileUtils.test (src, FileTest.EXISTS);
            logger.typed (LogType.LINK, "%s %s -> %s (source %s)".printf (
                mode, src, target, src_exists ? "exists" : "MISSING"));
            if (!src_exists) {
                throw new IOError.FAILED ("Link source missing: %s", src);
            }
            if (mode == "hardlink") {
                if (Posix.link (src, target) != 0) {
                    throw new IOError.FAILED (
                        "Hardlink failed: %s -> %s: %s",
                        src, target, Posix.strerror (Posix.errno)
                    );
                }
            } else {
                FileUtils.symlink (src, target);
            }
        }
    }

    private void run_git_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var git_dst = expand_path (step.dst, vars);
        if (git_dst == "") throw new IOError.FAILED ("git step requires dst");

        var target = new Utils.GitTarget () {
            branch = Utils.expand_vars (step.git_branch, vars),
            tag = Utils.expand_vars (step.git_tag, vars),
            commit = Utils.expand_vars (step.git_commit, vars)
        };
        var summary = "%s%s%s%s".printf (
            git_dst,
            target.branch != "" ? " branch=" + target.branch : "",
            target.tag != "" ? " tag=" + target.tag : "",
            target.commit != "" ? " commit=" + target.commit : ""
        );

        switch (step.command) {
            case "clone":
                var git_url = expand_path (step.src, vars);
                if (git_url == "") throw new IOError.FAILED ("git clone requires src (url)");
                logger.typed (LogType.GIT, "clone %s -> %s".printf (git_url, summary));
                Utils.git_clone (git_url, git_dst, target, null);
                break;

            case "pull":
                logger.typed (LogType.GIT, "pull %s".printf (summary));
                Utils.git_pull (git_dst, target, null);
                break;

            default:
                throw new IOError.FAILED ("Unknown git command: %s", step.command);
        }

        verify_step_paths (step.verify_paths, vars);
    }

    private void run_extract_multi_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        var volumes = new Gee.ArrayList<string> ();

        if (step.src != "") {
            volumes.add (expand_path (step.src, vars));
        }
        foreach (var arg in step.args) {
            volumes.add (expand_path (arg, vars));
        }
        if (volumes.size == 0) {
            throw new IOError.FAILED ("extract_multi requires at least one source volume");
        }

        foreach (var vol in volumes) {
            if (!FileUtils.test (vol, FileTest.EXISTS) || Utils.file_size_or_zero (vol) <= 0) {
                throw new IOError.FAILED ("extract_multi volume missing or empty: %s", vol);
            }
            logger.typed (LogType.EXTRACT, "volume: %s".printf (vol));
        }

        logger.typed (LogType.EXTRACT, "multi-volume -> %s".printf (dst));
        Utils.extract_archive_multi (Utils.arraylist_to_strv (volumes), dst);
        verify_step_paths (step.verify_paths, vars);
    }

    private void install_fonts_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var fonts_dir = expand_path (step.dst, vars);
        Utils.ensure_dir (fonts_dir);

        var tmp_dir = DirUtils.make_tmp ("fonts-XXXXXX");
        int packages_processed = 0;
        int fonts_copied_total = 0;

        foreach (var raw_path in step.args) {
            packages_processed++;
            var exe_path = expand_path (raw_path, vars);
            var exe_lower = exe_path.down ();

            if (exe_lower.has_suffix (".ttf") || exe_lower.has_suffix (".ttc")) {
                var dst = Path.build_filename (fonts_dir, Path.get_basename (exe_path).down ());
                uint8[] data;
                FileUtils.get_data (exe_path, out data);
                FileUtils.set_data (dst, data);
                fonts_copied_total++;
                logger.typed (LogType.FONTS, "copied %s".printf (dst));
                continue;
            }

            var basename = Path.get_basename (exe_path).replace (".exe", "");
            var extract_dir = Path.build_filename (tmp_dir, basename);
            Utils.ensure_dir (extract_dir);

            logger.typed (LogType.FONTS, "extracting %s".printf (Path.get_basename (exe_path)));
            Utils.extract_archive (exe_path, extract_dir);

            var found = collect_font_files (extract_dir);
            if (found.size == 0) {
                throw new IOError.FAILED ("No font files found in extracted package: %s", exe_path);
            }
            foreach (var src in found) {
                var dst = Path.build_filename (fonts_dir, Path.get_basename (src).down ());
                uint8[] data;
                FileUtils.get_data (src, out data);
                FileUtils.set_data (dst, data);
                fonts_copied_total++;
                logger.typed (LogType.FONTS, "copied %s".printf (dst));
            }
        }

        register_fonts_into_prefix (fonts_dir, tmp_dir, step, vars, paths, env, cancellable, logger);

        Utils.remove_recursive (tmp_dir);
        logger.typed (LogType.FONTS, "summary: packages=%d, fonts_copied=%d".printf (packages_processed, fonts_copied_total));
        logger.typed (LogType.FONTS, "installed to %s".printf (fonts_dir));
    }

    private void register_fonts_into_prefix (
        string fonts_dir,
        string tmp_dir,
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        Cancellable? cancellable,
        RuntimeLog logger
    ) throws Error {
        int declared = step.font_registrations.size;
        if (declared == 0) return;

        var entries = new Gee.ArrayList<string> ();
        foreach (var raw in step.font_registrations) {
            var parts = raw.split ("|", 2);
            if (parts.length != 2) continue;
            var file = parts[0].strip ();
            var face = parts[1].strip ();
            if (file == "" || face == "") continue;
            if (!FileUtils.test (Path.build_filename (fonts_dir, file), FileTest.EXISTS)) continue;
            var lower = file.down ();
            var suffix = (lower.has_suffix (".ttf") || lower.has_suffix (".ttc")) ? " (TrueType)" : "";
            entries.add ("\"%s%s\"=\"%s\"\r\n".printf (face, suffix, file));
        }

        if (entries.size == 0) {
            logger.typed (LogType.FONTS, "no registerable fonts (0/%d declared)".printf (declared));
            return;
        }

        string[] sections = {
            "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts",
            "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Fonts"
        };

        var payload = new StringBuilder ("REGEDIT4\r\n\r\n");
        foreach (var section in sections) {
            payload.append ("[%s]\r\n".printf (section));
            foreach (var line in entries) payload.append (line);
            payload.append ("\r\n");
        }

        var reg_path = Path.build_filename (tmp_dir, "fonts.reg");
        FileUtils.set_contents (reg_path, payload.str);

        var pfx = vars.has_key ("PREFIX") ? vars["PREFIX"] : "";
        wine_reg (
            build_redist_options (pfx, paths, env, cancellable),
            { "import", reg_path },
            logger
        );

        logger.typed (LogType.FONTS, "registered %d/%d font(s)".printf (entries.size, declared));
    }

    private Gee.ArrayList<string> collect_font_files (string dir_path) {
        var results = new Gee.ArrayList<string> ();
        try {
            var dir = Dir.open (dir_path);
            string? name;
            while ((name = dir.read_name ()) != null) {
                var path = Path.build_filename (dir_path, name);
                var lower = name.down ();
                if (lower.has_suffix (".ttf") || lower.has_suffix (".ttc")) {
                    results.add (path);
                } else if (FileUtils.test (path, FileTest.IS_DIR)) {
                    results.add_all (collect_font_files (path));
                }
            }
        } catch (Error e) {}
        return results;
    }

    private void install_font_replacements (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        Cancellable? cancellable,
        RuntimeLog logger
    ) throws Error {
        if (step.font_registrations.size == 0) return;

        var entries = new Gee.ArrayList<string> ();
        foreach (var raw in step.font_registrations) {
            var parts = raw.split ("|", 2);
            if (parts.length != 2) continue;
            var alias = parts[0].strip ();
            var target = parts[1].strip ();
            if (alias == "" || target == "") continue;
            entries.add ("\"%s\"=\"%s\"\r\n".printf (alias, target));
        }

        if (entries.size == 0) return;

        var payload = new StringBuilder ("REGEDIT4\r\n\r\n");
        payload.append ("[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]\r\n");
        foreach (var line in entries) payload.append (line);
        payload.append ("\r\n");

        var tmp_dir = DirUtils.make_tmp ("fontrep-XXXXXX");
        var reg_path = Path.build_filename (tmp_dir, "replacements.reg");
        FileUtils.set_contents (reg_path, payload.str);

        var pfx = vars.has_key ("PREFIX") ? vars["PREFIX"] : "";
        wine_reg (
            build_redist_options (pfx, paths, env, cancellable),
            { "import", reg_path },
            logger
        );

        Utils.remove_recursive (tmp_dir);
        logger.typed (LogType.FONTS, "registered %d font replacement(s)".printf (entries.size));
    }


    private void cabextract_file (string archive, string cab_filter, string dest, RuntimeLog logger) throws Error {
        var decomp = new MsPack.CabDecompressor ();

        var cab = decomp.search (archive);
        if (cab == null) {
            cab = decomp.open (archive);
        }
        if (cab == null) {
            throw new IOError.FAILED ("mspack: cannot open %s (error %d)", archive, decomp.last_error ());
        }

        var filter_normalized = cab_filter.down ().replace ("\\", "/");
        unowned MsPack.CabFile? match = null;
        uint expected_length = 0;
        int cab_count = 0;
        int file_count = 0;

        for (unowned var c = cab; c != null; c = c.get_next ()) {
            cab_count++;
            for (unowned var f = c.get_files (); f != null; f = f.get_next ()) {
                file_count++;
                var fname = f.get_filename ();
                if (fname == null) continue;
                var fname_normalized = fname.down ().replace ("\\", "/");
                if (fname_normalized == filter_normalized
                    || fname_normalized.has_suffix ("/" + filter_normalized)) {
                    match = f;
                    expected_length = f.get_length ();
                    break;
                }
            }
            if (match != null) break;
        }

        if (match == null) {
            logger.typed (LogType.MSPACK, "filter: %s".printf (filter_normalized));
            logger.typed (LogType.MSPACK, "scanned %d cab(s), %d file(s) in %s".printf (cab_count, file_count, Path.get_basename (archive)));
            int shown = 0;
            for (unowned var c = cab; c != null; c = c.get_next ()) {
                for (unowned var f = c.get_files (); f != null; f = f.get_next ()) {
                    var fname = f.get_filename ();
                    if (fname != null) {
                        logger.typed (LogType.MSPACK, "  %s".printf (fname));
                    }
                    shown++;
                    if (shown >= 50) {
                        logger.typed (LogType.MSPACK, "  ... (%d more)".printf (file_count - shown));
                        break;
                    }
                }
                if (shown >= 50) break;
            }
            decomp.close (cab);
            throw new IOError.FAILED ("mspack: %s not found in %s", cab_filter, archive);
        }

        Utils.ensure_dir (Path.get_dirname (dest));

        if (FileUtils.test (dest, FileTest.EXISTS) || FileUtils.test (dest, FileTest.IS_SYMLINK)) {
            if (FileUtils.unlink (dest) != 0 && FileUtils.test (dest, FileTest.EXISTS)) {
                logger.typed (LogType.WARN, "mspack: could not unlink %s before extract".printf (dest));
            }
        }

        int r = decomp.extract (match, dest);
        decomp.close (cab);

        if (r != MsPack.ERR_OK) {
            throw new IOError.FAILED ("mspack: extract failed for %s (error %d)", cab_filter, r);
        }

        int64 dest_size = Utils.file_size_or_zero (dest);
        logger.typed (LogType.MSPACK, "extracted %lld bytes to %s (expected %u)".printf (dest_size, dest, expected_length));

        if (dest_size <= 0) {
            throw new IOError.FAILED ("mspack: extract produced empty/missing %s", dest);
        }
        if (expected_length > 0 && dest_size != (int64) expected_length) {
            throw new IOError.FAILED (
                "mspack: size mismatch for %s (got %lld, expected %u)",
                dest, dest_size, expected_length
            );
        }
    }

    private Gee.HashMap<string, string> build_prefix_vars (
        string pfx_path,
        string cache_path,
        Gee.HashMap<string, string>? spec_vars
    ) {
        var vars = new Gee.HashMap<string, string> ();
        vars["CACHE_BASE"] = Utils.cache_dir ();
        vars["CACHE_REDIST"] = Path.build_filename (Utils.cache_dir (), "redist");
        vars["CACHE"] = cache_path;
        vars["PREFIX"] = pfx_path;
        vars["WINDOWS"] = Path.build_filename (pfx_path, "drive_c", "windows");
        vars["SYSTEM32"] = Path.build_filename (pfx_path, "drive_c", "windows", "system32");
        vars["SYSWOW64"] = Path.build_filename (pfx_path, "drive_c", "windows", "syswow64");
        vars["FONTS"] = Path.build_filename (pfx_path, "drive_c", "windows", "Fonts");
        if (spec_vars != null) {
            foreach (var e in spec_vars.entries) {
                vars[e.key] = e.value;
            }
        }
        return vars;
    }

    private void inject_prefix_context (
        Gee.HashMap<string, string> vars,
        WineRuntime runtime,
        Models.PrefixEntry? entry,
        RuntimeLog logger
    ) {
        vars["ARCH"] = runtime.wine_arch;
        resolve_prefix_vars (vars, entry, logger);
        Utils.resolve_var_references (vars);
    }

    private Gee.HashMap<string, string> build_post_install_vars (
        string pfx_path,
        string cache_path,
        Models.InstallerSpec installer_spec,
        Models.LauncherSpec? launcher,
        Models.PostInstallSpec post_install_spec
    ) {
        var vars = build_prefix_vars (pfx_path, cache_path, installer_spec.variables);
        if (launcher != null) {
            foreach (var e in launcher.variables.entries) {
                vars[e.key] = e.value;
            }
        }
        foreach (var e in post_install_spec.variables.entries) {
            vars[e.key] = e.value;
        }
        return vars;
    }

    private Gee.HashMap<string, string> build_action_vars (
        string pfx_path,
        string cache_path,
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        Models.SpecAction action
    ) {
        var installer_spec = Models.InstallerSpec.load_from_resource ();
        Models.LauncherSpec? launcher = null;
        if (entry.launcher_id != "") {
            foreach (var spec in launcher_specs) {
                if (spec.id == entry.launcher_id) {
                    launcher = spec;
                    break;
                }
            }
        }
        var post_install_spec = Runtime.load_prefix_post_install_spec (entry);
        var vars = build_prefix_vars (pfx_path, cache_path, installer_spec.variables);
        if (launcher != null) {
            foreach (var e in launcher.variables.entries) vars[e.key] = e.value;
        }
        if (post_install_spec != null) {
            foreach (var e in post_install_spec.variables.entries) vars[e.key] = e.value;
        }
        foreach (var e in action.variables.entries) vars[e.key] = e.value;
        return vars;
    }

    private Models.SpecAction? find_spec_action (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        string action_id
    ) {
        foreach (var action in Runtime.list_spec_actions (entry, launcher_specs)) {
            if (action.id == action_id) return action;
        }
        return null;
    }

    private string backup_post_install_spec (
        string prefix_root,
        string source_path,
        Models.PostInstallSpec spec
    ) throws Error {
        var backup_dir = Path.build_filename (prefix_root, "lumoria", "post-install");
        Utils.ensure_dir (backup_dir);

        var token = sanitize_filename_token (spec.id != "" ? spec.id : Path.get_basename (source_path));
        if (token == "") token = "post-install";
        var backup_path = Path.build_filename (backup_dir, token + ".json");
        Utils.copy_path (source_path, backup_path);
        return backup_path;
    }

    private void update_post_install_metadata (
        Models.PrefixEntry? prefix_entry,
        Models.PostInstallSpec spec,
        string original_path,
        string original_uri,
        string backup_path,
        string status,
        RuntimeLog logger
    ) {
        if (prefix_entry == null) return;

        var metadata = prefix_entry.post_install_spec;
        if (metadata == null) metadata = new Models.PrefixPostInstallSpec ();

        if (original_path != "") metadata.original_path = original_path;
        if (original_uri != "") metadata.original_uri = original_uri;
        if (backup_path != "") metadata.backup_path = backup_path;
        metadata.spec_id = spec.id;
        metadata.name = spec.display_label ();
        metadata.last_run_status = status;
        metadata.last_run_at = new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ");
        prefix_entry.post_install_spec = metadata;

        var reg = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
        reg.update_entry (prefix_entry);
        if (!reg.save (Utils.prefix_registry_path ())) {
            logger.typed (LogType.WARN, "Failed to save post install metadata");
        }
    }

    private void check_cancelled (Cancellable? cancellable) throws IOError {
        if (cancellable != null && cancellable.is_cancelled ()) {
            throw new IOError.CANCELLED ("Installation cancelled");
        }
    }

    private void verify_step_paths (Gee.ArrayList<string> verify_paths, Gee.HashMap<string, string> vars) throws IOError {
        var missing = new Gee.ArrayList<string> ();
        foreach (var vp in verify_paths) {
            var expanded = expand_path (vp, vars);
            if (!FileUtils.test (expanded, FileTest.EXISTS)) {
                missing.add (expanded);
            }
        }
        if (missing.size > 0) {
            throw new IOError.FAILED ("Extract verify failed, missing: %s", missing[0]);
        }
    }

    private bool has_msiexec_logging_flag (Gee.ArrayList<string> args) {
        foreach (var arg in args) {
            if (arg == null) continue;
            var lower = arg.down ();
            if (lower.has_prefix ("/l")) return true;
        }
        return false;
    }

    private bool verify_paths_with_logging (
        Gee.ArrayList<string> verify_paths,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) {
        if (verify_paths.size == 0) return false;
        bool all_verified = true;
        foreach (var vp in verify_paths) {
            var expanded = expand_path (vp, vars);
            var exists = FileUtils.test (expanded, FileTest.EXISTS);
            logger.typed (LogType.VERIFY, "%s -> %s".printf (expanded, exists ? "EXISTS" : "MISSING"));
            if (!exists) all_verified = false;
        }
        return all_verified;
    }

    private string create_msiexec_log_path (Models.InstallStep step, Gee.HashMap<string, string> vars) {
        string logs_dir;
        if (vars.has_key ("PREFIX") && vars["PREFIX"] != "") {
            logs_dir = Path.build_filename (vars["PREFIX"], "logs");
        } else {
            logs_dir = Path.build_filename (Utils.cache_dir (), "install-logs");
        }
        Utils.ensure_dir (logs_dir);

        var stamp = new DateTime.now_local ().format ("%Y%m%d-%H%M%S");
        var label = sanitize_filename_token (step.description != "" ? step.description : step.command);
        if (label == "") label = "step";
        return Path.build_filename (logs_dir, "msiexec-%s-%s.log".printf (label, stamp));
    }

    private string sanitize_filename_token (string input) {
        var sb = new StringBuilder ();
        for (int i = 0; i < input.length; i++) {
            var c = input[i];
            bool keep = (c >= 'a' && c <= 'z')
                || (c >= 'A' && c <= 'Z')
                || (c >= '0' && c <= '9')
                || c == '-'
                || c == '_';
            sb.append_c (keep ? c : '_');
        }
        return sb.str;
    }

    private string expand_path (string input, Gee.HashMap<string, string> vars) {
        return Utils.expand_vars (input, vars);
    }

    private bool is_builtin_wine_command (string command) {
        switch (command) {
            case "cmd":
            case "cmd.exe":
            case "msiexec":
            case "regedit":
            case "regsvr32":
            case "wineboot":
                return true;
            default:
                return false;
        }
    }

    private string wine_arg_path (string pfx_path, string host_exe) {
        var drive_c = Path.build_filename (pfx_path, "drive_c");
        if (host_exe.has_prefix (drive_c + "/")) {
            return to_wine_path (pfx_path, host_exe);
        }
        return host_exe;
    }

    private string normalize_wineexec_host_path (string value, Gee.HashMap<string, string> vars) {
        if (value == "") return value;
        if (Path.is_absolute (value)) return value;
        if (!vars.has_key ("PREFIX")) return value;

        var lower = value.down ();
        if (lower.has_prefix ("drive_c/")
            || lower.has_prefix ("drive_c\\")
            || lower.has_prefix ("c:\\")
            || lower.has_prefix ("c:/")
            || lower == "c:") {
            return resolve_host_path (value, vars["PREFIX"]);
        }

        return value;
    }

}
