namespace Lumoria.Widgets.Preferences {

    public class AboutPage : Gtk.Box {
        public AboutPage () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            build_ui ();
        }

        private void build_ui () {
            var app_group = SettingsShared.build_group (Config.APP_NAME);

            var icon = new Gtk.Image.from_icon_name (Config.APP_ID);
            icon.pixel_size = 96;
            icon.halign = Gtk.Align.CENTER;
            icon.margin_top = 12;
            icon.margin_bottom = 8;
            append (icon);

            var version_row = new Adw.ActionRow ();
            version_row.title = _("Version");
            version_row.subtitle = Config.APP_VERSION;
            app_group.add (version_row);

            var developer_row = new Adw.ActionRow ();
            developer_row.title = _("Developer");
            developer_row.subtitle = "rysas";
            app_group.add (developer_row);

            var license_row = new Adw.ActionRow ();
            license_row.title = _("License");
            license_row.subtitle = "GPL-3.0-or-later";
            app_group.add (license_row);

            var copyright_row = new Adw.ActionRow ();
            copyright_row.title = _("Copyright");
            copyright_row.subtitle = "© 2026 rysas";
            app_group.add (copyright_row);

            append (app_group);

            var credits_group = SettingsShared.build_group (_("Credits"), 24, 12, 12);

            add_credit_row (credits_group, _("Windower project maintainers"), "");
            add_credit_row (credits_group, _("Wine, Proton, and DXVK contributors"), "");
            add_credit_row (credits_group, _("ProtonPlus, Lutris and Winetrick "), _(""));

            append (credits_group);

            var community_group = SettingsShared.build_group (_("Special Thanks"), 24, 12, 12);

            var community_row = new Adw.ActionRow ();
            community_row.title = _("💖 The Windower Community");
            community_group.add (community_row);

            append (community_group);
        }

        private void add_credit_row (Adw.PreferencesGroup group, string name, string detail) {
            var row = new Adw.ActionRow ();
            row.title = name;
            if (detail != "") row.subtitle = detail;
            group.add (row);
        }
    }
}
