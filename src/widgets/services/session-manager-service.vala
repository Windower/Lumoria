namespace Lumoria.Widgets.Services {

    public delegate void SessionStatusCallback (Cli.SessionStatus status, string message);
    public delegate void SessionLaunchesCallback (owned Gee.ArrayList<Cli.SessionLaunchInfo> launches);
    public delegate void SessionErrorCallback (string message);


    public class SessionClient : Object {

        public void ping_async (owned SessionStatusCallback on_result) {
            var status = Cli.SessionStatus.UNAVAILABLE;
            string message = "";
            run_worker ("session-ping", () => {
                status = Cli.session_probe (out message);
            }, () => on_result (status, message), (error) => on_result (Cli.SessionStatus.UNAVAILABLE, error));
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

        public void force_pid_async (
            int wrap_pid,
            owned Utils.Action on_success,
            owned SessionErrorCallback on_error
        ) {
            run_worker ("session-force-pid", () => Cli.session_force_pid (wrap_pid), (owned) on_success, (owned) on_error);
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
