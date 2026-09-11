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
            if (system_env.size > 0) obj.set_object_member ("system_env", json_string_map_object (system_env));
            return obj;
        }

        public static RuntimeComponentOverride from_json (Json.Object obj) throws Error {
            var o = new RuntimeComponentOverride ();
            o.enabled = json_bool_nullable (obj, KEY_ENABLED);
            o.version = json_string (obj, "version");
            o.system_env = json_string_map (obj, "system_env");
            return o;
        }

        public bool is_empty () {
            return enabled == null && ToolVersionRef.is_inherit (version) && system_env.size == 0;
        }

        public RuntimeComponentOverride copy () {
            var o = new RuntimeComponentOverride ();
            o.enabled = enabled;
            o.version = version;
            o.system_env.set_all (system_env);
            return o;
        }
    }
}
