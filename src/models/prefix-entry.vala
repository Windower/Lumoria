namespace Lumoria.Models {

    public class RuntimeComponentOverride : Object {
        public const string KEY_ENABLED = "enabled";

        public bool? enabled = null;
        public string version { get; set; default = ""; }
        public Gee.HashMap<string, string> system_env { get; owned set; default = new Gee.HashMap<string, string> (); }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            if (enabled != null) obj.set_boolean_member (KEY_ENABLED, (bool) enabled);
            if (version != "") obj.set_string_member ("version", version);
            if (system_env.size > 0) {
                var env_obj = new Json.Object ();
                foreach (var entry in system_env.entries) {
                    env_obj.set_string_member (entry.key, entry.value);
                }
                obj.set_object_member ("system_env", env_obj);
            }
            return obj;
        }

        public static RuntimeComponentOverride from_json (Json.Object obj) {
            var o = new RuntimeComponentOverride ();
            o.enabled = json_bool_nullable (obj, KEY_ENABLED);
            o.version = json_string (obj, "version");
            o.system_env = json_string_map (obj, "system_env");
            return o;
        }
    }

    public class PrefixEntry : BaseSpec {
        public string path { get; set; default = ""; }
        public string uri { get; set; default = ""; }
        public string runner_id { get; set; default = ""; }
        public string runner_version { get; set; default = "latest"; }
        public string launcher_id { get; set; default = ""; }
        public string launch_entrypoint_id { get; set; default = ""; }
        public string variant_id { get; set; default = ""; }
        public string wine_arch { get; set; default = ""; }
        public string wine_debug { get; set; default = ""; }
        public bool? wine_wayland = null;
        public bool? large_address_aware = null;
        public string sync_mode { get; set; default = ""; }
        public string prelaunch_script { get; set; default = ""; }
        public Gee.ArrayList<Entrypoint> custom_entrypoints {
            get; owned set; default = new Gee.ArrayList<Entrypoint> ();
        }
        public Gee.HashMap<string, string> runtime_env_vars {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
        public Gee.HashMap<string, RuntimeComponentOverride> runtime_component_overrides {
            get; owned set; default = new Gee.HashMap<string, RuntimeComponentOverride> ();
        }
        public Gee.HashMap<string, string> dynamic_launcher_desktop_ids {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
        public string resolved_path () {
            if (uri != "") {
                try {
                    var u = Uri.parse (uri, UriFlags.NONE);
                    if (u.get_scheme () == "file") {
                        var p = u.get_path ();
                        if (p != null && p != "") return p;
                    }
                } catch (UriError e) {
                    warning ("Failed to parse URI for prefix path: %s", e.message);
                }
            }
            return path;
        }

        public string display_name () {
            if (name != "") return name;
            var p = resolved_path ();
            return Path.get_basename (p != "" ? p : path);
        }

        public string runner_summary (Gee.ArrayList<RunnerSpec> runner_specs) {
            if (runner_id == "") return "No runner configured";
            var found = RunnerSpec.find_by_id (runner_specs, runner_id);
            string runner_label = found != null ? found.display_label () : runner_id;
            var vl = variant_label (runner_specs);
            if (vl != "" && vl != "default") return runner_label + " / " + vl;
            return runner_label;
        }

        public string variant_label (Gee.ArrayList<RunnerSpec> runner_specs) {
            if (variant_id == "" || runner_id == "") return "default";
            var spec = RunnerSpec.find_by_id (runner_specs, runner_id);
            if (spec != null) {
                foreach (var v in spec.variants) {
                    if (v.id == variant_id) return v.display_label ();
                }
            }
            return variant_id;
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            obj.set_string_member ("id", id);
            obj.set_string_member ("name", name);
            obj.set_string_member ("path", path);
            if (uri != "") obj.set_string_member ("uri", uri);
            obj.set_string_member ("runner_id", runner_id);
            obj.set_string_member ("runner_version", runner_version);
            if (launcher_id != "") obj.set_string_member ("launcher_id", launcher_id);
            if (launch_entrypoint_id != "") obj.set_string_member ("launch_entrypoint_id", launch_entrypoint_id);
            if (variant_id != "") obj.set_string_member ("variant_id", variant_id);
            if (wine_arch != "") obj.set_string_member ("wine_arch", wine_arch);
            if (wine_debug != "") obj.set_string_member ("wine_debug", wine_debug);
            if (wine_wayland != null) obj.set_boolean_member ("wine_wayland", (bool) wine_wayland);
            if (large_address_aware != null) obj.set_boolean_member ("large_address_aware", (bool) large_address_aware);
            if (sync_mode != "") obj.set_string_member ("sync_mode", sync_mode);
            if (prelaunch_script != "") obj.set_string_member ("prelaunch_script", prelaunch_script);
            if (custom_entrypoints.size > 0) {
                var ep_arr = new Json.Array ();
                foreach (var ep in custom_entrypoints) {
                    var ep_obj = new Json.Object ();
                    ep_obj.set_string_member ("id", ep.id);
                    ep_obj.set_string_member ("name", ep.name);
                    ep_obj.set_string_member ("exe", ep.exe);
                    if (ep.args.size > 0) {
                        var args_arr = new Json.Array ();
                        foreach (var arg in ep.args) args_arr.add_string_element (arg);
                        ep_obj.set_array_member ("args", args_arr);
                    }
                    if (ep.prelaunch_script != "") {
                        ep_obj.set_string_member ("prelaunch_script", ep.prelaunch_script);
                    }
                    ep_arr.add_object_element (ep_obj);
                }
                obj.set_array_member ("custom_entrypoints", ep_arr);
            }
            if (runtime_env_vars.size > 0) {
                var env_obj = new Json.Object ();
                foreach (var entry in runtime_env_vars.entries) {
                    env_obj.set_string_member (entry.key, entry.value);
                }
                obj.set_object_member ("runtime_env_vars", env_obj);
            }
            if (dynamic_launcher_desktop_ids.size > 0) {
                var shortcuts_obj = new Json.Object ();
                foreach (var entry in dynamic_launcher_desktop_ids.entries) {
                    shortcuts_obj.set_string_member (entry.key, entry.value);
                }
                obj.set_object_member ("dynamic_launcher_desktop_ids", shortcuts_obj);
            }

            if (runtime_component_overrides.size > 0) {
                var overrides = new Json.Object ();
                foreach (var entry in runtime_component_overrides.entries) {
                    overrides.set_object_member (entry.key, entry.value.to_json ());
                }
                obj.set_object_member ("runtime_component_overrides", overrides);
            }
            return obj;
        }

        public static PrefixEntry from_json (Json.Object obj) {
            var e = new PrefixEntry ();
            e.parse_base (obj);
            e.path = json_string (obj, "path");
            e.uri = json_string (obj, "uri");
            e.runner_id = json_string (obj, "runner_id");
            e.runner_version = json_string (obj, "runner_version", "latest");
            e.launcher_id = json_string (obj, "launcher_id");
            e.launch_entrypoint_id = json_string (obj, "launch_entrypoint_id");
            e.variant_id = json_string (obj, "variant_id");
            e.wine_arch = json_string (obj, "wine_arch");
            e.wine_debug = json_string (obj, "wine_debug");
            e.wine_wayland = json_bool_nullable (obj, "wine_wayland");
            e.large_address_aware = json_bool_nullable (obj, "large_address_aware");
            e.sync_mode = json_string (obj, "sync_mode");
            e.prelaunch_script = json_string (obj, "prelaunch_script");

            if (obj.has_member ("custom_entrypoints")) {
                var ep_arr = obj.get_array_member ("custom_entrypoints");
                for (uint i = 0; i < ep_arr.get_length (); i++) {
                    e.custom_entrypoints.add (Entrypoint.from_json (ep_arr.get_object_element (i)));
                }
            }

            e.runtime_env_vars = json_string_map (obj, "runtime_env_vars");
            e.dynamic_launcher_desktop_ids = json_string_map (obj, "dynamic_launcher_desktop_ids");

            if (obj.has_member ("runtime_component_overrides")) {
                var overrides = obj.get_object_member ("runtime_component_overrides");
                overrides.foreach_member ((_, key, node) => {
                    e.runtime_component_overrides[key] = RuntimeComponentOverride.from_json (node.get_object ());
                });
            }
            return e;
        }
    }
}
