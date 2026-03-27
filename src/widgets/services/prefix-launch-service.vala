namespace Lumoria.Widgets.Services {

    public delegate void ToastCallback (string message);
    public delegate void CompletionCallback ();
    private delegate string LaunchOperation () throws Error;

    public class PrefixLaunchService : Object {
        public void launch_prefix (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs,
            string entrypoint_id,
            owned ToastCallback on_toast,
            owned CompletionCallback? on_complete = null
        ) {
            run_launch_worker (
                "launch-worker",
                () => {
                    var result = Runtime.run_prefix (entry, runner_specs, launcher_specs, entrypoint_id);
                    return _("Launched (pid %d)").printf (result.pid);
                },
                on_toast,
                on_complete
            );
        }

        public void launch_exe (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs,
            string exe_path,
            owned ToastCallback on_toast,
            owned CompletionCallback? on_complete = null
        ) {
            run_launch_worker (
                "launch-exe-worker",
                () => {
                    var result = Runtime.run_prefix (entry, runner_specs, launcher_specs, "", exe_path);
                    return _("Launched EXE (pid %d)").printf (result.pid);
                },
                on_toast,
                on_complete
            );
        }

        public void launch_wine_tool (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            string[] wine_args,
            string label,
            owned ToastCallback on_toast,
            owned CompletionCallback? on_complete = null
        ) {
            run_launch_worker (
                "launch-tool-worker",
                () => {
                    var result = Runtime.run_prefix_command (entry, runner_specs, wine_args, label);
                    return _("Launched %s (pid %d)").printf (label, result.pid);
                },
                on_toast,
                on_complete
            );
        }

        public void stop_wineserver (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            owned ToastCallback on_toast,
            owned CompletionCallback? on_complete = null
        ) {
            run_launch_worker (
                "launch-stop-wineserver-worker",
                () => {
                    Runtime.stop_prefix_wineserver (entry, runner_specs);
                    return _("Stopped wineserver.");
                },
                on_toast,
                on_complete
            );
        }

        private void run_launch_worker (
            string worker_name,
            owned LaunchOperation operation,
            ToastCallback on_toast,
            CompletionCallback? on_complete
        ) {
            new Thread<bool> (worker_name, () => {
                string toast_msg;
                try {
                    toast_msg = operation ();
                } catch (Error e) {
                    toast_msg = _("Launch failed: %s").printf (e.message);
                }
                notify_ui (toast_msg, on_toast, on_complete);
                return true;
            });
        }

        private void notify_ui (
            string message,
            ToastCallback on_toast,
            CompletionCallback? on_complete
        ) {
            var msg = message;
            Idle.add (() => {
                on_toast (msg);
                if (on_complete != null) {
                    on_complete ();
                }
                return false;
            });
        }
    }
}
