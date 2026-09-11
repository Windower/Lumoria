namespace Lumoria.Runtime {
    public class WineRuntimeRequest : Object {
        public Models.RunnerManifest runner_manifest { get; set; }
        public string variant_id { get; set; default = ""; }
        public string runner_version { get; set; default = Models.ToolVersionRef.WIRE_LATEST; }
        public string prefix_root { get; set; default = ""; }
        public string wine_arch { get; set; default = ""; }
        public string sync_mode { get; set; default = ""; }
        public string wine_debug { get; set; default = ""; }
        public bool? wine_wayland = null;
        public bool? large_address_aware = null;
        public Gee.HashMap<string, string> environment_overrides {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
        public DownloadProgress? download_progress = null;
        public LaunchPolicy launch_policy { get; set; default = LaunchPolicy.INTERACTIVE; }
        public Models.PrefixRunnerState? runner_state { get; set; default = null; }

        public static WineRuntimeRequest from_prefix (
            Models.PrefixEntry entry,
            Models.RunnerManifest runner_manifest,
            LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE
        ) {
            var request = new WineRuntimeRequest ();
            request.runner_manifest = runner_manifest;
            request.variant_id = entry.variant_id;
            request.runner_version = entry.runner_version;
            request.prefix_root = entry.resolved_path ();
            request.wine_arch = entry.wine_arch;
            request.sync_mode = entry.sync_mode;
            request.wine_debug = entry.wine_debug;
            request.wine_wayland = entry.wine_wayland;
            request.large_address_aware = entry.large_address_aware;
            request.environment_overrides = entry.runtime_env_vars;
            request.launch_policy = launch_policy;
            request.runner_state = entry.runner_state;
            return request;
        }
    }

    public class WineRuntime : Object {
        public Models.RunnerManifest     runner_manifest    { get; private set; }
        public Models.RunnerVariant  variant        { get; private set; }
        public string                runner_version { get; private set; }
        public DownloadResult        extract_result { get; private set; }
        public WinePaths             paths          { get; private set; }
        public string                prefix_path    { get; private set; }
        public string                wine_arch      { get; private set; }
        public WineEnv               env            { get; private set; }

        internal WineRuntime (
            Models.RunnerManifest runner_manifest,
            Models.RunnerVariant variant,
            string runner_version,
            DownloadResult extract_result,
            WinePaths paths,
            string prefix_path,
            string wine_arch,
            WineEnv env
        ) {
            this.runner_manifest = runner_manifest;
            this.variant = variant;
            this.runner_version = runner_version;
            this.extract_result = extract_result;
            this.paths = paths;
            this.prefix_path = prefix_path;
            this.wine_arch = wine_arch;
            this.env = env;
        }
    }

    public void try_stop_prefix_wineserver (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests
    ) {
        try {
            var runner_manifest = Models.RunnerManifest.resolve_for_entry (runner_manifests, entry);
            var request = WineRuntimeRequest.from_prefix (
                entry, runner_manifest, LaunchPolicy.OFFLINE_FAST_START
            );
            var logger = new RuntimeLog ();
            var runtime = prepare_wine_runtime (request, logger);
            shutdown_wineserver (runtime.paths, runtime.env, logger);
        } catch (Error e) {
            warning ("Wineserver stop skipped for %s: %s", entry.id, e.message);
        }
    }

    public WineRuntime prepare_wine_runtime (
        WineRuntimeRequest request,
        RuntimeLog logger,
        Cancellable? cancellable = null
    ) throws Error {
        var runner_manifest = request.runner_manifest;
        var variant_id = request.variant_id;
        var runner_version = request.runner_version;
        var prefix_root = request.prefix_root;
        var resolved_version = resolve_runner_version_for_policy (
            runner_manifest,
            variant_id,
            runner_version,
            request.launch_policy,
            request.runner_state
        );
        var extract = download_and_extract_runner (
            runner_manifest,
            variant_id,
            resolved_version,
            request.download_progress,
            logger,
            request.launch_policy == LaunchPolicy.INTERACTIVE,
            cancellable
        );
        var paths = resolve_wine_paths (extract.extracted_to, runner_manifest, variant_id);
        var variant = runner_manifest.effective_variant (variant_id);
        var pfx_path = PrefixPaths.from_root (prefix_root).wine_prefix;
        var arch = variant.effective_arch (request.wine_arch);
        var wayland_pref = Utils.Preferences.resolve_wine_wayland (request.wine_wayland);
        if (!wayland_pref && !Utils.EnvironmentInfo.has_x11_display ()) {
            logger.typed (
                LogType.WARN,
                "Wine Wayland is disabled but no X11 display is available; using the Wayland driver anyway."
                + (Utils.EnvironmentInfo.is_sandboxed ()
                    ? " Grant the X11 socket (flatpak override --user --socket=x11 net.windower.Lumoria) to use XWayland. Depending on your version of Flatpak, you might need to also disable Fallback X11 (--nosocket=fallback-x11)."
                    : "")
            );
        }
        var env = build_wine_env (paths, request);
        if (request.large_address_aware == true) {
            env.set_var ("WINE_LARGE_ADDRESS_AWARE", "1");
        }
        apply_env_overrides (env, Utils.Preferences.instance ().get_runtime_env_vars ());
        apply_env_overrides (env, request.environment_overrides);
        apply_runtime_logging_policy (env);
        return new WineRuntime (
            runner_manifest, variant, extract.version, extract,
            paths, pfx_path, arch, env
        );
    }

    private string resolve_runner_version_for_policy (
        Models.RunnerManifest runner_manifest,
        string variant_id,
        string runner_version,
        LaunchPolicy launch_policy,
        Models.PrefixRunnerState? runner_state
    ) throws Error {
        if (launch_policy == LaunchPolicy.INTERACTIVE) {
            return Utils.Preferences.resolve_version (runner_manifest.id, runner_version);
        }

        var requested = runner_version.strip ();
        if (Models.ToolVersionRef.is_pinned (requested)) {
            return requested;
        }

        var effective_variant = runner_manifest.effective_variant (variant_id);
        if (runner_state != null
            && runner_state.runner_id == runner_manifest.id
            && (runner_state.variant_id == effective_variant.id || runner_state.variant_id == "")
            && runner_state.resolved_version != "") {
            return runner_state.resolved_version;
        }

        throw new LumoriaError.FAILED (
            _("No installed runner version is stamped for %s. Open Lumoria once to prepare this prefix before launching from CLI.").printf (
                runner_manifest.id
            )
        );
    }

    public void ensure_prefix_runner_current (
        Models.PrefixEntry entry,
        WineRuntime runtime,
        RuntimeLog logger,
        bool run_update = true,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        RuntimeStatusCallback? status_cb = null
    ) throws Error {
        var runner_id = runtime.runner_manifest.id;
        var variant_id = runtime.variant.id;
        var resolved_version = runtime.runner_version;
        var state = entry.runner_state;
        var changed = state == null
            || !state.matches (runner_id, variant_id, resolved_version);

        if (!changed) return;

        if (launch_policy == LaunchPolicy.OFFLINE_FAST_START) {
            throw new LumoriaError.FAILED (
                _("Prefix runner changed to %s %s. Open Lumoria to update the prefix before launching from CLI.").printf (
                    runner_id, resolved_version
                )
            );
        }

        if (cleanup_runner_support_files (entry, logger)) {
            persist_prefix (entry);
        }

        if (run_update) {
            if (status_cb != null) {
                status_cb ("Updating prefix for %s %s...".printf (
                    runtime.runner_manifest.display_label (),
                    resolved_version
                ));
            }
            logger.banner ("Updating prefix for runner change");
            logger.emit_line ("Runner: %s\n".printf (runner_id));
            logger.emit_line ("Variant: %s\n".printf (variant_id));
            logger.emit_line ("Resolved version: %s\n\n".printf (resolved_version));
            create_wine_prefix (runtime.paths, runtime.env, logger);
        }

        var next = new Models.PrefixRunnerState ();
        next.runner_id = runner_id;
        next.variant_id = variant_id;
        next.resolved_version = resolved_version;
        entry.runner_state = next;
        persist_prefix (entry);
    }

    public void ensure_prefix_runner_ready (
        Models.PrefixEntry entry,
        WineRuntime runtime,
        RuntimeLog logger,
        bool run_update = true,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        RuntimeStatusCallback? status_cb = null
    ) throws Error {
        ensure_prefix_runner_current (entry, runtime, logger, run_update, launch_policy, status_cb);
        apply_runner_support_files (runtime, entry, logger);
    }

    private bool cleanup_runner_support_files (
        Models.PrefixEntry entry,
        RuntimeLog logger
    ) throws Error {
        if (entry.runner_support_files.size == 0) return false;

        foreach (var path in entry.runner_support_files) {
            if (Utils.remove_file_or_symlink (path)) {
                logger.typed (LogType.COPY, "removed runner support %s".printf (path));
            } else {
                logger.typed (LogType.DEBUG, "runner support cleanup skipped %s".printf (path));
            }
        }
        entry.runner_support_files.clear ();
        return true;
    }

    public void apply_runner_support_files (
        WineRuntime runtime,
        Models.PrefixEntry entry,
        RuntimeLog logger
    ) throws Error {
        if (runtime.runner_manifest.support_files.size == 0) return;

        var vars = new Gee.HashMap<string, string> ();
        vars[VAR_RUNNER] = runtime.paths.root;
        vars[VAR_PREFIX] = runtime.prefix_path;
        vars[VAR_ARCH] = runtime.wine_arch;

        bool dirty = false;
        foreach (var support in runtime.runner_manifest.support_files) {
            if (support.when != null && !support.when.evaluate (vars)) continue;

            if (support.files.size > 0) {
                if (support.dst_dir.strip () == "") continue;
                foreach (var file in support.files) {
                    var src = resolve_runner_support_source (runtime.paths.root, support.src_dirs, vars, file);
                    var dst = resolve_runner_support_destination (
                        runtime.prefix_path,
                        Path.build_filename (support.dst_dir, file),
                        vars
                    );
                    if (apply_runner_support_file (entry, support, src, dst, logger)) {
                        dirty = true;
                    }
                }
                continue;
            }

            if (support.dst.strip () == "") continue;
            var src = resolve_runner_support_source (runtime.paths.root, support.src, vars);
            var dst = resolve_runner_support_destination (runtime.prefix_path, support.dst, vars);
            if (apply_runner_support_file (entry, support, src, dst, logger)) {
                dirty = true;
            }
        }

        if (dirty) {
            persist_prefix (entry);
        }
    }

    private bool apply_runner_support_file (
        Models.PrefixEntry entry,
        Models.RunnerSupportFile support,
        string src,
        string dst,
        RuntimeLog logger
    ) throws Error {
        var id = support.id;
        if (src == "") {
            logger.typed (LogType.DEBUG, "runner support %s: source missing".printf (id));
            return false;
        }

        var mode = support.mode.down ().strip ();
        if (mode == "") mode = "copy";

        if (Utils.is_link_mode (mode)) {
            return link_runner_support_file (entry, id, src, dst, mode, logger);
        }

        if (FileUtils.test (dst, FileTest.EXISTS) || FileUtils.test (dst, FileTest.IS_SYMLINK)) {
            logger.typed (LogType.DEBUG, "runner support %s: already present".printf (id));
            return false;
        }

        Utils.copy_path (src, dst);
        logger.typed (LogType.COPY, "runner support %s: %s -> %s".printf (id, src, dst));
        return track_runner_support_file (entry, dst);
    }

    private bool link_runner_support_file (
        Models.PrefixEntry entry,
        string id,
        string src,
        string dst,
        string mode,
        RuntimeLog logger
    ) throws Error {
        var dst_exists = FileUtils.test (dst, FileTest.EXISTS);
        var dst_is_symlink = FileUtils.test (dst, FileTest.IS_SYMLINK);

        if (dst_is_symlink && mode == "symlink" && Utils.is_symlink_to (dst, src)) {
            logger.typed (LogType.DEBUG, "runner support %s: already linked".printf (id));
            return track_runner_support_file (entry, dst);
        }

        if (dst_exists && !dst_is_symlink) {
            logger.typed (LogType.DEBUG, "runner support %s: already present".printf (id));
            return false;
        }

        if (dst_is_symlink) {
            logger.typed (LogType.LINK, "runner support %s: replacing stale link %s".printf (id, dst));
        }

        Utils.link_file (src, dst, mode, dst_is_symlink);
        logger.typed (LogType.LINK, "runner support %s: %s %s -> %s".printf (id, mode, src, dst));
        return track_runner_support_file (entry, dst);
    }

    private bool track_runner_support_file (Models.PrefixEntry entry, string dst) {
        if (entry.runner_support_files.contains (dst)) return false;
        entry.runner_support_files.add (dst);
        return true;
    }

    /* First existing candidate, optionally joined with file, relative to the runner root unless absolute. */
    private string resolve_runner_support_source (
        string runner_root,
        Gee.ArrayList<string> candidates,
        Gee.HashMap<string, string> vars,
        string file = ""
    ) {
        foreach (var candidate in candidates) {
            var expanded = Utils.expand_vars (candidate, vars);
            if (file != "") expanded = Path.build_filename (expanded, file);
            var resolved = Path.is_absolute (expanded)
                ? expanded
                : Path.build_filename (runner_root, expanded);
            if (FileUtils.test (resolved, FileTest.EXISTS)) return resolved;
        }
        return "";
    }

    private string resolve_runner_support_destination (
        string prefix_path,
        string dst,
        Gee.HashMap<string, string> vars
    ) {
        var expanded = Utils.expand_vars (dst, vars);
        var resolved = Path.is_absolute (expanded)
            ? expanded
            : Path.build_filename (prefix_path, expanded);
        return Utils.collapse_path (resolved);
    }
}
