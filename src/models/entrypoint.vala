namespace Lumoria.Models {

    public class Entrypoint : IdentifiedRecord {
        public string icon { get; set; default = ""; }
        public string exe { get; set; default = ""; }
        public PortalPathRef? exe_portal { get; set; default = null; }
        public Gee.ArrayList<string> args { get; owned set; default = new Gee.ArrayList<string> (); }
        public bool is_default { get; set; default = false; }
        public string prelaunch_script { get; set; default = ""; }
        public PortalPathRef? prelaunch_script_portal { get; set; default = null; }
        public WhenClause? when { get; set; default = null; }
        public Gee.ArrayList<EnvRule> env { get; owned set; default = new Gee.ArrayList<EnvRule> (); }
        public Gee.HashMap<string, RuntimeComponentOverride> component_overrides {
            get; owned set; default = new Gee.HashMap<string, RuntimeComponentOverride> ();
        }
        public Gee.HashMap<string, string> runtime_dll_overrides {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
        public Gee.HashMap<string, string> runtime_env_overrides {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }

        public string title () {
            return name != "" ? name : Path.get_basename (exe);
        }

        public Entrypoint copy () {
            var e = new Entrypoint ();
            e.id = id;
            e.name = name;
            e.label = label;
            e.icon = icon;
            e.exe = exe;
            e.exe_portal = exe_portal != null ? exe_portal.copy () : null;
            e.args.add_all (args);
            e.is_default = is_default;
            e.prelaunch_script = prelaunch_script;
            e.prelaunch_script_portal = prelaunch_script_portal != null ? prelaunch_script_portal.copy () : null;
            e.when = when != null ? when.copy () : null;
            foreach (var rule in env) e.env.add (rule.copy ());
            foreach (var ov in component_overrides.entries) {
                e.component_overrides[ov.key] = ov.value.copy ();
            }
            e.runtime_dll_overrides.set_all (runtime_dll_overrides);
            e.runtime_env_overrides.set_all (runtime_env_overrides);
            return e;
        }

        public static Entrypoint from_json (Json.Object obj) throws Error {
            var e = new Entrypoint ();
            e.parse_identity (obj);
            e.icon = json_string (obj, "icon");
            e.exe = json_string (obj, "exe");
            e.exe_portal = json_parse_member<PortalPathRef> (obj, "exe_portal", PortalPathRef.from_json);
            e.is_default = json_bool (obj, "default");
            e.args = json_string_array (obj, "args");
            e.prelaunch_script = json_string (obj, "prelaunch_script");
            e.prelaunch_script_portal = json_parse_member<PortalPathRef> (
                obj, "prelaunch_script_portal", PortalPathRef.from_json
            );
            e.when = WhenClause.from_json_member (obj);
            e.env = parse_env_rules (obj);
            e.component_overrides = json_component_override_map (obj, "component_overrides");
            e.runtime_dll_overrides = json_string_map (obj, "runtime_dll_overrides");
            e.runtime_env_overrides = json_string_map (obj, "runtime_env_overrides");
            if (e.exe == "" && (e.exe_portal == null || e.exe_portal.is_empty ())) {
                throw new LumoriaError.INVALID_MANIFEST (_("Entrypoints require exe or exe_portal"));
            }
            return e;
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            if (id != "") obj.set_string_member ("id", id);
            if (name != "") obj.set_string_member ("name", name);
            if (label != "") obj.set_string_member ("label", label);
            if (icon != "") obj.set_string_member ("icon", icon);
            if (exe != "") obj.set_string_member ("exe", exe);
            if (exe_portal != null && !exe_portal.is_empty ()) {
                obj.set_object_member ("exe_portal", exe_portal.to_json ());
            }
            if (args.size > 0) {
                obj.set_array_member ("args", json_string_list_array (args));
            }
            if (is_default) obj.set_boolean_member ("default", true);
            if (prelaunch_script != "") {
                obj.set_string_member ("prelaunch_script", prelaunch_script);
            }
            if (prelaunch_script_portal != null && !prelaunch_script_portal.is_empty ()) {
                obj.set_object_member ("prelaunch_script_portal", prelaunch_script_portal.to_json ());
            }
            if (when != null) obj.set_object_member ("when", when.to_json ());
            if (env.size > 0) {
                var env_arr = new Json.Array ();
                foreach (var rule in env) env_arr.add_object_element (rule.to_json ());
                obj.set_array_member ("env", env_arr);
            }
            if (component_overrides.size > 0) {
                var ov_obj = new Json.Object ();
                foreach (var ov in component_overrides.entries) {
                    ov_obj.set_object_member (ov.key, ov.value.to_json ());
                }
                obj.set_object_member ("component_overrides", ov_obj);
            }
            if (runtime_dll_overrides.size > 0) {
                obj.set_object_member (
                    "runtime_dll_overrides",
                    json_string_map_object (runtime_dll_overrides)
                );
            }
            if (runtime_env_overrides.size > 0) {
                obj.set_object_member (
                    "runtime_env_overrides",
                    json_string_map_object (runtime_env_overrides)
                );
            }
            return obj;
        }
    }

}
