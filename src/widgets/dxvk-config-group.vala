namespace Lumoria.Widgets {

    public class DxvkConfigGroup : Gtk.Box {
        /* With for_entry, emitted only after a valid apply; invalid input is toasted instead. */
        public signal void changed ();

        private Adw.SwitchRow advanced_row;
        private Gtk.Box details;
        private Adw.SwitchRow fps_row;
        private Adw.SwitchRow hide_igpu_row;
        private Adw.EntryRow anisotropy_row;
        private Adw.EntryRow max_frame_row;
        private Adw.EntryRow sync_row;
        private Gtk.TextBuffer custom;
        private Lumoria.Application.Context? ctx;
        private Models.PrefixEntry? entry;

        private static bool validate_dxvk_integer (
            string value,
            bool allow_negative,
            string title,
            out string message
        ) {
            var trimmed = value.strip ();
            message = "";
            if (trimmed == "") return true;
            int parsed;
            if (!int.try_parse (trimmed, out parsed)) {
                message = _("%s must be Default or a whole number.").printf (title);
                return false;
            }
            if (!allow_negative && parsed < 0) {
                message = _("%s must be Default or a non-negative whole number.").printf (title);
                return false;
            }
            return true;
        }

        private static bool validate_dxvk_range (
            string value,
            int min,
            int max,
            string title,
            out string message
        ) {
            var trimmed = value.strip ();
            message = "";
            if (trimmed == "") return true;
            int parsed;
            if (!int.try_parse (trimmed, out parsed) || parsed < min || parsed > max) {
                message = _("%s must be Default or a whole number from %d to %d.").printf (title, min, max);
                return false;
            }
            return true;
        }

        public DxvkConfigGroup.for_entry (Lumoria.Application.Context ctx, Models.PrefixEntry entry) {
            this (
                entry.advanced_dxvk,
                entry.dxvk_show_fps,
                entry.dxvk_hide_integrated_graphics,
                entry.dxvk_sampler_anisotropy,
                entry.dxvk_max_frame_rate,
                entry.dxvk_sync_interval,
                entry.dxvk_config_custom
            );
            this.ctx = ctx;
            this.entry = entry;
        }

        private void on_field_changed () {
            if (entry != null) {
                string error;
                if (!validate (out error)) {
                    ctx.show_toast (error);
                    return;
                }
                apply_to_entry (entry);
            }
            changed ();
        }

        private void on_advanced_toggled () {
            details.visible = advanced_row.active;
            on_field_changed ();
        }

        public DxvkConfigGroup (
            bool advanced,
            bool show_fps,
            bool hide_igpu,
            string anisotropy,
            string max_frame,
            string sync_interval,
            string custom_text
        ) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            var dxvk = new PageSection (
                _("DXVK Configuration"),
                _("Leave fields blank to use DXVK defaults.")
            );
            advanced_row = new Adw.SwitchRow ();
            advanced_row.title = _("Advanced DXVK");
            advanced_row.subtitle = _("Write a managed dxvk.conf for this prefix when a DXVK-family component is active.");
            advanced_row.active = advanced;
            advanced_row.notify["active"].connect (on_advanced_toggled);
            dxvk.add (advanced_row);

            details = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            fps_row = new Adw.SwitchRow ();
            fps_row.title = _("Show FPS");
            fps_row.active = show_fps;
            fps_row.notify["active"].connect (on_field_changed);
            details.append (fps_row);

            hide_igpu_row = new Adw.SwitchRow ();
            hide_igpu_row.title = _("Hide Integrated Graphics");
            hide_igpu_row.active = hide_igpu;
            hide_igpu_row.notify["active"].connect (on_field_changed);
            details.append (hide_igpu_row);

            anisotropy_row = new Adw.EntryRow ();
            anisotropy_row.title = _("d3d9.samplerAnisotropy");
            anisotropy_row.text = anisotropy;
            anisotropy_row.notify["text"].connect (on_field_changed);
            details.append (anisotropy_row);

            max_frame_row = new Adw.EntryRow ();
            max_frame_row.title = _("d3d9.maxFrameRate");
            max_frame_row.text = max_frame;
            max_frame_row.notify["text"].connect (on_field_changed);
            details.append (max_frame_row);

            sync_row = new Adw.EntryRow ();
            sync_row.title = _("d3d9.presentInterval");
            sync_row.text = sync_interval;
            sync_row.notify["text"].connect (on_field_changed);
            details.append (sync_row);

            custom = new Gtk.TextBuffer (null);
            custom.set_text (custom_text, -1);
            custom.changed.connect (on_field_changed);
            var view = new Gtk.TextView.with_buffer (custom);
            view.monospace = true;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.child = view;
            scroll.min_content_height = 120;
            scroll.add_css_class ("card");
            details.append (scroll);
            details.visible = advanced;
            dxvk.add (details);
            append (dxvk);
        }

        public bool validate (out string message) {
            if (!validate_dxvk_range (
                anisotropy_row.text, 0, 16, _("Anisotropic Filtering"), out message
            )) {
                return false;
            }
            if (!validate_dxvk_integer (
                max_frame_row.text, true, _("Frame Rate Limit"), out message
            )) {
                return false;
            }
            return validate_dxvk_integer (
                sync_row.text, false, _("Vsync Interval"), out message
            );
        }

        public void apply_to_entry (Models.PrefixEntry entry) {
            entry.advanced_dxvk = advanced_row.active;
            entry.dxvk_show_fps = fps_row.active;
            entry.dxvk_hide_integrated_graphics = hide_igpu_row.active;
            entry.dxvk_sampler_anisotropy = anisotropy_row.text.strip ();
            entry.dxvk_max_frame_rate = max_frame_row.text.strip ();
            entry.dxvk_sync_interval = sync_row.text.strip ();
            entry.dxvk_config_custom = custom_text ();
        }

        private string custom_text () {
            Gtk.TextIter start;
            Gtk.TextIter end;
            custom.get_bounds (out start, out end);
            return custom.get_text (start, end, true);
        }
    }
}
