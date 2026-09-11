namespace Lumoria.Utils {
    public static string sanitize_ui_text (string value) {
        if (value == "") return "";
        return value.validate () ? value : value.make_valid ();
    }

    public static string sanitize_user_text (string value) {
        if (value == "") return "";
        var text = value.validate () ? value : value.make_valid ();
        var builder = new StringBuilder ();
        unichar c;
        int i = 0;
        while (text.get_next_char (ref i, out c)) {
            if (c == 0xFFFD || c == 0x7F) continue;
            if (c < 0x20) continue;
            if (c >= 0x80 && c < 0xA0) continue;
            builder.append_unichar (c);
        }
        return builder.str.strip ();
    }

    public static string sanitize_filename_token (string input) {
        var sb = new StringBuilder ();
        for (int i = 0; i < input.length; i++) {
            var c = input[i];
            bool keep = (c >= 'a' && c <= 'z')
                || (c >= 'A' && c <= 'Z')
                || (c >= '0' && c <= '9')
                || c == '-'
                || c == '_';
            sb.append_c (keep ? c : '_');
        }
        return sb.str;
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

    public static string random_id (string prefix) {
        return "%s-%s".printf (prefix, Uuid.string_random ());
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
                string val;
                switch (ns) {
                    case "var":
                        val = vars.has_key (name) ? vars[name] : "";
                        break;
                    case "env":
                        val = allowed_env (name);
                        break;
                    default:
                        warning ("expand_vars: unknown namespace '%s' in %s", ns, match.fetch (0));
                        builder.append (match.fetch (0));
                        return false;
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
            case "each": {
                /* Renders the template once per non-empty line, %s standing in for the line. */
                if (arg == null || arg == "") return raw;
                var lines = new Gee.ArrayList<string> ();
                foreach (var line in raw.split ("\n")) {
                    var item = line.strip ();
                    if (item != "") lines.add (arg.replace ("%s", item));
                }
                return string.joinv ("\n", lines.to_array ());
            }
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

    private static bool env_allowed (string name) {
        switch (name) {
            case "HOME":
            case "USER":
            case "USERNAME":
            case "LOGNAME":
            case "LANG":
            case "LC_ALL":
            case "LC_CTYPE":
            case "XDG_DATA_HOME":
            case "XDG_CONFIG_HOME":
            case "XDG_CACHE_HOME":
            case "XDG_RUNTIME_DIR":
            case "XDG_CURRENT_DESKTOP":
            case "DISPLAY":
            case "WAYLAND_DISPLAY":
            case "HOSTNAME":
                return true;
            default:
                return false;
        }
    }

    private static string allowed_env (string name) {
        if (!env_allowed (name)) return "";
        return Environment.get_variable (name) ?? "";
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
