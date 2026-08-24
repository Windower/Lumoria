namespace Lumoria.Utils {
    [DBus (name = "org.freedesktop.portal.Documents")]
    private interface DocumentPortal : Object {
        public abstract uint8[] GetMountPoint () throws Error;
    }

    public static string normalize_wine_arch (string arch) {
        var a = arch.down ().strip ();
        if (a == "win64" || a == "amd64" || a == "x86_64") return "win64";
        if (a == "win32" || a == "i386") return "win32";
        return "";
    }

    public static bool is_sandboxed () {
        return EnvironmentInfo.is_sandboxed ();
    }

    public static string config_dir () {
        return Path.build_filename (Environment.get_user_config_dir (), "lumoria");
    }

    public static string data_dir () {
        return Path.build_filename (Environment.get_user_data_dir (), "lumoria");
    }

    public static string prefix_log_dir (string prefix_path) {
        return Path.build_filename (prefix_path, "logs");
    }

    public static string cache_log_dir () {
        return Path.build_filename (cache_dir (), "logs");
    }

    public static string resolve_log_dir (string prefix_path) {
        if (prefix_path != "") {
            var dir = prefix_log_dir (prefix_path);
            if (ensure_dir (dir) && FileUtils.test (dir, FileTest.IS_DIR)) {
                return dir;
            }
            warning ("Could not create prefix log directory %s; using cache", dir);
        }
        var fallback = cache_log_dir ();
        if (ensure_dir (fallback) && FileUtils.test (fallback, FileTest.IS_DIR)) {
            return fallback;
        }
        return "";
    }

    public static string session_manager_log_dir () {
        return Path.build_filename (data_dir (), "session", "logs");
    }

    public static string session_manager_log_path () {
        return Path.build_filename (session_manager_log_dir (), "session-manager.log");
    }

    public static string cache_dir () {
        return Path.build_filename (Environment.get_user_cache_dir (), "lumoria");
    }

    public static string runner_dir () {
        if (EnvironmentInfo.is_flatpak ()) {
            return Path.build_filename (Environment.get_user_data_dir (), "runners");
        }
        return Path.build_filename (data_dir (), "runners");
    }

    public static string component_dir () {
        if (EnvironmentInfo.is_flatpak ()) {
            return Path.build_filename (Environment.get_user_data_dir (), "components");
        }
        return Path.build_filename (data_dir (), "components");
    }

    public static string prefix_registry_path () {
        return Path.build_filename (config_dir (), "prefixes.json");
    }

    public static string? resolve_resource_path () {
        var exe = current_executable_path ();
        if (exe == null) return null;
        var prefix = Path.get_dirname (Path.get_dirname (exe));
        var resource_name = "%s.gresource".printf (Config.APP_ID);

        var dev = Path.build_filename (prefix, "data", resource_name);
        if (FileUtils.test (dev, FileTest.EXISTS)) return dev;

        var installed = Path.build_filename (prefix, "share", "lumoria", resource_name);
        if (FileUtils.test (installed, FileTest.EXISTS)) return installed;

        return null;
    }

    public static string? current_executable_path () {
        try {
            var path = FileUtils.read_link ("/proc/self/exe");
            var deleted_suffix = " (deleted)";
            if (path.has_suffix (deleted_suffix)) {
                var live_path = path.substring (0, path.length - deleted_suffix.length);
                if (FileUtils.test (live_path, FileTest.EXISTS)) return live_path;
            }
            return path;
        } catch (FileError e) {
            warning ("Failed to resolve current executable path: %s", e.message);
            return null;
        }
    }

    public static void register_resources () {
        var resource_path = resolve_resource_path ();
        if (resource_path == null) return;
        try {
            var resource = Resource.load (resource_path);
            GLib.resources_register (resource);
        } catch (Error e) {
            warning ("Failed to load resource bundle: %s", e.message);
        }
    }

    public static string default_prefix_dir () {
        if (is_sandboxed ()) {
            return Path.build_filename (Environment.get_user_data_dir (), "prefixes");
        }
        return suggested_prefix_dir ();
    }

    public static string suggested_prefix_dir () {
        return Path.build_filename (Environment.get_home_dir (), "Games", "Lumoria", "prefixes");
    }

    public static string next_available_prefix_path (Models.PrefixRegistry registry) {
        var base_dir = default_prefix_dir ();
        var candidate = Path.build_filename (base_dir, "prefix-1");
        if (registry.by_path (candidate) == null) return candidate;
        for (int i = 2; i < 10000; i++) {
            candidate = Path.build_filename (base_dir, "prefix-%d".printf (i));
            if (registry.by_path (candidate) == null) return candidate;
        }
        return candidate;
    }

    public static string normalize_dir_path (string path) {
        var normalized = path.strip ();
        while (normalized.length > 1 && normalized.has_suffix ("/")) {
            normalized = normalized.substring (0, normalized.length - 1);
        }
        return normalized;
    }

    public static bool is_prefixes_root_path (string path) {
        var normalized = normalize_dir_path (path);
        if (normalized == normalize_dir_path (default_prefix_dir ())) return true;
        if (is_sandboxed () && normalized == normalize_dir_path (suggested_prefix_dir ())) return true;
        return false;
    }

    public static Models.PortalPathRef? portal_path_ref_from_path_uri (
        string raw_path,
        string raw_uri = ""
    ) {
        string document_id;
        string document_path;
        if (!parse_document_portal_path (raw_path, out document_id, out document_path)) {
            var uri_path = file_uri_path (raw_uri);
            if (!parse_document_portal_path (uri_path, out document_id, out document_path)) return null;
        }

        var portal = new Models.PortalPathRef ();
        portal.document_id = document_id;
        portal.document_path = document_path;
        portal.uri = raw_uri;
        return portal;
    }

    public static string resolve_user_path (
        string raw_path,
        Models.PortalPathRef? portal_ref = null,
        string raw_uri = ""
    ) {
        if (raw_path != "" && FileUtils.test (raw_path, FileTest.EXISTS)) return raw_path;

        var uri_path = file_uri_path (raw_uri);
        if (uri_path != "" && FileUtils.test (uri_path, FileTest.EXISTS)) return uri_path;

        var portal_path = resolve_portal_path (portal_ref);
        if (portal_path != "") return portal_path;

        return raw_path != "" ? raw_path : uri_path;
    }

    public static string resolve_portal_path (Models.PortalPathRef? portal_ref) {
        if (portal_ref == null || portal_ref.is_empty ()) return "";

        var mount = document_portal_mount_point ();
        if (mount == "") return "";

        var path = Path.build_filename (
            mount,
            portal_ref.document_id,
            portal_ref.document_path
        );
        if (FileUtils.test (path, FileTest.EXISTS)) return path;

        var by_app = Path.build_filename (
            mount,
            "by-app",
            Config.APP_ID,
            portal_ref.document_id,
            portal_ref.document_path
        );
        if (FileUtils.test (by_app, FileTest.EXISTS)) return by_app;

        return "";
    }

    public class PortalPathDiagnostics : Object {
        public bool has_portal_ref { get; set; default = false; }
        public string mount_point { get; set; default = ""; }
        public string direct_candidate { get; set; default = ""; }
        public string by_app_candidate { get; set; default = ""; }
        public bool direct_exists { get; set; default = false; }
        public bool by_app_exists { get; set; default = false; }
    }

    public static PortalPathDiagnostics portal_path_diagnostics (Models.PortalPathRef? portal_ref) {
        var diagnostics = new PortalPathDiagnostics ();
        diagnostics.has_portal_ref = portal_ref != null && !portal_ref.is_empty ();
        if (!diagnostics.has_portal_ref) return diagnostics;

        diagnostics.mount_point = document_portal_mount_point ();
        if (diagnostics.mount_point == "") return diagnostics;

        diagnostics.direct_candidate = Path.build_filename (
            diagnostics.mount_point,
            portal_ref.document_id,
            portal_ref.document_path
        );
        diagnostics.by_app_candidate = Path.build_filename (
            diagnostics.mount_point,
            "by-app",
            Config.APP_ID,
            portal_ref.document_id,
            portal_ref.document_path
        );
        diagnostics.direct_exists = FileUtils.test (diagnostics.direct_candidate, FileTest.EXISTS);
        diagnostics.by_app_exists = FileUtils.test (diagnostics.by_app_candidate, FileTest.EXISTS);
        return diagnostics;
    }

    private static string file_uri_path (string raw_uri) {
        if (raw_uri == "") return "";
        try {
            var uri = Uri.parse (raw_uri, UriFlags.NONE);
            if (uri.get_scheme () != "file") return "";
            var path = uri.get_path ();
            return path != null ? path : "";
        } catch (UriError e) {
            return "";
        }
    }

    private static bool parse_document_portal_path (
        string raw_path,
        out string document_id,
        out string document_path
    ) {
        document_id = "";
        document_path = "";

        var normalized = raw_path.replace ("\\", "/");
        var marker = "/doc/";
        var idx = normalized.index_of (marker);
        if (idx < 0) return false;

        var rest = normalized.substring (idx + marker.length);
        if (rest.has_prefix ("by-app/")) {
            var by_app_parts = rest.split ("/", 4);
            if (by_app_parts.length < 4) return false;
            document_id = by_app_parts[2];
            document_path = by_app_parts[3];
            return document_id != "" && document_path != "";
        }

        var parts = rest.split ("/", 2);
        if (parts.length < 2) return false;
        document_id = parts[0];
        document_path = parts[1];
        return document_id != "" && document_path != "";
    }

    private static string document_portal_mount_point () {
        try {
            var portal = Bus.get_proxy_sync<DocumentPortal> (
                BusType.SESSION,
                "org.freedesktop.portal.Documents",
                "/org/freedesktop/portal/documents"
            );
            return uint8_array_to_string (portal.GetMountPoint ());
        } catch (Error e) {
            warning ("Failed to resolve document portal mount point: %s", e.message);
            return "";
        }
    }

    private static string uint8_array_to_string (uint8[] bytes) {
        var builder = new StringBuilder ();
        foreach (var b in bytes) {
            if (b == 0) break;
            builder.append_c ((char) b);
        }
        return builder.str;
    }

    public static string slugify (string input) {
        var result = new StringBuilder ();
        unichar c;
        for (int i = 0; input.get_next_char (ref i, out c);) {
            if (c.isalnum ()) {
                result.append_unichar (c.tolower ());
            } else if (c == ' ' || c == '-' || c == '_' || c == '/') {
                if (result.len > 0 && result.str[result.len - 1] != '-') {
                    result.append_c ('-');
                }
            }
        }
        var s = result.str;
        while (s.has_suffix ("-")) s = s[0 : s.length - 1];
        return s;
    }

    public static string expand_vars (string input, Gee.HashMap<string, string> vars) {
        if (input.index_of_char ('$') < 0) return input;
        try {
            return var_token_regex ().replace_eval (input, input.length, 0, 0, (match, builder) => {
                var escape = match.fetch (1);
                var ns = match.fetch (2);
                var name = match.fetch (3);
                var chain = match.fetch (4);
                if (escape != null && escape == "$") {
                    builder.append ("${" + ns + "." + name + "}");
                    return false;
                }
                if (ns == null || name == null) {
                    builder.append (match.fetch (0));
                    return false;
                }
                string val = "";
                switch (ns) {
                    case "var":
                        val = vars.has_key (name) ? vars[name] : "";
                        break;
                    case "env":
                        val = Environment.get_variable (name) ?? "";
                        break;
                    default:
                        break;
                }
                builder.append (apply_modifier_chain (val, chain));
                return false;
            });
        } catch (RegexError e) {
            warning ("expand_vars: %s", e.message);
            return input;
        }
    }

    public static string apply_modifier_chain (string raw, string? chain) {
        if (chain == null || chain == "") return raw;
        string result = raw;
        foreach (var segment in chain.split ("|")) {
            if (segment == "") continue;
            var colon = segment.index_of_char (':');
            string mod_name;
            string? mod_arg;
            if (colon < 0) {
                mod_name = segment;
                mod_arg = null;
            } else {
                mod_name = segment.substring (0, colon);
                mod_arg = segment.substring (colon + 1);
            }
            result = apply_modifier (result, mod_name, mod_arg);
        }
        return result;
    }

    private static string apply_modifier (string raw, string modifier, string? arg) {
        switch (modifier) {
            case "upper":
                return raw.up ();
            case "lower":
                return raw.down ();
            case "capitalize":
                if (raw.length == 0) return raw;
                return raw.substring (0, 1).up () + raw.substring (1).down ();
            case "truncate":
                if (arg == null || arg == "") return raw;
                int64 n;
                if (int64.try_parse (arg, out n) && n >= 0 && n < raw.length)
                    return raw.substring (0, (long) n);
                return raw;
            case "replace":
                if (arg == null || arg.length < 2) return raw;
                var delim = arg.substring (0, 1);
                var parts = arg.substring (1).split (delim);
                if (parts.length < 2) return raw;
                return raw.replace (parts[0], parts[1]);
            case "default":
                return (raw == "") ? (arg ?? "") : raw;
            case "urlencode":
                return Uri.escape_string (raw, null, true);
            case "slug":
                return slugify (raw);
            default:
                warning ("expand_vars: unknown modifier '%s'", modifier);
                return raw;
        }
    }

    public static void resolve_var_references (Gee.HashMap<string, string> vars) {
        const int MAX_ITERATIONS = 16;
        int iterations = 0;
        bool changed = true;
        while (changed && iterations < MAX_ITERATIONS) {
            changed = false;
            iterations++;
            var keys = new Gee.ArrayList<string> ();
            foreach (var k in vars.keys) keys.add (k);
            foreach (var k in keys) {
                var current = vars[k];
                if (current.index_of_char ('$') < 0) continue;
                var expanded = expand_vars (current, vars);
                if (expanded != current) {
                    vars[k] = expanded;
                    changed = true;
                }
            }
        }
        if (changed) {
            warning ("resolve_var_references: did not stabilize after %d iterations (cycle?)", MAX_ITERATIONS);
        }
    }

    private static Regex? _var_token_regex = null;
    private static Regex var_token_regex () throws RegexError {
        if (_var_token_regex == null) {
            _var_token_regex = new Regex (
                "\\$(\\$)?\\{(var|env)\\.([A-Za-z_][A-Za-z0-9_]*)(?::([^}]+))?\\}"
            );
        }
        return _var_token_regex;
    }

}
