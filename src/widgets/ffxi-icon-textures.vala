namespace Lumoria.Widgets {

    /*
     * Decoded FFXI icon textures, keyed by file path and capped as an LRU. texture () decodes on the
     * calling thread; request () hands back a cached texture or queues a background decode and emits
     * decoded () once the batch has landed in the cache.
     */
    public class FfxiIconTextures : Object {
        private const int LIMIT = 256;

        public signal void decoded ();

        private static FfxiIconTextures? _instance;
        private Models.FfxiIconCatalog catalog;
        private Gee.HashMap<string, Gdk.Texture> textures = new Gee.HashMap<string, Gdk.Texture> ();
        private Gee.ArrayList<string> order = new Gee.ArrayList<string> ();
        private Gee.HashSet<string> queued = new Gee.HashSet<string> ();
        private Utils.Debouncer flush;

        public static FfxiIconTextures instance () {
            if (_instance == null) _instance = new FfxiIconTextures ();
            return _instance;
        }

        construct {
            catalog = Models.FfxiIconCatalog.instance ();
            catalog.changed.connect (clear);
            flush = new Utils.Debouncer (0, decode_queued);
        }

        public Gdk.Texture? texture (string id) {
            var path = catalog.path_for (id);
            if (path == null) return null;
            if (textures.has_key (path)) {
                touch (path);
                return textures[path];
            }
            try {
                var tex = Gdk.Texture.from_filename (path);
                insert (path, tex);
                return tex;
            } catch (Error e) {
                warning ("Failed to load FFXI icon %s: %s", id, e.message);
                return null;
            }
        }

        public Gdk.Texture? request (string id) {
            var path = catalog.path_for (id);
            if (path == null) return null;
            if (textures.has_key (path)) {
                touch (path);
                return textures[path];
            }
            if (queued.add (path)) flush.schedule ();
            return null;
        }

        private void decode_queued () {
            if (queued.size == 0) return;
            var paths = new Gee.ArrayList<string> ();
            paths.add_all (queued);
            queued.clear ();

            var loaded = new Gee.HashMap<string, Gdk.Texture> ();
            Utils.run_background ("icon-decode", () => {
                foreach (var path in paths) {
                    try {
                        loaded[path] = Gdk.Texture.from_filename (path);
                    } catch (Error e) {
                        warning ("Failed to load FFXI icon %s: %s", path, e.message);
                    }
                }
            }, (error) => {
                foreach (var entry in loaded.entries) {
                    if (textures.has_key (entry.key)) touch (entry.key);
                    else insert (entry.key, entry.value);
                }
                if (loaded.size > 0) decoded ();
            });
        }

        private void insert (string path, Gdk.Texture tex) {
            textures[path] = tex;
            order.add (path);
            while (order.size > LIMIT) textures.unset (order.remove_at (0));
        }

        private void touch (string path) {
            order.remove (path);
            order.add (path);
        }

        private void clear () {
            textures.clear ();
            order.clear ();
            queued.clear ();
        }
    }
}
