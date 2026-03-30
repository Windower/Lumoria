namespace Lumoria.Widgets {

    public class OptionListRow : Adw.ExpanderRow {
        private uint _selected = 0;
        private Gee.ArrayList<Adw.ActionRow> option_rows;
        private Gee.ArrayList<Gtk.Image> check_icons;
        private Gtk.StringList _model;
        private bool _suppress_notify = false;

        public uint selected {
            get { return _selected; }
            set { select_index (value); }
        }

        public Gtk.StringList model {
            get { return _model; }
            set { rebuild (value); }
        }

        public OptionListRow () {
            option_rows = new Gee.ArrayList<Adw.ActionRow> ();
            check_icons = new Gee.ArrayList<Gtk.Image> ();
            show_enable_switch = false;
        }

        private void rebuild (Gtk.StringList new_model) {
            _suppress_notify = true;
            foreach (var row in option_rows) remove (row);
            option_rows.clear ();
            check_icons.clear ();
            _model = new_model;

            for (uint i = 0; i < _model.get_n_items (); i++) {
                var label = _model.get_string (i);
                var row = new Adw.ActionRow ();
                row.title = label;
                row.activatable = true;

                var check = new Gtk.Image.from_icon_name (IconRegistry.CHECKMARK);
                check.visible = (i == _selected);
                row.add_suffix (check);

                var idx = i;
                row.activated.connect (() => {
                    this.selected = idx;
                    expanded = false;
                });

                add_row (row);
                option_rows.add (row);
                check_icons.add (check);
            }

            update_subtitle ();
            _suppress_notify = false;
        }

        private void select_index (uint index) {
            if (index >= option_rows.size) return;
            var prev = _selected;
            _selected = index;

            for (int i = 0; i < check_icons.size; i++) {
                check_icons[i].visible = (i == (int) index);
            }

            update_subtitle ();

            if (!_suppress_notify && prev != index) {
                notify_property ("selected");
            }
        }

        private void update_subtitle () {
            if (_model != null && _selected < _model.get_n_items ()) {
                subtitle = _model.get_string (_selected);
            }
        }
    }
}
