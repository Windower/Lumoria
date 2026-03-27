namespace Lumoria.Models {

    public delegate T SpecParser<T> (Json.Object obj) throws Error;
    public delegate T NamedSpecParser<T> (Json.Object obj, string name) throws Error;

    public static string json_string (Json.Object obj, string key, string fallback = "") {
        return obj.has_member (key) ? obj.get_string_member (key) : fallback;
    }

    public static bool json_bool (Json.Object obj, string key, bool fallback = false) {
        return obj.has_member (key) ? obj.get_boolean_member (key) : fallback;
    }

    public static bool? json_bool_nullable (Json.Object obj, string key) {
        if (!obj.has_member (key)) return null;
        var node = obj.get_member (key);
        if (node.get_node_type () == Json.NodeType.NULL) return null;
        return node.get_boolean ();
    }

    public static Gee.ArrayList<T> parse_json_array<T> (Json.Object obj, string member, SpecParser<T> parser) throws Error {
        var list = new Gee.ArrayList<T> ();
        if (!obj.has_member (member)) return list;
        var arr = obj.get_array_member (member);
        for (uint i = 0; i < arr.get_length (); i++) {
            list.add (parser (arr.get_object_element (i)));
        }
        return list;
    }

    public static Gee.ArrayList<string> json_string_array (Json.Object obj, string key) {
        var list = new Gee.ArrayList<string> ();
        if (!obj.has_member (key)) return list;
        var arr = obj.get_array_member (key);
        for (uint i = 0; i < arr.get_length (); i++) {
            list.add (arr.get_string_element (i));
        }
        return list;
    }

    public static Gee.HashMap<string, string> json_string_map (Json.Object obj, string key) {
        var map = new Gee.HashMap<string, string> ();
        if (!obj.has_member (key)) return map;
        var m = obj.get_object_member (key);
        m.foreach_member ((_, k, node) => { map[k] = node.get_string (); });
        return map;
    }

    private static Json.Object parse_resource_object (string resource_path) throws Error {
        var bytes = GLib.resources_lookup_data (resource_path, 0);
        var parser = new Json.Parser ();
        parser.load_from_data ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
        return parser.get_root ().get_object ();
    }

    public static string[] list_spec_ids_from_resource (string spec_subdir) {
        var ids = new Gee.ArrayList<string> ();
        var dir_path = Config.RESOURCE_BASE + "/specs/" + spec_subdir;
        try {
            var children = GLib.resources_enumerate_children (dir_path, ResourceLookupFlags.NONE);
            foreach (var child in children) {
                if (child.has_suffix (".json")) {
                    var id = child.substring (0, child.length - 5);
                    ids.add (id);
                }
            }
        } catch (Error e) {
            warning ("Failed to enumerate specs in %s: %s", spec_subdir, e.message);
        }
        ids.sort ((a, b) => strcmp (a, b));
        var arr = new string[ids.size];
        for (int i = 0; i < ids.size; i++) {
            arr[i] = ids[i];
        }
        return arr;
    }

    public static T load_single_spec_from_resource<T> (
        string relative_spec_path,
        string kind,
        SpecParser<T> parser,
        T fallback
    ) {
        if (relative_spec_path == "") {
            warning ("Failed to load %s spec: empty path", kind);
            return fallback;
        }
        var path = Config.RESOURCE_BASE + "/" + relative_spec_path;
        try {
            return parser (parse_resource_object (path));
        } catch (Error e) {
            warning ("Failed to load %s spec (%s): %s", kind, relative_spec_path, e.message);
            return fallback;
        }
    }

    public static Gee.ArrayList<T> load_named_specs_from_resource<T> (
        string spec_subdir,
        string[] names,
        string kind,
        NamedSpecParser<T> parser
    ) {
        var specs = new Gee.ArrayList<T> ();
        foreach (unowned string name in names) {
            if (name == null || name == "") continue;
            var relative_path = "specs/%s/%s.json".printf (spec_subdir, name);
            var full_path = Config.RESOURCE_BASE + "/" + relative_path;
            try {
                specs.add (parser (parse_resource_object (full_path), name));
            } catch (Error e) {
                warning ("Failed to load %s spec %s: %s", kind, name, e.message);
            }
        }
        return specs;
    }

    public abstract class BaseSpec : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string label { get; set; default = ""; }

        public string display_label () {
            if (label != "") return label;
            if (name != "") return name;
            return id;
        }

        protected void parse_base (Json.Object obj) {
            id = json_string (obj, "id");
            name = json_string (obj, "name");
            label = json_string (obj, "label");
        }
    }

    public abstract class InstallableSpec : BaseSpec {
        public Gee.ArrayList<DownloadItem> downloads { get; owned set; default = new Gee.ArrayList<DownloadItem> (); }
        public Gee.ArrayList<InstallStep> steps { get; owned set; default = new Gee.ArrayList<InstallStep> (); }

        protected void parse_installable (Json.Object obj) throws Error {
            parse_base (obj);
            downloads = parse_downloads (obj);
            steps = parse_steps (obj);
        }
    }
}
