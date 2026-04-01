namespace Lumoria.Runtime {

    public class DownloadResult : Object {
        public string version { get; set; default = ""; }
        public string archive_path { get; set; default = ""; }
        public string extracted_to { get; set; default = ""; }
    }

    public delegate void StepCallback (string description);
    public delegate void DownloadProgress (int64 downloaded, int64 total);

    public DownloadResult download_and_extract_runner (
        Models.RunnerSpec spec,
        string variant_id,
        string version,
        DownloadProgress? progress,
        RuntimeLog logger
    ) throws Error {
        var v = spec.effective_variant (variant_id);
        var cache_root = Path.build_filename (Utils.cache_dir (), "runners", spec.id);
        var extract_root = Path.build_filename (Utils.runner_dir (), spec.id);
        Utils.ensure_dir (cache_root);
        Utils.ensure_dir (extract_root);

        var releases_path = Path.build_filename (cache_root, "releases.json");
        var releases = Utils.fetch_github_releases_sync (spec.github_repo, releases_path, 6 * 3600);

        Utils.GitHubRelease? release = select_release (releases, version, logger);
        if (release == null) {
            throw new IOError.FAILED ("No release found for version: %s", version);
        }

        var version_dir = spec.resolve_version_dir (release.tag_name);
        var extract_to = Path.build_filename (extract_root, version_dir);
        if (FileUtils.test (extract_to, FileTest.IS_DIR)) {
            var result = new DownloadResult ();
            result.version = release.tag_name;
            result.extracted_to = normalize_runner_root (extract_to, logger);
            return result;
        }

        var alt_path = Path.build_filename (extract_root, release.tag_name);
        if (alt_path != extract_to && FileUtils.test (alt_path, FileTest.IS_DIR)) {
            var result = new DownloadResult ();
            result.version = release.tag_name;
            result.extracted_to = normalize_runner_root (alt_path, logger);
            return result;
        }

        var asset = find_asset (release, v.asset_regex, logger);
        if (asset == null) {
            throw new IOError.FAILED ("No asset matching regex '%s' in release %s", v.asset_regex, release.tag_name);
        }

        var archive_path = Path.build_filename (cache_root, asset.name);
        var checksum_pattern = v.checksum_regex != "" ? v.checksum_regex : spec.checksum_regex;
        var expected_checksum = Utils.resolve_github_asset_checksum (
            release,
            checksum_pattern,
            asset.name,
            cache_root,
            "runner " + spec.id
        );
        Utils.ensure_downloaded_file (
            asset.browser_download_url,
            archive_path,
            asset.size,
            expected_checksum,
            "runner " + spec.id,
            (dl, total) => {
                if (progress != null) progress (dl, total);
            }
        );

        Utils.extract_archive (archive_path, extract_to);

        var result = new DownloadResult ();
        result.version = release.tag_name;
        result.archive_path = archive_path;
        result.extracted_to = normalize_runner_root (extract_to, logger);
        return result;
    }

    private Utils.GitHubRelease? select_release (
        Gee.ArrayList<Utils.GitHubRelease> releases,
        string version,
        RuntimeLog logger
    ) {
        if (releases.size == 0) return null;
        if (version == "" || version == "latest") return releases[0];
        foreach (var r in releases) {
            if (r.tag_name == version) return r;
        }
        logger.typed (LogType.WARN, "No release matching tag '%s'; %d releases available".printf (
            version, releases.size
        ));
        return null;
    }

    private Utils.GitHubAsset? find_asset (Utils.GitHubRelease release, string regex, RuntimeLog logger) {
        try {
            return Utils.find_github_asset_by_regex (release, regex);
        } catch (RegexError e) {
            logger.typed (LogType.WARN, "Invalid asset regex '%s': %s".printf (regex, e.message));
            return null;
        }
    }

    private string normalize_runner_root (string root, RuntimeLog logger) {
        try {
            var dir = Dir.open (root);
            string? first_name = null;
            int count = 0;
            string? name;
            while ((name = dir.read_name ()) != null) {
                count++;
                if (count == 1) first_name = name;
                if (count > 1) return root;
            }
            if (count == 1 && first_name != null) {
                var inner = Path.build_filename (root, first_name);
                if (FileUtils.test (inner, FileTest.IS_DIR)) {
                    var inner_dir = Dir.open (inner);
                    string? child;
                    while ((child = inner_dir.read_name ()) != null) {
                        var src = Path.build_filename (inner, child);
                        var dst = Path.build_filename (root, child);
                        FileUtils.rename (src, dst);
                    }
                    DirUtils.remove (inner);
                }
            }
        } catch (FileError e) {
            logger.typed (LogType.WARN, "Failed to normalize runner root: %s".printf (e.message));
        }
        return root;
    }

}
