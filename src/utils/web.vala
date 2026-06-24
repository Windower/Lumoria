namespace Lumoria.Utils {

    private const uint API_TIMEOUT_SECONDS = 45;

    private Soup.Session? _shared_session = null;

    private Soup.Session get_api_session () {
        if (_shared_session == null) {
            _shared_session = new Soup.Session ();
            _shared_session.user_agent = "%s/%s".printf (Config.APP_NAME, Config.APP_VERSION);
            _shared_session.timeout = API_TIMEOUT_SECONDS;
            _shared_session.idle_timeout = API_TIMEOUT_SECONDS;
        }
        return _shared_session;
    }

    public class GitHubRelease : Object {
        public string tag_name { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string published_at { get; set; default = ""; }
        public string zipball_url { get; set; default = ""; }
        public string tarball_url { get; set; default = ""; }
        public Gee.ArrayList<GitHubAsset> assets { get; owned set; default = new Gee.ArrayList<GitHubAsset> (); }

        public static GitHubRelease from_json (Json.Object obj) {
            var r = new GitHubRelease ();
            r.tag_name = Models.json_string (obj, "tag_name");
            r.name = Models.json_string (obj, "name");
            r.published_at = Models.json_string (obj, "published_at");
            r.zipball_url = Models.json_string (obj, "zipball_url");
            r.tarball_url = Models.json_string (obj, "tarball_url");
            if (obj.has_member ("assets")) {
                var arr = obj.get_array_member ("assets");
                for (uint i = 0; i < arr.get_length (); i++) {
                    r.assets.add (GitHubAsset.from_json (arr.get_object_element (i)));
                }
            }
            return r;
        }
    }

    public class GitHubAsset : Object {
        public string name { get; set; default = ""; }
        public string browser_download_url { get; set; default = ""; }
        public int64 size { get; set; default = 0; }

        public static GitHubAsset from_json (Json.Object obj) {
            var a = new GitHubAsset ();
            a.name = Models.json_string (obj, "name");
            a.browser_download_url = Models.json_string (obj, "browser_download_url");
            a.size = obj.has_member ("size") ? obj.get_int_member ("size") : 0;
            return a;
        }
    }

    public class GitHubReleasePage : Object {
        public Gee.ArrayList<GitHubRelease> releases { get; owned set; default = new Gee.ArrayList<GitHubRelease> (); }
        public int page { get; set; default = 1; }
        public int per_page { get; set; default = 30; }
        public bool has_more { get; set; default = false; }
    }

    public GitHubAsset? find_github_asset_by_regex (GitHubRelease release, string regex) throws RegexError {
        var pattern = regex.strip ();
        if (pattern == "") return null;
        var re = new Regex (pattern);
        foreach (var asset in release.assets) {
            if (re.match (asset.name)) {
                return asset;
            }
        }
        return null;
    }

    private Gee.ArrayList<GitHubRelease> parse_github_releases_payload (
        string payload,
        ssize_t data_len,
        string repo
    ) throws Error {
        var releases = new Gee.ArrayList<GitHubRelease> ();
        var parser = new Json.Parser ();
        parser.load_from_data (payload, data_len);
        var root = parser.get_root ();
        if (root.get_node_type () != Json.NodeType.ARRAY) {
            throw new IOError.FAILED ("GitHub API payload for %s was not an array", repo);
        }
        var arr = root.get_array ();
        for (uint i = 0; i < arr.get_length (); i++) {
            releases.add (GitHubRelease.from_json (arr.get_object_element (i)));
        }
        return releases;
    }

    private bool try_read_releases_cache (
        string cache_path,
        int64 cache_ttl_seconds,
        string repo,
        out Gee.ArrayList<GitHubRelease> releases
    ) {
        releases = new Gee.ArrayList<GitHubRelease> ();
        if (cache_path == "" || !FileUtils.test (cache_path, FileTest.EXISTS)) return false;

        var file_stat = Stat (cache_path);
        var age = (int64) time_t () - (int64) file_stat.st_mtime;
        if (age >= cache_ttl_seconds) return false;

        try {
            string payload;
            size_t data_len;
            FileUtils.get_contents (cache_path, out payload, out data_len);
            releases = parse_github_releases_payload (payload, (ssize_t) data_len, repo);
            return true;
        } catch (Error e) {
            warning ("Failed to parse GitHub cache at %s: %s; refetching", cache_path, e.message);
            return false;
        }
    }

    private string read_response_payload (InputStream input, out ssize_t data_len) throws Error {
        var builder = new ByteArray ();
        var buf = new uint8[65536];
        ssize_t n;
        while ((n = input.read (buf)) > 0) {
            builder.append (buf[0:n]);
        }
        builder.append ({0});
        data_len = (ssize_t) (builder.len - 1);
        return (string) builder.data;
    }

    private void write_releases_cache (string cache_path, string payload, ssize_t data_len) {
        if (cache_path == "") return;
        try {
            ensure_dir (Path.get_dirname (cache_path));
            FileUtils.set_contents (cache_path, payload, data_len);
        } catch (Error e) {
            warning ("Failed to cache releases: %s", e.message);
        }
    }

    public Gee.ArrayList<GitHubRelease> fetch_github_releases_sync (
        string repo,
        string cache_path,
        int64 cache_ttl_seconds
    ) throws Error {
        Gee.ArrayList<GitHubRelease> releases;
        if (try_read_releases_cache (cache_path, cache_ttl_seconds, repo, out releases)) {
            return releases;
        }

        var url = "https://api.github.com/repos/%s/releases".printf (repo);
        var session = get_api_session ();
        var msg = new Soup.Message ("GET", url);

        var input = session.send (msg, null);
        if (msg.status_code != 200) {
            throw new IOError.FAILED ("GitHub API returned %u for %s", msg.status_code, url);
        }

        ssize_t data_len;
        var payload = read_response_payload (input, out data_len);
        releases = parse_github_releases_payload (payload, data_len, repo);
        write_releases_cache (cache_path, payload, data_len);

        return releases;
    }

    public GitHubReleasePage fetch_github_releases_page_sync (
        string repo,
        string cache_dir,
        int page,
        int per_page,
        int64 cache_ttl_seconds
    ) throws Error {
        var result = new GitHubReleasePage ();
        result.page = page > 0 ? page : 1;
        result.per_page = per_page > 0 ? per_page : 30;

        var cache_path = cache_dir != ""
            ? Path.build_filename (cache_dir, "releases-page-%d.json".printf (result.page))
            : "";
        Gee.ArrayList<GitHubRelease> releases;
        if (try_read_releases_cache (cache_path, cache_ttl_seconds, repo, out releases)) {
            result.releases = releases;
            result.has_more = releases.size >= result.per_page;
            return result;
        }

        var url = "https://api.github.com/repos/%s/releases?per_page=%d&page=%d".printf (
            repo,
            result.per_page,
            result.page
        );
        var session = get_api_session ();
        var msg = new Soup.Message ("GET", url);

        var input = session.send (msg, null);
        if (msg.status_code != 200) {
            throw new IOError.FAILED ("GitHub API returned %u for %s", msg.status_code, url);
        }

        ssize_t data_len;
        var payload = read_response_payload (input, out data_len);
        result.releases = parse_github_releases_payload (payload, data_len, repo);
        result.has_more = result.releases.size >= result.per_page;
        write_releases_cache (cache_path, payload, data_len);
        return result;
    }

    public delegate void ProgressCallback (int64 downloaded, int64 total);

    public void download_file_sync (
        string url,
        string dest,
        ProgressCallback? progress = null
    ) throws Error {
        ensure_dir (Path.get_dirname (dest));

        var session = new Soup.Session ();
        session.user_agent = "%s/%s".printf (Config.APP_NAME, Config.APP_VERSION);
        session.timeout = 0;
        session.idle_timeout = 60;
        var msg = new Soup.Message ("GET", url);

        var input = session.send (msg, null);
        if (msg.status_code != 200) {
            throw new IOError.FAILED ("Download returned %u for %s", msg.status_code, url);
        }

        var total = msg.response_headers.get_content_length ();
        var output = File.new_for_path (dest).replace (null, false, FileCreateFlags.NONE);
        var buf = new uint8[65536];
        int64 downloaded = 0;
        ssize_t n;
        while ((n = input.read (buf)) > 0) {
            output.write (buf[0:n]);
            downloaded += n;
            if (progress != null) progress (downloaded, total);
        }
        output.close ();
    }

    public string format_release_date (string iso8601) {
        if (iso8601 == "") return "";
        var dt = new DateTime.from_iso8601 (iso8601, new TimeZone.utc ());
        if (dt == null) return iso8601;
        return dt.format ("%x");
    }

    public class RemoteManifestFile : Object {
        public string filename { get; set; default = ""; }
        public string download_url { get; set; default = ""; }
        public string checksum { get; set; default = ""; }
        public string checksum_algorithm { get; set; default = ""; }
        public string sort_key { get; set; default = ""; }
        public Gee.HashMap<string, string> item_fields { get; owned set; default = new Gee.HashMap<string, string> (); }
    }

    private const int64 MANIFEST_CACHE_TTL = 3600;

    private string? try_load_manifest_envelope (string cache_path, int64 ttl) {
        if (!FileUtils.test (cache_path, FileTest.EXISTS)) return null;
        try {
            string raw;
            FileUtils.get_contents (cache_path, out raw);
            var parser = new Json.Parser ();
            parser.load_from_data (raw, raw.length);
            var obj = parser.get_root ().get_object ();
            if (ttl >= 0) {
                var age = (int64) time_t () - obj.get_int_member ("fetched_at");
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
            gen.to_file (cache_path);
        } catch (Error e) {
            warning ("Failed to write manifest cache %s: %s", cache_path, e.message);
        }
    }

    private Gee.ArrayList<RemoteManifestFile> parse_manifest_payload (
        string payload,
        Models.RemoteManifestSchema schema,
        Gee.HashMap<string, string> vars
    ) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_data (payload, payload.length);
        var target_node = parser.get_root ();

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
            if (filename == "") continue;

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
            if (node.get_node_type () != Json.NodeType.VALUE) return;
            var vtype = node.get_value_type ();
            if (vtype == typeof (string)) {
                fields[name] = node.get_string ();
            } else if (vtype == typeof (int64)) {
                fields[name] = node.get_int ().to_string ();
            } else if (vtype == typeof (bool)) {
                fields[name] = node.get_boolean () ? "true" : "false";
            } else if (vtype == typeof (double)) {
                fields[name] = node.get_double ().to_string ();
            }
        });
        return fields;
    }

    public Gee.ArrayList<RemoteManifestFile> fetch_remote_manifest_sync (
        string url,
        Models.RemoteManifestSchema schema,
        string cache_path,
        Gee.HashMap<string, string> vars
    ) throws Error {
        var fresh = try_load_manifest_envelope (cache_path, schema.cache_ttl);
        if (fresh != null) {
            return parse_manifest_payload (fresh, schema, vars);
        }

        string payload;
        try {
            var session = get_api_session ();
            var msg = new Soup.Message ("GET", url);
            var input = session.send (msg, null);
            if (msg.status_code != 200) {
                throw new IOError.FAILED ("Remote manifest returned %u for %s", msg.status_code, url);
            }
            ssize_t data_len;
            payload = read_response_payload (input, out data_len);
            write_manifest_envelope (cache_path, payload);
        } catch (Error e) {
            var stale = try_load_manifest_envelope (cache_path, -1);
            if (stale != null) {
                warning ("Remote manifest fetch failed for %s: %s — using stale cache", url, e.message);
                return parse_manifest_payload (stale, schema, vars);
            }
            throw e;
        }

        return parse_manifest_payload (payload, schema, vars);
    }

}
