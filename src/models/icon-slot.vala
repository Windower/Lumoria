namespace Lumoria.Models {

    public class IconSlot : Object {
        public string key { get; construct; }
        public string label { get; construct; }
        public string search_text { get; construct; }
        public string resource { get; construct; default = ""; }
        public string symbolic { get; construct; default = ""; }
        public string css_class { get; construct; default = ""; }
        public string shortcut_resource { get; construct; default = ""; }
        public string shortcut_file { get; construct; default = ""; }

        public IconSlot (
            string key,
            string label,
            string search_text,
            string resource,
            string symbolic = "",
            string css_class = "",
            string shortcut_resource = "",
            string shortcut_file = ""
        ) {
            Object (
                key: key,
                label: label,
                search_text: search_text,
                resource: resource,
                symbolic: symbolic,
                css_class: css_class,
                shortcut_resource: shortcut_resource,
                shortcut_file: shortcut_file
            );
        }

        public bool has_shortcut_art () {
            return shortcut_resource != "";
        }

        public FfxiIconPick to_pick () {
            return new FfxiIconPick (key, label, search_text);
        }

        public Bytes? shortcut_bytes () throws Error {
            if (shortcut_resource == "") return null;
            return resources_lookup_data (shortcut_resource, ResourceLookupFlags.NONE);
        }
    }

    public class IconSlots : Object {
        public const string LUMORIA = "lumoria";
        public const string WINDOWER = "windower";
        public const string WINDOWER_APP = "windower-app";

        public const string LUMORIA_SVG = Config.RESOURCE_BASE + "/icons/hicolor/scalable/apps/net.windower.Lumoria.svg";
        public const string LUMORIA_PNG = Config.RESOURCE_BASE + "/icons/hicolor/512x512/apps/net.windower.Lumoria.png";
        public const string WINDOWER_PNG = Config.RESOURCE_BASE + "/icons/hicolor/256x256/apps/windower.png";
        public const string WINDOWER_MANDIE = "windower-mandie-symbolic";
        public const string WINDOWER_MANDIE_SVG = Config.RESOURCE_BASE + "/icons/scalable/actions/windower-mandie-symbolic.svg";

        private static IconSlot[]? slots;
        private static Gee.HashMap<string, IconSlot>? by_key;

        public static IconSlot[] all () {
            ensure ();
            return slots;
        }

        public static IconSlot? lookup (string key) {
            ensure ();
            return by_key.has_key (key) ? by_key[key] : null;
        }

        public static FfxiIconPick[] picker_slots (bool include_default = true) {
            ensure ();
            var extra = include_default ? 1 : 0;
            var picks = new FfxiIconPick[slots.length + extra];
            var i = 0;
            if (include_default) {
                picks[i++] = new FfxiIconPick ("", _("Default"), "default");
            }
            foreach (var slot in slots) picks[i++] = slot.to_pick ();
            return picks;
        }

        private static void ensure () {
            if (slots != null) return;
            slots = {
                new IconSlot (LUMORIA, _("Lumoria"), "lumoria", LUMORIA_SVG),
                new IconSlot (
                    WINDOWER_APP,
                    _("Windower"),
                    "windower",
                    WINDOWER_PNG,
                    "",
                    "",
                    WINDOWER_PNG,
                    "windower.png"
                ),
                new IconSlot (
                    WINDOWER,
                    _("Mandie"),
                    "windower mandie mandy",
                    WINDOWER_MANDIE_SVG,
                    WINDOWER_MANDIE,
                    "windower-mandie",
                    WINDOWER_PNG,
                    "windower.png"
                )
            };
            by_key = new Gee.HashMap<string, IconSlot> ();
            foreach (var slot in slots) by_key[slot.key] = slot;
        }
    }
}
