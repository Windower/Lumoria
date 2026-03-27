namespace Lumoria.Models {

    public class ComponentSpec : InstallableSpec {
        public string github_repo { get; set; default = ""; }
        public string asset_regex { get; set; default = ""; }
        public string checksum_regex { get; set; default = ""; }
        public string default_version { get; set; default = "latest"; }
        public Gee.HashMap<string, string> system_env_defaults { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.HashMap<string, string> overrides { get; owned set; default = new Gee.HashMap<string, string> (); }

        public static ComponentSpec from_json (Json.Object obj) throws Error {
            var s = new ComponentSpec ();
            s.parse_installable (obj);
            s.github_repo = json_string (obj, "github_repo");
            s.asset_regex = json_string (obj, "asset_regex");
            s.checksum_regex = json_string (obj, "checksum_regex");
            s.default_version = json_string (obj, "default_version", "latest");
            s.system_env_defaults = json_string_map (obj, "system_env_defaults");
            s.overrides = json_string_map (obj, "overrides");
            return s;
        }

        public static Gee.ArrayList<ComponentSpec> load_all_from_resource () {
            return load_named_specs_from_resource<ComponentSpec> (
                "components",
                list_spec_ids_from_resource ("components"),
                "component",
                (obj, _) => {
                    return ComponentSpec.from_json (obj);
                }
            );
        }
    }
}
