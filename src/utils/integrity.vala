namespace Lumoria.Utils {

    public string resolve_github_asset_checksum (
        GitHubRelease release,
        string checksum_regex,
        string asset_name,
        string cache_root,
        string context
    ) {
        var pattern = checksum_regex.strip ();
        if (pattern == "") return "";

        try {
            var checksum_asset = find_github_asset_by_regex (release, pattern);
            if (checksum_asset == null) {
                warning ("No checksum asset found for %s release %s; continuing with size validation", context, release.tag_name);
                return "";
            }

            var checksum_path = Path.build_filename (cache_root, checksum_asset.name);
            if (!FileUtils.test (checksum_path, FileTest.EXISTS)) {
                try {
                    download_file_sync (checksum_asset.browser_download_url, checksum_path, null);
                } catch (Error e) {
                    warning ("Failed checksum download for %s: %s", context, e.message);
                    return "";
                }
            }

            return parse_checksum_for_asset (checksum_path, asset_name, context);
        } catch (RegexError e) {
            warning ("Invalid checksum regex for %s: %s", context, e.message);
            return "";
        }
    }

    public bool validate_downloaded_file (
        string path,
        int64 expected_size,
        string expected_checksum,
        string context
    ) {
        if (!FileUtils.test (path, FileTest.EXISTS)) return false;

        int64 actual_size = file_size_or_zero (path);
        if (actual_size <= 0) return false;
        if (expected_size > 0 && actual_size != expected_size) return false;

        if (expected_checksum != "") {
            var actual = compute_checksum_for_expected (path, expected_checksum);
            if (actual == "" || actual.down () != expected_checksum.down ()) {
                warning ("Checksum mismatch for %s (%s)", context, path);
                return false;
            }
        }
        return true;
    }

    public void ensure_downloaded_file (
        string url,
        string dest,
        int64 expected_size,
        string expected_checksum,
        string context,
        ProgressCallback? progress = null
    ) throws Error {
        ensure_dir (Path.get_dirname (dest));
        if (!validate_downloaded_file (dest, expected_size, expected_checksum, context)) {
            if (FileUtils.test (dest, FileTest.EXISTS)) {
                FileUtils.remove (dest);
            }
            download_file_sync (url, dest, progress);
        }
        if (!validate_downloaded_file (dest, expected_size, expected_checksum, context)) {
            throw new IOError.FAILED ("Downloaded file is invalid for %s: %s", context, dest);
        }
    }

    private string parse_checksum_for_asset (string checksum_path, string asset_name, string context) {
        string content;
        try {
            FileUtils.get_contents (checksum_path, out content);
        } catch (Error e) {
            warning ("Failed to read checksum file %s for %s: %s", checksum_path, context, e.message);
            return "";
        }

        Regex hex_re;
        try {
            hex_re = new Regex ("([A-Fa-f0-9]{128}|[A-Fa-f0-9]{64})");
        } catch (RegexError e) {
            warning ("Checksum hex regex failed to compile for %s: %s", context, e.message);
            return "";
        }

        foreach (var line in content.split ("\n")) {
            if (!line.contains (asset_name)) continue;
            MatchInfo match;
            if (hex_re.match (line, 0, out match)) {
                var hex = match.fetch (1);
                if (hex != null) return hex;
            }
        }
        warning ("Checksum entry not found for asset %s in %s (%s); continuing with size validation", asset_name, checksum_path, context);
        return "";
    }

    private string compute_checksum_for_expected (string path, string expected_hex) {
        var len = expected_hex.length;
        ChecksumType type;
        if (len == 64) {
            type = ChecksumType.SHA256;
        } else if (len == 128) {
            type = ChecksumType.SHA512;
        } else {
            return "";
        }

        try {
            var checksum = new Checksum (type);
            var input = File.new_for_path (path).read ();
            var buf = new uint8[65536];
            ssize_t n;
            while ((n = input.read (buf)) > 0) {
                checksum.update (buf, n);
            }
            input.close ();
            return checksum.get_string ();
        } catch (Error e) {
            warning ("Failed to compute checksum for %s: %s", path, e.message);
            return "";
        }
    }
}
