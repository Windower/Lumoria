namespace Lumoria.Widgets.Dialogs {

    public class RunnerSettingsShared : Object {
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
            var pref_runner_id = prefs.get_default_runner_id ();
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
            Adw.ComboRow runner_combo,
            Adw.ComboRow variant_combo,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.RunnerVariant> visible_variants,
            string preselect = ""
        ) {
            var model = (Gtk.StringList) variant_combo.model;
            while (model.get_n_items () > 0) model.remove (0);
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

            variant_combo.visible = true;
            int selected_idx = 0;
            for (int i = 0; i < candidates.size; i++) {
                var variant = candidates[i];
                visible_variants.add (variant);
                model.append (variant.display_label ());
                if (preselect != "" && variant.id == preselect) selected_idx = i;
                else if (preselect == "" && variant.is_default) selected_idx = i;
            }
            variant_combo.selected = selected_idx;
        }

        public static Adw.ComboRow build_sync_combo (string selected_mode = "ntsync") {
            var model = new Gtk.StringList (null);
            model.append (_("NTSync (recommended)"));
            model.append (_("Fsync"));
            model.append (_("Esync"));

            var combo = new Adw.ComboRow ();
            combo.title = _("Sync Mode");
            combo.model = model;
            combo.selected = sync_mode_index_for_value (selected_mode);
            return combo;
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

        public static Adw.ComboRow build_debug_combo (string current_debug = "") {
            var model = new Gtk.StringList (null);
            model.append (Runtime.WINE_DEBUG_LABEL_DEFAULT);
            model.append (Runtime.WINE_DEBUG_LABEL_GENERAL);
            model.append (Runtime.WINE_DEBUG_LABEL_FULL);

            var combo = new Adw.ComboRow ();
            combo.title = _("Debug Level");
            combo.model = model;
            if (current_debug == "") {
                combo.selected = 0;
            } else {
                combo.selected = Runtime.wine_debug_index_for_value (current_debug);
            }
            return combo;
        }

        public static Adw.ComboRow build_wayland_combo (bool? wayland_override = null) {
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
