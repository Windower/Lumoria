namespace Lumoria.Widgets.Preferences {

    public class RuntimePage : Gtk.Box {
        private Adw.SwitchRow logging_row;
        private Adw.SwitchRow wayland_row;
        private OptionListRow sync_mode_combo;
        private OptionListRow debug_combo;
        private Adw.SwitchRow laa_row;
        private Lumoria.Widgets.EnvVarsEditor global_env_editor;
        private Gtk.Label env_validation_label;

        public RuntimePage () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            build_ui ();
        }

        private void build_ui () {
            var prefs = Utils.Preferences.instance ();

            var logging_group = SettingsShared.build_group (_("Logging"));

            logging_row = new Adw.SwitchRow ();
            logging_row.title = _("Enable Logging");
            logging_row.subtitle = _("Keep log files under prefix-path/logs.");
            logging_row.active = prefs.keep_runtime_logs;
            logging_row.notify["active"].connect (() => {
                if (prefs.keep_runtime_logs != logging_row.active) {
                    prefs.set_keep_runtime_logs (logging_row.active);
                }
                update_debug_combo_state ();
            });
            logging_group.add (logging_row);
            append (logging_group);

            var wine_group = SettingsShared.build_group (_("Wine"));

            wayland_row = new Adw.SwitchRow ();
            wayland_row.title = _("Enable Wine Wayland");
            wayland_row.subtitle = _("Use Wine's Wayland driver instead of X11 by default.");
            wayland_row.active = prefs.wine_wayland;
            wayland_row.notify["active"].connect (() => {
                if (prefs.wine_wayland != wayland_row.active) {
                    prefs.set_wine_wayland (wayland_row.active);
                }
            });
            wine_group.add (wayland_row);

            sync_mode_combo = Dialogs.RunnerSettingsShared.build_sync_combo (prefs.sync_mode);
            sync_mode_combo.notify["selected"].connect (() => {
                var mode = Dialogs.RunnerSettingsShared.sync_mode_value_for_index (sync_mode_combo.selected);
                if (prefs.sync_mode != mode)
                    prefs.set_sync_mode (mode);
            });
            wine_group.add (sync_mode_combo);

            debug_combo = Dialogs.RunnerSettingsShared.build_debug_combo (prefs.wine_debug);
            debug_combo.notify["selected"].connect (() => {
                var debug_val = Runtime.wine_debug_value_for_index (debug_combo.selected);
                if (prefs.wine_debug != debug_val)
                    prefs.set_wine_debug (debug_val);
                update_debug_combo_state ();
            });
            update_debug_combo_state ();
            wine_group.add (debug_combo);

            append (wine_group);

            if (prefs.experimental_features) {
                var patches_group = SettingsShared.build_group (_("Patches"));

                laa_row = new Adw.SwitchRow ();
                laa_row.title = _("Enable Large Address Aware");
                laa_row.subtitle = _("Toggle the Large Address Aware flag on PlayOnline before launch by default.");
                laa_row.active = prefs.large_address_aware;
                laa_row.notify["active"].connect (() => {
                    if (prefs.large_address_aware != laa_row.active) {
                        prefs.set_large_address_aware (laa_row.active);
                    }
                });
                patches_group.add (laa_row);
                append (patches_group);
            }

            var env_group = SettingsShared.build_group (_("Global Runtime Variables"), 24, 12, 12);
            env_group.description = _("Applied to all prefixes. Prefix-level variables with the same key take precedence.");

            global_env_editor = new Lumoria.Widgets.EnvVarsEditor (prefs.get_runtime_env_vars ());
            global_env_editor.margin_top = 8;
            global_env_editor.margin_bottom = 6;
            global_env_editor.margin_start = 8;
            global_env_editor.margin_end = 8;
            global_env_editor.changed.connect (on_global_env_editor_changed);
            env_group.add (global_env_editor);

            env_validation_label = new Gtk.Label ("");
            env_validation_label.xalign = 0f;
            env_validation_label.wrap = true;
            env_validation_label.add_css_class ("error");
            env_validation_label.visible = false;
            env_validation_label.margin_start = 8;
            env_validation_label.margin_end = 8;
            env_validation_label.margin_bottom = 4;
            env_group.add (env_validation_label);
            append (env_group);
        }

        private void on_global_env_editor_changed () {
            string validation_error;
            if (!global_env_editor.validate (out validation_error)) {
                env_validation_label.label = validation_error;
                env_validation_label.visible = true;
                return;
            }
            env_validation_label.visible = false;
            Utils.Preferences.instance ().set_runtime_env_vars (global_env_editor.values ());
        }

        private void update_debug_combo_state () {
            if (debug_combo == null || logging_row == null) return;
            Dialogs.RunnerSettingsShared.update_debug_combo_logging_state (debug_combo, logging_row.active);
        }
    }
}
