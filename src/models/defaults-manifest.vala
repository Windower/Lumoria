namespace Lumoria.Models {

    /* One "runtime" block of defaults.json. An environment block starts from the default block and overrides fields it names. */
    public class DefaultRuntimeSettings : Object {
        public string runner_id { get; set; default = ""; }
        public string runner_version { get; set; default = ToolVersionRef.WIRE_LATEST; }
        public bool wine_wayland { get; set; default = false; }
        public string sync_mode { get; set; default = "ntsync"; }
        public string wine_debug { get; set; default = ""; }
        public bool large_address_aware { get; set; default = false; }
        public bool keep_runtime_logs { get; set; default = true; }
        public Gee.HashMap<string, bool> component_enabled {
            get; owned set; default = new Gee.HashMap<string, bool> ();
        }

        public static DefaultRuntimeSettings parse (Json.Object? obj, DefaultRuntimeSettings? inherited = null) {
            var s = new DefaultRuntimeSettings ();
            if (inherited != null) {
                s.runner_id = inherited.runner_id;
                s.runner_version = inherited.runner_version;
                s.wine_wayland = inherited.wine_wayland;
                s.sync_mode = inherited.sync_mode;
                s.wine_debug = inherited.wine_debug;
                s.large_address_aware = inherited.large_address_aware;
                s.keep_runtime_logs = inherited.keep_runtime_logs;
                s.component_enabled.set_all (inherited.component_enabled);
            }
            if (obj == null) return s;

            var runner = json_object (obj, "runner");
            if (runner != null) {
                s.runner_id = json_string (runner, "id", s.runner_id);
                s.runner_version = json_string (runner, "version", s.runner_version);
                if (s.runner_version == "") s.runner_version = ToolVersionRef.WIRE_LATEST;
            }
            var wine = json_object (obj, "wine");
            if (wine != null) {
                s.wine_wayland = json_bool (wine, "wayland", s.wine_wayland);
                s.sync_mode = json_string (wine, "sync_mode", s.sync_mode);
                s.wine_debug = json_string (wine, "debug", s.wine_debug);
            }
            var patches = json_object (obj, "patches");
            if (patches != null) {
                s.large_address_aware = json_bool (patches, InstallerPatch.SETTING_LARGE_ADDRESS_AWARE, s.large_address_aware);
            }
            var logging = json_object (obj, "logging");
            if (logging != null) {
                if (logging.has_member ("keep_files")) {
                    s.keep_runtime_logs = logging.get_boolean_member ("keep_files");
                } else if (logging.has_member ("mode")) {
                    s.keep_runtime_logs = Utils.Preferences.logging_mode_keeps_files (logging.get_string_member ("mode"));
                }
            }
            var components = json_object (obj, "components");
            if (components != null) {
                components.foreach_member ((_, id, node) => {
                    var enabled = json_bool_nullable (node.get_object (), "enabled");
                    if (enabled != null) s.component_enabled[id] = (bool) enabled;
                });
            }
            return s;
        }
    }

    public class DefaultsManifest : Object {
        public string startup_view { get; set; default = "last-prefix"; }
        public DefaultRuntimeSettings host { get; set; default = new DefaultRuntimeSettings (); }
        public DefaultRuntimeSettings sandbox { get; set; default = new DefaultRuntimeSettings (); }

        public static DefaultsManifest from_json (Json.Object obj) throws Error {
            var spec = new DefaultsManifest ();
            spec.startup_view = json_string (obj, "startup_view", spec.startup_view);
            spec.host = DefaultRuntimeSettings.parse (json_object (obj, "default"));
            spec.sandbox = DefaultRuntimeSettings.parse (
                json_object (json_object (obj, "environments"), "sandbox"), spec.host
            );
            return spec;
        }

        public static DefaultsManifest load () {
            try {
                return from_json (ManifestStore.load_object ("defaults.json"));
            } catch (Error e) {
                warning ("Failed to load defaults manifest: %s", e.message);
                return new DefaultsManifest ();
            }
        }

        public DefaultRuntimeSettings for_env (bool sandboxed) {
            return sandboxed ? sandbox : host;
        }
    }
}
