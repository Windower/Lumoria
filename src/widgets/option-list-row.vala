namespace Lumoria.Widgets {

    public class OptionListItem : Object {
        public string label { get; set; default = ""; }
        public bool is_default { get; set; default = false; }
        public bool recommended { get; set; default = false; }
        public Models.SupportStatus support { get; set; default = Models.SupportStatus.SUPPORTED; }
    }

    public class OptionListRow : Adw.ExpanderRow {
        private uint _selected = 0;
        private Gee.ArrayList<Adw.ActionRow> option_rows;
        private Gee.ArrayList<Gtk.Image> check_icons;
        private Gee.ArrayList<OptionListItem> _items;
        private Gtk.StringList _model;
        private Gtk.Box header_value;
        private bool _suppress_notify = false;

        public uint selected {
            get { return _selected; }
            set { select_index (value); }
        }

        public Gtk.StringList model {
            get { return _model; }
            set { rebuild_from_model (value); }
        }

        public OptionListRow () {
            option_rows = new Gee.ArrayList<Adw.ActionRow> ();
            check_icons = new Gee.ArrayList<Gtk.Image> ();
            _items = new Gee.ArrayList<OptionListItem> ();
            show_enable_switch = false;
            header_value = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            header_value.valign = Gtk.Align.CENTER;
            add_suffix (header_value);
        }

        public void set_items (Gee.ArrayList<OptionListItem> items) {
            var model = new Gtk.StringList (null);
            foreach (var item in items) {
                model.append (item.label);
            }
            _items = items;
            rebuild (model);
        }

        private void rebuild_from_model (Gtk.StringList new_model) {
            var items = new Gee.ArrayList<OptionListItem> ();
            for (uint i = 0; i < new_model.get_n_items (); i++) {
                var item = new OptionListItem ();
                item.label = new_model.get_string (i);
                items.add (item);
            }
            _items = items;
            rebuild (new_model);
        }

        private void rebuild (Gtk.StringList new_model) {
            _suppress_notify = true;
            foreach (var row in option_rows) remove (row);
            option_rows.clear ();
            check_icons.clear ();
            _model = new_model;

            for (uint i = 0; i < _model.get_n_items (); i++) {
                var item = item_at ((int) i);
                var row = new Adw.ActionRow ();
                row.activatable = true;

                var ident = name_pills (item);
                ident.hexpand = true;
                row.add_prefix (ident);

                var check = new Gtk.Image.from_icon_name (IconRegistry.CHECKMARK);
                check.visible = (i == _selected);
                row.add_suffix (check);

                row.activated.connect (on_option_activated);

                add_row (row);
                option_rows.add (row);
                check_icons.add (check);
            }

            update_header_value ();
            _suppress_notify = false;
        }

        private void on_option_activated (Adw.ActionRow row) {
            selected = (uint) option_rows.index_of (row);
            expanded = false;
        }

        private void select_index (uint index) {
            if (index >= option_rows.size) return;
            var prev = _selected;
            _selected = index;

            for (int i = 0; i < check_icons.size; i++) {
                check_icons[i].visible = (i == (int) index);
            }

            update_header_value ();

            if (!_suppress_notify && prev != index) {
                notify_property ("selected");
            }
        }

        private void update_header_value () {
            PageChrome.clear_children (header_value);
            var item = item_at ((int) _selected);
            if (item.label == "") return;

            var name = new Gtk.Label (item.label);
            name.add_css_class ("dim-label");
            name.valign = Gtk.Align.CENTER;
            name.ellipsize = Pango.EllipsizeMode.END;
            header_value.append (name);
            PageChrome.append_item_pills (header_value, item.recommended, item.support);
        }

        private static Gtk.Box name_pills (OptionListItem item) {
            var ident = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            ident.valign = Gtk.Align.CENTER;
            var name = new Gtk.Label (item.label);
            name.xalign = 0f;
            name.valign = Gtk.Align.CENTER;
            name.ellipsize = Pango.EllipsizeMode.END;
            ident.append (name);
            PageChrome.append_item_pills (ident, item.recommended, item.support);
            return ident;
        }

        private OptionListItem item_at (int index) {
            if (index >= 0 && index < _items.size) return _items[index];
            return new OptionListItem ();
        }
    }
}
