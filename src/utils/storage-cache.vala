namespace Lumoria.Utils {

    public enum StorageCategory {
        RUNNERS,
        COMPONENTS,
        PREFIXES,
        CACHE_RUNNERS,
        CACHE_COMPONENTS,
        CACHE_INSTALLER,
        CACHE_LAUNCHERS,
        CACHE_REDIST;

        public const int COUNT = 8;

        public string dir_path () {
            switch (this) {
                case RUNNERS:
                    return Utils.runner_dir ();
                case COMPONENTS:
                    return Utils.component_dir ();
                case CACHE_RUNNERS:
                    return Path.build_filename (Utils.cache_dir (), "runners");
                case CACHE_COMPONENTS:
                    return Path.build_filename (Utils.cache_dir (), "components");
                case CACHE_INSTALLER:
                    return Path.build_filename (Utils.cache_dir (), "installer");
                case CACHE_LAUNCHERS:
                    return Path.build_filename (Utils.cache_dir (), "launchers");
                case CACHE_REDIST:
                    return Path.build_filename (Utils.cache_dir (), "redist");
                default:
                    return "";
            }
        }

        public bool is_cache () {
            switch (this) {
                case CACHE_RUNNERS:
                case CACHE_COMPONENTS:
                case CACHE_INSTALLER:
                case CACHE_LAUNCHERS:
                case CACHE_REDIST:
                    return true;
                default:
                    return false;
            }
        }
    }

    public class StorageCache : Object {
        public signal void size_updated (StorageCategory category, int64 bytes);

        private static StorageCache? _instance;

        private int64[] sizes;
        private bool[] valid;
        private bool[] pending;

        private StorageCache () {
            sizes = new int64[StorageCategory.COUNT];
            valid = new bool[StorageCategory.COUNT];
            pending = new bool[StorageCategory.COUNT];
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                sizes[i] = -1;
                valid[i] = false;
                pending[i] = false;
            }
        }

        public static StorageCache instance () {
            if (_instance == null) {
                _instance = new StorageCache ();
            }
            return _instance;
        }

        public int64 get_size (StorageCategory category) {
            return sizes[category];
        }

        public bool is_valid (StorageCategory category) {
            return valid[category];
        }

        public int64 total () {
            int64 sum = 0;
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                if (sizes[i] > 0) sum += sizes[i];
            }
            return sum;
        }

        public int64 cache_total () {
            int64 sum = 0;
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                if (((StorageCategory) i).is_cache () && sizes[i] > 0) {
                    sum += sizes[i];
                }
            }
            return sum;
        }

        public bool all_valid () {
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                if (!valid[i]) return false;
            }
            return true;
        }

        public void invalidate (StorageCategory category) {
            valid[category] = false;
            pending[category] = false;
        }

        public void invalidate_all () {
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                valid[i] = false;
                pending[i] = false;
            }
        }

        public void invalidate_all_cache () {
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                if (((StorageCategory) i).is_cache ()) {
                    valid[i] = false;
                    pending[i] = false;
                }
            }
        }

        public void refresh_if_needed (
            Models.PrefixRegistry? registry,
            Cancellable? cancellable
        ) {
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                var cat = (StorageCategory) i;
                if (valid[i] || pending[i]) continue;

                if (cat == StorageCategory.PREFIXES) {
                    refresh_prefixes (registry, cancellable);
                } else {
                    refresh_single (cat, cancellable);
                }
            }
        }

        private void refresh_single (StorageCategory cat, Cancellable? cancellable) {
            pending[cat] = true;
            var path = cat.dir_path ();

            DiskUsage.calculate_async (path, cancellable, (p, bytes) => {
                if (cancellable != null && cancellable.is_cancelled ()) return;
                sizes[cat] = bytes;
                valid[cat] = true;
                pending[cat] = false;
                size_updated (cat, bytes);
            });
        }

        private void refresh_prefixes (
            Models.PrefixRegistry? registry,
            Cancellable? cancellable
        ) {
            pending[StorageCategory.PREFIXES] = true;

            if (registry == null || registry.prefixes.size == 0) {
                sizes[StorageCategory.PREFIXES] = 0;
                valid[StorageCategory.PREFIXES] = true;
                pending[StorageCategory.PREFIXES] = false;
                size_updated (StorageCategory.PREFIXES, 0);
                return;
            }

            var paths = new Gee.ArrayList<string> ();
            foreach (var entry in registry.prefixes) {
                var p = entry.resolved_path ();
                if (p != "") paths.add (p);
            }

            DiskUsage.calculate_paths_async (paths, cancellable, (p, bytes) => {
                if (cancellable != null && cancellable.is_cancelled ()) return;
                sizes[StorageCategory.PREFIXES] = bytes;
                valid[StorageCategory.PREFIXES] = true;
                pending[StorageCategory.PREFIXES] = false;
                size_updated (StorageCategory.PREFIXES, bytes);
            });
        }
    }
}
