namespace Lumoria.Models {

    public enum WhenClauseKind {
        MATCH,
        MANIFEST_FIELD_MATCH,
        FILE_EXISTS,
        ALL,
        ANY,
        NOT
    }

    public class WhenClause : Object {
        public WhenClauseKind kind { get; set; }
        public string key { get; set; default = ""; }
        public string value { get; set; default = ""; }
        public string op { get; set; default = "eq"; }
        public Gee.ArrayList<WhenClause> children { get; owned set; default = new Gee.ArrayList<WhenClause> (); }

        public WhenClause (WhenClauseKind kind) {
            this.kind = kind;
        }

        public bool evaluate (Gee.HashMap<string, string> vars, Gee.HashMap<string, string>? item_fields = null) {
            switch (kind) {
                case WhenClauseKind.MATCH:
                    return vars.has_key (key) && apply_op (vars[key]);
                case WhenClauseKind.MANIFEST_FIELD_MATCH:
                    return item_fields != null && item_fields.has_key (key) && apply_op (item_fields[key]);
                case WhenClauseKind.FILE_EXISTS:
                    var expanded = Utils.expand_vars (value, vars);
                    return FileUtils.test (expanded, FileTest.EXISTS);
                case WhenClauseKind.ALL:
                    foreach (var child in children) {
                        if (!child.evaluate (vars, item_fields)) return false;
                    }
                    return true;
                case WhenClauseKind.ANY:
                    foreach (var child in children) {
                        if (child.evaluate (vars, item_fields)) return true;
                    }
                    return false;
                case WhenClauseKind.NOT:
                    return children.size > 0 && !children[0].evaluate (vars, item_fields);
                default:
                    return false;
            }
        }

        private bool apply_op (string actual) {
            switch (op) {
                case "eq":         return actual == value;
                case "neq":        return actual != value;
                case "contains":   return actual.contains (value);
                case "startswith": return actual.has_prefix (value);
                case "endswith":   return actual.has_suffix (value);
                case "gt":
                case "gte":
                case "lt":
                case "lte": {
                    double a = 0, b = 0;
                    if (!double.try_parse (actual, out a) || !double.try_parse (value, out b)) return false;
                    if (op == "gt")  return a > b;
                    if (op == "gte") return a >= b;
                    if (op == "lt")  return a < b;
                    return a <= b;
                }
                default: return actual == value;
            }
        }

        public static WhenClause? from_json_member (Json.Object obj) throws Error {
            if (!obj.has_member ("when")) return null;
            var node = obj.get_member ("when");
            if (node.get_node_type () != Json.NodeType.OBJECT) return null;
            return parse_node (node.get_object ());
        }

        public static WhenClause? from_json_object (Json.Object obj) throws Error {
            return parse_node (obj);
        }

        private static WhenClause parse_node (Json.Object obj) throws Error {
            var members = obj.get_members ();
            if (members.length () != 1) {
                throw new IOError.FAILED ("Invalid when clause: expected exactly one operator");
            }

            var op = members.nth_data (0);
            switch (op) {
                case "all":
                    var all_clause = new WhenClause (WhenClauseKind.ALL);
                    parse_array_children (obj.get_array_member ("all"), all_clause);
                    return all_clause;
                case "any":
                    var any_clause = new WhenClause (WhenClauseKind.ANY);
                    parse_array_children (obj.get_array_member ("any"), any_clause);
                    return any_clause;
                case "not":
                    var not_clause = new WhenClause (WhenClauseKind.NOT);
                    var inner = obj.get_member ("not").get_object ();
                    not_clause.children.add (parse_node (inner));
                    return not_clause;
                case "file_exists":
                    var file_clause = new WhenClause (WhenClauseKind.FILE_EXISTS);
                    file_clause.value = obj.get_string_member ("file_exists");
                    return file_clause;
                case "var":
                    return parse_var_match (obj.get_object_member ("var"));
                case "manifestField":
                    return parse_manifest_field_match (obj.get_object_member ("manifestField"));
                default:
                    throw new IOError.FAILED ("Invalid when clause operator: %s", op);
            }
        }

        private static WhenClause parse_var_match (Json.Object obj) throws Error {
            var members = obj.get_members ();
            if (members.length () == 0) {
                throw new IOError.FAILED ("Invalid when var clause: expected at least one variable match");
            }
            var clause = new WhenClause (WhenClauseKind.ALL);
            foreach (unowned string k in members) {
                var child = new WhenClause (WhenClauseKind.MATCH);
                child.key = k;
                parse_match_value (obj.get_member (k), child);
                clause.children.add (child);
            }
            if (clause.children.size == 1) return clause.children[0];
            return clause;
        }

        private static WhenClause parse_manifest_field_match (Json.Object obj) throws Error {
            var members = obj.get_members ();
            if (members.length () == 0) {
                throw new IOError.FAILED ("Invalid manifestField clause: expected at least one field match");
            }
            var clause = new WhenClause (WhenClauseKind.ALL);
            foreach (unowned string k in members) {
                var child = new WhenClause (WhenClauseKind.MANIFEST_FIELD_MATCH);
                child.key = k;
                parse_match_value (obj.get_member (k), child);
                clause.children.add (child);
            }
            if (clause.children.size == 1) return clause.children[0];
            return clause;
        }

        private static void parse_array_children (Json.Array arr, WhenClause parent) throws Error {
            for (uint i = 0; i < arr.get_length (); i++) {
                parent.children.add (parse_node (arr.get_object_element (i)));
            }
        }

        private static void parse_match_value (Json.Node node, WhenClause clause) {
            if (node.get_node_type () == Json.NodeType.OBJECT) {
                var op_obj = node.get_object ();
                var ops = op_obj.get_members ();
                if (ops.length () == 1) {
                    clause.op = ops.nth_data (0);
                    clause.value = json_node_to_string (op_obj.get_member (clause.op));
                    return;
                }
            }
            clause.op = "eq";
            clause.value = json_node_to_string (node);
        }

        private static string json_node_to_string (Json.Node node) {
            if (node.get_node_type () != Json.NodeType.VALUE) return "";
            var vtype = node.get_value_type ();
            if (vtype == typeof (string)) return node.get_string ();
            if (vtype == typeof (bool))   return node.get_boolean () ? "true" : "false";
            if (vtype == typeof (int64))  return node.get_int ().to_string ();
            if (vtype == typeof (double)) return node.get_double ().to_string ();
            return "";
        }
    }

    public class EnvRule : Object {
        public Gee.HashMap<string, string> vars { get; owned set; default = new Gee.HashMap<string, string> (); }
        public WhenClause? when { get; set; default = null; }

        public static EnvRule from_json (Json.Object obj) throws Error {
            var r = new EnvRule ();
            r.vars = json_string_map (obj, "vars");
            r.when = WhenClause.from_json_member (obj);
            return r;
        }
    }

    public static void parse_variable_definitions (
        Json.Object obj,
        string key,
        out Gee.HashMap<string, string> variables,
        out Gee.ArrayList<EnvRule> variable_rules
    ) throws Error {
        var parsed_variables = new Gee.HashMap<string, string> ();
        var parsed_rules = new Gee.ArrayList<EnvRule> ();
        if (!obj.has_member (key)) {
            variables = parsed_variables;
            variable_rules = parsed_rules;
            return;
        }

        var map = obj.get_object_member (key);
        var members = map.get_members ();
        foreach (unowned string name in members) {
            var node = map.get_member (name);
            switch (node.get_node_type ()) {
                case Json.NodeType.OBJECT:
                    parse_variable_object (name, node.get_object (), parsed_variables, parsed_rules);
                    break;
                case Json.NodeType.ARRAY:
                    parse_variable_array (name, node.get_array (), parsed_variables, parsed_rules);
                    break;
                default:
                    parsed_variables[name] = node.get_string ();
                    break;
            }
        }
        variables = parsed_variables;
        variable_rules = parsed_rules;
    }

    private static void parse_variable_object (
        string name,
        Json.Object obj,
        Gee.HashMap<string, string> variables,
        Gee.ArrayList<EnvRule> variable_rules
    ) throws Error {
        if (obj.has_member ("default")) {
            variables[name] = obj.get_string_member ("default");
        }
        if (obj.has_member ("value")) {
            append_variable_rule_or_default (name, obj, variables, variable_rules);
        }
        if (obj.has_member ("rules")) {
            parse_variable_array (name, obj.get_array_member ("rules"), variables, variable_rules);
        }
    }

    private static void parse_variable_array (
        string name,
        Json.Array arr,
        Gee.HashMap<string, string> variables,
        Gee.ArrayList<EnvRule> variable_rules
    ) throws Error {
        for (uint i = 0; i < arr.get_length (); i++) {
            append_variable_rule_or_default (
                name,
                arr.get_object_element (i),
                variables,
                variable_rules
            );
        }
    }

    private static void append_variable_rule_or_default (
        string name,
        Json.Object obj,
        Gee.HashMap<string, string> variables,
        Gee.ArrayList<EnvRule> variable_rules
    ) throws Error {
        if (!obj.has_member ("value")) return;
        if (!obj.has_member ("when")) {
            variables[name] = obj.get_string_member ("value");
            return;
        }

        var rule = new EnvRule ();
        rule.vars[name] = obj.get_string_member ("value");
        rule.when = WhenClause.from_json_member (obj);
        variable_rules.add (rule);
    }

    public class PortalPathRef : Object {
        public string document_id { get; set; default = ""; }
        public string document_path { get; set; default = ""; }
        public string uri { get; set; default = ""; }

        public bool is_empty () {
            return document_id == "" || document_path == "";
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            if (document_id != "") obj.set_string_member ("document_id", document_id);
            if (document_path != "") obj.set_string_member ("document_path", document_path);
            if (uri != "") obj.set_string_member ("uri", uri);
            return obj;
        }

        public static PortalPathRef from_json (Json.Object obj) {
            var r = new PortalPathRef ();
            r.document_id = json_string (obj, "document_id");
            r.document_path = json_string (obj, "document_path");
            r.uri = json_string (obj, "uri");
            return r;
        }
    }

    public class Entrypoint : BaseSpec {
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

        public static Entrypoint from_json (Json.Object obj) throws Error {
            var e = new Entrypoint ();
            e.parse_base (obj);
            e.exe = json_string (obj, "exe");
            if (obj.has_member ("exe_portal")) {
                e.exe_portal = PortalPathRef.from_json (obj.get_object_member ("exe_portal"));
            }
            e.is_default = json_bool (obj, "default");
            e.args = json_string_array (obj, "args");
            e.prelaunch_script = json_string (obj, "prelaunch_script");
            if (obj.has_member ("prelaunch_script_portal")) {
                e.prelaunch_script_portal = PortalPathRef.from_json (obj.get_object_member ("prelaunch_script_portal"));
            }
            e.when = WhenClause.from_json_member (obj);
            e.env = parse_env_rules (obj);
            e.component_overrides = json_component_override_map (obj, "component_overrides");
            e.runtime_dll_overrides = json_string_map (obj, "runtime_dll_overrides");
            e.runtime_env_overrides = json_string_map (obj, "runtime_env_overrides");
            return e;
        }
    }

    public class DownloadItem : Object {
        public string id { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public string dest { get; set; default = ""; }
        public string sha256 { get; set; default = ""; }
        public string checksum_algorithm { get; set; default = ""; }
        public WhenClause? when { get; set; default = null; }

        public static DownloadItem from_json (Json.Object obj) throws Error {
            var d = new DownloadItem ();
            d.id = json_string (obj, "id");
            d.url = json_string (obj, "url");
            d.dest = json_string (obj, "dest");
            d.sha256 = json_string (obj, "sha256");
            d.checksum_algorithm = json_string (obj, "checksum_algorithm");
            d.when = WhenClause.from_json_member (obj);
            return d;
        }
    }

    public class InstallStep : Object {
        public string step_type { get; set; default = ""; }
        public string description { get; set; default = ""; }
        public string command { get; set; default = ""; }
        public string mode { get; set; default = ""; }
        public string src { get; set; default = ""; }
        public string dst { get; set; default = ""; }
        public string working_dir { get; set; default = ""; }
        public string content { get; set; default = ""; }
        public string root { get; set; default = ""; }
        public string element { get; set; default = ""; }
        public string git_branch { get; set; default = ""; }
        public string git_tag { get; set; default = ""; }
        public string git_commit { get; set; default = ""; }
        public bool create_if_missing { get; set; default = true; }
        public bool overwrite_existing { get; set; default = false; }
        public bool idempotent { get; set; default = true; }
        public string manifest_url { get; set; default = ""; }
        public RemoteManifestSchema? manifest_schema { get; set; default = null; }
        public WhenClause? when { get; set; default = null; }
        public Gee.HashMap<string, string> match { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.HashMap<string, string> children { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<string> args { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> verify_paths { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> font_registrations { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<EnvRule> env { get; owned set; default = new Gee.ArrayList<EnvRule> (); }

        public static InstallStep from_json (Json.Object obj) throws Error {
            var s = new InstallStep ();
            s.step_type = json_string (obj, "type");
            s.description = json_string (obj, "description");
            s.command = json_string (obj, "command");
            s.mode = json_string (obj, "mode");
            s.src = json_string (obj, "src");
            s.dst = json_string (obj, "dst");
            s.working_dir = json_string (obj, "working_dir");
            s.content = json_string_or_lines (obj, "content");
            s.root = json_string (obj, "root");
            s.element = json_string (obj, "element");
            s.git_branch = json_string (obj, "branch");
            s.git_tag = json_string (obj, "tag");
            s.git_commit = json_string (obj, "commit");
            s.create_if_missing = json_bool (obj, "create_if_missing", true);
            s.overwrite_existing = json_bool (obj, "overwrite_existing");
            s.idempotent = json_bool (obj, "idempotent", true);
            s.manifest_url = json_string (obj, "manifest_url");
            if (obj.has_member ("manifest_schema")) {
                s.manifest_schema = RemoteManifestSchema.from_json (obj.get_object_member ("manifest_schema"));
            }
            s.when = WhenClause.from_json_member (obj);
            s.match = json_string_map (obj, "match");
            s.children = json_string_map (obj, "children");
            s.args = json_string_array (obj, "args");
            s.verify_paths = json_string_array (obj, "verify_paths");
            s.font_registrations = json_string_array (obj, "font_registrations");
            s.env = parse_env_rules (obj);
            return s;
        }
    }

    public class SpecAction : BaseSpec {
        public string description { get; set; default = ""; }
        public string icon { get; set; default = ""; }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<DownloadItem> downloads { get; owned set; default = new Gee.ArrayList<DownloadItem> (); }
        public Gee.ArrayList<InstallStep> steps { get; owned set; default = new Gee.ArrayList<InstallStep> (); }
        public Gee.ArrayList<EnvRule> env { get; owned set; default = new Gee.ArrayList<EnvRule> (); }

        public static SpecAction from_json (Json.Object obj) throws Error {
            var a = new SpecAction ();
            a.parse_base (obj);
            a.description = json_string (obj, "description");
            a.icon = json_string (obj, "icon");
            a.variables = json_string_map (obj, "variables");
            a.redists = json_string_array (obj, "redists");
            a.downloads = parse_downloads (obj);
            a.steps = parse_steps (obj);
            a.env = parse_env_rules (obj);
            return a;
        }
    }

    public static Gee.ArrayList<DownloadItem> parse_downloads (Json.Object obj) throws Error {
        return parse_json_array<DownloadItem> (obj, "downloads", (o) => DownloadItem.from_json (o));
    }

    public static Gee.ArrayList<InstallStep> parse_steps (Json.Object obj) throws Error {
        return parse_json_array<InstallStep> (obj, "steps", (o) => InstallStep.from_json (o));
    }

    public static Gee.ArrayList<Entrypoint> parse_entrypoints (Json.Object obj) throws Error {
        return parse_json_array<Entrypoint> (obj, "entrypoints", (o) => Entrypoint.from_json (o));
    }

    public static Gee.ArrayList<SpecAction> parse_actions (Json.Object obj) throws Error {
        return parse_json_array<SpecAction> (obj, "actions", (o) => SpecAction.from_json (o));
    }

    public static Gee.ArrayList<EnvRule> parse_env_rules (Json.Object obj) throws Error {
        return parse_env_rules_member (obj, "env");
    }

    public static Gee.ArrayList<EnvRule> parse_env_rules_member (Json.Object obj, string member) throws Error {
        return parse_json_array<EnvRule> (obj, member, (o) => EnvRule.from_json (o));
    }

    public static Gee.HashMap<string, RuntimeComponentOverride> json_component_override_map (
        Json.Object obj,
        string key
    ) {
        var map = new Gee.HashMap<string, RuntimeComponentOverride> ();
        if (!obj.has_member (key)) return map;
        var overrides = obj.get_object_member (key);
        overrides.foreach_member ((_, member, node) => {
            map[member] = RuntimeComponentOverride.from_json (node.get_object ());
        });
        return map;
    }

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
                    s.filter = WhenClause.from_json_object (node.get_object ());
                }
            }
            s.sort_field = json_string (obj, "sort_field");
            s.available_field = json_string (obj, "available_field");
            s.cache_ttl = obj.has_member ("cache_ttl") ? obj.get_int_member ("cache_ttl") : 3600;
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

        public static RemoteManifestAction from_json (Json.Object obj) throws Error {
            var a = new RemoteManifestAction ();
            a.id_template = json_string (obj, "id_template");
            a.name_template = json_string (obj, "name_template");
            a.description = json_string (obj, "description");
            a.icon = json_string (obj, "icon");
            a.manifest_url = json_string (obj, "manifest_url");
            if (obj.has_member ("manifest_schema")) {
                a.manifest_schema = RemoteManifestSchema.from_json (obj.get_object_member ("manifest_schema"));
            }
            a.dst = json_string (obj, "dst");
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
