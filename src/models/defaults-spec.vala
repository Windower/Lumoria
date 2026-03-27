namespace Lumoria.Models {

    public class DefaultsSpec : Object {
        public string runner_id { get; set; default = ""; }
        public string runner_version { get; set; default = "latest"; }
        public string runner_id_sandbox { get; set; default = ""; }
        public string runner_version_sandbox { get; set; default = "latest"; }
        public bool wine_wayland { get; set; default = false; }
        public bool large_address_aware { get; set; default = false; }
        public Gee.HashMap<string, bool> component_enabled {
            get; owned set; default = new Gee.HashMap<string, bool> ();
        }

        public static DefaultsSpec from_json (Json.Object obj) {
            var spec = new DefaultsSpec ();

            if (obj.has_member ("default")) {
                var default_obj = obj.get_object_member ("default");
                if (default_obj.has_member ("runner")) {
                    var runner_obj = default_obj.get_object_member ("runner");
                    spec.runner_id = json_string (runner_obj, "id");
                    spec.runner_version = json_string (runner_obj, "version", "latest");
                }
                if (default_obj.has_member ("wine")) {
                    var wine_obj = default_obj.get_object_member ("wine");
                    spec.wine_wayland = json_bool (wine_obj, "wayland", false);
                }
                if (default_obj.has_member ("patches")) {
                    var patch_obj = default_obj.get_object_member ("patches");
                    spec.large_address_aware = json_bool (patch_obj, "large_address_aware", false);
                }
                if (default_obj.has_member ("components")) {
                    var comps_obj = default_obj.get_object_member ("components");
                    comps_obj.foreach_member ((_, cid, node) => {
                        var cnode = node.get_object ();
                        var val = json_bool_nullable (cnode, "enabled");
                        if (val != null) spec.component_enabled[cid] = (bool) val;
                    });
                }
            }

            if (obj.has_member ("environments")) {
                var env_obj = obj.get_object_member ("environments");
                if (env_obj.has_member ("sandbox")) {
                    var sandbox_obj = env_obj.get_object_member ("sandbox");
                    if (sandbox_obj.has_member ("runner")) {
                        var sandbox_runner_obj = sandbox_obj.get_object_member ("runner");
                        spec.runner_id_sandbox = json_string (sandbox_runner_obj, "id");
                        spec.runner_version_sandbox = json_string (sandbox_runner_obj, "version", "latest");
                    }
                }
            }

            // If sandbox runner is absent, keep base runner defaults.
            if (spec.runner_id_sandbox == "") {
                spec.runner_id_sandbox = spec.runner_id;
                spec.runner_version_sandbox = spec.runner_version;
            }

            return spec;
        }

        public static DefaultsSpec load_from_resource () {
            return load_single_spec_from_resource<DefaultsSpec> (
                "specs/defaults.json",
                "defaults",
                (obj) => {
                    return DefaultsSpec.from_json (obj);
                },
                new DefaultsSpec ()
            );
        }
    }
}
