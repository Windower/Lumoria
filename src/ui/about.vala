namespace Lumoria.Ui {

    public void present_about (Gtk.Widget parent) {
        var about = new Adw.AboutDialog ();
        about.application_name = Config.APP_NAME;
        about.application_icon = Config.APP_ID;
        about.developer_name = "rysas";
        about.version = Config.APP_VERSION;
        about.copyright = "© 2026 rysas";
        about.license_type = Gtk.License.GPL_3_0;
        about.developers = { "rysas" };
        about.add_credit_section (_("Credits"), {
            _("Windower project maintainers"),
            _("Wine, Proton, and DXVK contributors"),
            _("ProtonPlus, Lutris and Winetricks")
        });
        about.add_acknowledgement_section (_("Special Thanks"), {
            _("The Windower Community")
        });
        about.add_legal_section (
            "Square Enix",
            _("(c) 2002-2012 SQUARE ENIX CO., LTD. All Rights Reserved."),
            Gtk.License.CUSTOM,
            _("Title Design by Yoshitaka Amano. FINAL FANTASY and VANA'DIEL are registered trademarks of Square Enix Co., Ltd. SQUARE ENIX, PLAYONLINE and the PlayOnline logo are trademarks of Square Enix Co., Ltd.\n\nAll trademarks or registered trademarks are the property of their respective owners.\n\nWe are not affiliated with SQUARE ENIX CO., LTD. in any way.")
        );
        Widgets.Dialogs.DialogHelpers.present_tracked (parent, about);
    }
}
