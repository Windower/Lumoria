namespace Lumoria.Cli {

    [CCode (cname = "prctl", cheader_filename = "sys/prctl.h")]
    private extern int prctl (int option, ulong arg2, ulong arg3 = 0, ulong arg4 = 0, ulong arg5 = 0);

    private const int PR_SET_CHILD_SUBREAPER = 36;

    public int cmd_wrap (string[] args) {
        string log_path = "";
        int cmd_start = -1;

        for (int i = 2; i < args.length; i++) {
            if (args[i] == "--log" && i + 1 < args.length) {
                log_path = args[++i];
            } else if (args[i] == "--") {
                cmd_start = i + 1;
                break;
            }
        }

        if (cmd_start < 0 || cmd_start >= args.length) {
            stderr.printf ("Usage: lumoria wrap --log <path> -- <command...>\n");
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
            Posix.execvp (cmd[0], cmd);
            stdout.printf ("[wrap] exec failed: %s\n", Posix.strerror (Posix.errno));
            Posix._exit (127);
        }

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
}
