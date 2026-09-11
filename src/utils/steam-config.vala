// Credit to Lutris for the original implementation in Python: https://github.com/lutris/lutris/
namespace Lumoria.Utils.SteamConfig {

    public errordomain ConfigError {
        INVALID_CONFIG
    }

    public class UserConfig : Object {
        public string steam_dir { get; set; default = ""; }
        public string userdata_dir { get; set; default = ""; }
        public string config_dir { get; set; default = ""; }
        public string shortcuts_vdf_path { get; set; default = ""; }
        public string account_name { get; set; default = ""; }
        public string persona_name { get; set; default = ""; }
    }

    private class LoginUser : Object {
        public string steamid64 { get; set; default = ""; }
        public string account_name { get; set; default = ""; }
        public string persona_name { get; set; default = ""; }
        public bool most_recent { get; set; default = false; }
    }

    private class TextNode : Object {
        public string value { get; set; default = ""; }
        public Gee.HashMap<string, TextNode> children { get; private set; default = new Gee.HashMap<string, TextNode> (); }
    }

    private class TextParser : Object {
        private string[] tokens;
        private int index = 0;

        public TextParser (string data) throws Error {
            tokens = tokenize (data);
        }

        public TextNode parse () throws Error {
            var root = new TextNode ();
            parse_into (root, false);
            return root;
        }

        private void parse_into (TextNode parent, bool expect_close) throws Error {
            while (index < tokens.length) {
                var token = tokens[index++];
                if (token == "}") {
                    if (!expect_close) throw new ConfigError.INVALID_CONFIG ("Unexpected closing brace in Steam config");
                    return;
                }
                if (token == "{") throw new ConfigError.INVALID_CONFIG ("Unexpected opening brace in Steam config");

                if (index >= tokens.length) throw new ConfigError.INVALID_CONFIG ("Missing value for Steam config key '%s'".printf (token));
                var next = tokens[index++];
                var child = new TextNode ();
                if (next == "{") {
                    parse_into (child, true);
                } else if (next == "}") {
                    throw new ConfigError.INVALID_CONFIG ("Missing value for Steam config key '%s'".printf (token));
                } else {
                    child.value = next;
                }
                parent.children[token.down ()] = child;
            }

            if (expect_close) throw new ConfigError.INVALID_CONFIG ("Unterminated Steam config object");
        }

        private static string[] tokenize (string data) throws Error {
            var tokens = new Gee.ArrayList<string> ();
            for (int i = 0; i < data.length;) {
                var c = data[i];
                if (c.isspace ()) {
                    i++;
                    continue;
                }
                if (c == '{' || c == '}') {
                    tokens.add (((char) c).to_string ());
                    i++;
                    continue;
                }
                if (c != '"') {
                    while (i < data.length && data[i] != '\n') i++;
                    continue;
                }

                i++;
                var builder = new StringBuilder ();
                while (i < data.length) {
                    c = data[i++];
                    if (c == '"') break;
                    if (c == '\\' && i < data.length) {
                        builder.append_c ((char) data[i++]);
                    } else {
                        builder.append_c ((char) c);
                    }
                }
                tokens.add (builder.str);
            }
            return strv (tokens);
        }
    }

    public static string[] known_steam_dirs () {
        var home = Environment.get_home_dir ();
        return {
            Path.build_filename (home, ".steam", "debian-installation"),
            Path.build_filename (home, ".steam"),
            Path.build_filename (home, ".local", "share", "steam"),
            Path.build_filename (home, ".local", "share", "Steam"),
            Path.build_filename (home, "snap", "steam", "common", ".local", "share", "Steam"),
            Path.build_filename (home, ".steam", "steam"),
            Path.build_filename (home, ".var", "app", "com.valvesoftware.Steam", ".local", "share", "Steam"),
            Path.build_filename (home, ".var", "app", "com.valvesoftware.Steam", ".local", "share", "steam"),
            Path.build_filename (home, ".var", "app", "com.valvesoftware.Steam", "data", "steam"),
            Path.build_filename (home, ".var", "app", "com.valvesoftware.Steam", "data", "Steam"),
            "/usr/share/steam",
            "/usr/local/share/steam"
        };
    }

    public static UserConfig? detect () {
        foreach (var steam_dir in known_steam_dirs ()) {
            var config = resolve_from_steam_dir (steam_dir);
            if (config != null) return config;
        }
        return null;
    }

    public static UserConfig? resolve_from_steam_dir (string steam_dir) {
        var userdata_dir = Path.build_filename (steam_dir, "userdata");
        if (!FileUtils.test (userdata_dir, FileTest.IS_DIR)) return null;

        var user_ids = list_numeric_children (userdata_dir);
        if (user_ids.size == 0) return null;

        LoginUser? active = null;
        var loginusers_path = Path.build_filename (steam_dir, "config", "loginusers.vdf");
        if (FileUtils.test (loginusers_path, FileTest.EXISTS)) {
            active = read_active_login_user (loginusers_path);
        }

        string selected_id = "";
        if (active != null) {
            var id32 = steamid64_to_steamid32 (active.steamid64);
            if (id32 != "" && user_ids.contains (id32)) selected_id = id32;
        }
        if (selected_id == "") selected_id = user_ids[0];

        var config_dir = Path.build_filename (userdata_dir, selected_id, "config");
        if (!FileUtils.test (config_dir, FileTest.IS_DIR)) return null;

        var config = new UserConfig ();
        config.steam_dir = steam_dir;
        config.userdata_dir = userdata_dir;
        config.config_dir = config_dir;
        config.shortcuts_vdf_path = Path.build_filename (config_dir, "shortcuts.vdf");
        if (active != null && selected_id == steamid64_to_steamid32 (active.steamid64)) {
            config.account_name = active.account_name;
            config.persona_name = active.persona_name;
        }
        return config;
    }

    public static UserConfig? resolve_from_selected_folder (string selected_path) {
        var normalized = Utils.normalize_dir_path (selected_path);
        if (Path.get_basename (normalized) == "userdata") {
            return resolve_from_userdata_dir (normalized);
        }

        var userdata = Path.build_filename (normalized, "userdata");
        if (FileUtils.test (userdata, FileTest.IS_DIR)) {
            return resolve_from_steam_dir (normalized);
        }

        if (Path.get_basename (normalized) == "config") {
            var user_dir = Path.get_dirname (normalized);
            var user_id = Path.get_basename (user_dir);
            if (is_numeric (user_id)) {
                var config = new UserConfig ();
                config.steam_dir = Path.get_dirname (Path.get_dirname (user_dir));
                config.userdata_dir = Path.get_dirname (user_dir);
                config.config_dir = normalized;
                config.shortcuts_vdf_path = Path.build_filename (normalized, "shortcuts.vdf");
                return config;
            }
        }

        return null;
    }

    private static UserConfig? resolve_from_userdata_dir (string userdata_dir) {
        var user_ids = list_numeric_children (userdata_dir);
        if (user_ids.size == 0) return null;
        var config_dir = Path.build_filename (userdata_dir, user_ids[0], "config");
        if (!FileUtils.test (config_dir, FileTest.IS_DIR)) return null;

        var config = new UserConfig ();
        config.steam_dir = Path.get_dirname (userdata_dir);
        config.userdata_dir = userdata_dir;
        config.config_dir = config_dir;
        config.shortcuts_vdf_path = Path.build_filename (config_dir, "shortcuts.vdf");
        return config;
    }

    private static Gee.ArrayList<string> list_numeric_children (string dir_path) {
        var result = new Gee.ArrayList<string> ();
        try {
            var dir = Dir.open (dir_path);
            string? name;
            while ((name = dir.read_name ()) != null) {
                if (is_numeric (name) && FileUtils.test (Path.build_filename (dir_path, name), FileTest.IS_DIR)) {
                    result.add (name);
                }
            }
        } catch (FileError e) {
            warning ("Failed to read Steam userdata directory %s: %s", dir_path, e.message);
        }
        result.sort ((a, b) => strcmp (a, b));
        return result;
    }

    private static LoginUser? read_active_login_user (string path) {
        string contents;
        try {
            FileUtils.get_contents (path, out contents);
        } catch (FileError e) {
            warning ("Failed to read Steam login users %s: %s", path, e.message);
            return null;
        }

        try {
            var parser = new TextParser (contents);
            var root = parser.parse ();
            var users = root.children.has_key ("users") ? root.children["users"] : null;
            if (users == null) return null;

            LoginUser? fallback = null;
            foreach (var entry in users.children.entries) {
                var user = login_user_from_node (entry.key, entry.value);
                if (user == null) continue;
                if (user.most_recent) return user;
                if (fallback == null) fallback = user;
            }
            return fallback;
        } catch (Error e) {
            warning ("Failed to parse Steam login users %s: %s", path, e.message);
            return null;
        }
    }

    private static LoginUser? login_user_from_node (string steamid64, TextNode node) {
        if (!is_numeric (steamid64)) return null;
        var user = new LoginUser ();
        user.steamid64 = steamid64;
        user.account_name = text_member (node, "accountname");
        user.persona_name = text_member (node, "personaname");
        user.most_recent = text_member (node, "mostrecent") == "1";
        return user;
    }

    private static string text_member (TextNode node, string key) {
        return node.children.has_key (key) ? node.children[key].value : "";
    }

    private static string steamid64_to_steamid32 (string steamid64) {
        if (!is_numeric (steamid64)) return "";
        int64 value;
        if (!int64.try_parse (steamid64, out value)) return "";
        var account_id = value - 76561197960265728L;
        if (account_id < 0) return "";
        return account_id.to_string ();
    }

    private static bool is_numeric (string value) {
        if (value == "") return false;
        for (int i = 0; i < value.length; i++) {
            if (!value[i].isdigit ()) return false;
        }
        return true;
    }

}
