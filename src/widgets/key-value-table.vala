namespace Lumoria.Widgets {

    public class KeyValueRow : Gtk.Box {
        public signal void changed ();
        public signal void remove_requested (KeyValueRow row);

        private Gtk.Entry key_entry;
        private Gtk.Widget value_widget;
        private Gtk.Button remove_btn;

        public KeyValueRow (string key, string key_placeholder, Gtk.Widget value, string remove_tooltip) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 6);
            margin_top = 3;
            margin_bottom = 3;

            key_entry = new Gtk.Entry ();
            key_entry.placeholder_text = key_placeholder;
            key_entry.width_chars = 8;
            key_entry.hexpand = false;
            key_entry.text = key;
            key_entry.changed.connect (on_changed);
            append (key_entry);

            value_widget = value;
            value.hexpand = true;
            if (value is Gtk.Editable) ((Gtk.Editable) value).changed.connect (on_changed);
            else if (value is Gtk.DropDown) value.notify["selected"].connect (on_changed);
            append (value);

            remove_btn = new Gtk.Button.from_icon_name (IconRegistry.DELETE);
            if (remove_tooltip != "") PageChrome.set_icon_label (remove_btn, remove_tooltip);
            remove_btn.add_css_class ("flat");
            remove_btn.valign = Gtk.Align.CENTER;
            remove_btn.clicked.connect (request_remove);
            append (remove_btn);
        }

        /* Insensitive fields that show the expected content; the table adds a real row when it is clicked. */
        public KeyValueRow.placeholder (string key_placeholder, string value_placeholder) {
            var value_entry = new Gtk.Entry ();
            value_entry.placeholder_text = value_placeholder;
            value_entry.width_chars = 4;
            this ("", key_placeholder, value_entry, "");
            key_entry.sensitive = false;
            value_entry.sensitive = false;
            remove_btn.sensitive = false;
        }

        public string key_text () {
            return key_entry.text;
        }

        public Gtk.Widget value () {
            return value_widget;
        }

        private void on_changed () {
            changed ();
        }

        private void request_remove () {
            remove_requested (this);
        }
    }

    public class KeyValueTable : Gtk.Box {
        public signal void changed ();
        public signal void add_requested ();

        private Gtk.Box rows_box;
        private Gtk.Widget placeholder;
        private Gee.ArrayList<KeyValueRow> rows;

        public KeyValueTable (
            string key_header,
            string value_header,
            string add_label,
            string key_placeholder = "",
            string value_placeholder = ""
        ) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 10);
            rows = new Gee.ArrayList<KeyValueRow> ();

            var table_frame = new Gtk.Frame (null);
            table_frame.hexpand = true;

            var table_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            PageChrome.margins (header, 10, 8);
            var key_label = new Gtk.Label (key_header);
            key_label.xalign = 0f;
            key_label.width_chars = 8;
            key_label.add_css_class ("heading");
            header.append (key_label);
            var value_label = new Gtk.Label (value_header);
            value_label.xalign = 0f;
            value_label.hexpand = true;
            value_label.add_css_class ("heading");
            header.append (value_label);
            table_box.append (header);
            table_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            rows_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            PageChrome.margins (rows_box, 10, 6);
            placeholder = new KeyValueRow.placeholder (
                key_placeholder != "" ? key_placeholder : key_header,
                value_placeholder != "" ? value_placeholder : value_header
            );
            var click = new Gtk.GestureClick ();
            click.released.connect (request_add);
            placeholder.add_controller (click);
            rows_box.append (placeholder);
            table_box.append (rows_box);
            table_frame.child = table_box;
            append (table_frame);

            var add_btn = new Gtk.Button ();
            var add_btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var add_icon = new Gtk.Image ();
            add_icon.icon_name = IconRegistry.ADD;
            add_icon.pixel_size = 16;
            add_btn_box.append (add_icon);
            add_btn_box.append (new Gtk.Label (add_label));
            add_btn.child = add_btn_box;
            add_btn.add_css_class ("flat");
            add_btn.add_css_class ("env-add-btn");
            add_btn.tooltip_text = add_label;
            add_btn.halign = Gtk.Align.START;
            add_btn.clicked.connect (request_add);
            append (add_btn);
        }

        public Gee.List<KeyValueRow> all_rows () {
            return rows;
        }

        public void add_row (KeyValueRow row) {
            row.changed.connect (on_row_changed);
            row.remove_requested.connect (remove_row);
            rows.add (row);
            rows_box.append (row);
            sync_placeholder ();
        }

        private void request_add () {
            add_requested ();
        }

        private void on_row_changed () {
            changed ();
        }

        private void remove_row (KeyValueRow row) {
            rows.remove (row);
            rows_box.remove (row);
            sync_placeholder ();
            changed ();
        }

        private void sync_placeholder () {
            placeholder.visible = rows.size == 0;
        }

        public static Gee.ArrayList<string> sorted_keys (Gee.HashMap<string, string>? values) {
            var keys = new Gee.ArrayList<string> ();
            if (values == null) return keys;
            foreach (var entry in values.entries) {
                keys.add (entry.key);
            }
            keys.sort ((a, b) => strcmp (a, b));
            return keys;
        }
    }

    /* A validated key/value table: subclasses supply the value widget and per-row rules. */
    public abstract class KeyValueEditor : Gtk.Box {
        public signal void changed ();
        public signal void committed (Gee.HashMap<string, string> values);

        protected KeyValueTable table;
        private Gtk.Label? validation;

        protected KeyValueEditor (
            string key_header,
            string value_header,
            string add_label,
            Gee.HashMap<string, string>? initial_values
        ) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            table = new KeyValueTable (key_header, value_header, add_label);
            table.changed.connect (emit_changed);
            table.add_requested.connect (add_default_row);
            append (table);
            foreach (var key in KeyValueTable.sorted_keys (initial_values)) {
                add_row (key, initial_values[key]);
            }
        }

        protected abstract void add_row (string key, string value);
        protected abstract void add_default_row ();
        protected abstract string value_of (KeyValueRow row);
        protected abstract string? pair_error (string key, string value);

        /* Rows ignored by both values () and validate (). */
        protected virtual bool skip_row (string key, string value) {
            return key == "" && value == "";
        }

        protected virtual string dedupe_key (string key) {
            return key;
        }

        protected abstract string duplicate_error (string key);

        /* Shows errors in label and emits committed for every valid edit. */
        public void bind_validated (Gtk.Label label) {
            validation = label;
            changed.connect (commit);
        }

        public Gee.HashMap<string, string> values () {
            var result = new Gee.HashMap<string, string> ();
            foreach (var row in table.all_rows ()) {
                var key = row.key_text ().strip ();
                if (key == "") continue;
                result[key] = value_of (row);
            }
            return result;
        }

        public bool validate (out string message) {
            message = "";
            var seen = new Gee.HashSet<string> ();
            foreach (var row in table.all_rows ()) {
                var key = row.key_text ().strip ();
                var value = value_of (row);
                if (skip_row (key, value)) continue;
                var error = pair_error (key, value);
                if (error != null) {
                    message = error;
                    return false;
                }
                if (!seen.add (dedupe_key (key))) {
                    message = duplicate_error (key);
                    return false;
                }
            }
            return true;
        }

        private void commit () {
            string error;
            var ok = validate (out error);
            if (!PageChrome.show_validation (validation, ok, error)) return;
            committed (values ());
        }

        private void emit_changed () {
            changed ();
        }
    }
}
