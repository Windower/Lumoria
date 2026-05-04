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
            return FileUtils.read_link ("/proc/self/exe");
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
                var name = match.fetch (2);
                var chain = match.fetch (3);
                if (escape != null && escape == "$") {
                    builder.append ("${" + name + "}");
                    return false;
                }
                if (name == null) {
                    builder.append (match.fetch (0));
                    return false;
                }
                string val = vars.has_key (name) ? vars[name] : "";
                builder.append (apply_modifier_chain (val, chain));
                return false;
            });
        } catch (RegexError e) {
            warning ("expand_vars: %s", e.message);
            return input;
        }
    }

    private static string apply_modifier_chain (string raw, string? chain) {
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
                "\\$(\\$)?\\{([A-Za-z_][A-Za-z0-9_]*)(?::([^}]+))?\\}"
            );
        }
        return _var_token_regex;
    }

}
