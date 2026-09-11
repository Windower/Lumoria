namespace Lumoria.Utils {

    private const uint API_TIMEOUT_SECONDS = 45;

    private Soup.Session? _shared_session = null;

    private Soup.Session new_session (uint timeout_seconds) {
        var session = new Soup.Session ();
        session.user_agent = "%s/%s".printf (Config.APP_NAME, Config.APP_VERSION);
        session.timeout = timeout_seconds;
        session.idle_timeout = timeout_seconds;
        return session;
    }

    public Soup.Session get_api_session () {
        if (_shared_session == null) _shared_session = new_session (API_TIMEOUT_SECONDS);
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
            a.size = Models.json_int (obj, "size");
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

    private Gee.ArrayList<GitHubRelease> parse_github_releases_payload (string payload, string repo) throws Error {
        var releases = new Gee.ArrayList<GitHubRelease> ();
        var root = Models.parse_data_node (payload);
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
            FileUtils.get_contents (cache_path, out payload);
            releases = parse_github_releases_payload (payload, repo);
            return true;
        } catch (Error e) {
            warning ("Failed to parse GitHub cache at %s: %s; refetching", cache_path, e.message);
            return false;
        }
    }

    private string request_text (Soup.Session session, string url, Cancellable? cancellable) throws Error {
        var msg = new Soup.Message ("GET", url);
        var body = session.send_and_read (msg, cancellable);
        if (msg.status_code != 200) {
            throw new IOError.FAILED ("Request returned %u for %s", msg.status_code, url);
        }
        var data = body.get_data ();
        return data.length == 0 ? "" : ((string) data).substring (0, data.length);
    }

    private void write_releases_cache (string cache_path, string payload) {
        if (cache_path == "") return;
        try {
            write_text_atomic (cache_path, payload);
        } catch (Error e) {
            warning ("Failed to cache releases: %s", e.message);
        }
    }

    private Gee.ArrayList<GitHubRelease> fetch_github_releases_url (
        string repo,
        string url,
        string cache_path,
        int64 cache_ttl_seconds
    ) throws Error {
        Gee.ArrayList<GitHubRelease> releases;
        if (try_read_releases_cache (cache_path, cache_ttl_seconds, repo, out releases)) {
            return releases;
        }

        var payload = request_text (get_api_session (), url, null);
        releases = parse_github_releases_payload (payload, repo);
        write_releases_cache (cache_path, payload);
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
        result.releases = fetch_github_releases_url (
            repo,
            "https://api.github.com/repos/%s/releases?per_page=%d&page=%d".printf (
                repo, result.per_page, result.page
            ),
            cache_path,
            cache_ttl_seconds
        );
        result.has_more = result.releases.size >= result.per_page;
        return result;
    }

    public delegate void ProgressCallback (int64 downloaded, int64 total);

    private const uint DOWNLOAD_STALL_SECONDS = 30;
    private const int DOWNLOAD_ATTEMPTS = 4;

    public string fetch_text_sync (string url, Cancellable? cancellable = null) throws Error {
        check_cancelled (cancellable);
        return request_text (get_api_session (), url, cancellable);
    }

    public void download_file_sync (
        string url,
        string dest,
        ProgressCallback? progress = null,
        Cancellable? cancellable = null
    ) throws Error {
        ensure_dir (Path.get_dirname (dest));
        Error? last_error = null;
        for (int attempt = 1; attempt <= DOWNLOAD_ATTEMPTS; attempt++) {
            try {
                download_file_once (url, dest, progress, cancellable);
                return;
            } catch (IOError.CANCELLED e) {
                throw e;
            } catch (Error e) {
                last_error = e;
                check_cancelled (cancellable);
                if (attempt == DOWNLOAD_ATTEMPTS || !download_error_is_retryable (e)) {
                    throw e;
                }
                warning (
                    "Download stalled or dropped for %s (attempt %d/%d): %s; resuming",
                    url, attempt, DOWNLOAD_ATTEMPTS, e.message
                );
            }
        }
        throw last_error != null ? last_error : new IOError.FAILED ("Download failed for %s", url);
    }

    private bool download_error_is_retryable (Error e) {
        if (e is IOError.TIMED_OUT || e is IOError.CLOSED || e is IOError.PARTIAL_INPUT) {
            return true;
        }
        if (e is IOError.FAILED && e.message.has_prefix ("Download returned")) {
            return false;
        }
        return e is IOError.FAILED || e is IOError.CONNECTION_CLOSED;
    }

    /* Stalls surface as IOError.TIMED_OUT through the session's I/O timeout and are retried with a Range resume. */
    private void download_file_once (
        string url,
        string dest,
        ProgressCallback? progress,
        Cancellable? cancellable
    ) throws Error {
        check_cancelled (cancellable);
        var session = new_session (DOWNLOAD_STALL_SECONDS);

        var resume_from = FileUtils.test (dest, FileTest.IS_REGULAR)
            ? file_size_or_zero (dest) : 0;
        var msg = new Soup.Message ("GET", url);
        msg.set_force_http1 (true);
        if (resume_from > 0) {
            msg.request_headers.replace ("Range", "bytes=%s-".printf (resume_from.to_string ()));
        }

        var input = session.send (msg, cancellable);
        var status = msg.status_code;
        if (status == Soup.Status.REQUESTED_RANGE_NOT_SATISFIABLE) {
            FileUtils.remove (dest);
            throw new IOError.FAILED ("Download range no longer valid for %s", url);
        }
        if (status != Soup.Status.OK && status != Soup.Status.PARTIAL_CONTENT) {
            throw new IOError.FAILED ("Download returned %u for %s", status, url);
        }

        var resume = resume_from > 0 && status == Soup.Status.PARTIAL_CONTENT;
        if (resume_from > 0 && !resume) {
            FileUtils.remove (dest);
            resume_from = 0;
        }

        var remaining = msg.response_headers.get_content_length ();
        var total = remaining > 0 ? resume_from + remaining : 0;
        var output = resume
            ? File.new_for_path (dest).append_to (FileCreateFlags.NONE, cancellable)
            : File.new_for_path (dest).replace (null, false, FileCreateFlags.NONE, cancellable);
        var buf = new uint8[65536];
        int64 downloaded = resume ? resume_from : 0;
        ssize_t n;
        while ((n = input.read (buf, cancellable)) > 0) {
            output.write (buf[0:n], cancellable);
            downloaded += n;
            if (progress != null) progress (downloaded, total);
        }
        output.close ();

        if (total > 0 && downloaded < total) {
            throw new IOError.PARTIAL_INPUT (
                "Download ended after %s of %s bytes for %s".printf (
                    downloaded.to_string (), total.to_string (), url
                )
            );
        }
    }

    public string format_release_date (string iso8601) {
        if (iso8601 == "") return "";
        var dt = new DateTime.from_iso8601 (iso8601, new TimeZone.utc ());
        if (dt == null) return iso8601;
        return dt.format ("%x");
    }
}
