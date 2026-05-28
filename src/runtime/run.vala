namespace Lumoria.Runtime {
    private const int WRAP_ENV_FD = 3;
    private const int WRAP_FD_SCAN_LIMIT = 1024;
    private const string FEATURE_WAYLAND_PRIMARY_MONITOR = "wayland-primary-monitor";

    public class RunResult : Object {
        public int pid { get; set; default = 0; }
        public string executable { get; set; default = ""; }
        public string log_path { get; set; default = ""; }
        public string error_message { get; set; default = ""; }
    }

    private void require_prefix_path (Models.PrefixEntry entry) throws Error {
        if (entry.resolved_path () == "")
            throw new IOError.FAILED ("Prefix path is required");
    }

    public RunResult run_prefix (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        string entrypoint_id = "",
        string custom_exe = "",
        string[]? custom_wine_args = null,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        RuntimeStatusCallback? status_cb = null
    ) throws Error {
        require_prefix_path (entry);

        var session_id = generate_session_id ();
        var logger = RuntimeLog.for_run (entry.resolved_path (), session_id);

        var active_entrypoint_id = entrypoint_id;
        if (active_entrypoint_id == "") {
            active_entrypoint_id = entry.launch_entrypoint_id;
            if (active_entrypoint_id == "") {
                active_entrypoint_id = resolve_effective_entrypoint_id (entry, launcher_specs);
            }
        }

        string exe;
        string[] wine_args;
        if (custom_exe != "") {
            exe = custom_exe;
            wine_args = custom_wine_args != null ? custom_wine_args : new string[] {};
        } else {
            resolve_launcher_exe (entry, launcher_specs, active_entrypoint_id, out exe, out wine_args);
        }

        var active_entrypoint = custom_exe == ""
            ? resolve_launch_entrypoint (entry, launcher_specs, active_entrypoint_id)
            : null;
        var ctx = prepare_runtime_context (
            entry,
            runner_specs,
            false,
            logger,
            active_entrypoint,
            launch_policy,
            status_cb
        );
        apply_launch_env (entry, launcher_specs, custom_exe != "" ? "" : active_entrypoint_id, ctx.env);
        apply_entrypoint_runtime_overrides (active_entrypoint, ctx.env, logger);
        apply_wayland_primary_monitor (entry, runner_specs, ctx.env, logger);
        apply_runtime_logging_policy (ctx.env);
        apply_dxvk_config (entry.resolved_path (), entry, active_entrypoint, ctx.env, logger);

        var host_exe = resolve_host_path (exe, ctx.prefix_path);
        var wine_path = to_wine_path (ctx.prefix_path, host_exe);
        var wine_argv = new Gee.ArrayList<string> ();
        wine_argv.add (ctx.paths.wine);

        var work_dir = Path.get_dirname (host_exe);
        if (!FileUtils.test (work_dir, FileTest.IS_DIR)) {
            work_dir = ctx.prefix_path;
        }
        wine_argv.add (host_exe);
        foreach (var arg in wine_args) wine_argv.add (arg);

        write_run_log_header (logger, entry, host_exe, wine_path, work_dir, wine_argv, ctx.env);

        if (!FileUtils.test (host_exe, FileTest.EXISTS)) {
            var err_msg = "Executable not found: %s".printf (host_exe);
            logger.typed (LogType.ERROR, err_msg);
            throw new IOError.FAILED ("%s", err_msg);
        }

        if (custom_exe == "") {
            try {
                apply_prelaunch_patches (entry, host_exe, logger);
            } catch (Error e) {
                logger.typed (LogType.ERROR, e.message);
                throw e;
            }
        }

        var argv = wine_argv;
        if (!Utils.EnvironmentInfo.is_gamescope ()) {
            var prelaunch_work_dir = ctx.prefix_path;
            argv = wrap_with_prelaunch (
                active_entrypoint != null
                    ? Utils.resolve_user_path (
                        active_entrypoint.prelaunch_script,
                        active_entrypoint.prelaunch_script_portal
                    )
                    : "",
                prelaunch_work_dir,
                argv
            );
            argv = wrap_with_prelaunch (
                Utils.resolve_user_path (entry.prelaunch_script, entry.prelaunch_script_portal),
                prelaunch_work_dir,
                argv
            );
        }

        return spawn_wrapped_process (
            host_exe, work_dir, argv, ctx.env, logger,
            entry.id, ctx.prefix_path, ctx.paths.wineserver
        );
    }

    public RunResult run_prefix_command (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        Gee.ArrayList<string> wine_args,
        string command_label,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        RuntimeStatusCallback? status_cb = null
    ) throws Error {
        require_prefix_path (entry);

        var session_id = generate_session_id ();
        var logger = RuntimeLog.for_run (entry.resolved_path (), session_id);
        var ctx = prepare_runtime_context (
            entry,
            runner_specs,
            true,
            logger,
            null,
            launch_policy,
            status_cb
        );
        apply_launch_env (entry, null, "", ctx.env);
        apply_runtime_logging_policy (ctx.env);
        var argv = new Gee.ArrayList<string> ();
        argv.add (ctx.paths.wine);
        argv.add_all (wine_args);

        write_run_command_log_header (logger, entry, command_label, argv, ctx.env);

        var work_dir = ctx.prefix_path;
        if (!FileUtils.test (work_dir, FileTest.IS_DIR)) {
            work_dir = entry.resolved_path ();
        }

        return spawn_wrapped_process (
            command_label, work_dir, argv, ctx.env, logger,
            entry.id, ctx.prefix_path, ctx.paths.wineserver
        );
    }

    public class TerminalContext : Object {
        public string working_directory { get; set; default = ""; }
        public Gee.HashMap<string, string> env_vars { get; set; }
    }

    public TerminalContext prepare_prefix_terminal_context (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs
    ) throws Error {
        require_prefix_path (entry);

        var session_id = generate_session_id ();
        var logger = RuntimeLog.for_run (entry.resolved_path (), session_id);
        var ctx = prepare_runtime_context (entry, runner_specs, false, logger, null);
        apply_launch_env (entry, null, "", ctx.env);
        apply_runtime_logging_policy (ctx.env);

        var result = new TerminalContext ();
        result.working_directory = entry.resolved_path ();
        result.env_vars = ctx.env.snapshot_vars ();
        return result;
    }

    public void stop_prefix_wineserver (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs
    ) throws Error {
        require_prefix_path (entry);

        var session_id = generate_session_id ();
        var logger = RuntimeLog.for_run (entry.resolved_path (), session_id);
        var ctx = prepare_runtime_context (entry, runner_specs, true, logger, null);
        shutdown_wineserver (ctx.paths, ctx.env, logger);
    }

    private Gee.ArrayList<string> wrap_with_prelaunch (
        string prelaunch_script,
        string prelaunch_work_dir,
        Gee.ArrayList<string> wine_argv
    ) {
        if (prelaunch_script == "" || !FileUtils.test (prelaunch_script, FileTest.EXISTS)) {
            return wine_argv;
        }

        var argv = new Gee.ArrayList<string> ();
        argv.add ("bash");
        argv.add ("-c");
        argv.add ("__lumoria_script=\"$1\"; __lumoria_cwd=\"$2\"; __lumoria_launch_cwd=\"$PWD\"; shift 2; __lumoria_argv=(\"$@\"); cd \"$__lumoria_cwd\" && source \"$__lumoria_script\" && cd \"$__lumoria_launch_cwd\" && exec \"${__lumoria_argv[@]}\"");
        argv.add ("--");
        argv.add (prelaunch_script);
        argv.add (prelaunch_work_dir);
        foreach (var arg in wine_argv) argv.add (arg);
        return argv;
    }

    private WineRuntime prepare_runtime_context (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        bool disable_mscoree,
        RuntimeLog logger,
        Models.Entrypoint? active_entrypoint,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        RuntimeStatusCallback? status_cb = null
    ) throws Error {
        var runner_spec = resolve_runner_spec_for_entry (entry, runner_specs);
        var runtime = prepare_wine_runtime (
            runner_spec, entry.variant_id, entry.runner_version,
            entry.resolved_path (), entry.wine_arch,
            entry.sync_mode, entry.wine_debug, entry.wine_wayland,
            entry.large_address_aware,
            null, null, logger,
            launch_policy,
            entry.runner_state
        );
        ensure_prefix_runner_ready (entry, runtime, logger, true, launch_policy, status_cb);

        if (disable_mscoree) {
            runtime.env.add_dll_override ("mscoree", DLL_DISABLED);
        }
        try {
            var comp_result = apply_enabled_components (
                runtime.paths,
                runtime.prefix_path,
                entry,
                active_entrypoint,
                logger,
                launch_policy
            );
            foreach (var ov in comp_result.dll_overrides.entries) {
                runtime.env.add_dll_override (ov.key, ov.value);
            }
        } catch (Error comp_err) {
            logger.typed (LogType.WARN, "Component application failed: %s".printf (comp_err.message));
        }
        apply_prefix_runtime_dll_overrides (runtime.env, entry, logger);
        apply_env_overrides (runtime.env, Utils.Preferences.instance ().get_runtime_env_vars ());
        apply_env_overrides (runtime.env, entry.runtime_env_vars);
        apply_runtime_logging_policy (runtime.env);
        return runtime;
    }

    private void apply_wayland_primary_monitor (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        WineEnv env,
        RuntimeLog logger
    ) {
        var connector = entry.wayland_primary_monitor.strip ();
        if (connector == "") return;

        try {
            var runner = resolve_runner_spec_for_entry (entry, runner_specs);
            var variant = runner.effective_variant (entry.variant_id);
            if (!variant.supports_feature (FEATURE_WAYLAND_PRIMARY_MONITOR)) return;

            env.set_var ("WAYLANDDRV_PRIMARY_MONITOR", connector);
            logger.typed (LogType.DEBUG, "applied Wayland primary monitor: %s".printf (connector));
        } catch (Error e) {
            logger.typed (LogType.WARN, "Failed to resolve Wayland primary monitor support: %s".printf (e.message));
        }
    }

    private void apply_prefix_runtime_dll_overrides (
        WineEnv env,
        Models.PrefixEntry entry,
        RuntimeLog logger
    ) {
        foreach (var ov in entry.runtime_dll_overrides.entries) {
            var dll = ov.key.strip ();
            var mode = ov.value.strip ();
            if (dll == "" || mode == "") continue;
            env.set_dll_override (dll, mode);
        }
        if (entry.runtime_dll_overrides.size > 0) {
            logger.typed (LogType.DEBUG, "applied prefix runtime dll overrides");
        }
    }

    private void apply_entrypoint_runtime_overrides (
        Models.Entrypoint? entrypoint,
        WineEnv env,
        RuntimeLog logger
    ) {
        if (entrypoint == null) return;
        if (entrypoint.runtime_env_overrides.size > 0) {
            apply_env_overrides (env, entrypoint.runtime_env_overrides);
            logger.typed (LogType.DEBUG, "applied entrypoint runtime env overrides");
        }
        foreach (var ov in entrypoint.runtime_dll_overrides.entries) {
            var dll = ov.key.strip ();
            var mode = ov.value.strip ();
            if (dll == "" || mode == "") continue;
            env.set_dll_override (dll, mode);
        }
        if (entrypoint.runtime_dll_overrides.size > 0) {
            logger.typed (LogType.DEBUG, "applied entrypoint runtime dll overrides");
        }
    }

    private Models.RunnerSpec resolve_runner_spec_for_entry (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs
    ) throws Error {
        var spec = Models.RunnerSpec.find_by_id (runner_specs, entry.runner_id);
        if (spec == null) throw new IOError.FAILED ("No runner spec found for: %s", entry.runner_id);
        return spec;
    }

    private void write_log_header_common (
        RuntimeLog logger,
        Models.PrefixEntry entry,
        Gee.ArrayList<string> detail_lines,
        string cmd_line,
        WineEnv env
    ) {
        var now = new DateTime.now_local ();
        var sandbox_kind = Utils.EnvironmentInfo.is_flatpak () ? "flatpak" : "none";
        logger.banner ("Lumoria Run Log", false);
        logger.emit_line ("Version: %s\n".printf (Config.APP_VERSION));
        var uts = Posix.utsname ();
        var os_name = os_release_value ("PRETTY_NAME")
            ?? os_release_value ("NAME")
            ?? lsb_release_value ("DISTRIB_DESCRIPTION")
            ?? uts.sysname;
        var os_build = os_release_value ("BUILD_ID");
        var os_line = os_build != null ? "%s (build: %s)".printf (os_name, os_build) : os_name;
        logger.emit_line ("OS: %s\n".printf (os_line));
        logger.emit_line ("Kernel: %s %s (%s)\n".printf (uts.sysname, uts.release, uts.machine));
        logger.emit_line ("Started: %s\n".printf (now.format ("%F %T")));
        logger.emit_line ("Prefix: %s\n".printf (entry.resolved_path ()));
        logger.emit_line ("Context: gamescope=%s sandbox=%s\n".printf (
            Utils.EnvironmentInfo.is_gamescope () ? "yes" : "no",
            sandbox_kind
        ));
        logger.emit_line ("Session: DESKTOP_SESSION=%s XDG_SESSION_DESKTOP=%s XDG_CURRENT_DESKTOP=%s\n".printf (
            Environment.get_variable ("DESKTOP_SESSION") ?? "",
            Environment.get_variable ("XDG_SESSION_DESKTOP") ?? "",
            Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? ""
        ));
        foreach (var line in detail_lines) {
            logger.emit_line ("%s\n".printf (line));
        }
        logger.typed (LogType.CMD, cmd_line);
        env.log_wine_vars (logger);
        logger.emit_line ("\n");
    }

    private string? os_release_value (string key) {
        var path = Utils.EnvironmentInfo.is_flatpak () && FileUtils.test ("/run/host/etc/os-release", FileTest.EXISTS)
            ? "/run/host/etc/os-release"
            : "/etc/os-release";
        string content;
        try {
            FileUtils.get_contents (path, out content);
        } catch (Error e) {
            return null;
        }
        foreach (var line in content.split ("\n")) {
            var trimmed = line.strip ();
            if (trimmed == "" || trimmed.has_prefix ("#")) continue;
            var eq = trimmed.index_of_char ('=');
            if (eq <= 0) continue;
            if (trimmed.substring (0, eq) != key) continue;
            return unquote_os_release_value (trimmed.substring (eq + 1));
        }
        return null;
    }

    private string? lsb_release_value (string key) {
        var path = Utils.EnvironmentInfo.is_flatpak () && FileUtils.test ("/run/host/etc/lsb-release", FileTest.EXISTS)
            ? "/run/host/etc/lsb-release"
            : "/etc/lsb-release";
        string content;
        try {
            FileUtils.get_contents (path, out content);
        } catch (Error e) {
            return null;
        }
        foreach (var line in content.split ("\n")) {
            var trimmed = line.strip ();
            if (trimmed == "" || trimmed.has_prefix ("#")) continue;
            var eq = trimmed.index_of_char ('=');
            if (eq <= 0) continue;
            if (trimmed.substring (0, eq) != key) continue;
            return unquote_os_release_value (trimmed.substring (eq + 1));
        }
        return null;
    }

    private string unquote_os_release_value (string value) {
        var trimmed = value.strip ();
        if (trimmed.length >= 2) {
            var first = trimmed[0];
            var last = trimmed[trimmed.length - 1];
            if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
                return trimmed.substring (1, trimmed.length - 2);
            }
        }
        return trimmed;
    }

    private void write_run_log_header (
        RuntimeLog logger,
        Models.PrefixEntry entry,
        string host_exe,
        string wine_path,
        string work_dir,
        Gee.ArrayList<string> argv,
        WineEnv env
    ) {
        var detail_lines = new Gee.ArrayList<string> ();
        detail_lines.add ("Executable: %s".printf (host_exe));
        detail_lines.add ("Wine path: %s".printf (wine_path));
        detail_lines.add ("Working dir: %s".printf (work_dir));
        write_log_header_common (
            logger, entry, detail_lines,
            string.joinv (" ", Utils.arraylist_to_strv (argv)),
            env
        );
    }

    private void write_run_command_log_header (
        RuntimeLog logger,
        Models.PrefixEntry entry,
        string command_label,
        Gee.ArrayList<string> argv,
        WineEnv env
    ) {
        var detail_lines = new Gee.ArrayList<string> ();
        detail_lines.add ("Command: %s".printf (command_label));
        write_log_header_common (
            logger, entry, detail_lines,
            string.joinv (" ", Utils.arraylist_to_strv (argv)),
            env
        );
    }

    private bool session_manager_responds () {
        try {
            var obj = new Json.Object ();
            obj.set_string_member ("method", "ping");
            return Cli.response_ok (Cli.session_send_request (json_object_to_string (obj)));
        } catch (Error e) {
            return false;
        }
    }

    private bool ensure_session_manager () {
        if (session_manager_responds ()) return true;

        var socket_path = Cli.session_socket_path ();
        Utils.ensure_dir (Path.get_dirname (socket_path));
        FileUtils.unlink (socket_path);
        try {
            Pid session_pid;
            Process.spawn_async (
                null,
                session_manager_spawn_argv (),
                null,
                SpawnFlags.SEARCH_PATH,
                null,
                out session_pid
            );
        } catch (Error e) {
            warning ("Session manager self-spawn failed: %s", e.message);
            return false;
        }

        for (int i = 0; i < 10; i++) {
            Posix.usleep (100 * 1000);
            if (session_manager_responds ()) return true;
        }

        warning ("Session manager did not respond after 1s");
        return false;
    }

    private string[] session_manager_spawn_argv () throws Error {
        var self_exe = Utils.current_executable_path ();
        if (self_exe == null)
            throw new IOError.FAILED ("could not resolve self executable path");

        return { self_exe, "session-manager" };
    }

    private int session_launch (
        string prefix_id,
        string prefix_path,
        string wineserver_path,
        string log_path,
        string[] env,
        string work_dir,
        string[] argv
    ) throws Error {
        var obj = new Json.Object ();
        obj.set_string_member ("method", "launch");
        obj.set_string_member ("prefix_id", prefix_id);
        obj.set_string_member ("prefix_path", prefix_path);
        obj.set_string_member ("wineserver", wineserver_path);
        obj.set_string_member ("log_path", log_path);
        obj.set_string_member ("cwd", work_dir);
        obj.set_array_member ("env", strv_to_json_array (env));
        obj.set_array_member ("argv", strv_to_json_array (argv));

        var response = Cli.session_send_request (json_object_to_string (obj));
        if (!Cli.response_ok (response))
            throw new IOError.FAILED ("%s", Cli.response_error (response));

        var parser = new Json.Parser ();
        parser.load_from_data (response);
        return (int) parser.get_root ().get_object ().get_int_member ("pid");
    }

    private Json.Array strv_to_json_array (string[] values) {
        var array = new Json.Array ();
        foreach (var value in values) {
            array.add_string_element (value);
        }
        return array;
    }

    private string json_object_to_string (Json.Object obj) {
        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (obj);
        var generator = new Json.Generator ();
        generator.root = node;
        return generator.to_data (null);
    }

    private string[] wine_env_to_strv (WineEnv env) {
        var lines = new Gee.ArrayList<string> ();
        foreach (var e in env.snapshot_vars ().entries) {
            lines.add ("%s=%s".printf (e.key, e.value));
        }
        return Utils.arraylist_to_strv (lines);
    }

    private RunResult spawn_wrapped_process (
        string executable_label,
        string work_dir,
        Gee.ArrayList<string> argv,
        WineEnv env,
        RuntimeLog logger,
        string prefix_id = "",
        string prefix_path = "",
        string wineserver_path = ""
    ) throws Error {
        var log_path = logger.log_path;

        if (Utils.Preferences.instance ().session_manager) {
            if (ensure_session_manager ()) {
                logger.close ();
                try {
                    var pid = session_launch (
                        prefix_id, prefix_path, wineserver_path,
                        log_path, wine_env_to_strv (env), work_dir,
                        Utils.arraylist_to_strv (argv)
                    );
                    var run_result = new RunResult ();
                    run_result.pid = pid;
                    run_result.executable = executable_label;
                    run_result.log_path = log_path;
                    return run_result;
                } catch (Error e) {
                    warning ("Session manager launch failed, falling back to direct fork: %s", e.message);
                }
            } else {
                warning ("Session manager unavailable, falling back to direct fork");
            }
        }
        var env_pipe = new int[2];
        if (Posix.pipe (env_pipe) != 0) {
            throw new IOError.FAILED ("Failed to create wrapper environment pipe: %s", Posix.strerror (Posix.errno));
        }

        logger.close ();

        var self_exe = Utils.current_executable_path () ?? "lumoria";
        var wrapped = new Gee.ArrayList<string> ();
        wrapped.add (self_exe);
        wrapped.add ("wrap");
        wrapped.add ("--log");
        wrapped.add (log_path);
        wrapped.add ("--env-fd");
        wrapped.add (WRAP_ENV_FD.to_string ());
        if (work_dir != "") {
            wrapped.add ("--cwd");
            wrapped.add (work_dir);
        }
        wrapped.add ("--");
        wrapped.add_all (argv);

        var child_pid = Posix.fork ();
        if (child_pid < 0) {
            Posix.close (env_pipe[0]);
            Posix.close (env_pipe[1]);
            throw new IOError.FAILED ("Failed to fork wrapper: %s", Posix.strerror (Posix.errno));
        }

        if (child_pid == 0) {
            Posix.close (env_pipe[1]);
            if (env_pipe[0] != WRAP_ENV_FD) {
                Posix.dup2 (env_pipe[0], WRAP_ENV_FD);
            }
            if (work_dir != "") {
                Posix.chdir (work_dir);
            }
            close_unrelated_fds (WRAP_ENV_FD);
            Posix.execvp (wrapped[0], Utils.arraylist_to_strv (wrapped));
            Posix._exit (127);
        }
        Posix.close (env_pipe[0]);
        try {
            write_all_fd (env_pipe[1], build_wrap_env_payload (env));
        } finally {
            Posix.close (env_pipe[1]);
        }

        var pid_copy = child_pid;
        new Thread<bool> ("wrap-reaper", () => {
            int status;
            Posix.waitpid (pid_copy, out status, 0);
            Process.close_pid (pid_copy);
            return true;
        });

        var run_result = new RunResult ();
        run_result.pid = child_pid;
        run_result.executable = executable_label;
        run_result.log_path = log_path;
        return run_result;
    }

    private void close_unrelated_fds (int keep_fd) {
        for (int fd = 3; fd < WRAP_FD_SCAN_LIMIT; fd++) {
            if (fd != keep_fd) Posix.close (fd);
        }
    }

    private string build_wrap_env_payload (WineEnv env) {
        var lines = new Gee.ArrayList<string> ();
        foreach (var entry in env.snapshot_vars ().entries) {
            lines.add ("%s=%s".printf (entry.key, entry.value));
        }
        return string.joinv ("\n", Utils.arraylist_to_strv (lines));
    }

    private void write_all_fd (int fd, string payload) throws Error {
        uint8[] bytes = payload.data;
        size_t offset = 0;
        while (offset < bytes.length) {
            var written = Posix.write (fd, (uint8[]) bytes[offset:bytes.length], bytes.length - offset);
            if (written < 0) {
                throw new IOError.FAILED ("Failed to write wrapper environment pipe: %s", Posix.strerror (Posix.errno));
            }
            if (written == 0) {
                throw new IOError.FAILED ("Failed to write wrapper environment pipe");
            }
            offset += written;
        }
    }

    private RunResult spawn_tracked_process (
        string executable_label,
        string work_dir,
        Gee.ArrayList<string> argv,
        WineEnv env,
        RuntimeLog logger
    ) throws Error {
        var spawn_argv = Utils.arraylist_to_strv (argv);

        int child_pid;
        int stdout_fd;
        int stderr_fd;
        Process.spawn_async_with_pipes (
            work_dir,
            spawn_argv,
            env.to_spawn_strv (),
            CHILD_SPAWN_FLAGS,
            null,
            out child_pid,
            null,
            out stdout_fd,
            out stderr_fd
        );

        var logger_copy = logger;
        var pid_copy = child_pid;
        new Thread<bool> ("run-logger", () => {
            drain_pipes_to_log (logger_copy, stdout_fd, stderr_fd, pid_copy);
            return true;
        });

        var run_result = new RunResult ();
        run_result.pid = child_pid;
        run_result.executable = executable_label;
        run_result.log_path = logger.log_path;
        return run_result;
    }

    private string generate_session_id () {
        return "%08x-%04x".printf (
            (uint32) GLib.get_real_time (),
            (uint16) GLib.Random.next_int ()
        );
    }

    private void drain_pipes_to_log (RuntimeLog logger, int stdout_fd, int stderr_fd, int child_pid) {

        var stdout_sb = new StringBuilder ();
        var stderr_sb = new StringBuilder ();

        LogFunc write_to_log = (msg) => {
            logger.emit_line (msg);
        };

        int exit_code = drain_spawned_process (
            child_pid,
            stdout_fd,
            stderr_fd,
            stdout_sb,
            stderr_sb,
            write_to_log
        );
        logger.emit_line ("\n");
        logger.typed (LogType.EXIT, "code=%d".printf (exit_code));
        logger.close ();
    }
}
