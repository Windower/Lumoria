namespace Lumoria.Models {

    public class FfxiIconPick : Object {
        public string key { get; set; default = ""; }
        public string label { get; set; default = ""; }
        public string search_text { get; set; default = ""; }

        public FfxiIconPick (string key, string label, string search_text) {
            Object (key: key, label: label, search_text: search_text);
        }

        public FfxiIconPick.from_icon (FfxiIconEntry icon) {
            this (FfxiIconCatalog.key_for (icon.id), icon.name, icon.search_text);
        }
    }

    public class FfxiIconHits : Object {
        public bool any = false;
        private Gee.HashSet<string> groups = new Gee.HashSet<string> ();
        private Gee.HashSet<string> subgroups = new Gee.HashSet<string> ();

        public void add (string group, string subgroup) {
            any = true;
            groups.add (group);
            if (subgroup != "") subgroups.add (group + "\x1f" + subgroup);
        }

        public bool has (string group, string subgroup) {
            if (group == FfxiIconCatalog.GROUP_ALL) return any;
            if (subgroup != "") return subgroups.contains (group + "\x1f" + subgroup);
            return groups.contains (group);
        }
    }

    public class FfxiIconEntry : Object {
        public string id { get; set; default = ""; }
        public string icon { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string group { get; set; default = ""; }
        public string subgroup { get; set; default = ""; }
        public string search_text { get; set; default = ""; }
        public Gee.ArrayList<string> groups {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
    }

    public class FfxiIconCatalog : Object {
        public const string KEY_PREFIX = "ffxi:";
        public const string RESOURCE_ID = "ffxi-icons";
        public const string REGISTRY_FILE = "icon-registry.json";
        public const string GROUP_ALL = "all";
        public const string GROUP_APP = "Application";
        public const string GROUP_OTHER = "Other";
        public const string GROUP_RECENT = "recent";
        private const string SIZE_128 = "128x128";

        public signal void changed ();

        public bool ready { get { return icons.size > 0; } }
        public string pack_root { get; private set; default = ""; }
        public Gee.ArrayList<FfxiIconEntry> icons {
            get; private set; default = new Gee.ArrayList<FfxiIconEntry> ();
        }
        public Gee.ArrayList<string> group_names {
            get; private set; default = new Gee.ArrayList<string> ();
        }

        private static FfxiIconCatalog? _instance;
        private string png_size = "";
        private Gee.HashMap<string, FfxiIconEntry> by_id;
        private Gee.HashMap<string, Gee.ArrayList<string>> subgroups_by_group;

        public static FfxiIconCatalog instance () {
            if (_instance == null) _instance = new FfxiIconCatalog ();
            return _instance;
        }

        construct {
            by_id = new Gee.HashMap<string, FfxiIconEntry> ();
            subgroups_by_group = new Gee.HashMap<string, Gee.ArrayList<string>> ();
        }

        public static bool is_slot_key (string key) {
            return IconSlots.lookup (key) != null || id_from_key (key) != null;
        }

        public static string sanitize_slot_key (string key) {
            var trimmed = key.strip ();
            if (trimmed == ""
                || trimmed == "play"
                || trimmed == "media-playback-start-symbolic") {
                return "";
            }
            return is_slot_key (trimmed) ? trimmed : "";
        }

        public static string sanitize_shortcut_icon (string value) {
            return value.strip () == IconSlots.LUMORIA ? IconSlots.LUMORIA : "";
        }

        public static bool is_item_id (string id) {
            string rest;
            if (id.has_prefix ("item-")) rest = id.substring (5);
            else if (id.has_prefix ("status-")) rest = id.substring (7);
            else if (id.has_prefix ("app-")) rest = id.substring (4);
            else return false;
            if (rest.length == 0) return false;
            for (int i = 0; i < rest.length; i++) {
                var c = rest.get_char (i);
                if (!c.isalnum () && c != '-') return false;
            }
            return true;
        }

        public static string key_for (string id) {
            return KEY_PREFIX + id;
        }

        public static bool has_registry (string dir) {
            return dir != ""
                && FileUtils.test (Path.build_filename (dir, REGISTRY_FILE), FileTest.IS_REGULAR);
        }

        public static string? installed_root () {
            var dir = Utils.resource_dir (RESOURCE_ID);
            return has_registry (dir) ? dir : null;
        }

        public static string? payload_root (string staging) {
            var nested = Path.build_filename (staging, RESOURCE_ID);
            if (has_registry (nested)) return nested;
            if (has_registry (staging)) return staging;
            return null;
        }

        public static string? id_from_key (string key) {
            if (!key.has_prefix (KEY_PREFIX)) return null;
            var id = key.substring (KEY_PREFIX.length);
            return is_item_id (id) ? id : null;
        }

        public FfxiIconEntry? by_key (string key) {
            var id = id_from_key (key);
            if (id == null) return null;
            return by_id.has_key (id) ? by_id[id] : null;
        }

        public Gee.ArrayList<string> subgroups_for (string group) {
            if (!subgroups_by_group.has_key (group)) return new Gee.ArrayList<string> ();
            return subgroups_by_group[group];
        }

        public static string display_group (string group) {
            if (group == GROUP_ALL) return _("All");
            if (group == GROUP_RECENT) return _("Recently used");
            return display_catalog_name (group);
        }

        public static string display_subgroup (string subgroup) {
            return display_catalog_name (subgroup);
        }

        private static string display_catalog_name (string name) {
            if (name == GROUP_APP) return _("Application");
            if (name == GROUP_OTHER) return _("Other");
            foreach (var msgid in catalog_label_msgids ()) {
                if (msgid == name) return _(msgid);
            }
            return name;
        }

        private static string[] catalog_label_msgids () {
            return {
                N_("Jobs"),
                N_("Weapons"),
                N_("Armor"),
                N_("Items"),
                N_("Status"),
                N_("Zones"),
                N_("Food"),
                N_("Usable"),
                N_("Furniture"),
                N_("Key Items"),
                N_("Synthesis"),
                N_("Fishing"),
                N_("General"),
                N_("Scrolls"),
                N_("Medicine"),
                N_("Ammo"),
                N_("Instruments"),
            };
        }

        public void reload () {
            clear ();
            group_names.clear ();
            subgroups_by_group.clear ();
            pack_root = installed_root () ?? "";
            if (pack_root == "") {
                changed ();
                return;
            }
            var registry = Path.build_filename (pack_root, REGISTRY_FILE);
            try {
                var root = parse_file_object (registry);
                png_size = pick_png_size (root);
                if (png_size == "" || !root.has_member ("items")) {
                    throw new IOError.FAILED ("Icon registry is missing items or sizes");
                }
                var arr = root.get_array_member ("items");
                var groups = new Gee.HashSet<string> ();
                var subgroup_sets = new Gee.HashMap<string, Gee.HashSet<string>> ();
                for (uint i = 0; i < arr.get_length (); i++) {
                    var entry = parse_item (arr.get_object_element (i));
                    if (entry == null) continue;
                    icons.add (entry);
                    by_id[entry.id] = entry;
                    if (entry.group == "") continue;
                    groups.add (entry.group);
                    if (entry.subgroup == "") continue;
                    if (!subgroup_sets.has_key (entry.group)) {
                        subgroup_sets[entry.group] = new Gee.HashSet<string> ();
                    }
                    subgroup_sets[entry.group].add (entry.subgroup);
                }
                group_names = sorted_names (groups);
                foreach (var group in group_names) {
                    if (!subgroup_sets.has_key (group)) continue;
                    subgroups_by_group[group] = sorted_names (subgroup_sets[group]);
                }
            } catch (Error e) {
                warning ("Failed to parse FFXI icon registry: %s", e.message);
                clear ();
                pack_root = "";
            }
            changed ();
        }

        private void clear () {
            icons.clear ();
            by_id.clear ();
            png_size = "";
        }

        public string? path_for (string id) {
            var hash = hash_for_id (id);
            if (hash == null) return null;
            return path_for_hash (hash);
        }

        public string? png_path_for_key (string key) {
            var id = id_from_key (key);
            if (id == null) return null;
            var path = path_for (id);
            if (path == null || !FileUtils.test (path, FileTest.IS_REGULAR)) return null;
            return path;
        }

        private string? hash_for_id (string id) {
            return by_id.has_key (id) ? by_id[id].icon : null;
        }

        private string? path_for_hash (string hash) {
            if (pack_root == "" || png_size == "" || !is_icon_hash (hash)) return null;
            return Path.build_filename (pack_root, png_size, hash + ".png");
        }

        /* Which groups and subgroups still have icons matching a search query. */
        public FfxiIconHits hits_for (string query) {
            var hits = new FfxiIconHits ();
            foreach (var icon in icons) {
                if (!icon.search_text.contains (query)) continue;
                hits.any = true;
                if (icon.group != "") hits.add (icon.group, icon.subgroup);
                foreach (var extra in icon.groups) {
                    if (extra != "") hits.add (extra, "");
                }
            }
            return hits;
        }

        public bool matches (FfxiIconEntry entry, string group, string subgroup, string query) {
            if (query != "" && !entry.search_text.contains (query)) return false;
            if (group == GROUP_RECENT) return false;
            if (group == "" || group == GROUP_ALL) return true;
            if (!in_group (entry, group)) return false;
            if (subgroup == "") return true;
            return entry.subgroup.down () == subgroup.down ();
        }

        public static bool in_group (FfxiIconEntry entry, string group) {
            if (group == "" || group == GROUP_ALL) return true;
            var want = group.down ();
            if (entry.group.down () == want) return true;
            foreach (var extra in entry.groups) {
                if (extra.down () == want) return true;
            }
            return false;
        }

        private static Gee.ArrayList<string> sorted_names (Gee.Collection<string> values) {
            var list = new Gee.ArrayList<string> ();
            foreach (var value in values) list.add (value);
            list.sort ((a, b) => a.collate (b));
            return list;
        }

        private static string pick_png_size (Json.Object root) {
            if (!root.has_member ("sizes")
                || root.get_member ("sizes").get_node_type () != Json.NodeType.ARRAY) {
                return "";
            }
            var arr = root.get_array_member ("sizes");
            var first = "";
            for (uint i = 0; i < arr.get_length (); i++) {
                var size = arr.get_string_element (i).strip ();
                if (size == "") continue;
                if (size == SIZE_128) return size;
                if (first == "") first = size;
            }
            return first;
        }

        private static FfxiIconEntry? parse_item (Json.Object obj) {
            var id = json_string (obj, "id");
            var hash = json_string (obj, "icon");
            if (!is_item_id (id) || !is_icon_hash (hash)) return null;
            var entry = new FfxiIconEntry ();
            entry.id = id;
            entry.icon = hash;
            entry.name = json_string (obj, "name");
            entry.group = json_string (obj, "group");
            entry.subgroup = json_string (obj, "subgroup");
            entry.groups = json_string_array (obj, "groups");
            var parts = new Gee.ArrayList<string> ();
            add_search_term (parts, entry.id);
            add_search_term (parts, entry.name);
            add_search_term (parts, json_string (obj, "logName"));
            foreach (var name in json_string_array (obj, "names")) add_search_term (parts, name);
            foreach (var name in json_string_array (obj, "logNames")) add_search_term (parts, name);
            add_search_term (parts, entry.group);
            add_search_term (parts, entry.subgroup);
            foreach (var extra in entry.groups) add_search_term (parts, extra);
            normalize_group (entry);
            add_search_term (parts, entry.group);
            entry.search_text = string.joinv (" ", Utils.strv (parts));
            return entry;
        }

        private static void normalize_group (FfxiIconEntry entry) {
            if (folds_into_other (entry.group)) {
                entry.group = GROUP_OTHER;
                entry.subgroup = "";
                return;
            }
            if (entry.subgroup == entry.group) entry.subgroup = "";
        }

        private static bool folds_into_other (string group) {
            switch (group) {
                case GROUP_OTHER:
                case "Book":
                case "Seeds":
                case "Linkshell":
                case "Flowerpot":
                case "Chocobo Item":
                case "Crystal":
                case "Fish":
                case "Automaton":
                case "Quest Item":
                    return true;
                default:
                    return false;
            }
        }

        private static bool is_icon_hash (string hash) {
            if (hash.length != 12) return false;
            for (int i = 0; i < hash.length; i++) {
                if (!hash.get_char (i).isxdigit ()) return false;
            }
            return true;
        }

        private static void add_search_term (Gee.ArrayList<string> parts, string value) {
            var folded = value.strip ().down ();
            if (folded != "") parts.add (folded);
        }
    }
}
