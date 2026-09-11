namespace Lumoria.Utils {

    [CCode (cname = "archive_read_open_filenames")]
    private extern Archive.Result archive_read_open_filenames (
        Archive.Read reader,
        [CCode (array_null_terminated = true, array_length = false, type = "const char **")] string[] filenames,
        size_t block_size
    );

    private const int SFX_SCAN_SIZE = 16 << 20;
    private const uint8[] RAR5_SIGNATURE = { 0x52, 0x61, 0x72, 0x21, 0x1a, 0x07 };
    private const uint8[] SEVENZIP_SIGNATURE = { 0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c };

    public static void extract_archive (
        string archive_path,
        string extract_to,
        string[] only = {},
        Cancellable? cancellable = null
    ) throws Error {
        extract_archive_multi ({ archive_path }, extract_to, only, cancellable);
    }

    /* Called from worker threads. */
    public delegate string? CabDestinationResolver (string name, uint size) throws Error;

    public static Gee.ArrayList<string> list_cab_entries (string archive_path) throws Error {
        var names = new Gee.ArrayList<string> ();
        var decomp = new MsPack.CabDecompressor ();
        var cab = open_cab (decomp, archive_path);
        try {
            for (unowned var current = cab; current != null; current = current.get_next ()) {
                for (unowned var file = current.get_files (); file != null; file = file.get_next ()) {
                    var name = file.get_filename ();
                    if (name != null) names.add (name);
                }
            }
        } finally {
            decomp.close (cab);
        }
        return names;
    }

    public static int extract_cab_entries (
        string[] archive_paths,
        owned CabDestinationResolver resolve,
        Cancellable? cancellable = null
    ) throws Error {
        var shared = new CabResolver ((owned) resolve);
        var jobs = new Gee.ArrayList<CabJob> ();
        foreach (var archive_path in archive_paths) {
            jobs.add (new CabJob (archive_path, shared, cancellable));
        }
        run_parallel<CabJob> (jobs, () => new CabWorker (), cancellable);
        return AtomicInt.get (ref shared.extracted);
    }

    private class CabResolver : Object {
        public CabDestinationResolver resolve;
        public int extracted = 0;

        public CabResolver (owned CabDestinationResolver resolve) {
            this.resolve = (owned) resolve;
        }
    }

    private class CabJob : Object {
        public string archive;
        public CabResolver resolver;
        public Cancellable? cancellable;

        public CabJob (string archive, CabResolver resolver, Cancellable? cancellable) {
            this.archive = archive;
            this.resolver = resolver;
            this.cancellable = cancellable;
        }
    }

    private class CabWorker : Worker<CabJob> {
        public override void run (CabJob job) throws Error {
            var decomp = new MsPack.CabDecompressor ();
            var cab = open_cab (decomp, job.archive);
            try {
                for (unowned var current = cab; current != null; current = current.get_next ()) {
                    for (unowned var file = current.get_files (); file != null; file = file.get_next ()) {
                        check_cancelled (job.cancellable);
                        var name = file.get_filename ();
                        if (name == null || name == "") continue;

                        var destination = job.resolver.resolve (name, file.get_length ());
                        if (destination == null) continue;

                        var parent = Path.get_dirname (destination);
                        ensure_dir (parent);
                        if (FileUtils.test (parent, FileTest.IS_SYMLINK)
                            || FileUtils.test (destination, FileTest.IS_SYMLINK)) {
                            throw new LumoriaError.FAILED ("mspack: refusing symlink path: %s", name);
                        }

                        var result = decomp.extract (file, destination);
                        if (result != MsPack.ERR_OK) {
                            throw new LumoriaError.FAILED ("mspack: extract failed for %s (error %d)", name, result);
                        }
                        AtomicInt.inc (ref job.resolver.extracted);
                    }
                }
            } finally {
                decomp.close (cab);
            }
        }
    }

    private static MsPack.Cabinet open_cab (MsPack.CabDecompressor decomp, string archive_path) throws Error {
        var cab = decomp.open (archive_path);
        if (cab == null) cab = decomp.search (archive_path);
        if (cab == null) {
            throw new LumoriaError.FAILED ("mspack: cannot open %s (error %d)", archive_path, decomp.last_error ());
        }
        return cab;
    }

    private static string safe_cab_destination (string extract_root, string name) throws Error {
        var relative = name.replace ("\\", "/");
        if (relative.length > 1 && relative[1] == ':') {
            throw new LumoriaError.FAILED ("mspack: unsafe cab path: %s", name);
        }
        while (relative.has_prefix ("./")) relative = relative.substring (2);
        return join_inside (extract_root, relative);
    }

    public static void extract_archive_multi (
        string[] archive_paths,
        string extract_to,
        string[] only = {},
        Cancellable? cancellable = null
    ) throws Error {
        check_cancelled (cancellable);
        if (archive_paths.length == 0) {
            throw new IOError.FAILED ("No archive volumes provided");
        }

        ensure_dir (extract_to);
        var extract_root = Posix.realpath (extract_to);
        if (extract_root == null) {
            throw new IOError.FAILED ("Failed to resolve extraction directory: %s", extract_to);
        }

        var filter = new EntryFilter (only);
        if (archive_paths.length == 1 && is_cab_path (archive_paths[0])) {
            var extracted = extract_cab_entries (archive_paths, (name, size) => {
                return filter.matches (name) ? safe_cab_destination (extract_root, name) : null;
            });
            if (extracted == 0) throw new LumoriaError.FAILED ("mspack: no files found in %s", archive_paths[0]);
            return;
        }
        if (archive_paths.length == 1 && is_7z_archive (archive_paths[0])) {
            extract_7z (archive_paths[0], extract_root, filter);
            return;
        }

        try {
            extract_archive_multi_libarchive (archive_paths, extract_root, filter, cancellable);
        } catch (Error e) {
            int offset = find_signature_offset (archive_paths[0], RAR5_SIGNATURE);
            if (offset <= 0) throw e;

            var rar_payload_path = extract_rar_sfx_payload (archive_paths[0], offset);
            if (rar_payload_path == null) throw e;

            var patched = new string[archive_paths.length];
            patched[0] = rar_payload_path;
            for (int i = 1; i < archive_paths.length; i++) {
                patched[i] = archive_paths[i];
            }

            try {
                extract_archive_multi_libarchive (patched, extract_root, filter, cancellable);
            } finally {
                FileUtils.remove (rar_payload_path);
            }
        }
    }

    private class EntryFilter : Object {
        private string[] globs;

        public EntryFilter (string[] globs) {
            this.globs = globs;
        }

        public bool matches (string name) {
            if (globs.length == 0) return true;
            var normalized = name.replace ("\\", "/");
            while (normalized.has_prefix ("./")) normalized = normalized.substring (2);
            foreach (var glob in globs) {
                if (PatternSpec.match_simple (glob, normalized)) return true;
            }
            return false;
        }
    }

    private static bool is_cab_path (string path) {
        return path.down ().has_suffix (".cab");
    }

    private static bool is_7z_archive (string path) {
        return find_signature_offset (path, SEVENZIP_SIGNATURE) >= 0;
    }

    /* libarchive rejects LZMA lc=8 / BCJ2. */
    private static void extract_7z (string archive_path, string extract_root, EntryFilter filter) throws Error {
        string? error;
        var listing = Native.SevenZip.list (archive_path, out error);
        if (listing == null) {
            throw new LumoriaError.FAILED ("7z: cannot read %s: %s", archive_path, error ?? "unknown error");
        }

        var listing_root = Models.parse_data_node (listing);
        var plan = new Json.Builder ();
        plan.begin_object ();
        int planned = 0;
        foreach (var node in listing_root.get_array ().get_elements ()) {
            var name = node.get_object ().get_string_member ("name");
            if (!filter.matches (name)) continue;
            plan.set_member_name (name);
            plan.add_string_value (safe_cab_destination (extract_root, name));
            planned++;
        }
        plan.end_object ();
        if (planned == 0) {
            throw new LumoriaError.FAILED ("7z: no matching entries in %s", archive_path);
        }

        var plan_json = Json.to_string (plan.get_root (), false);
        if (!Native.SevenZip.extract (archive_path, plan_json, extract_root, out error)) {
            throw new LumoriaError.FAILED ("7z: extraction failed for %s: %s", archive_path, error ?? "unknown error");
        }
    }

    private static int find_signature_offset (string path, uint8[] signature) {
        int fd = Posix.open (path, Posix.O_RDONLY);
        if (fd < 0) return -1;

        var scan = new uint8[SFX_SCAN_SIZE];
        var n = Posix.read (fd, scan, scan.length);
        Posix.close (fd);
        if (n < 8) return -1;

        var limit = (scan[0] == 'M' && scan[1] == 'Z') ? n - signature.length : 0;
        for (int i = 0; i <= limit; i++) {
            bool match = true;
            for (int j = 0; j < signature.length; j++) {
                if (scan[i + j] != signature[j]) { match = false; break; }
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

    private static void extract_archive_multi_libarchive (
        string[] archive_paths,
        string extract_to,
        EntryFilter filter,
        Cancellable? cancellable
    ) throws Error {
        var buckets = plan_rar_buckets (archive_paths);
        if (buckets == null) {
            new ArchiveWorker (archive_paths, extract_to, filter, cancellable).extract_bucket (null);
            return;
        }
        run_parallel<ArchiveBucket> (
            buckets,
            () => new ArchiveWorker (archive_paths, extract_to, filter, cancellable),
            cancellable
        );
    }

    private static Gee.ArrayList<ArchiveBucket>? plan_rar_buckets (string[] archive_paths) throws Error {
        if (rar_is_solid (archive_paths[0]) != false) return null;

        var sizes = new Gee.ArrayList<int64?> ();
        var reader = open_archive_reader (archive_paths);
        unowned Archive.Entry entry;
        while (true) {
            var r = reader.next_header (out entry);
            if (r == Archive.Result.EOF) break;
            if (r < Archive.Result.WARN) {
                throw new IOError.FAILED ("Archive read error: %s", reader.error_string () ?? "unknown");
            }
            sizes.add (entry.size ());
        }

        var count = int.min (sizes.size, parallel_workers ());
        if (count < 2) return null;

        var order = new Gee.ArrayList<int> ();
        for (int i = 0; i < sizes.size; i++) order.add (i);
        order.sort ((a, b) => {
            int64 diff = sizes[b] - sizes[a];
            return diff > 0 ? 1 : (diff < 0 ? -1 : 0);
        });

        var buckets = new Gee.ArrayList<ArchiveBucket> ();
        for (int i = 0; i < count; i++) buckets.add (new ArchiveBucket (sizes.size));
        foreach (var index in order) {
            ArchiveBucket lightest = buckets[0];
            foreach (var bucket in buckets) {
                if (bucket.total < lightest.total) lightest = bucket;
            }
            lightest.take (index, sizes[index]);
        }
        return buckets;
    }

    /* RAR4 main header flag 0x0008 and RAR5 archive flag 0x0004 mark solid archives. Null when not a RAR. */
    private static bool? rar_is_solid (string path) {
        var offset = find_signature_offset (path, RAR5_SIGNATURE);
        if (offset < 0) return null;

        var header = new uint8[64];
        int fd = Posix.open (path, Posix.O_RDONLY);
        if (fd < 0) return null;
        Posix.lseek (fd, offset, Posix.SEEK_SET);
        var n = Posix.read (fd, header, header.length);
        Posix.close (fd);
        if (n < RAR5_SIGNATURE.length + 2) return null;

        if (header[6] == 0x00) {
            if (n < 12 || header[9] != 0x73) return null;
            return ((header[10] | (header[11] << 8)) & 0x0008) != 0;
        }
        if (header[6] != 0x01 || header[7] != 0x00) return null;

        size_t pos = 8 + 4;
        var header_size = read_vint (header, n, ref pos);
        var header_type = read_vint (header, n, ref pos);
        var header_flags = read_vint (header, n, ref pos);
        if (header_size < 0 || header_type != 1 || header_flags < 0) return null;
        if ((header_flags & 0x01) != 0 && read_vint (header, n, ref pos) < 0) return null;
        if ((header_flags & 0x02) != 0 && read_vint (header, n, ref pos) < 0) return null;
        var archive_flags = read_vint (header, n, ref pos);
        if (archive_flags < 0) return null;
        return (archive_flags & 0x0004) != 0;
    }

    private static int64 read_vint (uint8[] data, ssize_t length, ref size_t pos) {
        int64 value = 0;
        for (int shift = 0; shift < 64 && pos < length; shift += 7) {
            var byte = data[pos++];
            value |= (int64) (byte & 0x7f) << shift;
            if ((byte & 0x80) == 0) return value;
        }
        return -1;
    }

    private static Archive.Read open_archive_reader (string[] archive_paths) throws Error {
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
        return reader;
    }

    private class ArchiveBucket : Object {
        public int64 total = 0;
        private bool[] members;

        public ArchiveBucket (int entries) {
            members = new bool[entries];
        }

        public void take (int index, int64 size) {
            members[index] = true;
            total += size;
        }

        public bool contains (int index) {
            return index < members.length && members[index];
        }
    }

    private class ArchiveWorker : Worker<ArchiveBucket> {
        private string[] archive_paths;
        private string extract_to;
        private EntryFilter filter;
        private Cancellable? cancellable;

        public ArchiveWorker (
            string[] archive_paths,
            string extract_to,
            EntryFilter filter,
            Cancellable? cancellable
        ) {
            this.archive_paths = archive_paths;
            this.extract_to = extract_to;
            this.filter = filter;
            this.cancellable = cancellable;
        }

        public override void run (ArchiveBucket bucket) throws Error {
            extract_bucket (bucket);
        }

        public void extract_bucket (ArchiveBucket? bucket) throws Error {
            var reader = open_archive_reader (archive_paths);
            var writer = new Archive.WriteDisk ();
            writer.set_options (
                Archive.ExtractFlags.TIME
                | Archive.ExtractFlags.PERM
                | Archive.ExtractFlags.SECURE_SYMLINKS
                | Archive.ExtractFlags.SECURE_NODOTDOT
            );
            writer.set_standard_lookup ();

            unowned Archive.Entry entry;
            for (int index = 0; ; index++) {
                check_cancelled (cancellable);
                var r = reader.next_header (out entry);
                if (r == Archive.Result.EOF) break;
                if (r < Archive.Result.WARN) {
                    throw new IOError.FAILED ("Archive read error: %s", reader.error_string () ?? "unknown");
                }
                if (bucket != null && !bucket.contains (index)) continue;

                var path = entry.pathname ();
                if (path != null && !filter.matches (path)) continue;
                if (path != null) {
                    entry.set_pathname (Path.build_filename (extract_to, path));
                }

                if (writer.write_header (entry) < Archive.Result.OK) {
                    throw new IOError.FAILED ("Archive write error: %s", writer.error_string () ?? "unknown");
                }
                if (entry.size () > 0) {
                    copy_archive_data (reader, writer);
                }
                writer.finish_entry ();
            }
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
