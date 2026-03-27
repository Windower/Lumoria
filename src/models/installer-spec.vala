namespace Lumoria.Models {

    public class InstallerSpec : InstallableSpec {
        public string version { get; set; default = ""; }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<Entrypoint> entrypoints { get; owned set; default = new Gee.ArrayList<Entrypoint> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }

        public static InstallerSpec load_from_resource () {
            return load_single_spec_from_resource<InstallerSpec> (
                "specs/installer.json",
                "installer",
                (obj) => {
                    return InstallerSpec.from_json (obj);
                },
                new InstallerSpec ()
            );
        }

        public static InstallerSpec from_json (Json.Object obj) throws Error {
            var s = new InstallerSpec ();
            s.parse_installable (obj);
            s.version = json_string (obj, "version");
            s.variables = json_string_map (obj, "variables");
            s.entrypoints = parse_entrypoints (obj);
            s.redists = json_string_array (obj, "redists");
            return s;
        }
    }
}
