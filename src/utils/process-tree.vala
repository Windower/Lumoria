namespace Lumoria.Utils {

    public class ProcessTree : Object {
        private const int WAIT_POLL_MS = 100;

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

        public static Gee.ArrayList<int> monitored_descendants (int root_pid) {
            var descendants = new Gee.ArrayList<int> ();
            var seen = new Gee.HashSet<int> ();
            collect_descendants (root_pid, descendants, seen);

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

        public static bool has_monitored_descendants (int root_pid) {
            return monitored_descendants (root_pid).size > 0;
        }

        public static void signal_monitored_descendants (int root_pid, int signum) {
            foreach (var pid in monitored_descendants (root_pid)) {
                Posix.kill ((Posix.pid_t) pid, signum);
            }
        }

        public static bool wait_for_monitored_descendants (int root_pid, int timeout_ms) {
            var deadline = GLib.get_monotonic_time () + (int64) timeout_ms * 1000;
            while (GLib.get_monotonic_time () < deadline) {
                if (!has_monitored_descendants (root_pid)) return true;
                Thread.usleep ((uint) WAIT_POLL_MS * 1000);
            }
            return !has_monitored_descendants (root_pid);
        }

        public static bool terminate_descendants (
            int root_pid,
            int term_ms,
            int kill_ms,
            int kill_attempts = 1
        ) {
            signal_monitored_descendants (root_pid, Posix.Signal.TERM);
            if (wait_for_monitored_descendants (root_pid, term_ms)) return true;
            for (var i = 0; i < kill_attempts; i++) {
                signal_monitored_descendants (root_pid, Posix.Signal.KILL);
            }
            return wait_for_monitored_descendants (root_pid, kill_ms);
        }

        public static bool process_alive (int pid) {
            return Posix.kill ((Posix.pid_t) pid, 0) == 0;
        }

        public static string? process_comm (int pid) {
            string name;
            char state;
            if (!read_process_stat (pid, out name, out state)) return null;
            if (state == 'Z') return null;
            if (is_system_process (name)) return null;
            return name;
        }

        public static Gee.ArrayList<string> monitored_process_names (int root_pid) {
            var names = new Gee.ArrayList<string> ();
            var seen = new Gee.HashSet<string> ();
            foreach (var pid in monitored_descendants (root_pid)) {
                var comm = process_comm (pid);
                if (comm == null || seen.contains (comm)) continue;
                seen.add (comm);
                names.add (comm);
            }
            return names;
        }

        public static Gee.ArrayList<string> direct_child_process_names (int root_pid) {
            var names = new Gee.ArrayList<string> ();
            var seen = new Gee.HashSet<string> ();
            var seen_pids = new Gee.HashSet<int> ();
            try {
                var task_dir = Dir.open ("/proc/%d/task".printf (root_pid));
                string? tid;
                while ((tid = task_dir.read_name ()) != null) {
                    foreach (var child_pid in read_thread_children (root_pid, tid)) {
                        if (seen_pids.contains (child_pid)) continue;
                        seen_pids.add (child_pid);
                        var comm = process_comm (child_pid);
                        if (comm == null || seen.contains (comm)) continue;
                        seen.add (comm);
                        names.add (comm);
                    }
                }
            } catch (Error e) {
                debug ("Failed to walk /proc/%d/task: %s", root_pid, e.message);
            }
            return names;
        }

        private static void collect_descendants (
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
                debug ("Failed to walk /proc/%d/task: %s", parent_pid, e.message);
            }
        }

        private static Gee.ArrayList<int> read_thread_children (int pid, string tid) {
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

        private static bool read_process_stat (int pid, out string name, out char state) {
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

        private static bool is_system_process (string name) {
            var comm = truncate_comm (name);
            foreach (var process in SYSTEM_PROCESSES) {
                if (comm == truncate_comm (process)) return true;
            }
            return false;
        }

        private static string truncate_comm (string name) {
            return name.length > 15 ? name.substring (0, 15) : name;
        }
    }
}
