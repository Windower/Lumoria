namespace Lumoria.Models {

    public class PostInstallSpec : InstallableSpec {
        public string version { get; set; default = ""; }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<EnvRule> variable_rules { get; owned set; default = new Gee.ArrayList<EnvRule> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<Entrypoint> entrypoints { get; owned set; default = new Gee.ArrayList<Entrypoint> (); }

        public static PostInstallSpec load_from_file (string path) throws Error {
            return from_json (parse_file_object (path));
        }

        public static PostInstallSpec from_json (Json.Object obj) throws Error {
            var s = new PostInstallSpec ();
            s.parse_installable (obj);
            s.version = json_string (obj, "version");
            Gee.HashMap<string, string> variables;
            Gee.ArrayList<EnvRule> variable_rules;
            Gee.ArrayList<Entrypoint> entrypoints;
            Gee.ArrayList<string> redists;
            s.parse_installable_supporting_fields (
                obj,
                out variables,
                out variable_rules,
                out entrypoints,
                out redists
            );
            s.variables = variables;
            s.variable_rules = variable_rules;
            s.entrypoints = entrypoints;
            s.redists = redists;
            return s;
        }
    }
}
