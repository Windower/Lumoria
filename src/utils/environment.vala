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

        public static bool has_x11_display () {
            var display = Environment.get_variable ("DISPLAY");
            return display != null && display.strip () != "";
        }

        public static string host_etc_path (string name) {
            var host = Path.build_filename ("/run/host/etc", name);
            if (is_flatpak () && FileUtils.test (host, FileTest.EXISTS)) return host;
            return Path.build_filename ("/etc", name);
        }
    }

    public delegate string KeyValueTransform (string value);

    public static string? key_value_file_value (
        string path,
        string key,
        KeyValueTransform? transform = null
    ) {
        string content;
        try {
            FileUtils.get_contents (path, out content);
        } catch (Error e) {
            return null;
        }
        foreach (var line in content.split ("\n")) {
            var trimmed = line.strip ();
            if (trimmed == "" || trimmed.has_prefix ("#")) continue;
            var eq = trimmed.index_of_char ('=');
            if (eq <= 0) continue;
            if (trimmed.substring (0, eq) != key) continue;
            var raw = trimmed.substring (eq + 1);
            return transform != null ? transform (raw) : raw.strip ();
        }
        return null;
    }
}
