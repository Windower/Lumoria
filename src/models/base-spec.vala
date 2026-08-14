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

    public static string json_string_or_lines (Json.Object obj, string key) {
        if (!obj.has_member (key)) return "";
        var node = obj.get_member (key);
        if (node.get_node_type () == Json.NodeType.ARRAY) {
            var arr = node.get_array ();
            var parts = new string[arr.get_length ()];
            for (uint i = 0; i < arr.get_length (); i++) {
                parts[i] = arr.get_string_element (i);
            }
            return string.joinv ("\n", parts);
        }
        if (node.get_node_type () == Json.NodeType.NULL) return "";
        return node.get_string ();
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

    public static Json.Object parse_file_object (string file_path) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_file (file_path);
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
        public Gee.ArrayList<string> skip_versions { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> features { get; owned set; default = new Gee.ArrayList<string> (); }

        public string display_label () {
            if (label != "") return label;
            if (name != "") return name;
            return id;
        }

        public bool skips_version (string tag) {
            var normalized = tag.strip ();
            if (normalized == "") return false;
            foreach (var skipped in skip_versions) {
                if (skipped.strip () == normalized) return true;
            }
            return false;
        }

        public bool supports_feature (string feature) {
            var normalized = feature.strip ();
            if (normalized == "") return false;
            foreach (var f in features) {
                if (f.strip () == normalized) return true;
            }
            return false;
        }

        protected void parse_base (Json.Object obj) {
            id = json_string (obj, "id");
            name = json_string (obj, "name");
            label = json_string (obj, "label");
            skip_versions = json_string_array (obj, "skip_versions");
            features = json_string_array (obj, "features");
        }
    }

    public abstract class InstallableSpec : BaseSpec {
        public Gee.ArrayList<DownloadItem> downloads { get; owned set; default = new Gee.ArrayList<DownloadItem> (); }
        public Gee.ArrayList<InstallStep> steps { get; owned set; default = new Gee.ArrayList<InstallStep> (); }
        public Gee.ArrayList<SpecAction> actions { get; owned set; default = new Gee.ArrayList<SpecAction> (); }
        public Gee.ArrayList<RemoteManifestAction> remote_manifest_actions { get; owned set; default = new Gee.ArrayList<RemoteManifestAction> (); }
        public Gee.ArrayList<EnvRule> env { get; owned set; default = new Gee.ArrayList<EnvRule> (); }
        public bool reinstallable { get; set; default = true; }
        public string wineboot_mscoree { get; set; default = "disabled"; }
        public bool has_wineboot_mscoree { get; set; default = false; }

        protected void parse_installable (Json.Object obj) throws Error {
            parse_base (obj);
            downloads = parse_downloads (obj);
            steps = parse_steps (obj);
            actions = parse_actions (obj);
            remote_manifest_actions = parse_remote_manifest_actions (obj);
            env = parse_env_rules (obj);
            reinstallable = json_bool (obj, "reinstallable", true);
            has_wineboot_mscoree = obj.has_member ("wineboot_mscoree");
            wineboot_mscoree = json_string (obj, "wineboot_mscoree", "disabled");
        }

        protected void parse_installable_supporting_fields (
            Json.Object obj,
            out Gee.HashMap<string, string> variables,
            out Gee.ArrayList<EnvRule> variable_rules,
            out Gee.ArrayList<Entrypoint> entrypoints,
            out Gee.ArrayList<string> redists
        ) throws Error {
            parse_variable_definitions (obj, "variables", out variables, out variable_rules);
            entrypoints = parse_entrypoints (obj);
            redists = json_string_array (obj, "redists");
        }
    }

    public class SpecRepository : Object {
        private static SpecRepository? shared_instance;
        private string validation_error = "";

        public Gee.ArrayList<InstallerSpec> installers { get; private set; }
        public Gee.ArrayList<RunnerSpec> runners { get; private set; }
        public Gee.ArrayList<LauncherSpec> launchers { get; private set; }
        public Gee.HashMap<string, RedistSpec> redists { get; private set; }
        public Gee.ArrayList<ComponentSpec> components { get; private set; }

        public SpecRepository () {
            installers = InstallerSpec.load_all_from_resource ();
            runners = RunnerSpec.load_all_from_resource ();
            launchers = LauncherSpec.load_all_from_resource ();
            redists = RedistSpec.load_all_from_resource ();
            components = ComponentSpec.load_all_from_resource ();
            try {
                validate ();
            } catch (Error e) {
                validation_error = e.message;
                critical ("Invalid specification repository: %s", e.message);
            }
        }

        public static SpecRepository shared () {
            if (shared_instance == null) shared_instance = new SpecRepository ();
            return shared_instance;
        }

        public InstallerSpec? installer (string id) {
            return InstallerSpec.find_by_id (installers, id);
        }

        public InstallerSpec require_installer (string id) throws Error {
            require_valid ();
            var spec = installer (id);
            if (spec == null) {
                throw new IOError.FAILED ("Unknown installer specification: %s", id);
            }
            return spec;
        }

        public LauncherSpec? launcher (string id) {
            foreach (var spec in launchers) {
                if (spec.id == id) return spec;
            }
            return null;
        }

        public void require_valid () throws Error {
            if (validation_error != "") {
                throw new IOError.FAILED ("Invalid specification repository: %s", validation_error);
            }
        }

        private void validate () throws Error {
            var installer_resources = list_spec_ids_from_resource ("installers");
            if (installer_resources.length == 0) {
                throw new IOError.FAILED ("No installer specifications were loaded");
            }
            if (installers.size != installer_resources.length) {
                throw new IOError.FAILED (
                    "One or more installer specifications failed to load"
                );
            }

            var installer_ids = new Gee.HashSet<string> ();
            foreach (var installer in installers) {
                if (installer.id == "") {
                    throw new IOError.FAILED ("Installer specification has no id");
                }
                if (!installer_ids.add (installer.id)) {
                    throw new IOError.FAILED ("Duplicate installer id: %s", installer.id);
                }

                var region_ids = new Gee.HashSet<string> ();
                foreach (var region in installer.regions) {
                    if (region.id == "" || !region_ids.add (region.id)) {
                        throw new IOError.FAILED (
                            "Installer '%s' has an empty or duplicate region id", installer.id
                        );
                    }
                }
                if (installer.default_region_id != ""
                    && !region_ids.contains (installer.default_region_id)) {
                    throw new IOError.FAILED (
                        "Installer '%s' has unknown default region '%s'",
                        installer.id,
                        installer.default_region_id
                    );
                }

                var launcher_ids = new Gee.HashSet<string> ();
                foreach (var launcher_id in installer.launcher_ids) {
                    if (launcher_id == "" || !launcher_ids.add (launcher_id)) {
                        throw new IOError.FAILED (
                            "Installer '%s' has an empty or duplicate launcher reference", installer.id
                        );
                    }
                    if (launcher (launcher_id) == null) {
                        throw new IOError.FAILED (
                            "Installer '%s' references unknown launcher '%s'", installer.id, launcher_id
                        );
                    }
                }
                if (installer.default_launcher_id != ""
                    && !installer.launcher_ids.contains (installer.default_launcher_id)) {
                    throw new IOError.FAILED (
                        "Installer '%s' has unsupported default launcher '%s'",
                        installer.id,
                        installer.default_launcher_id
                    );
                }

                var patch_ids = new Gee.HashSet<string> ();
                foreach (var patch in installer.patches) {
                    if (patch.id == "" || !patch_ids.add (patch.id)) {
                        throw new IOError.FAILED (
                            "Installer '%s' has an empty or duplicate patch id", installer.id
                        );
                    }
                    if (patch.patch_type != "pe_characteristic"
                        || patch.setting != "large_address_aware"
                        || patch.flag != "IMAGE_FILE_LARGE_ADDRESS_AWARE"
                        || patch.target.strip () == "") {
                        throw new IOError.FAILED (
                            "Installer '%s' has unsupported patch '%s'", installer.id, patch.id
                        );
                    }
                }

                foreach (var redist_id in installer.redists) {
                    if (!redists.has_key (redist_id)) {
                        throw new IOError.FAILED (
                            "Installer '%s' references unknown redist '%s'", installer.id, redist_id
                        );
                    }
                }
            }

            var component_ids = new Gee.HashSet<string> ();
            foreach (var component in components) {
                if (component.id == "" || !component_ids.add (component.id)) {
                    throw new IOError.FAILED ("Component has an empty or duplicate id");
                }
                foreach (var installer_id in component.installer_ids) {
                    if (!installer_ids.contains (installer_id)) {
                        throw new IOError.FAILED (
                            "Component '%s' references unknown installer '%s'",
                            component.id,
                            installer_id
                        );
                    }
                }
            }
        }
    }
}
