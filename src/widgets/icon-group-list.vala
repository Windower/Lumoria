namespace Lumoria.Widgets {

    /* Group sidebar of the icon picker. Subgroups are listed only under the selected group. */
    public class IconGroupList : Gtk.Box {
        public signal void selection_changed ();

        public string group { get; private set; default = Models.FfxiIconCatalog.GROUP_ALL; }
        public string subgroup { get; private set; default = ""; }

        private Gtk.ListBox list = new Gtk.ListBox ();
        private Models.FfxiIconHits? hits;
        private bool show_recent;
        private bool rebuilding;
        private bool expanded = true;
        private bool selection_moved;

        private class GroupRow : Gtk.ListBoxRow {
            public string group;
            public string subgroup;

            public GroupRow (string title, string group, string subgroup, bool split) {
                this.group = group;
                this.subgroup = subgroup;
                var label = new Gtk.Label (title);
                label.xalign = 0f;
                label.ellipsize = Pango.EllipsizeMode.END;
                label.hexpand = true;
                child = label;
                activatable = true;
                if (subgroup != "") add_css_class ("icon-pick-subgroup");
                if (split) add_css_class ("icon-pick-split");
            }
        }

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            add_css_class ("icon-pick-sidebar");
            list.add_css_class ("icon-pick-groups");
            list.selection_mode = Gtk.SelectionMode.SINGLE;
            list.row_selected.connect (on_row_selected);
            list.row_activated.connect (on_row_activated);
            list.set_filter_func (row_visible);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.has_frame = false;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = list;
            append (scroll);
        }

        public void release () {
            list.set_filter_func (null);
        }

        public override bool grab_focus () {
            return list.grab_focus ();
        }

        /* Points the selection at the group that contains an icon key, without emitting selection_changed. */
        public void select_for_icon (string key) {
            var entry = Models.FfxiIconCatalog.instance ().by_key (key);
            if (key == "" || Models.IconSlots.lookup (key) != null) {
                group = Models.FfxiIconCatalog.GROUP_APP;
            } else if (entry == null || entry.group == "") {
                group = Models.FfxiIconCatalog.GROUP_ALL;
            } else {
                group = entry.group;
            }
            subgroup = "";
            expanded = true;
        }

        public void rebuild (bool show_recent) {
            this.show_recent = show_recent;
            rebuilding = true;
            while (list.get_row_at_index (0) != null) list.remove (list.get_row_at_index (0));

            add_group (Models.FfxiIconCatalog.GROUP_ALL, false);
            if (show_recent) add_group (Models.FfxiIconCatalog.GROUP_RECENT, false);
            add_group (Models.FfxiIconCatalog.GROUP_APP, true);

            foreach (var name in Models.FfxiIconCatalog.instance ().group_names) {
                if (name != Models.FfxiIconCatalog.GROUP_APP) add_group (name, false);
            }
            sync_subgroups ();
            sync_selection ();
            rebuilding = false;
        }

        /* Subgroup rows sit under the selected group while it is expanded; group rows themselves stay put. */
        private void sync_subgroups () {
            int anchor = -1;
            for (var i = 0; ; ) {
                var row = list.get_row_at_index (i) as GroupRow;
                if (row == null) break;
                if (row.subgroup != "") {
                    list.remove (row);
                    continue;
                }
                if (row.group == group) anchor = i;
                i++;
            }
            if (anchor >= 0 && expanded) {
                foreach (var sub in Models.FfxiIconCatalog.instance ().subgroups_for (group)) {
                    list.insert (
                        new GroupRow (Models.FfxiIconCatalog.display_subgroup (sub), group, sub, false),
                        ++anchor
                    );
                }
            }
            list.invalidate_filter ();
        }

        /* Null hits means no search is active. A selection left without hits falls back to All. */
        public void apply_hits (Models.FfxiIconHits? hits) {
            this.hits = hits;
            if (hits != null && !hits.has (group, subgroup)) {
                group = Models.FfxiIconCatalog.GROUP_ALL;
                subgroup = "";
                rebuild (show_recent);
                return;
            }
            list.invalidate_filter ();
            sync_selection ();
        }

        private void add_group (string name, bool split) {
            list.append (new GroupRow (Models.FfxiIconCatalog.display_group (name), name, "", split));
        }

        private bool row_visible (Gtk.ListBoxRow row) {
            var group_row = (GroupRow) row;
            return hits == null || hits.has (group_row.group, group_row.subgroup);
        }

        private void sync_selection () {
            for (var i = 0; ; i++) {
                var row = list.get_row_at_index (i) as GroupRow;
                if (row == null) break;
                if (row.group == group && row.subgroup == subgroup) {
                    list.select_row (row);
                    return;
                }
            }
            list.unselect_all ();
        }

        private void on_row_selected (Gtk.ListBoxRow? row) {
            var group_row = row as GroupRow;
            if (rebuilding || group_row == null) return;
            if (group_row.group == group && group_row.subgroup == subgroup) return;
            var group_changed = group_row.group != group;
            group = group_row.group;
            subgroup = group_row.subgroup;
            /* The click that moved the selection also activates the row; only outlive this event. */
            selection_moved = true;
            Idle.add (() => {
                selection_moved = false;
                return Source.REMOVE;
            });
            if (group_changed) {
                expanded = true;
                sync_subgroups ();
            }
            selection_changed ();
        }

        /* Activating the already-selected group toggles its subgroups; a fresh selection is handled above. */
        private void on_row_activated (Gtk.ListBoxRow row) {
            var group_row = (GroupRow) row;
            if (selection_moved || group_row.subgroup != "" || group_row.group != group || subgroup != "") return;
            if (Models.FfxiIconCatalog.instance ().subgroups_for (group).size == 0) return;
            expanded = !expanded;
            sync_subgroups ();
        }
    }
}
