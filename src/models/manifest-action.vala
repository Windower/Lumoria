namespace Lumoria.Models {

    public class ManifestAction : IdentifiedRecord {
        public string description { get; set; default = ""; }
        public string icon { get; set; default = ""; }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<DownloadItem> downloads { get; owned set; default = new Gee.ArrayList<DownloadItem> (); }
        public Gee.ArrayList<InstallStep> steps { get; owned set; default = new Gee.ArrayList<InstallStep> (); }
        public Gee.ArrayList<EnvRule> env { get; owned set; default = new Gee.ArrayList<EnvRule> (); }
        public ActionConfirm confirm { get; owned set; default = new ActionConfirm (); }
        public ActionButton button { get; owned set; default = new ActionButton (); }

        public static ManifestAction from_json (Json.Object obj) throws Error {
            var a = new ManifestAction ();
            a.parse_identity (obj);
            a.description = json_string (obj, "description");
            a.icon = json_string (obj, "icon");
            a.variables = json_string_map (obj, "variables");
            a.redists = json_string_array (obj, "redists");
            a.downloads = parse_downloads (obj);
            a.steps = parse_steps (obj);
            a.env = parse_env_rules (obj);
            a.confirm = ActionConfirm.from_json (obj);
            a.button = ActionButton.from_json (obj);
            return a;
        }

        public ManifestAction copy (string new_id = "") {
            var copy = new ManifestAction ();
            copy.id = new_id != "" ? new_id : id;
            copy.name = name;
            copy.label = label;
            copy.description = description;
            copy.icon = icon;
            copy.variables.set_all (variables);
            copy.redists.add_all (redists);
            copy.downloads.add_all (downloads);
            copy.steps.add_all (steps);
            copy.env.add_all (env);
            copy.confirm = confirm;
            copy.button = button;
            return copy;
        }
    }

}
