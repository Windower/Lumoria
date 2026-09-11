namespace Lumoria.Runtime {
    private const int LOG_OUTPUT_TAIL_BYTES = 8192;
    private const int WINE_COMMAND_TERM_WAIT_MS = 1000;
    private const int WINE_COMMAND_KILL_WAIT_MS = 1000;

    private class WineCommandState {
        private Mutex mutex = Mutex ();
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
        Posix.kill ((Posix.pid_t) child_pid, Posix.Signal.TERM);
        Utils.ProcessTree.terminate_descendants (
            child_pid, WINE_COMMAND_TERM_WAIT_MS, WINE_COMMAND_KILL_WAIT_MS
        );
        if (Utils.ProcessTree.process_alive (child_pid)) {
            Posix.kill ((Posix.pid_t) child_pid, Posix.Signal.KILL);
        }
    }

    public void run_wine_command (
        WinePaths paths,
        string[] wine_args,
        WineEnv wine_env,
        string? working_dir,
        RuntimeLog logger,
        Cancellable? cancellable = null,
        int timeout_ms = 0
    ) throws Error {
        run_wine_command_internal (paths, wine_args, wine_env, working_dir, logger, cancellable, timeout_ms, false);
    }

    /* Like run_wine_command, but returns everything the command wrote to stdout. */
    public string run_wine_command_capture (
        WinePaths paths,
        string[] wine_args,
        WineEnv wine_env,
        string? working_dir,
        RuntimeLog logger,
        Cancellable? cancellable = null,
        int timeout_ms = 0
    ) throws Error {
        return run_wine_command_internal (paths, wine_args, wine_env, working_dir, logger, cancellable, timeout_ms, true);
    }

    private string run_wine_command_internal (
        WinePaths paths,
        string[] wine_args,
        WineEnv wine_env,
        string? working_dir,
        RuntimeLog logger,
        Cancellable? cancellable,
        int timeout_ms,
        bool capture_stdout
    ) throws Error {
        var wine_bin = paths.wine;
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
            Utils.strv (argv),
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
            capture_stdout || logger.is_disk_enabled () ? 0 : LOG_OUTPUT_TAIL_BYTES,
            cancellable
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
        return stdout_output.str;
    }

    public void retry_wine_command_after_wineserver (
        WinePaths paths,
        string[] wine_args,
        WineEnv wine_env,
        string? working_dir,
        RuntimeLog logger,
        Cancellable? cancellable = null
    ) throws Error {
        shutdown_wineserver (paths, wine_env, logger);
        Thread.usleep (750000);
        run_wine_command (paths, wine_args, wine_env, working_dir, logger, cancellable);
    }

    public void run_wine_command_with_retry (
        WinePaths paths,
        string[] wine_args,
        WineEnv wine_env,
        string? working_dir,
        RuntimeLog logger,
        Cancellable? cancellable = null,
        string retry_message = "wine command failed; retrying once after wineserver shutdown"
    ) throws Error {
        try {
            run_wine_command (paths, wine_args, wine_env, working_dir, logger, cancellable);
        } catch (Error e) {
            if (!(e is IOError.FAILED)) throw e;
            logger.typed (LogType.WARN, retry_message);
            retry_wine_command_after_wineserver (
                paths, wine_args, wine_env, working_dir, logger, cancellable
            );
        }
    }

    private int drain_spawned_process (
        int child_pid,
        int stdout_fd,
        int stderr_fd,
        StringBuilder stdout_output,
        StringBuilder stderr_output,
        LogFunc emit_log,
        int max_retained_bytes = 0,
        Cancellable? cancellable = null
    ) {
        var stderr_thread = new Thread<void> ("stderr-reader", () => {
            read_fd_to_log (stderr_fd, stderr_output, emit_log, STDERR_LOG_PREFIX, max_retained_bytes, cancellable);
        });
        read_fd_to_log (stdout_fd, stdout_output, emit_log, "", max_retained_bytes, cancellable);
        stderr_thread.join ();

        int status = 0;
        if (cancellable != null && cancellable.is_cancelled ()) {
            var deadline = GLib.get_monotonic_time () + 2 * 1000 * 1000;
            while (Posix.waitpid (child_pid, out status, Posix.WNOHANG) == 0) {
                if (GLib.get_monotonic_time () >= deadline) {
                    Posix.kill ((Posix.pid_t) child_pid, Posix.Signal.KILL);
                    Posix.waitpid (child_pid, out status, 0);
                    break;
                }
                Thread.usleep (10000);
            }
        } else {
            Posix.waitpid (child_pid, out status, 0);
        }
        Process.close_pid (child_pid);
        return Process.if_exited (status) ? Process.exit_status (status) : -1;
    }

    private void read_fd_to_log (
        int fd,
        StringBuilder output,
        LogFunc emit_log,
        string line_prefix,
        int max_retained_bytes = 0,
        Cancellable? cancellable = null
    ) {
        var input = new DataInputStream (new UnixInputStream (fd, true));
        try {
            string? line;
            while ((line = input.read_line (null, cancellable)) != null) {
                var text = line.make_valid ().chomp ();
                append_retained_output (output, text + "\n", max_retained_bytes);
                if (text != "") emit_log ("%s%s\n".printf (line_prefix, text));
            }
        } catch (IOError.CANCELLED e) {
        } catch (Error e) {
            warning ("Failed to read fd for log: %s", e.message);
        }
        try {
            input.close ();
        } catch (Error e) {
            warning ("Failed to close log pipe: %s", e.message);
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
            boot_env.set_dll_override ("mscoree", DLL_DISABLED);
        }

        run_wine_command (paths, { "wineboot", "-u" }, boot_env, null, logger, cancellable);
        // Settle the initial prefix-update session before any subsequent wine
        // command runs. If we leave wineboot's wineserver alive, later wine
        // calls inherit "prefix still being initialized" state and a
        // post-install launch will re-run the update and clobber any native
        // DLLs we placed (e.g. gdiplus). Killing here closes that out.
        shutdown_wineserver (paths, boot_env, logger);
    }

    public void shutdown_wineserver (WinePaths paths, WineEnv env, RuntimeLog logger) {
        shutdown_wineserver_bin (paths.wineserver, env.to_spawn_strv (), logger);
    }

    public int shutdown_wineserver_bin (string wineserver, string[] env, RuntimeLog? logger = null) {
        if (wineserver == "" || !FileUtils.test (wineserver, FileTest.EXISTS)) return -1;
        if (logger != null) logger.typed (LogType.CMD, "%s -k".printf (wineserver));
        try {
            int status;
            Process.spawn_sync (
                null, { wineserver, "-k" }, env, SpawnFlags.SEARCH_PATH, null, null, null, out status
            );
            if (logger != null) logger.typed (LogType.EXIT, "wineserver shutdown code=%d".printf (status));
            return status;
        } catch (Error e) {
            if (logger != null) logger.typed (LogType.WARN, "wineserver shutdown failed: %s".printf (e.message));
            else warning ("wineserver shutdown failed: %s", e.message);
            return -1;
        }
    }
}
