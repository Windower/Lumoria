namespace Lumoria.Models {

    public class RemoteManifestSchema : Object {
        public string url_template { get; set; default = ""; }
        public string files_path { get; set; default = ""; }
        public string checksum_field { get; set; default = ""; }
        public string checksum_algorithm { get; set; default = ""; }
        public string checksum_algorithm_field { get; set; default = ""; }
        public string filename_field { get; set; default = ""; }
        public WhenClause? filter { get; set; default = null; }
        public string sort_field { get; set; default = ""; }
        public string available_field { get; set; default = ""; }
        public int64 cache_ttl { get; set; default = 3600; }

        public static RemoteManifestSchema from_json (Json.Object obj) throws Error {
            var s = new RemoteManifestSchema ();
            s.url_template = json_string (obj, "url_template");
            s.files_path = json_string (obj, "files_path");
            s.checksum_field = json_string (obj, "checksum_field");
            s.checksum_algorithm = json_string (obj, "checksum_algorithm");
            s.checksum_algorithm_field = json_string (obj, "checksum_algorithm_field");
            s.filename_field = json_string (obj, "filename_field");
            if (obj.has_member ("filter")) {
                var node = obj.get_member ("filter");
                if (node.get_node_type () == Json.NodeType.OBJECT) {
                    s.filter = WhenClause.parse_node (node.get_object ());
                }
            }
            s.sort_field = json_string (obj, "sort_field");
            s.available_field = json_string (obj, "available_field");
            s.cache_ttl = json_int (obj, "cache_ttl", 3600);
            if (s.url_template == "") {
                throw new LumoriaError.INVALID_MANIFEST (_("Remote manifest schema requires url_template"));
            }
            return s;
        }
    }

    public class RemoteManifestAction : Object {
        public string id_template { get; set; default = ""; }
        public string name_template { get; set; default = ""; }
        public string description { get; set; default = ""; }
        public string icon { get; set; default = ""; }
        public string manifest_url { get; set; default = ""; }
        public RemoteManifestSchema? manifest_schema { get; set; default = null; }
        public string dst { get; set; default = ""; }
        public ActionConfirm confirm { get; owned set; default = new ActionConfirm (); }
        public ActionButton button { get; owned set; default = new ActionButton (); }

        public static RemoteManifestAction from_json (Json.Object obj) throws Error {
            var a = new RemoteManifestAction ();
            a.id_template = json_string (obj, "id_template");
            a.name_template = json_string (obj, "name_template");
            a.description = json_string (obj, "description");
            a.icon = json_string (obj, "icon");
            a.manifest_url = json_string (obj, "manifest_url");
            a.manifest_schema = json_parse_member<RemoteManifestSchema> (
                obj, "manifest_schema", RemoteManifestSchema.from_json
            );
            a.dst = json_string (obj, "dst");
            a.confirm = ActionConfirm.from_json (obj);
            a.button = ActionButton.from_json (obj);
            return a;
        }
    }

    public static Gee.ArrayList<RemoteManifestAction> parse_remote_manifest_actions (Json.Object obj) throws Error {
        return parse_json_array<RemoteManifestAction> (obj, "remote_manifest_actions", (o) => RemoteManifestAction.from_json (o));
    }

    public static string expand_manifest_template (
        string template,
        Gee.HashMap<string, string> item_fields,
        Gee.HashMap<string, string> vars
    ) {
        var result = template;
        try {
            var re = new Regex ("\\$\\{manifestField\\.([^}:]+)(?::([^}]*))?\\}");
            result = re.replace_eval (template, template.length, 0, 0, (match, builder) => {
                var field_name = match.fetch (1);
                var modifiers  = match.fetch (2);
                var value = (field_name != null && item_fields.has_key (field_name))
                    ? item_fields[field_name] : "";
                builder.append (Utils.apply_modifier_chain (value, modifiers));
                return false;
            });
        } catch (RegexError e) {
            warning ("expand_manifest_template: %s", e.message);
        }
        return Utils.expand_vars (result, vars);
    }

}
