namespace Lumoria.Utils {

    public class ScreenInhibitor : Object {
        private Xdp.Portal? portal = null;
        private int handle = -1;

        public bool start (string reason, int timeout_ms, out string error) {
            error = "";
            try {
                portal = new Xdp.Portal.initable_new ();
            } catch (Error e) {
                portal = null;
                error = e.message;
                return false;
            }

            var loop = new MainLoop ();
            string local_error = "";
            bool timed_out = false;
            uint timeout_id = Timeout.add (timeout_ms, () => {
                timed_out = true;
                loop.quit ();
                return Source.REMOVE;
            });

            portal.session_inhibit.begin (
                null,
                reason,
                Xdp.InhibitFlags.IDLE | Xdp.InhibitFlags.SUSPEND,
                null,
                (obj, res) => {
                    try {
                        handle = portal.session_inhibit.end (res);
                    } catch (Error e) {
                        local_error = e.message;
                    }
                    loop.quit ();
                });

            loop.run ();
            if (!timed_out) Source.remove (timeout_id);
            error = timed_out ? "timed out" : local_error;
            return handle >= 0;
        }

        public bool stop () {
            if (portal == null || handle < 0) return false;
            portal.session_uninhibit (handle);
            handle = -1;
            return true;
        }

        public static bool probe (int timeout_ms, out string error) {
            var inhibitor = new ScreenInhibitor ();
            var supported = inhibitor.start ("Checking screen inhibitor support", timeout_ms, out error);
            inhibitor.stop ();
            return supported;
        }
    }
}
