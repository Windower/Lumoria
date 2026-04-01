namespace Lumoria.Models {

    public class LauncherSpec : InstallableSpec {
        public string prefix { get; set; default = ""; }
        public bool is_default { get; set; default = false; }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<Entrypoint> entrypoints { get; owned set; default = new Gee.ArrayList<Entrypoint> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }

        public static LauncherSpec from_json (Json.Object obj) throws Error {
            var s = new LauncherSpec ();
            s.parse_installable (obj);
            s.prefix = json_string (obj, "prefix");
            s.is_default = json_bool (obj, "default");
            Gee.HashMap<string, string> variables;
            Gee.ArrayList<Entrypoint> entrypoints;
            Gee.ArrayList<string> redists;
            s.parse_installable_supporting_fields (obj, out variables, out entrypoints, out redists);
            s.variables = variables;
            s.entrypoints = entrypoints;
            s.redists = redists;
            return s;
        }

        public static Gee.ArrayList<LauncherSpec> load_all_from_resource () {
            return load_named_specs_from_resource<LauncherSpec> (
                "launchers",
                list_spec_ids_from_resource ("launchers"),
                "launcher",
                (obj, _) => {
                    return LauncherSpec.from_json (obj);
                }
            );
        }
    }
}
