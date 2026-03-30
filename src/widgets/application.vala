namespace Lumoria.Widgets {

    public class Application : Adw.Application {
        public Application () {
            Object (
                application_id: Config.APP_ID,
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
        }

        construct {
            ActionEntry[] action_entries = {
                { "preferences", this.on_preferences_action },
                { "quit", this.quit },
            };
            this.add_action_entries (action_entries, this);
            this.set_accels_for_action ("app.quit", { "<primary>q" });
            this.set_accels_for_action ("app.preferences", { "<primary>comma" });
        }

        protected override void activate () {
            base.activate ();

            var resource_path = Config.RESOURCE_BASE + "/css/style.css";
            try {
                var bytes = GLib.resources_lookup_data (resource_path, 0);
                var provider = new Gtk.CssProvider ();
                provider.load_from_string ((string) bytes.get_data ());
                var display = Gdk.Display.get_default ();
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display (
                        display, provider,
                        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                    );
                    var icon_theme = Gtk.IconTheme.get_for_display (display);
                    icon_theme.add_resource_path (Config.RESOURCE_BASE + "/icons");
                }
            } catch (Error e) {
                warning ("Failed to load CSS: %s", e.message);
            }

            var win = this.active_window ?? new Window (this);
            win.present ();
        }

        private void on_preferences_action () {
            var win = this.active_window as Window;
            if (win != null) win.show_preferences ();
        }
    }
}
