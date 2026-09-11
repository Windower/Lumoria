namespace Lumoria.Models {

    public delegate T ManifestParser<T> (Json.Object obj) throws Error;
    public delegate T NamedManifestParser<T> (Json.Object obj, string name) throws Error;

    public static bool json_has (Json.Object? obj, string key) {
        return obj != null && obj.has_member (key);
    }

    public static Json.Object? json_object (Json.Object? obj, string key) {
        if (!json_has (obj, key)) return null;
        var node = obj.get_member (key);
        return node.get_node_type () == Json.NodeType.OBJECT ? node.get_object () : null;
    }

    /* Optional nested object run through parser: null when absent, an error when present but not an object. */
    public static T? json_parse_member<T> (Json.Object obj, string key, ManifestParser<T> parser) throws Error {
        if (!obj.has_member (key)) return null;
        var node = obj.get_member (key);
        if (node.get_node_type () != Json.NodeType.OBJECT) {
            throw new LumoriaError.INVALID_MANIFEST (_("Field '%s' must be an object").printf (key));
        }
        return parser (node.get_object ());
    }

    public static string json_string (Json.Object? obj, string key, string fallback = "") {
        if (!json_has (obj, key) || obj.get_null_member (key)) return fallback;
        return obj.get_string_member (key);
    }

    public static string json_require_string (Json.Object obj, string key) throws Error {
        var value = json_string (obj, key);
        if (value == "") {
            throw new LumoriaError.INVALID_MANIFEST (_("Missing required field '%s'").printf (key));
        }
        return value;
    }

    public static bool json_bool (Json.Object obj, string key, bool fallback = false) {
        return obj.has_member (key) ? obj.get_boolean_member (key) : fallback;
    }

    public static int64 json_int (Json.Object obj, string key, int64 fallback = 0) {
        return obj.has_member (key) ? obj.get_int_member (key) : fallback;
    }

    public static Gee.HashMap<string, T> json_object_map<T> (
        Json.Object obj,
        string key,
        ManifestParser<T> parser
    ) throws Error {
        var map = new Gee.HashMap<string, T> ();
        if (!obj.has_member (key)) return map;
        var members = obj.get_object_member (key);
        foreach (var member in members.get_members ()) {
            map[member] = parser (members.get_object_member (member));
        }
        return map;
    }

    public static string? json_scalar_to_string (Json.Node node) {
        switch (node.get_node_type ()) {
            case Json.NodeType.NULL:
                return "";
            case Json.NodeType.VALUE:
                var t = node.get_value_type ();
                if (t == typeof (bool)) return node.get_boolean ().to_string ();
                if (t == typeof (string)) return node.get_string ();
                if (t == typeof (int64)) return node.get_int ().to_string ();
                if (t == typeof (double)) return node.get_double ().to_string ();
                return "";
            default:
                return null;
        }
    }

    public static bool? json_bool_nullable (Json.Object obj, string key) {
        if (!obj.has_member (key)) return null;
        var node = obj.get_member (key);
        if (node.get_node_type () == Json.NodeType.NULL) return null;
        return node.get_boolean ();
    }

    public static Gee.ArrayList<DownloadItem> parse_downloads (Json.Object obj) throws Error {
        return parse_json_array<DownloadItem> (obj, "downloads", (o) => DownloadItem.from_json (o));
    }

    public static Gee.ArrayList<InstallStep> parse_steps (Json.Object obj) throws Error {
        return parse_json_array<InstallStep> (obj, "steps", (o) => InstallStep.from_json (o));
    }

    public static Gee.ArrayList<Entrypoint> parse_entrypoints (Json.Object obj) throws Error {
        return parse_json_array<Entrypoint> (obj, "entrypoints", (o) => Entrypoint.from_json (o));
    }

    public static Gee.ArrayList<ManifestAction> parse_manifest_actions (Json.Object obj) throws Error {
        return parse_json_array<ManifestAction> (obj, "actions", (o) => ManifestAction.from_json (o));
    }

    public static Gee.ArrayList<EnvRule> parse_env_rules (Json.Object obj) throws Error {
        return parse_json_array<EnvRule> (obj, "env", (o) => EnvRule.from_json (o));
    }

    public static Gee.HashMap<string, RuntimeComponentOverride> json_component_override_map (
        Json.Object obj,
        string key
    ) throws Error {
        return json_object_map<RuntimeComponentOverride> (obj, key, (o) => RuntimeComponentOverride.from_json (o));
    }

    public static Gee.ArrayList<T> parse_json_array<T> (Json.Object obj, string member, ManifestParser<T> parser) throws Error {
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

    public static string json_string_or_array (Json.Object obj, string key) {
        if (!obj.has_member (key)) return "";
        var node = obj.get_member (key);
        if (node.get_node_type () == Json.NodeType.ARRAY) return json_join_lines (node.get_array ());
        if (node.get_node_type () == Json.NodeType.NULL) return "";
        return node.get_string ();
    }

    public static string json_join_lines (Json.Array arr) {
        var parts = new string[arr.get_length ()];
        for (uint i = 0; i < arr.get_length (); i++) {
            parts[i] = arr.get_string_element (i);
        }
        return string.joinv ("\n", parts);
    }

    public static bool json_array_of_strings (Json.Array arr) {
        for (uint i = 0; i < arr.get_length (); i++) {
            var node = arr.get_element (i);
            if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string)) return false;
        }
        return true;
    }

    public static Gee.HashMap<string, string> json_string_map (Json.Object obj, string key) {
        var map = new Gee.HashMap<string, string> ();
        if (!obj.has_member (key)) return map;
        var m = obj.get_object_member (key);
        m.foreach_member ((_, k, node) => {
            var value = json_scalar_to_string (node);
            if (value != null) map[k] = value;
        });
        return map;
    }

    public static Json.Object json_string_map_object (Gee.Map<string, string> map) {
        var obj = new Json.Object ();
        foreach (var entry in map.entries) {
            obj.set_string_member (entry.key, entry.value);
        }
        return obj;
    }

    public static Json.Array json_string_list_array (Gee.Collection<string> values) {
        var arr = new Json.Array ();
        foreach (var value in values) arr.add_string_element (value);
        return arr;
    }

    public static string json_object_to_string (Json.Object obj, bool pretty = false) {
        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (obj);
        var gen = new Json.Generator ();
        gen.set_root (node);
        gen.pretty = pretty;
        if (pretty) gen.indent = 2;
        return gen.to_data (null);
    }

    public static Json.Array strv_to_json_array (string[] values) {
        var arr = new Json.Array ();
        foreach (var value in values) {
            if (value != null) arr.add_string_element (value);
        }
        return arr;
    }

    public static string[] json_array_to_strv (Json.Array arr) {
        var values = new string[arr.get_length ()];
        for (uint i = 0; i < arr.get_length (); i++) {
            values[i] = arr.get_string_element (i);
        }
        return values;
    }

    public static T? find_by_id<T> (Gee.Iterable<T> items, string id) {
        if (id == "") return null;
        foreach (var item in items) {
            var record = item as IdentifiedRecord;
            if (record != null && record.id == id) return item;
        }
        return null;
    }

    public static Json.Object parse_file_object (string file_path) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_file (file_path);
        return require_object_root (parser.get_root (), file_path);
    }

    public static Json.Node parse_data_node (string data, ssize_t len = -1) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_data (data, len);
        var root = parser.get_root ();
        if (root == null) {
            throw new LumoriaError.INVALID_MANIFEST ("Expected JSON");
        }
        return root;
    }

    public static Json.Object parse_data_object (string data, ssize_t len = -1) throws Error {
        return require_object_root (parse_data_node (data, len), "payload");
    }

    private static Json.Object require_object_root (Json.Node? root, string source) throws Error {
        if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
            throw new LumoriaError.INVALID_MANIFEST ("Expected a JSON object in %s", source);
        }
        return root.get_object ();
    }

    /* Adds the ids of every bundled <id>.json under the manifest subdirectory to ids. */
    public static void collect_manifest_ids_from_resource (string manifest_subdir, Gee.Set<string> ids) {
        var dir_path = Config.RESOURCE_BASE + "/manifests/" + manifest_subdir;
        try {
            foreach (var child in GLib.resources_enumerate_children (dir_path, ResourceLookupFlags.NONE)) {
                if (child.has_suffix (".json")) ids.add (child.substring (0, child.length - 5));
            }
        } catch (Error e) {
            warning ("Failed to enumerate manifests in %s: %s", manifest_subdir, e.message);
        }
    }

    public static Gee.ArrayList<T> load_named_manifests_from_resource<T> (
        string manifest_subdir,
        string[] names,
        string kind,
        NamedManifestParser<T> parser
    ) throws Error {
        var loaded = new Gee.ArrayList<T> ();
        var failures = new Gee.ArrayList<string> ();
        foreach (unowned string name in names) {
            if (name == null || name == "") continue;
            var relative_path = "%s/%s.json".printf (manifest_subdir, name);
            try {
                loaded.add (parser (ManifestStore.load_object (relative_path), name));
            } catch (Error e) {
                failures.add ("%s (%s)".printf (name, e.message));
            }
        }
        if (failures.size > 0) {
            throw new LumoriaError.INVALID_MANIFEST (
                "Failed to load %s manifest(s): %s".printf (kind, string.joinv (", ", Utils.strv (failures)))
            );
        }
        return loaded;
    }
}
