namespace Lumoria.Utils {

    public delegate void SizeReadyCallback (string path, int64 bytes);

    public class DiskUsage : Object {

        public static void calculate_async (
            string path,
            Cancellable? cancellable,
            owned SizeReadyCallback callback
        ) {
            var p = path;
            new Thread<bool> ("disk-usage", () => {
                int64 total = calculate_sync (p, cancellable);
                if (cancellable != null && cancellable.is_cancelled ()) return true;
                var cb = (owned) callback;
                var pp = p;
                Idle.add (() => {
                    cb (pp, total);
                    return false;
                });
                return true;
            });
        }

        public static void calculate_paths_async (
            Gee.ArrayList<string> paths,
            Cancellable? cancellable,
            owned SizeReadyCallback callback
        ) {
            var owned_paths = paths;
            new Thread<bool> ("disk-usage-multi", () => {
                int64 total = 0;
                foreach (var p in owned_paths) {
                    if (cancellable != null && cancellable.is_cancelled ()) return true;
                    total += calculate_sync (p, cancellable);
                }
                if (cancellable != null && cancellable.is_cancelled ()) return true;
                var cb = (owned) callback;
                Idle.add (() => {
                    cb ("", total);
                    return false;
                });
                return true;
            });
        }

        public static void calculate_excluding_async (
            string path,
            Gee.ArrayList<string> excluded_paths,
            Cancellable? cancellable,
            owned SizeReadyCallback callback
        ) {
            var p = path;
            var excludes = normalized_paths (excluded_paths);
            new Thread<bool> ("disk-usage-excluding", () => {
                int64 total = calculate_excluding_sync (p, excludes, cancellable);
                if (cancellable != null && cancellable.is_cancelled ()) return true;
                var cb = (owned) callback;
                var pp = p;
                Idle.add (() => {
                    cb (pp, total);
                    return false;
                });
                return true;
            });
        }

        public static int64 calculate_sync (string path, Cancellable? cancellable) {
            try {
                var file = File.new_for_path (path);
                if (!file.query_exists ()) return 0;

                var info = file.query_info (
                    FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_SIZE,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                );

                if (info.get_file_type () != FileType.DIRECTORY) {
                    return info.get_size ();
                }

                return walk_dir (file, cancellable);
            } catch (Error e) {
                return 0;
            }
        }

        public static int64 calculate_excluding_sync (
            string path,
            Gee.ArrayList<string> excluded_paths,
            Cancellable? cancellable
        ) {
            try {
                if (is_excluded_path (path, excluded_paths)) return 0;

                var file = File.new_for_path (path);
                if (!file.query_exists ()) return 0;

                var info = file.query_info (
                    FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_SIZE,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                );

                if (info.get_file_type () != FileType.DIRECTORY) {
                    return info.get_size ();
                }

                return walk_dir_excluding (file, excluded_paths, cancellable);
            } catch (Error e) {
                return 0;
            }
        }

        private static int64 walk_dir (File dir, Cancellable? cancellable) throws Error {
            int64 total = 0;
            var enumerator = dir.enumerate_children (
                FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_SIZE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS
            );

            FileInfo? child_info;
            while ((child_info = enumerator.next_file ()) != null) {
                if (cancellable != null && cancellable.is_cancelled ()) break;

                if (child_info.get_file_type () == FileType.DIRECTORY) {
                    total += walk_dir (enumerator.get_child (child_info), cancellable);
                } else {
                    total += child_info.get_size ();
                }
            }
            enumerator.close ();
            return total;
        }

        private static int64 walk_dir_excluding (
            File dir,
            Gee.ArrayList<string> excluded_paths,
            Cancellable? cancellable
        ) throws Error {
            int64 total = 0;
            var enumerator = dir.enumerate_children (
                FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_SIZE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS
            );

            FileInfo? child_info;
            while ((child_info = enumerator.next_file ()) != null) {
                if (cancellable != null && cancellable.is_cancelled ()) break;

                var child = enumerator.get_child (child_info);
                var child_path = child.get_path ();
                if (child_path != null && is_excluded_path (child_path, excluded_paths)) continue;

                if (child_info.get_file_type () == FileType.DIRECTORY) {
                    total += walk_dir_excluding (child, excluded_paths, cancellable);
                } else {
                    total += child_info.get_size ();
                }
            }
            enumerator.close ();
            return total;
        }

        private static Gee.ArrayList<string> normalized_paths (Gee.ArrayList<string> paths) {
            var normalized = new Gee.ArrayList<string> ();
            foreach (var path in paths) {
                var p = Utils.normalize_dir_path (path);
                if (p != "") normalized.add (p);
            }
            return normalized;
        }

        private static bool is_excluded_path (string path, Gee.ArrayList<string> excluded_paths) {
            var p = Utils.normalize_dir_path (path);
            foreach (var excluded in excluded_paths) {
                if (p == excluded || p.has_prefix (excluded + "/")) return true;
            }
            return false;
        }
    }
}
