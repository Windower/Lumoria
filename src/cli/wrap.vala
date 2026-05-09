namespace Lumoria.Cli {

    [CCode (cname = "prctl", cheader_filename = "sys/prctl.h")]
    private extern int prctl (int option, ulong arg2, ulong arg3 = 0, ulong arg4 = 0, ulong arg5 = 0);

    private const int PR_SET_CHILD_SUBREAPER = 36;

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

        int log_fd = -1;
        if (log_path != "") {
            log_fd = Posix.open (log_path,
                Posix.O_WRONLY | Posix.O_CREAT | Posix.O_APPEND, 0644);
            if (log_fd >= 0) {
                Posix.dup2 (log_fd, Posix.STDOUT_FILENO);
                Posix.dup2 (log_fd, Posix.STDERR_FILENO);
                Posix.close (log_fd);
            } else {
                stderr.printf ("warn: could not open log %s, inheriting caller fds\n", log_path);
            }
        }

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

        if (log_path != "") {
            stdout.printf ("\n[exit] code=%d\n", initial_code);
        }

        return initial_code >= 0 ? initial_code : 1;
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
