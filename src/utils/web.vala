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
        public Gee.ArrayList<GitHubAsset> assets { get; owned set; default = new Gee.ArrayList<GitHubAsset> (); }

        public static GitHubRelease from_json (Json.Object obj) {
            var r = new GitHubRelease ();
            r.tag_name = Models.json_string (obj, "tag_name");
            r.name = Models.json_string (obj, "name");
            r.published_at = Models.json_string (obj, "published_at");
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

    public Gee.ArrayList<GitHubRelease> fetch_github_releases_sync (
        string repo,
        string cache_path,
        int64 cache_ttl_seconds
    ) throws Error {
        var releases = new Gee.ArrayList<GitHubRelease> ();

        if (cache_path != "" && FileUtils.test (cache_path, FileTest.EXISTS)) {
            var file_stat = Stat (cache_path);
            var age = (int64) time_t () - (int64) file_stat.st_mtime;
            if (age < cache_ttl_seconds) {
                try {
                    var parser = new Json.Parser ();
                    parser.load_from_file (cache_path);
                    var root = parser.get_root ();
                    if (root.get_node_type () == Json.NodeType.ARRAY) {
                        var arr = root.get_array ();
                        for (uint i = 0; i < arr.get_length (); i++) {
                            releases.add (GitHubRelease.from_json (arr.get_object_element (i)));
                        }
                        return releases;
                    }
                    warning ("Invalid GitHub cache payload at %s (expected JSON array); refetching", cache_path);
                } catch (Error e) {
                    warning ("Failed to parse GitHub cache at %s: %s; refetching", cache_path, e.message);
                }
            }
        }

        var url = "https://api.github.com/repos/%s/releases".printf (repo);
        var session = get_api_session ();
        var msg = new Soup.Message ("GET", url);

        var input = session.send (msg, null);
        if (msg.status_code != 200) {
            throw new IOError.FAILED ("GitHub API returned %u for %s", msg.status_code, url);
        }

        var builder = new ByteArray ();
        var buf = new uint8[65536];
        ssize_t n;
        while ((n = input.read (buf)) > 0) {
            builder.append (buf[0:n]);
        }
        builder.append ({0});
        var data_len = (ssize_t) (builder.len - 1);
        var payload = (string) builder.data;
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

        if (cache_path != "") {
            try {
                ensure_dir (Path.get_dirname (cache_path));
                FileUtils.set_contents (cache_path, payload, data_len);
            } catch (Error e) {
                warning ("Failed to cache releases: %s", e.message);
            }
        }

        return releases;
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

}
