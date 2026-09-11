namespace Lumoria.Models {

    public class LaunchDisplay : Object {
        public string icon { get; set; default = ""; }
        public string nickname { get; set; default = ""; }
        public string shortcut_icon { get; set; default = ""; }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            var safe_icon = FfxiIconCatalog.sanitize_slot_key (icon);
            var safe_nick = Utils.sanitize_user_text (nickname);
            var safe_shortcut = FfxiIconCatalog.sanitize_shortcut_icon (shortcut_icon);
            if (safe_icon != "") obj.set_string_member ("icon", safe_icon);
            if (safe_nick != "") obj.set_string_member ("nickname", safe_nick);
            if (safe_shortcut != "") obj.set_string_member ("shortcut_icon", safe_shortcut);
            return obj;
        }

        public static LaunchDisplay from_json (Json.Object obj) {
            var d = new LaunchDisplay ();
            d.icon = FfxiIconCatalog.sanitize_slot_key (json_string (obj, "icon"));
            d.nickname = Utils.sanitize_user_text (json_string (obj, "nickname"));
            d.shortcut_icon = FfxiIconCatalog.sanitize_shortcut_icon (json_string (obj, "shortcut_icon"));
            return d;
        }

        public bool is_empty () {
            return FfxiIconCatalog.sanitize_slot_key (icon) == ""
                && Utils.sanitize_user_text (nickname) == ""
                && FfxiIconCatalog.sanitize_shortcut_icon (shortcut_icon) == "";
        }

        public LaunchDisplay copy () {
            var d = new LaunchDisplay ();
            d.icon = icon;
            d.nickname = nickname;
            d.shortcut_icon = shortcut_icon;
            return d;
        }
    }

    public class AppliedComponentRecord : Object {
        public string version { get; set; default = ""; }
        public Gee.ArrayList<string> installed_files {
            get; owned set; default = new Gee.ArrayList<string> ();
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            obj.set_string_member ("version", version);
            obj.set_array_member ("installed_files", json_string_list_array (installed_files));
            return obj;
        }

        public static AppliedComponentRecord from_json (Json.Object obj) throws Error {
            var r = new AppliedComponentRecord ();
            r.version = json_string (obj, "version");
            r.installed_files = json_string_array (obj, "installed_files");
            return r;
        }

        public AppliedComponentRecord copy () {
            var r = new AppliedComponentRecord ();
            r.version = version;
            r.installed_files.add_all (installed_files);
            return r;
        }
    }

    public class PrefixRunnerState : Object {
        public string runner_id { get; set; default = ""; }
        public string variant_id { get; set; default = ""; }
        public string resolved_version { get; set; default = ""; }

        public bool matches (string runner_id, string variant_id, string resolved_version) {
            return this.runner_id == runner_id
                && this.variant_id == variant_id
                && this.resolved_version == resolved_version;
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            if (runner_id != "") obj.set_string_member ("runner_id", runner_id);
            if (variant_id != "") obj.set_string_member ("variant_id", variant_id);
            if (resolved_version != "") obj.set_string_member ("resolved_version", resolved_version);
            return obj;
        }

        public static PrefixRunnerState from_json (Json.Object obj) throws Error {
            var s = new PrefixRunnerState ();
            s.runner_id = json_string (obj, "runner_id");
            s.variant_id = json_string (obj, "variant_id");
            s.resolved_version = json_string (obj, "resolved_version");
            return s;
        }

        public PrefixRunnerState copy () {
            var s = new PrefixRunnerState ();
            s.runner_id = runner_id;
            s.variant_id = variant_id;
            s.resolved_version = resolved_version;
            return s;
        }
    }

    public class PrefixPostInstallManifest : Object {
        public string id { get; set; default = ""; }
        public string original_path { get; set; default = ""; }
        public string original_uri { get; set; default = ""; }
        public string manifest_id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string last_run_status { get; set; default = ""; }
        public string last_run_at { get; set; default = ""; }

        public static string generate_id () {
            return Utils.random_id ("script");
        }

        public void ensure_id () {
            if (id == "") id = generate_id ();
        }

        public static string path_for (string prefix_root, string instance_id) {
            var token = Utils.sanitize_filename_token (instance_id);
            if (token == "") token = "post-install";
            return Path.build_filename (prefix_root, "lumoria", "post-install", token + ".json");
        }

        public string stored_path (string prefix_root) {
            return path_for (prefix_root, id);
        }

        public string[] file_candidates (string prefix_root) {
            string[] paths = {};
            if (prefix_root != "" && id != "") {
                paths += stored_path (prefix_root);
            }
            if (prefix_root != "" && manifest_id != "" && manifest_id != id) {
                var legacy = path_for (prefix_root, manifest_id);
                if (legacy != stored_path (prefix_root)) paths += legacy;
            }
            if (original_path != "") paths += original_path;
            return paths;
        }

        public string? locate_file (string prefix_root) {
            foreach (var path in file_candidates (prefix_root)) {
                if (FileUtils.test (path, FileTest.IS_REGULAR)) return path;
            }
            return null;
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            if (id != "") obj.set_string_member ("id", id);
            if (original_path != "") obj.set_string_member ("original_path", original_path);
            if (original_uri != "") obj.set_string_member ("original_uri", original_uri);
            if (manifest_id != "") obj.set_string_member ("manifest_id", manifest_id);
            if (name != "") obj.set_string_member ("name", name);
            if (last_run_status != "") obj.set_string_member ("last_run_status", last_run_status);
            if (last_run_at != "") obj.set_string_member ("last_run_at", last_run_at);
            return obj;
        }

        public static PrefixPostInstallManifest from_json (Json.Object obj) {
            var s = new PrefixPostInstallManifest ();
            s.id = json_string (obj, "id");
            s.original_path = json_string (obj, "original_path");
            s.original_uri = json_string (obj, "original_uri");
            s.manifest_id = json_string (obj, "manifest_id");
            s.name = json_string (obj, "name");
            s.last_run_status = json_string (obj, "last_run_status");
            s.last_run_at = json_string (obj, "last_run_at");
            return s;
        }

        public PrefixPostInstallManifest copy () {
            var s = new PrefixPostInstallManifest ();
            s.id = id;
            s.original_path = original_path;
            s.original_uri = original_uri;
            s.manifest_id = manifest_id;
            s.name = name;
            s.last_run_status = last_run_status;
            s.last_run_at = last_run_at;
            return s;
        }
    }
}
