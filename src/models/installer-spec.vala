namespace Lumoria.Models {
    public class InstallerRegion : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }

        public static InstallerRegion from_json (Json.Object obj) {
            var region = new InstallerRegion ();
            region.id = json_string (obj, "id");
            region.name = json_string (obj, "name", region.id);
            return region;
        }
    }

    public class InstallerPatch : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string patch_type { get; set; default = ""; }
        public string target { get; set; default = ""; }
        public string setting { get; set; default = ""; }
        public string flag { get; set; default = ""; }

        public static InstallerPatch from_json (Json.Object obj) {
            var patch = new InstallerPatch ();
            patch.id = json_string (obj, "id");
            patch.name = json_string (obj, "name", patch.id);
            patch.patch_type = json_string (obj, "type");
            patch.target = json_string (obj, "target");
            patch.setting = json_string (obj, "setting");
            patch.flag = json_string (obj, "flag");
            return patch;
        }
    }

    public class InstallerSpec : InstallableSpec {
        public string version { get; set; default = ""; }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<EnvRule> variable_rules { get; owned set; default = new Gee.ArrayList<EnvRule> (); }
        public Gee.ArrayList<Entrypoint> entrypoints { get; owned set; default = new Gee.ArrayList<Entrypoint> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<InstallerRegion> regions { get; owned set; default = new Gee.ArrayList<InstallerRegion> (); }
        public string default_region_id { get; set; default = ""; }
        public Gee.ArrayList<string> launcher_ids { get; owned set; default = new Gee.ArrayList<string> (); }
        public string default_launcher_id { get; set; default = ""; }
        public Gee.ArrayList<InstallerPatch> patches { get; owned set; default = new Gee.ArrayList<InstallerPatch> (); }

        public string effective_default_region_id () {
            if (default_region_id != "") return default_region_id;
            return regions.size > 0 ? regions[0].id : "";
        }

        public bool supports_launcher (string launcher_id) {
            return launcher_ids.contains (launcher_id);
        }

        public static InstallerSpec from_json (Json.Object obj) throws Error {
            var s = new InstallerSpec ();
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
            if (obj.has_member ("regions")) {
                var region_array = obj.get_array_member ("regions");
                for (uint i = 0; i < region_array.get_length (); i++) {
                    s.regions.add (InstallerRegion.from_json (region_array.get_object_element (i)));
                }
            }
            s.default_region_id = json_string (obj, "default_region");
            s.launcher_ids = json_string_array (obj, "launchers");
            s.default_launcher_id = json_string (obj, "default_launcher");
            if (obj.has_member ("patches")) {
                var patch_array = obj.get_array_member ("patches");
                for (uint i = 0; i < patch_array.get_length (); i++) {
                    s.patches.add (InstallerPatch.from_json (patch_array.get_object_element (i)));
                }
            }
            return s;
        }

        public static Gee.ArrayList<InstallerSpec> load_all_from_resource () {
            return load_named_specs_from_resource<InstallerSpec> (
                "installers",
                list_spec_ids_from_resource ("installers"),
                "installer",
                (obj, resource_id) => {
                    var spec = InstallerSpec.from_json (obj);
                    if (spec.id != resource_id) {
                        throw new IOError.FAILED (
                            "Installer resource '%s' declares id '%s'",
                            resource_id,
                            spec.id
                        );
                    }
                    return spec;
                }
            );
        }

        public static InstallerSpec? find_by_id (
            Gee.ArrayList<InstallerSpec> specs,
            string id
        ) {
            foreach (var spec in specs) {
                if (spec.id == id) return spec;
            }
            return null;
        }
    }
}
