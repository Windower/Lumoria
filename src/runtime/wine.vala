namespace Lumoria.Runtime {
    public const string STDERR_LOG_PREFIX = "[stderr] ";
    public const SpawnFlags CHILD_SPAWN_FLAGS = SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD;

    public const string DLL_DISABLED = "d";
    public const string WINE_DEBUG_DEFAULT = "";
    public const string WINE_DEBUG_OFF = "-all";
    public const string WINE_DEBUG_GENERAL = "+warn,+err,+fixme";
    public const string WINE_DEBUG_FULL = "+warn,+err,+fixme,+seh,+loaddll,+debugstr";

    public enum LaunchPolicy {
        INTERACTIVE,
        OFFLINE_FAST_START
    }

    public delegate void RuntimeStatusCallback (string message);

    public enum WineDebugMode {
        DEFAULT,
        GENERAL,
        FULL,
        OFF;

        public static WineDebugMode parse (string value) {
            var mode = value.down ().strip ();
            if (mode == WINE_DEBUG_OFF || mode == "off") return OFF;
            if (mode == WINE_DEBUG_GENERAL) return GENERAL;
            if (mode == WINE_DEBUG_FULL || (mode != "" && mode != "off")) return FULL;
            return DEFAULT;
        }

        public unowned string id () {
            switch (this) {
                case GENERAL: return WINE_DEBUG_GENERAL;
                case FULL: return WINE_DEBUG_FULL;
                case OFF: return WINE_DEBUG_OFF;
                default: return WINE_DEBUG_DEFAULT;
            }
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

        /* Blank names or modes are skipped; later entries replace earlier ones for the same DLL. */
        public void set_dll_overrides (Gee.Map<string, string> overrides) {
            foreach (var ov in overrides.entries) {
                var dll = ov.key.strip ();
                var mode = ov.value.strip ();
                if (dll != "" && mode != "") set_dll_override (dll, mode);
            }
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
            set_var ("WINEDLLOVERRIDES", string.joinv (";", Utils.strv (parts)));
        }

        public WineEnv copy () {
            var c = new WineEnv ();
            foreach (var entry in vars.entries) {
                c.vars[entry.key] = entry.value;
            }
            return c;
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

    public WinePaths resolve_wine_paths (string root, Models.RunnerManifest spec, string variant_id) throws Error {
        if (root == "") throw new LumoriaError.FAILED (_("Runner root is required"));

        var v = spec.effective_variant (variant_id);

        var wine_bin = resolve_first_existing_mapped_path (root, v.wine_bins, v.wine_bin);
        if (wine_bin == "" || !FileUtils.test (wine_bin, FileTest.EXISTS)) {
            throw new LumoriaError.NOT_FOUND (
                _("Wine binary not found for runner '%s': %s").printf (spec.id, wine_bin)
            );
        }

        var wineserver = resolve_first_existing_mapped_path (root, v.wineservers, v.wineserver);
        if (wineserver == "" || !FileUtils.test (wineserver, FileTest.EXISTS)) {
            throw new LumoriaError.NOT_FOUND (
                _("Wineserver not found for runner '%s': %s").printf (spec.id, wineserver)
            );
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

    private void add_wine_dll_dir (WinePaths paths, string root, string mapped) {
        var resolved = resolve_mapped_path (root, mapped);
        paths.wine_dll_dirs.add (resolved);
        if (!is_wine_dll_root (mapped)) {
            paths.winedllpath_dirs.add (resolved);
        }
    }

    private bool is_wine_dll_root (string mapped) {
        var normalized = mapped.strip ().replace ("\\", "/");
        return normalized == "wine" || normalized.has_suffix ("/wine");
    }

    public WineEnv build_wine_env (
        WinePaths paths,
        WineRuntimeRequest request
    ) throws Error {
        var spec = request.runner_manifest;
        var variant_id = request.variant_id;
        var prefix_path = PrefixPaths.from_root (request.prefix_root).wine_prefix;
        var effective_arch = spec.effective_variant (variant_id).effective_arch (request.wine_arch);
        var sync_mode = Utils.Preferences.resolve_sync_mode (request.sync_mode);
        var wine_debug = Utils.Preferences.resolve_wine_debug (request.wine_debug);
        var wayland_enabled = Utils.Preferences.resolve_wine_wayland (request.wine_wayland);
        var env = new WineEnv ();
        var runtime_prefix = runtime_prefix_path (prefix_path);

        env.set_var ("WINEARCH", effective_arch);
        env.set_var ("WINEPREFIX", runtime_prefix);
        env.set_dll_override ("winemenubuilder", DLL_DISABLED);

        var display = Environment.get_variable ("DISPLAY");
        var wayland_display = Environment.get_variable ("WAYLAND_DISPLAY");
        var has_x11 = display != null && display.strip () != "";
        var has_wayland = wayland_display != null && wayland_display.strip () != "";

        var has_wayland_driver = runner_has_wayland_driver (paths, effective_arch);
        var can_use_wayland = has_wayland && has_wayland_driver;

        if (wayland_enabled && can_use_wayland) {
            env.set_dll_override ("winex11.drv", DLL_DISABLED);
            apply_wayland_driver_env (env, paths);
        } else if (has_x11) {
            env.set_dll_override ("winewayland.drv", DLL_DISABLED);
        } else if (can_use_wayland) {
            env.set_dll_override ("winex11.drv", DLL_DISABLED);
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
                foreach (var b in p.bin_paths) bin_parts.add (resolve_mapped_path (root, b));
            } else if (p.bin != "") {
                bin_parts.add (resolve_mapped_path (root, p.bin));
            }

            var ld_parts = new Gee.ArrayList<string> ();
            foreach (var l in p.lib) ld_parts.add (resolve_mapped_path (root, l));
            foreach (var l in p.lib_64) ld_parts.add (resolve_mapped_path (root, l));
            foreach (var l in p.lib_32) ld_parts.add (resolve_mapped_path (root, l));
            foreach (var l in p.wine_unix) ld_parts.add (resolve_mapped_path (root, l));

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

    internal string resolve_mapped_path (string root, string mapped) {
        var m = mapped.strip ();
        if (m == "") return "";
        if (Path.is_absolute (m)) return m;
        return Path.build_filename (root, m);
    }

    internal string resolve_first_existing_mapped_path (
        string root,
        Gee.ArrayList<string> candidates,
        string fallback
    ) {
        string first = "";
        foreach (var candidate in candidates) {
            var resolved = resolve_mapped_path (root, candidate);
            if (first == "") first = resolved;
            if (resolved != "" && FileUtils.test (resolved, FileTest.EXISTS)) return resolved;
        }
        if (first != "") return first;
        return resolve_mapped_path (root, fallback);
    }

    internal string join_existing_paths (Gee.ArrayList<string> paths) {
        var parts = new Gee.ArrayList<string> ();
        foreach (var p in paths) {
            if (p != "" && FileUtils.test (p, FileTest.IS_DIR)) {
                parts.add (p);
            }
        }
        return string.joinv (":", Utils.strv (parts));
    }

    private void apply_sync_mode (WineEnv env, Utils.WineSyncMode mode) {
        switch (mode) {
            case Utils.WineSyncMode.ESYNC:
                env.set_var ("WINEESYNC", "1");
                env.set_var ("WINEFSYNC", "0");
                env.set_var ("WINENTSYNC", "0");
                break;
            case Utils.WineSyncMode.FSYNC:
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
}
