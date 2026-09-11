namespace Lumoria.Widgets {

    public class EnvVarsEditor : KeyValueEditor {
        private Regex? key_regex;

        public EnvVarsEditor (Gee.HashMap<string, string>? initial_values = null) {
            base (_("Key"), _("Value"), _("Add Variable"), initial_values);
            try {
                key_regex = new Regex ("^[A-Za-z_][A-Za-z0-9_]*$");
            } catch (RegexError e) {
                warning ("Failed to compile env key regex: %s", e.message);
            }
        }

        protected override void add_row (string key, string value) {
            var value_entry = new Gtk.Entry ();
            value_entry.placeholder_text = _("Value");
            value_entry.width_chars = 4;
            value_entry.text = value;
            table.add_row (new KeyValueRow (key, _("Key"), value_entry, _("Remove variable")));
        }

        protected override void add_default_row () {
            add_row ("", "");
        }

        protected override string value_of (KeyValueRow row) {
            return ((Gtk.Entry) row.value ()).text;
        }

        protected override string? pair_error (string key, string value) {
            if (key == "") return _("Environment variable key cannot be empty.");
            if (key_regex != null && !key_regex.match (key)) return _("Invalid env key: %s").printf (key);
            return null;
        }

        protected override string duplicate_error (string key) {
            return _("Duplicate env key: %s").printf (key);
        }
    }

    private class DllModeItem : Object {
        public string id { get; set; }
        public string label { get; set; }

        public DllModeItem (string id, string label) {
            Object (id: id, label: label);
        }
    }

    public class DllOverridesEditor : KeyValueEditor {
        private const string MODE_NATIVE = "native";
        private const string MODE_BUILTIN = "builtin";
        private const string MODE_NATIVE_BUILTIN = "n,b";
        private const string MODE_BUILTIN_NATIVE = "b,n";
        private const string MODE_DISABLED = "d";

        public DllOverridesEditor (Gee.HashMap<string, string>? initial_values = null) {
            base (_("DLL"), _("Mode"), _("Add Override"), initial_values);
        }

        protected override void add_row (string dll, string mode) {
            table.add_row (new KeyValueRow (dll, _("DLL"), mode_dropdown (mode), _("Remove override")));
        }

        protected override void add_default_row () {
            add_row ("", MODE_NATIVE);
        }

        protected override string value_of (KeyValueRow row) {
            var item = ((Gtk.DropDown) row.value ()).selected_item as DllModeItem;
            return item != null ? item.id : "";
        }

        protected override bool skip_row (string dll, string mode) {
            return dll == "";
        }

        protected override string dedupe_key (string dll) {
            return dll.down ();
        }

        protected override string? pair_error (string dll, string mode) {
            if (has_whitespace (dll) || dll.contains (";") || dll.contains ("=")) {
                return _("Invalid DLL name: %s").printf (dll);
            }
            if (mode == "") return _("DLL override mode is required for %s").printf (dll);
            return null;
        }

        protected override string duplicate_error (string dll) {
            return _("Duplicate DLL override: %s").printf (dll);
        }

        private static bool has_whitespace (string value) {
            unichar c;
            int i = 0;
            while (value.get_next_char (ref i, out c)) {
                if (c.isspace ()) return true;
            }
            return false;
        }

        private static bool is_known_mode (string id) {
            return id == MODE_NATIVE
                || id == MODE_BUILTIN
                || id == MODE_NATIVE_BUILTIN
                || id == MODE_BUILTIN_NATIVE
                || id == MODE_DISABLED;
        }

        private static Gtk.DropDown mode_dropdown (string mode) {
            var model = new GLib.ListStore (typeof (DllModeItem));
            model.append (new DllModeItem (MODE_NATIVE, _("Native")));
            model.append (new DllModeItem (MODE_BUILTIN, _("Builtin")));
            model.append (new DllModeItem (MODE_NATIVE_BUILTIN, _("Native, Builtin")));
            model.append (new DllModeItem (MODE_BUILTIN_NATIVE, _("Builtin, Native")));
            model.append (new DllModeItem (MODE_DISABLED, _("Disabled")));
            var id = mode.strip ();
            if (id == "") id = MODE_NATIVE;
            if (!is_known_mode (id)) model.append (new DllModeItem (id, id));

            var dropdown = new Gtk.DropDown (model, new Gtk.PropertyExpression (typeof (DllModeItem), null, "label"));
            dropdown.hexpand = true;
            uint selected = 0;
            for (uint i = 0; i < model.get_n_items (); i++) {
                var item = (DllModeItem) model.get_item (i);
                if (item.id == id) {
                    selected = i;
                    break;
                }
            }
            dropdown.selected = selected;
            return dropdown;
        }
    }
}
