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
    private const int WRAP_INHIBIT_RESOLVE_WAIT_MS = 2000;
    private const int WRAP_FERAL_GAME_MODE_WAIT_MS = 2000;

    private int wrap_signal_state = 0;
    private int wrap_signal_number = 0;
    private Thread<void>? log_relay_thread = null;
    private bool log_relay_done = false;

    private class WrapProcessIntegrations : Object {
        private Utils.FeralGameModePortal? feral_game_mode = null;
        private Gee.HashSet<int> feral_game_mode_seen_pids = new Gee.HashSet<int> ();

        public void start (Utils.Preferences.PowerSnapshot power) {
            if (!power.feral_game_mode) return;

            var candidate = new Utils.FeralGameModePortal ();
            string error;
            if (candidate.start (WRAP_FERAL_GAME_MODE_WAIT_MS, out error)) {
                feral_game_mode = candidate;
                wrap_log ("Feral GameMode active for wrapper pid=%d".printf ((int) Posix.getpid ()));
                poll ();
            } else {
                wrap_log ("Feral GameMode failed: %s".printf (error));
            }
        }

        public void poll () {
            if (feral_game_mode == null) return;

            foreach (var pid in Utils.ProcessTree.monitored_descendants ((int) Posix.getpid ())) {
                if (feral_game_mode_seen_pids.contains (pid)) continue;
                feral_game_mode_seen_pids.add (pid);

                var process_name = Utils.ProcessTree.process_comm (pid) ?? "unknown";
                string error;
                if (feral_game_mode.register_target (pid, WRAP_FERAL_GAME_MODE_WAIT_MS, out error)) {
                    wrap_log ("Feral GameMode registered pid=%d process=%s".printf (pid, process_name));
                } else {
                    wrap_log ("Feral GameMode target failed pid=%d process=%s: %s".printf (
                        pid, process_name, error
                    ));
                }
            }
        }

        public void shutdown () {
            if (feral_game_mode == null) return;

            string error;
            if (feral_game_mode.stop (WRAP_FERAL_GAME_MODE_WAIT_MS, out error)) {
                wrap_log ("Feral GameMode released");
            } else {
                wrap_log ("Feral GameMode release failed: %s".printf (error));
            }
        }
    }

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
            stderr.printf ("%s\n", _("Usage: lumoria wrap --log <path> [--env-fd <fd>] [--cwd <path>] -- <command...>"));
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
            wrap_log ("fork failed: %s".printf (Posix.strerror (Posix.errno)));
            return 1;
        }

        if (child_pid == 0) {
            apply_child_env (env_fd);
            if (child_pwd != "") {
                Environment.set_variable ("PWD", child_pwd, true);
            }
            Posix.execvp (cmd[0], cmd);
            var failure = "[lumoria-internal] exec failed: %s\n".printf (Posix.strerror (Posix.errno));
            Posix.write (Posix.STDOUT_FILENO, failure, failure.length);
            Posix._exit (127);
        }

        if (env_fd >= 0) Posix.close (env_fd);

        var power = Utils.Preferences.PowerSnapshot.load ();
        var inhibitor = new Utils.ScreenInhibitor ();
        if (power.screen_inhibitor) {
            string inhibit_error;
            if (inhibitor.start ("Running a Windows application", WRAP_INHIBIT_RESOLVE_WAIT_MS, out inhibit_error)) {
                wrap_log ("screensaver inhibit active");
            } else {
                wrap_log ("screensaver inhibit failed: %s".printf (inhibit_error));
            }
        }

        var process_integrations = new WrapProcessIntegrations ();
        process_integrations.start (power);

        var poll_ms = wrap_poll_interval_ms ();
        int initial_signal = 0;
        var initial_code = watcher_loop (
            child_pid,
            poll_ms,
            process_integrations,
            out initial_signal
        );
        cleanup_remaining_descendants ();
        process_integrations.shutdown ();
        if (inhibitor.stop ()) {
            wrap_log ("screensaver inhibit released");
        }

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
        var log_fd = Posix.open (target_path, flags | Posix.O_CLOEXEC, 0644);
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
        Posix.fcntl (relay_read, Posix.F_SETFD, Posix.FD_CLOEXEC);
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

    private void wrap_log (string message) {
        stdout.printf ("[wrap] %s\n", message);
        stdout.flush ();
    }

    private string apply_working_directory (string cwd) {
        if (cwd == "") return "";
        if (Posix.chdir (cwd) == 0) {
            wrap_log ("cwd=%s".printf (cwd));
            return Environment.get_current_dir ();
        }
        wrap_log ("cwd failed: %s: %s".printf (cwd, Posix.strerror (Posix.errno)));
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

    private int watcher_loop (
        int child_pid,
        int poll_ms,
        WrapProcessIntegrations process_integrations,
        out int initial_signal
    ) {
        int initial_code = -1;
        initial_signal = 0;
        bool initial_reaped = false;
        bool no_more_children = false;
        bool soft_signal_processed = false;
        bool hard_signal_processed = false;

        install_wrap_signal_handlers ();

        try {
            process_integrations.poll ();
            if (!Utils.ProcessTree.has_monitored_descendants ((int) Posix.getpid ())) {
                wrap_log ("waiting for monitored process to start");
                while (!Utils.ProcessTree.has_monitored_descendants ((int) Posix.getpid ())) {
                    process_integrations.poll ();
                    reap_children_nonblocking (
                        child_pid, ref initial_code, ref initial_signal, ref initial_reaped, out no_more_children
                    );
                    process_pending_wrap_signal (ref soft_signal_processed, ref hard_signal_processed);
                    if (no_more_children) return initial_code;
                    sleep_poll_interval (poll_ms);
                }
            }

            while (Utils.ProcessTree.has_monitored_descendants ((int) Posix.getpid ())) {
                process_integrations.poll ();
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

    private void signal_monitored_descendants (int signum) {
        Utils.ProcessTree.signal_monitored_descendants ((int) Posix.getpid (), signum);
    }

    private void cleanup_remaining_descendants () {
        Utils.ProcessTree.terminate_descendants (
            (int) Posix.getpid (), WRAP_CLEANUP_TERM_WAIT_MS, WRAP_CLEANUP_KILL_WAIT_MS, 3
        );
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
            wrap_log ("caught signal %d, terminating monitored processes".printf (wrap_signal_number));
            signal_monitored_descendants (Posix.Signal.TERM);
            soft_signal_processed = true;
        }
        if (wrap_signal_state >= 2 && !hard_signal_processed) {
            wrap_log ("caught second signal, killing monitored processes");
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
