namespace Lumoria.Models {

    public class PostInstallSpec : InstallableSpec {
        public string version { get; set; default = ""; }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<Entrypoint> entrypoints { get; owned set; default = new Gee.ArrayList<Entrypoint> (); }

        public static PostInstallSpec load_from_file (string path) throws Error {
            return from_json (parse_file_object (path));
        }

        public static PostInstallSpec from_json (Json.Object obj) throws Error {
            var s = new PostInstallSpec ();
            s.parse_installable (obj);
            s.version = json_string (obj, "version");
            s.variables = json_string_map (obj, "variables");
            s.redists = json_string_array (obj, "redists");
            s.entrypoints = parse_entrypoints (obj);
            return s;
        }
    }
}
