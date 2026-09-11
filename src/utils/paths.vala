namespace Lumoria.Utils {
    public static string normalize_wine_arch (string arch) {
        var a = arch.down ().strip ();
        if (a == "win64" || a == "amd64" || a == "x86_64") return "win64";
        if (a == "win32" || a == "i386") return "win32";
        return "";
    }


    /* Filesystem-safe local timestamp for log and dump file names. */
    public static string log_stamp () {
        return new DateTime.now_local ().format ("%Y%m%d-%H%M%S");
    }

    /* Human-readable local timestamp for log lines. */
    public static string log_time () {
        return new DateTime.now_local ().format ("%F %T");
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
            try {
                ensure_dir (dir);
                if (FileUtils.test (dir, FileTest.IS_DIR)) return dir;
            } catch (Error e) {
                warning ("Could not create prefix log directory %s: %s; using cache", dir, e.message);
            }
        }
        var fallback = cache_log_dir ();
        try {
            ensure_dir (fallback);
            if (FileUtils.test (fallback, FileTest.IS_DIR)) return fallback;
        } catch (Error e) {
            warning ("Could not create cache log directory %s: %s", fallback, e.message);
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

    public static string resources_dir () {
        return Path.build_filename (data_dir (), "resources");
    }

    public static string resource_dir (string id) {
        return Path.build_filename (resources_dir (), id);
    }

    public static string prefix_registry_path () {
        return Path.build_filename (config_dir (), "prefixes.json");
    }

    public static string preferences_path () {
        return Path.build_filename (config_dir (), "preferences.json");
    }

    public static string app_state_path () {
        return Path.build_filename (config_dir (), "app-state.json");
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

    public static string host_lumoria_bin () {
        var exe = current_executable_path ();
        return exe != null && exe != "" ? exe : "lumoria";
    }

    public static string host_lumoria_exec (string args) {
        if (EnvironmentInfo.is_flatpak ()) return "lumoria %s".printf (args);
        return "%s %s".printf (shell_quote (host_lumoria_bin ()), args);
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
        if (EnvironmentInfo.is_sandboxed ()) {
            return Path.build_filename (Environment.get_user_data_dir (), "prefixes");
        }
        return suggested_prefix_dir ();
    }

    public static string suggested_prefix_dir () {
        return Path.build_filename (Environment.get_home_dir (), "Games", "Lumoria", "prefixes");
    }

    public static void ensure_prefix_indexer_ignores () {
        ensure_indexer_ignore (default_prefix_dir ());
        var suggested = suggested_prefix_dir ();
        if (suggested != default_prefix_dir () && FileUtils.test (suggested, FileTest.IS_DIR)) {
            ensure_indexer_ignore (suggested);
        }
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

    public static string collapse_path (string path) {
        var raw = path.replace ("\\", "/");
        var absolute = raw.has_prefix ("/");
        var stack = new Gee.ArrayList<string> ();
        foreach (var part in raw.split ("/")) {
            if (part == "" || part == ".") continue;
            if (part == "..") {
                if (stack.size > 0) stack.remove_at (stack.size - 1);
                continue;
            }
            stack.add (part);
        }
        if (stack.size == 0) return absolute ? "/" : "";
        var builder = new StringBuilder ();
        if (absolute) builder.append_c ('/');
        builder.append (stack[0]);
        for (int i = 1; i < stack.size; i++) {
            builder.append_c ('/');
            builder.append (stack[i]);
        }
        return builder.str;
    }

    public static string resolve_existing (string path) {
        var collapsed = collapse_path (path);
        if (collapsed == "") return collapsed;
        var current = collapsed;
        var suffix = "";
        while (current != "" && current != "/") {
            var resolved = Posix.realpath (current);
            if (resolved != null && resolved != "") {
                return suffix == "" ? resolved : Path.build_filename (resolved, suffix);
            }
            var name = Path.get_basename (current);
            var parent = Path.get_dirname (current);
            suffix = suffix == "" ? name : Path.build_filename (name, suffix);
            if (parent == current) break;
            current = parent;
        }
        return collapsed;
    }

    /* Symlink-aware containment check. */
    public static bool path_inside (string path, string root) {
        return path_within (
            collapse_path (normalize_dir_path (resolve_existing (path))),
            collapse_path (normalize_dir_path (resolve_existing (root)))
        );
    }

    /* Lexical containment of already-normalized paths. */
    public static bool path_within (string path, string root) {
        return path == root || path.has_prefix (root + "/");
    }

    public static string confined_filename (string name) throws Error {
        var filename = Path.get_basename (name.replace ("\\", "/").strip ());
        if (filename == "" || filename == "." || filename == "..") {
            throw new LumoriaError.FAILED (_("Invalid filename: %s").printf (name));
        }
        return filename;
    }

    public static string join_inside (string root, string relative) throws Error {
        var rel = relative.replace ("\\", "/").strip ();
        if (rel == "" || rel.has_prefix ("/")) {
            throw new LumoriaError.FAILED (_("Path is outside the allowed directory: %s").printf (relative));
        }
        foreach (var part in rel.split ("/")) {
            if (part == "..") {
                throw new LumoriaError.FAILED (_("Path is outside the allowed directory: %s").printf (relative));
            }
        }
        return Path.build_filename (root, relative);
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
        if (EnvironmentInfo.is_sandboxed () && normalized == normalize_dir_path (suggested_prefix_dir ())) return true;
        return false;
    }
}
