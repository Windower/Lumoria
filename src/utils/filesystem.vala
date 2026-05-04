namespace Lumoria.Utils {

    public delegate void CopyFileCallback (string src_path, string dst_path);

    public static bool ensure_dir (string path) {
        return DirUtils.create_with_parents (path, 0755) == 0;
    }

    public static bool remove_recursive (string path) {
        try {
            var file = File.new_for_path (path);
            if (!file.query_exists ()) return true;

            var info = file.query_info (FileAttribute.STANDARD_TYPE, FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            if (info.get_file_type () == FileType.DIRECTORY) {
                var enumerator = file.enumerate_children (
                    FileAttribute.STANDARD_NAME,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                );
                FileInfo? child_info;
                while ((child_info = enumerator.next_file ()) != null) {
                    var child_path = Path.build_filename (path, child_info.get_name ());
                    remove_recursive (child_path);
                }
                enumerator.close ();
            }
            file.delete ();
            return true;
        } catch (Error e) {
            warning ("Failed to remove %s: %s", path, e.message);
            return false;
        }
    }

    public static string[] arraylist_to_strv (Gee.ArrayList<string> list) {
        var arr = new string[list.size + 1];
        for (int i = 0; i < list.size; i++) {
            arr[i] = list[i];
        }
        arr[list.size] = null;
        return arr;
    }

    public static Gee.ArrayList<string> list_dirs (string path) {
        var dirs = new Gee.ArrayList<string> ();
        try {
            var dir = Dir.open (path);
            string? name;
            while ((name = dir.read_name ()) != null) {
                var full = Path.build_filename (path, name);
                if (FileUtils.test (full, FileTest.IS_DIR)) {
                    dirs.add (name);
                }
            }
        } catch (FileError e) {
            warning ("Failed to list directories in %s: %s", path, e.message);
        }
        return dirs;
    }

    public static int64 file_size_or_zero (string path) {
        try {
            return File.new_for_path (path)
                .query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE)
                .get_size ();
        } catch (Error e) {
            warning ("file_size_or_zero: failed to query %s: %s", path, e.message);
            return 0;
        }
    }

    public static void copy_path (string src, string dst, CopyFileCallback? on_file = null) throws Error {
        if (FileUtils.test (src, FileTest.IS_DIR)) {
            var src_treated_as_contents = src.has_suffix ("/");
            var src_clean = strip_trailing_slashes (src);
            var nest_into_existing_dir = !src_treated_as_contents && FileUtils.test (dst, FileTest.IS_DIR);
            var actual_dst = nest_into_existing_dir
                ? Path.build_filename (dst, Path.get_basename (src_clean))
                : dst;
            copy_dir_recursive (src_clean, actual_dst, on_file);
            return;
        }

        var dst_base = Path.get_basename (dst);
        var is_dir_dest = FileUtils.test (dst, FileTest.IS_DIR)
            || (!dst_base.contains (".") && !FileUtils.test (dst, FileTest.EXISTS));
        if (is_dir_dest) {
            ensure_dir (dst);
            var file_dst = Path.build_filename (dst, Path.get_basename (src));
            copy_file (src, file_dst);
            if (on_file != null) on_file (src, file_dst);
        } else {
            ensure_dir (Path.get_dirname (dst));
            copy_file (src, dst);
            if (on_file != null) on_file (src, dst);
        }
    }

    private static string strip_trailing_slashes (string path) {
        var s = path;
        while (s.length > 1 && s.has_suffix ("/")) {
            s = s.substring (0, s.length - 1);
        }
        return s;
    }

    private static void copy_dir_recursive (string src, string dst, CopyFileCallback? on_file) throws Error {
        ensure_dir (dst);
        var dir = Dir.open (src);
        string? name;
        while ((name = dir.read_name ()) != null) {
            var src_path = Path.build_filename (src, name);
            var dst_path = Path.build_filename (dst, name);
            if (FileUtils.test (src_path, FileTest.IS_DIR)) {
                copy_dir_recursive (src_path, dst_path, on_file);
            } else {
                copy_file (src_path, dst_path);
                if (on_file != null) on_file (src_path, dst_path);
            }
        }
    }

    private static void copy_file (string src, string dst) throws Error {
        ensure_dir (Path.get_dirname (dst));
        var source = File.new_for_path (src);
        var dest = File.new_for_path (dst);
        source.copy (dest, FileCopyFlags.OVERWRITE);
    }
}
