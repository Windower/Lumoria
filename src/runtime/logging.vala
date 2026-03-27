namespace Lumoria.Runtime {

    public delegate void RuntimeLogSink (string message);
    public enum LogType {
        WARN,
        ERROR,
        WINE,
        CACHED,
        DONE,
        SKIP,
        WINEEXEC,
        DEBUG,
        VERIFY,
        COPY,
        LINK,
        EXTRACT,
        CABEXTRACT,
        DLL_OVERRIDE,
        FONTS,
        MSPACK,
        ENV,
        CMD,
        CWD,
        STDERR,
        EXIT,
        PATCH,
        COMPONENT
    }

    public class RuntimeLog : Object {
        public string log_path { get; private set; default = ""; }
        private Utils.LoggingMode mode;
        private RuntimeLogSink? sink;
        private FileOutputStream? stream;

        public RuntimeLog (Utils.LoggingMode mode, string log_path = "", RuntimeLogSink? sink = null) {
            this.mode = mode;
            this.log_path = log_path;
            this.sink = sink;
        }

        public static RuntimeLog for_install (string prefix_path, RuntimeLogSink? sink = null) {
            var mode = Utils.LoggingMode.from_settings ();
            var log_path = "";
            if (mode == Utils.LoggingMode.KEEP) {
                var log_dir = Path.build_filename (prefix_path, "logs");
                Utils.ensure_dir (log_dir);
                var timestamp = new DateTime.now_utc ().format ("%Y%m%d-%H%M%S");
                log_path = Path.build_filename (log_dir, "install-%s.log".printf (timestamp));
            }
            return new RuntimeLog (mode, log_path, sink);
        }

        public static RuntimeLog for_run (string prefix_path, string session_id, RuntimeLogSink? sink = null) {
            var mode = Utils.LoggingMode.from_settings ();
            var log_path = "";
            if (mode == Utils.LoggingMode.KEEP) {
                var log_dir = Path.build_filename (prefix_path, "logs");
                Utils.ensure_dir (log_dir);
                var timestamp = new DateTime.now_local ().format ("%Y%m%d-%H%M%S");
                log_path = Path.build_filename (log_dir, "run-%s-%s.log".printf (timestamp, session_id));
            }
            return new RuntimeLog (mode, log_path, sink);
        }

        public bool is_disk_enabled () {
            return mode == Utils.LoggingMode.KEEP && log_path != "";
        }

        public LogFunc emitter () {
            return (msg) => {
                emit_line (msg);
            };
        }

        public static string tag_prefix (LogType tag) {
            return "[%s] ".printf (tag_name (tag));
        }

        public static string tagged_line (LogType tag, string message) {
            return "%s%s".printf (tag_prefix (tag), message);
        }

        public static void emit_typed (LogFunc emit, LogType tag, string message) {
            emit ("%s\n".printf (tagged_line (tag, message)));
        }

        public static LogFunc tagged_emitter (LogFunc emit, LogType tag) {
            return (msg) => {
                emit_prefixed_to (emit, tag_prefix (tag), msg);
            };
        }

        public void emit_line (string message) {
            if (sink != null) {
                sink (message);
            }
            if (log_path == "") return;
            ensure_stream ();
            if (stream != null) {
                try {
                    stream.write (message.data);
                } catch (Error e) {
                    warning ("Failed to write to log stream: %s", e.message);
                }
            }
        }

        public void close () {
            if (stream == null) return;
            try { stream.flush (); } catch (Error e) {
                warning ("Failed to flush log stream: %s", e.message);
            }
            try { stream.close (); } catch (Error e) {
                warning ("Failed to close log stream: %s", e.message);
            }
            stream = null;
        }

        public void banner (string title, bool leading_newline = true) {
            if (leading_newline) {
                emit_line ("\n=== %s ===\n".printf (title));
            } else {
                emit_line ("=== %s ===\n".printf (title));
            }
        }

        public void phase (string title) {
            banner ("Phase: %s".printf (title));
        }

        public void step (int step_idx, int total_steps, string description, string step_type) {
            banner ("Step %d/%d: %s [type=%s]".printf (
                step_idx, total_steps, description, step_type
            ));
        }

        public void warn (string message) {
            emit_line ("%s\n".printf (tagged_line (LogType.WARN, message)));
        }

        public void error (string message) {
            emit_line ("%s\n".printf (tagged_line (LogType.ERROR, message)));
        }

        public void overwrite_lines (Gee.ArrayList<string> lines) {
            if (!is_disk_enabled ()) return;
            try {
                var file = File.new_for_path (log_path).replace (null, false, FileCreateFlags.NONE);
                foreach (var line in lines) {
                    file.write ((line + "\n").data);
                }
                file.close ();
            } catch (Error e) {
                warning ("Could not write log file %s: %s", log_path, e.message);
            }
        }

        public void append_line (string line) {
            if (!is_disk_enabled ()) return;
            ensure_stream ();
            if (stream != null) {
                try {
                    stream.write ((line + "\n").data);
                } catch (Error e) {
                    warning ("Failed to append line to log file: %s", e.message);
                }
            }
        }

        private void ensure_stream () {
            if (stream != null || log_path == "") return;
            try {
                stream = File.new_for_path (log_path).append_to (FileCreateFlags.NONE);
            } catch (Error e) {
                warning ("Could not open log file %s: %s", log_path, e.message);
            }
        }

        private static void emit_prefixed_to (LogFunc emit, string prefix, string message) {
            var parts = message.split ("\n");
            for (int i = 0; i < parts.length; i++) {
                if (i == parts.length - 1 && parts[i] == "") continue;
                emit ("%s%s\n".printf (prefix, parts[i]));
            }
        }

        private static string tag_name (LogType tag) {
            switch (tag) {
                case LogType.WARN: return "warn";
                case LogType.ERROR: return "error";
                case LogType.WINE: return "wine";
                case LogType.CACHED: return "cached";
                case LogType.DONE: return "done";
                case LogType.SKIP: return "skip";
                case LogType.WINEEXEC: return "wineexec";
                case LogType.DEBUG: return "debug";
                case LogType.VERIFY: return "verify";
                case LogType.COPY: return "copy";
                case LogType.LINK: return "link";
                case LogType.EXTRACT: return "extract";
                case LogType.CABEXTRACT: return "cabextract";
                case LogType.DLL_OVERRIDE: return "dll_override";
                case LogType.FONTS: return "fonts";
                case LogType.MSPACK: return "mspack";
                case LogType.ENV: return "env";
                case LogType.CMD: return "cmd";
                case LogType.CWD: return "cwd";
                case LogType.STDERR: return "stderr";
                case LogType.EXIT: return "exit";
                case LogType.PATCH: return "patch";
                case LogType.COMPONENT: return "component";
                default: return "log";
            }
        }
    }
}
