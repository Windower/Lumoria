namespace Lumoria.Widgets.Preferences {

    public class AdvancedPage : Gtk.Box {
        public signal void reset_requested ();
        public signal void experimental_changed ();
        public signal void toast_message (string message);

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

            var cache_group = SettingsShared.build_group (_("Cache"), 24, 12, 12);
            cache_group.description = _("Clear cached metadata and downloaded archives.");

            add_cache_clear_row (cache_group, _("Clear Runner Cache"), "runners", _("Runner cache cleared."));
            add_cache_clear_row (cache_group, _("Clear Component Cache"), "components", _("Component cache cleared."));
            add_cache_clear_row (cache_group, _("Clear Installer Cache"), "installer", _("Installer cache cleared."));
            add_cache_clear_row (cache_group, _("Clear Launcher Cache"), "launchers", _("Launcher cache cleared."));
            add_cache_clear_row (cache_group, _("Clear Redistributable Cache"), "redist", _("Redistributable cache cleared."));

            var clear_all = new Adw.ActionRow ();
            clear_all.title = _("Clear All Cache");
            clear_all.activatable = true;
            clear_all.add_css_class ("error");
            clear_all.activated.connect (() => {
                if (Utils.remove_recursive (Utils.cache_dir ())) {
                    toast_message (_("All cache cleared."));
                } else {
                    toast_message (_("Failed to clear some cache files."));
                }
            });
            cache_group.add (clear_all);
            append (cache_group);
        }

        private void add_cache_clear_row (
            Adw.PreferencesGroup group,
            string title,
            string cache_subdir,
            string toast
        ) {
            var row = new Adw.ActionRow ();
            row.title = title;
            row.activatable = true;
            row.activated.connect (() => {
                if (Utils.remove_recursive (Path.build_filename (Utils.cache_dir (), cache_subdir))) {
                    toast_message (toast);
                } else {
                    toast_message (_("Failed to clear cache."));
                }
            });
            group.add (row);
        }
    }
}
