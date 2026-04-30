namespace Lumoria.Utils {

    [CCode (cname = "archive_read_open_filenames")]
    private extern Archive.Result archive_read_open_filenames (
        Archive.Read reader,
        [CCode (array_null_terminated = true, array_length = false, type = "const char **")] string[] filenames,
        size_t block_size
    );

    public static void extract_archive (string archive_path, string extract_to) throws Error {
        extract_archive_multi ({ archive_path }, extract_to);
    }

    public static void extract_archive_multi (string[] archive_paths, string extract_to) throws Error {
        if (archive_paths.length == 0) {
            throw new IOError.FAILED ("No archive volumes provided");
        }

        ensure_dir (extract_to);

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
