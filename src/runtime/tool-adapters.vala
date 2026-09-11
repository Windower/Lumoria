namespace Lumoria.Runtime {

    public abstract class ToolAdapter : Object {
        protected const int DEFAULT_RELEASE_PAGE_SIZE = 30;

        public abstract Utils.ToolKind tool_kind { get; }
        public abstract string tool_id { get; }
        public abstract string tool_name { owned get; }
        public abstract string tool_description { owned get; }
        public abstract string github_repo { get; }
        public abstract string install_base_dir { owned get; }

        protected abstract string cache_kind { get; }
        protected abstract Utils.GitHubAsset? match_asset (Utils.GitHubRelease release);
        protected abstract string version_dir_for (string tag);
        protected virtual string checksum_regex () { return ""; }
        protected virtual string source_archive_kind () { return ""; }
        protected virtual bool skips_version (string tag) { return false; }
        protected virtual bool show_hidden_versions () {
            return Utils.Preferences.instance ().show_hidden_tool_versions;
        }

        protected string releases_cache_dir () {
            return Path.build_filename (Utils.cache_dir (), cache_kind, tool_id);
        }

        protected Utils.GitHubReleasePage fetch_release_page (
            int page,
            int per_page = DEFAULT_RELEASE_PAGE_SIZE,
            int64 ttl = 6 * 3600
        ) throws Error {
            if (github_repo == "") return new Utils.GitHubReleasePage ();
            return Utils.fetch_github_releases_page_sync (
                github_repo,
                releases_cache_dir (),
                page,
                per_page,
                ttl
            );
        }

        protected Utils.GitHubRelease? find_release_for (Models.ToolVersion ver) throws Error {
            if (ver.is_latest || Models.ToolVersionRef.is_latest (ver.tag)) {
                var first = fetch_release_page (1);
                return latest_release (first.releases);
            }

            var page = 1;
            while (true) {
                var release_page = fetch_release_page (page);
                foreach (var r in release_page.releases) {
                    if (r.tag_name != ver.tag) continue;
                    if (match_asset (r) != null || source_archive_url (r) != "") return r;
                    return null;
                }
                if (!release_page.has_more) break;
                page++;
            }
            return null;
        }

        public void invalidate_cache () {
            try {
                var dir = Dir.open (releases_cache_dir ());
                string? name;
                while ((name = dir.read_name ()) != null) {
                    if (name.has_prefix ("releases-page-") && name.has_suffix (".json")) {
                        FileUtils.remove (Path.build_filename (releases_cache_dir (), name));
                    }
                }
            } catch (FileError e) {
                warning ("Failed to invalidate page cache for %s: %s", tool_id, e.message);
            }
        }

        public string resolve_latest_tag () throws Error {
            var releases = fetch_release_page (1).releases;
            var release = latest_release (releases);
            return release != null ? release.tag_name : "";
        }

        public Models.ToolVersionPage list_version_page (int page, int per_page) throws Error {
            var release_page = fetch_release_page (page, per_page);
            var result = new Models.ToolVersionPage ();
            result.page = release_page.page;
            result.per_page = release_page.per_page;
            result.has_more = release_page.has_more;

            if (result.page == 1) {
                var latest = latest_release (release_page.releases);
                var latest_tag = latest != null ? latest.tag_name : "";
                result.versions.add (new Models.ToolVersion.latest (latest_tag));
            }

            foreach (var rel in release_page.releases) {
                if (!release_is_available (rel)) continue;
                result.versions.add (new Models.ToolVersion (rel.tag_name, rel.published_at));
            }
            return result;
        }

        private Utils.GitHubRelease? latest_release (Gee.ArrayList<Utils.GitHubRelease> releases) {
            foreach (var release in releases) {
                if (skips_version (release.tag_name)) continue;
                if (release_is_available (release)) return release;
            }
            return null;
        }

        protected bool release_is_available (Utils.GitHubRelease release) {
            if (skips_version (release.tag_name) && !show_hidden_versions ()) return false;
            if (match_asset (release) != null) return true;
            return source_archive_url (release) != "";
        }

        public virtual void install_version (
            Models.ToolVersion ver,
            Models.VersionProgress? progress,
            Cancellable? cancellable = null
        ) throws Error {
            Utils.check_cancelled (cancellable);
            if (github_repo == "") throw new IOError.FAILED ("No source for %s %s", cache_kind, tool_id);

            var cache_root = Path.build_filename (Utils.cache_dir (), cache_kind, tool_id);
            Utils.ensure_dir (cache_root);

            var release = find_release_for (ver);
            if (release == null) throw new IOError.FAILED ("Release not found: %s", ver.tag);

            var asset = match_asset (release);
            var archive_path = "";
            if (asset != null) {
                archive_path = Path.build_filename (cache_root, asset.name);
                var expected_checksum = Utils.resolve_github_asset_checksum (
                    release,
                    checksum_regex (),
                    asset.name,
                    cache_root,
                    tool_id
                );
                var require_checksum = expected_checksum != "";
                Utils.ensure_downloaded_file (
                    asset.browser_download_url,
                    archive_path,
                    asset.size,
                    expected_checksum,
                    tool_id,
                    (dl, total) => {
                        if (progress != null) progress (dl, total);
                    },
                    null,
                    cancellable,
                    require_checksum
                );
            } else {
                var source_url = source_archive_url (release);
                if (source_url == "") throw new IOError.FAILED ("No matching asset or source archive in %s", release.tag_name);

                archive_path = Path.build_filename (cache_root, source_archive_name (release));
                Utils.ensure_downloaded_file (
                    source_url,
                    archive_path,
                    0,
                    "",
                    tool_id,
                    (dl, total) => {
                        if (progress != null) progress (dl, total);
                    },
                    null,
                    cancellable,
                    false
                );
            }

            Utils.check_cancelled (cancellable);
            var extract_to = Path.build_filename (install_base_dir, version_dir_for (release.tag_name));
            var staging = extract_to + ".part";
            if (FileUtils.test (staging, FileTest.EXISTS)) Utils.remove_recursive (staging);
            Utils.extract_archive (archive_path, staging, {}, cancellable);
            flatten_single_nested_dir (staging);
            try {
                Utils.replace_dir_atomic (
                    staging, extract_to, _("Failed to install %s %s").printf (tool_id, release.tag_name)
                );
            } finally {
                Utils.remove_recursive (staging);
            }
        }

        private void flatten_single_nested_dir (string root) {
            try {
                var dir = Dir.open (root);
                string? first_name = null;
                int count = 0;
                string? name;
                while ((name = dir.read_name ()) != null) {
                    count++;
                    if (count == 1) first_name = name;
                    if (count > 1) return;
                }
                if (count != 1 || first_name == null) return;
                var inner = Path.build_filename (root, first_name);
                if (!FileUtils.test (inner, FileTest.IS_DIR)) return;
                var inner_dir = Dir.open (inner);
                string? child;
                while ((child = inner_dir.read_name ()) != null) {
                    var from = Path.build_filename (inner, child);
                    var to = Path.build_filename (root, child);
                    if (FileUtils.rename (from, to) != 0) {
                        warning ("Failed to flatten %s -> %s", from, to);
                    }
                }
                DirUtils.remove (inner);
            } catch (FileError e) {
                warning ("Failed to flatten %s: %s", root, e.message);
            }
        }

        private string source_archive_url (Utils.GitHubRelease release) {
            switch (source_archive_kind ().strip ().down ()) {
                case "zip":
                    return release.zipball_url;
                case "tar":
                case "tar.gz":
                case "tgz":
                    return release.tarball_url;
                default:
                    return "";
            }
        }

        private string source_archive_name (Utils.GitHubRelease release) {
            var tag = release.tag_name.replace ("/", "-");
            switch (source_archive_kind ().strip ().down ()) {
                case "zip":
                    return "%s-%s-source.zip".printf (tool_id, tag);
                default:
                    return "%s-%s-source.tar.gz".printf (tool_id, tag);
            }
        }

        private string resolve_effective_tag (Models.ToolVersion ver) {
            if (!ver.is_latest) return ver.tag;
            try {
                return resolve_latest_tag ();
            } catch (Error e) {
                warning ("Failed to resolve latest tag for %s: %s", tool_id, e.message);
                return "";
            }
        }

        public virtual void remove_version (Models.ToolVersion ver) throws Error {
            var dir = installed_path (ver);
            if (dir != "" && FileUtils.test (dir, FileTest.IS_DIR)) {
                Utils.remove_recursive (dir);
            }
        }

        public virtual bool is_installed (Models.ToolVersion ver) {
            var path = installed_path (ver);
            return path != "" && FileUtils.test (path, FileTest.IS_DIR);
        }

        public virtual string installed_path (Models.ToolVersion ver) {
            var tag = resolve_effective_tag (ver);
            if (tag == "") return "";
            return Path.build_filename (install_base_dir, version_dir_for (tag));
        }
    }

    public class RunnerToolAdapter : ToolAdapter {
        private Models.RunnerManifest spec;
        private string variant_id;

        public RunnerToolAdapter (Models.RunnerManifest spec, string variant_id = "") {
            this.spec = spec;
            this.variant_id = variant_id;
        }

        public override Utils.ToolKind tool_kind { get { return Utils.ToolKind.RUNNER; } }
        public override string tool_id { get { return spec.id; } }
        public override string tool_name { owned get { return spec.display_label (); } }
        public override string tool_description { owned get { return spec.github_repo; } }
        public override string github_repo { get { return spec.github_repo; } }
        public override string install_base_dir { owned get { return Path.build_filename (Utils.runner_dir (), spec.id); } }
        protected override string cache_kind { get { return "runners"; } }

        protected override string version_dir_for (string tag) {
            return spec.resolve_version_dir (tag);
        }

        protected override Utils.GitHubAsset? match_asset (Utils.GitHubRelease release) {
            try {
                var v = spec.effective_variant (variant_id);
                return Utils.find_github_asset_by_regex (release, v.asset_regex);
            } catch (Error e) {
                warning ("RunnerToolAdapter.match_asset: failed to resolve variant: %s", e.message);
                return null;
            }
        }

        protected override string checksum_regex () {
            try {
                var v = spec.effective_variant (variant_id);
                return v.checksum_regex;
            } catch (Error e) {
                warning ("RunnerToolAdapter.checksum_regex: failed to resolve variant: %s", e.message);
                return "";
            }
        }

        protected override bool skips_version (string tag) {
            return spec.skips_version (tag);
        }

        public override string installed_path (Models.ToolVersion ver) {
            if (ver.is_latest) {
                return base.installed_path (ver);
            }
            var dir = version_dir_for (ver.tag);
            var path = Path.build_filename (install_base_dir, dir);
            if (FileUtils.test (path, FileTest.IS_DIR)) return path;
            var alt = Path.build_filename (install_base_dir, ver.tag);
            if (FileUtils.test (alt, FileTest.IS_DIR)) return alt;
            return path;
        }
    }

    public class ComponentToolAdapter : ToolAdapter {
        private Models.ComponentManifest spec;

        public ComponentToolAdapter (Models.ComponentManifest spec) {
            this.spec = spec;
        }

        public override Utils.ToolKind tool_kind { get { return Utils.ToolKind.COMPONENT; } }
        public override string tool_id { get { return spec.id; } }
        public override string tool_name { owned get { return spec.display_label (); } }
        public override string tool_description { owned get { return spec.github_repo; } }
        public override string github_repo { get { return spec.github_repo; } }
        public override string install_base_dir { owned get { return Path.build_filename (Utils.component_dir (), spec.id); } }
        protected override string cache_kind { get { return "components"; } }

        protected override string version_dir_for (string tag) {
            return tag;
        }

        protected override Utils.GitHubAsset? match_asset (Utils.GitHubRelease release) {
            try {
                return Utils.find_github_asset_by_regex (release, spec.asset_regex);
            } catch (RegexError e) {
                warning ("Failed to match asset regex: %s", e.message);
                return null;
            }
        }

        protected override string checksum_regex () {
            return spec.checksum_regex;
        }

        protected override string source_archive_kind () {
            return spec.source_archive;
        }

        protected override bool skips_version (string tag) {
            return spec.skips_version (tag);
        }
    }

}
