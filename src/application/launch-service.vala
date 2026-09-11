namespace Lumoria.Application {

    private delegate string LaunchOperation (Runtime.UpdateDecisionCallback? decide) throws Error;

    public class LaunchService : Object {
        public signal void changed ();

        public string launching_prefix_id { get; private set; default = ""; }
        public bool is_launching {
            get { return launching_prefix_id != ""; }
        }

        private Context ctx;

        public LaunchService (Context ctx) {
            this.ctx = ctx;
        }

        public void launch_now (
            Models.PrefixEntry entry,
            string action_id = "",
            string custom_exe = "",
            Runtime.LaunchPolicy policy = Runtime.LaunchPolicy.OFFLINE_FAST_START
        ) throws Error {
            require_runnable (entry);
            if (!ctx.try_begin (ExclusiveKind.LAUNCH)) {
                throw new LumoriaError.BUSY (ctx.exclusive_busy_message ());
            }
            try {
                Runtime.run_prefix (
                    entry,
                    ctx.runner_manifests,
                    ctx.launcher_manifests,
                    action_id,
                    custom_exe,
                    null,
                    policy
                );
            } finally {
                ctx.end_session (ExclusiveKind.LAUNCH);
            }
        }

        public void launch_prefix (Models.PrefixEntry entry, string action_id, string custom_exe = "") {
            run_launch (entry, _("Launching…"), custom_exe != "" ? "launch-exe-worker" : "launch-worker", (decide) => {
                var result = Runtime.run_prefix (
                    entry,
                    ctx.runner_manifests,
                    ctx.launcher_manifests,
                    action_id,
                    custom_exe,
                    null,
                    Runtime.LaunchPolicy.INTERACTIVE,
                    notify_status,
                    decide
                );
                return custom_exe != ""
                    ? _("Launched EXE (pid %d)").printf (result.pid)
                    : _("Launched (pid %d)").printf (result.pid);
            }, () => {
                if (custom_exe == "" && ctx.ui != null) ctx.ui.close_after_successful_launch ();
            });
        }

        public const string WINE_CONSOLE = "wineconsole";
        public const string WINE_TASKMGR = "taskmgr";
        public const string WINE_CONTROL = "control";
        public const string WINE_REGEDIT = "regedit";
        public const string WINE_CFG = "winecfg";

        public void launch_wine_tool (Models.PrefixEntry entry, string[] wine_args, string label) {
            var args = new Gee.ArrayList<string> ();
            foreach (var a in wine_args) args.add (a);

            run_launch (entry, _("Launching %s…").printf (label), "launch-tool-worker", (decide) => {
                var result = Runtime.run_prefix_command (
                    entry,
                    ctx.runner_manifests,
                    args,
                    label,
                    Runtime.LaunchPolicy.INTERACTIVE,
                    notify_status,
                    decide
                );
                return _("Launched %s (pid %d)").printf (label, result.pid);
            });
        }

        public void open_prefix_shell (Models.PrefixEntry entry) {
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                ctx.show_toast (_("These tools are disabled while in a gamescope session."));
                return;
            }
            Runtime.TerminalContext? term = null;
            run_launch (entry, _("Opening terminal…"), "prepare-terminal", (decide) => {
                term = Runtime.prepare_prefix_terminal_context (entry, ctx.runner_manifests, decide);
                return "";
            }, () => {
                if (ctx.ui != null) ctx.ui.present_terminal (term.working_directory, term.env_vars);
                else ctx.show_toast (_("Terminal is not available without a window."));
            });
        }

        private delegate void DecidedLaunch (Runtime.UpdateDecisionCallback? decide);

        private void with_update_decision (Models.PrefixEntry entry, owned DecidedLaunch next) {
            if (ctx.ui == null) {
                next (null);
                return;
            }
            Gee.ArrayList<Runtime.PendingUpdate>? pending = null;
            Utils.run_background ("collect-updates", () => {
                pending = Runtime.list_pending_updates (entry, ctx.runner_manifests);
            }, (error) => {
                if (error != null) {
                    ctx.show_toast (user_error (error));
                    finish_busy ();
                    return;
                }
                if (pending == null || pending.size == 0) {
                    next (fixed_decision (Runtime.UpdateDecision.UPDATE));
                    return;
                }
                ctx.present_updates (pending, (decision) => {
                    if (decision == Runtime.UpdateDecision.CANCEL) {
                        ctx.show_toast (_("Launch cancelled."));
                        finish_busy ();
                        return;
                    }
                    next (fixed_decision (decision));
                });
            });
        }

        private static Runtime.UpdateDecisionCallback fixed_decision (Runtime.UpdateDecision decision) {
            return (updates) => decision;
        }

        private void queue_launch (
            string worker_name,
            owned LaunchOperation operation,
            Runtime.UpdateDecisionCallback? decide,
            owned Utils.Action? on_success = null
        ) {
            string message = "";
            Utils.run_background (worker_name, () => {
                message = operation (decide);
            }, (error) => {
                if (error != null) {
                    if (error is IOError.CANCELLED) {
                        message = _("Launch cancelled.");
                    } else {
                        message = user_error (error);
                    }
                }
                if (message != "") ctx.show_toast (message);
                finish_busy ();
                if (error == null && on_success != null) on_success ();
            });
        }

        private void notify_status (string message) {
            Idle.add (() => {
                ctx.set_busy_status (message);
                return false;
            });
        }

        private void run_launch (
            Models.PrefixEntry entry,
            string status,
            string worker_name,
            owned LaunchOperation operation,
            owned Utils.Action? on_success = null
        ) {
            if (!ctx.try_begin (ExclusiveKind.LAUNCH)) {
                ctx.show_toast (ctx.exclusive_busy_message ());
                return;
            }
            if (!prefix_runnable (entry)) {
                ctx.end_session (ExclusiveKind.LAUNCH);
                return;
            }
            launching_prefix_id = entry.id;
            changed ();
            ctx.present_busy (status);
            ctx.state.set_busy (status);
            with_update_decision (entry, (decide) => {
                queue_launch (worker_name, (owned) operation, decide, (owned) on_success);
            });
        }

        private void finish_busy () {
            ctx.dismiss_busy ();
            ctx.state.clear_busy ();
            launching_prefix_id = "";
            ctx.end_session (ExclusiveKind.LAUNCH);
            changed ();
        }

        private void require_runnable (Models.PrefixEntry entry) throws Error {
            Models.ManifestRepository.shared ().require_valid ();
            Models.RunnerManifest.resolve_for_entry (ctx.runner_manifests, entry);
            ctx.prefixes.require_access (entry);
        }

        private bool prefix_runnable (Models.PrefixEntry entry) {
            try {
                require_runnable (entry);
                return true;
            } catch (Error e) {
                ctx.show_toast (user_error (e));
                return false;
            }
        }
    }
}
