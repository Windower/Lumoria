namespace Lumoria.Runtime {
    public const string VAR_PREFIX = "PREFIX";
    public const string VAR_ARCH = "ARCH";
    public const string VAR_COMPONENT = "COMPONENT";
    public const string VAR_RUNNER = "RUNNER";
    public const string VAR_WINDOWS = "WINDOWS";
    public const string VAR_SYSTEM32 = "SYSTEM32";
    public const string VAR_SYSWOW64 = "SYSWOW64";
    public const string VAR_SYS32 = "SYS32";
    public const string VAR_FONTS = "FONTS";
    public const string VAR_CACHE = "CACHE";
    public const string VAR_CACHE_BASE = "CACHE_BASE";
    public const string VAR_CACHE_REDIST = "CACHE_REDIST";
    public const string VAR_WINEBOOT_MSCOREE = "WINEBOOT_MSCOREE";

    public string get_var (Gee.HashMap<string, string> vars, string key, string fallback = "") {
        return vars.has_key (key) ? vars[key] : fallback;
    }

    public bool is_confined_path (string path, Gee.HashMap<string, string> vars, bool allow_cache) {
        var resolved = Utils.collapse_path (path);
        var prefix = get_var (vars, VAR_PREFIX);
        if (prefix != "" && Utils.path_inside (resolved, prefix)) return true;
        if (!allow_cache) return false;
        var cache = get_var (vars, VAR_CACHE_BASE);
        if (cache == "") cache = Utils.cache_dir ();
        return cache != "" && Utils.path_inside (resolved, cache);
    }

    public string require_confined_path (
        string raw,
        Gee.HashMap<string, string> vars,
        string escape_message,
        bool allow_cache = false
    ) throws Error {
        var expanded = Utils.expand_vars (raw, vars);
        if (expanded == "") return expanded;
        var resolved = Utils.collapse_path (expanded);
        if (is_confined_path (resolved, vars, allow_cache)) return resolved;
        throw new LumoriaError.FAILED (escape_message.printf (expanded));
    }

    public delegate void EnvAssignment (string key, string value);

    public void for_each_matching_env_rule (
        Gee.ArrayList<Models.EnvRule> rules,
        Gee.HashMap<string, string> vars,
        EnvAssignment assign
    ) {
        foreach (var rule in rules) {
            if (rule.when != null && !rule.when.evaluate (vars)) continue;
            foreach (var entry in rule.vars.entries) {
                assign (entry.key, Utils.expand_vars (entry.value, vars));
            }
        }
    }

    public void apply_env_rules (
        WineEnv env,
        Gee.ArrayList<Models.EnvRule> rules,
        Gee.HashMap<string, string> vars
    ) {
        for_each_matching_env_rule (rules, vars, (key, value) => env.set_var (key, value));
    }

    /* ARCH plus SYS32, the directory holding that arch's 32-bit DLLs; needs the prefix paths seeded first. */
    public void set_arch_vars (Gee.HashMap<string, string> vars, string arch) {
        vars[VAR_ARCH] = arch;
        var sys32 = vars[arch == "win32" ? VAR_SYSTEM32 : VAR_SYSWOW64];
        if (sys32 != null) vars[VAR_SYS32] = sys32;
    }

    public void seed_prefix_paths (Gee.HashMap<string, string> vars, string pfx_path) {
        var paths = PrefixPaths.from_root (pfx_path);
        vars[VAR_PREFIX] = paths.wine_prefix;
        vars[VAR_WINDOWS] = paths.windows;
        vars[VAR_SYSTEM32] = paths.system32;
        vars[VAR_SYSWOW64] = paths.syswow64;
        vars[VAR_FONTS] = paths.fonts;
    }

    public void seed_manifest_vars (
        Gee.HashMap<string, string> vars,
        string pfx_path,
        Models.InstallerManifest? installer = null,
        string? cache_path = null
    ) {
        seed_prefix_paths (vars, pfx_path);
        if (cache_path != null) {
            vars[VAR_CACHE_BASE] = Utils.cache_dir ();
            vars[VAR_CACHE_REDIST] = Path.build_filename (Utils.cache_dir (), "redist");
            vars[VAR_CACHE] = cache_path;
        }
        if (installer != null) merge_vars (vars, installer.variables);
    }

    public void merge_vars (Gee.HashMap<string, string> dst, Gee.HashMap<string, string> src) {
        foreach (var e in src.entries) {
            dst[e.key] = e.value;
        }
    }

    public void apply_variable_rules (
        Gee.HashMap<string, string> vars,
        Gee.ArrayList<Models.EnvRule> rules
    ) {
        for_each_matching_env_rule (rules, vars, (key, value) => { vars[key] = value; });
    }

    public string resolve_host_path (string exe, string pfx_path) {
        var drive_c = PrefixPaths.drive_c_of (pfx_path);
        var lower = exe.down ();
        string resolved;
        if (lower.has_prefix ("c:\\") || lower.has_prefix ("c:") || lower.has_prefix ("c:/")) {
            var rest = exe.substring (2);
            if (rest.has_prefix ("\\") || rest.has_prefix ("/")) rest = rest.substring (1);
            resolved = Path.build_filename (drive_c, rest.replace ("\\", "/"));
        } else if (Path.is_absolute (exe)) {
            resolved = exe;
        } else {
            resolved = Path.build_filename (pfx_path, exe.replace ("\\", "/"));
        }
        return Utils.collapse_path (resolved);
    }

    public string to_wine_path (string pfx_path, string host_exe) {
        var drive_c = PrefixPaths.drive_c_of (pfx_path);
        if (host_exe.has_prefix (drive_c + "/")) {
            var rel = host_exe.substring (drive_c.length + 1);
            return "C:\\" + rel.replace ("/", "\\");
        }
        return "Z:" + host_exe.replace ("/", "\\");
    }

    public string wine_arg_path (string pfx_path, string host_exe) {
        var drive_c = PrefixPaths.drive_c_of (pfx_path);
        return host_exe.has_prefix (drive_c + "/") ? to_wine_path (pfx_path, host_exe) : host_exe;
    }

    public string normalize_wineexec_host_path (string value, Gee.HashMap<string, string> vars) throws Error {
        if (value == "") return value;
        if (Path.is_absolute (value)) return value;
        if (!vars.has_key (VAR_PREFIX)) return value;

        var lower = value.down ();
        if (lower.has_prefix ("drive_c/")
            || lower.has_prefix ("drive_c\\")
            || lower.has_prefix ("c:\\")
            || lower.has_prefix ("c:/")
            || lower == "c:") {
            return resolve_host_path (value, vars[VAR_PREFIX]);
        }

        return value;
    }

    public void resolve_prefix_vars (
        Gee.HashMap<string, string> vars,
        Models.PrefixEntry? entry,
        RuntimeLog? logger = null
    ) {
        if (entry == null) return;
        var keys = new Gee.ArrayList<string> ();
        foreach (var k in vars.keys) keys.add (k);
        foreach (var k in keys) {
            var raw = vars[k];
            string name;
            if (!parse_computed_expr (raw, "prefix.", out name)) continue;
            Models.PrefixVarField field;
            if (!Models.PrefixVarField.parse (name, out field)) {
                if (logger != null) {
                    logger.typed (LogType.WARN, "unknown prefix field '%s' in %s".printf (name, k));
                }
                continue;
            }
            vars[k] = entry.var_field (field);
        }
    }

    public void finalize_manifest_vars (
        Gee.HashMap<string, string> vars,
        WinePaths? paths = null,
        WineEnv? env = null,
        RuntimeLog? logger = null
    ) {
        var log = logger ?? new RuntimeLog ();
        resolve_computed_vars (vars, paths, env, log);
        Utils.resolve_var_references (vars);
    }

    public void resolve_computed_vars (
        Gee.HashMap<string, string> vars,
        WinePaths? paths,
        WineEnv? env,
        RuntimeLog logger
    ) {
        var keys = new Gee.ArrayList<string> ();
        foreach (var k in vars.keys) keys.add (k);
        foreach (var k in keys) {
            var raw = vars[k];
            string? resolved = null;
            string arg;
            if (parse_computed_expr (raw, "winepath:", out arg)) {
                if (paths == null || env == null || paths.wine == "") continue;
                resolved = resolve_winepath (arg, paths, env, logger);
            } else if (parse_computed_expr (raw, "pref:", out arg)) {
                resolved = resolve_pref (arg, logger);
            } else {
                continue;
            }
            if (resolved != null) vars[k] = resolved;
        }
    }

    private bool parse_computed_expr (string raw, string prefix, out string arg) {
        arg = "";
        if (!raw.has_prefix ("${") || !raw.has_suffix ("}")) return false;
        var body = raw.substring (2, raw.length - 3);
        if (!body.has_prefix (prefix)) return false;
        arg = body.substring (prefix.length);
        return arg != "";
    }

    public string? resolve_pref (string key, RuntimeLog logger) {
        var node = (Json.Node) new Json.Node (Json.NodeType.OBJECT);
        node.set_object (Utils.Preferences.instance ().snapshot ());
        foreach (var part in key.split (".")) {
            switch (node.get_node_type ()) {
                case Json.NodeType.OBJECT:
                    var obj = node.get_object ();
                    if (!obj.has_member (part)) {
                        logger.typed (LogType.WARN, "unknown pref key '%s'".printf (key));
                        return null;
                    }
                    node = obj.get_member (part);
                    break;
                case Json.NodeType.ARRAY:
                    int64 idx;
                    if (!int64.try_parse (part, out idx) || idx < 0) {
                        logger.typed (LogType.WARN, "pref '%s': '%s' is not a valid array index".printf (key, part));
                        return null;
                    }
                    var arr = node.get_array ();
                    if (idx >= arr.get_length ()) {
                        logger.typed (LogType.WARN, "pref '%s': index %s out of range (size=%u)".printf (key, part, arr.get_length ()));
                        return null;
                    }
                    node = arr.get_element ((uint) idx);
                    break;
                default:
                    logger.typed (LogType.WARN, "pref '%s': cannot descend through '%s'".printf (key, part));
                    return null;
            }
        }
        var s = Models.json_scalar_to_string (node);
        if (s == null) {
            logger.typed (LogType.WARN, "pref '%s' is not a scalar value".printf (key));
        }
        return s;
    }

    private const int WINEPATH_TIMEOUT_MS = 60 * 1000;

    public string? resolve_winepath (string windows_expr, WinePaths paths, WineEnv env, RuntimeLog logger) {
        try {
            var captured = run_wine_command_capture (
                paths, { "cmd.exe", "/C", "winepath", "-u", windows_expr }, env, null, logger, null, WINEPATH_TIMEOUT_MS
            ).strip ();
            if (captured == "") return null;
            string last = captured;
            foreach (var line in captured.split ("\n")) {
                var trimmed = line.strip ();
                if (trimmed != "") last = trimmed;
            }
            var path = last.replace ("\\", "/");
            while (path.length > 1 && path.has_suffix ("/")) {
                path = path.substring (0, path.length - 1);
            }
            return path;
        } catch (Error e) {
            logger.typed (LogType.WARN, "winepath '%s' failed: %s".printf (windows_expr, e.message));
            return null;
        }
    }
}
