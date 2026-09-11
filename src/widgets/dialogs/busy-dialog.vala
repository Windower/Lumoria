namespace Lumoria.Widgets.Dialogs {

    public class BusyDialog : DialogHelpers.GamepadDialog {
        public Busy busy { get; private set; }

        private Gtk.Button close_btn;

        public BusyDialog (string status = "") {
            Object (
                title: "",
                content_width: Lumoria.Ui.Metrics.DIALOG_WIDTH_NARROW,
                can_close: false
            );

            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, Lumoria.Ui.Metrics.GROUP_SPACING);
            PageChrome.margins (body, Lumoria.Ui.Metrics.PAGE_MARGIN_WIDE, Lumoria.Ui.Metrics.PAGE_MARGIN_WIDE);
            body.halign = Gtk.Align.FILL;

            busy = new Busy (status);
            body.append (busy);

            close_btn = new Gtk.Button.with_label (_("Close"));
            close_btn.halign = Gtk.Align.CENTER;
            close_btn.visible = false;
            close_btn.clicked.connect (force_close);
            body.append (close_btn);

            set_body (body);
        }

        protected override bool on_gamepad_back () {
            if (!can_close) return false;
            force_close ();
            return true;
        }

        public void set_close_visible (bool visible) {
            close_btn.visible = visible;
            close_btn.sensitive = visible;
        }

        public void fail (string heading, string detail) {
            can_close = true;
            busy.set_status (heading);
            busy.set_detail (detail);
            busy.hide_meter ();
            set_close_visible (true);
        }
    }
}
