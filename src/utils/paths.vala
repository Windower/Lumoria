namespace Lumoria.Utils {

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
        try {
            var exe = FileUtils.read_link ("/proc/self/exe");
            var prefix = Path.get_dirname (Path.get_dirname (exe));
            var resource_name = "%s.gresource".printf (Config.APP_ID);

            var dev = Path.build_filename (prefix, "data", resource_name);
            if (FileUtils.test (dev, FileTest.EXISTS)) return dev;

            var installed = Path.build_filename (prefix, "share", "lumoria", resource_name);
            if (FileUtils.test (installed, FileTest.EXISTS)) return installed;
        } catch (FileError e) {
            warning ("Failed to resolve resource path: %s", e.message);
        }

        return null;
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
        var result = input;
        var keys = new Gee.ArrayList<string> ();
        foreach (var e in vars.entries) {
            keys.add (e.key);
        }
        keys.sort ((a, b) => {
            if (a.length == b.length) return 0;
            return a.length > b.length ? -1 : 1;
        });
        foreach (var key in keys) {
            result = result.replace ("${" + key + "}", vars[key]);
            result = result.replace ("$" + key, vars[key]);
        }
        return result;
    }

}
