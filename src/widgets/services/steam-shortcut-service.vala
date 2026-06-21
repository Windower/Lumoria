namespace Lumoria.Widgets.Services {

    public class SteamShortcutService : Object {
        private const string IDENTITY_PREFIX = "net.windower.Lumoria";
        private const string IDENTITY_ARG = "--lumoria-shortcut-id";
        private const string ICON_RESOURCE = "/net/windower/Lumoria/icons/hicolor/512x512/apps/net.windower.Lumoria.png";

        private string ensure_icon_on_disk () throws Error {
            var icon_path = Path.build_filename (Utils.data_dir (), "icons", "net.windower.Lumoria.png");
            if (FileUtils.test (icon_path, FileTest.EXISTS)) return icon_path;
            DirUtils.create_with_parents (Path.get_dirname (icon_path), 0755);
            var bytes = resources_lookup_data (ICON_RESOURCE, ResourceLookupFlags.NONE);
            FileUtils.set_data (icon_path, bytes.get_data ());
            return icon_path;
        }

        public Utils.SteamConfig.UserConfig? detect_config () {
            return Utils.SteamConfig.detect ();
        }

        public Utils.SteamConfig.UserConfig? resolve_config_from_folder (string folder) {
            return Utils.SteamConfig.resolve_from_selected_folder (folder);
        }

        public bool has_steam_shortcut (Models.PrefixEntry entry, string entrypoint_id) {
            return entry.steam_shortcut_app_ids.has_key (entrypoint_id);
        }

        public void install_steam_shortcut (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target,
            Utils.SteamConfig.UserConfig config
        ) throws Error {
            var root = load_shortcuts_file (config.shortcuts_vdf_path);
            var shortcuts = Utils.SteamVdf.shortcuts_object (root);
            var identity = shortcut_identity (entry, target.id);

            var values = shortcut_values_except_identity (shortcuts, identity);
            var shortcut = build_shortcut (entry, target, config, values);
            values.add (shortcut);
            replace_shortcuts (shortcuts, values);
            save_shortcuts_file (config.shortcuts_vdf_path, root);

            entry.steam_shortcut_app_ids[target.id] = shortcut.int32_member ("appid").to_string ();
        }

        public void remove_steam_shortcut (
            Models.PrefixEntry entry,
            string entrypoint_id,
            Utils.SteamConfig.UserConfig config
        ) throws Error {
            if (!FileUtils.test (config.shortcuts_vdf_path, FileTest.EXISTS)) {
                entry.steam_shortcut_app_ids.unset (entrypoint_id);
                return;
            }

            var root = load_shortcuts_file (config.shortcuts_vdf_path);
            var shortcuts = Utils.SteamVdf.shortcuts_object (root);
            var identity = shortcut_identity (entry, entrypoint_id);
            var values = shortcut_values_except_identity (shortcuts, identity);
            replace_shortcuts (shortcuts, values);
            save_shortcuts_file (config.shortcuts_vdf_path, root);
            entry.steam_shortcut_app_ids.unset (entrypoint_id);
        }

        private Utils.SteamVdf.Value build_shortcut (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target,
            Utils.SteamConfig.UserConfig config,
            Gee.ArrayList<Utils.SteamVdf.Value> existing
        ) throws Error {
            var identity = shortcut_identity (entry, target.id);
            var appid = generate_available_appid (identity, existing);
            var command = build_launch_command (entry, target.id, identity, config);
            var icon_path = ensure_icon_on_disk ();
            return Utils.SteamVdf.build_shortcut (
                appid,
                build_shortcut_label (entry, target),
                command.exe,
                command.start_dir,
                icon_path,
                command.launch_options
            );
        }

        private class LaunchCommand : Object {
            public string exe { get; set; default = ""; }
            public string start_dir { get; set; default = ""; }
            public string launch_options { get; set; default = ""; }
        }

        private LaunchCommand build_launch_command (
            Models.PrefixEntry entry,
            string entrypoint_id,
            string identity,
            Utils.SteamConfig.UserConfig config
        ) {
            var cmd = new LaunchCommand ();
            cmd.start_dir = Utils.double_quote (Environment.get_home_dir ());
            var args = "launch %s --entrypoint %s %s %s".printf (
                Utils.shell_quote (entry.id),
                Utils.shell_quote (entrypoint_id),
                IDENTITY_ARG,
                Utils.shell_quote (identity)
            );

            if (Utils.EnvironmentInfo.is_flatpak ()) {
                if (config.steam_dir.contains (".var/app/com.valvesoftware.Steam")) {
                    cmd.exe = Utils.double_quote ("/usr/bin/flatpak-spawn");
                    cmd.launch_options = "--host /usr/bin/flatpak run %s %s".printf (Config.APP_ID, args);
                } else {
                    cmd.exe = Utils.double_quote ("/usr/bin/flatpak");
                    cmd.launch_options = "run %s %s".printf (Config.APP_ID, args);
                }
                return cmd;
            }

            var exe = Utils.current_executable_path ();
            cmd.exe = Utils.double_quote (exe != null && exe != "" ? exe : "lumoria");
            cmd.launch_options = args;
            return cmd;
        }

        private Utils.SteamVdf.Value load_shortcuts_file (string path) throws Error {
            if (!FileUtils.test (path, FileTest.EXISTS)) {
                return Utils.SteamVdf.empty_shortcuts_file ();
            }
            uint8[] data;
            FileUtils.get_data (path, out data);
            if (data.length == 0) return Utils.SteamVdf.empty_shortcuts_file ();
            return Utils.SteamVdf.parse (data);
        }

        private void save_shortcuts_file (string path, Utils.SteamVdf.Value root) throws Error {
            var data = Utils.SteamVdf.serialize (root);
            var file = File.new_for_path (path);
            var parent = file.get_parent ();
            if (parent != null) {
                var parent_path = parent.get_path ();
                if (parent_path != null && parent_path != "") {
                    DirUtils.create_with_parents (parent_path, 0755);
                }
            }

            if (FileUtils.test (path, FileTest.EXISTS)) {
                var backup = File.new_for_path ("%s.bak".printf (path));
                file.copy (backup, FileCopyFlags.OVERWRITE);
            }

            var tmp_path = "%s.tmp".printf (path);
            var tmp = File.new_for_path (tmp_path);
            var stream = tmp.replace (null, false, FileCreateFlags.REPLACE_DESTINATION);
            size_t written;
            stream.write_all (data, out written);
            stream.close ();
            tmp.move (file, FileCopyFlags.OVERWRITE);
        }

        private Gee.ArrayList<Utils.SteamVdf.Value> shortcut_values_except_identity (
            Utils.SteamVdf.Value shortcuts,
            string identity
        ) {
            var values = new Gee.ArrayList<Utils.SteamVdf.Value> ();
            foreach (var entry in shortcuts.object_value.entries) {
                if (entry.value.kind != Utils.SteamVdf.ValueKind.OBJECT) continue;
                if (shortcut_matches_identity (entry.value, identity)) continue;
                values.add (entry.value);
            }
            return values;
        }

        private void replace_shortcuts (
            Utils.SteamVdf.Value shortcuts,
            Gee.ArrayList<Utils.SteamVdf.Value> values
        ) {
            shortcuts.object_value.clear ();
            for (int i = 0; i < values.size; i++) {
                shortcuts.object_value[i.to_string ()] = values[i];
            }
        }

        private static bool shortcut_matches_identity (Utils.SteamVdf.Value shortcut, string identity) {
            return shortcut.string_member ("LaunchOptions").contains ("%s %s".printf (IDENTITY_ARG, Utils.shell_quote (identity))) ||
                shortcut.string_member ("LaunchOptions").contains ("%s=%s".printf (IDENTITY_ARG, identity));
        }

        private static int32 generate_available_appid (
            string identity,
            Gee.ArrayList<Utils.SteamVdf.Value> existing
        ) {
            for (int salt = 0; salt < 1000; salt++) {
                var seed = salt == 0 ? identity : "%s:%d".printf (identity, salt);
                var candidate = appid_for_seed (seed);
                if (!appid_exists (existing, candidate)) return candidate;
            }
            return appid_for_seed ("%s:fallback".printf (identity));
        }

        private static bool appid_exists (Gee.ArrayList<Utils.SteamVdf.Value> existing, int32 appid) {
            foreach (var shortcut in existing) {
                if (shortcut.int32_member ("appid") == appid) return true;
            }
            return false;
        }

        public static int32 appid_for_seed (string seed) {
            var top = Utils.crc32 (seed.data) | 0x80000000U;
            return (int32) top;
        }

        private static string shortcut_identity (Models.PrefixEntry entry, string entrypoint_id) {
            return "%s:%s:%s".printf (IDENTITY_PREFIX, entry.id, entrypoint_id);
        }

        private string build_shortcut_label (Models.PrefixEntry entry, Runtime.LaunchTarget target) {
            var prefix_label = "%s (%s)".printf (Config.APP_NAME, entry.display_name ());
            return "%s - %s".printf (prefix_label, target.selector_label);
        }

    }
}
