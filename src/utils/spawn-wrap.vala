namespace Lumoria.Utils {

    public const int WRAP_ENV_FD = 3;

    [CCode (cname = "flock", cheader_filename = "sys/file.h")]
    private extern int sys_flock (int fd, int operation);

    private const int LOCK_EX = 2;
    private const int LOCK_NB = 4;

    /*
     * Starts lumoria wrap for argv with the environment delivered over a pipe on WRAP_ENV_FD.
     * The returned Subprocess reaps the child on its own; callers wait on it instead of the pid.
     */
    public Subprocess spawn_wrap (string log_path, string cwd, string env_payload, string[] argv) throws Error {
        var self_exe = current_executable_path ();
        if (self_exe == null || self_exe == "") {
            throw new IOError.FAILED ("could not resolve self executable path");
        }

        var wrapped = new Gee.ArrayList<string> ();
        wrapped.add (self_exe);
        wrapped.add ("wrap");
        wrapped.add ("--log");
        wrapped.add (log_path);
        wrapped.add ("--env-fd");
        wrapped.add (WRAP_ENV_FD.to_string ());
        if (cwd != "") {
            wrapped.add ("--cwd");
            wrapped.add (cwd);
        }
        wrapped.add ("--");
        foreach (var arg in argv) {
            if (arg != null) wrapped.add (arg);
        }

        var env_pipe = new int[2];
        Unix.open_pipe (env_pipe, Posix.FD_CLOEXEC);
        var writer = new UnixOutputStream (env_pipe[1], true);

        var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
        launcher.take_fd (env_pipe[0], WRAP_ENV_FD);
        if (cwd != "") launcher.set_cwd (cwd);
        var child = launcher.spawnv (strv (wrapped));
        writer.write_all (env_payload.data, null);
        writer.close ();
        return child;
    }

    public int acquire_exclusive_lock (string path, bool wait = false) throws Error {
        var fd = Posix.open (path, Posix.O_RDWR | Posix.O_CREAT, 0600);
        if (fd < 0) {
            throw new IOError.FAILED (
                "Failed to open lock %s: %s",
                path,
                Posix.strerror (Posix.errno)
            );
        }
        var flags = wait ? LOCK_EX : (LOCK_EX | LOCK_NB);
        if (sys_flock (fd, flags) != 0) {
            Posix.close (fd);
            throw new IOError.EXISTS ("already locked");
        }
        return fd;
    }

    public static string session_lock_path () {
        return Path.build_filename (data_dir (), "session", "manager.lock");
    }
}
