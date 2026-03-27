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
            return Environment.get_variable ("DESKTOP_SESSION") == "gamescope-wayland";
        }

        public static bool is_sandboxed () {
            return is_flatpak ();
        }
    }
}
