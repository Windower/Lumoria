namespace Lumoria.Models {

    public abstract class BaseToolAdapter : Object, ToolSpec {
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
        protected virtual bool skips_version (string tag) { return false; }

        protected string releases_cache_path () {
            return Path.build_filename (Utils.cache_dir (), cache_kind, tool_id, "releases.json");
        }

        protected string releases_cache_dir () {
            return Path.build_filename (Utils.cache_dir (), cache_kind, tool_id);
        }

        protected Gee.ArrayList<Utils.GitHubRelease> fetch_releases (int64 ttl = 6 * 3600) throws Error {
            if (github_repo == "") return new Gee.ArrayList<Utils.GitHubRelease> ();
            return Utils.fetch_github_releases_sync (github_repo, releases_cache_path (), ttl);
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

        protected Utils.GitHubRelease? find_release_for (ToolVersion ver) throws Error {
            if (ver.tag == "latest" || ver.is_latest) {
                var first = fetch_release_page (1);
                return latest_release (first.releases);
            }

            var page = 1;
            while (true) {
                var release_page = fetch_release_page (page);
                foreach (var r in release_page.releases) {
                    if (!release_is_available (r)) continue;
                    if (r.tag_name == ver.tag) return r;
                }
                if (!release_page.has_more) break;
                page++;
            }
            return null;
        }

        public void invalidate_cache () {
            var path = releases_cache_path ();
            if (FileUtils.test (path, FileTest.EXISTS)) {
                FileUtils.remove (path);
            }
            try {
                var dir = Dir.open (releases_cache_dir ());
                string? name;
                while ((name = dir.read_name ()) != null) {
                    if (name.has_prefix ("releases-page-") && name.has_suffix (".json")) {
                        FileUtils.remove (Path.build_filename (releases_cache_dir (), name));
                    }
                }
            } catch (FileError e) {
                // No page cache exists yet.
            }
        }

        public string resolve_latest_tag () throws Error {
            var releases = fetch_release_page (1).releases;
            var release = latest_release (releases);
            return release != null ? release.tag_name : "";
        }

        public Gee.ArrayList<ToolVersion> list_versions () throws Error {
            var releases = fetch_release_page (1).releases;
            var versions = new Gee.ArrayList<ToolVersion> ();

            var latest = latest_release (releases);
            var latest_tag = latest != null ? latest.tag_name : "";
            versions.add (new ToolVersion.latest (latest_tag));

            foreach (var rel in releases) {
                if (!release_is_available (rel)) continue;
                versions.add (new ToolVersion (rel.tag_name, rel.published_at));
            }
            return versions;
        }

        public ToolVersionPage list_version_page (int page, int per_page) throws Error {
            var release_page = fetch_release_page (page, per_page);
            var result = new ToolVersionPage ();
            result.page = release_page.page;
            result.per_page = release_page.per_page;
            result.has_more = release_page.has_more;

            if (result.page == 1) {
                var latest = latest_release (release_page.releases);
                var latest_tag = latest != null ? latest.tag_name : "";
                result.versions.add (new ToolVersion.latest (latest_tag));
            }

            foreach (var rel in release_page.releases) {
                if (!release_is_available (rel)) continue;
                result.versions.add (new ToolVersion (rel.tag_name, rel.published_at));
            }
            return result;
        }

        private Utils.GitHubRelease? latest_release (Gee.ArrayList<Utils.GitHubRelease> releases) {
            foreach (var release in releases) {
                if (release_is_available (release)) return release;
            }
            return null;
        }

        protected bool release_is_available (Utils.GitHubRelease release) {
            if (skips_version (release.tag_name)) return false;
            return match_asset (release) != null;
        }

        public virtual void install_version (ToolVersion ver, VersionProgress? progress) throws Error {
            if (github_repo == "") throw new IOError.FAILED ("No source for %s %s", cache_kind, tool_id);

            var cache_root = Path.build_filename (Utils.cache_dir (), cache_kind, tool_id);
            Utils.ensure_dir (cache_root);

            var release = find_release_for (ver);
            if (release == null) throw new IOError.FAILED ("Release not found: %s", ver.tag);

            var asset = match_asset (release);
            if (asset == null) throw new IOError.FAILED ("No matching asset in %s", release.tag_name);

            var archive_path = Path.build_filename (cache_root, asset.name);
            var expected_checksum = resolve_asset_checksum (release, asset.name, cache_root);
            Utils.ensure_downloaded_file (
                asset.browser_download_url,
                archive_path,
                asset.size,
                expected_checksum,
                tool_id,
                (dl, total) => {
                    if (progress != null) progress (dl, total);
                }
            );

            var extract_to = Path.build_filename (install_base_dir, version_dir_for (release.tag_name));
            Utils.extract_archive (archive_path, extract_to);
        }

        private string resolve_asset_checksum (Utils.GitHubRelease release, string asset_name, string cache_root) {
            return Utils.resolve_github_asset_checksum (
                release,
                checksum_regex (),
                asset_name,
                cache_root,
                tool_id
            );
        }

        private string resolve_effective_tag (ToolVersion ver) {
            if (!ver.is_latest) return ver.tag;
            try {
                return resolve_latest_tag ();
            } catch (Error e) {
                warning ("Failed to resolve latest tag for %s: %s", tool_id, e.message);
                return "";
            }
        }

        public virtual void remove_version (ToolVersion ver) throws Error {
            var dir = installed_path (ver);
            if (dir != "" && FileUtils.test (dir, FileTest.IS_DIR)) {
                Utils.remove_recursive (dir);
            }
        }

        public virtual bool is_installed (ToolVersion ver) {
            var path = installed_path (ver);
            return path != "" && FileUtils.test (path, FileTest.IS_DIR);
        }

        public virtual string installed_path (ToolVersion ver) {
            var tag = resolve_effective_tag (ver);
            if (tag == "") return "";
            return Path.build_filename (install_base_dir, version_dir_for (tag));
        }
    }

    public class RunnerToolAdapter : BaseToolAdapter {
        private RunnerSpec spec;

        public RunnerToolAdapter (RunnerSpec spec) {
            this.spec = spec;
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
                var v = spec.effective_variant ("");
                return Utils.find_github_asset_by_regex (release, v.asset_regex);
            } catch (Error e) {
                warning ("RunnerToolAdapter.match_asset: failed to resolve variant: %s", e.message);
                return null;
            }
        }

        protected override string checksum_regex () {
            try {
                var v = spec.effective_variant ("");
                return v.checksum_regex;
            } catch (Error e) {
                warning ("RunnerToolAdapter.checksum_regex: failed to resolve variant: %s", e.message);
                return "";
            }
        }

        protected override bool skips_version (string tag) {
            return spec.skips_version (tag);
        }

        public override string installed_path (ToolVersion ver) {
            if (ver.is_latest) {
                try {
                    var tag = resolve_latest_tag ();
                    if (tag != "") return installed_path (new ToolVersion (tag));
                } catch (Error e) {
                    warning ("Failed to resolve latest tag for RunnerToolAdapter installed_path: %s", e.message);
                }
                return "";
            }
            var dir = version_dir_for (ver.tag);
            var path = Path.build_filename (install_base_dir, dir);
            if (FileUtils.test (path, FileTest.IS_DIR)) return path;
            var alt = Path.build_filename (install_base_dir, ver.tag);
            if (FileUtils.test (alt, FileTest.IS_DIR)) return alt;
            return path;
        }
    }

    public class ComponentToolAdapter : BaseToolAdapter {
        private ComponentSpec spec;

        public ComponentToolAdapter (ComponentSpec spec) {
            this.spec = spec;
        }

        public Gee.ArrayList<Models.InstallStep> steps { get { return spec.steps; } }
        public Gee.HashMap<string, string> overrides { get { return spec.overrides; } }
        public Gee.HashMap<string, string> system_env_defaults { get { return spec.system_env_defaults; } }

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

        protected override bool skips_version (string tag) {
            return spec.skips_version (tag);
        }
    }

}
