namespace Lumoria.Models {
    public class InstallerRegion : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }

        public static InstallerRegion from_json (Json.Object obj) throws Error {
            var region = new InstallerRegion ();
            region.id = json_require_string (obj, "id");
            region.name = json_string (obj, "name", region.id);
            return region;
        }
    }

    public class InstallerPatch : Object {
        public const string SETTING_LARGE_ADDRESS_AWARE = "large_address_aware";

        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string patch_type { get; set; default = ""; }
        public string target { get; set; default = ""; }
        public string setting { get; set; default = ""; }
        public string flag { get; set; default = ""; }

        public static InstallerPatch from_json (Json.Object obj) throws Error {
            var patch = new InstallerPatch ();
            patch.id = json_require_string (obj, "id");
            patch.name = json_string (obj, "name", patch.id);
            patch.patch_type = json_string (obj, "type");
            patch.target = json_string (obj, "target");
            patch.setting = json_string (obj, "setting");
            patch.flag = json_string (obj, "flag");
            return patch;
        }
    }

    public class InstallerManifest : InstallableManifest {
        public const string EMPTY_ID = "empty-wine-prefix";

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

        public Gee.ArrayList<LauncherManifest> ordered_launchers (Gee.List<LauncherManifest> catalog) {
            var by_id = new Gee.HashMap<string, LauncherManifest> ();
            foreach (var launcher in catalog) {
                by_id[launcher.id] = launcher;
            }
            var ordered = new Gee.ArrayList<LauncherManifest> ();
            foreach (var id in launcher_ids) {
                var launcher = by_id[id];
                if (launcher != null) ordered.add (launcher);
            }
            return ordered;
        }

        public static Gee.ArrayList<LauncherManifest> order_launchers (
            Gee.List<InstallerManifest> installers,
            Gee.List<LauncherManifest> launchers
        ) {
            var by_id = new Gee.HashMap<string, LauncherManifest> ();
            foreach (var launcher in launchers) {
                by_id[launcher.id] = launcher;
            }
            var ordered = new Gee.ArrayList<LauncherManifest> ();
            var seen = new Gee.HashSet<string> ();
            foreach (var installer in installers) {
                foreach (var id in installer.launcher_ids) {
                    if (!seen.add (id)) continue;
                    var launcher = by_id[id];
                    if (launcher != null) ordered.add (launcher);
                }
            }
            foreach (var launcher in launchers) {
                if (seen.add (launcher.id)) ordered.add (launcher);
            }
            return ordered;
        }

        public static InstallerManifest from_json (Json.Object obj) throws Error {
            var s = new InstallerManifest ();
            s.parse_installable (obj);
            s.regions = parse_json_array<InstallerRegion> (obj, "regions", (o) => InstallerRegion.from_json (o));
            s.default_region_id = json_string (obj, "default_region");
            s.launcher_ids = json_string_array (obj, "launchers");
            s.default_launcher_id = json_string (obj, "default_launcher");
            s.patches = parse_json_array<InstallerPatch> (obj, "patches", (o) => InstallerPatch.from_json (o));
            return s;
        }

        public static Gee.ArrayList<InstallerManifest> load_all_from_resource () throws Error {
            return load_named_manifests_from_resource<InstallerManifest> (
                "installers",
                ManifestStore.list_ids ("installers"),
                "installer",
                (obj, resource_id) => {
                    var spec = InstallerManifest.from_json (obj);
                    if (spec.id != resource_id) {
                        throw new LumoriaError.INVALID_MANIFEST (
                            "Installer resource '%s' declares id '%s'",
                            resource_id,
                            spec.id
                        );
                    }
                    return spec;
                }
            );
        }

    }
}
