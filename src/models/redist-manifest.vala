namespace Lumoria.Models {

    public class RedistManifest : InstallableManifest {
        public bool defer { get; set; default = false; }
        public string category { get; set; default = ""; }

        public string package_category () {
            if (category != "") return category;
            foreach (var step in steps) {
                if (step.step_type == InstallStepKind.FONTS || step.step_type == InstallStepKind.FONT_REPLACEMENT) {
                    return "fonts";
                }
            }
            var key = id.down ();
            var title = display_label ().down ();
            if (key.has_prefix ("dotnet")) return "dotnet";
            if (key.has_prefix ("vcrun")) return "vcrun";
            if (key.has_prefix ("d3d")) return "directx";
            if (key.contains ("font") || title.contains ("font")) return "fonts";
            return "other";
        }

        public static string package_category_label (string key) {
            switch (key) {
                case "dotnet": return _(".NET");
                case "vcrun": return _("Visual C++");
                case "directx": return _("DirectX");
                case "fonts": return _("Fonts");
                default: return _("Other");
            }
        }

        public static int package_category_rank (string key) {
            switch (key) {
                case "dotnet": return 0;
                case "vcrun": return 1;
                case "directx": return 2;
                case "other": return 3;
                case "fonts": return 4;
                default: return 5;
            }
        }

        public static RedistManifest from_json (Json.Object obj) throws Error {
            var s = new RedistManifest ();
            s.parse_installable (obj);
            s.defer = json_bool (obj, "defer", false);
            s.category = json_string (obj, "category");
            return s;
        }

        public static Gee.HashMap<string, RedistManifest> load_all_from_resource () throws Error {
            var specs = new Gee.HashMap<string, RedistManifest> ();
            var loaded = load_named_manifests_from_resource<RedistManifest> (
                "redists",
                ManifestStore.list_ids ("redists"),
                "redist",
                (obj, rid) => {
                    var spec = RedistManifest.from_json (obj);
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
