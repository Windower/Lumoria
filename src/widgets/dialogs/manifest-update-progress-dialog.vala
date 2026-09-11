namespace Lumoria.Widgets.Dialogs {

    public class ManifestUpdateProgressDialog : BusyDialog {
        private bool stopped = false;
        private bool applying = false;

        public ManifestUpdateProgressDialog () {
            base (_("Checking for updates…"));
        }

        public void show_checking () {
            stopped = false;
            applying = false;
            can_close = false;
            set_close_visible (false);
            busy.set_status (_("Checking for updates…"));
            busy.set_detail (null);
            busy.show_spinner ();
        }

        public void show_applying (string status = _("Downloading…")) {
            stopped = false;
            applying = true;
            can_close = false;
            set_close_visible (false);
            busy.set_status (status);
            busy.set_detail (null);
            busy.show_progress (0, "");
        }

        public void set_status (string status) {
            if (stopped) return;
            busy.set_status (status);
        }

        public void set_progress (int64 downloaded, int64 total) {
            if (stopped) return;
            if (total > 0) {
                busy.show_progress (
                    (double) downloaded / (double) total,
                    "%s / %s".printf (
                        GLib.format_size ((uint64) downloaded),
                        GLib.format_size ((uint64) total)
                    )
                );
            } else {
                busy.pulse_progress (GLib.format_size ((uint64) downloaded));
            }
        }

        public new void fail (string message, string? heading = null) {
            stopped = true;
            base.fail (
                heading ?? (applying
                    ? _("There was a problem while applying the update.")
                    : _("There was a problem while checking for updates.")),
                message
            );
        }
    }
}
