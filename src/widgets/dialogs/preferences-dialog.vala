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
            string? restore_page = stack != null ? stack.visible_child_name : null;

            var toolbar = new Adw.ToolbarView ();

            stack = new Adw.ViewStack ();
            stack.vexpand = true;

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
            advanced_page.experimental_changed.connect (() => build_ui ());
            SettingsShared.add_scrolled_settings_page (stack, advanced_page, SettingsShared.PAGE_ADVANCED, _("Advanced"));

            var about_page = new Preferences.AboutPage ();
            SettingsShared.add_scrolled_settings_page (stack, about_page, SettingsShared.PAGE_ABOUT, _("About"));

            if (restore_page != null) {
                stack.visible_child_name = restore_page;
            }

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
            SettingsShared.present_destructive_confirmation (
                this,
                _("Reset to Defaults?"),
                _("This will reset global runner defaults, component defaults, runtime environment settings, and global Wine/patch preferences."),
                "reset",
                _("Reset"),
                () => {
                Utils.Preferences.instance ().reset_to_defaults ();
                build_ui ();
                show_toast (_("Preferences reset to defaults."));
            });
        }
    }
}
