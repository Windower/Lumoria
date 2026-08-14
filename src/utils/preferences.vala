namespace Lumoria.Utils {

    public enum ToolKind {
        RUNNER,
        COMPONENT
    }

    public class Preferences : Object {
        private static Preferences? _instance = null;
        private string file_path;
        private int _freeze_count = 0;
        private bool _dirty = false;

        public signal void gamepad_navigation_changed (bool enabled);
        public signal void session_manager_changed (bool enabled);

        public string runner_id { get; private set; default = ""; }
        public string runner_version { get; private set; default = "latest"; }

        private bool _updates_lumoria = true;
        private bool _updates_runners = true;
        private bool _updates_components = true;
        private bool _keep_runtime_logs = false;
        private bool _wine_wayland = false;
        private string _sync_mode = "ntsync";
        private string _wine_debug = "";
        private bool _large_address_aware = false;
        private bool _experimental_features = false;
        private bool _show_hidden_runner_versions = false;
        private bool _session_manager = true;
        private bool _gamepad_navigation = false;
        private bool _screen_inhibitor = true;
        private bool _feral_game_mode = false;
        private string _steam_userdata_dir = "";
        private Models.PortalPathRef? _steam_userdata_dir_portal = null;

        public bool updates_lumoria { get { return _updates_lumoria; } }
        public bool updates_runners { get { return _updates_runners; } }
        public bool updates_components { get { return _updates_components; } }
        public bool keep_runtime_logs { get { return _keep_runtime_logs; } }
        public bool wine_wayland { get { return _wine_wayland; } }
        public string sync_mode { get { return _sync_mode; } }
        public string wine_debug { get { return _wine_debug; } }
        public bool large_address_aware { get { return _large_address_aware; } }
        public bool experimental_features { get { return _experimental_features; } }
        public bool show_hidden_runner_versions { get { return _show_hidden_runner_versions; } }
        public bool session_manager { get { return _session_manager; } }
        public bool gamepad_navigation { get { return _gamepad_navigation; } }
        public bool screen_inhibitor { get { return _screen_inhibitor; } }
        public bool feral_game_mode { get { return _feral_game_mode; } }

        public string resolved_steam_userdata_dir () {
            return Utils.resolve_user_path (_steam_userdata_dir, _steam_userdata_dir_portal);
        }

        public void set_steam_userdata_dir (string path, Models.PortalPathRef? portal_ref) {
            _steam_userdata_dir = path;
            _steam_userdata_dir_portal = portal_ref;
            save ();
        }

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

        public static bool saved_screen_inhibitor () {
            return saved_power_boolean ("screen_inhibitor", true);
        }

        public static bool saved_feral_game_mode () {
            return saved_power_boolean ("feral_game_mode", false);
        }

        private static bool saved_power_boolean (string member, bool fallback) {
            var file_path = Path.build_filename (config_dir (), "preferences.json");
            if (!FileUtils.test (file_path, FileTest.EXISTS)) return fallback;

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (file_path);
                var obj = parser.get_root ().get_object ();
                if (!obj.has_member ("power")) return fallback;

                var power_obj = obj.get_object_member ("power");
                if (!power_obj.has_member (member)) return fallback;

                return power_obj.get_boolean_member (member);
            } catch (Error e) {
                warning ("Failed to load power preferences: %s", e.message);
                return fallback;
            }
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

        public void set_keep_runtime_logs (bool enabled) {
            _keep_runtime_logs = enabled;
            save ();
        }

        public void set_wine_wayland (bool enabled) {
            _wine_wayland = enabled;
            save ();
        }

        public void set_sync_mode (string mode) {
            _sync_mode = mode;
            save ();
        }

        public void set_wine_debug (string debug) {
            _wine_debug = debug;
            save ();
        }

        public void set_large_address_aware (bool enabled) {
            _large_address_aware = enabled;
            save ();
        }

        public void set_experimental_features (bool enabled) {
            _experimental_features = enabled;
            save ();
        }

        public void set_show_hidden_runner_versions (bool enabled) {
            if (_show_hidden_runner_versions == enabled) return;
            _show_hidden_runner_versions = enabled;
            save ();
        }

        public void set_session_manager (bool enabled) {
            if (_session_manager == enabled) return;
            _session_manager = enabled;
            save ();
            session_manager_changed (enabled);
        }

        public void set_gamepad_navigation (bool enabled) {
            if (_gamepad_navigation == enabled) return;
            _gamepad_navigation = enabled;
            save ();
            gamepad_navigation_changed (enabled);
        }

        public void set_screen_inhibitor (bool enabled) {
            if (_screen_inhibitor == enabled) return;
            _screen_inhibitor = enabled;
            save ();
        }

        public void set_feral_game_mode (bool enabled) {
            if (_feral_game_mode == enabled) return;
            _feral_game_mode = enabled;
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

        public static string resolve_sync_mode (string prefix_value) {
            if (prefix_value != "") return prefix_value;
            return instance ().sync_mode;
        }

        public static string resolve_wine_debug (string prefix_value) {
            if (prefix_value != "") return prefix_value;
            return instance ().wine_debug;
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
            var defaults = resolved_defaults ();
            if (defaults.component_enabled.has_key (comp_id)) {
                return defaults.component_enabled[comp_id];
            }
            return spec_default;
        }

        public bool default_component_enabled (string comp_id) {
            var defaults = resolved_defaults ();
            if (defaults.component_enabled.has_key (comp_id)) {
                return defaults.component_enabled[comp_id];
            }
            return false;
        }

        public void set_component_enabled (string comp_id, bool enabled) {
            component_enabled[comp_id] = enabled;
            save ();
        }

        public void reset_to_defaults () {
            var defaults = resolved_defaults ();
            runner_id = defaults.runner_id;
            runner_version = defaults.runner_version;
            _wine_wayland = default_wine_wayland ();
            _sync_mode = defaults.sync_mode;
            _wine_debug = defaults.wine_debug;
            _large_address_aware = defaults.large_address_aware;
            _keep_runtime_logs = defaults.keep_runtime_logs;
            _experimental_features = false;
            _show_hidden_runner_versions = false;
            _session_manager = true;
            _gamepad_navigation = false;
            _screen_inhibitor = true;
            _feral_game_mode = false;

            component_versions.clear ();
            component_enabled.clear ();
            runtime_env_vars.clear ();
            foreach (var entry in defaults.component_enabled.entries) {
                component_enabled[entry.key] = entry.value;
            }

            save ();
            session_manager_changed (false);
            gamepad_navigation_changed (false);
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
                if (seed_missing_defaults (false, false, false, false, false, false, false)) {
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
                bool has_sync_mode = false;
                bool has_wine_debug = false;
                bool has_large_address_aware = false;
                bool has_keep_runtime_logs = false;

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
                    has_sync_mode = wine_obj.has_member ("sync_mode");
                    has_wine_debug = wine_obj.has_member ("debug");
                }
                if (obj.has_member ("patches")) {
                    var patch_obj = obj.get_object_member ("patches");
                    has_large_address_aware = patch_obj.has_member ("large_address_aware");
                }
                if (obj.has_member ("logging")) {
                    var logging_obj = obj.get_object_member ("logging");
                    has_keep_runtime_logs = logging_obj.has_member ("keep_files")
                        || logging_obj.has_member ("mode");
                }
                if (obj.has_member ("experimental_features"))
                    _experimental_features = obj.get_boolean_member ("experimental_features");
                if (obj.has_member ("show_hidden_runner_versions"))
                    _show_hidden_runner_versions = obj.get_boolean_member ("show_hidden_runner_versions");
                if (obj.has_member ("session_manager"))
                    _session_manager = obj.get_boolean_member ("session_manager");

                load_updates (obj);
                load_logging (obj);
                load_wine (obj);
                load_patches (obj);
                load_input (obj);
                load_power (obj);
                load_components (obj);
                load_runtime (obj);
                load_steam (obj);

                if (seed_missing_defaults (
                    has_runner_id,
                    has_runner_version,
                    has_wine_wayland,
                    has_sync_mode,
                    has_wine_debug,
                    has_large_address_aware,
                    has_keep_runtime_logs
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
            bool has_sync_mode,
            bool has_wine_debug,
            bool has_large_address_aware,
            bool has_keep_runtime_logs
        ) {
            bool changed = false;
            var defaults = resolved_defaults ();

            if (!has_runner_id && defaults.runner_id != "") {
                runner_id = defaults.runner_id;
                changed = true;
            }
            if (!has_runner_version) {
                runner_version = defaults.runner_version;
                changed = true;
            }
            if (!has_wine_wayland) {
                _wine_wayland = default_wine_wayland ();
                changed = true;
            }
            if (!has_sync_mode) {
                _sync_mode = defaults.sync_mode;
                changed = true;
            }
            if (!has_wine_debug) {
                _wine_debug = defaults.wine_debug;
                changed = true;
            }
            if (!has_large_address_aware) {
                _large_address_aware = defaults.large_address_aware;
                changed = true;
            }
            if (!has_keep_runtime_logs) {
                _keep_runtime_logs = defaults.keep_runtime_logs;
                changed = true;
            }

            foreach (var entry in defaults.component_enabled.entries) {
                if (!component_enabled.has_key (entry.key)) {
                    component_enabled[entry.key] = entry.value;
                    changed = true;
                }
            }

            return changed;
        }

        private Models.DefaultRuntimeSettings resolved_defaults () {
            return defaults_spec.resolve_for_env (Utils.is_sandboxed ());
        }

        private bool default_wine_wayland () {
            return EnvironmentInfo.is_wayland ();
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
            if (log_obj.has_member ("keep_files")) {
                _keep_runtime_logs = log_obj.get_boolean_member ("keep_files");
                return;
            }
            if (log_obj.has_member ("mode")) {
                _keep_runtime_logs = logging_mode_keeps_files (log_obj.get_string_member ("mode"));
            }
        }

        private void load_wine (Json.Object obj) {
            if (!obj.has_member ("wine")) return;
            var wine_obj = obj.get_object_member ("wine");
            if (wine_obj.has_member ("wayland"))
                _wine_wayland = wine_obj.get_boolean_member ("wayland");
            if (wine_obj.has_member ("sync_mode"))
                _sync_mode = wine_obj.get_string_member ("sync_mode");
            if (wine_obj.has_member ("debug"))
                _wine_debug = wine_obj.get_string_member ("debug");
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

        private void load_input (Json.Object obj) {
            if (!obj.has_member ("input")) return;
            var input_obj = obj.get_object_member ("input");
            if (input_obj.has_member ("gamepad_nav"))
                _gamepad_navigation = input_obj.get_boolean_member ("gamepad_nav");
        }

        private void load_power (Json.Object obj) {
            if (!obj.has_member ("power")) return;
            var power_obj = obj.get_object_member ("power");
            if (power_obj.has_member ("screen_inhibitor"))
                _screen_inhibitor = power_obj.get_boolean_member ("screen_inhibitor");
            if (power_obj.has_member ("feral_game_mode"))
                _feral_game_mode = power_obj.get_boolean_member ("feral_game_mode");
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

        private void load_steam (Json.Object obj) {
            if (!obj.has_member ("steam")) return;
            var steam_obj = obj.get_object_member ("steam");
            if (steam_obj.has_member ("userdata_dir"))
                _steam_userdata_dir = steam_obj.get_string_member ("userdata_dir");
            if (steam_obj.has_member ("userdata_dir_portal"))
                _steam_userdata_dir_portal = Models.PortalPathRef.from_json (
                    steam_obj.get_object_member ("userdata_dir_portal"));
        }

        public Json.Object snapshot () {
            var obj = new Json.Object ();

            obj.set_string_member ("runner_id", runner_id);
            obj.set_string_member ("runner_version", runner_version);
            obj.set_boolean_member ("experimental_features", _experimental_features);
            obj.set_boolean_member ("show_hidden_runner_versions", _show_hidden_runner_versions);
            obj.set_boolean_member ("session_manager", _session_manager);

            var upd = new Json.Object ();
            upd.set_boolean_member ("lumoria", _updates_lumoria);
            upd.set_boolean_member ("runners", _updates_runners);
            upd.set_boolean_member ("components", _updates_components);
            obj.set_object_member ("updates", upd);

            var log_obj = new Json.Object ();
            log_obj.set_boolean_member ("keep_files", _keep_runtime_logs);
            obj.set_object_member ("logging", log_obj);

            var wine_obj = new Json.Object ();
            wine_obj.set_boolean_member ("wayland", _wine_wayland);
            wine_obj.set_string_member ("sync_mode", _sync_mode);
            wine_obj.set_string_member ("debug", _wine_debug);
            obj.set_object_member ("wine", wine_obj);

            var patches_obj = new Json.Object ();
            patches_obj.set_boolean_member ("large_address_aware", _large_address_aware);
            obj.set_object_member ("patches", patches_obj);

            var input_obj = new Json.Object ();
            input_obj.set_boolean_member ("gamepad_nav", _gamepad_navigation);
            obj.set_object_member ("input", input_obj);

            var power_obj = new Json.Object ();
            power_obj.set_boolean_member ("screen_inhibitor", _screen_inhibitor);
            power_obj.set_boolean_member ("feral_game_mode", _feral_game_mode);
            obj.set_object_member ("power", power_obj);

            var runtime_obj = new Json.Object ();
            var env_obj = new Json.Object ();
            foreach (var entry in runtime_env_vars.entries) {
                env_obj.set_string_member (entry.key, entry.value);
            }
            runtime_obj.set_object_member ("env", env_obj);
            obj.set_object_member ("runtime", runtime_obj);

            var all_comp_keys = new Gee.HashSet<string> ();
            foreach (var k in component_versions.keys) all_comp_keys.add (k);
            foreach (var k in component_enabled.keys) all_comp_keys.add (k);
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

            var steam_obj = new Json.Object ();
            steam_obj.set_string_member ("userdata_dir", _steam_userdata_dir);
            if (_steam_userdata_dir_portal != null && !_steam_userdata_dir_portal.is_empty ())
                steam_obj.set_object_member ("userdata_dir_portal", _steam_userdata_dir_portal.to_json ());
            obj.set_object_member ("steam", steam_obj);

            return obj;
        }

        private void save () {
            if (_freeze_count > 0) {
                _dirty = true;
                return;
            }
            _dirty = false;
            try {
                ensure_dir (Path.get_dirname (file_path));
                var root = new Json.Node (Json.NodeType.OBJECT);
                root.set_object (snapshot ());
                var gen = new Json.Generator ();
                gen.root = root;
                gen.pretty = true;
                gen.to_file (file_path);
            } catch (Error e) {
                warning ("Failed to save preferences: %s", e.message);
            }
        }

        private static bool logging_mode_keeps_files (string value) {
            switch (value) {
                case "off":
                case "memory":
                case "dont_keep":
                    return false;
                default:
                    return true;
            }
        }
    }
}
