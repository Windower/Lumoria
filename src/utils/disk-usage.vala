namespace Lumoria.Utils {

    public delegate void SizeReadyCallback (string path, int64 bytes);

    public class DiskUsage : Object {

        public static void calculate_async (
            string path,
            Cancellable? cancellable,
            owned SizeReadyCallback callback
        ) {
            var p = path;
            int64 total = 0;
            Utils.run_background ("disk-usage", () => {
                total = calculate_sync (p, cancellable);
            }, (error) => {
                if (cancellable != null && cancellable.is_cancelled ()) return;
                if (error != null) {
                    warning ("Disk usage failed for %s: %s", p, error.message);
                    callback (p, -1);
                    return;
                }
                callback (p, total);
            });
        }

        public static int64 calculate_sync (string path, Cancellable? cancellable) throws Error {
            return measure (path, null, cancellable);
        }

        public static int64 calculate_excluding_sync (
            string path,
            Gee.ArrayList<string> excluded_paths,
            Cancellable? cancellable
        ) throws Error {
            return measure (path, normalized_paths (excluded_paths), cancellable);
        }

        private static int64 measure (
            string path,
            Gee.ArrayList<string>? excluded_paths,
            Cancellable? cancellable
        ) throws Error {
            check_cancelled (cancellable);
            if (excluded_paths != null && is_excluded_path (path, excluded_paths)) return 0;

            var file = File.new_for_path (path);
            FileInfo info;
            try {
                info = file.query_info (
                    FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_SIZE,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    cancellable
                );
            } catch (IOError.NOT_FOUND e) {
                return 0;
            }

            if (info.get_file_type () != FileType.DIRECTORY) {
                return info.get_size ();
            }
            return walk_dir (file, excluded_paths, cancellable);
        }

        private static int64 walk_dir (
            File dir,
            Gee.ArrayList<string>? excluded_paths,
            Cancellable? cancellable
        ) throws Error {
            int64 total = 0;
            var enumerator = dir.enumerate_children (
                FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_SIZE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                cancellable
            );

            FileInfo? child_info;
            while ((child_info = enumerator.next_file (cancellable)) != null) {
                check_cancelled (cancellable);

                var child = enumerator.get_child (child_info);
                var child_path = child.get_path ();
                if (child_path != null && excluded_paths != null && is_excluded_path (child_path, excluded_paths)) {
                    continue;
                }

                if (child_info.get_file_type () == FileType.DIRECTORY) {
                    total += walk_dir (child, excluded_paths, cancellable);
                } else {
                    total += child_info.get_size ();
                }
            }
            enumerator.close (cancellable);
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
                if (Utils.path_within (p, excluded)) return true;
            }
            return false;
        }
    }
}
