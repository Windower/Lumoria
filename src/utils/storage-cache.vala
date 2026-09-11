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
        CACHE_REDIST,
        CACHE_REMOTE_MANIFESTS,
        CACHE_MANIFESTS;

        public const int COUNT = 11;

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
                case CACHE_REMOTE_MANIFESTS:
                    return Path.build_filename (Utils.cache_dir (), "remote-manifests");
                case CACHE_MANIFESTS:
                    return Path.build_filename (Utils.cache_dir (), "manifests");
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
                case CACHE_REMOTE_MANIFESTS:
                case CACHE_MANIFESTS:
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
                if (sizes[i] < 0) return -1;
                if (sizes[i] > 0) sum += sizes[i];
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

        public void drop_prefix (string prefix_id) {
            int64 lost = 0;
            if (prefix_sizes.has_key (prefix_id)) {
                lost = (int64) prefix_sizes[prefix_id];
                prefix_sizes.unset (prefix_id);
            }
            if (!valid[StorageCategory.PREFIXES]) return;
            if (lost > 0) {
                sizes[StorageCategory.PREFIXES] = int64.max (0, sizes[StorageCategory.PREFIXES] - lost);
            }
            size_updated (StorageCategory.PREFIXES, sizes[StorageCategory.PREFIXES]);
        }

        public void refresh_prefix (Models.PrefixEntry entry, Cancellable? cancellable = null) {
            var prefix_id = entry.id;
            var path = entry.resolved_path ();
            if (path == "") return;
            DiskUsage.calculate_async (path, cancellable, (measured_path, bytes) => {
                if (cancellable != null && cancellable.is_cancelled ()) return;
                int64 prev = prefix_sizes.has_key (prefix_id) ? (int64) prefix_sizes[prefix_id] : 0;
                prefix_sizes[prefix_id] = bytes;
                prefix_size_updated (prefix_id, bytes);
                if (!valid[StorageCategory.PREFIXES]) return;
                if (bytes < 0 || sizes[StorageCategory.PREFIXES] < 0) {
                    sizes[StorageCategory.PREFIXES] = -1;
                } else {
                    sizes[StorageCategory.PREFIXES] = int64.max (0, sizes[StorageCategory.PREFIXES] - int64.max (prev, 0) + bytes);
                }
                size_updated (StorageCategory.PREFIXES, sizes[StorageCategory.PREFIXES]);
            });
        }

        /* Deletes one cache subdirectory off the UI thread and invalidates its size once done. */
        public void clear_cache_async (StorageCategory category, string subdir, owned BackgroundDone? on_done = null) {
            var path = Path.build_filename (Utils.cache_dir (), subdir);
            run_background ("cache-clear", () => remove_or_throw (path), (error) => {
                invalidate (category);
                if (on_done != null) on_done (error);
            });
        }

        /* Deletes the whole cache directory and drops every cached size that depended on it. */
        public void clear_all_cache_async (owned BackgroundDone? on_done = null) {
            run_background ("cache-clear", () => remove_or_throw (Utils.cache_dir ()), (error) => {
                for (int i = 0; i < StorageCategory.COUNT; i++) {
                    if (((StorageCategory) i).is_cache ()) invalidate ((StorageCategory) i);
                }
                invalidate (StorageCategory.APP_DATA);
                if (on_done != null) on_done (error);
            });
        }

        private static void remove_or_throw (string path) throws Error {
            if (!Utils.remove_recursive (path)) {
                throw new LumoriaError.FAILED (_("Failed to clear some cache files."));
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

            int64 total = 0;
            Utils.run_background ("disk-usage-app-data", () => {
                total += DiskUsage.calculate_excluding_sync (Utils.data_dir (), data_excludes, cancellable);
                if (cancellable != null && cancellable.is_cancelled ()) return;
                total += DiskUsage.calculate_sync (Utils.config_dir (), cancellable);
                if (cancellable != null && cancellable.is_cancelled ()) return;
                total += DiskUsage.calculate_excluding_sync (Utils.cache_dir (), cache_excludes, cancellable);
            }, (error) => {
                if (cancellable != null && cancellable.is_cancelled ()) return;
                if (error != null) {
                    warning ("Disk usage failed for app data: %s", error.message);
                    total = -1;
                }
                sizes[StorageCategory.APP_DATA] = total;
                valid[StorageCategory.APP_DATA] = true;
                pending[StorageCategory.APP_DATA] = false;
                size_updated (StorageCategory.APP_DATA, total);
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
                        if ((int64) value < 0) {
                            total = -1;
                            break;
                        }
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
