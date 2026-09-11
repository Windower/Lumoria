namespace Lumoria.Models {

    public enum PrefixVarField {
        ID,
        NAME,
        PATH,
        URI,
        RUNNER_ID,
        RUNNER_VERSION,
        LAUNCHER_ID,
        VARIANT_ID,
        WINE_ARCH,
        WINE_DEBUG,
        SYNC_MODE,
        REGION,
        INSTALLER_ID;

        public static bool parse (string field, out PrefixVarField result) {
            switch (field.strip ()) {
                case "id":             result = ID; return true;
                case "name":           result = NAME; return true;
                case "path":           result = PATH; return true;
                case "uri":            result = URI; return true;
                case "runner_id":      result = RUNNER_ID; return true;
                case "runner_version": result = RUNNER_VERSION; return true;
                case "launcher_id":    result = LAUNCHER_ID; return true;
                case "variant_id":     result = VARIANT_ID; return true;
                case "wine_arch":      result = WINE_ARCH; return true;
                case "wine_debug":     result = WINE_DEBUG; return true;
                case "sync_mode":      result = SYNC_MODE; return true;
                case "region":         result = REGION; return true;
                case "installer_id":   result = INSTALLER_ID; return true;
                default:
                    result = ID;
                    return false;
            }
        }
    }

    public class PrefixEntry : IdentifiedRecord {
        public string path { get; set; default = ""; }
        public string uri { get; set; default = ""; }
        public PortalPathRef? path_portal { get; set; default = null; }
        public string installer_id { get; set; default = ""; }
        public string runner_id { get; set; default = ""; }
        public string runner_version { get; set; default = ToolVersionRef.WIRE_INHERIT; }
        public string launcher_id { get; set; default = ""; }
        public string launch_entrypoint_id { get; set; default = ""; }
        public string variant_id { get; set; default = ""; }
        public string wine_arch { get; set; default = ""; }
        public string wine_debug { get; set; default = ""; }
        public bool? wine_wayland = null;
        public string wayland_primary_monitor { get; set; default = ""; }
        public bool? large_address_aware = null;
        public string sync_mode { get; set; default = ""; }
        public string region { get; set; default = "us"; }
        public string prelaunch_script { get; set; default = ""; }
        public PortalPathRef? prelaunch_script_portal { get; set; default = null; }
        public bool advanced_dxvk { get; set; default = false; }
        public bool dxvk_show_fps { get; set; default = false; }
        public bool dxvk_hide_integrated_graphics { get; set; default = false; }
        public string dxvk_sampler_anisotropy { get; set; default = ""; }
        public string dxvk_max_frame_rate { get; set; default = ""; }
        public string dxvk_sync_interval { get; set; default = ""; }
        public string dxvk_config_custom { get; set; default = ""; }
        public Gee.ArrayList<Entrypoint> custom_entrypoints {
            get; owned set; default = new Gee.ArrayList<Entrypoint> ();
        }
        public Gee.HashMap<string, LaunchDisplay> launch_display {
            get; owned set; default = new Gee.HashMap<string, LaunchDisplay> ();
        }
        public Gee.HashMap<string, string> runtime_env_vars {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
        public Gee.HashMap<string, string> runtime_dll_overrides {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
        public Gee.HashMap<string, RuntimeComponentOverride> runtime_component_overrides {
            get; owned set; default = new Gee.HashMap<string, RuntimeComponentOverride> ();
        }
        public Gee.HashMap<string, string> dynamic_launcher_desktop_ids {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
        public Gee.HashMap<string, string> steam_shortcut_app_ids {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
        public Gee.ArrayList<string> installed_redists {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public Gee.HashMap<string, AppliedComponentRecord> applied_components {
            get; owned set; default = new Gee.HashMap<string, AppliedComponentRecord> ();
        }
        public Gee.ArrayList<string> runner_support_files {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public PrefixRunnerState? runner_state { get; set; default = null; }
        public Gee.ArrayList<PrefixPostInstallManifest> post_install_manifests {
            get; owned set; default = new Gee.ArrayList<PrefixPostInstallManifest> ();
        }

        public PrefixPostInstallManifest? find_post_install_metadata (string instance_id) {
            foreach (var spec in post_install_manifests) {
                if (spec.id == instance_id) return spec;
            }
            return null;
        }

        public bool has_post_install_manifest_id (string manifest_id) {
            if (manifest_id == "") return false;
            foreach (var spec in post_install_manifests) {
                if (spec.manifest_id == manifest_id) return true;
            }
            return false;
        }

        public string var_field (PrefixVarField field) {
            switch (field) {
                case ID:             return id;
                case NAME:           return name;
                case PATH:           return resolved_path ();
                case URI:            return uri;
                case RUNNER_ID:      return Utils.Preferences.effective_runner_id (runner_id);
                case RUNNER_VERSION: return runner_version;
                case LAUNCHER_ID:    return launcher_id;
                case VARIANT_ID:     return variant_id;
                case WINE_ARCH:      return wine_arch;
                case WINE_DEBUG:     return wine_debug;
                case SYNC_MODE:      return sync_mode;
                case REGION:         return region;
                case INSTALLER_ID:   return installer_id;
            }
            return "";
        }

        public string resolved_path () {
            return Utils.resolve_user_path (path, path_portal, uri);
        }

        public bool needs_grant () {
            return !FileUtils.test (resolved_path (), FileTest.IS_DIR);
        }

        public bool has_menu_shortcut (string entrypoint_id) {
            return dynamic_launcher_desktop_ids.has_key (entrypoint_id);
        }

        public bool has_steam_shortcut (string entrypoint_id) {
            return steam_shortcut_app_ids.has_key (entrypoint_id);
        }

        public RuntimeComponentOverride ensure_component_override (string component_id) {
            if (runtime_component_overrides.has_key (component_id)) {
                return runtime_component_overrides[component_id];
            }
            var ov = new RuntimeComponentOverride ();
            runtime_component_overrides[component_id] = ov;
            return ov;
        }

        public void apply_component_enabled (string component_id, bool? enabled) {
            if (enabled == null) {
                if (!runtime_component_overrides.has_key (component_id)) return;
                runtime_component_overrides[component_id].enabled = null;
                prune_component_override (component_id);
                return;
            }
            ensure_component_override (component_id).enabled = enabled;
        }

        public void apply_component_version (string component_id, string version) {
            if (ToolVersionRef.is_inherit (version)) {
                if (!runtime_component_overrides.has_key (component_id)) return;
                runtime_component_overrides[component_id].version = "";
                prune_component_override (component_id);
                return;
            }
            ensure_component_override (component_id).version = version.strip ();
        }

        private void prune_component_override (string component_id) {
            if (!runtime_component_overrides.has_key (component_id)) return;
            if (runtime_component_overrides[component_id].is_empty ()) {
                runtime_component_overrides.unset (component_id);
            }
        }

        public string display_icon (string action_id, string fallback = "") {
            var meta = display_for (action_id);
            if (meta != null && meta.icon != "") {
                var key = FfxiIconCatalog.sanitize_slot_key (meta.icon);
                if (key != "") return key;
            }
            return FfxiIconCatalog.sanitize_slot_key (fallback);
        }

        public string display_nickname (string action_id) {
            if (is_custom_entry_id (action_id)) return "";
            var meta = display_for (action_id);
            return meta != null ? Utils.sanitize_user_text (meta.nickname) : "";
        }

        public bool uses_launch_icon_for_shortcut (string action_id) {
            var meta = display_for (action_id);
            return meta == null || meta.shortcut_icon != IconSlots.LUMORIA;
        }

        public string shortcut_icon_preference (string action_id) {
            var meta = display_for (action_id);
            return meta != null ? meta.shortcut_icon : "";
        }

        public void apply_launch_display (
            string action_id,
            string icon,
            string nickname,
            string shortcut_icon = ""
        ) {
            if (action_id == "") return;
            var meta = display_for (action_id) ?? new LaunchDisplay ();
            meta.icon = FfxiIconCatalog.sanitize_slot_key (icon);
            meta.nickname = is_custom_entry_id (action_id) ? "" : Utils.sanitize_user_text (nickname);
            meta.shortcut_icon = FfxiIconCatalog.sanitize_shortcut_icon (shortcut_icon);
            if (meta.is_empty ()) {
                launch_display.unset (action_id);
                return;
            }
            launch_display[action_id] = meta;
        }

        private LaunchDisplay? display_for (string action_id) {
            return launch_display.get (action_id);
        }

        public void set_runner_identity (string runner_id, string variant_id) {
            if (this.runner_id == runner_id && this.variant_id == variant_id) return;
            this.runner_id = runner_id;
            this.variant_id = variant_id;
            if (runner_state == null) return;
            if (runner_state.runner_id == runner_id
                && (runner_state.variant_id == variant_id || runner_state.variant_id == "")) {
                return;
            }
            runner_state = null;
        }

        public string display_name () {
            if (name != "") return name;
            var p = resolved_path ();
            return Path.get_basename (p != "" ? p : path);
        }

        public Entrypoint? custom_entrypoint (string id) {
            if (id == "") return null;
            foreach (var ep in custom_entrypoints) {
                if (ep.id == id) return ep;
            }
            return null;
        }

        public string unique_custom_entry_id () {
            var id = generate_custom_entry_id ();
            while (custom_entrypoint (id) != null) {
                id = generate_custom_entry_id ();
            }
            return id;
        }

        private const string CUSTOM_ENTRY_ID_KIND = "custom";
        private const string CUSTOM_ENTRY_ID_PREFIX = CUSTOM_ENTRY_ID_KIND + "-";

        public static string generate_custom_entry_id () {
            return Utils.random_id (CUSTOM_ENTRY_ID_KIND);
        }

        public static bool is_custom_entry_id (string id) {
            return id.has_prefix (CUSTOM_ENTRY_ID_PREFIX);
        }

        public static bool is_legacy_custom_entry_id (string id) {
            if (!id.has_prefix (CUSTOM_ENTRY_ID_PREFIX) || id.length != 39) return false;
            for (int i = CUSTOM_ENTRY_ID_PREFIX.length; i < id.length; i++) {
                var c = id[i];
                if (!((c >= '0' && c <= '9') ||
                      (c >= 'a' && c <= 'f') ||
                      (c >= 'A' && c <= 'F'))) {
                    return false;
                }
            }
            return true;
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            obj.set_string_member ("id", id);
            obj.set_string_member ("name", Utils.sanitize_user_text (name));
            obj.set_string_member ("path", path);
            if (uri != "") obj.set_string_member ("uri", uri);
            if (path_portal != null && !path_portal.is_empty ()) {
                obj.set_object_member ("path_portal", path_portal.to_json ());
            }
            obj.set_string_member ("installer_id", installer_id);
            obj.set_string_member ("runner_id", runner_id);
            obj.set_string_member ("runner_version", runner_version);
            if (launcher_id != "") obj.set_string_member ("launcher_id", launcher_id);
            if (launch_entrypoint_id != "") obj.set_string_member ("launch_entrypoint_id", launch_entrypoint_id);
            if (variant_id != "") obj.set_string_member ("variant_id", variant_id);
            if (wine_arch != "") obj.set_string_member ("wine_arch", wine_arch);
            if (wine_debug != "") obj.set_string_member ("wine_debug", wine_debug);
            if (wine_wayland != null) obj.set_boolean_member ("wine_wayland", (bool) wine_wayland);
            if (wayland_primary_monitor != "") obj.set_string_member ("wayland_primary_monitor", wayland_primary_monitor);
            if (large_address_aware != null) obj.set_boolean_member (InstallerPatch.SETTING_LARGE_ADDRESS_AWARE, (bool) large_address_aware);
            if (sync_mode != "") obj.set_string_member ("sync_mode", sync_mode);
            if (region != "" && region != "us") obj.set_string_member ("region", region);
            if (prelaunch_script != "") obj.set_string_member ("prelaunch_script", prelaunch_script);
            if (prelaunch_script_portal != null && !prelaunch_script_portal.is_empty ()) {
                obj.set_object_member ("prelaunch_script_portal", prelaunch_script_portal.to_json ());
            }
            if (advanced_dxvk) obj.set_boolean_member ("advanced_dxvk", true);
            if (dxvk_show_fps) obj.set_boolean_member ("dxvk_show_fps", true);
            if (dxvk_hide_integrated_graphics) obj.set_boolean_member ("dxvk_hide_integrated_graphics", true);
            if (dxvk_sampler_anisotropy != "") obj.set_string_member ("dxvk_sampler_anisotropy", dxvk_sampler_anisotropy);
            if (dxvk_max_frame_rate != "") obj.set_string_member ("dxvk_max_frame_rate", dxvk_max_frame_rate);
            if (dxvk_sync_interval != "") obj.set_string_member ("dxvk_sync_interval", dxvk_sync_interval);
            if (dxvk_config_custom != "") obj.set_string_member ("dxvk_config_custom", dxvk_config_custom);
            if (custom_entrypoints.size > 0) {
                var ep_arr = new Json.Array ();
                foreach (var ep in custom_entrypoints) {
                    ep_arr.add_object_element (ep.to_json ());
                }
                obj.set_array_member ("custom_entrypoints", ep_arr);
            }
            if (launch_display.size > 0) {
                var display = new Json.Object ();
                foreach (var item in launch_display.entries) {
                    if (item.value.is_empty ()) continue;
                    display.set_object_member (item.key, item.value.to_json ());
                }
                if (display.get_size () > 0) obj.set_object_member ("launch_display", display);
            }
            if (runtime_env_vars.size > 0) {
                obj.set_object_member ("runtime_env_vars", json_string_map_object (runtime_env_vars));
            }
            if (runtime_dll_overrides.size > 0) {
                obj.set_object_member ("runtime_dll_overrides", json_string_map_object (runtime_dll_overrides));
            }
            if (dynamic_launcher_desktop_ids.size > 0) {
                obj.set_object_member (
                    "dynamic_launcher_desktop_ids",
                    json_string_map_object (dynamic_launcher_desktop_ids)
                );
            }
            if (steam_shortcut_app_ids.size > 0) {
                obj.set_object_member (
                    "steam_shortcut_app_ids",
                    json_string_map_object (steam_shortcut_app_ids)
                );
            }

            if (runtime_component_overrides.size > 0) {
                var overrides = new Json.Object ();
                foreach (var entry in runtime_component_overrides.entries) {
                    overrides.set_object_member (entry.key, entry.value.to_json ());
                }
                obj.set_object_member ("runtime_component_overrides", overrides);
            }
            if (installed_redists.size > 0) {
                obj.set_array_member ("installed_redists", json_string_list_array (installed_redists));
            }
            if (applied_components.size > 0) {
                var ac = new Json.Object ();
                foreach (var entry in applied_components.entries) {
                    ac.set_object_member (entry.key, entry.value.to_json ());
                }
                obj.set_object_member ("applied_components", ac);
            }
            if (runner_support_files.size > 0) {
                obj.set_array_member ("runner_support_files", json_string_list_array (runner_support_files));
            }
            if (runner_state != null) {
                obj.set_object_member ("runner_state", runner_state.to_json ());
            }
            if (post_install_manifests.size > 0) {
                var arr = new Json.Array ();
                foreach (var spec in post_install_manifests) {
                    arr.add_object_element (spec.to_json ());
                }
                obj.set_array_member ("post_install_manifests", arr);
            }
            return obj;
        }

        public PrefixEntry snapshot () {
            var e = new PrefixEntry ();
            e.id = id;
            e.name = name;
            e.path = path;
            e.uri = uri;
            e.path_portal = clone_portal (path_portal);
            e.installer_id = installer_id;
            e.runner_id = runner_id;
            e.runner_version = runner_version;
            e.launcher_id = launcher_id;
            e.launch_entrypoint_id = launch_entrypoint_id;
            e.variant_id = variant_id;
            e.wine_arch = wine_arch;
            e.wine_debug = wine_debug;
            e.wine_wayland = wine_wayland;
            e.wayland_primary_monitor = wayland_primary_monitor;
            e.large_address_aware = large_address_aware;
            e.sync_mode = sync_mode;
            e.region = region;
            e.prelaunch_script = prelaunch_script;
            e.prelaunch_script_portal = clone_portal (prelaunch_script_portal);
            e.advanced_dxvk = advanced_dxvk;
            e.dxvk_show_fps = dxvk_show_fps;
            e.dxvk_hide_integrated_graphics = dxvk_hide_integrated_graphics;
            e.dxvk_sampler_anisotropy = dxvk_sampler_anisotropy;
            e.dxvk_max_frame_rate = dxvk_max_frame_rate;
            e.dxvk_sync_interval = dxvk_sync_interval;
            e.dxvk_config_custom = dxvk_config_custom;
            e.custom_entrypoints = clone_entrypoints (custom_entrypoints);
            e.launch_display = clone_launch_display (launch_display);
            e.runtime_env_vars = copy_string_map (runtime_env_vars);
            e.runtime_dll_overrides = copy_string_map (runtime_dll_overrides);
            e.runtime_component_overrides = clone_component_overrides (runtime_component_overrides);
            e.dynamic_launcher_desktop_ids = copy_string_map (dynamic_launcher_desktop_ids);
            e.steam_shortcut_app_ids = copy_string_map (steam_shortcut_app_ids);
            e.installed_redists = copy_string_list (installed_redists);
            e.applied_components = clone_applied_components (applied_components);
            e.runner_support_files = copy_string_list (runner_support_files);
            e.runner_state = clone_runner_state (runner_state);
            e.post_install_manifests = clone_post_installs (post_install_manifests);
            return e;
        }

        public void apply_runtime_state (PrefixEntry source) {
            if (source == this) return;
            runner_version = source.runner_version;
            installed_redists = copy_string_list (source.installed_redists);
            applied_components = clone_applied_components (source.applied_components);
            runtime_env_vars = copy_string_map (source.runtime_env_vars);
            runtime_dll_overrides = copy_string_map (source.runtime_dll_overrides);
            runtime_component_overrides = clone_component_overrides (source.runtime_component_overrides);
            merge_post_install_runtime_state (source.post_install_manifests);
            runner_state = clone_runner_state (source.runner_state);
            runner_support_files = copy_string_list (source.runner_support_files);
        }

        private void merge_post_install_runtime_state (Gee.ArrayList<PrefixPostInstallManifest> source) {
            foreach (var src in source) {
                if (src.id == "") continue;
                var live = find_post_install_metadata (src.id);
                if (live == null) continue;
                live.last_run_status = src.last_run_status;
                live.last_run_at = src.last_run_at;
                if (src.name != "") live.name = src.name;
                if (src.manifest_id != "") live.manifest_id = src.manifest_id;
            }
        }

        private static PortalPathRef? clone_portal (PortalPathRef? src) {
            if (src == null || src.is_empty ()) return null;
            return src.copy ();
        }

        private static Gee.HashMap<string, string> copy_string_map (Gee.Map<string, string> src) {
            var copy = new Gee.HashMap<string, string> ();
            copy.set_all (src);
            return copy;
        }

        private static Gee.ArrayList<string> copy_string_list (Gee.Collection<string> src) {
            var copy = new Gee.ArrayList<string> ();
            copy.add_all (src);
            return copy;
        }

        private static Gee.HashMap<string, LaunchDisplay> clone_launch_display (
            Gee.Map<string, LaunchDisplay> src
        ) {
            var copy = new Gee.HashMap<string, LaunchDisplay> ();
            foreach (var item in src.entries) {
                copy[item.key] = item.value.copy ();
            }
            return copy;
        }

        private static Gee.ArrayList<Entrypoint> clone_entrypoints (Gee.ArrayList<Entrypoint> src) {
            var copy = new Gee.ArrayList<Entrypoint> ();
            foreach (var ep in src) copy.add (ep.copy ());
            return copy;
        }

        private static Gee.HashMap<string, RuntimeComponentOverride> clone_component_overrides (
            Gee.Map<string, RuntimeComponentOverride> src
        ) {
            var copy = new Gee.HashMap<string, RuntimeComponentOverride> ();
            foreach (var entry in src.entries) copy[entry.key] = entry.value.copy ();
            return copy;
        }

        private static Gee.HashMap<string, AppliedComponentRecord> clone_applied_components (
            Gee.Map<string, AppliedComponentRecord> src
        ) {
            var copy = new Gee.HashMap<string, AppliedComponentRecord> ();
            foreach (var entry in src.entries) copy[entry.key] = entry.value.copy ();
            return copy;
        }

        private static PrefixRunnerState? clone_runner_state (PrefixRunnerState? src) {
            return src != null ? src.copy () : null;
        }

        private static Gee.ArrayList<PrefixPostInstallManifest> clone_post_installs (
            Gee.ArrayList<PrefixPostInstallManifest> src
        ) {
            var copy = new Gee.ArrayList<PrefixPostInstallManifest> ();
            foreach (var spec in src) copy.add (spec.copy ());
            return copy;
        }

        public static PrefixEntry from_json (Json.Object obj) throws Error {
            var e = new PrefixEntry ();
            e.parse_identity (obj);
            e.name = Utils.sanitize_user_text (e.name);
            e.path = json_string (obj, "path");
            e.uri = json_string (obj, "uri");
            e.path_portal = json_parse_member<PortalPathRef> (obj, "path_portal", PortalPathRef.from_json);
            e.installer_id = json_string (obj, "installer_id").strip ();
            if (e.installer_id == "") e.installer_id = ManifestRepository.shared ().default_installer_id ();
            e.runner_id = json_string (obj, "runner_id");
            e.runner_version = json_string (obj, "runner_version", ToolVersionRef.WIRE_INHERIT);
            e.launcher_id = json_string (obj, "launcher_id");
            e.launch_entrypoint_id = json_string (obj, "launch_entrypoint_id");
            e.variant_id = json_string (obj, "variant_id");
            e.wine_arch = json_string (obj, "wine_arch");
            e.wine_debug = json_string (obj, "wine_debug");
            e.wine_wayland = json_bool_nullable (obj, "wine_wayland");
            e.wayland_primary_monitor = json_string (obj, "wayland_primary_monitor");
            e.large_address_aware = json_bool_nullable (obj, InstallerPatch.SETTING_LARGE_ADDRESS_AWARE);
            e.sync_mode = json_string (obj, "sync_mode");
            e.region = json_string (obj, "region", "us");
            e.prelaunch_script = json_string (obj, "prelaunch_script");
            e.prelaunch_script_portal = json_parse_member<PortalPathRef> (
                obj, "prelaunch_script_portal", PortalPathRef.from_json
            );
            e.advanced_dxvk = json_bool (obj, "advanced_dxvk");
            e.dxvk_show_fps = json_bool (obj, "dxvk_show_fps");
            e.dxvk_hide_integrated_graphics = json_bool (obj, "dxvk_hide_integrated_graphics");
            e.dxvk_sampler_anisotropy = json_string (obj, "dxvk_sampler_anisotropy");
            e.dxvk_max_frame_rate = json_string (obj, "dxvk_max_frame_rate");
            e.dxvk_sync_interval = json_string (obj, "dxvk_sync_interval");
            e.dxvk_config_custom = json_string_or_array (obj, "dxvk_config_custom");

            e.custom_entrypoints = parse_json_array<Entrypoint> (obj, "custom_entrypoints", (o) => Entrypoint.from_json (o));
            foreach (var display in json_object_map<LaunchDisplay> (obj, "launch_display", (o) => LaunchDisplay.from_json (o)).entries) {
                if (!display.value.is_empty ()) e.launch_display[display.key] = display.value;
            }

            e.runtime_env_vars = json_string_map (obj, "runtime_env_vars");
            e.runtime_dll_overrides = json_string_map (obj, "runtime_dll_overrides");
            e.dynamic_launcher_desktop_ids = json_string_map (obj, "dynamic_launcher_desktop_ids");
            e.steam_shortcut_app_ids = json_string_map (obj, "steam_shortcut_app_ids");
            e.installed_redists = json_string_array (obj, "installed_redists");

            e.runtime_component_overrides = json_component_override_map (obj, "runtime_component_overrides");
            e.post_install_manifests = parse_json_array<PrefixPostInstallManifest> (
                obj, "post_install_manifests", (o) => PrefixPostInstallManifest.from_json (o)
            );
            e.applied_components = json_object_map<AppliedComponentRecord> (
                obj, "applied_components", (o) => AppliedComponentRecord.from_json (o)
            );
            e.runner_support_files = json_string_array (obj, "runner_support_files");
            e.runner_state = json_parse_member<PrefixRunnerState> (obj, "runner_state", PrefixRunnerState.from_json);
            if (e.installer_id == InstallerManifest.EMPTY_ID) {
                e.region = "";
                e.launcher_id = "";
            }
            return e;
        }
    }
}
