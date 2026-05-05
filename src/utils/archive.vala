namespace Lumoria.Utils {

    [CCode (cname = "archive_read_open_filenames")]
    private extern Archive.Result archive_read_open_filenames (
        Archive.Read reader,
        [CCode (array_null_terminated = true, array_length = false, type = "const char **")] string[] filenames,
        size_t block_size
    );

    private const int RAR_SFX_SCAN_SIZE = 1048576;
    private const uint8[] RAR5_SIGNATURE = { 0x52, 0x61, 0x72, 0x21, 0x1a, 0x07 };

    public static void extract_archive (string archive_path, string extract_to) throws Error {
        extract_archive_multi ({ archive_path }, extract_to);
    }

    public static void extract_archive_multi (string[] archive_paths, string extract_to) throws Error {
        if (archive_paths.length == 0) {
            throw new IOError.FAILED ("No archive volumes provided");
        }

        ensure_dir (extract_to);
        var extract_root = Posix.realpath (extract_to);
        if (extract_root == null) {
            throw new IOError.FAILED ("Failed to resolve extraction directory: %s", extract_to);
        }

        try {
            extract_archive_multi_libarchive (archive_paths, extract_root);
        } catch (Error e) {
            int offset = find_rar_sfx_offset (archive_paths[0]);
            if (offset < 0) throw e;

            var rar_payload_path = extract_rar_sfx_payload (archive_paths[0], offset);
            if (rar_payload_path == null) throw e;

            var patched = new string[archive_paths.length];
            patched[0] = rar_payload_path;
            for (int i = 1; i < archive_paths.length; i++) {
                patched[i] = archive_paths[i];
            }

            try {
                extract_archive_multi_libarchive (patched, extract_root);
            } finally {
                FileUtils.remove (rar_payload_path);
            }
        }
    }

    private static int find_rar_sfx_offset (string path) {
        int fd = Posix.open (path, Posix.O_RDONLY);
        if (fd < 0) return -1;

        var scan = new uint8[RAR_SFX_SCAN_SIZE];
        var n = Posix.read (fd, scan, scan.length);
        Posix.close (fd);

        if (n < 8 || scan[0] != 'M' || scan[1] != 'Z') return -1;

        for (int i = 0; i <= n - RAR5_SIGNATURE.length; i++) {
            bool match = true;
            for (int j = 0; j < RAR5_SIGNATURE.length; j++) {
                if (scan[i + j] != RAR5_SIGNATURE[j]) { match = false; break; }
            }
            if (match) return i;
        }
        return -1;
    }

    private static string? extract_rar_sfx_payload (string sfx_path, int rar_offset) {
        string tmp_path;
        int dst;
        try {
            dst = FileUtils.open_tmp ("lumoria-rar-sfx-XXXXXX", out tmp_path);
        } catch (Error e) {
            return null;
        }

        int src = Posix.open (sfx_path, Posix.O_RDONLY);
        if (src < 0) { Posix.close (dst); FileUtils.remove (tmp_path); return null; }

        Posix.lseek (src, rar_offset, Posix.SEEK_SET);
        var buf = new uint8[65536];
        ssize_t bytes;
        while ((bytes = Posix.read (src, buf, buf.length)) > 0) {
            Posix.write (dst, buf, bytes);
        }
        Posix.close (src);
        Posix.close (dst);

        return tmp_path;
    }

    private static void extract_archive_multi_libarchive (string[] archive_paths, string extract_to) throws Error {
        var reader = new Archive.Read ();
        reader.support_filter_all ();
        reader.support_format_all ();

        var filenames = new string[archive_paths.length + 1];
        for (int i = 0; i < archive_paths.length; i++) {
            filenames[i] = archive_paths[i];
        }
        filenames[archive_paths.length] = null;

        if (archive_read_open_filenames (reader, filenames, 10240) != Archive.Result.OK) {
            var msg = reader.error_string () ?? "unknown error";
            throw new IOError.FAILED ("Failed to open archive volume set: %s", msg);
        }

        var writer = new Archive.WriteDisk ();
        writer.set_options (
            Archive.ExtractFlags.TIME
            | Archive.ExtractFlags.PERM
            | Archive.ExtractFlags.SECURE_SYMLINKS
            | Archive.ExtractFlags.SECURE_NODOTDOT
        );
        writer.set_standard_lookup ();

        unowned Archive.Entry entry;
        while (true) {
            var r = reader.next_header (out entry);
            if (r == Archive.Result.EOF) break;
            if (r < Archive.Result.WARN) {
                throw new IOError.FAILED ("Archive read error: %s",
                    reader.error_string () ?? "unknown");
            }

            var path = entry.pathname ();
            if (path != null) {
                entry.set_pathname (Path.build_filename (extract_to, path));
            }

            if (writer.write_header (entry) < Archive.Result.OK) {
                throw new IOError.FAILED ("Archive write error: %s",
                    writer.error_string () ?? "unknown");
            }

            if (entry.size () > 0) {
                copy_archive_data (reader, writer);
            }

            writer.finish_entry ();
        }
    }

    private static void copy_archive_data (Archive.Read reader, Archive.WriteDisk writer) throws Error {
        unowned uint8[] buf;
        Archive.int64_t offset;
        while (true) {
            var r = reader.read_data_block (out buf, out offset);
            if (r == Archive.Result.EOF) return;
            if (r < Archive.Result.WARN) {
                throw new IOError.FAILED ("Archive data read error: %s",
                    reader.error_string () ?? "unknown");
            }
            if (writer.write_data_block (buf, offset) < Archive.Result.OK) {
                throw new IOError.FAILED ("Archive data write error: %s",
                    writer.error_string () ?? "unknown");
            }
        }
    }
}
