namespace Lumoria.Utils {

    public delegate void CopyFileCallback (string src_path, string dst_path);

    public static void check_cancelled (Cancellable? cancellable) throws IOError {
        if (cancellable != null) cancellable.set_error_if_cancelled ();
    }

    /* Gee's to_array () is not NULL-terminated; execvp, spawn and string.joinv all require it. */
    public static string[] strv (Gee.Collection<string> items) {
        var array = new string[items.size];
        int i = 0;
        foreach (var item in items) array[i++] = item;
        return array;
    }

    public static void ensure_dir (string path) throws Error {
        if (DirUtils.create_with_parents (path, 0755) != 0) {
            throw new IOError.FAILED (
                "Failed to create directory %s: %s",
                path,
                Posix.strerror (Posix.errno)
            );
        }
    }

    public static void ensure_private_dir (string path) throws Error {
        if (DirUtils.create_with_parents (path, 0700) != 0) {
            throw new IOError.FAILED (
                "Failed to create directory %s: %s",
                path,
                Posix.strerror (Posix.errno)
            );
        }
        if (FileUtils.chmod (path, 0700) != 0) {
            throw new IOError.FAILED (
                "Failed to restrict %s: %s",
                path,
                Posix.strerror (Posix.errno)
            );
        }
    }

    public static void write_text_atomic (string path, string contents, int mode = -1) throws Error {
        write_bytes_atomic (path, contents.data, mode);
    }

    /* Temp file, fsync and rename; mode is applied exactly (not masked) when given. */
    public static void write_bytes_atomic (string path, uint8[] data, int mode = -1) throws Error {
        ensure_dir (Path.get_dirname (path));
        FileUtils.set_contents_full (
            path, (string) data, data.length,
            FileSetContentsFlags.CONSISTENT | FileSetContentsFlags.DURABLE,
            mode >= 0 ? mode : 0666
        );
        if (mode >= 0 && FileUtils.chmod (path, mode) != 0) {
            throw new IOError.FAILED ("Failed to set mode on %s: %s", path, Posix.strerror (Posix.errno));
        }
    }

    public static void write_json_atomic (string path, Json.Object obj) throws Error {
        write_text_atomic (path, Models.json_object_to_string (obj, true));
    }

    public static void write_validated_json (string path, string schema, Json.Object obj) throws Error {
        var json = Models.json_object_to_string (obj, true);
        Models.ManifestSchema.validate_json (schema, json);
        write_text_atomic (path, json);
    }

    /* Null when the file does not exist. */
    public static Json.Object? read_validated_json (string path, string schema) throws Error {
        string json;
        if (!read_user_text (path, out json)) return null;
        Models.ManifestSchema.validate_json (schema, json);
        return Models.parse_data_object (json);
    }

    public static bool read_user_text (string path, out string contents) throws Error {
        contents = "";
        if (!FileUtils.test (path, FileTest.IS_REGULAR)) return false;
        FileUtils.get_contents (path, out contents);
        return true;
    }

    /* Moves the file aside as .broken; the caller then persists defaults so the next launch is clean. */
    public static void quarantine_broken_file (string path) {
        if (!FileUtils.test (path, FileTest.EXISTS)) return;
        var dest = path + ".broken";
        try {
            File.new_for_path (path).move (File.new_for_path (dest), FileCopyFlags.OVERWRITE);
        } catch (Error e) {
            warning ("Failed to quarantine %s: %s", path, e.message);
        }
    }

    /* Keeps a copy as .broken while the live file is rewritten without the entries that failed. */
    public static void preserve_broken_copy (string path) {
        try {
            File.new_for_path (path).copy (File.new_for_path (path + ".broken"), FileCopyFlags.OVERWRITE);
        } catch (Error e) {
            warning ("Failed to preserve a copy of %s: %s", path, e.message);
        }
    }

    /* Swaps staged into dest, keeping the previous tree until the new one is in place. */
    public static void replace_dir_atomic (string staged, string dest, string failure_message) throws Error {
        ensure_dir (Path.get_dirname (dest));
        var backup = dest + ".old";
        var had_previous = FileUtils.test (dest, FileTest.EXISTS);
        if (had_previous) {
            remove_recursive (backup);
            if (FileUtils.rename (dest, backup) != 0) throw new LumoriaError.FAILED (failure_message);
        }
        if (FileUtils.rename (staged, dest) != 0) {
            if (had_previous) FileUtils.rename (backup, dest);
            throw new LumoriaError.FAILED (failure_message);
        }
        if (had_previous) remove_recursive (backup);
    }

    public static bool remove_recursive (string path) {
        if (path == "" || path == "/") return false;
        var exists = FileUtils.test (path, FileTest.EXISTS);
        var is_link = FileUtils.test (path, FileTest.IS_SYMLINK);
        if (!exists && !is_link) return true;
        if (is_link || !FileUtils.test (path, FileTest.IS_DIR)) {
            if (Posix.unlink (path) != 0) {
                warning ("Failed to unlink %s: %s", path, Posix.strerror (Posix.errno));
                return false;
            }
            return true;
        }

        var ok = true;
        try {
            var dir = Dir.open (path);
            string? name;
            while ((name = dir.read_name ()) != null) {
                if (name == "." || name == "..") continue;
                if (!remove_recursive (Path.build_filename (path, name))) ok = false;
            }
        } catch (FileError e) {
            warning ("Failed to list %s: %s", path, e.message);
            return false;
        }
        if (Posix.rmdir (path) != 0) {
            warning ("Failed to rmdir %s: %s", path, Posix.strerror (Posix.errno));
            return false;
        }
        return ok;
    }

    public static void ensure_indexer_ignore (string dir) {
        if (dir == "" || dir == "/") return;
        try {
            ensure_dir (dir);
        } catch (Error e) {
            warning ("Failed to create %s: %s", dir, e.message);
            return;
        }
        touch_empty (Path.build_filename (dir, ".nomedia"));
        touch_empty (Path.build_filename (dir, ".trackerignore"));
    }

    private static void touch_empty (string path) {
        if (FileUtils.test (path, FileTest.EXISTS)) return;
        try {
            FileUtils.set_contents (path, "");
        } catch (Error e) {
            warning ("Failed to write %s: %s", path, e.message);
        }
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
        } catch (IOError.NOT_FOUND e) {
            return 0;
        } catch (Error e) {
            warning ("file_size_or_zero: failed to query %s: %s", path, e.message);
            return 0;
        }
    }

    public static bool is_link_mode (string mode) {
        var normalized = mode.down ().strip ();
        return normalized == "symlink" || normalized == "hardlink";
    }

    public static bool is_symlink_to (string path, string target) {
        try {
            var info = File.new_for_path (path).query_info (
                FileAttribute.STANDARD_SYMLINK_TARGET,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS
            );
            var link_target = info.get_symlink_target ();
            return link_target == target;
        } catch (Error e) {
            warning ("Failed to read symlink %s: %s", path, e.message);
            return false;
        }
    }

    public static bool remove_file_or_symlink (string path) throws Error {
        var is_symlink = FileUtils.test (path, FileTest.IS_SYMLINK);
        var exists = FileUtils.test (path, FileTest.EXISTS);
        if (!is_symlink && !exists) return false;
        if (!is_symlink && FileUtils.test (path, FileTest.IS_DIR)) return false;
        if (FileUtils.remove (path) != 0) {
            throw new IOError.FAILED (
                "Failed to remove %s: %s",
                path,
                Posix.strerror (Posix.errno)
            );
        }
        return true;
    }

    public static void link_file (
        string src,
        string dst,
        string mode,
        bool replace_existing = false
    ) throws Error {
        var normalized = mode.down ().strip ();
        if (normalized == "") normalized = "symlink";
        if (!is_link_mode (normalized)) {
            throw new IOError.FAILED ("Invalid link mode: %s", mode);
        }
        if (!FileUtils.test (src, FileTest.EXISTS)) {
            throw new IOError.FAILED ("Link source missing: %s", src);
        }

        ensure_dir (Path.get_dirname (dst));
        if (FileUtils.test (dst, FileTest.EXISTS) || FileUtils.test (dst, FileTest.IS_SYMLINK)) {
            if (!replace_existing) {
                throw new IOError.FAILED ("Link target exists: %s", dst);
            }
            remove_file_or_symlink (dst);
        }

        if (normalized == "hardlink") {
            if (Posix.link (src, dst) != 0) {
                throw new IOError.FAILED (
                    "Hardlink failed: %s -> %s: %s",
                    src,
                    dst,
                    Posix.strerror (Posix.errno)
                );
            }
        } else if (FileUtils.symlink (src, dst) != 0) {
            throw new IOError.FAILED (
                "Symlink failed: %s -> %s: %s",
                src,
                dst,
                Posix.strerror (Posix.errno)
            );
        }
    }

    public static string resolve_copy_file_destination (string src, string dst) {
        var src_basename = Path.get_basename (src);
        if (src_basename == "" || src_basename == ".") return "";

        var dst_base = Path.get_basename (dst);
        var is_dir_dest = FileUtils.test (dst, FileTest.IS_DIR)
            || (!dst_base.contains (".") && !FileUtils.test (dst, FileTest.EXISTS));
        return is_dir_dest ? Path.build_filename (dst, src_basename) : dst;
    }

    public static void copy_path (
        string src,
        string dst,
        CopyFileCallback? on_file = null,
        Cancellable? cancellable = null
    ) throws Error {
        check_cancelled (cancellable);
        if (FileUtils.test (src, FileTest.IS_DIR)) {
            var src_treated_as_contents = src.has_suffix ("/");
            var src_clean = normalize_dir_path (src);
            var nest_into_existing_dir = !src_treated_as_contents && FileUtils.test (dst, FileTest.IS_DIR);
            var actual_dst = nest_into_existing_dir
                ? Path.build_filename (dst, Path.get_basename (src_clean))
                : dst;
            copy_dir_recursive (src_clean, actual_dst, on_file, cancellable);
            return;
        }

        var file_dst = resolve_copy_file_destination (src, dst);
        if (file_dst == "") {
            throw new IOError.FAILED ("copy source has no filename: %s", src);
        }
        ensure_dir (Path.get_dirname (file_dst));
        copy_file (src, file_dst, cancellable);
        if (on_file != null) on_file (src, file_dst);
    }

    private static void copy_dir_recursive (
        string src,
        string dst,
        CopyFileCallback? on_file,
        Cancellable? cancellable
    ) throws Error {
        check_cancelled (cancellable);
        ensure_dir (dst);
        var dir = Dir.open (src);
        string? name;
        while ((name = dir.read_name ()) != null) {
            var src_path = Path.build_filename (src, name);
            var dst_path = Path.build_filename (dst, name);
            if (FileUtils.test (src_path, FileTest.IS_DIR)) {
                copy_dir_recursive (src_path, dst_path, on_file, cancellable);
            } else {
                copy_file (src_path, dst_path, cancellable);
                if (on_file != null) on_file (src_path, dst_path);
            }
        }
    }

    private static void copy_file (string src, string dst, Cancellable? cancellable = null) throws Error {
        check_cancelled (cancellable);
        ensure_dir (Path.get_dirname (dst));
        var source = File.new_for_path (src);
        var dest = File.new_for_path (dst);
        source.copy (dest, FileCopyFlags.OVERWRITE, cancellable);
    }

    public static uint32 crc32 (uint8[] bytes) {
        uint32 crc = 0xffffffffU;
        foreach (var byte in bytes) {
            crc ^= (uint32) byte;
            for (int i = 0; i < 8; i++) {
                if ((crc & 1U) != 0) {
                    crc = (crc >> 1) ^ 0xedb88320U;
                } else {
                    crc >>= 1;
                }
            }
        }
        return crc ^ 0xffffffffU;
    }

    /* Shell.quote unless the word is plain, so ids and paths stay readable in Exec lines and launch options. */
    public static string shell_quote (string s) {
        if (s == "") return "''";
        for (int i = 0; i < s.length; i++) {
            var c = s[i];
            if (!c.isalnum () && "_-./:=+@".index_of_char (c) < 0) return Shell.quote (s);
        }
        return s;
    }
}
