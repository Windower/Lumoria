namespace Lumoria.Models {

    public class RedistSpec : InstallableSpec {
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public bool defer { get; set; default = false; }

        public static RedistSpec from_json (Json.Object obj) throws Error {
            var s = new RedistSpec ();
            s.parse_installable (obj);
            s.redists = json_string_array (obj, "redists");
            s.defer = json_bool (obj, "defer", false);
            return s;
        }

        public static Gee.HashMap<string, RedistSpec> load_all_from_resource () {
            var specs = new Gee.HashMap<string, RedistSpec> ();
            var loaded = load_named_specs_from_resource<RedistSpec> (
                "redists",
                list_spec_ids_from_resource ("redists"),
                "redist",
                (obj, rid) => {
                    var spec = RedistSpec.from_json (obj);
                    if (spec.id == "") spec.id = rid;
                    return spec;
                }
            );
            foreach (var spec in loaded) {
                if (spec.id != "") {
                    specs[spec.id] = spec;
                }
            }
            return specs;
        }
    }
}
