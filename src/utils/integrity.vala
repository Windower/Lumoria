namespace Lumoria.Utils {

    public string resolve_github_asset_checksum (
        GitHubRelease release,
        string checksum_regex,
        string asset_name,
        string cache_root,
        string context
    ) throws Error {
        var pattern = checksum_regex.strip ();
        if (pattern == "") return "";

        GitHubAsset? checksum_asset;
        try {
            checksum_asset = find_github_asset_by_regex (release, pattern);
        } catch (RegexError e) {
            throw new IOError.FAILED ("Invalid checksum regex for %s: %s", context, e.message);
        }
        if (checksum_asset == null) {
            return "";
        }

        var tag = release.tag_name.replace ("/", "-");
        if (tag == "") tag = "unknown";
        var checksum_dir = Path.build_filename (cache_root, tag);
        ensure_dir (checksum_dir);
        var checksum_path = Path.build_filename (checksum_dir, checksum_asset.name);
        ensure_downloaded_file (checksum_asset.browser_download_url, checksum_path, checksum_asset.size, "", context);

        var hex = parse_checksum_for_asset (checksum_path, asset_name, context);
        if (hex == "") {
            throw new IOError.FAILED ("Checksum entry not found for asset %s in %s (%s)", asset_name, checksum_path, context);
        }
        return hex;
    }

    public string? downloaded_file_problem (
        string path,
        int64 expected_size,
        string expected_checksum,
        string context,
        string? algorithm = null,
        bool checksum_required = false
    ) {
        if (!FileUtils.test (path, FileTest.IS_REGULAR)) {
            return _("Download of %s did not produce a file").printf (context);
        }

        int64 actual_size = file_size_or_zero (path);
        if (actual_size <= 0) {
            return _("Download of %s was empty").printf (context);
        }
        if (expected_size > 0 && actual_size != expected_size) {
            return _("Size mismatch for %s (%s / %s)").printf (
                context,
                GLib.format_size ((uint64) actual_size),
                GLib.format_size ((uint64) expected_size)
            );
        }

        if (expected_checksum == "") {
            if (checksum_required) {
                return _("Download of %s has no checksum").printf (context);
            }
        } else {
            var actual = compute_checksum_for_expected (path, expected_checksum, algorithm);
            if (actual == "" || actual.down () != expected_checksum.down ()) {
                warning ("Checksum mismatch for %s (%s)", context, path);
                return _("Checksum mismatch for %s").printf (context);
            }
        }
        return null;
    }

    public bool validate_downloaded_file (
        string path,
        int64 expected_size,
        string expected_checksum,
        string context,
        string? algorithm = null,
        bool checksum_required = false
    ) {
        return downloaded_file_problem (path, expected_size, expected_checksum, context, algorithm, checksum_required) == null;
    }

    public void ensure_downloaded_file (
        string url,
        string dest,
        int64 expected_size,
        string expected_checksum,
        string context,
        ProgressCallback? progress = null,
        string? algorithm = null,
        Cancellable? cancellable = null,
        bool checksum_required = false
    ) throws Error {
        if (validate_downloaded_file (dest, expected_size, expected_checksum, context, algorithm, checksum_required)) return;
        download_file_verified (
            url, dest, expected_size, expected_checksum, context, progress, algorithm, cancellable, checksum_required
        );
    }

    /* Downloads to dest.part, verifies it once, then renames over dest. */
    public void download_file_verified (
        string url,
        string dest,
        int64 expected_size,
        string expected_checksum,
        string context,
        ProgressCallback? progress = null,
        string? algorithm = null,
        Cancellable? cancellable = null,
        bool checksum_required = false
    ) throws Error {
        ensure_dir (Path.get_dirname (dest));
        if (FileUtils.test (dest, FileTest.EXISTS)) FileUtils.remove (dest);
        var partial = dest + ".part";
        try {
            download_file_sync (url, partial, progress, cancellable);
            check_cancelled (cancellable);
            var problem = downloaded_file_problem (partial, expected_size, expected_checksum, context, algorithm, checksum_required);
            if (problem != null) {
                FileUtils.remove (partial);
                throw new IOError.FAILED ("%s", problem);
            }
            if (FileUtils.rename (partial, dest) != 0) {
                throw new IOError.FAILED ("Failed to commit downloaded file for %s", context);
            }
        } catch (Error e) {
            if (!(e is IOError.CANCELLED) && FileUtils.test (partial, FileTest.EXISTS)
                && file_size_or_zero (partial) <= 0) {
                FileUtils.remove (partial);
            }
            throw e;
        }
    }

    public string file_checksum (string path, ChecksumType type) throws Error {
        var checksum = new Checksum (type);
        var input = File.new_for_path (path).read ();
        var buf = new uint8[65536];
        ssize_t n;
        while ((n = input.read (buf)) > 0) {
            checksum.update (buf, n);
        }
        input.close ();
        return checksum.get_string ();
    }

    public bool files_have_same_contents (string a, string b) {
        var a_size = file_size_or_zero (a);
        var b_size = file_size_or_zero (b);
        if (a_size <= 0 || a_size != b_size) return false;

        try {
            return file_checksum (a, ChecksumType.SHA256) == file_checksum (b, ChecksumType.SHA256);
        } catch (Error e) {
            return false;
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
        return "";
    }

    private string compute_checksum_for_expected (string path, string expected_hex, string? algorithm = null) {
        var type = ChecksumType.SHA256;
        var resolved = false;

        if (algorithm != null && algorithm != "") {
            switch (algorithm.down ()) {
                case "sha256":  type = ChecksumType.SHA256; resolved = true; break;
                case "sha512":  type = ChecksumType.SHA512; resolved = true; break;
                case "sha384":  type = ChecksumType.SHA384; resolved = true; break;
                case "sha1":    type = ChecksumType.SHA1;   resolved = true; break;
                case "md5":     type = ChecksumType.MD5;    resolved = true; break;
                default:
                    warning ("Unknown checksum algorithm '%s'; falling back to hex-length inference", algorithm);
                    break;
            }
        }

        if (!resolved) {
            var len = expected_hex.length;
            if (len == 64) {
                type = ChecksumType.SHA256;
            } else if (len == 128) {
                type = ChecksumType.SHA512;
            } else {
                return "";
            }
        }

        try {
            return file_checksum (path, type);
        } catch (Error e) {
            warning ("Failed to compute checksum for %s: %s", path, e.message);
            return "";
        }
    }
}
