namespace Lumoria.Widgets.Services {

    public delegate void SessionBoolCallback (bool value);
    public delegate void SessionLaunchesCallback (owned Gee.ArrayList<Cli.SessionLaunchInfo> launches);
    public delegate void SessionErrorCallback (string message);


    public class SessionClient : Object {

        public void ping_async (owned SessionBoolCallback on_result) {
            bool value = false;
            run_worker ("session-ping", () => {
                value = Cli.session_ping ();
            }, () => on_result (value), (_) => on_result (false));
        }

        public void list_launches_async (owned SessionLaunchesCallback on_result, owned SessionErrorCallback on_error) {
            Gee.ArrayList<Cli.SessionLaunchInfo>? launches = null;
            run_worker ("session-list", () => {
                launches = Cli.session_list_launches ();
            }, () => on_result (launches), (owned) on_error);
        }

        public void stop_pid_async (
            int wrap_pid,
            owned Utils.Action on_success,
            owned SessionErrorCallback on_error
        ) {
            run_worker ("session-stop-pid", () => Cli.session_stop_pid (wrap_pid), (owned) on_success, (owned) on_error);
        }

        public void stop_all_async (
            owned Utils.Action on_success,
            owned SessionErrorCallback on_error
        ) {
            run_worker ("session-stop-all", () => Cli.session_stop_all (), (owned) on_success, (owned) on_error);
        }

        private void run_worker (
            string name,
            owned Utils.FallibleAction operation,
            owned Utils.Action on_success,
            owned SessionErrorCallback on_error
        ) {
            Utils.run_background (name, () => {
                operation ();
            }, (error) => {
                if (error != null) on_error (error.message);
                else on_success ();
            });
        }
    }
}
