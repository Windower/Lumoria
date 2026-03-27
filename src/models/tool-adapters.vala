namespace Lumoria.Models {

    public abstract class BaseToolAdapter : Object, ToolSpec {
        public abstract Utils.ToolKind tool_kind { get; }
        public abstract string tool_id { get; }
        public abstract string tool_name { owned get; }
        public abstract string tool_description { owned get; }
        public abstract string github_repo { get; }
        public abstract string install_base_dir { owned get; }

        protected abstract string cache_kind { get; }
        protected abstract string? match_asset (Utils.GitHubRelease release);
        protected abstract string version_dir_for (string tag);
        protected virtual string checksum_regex () { return ""; }

        protected static string? match_asset_by_regex (Utils.GitHubRelease release, string regex) {
            if (regex == "") return null;
            try {
                var re = new Regex (regex);
                foreach (var a in release.assets) {
                    if (re.match (a.name)) return a.name;
                }
            } catch (RegexError e) {
                warning ("Failed to match asset regex: %s", e.message);
            }
            return null;
        }

        protected string releases_cache_path () {
            return Path.build_filename (Utils.cache_dir (), cache_kind, tool_id, "releases.json");
        }

        protected Gee.ArrayList<Utils.GitHubRelease> fetch_releases (int64 ttl = 6 * 3600) throws Error {
            if (github_repo == "") return new Gee.ArrayList<Utils.GitHubRelease> ();
            return Utils.fetch_github_releases_sync (github_repo, releases_cache_path (), ttl);
        }

        protected Utils.GitHubRelease? find_release_for (ToolVersion ver) throws Error {
            var releases = fetch_releases ();
            if (releases.size == 0) return null;
            if (ver.tag == "latest" || ver.is_latest) return releases[0];
            foreach (var r in releases) {
                if (r.tag_name == ver.tag) return r;
            }
            return null;
        }

        public void invalidate_cache () {
            var path = releases_cache_path ();
            if (FileUtils.test (path, FileTest.EXISTS)) {
                FileUtils.remove (path);
            }
        }

        public string resolve_latest_tag () throws Error {
            var releases = fetch_releases ();
            if (releases.size == 0) return "";
            return releases[0].tag_name;
        }

        public Gee.ArrayList<ToolVersion> list_versions () throws Error {
            var releases = fetch_releases ();
            var versions = new Gee.ArrayList<ToolVersion> ();

            var latest_tag = releases.size > 0 ? releases[0].tag_name : "";
            versions.add (new ToolVersion.latest (latest_tag));

            foreach (var rel in releases) {
                versions.add (new ToolVersion (rel.tag_name, rel.published_at));
            }
            return versions;
        }

        public virtual void install_version (ToolVersion ver, VersionProgress? progress) throws Error {
            if (github_repo == "") throw new IOError.FAILED ("No source for %s %s", cache_kind, tool_id);

            var cache_root = Path.build_filename (Utils.cache_dir (), cache_kind, tool_id);
            Utils.ensure_dir (cache_root);

            var release = find_release_for (ver);
            if (release == null) throw new IOError.FAILED ("Release not found: %s", ver.tag);

            var asset_name = match_asset (release);
            if (asset_name == null) throw new IOError.FAILED ("No matching asset in %s", release.tag_name);

            Utils.GitHubAsset? asset = null;
            foreach (var a in release.assets) {
                if (a.name == asset_name) { asset = a; break; }
            }
            if (asset == null) throw new IOError.FAILED ("Asset not found: %s", asset_name);

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

        protected override string? match_asset (Utils.GitHubRelease release) {
            try {
                var v = spec.effective_variant ("");
                return match_asset_by_regex (release, v.asset_regex);
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

        protected override string? match_asset (Utils.GitHubRelease release) {
            return match_asset_by_regex (release, spec.asset_regex);
        }

        protected override string checksum_regex () {
            return spec.checksum_regex;
        }
    }

}
