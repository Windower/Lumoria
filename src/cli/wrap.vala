namespace Lumoria.Cli {

    [CCode (cname = "prctl", cheader_filename = "sys/prctl.h")]
    private extern int prctl (int option, ulong arg2, ulong arg3 = 0, ulong arg4 = 0, ulong arg5 = 0);

    private const int PR_SET_CHILD_SUBREAPER = 36;
    private const int DEFAULT_WRAP_POLL_MS = 100;
    private const int MIN_WRAP_POLL_MS = 10;
    private const int MAX_WRAP_POLL_MS = 5000;
    private const int WRAP_CLEANUP_TERM_WAIT_MS = 1000;
    private const int WRAP_CLEANUP_KILL_WAIT_MS = 1000;
    private const int WRAP_REAP_WAIT_MS = 1000;
    private const int WRAP_LOG_RELAY_JOIN_WAIT_MS = 1000;
    private const string WRAP_MODE_LEGACY = "legacy";

    private int wrap_signal_state = 0;
    private int wrap_signal_number = 0;
    private Thread<void>? log_relay_thread = null;
    private bool log_relay_done = false;

    public int cmd_wrap (string[] args) {
        string log_path = "";
        string cwd = "";
        int env_fd = -1;
        int cmd_start = -1;

        for (int i = 2; i < args.length; i++) {
            if (args[i] == "--log" && i + 1 < args.length) {
                log_path = args[++i];
            } else if (args[i] == "--env-fd" && i + 1 < args.length) {
                env_fd = int.parse (args[++i]);
            } else if (args[i] == "--cwd" && i + 1 < args.length) {
                cwd = args[++i];
            } else if (args[i] == "--") {
                cmd_start = i + 1;
                break;
            }
        }

        if (cmd_start < 0 || cmd_start >= args.length) {
            stderr.printf ("Usage: lumoria wrap --log <path> [--env-fd <fd>] [--cwd <path>] -- <command...>\n");
            return 1;
        }

        if (prctl (PR_SET_CHILD_SUBREAPER, 1) != 0) {
            stderr.printf ("warn: PR_SET_CHILD_SUBREAPER failed (errno %d), continuing without subreaper\n",
                Posix.errno);
        }

        redirect_stdio (log_path);
        var child_pwd = apply_working_directory (cwd);

        var cmd = new string[args.length - cmd_start + 1];
        for (int i = cmd_start; i < args.length; i++) {
            cmd[i - cmd_start] = args[i];
        }
        cmd[args.length - cmd_start] = null;

        var child_pid = Posix.fork ();
        if (child_pid < 0) {
            stdout.printf ("[wrap] fork failed: %s\n", Posix.strerror (Posix.errno));
            return 1;
        }

        if (child_pid == 0) {
            apply_child_env (env_fd);
            if (child_pwd != "") {
                Environment.set_variable ("PWD", child_pwd, true);
            }
            Posix.execvp (cmd[0], cmd);
            stdout.printf ("[lumoria-internal] exec failed: %s\n", Posix.strerror (Posix.errno));
            Posix._exit (127);
        }

        if (env_fd >= 0) Posix.close (env_fd);

        var mode = Environment.get_variable ("LUMORIA_WRAP_MODE") ?? "";
        var poll_ms = wrap_poll_interval_ms ();
        int initial_signal = 0;
        var initial_code = mode == WRAP_MODE_LEGACY
            ? legacy_loop (child_pid, out initial_signal)
            : watcher_loop (child_pid, poll_ms, out initial_signal);
        cleanup_remaining_descendants ();

        if (log_path != "") {
            if (initial_signal > 0) {
                stdout.printf ("\n[exit] code=%d signal=%d\n", initial_code, initial_signal);
            } else {
                stdout.printf ("\n[exit] code=%d\n", initial_code);
            }
            stdout.flush ();
        }

        Posix.close (Posix.STDOUT_FILENO);
        Posix.close (Posix.STDERR_FILENO);
        finish_log_relay ();

        return initial_code >= 0 ? initial_code : 1;
    }

    private void redirect_stdio (string log_path) {
        var target_path = log_path != "" ? log_path : "/dev/null";
        var flags = log_path != ""
            ? Posix.O_WRONLY | Posix.O_CREAT | Posix.O_APPEND
            : Posix.O_WRONLY;
        var log_fd = Posix.open (target_path, flags, 0644);
        if (log_fd < 0) {
            if (log_path != "") {
                stderr.printf ("warn: could not open log %s, inheriting caller fds\n", log_path);
            }
            return;
        }

        if (log_path == "") {
            Posix.dup2 (log_fd, Posix.STDOUT_FILENO);
            Posix.dup2 (log_fd, Posix.STDERR_FILENO);
            Posix.close (log_fd);
            return;
        }

        // Relay through a pipe so wine never directly inherits the log fd.
        // Wine segfaults inside the flatpak sandbox when it inherits an fd that
        // points to an xdg-document-portal FUSE file.
        var pipe_fds = new int[2];
        if (Posix.pipe (pipe_fds) != 0) {
            Posix.dup2 (log_fd, Posix.STDOUT_FILENO);
            Posix.dup2 (log_fd, Posix.STDERR_FILENO);
            Posix.close (log_fd);
            return;
        }

        var relay_read = pipe_fds[0];
        log_relay_done = false;
        log_relay_thread = new Thread<void> ("log-relay", () => {
            relay_pipe_to_fd (relay_read, log_fd);
            log_relay_done = true;
        });
        Posix.dup2 (pipe_fds[1], Posix.STDOUT_FILENO);
        Posix.dup2 (pipe_fds[1], Posix.STDERR_FILENO);
        Posix.close (pipe_fds[1]);
    }

    private void finish_log_relay () {
        if (log_relay_thread == null) return;

        var deadline = GLib.get_monotonic_time () + (int64) WRAP_LOG_RELAY_JOIN_WAIT_MS * 1000;
        while (!log_relay_done && GLib.get_monotonic_time () < deadline) {
            Thread.usleep (100000);
        }

        if (log_relay_done) {
            log_relay_thread.join ();
        }
    }

    private string apply_working_directory (string cwd) {
        if (cwd == "") return "";
        if (Posix.chdir (cwd) == 0) {
            stdout.printf ("[wrap] cwd=%s\n", cwd);
            stdout.flush ();
            return Environment.get_current_dir ();
        }
        stdout.printf ("[wrap] cwd failed: %s: %s\n", cwd, Posix.strerror (Posix.errno));
        stdout.flush ();
        return "";
    }

    private void relay_pipe_to_fd (int read_fd, int write_fd) {
        var buf = new uint8[65536];
        ssize_t n;
        while ((n = Posix.read (read_fd, buf, buf.length)) > 0) {
            ssize_t offset = 0;
            while (offset < n) {
                var w = Posix.write (write_fd, (uint8[]) buf[offset:n], (size_t) (n - offset));
                if (w <= 0) break;
                offset += w;
            }
        }
        Posix.close (read_fd);
        Posix.close (write_fd);
    }

    private int legacy_loop (int child_pid, out int initial_signal) {
        int initial_code = -1;
        initial_signal = 0;
        bool initial_reaped = false;

        while (true) {
            int status;
            var pid = Posix.waitpid (-1, out status, 0);
            if (pid < 0) break;
            if (pid == child_pid && !initial_reaped) {
                initial_reaped = true;
                if (Process.if_exited (status)) {
                    initial_code = Process.exit_status (status);
                } else if (Process.if_signaled (status)) {
                    initial_signal = Process.term_sig (status);
                }
            }
        }

        return initial_code;
    }

    private int watcher_loop (int child_pid, int poll_ms, out int initial_signal) {
        int initial_code = -1;
        initial_signal = 0;
        bool initial_reaped = false;
        bool no_more_children = false;
        bool soft_signal_processed = false;
        bool hard_signal_processed = false;

        install_wrap_signal_handlers ();

        try {
            if (!has_monitored_descendants ()) {
                stdout.printf ("[wrap] waiting for monitored process to start\n");
                while (!has_monitored_descendants ()) {
                    reap_children_nonblocking (
                        child_pid, ref initial_code, ref initial_signal, ref initial_reaped, out no_more_children
                    );
                    process_pending_wrap_signal (ref soft_signal_processed, ref hard_signal_processed);
                    if (no_more_children) return initial_code;
                    sleep_poll_interval (poll_ms);
                }
            }

            while (has_monitored_descendants ()) {
                reap_children_nonblocking (
                    child_pid, ref initial_code, ref initial_signal, ref initial_reaped, out no_more_children
                );
                process_pending_wrap_signal (ref soft_signal_processed, ref hard_signal_processed);
                if (no_more_children) return initial_code;
                sleep_poll_interval (poll_ms);
            }

            reap_children_nonblocking (
                child_pid, ref initial_code, ref initial_signal, ref initial_reaped, out no_more_children
            );
        } finally {
            restore_default_wrap_signal_handlers ();
        }

        return initial_code;
    }

    private int wrap_poll_interval_ms () {
        var value = Environment.get_variable ("LUMORIA_WRAP_POLL_MS") ?? "";
        int64 parsed;
        if (!int64.try_parse (value, out parsed)) return DEFAULT_WRAP_POLL_MS;
        if (parsed < MIN_WRAP_POLL_MS) return MIN_WRAP_POLL_MS;
        if (parsed > MAX_WRAP_POLL_MS) return MAX_WRAP_POLL_MS;
        return (int) parsed;
    }

    private void sleep_poll_interval (int poll_ms) {
        Posix.usleep ((uint) poll_ms * 1000);
    }

    private void reap_children_nonblocking (
        int child_pid,
        ref int initial_code,
        ref int initial_signal,
        ref bool initial_reaped,
        out bool no_more_children
    ) {
        no_more_children = false;
        while (true) {
            int status;
            var pid = Posix.waitpid (-1, out status, Posix.WNOHANG);
            if (pid == 0) return;
            if (pid < 0) {
                no_more_children = Posix.errno == Posix.ECHILD;
                return;
            }
            if (pid == child_pid && !initial_reaped) {
                initial_reaped = true;
                if (Process.if_exited (status)) {
                    initial_code = Process.exit_status (status);
                } else if (Process.if_signaled (status)) {
                    initial_signal = Process.term_sig (status);
                }
            }
        }
    }

    private bool has_monitored_descendants () {
        return Utils.ProcessTree.has_monitored_descendants ((int) Posix.getpid ());
    }

    private void signal_monitored_descendants (int signum) {
        Utils.ProcessTree.signal_monitored_descendants ((int) Posix.getpid (), signum);
    }

    private void cleanup_remaining_descendants () {
        signal_monitored_descendants (Posix.Signal.TERM);
        if (Utils.ProcessTree.wait_for_monitored_descendants ((int) Posix.getpid (), WRAP_CLEANUP_TERM_WAIT_MS)) {
            drain_remaining_children ();
            return;
        }

        for (var i = 0; i < 3; i++) {
            signal_monitored_descendants (Posix.Signal.KILL);
        }
        Utils.ProcessTree.wait_for_monitored_descendants ((int) Posix.getpid (), WRAP_CLEANUP_KILL_WAIT_MS);
        drain_remaining_children ();
    }

    private bool reap_remaining_children () {
        bool reaped = false;
        while (true) {
            int status;
            var pid = Posix.waitpid (-1, out status, Posix.WNOHANG);
            if (pid > 0) {
                reaped = true;
                continue;
            }
            return reaped || (pid < 0 && Posix.errno == Posix.ECHILD);
        }
    }

    private void drain_remaining_children () {
        var deadline = GLib.get_monotonic_time () + (int64) WRAP_REAP_WAIT_MS * 1000;
        while (GLib.get_monotonic_time () < deadline) {
            if (reap_remaining_children ()) return;
            Thread.usleep (100000);
        }
    }

    private void install_wrap_signal_handlers () {
        wrap_signal_state = 0;
        wrap_signal_number = 0;
        Posix.signal (Posix.Signal.TERM, wrap_soft_signal_handler);
        Posix.signal (Posix.Signal.INT, wrap_soft_signal_handler);
    }

    private void restore_default_wrap_signal_handlers () {
        Posix.signal (Posix.Signal.TERM, Posix.SIG_DFL);
        Posix.signal (Posix.Signal.INT, Posix.SIG_DFL);
    }

    private void wrap_soft_signal_handler (int signum) {
        wrap_signal_number = signum;
        wrap_signal_state = 1;
        Posix.signal (Posix.Signal.TERM, wrap_hard_signal_handler);
        Posix.signal (Posix.Signal.INT, wrap_hard_signal_handler);
    }

    private void wrap_hard_signal_handler (int signum) {
        wrap_signal_number = signum;
        wrap_signal_state = 2;
    }

    private void process_pending_wrap_signal (
        ref bool soft_signal_processed,
        ref bool hard_signal_processed
    ) {
        if (wrap_signal_state >= 1 && !soft_signal_processed) {
            stdout.printf ("[wrap] caught signal %d, terminating monitored processes\n", wrap_signal_number);
            signal_monitored_descendants (Posix.Signal.TERM);
            soft_signal_processed = true;
        }
        if (wrap_signal_state >= 2 && !hard_signal_processed) {
            stdout.printf ("[wrap] caught second signal, killing monitored processes\n");
            for (var i = 0; i < 3; i++) {
                signal_monitored_descendants (Posix.Signal.KILL);
            }
            hard_signal_processed = true;
        }
    }

    private void apply_child_env (int env_fd) {
        if (env_fd < 0) return;

        var builder = new StringBuilder ();
        var buf = new uint8[4097];
        ssize_t bytes;
        while ((bytes = Posix.read (env_fd, buf, 4096)) > 0) {
            buf[bytes] = 0;
            builder.append ((string) buf);
        }
        Posix.close (env_fd);
        if (bytes < 0) {
            stdout.printf ("[lumoria-internal] env read failed: %s\n", Posix.strerror (Posix.errno));
        }

        foreach (var line in builder.str.split ("\n")) {
            if (line == "") continue;
            var eq = line.index_of ("=");
            if (eq <= 0) continue;
            var key = line.substring (0, eq);
            var value = line.substring (eq + 1);
            Environment.set_variable (key, value, true);
        }
    }
}
