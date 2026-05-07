namespace Lumoria.Widgets.Dialogs {

    public class RunnerSettingsShared : Object {
        public static Gtk.StringList build_runner_model (Gee.ArrayList<Models.RunnerSpec> runner_specs) {
            var model = new Gtk.StringList (null);
            for (int i = 0; i < runner_specs.size; i++) {
                model.append (runner_specs[i].display_label ());
            }
            return model;
        }

        public static int select_runner_index (
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            string current_runner_id = ""
        ) {
            if (runner_specs.size == 0) return 0;

            if (current_runner_id != "") {
                for (int i = 0; i < runner_specs.size; i++) {
                    if (runner_specs[i].id == current_runner_id) return i;
                }
            }

            var prefs = Utils.Preferences.instance ();
            var pref_runner_id = prefs.runner_id;
            if (pref_runner_id != "") {
                for (int i = 0; i < runner_specs.size; i++) {
                    if (runner_specs[i].id == pref_runner_id) return i;
                }
            }

            for (int i = 0; i < runner_specs.size; i++) {
                if (runner_specs[i].is_default) return i;
            }
            return 0;
        }

        public static void rebuild_variant_combo (
            OptionListRow runner_combo,
            OptionListRow variant_combo,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.RunnerVariant> visible_variants,
            string preselect = ""
        ) {
            visible_variants.clear ();

            var sel = (int) runner_combo.selected;
            if (sel < 0 || sel >= runner_specs.size) {
                variant_combo.visible = false;
                return;
            }

            var candidates = runner_specs[sel].selectable_variants (Utils.is_sandboxed ());
            if (candidates.size == 0) {
                variant_combo.visible = false;
                return;
            }

            var model = new Gtk.StringList (null);
            int selected_idx = 0;
            for (int i = 0; i < candidates.size; i++) {
                var variant = candidates[i];
                visible_variants.add (variant);
                model.append (variant.display_label ());
                if (preselect != "" && variant.id == preselect) selected_idx = i;
                else if (preselect == "" && variant.is_default) selected_idx = i;
            }

            variant_combo.visible = true;
            variant_combo.model = model;
            variant_combo.selected = selected_idx;
        }

        public static void rebuild_version_combo (
            OptionListRow runner_combo,
            OptionListRow variant_combo,
            OptionListRow version_combo,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.RunnerVariant> visible_variants,
            Gee.ArrayList<string> version_values,
            string preselect = "default"
        ) {
            var model = new Gtk.StringList (null);
            version_values.clear ();

            var runner = selected_runner (runner_combo, runner_specs);
            var runner_id = runner != null ? runner.id : "";

            add_default_version_option (model, version_values, runner_id);
            add_version_option (model, version_values, _("Latest (always newest)"), "latest");

            if (runner != null) {
                add_installed_versions (model, version_values, runner);
                add_release_versions (model, version_values, runner, selected_variant (variant_combo, visible_variants));
            }

            version_combo.model = model;
            version_combo.selected = selected_version_index (version_values, preselect);
        }

        public static string selected_version_value (
            OptionListRow version_combo,
            Gee.ArrayList<string> version_values
        ) {
            var idx = (int) version_combo.selected;
            if (idx >= 0 && idx < version_values.size) return version_values[idx];
            return "default";
        }

        private static Models.RunnerSpec? selected_runner (
            OptionListRow runner_combo,
            Gee.ArrayList<Models.RunnerSpec> runner_specs
        ) {
            var sel = (int) runner_combo.selected;
            if (sel < 0 || sel >= runner_specs.size) return null;
            return runner_specs[sel];
        }

        private static Models.RunnerVariant? selected_variant (
            OptionListRow variant_combo,
            Gee.ArrayList<Models.RunnerVariant> visible_variants
        ) {
            if (visible_variants.size == 0) return null;
            var sel = (int) variant_combo.selected;
            if (sel < 0 || sel >= visible_variants.size) return visible_variants[0];
            return visible_variants[sel];
        }

        private static void add_default_version_option (
            Gtk.StringList model,
            Gee.ArrayList<string> version_values,
            string runner_id
        ) {
            var defaults = Utils.Preferences.instance ();
            var default_id = defaults.runner_id;
            var default_ver = defaults.get_default_runner_version ();
            if (runner_id != "" && runner_id != default_id) {
                model.append (_("Use Runner Default (%s latest)").printf (runner_id));
            } else {
                var default_label = default_id != "" ? "%s %s".printf (default_id, default_ver) : default_ver;
                model.append (_("Use Global Default (%s)").printf (default_label));
            }
            version_values.add ("default");
        }

        private static void add_installed_versions (
            Gtk.StringList model,
            Gee.ArrayList<string> version_values,
            Models.RunnerSpec runner
        ) {
            var installed = Utils.list_dirs (Path.build_filename (Utils.runner_dir (), runner.id));
            installed.sort ((a, b) => strcmp (b, a));
            foreach (var dir_name in installed) {
                add_version_option (model, version_values, dir_name, dir_name);
            }
        }

        private static void add_release_versions (
            Gtk.StringList model,
            Gee.ArrayList<string> version_values,
            Models.RunnerSpec runner,
            Models.RunnerVariant? variant
        ) {
            if (runner.github_repo == "" || variant == null) return;
            var selected = (Models.RunnerVariant) variant;

            try {
                var cache_path = Path.build_filename (Utils.cache_dir (), "runners", runner.id, "releases.json");
                var releases = Utils.fetch_github_releases_sync (runner.github_repo, cache_path, 6 * 3600);
                foreach (var release in releases) {
                    if (runner.skips_version (release.tag_name)) continue;
                    if (release_has_variant_asset (release, selected)) {
                        add_version_option (model, version_values, release.tag_name, release.tag_name);
                    }
                }
            } catch (Error e) {
                warning ("Failed to load runner releases for %s: %s", runner.id, e.message);
            }
        }

        private static bool release_has_variant_asset (
            Utils.GitHubRelease release,
            Models.RunnerVariant variant
        ) {
            try {
                return Utils.find_github_asset_by_regex (release, variant.asset_regex) != null;
            } catch (RegexError e) {
                warning ("Invalid runner variant asset regex '%s': %s", variant.asset_regex, e.message);
                return false;
            }
        }

        private static void add_version_option (
            Gtk.StringList model,
            Gee.ArrayList<string> version_values,
            string label,
            string value
        ) {
            if (value == "") return;
            if (version_values.contains (value)) return;
            model.append (label);
            version_values.add (value);
        }

        private static uint selected_version_index (
            Gee.ArrayList<string> version_values,
            string preselect
        ) {
            for (int i = 0; i < version_values.size; i++) {
                if (version_values[i] == preselect) return (uint) i;
            }
            return 0;
        }

        public static OptionListRow build_sync_combo (string selected_mode = "ntsync") {
            var model = new Gtk.StringList (null);
            model.append (_("NTSync (recommended)"));
            model.append (_("Fsync"));
            model.append (_("Esync"));

            var row = new OptionListRow ();
            row.title = _("Sync Mode");
            row.model = model;
            row.selected = sync_mode_index_for_value (selected_mode);
            return row;
        }

        public static int sync_mode_index_for_value (string sync_mode) {
            switch (sync_mode) {
                case "fsync": return 1;
                case "esync": return 2;
                default: return 0;
            }
        }

        public static string sync_mode_value_for_index (uint selected) {
            switch (selected) {
                case 1: return "fsync";
                case 2: return "esync";
                default: return "ntsync";
            }
        }

        public static OptionListRow build_debug_combo (string current_debug = "") {
            var model = new Gtk.StringList (null);
            model.append (Runtime.WINE_DEBUG_LABEL_DEFAULT);
            model.append (Runtime.WINE_DEBUG_LABEL_GENERAL);
            model.append (Runtime.WINE_DEBUG_LABEL_FULL);

            var row = new OptionListRow ();
            row.title = _("Debug Level");
            row.model = model;
            row.selected = (current_debug == "") ? 0 : Runtime.wine_debug_index_for_value (current_debug);
            return row;
        }

        public static OptionListRow build_sync_override_combo (string prefix_sync_mode = "") {
            var global = Utils.Preferences.instance ().sync_mode;
            var global_label = sync_mode_display_label (global);

            var model = new Gtk.StringList (null);
            model.append (_("Inherit default (%s)").printf (global_label));
            model.append (_("NTSync (recommended)"));
            model.append (_("Fsync"));
            model.append (_("Esync"));

            var row = new OptionListRow ();
            row.title = _("Sync Mode");
            row.model = model;
            row.selected = sync_override_index_for_value (prefix_sync_mode);
            return row;
        }

        public static uint sync_override_index_for_value (string prefix_sync_mode) {
            if (prefix_sync_mode == "") return 0;
            return sync_mode_index_for_value (prefix_sync_mode) + 1;
        }

        public static string sync_override_value_for_index (uint selected) {
            if (selected == 0) return "";
            return sync_mode_value_for_index (selected - 1);
        }

        public static OptionListRow build_debug_override_combo (string prefix_wine_debug = "") {
            var global = Utils.Preferences.instance ().wine_debug;
            var global_label = debug_display_label (global);

            var model = new Gtk.StringList (null);
            model.append (_("Inherit default (%s)").printf (global_label));
            model.append (Runtime.WINE_DEBUG_LABEL_DEFAULT);
            model.append (Runtime.WINE_DEBUG_LABEL_GENERAL);
            model.append (Runtime.WINE_DEBUG_LABEL_FULL);

            var row = new OptionListRow ();
            row.title = _("Debug Level");
            row.model = model;
            row.selected = debug_override_index_for_value (prefix_wine_debug);
            return row;
        }

        public static uint debug_override_index_for_value (string prefix_wine_debug) {
            if (prefix_wine_debug == "") return 0;
            return Runtime.wine_debug_index_for_value (prefix_wine_debug) + 1;
        }

        public static string debug_override_value_for_index (uint selected) {
            if (selected == 0) return "";
            return Runtime.wine_debug_value_for_index (selected - 1);
        }

        private static string sync_mode_display_label (string mode) {
            switch (mode) {
                case "fsync": return _("Fsync");
                case "esync": return _("Esync");
                default: return _("NTSync");
            }
        }

        private static string debug_display_label (string debug) {
            if (debug == Runtime.WINE_DEBUG_GENERAL) return Runtime.WINE_DEBUG_LABEL_GENERAL;
            if (debug == Runtime.WINE_DEBUG_FULL) return Runtime.WINE_DEBUG_LABEL_FULL;
            return Runtime.WINE_DEBUG_LABEL_DEFAULT;
        }

        public static OptionListRow build_wayland_combo (bool? wayland_override = null) {
            var wayland_global = Utils.Preferences.instance ().wine_wayland ? _("enabled") : _("disabled");
            return SettingsShared.build_toggle_override_combo (
                _("Wine Wayland"),
                wayland_override,
                wayland_global
            );
        }

        public static int wayland_index_for_value (bool? wayland_override) {
            return (int) ToggleOverrideState.from_nullable_bool (wayland_override);
        }

        public static bool? wayland_value_for_index (uint selected) {
            return ((ToggleOverrideState) selected).to_nullable_bool ();
        }
    }
}
