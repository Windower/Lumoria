namespace Lumoria.Cli {

    private const int SESSION_IDLE_TIMEOUT_SECS = 30;
    private const int SESSION_WRAP_ENV_FD = 3;
    private const int SESSION_FD_SCAN_LIMIT = 1024;
    private const int STOP_DESCENDANT_WAIT_MS = 5000;
    private const int STOP_DESCENDANT_KILL_WAIT_MS = 1000;
    private const int STOP_WRAP_WAIT_MS = 500;

    public class SessionLaunchInfo : Object {
        public int pid { get; construct set; }
        public string prefix_id { get; construct set; }
        public string log_path { get; construct set; default = ""; }
        public string label { get; construct set; default = ""; }
        public string[] processes { get; construct set; default = {}; }

        public SessionLaunchInfo (
            int pid,
            string prefix_id,
            string log_path,
            string label,
            owned string[] processes
        ) {
            Object (
                pid: pid,
                prefix_id: prefix_id,
                log_path: log_path,
                label: label,
                processes: (owned) processes
            );
        }
    }

    private string[] session_launch_process_names (int wrap_pid) {
        var names = Utils.ProcessTree.monitored_process_names (wrap_pid);
        if (names.size == 0) {
            names = Utils.ProcessTree.direct_child_process_names (wrap_pid);
        }
        return session_process_names_to_array (names);
    }

    private string[] session_process_names_to_array (Gee.ArrayList<string> names) {
        var result = new string[names.size];
        for (var i = 0; i < names.size; i++) {
            result[i] = names[i];
        }
        return result;
    }

    private string session_format_process_label (string[] processes) {
        var label = new StringBuilder ();
        foreach (var process in processes) {
            if (process == null || process == "") continue;
            if (label.len > 0) label.append (", ");
            label.append (process);
        }
        return label.len > 0 ? label.str : "Starting…";
    }

    private SessionLaunchInfo session_launch_info_from_processes (int wrap_pid, string prefix_id, string log_path) {
        var processes = session_launch_process_names (wrap_pid);
        return new SessionLaunchInfo (
            wrap_pid,
            prefix_id,
            log_path,
            session_format_process_label (processes),
            processes
        );
    }

    public class SessionManagerService : Object {

        private class LaunchState {
            public int pid;
            public string prefix_id;
            public string wineserver_path;
            public string log_path;
            public string[] env;

            public LaunchState (int pid, string prefix_id, string wineserver_path, string log_path, string[] env) {
                this.pid = pid;
                this.prefix_id = prefix_id;
                this.wineserver_path = wineserver_path;
                this.log_path = log_path;
                this.env = env;
            }
        }

        private Gee.HashMap<int, LaunchState> launches;
        private MainLoop main_loop;
        private SocketService socket_service;
        private string socket_path;
        private uint idle_source_id = 0;
        private bool exit_when_empty = false;

        public SessionManagerService (MainLoop loop, string socket_path) {
            this.main_loop = loop;
            this.socket_path = socket_path;
            this.launches = new Gee.HashMap<int, LaunchState> ();
            this.socket_service = new SocketService ();
            schedule_idle_exit ();
        }

        public void start () throws Error {
            var socket_file = File.new_for_path (socket_path);
            var socket_dir = socket_file.get_parent ();
            if (socket_dir != null) {
                Utils.ensure_dir (socket_dir.get_path ());
            }

            var address = new UnixSocketAddress (socket_path);
            socket_service.add_address (
                address,
                SocketType.STREAM,
                SocketProtocol.DEFAULT,
                null,
                null
            );
            socket_service.incoming.connect ((connection) => {
                handle_connection.begin (connection);
                return true;
            });
            socket_service.start ();
            stderr.printf ("lumoria session-manager: socket ready at %s\n", socket_path);
            session_log ("socket ready at %s".printf (socket_path));
        }

        public void stop_service () {
            socket_service.stop ();
            FileUtils.unlink (socket_path);
        }

        public uint launch (
            string prefix_id,
            string wineserver_path,
            string log_path,
            string[] env,
            string cwd,
            string[] argv
        ) throws GLib.IOError {
            var self_exe = Utils.current_executable_path () ?? "lumoria";
            session_log ("launch request prefix=%s cwd=%s log=%s argv=%s".printf (
                prefix_id,
                cwd != "" ? cwd : "(default)",
                log_path != "" ? log_path : "(disabled)",
                string.joinv (" ", argv)
            ));

            var wrapped = new Gee.ArrayList<string> ();
            wrapped.add (self_exe);
            wrapped.add ("wrap");
            wrapped.add ("--log");
            wrapped.add (log_path);
            wrapped.add ("--env-fd");
            wrapped.add (SESSION_WRAP_ENV_FD.to_string ());
            if (cwd != "") {
                wrapped.add ("--cwd");
                wrapped.add (cwd);
            }
            wrapped.add ("--");
            foreach (var arg in argv) wrapped.add (arg);
            var wrapped_strv = Utils.arraylist_to_strv (wrapped);

            var env_payload = string.joinv ("\n", env);
            var env_pipe = new int[2];
            if (Posix.pipe (env_pipe) != 0) {
                throw new GLib.IOError.FAILED ("Failed to create environment pipe: %s",
                    Posix.strerror (Posix.errno));
            }

            var child_pid = Posix.fork ();
            if (child_pid < 0) {
                Posix.close (env_pipe[0]);
                Posix.close (env_pipe[1]);
                session_log ("launch fork failed prefix=%s error=%s".printf (
                    prefix_id,
                    Posix.strerror (Posix.errno)
                ));
                throw new GLib.IOError.FAILED ("Failed to fork: %s", Posix.strerror (Posix.errno));
            }

            if (child_pid == 0) {
                Posix.close (env_pipe[1]);
                if (env_pipe[0] != SESSION_WRAP_ENV_FD) {
                    Posix.dup2 (env_pipe[0], SESSION_WRAP_ENV_FD);
                    Posix.close (env_pipe[0]);
                }
                if (cwd != "") Posix.chdir (cwd);
                session_close_fds (SESSION_WRAP_ENV_FD);
                Posix.execvp (wrapped_strv[0], wrapped_strv);
                Posix._exit (127);
            }

            Posix.close (env_pipe[0]);
            try {
                session_write_all_fd (env_pipe[1], env_payload);
            } finally {
                Posix.close (env_pipe[1]);
            }

            cancel_idle_exit ();
            exit_when_empty = false;
            launches[child_pid] = new LaunchState (child_pid, prefix_id, wineserver_path, log_path, env);
            session_log ("spawned wrap pid=%d prefix=%s".printf (child_pid, prefix_id));

            var pid_copy = child_pid;
            ChildWatch.add ((Pid) child_pid, (pid, status) => {
                Process.close_pid (pid);
                on_wrap_exited (pid_copy, status);
            });

            return (uint) child_pid;
        }

        public void stop_pid (int wrap_pid) {
            if (!launches.has_key (wrap_pid)) return;
            stop_wrap_tree (launches.get (wrap_pid));
        }

        public void stop (string prefix_id) {
            var states = new Gee.ArrayList<LaunchState> ();
            foreach (var state in launches.values) {
                if (state.prefix_id == prefix_id) states.add (state);
            }
            foreach (var state in states) stop_wrap_tree (state);
        }

        public void stop_all () {
            var states = new Gee.ArrayList<LaunchState> ();
            foreach (var state in launches.values) states.add (state);
            exit_when_empty = true;
            foreach (var state in states) stop_wrap_tree (state);
            quit_if_empty ();
        }

        public Gee.ArrayList<SessionLaunchInfo> list_launches () {
            var result = new Gee.ArrayList<SessionLaunchInfo> ();
            foreach (var entry in launches.entries) {
                result.add (launch_info_for_state (entry.key, entry.value));
            }
            return result;
        }

        private SessionLaunchInfo launch_info_for_state (int wrap_pid, LaunchState state) {
            return session_launch_info_from_processes (wrap_pid, state.prefix_id, state.log_path);
        }

        private void stop_wrap_tree (LaunchState state) {
            Utils.ProcessTree.signal_monitored_descendants (state.pid, Posix.Signal.TERM);
            if (!Utils.ProcessTree.wait_for_monitored_descendants (state.pid, STOP_DESCENDANT_WAIT_MS)) {
                for (var i = 0; i < 3; i++) {
                    Utils.ProcessTree.signal_monitored_descendants (state.pid, Posix.Signal.KILL);
                }
                Utils.ProcessTree.wait_for_monitored_descendants (state.pid, STOP_DESCENDANT_KILL_WAIT_MS);
            }

            if (Utils.ProcessTree.process_alive (state.pid)) {
                Posix.kill ((Posix.pid_t) state.pid, Posix.Signal.TERM);
                var deadline = GLib.get_monotonic_time () + (int64) STOP_WRAP_WAIT_MS * 1000;
                while (GLib.get_monotonic_time () < deadline
                    && Utils.ProcessTree.process_alive (state.pid)) {
                    Thread.usleep (100000);
                }
            }

            if (Utils.ProcessTree.process_alive (state.pid)
                && !Utils.ProcessTree.has_monitored_descendants (state.pid)) {
                Posix.kill ((Posix.pid_t) state.pid, Posix.Signal.KILL);
            }
        }

        private void on_wrap_exited (int pid, int status) {
            session_log ("wrap exited pid=%d status=%d".printf (pid, status));
            launches.unset (pid);
            if (quit_if_empty ()) return;
            if (launches.size == 0) {
                schedule_idle_exit ();
            }
        }

        private bool quit_if_empty () {
            if (!exit_when_empty || launches.size != 0) return false;
            main_loop.quit ();
            return true;
        }

        private void schedule_idle_exit () {
            if (idle_source_id != 0) return;
            idle_source_id = Timeout.add_seconds (SESSION_IDLE_TIMEOUT_SECS, () => {
                idle_source_id = 0;
                if (launches.size == 0) main_loop.quit ();
                return Source.REMOVE;
            });
        }

        private void cancel_idle_exit () {
            if (idle_source_id != 0) {
                Source.remove (idle_source_id);
                idle_source_id = 0;
            }
        }

        private async void handle_connection (SocketConnection connection) {
            try {
                var input = new DataInputStream (connection.input_stream);
                var output = new DataOutputStream (connection.output_stream);
                string? line = input.read_line (null);
                if (line == null || line.strip () == "") {
                    write_response (output, false, "empty request");
                    return;
                }
                var response = handle_request (line);
                output.put_string (response + "\n");
                output.flush ();
            } catch (Error e) {
                warning ("Session request failed: %s", e.message);
            }
        }

        private string handle_request (string request) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (request);
                var obj = parser.get_root ().get_object ();
                var method = obj.get_string_member ("method");

                switch (method) {
                    case "ping":
                        return ok_response ();
                    case "launch":
                        return launch_response (obj);
                    case "list":
                        return list_response ();
                    case "stop_pid":
                        stop_pid ((int) obj.get_int_member ("pid"));
                        return ok_response ();
                    case "stop":
                        stop (obj.get_string_member ("prefix_id"));
                        return ok_response ();
                    case "stop_all":
                        stop_all ();
                        return ok_response ();
                    default:
                        return error_response ("unknown method: %s".printf (method));
                }
            } catch (Error e) {
                return error_response (e.message);
            }
        }

        private string launch_response (Json.Object obj) throws Error {
            var prefix_id = obj.get_string_member ("prefix_id");
            var pid = launch (
                prefix_id,
                obj.get_string_member ("wineserver"),
                obj.get_string_member ("log_path"),
                json_array_to_strv (obj.get_array_member ("env")),
                obj.get_string_member ("cwd"),
                json_array_to_strv (obj.get_array_member ("argv"))
            );

            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("ok");
            builder.add_boolean_value (true);
            builder.set_member_name ("pid");
            builder.add_int_value ((int64) pid);
            builder.end_object ();
            return json_builder_to_string (builder);
        }

        private string list_response () {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("ok");
            builder.add_boolean_value (true);
            builder.set_member_name ("launches");
            builder.begin_array ();
            foreach (var info in list_launches ()) {
                builder.begin_object ();
                builder.set_member_name ("pid");
                builder.add_int_value (info.pid);
                builder.set_member_name ("prefix_id");
                builder.add_string_value (info.prefix_id);
                builder.set_member_name ("log_path");
                builder.add_string_value (info.log_path);
                builder.set_member_name ("processes");
                builder.begin_array ();
                foreach (var process in info.processes) {
                    if (process == null || process == "") continue;
                    builder.add_string_value (process);
                }
                builder.end_array ();
                builder.end_object ();
            }
            builder.end_array ();
            builder.end_object ();
            return json_builder_to_string (builder);
        }
    }

    private void session_close_fds (int keep_fd) {
        for (int fd = 3; fd < SESSION_FD_SCAN_LIMIT; fd++) {
            if (fd != keep_fd) Posix.close (fd);
        }
    }

    private void session_write_all_fd (int fd, string payload) throws IOError {
        uint8[] bytes = payload.data;
        size_t offset = 0;
        while (offset < bytes.length) {
            var written = Posix.write (fd, (uint8[]) bytes[offset:bytes.length], bytes.length - offset);
            if (written < 0) {
                throw new IOError.FAILED ("Environment pipe write failed: %s",
                    Posix.strerror (Posix.errno));
            }
            if (written == 0)
                throw new IOError.FAILED ("Environment pipe write: zero bytes written");
            offset += (size_t) written;
        }
    }

    private int run_session_service () {
        session_redirect_stdio_to_log ();
        var loop = new MainLoop ();
        var service = new SessionManagerService (loop, session_socket_path ());
        try {
            service.start ();
        } catch (Error e) {
            stderr.printf ("lumoria session-manager: failed to start: %s\n", e.message);
            return 1;
        }

        loop.run ();
        service.stop_service ();
        return 0;
    }

    private void session_redirect_stdio_to_log () {
        if (Utils.LoggingMode.from_settings () != Utils.LoggingMode.KEEP) return;

        var log_dir = Utils.session_manager_log_dir ();
        Utils.ensure_dir (log_dir);
        var log_path = Utils.session_manager_log_path ();
        var log_fd = Posix.open (log_path, Posix.O_WRONLY | Posix.O_CREAT | Posix.O_APPEND, 0644);
        if (log_fd < 0) {
            stderr.printf ("lumoria session-manager: could not open log %s: %s\n",
                log_path, Posix.strerror (Posix.errno));
            return;
        }

        Posix.dup2 (log_fd, Posix.STDOUT_FILENO);
        Posix.dup2 (log_fd, Posix.STDERR_FILENO);
        Posix.close (log_fd);
        stderr.printf ("\n[%s] lumoria session-manager starting\n",
            new DateTime.now_local ().format ("%F %T"));
        stderr.flush ();
    }

    private void session_log (string message) {
        stderr.printf ("[%s] %s\n", new DateTime.now_local ().format ("%F %T"), message);
        stderr.flush ();
    }

    public int cmd_session_manager (string[] args) {
        if (args.length >= 3) {
            switch (args[2]) {
                case "stop-all":
                    return session_client_stop_all ();
                case "stop-pid":
                    if (args.length < 4) {
                        stderr.printf ("Usage: lumoria session-manager stop-pid <wrap-pid>\n");
                        return 1;
                    }
                    return session_client_stop_pid (int.parse (args[3]));
                case "stop":
                    if (args.length < 4) {
                        stderr.printf ("Usage: lumoria session-manager stop <prefix-id>\n");
                        return 1;
                    }
                    return session_client_stop_prefix (args[3]);
            }
        }
        return run_session_service ();
    }

    public bool session_ping () {
        try {
            var obj = new Json.Object ();
            obj.set_string_member ("method", "ping");
            return response_ok (session_send_request (json_object_to_string (obj)));
        } catch (Error e) {
            return false;
        }
    }

    public Gee.ArrayList<SessionLaunchInfo> session_list_launches () throws Error {
        var obj = new Json.Object ();
        obj.set_string_member ("method", "list");
        var response = session_send_request (json_object_to_string (obj));
        if (!response_ok (response))
            throw new IOError.FAILED ("%s", response_error (response));

        var parser = new Json.Parser ();
        parser.load_from_data (response);
        var root = parser.get_root ().get_object ();
        var launches = new Gee.ArrayList<SessionLaunchInfo> ();
        var array = root.get_array_member ("launches");
        for (uint i = 0; i < array.get_length (); i++) {
            var entry = array.get_object_element (i);
            if (!entry.has_member ("processes")) {
                throw new IOError.FAILED ("session manager returned launch data without process labels");
            }

            var processes = new Gee.ArrayList<string> ();
            var process_array = entry.get_array_member ("processes");
            for (uint j = 0; j < process_array.get_length (); j++) {
                processes.add (process_array.get_string_element (j));
            }
            var process_names = session_process_names_to_array (processes);

            launches.add (new SessionLaunchInfo (
                (int) entry.get_int_member ("pid"),
                entry.get_string_member ("prefix_id"),
                entry.has_member ("log_path") ? entry.get_string_member ("log_path") : "",
                session_format_process_label (process_names),
                process_names
            ));
        }
        return launches;
    }

    public void session_stop_pid (int wrap_pid) throws Error {
        var obj = new Json.Object ();
        obj.set_string_member ("method", "stop_pid");
        obj.set_int_member ("pid", wrap_pid);
        var response = session_send_request (json_object_to_string (obj));
        if (!response_ok (response))
            throw new IOError.FAILED ("%s", response_error (response));
    }

    public void session_stop_prefix (string prefix_id) throws Error {
        var obj = new Json.Object ();
        obj.set_string_member ("method", "stop");
        obj.set_string_member ("prefix_id", prefix_id);
        var response = session_send_request (json_object_to_string (obj));
        if (!response_ok (response))
            throw new IOError.FAILED ("%s", response_error (response));
    }

    public void session_stop_all () throws Error {
        var obj = new Json.Object ();
        obj.set_string_member ("method", "stop_all");
        var response = session_send_request (json_object_to_string (obj));
        if (!response_ok (response))
            throw new IOError.FAILED ("%s", response_error (response));
    }

    private int session_client_stop_all () {
        try {
            session_stop_all ();
            return 0;
        } catch (Error e) {
            stderr.printf ("Failed to connect to session manager: %s\n", e.message);
            return 1;
        }
    }

    private int session_client_stop_pid (int wrap_pid) {
        try {
            session_stop_pid (wrap_pid);
            return 0;
        } catch (Error e) {
            stderr.printf ("Failed to connect to session manager: %s\n", e.message);
            return 1;
        }
    }

    private int session_client_stop_prefix (string prefix_id) {
        try {
            session_stop_prefix (prefix_id);
            return 0;
        } catch (Error e) {
            stderr.printf ("Failed to connect to session manager: %s\n", e.message);
            return 1;
        }
    }

    public string session_socket_path () {
        return Path.build_filename (Utils.data_dir (), "session", "manager.sock");
    }

    public string session_send_request (string request) throws Error {
        var client = new SocketClient ();
        var address = new UnixSocketAddress (session_socket_path ());
        var connection = client.connect (address);
        var output = new DataOutputStream (connection.output_stream);
        var input = new DataInputStream (connection.input_stream);
        output.put_string (request + "\n");
        output.flush ();
        var response = input.read_line (null);
        if (response == null || response == "")
            throw new IOError.FAILED ("empty session response");
        return response;
    }

    public bool response_ok (string response) {
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (response);
            return parser.get_root ().get_object ().get_boolean_member ("ok");
        } catch (Error e) {
            return false;
        }
    }

    public string response_error (string response) {
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (response);
            var obj = parser.get_root ().get_object ();
            if (obj.has_member ("error")) return obj.get_string_member ("error");
        } catch (Error e) {
        }
        return "session request failed";
    }

    private void write_response (DataOutputStream output, bool ok, string error = "") throws Error {
        output.put_string (ok ? ok_response () + "\n" : error_response (error) + "\n");
        output.flush ();
    }

    private string ok_response () {
        var obj = new Json.Object ();
        obj.set_boolean_member ("ok", true);
        return json_object_to_string (obj);
    }

    private string error_response (string error) {
        var obj = new Json.Object ();
        obj.set_boolean_member ("ok", false);
        obj.set_string_member ("error", error);
        return json_object_to_string (obj);
    }

    private string[] json_array_to_strv (Json.Array array) {
        var values = new Gee.ArrayList<string> ();
        for (uint i = 0; i < array.get_length (); i++) {
            values.add (array.get_string_element (i));
        }
        return Utils.arraylist_to_strv (values);
    }

    private string json_object_to_string (Json.Object obj) {
        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (obj);
        var generator = new Json.Generator ();
        generator.root = node;
        return generator.to_data (null);
    }

    private string json_builder_to_string (Json.Builder builder) {
        var generator = new Json.Generator ();
        generator.root = builder.get_root ();
        return generator.to_data (null);
    }
}
