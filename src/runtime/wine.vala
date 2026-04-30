namespace Lumoria.Runtime {
    public const string STDERR_LOG_PREFIX = "[stderr] ";
    public const SpawnFlags CHILD_SPAWN_FLAGS = SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD;

    public const string DLL_NATIVE   = "native";
    public const string DLL_BUILTIN  = "builtin";
    public const string DLL_DISABLED = "d";
    public const string WINE_DEBUG_DEFAULT = "";
    public const string WINE_DEBUG_GENERAL = "+warn,+err,+fixme";
    public const string WINE_DEBUG_FULL = "+warn,+err,+fixme,+seh,+loaddll,+debugstr";
    public const string WINE_DEBUG_LABEL_DEFAULT = "Default";
    public const string WINE_DEBUG_LABEL_GENERAL = "General";
    public const string WINE_DEBUG_LABEL_FULL = "Full";

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

    const string[] LOG_ENV_KEYS = {
        "WINEPREFIX", "WINEARCH", "WINEDLLOVERRIDES", "WINEDEBUG",
        "WINEESYNC", "WINEFSYNC", "WINENTSYNC",
        "PATH", "LD_LIBRARY_PATH", "WINEDLLPATH",
        "DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"
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
    }

    public WinePaths resolve_wine_paths (string root, Models.RunnerSpec spec, string variant_id) throws Error {
        if (root == "") throw new IOError.FAILED ("runner root is required");

        var v = spec.effective_variant (variant_id);

        var wine_bin = resolve_spec_path_public (root, v.wine_bin);
        if (wine_bin == "" || !FileUtils.test (wine_bin, FileTest.EXISTS)) {
            throw new IOError.FAILED ("runner '%s': wine binary not found: %s", spec.id, wine_bin);
        }

        var wineserver = resolve_spec_path_public (root, v.wineserver);
        if (wineserver == "" || !FileUtils.test (wineserver, FileTest.EXISTS)) {
            throw new IOError.FAILED ("runner '%s': wineserver not found: %s", spec.id, wineserver);
        }

        var paths = new WinePaths ();
        paths.wine = wine_bin;
        paths.wineserver = wineserver;
        paths.root = root;
        return paths;
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

        if (headless) {
            env.add_dll_override ("winex11.drv", DLL_DISABLED);
            env.add_dll_override ("winewayland.drv", DLL_DISABLED);
        } else if (wayland_enabled && has_wayland) {
            env.add_dll_override ("winex11.drv", DLL_DISABLED);
        } else if (has_x11) {
            env.add_dll_override ("winewayland.drv", DLL_DISABLED);
        } else if (has_wayland) {
            env.add_dll_override ("winex11.drv", DLL_DISABLED);
        }

        if (wine_debug != "" && wine_debug != "off") {
            env.set_var ("WINEDEBUG", wine_debug);
        }

        if (paths.root != "") {
            var v = spec.effective_variant (variant_id);
            var p = v.paths;
            var root = paths.root;

            var bin_dir = resolve_spec_path_public (root, p.bin);

            var ld_parts = new Gee.ArrayList<string> ();
            foreach (var l in p.lib) ld_parts.add (resolve_spec_path_public (root, l));
            foreach (var l in p.lib_64) ld_parts.add (resolve_spec_path_public (root, l));
            foreach (var l in p.lib_32) ld_parts.add (resolve_spec_path_public (root, l));
            foreach (var l in p.wine_unix) ld_parts.add (resolve_spec_path_public (root, l));

            var dll_parts = new Gee.ArrayList<string> ();
            foreach (var d in p.wine_dll) dll_parts.add (resolve_spec_path_public (root, d));
            foreach (var d in p.wine_dll_64) dll_parts.add (resolve_spec_path_public (root, d));
            foreach (var d in p.wine_dll_32) dll_parts.add (resolve_spec_path_public (root, d));

            var ld = join_existing_paths (ld_parts);
            var wine_dll = join_existing_paths (dll_parts);

            env.prepend_path ("PATH", bin_dir);
            env.prepend_path ("LD_LIBRARY_PATH", ld);
            env.prepend_path ("WINEDLLPATH", wine_dll);
            env.set_var ("WINEPATH", wine_dll);
        }

        apply_sync_mode (env, sync_mode);

        return env;
    }

    public void apply_env_overrides (WineEnv env, Gee.HashMap<string, string> overrides) {
        foreach (var entry in overrides.entries) {
            env.set_var (entry.key, entry.value);
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
        Models.RunnerSpec runner_spec,
        string variant_id,
        string runner_version,
        string prefix_root,
        string wine_arch_override,
        string sync_mode,
        string wine_debug,
        bool? wine_wayland,
        Gee.HashMap<string, string>? entry_runtime_env_vars,
        DownloadProgress? download_progress_cb,
        RuntimeLog logger
    ) throws Error {
        var resolved_version = Utils.Preferences.resolve_version (runner_spec.id, runner_version);
        var extract = download_and_extract_runner (
            runner_spec, variant_id, resolved_version, download_progress_cb, logger
        );
        var paths = resolve_wine_paths (extract.extracted_to, runner_spec, variant_id);
        var variant = runner_spec.effective_variant (variant_id);
        var pfx_path = install_prefix_path (prefix_root);
        var arch = wine_arch_override != "" ? wine_arch_override : variant.wine_arch;
        var env = build_wine_env (
            paths, runner_spec, variant_id,
            pfx_path, arch,
            Utils.Preferences.resolve_sync_mode (sync_mode),
            Utils.Preferences.resolve_wine_debug (wine_debug),
            false,
            Utils.Preferences.resolve_wine_wayland (wine_wayland)
        );
        apply_env_overrides (env, Utils.Preferences.instance ().get_runtime_env_vars ());
        if (entry_runtime_env_vars != null) {
            apply_env_overrides (env, entry_runtime_env_vars);
        }
        return new WineRuntime (
            runner_spec, variant, resolved_version, extract,
            paths, pfx_path, arch, env
        );
    }

    private string resolve_spec_path_public (string root, string mapped) {
        var m = mapped.strip ();
        if (m == "") return "";
        if (Path.is_absolute (m)) return m;
        return Path.build_filename (root, m);
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
                if (ntsync_available ()) {
                    env.set_var ("WINEESYNC", "0");
                    env.set_var ("WINEFSYNC", "0");
                    env.set_var ("WINENTSYNC", "1");
                } else {
                    env.set_var ("WINEESYNC", "1");
                    env.set_var ("WINEFSYNC", "1");
                    env.set_var ("WINENTSYNC", "0");
                }
                break;
        }
    }

    private bool ntsync_available () {
        return FileUtils.test ("/dev/ntsync", FileTest.EXISTS) ||
               FileUtils.test ("/sys/module/ntsync", FileTest.IS_DIR);
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

    public void run_wine_command (
        string wine_bin,
        string[] wine_args,
        WineEnv wine_env,
        string? working_dir,
        RuntimeLog logger,
        Cancellable? cancellable = null
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

        var child_killed = false;
        var pid_copy = child_pid;
        ulong cancel_handler = 0;
        if (cancellable != null) {
            cancel_handler = cancellable.connect (() => {
                child_killed = true;
                Posix.kill (pid_copy, Posix.Signal.TERM);
                Thread.usleep (200000);
                Posix.kill (pid_copy, Posix.Signal.KILL);
            });
        }

        int exit_code = drain_spawned_process (
            child_pid,
            stdout_fd,
            stderr_fd,
            stdout_output,
            stderr_output,
            emit_fn
        );

        if (cancellable != null && cancel_handler != 0) {
            cancellable.disconnect (cancel_handler);
        }

        if (child_killed || (cancellable != null && cancellable.is_cancelled ())) {
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
        LogFunc emit_log
    ) {
        var stderr_thread = new Thread<void> ("stderr-reader", () => {
            read_fd_to_log (stderr_fd, stderr_output, emit_log, STDERR_LOG_PREFIX);
        });
        read_fd_to_log (stdout_fd, stdout_output, emit_log, "");
        stderr_thread.join ();

        int status;
        Posix.waitpid (child_pid, out status, 0);
        Process.close_pid (child_pid);
        return Process.if_exited (status) ? Process.exit_status (status) : -1;
    }

    private void read_fd_to_log (int fd, StringBuilder output, LogFunc emit_log, string line_prefix) {
        var channel = new IOChannel.unix_new (fd);
        try {
            channel.set_flags (IOFlags.NONBLOCK);
        } catch (IOChannelError e) {
        }

        char buf[4096];
        size_t bytes_read;
        IOStatus st;
        try {
            while (true) {
                st = channel.read_chars (buf, out bytes_read);
                if (st == IOStatus.EOF || bytes_read == 0) break;
                if (st == IOStatus.AGAIN) {
                    Thread.usleep (10000);
                    continue;
                }
                var chunk = ((string) buf).substring (0, (long) bytes_read);
                output.append (chunk);
                if (line_prefix != "") {
                    var lines = chunk.split ("\n");
                    for (int i = 0; i < lines.length; i++) {
                        if (lines[i] == "" && i == lines.length - 1) continue;
                        emit_log ("%s%s\n".printf (line_prefix, lines[i]));
                    }
                } else {
                    emit_log (chunk);
                }
            }
        } catch (Error e) {
            warning ("Failed to read fd for log: %s", e.message);
        }
        try { channel.shutdown (false); } catch (Error e) {
            warning ("IOChannel shutdown failed: %s", e.message);
        }
    }

    public void create_wine_prefix (WinePaths paths, WineEnv env, RuntimeLog logger, Cancellable? cancellable = null) throws Error {
        var prefix = env.get_var ("WINEPREFIX");
        if (prefix != null) Utils.ensure_dir (prefix);

        var boot_env = env.copy ();
        boot_env.add_dll_override ("mscoree", DLL_DISABLED);

        run_wine_command (paths.wine, { "wineboot", "-u" }, boot_env, null, logger, cancellable);
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
