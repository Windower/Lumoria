namespace Lumoria.Utils {

    public class ScreenInhibitor : Object {
        private Xdp.Portal? portal = null;
        private int handle = -1;

        /* Blocks on a private main context so it is safe from worker threads and the wrap process alike. */
        public bool start (string reason, int timeout_ms, out string error) {
            error = "";
            var context = new MainContext ();
            context.push_thread_default ();
            try {
                portal = new Xdp.Portal.initable_new ();
            } catch (Error e) {
                context.pop_thread_default ();
                portal = null;
                error = e.message;
                return false;
            }

            var loop = new MainLoop (context);
            string local_error = "";
            bool timed_out = false;
            var timeout = new TimeoutSource (timeout_ms);
            timeout.set_callback (() => {
                timed_out = true;
                loop.quit ();
                return Source.REMOVE;
            });
            timeout.attach (context);

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
            timeout.destroy ();
            context.pop_thread_default ();
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
