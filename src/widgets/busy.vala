namespace Lumoria.Widgets {

    public class Busy : Gtk.Box {
        private Gtk.Image mascot;
        private Gtk.Label status_label;
        private Gtk.Label detail_label;
        private Gtk.Stack meter;
        private Gtk.Spinner spinner;
        private Gtk.ProgressBar bar;

        public Busy (string status = "") {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 16);
            hexpand = true;
            mascot = IconRegistry.mascot_image (80);
            append (mascot);

            status_label = new Gtk.Label (status);
            status_label.wrap = true;
            status_label.justify = Gtk.Justification.CENTER;
            status_label.add_css_class ("heading");
            append (status_label);

            detail_label = new Gtk.Label ("");
            detail_label.wrap = true;
            detail_label.justify = Gtk.Justification.CENTER;
            detail_label.add_css_class ("body");
            detail_label.visible = false;
            append (detail_label);

            spinner = new Gtk.Spinner ();
            spinner.spinning = true;
            spinner.halign = Gtk.Align.CENTER;
            spinner.width_request = 32;
            spinner.height_request = 32;

            bar = new Gtk.ProgressBar ();
            bar.show_text = true;
            bar.hexpand = true;

            meter = new Gtk.Stack ();
            meter.add_child (spinner);
            meter.add_child (bar);
            meter.visible_child = spinner;
            append (meter);
        }

        public void set_status (string status) {
            status_label.label = status;
        }

        public void set_detail (string? detail) {
            var text = detail ?? "";
            detail_label.label = text;
            detail_label.visible = text != "";
        }

        public void show_spinner () {
            meter.visible = true;
            spinner.spinning = true;
            meter.visible_child = spinner;
        }

        public void show_progress (double fraction, string text) {
            meter.visible = true;
            spinner.spinning = false;
            bar.fraction = fraction;
            bar.text = text;
            meter.visible_child = bar;
        }

        public void pulse_progress (string text) {
            meter.visible = true;
            spinner.spinning = false;
            bar.pulse ();
            bar.text = text;
            meter.visible_child = bar;
        }

        public void hide_meter () {
            spinner.spinning = false;
            meter.visible = false;
        }
    }
}
