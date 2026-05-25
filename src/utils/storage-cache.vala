namespace Lumoria.Utils {

    public enum StorageCategory {
        RUNNERS,
        COMPONENTS,
        APP_DATA,
        PREFIXES,
        CACHE_RUNNERS,
        CACHE_COMPONENTS,
        CACHE_INSTALLER,
        CACHE_LAUNCHERS,
        CACHE_REDIST;

        public const int COUNT = 9;

        public string dir_path () {
            switch (this) {
                case RUNNERS:
                    return Utils.runner_dir ();
                case COMPONENTS:
                    return Utils.component_dir ();
                case APP_DATA:
                    return Utils.data_dir ();
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
        public signal void prefix_size_updated (string prefix_id, int64 bytes);

        private static StorageCache? _instance;

        private int64[] sizes;
        private bool[] valid;
        private bool[] pending;
        private Gee.HashMap<string, int64?> prefix_sizes;
        private int active_prefix_refresh = 0;

        private StorageCache () {
            sizes = new int64[StorageCategory.COUNT];
            valid = new bool[StorageCategory.COUNT];
            pending = new bool[StorageCategory.COUNT];
            prefix_sizes = new Gee.HashMap<string, int64?> ();
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

        public int64 get_prefix_size (string prefix_id) {
            if (!prefix_sizes.has_key (prefix_id)) return -1;
            return (int64) prefix_sizes[prefix_id];
        }

        public bool is_prefix_valid (string prefix_id) {
            return prefix_sizes.has_key (prefix_id);
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
            if (category == StorageCategory.PREFIXES) {
                active_prefix_refresh++;
                prefix_sizes.clear ();
            }
        }

        public void invalidate_all () {
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                valid[i] = false;
                pending[i] = false;
            }
            prefix_sizes.clear ();
            active_prefix_refresh++;
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

                if (cat == StorageCategory.APP_DATA) {
                    refresh_app_data (registry, cancellable);
                } else if (cat == StorageCategory.PREFIXES) {
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

        private void refresh_app_data (
            Models.PrefixRegistry? registry,
            Cancellable? cancellable
        ) {
            pending[StorageCategory.APP_DATA] = true;

            var data_excludes = new Gee.ArrayList<string> ();
            data_excludes.add (Utils.runner_dir ());
            data_excludes.add (Utils.component_dir ());
            if (registry != null) {
                foreach (var entry in registry.prefixes) {
                    var p = entry.resolved_path ();
                    if (p != "") data_excludes.add (p);
                }
            }

            var cache_excludes = new Gee.ArrayList<string> ();
            for (int i = 0; i < StorageCategory.COUNT; i++) {
                var cat = (StorageCategory) i;
                if (cat.is_cache ()) cache_excludes.add (cat.dir_path ());
            }

            new Thread<bool> ("disk-usage-app-data", () => {
                int64 total = 0;
                total += DiskUsage.calculate_excluding_sync (Utils.data_dir (), data_excludes, cancellable);
                if (cancellable != null && cancellable.is_cancelled ()) return true;
                total += DiskUsage.calculate_sync (Utils.config_dir (), cancellable);
                if (cancellable != null && cancellable.is_cancelled ()) return true;
                total += DiskUsage.calculate_excluding_sync (Utils.cache_dir (), cache_excludes, cancellable);
                if (cancellable != null && cancellable.is_cancelled ()) return true;
                Idle.add (() => {
                    if (cancellable != null && cancellable.is_cancelled ()) return false;
                    sizes[StorageCategory.APP_DATA] = total;
                    valid[StorageCategory.APP_DATA] = true;
                    pending[StorageCategory.APP_DATA] = false;
                    size_updated (StorageCategory.APP_DATA, total);
                    return false;
                });
                return true;
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
                prefix_sizes.clear ();
                size_updated (StorageCategory.PREFIXES, 0);
                return;
            }

            var entries = new Gee.ArrayList<Models.PrefixEntry> ();
            foreach (var entry in registry.prefixes) {
                var p = entry.resolved_path ();
                if (p != "") entries.add (entry);
            }
            if (entries.size == 0) {
                sizes[StorageCategory.PREFIXES] = 0;
                valid[StorageCategory.PREFIXES] = true;
                pending[StorageCategory.PREFIXES] = false;
                prefix_sizes.clear ();
                size_updated (StorageCategory.PREFIXES, 0);
                return;
            }

            active_prefix_refresh++;
            var refresh_id = active_prefix_refresh;
            var measured = new Gee.HashMap<string, int64?> ();
            var remaining = entries.size;

            foreach (var entry in entries) {
                var prefix_id = entry.id;
                var prefix_path = entry.resolved_path ();
                DiskUsage.calculate_async (prefix_path, cancellable, (path, bytes) => {
                    if (cancellable != null && cancellable.is_cancelled ()) return;
                    if (refresh_id != active_prefix_refresh) return;

                    measured[prefix_id] = bytes;
                    prefix_sizes[prefix_id] = bytes;
                    prefix_size_updated (prefix_id, bytes);

                    remaining--;
                    if (remaining > 0) return;

                    int64 total = 0;
                    foreach (var value in measured.values) {
                        total += (int64) value;
                    }

                    prefix_sizes = measured;
                    sizes[StorageCategory.PREFIXES] = total;
                    valid[StorageCategory.PREFIXES] = true;
                    pending[StorageCategory.PREFIXES] = false;
                    size_updated (StorageCategory.PREFIXES, total);
                });
            }
        }
    }
}
