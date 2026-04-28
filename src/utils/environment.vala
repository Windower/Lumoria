namespace Lumoria.Utils {

    public class EnvironmentInfo : Object {
        private static bool? flatpak_cached = null;

        public static bool is_flatpak () {
            if (flatpak_cached == null) {
                flatpak_cached = FileUtils.test ("/.flatpak-info", FileTest.IS_REGULAR);
            }
            return flatpak_cached;
        }

        public static bool is_gamescope () {
            var desktop_session = (Environment.get_variable ("DESKTOP_SESSION") ?? "").down ();
            if (desktop_session == "gamescope-wayland" ||
                desktop_session == "gamescope-session" ||
                desktop_session == "gamescope") {
                return true;
            }

            var session_desktop = (Environment.get_variable ("XDG_SESSION_DESKTOP") ?? "").down ();
            if (session_desktop == "gamescope") return true;

            var current_desktop = Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
            foreach (var part in current_desktop.split (":")) {
                if (part.down ().strip () == "gamescope") return true;
            }

            return false;
        }

        public static bool is_sandboxed () {
            return is_flatpak ();
        }

        public static bool is_wayland () {
            var display = Gdk.Display.get_default ();
            if (display == null) {
                return false;
            }

            return display.get_type ().name ().down ().contains ("wayland");
        }
    }
}
