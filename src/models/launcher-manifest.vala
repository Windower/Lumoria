namespace Lumoria.Models {

    public class LauncherManifest : InstallableManifest {
        public bool is_default { get; set; default = false; }

        public static LauncherManifest from_json (Json.Object obj) throws Error {
            var s = new LauncherManifest ();
            s.parse_installable (obj);
            s.is_default = json_bool (obj, "default");
            return s;
        }

        public static Gee.ArrayList<LauncherManifest> load_all_from_resource () throws Error {
            return load_named_manifests_from_resource<LauncherManifest> (
                "launchers",
                ManifestStore.list_ids ("launchers"),
                "launcher",
                (obj, _) => {
                    return LauncherManifest.from_json (obj);
                }
            );
        }
    }
}
