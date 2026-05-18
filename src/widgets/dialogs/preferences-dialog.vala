namespace Lumoria.Widgets.Dialogs {

    public class PreferencesDialog : Adw.Dialog {
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Models.PrefixRegistry registry;
        private Adw.ToastOverlay toast_overlay;
        private Adw.ViewStack stack;
        private Gtk.Window host_window;
        private ulong host_width_handler = 0;
        private ulong host_height_handler = 0;

        public PreferencesDialog (
            Gtk.Window parent,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Models.PrefixRegistry registry
        ) {
            Object (
                title: _("Preferences"),
                content_width: 650,
                content_height: 700
            );
            this.host_window = parent;
            this.runner_specs = Models.RunnerSpec.filter_for_environment (runner_specs, Utils.is_sandboxed ());
            this.registry = registry;
            update_dialog_size ();
            bind_host_size ();
            build_ui ();
        }

        ~PreferencesDialog () {
            unbind_host_size ();
        }

        private void bind_host_size () {
            host_width_handler = host_window.notify["width"].connect (() => update_dialog_size ());
            host_height_handler = host_window.notify["height"].connect (() => update_dialog_size ());
            closed.connect (() => unbind_host_size ());
        }

        private void unbind_host_size () {
            if (host_width_handler != 0) {
                host_window.disconnect (host_width_handler);
                host_width_handler = 0;
            }
            if (host_height_handler != 0) {
                host_window.disconnect (host_height_handler);
                host_height_handler = 0;
            }
        }

        private void update_dialog_size () {
            var pw = host_window.get_width ();
            var ph = host_window.get_height ();
            if (pw <= 0 || ph <= 0) return;
            content_width = (int) (pw * 0.9).clamp (650, 1200);
            content_height = (int) (ph * 0.92).clamp (700, 1100);
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

            var storage_page = new Preferences.StoragePage (registry);
            storage_page.toast_message.connect (show_toast);
            SettingsShared.add_scrolled_settings_page (stack, storage_page, SettingsShared.PAGE_STORAGE, _("Storage"));

            var advanced_page = new Preferences.AdvancedPage ();
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
