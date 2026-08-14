namespace Lumoria.Utils {

    [CCode (cname = "pidfd_open", cheader_filename = "sys/pidfd.h")]
    private extern int pidfd_open (Posix.pid_t pid, uint flags);

    public class FeralGameModePortal : Object {
        private const string BUS_NAME = "org.freedesktop.portal.Desktop";
        private const string OBJECT_PATH = "/org/freedesktop/portal/desktop";
        private const string INTERFACE_NAME = "org.freedesktop.portal.GameMode";

        private DBusConnection? connection = null;
        private int requester_pid = -1;
        private bool anchor_registered = false;
        private Gee.HashSet<int> registered_targets = new Gee.HashSet<int> ();

        public bool start (int timeout_ms, out string error) {
            error = "";
            requester_pid = (int) Posix.getpid ();

            try {
                connection = Bus.get_sync (BusType.SESSION);
                var result = call_by_pidfd ("RegisterGameByPIDFd", requester_pid, timeout_ms);
                if (result != 0) {
                    error = "portal rejected wrapper registration";
                    connection = null;
                    return false;
                }
                anchor_registered = true;
                return true;
            } catch (Error e) {
                connection = null;
                error = e.message;
                return false;
            }
        }

        public bool register_target (int target_pid, int timeout_ms, out string error) {
            error = "";
            if (connection == null || !anchor_registered) {
                error = "GameMode portal is not active";
                return false;
            }
            if (target_pid <= 0 || target_pid == requester_pid) return true;
            if (registered_targets.contains (target_pid)) return true;

            try {
                var result = call_by_pidfd ("RegisterGameByPIDFd", target_pid, timeout_ms);
                if (result != 0) {
                    error = "portal rejected target registration";
                    return false;
                }
                registered_targets.add (target_pid);
                return true;
            } catch (Error e) {
                error = e.message;
                return false;
            }
        }

        public bool stop (int timeout_ms, out string error) {
            error = "";
            if (connection == null || !anchor_registered) return false;

            // The wrapper only stops after its monitored targets have exited.
            // The portal removes those registrations automatically; explicitly
            // unregistering dead PIDs would add one timeout per former target.
            registered_targets.clear ();

            try {
                var result = call_by_pidfd ("UnregisterGameByPIDFd", requester_pid, timeout_ms);
                anchor_registered = false;
                if (result != 0) {
                    error = "portal rejected wrapper unregistration";
                    return false;
                }
                return true;
            } catch (Error e) {
                anchor_registered = false;
                error = e.message;
                return false;
            }
        }

        public static bool probe (int timeout_ms, out string error) {
            error = "";
            var portal = new FeralGameModePortal ();
            portal.requester_pid = (int) Posix.getpid ();
            try {
                portal.connection = Bus.get_sync (BusType.SESSION);
                var result = portal.call_by_pidfd (
                    "QueryStatusByPIDFd",
                    portal.requester_pid,
                    timeout_ms
                );
                if (result >= 0) return true;
                error = "Feral GameMode is unavailable";
                return false;
            } catch (Error e) {
                error = e.message;
                return false;
            }
        }

        private int call_by_pidfd (string method, int target_pid, int timeout_ms) throws Error {
            var target_fd = pidfd_open ((Posix.pid_t) target_pid, 0);
            if (target_fd < 0) {
                throw new IOError.FAILED ("Could not open pidfd for target %d", target_pid);
            }

            var requester_fd = pidfd_open ((Posix.pid_t) requester_pid, 0);
            if (requester_fd < 0) {
                Posix.close (target_fd);
                throw new IOError.FAILED ("Could not open pidfd for requester %d", requester_pid);
            }

            try {
                var fd_list = new UnixFDList ();
                var target_handle = fd_list.append (target_fd);
                var requester_handle = fd_list.append (requester_fd);
                UnixFDList? out_fd_list;
                var reply = connection.call_with_unix_fd_list_sync (
                    BUS_NAME,
                    OBJECT_PATH,
                    INTERFACE_NAME,
                    method,
                    new Variant ("(hh)", target_handle, requester_handle),
                    new VariantType ("(i)"),
                    DBusCallFlags.NONE,
                    timeout_ms,
                    fd_list,
                    out out_fd_list,
                    null
                );
                int result;
                reply.get ("(i)", out result);
                return result;
            } finally {
                Posix.close (target_fd);
                Posix.close (requester_fd);
            }
        }
    }
}
