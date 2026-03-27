namespace Lumoria.Widgets {

    public class EnvVarRowWidget : Gtk.Box {
        public signal void changed ();
        public signal void remove_requested (EnvVarRowWidget row);

        private Gtk.Entry key_entry;
        private Gtk.Entry value_entry;

        public EnvVarRowWidget (string key = "", string value = "") {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 6);
            margin_top = 3;
            margin_bottom = 3;
            build_ui (key, value);
        }

        public string key_text () {
            return key_entry.text;
        }

        public string value_text () {
            return value_entry.text;
        }

        private void build_ui (string key, string value) {
            key_entry = new Gtk.Entry ();
            key_entry.placeholder_text = _("KEY");
            key_entry.width_chars = 18;
            key_entry.hexpand = false;
            key_entry.text = key;
            key_entry.changed.connect (() => changed ());
            append (key_entry);

            value_entry = new Gtk.Entry ();
            value_entry.placeholder_text = _("value");
            value_entry.hexpand = true;
            value_entry.text = value;
            value_entry.changed.connect (() => changed ());
            append (value_entry);

            var remove_btn = new Gtk.Button.from_icon_name (IconRegistry.DELETE);
            remove_btn.tooltip_text = _("Remove variable");
            remove_btn.add_css_class ("flat");
            remove_btn.valign = Gtk.Align.CENTER;
            remove_btn.clicked.connect (() => remove_requested (this));
            append (remove_btn);
        }
    }

    public class EnvVarsEditor : Gtk.Box {
        public signal void changed ();

        private Gtk.Box rows_box;
        private Gee.ArrayList<EnvVarRowWidget> rows;
        private Regex? key_regex;

        public EnvVarsEditor (Gee.HashMap<string, string>? initial_values = null) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 10);
            rows = new Gee.ArrayList<EnvVarRowWidget> ();
            try {
                key_regex = new Regex ("^[A-Za-z_][A-Za-z0-9_]*$");
            } catch (RegexError e) {
                warning ("Failed to compile env key regex: %s", e.message);
            }
            build_ui ();
            load_values (initial_values);
        }

        public Gee.HashMap<string, string> values () {
            var result = new Gee.HashMap<string, string> ();
            foreach (var row in rows) {
                var key = row.key_text ().strip ();
                var value = row.value_text ();
                if (key == "" && value == "") continue;
                if (key == "") continue;
                result[key] = value;
            }
            return result;
        }

        public bool validate (out string message) {
            message = "";
            var seen = new Gee.HashSet<string> ();
            foreach (var row in rows) {
                var key = row.key_text ().strip ();
                var value = row.value_text ();

                if (key == "" && value == "") continue;
                if (key == "") {
                    message = _("Environment variable key cannot be empty.");
                    return false;
                }
                if (key_regex != null && !key_regex.match (key)) {
                    message = _("Invalid env key: %s").printf (key);
                    return false;
                }
                if (seen.contains (key)) {
                    message = _("Duplicate env key: %s").printf (key);
                    return false;
                }
                seen.add (key);
            }
            return true;
        }

        private void build_ui () {
            var table_frame = new Gtk.Frame (null);
            table_frame.hexpand = true;

            var table_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            header.margin_start = 10;
            header.margin_end = 10;
            header.margin_top = 8;
            header.margin_bottom = 8;
            var key_header = new Gtk.Label (_("Key"));
            key_header.xalign = 0f;
            key_header.width_chars = 18;
            key_header.add_css_class ("heading");
            header.append (key_header);
            var value_header = new Gtk.Label (_("Value"));
            value_header.xalign = 0f;
            value_header.hexpand = true;
            value_header.add_css_class ("heading");
            header.append (value_header);
            table_box.append (header);
            table_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            rows_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            rows_box.margin_start = 10;
            rows_box.margin_end = 10;
            rows_box.margin_top = 6;
            rows_box.margin_bottom = 6;
            table_box.append (rows_box);
            table_frame.child = table_box;
            append (table_frame);

            var add_btn = new Gtk.Button ();
            var add_btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var add_icon = new Gtk.Image ();
            add_icon.icon_name = IconRegistry.ADD;
            add_icon.pixel_size = 16;
            add_btn_box.append (add_icon);
            add_btn_box.append (new Gtk.Label (_("Add Variable")));
            add_btn.child = add_btn_box;
            add_btn.add_css_class ("flat");
            add_btn.add_css_class ("env-add-btn");
            add_btn.tooltip_text = _("Add Variable");
            add_btn.halign = Gtk.Align.START;
            add_btn.clicked.connect (() => {
                add_row ("", "");
                changed ();
            });
            append (add_btn);
        }

        private void load_values (Gee.HashMap<string, string>? values) {
            if (values == null) return;
            var keys = new Gee.ArrayList<string> ();
            foreach (var entry in values.entries) {
                keys.add (entry.key);
            }
            keys.sort ((a, b) => strcmp (a, b));
            foreach (var key in keys) {
                add_row (key, values[key]);
            }
        }

        private void add_row (string key, string value) {
            var row = new EnvVarRowWidget (key, value);
            row.changed.connect (() => changed ());
            row.remove_requested.connect ((r) => {
                rows.remove (r);
                rows_box.remove (r);
                changed ();
            });
            rows.add (row);
            rows_box.append (row);
        }
    }
}
