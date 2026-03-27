namespace Lumoria.Utils {

    public enum ToolKind {
        RUNNER,
        COMPONENT
    }

    public enum LoggingMode {
        DONT_KEEP,
        KEEP;

        public static LoggingMode from_settings () {
            return from_value (Preferences.instance ().logging_mode);
        }

        public static LoggingMode from_value (string value) {
            switch (value) {
                case "off":
                case "memory":
                case "dont_keep": return DONT_KEEP;
                default: return KEEP;
            }
        }

        public string to_value () {
            switch (this) {
                case DONT_KEEP: return "dont_keep";
                default: return "keep";
            }
        }
    }

    public class Preferences : Object {
        private static Preferences? _instance = null;
        private string file_path;
        private int _freeze_count = 0;
        private bool _dirty = false;

        public string runner_id { get; private set; default = ""; }
        public string runner_version { get; private set; default = "latest"; }

        private bool _updates_lumoria = true;
        private bool _updates_runners = true;
        private bool _updates_components = true;
        private string _logging_mode = "keep";
        private bool _wine_wayland = false;
        private bool _large_address_aware = false;

        public bool updates_lumoria { get { return _updates_lumoria; } }
        public bool updates_runners { get { return _updates_runners; } }
        public bool updates_components { get { return _updates_components; } }
        public string logging_mode { get { return _logging_mode; } }
        public bool wine_wayland { get { return _wine_wayland; } }
        public bool large_address_aware { get { return _large_address_aware; } }

        private Gee.HashMap<string, string> component_versions;
        private Gee.HashMap<string, bool?> component_enabled;
        private Gee.HashMap<string, string> runtime_env_vars;
        private Models.DefaultsSpec defaults_spec;

        private Preferences () {
            file_path = Path.build_filename (config_dir (), "preferences.json");
            component_versions = new Gee.HashMap<string, string> ();
            component_enabled = new Gee.HashMap<string, bool?> ();
            runtime_env_vars = new Gee.HashMap<string, string> ();
            defaults_spec = Models.DefaultsSpec.load_from_resource ();
            load ();
        }

        public static Preferences instance () {
            if (_instance == null) {
                _instance = new Preferences ();
            }
            return _instance;
        }

        public void freeze () { _freeze_count++; }

        public void thaw () {
            if (_freeze_count > 0) _freeze_count--;
            if (_freeze_count == 0 && _dirty) save ();
        }

        public void set_updates_lumoria (bool val) {
            _updates_lumoria = val;
            save ();
        }

        public void set_updates_runners (bool val) {
            _updates_runners = val;
            save ();
        }

        public void set_updates_components (bool val) {
            _updates_components = val;
            save ();
        }

        public void set_logging_mode (string mode) {
            _logging_mode = mode;
            save ();
        }

        public void set_wine_wayland (bool enabled) {
            _wine_wayland = enabled;
            save ();
        }

        public void set_large_address_aware (bool enabled) {
            _large_address_aware = enabled;
            save ();
        }

        public Gee.HashMap<string, string> get_runtime_env_vars () {
            var copy = new Gee.HashMap<string, string> ();
            foreach (var entry in runtime_env_vars.entries) {
                copy[entry.key] = entry.value;
            }
            return copy;
        }

        public void set_runtime_env_vars (Gee.HashMap<string, string> values) {
            runtime_env_vars.clear ();
            foreach (var entry in values.entries) {
                runtime_env_vars[entry.key] = entry.value;
            }
            save ();
        }

        public static bool resolve_wine_wayland (bool? prefix_override) {
            if (prefix_override != null) return (bool) prefix_override;
            return instance ().wine_wayland;
        }

        public static bool resolve_large_address_aware (bool? prefix_override) {
            if (prefix_override != null) return (bool) prefix_override;
            return instance ().large_address_aware;
        }

        public string get_default_runner_id () {
            return runner_id;
        }

        public string get_default_runner_version () {
            return runner_version != "" ? runner_version : "latest";
        }

        public void set_default_runner (string id, string version) {
            runner_id = id;
            runner_version = version != "" ? version : "latest";
            save ();
        }

        public bool is_default_runner (string id, string version) {
            return runner_id == id && get_default_runner_version () == version;
        }

        public string get_tool_version (ToolKind kind, string tool_id) {
            switch (kind) {
                case ToolKind.COMPONENT:
                    return component_versions.has_key (tool_id) ? component_versions[tool_id] : "latest";
                default:
                    return get_default_runner_version ();
            }
        }

        public void set_tool_version (ToolKind kind, string tool_id, string version) {
            var ver = version != "" ? version : "latest";
            switch (kind) {
                case ToolKind.COMPONENT:
                    component_versions[tool_id] = ver;
                    save ();
                    break;
                case ToolKind.RUNNER:
                    set_default_runner (tool_id, ver);
                    break;
                default:
                    warning ("set_tool_version: unhandled kind for tool_id=%s", tool_id);
                    break;
            }
        }

        public bool is_tool_default (ToolKind kind, string tool_id, string version) {
            return get_tool_version (kind, tool_id) == version;
        }

        public bool is_component_enabled (string comp_id, bool spec_default = false) {
            if (component_enabled.has_key (comp_id)) {
                return component_enabled[comp_id];
            }
            if (defaults_spec.component_enabled.has_key (comp_id)) {
                return defaults_spec.component_enabled[comp_id];
            }
            return spec_default;
        }

        public bool default_component_enabled (string comp_id) {
            if (defaults_spec.component_enabled.has_key (comp_id)) {
                return defaults_spec.component_enabled[comp_id];
            }
            return false;
        }

        public void set_component_enabled (string comp_id, bool enabled) {
            component_enabled[comp_id] = enabled;
            save ();
        }

        public void reset_to_defaults () {
            runner_id = default_runner_id_for_env ();
            runner_version = default_runner_version_for_env ();
            _wine_wayland = defaults_spec.wine_wayland;
            _large_address_aware = defaults_spec.large_address_aware;

            component_versions.clear ();
            component_enabled.clear ();
            runtime_env_vars.clear ();
            foreach (var entry in defaults_spec.component_enabled.entries) {
                component_enabled[entry.key] = entry.value;
            }

            save ();
        }

        public static string resolve_version (string prefix_runner_id, string version) {
            if (version == "default" || version == "") {
                var inst = instance ();
                if (inst.runner_id == "" || inst.runner_id == prefix_runner_id) {
                    return inst.get_default_runner_version ();
                }
                return "latest";
            }
            return version;
        }

        private void load () {
            if (!FileUtils.test (file_path, FileTest.EXISTS)) {
                if (seed_missing_defaults (false, false, false, false)) {
                    save ();
                }
                return;
            }

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (file_path);
                var obj = parser.get_root ().get_object ();

                bool has_runner_id = false;
                bool has_runner_version = false;
                bool has_wine_wayland = false;
                bool has_large_address_aware = false;

                if (obj.has_member ("runner_id")) {
                    runner_id = obj.get_string_member ("runner_id");
                    has_runner_id = runner_id != "";
                }
                if (obj.has_member ("runner_version")) {
                    runner_version = obj.get_string_member ("runner_version");
                    has_runner_version = runner_version != "";
                }
                if (obj.has_member ("wine")) {
                    var wine_obj = obj.get_object_member ("wine");
                    has_wine_wayland = wine_obj.has_member ("wayland");
                }
                if (obj.has_member ("patches")) {
                    var patch_obj = obj.get_object_member ("patches");
                    has_large_address_aware = patch_obj.has_member ("large_address_aware");
                }
                load_updates (obj);
                load_logging (obj);
                load_wine (obj);
                load_patches (obj);
                load_components (obj);
                load_runtime (obj);

                if (seed_missing_defaults (
                    has_runner_id,
                    has_runner_version,
                    has_wine_wayland,
                    has_large_address_aware
                )) {
                    save ();
                }
            } catch (Error e) {
                warning ("Failed to load preferences: %s", e.message);
            }
        }

        private bool seed_missing_defaults (
            bool has_runner_id,
            bool has_runner_version,
            bool has_wine_wayland,
            bool has_large_address_aware
        ) {
            bool changed = false;

            var env_runner_id = default_runner_id_for_env ();
            var env_runner_version = default_runner_version_for_env ();

            if (!has_runner_id && env_runner_id != "") {
                runner_id = env_runner_id;
                changed = true;
            }
            if (!has_runner_version) {
                runner_version = env_runner_version;
                changed = true;
            }
            if (!has_wine_wayland) {
                _wine_wayland = defaults_spec.wine_wayland;
                changed = true;
            }
            if (!has_large_address_aware) {
                _large_address_aware = defaults_spec.large_address_aware;
                changed = true;
            }

            foreach (var entry in defaults_spec.component_enabled.entries) {
                if (!component_enabled.has_key (entry.key)) {
                    component_enabled[entry.key] = entry.value;
                    changed = true;
                }
            }

            return changed;
        }

        private string default_runner_id_for_env () {
            if (Utils.is_sandboxed () && defaults_spec.runner_id_sandbox != "") {
                return defaults_spec.runner_id_sandbox;
            }
            return defaults_spec.runner_id;
        }

        private string default_runner_version_for_env () {
            if (Utils.is_sandboxed () && defaults_spec.runner_id_sandbox != "") {
                return defaults_spec.runner_version_sandbox != "" ? defaults_spec.runner_version_sandbox : "latest";
            }
            return defaults_spec.runner_version != "" ? defaults_spec.runner_version : "latest";
        }

        private void load_updates (Json.Object obj) {
            if (!obj.has_member ("updates")) return;
            var upd = obj.get_object_member ("updates");
            if (upd.has_member ("lumoria"))
                _updates_lumoria = upd.get_boolean_member ("lumoria");
            if (upd.has_member ("runners"))
                _updates_runners = upd.get_boolean_member ("runners");
            if (upd.has_member ("components"))
                _updates_components = upd.get_boolean_member ("components");
        }

        private void load_logging (Json.Object obj) {
            if (!obj.has_member ("logging")) return;
            var log_obj = obj.get_object_member ("logging");
            if (log_obj.has_member ("mode"))
                _logging_mode = log_obj.get_string_member ("mode");
        }

        private void load_wine (Json.Object obj) {
            if (!obj.has_member ("wine")) return;
            var wine_obj = obj.get_object_member ("wine");
            if (wine_obj.has_member ("wayland"))
                _wine_wayland = wine_obj.get_boolean_member ("wayland");
        }

        private void load_components (Json.Object obj) {
            if (!obj.has_member ("components")) return;
            var comps = obj.get_object_member ("components");
            comps.foreach_member ((_, key, node) => {
                var entry = node.get_object ();
                if (entry.has_member ("version"))
                    component_versions[key] = entry.get_string_member ("version");
                if (entry.has_member ("enabled"))
                    component_enabled[key] = entry.get_boolean_member ("enabled");
            });
        }

        private void load_patches (Json.Object obj) {
            if (!obj.has_member ("patches")) return;
            var patches_obj = obj.get_object_member ("patches");
            if (patches_obj.has_member ("large_address_aware"))
                _large_address_aware = patches_obj.get_boolean_member ("large_address_aware");
        }

        private void load_runtime (Json.Object obj) {
            if (!obj.has_member ("runtime")) return;
            var runtime_obj = obj.get_object_member ("runtime");
            runtime_env_vars.clear ();
            if (runtime_obj.has_member ("env")) {
                var env_obj = runtime_obj.get_object_member ("env");
                env_obj.foreach_member ((_, key, node) => {
                    runtime_env_vars[key] = node.get_string ();
                });
            }
        }

        private void save () {
            if (_freeze_count > 0) {
                _dirty = true;
                return;
            }
            _dirty = false;
            try {
                ensure_dir (Path.get_dirname (file_path));
                var obj = new Json.Object ();

                obj.set_string_member ("runner_id", runner_id);
                obj.set_string_member ("runner_version", runner_version);

                var upd = new Json.Object ();
                upd.set_boolean_member ("lumoria", _updates_lumoria);
                upd.set_boolean_member ("runners", _updates_runners);
                upd.set_boolean_member ("components", _updates_components);
                obj.set_object_member ("updates", upd);

                var log_obj = new Json.Object ();
                log_obj.set_string_member ("mode", _logging_mode);
                obj.set_object_member ("logging", log_obj);

                var wine_obj = new Json.Object ();
                wine_obj.set_boolean_member ("wayland", _wine_wayland);
                obj.set_object_member ("wine", wine_obj);

                var patches_obj = new Json.Object ();
                patches_obj.set_boolean_member ("large_address_aware", _large_address_aware);
                obj.set_object_member ("patches", patches_obj);

                var runtime_obj = new Json.Object ();
                if (runtime_env_vars.size > 0) {
                    var env_obj = new Json.Object ();
                    foreach (var entry in runtime_env_vars.entries) {
                        env_obj.set_string_member (entry.key, entry.value);
                    }
                    runtime_obj.set_object_member ("env", env_obj);
                }
                obj.set_object_member ("runtime", runtime_obj);

                var all_comp_keys = new Gee.HashSet<string> ();
                foreach (var k in component_versions.keys) all_comp_keys.add (k);
                foreach (var k in component_enabled.keys) all_comp_keys.add (k);
                if (all_comp_keys.size > 0) {
                    var comps = new Json.Object ();
                    foreach (var key in all_comp_keys) {
                        var entry = new Json.Object ();
                        entry.set_string_member ("version",
                            component_versions.has_key (key) ? component_versions[key] : "latest");
                        entry.set_boolean_member ("enabled",
                            component_enabled.has_key (key) ? component_enabled[key] : false);
                        comps.set_object_member (key, entry);
                    }
                    obj.set_object_member ("components", comps);
                }

                var root = new Json.Node (Json.NodeType.OBJECT);
                root.set_object (obj);
                var gen = new Json.Generator ();
                gen.root = root;
                gen.pretty = true;
                gen.to_file (file_path);
            } catch (Error e) {
                warning ("Failed to save preferences: %s", e.message);
            }
        }
    }
}
