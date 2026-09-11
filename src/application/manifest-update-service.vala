namespace Lumoria.Application {

    public delegate void ManifestCheckReport (string message, bool error);

    public enum ManifestUpdateStatus {
        UP_TO_DATE,
        AVAILABLE,
        SKIPPED,
        DISABLED
    }

    public class ManifestFileEntry : Object {
        public string path { get; set; default = ""; }
        public string sha256 { get; set; default = ""; }
        public int64 size { get; set; default = 0; }
    }

    public class ManifestIndex : Object {
        public int format_version { get; set; default = 0; }
        public string revision { get; set; default = ""; }
        public string generated_at { get; set; default = ""; }
        public string min_app_version { get; set; default = ""; }
        public Gee.ArrayList<ManifestFileEntry> files {
            get; owned set; default = new Gee.ArrayList<ManifestFileEntry> ();
        }

        public static ManifestIndex from_json (Json.Object obj) throws Error {
            var m = new ManifestIndex ();
            m.format_version = (int) Models.json_int (obj, "format_version");
            m.revision = Models.json_string (obj, "revision");
            m.generated_at = Models.json_string (obj, "generated_at");
            m.min_app_version = Models.json_string (obj, "min_app_version");
            if (!obj.has_member ("files")) {
                throw new LumoriaError.INVALID_MANIFEST (_("Manifest index is missing files"));
            }
            var arr = obj.get_array_member ("files");
            for (uint i = 0; i < arr.get_length (); i++) {
                var file_obj = arr.get_object_element (i);
                var file = new ManifestFileEntry ();
                file.path = Models.json_require_string (file_obj, "path");
                file.sha256 = Models.json_require_string (file_obj, "sha256");
                file.size = Models.json_int (file_obj, "size");
                m.files.add (file);
            }
            return m;
        }
    }

    public class ManifestUpdateCheck : Object {
        public ManifestUpdateStatus status { get; set; default = ManifestUpdateStatus.UP_TO_DATE; }
        public string message { get; set; default = ""; }
        public ManifestIndex? remote { get; set; default = null; }
        public string index_payload { get; set; default = ""; }
        public Gee.ArrayList<ManifestFileEntry> changed {
            get; owned set; default = new Gee.ArrayList<ManifestFileEntry> ();
        }
    }

    /*
     * Network and disk work runs on worker threads and only returns values; everything that
     * touches preferences, caches or emits signals happens here on the main thread.
     */

    public class ManifestUpdateService : Object {
        private const string INDEX_FILE = "manifest.json";

        public signal void status_changed (string status);
        public signal void progress (int64 downloaded, int64 total);
        public signal void checking (bool manual);
        public signal void consent_needed (ManifestUpdateCheck result, owned ManifestCheckReport? report);
        public signal void apply_started ();
        public signal void apply_finished (Error? error);

        public bool busy { get; private set; default = false; }
        public bool catalog_refresh_busy { get; private set; default = false; }

        private Context ctx;
        private Cancellable? apply_cancellable;

        public ManifestUpdateService (Context ctx) {
            this.ctx = ctx;
        }

        public string index_url () {
            return "%s/%d/%s".printf (origin (), Config.MANIFEST_FORMAT_VERSION, INDEX_FILE);
        }

        public string file_url (string relative_path, string sha256 = "") {
            var url = "%s/%d/%s".printf (origin (), Config.MANIFEST_FORMAT_VERSION, relative_path);
            return sha256 == "" ? url : "%s?h=%s".printf (url, sha256);
        }

        private static string origin () {
            var url = Config.MANIFEST_BASE_URL.strip ();
            while (url.has_suffix ("/")) {
                url = url.substring (0, url.length - 1);
            }
            return url;
        }

        /* Synchronous check for callers without a main loop (CLI). */
        public ManifestUpdateCheck check (bool force, Cancellable? cancellable = null) throws Error {
            var result = fetch_check (force, cancellable);
            record_check (result);
            return result;
        }

        private ManifestUpdateCheck fetch_check (bool force, Cancellable? cancellable) throws Error {
            var prefs = Utils.Preferences.instance ();
            if (!prefs.updates_lumoria) {
                var disabled = new ManifestUpdateCheck ();
                disabled.status = ManifestUpdateStatus.DISABLED;
                disabled.message = _("Manifest updates are turned off.");
                return disabled;
            }

            var payload = Utils.fetch_text_sync (index_url (), cancellable);
            Models.ManifestSchema.validate_json ("index", payload);
            var remote = ManifestIndex.from_json (Models.parse_data_object (payload));
            if (remote.format_version != Config.MANIFEST_FORMAT_VERSION) {
                throw new LumoriaError.FAILED (
                    _("Remote format version %d does not match %d").printf (
                        remote.format_version,
                        Config.MANIFEST_FORMAT_VERSION
                    )
                );
            }
            if (remote.min_app_version != "" && compare_versions (Config.APP_VERSION, remote.min_app_version) < 0) {
                throw new LumoriaError.FAILED (
                    _("Lumoria %s is required for this manifest tree (running %s)").printf (
                        remote.min_app_version,
                        Config.APP_VERSION
                    )
                );
            }
            var changed = diff_files (remote);
            var result = new ManifestUpdateCheck ();
            result.remote = remote;
            result.index_payload = payload;
            result.changed = changed;
            if (changed.size == 0) {
                result.status = ManifestUpdateStatus.UP_TO_DATE;
                result.message = _("Manifests are up to date");
                return result;
            }
            if (!force && remote.revision == prefs.updates_skipped_revision) {
                result.status = ManifestUpdateStatus.SKIPPED;
                result.message = _("A manifest update is available.");
                return result;
            }
            result.status = ManifestUpdateStatus.AVAILABLE;
            result.message = _("A manifest update is available.");
            return result;
        }

        private void record_check (ManifestUpdateCheck result) {
            if (result.status == ManifestUpdateStatus.DISABLED) return;
            try {
                Models.ManifestStore.ensure_cache_dirs ();
                Utils.write_text_atomic (Models.ManifestStore.current_file (INDEX_FILE), result.index_payload);
                Utils.StorageCache.instance ().invalidate (Utils.StorageCategory.CACHE_MANIFESTS);
            } catch (Error e) {
                warning ("Failed to cache manifest index: %s", e.message);
            }
            Utils.Preferences.instance ().mark_manifests_checked ();
        }

        public void cancel () {
            if (apply_cancellable != null) apply_cancellable.cancel ();
        }

        public void apply (
            ManifestIndex remote,
            Cancellable? cancellable = null,
            bool resources = true
        ) throws Error {
            if (busy) {
                throw new LumoriaError.BUSY (_("A manifest update is already running"));
            }
            busy = true;
            try {
                run_apply (remote, cancellable, resources);
                Utils.StorageCache.instance ().invalidate (Utils.StorageCategory.CACHE_MANIFESTS);
            } finally {
                busy = false;
            }
        }

        private void run_apply (ManifestIndex remote, Cancellable? cancellable, bool resources) throws Error {
            apply_cancellable = cancellable ?? new Cancellable ();
            try {
                apply_locked (remote, apply_cancellable);
                if (resources && Utils.Preferences.instance ().updates_resources) {
                    report_status (_("Downloading resources…"));
                    try {
                        Application.ResourceStore.instance ().ensure_all (apply_cancellable);
                    } catch (Error e) {
                        warning ("Resource download failed after manifest apply: %s", e.message);
                        throw new LumoriaError.FAILED (
                            _("Manifests updated, but resources failed: %s").printf (user_error (e))
                        );
                    }
                }
            } finally {
                apply_cancellable = null;
                try {
                    discard_staging ();
                } catch (Error e) {
                    warning ("Failed to clean manifest staging: %s", e.message);
                }
            }
        }

        public void check_startup () {
            check_async ();
            var prefs = Utils.Preferences.instance ();
            refresh_tool_release_indexes (prefs.updates_runners, prefs.updates_components);
        }

        public void refresh_tool_release_indexes (
            bool runners,
            bool components,
            bool force = false,
            owned ManifestCheckReport? report = null
        ) {
            if (catalog_refresh_busy) {
                if (report != null) report (_("A catalog refresh is already running."), true);
                return;
            }

            var jobs = new Gee.ArrayList<Runtime.ToolAdapter> ();
            if (runners) {
                foreach (var spec in ctx.runner_manifests) {
                    var adapter = new Runtime.RunnerToolAdapter (spec);
                    if (adapter.github_repo != "") jobs.add (adapter);
                }
            }
            if (components) {
                foreach (var spec in Models.ManifestRepository.shared ().components) {
                    var adapter = new Runtime.ComponentToolAdapter (spec);
                    if (adapter.github_repo != "") jobs.add (adapter);
                }
            }
            if (jobs.size == 0) {
                if (report != null) report (_("No GitHub catalogs to refresh."), false);
                return;
            }

            catalog_refresh_busy = true;
            var batch = new ReleaseIndexBatch ();
            Utils.run_background ("tool-release-refresh", () => {
                Utils.get_api_session ();
                Utils.run_parallel<Runtime.ToolAdapter> (jobs, () => new ReleaseIndexWorker (batch, force));
            }, (error) => {
                catalog_refresh_busy = false;
                if (report == null) return;
                if (error != null) {
                    warning ("Release index refresh failed: %s", error.message);
                    report (user_error (error), true);
                } else if (batch.failures.size > 0) {
                    report (_("Could not refresh %s").printf (string.joinv (", ", Utils.strv (batch.failures))), true);
                } else if (runners && !components) {
                    report (_("Runner catalogs are up to date"), false);
                } else if (components && !runners) {
                    report (_("Component catalogs are up to date"), false);
                } else {
                    report (_("Catalogs are up to date"), false);
                }
            });
        }

        public void check_async (bool manual = false, owned ManifestCheckReport? report = null) {
            if (busy) {
                if (report != null) report (_("A manifest update is already running."), true);
                return;
            }
            if (!Utils.Preferences.instance ().updates_lumoria) {
                if (report != null) report (_("Manifest updates are turned off."), true);
                return;
            }

            checking (manual);

            ManifestUpdateCheck? result = null;
            Utils.run_background ("manifest-check", () => {
                result = fetch_check (manual, Utils.BackgroundJobs.instance ().cancellable);
            }, (error) => {
                if (result != null) record_check (result);
                handle_check (manual, result, error, (owned) report);
            });
        }

        internal void report_status (string status) {
            Idle.add (() => {
                status_changed (status);
                return false;
            });
        }

        internal void report_progress (int64 downloaded, int64 total) {
            Idle.add (() => {
                progress (downloaded, total);
                return false;
            });
        }

        private void handle_check (
            bool manual,
            ManifestUpdateCheck? result,
            Error? error,
            owned ManifestCheckReport? report
        ) {
            if (error != null) {
                apply_finished (error);
                if (report != null) report (user_error (error), true);
                else ctx.show_toast (user_error (error));
                return;
            }
            if (result == null) {
                apply_finished (null);
                return;
            }

            if (result.status == ManifestUpdateStatus.UP_TO_DATE
                || result.status == ManifestUpdateStatus.DISABLED) {
                apply_finished (null);
                if (report != null) report (result.message, false);
                return;
            }
            if (result.status == ManifestUpdateStatus.SKIPPED) {
                apply_finished (null);
                if (manual) consent_needed (result, (owned) report);
                return;
            }
            if (result.status != ManifestUpdateStatus.AVAILABLE) {
                apply_finished (null);
                if (report != null) report (result.message, true);
                else ctx.show_toast (result.message);
                return;
            }

            var prefs = Utils.Preferences.instance ();
            if (prefs.updates_manifests_auto && !prefs.updates_manifests_ask) {
                apply_async (result, (owned) report);
                return;
            }
            apply_finished (null);
            if (!manual && !prefs.updates_manifests_ask) return;
            consent_needed (result, (owned) report);
        }

        public void apply_async (
            ManifestUpdateCheck result,
            owned ManifestCheckReport? report = null
        ) {
            if (result.remote == null) return;
            if (busy) {
                if (report != null) report (_("A manifest update is already running."), true);
                return;
            }
            if (!ctx.try_begin (ExclusiveKind.MANIFEST)) {
                var message = ctx.exclusive_busy_message ();
                if (report != null) report (message, true);
                else ctx.show_toast (message);
                return;
            }
            var remote = result.remote;
            busy = true;
            ctx.state.set_busy (_("Updating manifests…"));
            apply_started ();
            Utils.run_background ("manifest-apply", () => {
                run_apply (remote, null, true);
            }, (error) => {
                busy = false;
                ctx.state.clear_busy ();
                ctx.end_session (ExclusiveKind.MANIFEST);
                ctx.reload_manifests ();
                Utils.StorageCache.instance ().invalidate (Utils.StorageCategory.CACHE_MANIFESTS);
                if (error == null) {
                    apply_finished (null);
                    if (report != null) report (_("Manifests updated"), false);
                } else {
                    apply_finished (error);
                    if (report != null) report (user_error (error), true);
                    else ctx.show_toast (user_error (error));
                }
            });
        }

        private void apply_locked (ManifestIndex remote, Cancellable? cancellable) throws Error {
            Models.ManifestStore.ensure_cache_dirs ();
            discard_staging ();
            Utils.ensure_dir (Models.ManifestStore.staging_dir ());

            var changed = diff_files (remote);
            int64 total_bytes = 0;
            foreach (var file in changed) {
                total_bytes += file.size > 0 ? file.size : 0;
            }

            if (changed.size > 0) {
                report_status (_("Downloading manifests…"));
                var tracker = new ManifestDownloadProgress (this, total_bytes, changed.size);
                Utils.run_parallel<ManifestFileEntry> (changed, () => {
                    return new ManifestDownloadWorker (this, tracker, cancellable);
                }, cancellable);
                report_progress (tracker.downloaded, total_bytes);
            }

            report_status (_("Validating…"));
            var merged = Path.build_filename (Models.ManifestStore.staging_dir (), "merged");
            build_merged_tree (merged, remote);
            validate_merged (merged, remote);

            report_status (_("Applying…"));
            commit_merged (merged);
            report_status (_("Manifests updated"));
        }

        private Gee.ArrayList<ManifestFileEntry> diff_files (ManifestIndex remote) throws Error {
            var changed = new Gee.ArrayList<ManifestFileEntry> ();
            foreach (var file in remote.files) {
                if (!local_hash_matches (file)) changed.add (file);
            }
            return changed;
        }

        private bool local_hash_matches (ManifestFileEntry file) {
            string cached;
            try {
                cached = Models.ManifestStore.current_file (file.path);
            } catch (Error e) {
                return false;
            }
            if (FileUtils.test (cached, FileTest.IS_REGULAR)) {
                return Utils.downloaded_file_problem (cached, file.size, file.sha256, file.path) == null;
            }
            var text = Models.ManifestStore.load_text (file.path, true);
            if (text == null) return false;
            var actual = Checksum.compute_for_string (ChecksumType.SHA256, text);
            return actual.down () == file.sha256.down ();
        }

        private void build_merged_tree (string merged, ManifestIndex remote) throws Error {
            remove_tree (merged);
            Utils.ensure_dir (merged);
            var index = Models.ManifestStore.current_file (INDEX_FILE);
            if (FileUtils.test (index, FileTest.IS_REGULAR)) {
                Utils.copy_path (index, Path.build_filename (merged, INDEX_FILE));
            }
            foreach (var file in remote.files) {
                var dest = Utils.join_inside (merged, file.path);
                Utils.ensure_dir (Path.get_dirname (dest));
                var staged = Models.ManifestStore.staging_file (file.path);
                if (FileUtils.test (staged, FileTest.IS_REGULAR)) {
                    Utils.copy_path (staged, dest);
                    continue;
                }
                var cached = Models.ManifestStore.current_file (file.path);
                if (FileUtils.test (cached, FileTest.IS_REGULAR)) {
                    Utils.copy_path (cached, dest);
                    continue;
                }
                var text = Models.ManifestStore.load_text (file.path, true);
                if (text == null) {
                    throw new LumoriaError.NOT_FOUND (_("Missing merged manifest file %s").printf (file.path));
                }
                Utils.write_text_atomic (dest, text);
            }
        }

        private void validate_merged (string merged, ManifestIndex remote) throws Error {
            foreach (var file in remote.files) {
                var path = Utils.join_inside (merged, file.path);
                if (!Utils.validate_downloaded_file (path, file.size, file.sha256, file.path)) {
                    throw new LumoriaError.FAILED (_("Merged tree failed checksum for %s").printf (file.path));
                }
                if (file.path.has_suffix (".json") && !file.path.has_prefix ("schemas/")) {
                    string json;
                    FileUtils.get_contents (path, out json);
                    Models.ManifestSchema.validate_relative (file.path, json);
                }
            }
            Models.ManifestStore.validate_tree (merged);
        }

        private void commit_merged (string merged) throws Error {
            Utils.replace_dir_atomic (
                merged, Models.ManifestStore.current_dir (), _("Failed to replace installer manifest cache")
            );
        }

        private void discard_staging () throws Error {
            remove_tree (Models.ManifestStore.staging_dir ());
        }

        private static void remove_tree (string path) throws Error {
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            if (!Utils.remove_recursive (path)) {
                throw new IOError.FAILED (_("Could not remove %s").printf (path));
            }
        }

        private static int compare_versions (string a, string b) {
            var left = a.split (".");
            var right = b.split (".");
            int n = int.max (left.length, right.length);
            for (int i = 0; i < n; i++) {
                int av = i < left.length ? version_component (left[i]) : 0;
                int bv = i < right.length ? version_component (right[i]) : 0;
                if (av != bv) return av - bv;
            }
            return 0;
        }

        private static int version_component (string part) {
            var digits = new StringBuilder ();
            for (int i = 0; i < part.length; i++) {
                var c = part[i];
                if (c < '0' || c > '9') break;
                digits.append_c (c);
            }
            return digits.len == 0 ? 0 : int.parse (digits.str);
        }
    }
}
