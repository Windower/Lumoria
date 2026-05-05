namespace Lumoria.Models {

    public enum WhenClauseKind {
        MATCH,
        FILE_EXISTS,
        ALL,
        ANY,
        NOT
    }

    public class WhenClause : Object {
        public WhenClauseKind kind { get; set; }
        public string key { get; set; default = ""; }
        public string value { get; set; default = ""; }
        public Gee.ArrayList<WhenClause> children { get; owned set; default = new Gee.ArrayList<WhenClause> (); }

        public WhenClause (WhenClauseKind kind) {
            this.kind = kind;
        }

        public bool evaluate (Gee.HashMap<string, string> vars) {
            switch (kind) {
                case WhenClauseKind.MATCH:
                    return vars.has_key (key) && vars[key] == value;
                case WhenClauseKind.FILE_EXISTS:
                    var expanded = Utils.expand_vars (value, vars);
                    return FileUtils.test (expanded, FileTest.EXISTS);
                case WhenClauseKind.ALL:
                    foreach (var child in children) {
                        if (!child.evaluate (vars)) return false;
                    }
                    return true;
                case WhenClauseKind.ANY:
                    foreach (var child in children) {
                        if (child.evaluate (vars)) return true;
                    }
                    return false;
                case WhenClauseKind.NOT:
                    return children.size > 0 && !children[0].evaluate (vars);
                default:
                    return false;
            }
        }

        public static WhenClause? from_json_member (Json.Object obj) {
            if (!obj.has_member ("when")) return null;
            var node = obj.get_member ("when");
            if (node.get_node_type () != Json.NodeType.OBJECT) return null;
            return parse_node (node.get_object ());
        }

        private static WhenClause parse_node (Json.Object obj) {
            if (obj.has_member ("all")) {
                var clause = new WhenClause (WhenClauseKind.ALL);
                parse_array_children (obj.get_array_member ("all"), clause);
                return clause;
            }
            if (obj.has_member ("any")) {
                var clause = new WhenClause (WhenClauseKind.ANY);
                parse_array_children (obj.get_array_member ("any"), clause);
                return clause;
            }
            if (obj.has_member ("not")) {
                var clause = new WhenClause (WhenClauseKind.NOT);
                var inner = obj.get_member ("not").get_object ();
                clause.children.add (parse_node (inner));
                return clause;
            }
            if (obj.has_member ("file_exists")) {
                var clause = new WhenClause (WhenClauseKind.FILE_EXISTS);
                clause.value = obj.get_string_member ("file_exists");
                return clause;
            }
            var members = obj.get_members ();
            if (members.length () == 1) {
                var k = members.nth_data (0);
                var clause = new WhenClause (WhenClauseKind.MATCH);
                clause.key = k;
                clause.value = obj.get_string_member (k);
                return clause;
            }
            var clause = new WhenClause (WhenClauseKind.ALL);
            foreach (unowned string k in members) {
                var child = new WhenClause (WhenClauseKind.MATCH);
                child.key = k;
                child.value = obj.get_string_member (k);
                clause.children.add (child);
            }
            return clause;
        }

        private static void parse_array_children (Json.Array arr, WhenClause parent) {
            for (uint i = 0; i < arr.get_length (); i++) {
                parent.children.add (parse_node (arr.get_object_element (i)));
            }
        }
    }

    public class EnvRule : Object {
        public Gee.HashMap<string, string> vars { get; owned set; default = new Gee.HashMap<string, string> (); }
        public WhenClause? when { get; set; default = null; }

        public static EnvRule from_json (Json.Object obj) {
            var r = new EnvRule ();
            r.vars = json_string_map (obj, "vars");
            r.when = WhenClause.from_json_member (obj);
            return r;
        }
    }

    public class Entrypoint : BaseSpec {
        public string exe { get; set; default = ""; }
        public Gee.ArrayList<string> args { get; owned set; default = new Gee.ArrayList<string> (); }
        public bool is_default { get; set; default = false; }
        public string prelaunch_script { get; set; default = ""; }
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
            e.is_default = json_bool (obj, "default");
            e.args = json_string_array (obj, "args");
            e.prelaunch_script = json_string (obj, "prelaunch_script");
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
        public WhenClause? when { get; set; default = null; }

        public static DownloadItem from_json (Json.Object obj) {
            var d = new DownloadItem ();
            d.id = json_string (obj, "id");
            d.url = json_string (obj, "url");
            d.dest = json_string (obj, "dest");
            d.sha256 = json_string (obj, "sha256");
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
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<DownloadItem> downloads { get; owned set; default = new Gee.ArrayList<DownloadItem> (); }
        public Gee.ArrayList<InstallStep> steps { get; owned set; default = new Gee.ArrayList<InstallStep> (); }
        public Gee.ArrayList<EnvRule> env { get; owned set; default = new Gee.ArrayList<EnvRule> (); }

        public static SpecAction from_json (Json.Object obj) throws Error {
            var a = new SpecAction ();
            a.parse_base (obj);
            a.description = json_string (obj, "description");
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
        return parse_json_array<EnvRule> (obj, "env", (o) => EnvRule.from_json (o));
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
}
