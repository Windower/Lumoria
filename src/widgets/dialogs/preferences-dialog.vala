namespace Lumoria.Widgets.Dialogs {

    public class PreferencesDialog : Adw.Dialog {
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Adw.ToastOverlay toast_overlay;
        private Adw.ViewStack stack;

        public PreferencesDialog (Gtk.Window parent, Gee.ArrayList<Models.RunnerSpec> runner_specs) {
            Object (
                title: _("Preferences"),
                content_width: 650,
                content_height: 700
            );
            this.runner_specs = runner_specs;
            build_ui ();
        }

        private void build_ui () {
            var toolbar = new Adw.ToolbarView ();

            stack = new Adw.ViewStack ();
            stack.vexpand = true;

            //  var general_page = new Preferences.GeneralPage ();
            //  SettingsShared.add_scrolled_settings_page (stack, general_page, SettingsShared.PAGE_GENERAL, _("General"));

            var runtime_page = new Preferences.RuntimePage ();
            SettingsShared.add_scrolled_settings_page (stack, runtime_page, SettingsShared.PAGE_RUNTIME, _("Runtime"));
            var runners_page = new Preferences.RunnersPage (runner_specs);
            runners_page.toast_message.connect (show_toast);
            SettingsShared.add_scrolled_settings_page (stack, runners_page, SettingsShared.PAGE_RUNNERS, _("Runners"));

            var components_page = new Preferences.ComponentsPage ();
            components_page.toast_message.connect (show_toast);
            SettingsShared.add_scrolled_settings_page (stack, components_page, SettingsShared.PAGE_COMPONENTS, _("Components"));

            var advanced_page = new Preferences.AdvancedPage ();
            advanced_page.toast_message.connect (show_toast);
            advanced_page.reset_requested.connect (on_reset_defaults);
            SettingsShared.add_scrolled_settings_page (stack, advanced_page, SettingsShared.PAGE_ADVANCED, _("Advanced"));

            var header = new Adw.HeaderBar ();
            toolbar.add_top_bar (header);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.vexpand = true;
            var switcher_bar = new Adw.ViewSwitcherBar ();
            switcher_bar.stack = stack;
            switcher_bar.reveal = true;
            content.append (switcher_bar);
            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.vexpand = true;
            toast_overlay.child = stack;
            content.append (toast_overlay);
            toolbar.content = content;

            this.child = toolbar;
        }

        private void show_toast (string message) {
            toast_overlay.add_toast (new Adw.Toast (message));
        }

        private void on_reset_defaults () {
            var dialog = new Adw.AlertDialog (
                _("Reset to Defaults?"),
                _("This will reset global runner defaults, component defaults, runtime environment settings, and global Wine/patch preferences.")
            );
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("reset", _("Reset"));
            dialog.set_response_appearance ("reset", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response != "reset") return;
                Utils.Preferences.instance ().reset_to_defaults ();
                build_ui ();
                show_toast (_("Preferences reset to defaults."));
            });
            dialog.present (this);
        }
    }
}
