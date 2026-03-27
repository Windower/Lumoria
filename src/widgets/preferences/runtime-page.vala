namespace Lumoria.Widgets.Preferences {

    public class RuntimePage : Gtk.Box {
        private Adw.ComboRow logging_combo;
        private Adw.SwitchRow wayland_row;
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

            logging_combo = new Adw.ComboRow ();
            logging_combo.title = _("Runtime Launch Logs");
            logging_combo.model = SettingsShared.build_logging_mode_model ();
            logging_combo.selected = (uint) Utils.LoggingMode.from_value (prefs.logging_mode);
            logging_combo.notify["selected"].connect (() => {
                var inst = Utils.Preferences.instance ();
                var selected = (Utils.LoggingMode) logging_combo.selected;
                var mode = selected.to_value ();
                if (inst.logging_mode != mode) {
                    inst.set_logging_mode (mode);
                }
            });
            logging_group.add (logging_combo);
            append (logging_group);

            var wine_group = SettingsShared.build_group (_("Wine"));

            wayland_row = new Adw.SwitchRow ();
            wayland_row.title = _("Enable Wine Wayland");
            wayland_row.subtitle = _("Use Wine's Wayland driver instead of X11 by default.");
            wayland_row.active = prefs.wine_wayland;
            wayland_row.notify["active"].connect (() => {
                var inst = Utils.Preferences.instance ();
                if (inst.wine_wayland != wayland_row.active) {
                    inst.set_wine_wayland (wayland_row.active);
                }
            });
            wine_group.add (wayland_row);
            append (wine_group);

            var patches_group = SettingsShared.build_group (_("Patches"));

            laa_row = new Adw.SwitchRow ();
            laa_row.title = _("Enable Large Address Aware");
            laa_row.subtitle = _("Toggle the Large Address Aware flag on PlayOnline before launch by default.");
            laa_row.active = prefs.large_address_aware;
            laa_row.notify["active"].connect (() => {
                var inst = Utils.Preferences.instance ();
                if (inst.large_address_aware != laa_row.active) {
                    inst.set_large_address_aware (laa_row.active);
                }
            });
            patches_group.add (laa_row);
            append (patches_group);

            var env_group = SettingsShared.build_group (_("Global Runtime Variables"), 24, 12, 12);

            var env_row = new Adw.ActionRow ();
            env_row.title = _("Environment Variables");
            env_row.subtitle = _("Applied to all prefixes. Prefix-level variables with the same key take precedence.");
            env_row.activatable = false;
            env_group.add (env_row);
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
    }
}
