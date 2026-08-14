namespace Lumoria.Widgets.Preferences {

    public class RuntimePage : Gtk.Box {
        private const int SCREEN_INHIBITOR_PROBE_TIMEOUT_MS = 1500;
        private const int FERAL_GAME_MODE_PROBE_TIMEOUT_MS = 1500;

        private Adw.SwitchRow logging_row;
        private Adw.SwitchRow screen_inhibitor_row;
        private Adw.SwitchRow feral_game_mode_row;
        private Adw.SwitchRow wayland_row;
        private OptionListRow sync_mode_combo;
        private OptionListRow debug_combo;
        private Adw.SwitchRow laa_row;
        private Lumoria.Widgets.EnvVarsEditor global_env_editor;
        private Gtk.Label env_validation_label;
        private bool updating_screen_inhibitor_row = false;
        private bool updating_feral_game_mode_row = false;

        public RuntimePage () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            build_ui ();
        }

        private void build_ui () {
            var prefs = Utils.Preferences.instance ();

            var general_group = SettingsShared.build_group (_("General"));

            logging_row = new Adw.SwitchRow ();
            logging_row.title = _("Enable Logging");
            logging_row.active = prefs.keep_runtime_logs;
            logging_row.notify["active"].connect (() => {
                if (prefs.keep_runtime_logs != logging_row.active) {
                    prefs.set_keep_runtime_logs (logging_row.active);
                }
                update_debug_combo_state ();
            });
            general_group.add (logging_row);

            screen_inhibitor_row = new Adw.SwitchRow ();
            screen_inhibitor_row.title = _("Keep Display Awake While Playing");
            screen_inhibitor_row.sensitive = false;
            screen_inhibitor_row.active = prefs.screen_inhibitor;
            screen_inhibitor_row.notify["active"].connect (() => {
                if (updating_screen_inhibitor_row) return;
                if (prefs.screen_inhibitor != screen_inhibitor_row.active) {
                    prefs.set_screen_inhibitor (screen_inhibitor_row.active);
                }
            });
            general_group.add (screen_inhibitor_row);
            check_screen_inhibitor_support ();

            feral_game_mode_row = new Adw.SwitchRow ();
            feral_game_mode_row.title = _("Enable Feral GameMode");
            feral_game_mode_row.sensitive = false;
            feral_game_mode_row.active = prefs.feral_game_mode;
            feral_game_mode_row.notify["active"].connect (() => {
                if (updating_feral_game_mode_row) return;
                if (prefs.feral_game_mode != feral_game_mode_row.active) {
                    prefs.set_feral_game_mode (feral_game_mode_row.active);
                }
            });
            general_group.add (feral_game_mode_row);
            check_feral_game_mode_support ();

            append (general_group);

            var wine_group = SettingsShared.build_group (_("Wine"));

            wayland_row = new Adw.SwitchRow ();
            wayland_row.title = _("Enable Wine Wayland");
            wayland_row.subtitle = SettingsShared.wayland_no_x11_hint ();
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

        private void check_screen_inhibitor_support () {
            new Thread<bool> ("screen-inhibitor-probe", () => {
                string error;
                var supported = Utils.ScreenInhibitor.probe (SCREEN_INHIBITOR_PROBE_TIMEOUT_MS, out error);
                Idle.add (() => {
                    updating_screen_inhibitor_row = true;
                    screen_inhibitor_row.active = supported && Utils.Preferences.instance ().screen_inhibitor;
                    screen_inhibitor_row.sensitive = supported;
                    updating_screen_inhibitor_row = false;
                    return Source.REMOVE;
                });
                return true;
            });
        }

        private void check_feral_game_mode_support () {
            new Thread<bool> ("feral-game-mode-probe", () => {
                string error;
                var supported = Utils.FeralGameModePortal.probe (FERAL_GAME_MODE_PROBE_TIMEOUT_MS, out error);
                Idle.add (() => {
                    updating_feral_game_mode_row = true;
                    feral_game_mode_row.active = supported && Utils.Preferences.instance ().feral_game_mode;
                    feral_game_mode_row.sensitive = supported;
                    feral_game_mode_row.subtitle = supported
                        ? ""
                        : _("Feral GameMode is not available through the desktop portal");
                    updating_feral_game_mode_row = false;
                    return Source.REMOVE;
                });
                return true;
            });
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
