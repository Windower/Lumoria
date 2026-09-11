namespace Lumoria.Models {

    public class ResourceEntry : Object {
        public string id { get; set; default = ""; }
        public string kind { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public string sha256 { get; set; default = ""; }
        public int64 size { get; set; default = 0; }
        public bool required { get; set; default = false; }

        public static ResourceEntry from_json (Json.Object obj) throws Error {
            var entry = new ResourceEntry ();
            entry.id = json_require_string (obj, "id");
            entry.kind = json_require_string (obj, "kind");
            entry.url = json_require_string (obj, "url");
            entry.sha256 = json_require_string (obj, "sha256").down ();
            entry.size = json_int (obj, "size");
            entry.required = json_bool (obj, "required");
            return entry;
        }
    }

    public class ResourceManifest : Object {
        public Gee.ArrayList<ResourceEntry> resources {
            get; owned set; default = new Gee.ArrayList<ResourceEntry> ();
        }

        public static ResourceManifest from_json (Json.Object obj) throws Error {
            var spec = new ResourceManifest ();
            spec.resources = parse_json_array<ResourceEntry> (obj, "resources", ResourceEntry.from_json);
            return spec;
        }

        public static ResourceManifest load () throws Error {
            return from_json (ManifestStore.load_object ("resources.json"));
        }
    }
}
