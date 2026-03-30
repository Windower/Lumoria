namespace Lumoria.Runtime {

    public class RunResult : Object {
        public int pid { get; set; default = 0; }
        public string executable { get; set; default = ""; }
        public string log_path { get; set; default = ""; }
        public string error_message { get; set; default = ""; }
    }

    private class RuntimeContext : Object {
        public WinePaths paths { get; set; }
        public string prefix_path { get; set; default = ""; }
        public WineEnv env { get; set; }
    }

    private void require_prefix_path (Models.PrefixEntry entry) throws Error {
        if (entry.path == "")
            throw new IOError.FAILED ("Prefix path is required");
    }

    public RunResult run_prefix (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        string entrypoint_id = "",
        string custom_exe = "",
        string[]? custom_wine_args = null
    ) throws Error {
        require_prefix_path (entry);

        var session_id = generate_session_id ();
        var logger = RuntimeLog.for_run (entry.path, session_id);
        var ctx = prepare_runtime_context (entry, runner_specs, false, logger);

        if (entrypoint_id == "") {
            entrypoint_id = entry.launch_entrypoint_id;
        }

        string exe;
        string[] wine_args;
        if (custom_exe != "") {
            exe = custom_exe;
            wine_args = custom_wine_args != null ? custom_wine_args : new string[] {};
        } else {
            resolve_launcher_exe (entry, launcher_specs, entrypoint_id, out exe, out wine_args);
        }

        var host_exe = resolve_host_path (exe, ctx.prefix_path);
        var wine_path = to_wine_path (ctx.prefix_path, host_exe);
        var log_path = logger.log_path;

        var wine_argv = new Gee.ArrayList<string> ();
        wine_argv.add (ctx.paths.wine);
        wine_argv.add (wine_path);
        foreach (var arg in wine_args) wine_argv.add (arg);

        var work_dir = Path.get_dirname (host_exe);
        if (!FileUtils.test (work_dir, FileTest.IS_DIR)) {
            work_dir = ctx.prefix_path;
        }

        if (logger.is_disk_enabled ()) {
            write_run_log_header (logger, entry, host_exe, wine_path, work_dir, wine_argv, ctx.env);
        }

        if (!FileUtils.test (host_exe, FileTest.EXISTS)) {
            var err_msg = "Executable not found: %s".printf (host_exe);
            logger.append_line (RuntimeLog.tagged_line (LogType.ERROR, err_msg));
            throw new IOError.FAILED ("%s", err_msg);
        }

        if (custom_exe == "") {
            try {
                apply_prelaunch_patches (entry, host_exe, logger);
            } catch (Error e) {
                logger.append_line (RuntimeLog.tagged_line (LogType.ERROR, e.message));
                throw e;
            }
        }

        string ep_prelaunch = "";
        if (custom_exe == "") {
            foreach (var ep in entry.custom_entrypoints) {
                if (ep.id == entrypoint_id) {
                    ep_prelaunch = ep.prelaunch_script;
                    break;
                }
            }
        }

        var argv = wrap_with_prelaunch (ep_prelaunch, wine_argv);
        argv = wrap_with_prelaunch (entry.prelaunch_script, argv);

        return spawn_tracked_process (
            host_exe, work_dir, argv, ctx.env, log_path
        );
    }

    public RunResult run_prefix_command (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        Gee.ArrayList<string> wine_args,
        string command_label
    ) throws Error {
        require_prefix_path (entry);

        var session_id = generate_session_id ();
        var logger = RuntimeLog.for_run (entry.path, session_id);
        var ctx = prepare_runtime_context (entry, runner_specs, true, logger);
        var log_path = logger.log_path;

        var argv = new Gee.ArrayList<string> ();
        argv.add (ctx.paths.wine);
        argv.add_all (wine_args);

        if (logger.is_disk_enabled ()) {
            write_run_command_log_header (logger, entry, command_label, argv, ctx.env);
        }

        var work_dir = ctx.prefix_path;
        if (!FileUtils.test (work_dir, FileTest.IS_DIR)) {
            work_dir = entry.path;
        }

        return spawn_tracked_process (
            command_label, work_dir, argv, ctx.env, log_path
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
        var logger = RuntimeLog.for_run (entry.path, session_id);
        var ctx = prepare_runtime_context (entry, runner_specs, false, logger);

        var result = new TerminalContext ();
        result.working_directory = ctx.prefix_path;
        result.env_vars = ctx.env.snapshot_vars ();
        return result;
    }

    public void stop_prefix_wineserver (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs
    ) throws Error {
        require_prefix_path (entry);

        var session_id = generate_session_id ();
        var logger = RuntimeLog.for_run (entry.path, session_id);
        var ctx = prepare_runtime_context (entry, runner_specs, true, logger);
        shutdown_wineserver (ctx.paths, ctx.env, logger.emitter ());
    }

    private Gee.ArrayList<string> wrap_with_prelaunch (
        string prelaunch_script,
        Gee.ArrayList<string> wine_argv
    ) {
        if (prelaunch_script == "" || !FileUtils.test (prelaunch_script, FileTest.EXISTS)) {
            return wine_argv;
        }

        var argv = new Gee.ArrayList<string> ();
        argv.add ("bash");
        argv.add ("-c");
        argv.add ("source \"$1\" && shift && exec \"$@\"");
        argv.add ("--");
        argv.add (prelaunch_script);
        foreach (var arg in wine_argv) argv.add (arg);
        return argv;
    }

    private RuntimeContext prepare_runtime_context (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        bool disable_mscoree,
        RuntimeLog logger
    ) throws Error {
        var runner_spec = resolve_runner_spec_for_entry (entry, runner_specs);
        var runner_version = Utils.Preferences.resolve_version (entry.runner_id, entry.runner_version);

        var result = download_and_extract_runner (
            runner_spec, entry.variant_id, runner_version, null
        );
        var paths = resolve_wine_paths (result.extracted_to, runner_spec, entry.variant_id);
        var variant = runner_spec.effective_variant (entry.variant_id);
        var pfx_path = install_prefix_path (entry.path);

        var env = build_wine_env (
            paths, runner_spec, entry.variant_id,
            pfx_path, variant.wine_arch,
            Utils.Preferences.resolve_sync_mode (entry.sync_mode),
            Utils.Preferences.resolve_wine_debug (entry.wine_debug),
            false,
            Utils.Preferences.resolve_wine_wayland (entry.wine_wayland)
        );
        if (disable_mscoree) {
            env.add_dll_override ("mscoree", DLL_DISABLED);
        }

        var prefs = Utils.Preferences.instance ();
        try {
            var comp_result = apply_enabled_components (pfx_path, entry, null);
            foreach (var ov in comp_result.dll_overrides.entries) {
                env.add_dll_override (ov.key, ov.value);
            }
        } catch (Error comp_err) {
            logger.warn ("Component application failed: %s".printf (comp_err.message));
        }
        apply_env_overrides (env, prefs.get_runtime_env_vars ());
        apply_env_overrides (env, entry.runtime_env_vars);

        var ctx = new RuntimeContext ();
        ctx.paths = paths;
        ctx.prefix_path = pfx_path;
        ctx.env = env;
        return ctx;
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
        var lines = new Gee.ArrayList<string> ();
        var now = new DateTime.now_local ();
        lines.add ("=== Lumoria Run Log ===");
        lines.add ("Started: %s".printf (now.format ("%F %T")));
        lines.add ("Prefix: %s".printf (entry.path));
        foreach (var line in detail_lines) {
            lines.add (line);
        }
        lines.add (RuntimeLog.tagged_line (LogType.CMD, cmd_line));
        foreach (var key in LOG_ENV_KEYS) {
            var val = env.get_var (key);
            if (val != null) {
                lines.add (RuntimeLog.tagged_line (LogType.ENV, "%s=%s".printf (key, val)));
            }
        }
        lines.add ("");
        logger.overwrite_lines (lines);
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

    private RunResult spawn_tracked_process (
        string executable_label,
        string work_dir,
        Gee.ArrayList<string> argv,
        WineEnv env,
        string log_path
    ) throws Error {
        var spawn_argv = Utils.arraylist_to_strv (argv);

        int child_pid;
        int stdout_fd;
        int stderr_fd;
        Process.spawn_async_with_pipes (
            work_dir,
            spawn_argv,
            env.to_spawn_strv (),
            SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
            null,
            out child_pid,
            null,
            out stdout_fd,
            out stderr_fd
        );

        if (log_path != "") {
            var log_path_copy = log_path;
            var pid_copy = child_pid;
            new Thread<bool> ("run-logger", () => {
                drain_pipes_to_log (log_path_copy, stdout_fd, stderr_fd, pid_copy);
                return true;
            });
        } else {
            var pid_copy = child_pid;
            var sfd = stdout_fd;
            var efd = stderr_fd;
            new Thread<bool> ("run-reaper", () => {
                try { new IOChannel.unix_new (sfd).shutdown (false); } catch (Error e) {
                    warning ("IOChannel stdout shutdown failed: %s", e.message);
                }
                try { new IOChannel.unix_new (efd).shutdown (false); } catch (Error e) {
                    warning ("IOChannel stderr shutdown failed: %s", e.message);
                }
                int status;
                Posix.waitpid (pid_copy, out status, 0);
                Process.close_pid (pid_copy);
                return true;
            });
        }

        var run_result = new RunResult ();
        run_result.pid = child_pid;
        run_result.executable = executable_label;
        run_result.log_path = log_path;
        return run_result;
    }

    private string generate_session_id () {
        return "%08x-%04x".printf (
            (uint32) GLib.get_real_time (),
            (uint16) GLib.Random.next_int ()
        );
    }

    private void drain_pipes_to_log (string log_path, int stdout_fd, int stderr_fd, int child_pid) {
        OutputStream? log_out = null;
        try {
            log_out = File.new_for_path (log_path).append_to (FileCreateFlags.NONE);
        } catch (Error e) {
            warning ("Failed to open run log for appending: %s", e.message);
        }

        var stdout_sb = new StringBuilder ();
        var stderr_sb = new StringBuilder ();

        LogFunc write_to_log = (msg) => {
            if (log_out == null) return;
            try { log_out.write (msg.data); } catch (Error e) {
                warning ("Failed to write to run log: %s", e.message);
            }
        };

        var stderr_thread = new Thread<void> ("stderr-drain", () => {
            read_fd_to_log (stderr_fd, stderr_sb, write_to_log, RuntimeLog.tag_prefix (LogType.STDERR));
        });

        read_fd_to_log (stdout_fd, stdout_sb, write_to_log, "");

        stderr_thread.join ();

        int status;
        Posix.waitpid (child_pid, out status, 0);
        Process.close_pid (child_pid);

        int exit_code = Process.if_exited (status) ? Process.exit_status (status) : -1;

        if (log_out != null) {
            try {
                log_out.write (("\n%s\n".printf (RuntimeLog.tagged_line (LogType.EXIT, "code=%d".printf (exit_code)))).data);
                log_out.close ();
            } catch (Error e) {
                warning ("Failed to write exit code or close run log: %s", e.message);
            }
        }
    }
}
