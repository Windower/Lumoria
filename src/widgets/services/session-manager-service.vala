namespace Lumoria.Widgets.Services {

    public delegate void SessionBoolCallback (bool value);
    public delegate void SessionLaunchesCallback (owned Gee.ArrayList<Cli.SessionLaunchInfo> launches);
    public delegate void SessionVoidCallback ();
    public delegate void SessionErrorCallback (string message);

    private delegate bool SessionPingOperation ();
    private delegate void SessionVoidOperation () throws Error;

    public class SessionManagerService : Object {

        public void ping_async (owned SessionBoolCallback on_result) {
            new Thread<bool> ("session-ping", () => {
                bool value = Cli.session_ping ();
                Idle.add (() => {
                    on_result (value);
                    return false;
                });
                return true;
            });
        }

        public void list_launches_async (owned SessionLaunchesCallback on_result, owned SessionErrorCallback on_error) {
            new Thread<bool> ("session-list", () => {
                Gee.ArrayList<Cli.SessionLaunchInfo>? launches = null;
                string? error = null;
                try {
                    launches = Cli.session_list_launches ();
                } catch (Error e) {
                    error = e.message;
                }
                Idle.add (() => {
                    if (error != null) {
                        on_error (error);
                    } else {
                        on_result (launches);
                    }
                    return false;
                });
                return true;
            });
        }

        public void stop_pid_async (
            int wrap_pid,
            owned SessionVoidCallback on_success,
            owned SessionErrorCallback on_error
        ) {
            run_void_worker ("session-stop-pid", () => Cli.session_stop_pid (wrap_pid), (owned) on_success, (owned) on_error);
        }

        public void stop_prefix_async (
            string prefix_id,
            owned SessionVoidCallback on_success,
            owned SessionErrorCallback on_error
        ) {
            run_void_worker (
                "session-stop-prefix",
                () => Cli.session_stop_prefix (prefix_id),
                (owned) on_success,
                (owned) on_error
            );
        }

        public void stop_all_async (
            owned SessionVoidCallback on_success,
            owned SessionErrorCallback on_error
        ) {
            run_void_worker ("session-stop-all", () => Cli.session_stop_all (), (owned) on_success, (owned) on_error);
        }

        private void run_void_worker (
            string name,
            owned SessionVoidOperation operation,
            owned SessionVoidCallback on_success,
            owned SessionErrorCallback on_error
        ) {
            new Thread<bool> (name, () => {
                string? error = null;
                try {
                    operation ();
                } catch (Error e) {
                    error = e.message;
                }
                Idle.add (() => {
                    if (error != null) {
                        on_error (error);
                    } else {
                        on_success ();
                    }
                    return false;
                });
                return true;
            });
        }
    }
}
