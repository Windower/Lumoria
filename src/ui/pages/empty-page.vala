namespace Lumoria.Ui {

    public class EmptyPage : Gtk.Box {
        public signal void create_requested ();

        public EmptyPage () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            hexpand = true;
            vexpand = true;

            var page = new Adw.StatusPage ();
            var mascot = Widgets.IconRegistry.mascot_image (180);
            page.title = _("Get Started");
            page.description = _("Create a Wine prefix to play.");
            page.paintable = mascot.get_paintable ();

            var button = new Gtk.Button.with_label (_("Create a Prefix"));
            button.add_css_class ("suggested-action");
            button.add_css_class ("pill");
            button.halign = Gtk.Align.CENTER;
            button.sensitive = !Utils.EnvironmentInfo.is_gamescope ();
            button.clicked.connect (() => create_requested ());
            page.child = button;
            append (page);
        }
    }
}
