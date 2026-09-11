namespace Lumoria.Models {

    public class LaunchRef : Object {
        public string prefix_id { get; set; default = ""; }
        public string action_id { get; set; default = ""; }

        public bool is_empty () {
            return prefix_id == "";
        }

        public void pin_prefix (string prefix_id) {
            this.prefix_id = prefix_id;
            action_id = "";
        }

        public bool matches (string prefix_id, string action_id) {
            return this.prefix_id == prefix_id && this.action_id == action_id;
        }

        public string tile_key () {
            return compose_tile_key (prefix_id, action_id);
        }

        public static string compose_tile_key (string prefix_id, string action_id) {
            return prefix_id + "\t" + action_id;
        }

        public static bool parse_tile_key (string raw, out string prefix_id, out string action_id) {
            prefix_id = "";
            action_id = "";
            if (raw == null) return false;
            var parts = raw.split ("\t", 2);
            if (parts.length != 2) return false;
            prefix_id = parts[0];
            action_id = parts[1];
            return prefix_id != "";
        }

        public bool matches_prefix (string prefix_id) {
            return this.prefix_id == prefix_id && prefix_id != "";
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            if (prefix_id != "") obj.set_string_member ("prefix_id", prefix_id);
            if (action_id != "") obj.set_string_member ("action_id", action_id);
            return obj;
        }

        public static LaunchRef from_json (Json.Object obj) throws Error {
            var t = new LaunchRef ();
            t.prefix_id = json_string (obj, "prefix_id");
            t.action_id = json_string (obj, "action_id");
            return t;
        }
    }
}
