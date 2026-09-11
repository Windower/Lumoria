namespace Lumoria.Models {

    public class ManifestStore : Object {
        private static string? overlay_dir;
        /* Per-thread override so a worker can validate a candidate tree without the main thread seeing it.
           Created on first use: static initialisers only run in class_init, which never fires for a
           class that is used purely statically. */
        private static GLib.Once<GLib.Private> validating_dir;

        private static unowned GLib.Private validating_slot () {
            return validating_dir.once (() => new GLib.Private ());
        }

        private static unowned string? active_overlay () {
            unowned string? validating = (string?) validating_slot ().get ();
            return validating ?? overlay_dir;
        }

        public static void validate_tree (string dir) throws Error {
            validating_slot ().set (dir);
            try {
                new ManifestRepository ().require_valid ();
            } finally {
                validating_slot ().set (null);
            }
        }

        public static void apply_startup_overlay () {
            if (overlay_dir != null) return;
            try_overlay (Environment.get_variable ("LUMORIA_MANIFESTS"));
        }

        private static bool try_overlay (string? path) {
            if (path == null) return false;
            var dir = path.strip ();
            if (dir == "") return false;
            if (!FileUtils.test (Path.build_filename (dir, "launchers"), FileTest.IS_DIR)) {
                return false;
            }
            overlay_dir = dir;
            debug ("Manifest overlay active at %s (index trust chain skipped)", dir);
            return true;
        }

        public static string cache_root () {
            return Path.build_filename (Utils.cache_dir (), "manifests");
        }

        public static string current_dir () {
            return Path.build_filename (cache_root (), "current");
        }

        public static string staging_dir () {
            return Path.build_filename (cache_root (), "staging");
        }

        public static string current_file (string relative_path) throws Error {
            return Utils.join_inside (current_dir (), relative_path);
        }

        public static string staging_file (string relative_path) throws Error {
            return Utils.join_inside (staging_dir (), relative_path);
        }

        public static void ensure_cache_dirs () throws Error {
            Utils.ensure_dir (current_dir ());
            Utils.ensure_dir (staging_dir ());
        }

        public static bool clear_cache () {
            var ok = true;
            if (FileUtils.test (cache_root (), FileTest.EXISTS)) {
                ok = Utils.remove_recursive (cache_root ());
            }
            return ok;
        }

        public static string[] list_ids (string subdir) {
            var ids = new Gee.TreeSet<string> ();
            collect_manifest_ids_from_resource (subdir, ids);
            var cache_subdir = Path.build_filename (active_overlay () ?? current_dir (), subdir);
            if (FileUtils.test (cache_subdir, FileTest.IS_DIR)) {
                try {
                    var dir = Dir.open (cache_subdir);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        if (name.has_suffix (".json")) {
                            ids.add (name.substring (0, name.length - 5));
                        }
                    }
                } catch (Error e) {
                    warning ("Failed to enumerate cached manifests in %s: %s", subdir, e.message);
                }
            }
            return Utils.strv (ids);
        }

        public static Json.Object load_object (string relative_path) throws Error {
            var overlay = overlay_file (relative_path);
            if (overlay != null) return parse_validated (relative_path, read_file (overlay));

            var cached = current_file (relative_path);
            if (FileUtils.test (cached, FileTest.IS_REGULAR)) {
                try {
                    return parse_validated (relative_path, read_file (cached));
                } catch (Error e) {
                    warning ("Ignoring invalid cached manifest %s: %s", relative_path, e.message);
                }
            }

            var json = load_resource_text (relative_path);
            if (json == null) {
                throw new IOError.FAILED ("Failed to load manifest %s", relative_path);
            }
            return parse_validated (relative_path, json);
        }

        public static string? resolve_cached (string relative_path) {
            var overlay = overlay_file (relative_path);
            if (overlay != null) return overlay;
            try {
                var cached = current_file (relative_path);
                return FileUtils.test (cached, FileTest.IS_REGULAR) ? cached : null;
            } catch (Error e) {
                return null;
            }
        }

        private static string? overlay_file (string relative_path) {
            unowned string? root = active_overlay ();
            if (root == null) return null;
            var path = Path.build_filename (root, relative_path);
            return FileUtils.test (path, FileTest.IS_REGULAR) ? path : null;
        }

        public static string? load_text (string relative_path, bool include_schemas = false) {
            var cached = resolve_cached (relative_path);
            if (cached != null) {
                try {
                    return read_file (cached);
                } catch (Error e) {
                    warning ("Failed to read cached manifest %s: %s", relative_path, e.message);
                }
            }
            return load_resource_text (relative_path, include_schemas);
        }

        private static Json.Object parse_validated (string relative_path, string json) throws Error {
            ManifestSchema.validate_relative (relative_path, json);
            return parse_data_object (json);
        }

        private static string read_file (string path) throws Error {
            string contents;
            FileUtils.get_contents (path, out contents);
            return contents;
        }

        private static string? load_resource_text (string relative_path, bool include_schemas = false) {
            var resource_path = include_schemas && relative_path.has_prefix ("schemas/")
                ? Config.RESOURCE_BASE + "/" + relative_path
                : Config.RESOURCE_BASE + "/manifests/" + relative_path;
            try {
                var bytes = GLib.resources_lookup_data (resource_path, 0);
                return (string) bytes.get_data ();
            } catch (Error e) {
                return null;
            }
        }

        public static string schema_kind_for_path (string relative_path) {
            if (relative_path == "manifest.json") return "index";
            if (relative_path == "defaults.json") return "defaults";
            if (relative_path == "catalog.json") return "catalog";
            if (relative_path == "resources.json") return "resources";
            if (relative_path.has_prefix ("installers/")) return "installer";
            if (relative_path.has_prefix ("launchers/")) return "launcher";
            if (relative_path.has_prefix ("redists/")) return "redist";
            if (relative_path.has_prefix ("runners/")) return "runner";
            if (relative_path.has_prefix ("components/")) return "component";
            if (relative_path.has_prefix ("schemas/")) return "";
            return "";
        }
    }
}
