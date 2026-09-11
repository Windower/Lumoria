namespace Lumoria.Utils {

    public enum ToolKind {
        RUNNER,
        COMPONENT
    }

    public enum WineSyncMode {
        NTSYNC,
        FSYNC,
        ESYNC;

        public static WineSyncMode parse (string mode) {
            switch (mode.down ().strip ()) {
                case "fsync": return FSYNC;
                case "esync": return ESYNC;
                default: return NTSYNC;
            }
        }

        public unowned string id () {
            switch (this) {
                case FSYNC: return "fsync";
                case ESYNC: return "esync";
                default: return "ntsync";
            }
        }
    }

    public enum StartupView {
        HOME,
        LAST_PREFIX;

        public string to_key () {
            switch (this) {
                case HOME: return "home";
                default: return "last-prefix";
            }
        }

        public static StartupView from_key (string key) {
            switch (key) {
                case "home": return HOME;
                default: return LAST_PREFIX;
            }
        }
    }

    public class Preferences : Object {
        /*
         * Where each GObject property lives in preferences.json. Loading, saving and resetting walk
         * this table; the ParamSpec supplies the type and the built-in default, the defaults manifest
         * overrides some of those in seed_missing_defaults. Entries with reset = false survive a reset.
         */
        private struct Field {
            unowned string section;
            unowned string key;
            unowned string property;
            bool reset;
        }

        private const Field[] FIELDS = {
            { "", "runner_id", "runner-id", true },
            { "", "runner_version", "runner-version", true },
            { "", "experimental_features", "experimental-features", true },
            { "", "show_hidden_tool_versions", "show-hidden-tool-versions", true },
            { "", "session_manager", "session-manager", true },
            { "", "show_sidebar", "show-sidebar", true },
            { "", "close_after_launch", "close-after-launch", true },
            { "", "startup_view", "startup-view", true },
            { "updates", "lumoria", "updates-lumoria", false },
            { "updates", "resources", "updates-resources", false },
            { "updates", "runners", "updates-runners", false },
            { "updates", "components", "updates-components", false },
            { "updates", "manifests_ask", "updates-manifests-ask", false },
            { "updates", "manifests_auto", "updates-manifests-auto", false },
            { "updates", "skipped_revision", "updates-skipped-revision", false },
            { "updates", "last_checked", "updates-last-checked", false },
            { "logging", "keep_files", "keep-runtime-logs", true },
            { "wine", "wayland", "wine-wayland", true },
            { "wine", "sync_mode", "sync-mode", true },
            { "wine", "debug", "wine-debug", true },
            { "patches", "large_address_aware", "large-address-aware", true },
            { "input", "gamepad_nav", "gamepad-navigation", true },
            { "power", "screen_inhibitor", "screen-inhibitor", true },
            { "power", "feral_game_mode", "feral-game-mode", true },
        };

        /* Schema keys that are read and written by hand rather than through FIELDS. */
        private const string[] HANDLED_ELSEWHERE = {
            "$schema", "format_version", "show_hidden_runner_versions", "components", "patches",
            "runtime.env", "steam.userdata_dir", "steam.userdata_dir_portal",
        };

        private static Preferences? _instance = null;
        private string file_path;
        private int _batch_count = 0;
        private bool _dirty = false;
        private Utils.Debouncer persist;

        public signal void gamepad_navigation_changed (bool enabled);
        public signal void persist_failed (string message);
        public signal void reset ();

        public string runner_id { get; set; default = ""; }
        public string runner_version { get; set; default = Models.ToolVersionRef.WIRE_LATEST; }

        public bool updates_lumoria { get; set; default = true; }
        public bool updates_resources { get; set; default = true; }
        public bool updates_runners { get; set; default = true; }
        public bool updates_components { get; set; default = true; }
        public bool updates_manifests_ask { get; set; default = true; }
        public bool updates_manifests_auto { get; set; default = false; }
        public string updates_skipped_revision { get; set; default = ""; }
        public string updates_last_checked { get; set; default = ""; }
        public bool keep_runtime_logs { get; set; default = false; }
        public bool wine_wayland { get; set; default = false; }
        public string wine_debug { get; set; default = ""; }
        public bool large_address_aware { get; set; default = false; }
        public bool experimental_features { get; set; default = false; }
        public bool show_hidden_tool_versions { get; set; default = false; }
        public bool session_manager { get; set; default = true; }
        public bool show_sidebar { get; set; default = false; }
        public bool close_after_launch { get; set; default = false; }
        public bool gamepad_navigation { get; set; default = false; }
        public bool screen_inhibitor { get; set; default = true; }
        public bool feral_game_mode { get; set; default = false; }
        public StartupView startup_view { get; set; default = StartupView.LAST_PREFIX; }
        public string load_error { get; private set; default = ""; }

        private string _sync_mode = "ntsync";
        public string sync_mode {
            get { return _sync_mode; }
            set { _sync_mode = WineSyncMode.parse (value).id (); }
        }
        private string _steam_userdata_dir = "";
        private Models.PortalPathRef? _steam_userdata_dir_portal = null;

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
        private Models.DefaultsManifest defaults_manifest;

        private bool _loading = false;

        private Preferences () {
            file_path = preferences_path ();
            persist = new Utils.Debouncer (0, write_prefs);
            component_versions = new Gee.HashMap<string, string> ();
            component_enabled = new Gee.HashMap<string, bool?> ();
            runtime_env_vars = new Gee.HashMap<string, string> ();
            defaults_manifest = Models.DefaultsManifest.load ();
            notify.connect (on_pref_notify);
            check_schema_coverage ();
            load ();
        }

        private void on_pref_notify (ParamSpec p) {
            if (_loading) return;
            if (p.name == "gamepad-navigation") gamepad_navigation_changed (gamepad_navigation);
            save ();
        }

        public static Preferences instance () {
            if (_instance == null) {
                _instance = new Preferences ();
            }
            return _instance;
        }

        /* Pre-format-1 preference files stored a logging "mode" instead of "keep_files". */
        public static bool logging_mode_keeps_files (string mode) {
            return mode != "off" && mode != "memory" && mode != "dont_keep";
        }

        public void reload_defaults () {
            defaults_manifest = Models.DefaultsManifest.load ();
            try {
                if (seed_missing_defaults (read_saved ())) save (true);
            } catch (Error e) {
                warning ("Failed to reload preference defaults: %s", e.message);
            }
        }

        public class PowerSnapshot : Object {
            public bool screen_inhibitor { get; private set; default = true; }
            public bool feral_game_mode { get; private set; default = false; }

            public static PowerSnapshot load () {
                var snap = new PowerSnapshot ();
                var path = preferences_path ();
                if (!FileUtils.test (path, FileTest.EXISTS)) return snap;
                try {
                    var obj = Models.parse_file_object (path);
                    var power = Models.json_object (obj, "power");
                    if (power == null) return snap;
                    snap.screen_inhibitor = Models.json_bool (power, "screen_inhibitor", snap.screen_inhibitor);
                    snap.feral_game_mode = Models.json_bool (power, "feral_game_mode", snap.feral_game_mode);
                } catch (Error e) {
                    warning ("Failed to load power preferences: %s", e.message);
                }
                return snap;
            }
        }

        private void begin_batch () { _batch_count++; }

        private void end_batch () {
            if (_batch_count > 0) _batch_count--;
            if (_batch_count == 0 && _dirty) save (true);
        }

        public void remember_manifest_consent (bool update, bool dont_ask, string revision) {
            begin_batch ();
            if (dont_ask) {
                updates_manifests_ask = false;
                updates_manifests_auto = update;
            }
            updates_skipped_revision = update ? "" : revision;
            end_batch ();
        }

        public void mark_manifests_checked () {
            updates_last_checked = new DateTime.now_local ().format ("%Y-%m-%d %H:%M");
        }

        public Gee.HashMap<string, string> get_runtime_env_vars () {
            var copy = new Gee.HashMap<string, string> ();
            copy.set_all (runtime_env_vars);
            return copy;
        }

        public void set_runtime_env_vars (Gee.HashMap<string, string> values) {
            runtime_env_vars.clear ();
            runtime_env_vars.set_all (values);
            save ();
        }

        public static bool resolve_wine_wayland (bool? prefix_override) {
            if (prefix_override != null) return (bool) prefix_override;
            return instance ().wine_wayland;
        }

        public static WineSyncMode resolve_sync_mode (string prefix_value) {
            if (prefix_value != "") return WineSyncMode.parse (prefix_value);
            return WineSyncMode.parse (instance ().sync_mode);
        }

        public static string resolve_wine_debug (string prefix_value) {
            if (prefix_value != "") return prefix_value;
            return instance ().wine_debug;
        }

        public string get_default_runner_version () {
            return runner_version != "" ? runner_version : Models.ToolVersionRef.LATEST.id ();
        }

        public void set_default_runner (string id, string version) {
            begin_batch ();
            runner_id = id;
            runner_version = version != "" ? version : Models.ToolVersionRef.LATEST.id ();
            end_batch ();
        }

        public bool is_default_runner (string id, string version) {
            return runner_id == id && get_default_runner_version () == version;
        }

        public string get_tool_version (ToolKind kind, string tool_id) {
            if (kind == ToolKind.COMPONENT) {
                return component_versions.has_key (tool_id)
                    ? component_versions[tool_id]
                    : Models.ToolVersionRef.LATEST.id ();
            }
            return get_default_runner_version ();
        }

        public void set_tool_version (ToolKind kind, string tool_id, string version) {
            var ver = version != "" ? version : Models.ToolVersionRef.LATEST.id ();
            if (kind == ToolKind.COMPONENT) {
                component_versions[tool_id] = ver;
                save ();
                return;
            }
            set_default_runner (tool_id, ver);
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

        public void set_component_enabled (string comp_id, bool enabled) {
            component_enabled[comp_id] = enabled;
            save ();
        }

        public void reset_to_defaults () {
            begin_batch ();
            foreach (var field in FIELDS) {
                if (!field.reset) continue;
                var pspec = get_class ().find_property (field.property);
                set_property (field.property, pspec.get_default_value ());
            }
            component_versions.clear ();
            component_enabled.clear ();
            runtime_env_vars.clear ();
            seed_missing_defaults (null);
            end_batch ();
            reset ();
        }

        public static string effective_runner_id (string prefix_runner_id) {
            return prefix_runner_id != "" ? prefix_runner_id : instance ().runner_id;
        }

        public static string resolve_version (string prefix_runner_id, string version) {
            if (Models.ToolVersionRef.is_inherit (version)) {
                var inst = instance ();
                if (inst.runner_id == "" || inst.runner_id == prefix_runner_id) {
                    return inst.get_default_runner_version ();
                }
                return Models.ToolVersionRef.LATEST.id ();
            }
            return version;
        }

        private Json.Object? read_saved () throws Error {
            return Utils.read_validated_json (file_path, "preferences");
        }

        private void load () {
            Json.Object? saved = null;
            try {
                saved = read_saved ();
            } catch (Error e) {
                warning ("Failed to load preferences: %s", e.message);
                Utils.quarantine_broken_file (file_path);
                _loading = true;
                load_error = _("Could not load preferences; using defaults.");
                seed_missing_defaults (null);
                _loading = false;
                flush_persist ();
                return;
            }
            if (saved == null) {
                begin_batch ();
                var seeded = seed_missing_defaults (null);
                if (!seeded) _dirty = false;
                end_batch ();
                return;
            }
            _loading = true;
            apply_saved (saved);
            var seeded = seed_missing_defaults (saved);
            _loading = false;
            if (seeded) save (true);
        }

        private void apply_saved (Json.Object obj) {
            foreach (var field in FIELDS) {
                var section = field.section == "" ? obj : Models.json_object (obj, field.section);
                if (!Models.json_has (section, field.key)) continue;
                set_property (field.property, value_from_json (field.property, section.get_member (field.key)));
            }
            if (!obj.has_member ("show_hidden_tool_versions")) {
                show_hidden_tool_versions = Models.json_bool (obj, "show_hidden_runner_versions", show_hidden_tool_versions);
            }
            load_components (obj);
            load_runtime (obj);
            load_steam (obj);
        }

        private Value value_from_json (string property, Json.Node node) {
            var type = get_class ().find_property (property).value_type;
            var value = Value (type);
            if (type == typeof (bool)) {
                value.set_boolean (node.get_boolean ());
            } else if (type == typeof (string)) {
                value.set_string (node.get_string ());
            } else {
                var enum_value = ((EnumClass) type.class_ref ()).get_value_by_nick (node.get_string ());
                value.set_enum (enum_value != null ? enum_value.value : get_class ().find_property (property).get_default_value ().get_enum ());
            }
            return value;
        }

        private Json.Node value_to_json (Value value) {
            var node = new Json.Node (Json.NodeType.VALUE);
            if (value.holds (typeof (bool))) {
                node.set_boolean (value.get_boolean ());
            } else if (value.holds (typeof (string))) {
                node.set_string (value.get_string () ?? "");
            } else {
                node.set_string (((EnumClass) value.type ().class_ref ()).get_value (value.get_enum ()).value_nick);
            }
            return node;
        }

        /* The manifest supplies defaults the ParamSpecs cannot know; a key absent from disk takes them. */
        private bool seed_missing_defaults (Json.Object? saved) {
            var defaults = resolved_defaults ();
            var changed = false;

            if (Models.json_string (saved, "runner_id") == "" && defaults.runner_id != "") {
                runner_id = defaults.runner_id;
                changed = true;
            }
            if (Models.json_string (saved, "runner_version") == "") {
                runner_version = defaults.runner_version;
                changed = true;
            }
            if (missing (saved, "wine", "wayland")) {
                wine_wayland = EnvironmentInfo.is_wayland ();
                changed = true;
            }
            if (missing (saved, "wine", "sync_mode")) {
                sync_mode = defaults.sync_mode;
                changed = true;
            }
            if (missing (saved, "wine", "debug")) {
                wine_debug = defaults.wine_debug;
                changed = true;
            }
            if (missing (saved, "patches", Models.InstallerPatch.SETTING_LARGE_ADDRESS_AWARE)) {
                large_address_aware = defaults.large_address_aware;
                changed = true;
            }
            if (missing (saved, "logging", "keep_files")) {
                keep_runtime_logs = defaults.keep_runtime_logs;
                changed = true;
            }
            if (missing (saved, "", "startup_view")) {
                startup_view = StartupView.from_key (defaults_manifest.startup_view);
                changed = true;
            }

            foreach (var entry in defaults.component_enabled.entries) {
                if (component_enabled.has_key (entry.key)) continue;
                component_enabled[entry.key] = entry.value;
                changed = true;
            }
            return changed;
        }

        private static bool missing (Json.Object? saved, string section, string key) {
            return !Models.json_has (section == "" ? saved : Models.json_object (saved, section), key);
        }

        private void check_schema_coverage () {
            var covered = new Gee.HashSet<string> ();
            covered.add_all_array (HANDLED_ELSEWHERE);
            foreach (var field in FIELDS) {
                covered.add (field.section == "" ? field.key : field.section + "." + field.key);
            }
            try {
                var bytes = GLib.resources_lookup_data (Config.RESOURCE_BASE + "/schemas/preferences.json", 0);
                var schema = Models.parse_data_object (((string) bytes.get_data ()).substring (0, (long) bytes.get_size ()));
                var properties = Models.json_object (schema, "properties");
                properties.foreach_member ((_, key, node) => {
                    var nested = Models.json_object (node.get_object (), "properties");
                    if (nested == null) {
                        if (!covered.contains (key)) critical ("Preference '%s' has no FIELDS row", key);
                        return;
                    }
                    foreach (var sub in nested.get_members ()) {
                        var path = key + "." + sub;
                        if (!covered.contains (path)) critical ("Preference '%s' has no FIELDS row", path);
                    }
                });
            } catch (Error e) {
                critical ("Failed to read the preferences schema: %s", e.message);
            }
        }

        private Models.DefaultRuntimeSettings resolved_defaults () {
            return defaults_manifest.for_env (Utils.EnvironmentInfo.is_sandboxed ());
        }

        private void load_components (Json.Object obj) {
            var comps = Models.json_object (obj, "components");
            if (comps == null) return;
            comps.foreach_member ((_, key, node) => {
                var entry = node.get_object ();
                if (entry.has_member ("version"))
                    component_versions[key] = entry.get_string_member ("version");
                if (entry.has_member ("enabled"))
                    component_enabled[key] = entry.get_boolean_member ("enabled");
            });
        }

        private void load_runtime (Json.Object obj) {
            var runtime_obj = Models.json_object (obj, "runtime");
            if (runtime_obj == null) return;
            runtime_env_vars.clear ();
            runtime_env_vars.set_all (Models.json_string_map (runtime_obj, "env"));
        }

        private void load_steam (Json.Object obj) {
            var steam_obj = Models.json_object (obj, "steam");
            if (steam_obj == null) return;
            _steam_userdata_dir = Models.json_string (steam_obj, "userdata_dir", _steam_userdata_dir);
            try {
                _steam_userdata_dir_portal = Models.json_parse_member<Models.PortalPathRef> (
                    steam_obj, "userdata_dir_portal", Models.PortalPathRef.from_json
                );
            } catch (Error e) {
                warning ("Invalid Steam portal path: %s", e.message);
            }
        }

        public Json.Object snapshot () {
            var obj = new Json.Object ();
            obj.set_int_member ("format_version", Config.CONFIG_FORMAT_VERSION);

            foreach (var field in FIELDS) {
                var target = obj;
                if (field.section != "") {
                    target = Models.json_object (obj, field.section);
                    if (target == null) {
                        target = new Json.Object ();
                        obj.set_object_member (field.section, target);
                    }
                }
                var value = Value (get_class ().find_property (field.property).value_type);
                get_property (field.property, ref value);
                target.set_member (field.key, value_to_json (value));
            }

            var runtime_obj = new Json.Object ();
            runtime_obj.set_object_member ("env", Models.json_string_map_object (runtime_env_vars));
            obj.set_object_member ("runtime", runtime_obj);

            var all_comp_keys = new Gee.HashSet<string> ();
            foreach (var k in component_versions.keys) all_comp_keys.add (k);
            foreach (var k in component_enabled.keys) all_comp_keys.add (k);
            var comps = new Json.Object ();
            foreach (var key in all_comp_keys) {
                var entry = new Json.Object ();
                entry.set_string_member ("version",
                    component_versions.has_key (key)
                        ? component_versions[key]
                        : Models.ToolVersionRef.LATEST.id ());
                entry.set_boolean_member ("enabled", is_component_enabled (key));
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

        private void save (bool immediate = false) {
            if (_batch_count > 0) {
                _dirty = true;
                return;
            }
            if (immediate) {
                flush_persist ();
                return;
            }
            persist.schedule ();
        }

        public void flush_persist () {
            persist.cancel ();
            if (_batch_count > 0) {
                _dirty = true;
                return;
            }
            write_prefs ();
        }

        private void write_prefs () {
            _dirty = false;
            try {
                write_validated_json (file_path, "preferences", snapshot ());
            } catch (Error e) {
                warning ("Failed to save preferences: %s", e.message);
                persist_failed (user_error (e));
            }
        }

    }
}
