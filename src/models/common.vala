namespace Lumoria.Models {

    public class Entrypoint : BaseSpec {
        public string exe { get; set; default = ""; }
        public Gee.ArrayList<string> args { get; owned set; default = new Gee.ArrayList<string> (); }
        public bool is_default { get; set; default = false; }
        public string prelaunch_script { get; set; default = ""; }

        public static Entrypoint from_json (Json.Object obj) {
            var e = new Entrypoint ();
            e.parse_base (obj);
            e.exe = json_string (obj, "exe");
            e.is_default = json_bool (obj, "default");
            e.args = json_string_array (obj, "args");
            e.prelaunch_script = json_string (obj, "prelaunch_script");
            return e;
        }
    }

    public class DownloadItem : Object {
        public string id { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public string dest { get; set; default = ""; }
        public string sha256 { get; set; default = ""; }

        public static DownloadItem from_json (Json.Object obj) {
            var d = new DownloadItem ();
            d.id = json_string (obj, "id");
            d.url = json_string (obj, "url");
            d.dest = json_string (obj, "dest");
            d.sha256 = json_string (obj, "sha256");
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
        public string condition { get; set; default = ""; }
        public string content { get; set; default = ""; }
        public string root { get; set; default = ""; }
        public string element { get; set; default = ""; }
        public bool create_if_missing { get; set; default = true; }
        public bool overwrite_existing { get; set; default = false; }
        public Gee.HashMap<string, string> match { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.HashMap<string, string> children { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<string> args { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> skip_if_exists { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> verify_paths { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> font_registrations { get; owned set; default = new Gee.ArrayList<string> (); }

        public static InstallStep from_json (Json.Object obj) {
            var s = new InstallStep ();
            s.step_type = json_string (obj, "type");
            s.description = json_string (obj, "description");
            s.command = json_string (obj, "command");
            s.mode = json_string (obj, "mode");
            s.src = json_string (obj, "src");
            s.dst = json_string (obj, "dst");
            s.working_dir = json_string (obj, "working_dir");
            s.condition = json_string (obj, "condition");
            s.content = json_string (obj, "content");
            s.root = json_string (obj, "root");
            s.element = json_string (obj, "element");
            s.create_if_missing = json_bool (obj, "create_if_missing", true);
            s.overwrite_existing = json_bool (obj, "overwrite_existing");
            s.match = json_string_map (obj, "match");
            s.children = json_string_map (obj, "children");
            s.args = json_string_array (obj, "args");
            s.skip_if_exists = json_string_array (obj, "skip_if_exists");
            s.verify_paths = json_string_array (obj, "verify_paths");
            s.font_registrations = json_string_array (obj, "font_registrations");
            return s;
        }
    }

    public class SpecAction : BaseSpec {
        public string description { get; set; default = ""; }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<DownloadItem> downloads { get; owned set; default = new Gee.ArrayList<DownloadItem> (); }
        public Gee.ArrayList<InstallStep> steps { get; owned set; default = new Gee.ArrayList<InstallStep> (); }

        public static SpecAction from_json (Json.Object obj) throws Error {
            var a = new SpecAction ();
            a.parse_base (obj);
            a.description = json_string (obj, "description");
            a.variables = json_string_map (obj, "variables");
            a.redists = json_string_array (obj, "redists");
            a.downloads = parse_downloads (obj);
            a.steps = parse_steps (obj);
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
}
