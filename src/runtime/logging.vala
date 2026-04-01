namespace Lumoria.Runtime {

    public delegate void LogFunc (string message);

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
        private LogFunc? sink;
        private FileOutputStream? stream;

        public RuntimeLog (string log_path = "", owned LogFunc? sink = null) {
            this.log_path = log_path;
            this.sink = (owned) sink;
        }

        public static RuntimeLog for_install (string prefix_path, owned LogFunc? sink = null) {
            return new RuntimeLog (resolve_log_path (
                prefix_path,
                "install-%s.log".printf (new DateTime.now_local ().format ("%Y%m%d-%H%M%S"))
            ), (owned) sink);
        }

        public static RuntimeLog for_run (string prefix_path, string session_id, owned LogFunc? sink = null) {
            return new RuntimeLog (resolve_log_path (
                prefix_path,
                "run-%s-%s.log".printf (new DateTime.now_local ().format ("%Y%m%d-%H%M%S"), session_id)
            ), (owned) sink);
        }

        public bool is_disk_enabled () {
            return log_path != "";
        }

        private static string tagged_line (LogType tag, string message) {
            return "[%s] %s".printf (tag_name (tag), message);
        }

        public void typed (LogType tag, string message) {
            emit_line ("%s\n".printf (tagged_line (tag, message)));
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

        private void ensure_stream () {
            if (stream != null || log_path == "") return;
            try {
                var file = File.new_for_path (log_path);
                if (FileUtils.test (log_path, FileTest.EXISTS)) {
                    stream = file.append_to (FileCreateFlags.NONE);
                } else {
                    stream = file.create (FileCreateFlags.NONE);
                }
            } catch (Error e) {
                warning ("Could not open log file %s: %s", log_path, e.message);
            }
        }

        private static string resolve_log_path (string prefix_path, string filename) {
            if (Utils.LoggingMode.from_settings () != Utils.LoggingMode.KEEP) {
                return "";
            }
            var log_dir = Path.build_filename (prefix_path, "logs");
            Utils.ensure_dir (log_dir);
            return Path.build_filename (log_dir, filename);
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
