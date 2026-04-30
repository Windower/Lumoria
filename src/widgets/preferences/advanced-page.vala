namespace Lumoria.Widgets.Preferences {

    public class AdvancedPage : Gtk.Box {
        public signal void reset_requested ();
        public signal void experimental_changed ();

        public AdvancedPage () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            build_ui ();
        }

        private void build_ui () {
            var prefs = Utils.Preferences.instance ();

            var experimental_group = SettingsShared.build_group (_("Experimental"));
            var experimental_row = new Adw.SwitchRow ();
            experimental_row.title = _("Experimental Features");
            experimental_row.subtitle = _("Enable features that are still in development.");
            experimental_row.active = prefs.experimental_features;
            experimental_row.notify["active"].connect (() => {
                if (prefs.experimental_features != experimental_row.active) {
                    prefs.set_experimental_features (experimental_row.active);
                    experimental_changed ();
                }
            });
            experimental_group.add (experimental_row);
            append (experimental_group);

            var reset_group = SettingsShared.build_group (_("Reset"));

            var reset_row = new Adw.ActionRow ();
            reset_row.title = _("Reset Preferences To Defaults");
            reset_row.subtitle = _("Restore runner defaults, component defaults, runtime env settings, and global Wine/patch settings.");
            var reset_btn = new Gtk.Button.with_label (_("Reset"));
            reset_btn.add_css_class ("destructive-action");
            reset_btn.valign = Gtk.Align.CENTER;
            reset_btn.clicked.connect (() => reset_requested ());
            reset_row.add_suffix (reset_btn);
            reset_row.activatable_widget = reset_btn;
            reset_group.add (reset_row);
            append (reset_group);
        }
    }
}
