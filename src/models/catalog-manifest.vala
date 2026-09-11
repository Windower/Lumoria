namespace Lumoria.Models {

    public delegate string CatalogItemId<T> (T item);

    public class CatalogManifest : Object {
        public Gee.ArrayList<string> runners {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public Gee.ArrayList<string> components {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public Gee.ArrayList<string> redists {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public string default_installer { get; set; default = ""; }

        public static CatalogManifest from_json (Json.Object obj) throws Error {
            var catalog = new CatalogManifest ();
            catalog.default_installer = json_require_string (obj, "default_installer");
            catalog.runners = json_string_array (obj, "runners");
            catalog.components = json_string_array (obj, "components");
            catalog.redists = json_string_array (obj, "redists");
            return catalog;
        }

        public static CatalogManifest load () throws Error {
            return from_json (ManifestStore.load_object ("catalog.json"));
        }

        public static Gee.ArrayList<T> select<T> (
            Gee.List<T> items,
            Gee.List<string> ids,
            CatalogItemId<T> get_id
        ) {
            var by_id = new Gee.HashMap<string, T> ();
            foreach (var item in items) {
                var id = get_id (item);
                if (id == "" || by_id.has_key (id)) continue;
                by_id[id] = item;
            }

            if (ids.size == 0) {
                return new Gee.ArrayList<T> ();
            }

            var selected = new Gee.ArrayList<T> ();
            var seen = new Gee.HashSet<string> ();
            foreach (var id in ids) {
                if (!seen.add (id)) continue;
                if (!by_id.has_key (id)) continue;
                selected.add (by_id[id]);
            }
            return selected;
        }
    }
}
