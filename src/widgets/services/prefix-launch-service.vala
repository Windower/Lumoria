namespace Lumoria.Widgets.Services {

    public delegate void ToastCallback (string message);
    public delegate void StatusCallback (string message);
    public delegate void CompletionCallback ();
    private delegate string LaunchOperation () throws Error;

    private class LaunchCallbacks : Object {
        public ToastCallback on_toast;
        public StatusCallback? on_status;
        public CompletionCallback? on_complete;

        public LaunchCallbacks (
            owned ToastCallback on_toast,
            owned StatusCallback? on_status,
            owned CompletionCallback? on_complete
        ) {
            this.on_toast = (owned) on_toast;
            this.on_status = (owned) on_status;
            this.on_complete = (owned) on_complete;
        }
    }

    public class PrefixLaunchService : Object {
        public void launch_prefix (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs,
            string entrypoint_id,
            owned ToastCallback on_toast,
            owned StatusCallback? on_status = null,
            owned CompletionCallback? on_complete = null
        ) {
            var callbacks = new LaunchCallbacks ((owned) on_toast, (owned) on_status, (owned) on_complete);
            run_launch_worker ("launch-worker", () => {
                var result = Runtime.run_prefix (
                    entry,
                    runner_specs,
                    launcher_specs,
                    entrypoint_id,
                    "",
                    null,
                    Runtime.LaunchPolicy.INTERACTIVE,
                    (message) => notify_status (message, callbacks)
                );
                return _("Launched (pid %d)").printf (result.pid);
            }, callbacks);
        }

        public void launch_exe (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs,
            string exe_path,
            owned ToastCallback on_toast,
            owned StatusCallback? on_status = null,
            owned CompletionCallback? on_complete = null
        ) {
            var callbacks = new LaunchCallbacks ((owned) on_toast, (owned) on_status, (owned) on_complete);
            run_launch_worker ("launch-exe-worker", () => {
                var result = Runtime.run_prefix (
                    entry,
                    runner_specs,
                    launcher_specs,
                    "",
                    exe_path,
                    null,
                    Runtime.LaunchPolicy.INTERACTIVE,
                    (message) => notify_status (message, callbacks)
                );
                return _("Launched EXE (pid %d)").printf (result.pid);
            }, callbacks);
        }

        public void launch_wine_tool (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            string[] wine_args,
            string label,
            owned ToastCallback on_toast,
            owned StatusCallback? on_status = null,
            owned CompletionCallback? on_complete = null
        ) {
            var args = new Gee.ArrayList<string> ();
            foreach (var a in wine_args) args.add (a);

            var callbacks = new LaunchCallbacks ((owned) on_toast, (owned) on_status, (owned) on_complete);
            run_launch_worker ("launch-tool-worker", () => {
                var result = Runtime.run_prefix_command (
                    entry,
                    runner_specs,
                    args,
                    label,
                    Runtime.LaunchPolicy.INTERACTIVE,
                    (message) => notify_status (message, callbacks)
                );
                return _("Launched %s (pid %d)").printf (label, result.pid);
            }, callbacks);
        }

        public void stop_wineserver (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            owned ToastCallback on_toast,
            owned CompletionCallback? on_complete = null
        ) {
            var callbacks = new LaunchCallbacks ((owned) on_toast, null, (owned) on_complete);
            run_launch_worker ("launch-stop-wineserver-worker", () => {
                Runtime.stop_prefix_wineserver (entry, runner_specs);
                return _("Stopped wineserver.");
            }, callbacks);
        }

        private void run_launch_worker (
            string worker_name,
            owned LaunchOperation operation,
            LaunchCallbacks callbacks
        ) {
            new Thread<bool> (worker_name, () => {
                string toast_msg;
                try {
                    toast_msg = operation ();
                } catch (Error e) {
                    toast_msg = _("Launch failed: %s").printf (e.message);
                }
                notify_ui (toast_msg, callbacks);
                return true;
            });
        }

        private void notify_ui (
            string message,
            LaunchCallbacks callbacks
        ) {
            Idle.add (() => {
                callbacks.on_toast (message);
                if (callbacks.on_complete != null) callbacks.on_complete ();
                return false;
            });
        }

        private void notify_status (string message, LaunchCallbacks callbacks) {
            Idle.add (() => {
                if (callbacks.on_status != null) callbacks.on_status (message);
                return false;
            });
        }
    }
}
