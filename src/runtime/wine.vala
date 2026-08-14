namespace Lumoria.Runtime {
    public const string STDERR_LOG_PREFIX = "[stderr] ";
    public const SpawnFlags CHILD_SPAWN_FLAGS = SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD;
    private const int LOG_OUTPUT_TAIL_BYTES = 8192;

    public const string DLL_NATIVE   = "native";
    public const string DLL_BUILTIN  = "builtin";
    public const string DLL_DISABLED = "d";
    public const string WINE_DEBUG_DEFAULT = "";
    public const string WINE_DEBUG_OFF = "-all";
    public const string WINE_DEBUG_GENERAL = "+warn,+err,+fixme";
    public const string WINE_DEBUG_FULL = "+warn,+err,+fixme,+seh,+loaddll,+debugstr";
    public const string WINE_DEBUG_LABEL_DEFAULT = "Default";
    public const string WINE_DEBUG_LABEL_GENERAL = "General";
    public const string WINE_DEBUG_LABEL_FULL = "Full";
    private const int WINE_COMMAND_TERM_WAIT_MS = 1000;
    private const int WINE_COMMAND_KILL_WAIT_MS = 1000;

    public enum LaunchPolicy {
        INTERACTIVE,
        OFFLINE_FAST_START
    }

    public delegate void RuntimeStatusCallback (string message);
    private delegate void PrefixEntryMutation (Models.PrefixEntry target);

    public uint wine_debug_index_for_value (string value) {
        var mode = value.down ().strip ();
        if (mode == WINE_DEBUG_GENERAL) return 1;
        if (mode != "" && mode != "off") return 2;
        return 0;
    }

    public string wine_debug_value_for_index (uint index) {
        switch (index) {
            case 1: return WINE_DEBUG_GENERAL;
            case 2: return WINE_DEBUG_FULL;
            default: return WINE_DEBUG_DEFAULT;
        }
    }

    public void apply_runtime_logging_policy (WineEnv env) {
        if (!Utils.Preferences.instance ().keep_runtime_logs) {
            env.set_var ("WINEDEBUG", WINE_DEBUG_OFF);
        }
    }

    const string[] LOG_ENV_KEYS = {
        "WINEPREFIX", "WINEARCH", "WINEDLLOVERRIDES", "WINEDEBUG",
        "WINE_LARGE_ADDRESS_AWARE",
        "WINEESYNC", "WINEFSYNC", "WINENTSYNC",
        "PATH", "LD_LIBRARY_PATH", "WINEDLLPATH",
        "DISPLAY", "WAYLAND_DISPLAY", "WAYLANDDRV_PRIMARY_MONITOR", "XDG_RUNTIME_DIR",
        "PWD"
    };

    public class WineEnv : Object {
        private Gee.HashMap<string, string> vars;

        public WineEnv () {
            vars = new Gee.HashMap<string, string> ();
        }

        public void set_var (string key, string value) {
            vars[key] = value;
        }

        public string? get_var (string key) {
            return vars.has_key (key) ? vars[key] : null;
        }

        public void prepend_path (string key, string path) {
            if (path == "") return;
            var existing = get_var (key) ?? Environment.get_variable (key) ?? "";
            set_var (key, existing == "" ? path : path + ":" + existing);
        }

        public void add_dll_override (string dll, string mode) {
            var entry = "%s=%s".printf (dll, mode);
            var existing = get_var ("WINEDLLOVERRIDES") ?? "";
            set_var ("WINEDLLOVERRIDES", existing == "" ? entry : existing + ";" + entry);
        }

        public void set_dll_override (string dll, string mode) {
            var parts = new Gee.ArrayList<string> ();
            var dll_key = dll.down ();
            var existing = get_var ("WINEDLLOVERRIDES") ?? "";
            foreach (var part in existing.split (";")) {
                var trimmed = part.strip ();
                if (trimmed == "") continue;
                var eq = trimmed.index_of ("=");
                var key = eq >= 0 ? trimmed.substring (0, eq).down () : trimmed.down ();
                if (key == dll_key) continue;
                parts.add (trimmed);
            }
            parts.add ("%s=%s".printf (dll, mode));
            set_var ("WINEDLLOVERRIDES", string.joinv (";", Utils.arraylist_to_strv (parts)));
        }

        public WineEnv copy () {
            var c = new WineEnv ();
            foreach (var entry in vars.entries) {
                c.vars[entry.key] = entry.value;
            }
            return c;
        }

        public void apply (WineEnv other) {
            foreach (var entry in other.vars.entries) {
                vars[entry.key] = entry.value;
            }
        }

        public Gee.HashMap<string, string> snapshot_vars () {
            var copy = new Gee.HashMap<string, string> ();
            foreach (var entry in vars.entries) {
                copy[entry.key] = entry.value;
            }
            return copy;
        }

        public string[] to_spawn_strv () {
            var merged = new Gee.HashMap<string, string> ();
            foreach (var key in Environment.list_variables ()) {
                var val = Environment.get_variable (key);
                if (val != null) merged[key] = val;
            }
            foreach (var entry in vars.entries) {
                merged[entry.key] = entry.value;
            }
            var result = new string[merged.size + 1];
            int i = 0;
            foreach (var entry in merged.entries) {
                result[i++] = "%s=%s".printf (entry.key, entry.value);
            }
            result[merged.size] = null;
            return result;
        }

        public void log_wine_vars (RuntimeLog logger) {
            var logged = new Gee.HashSet<string> ();
            foreach (var key in LOG_ENV_KEYS) {
                var val = get_var (key) ?? Environment.get_variable (key);
                if (val != null) {
                    logger.typed (LogType.ENV, "%s=%s".printf (key, val));
                    logged.add (key);
                }
            }
            foreach (var entry in vars.entries) {
                if (!logged.contains (entry.key)) {
                    logger.typed (LogType.ENV, "%s=%s".printf (entry.key, entry.value));
                }
            }
        }
    }

    public class WinePaths : Object {
        public string wine { get; set; default = ""; }
        public string wineserver { get; set; default = ""; }
        public string root { get; set; default = ""; }
        public Gee.ArrayList<string> wine_dll_dirs {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public Gee.ArrayList<string> winedllpath_dirs {
            get; owned set; default = new Gee.ArrayList<string> ();
        }

        public string find_runner_pe_dir (string arch_subdir) {
            foreach (var dir in wine_dll_dirs) {
                var candidate = Path.build_filename (dir, arch_subdir);
                if (FileUtils.test (candidate, FileTest.IS_DIR)) return candidate;
            }
            return "";
        }
    }

    public WinePaths resolve_wine_paths (string root, Models.RunnerSpec spec, string variant_id) throws Error {
        if (root == "") throw new IOError.FAILED ("runner root is required");

        var v = spec.effective_variant (variant_id);

        var wine_bin = resolve_first_existing_spec_path (root, v.wine_bins, v.wine_bin);
        if (wine_bin == "" || !FileUtils.test (wine_bin, FileTest.EXISTS)) {
            throw new IOError.FAILED ("runner '%s': wine binary not found: %s", spec.id, wine_bin);
        }

        var wineserver = resolve_first_existing_spec_path (root, v.wineservers, v.wineserver);
        if (wineserver == "" || !FileUtils.test (wineserver, FileTest.EXISTS)) {
            throw new IOError.FAILED ("runner '%s': wineserver not found: %s", spec.id, wineserver);
        }

        var paths = new WinePaths ();
        paths.wine = wine_bin;
        paths.wineserver = wineserver;
        paths.root = root;
        foreach (var d in v.paths.wine_dll) add_wine_dll_dir (paths, root, d);
        foreach (var d in v.paths.wine_dll_64) add_wine_dll_dir (paths, root, d);
        foreach (var d in v.paths.wine_dll_32) add_wine_dll_dir (paths, root, d);
        return paths;
    }

    private void add_wine_dll_dir (WinePaths paths, string root, string spec_path) {
        var resolved = resolve_spec_path_public (root, spec_path);
        paths.wine_dll_dirs.add (resolved);
        if (!is_wine_dll_root (spec_path)) {
            paths.winedllpath_dirs.add (resolved);
        }
    }

    private bool is_wine_dll_root (string spec_path) {
        var normalized = spec_path.strip ().replace ("\\", "/");
        return normalized == "wine" || normalized.has_suffix ("/wine");
    }

    public WineEnv build_wine_env (
        WinePaths paths,
        Models.RunnerSpec spec,
        string variant_id,
        string prefix_path,
        string wine_arch,
        string sync_mode,
        string wine_debug,
        bool headless,
        bool wayland_enabled
    ) throws Error {
        var env = new WineEnv ();
        var effective_arch = (wine_arch == "win32") ? "win32" : "win64";
        var runtime_prefix = runtime_prefix_path (prefix_path);

        env.set_var ("WINEARCH", effective_arch);
        env.set_var ("WINEPREFIX", runtime_prefix);
        env.add_dll_override ("winemenubuilder", DLL_DISABLED);

        var display = Environment.get_variable ("DISPLAY");
        var wayland_display = Environment.get_variable ("WAYLAND_DISPLAY");
        var has_x11 = display != null && display.strip () != "";
        var has_wayland = wayland_display != null && wayland_display.strip () != "";

        var has_wayland_driver = runner_has_wayland_driver (paths, effective_arch);
        var can_use_wayland = has_wayland && has_wayland_driver;

        if (headless) {
            env.add_dll_override ("winex11.drv", DLL_DISABLED);
            env.add_dll_override ("winewayland.drv", DLL_DISABLED);
        } else if (wayland_enabled && can_use_wayland) {
            env.add_dll_override ("winex11.drv", DLL_DISABLED);
            apply_wayland_driver_env (env, paths);
        } else if (has_x11) {
            env.add_dll_override ("winewayland.drv", DLL_DISABLED);
        } else if (can_use_wayland) {
            env.add_dll_override ("winex11.drv", DLL_DISABLED);
            apply_wayland_driver_env (env, paths);
        }

        if (wine_debug != "" && wine_debug != "off") {
            env.set_var ("WINEDEBUG", wine_debug);
        }

        if (paths.root != "") {
            var v = spec.effective_variant (variant_id);
            var p = v.paths;
            var root = paths.root;

            var bin_parts = new Gee.ArrayList<string> ();
            if (p.bin_paths.size > 0) {
                foreach (var b in p.bin_paths) bin_parts.add (resolve_spec_path_public (root, b));
            } else if (p.bin != "") {
                bin_parts.add (resolve_spec_path_public (root, p.bin));
            }

            var ld_parts = new Gee.ArrayList<string> ();
            foreach (var l in p.lib) ld_parts.add (resolve_spec_path_public (root, l));
            foreach (var l in p.lib_64) ld_parts.add (resolve_spec_path_public (root, l));
            foreach (var l in p.lib_32) ld_parts.add (resolve_spec_path_public (root, l));
            foreach (var l in p.wine_unix) ld_parts.add (resolve_spec_path_public (root, l));

            var ld = join_existing_paths (ld_parts);
            var wine_dll = join_existing_paths (paths.winedllpath_dirs);

            env.prepend_path ("PATH", join_existing_paths (bin_parts));
            env.prepend_path ("LD_LIBRARY_PATH", ld);
            env.prepend_path ("WINEDLLPATH", wine_dll);
        }

        apply_sync_mode (env, sync_mode);

        return env;
    }

    private void apply_wayland_driver_env (WineEnv env, WinePaths paths) {
        env.set_var ("WINE_USE_EGL", "1");
        env.set_var ("WINE_DISABLE_FULLSCREEN_HACK", "1");
        env.set_var ("WINE_MOVE_HACK", "1");

        // GE-Proton's bundled libxkbcommon has its build machine's X locale
        // root baked in, so the Compose table lookup fails and dead keys type
        // nothing. The proton script works around it by pointing XLOCALEDIR
        // at the locale data shipped with the runner; fall back to the system
        // copy for runners that do not ship one.
        if (Environment.get_variable ("XLOCALEDIR") == null) {
            var runner_locale = Path.build_filename (paths.root, "files", "share", "X11", "locale");
            env.set_var (
                "XLOCALEDIR",
                FileUtils.test (runner_locale, FileTest.IS_DIR) ? runner_locale : "/usr/share/X11/locale"
            );
        }
    }

    private bool runner_has_wayland_driver (WinePaths paths, string wine_arch) {
        foreach (var dir in paths.wine_dll_dirs) {
            var pe_arch = wine_arch == "win32" ? "i386-windows" : "x86_64-windows";
            if (FileUtils.test (Path.build_filename (dir, pe_arch, "winewayland.drv"), FileTest.EXISTS)) {
                return true;
            }
            var unix_arch = wine_arch == "win32" ? "i386-unix" : "x86_64-unix";
            if (FileUtils.test (Path.build_filename (dir, unix_arch, "winewayland.drv.so"), FileTest.EXISTS)) {
                return true;
            }
        }
        return false;
    }

    public void apply_env_overrides (WineEnv env, Gee.HashMap<string, string> overrides) {
        foreach (var entry in overrides.entries) {
            env.set_var (entry.key, entry.value);
        }
    }

    public void apply_env_rules (
        WineEnv env,
        Gee.ArrayList<Models.EnvRule> rules,
        Gee.HashMap<string, string> vars
    ) {
        foreach (var rule in rules) {
            if (rule.when != null && !rule.when.evaluate (vars)) continue;
            foreach (var entry in rule.vars.entries) {
                env.set_var (entry.key, Utils.expand_vars (entry.value, vars));
            }
        }
    }

    public class WineRuntimeRequest : Object {
        public Models.RunnerSpec runner_spec { get; set; }
        public string variant_id { get; set; default = ""; }
        public string runner_version { get; set; default = "latest"; }
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
            Models.RunnerSpec runner_spec,
            LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE
        ) {
            var request = new WineRuntimeRequest ();
            request.runner_spec = runner_spec;
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
        public Models.RunnerSpec     runner_spec    { get; private set; }
        public Models.RunnerVariant  variant        { get; private set; }
        public string                runner_version { get; private set; }
        public DownloadResult        extract_result { get; private set; }
        public WinePaths             paths          { get; private set; }
        public string                prefix_path    { get; private set; }
        public string                wine_arch      { get; private set; }
        public WineEnv               env            { get; private set; }

        internal WineRuntime (
            Models.RunnerSpec runner_spec,
            Models.RunnerVariant variant,
            string runner_version,
            DownloadResult extract_result,
            WinePaths paths,
            string prefix_path,
            string wine_arch,
            WineEnv env
        ) {
            this.runner_spec = runner_spec;
            this.variant = variant;
            this.runner_version = runner_version;
            this.extract_result = extract_result;
            this.paths = paths;
            this.prefix_path = prefix_path;
            this.wine_arch = wine_arch;
            this.env = env;
        }
    }

    public WineRuntime prepare_wine_runtime (
        WineRuntimeRequest request,
        RuntimeLog logger
    ) throws Error {
        var runner_spec = request.runner_spec;
        var variant_id = request.variant_id;
        var runner_version = request.runner_version;
        var prefix_root = request.prefix_root;
        var resolved_version = resolve_runner_version_for_policy (
            runner_spec,
            variant_id,
            runner_version,
            request.launch_policy,
            request.runner_state
        );
        var extract = download_and_extract_runner (
            runner_spec,
            variant_id,
            resolved_version,
            request.download_progress,
            logger,
            request.launch_policy == LaunchPolicy.INTERACTIVE
        );
        var paths = resolve_wine_paths (extract.extracted_to, runner_spec, variant_id);
        var variant = runner_spec.effective_variant (variant_id);
        var pfx_path = install_prefix_path (prefix_root);
        var arch = request.wine_arch != "" ? request.wine_arch : variant.wine_arch;
        var wayland_pref = Utils.Preferences.resolve_wine_wayland (request.wine_wayland);
        if (!wayland_pref && !Utils.EnvironmentInfo.has_x11_display ()) {
            logger.typed (
                LogType.WARN,
                "Wine Wayland is disabled but no X11 display is available; using the Wayland driver anyway."
                + (Utils.EnvironmentInfo.is_sandboxed ()
                    ? " Grant the X11 socket (flatpak override --user --socket=x11 net.windower.Lumoria) to use XWayland."
                    : "")
            );
        }
        var env = build_wine_env (
            paths, runner_spec, variant_id,
            pfx_path, arch,
            Utils.Preferences.resolve_sync_mode (request.sync_mode),
            Utils.Preferences.resolve_wine_debug (request.wine_debug),
            false,
            wayland_pref
        );
        if (Utils.Preferences.resolve_large_address_aware (request.large_address_aware)) {
            env.set_var ("WINE_LARGE_ADDRESS_AWARE", "1");
        }
        apply_env_overrides (env, Utils.Preferences.instance ().get_runtime_env_vars ());
        apply_env_overrides (env, request.environment_overrides);
        apply_runtime_logging_policy (env);
        return new WineRuntime (
            runner_spec, variant, extract.version, extract,
            paths, pfx_path, arch, env
        );
    }

    private string resolve_runner_version_for_policy (
        Models.RunnerSpec runner_spec,
        string variant_id,
        string runner_version,
        LaunchPolicy launch_policy,
        Models.PrefixRunnerState? runner_state
    ) throws Error {
        if (launch_policy == LaunchPolicy.INTERACTIVE) {
            return Utils.Preferences.resolve_version (runner_spec.id, runner_version);
        }

        var requested = runner_version.strip ();
        if (requested != "" && requested != "default" && requested != "latest") {
            return requested;
        }

        var effective_variant = runner_spec.effective_variant (variant_id);
        if (runner_state != null
            && runner_state.runner_id == runner_spec.id
            && (runner_state.variant_id == effective_variant.id || runner_state.variant_id == "")
            && runner_state.resolved_version != "") {
            return runner_state.resolved_version;
        }

        throw new IOError.FAILED (
            "No installed runner version is stamped for %s. Open Lumoria once to prepare this prefix before launching from CLI.",
            runner_spec.id
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
        var runner_id = runtime.runner_spec.id;
        var variant_id = runtime.variant.id;
        var resolved_version = runtime.runner_version;
        var state = entry.runner_state;
        var changed = state == null
            || !state.matches (runner_id, variant_id, resolved_version);

        if (!changed) return;

        if (launch_policy == LaunchPolicy.OFFLINE_FAST_START) {
            throw new IOError.FAILED (
                "Prefix runner changed to %s %s. Open Lumoria to update the prefix before launching from CLI.",
                runner_id,
                resolved_version
            );
        }

        if (cleanup_runner_support_files (entry, logger)) {
            persist_runner_support_files (entry, logger);
        }

        if (run_update) {
            if (status_cb != null) {
                status_cb (_("Updating prefix for %s %s...").printf (
                    runtime.runner_spec.display_label (),
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
        persist_prefix_runner_state (entry, next, logger);
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
        if (runtime.runner_spec.support_files.size == 0) return;

        var vars = new Gee.HashMap<string, string> ();
        vars["RUNNER"] = runtime.paths.root;
        vars["PREFIX"] = runtime.prefix_path;
        vars["ARCH"] = runtime.wine_arch == "win32" ? "win32" : "win64";

        bool dirty = false;
        foreach (var support in runtime.runner_spec.support_files) {
            if (support.when != null && !support.when.evaluate (vars)) continue;

            if (support.files.size > 0) {
                if (support.dst_dir.strip () == "") continue;
                foreach (var file in support.files) {
                    var src = resolve_runner_support_source_from_dirs (
                        runtime.paths.root,
                        support.src_dirs,
                        file,
                        vars
                    );
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
            persist_runner_support_files (entry, logger);
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

        if (entry.runner_support_files.contains (dst)) return false;
        entry.runner_support_files.add (dst);
        return true;
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

    private string resolve_runner_support_source (
        string runner_root,
        Gee.ArrayList<string> candidates,
        Gee.HashMap<string, string> vars
    ) {
        foreach (var candidate in candidates) {
            var expanded = Utils.expand_vars (candidate, vars);
            var resolved = Path.is_absolute (expanded)
                ? expanded
                : Path.build_filename (runner_root, expanded);
            if (FileUtils.test (resolved, FileTest.EXISTS)) return resolved;
        }
        return "";
    }

    private string resolve_runner_support_source_from_dirs (
        string runner_root,
        Gee.ArrayList<string> dirs,
        string file,
        Gee.HashMap<string, string> vars
    ) {
        foreach (var dir in dirs) {
            var expanded_dir = Utils.expand_vars (dir, vars);
            var candidate = Path.build_filename (expanded_dir, file);
            var resolved = Path.is_absolute (candidate)
                ? candidate
                : Path.build_filename (runner_root, candidate);
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
        return Path.is_absolute (expanded)
            ? expanded
            : Path.build_filename (prefix_path, expanded);
    }

    private void persist_runner_support_files (
        Models.PrefixEntry entry,
        RuntimeLog logger
    ) {
        persist_prefix_entry_update (
            entry,
            logger,
            "Failed to save runner support files for prefix",
            (target) => {
                var copied = new Gee.ArrayList<string> ();
                foreach (var path in entry.runner_support_files) copied.add (path);
                target.runner_support_files = copied;
            }
        );
    }

    private void persist_prefix_runner_state (
        Models.PrefixEntry entry,
        Models.PrefixRunnerState state,
        RuntimeLog logger
    ) {
        persist_prefix_entry_update (
            entry,
            logger,
            "Failed to save runner state for prefix",
            (target) => {
                target.runner_state = state;
            }
        );
    }

    private void persist_prefix_entry_update (
        Models.PrefixEntry entry,
        RuntimeLog logger,
        string failure_message,
        PrefixEntryMutation mutate
    ) {
        var reg_path = Utils.prefix_registry_path ();
        var reg = Models.PrefixRegistry.load (reg_path);
        Models.PrefixEntry? target = null;
        if (entry.id != "") target = reg.by_id (entry.id);
        if (target == null) target = reg.by_path (entry.resolved_path ());
        if (target == null) return;

        mutate (target);
        reg.update_entry (target);
        if (!reg.save (reg_path)) {
            logger.typed (LogType.WARN, failure_message);
        }
    }

    private string resolve_spec_path_public (string root, string mapped) {
        var m = mapped.strip ();
        if (m == "") return "";
        if (Path.is_absolute (m)) return m;
        return Path.build_filename (root, m);
    }

    private string resolve_first_existing_spec_path (
        string root,
        Gee.ArrayList<string> candidates,
        string fallback
    ) {
        string first = "";
        foreach (var candidate in candidates) {
            var resolved = resolve_spec_path_public (root, candidate);
            if (first == "") first = resolved;
            if (resolved != "" && FileUtils.test (resolved, FileTest.EXISTS)) return resolved;
        }
        if (first != "") return first;
        return resolve_spec_path_public (root, fallback);
    }

    private string join_existing_paths (Gee.ArrayList<string> paths) {
        var parts = new Gee.ArrayList<string> ();
        foreach (var p in paths) {
            if (p != "" && FileUtils.test (p, FileTest.IS_DIR)) {
                parts.add (p);
            }
        }
        return string.joinv (":", Utils.arraylist_to_strv (parts));
    }

    private void apply_sync_mode (WineEnv env, string mode) {
        switch (mode.down ().strip ()) {
            case "esync":
                env.set_var ("WINEESYNC", "1");
                env.set_var ("WINEFSYNC", "0");
                env.set_var ("WINENTSYNC", "0");
                break;
            case "fsync":
                env.set_var ("WINEESYNC", "1");
                env.set_var ("WINEFSYNC", "1");
                env.set_var ("WINENTSYNC", "0");
                break;
            default:
                env.set_var ("WINEESYNC", "1");
                env.set_var ("WINEFSYNC", "1");
                env.set_var ("WINENTSYNC", "1");
                break;
        }
    }

    public string runtime_prefix_path (string prefix_path) {
        var trimmed = prefix_path.strip ();
        if (trimmed == "") return "";
        if (Path.get_basename (trimmed) == "pfx") return trimmed;
        var pfx = Path.build_filename (trimmed, "pfx");
        if (FileUtils.test (Path.build_filename (pfx, "drive_c"), FileTest.IS_DIR)) return pfx;
        return trimmed;
    }

    public string install_prefix_path (string prefix_path) {
        var trimmed = prefix_path.strip ();
        if (trimmed == "") return trimmed;
        if (Path.get_basename (trimmed) == "pfx") return trimmed;
        return Path.build_filename (trimmed, "pfx");
    }

    public string runner_builtin_for_dst (WinePaths paths, string dst_path, string wine_arch) {
        var parent_dir = Path.get_basename (Path.get_dirname (dst_path));
        string arch_subdir;
        if (parent_dir == "syswow64") {
            arch_subdir = "i386-windows";
        } else if (parent_dir == "system32") {
            arch_subdir = (wine_arch == "win32") ? "i386-windows" : "x86_64-windows";
        } else {
            return "";
        }
        var pe_dir = paths.find_runner_pe_dir (arch_subdir);
        if (pe_dir == "") return "";
        var candidate = Path.build_filename (pe_dir, Path.get_basename (dst_path));
        return FileUtils.test (candidate, FileTest.EXISTS) ? candidate : "";
    }

    private class WineCommandState {
        private Mutex mutex;
        private Cond cond;
        private bool completed = false;
        private bool terminating = false;
        private bool cancelled = false;
        private bool timed_out = false;

        public bool request_cancel () {
            mutex.lock ();
            var should_signal = !completed && !terminating;
            if (should_signal) {
                cancelled = true;
                terminating = true;
            }
            mutex.unlock ();
            return should_signal;
        }

        public bool wait_until_timeout (int timeout_ms) {
            var deadline = GLib.get_monotonic_time () + (int64) timeout_ms * 1000;
            mutex.lock ();
            while (!completed) {
                if (!cond.wait_until (mutex, deadline)) break;
            }

            var should_signal = !completed && !terminating;
            if (should_signal) {
                timed_out = true;
                terminating = true;
            }
            mutex.unlock ();
            return should_signal;
        }

        public void mark_completed () {
            mutex.lock ();
            completed = true;
            cond.broadcast ();
            mutex.unlock ();
        }

        public bool was_cancelled () {
            mutex.lock ();
            var value = cancelled;
            mutex.unlock ();
            return value;
        }

        public bool was_timed_out () {
            mutex.lock ();
            var value = timed_out;
            mutex.unlock ();
            return value;
        }
    }

    private void terminate_wine_command_tree (int child_pid) {
        Utils.ProcessTree.signal_monitored_descendants (child_pid, Posix.Signal.TERM);
        Posix.kill ((Posix.pid_t) child_pid, Posix.Signal.TERM);
        if (!Utils.ProcessTree.wait_for_monitored_descendants (child_pid, WINE_COMMAND_TERM_WAIT_MS)) {
            Utils.ProcessTree.signal_monitored_descendants (child_pid, Posix.Signal.KILL);
            Utils.ProcessTree.wait_for_monitored_descendants (child_pid, WINE_COMMAND_KILL_WAIT_MS);
        }

        if (Utils.ProcessTree.process_alive (child_pid)) {
            Posix.kill ((Posix.pid_t) child_pid, Posix.Signal.KILL);
        }
    }

    public void run_wine_command (
        string wine_bin,
        string[] wine_args,
        WineEnv wine_env,
        string? working_dir,
        RuntimeLog logger,
        Cancellable? cancellable = null,
        int timeout_ms = 0
    ) throws Error {
        var argv = new Gee.ArrayList<string> ();
        argv.add (wine_bin);
        foreach (var arg in wine_args) argv.add (arg);

        var cmd_line = wine_bin;
        foreach (var arg in wine_args) {
            if (" " in arg) {
                cmd_line += " \"%s\"".printf (arg);
            } else {
                cmd_line += " " + arg;
            }
        }
        logger.typed (LogType.CMD, cmd_line);
        if (working_dir != null) logger.typed (LogType.CWD, working_dir);
        wine_env.log_wine_vars (logger);

        var full_env = wine_env.to_spawn_strv ();
        LogFunc emit_fn = (msg) => {
            logger.emit_line (msg);
        };

        int child_pid;
        int stdout_fd;
        int stderr_fd;
        Process.spawn_async_with_pipes (
            working_dir,
            Utils.arraylist_to_strv (argv),
            full_env,
            CHILD_SPAWN_FLAGS,
            null,
            out child_pid,
            null,
            out stdout_fd,
            out stderr_fd
        );

        var stdout_output = new StringBuilder ();
        var stderr_output = new StringBuilder ();

        var command_state = new WineCommandState ();
        var pid_copy = child_pid;
        ulong cancel_handler = 0;
        if (cancellable != null) {
            cancel_handler = cancellable.connect (() => {
                if (command_state.request_cancel ()) {
                    terminate_wine_command_tree (pid_copy);
                }
            });
        }
        Thread<bool>? timeout_thread = null;
        if (timeout_ms > 0) {
            timeout_thread = new Thread<bool> ("wine-timeout", () => {
                if (command_state.wait_until_timeout (timeout_ms)) {
                    logger.typed (LogType.WARN, "command timed out after %d seconds; terminating process tree".printf (timeout_ms / 1000));
                    terminate_wine_command_tree (pid_copy);
                }
                return true;
            });
        }

        int exit_code = drain_spawned_process (
            child_pid,
            stdout_fd,
            stderr_fd,
            stdout_output,
            stderr_output,
            emit_fn,
            logger.is_disk_enabled () ? 0 : LOG_OUTPUT_TAIL_BYTES
        );
        command_state.mark_completed ();
        if (timeout_thread != null) timeout_thread.join ();

        if (cancellable != null && cancel_handler != 0) {
            cancellable.disconnect (cancel_handler);
        }

        if (command_state.was_timed_out ()) {
            throw new IOError.TIMED_OUT ("Wine command timed out");
        }
        if (command_state.was_cancelled () || (cancellable != null && cancellable.is_cancelled ())) {
            throw new IOError.CANCELLED ("Cancelled");
        }

        logger.typed (LogType.EXIT, "code=%d".printf (exit_code));

        if (exit_code != 0) {
            var msg = new StringBuilder ();
            msg.append ("Command failed with exit code %d\n".printf (exit_code));
            msg.append ("  Command: %s\n".printf (cmd_line));
            if (working_dir != null) msg.append ("  Working dir: %s\n".printf (working_dir));
            if (stderr_output.len > 0) {
                var err_text = stderr_output.str;
                if (err_text.length > 2000) err_text = err_text.substring (err_text.length - 2000);
                msg.append ("  stderr (tail):\n%s\n".printf (err_text));
            }
            if (stdout_output.len > 0) {
                var out_text = stdout_output.str;
                if (out_text.length > 2000) out_text = out_text.substring (out_text.length - 2000);
                msg.append ("  stdout (tail):\n%s\n".printf (out_text));
            }
            throw new IOError.FAILED ("%s", msg.str);
        }
    }

    private int drain_spawned_process (
        int child_pid,
        int stdout_fd,
        int stderr_fd,
        StringBuilder stdout_output,
        StringBuilder stderr_output,
        LogFunc emit_log,
        int max_retained_bytes = 0
    ) {
        var stderr_thread = new Thread<void> ("stderr-reader", () => {
            read_fd_to_log (stderr_fd, stderr_output, emit_log, STDERR_LOG_PREFIX, max_retained_bytes);
        });
        read_fd_to_log (stdout_fd, stdout_output, emit_log, "", max_retained_bytes);
        stderr_thread.join ();

        int status;
        Posix.waitpid (child_pid, out status, 0);
        Process.close_pid (child_pid);
        return Process.if_exited (status) ? Process.exit_status (status) : -1;
    }

    private void read_fd_to_log (
        int fd,
        StringBuilder output,
        LogFunc emit_log,
        string line_prefix,
        int max_retained_bytes = 0
    ) {
        var channel = new IOChannel.unix_new (fd);
        try {
            channel.set_flags (IOFlags.NONBLOCK);
        } catch (IOChannelError e) {
        }

        char buf[4096];
        var pending = new StringBuilder ();
        size_t bytes_read;
        IOStatus st;
        try {
            while (true) {
                st = channel.read_chars (buf, out bytes_read);
                if (st == IOStatus.AGAIN) {
                    Thread.usleep (10000);
                    continue;
                }
                if (st == IOStatus.EOF) break;
                if (bytes_read == 0) continue;

                uint8[] bytes = new uint8[bytes_read + 1];
                Memory.copy (bytes, buf, bytes_read);
                bytes[bytes_read] = 0;
                var chunk = ((string) bytes).make_valid ();
                append_retained_output (output, chunk, max_retained_bytes);
                pending.append (chunk);

                var text = pending.str;
                var end = text.last_index_of_char ('\n');
                if (end < 0) continue;

                var complete = text.substring (0, end + 1);
                pending.erase (0, end + 1);
                foreach (var line in complete.split ("\n")) {
                    if (line == "") continue;
                    emit_log ("%s%s\n".printf (line_prefix, line));
                }
            }
            if (pending.len > 0) emit_log ("%s%s\n".printf (line_prefix, pending.str));
        } catch (Error e) {
            warning ("Failed to read fd for log: %s", e.message);
        }
        try { channel.shutdown (false); } catch (Error e) {
            warning ("IOChannel shutdown failed: %s", e.message);
        }
    }

    private void append_retained_output (StringBuilder output, string chunk, int max_retained_bytes) {
        output.append (chunk);
        if (max_retained_bytes <= 0 || output.len <= max_retained_bytes) return;
        output.erase (0, (ssize_t) (output.len - max_retained_bytes));
    }

    public void create_wine_prefix (
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable = null,
        string wineboot_mscoree = "disabled"
    ) throws Error {
        var prefix = env.get_var ("WINEPREFIX");
        if (prefix != null) Utils.ensure_dir (prefix);

        var boot_env = env.copy ();
        if (wineboot_mscoree.down ().strip () == "disabled") {
            boot_env.add_dll_override ("mscoree", DLL_DISABLED);
        }

        run_wine_command (paths.wine, { "wineboot", "-u" }, boot_env, null, logger, cancellable);
        // Settle the initial prefix-update session before any subsequent wine
        // command runs. If we leave wineboot's wineserver alive, later wine
        // calls inherit "prefix still being initialized" state and a
        // post-install launch will re-run the update and clobber any native
        // DLLs we placed (e.g. gdiplus). Killing here closes that out.
        shutdown_wineserver (paths, boot_env, logger);
    }

    public delegate string? ComputedVarResolver (string arg, WinePaths paths, WineEnv env, RuntimeLog logger);

    public void resolve_prefix_vars (
        Gee.HashMap<string, string> vars,
        Models.PrefixEntry? entry,
        RuntimeLog? logger = null
    ) {
        if (entry == null) return;
        var keys = new Gee.ArrayList<string> ();
        foreach (var k in vars.keys) keys.add (k);
        foreach (var k in keys) {
            var raw = vars[k];
            string field;
            if (!parse_computed_expr (raw, "prefix.", out field)) continue;
            var resolved = resolve_prefix_field (entry, field);
            if (resolved != null) {
                vars[k] = resolved;
            } else if (logger != null) {
                logger.typed (LogType.WARN, "unknown prefix field '%s' in %s".printf (field, k));
            }
        }
    }

    private string? resolve_prefix_field (Models.PrefixEntry entry, string field) {
        switch (field) {
            case "id":             return entry.id;
            case "name":           return entry.name;
            case "path":           return entry.resolved_path ();
            case "uri":            return entry.uri;
            case "runner_id":      return entry.runner_id;
            case "runner_version": return entry.runner_version;
            case "launcher_id":    return entry.launcher_id;
            case "variant_id":     return entry.variant_id;
            case "wine_arch":      return entry.wine_arch;
            case "wine_debug":     return entry.wine_debug;
            case "sync_mode":      return entry.sync_mode;
            case "region":         return entry.region;
            case "installer_id":   return entry.installer_id;
            default:               return null;
        }
    }

    public void resolve_computed_vars (
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger
    ) {
        var keys = new Gee.ArrayList<string> ();
        foreach (var k in vars.keys) keys.add (k);
        foreach (var k in keys) {
            var raw = vars[k];
            string? resolved = null;
            string arg;
            if (parse_computed_expr (raw, "winepath:", out arg)) {
                resolved = resolve_winepath (arg, paths, env, logger);
            } else if (parse_computed_expr (raw, "pref:", out arg)) {
                resolved = resolve_pref (arg, logger);
            } else {
                continue;
            }
            if (resolved != null) vars[k] = resolved;
        }
    }

    private bool parse_computed_expr (string raw, string prefix, out string arg) {
        arg = "";
        if (!raw.has_prefix ("${") || !raw.has_suffix ("}")) return false;
        var body = raw.substring (2, raw.length - 3);
        if (!body.has_prefix (prefix)) return false;
        arg = body.substring (prefix.length);
        return arg != "";
    }

    public string? resolve_pref (string key, RuntimeLog logger) {
        var node = (Json.Node) new Json.Node (Json.NodeType.OBJECT);
        node.set_object (Utils.Preferences.instance ().snapshot ());
        foreach (var part in key.split (".")) {
            switch (node.get_node_type ()) {
                case Json.NodeType.OBJECT:
                    var obj = node.get_object ();
                    if (!obj.has_member (part)) {
                        logger.typed (LogType.WARN, "unknown pref key '%s'".printf (key));
                        return null;
                    }
                    node = obj.get_member (part);
                    break;
                case Json.NodeType.ARRAY:
                    int64 idx;
                    if (!int64.try_parse (part, out idx) || idx < 0) {
                        logger.typed (LogType.WARN, "pref '%s': '%s' is not a valid array index".printf (key, part));
                        return null;
                    }
                    var arr = node.get_array ();
                    if (idx >= arr.get_length ()) {
                        logger.typed (LogType.WARN, "pref '%s': index %s out of range (size=%u)".printf (key, part, arr.get_length ()));
                        return null;
                    }
                    node = arr.get_element ((uint) idx);
                    break;
                default:
                    logger.typed (LogType.WARN, "pref '%s': cannot descend through '%s'".printf (key, part));
                    return null;
            }
        }
        var s = json_node_to_string (node);
        if (s == null) {
            logger.typed (LogType.WARN, "pref '%s' is not a scalar value".printf (key));
        }
        return s;
    }

    private string? json_node_to_string (Json.Node node) {
        switch (node.get_node_type ()) {
            case Json.NodeType.NULL:
                return "";
            case Json.NodeType.VALUE:
                var t = node.get_value_type ();
                if (t == typeof (bool))   return node.get_boolean ().to_string ();
                if (t == typeof (string)) return node.get_string ();
                if (t == typeof (int64))  return node.get_int ().to_string ();
                if (t == typeof (double)) return node.get_double ().to_string ();
                return "";
            default:
                return null;
        }
    }

    public string? resolve_winepath (string windows_expr, WinePaths paths, WineEnv env, RuntimeLog logger) {
        try {
            string stdout_data;
            int status;
            Process.spawn_sync (
                null,
                { paths.wine, "cmd.exe", "/C", "winepath", "-u", windows_expr },
                env.to_spawn_strv (),
                SpawnFlags.SEARCH_PATH,
                null,
                out stdout_data,
                null,
                out status
            );
            if (!Process.if_exited (status) || Process.exit_status (status) != 0) {
                logger.typed (LogType.WARN, "winepath '%s' exit=%d".printf (windows_expr, status));
                return null;
            }
            var captured = (stdout_data ?? "").strip ();
            if (captured == "") return null;
            string last = captured;
            foreach (var line in captured.split ("\n")) {
                var trimmed = line.strip ();
                if (trimmed != "") last = trimmed;
            }
            var path = last.replace ("\\", "/");
            while (path.length > 1 && path.has_suffix ("/")) {
                path = path.substring (0, path.length - 1);
            }
            return path;
        } catch (Error e) {
            logger.typed (LogType.WARN, "winepath '%s' failed: %s".printf (windows_expr, e.message));
            return null;
        }
    }

    public void shutdown_wineserver (WinePaths paths, WineEnv env, RuntimeLog logger) {
        var ws = paths.wineserver;
        if (ws == "" || !FileUtils.test (ws, FileTest.EXISTS)) return;
        logger.typed (LogType.CMD, "%s -k".printf (ws));
        try {
            int status;
            Process.spawn_sync (null, { ws, "-k" }, env.to_spawn_strv (), SpawnFlags.SEARCH_PATH, null, null, null, out status);
            logger.typed (LogType.EXIT, "wineserver shutdown code=%d".printf (status));
        } catch (Error e) {
            logger.typed (LogType.WARN, "wineserver shutdown failed: %s".printf (e.message));
        }
    }
}
