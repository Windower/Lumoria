namespace Lumoria.Application {

    internal enum ConfigKind {
        PREFERENCES,
        PREFIXES,
        APP_STATE;

        public string path () {
            switch (this) {
                case PREFERENCES: return Utils.preferences_path ();
                case PREFIXES: return Utils.prefix_registry_path ();
                default: return Utils.app_state_path ();
            }
        }
    }

    internal class ConfigFileCheck : Object {
        public ConfigKind kind { get; set; default = ConfigKind.PREFERENCES; }
        public string path { get; set; default = ""; }
        public int version { get; set; default = 0; }
        public bool exists { get; set; default = false; }
        public bool needed { get; set; default = false; }
        public bool incompatible { get; set; default = false; }
    }

    internal class MigrationCheck : Object {
        public Gee.ArrayList<ConfigFileCheck> files {
            get; owned set; default = new Gee.ArrayList<ConfigFileCheck> ();
        }
        public bool needed { get; set; default = false; }
        public bool incompatible { get; set; default = false; }

        public ConfigFileCheck? file (ConfigKind kind) {
            foreach (var file in files) {
                if (file.kind == kind) return file;
            }
            return null;
        }
    }

    public class MigrationService : Object {
        private static ConfigKind[] APPLY_ORDER = {
            ConfigKind.PREFERENCES,
            ConfigKind.PREFIXES,
            ConfigKind.APP_STATE
        };

        /* Every 0.1.x release wrote this runner id and no format_version; v1 files only ever carry the new one. */
        private const string LEGACY_GE_PROTON_ID = "proton-ge";
        private const string GE_PROTON_ID = "ge-proton";

        public static void ensure_current () throws Error {
            Models.ManifestStore.apply_startup_overlay ();
            var service = new MigrationService ();
            var pending = service.check ();
            if (pending.incompatible) {
                throw new LumoriaError.FAILED (incompatible_message (pending));
            }
            if (pending.needed) service.apply (pending);
        }

        private static void rename_legacy_runner_dir () {
            var src = Path.build_filename (Utils.runner_dir (), LEGACY_GE_PROTON_ID);
            var dest = Path.build_filename (Utils.runner_dir (), GE_PROTON_ID);
            if (!FileUtils.test (src, FileTest.IS_DIR)) return;
            if (FileUtils.test (dest, FileTest.EXISTS)) return;
            try {
                File.new_for_path (src).move (File.new_for_path (dest), FileCopyFlags.NONE);
            } catch (Error e) {
                warning ("Failed to rename runner dir %s -> %s: %s", src, dest, e.message);
            }
        }

        private static void rename_legacy_runner_id (Json.Object obj) {
            if (Models.json_string (obj, "runner_id") == LEGACY_GE_PROTON_ID) {
                obj.set_string_member ("runner_id", GE_PROTON_ID);
            }
        }

        private MigrationCheck check () {
            var result = new MigrationCheck ();
            var current = Config.CONFIG_FORMAT_VERSION;
            foreach (var kind in APPLY_ORDER) {
                var file = inspect (kind, current);
                result.files.add (file);
                if (file.needed) result.needed = true;
                if (file.incompatible) result.incompatible = true;
            }
            return result;
        }

        private void apply (MigrationCheck check) throws Error {
            if (check.incompatible) {
                throw new LumoriaError.FAILED (incompatible_message (check));
            }
            if (!check.needed) return;

            var current = Config.CONFIG_FORMAT_VERSION;
            foreach (var kind in APPLY_ORDER) {
                var file = check.file (kind);
                if (file == null || !file.needed) continue;
                var version = file.version;
                if (version == 0) rename_legacy_runner_dir ();
                while (version < current) {
                    backup_file (file.path, version);
                    apply_step (kind, version, file.path);
                    version++;
                }
            }
        }

        /* A corrupt file is quarantined here so the loaders downstream fall back to defaults instead of failing startup. */
        private static ConfigFileCheck inspect (ConfigKind kind, int current) {
            var file = new ConfigFileCheck ();
            file.kind = kind;
            file.path = kind.path ();
            file.exists = FileUtils.test (file.path, FileTest.IS_REGULAR);
            if (!file.exists) return file;

            int version;
            try {
                version = format_version_of (Models.parse_file_object (file.path));
            } catch (Error e) {
                warning ("Config %s is unreadable, quarantining: %s", file.path, e.message);
                Utils.quarantine_broken_file (file.path);
                file.exists = false;
                return file;
            }
            file.version = version;
            file.needed = version < current;
            file.incompatible = version > current;
            return file;
        }

        private static void backup_file (string path, int from_version) throws Error {
            var dest = "%s.v%d".printf (path, from_version);
            if (FileUtils.test (dest, FileTest.IS_REGULAR)) return;
            Utils.copy_path (path, dest);
        }

        private delegate void MigrationStep (string path) throws Error;

        private void apply_step (ConfigKind kind, int from_version, string path) throws Error {
            var step = step_for (kind, from_version);
            if (step == null) {
                throw new LumoriaError.FAILED (
                    _("No migration step from config format %d to %d").printf (
                        from_version,
                        from_version + 1
                    )
                );
            }
            step (path);
        }

        private MigrationStep? step_for (ConfigKind kind, int from_version) {
            if (from_version != 0) return null;
            switch (kind) {
                case ConfigKind.PREFERENCES:
                    return apply_preferences_v0_v1;
                case ConfigKind.PREFIXES:
                    return apply_prefixes_v0_v1;
                case ConfigKind.APP_STATE:
                    return apply_app_state_v0_v1;
            }
            return null;
        }

        private void apply_preferences_v0_v1 (string path) throws Error {
            var obj = Models.parse_file_object (path);
            rename_legacy_runner_id (obj);
            if (obj.has_member ("logging")) {
                var log_obj = obj.get_object_member ("logging");
                if (!log_obj.has_member ("keep_files") && log_obj.has_member ("mode")) {
                    log_obj.set_boolean_member (
                        "keep_files",
                        Utils.Preferences.logging_mode_keeps_files (log_obj.get_string_member ("mode"))
                    );
                }
                if (log_obj.has_member ("mode")) log_obj.remove_member ("mode");
            }
            stamp (obj, 1);
            write_object (path, obj);
        }

        private void apply_app_state_v0_v1 (string path) throws Error {
            var obj = Models.parse_file_object (path);
            if (!obj.has_member ("page") && obj.has_member ("workspace")) {
                obj.set_string_member ("page", obj.get_string_member ("workspace"));
            }
            if (obj.has_member ("workspace")) obj.remove_member ("workspace");
            if (obj.has_member ("page")) {
                var page = obj.get_string_member ("page");
                if (page == "favorites") obj.set_string_member ("page", "home");
                else if (page == "install") obj.set_string_member ("page", "prefix");
            }
            stamp (obj, 1);
            write_object (path, obj);
        }

        private void apply_prefixes_v0_v1 (string path) throws Error {
            var root = Models.parse_file_object (path);
            if (root.has_member ("prefixes")) {
                var arr = root.get_array_member ("prefixes");
                for (uint i = 0; i < arr.get_length (); i++) {
                    var prefix = arr.get_object_element (i);
                    rename_legacy_runner_id (prefix);
                    if (prefix.has_member ("runner_state")) {
                        rename_legacy_runner_id (prefix.get_object_member ("runner_state"));
                    }
                }
            }
            var reg = new Models.PrefixRegistry ();
            reg.prefixes = Models.parse_json_array<Models.PrefixEntry> (
                root, "prefixes", (o) => parse_prefix_v0 (o)
            );
            reg.default_prefix_id = Models.json_string (root, "default_prefix_id");
            if (reg.prefixes.size > 1) Utils.Preferences.instance ().show_sidebar = true;
            backfill_installer_ids (reg);
            backfill_runner_state (reg);
            migrate_duplicate_custom_entry_ids (reg);
            backfill_portal_path_refs (reg);
            migrate_post_install_manifests (reg);
            snapshot_large_address_aware (reg);
            reg.save (path);
        }

        private static Models.PrefixEntry parse_prefix_v0 (Json.Object obj) throws Error {
            var entry = Models.PrefixEntry.from_json (obj);
            if (entry.post_install_manifests.size > 0) return entry;

            if (obj.has_member ("post_install_specs")) {
                entry.post_install_manifests = Models.parse_json_array<Models.PrefixPostInstallManifest> (
                    obj, "post_install_specs", (o) => parse_post_install_v0 (o)
                );
            } else if (obj.has_member ("post_install_spec")) {
                entry.post_install_manifests.add (
                    parse_post_install_v0 (obj.get_object_member ("post_install_spec"))
                );
            }
            return entry;
        }

        private static Models.PrefixPostInstallManifest parse_post_install_v0 (Json.Object obj) {
            var meta = Models.PrefixPostInstallManifest.from_json (obj);
            if (meta.manifest_id == "") meta.manifest_id = Models.json_string (obj, "spec_id");
            return meta;
        }

        private static void backfill_installer_ids (Models.PrefixRegistry reg) {
            foreach (var prefix in reg.prefixes) {
                if (prefix.installer_id.strip () != "") continue;
                prefix.installer_id = Models.ManifestRepository.shared ().default_installer_id ();
            }
        }

        private static void backfill_runner_state (Models.PrefixRegistry reg) {
            foreach (var prefix in reg.prefixes) {
                if (prefix.runner_state != null) continue;
                var state = new Models.PrefixRunnerState ();
                state.runner_id = prefix.runner_id;
                state.variant_id = prefix.variant_id;
                if (!Models.ToolVersionRef.is_deferred (prefix.runner_version)) {
                    state.resolved_version = prefix.runner_version;
                }
                prefix.runner_state = state;
            }
        }

        private static void migrate_duplicate_custom_entry_ids (Models.PrefixRegistry reg) {
            foreach (var prefix in reg.prefixes) {
                migrate_duplicate_custom_entry_ids_for_prefix (prefix);
            }
        }

        private static void migrate_duplicate_custom_entry_ids_for_prefix (Models.PrefixEntry prefix) {
            if (prefix.custom_entrypoints.size < 2) return;

            var seen_ids = new Gee.HashSet<string> ();
            var used_ids = new Gee.HashSet<string> ();
            foreach (var ep in prefix.custom_entrypoints) {
                if (ep.id != "") used_ids.add (ep.id);
            }

            foreach (var ep in prefix.custom_entrypoints) {
                if (!Models.PrefixEntry.is_legacy_custom_entry_id (ep.id)) continue;

                var old_id = ep.id;
                if (!seen_ids.contains (old_id)) {
                    seen_ids.add (old_id);
                    continue;
                }

                var new_id = generate_unique_custom_entry_id (used_ids);
                ep.id = new_id;
                used_ids.add (new_id);
                if (prefix.custom_entrypoint (old_id) == null) {
                    remap_entrypoint_id (prefix, old_id, new_id);
                }
            }
        }

        private static string generate_unique_custom_entry_id (Gee.HashSet<string> used_ids) {
            while (true) {
                var id = Models.PrefixEntry.generate_custom_entry_id ();
                if (!used_ids.contains (id)) return id;
            }
        }

        private static void remap_entrypoint_id (Models.PrefixEntry prefix, string old_id, string new_id) {
            if (prefix.launch_entrypoint_id == old_id) {
                prefix.launch_entrypoint_id = new_id;
            }
            if (prefix.dynamic_launcher_desktop_ids.has_key (old_id)) {
                var desktop_id = prefix.dynamic_launcher_desktop_ids[old_id];
                prefix.dynamic_launcher_desktop_ids.unset (old_id);
                prefix.dynamic_launcher_desktop_ids[new_id] = desktop_id;
            }
            if (prefix.steam_shortcut_app_ids.has_key (old_id)) {
                var app_id = prefix.steam_shortcut_app_ids[old_id];
                prefix.steam_shortcut_app_ids.unset (old_id);
                prefix.steam_shortcut_app_ids[new_id] = app_id;
            }
            if (prefix.launch_display.has_key (old_id)) {
                var display = prefix.launch_display[old_id];
                prefix.launch_display.unset (old_id);
                prefix.launch_display[new_id] = display;
            }
        }

        private static void backfill_portal_path_refs (Models.PrefixRegistry reg) {
            foreach (var prefix in reg.prefixes) {
                if (prefix.path_portal == null) {
                    var portal = Utils.portal_path_ref_from_path_uri (prefix.path, prefix.uri);
                    if (portal != null) prefix.path_portal = portal;
                }

                if (prefix.prelaunch_script_portal == null) {
                    var portal = Utils.portal_path_ref_from_path_uri (prefix.prelaunch_script);
                    if (portal != null) prefix.prelaunch_script_portal = portal;
                }

                foreach (var ep in prefix.custom_entrypoints) {
                    if (ep.exe_portal == null) {
                        var portal = Utils.portal_path_ref_from_path_uri (ep.exe);
                        if (portal != null) ep.exe_portal = portal;
                    }
                    if (ep.prelaunch_script_portal == null) {
                        var portal = Utils.portal_path_ref_from_path_uri (ep.prelaunch_script);
                        if (portal != null) ep.prelaunch_script_portal = portal;
                    }
                }
            }
        }

        private static void migrate_post_install_manifests (Models.PrefixRegistry reg) {
            foreach (var prefix in reg.prefixes) {
                var used_ids = new Gee.HashSet<string> ();
                foreach (var spec in prefix.post_install_manifests) {
                    if (spec.id != "") used_ids.add (spec.id);
                }
                var root = prefix.resolved_path ();
                foreach (var spec in prefix.post_install_manifests) {
                    if (spec.id == "") {
                        do {
                            spec.id = Models.PrefixPostInstallManifest.generate_id ();
                        } while (used_ids.contains (spec.id));
                        used_ids.add (spec.id);
                    }
                    if (root == "" || spec.manifest_id == "") continue;
                    var dest = spec.stored_path (root);
                    if (FileUtils.test (dest, FileTest.IS_REGULAR)) continue;
                    var source = Models.PrefixPostInstallManifest.path_for (root, spec.manifest_id);
                    if (source == dest || !FileUtils.test (source, FileTest.IS_REGULAR)) continue;
                    try {
                        File.new_for_path (source).move (File.new_for_path (dest), FileCopyFlags.NONE);
                    } catch (Error e) {
                        warning (
                            "Failed to migrate post-install %s -> %s: %s",
                            source,
                            dest,
                            e.message
                        );
                    }
                }
            }
        }

        private static void snapshot_large_address_aware (Models.PrefixRegistry reg) {
            var fallback = Utils.Preferences.instance ().large_address_aware;
            foreach (var prefix in reg.prefixes) {
                if (prefix.large_address_aware != null) continue;
                prefix.large_address_aware = prefix.installer_id == Models.InstallerManifest.EMPTY_ID
                    ? false
                    : fallback;
            }
        }

        private static int format_version_of (Json.Object obj) {
            return (int) Models.json_int (obj, "format_version");
        }

        private static void stamp (Json.Object obj, int version) {
            obj.set_int_member ("format_version", version);
        }

        private static void write_object (string path, Json.Object obj) throws Error {
            Utils.write_json_atomic (path, obj);
        }

        private static string incompatible_message (MigrationCheck check) {
            var current = Config.CONFIG_FORMAT_VERSION;
            var parts = "";
            foreach (var file in check.files) {
                if (!file.incompatible) continue;
                if (parts != "") parts += ", ";
                parts += "%s (format %d)".printf (file.path, file.version);
            }
            return _(
                "This configuration was written by a newer Lumoria (supported format %d): %s"
            ).printf (current, parts);
        }
    }
}
