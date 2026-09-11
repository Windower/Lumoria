namespace Lumoria.Utils {

    public class RemoteManifestFile : Object {
        public string filename { get; set; default = ""; }
        public string download_url { get; set; default = ""; }
        public string checksum { get; set; default = ""; }
        public string checksum_algorithm { get; set; default = ""; }
        public string sort_key { get; set; default = ""; }
        public Gee.HashMap<string, string> item_fields { get; owned set; default = new Gee.HashMap<string, string> (); }
    }


    private const int64 STALE_MAX_AGE = 7 * 24 * 60 * 60;

    private string? try_load_manifest_envelope (string cache_path, int64 ttl) {
        int64 fetched_at;
        return load_manifest_envelope (cache_path, ttl, out fetched_at);
    }

    private string? load_manifest_envelope (string cache_path, int64 ttl, out int64 fetched_at) {
        fetched_at = 0;
        if (!FileUtils.test (cache_path, FileTest.EXISTS)) return null;
        try {
            string raw;
            FileUtils.get_contents (cache_path, out raw);
            var obj = Models.parse_data_object (raw, raw.length);
            fetched_at = obj.get_int_member ("fetched_at");
            if (ttl >= 0) {
                var age = (int64) time_t () - fetched_at;
                if (age >= ttl) return null;
            }
            return obj.get_string_member ("content");
        } catch (Error e) {
            return null;
        }
    }

    private void write_manifest_envelope (string cache_path, string content) {
        if (cache_path == "") return;
        try {
            ensure_dir (Path.get_dirname (cache_path));
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("fetched_at");
            builder.add_int_value ((int64) time_t ());
            builder.set_member_name ("content");
            builder.add_string_value (content);
            builder.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (builder.get_root ());
            size_t len;
            write_text_atomic (cache_path, gen.to_data (out len));
        } catch (Error e) {
            warning ("Failed to write manifest cache %s: %s", cache_path, e.message);
        }
    }

    private Gee.ArrayList<RemoteManifestFile> parse_manifest_payload (
        string payload,
        Models.RemoteManifestSchema schema,
        Gee.HashMap<string, string> vars
    ) throws Error {
        var target_node = Models.parse_data_node (payload, payload.length);

        if (schema.files_path != "") {
            foreach (var segment in schema.files_path.split (".")) {
                if (target_node.get_node_type () != Json.NodeType.OBJECT) {
                    throw new IOError.FAILED ("files_path '%s': not an object at '%s'", schema.files_path, segment);
                }
                var obj = target_node.get_object ();
                if (!obj.has_member (segment)) {
                    throw new IOError.FAILED ("files_path '%s': field '%s' not found", schema.files_path, segment);
                }
                target_node = obj.get_member (segment);
            }
        }

        Json.Array arr;
        if (target_node.get_node_type () == Json.NodeType.ARRAY) {
            arr = target_node.get_array ();
        } else if (target_node.get_node_type () == Json.NodeType.OBJECT) {
            arr = new Json.Array ();
            arr.add_element (target_node);
        } else {
            throw new IOError.FAILED ("Manifest files_path target is not an array or object");
        }

        var files = new Gee.ArrayList<RemoteManifestFile> ();

        for (uint i = 0; i < arr.get_length (); i++) {
            var item_node = arr.get_element (i);
            if (item_node.get_node_type () != Json.NodeType.OBJECT) continue;
            var item = item_node.get_object ();

            var fields = manifest_item_to_string_map (item);

            if (schema.available_field != "" &&
                fields.has_key (schema.available_field) &&
                fields[schema.available_field] == "false") continue;

            if (schema.filter != null && !schema.filter.evaluate (vars, fields)) continue;

            var download_url = Models.expand_manifest_template (schema.url_template, fields, vars);
            if (download_url == "") continue;

            string filename;
            if (schema.filename_field != "" && fields.has_key (schema.filename_field)) {
                filename = fields[schema.filename_field];
            } else {
                filename = Path.get_basename (download_url.split ("?")[0]);
            }
            try {
                filename = confined_filename (filename);
            } catch (Error e) {
                continue;
            }

            var checksum = schema.checksum_field != "" && fields.has_key (schema.checksum_field)
                ? fields[schema.checksum_field] : "";

            var algorithm = "";
            if (schema.checksum_algorithm_field != "" && fields.has_key (schema.checksum_algorithm_field)) {
                algorithm = fields[schema.checksum_algorithm_field];
            }
            if (algorithm == "" && schema.checksum_algorithm != "") {
                algorithm = schema.checksum_algorithm;
            }

            var sort_key = schema.sort_field != "" && fields.has_key (schema.sort_field)
                ? fields[schema.sort_field] : "";

            var file = new RemoteManifestFile ();
            file.filename = filename;
            file.download_url = download_url;
            file.checksum = checksum;
            file.checksum_algorithm = algorithm;
            file.sort_key = sort_key;
            file.item_fields = fields;
            files.add (file);
        }

        if (schema.sort_field != "") {
            files.sort ((a, b) => strcmp (a.sort_key, b.sort_key));
        }

        return files;
    }

    private Gee.HashMap<string, string> manifest_item_to_string_map (Json.Object item) {
        var fields = new Gee.HashMap<string, string> ();
        item.foreach_member ((_, name, node) => {
            var value = Models.json_scalar_to_string (node);
            if (value != null) fields[name] = value;
        });
        return fields;
    }

    public class RemoteManifestCache {
        public string url_hash { get; private set; }
        public string cache_path { get; private set; }
        public string download_dir { get; private set; }

        public RemoteManifestCache (string url) {
            url_hash = Checksum.compute_for_string (ChecksumType.SHA256, url).substring (0, 16);
            cache_path = Path.build_filename (cache_dir (), "remote-manifests", url_hash + ".json");
            download_dir = Path.build_filename (cache_dir (), "remote-manifests", "downloads", url_hash);
        }

        public string download_path (string filename) throws Error {
            return join_inside (download_dir, confined_filename (filename));
        }
    }

    public bool remote_manifest_cache_fresh (string cache_path, int64 ttl) {
        return try_load_manifest_envelope (cache_path, ttl) != null;
    }

    public Gee.ArrayList<RemoteManifestFile>? load_cached_remote_manifest (
        Models.RemoteManifestSchema schema,
        string cache_path,
        Gee.HashMap<string, string> vars
    ) {
        var payload = try_load_manifest_envelope (cache_path, -1);
        if (payload == null) return null;
        try {
            return parse_manifest_payload (payload, schema, vars);
        } catch (Error e) {
            warning ("Remote manifest cache unreadable (%s): %s", cache_path, e.message);
            return null;
        }
    }

    public Uri require_remote_fetch_url (string url) throws Error {
        Uri uri;
        try {
            uri = Uri.parse (url, UriFlags.NONE);
        } catch (UriError e) {
            throw new LumoriaError.FAILED (_("Invalid remote manifest URL: %s").printf (url));
        }
        var scheme = uri.get_scheme ().down ();
        if (scheme == "http" || scheme == "https" || scheme == "file") return uri;
        throw new LumoriaError.FAILED (
            _("Remote manifests must use http, https, or file: %s").printf (url)
        );
    }

    public Gee.ArrayList<RemoteManifestFile> fetch_remote_manifest_sync (
        string url,
        Models.RemoteManifestSchema schema,
        string cache_path,
        Gee.HashMap<string, string> vars,
        Cancellable? cancellable = null
    ) throws Error {
        var uri = require_remote_fetch_url (url);
        var fresh = try_load_manifest_envelope (cache_path, schema.cache_ttl);
        if (fresh != null) {
            return parse_manifest_payload (fresh, schema, vars);
        }

        string payload;
        try {
            if (uri.get_scheme ().down () == "file") {
                var path = uri.get_path ();
                if (path == null || path == "") {
                    throw new LumoriaError.FAILED (_("Remote manifest file URL has no path: %s").printf (url));
                }
                FileUtils.get_contents (path, out payload);
            } else {
                payload = fetch_text_sync (url, cancellable);
            }
            write_manifest_envelope (cache_path, payload);
        } catch (Error e) {
            if (e is IOError.CANCELLED) throw e;
            check_cancelled (cancellable);
            int64 fetched_at;
            var stale = load_manifest_envelope (cache_path, STALE_MAX_AGE, out fetched_at);
            if (stale != null) {
                warning (
                    "Remote manifest fetch failed for %s: %s — using stale cache from %s",
                    url,
                    e.message,
                    fetched_at > 0 ? new DateTime.from_unix_utc (fetched_at).format_iso8601 () : "unknown"
                );
                return parse_manifest_payload (stale, schema, vars);
            }
            throw e;
        }

        return parse_manifest_payload (payload, schema, vars);
    }
}
