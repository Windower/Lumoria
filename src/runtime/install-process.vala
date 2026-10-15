namespace Lumoria.Runtime {
    [CCode (cname = "pidfd_open", cheader_filename = "sys/pidfd.h")]
    private extern int install_pidfd_open (Posix.pid_t pid, uint flags);
    [CCode (cname = "pidfd_send_signal", cheader_filename = "sys/pidfd.h")]
    private extern int install_pidfd_send_signal (int fd, int signal, void* info, uint flags);

    internal void wait_install_delay (int duration_ms, Cancellable? cancellable = null) throws Error {
        if (duration_ms < 0) throw new IOError.INVALID_ARGUMENT ("Negative sleep duration");
        var deadline = GLib.get_monotonic_time () + (int64) duration_ms * 1000;
        var mutex = Mutex ();
        var cond = Cond ();
        ulong handler = 0;
        if (cancellable != null) {
            handler = cancellable.connect (() => {
                mutex.lock ();
                cond.broadcast ();
                mutex.unlock ();
            });
        }
        mutex.lock ();
        while (cancellable == null || !cancellable.is_cancelled ()) {
            if (!cond.wait_until (mutex, deadline)) break;
        }
        mutex.unlock ();
        if (cancellable != null && handler != 0) cancellable.disconnect (handler);
        Utils.check_cancelled (cancellable);
    }

    private string[] read_proc_strings (string path) throws Error {
        uint8[] bytes;
        FileUtils.get_data (path, out bytes);
        var result = new Gee.ArrayList<string> ();
        var item = new StringBuilder ();
        foreach (var b in bytes) {
            if (b == 0) {
                result.add (item.str);
                item = new StringBuilder ();
            } else {
                item.append_c ((char) b);
            }
        }
        if (item.len > 0) result.add (item.str);
        while (result.size > 0 && result[result.size - 1] == "") result.remove_at (result.size - 1);
        return result.to_array ();
    }

    private bool same_prefix (string proc_dir, string prefix) throws Error {
        foreach (var entry in read_proc_strings (proc_dir + "/environ")) {
            if (!entry.has_prefix ("WINEPREFIX=")) continue;
            var path = entry.substring (11);
            if (!Path.is_absolute (path)) return false;
            var actual = Posix.realpath (proc_dir + "/root" + path);
            return actual != null && actual == prefix;
        }
        return false;
    }

    private bool pidfd_dead (int fd) {
        Posix.pollfd[] fds = { Posix.pollfd () };
        fds[0].fd = fd;
        fds[0].events = Posix.POLLIN;
        if (Posix.poll (fds, 0) <= 0) return false;
        return (fds[0].revents & (Posix.POLLIN | Posix.POLLHUP | Posix.POLLNVAL)) != 0;
    }

    internal int kill_wine_processes (
        string prefix_path, string command, string[] args,
        RuntimeLog logger, Cancellable? cancellable = null
    ) throws Error {
        if (command == "" || "/" in command || "\\" in command) {
            throw new IOError.INVALID_ARGUMENT ("winekill requires an executable basename");
        }
        var prefix = Posix.realpath (prefix_path);
        if (prefix_path == "" || prefix == null) throw new IOError.INVALID_ARGUMENT ("Cannot resolve winekill prefix");

        var needle = new StringBuilder (command);
        foreach (var arg in args) needle.append (" ").append (arg);

        var directory = Dir.open ("/proc");
        string? name;
        int matched = 0;
        while ((name = directory.read_name ()) != null) {
            Utils.check_cancelled (cancellable);
            int pid;
            if (!int.try_parse (name, out pid) || pid <= 0) continue;
            var proc_dir = "/proc/" + name;
            Posix.Stat st;
            if (Posix.stat (proc_dir, out st) != 0 || st.st_uid != Posix.getuid ()) continue;

            int fd = install_pidfd_open (pid, 0);
            if (fd < 0) continue;
            try {
                if (pidfd_dead (fd)) continue;
                bool matches;
                try {
                    var cmdline = string.joinv (" ", read_proc_strings (proc_dir + "/cmdline"));
                    matches = needle.str in cmdline && same_prefix (proc_dir, prefix);
                } catch (Error e) {
                    if (pidfd_dead (fd)) continue;
                    logger.typed (LogType.WARN, "winekill: cannot inspect PID %d: %s".printf (pid, e.message));
                    continue;
                }
                if (!matches || pidfd_dead (fd)) continue;
                Utils.check_cancelled (cancellable);
                if (install_pidfd_send_signal (fd, Posix.Signal.KILL, null, 0) != 0) continue;
                matched++;
                logger.typed (LogType.CMD, "winekill: SIGKILL PID %d (%s)".printf (pid, needle.str));
            } finally {
                Posix.close (fd);
            }
        }
        logger.typed (LogType.DONE, "winekill: %d matching process(es) stopped".printf (matched));
        return matched;
    }
}
