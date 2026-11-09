namespace Lumoria.Cli {

    private const int SESSION_IDLE_TIMEOUT_SECS = 30;
    private const uint STOP_TERM_GRACE_SECS = 5;
    private const uint STOP_KILL_GRACE_SECS = 3;
    private const int STOP_WAIT_TIMEOUT_MS = 15000;
    private const int STOP_WAIT_POLL_MS = 200;

    public class SessionLaunchInfo : Object {
        public int pid { get; construct set; }
        public string prefix_id { get; construct set; }
        public string log_path { get; construct set; default = ""; }
        public string label { get; construct set; default = ""; }
        public string[] processes { get; construct set; default = {}; }
        public bool stopping { get; construct set; default = false; }

        public SessionLaunchInfo (
            int pid,
            string prefix_id,
            string log_path,
            string label,
            owned string[] processes,
            bool stopping
        ) {
            Object (
                pid: pid,
                prefix_id: prefix_id,
                log_path: log_path,
                label: label,
                processes: (owned) processes,
                stopping: stopping
            );
        }
    }

    private string[] session_launch_process_names (int wrap_pid) {
        var names = Utils.ProcessTree.monitored_process_names (wrap_pid);
        if (names.size == 0) {
            names = Utils.ProcessTree.direct_child_process_names (wrap_pid);
        }
        return Utils.strv (names);
    }

    private string session_format_process_label (string[] processes) {
        var label = new StringBuilder ();
        foreach (var process in processes) {
            if (process == null || process == "") continue;
            if (label.len > 0) label.append (", ");
            label.append (process);
        }
        return label.len > 0 ? label.str : _("Starting...");
    }

    private SessionLaunchInfo session_launch_info_from_processes (
        int wrap_pid,
        string prefix_id,
        string log_path,
        bool stopping
    ) {
        var processes = session_launch_process_names (wrap_pid);
        return new SessionLaunchInfo (
            wrap_pid,
            prefix_id,
            log_path,
            session_format_process_label (processes),
            processes,
            stopping
        );
    }

    public class SessionManagerService : Object {

        private class LaunchState {
            public int pid;
            public string prefix_id;
            public string log_path;
            public bool stopping = false;
            public bool forced = false;
            public uint stop_timer_id = 0;

            public LaunchState (int pid, string prefix_id, string log_path) {
                this.pid = pid;
                this.prefix_id = prefix_id;
                this.log_path = log_path;
            }
        }

        private Gee.HashMap<int, LaunchState> launches;
        private MainLoop main_loop;
        private SocketService socket_service;
        private string socket_path;
        private string token_path;
        private string token = "";
        private uint idle_source_id = 0;
        private bool exit_when_empty = false;
        private int lock_fd = -1;

        public SessionManagerService (MainLoop loop, string socket_path) {
            this.main_loop = loop;
            this.socket_path = socket_path;
            this.token_path = session_token_path ();
            this.launches = new Gee.HashMap<int, LaunchState> ();
            this.socket_service = new SocketService ();
            schedule_idle_exit ();
        }

        public void start () throws Error {
            var socket_dir = Path.get_dirname (socket_path);
            Utils.ensure_private_dir (socket_dir);
            try {
                lock_fd = Utils.acquire_exclusive_lock (Utils.session_lock_path ());
            } catch (IOError.EXISTS e) {
                if (session_ping ()) {
                    throw new IOError.EXISTS ("session manager already running");
                }
                throw new IOError.FAILED ("session manager lock is held but the existing manager could not be reached");
            }
            FileUtils.unlink (socket_path);

            token = session_mint_token ();
            Utils.write_text_atomic (token_path, token + "\n", 0600);

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
            if (FileUtils.chmod (socket_path, 0600) != 0) {
                throw new IOError.FAILED (
                    "Failed to restrict session socket: %s",
                    Posix.strerror (Posix.errno)
                );
            }
            stderr.printf ("lumoria session-manager: socket ready at %s\n", socket_path);
            session_log ("socket ready at %s".printf (socket_path));
        }

        public void stop_service () {
            socket_service.stop ();
            FileUtils.unlink (socket_path);
            FileUtils.unlink (token_path);
            if (lock_fd >= 0) {
                Posix.close (lock_fd);
                lock_fd = -1;
            }
        }

        public uint launch (
            string prefix_id,
            string log_path,
            string[] env,
            string cwd,
            string[] argv
        ) throws GLib.IOError {
            session_log ("launch request prefix=%s cwd=%s log=%s argv=%s".printf (
                prefix_id,
                cwd != "" ? cwd : "(default)",
                log_path != "" ? log_path : "(disabled)",
                string.joinv (" ", argv)
            ));

            Subprocess child;
            try {
                child = Utils.spawn_wrap (log_path, cwd, string.joinv ("\n", env), argv);
            } catch (Error e) {
                session_log ("launch fork failed prefix=%s error=%s".printf (prefix_id, e.message));
                throw new GLib.IOError.FAILED ("%s", e.message);
            }
            var child_pid = int.parse (child.get_identifier ());

            cancel_idle_exit ();
            exit_when_empty = false;
            launches[child_pid] = new LaunchState (child_pid, prefix_id, log_path);
            session_log ("spawned wrap pid=%d prefix=%s".printf (child_pid, prefix_id));

            child.wait_async.begin (null, (obj, res) => {
                try {
                    child.wait_async.end (res);
                } catch (Error e) {
                    session_log ("wait failed pid=%d error=%s".printf (child_pid, e.message));
                }
                on_wrap_exited (child_pid, child.get_status ());
            });

            return (uint) child_pid;
        }

        public bool stop_pid (int wrap_pid) {
            return begin_stops (pid_states (wrap_pid));
        }

        public bool stop (string prefix_id) {
            return begin_stops (prefix_states (prefix_id));
        }

        public bool stop_all () {
            exit_when_empty = true;
            var stopping = begin_stops (all_states ());
            quit_if_empty ();
            return stopping;
        }

        public void force_pid (int wrap_pid) throws IOError {
            force_stops (pid_states (wrap_pid));
        }

        public void force (string prefix_id) throws IOError {
            force_stops (prefix_states (prefix_id));
        }

        public void force_all () throws IOError {
            force_stops (all_states ());
        }

        public Gee.ArrayList<SessionLaunchInfo> list_launches () {
            var result = new Gee.ArrayList<SessionLaunchInfo> ();
            foreach (var entry in launches.entries) {
                result.add (session_launch_info_from_processes (
                    entry.key, entry.value.prefix_id, entry.value.log_path, entry.value.stopping
                ));
            }
            return result;
        }

        private Gee.ArrayList<LaunchState> pid_states (int wrap_pid) {
            var states = new Gee.ArrayList<LaunchState> ();
            if (launches.has_key (wrap_pid)) states.add (launches.get (wrap_pid));
            return states;
        }

        private Gee.ArrayList<LaunchState> prefix_states (string prefix_id) {
            var states = new Gee.ArrayList<LaunchState> ();
            foreach (var state in launches.values) {
                if (state.prefix_id == prefix_id) states.add (state);
            }
            return states;
        }

        private Gee.ArrayList<LaunchState> all_states () {
            var states = new Gee.ArrayList<LaunchState> ();
            states.add_all (launches.values);
            return states;
        }

        private bool begin_stops (Gee.ArrayList<LaunchState> states) {
            foreach (var state in states) begin_stop (state);
            return states.size > 0;
        }

        private void force_stops (Gee.ArrayList<LaunchState> states) throws IOError {
            var forced = false;
            foreach (var state in states) {
                if (!state.stopping) continue;
                escalate_stop (state);
                forced = true;
            }
            if (!forced && states.size > 0) {
                throw new IOError.FAILED ("launch is not stopping");
            }
        }

        private void begin_stop (LaunchState state) {
            if (state.stopping) return;
            state.stopping = true;
            session_log ("stopping wrap pid=%d prefix=%s".printf (state.pid, state.prefix_id));
            Posix.kill ((Posix.pid_t) state.pid, Posix.Signal.TERM);
            state.stop_timer_id = Timeout.add_seconds (STOP_TERM_GRACE_SECS, () => {
                state.stop_timer_id = 0;
                escalate_stop (state);
                return Source.REMOVE;
            });
        }

        private void escalate_stop (LaunchState state) {
            if (state.forced) return;
            state.forced = true;
            cancel_stop_timer (state);
            session_log ("force stopping wrap pid=%d prefix=%s".printf (state.pid, state.prefix_id));
            Posix.kill ((Posix.pid_t) state.pid, Posix.Signal.TERM);
            state.stop_timer_id = Timeout.add_seconds (STOP_KILL_GRACE_SECS, () => {
                state.stop_timer_id = 0;
                session_log ("killing wrap pid=%d prefix=%s".printf (state.pid, state.prefix_id));
                Utils.ProcessTree.signal_monitored_descendants (state.pid, Posix.Signal.KILL);
                Posix.kill ((Posix.pid_t) state.pid, Posix.Signal.KILL);
                return Source.REMOVE;
            });
        }

        private void cancel_stop_timer (LaunchState state) {
            if (state.stop_timer_id == 0) return;
            Source.remove (state.stop_timer_id);
            state.stop_timer_id = 0;
        }

        private void on_wrap_exited (int pid, int status) {
            session_log ("wrap exited pid=%d status=%d".printf (pid, status));
            if (launches.has_key (pid)) cancel_stop_timer (launches.get (pid));
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
                var output = new DataOutputStream (connection.output_stream);
                if (!peer_uid_allowed (connection)) {
                    write_response (output, false, "unauthorized");
                    return;
                }
                var input = new DataInputStream (connection.input_stream);
                string? line = yield input.read_line_async (Priority.DEFAULT, null, null);
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

        [CCode (cname = "lumoria_session_peer_allowed", cheader_filename = "session-peer.h")]
        private static extern bool native_peer_allowed (int fd) throws Error;

        private bool peer_uid_allowed (SocketConnection connection) {
            try {
                return native_peer_allowed (connection.socket.fd);
            } catch (Error e) {
                session_log ("rejected peer credentials: %s".printf (e.message));
                return false;
            }
        }

        private string handle_request (string request) {
            try {
                var obj = Models.parse_data_object (request);
                var provided = obj.has_member ("token") ? obj.get_string_member ("token") : "";
                if (!session_token_matches (token, provided)) {
                    return error_response ("unauthorized");
                }
                var method = obj.get_string_member ("method");

                switch (method) {
                    case "ping":
                        return ok_response ();
                    case "launch":
                        return launch_response (obj);
                    case "list":
                        return list_response ();
                    case "stop_pid":
                        return stop_response (stop_pid ((int) obj.get_int_member ("pid")));
                    case "stop":
                        return stop_response (stop (obj.get_string_member ("prefix_id")));
                    case "stop_all":
                        return stop_response (stop_all ());
                    case "force_pid":
                        force_pid ((int) obj.get_int_member ("pid"));
                        return ok_response ();
                    case "force":
                        force (obj.get_string_member ("prefix_id"));
                        return ok_response ();
                    case "force_all":
                        force_all ();
                        return ok_response ();
                    default:
                        return error_response ("unknown method: %s".printf (method));
                }
            } catch (Error e) {
                return error_response (e.message);
            }
        }

        private string launch_response (Json.Object obj) throws Error {
            var argv = Models.json_array_to_strv (obj.get_array_member ("argv"));
            if (argv.length == 0) {
                throw new IOError.FAILED ("launch argv is empty");
            }
            var cwd = obj.has_member ("cwd") ? obj.get_string_member ("cwd") : "";
            var prefix_id = obj.get_string_member ("prefix_id");
            var pid = launch (
                prefix_id,
                obj.get_string_member ("log_path"),
                Models.json_array_to_strv (obj.get_array_member ("env")),
                cwd,
                argv
            );

            var root = new Json.Object ();
            root.set_boolean_member ("ok", true);
            root.set_int_member ("pid", (int64) pid);
            return Models.json_object_to_string (root);
        }

        private string list_response () {
            var launches = new Json.Array ();
            foreach (var info in list_launches ()) {
                var entry = new Json.Object ();
                entry.set_int_member ("pid", info.pid);
                entry.set_string_member ("prefix_id", info.prefix_id);
                entry.set_string_member ("log_path", info.log_path);
                var processes = new Json.Array ();
                foreach (var process in info.processes) {
                    if (process == null || process == "") continue;
                    processes.add_string_element (process);
                }
                entry.set_array_member ("processes", processes);
                entry.set_boolean_member ("stopping", info.stopping);
                launches.add_object_element (entry);
            }
            var root = new Json.Object ();
            root.set_boolean_member ("ok", true);
            root.set_array_member ("launches", launches);
            return Models.json_object_to_string (root);
        }
    }

    private int run_session_service () {
        session_redirect_stdio_to_log ();
        var loop = new MainLoop ();
        var service = new SessionManagerService (loop, session_socket_path ());
        try {
            service.start ();
        } catch (IOError.EXISTS e) {
            return 0;
        } catch (Error e) {
            stderr.printf ("lumoria session-manager: failed to start: %s\n", e.message);
            return 1;
        }

        loop.run ();
        service.stop_service ();
        return 0;
    }

    private void session_redirect_stdio_to_log () {
        if (!Utils.Preferences.instance ().keep_runtime_logs) return;

        var log_dir = Utils.session_manager_log_dir ();
        try {
            Utils.ensure_dir (log_dir);
        } catch (Error e) {
            stderr.printf ("lumoria session-manager: could not create log dir %s: %s\n",
                log_dir, e.message);
            return;
        }
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
        stderr.printf ("\n[%s] lumoria session-manager starting\n", Utils.log_time ());
        stderr.flush ();
    }

    private void session_log (string message) {
        stderr.printf ("[%s] %s\n", Utils.log_time (), message);
        stderr.flush ();
    }

    public int cmd_session_manager (string[] args) {
        if (args.length >= 3) {
            switch (args[2]) {
                case "stop-all":
                    return session_cli_call (() => session_stop_all ());
                case "force-all":
                    return session_cli_call (() => session_force_all ());
                case "force-pid":
                    if (args.length < 4) {
                        stderr.printf ("Usage: lumoria session-manager force-pid <wrap-pid>\n");
                        return 1;
                    }
                    return session_cli_call (() => session_force_pid (int.parse (args[3])));
                case "force":
                    if (args.length < 4) {
                        stderr.printf ("Usage: lumoria session-manager force <prefix-id>\n");
                        return 1;
                    }
                    return session_cli_call (() => session_force_prefix (args[3]));
                case "stop-pid":
                    if (args.length < 4) {
                        stderr.printf ("Usage: lumoria session-manager stop-pid <wrap-pid>\n");
                        return 1;
                    }
                    return session_cli_call (() => session_stop_pid (int.parse (args[3])));
                case "stop":
                    if (args.length < 4) {
                        stderr.printf ("Usage: lumoria session-manager stop <prefix-id>\n");
                        return 1;
                    }
                    return session_cli_call (() => session_stop_prefix (args[3]));
            }
        }
        return run_session_service ();
    }

    public delegate void SessionRequestFill (Json.Object obj);

    public Json.Object session_call (string method, SessionRequestFill? fill = null) throws Error {
        var obj = session_request (method);
        if (fill != null) fill (obj);
        var response = session_send_request (Models.json_object_to_string (obj));
        if (!response_ok (response))
            throw new IOError.FAILED ("%s", response_error (response));
        return Models.parse_data_object (response);
    }

    private int session_cli_call (owned Utils.FallibleAction op) {
        try {
            op ();
            return 0;
        } catch (Error e) {
            stderr.printf ("Session manager request failed: %s\n", e.message);
            return 1;
        }
    }

    public enum SessionStatus { READY, ABSENT, UNAVAILABLE }

    public SessionStatus session_probe (out string message) {
        message = "";
        try {
            session_call ("ping");
            return SessionStatus.READY;
        } catch (Error e) {
            message = e.message;
        }
        try {
            Utils.ensure_private_dir (Path.get_dirname (session_socket_path ()));
            var fd = Utils.acquire_exclusive_lock (Utils.session_lock_path ());
            Posix.close (fd);
            return SessionStatus.ABSENT;
        } catch (Error e) {
            return SessionStatus.UNAVAILABLE;
        }
    }

    public bool session_ping () {
        try {
            session_call ("ping");
            return true;
        } catch (Error e) {
            return false;
        }
    }

    public Gee.ArrayList<SessionLaunchInfo> session_list_launches () throws Error {
        var root = session_call ("list");
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
            var process_names = Utils.strv (processes);

            launches.add (new SessionLaunchInfo (
                (int) entry.get_int_member ("pid"),
                entry.get_string_member ("prefix_id"),
                entry.has_member ("log_path") ? entry.get_string_member ("log_path") : "",
                session_format_process_label (process_names),
                process_names,
                Models.json_bool (entry, "stopping")
            ));
        }
        return launches;
    }

    public void session_stop_pid (int wrap_pid) throws Error {
        session_call ("stop_pid", (obj) => obj.set_int_member ("pid", wrap_pid));
    }

    public void session_stop_prefix (string prefix_id) throws Error {
        session_call ("stop", (obj) => obj.set_string_member ("prefix_id", prefix_id));
    }

    public void session_stop_all () throws Error {
        session_call ("stop_all");
    }

    public void session_force_pid (int wrap_pid) throws Error {
        session_call ("force_pid", (obj) => obj.set_int_member ("pid", wrap_pid));
    }

    public void session_force_prefix (string prefix_id) throws Error {
        session_call ("force", (obj) => obj.set_string_member ("prefix_id", prefix_id));
    }

    public void session_force_all () throws Error {
        try {
            session_call ("force_all");
        } catch (Error e) {
            string message;
            if (session_probe (out message) != SessionStatus.ABSENT) throw e;
        }
    }

    public delegate bool SessionLaunchMatch (SessionLaunchInfo info);

    public void session_wait_stopped (SessionLaunchMatch matches) throws Error {
        var deadline = GLib.get_monotonic_time () + (int64) STOP_WAIT_TIMEOUT_MS * 1000;
        while (true) {
            try {
                var running = false;
                foreach (var info in session_list_launches ()) {
                    if (matches (info)) running = true;
                }
                if (!running) return;
            } catch (Error e) {
                string message;
                if (session_probe (out message) == SessionStatus.ABSENT) return;
            }
            if (GLib.get_monotonic_time () >= deadline) {
                throw new IOError.TIMED_OUT ("processes are still stopping");
            }
            Thread.usleep ((uint) STOP_WAIT_POLL_MS * 1000);
        }
    }

    public string session_socket_path () {
        return Path.build_filename (Utils.data_dir (), "session", "manager.sock");
    }

    public string session_token_path () {
        return Path.build_filename (Utils.data_dir (), "session", "manager.token");
    }

    private Json.Object session_request (string method) throws Error {
        var obj = new Json.Object ();
        obj.set_string_member ("method", method);
        obj.set_string_member ("token", session_read_token ());
        return obj;
    }

    private string session_read_token () throws Error {
        string contents;
        FileUtils.get_contents (session_token_path (), out contents);
        contents = contents.strip ();
        if (contents == "") {
            throw new IOError.FAILED ("session token is empty");
        }
        return contents;
    }

    private string session_mint_token () throws Error {
        var bytes = new uint8[32];
        var fd = Posix.open ("/dev/urandom", Posix.O_RDONLY);
        if (fd < 0) {
            throw new IOError.FAILED ("Failed to open /dev/urandom: %s", Posix.strerror (Posix.errno));
        }
        var got = Posix.read (fd, bytes, bytes.length);
        Posix.close (fd);
        if (got != bytes.length) {
            throw new IOError.FAILED ("Failed to read random session token");
        }
        var hex = new StringBuilder.sized (bytes.length * 2);
        foreach (var b in bytes) {
            hex.append_printf ("%02x", b);
        }
        return hex.str;
    }

    private bool session_token_matches (string expected, string provided) {
        if (expected.length == 0 || expected.length != provided.length) return false;
        uint8 acc = 0;
        for (int i = 0; i < expected.length; i++) {
            acc |= expected[i] ^ provided[i];
        }
        return acc == 0;
    }

    private string session_send_request (string request) throws Error {
        var client = new SocketClient ();
        client.timeout = 2;
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

    private bool response_ok (string response) {
        try {
            return Models.parse_data_object (response).get_boolean_member ("ok");
        } catch (Error e) {
            return false;
        }
    }

    private string response_error (string response) {
        try {
            return Models.json_string (Models.parse_data_object (response), "error", "session request failed");
        } catch (Error e) {
            return "session request failed";
        }
    }

    private void write_response (DataOutputStream output, bool ok, string error = "") throws Error {
        output.put_string (ok ? ok_response () + "\n" : error_response (error) + "\n");
        output.flush ();
    }

    private string stop_response (bool stopping) {
        if (!stopping) return ok_response ();
        var obj = new Json.Object ();
        obj.set_boolean_member ("ok", true);
        obj.set_string_member ("status", "stopping");
        return Models.json_object_to_string (obj);
    }

    private string ok_response () {
        var obj = new Json.Object ();
        obj.set_boolean_member ("ok", true);
        return Models.json_object_to_string (obj);
    }

    private string error_response (string error) {
        var obj = new Json.Object ();
        obj.set_boolean_member ("ok", false);
        obj.set_string_member ("error", error);
        return Models.json_object_to_string (obj);
    }
}
