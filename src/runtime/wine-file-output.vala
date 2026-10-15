namespace Lumoria.Runtime {
    private class WineFileOutput {
        public int stdout_fd = -1;
        public int stderr_fd = -1;
        private Posix.off_t stdout_size;
        private Posix.off_t stderr_size;

        public WineFileOutput () throws Error {
            try {
                stdout_fd = open_output_file ();
                stderr_fd = open_output_file ();
            } catch (Error e) {
                close ();
                throw e;
            }
        }

        ~WineFileOutput () {
            close ();
        }

        private static int open_output_file () throws Error {
            string path;
            var fd = FileUtils.open_tmp ("lumoria-wine-output-XXXXXX", out path);
            if (Posix.unlink (path) != 0) {
                var message = Posix.strerror (Posix.errno).dup ();
                Posix.close (fd);
                throw new IOError.FAILED ("Cannot unlink command output file: %s", message);
            }
            if (Posix.fcntl (fd, Posix.F_SETFD, Posix.FD_CLOEXEC) < 0) {
                var message = Posix.strerror (Posix.errno).dup ();
                Posix.close (fd);
                throw new IOError.FAILED ("Cannot configure command output file: %s", message);
            }
            return fd;
        }

        public void close () {
            if (stdout_fd >= 0) {
                Posix.close (stdout_fd);
                stdout_fd = -1;
            }
            if (stderr_fd >= 0) {
                Posix.close (stderr_fd);
                stderr_fd = -1;
            }
        }

        public void snapshot (RuntimeLog logger) {
            stdout_size = snapshot_size (stdout_fd, logger);
            stderr_size = snapshot_size (stderr_fd, logger);
        }

        private static Posix.off_t snapshot_size (int fd, RuntimeLog logger) {
            Posix.Stat stat;
            if (Posix.fstat (fd, out stat) == 0) return stat.st_size;
            logger.typed (LogType.WARN, "Cannot inspect command output: %s".printf (Posix.strerror (Posix.errno)));
            return 0;
        }

        public void collect (
            StringBuilder stdout_output, StringBuilder stderr_output,
            RuntimeLog logger, int max_retained_bytes
        ) {
            try {
                collect_file (stdout_fd, stdout_size, stdout_output, "", logger, max_retained_bytes);
                collect_file (stderr_fd, stderr_size, stderr_output, STDERR_LOG_PREFIX, logger, max_retained_bytes);
            } finally {
                close ();
            }
        }

        private static void collect_file (
            int fd, Posix.off_t size, StringBuilder output, string prefix,
            RuntimeLog logger, int max_retained_bytes
        ) {
            var line = new StringBuilder ();
            uint8[] buffer = new uint8[8192];
            Posix.off_t offset = 0;
            while (offset < size) {
                var length = (size_t) int64.min (buffer.length, size - offset);
                var count = Posix.pread (fd, buffer, length, offset);
                if (count < 0) {
                    if (Posix.errno == Posix.EINTR) continue;
                    logger.typed (LogType.WARN, "Cannot read command output: %s".printf (Posix.strerror (Posix.errno)));
                    break;
                }
                if (count == 0) break;
                offset += count;
                for (ssize_t i = 0; i < count; i++) {
                    if (buffer[i] == '\n') {
                        collect_line (line, output, prefix, logger, max_retained_bytes);
                    } else {
                        line.append_c ((char) buffer[i]);
                    }
                }
            }
            if (line.len > 0) collect_line (line, output, prefix, logger, max_retained_bytes);
        }

        private static void collect_line (
            StringBuilder line, StringBuilder output, string prefix,
            RuntimeLog logger, int max_retained_bytes
        ) {
            var text = line.str.make_valid ().chomp ();
            append_retained_output (output, text + "\n", max_retained_bytes);
            if (text != "") logger.emit_line ("%s%s\n".printf (prefix, text));
            line.truncate (0);
        }
    }
}
