namespace Lumoria.Application {

    public class SteamShortcutService : Object {
        public const string QUICK_LAUNCH_IDENTITY = Config.APP_ID + ":quick-launch";
        private const string IDENTITY_ARG = "--lumoria-shortcut-id";
        private PrefixService prefixes;

        public SteamShortcutService (PrefixService prefixes) {
            this.prefixes = prefixes;
        }

        public Utils.SteamConfig.UserConfig? resolve_config (out bool access_lost) {
            access_lost = false;
            var config = Utils.SteamConfig.detect ();
            if (config != null) return config;

            var saved = Utils.Preferences.instance ().resolved_steam_userdata_dir ();
            if (saved == "") return null;

            config = Utils.SteamConfig.resolve_from_selected_folder (saved);
            access_lost = config == null;
            return config;
        }

        public Utils.SteamConfig.UserConfig? remember_folder (string raw_path, string uri = "") {
            var portal_ref = Utils.portal_path_ref_from_path_uri (raw_path, uri);
            var path = Utils.resolve_user_path (raw_path, portal_ref, uri);
            var config = Utils.SteamConfig.resolve_from_selected_folder (path);
            if (config == null) return null;
            Utils.Preferences.instance ().set_steam_userdata_dir (raw_path, portal_ref);
            return config;
        }

        public string install_quick_launch_shortcut (Utils.SteamConfig.UserConfig config) throws Error {
            var command = build_command (
                "launch --quick %s %s".printf (IDENTITY_ARG, Utils.shell_quote (QUICK_LAUNCH_IDENTITY)),
                config
            );
            return upsert_shortcut (
                config.shortcuts_vdf_path,
                QUICK_LAUNCH_IDENTITY,
                _("Lumoria Quick Launch"),
                ShortcutArtwork.lumoria_path (),
                command
            );
        }

        public void remove_quick_launch_shortcut (Utils.SteamConfig.UserConfig config) throws Error {
            remove_by_identity (config.shortcuts_vdf_path, QUICK_LAUNCH_IDENTITY);
        }

        public void install_steam_shortcut (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target,
            Utils.SteamConfig.UserConfig config
        ) throws Error {
            var identity = shortcut_identity (entry, target.id);
            var command = build_command (
                "launch %s --entrypoint %s %s %s".printf (
                    Utils.shell_quote (entry.id),
                    Utils.shell_quote (target.id),
                    IDENTITY_ARG,
                    Utils.shell_quote (identity)
                ),
                config
            );
            entry.steam_shortcut_app_ids[target.id] = upsert_shortcut (
                config.shortcuts_vdf_path,
                identity,
                target.shortcut_label (entry),
                ShortcutArtwork.path_for (entry, target),
                command
            );
            prefixes.schedule_save ();
        }

        public void remove_steam_shortcut (
            Models.PrefixEntry entry,
            string entrypoint_id,
            Utils.SteamConfig.UserConfig config
        ) throws Error {
            remove_by_identity (config.shortcuts_vdf_path, shortcut_identity (entry, entrypoint_id));
            entry.steam_shortcut_app_ids.unset (entrypoint_id);
            prefixes.schedule_save ();
        }

        /* Replaces whatever shortcut carries identity and returns the appid Steam will use. */
        private string upsert_shortcut (
            string path,
            string identity,
            string label,
            string icon_path,
            LaunchCommand command
        ) throws Error {
            string appid = "";
            mutate_shortcuts (path, (shortcuts) => {
                var values = shortcut_values_except_identity (shortcuts, identity);
                var shortcut = Utils.SteamVdf.build_shortcut (
                    generate_available_appid (identity, values),
                    label,
                    command.exe,
                    command.start_dir,
                    icon_path,
                    command.launch_options
                );
                values.add (shortcut);
                replace_shortcuts (shortcuts, values);
                appid = shortcut.int32_member ("appid").to_string ();
            });
            return appid;
        }

        private void remove_by_identity (string path, string identity) throws Error {
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            mutate_shortcuts (path, (shortcuts) => {
                replace_shortcuts (shortcuts, shortcut_values_except_identity (shortcuts, identity));
            });
        }

        private class LaunchCommand : Object {
            public string exe { get; set; default = ""; }
            public string start_dir { get; set; default = ""; }
            public string launch_options { get; set; default = ""; }
        }

        private LaunchCommand build_command (string args, Utils.SteamConfig.UserConfig config) {
            var cmd = new LaunchCommand ();
            cmd.start_dir = vdf_quoted (Environment.get_home_dir ());
            if (Utils.EnvironmentInfo.is_flatpak ()) {
                if (config.steam_dir.contains (".var/app/com.valvesoftware.Steam")) {
                    cmd.exe = vdf_quoted ("/usr/bin/flatpak-spawn");
                    cmd.launch_options = "--host /usr/bin/flatpak run %s %s".printf (Config.APP_ID, args);
                } else {
                    cmd.exe = vdf_quoted ("/usr/bin/flatpak");
                    cmd.launch_options = "run %s %s".printf (Config.APP_ID, args);
                }
                return cmd;
            }

            cmd.exe = vdf_quoted (Utils.host_lumoria_bin ());
            cmd.launch_options = args;
            return cmd;
        }

        private delegate void ShortcutsMutator (Utils.SteamVdf.Value shortcuts) throws Error;

        private void mutate_shortcuts (string path, owned ShortcutsMutator mutate) throws Error {
            var lock_fd = Utils.acquire_exclusive_lock (path + ".lock", true);
            try {
                var root = load_shortcuts_file (path);
                mutate (Utils.SteamVdf.shortcuts_object (root));
                save_shortcuts_file (path, root);
            } finally {
                Posix.close (lock_fd);
            }
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
            if (FileUtils.test (path, FileTest.EXISTS)) {
                Utils.copy_path (path, "%s.bak".printf (path));
            }

            Utils.write_bytes_atomic (path, data);
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

        private static int32 appid_for_seed (string seed) {
            var top = Utils.crc32 (seed.data) | 0x80000000U;
            return (int32) top;
        }

        private static string shortcut_identity (Models.PrefixEntry entry, string entrypoint_id) {
            return "%s:%s:%s".printf (Config.APP_ID, entry.id, entrypoint_id);
        }

        /* Steam stores exe and StartDir wrapped in double quotes. */
        private static string vdf_quoted (string s) {
            return "\"%s\"".printf (s.replace ("\"", "\\\""));
        }
    }
}
