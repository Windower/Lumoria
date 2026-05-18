namespace Lumoria.Cli {

    [CCode (cname = "prctl", cheader_filename = "sys/prctl.h")]
    private extern int prctl (int option, ulong arg2, ulong arg3 = 0, ulong arg4 = 0, ulong arg5 = 0);

    private const int PR_SET_CHILD_SUBREAPER = 36;
    private const int DEFAULT_WRAP_POLL_MS = 100;
    private const int MIN_WRAP_POLL_MS = 10;
    private const int MAX_WRAP_POLL_MS = 5000;
    private const string WRAP_MODE_LEGACY = "legacy";
    private const string[] SYSTEM_PROCESSES = {
        "wineserver",
        "services.exe",
        "winedevice.exe",
        "plugplay.exe",
        "explorer.exe",
        "wineconsole",
        "svchost.exe",
        "rpcss.exe",
        "rundll32.exe",
        "mscorsvw.exe",
        "iexplore.exe",
        "winedbg.exe",
        "tabtip.exe",
        "conhost.exe"
    };

    private int wrap_signal_state = 0;
    private int wrap_signal_number = 0;

    public int cmd_wrap (string[] args) {
        string log_path = "";
        int env_fd = -1;
        int cmd_start = -1;

        for (int i = 2; i < args.length; i++) {
            if (args[i] == "--log" && i + 1 < args.length) {
                log_path = args[++i];
            } else if (args[i] == "--env-fd" && i + 1 < args.length) {
                env_fd = int.parse (args[++i]);
            } else if (args[i] == "--") {
                cmd_start = i + 1;
                break;
            }
        }

        if (cmd_start < 0 || cmd_start >= args.length) {
            stderr.printf ("Usage: lumoria wrap --log <path> [--env-fd <fd>] -- <command...>\n");
            return 1;
        }

        if (prctl (PR_SET_CHILD_SUBREAPER, 1) != 0) {
            stderr.printf ("warn: PR_SET_CHILD_SUBREAPER failed (errno %d), continuing without subreaper\n",
                Posix.errno);
        }

        redirect_stdio (log_path);

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
            Posix.execvp (cmd[0], cmd);
            stdout.printf ("[lumoria-internal] exec failed: %s\n", Posix.strerror (Posix.errno));
            Posix._exit (127);
        }

        if (env_fd >= 0) Posix.close (env_fd);

        var mode = Environment.get_variable ("LUMORIA_WRAP_MODE") ?? "";
        var poll_ms = wrap_poll_interval_ms ();
        var initial_code = mode == WRAP_MODE_LEGACY
            ? legacy_loop (child_pid)
            : watcher_loop (child_pid, poll_ms);

        if (log_path != "") {
            stdout.printf ("\n[exit] code=%d\n", initial_code);
        }

        return initial_code >= 0 ? initial_code : 1;
    }

    private void redirect_stdio (string log_path) {
        var target_path = log_path != "" ? log_path : "/dev/null";
        var flags = log_path != ""
            ? Posix.O_WRONLY | Posix.O_CREAT | Posix.O_APPEND
            : Posix.O_WRONLY;
        var fd = Posix.open (target_path, flags, 0644);
        if (fd < 0) {
            if (log_path != "") {
                stderr.printf ("warn: could not open log %s, inheriting caller fds\n", log_path);
            }
            return;
        }
        Posix.dup2 (fd, Posix.STDOUT_FILENO);
        Posix.dup2 (fd, Posix.STDERR_FILENO);
        Posix.close (fd);
    }

    private int legacy_loop (int child_pid) {
        int initial_code = -1;
        bool initial_reaped = false;

        while (true) {
            int status;
            var pid = Posix.waitpid (-1, out status, 0);
            if (pid < 0) break;
            if (pid == child_pid && !initial_reaped) {
                initial_reaped = true;
                initial_code = Process.if_exited (status)
                    ? Process.exit_status (status)
                    : -1;
            }
        }

        return initial_code;
    }

    private int watcher_loop (int child_pid, int poll_ms) {
        int initial_code = -1;
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
                        child_pid, ref initial_code, ref initial_reaped, out no_more_children
                    );
                    process_pending_wrap_signal (ref soft_signal_processed, ref hard_signal_processed);
                    if (no_more_children) return initial_code;
                    sleep_poll_interval (poll_ms);
                }
            }

            while (has_monitored_descendants ()) {
                reap_children_nonblocking (
                    child_pid, ref initial_code, ref initial_reaped, out no_more_children
                );
                process_pending_wrap_signal (ref soft_signal_processed, ref hard_signal_processed);
                if (no_more_children) return initial_code;
                sleep_poll_interval (poll_ms);
            }

            reap_children_nonblocking (
                child_pid, ref initial_code, ref initial_reaped, out no_more_children
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
                initial_code = Process.if_exited (status)
                    ? Process.exit_status (status)
                    : -1;
            }
        }
    }

    private bool has_monitored_descendants () {
        return monitored_descendants ().size > 0;
    }

    private Gee.ArrayList<int> monitored_descendants () {
        var descendants = new Gee.ArrayList<int> ();
        var seen = new Gee.HashSet<int> ();
        collect_descendants ((int) Posix.getpid (), descendants, seen);

        var monitored = new Gee.ArrayList<int> ();
        foreach (var pid in descendants) {
            string name;
            char state;
            if (!read_process_stat (pid, out name, out state)) continue;
            if (state == 'Z') continue;
            if (is_system_process (name)) continue;
            monitored.add (pid);
        }
        return monitored;
    }

    private void collect_descendants (
        int parent_pid,
        Gee.ArrayList<int> descendants,
        Gee.HashSet<int> seen
    ) {
        try {
            var task_dir = Dir.open ("/proc/%d/task".printf (parent_pid));
            string? tid;
            while ((tid = task_dir.read_name ()) != null) {
                foreach (var child_pid in read_thread_children (parent_pid, tid)) {
                    if (seen.contains (child_pid)) continue;
                    seen.add (child_pid);
                    descendants.add (child_pid);
                    collect_descendants (child_pid, descendants, seen);
                }
            }
        } catch (Error e) {
        }
    }

    private Gee.ArrayList<int> read_thread_children (int pid, string tid) {
        var children = new Gee.ArrayList<int> ();
        string content;
        try {
            FileUtils.get_contents ("/proc/%d/task/%s/children".printf (pid, tid), out content);
        } catch (Error e) {
            return children;
        }

        foreach (var token in content.strip ().split (" ")) {
            if (token == "") continue;
            int64 parsed;
            if (!int64.try_parse (token, out parsed) || parsed <= 0 || parsed > int.MAX) continue;
            children.add ((int) parsed);
        }
        return children;
    }

    private bool read_process_stat (int pid, out string name, out char state) {
        name = "";
        state = '\0';

        string stat;
        try {
            FileUtils.get_contents ("/proc/%d/stat".printf (pid), out stat);
        } catch (Error e) {
            return false;
        }

        var open = stat.index_of_char ('(');
        var close = stat.last_index_of_char (')');
        if (open < 0 || close <= open || close + 2 >= stat.length) return false;

        name = stat.substring (open + 1, close - open - 1);
        state = stat[close + 2];
        return true;
    }

    private bool is_system_process (string name) {
        var comm = truncate_comm (name);
        foreach (var process in SYSTEM_PROCESSES) {
            if (comm == truncate_comm (process)) return true;
        }
        return false;
    }

    private string truncate_comm (string name) {
        return name.length > 15 ? name.substring (0, 15) : name;
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

    private void signal_monitored_descendants (int signum) {
        foreach (var pid in monitored_descendants ()) {
            Posix.kill ((Posix.pid_t) pid, signum);
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
