namespace Lumoria.Ui {

    public abstract class Metrics {
        public const int PAGE_MARGIN = 12;
        public const int PAGE_MARGIN_WIDE = 24;
        public const int GROUP_SPACING = 12;
        public const int HEADING_GAP = 6;
        public const int PAGE_BOTTOM = 24;
        public const int EDITOR_INSET = 8;
        public const int SIDEBAR_MIN = 240;
        public const int SIDEBAR_MAX = 360;
        public const double SIDEBAR_FRACTION = 0.28;
        public const int COMPACT_MAX_WIDTH = 960;
        public const int TOOLBAR_ICONS_MAX_WIDTH = 450;
        public const int BANNER_STACK_WIDTH = 520;
        public const int DIALOG_WIDTH_NARROW = 420;
        public const int DIALOG_WIDTH_WIDE = 560;
        public const int WINDOW_WIDTH = 980;
        public const int WINDOW_HEIGHT = 640;
        public const int WINDOW_WIDTH_SCREENSHOTS = 1100;
        public const int WINDOW_HEIGHT_SCREENSHOTS = 720;

        public static string compact_condition () {
            return "max-width: %dpx".printf (COMPACT_MAX_WIDTH);
        }

        public static string toolbar_icons_condition () {
            return "max-width: %dpx".printf (TOOLBAR_ICONS_MAX_WIDTH);
        }

        public static string banner_stack_condition () {
            return "max-width: %dpx".printf (BANNER_STACK_WIDTH);
        }
    }
}
