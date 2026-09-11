namespace Lumoria.Ui {

    public class NavigationSidebar : Gtk.Box {
        public signal void navigated ();

        private class PrefixRow : Adw.ActionRow {
            public string prefix_id;
            public string path = "";

            public PrefixRow (string prefix_id) {
                this.prefix_id = prefix_id;
                title_lines = 1;
                activatable = true;
            }

            public void update (Models.PrefixEntry prefix) {
                title = prefix.display_name ();
                path = prefix.resolved_path ();
            }

            public bool matches (string needle) {
                return title.down ().contains (needle)
                    || path.down ().contains (needle)
                    || prefix_id.down ().contains (needle);
            }
        }

        private class ManageRow : Adw.ActionRow {
            public Application.PageKind kind;

            public ManageRow (string title, Application.PageKind kind, string icon) {
                this.kind = kind;
                this.title = title;
                add_prefix (new Gtk.Image.from_icon_name (icon));
                activatable = true;
            }
        }

        private Application.Context ctx;
        private Gtk.Stack prefixes_stack;
        private Gtk.ListBox prefixes_list;
        private Gtk.ListBox manage_list;
        private Gtk.SearchBar search_bar;
        private Gtk.SearchEntry search_entry;
        private Widgets.ListReorder reorder;
        private Gee.HashMap<string, PrefixRow> rows = new Gee.HashMap<string, PrefixRow> ();
        private uint prune_id = 0;
        private string query = "";
        private bool applying = false;

        public NavigationSidebar (Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            build_ui ();
            ctx.state.changed.connect (sync_selection);
            ctx.prefixes.changed.connect (sync_prefixes);
            ctx.prefixes.list_changed.connect (sync_prefixes);
        }

        public void toggle_search () {
            search_bar.search_mode_enabled = !search_bar.search_mode_enabled;
        }

        private void build_ui () {
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = false;
            header.title_widget = new Gtk.Label (_("Prefixes")) {
                css_classes = { "heading" }
            };

            var search_btn = Widgets.PageChrome.icon_button (Widgets.IconRegistry.SEARCH, _("Search prefixes"));
            search_btn.clicked.connect (toggle_search);
            header.pack_start (search_btn);

            var add_btn = Widgets.PageChrome.icon_button (Widgets.IconRegistry.ADD, _("New Prefix"));
            add_btn.sensitive = !Utils.EnvironmentInfo.is_gamescope ();
            add_btn.clicked.connect (show_create_prefix);
            header.pack_end (add_btn);

            search_entry = new Gtk.SearchEntry ();
            search_entry.placeholder_text = _("Search prefixes");
            search_entry.hexpand = true;
            search_entry.search_changed.connect (on_search_changed);

            search_bar = new Gtk.SearchBar ();
            search_bar.child = search_entry;
            search_bar.show_close_button = true;
            search_bar.key_capture_widget = this;
            search_bar.notify["search-mode-enabled"].connect (on_search_mode_changed);

            prefixes_stack = new Gtk.Stack ();
            prefixes_stack.hexpand = true;
            prefixes_stack.vexpand = true;
            prefixes_stack.transition_duration = 250;
            prefixes_stack.interpolate_size = true;
            destroy.connect (() => Widgets.FadeSlot.cancel_prune (ref prune_id));

            var prefixes_scroll = new Gtk.ScrolledWindow ();
            prefixes_scroll.child = prefixes_stack;
            prefixes_scroll.vexpand = true;
            prefixes_scroll.hexpand = true;

            manage_list = new Gtk.ListBox ();
            manage_list.add_css_class ("navigation-sidebar");
            manage_list.add_css_class ("manage-sidebar");
            manage_list.selection_mode = Gtk.SelectionMode.SINGLE;
            manage_list.append (new ManageRow (_("Runtime"), Application.PageKind.RUNNERS, Widgets.IconRegistry.PAGE_RUNTIME));
            manage_list.append (new ManageRow (_("Storage"), Application.PageKind.STORAGE, Widgets.IconRegistry.PAGE_STORAGE));
            manage_list.append (new ManageRow (_("Preferences"), Application.PageKind.PREFERENCES, Widgets.IconRegistry.MANAGE));
            manage_list.row_activated.connect (on_manage_activated);

            var footer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            footer.add_css_class ("manage-footer");
            footer.append (manage_list);

            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            body.append (prefixes_scroll);
            body.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            body.append (footer);

            var toolbar = new Adw.ToolbarView ();
            toolbar.add_top_bar (header);
            toolbar.add_top_bar (search_bar);
            toolbar.content = body;

            hexpand = true;
            vexpand = true;
            append (toolbar);
            sync_prefixes ();
        }

        private void show_create_prefix () {
            ctx.state.show_page (Application.PageKind.CREATE_PREFIX);
            navigated ();
        }

        private void on_search_changed () {
            apply_query (search_entry.text.strip ());
        }

        private void on_search_mode_changed () {
            if (search_bar.search_mode_enabled) {
                search_entry.grab_focus ();
                return;
            }
            search_entry.text = "";
            apply_query ("");
        }

        /* Rows cannot be dragged while a search hides some of them. */
        private void apply_query (string text) {
            query = text;
            prefixes_list.invalidate_filter ();
            reorder.enabled = query == "";
        }

        private bool prefix_visible (Gtk.ListBoxRow row) {
            return query == "" || ((PrefixRow) row).matches (query.down ());
        }

        private Gtk.Widget make_prefixes_list () {
            prefixes_list = new Gtk.ListBox ();
            prefixes_list.add_css_class ("navigation-sidebar");
            prefixes_list.selection_mode = Gtk.SelectionMode.SINGLE;
            prefixes_list.row_activated.connect (on_prefix_activated);
            prefixes_list.set_filter_func (prefix_visible);
            reorder = new Widgets.ListReorder (prefixes_list, move_prefix);
            reorder.enabled = query == "";
            rows = new Gee.HashMap<string, PrefixRow> ();
            foreach (var prefix in ctx.registry.prefixes) {
                var row = new PrefixRow (prefix.id);
                row.update (prefix);
                prefixes_list.append (row);
                reorder.add_item (row, prefix.id);
                rows[prefix.id] = row;
            }
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            Widgets.PageChrome.margins (box, 6, 4);
            box.append (prefixes_list);
            return box;
        }

        private bool ids_changed () {
            int n = 0;
            foreach (var prefix in ctx.registry.prefixes) {
                var row = prefixes_list.get_row_at_index (n) as PrefixRow;
                if (row == null || row.prefix_id != prefix.id) return true;
                n++;
            }
            return prefixes_list.get_row_at_index (n) != null;
        }

        private void sync_prefixes () {
            if (prefixes_stack.visible_child == null || ids_changed ()) {
                applying = true;
                prefixes_stack.transition_duration = 250;
                prefixes_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
                Widgets.FadeSlot.present_child (prefixes_stack, make_prefixes_list (), ref prune_id);
                applying = false;
                prefixes_list.invalidate_filter ();
                sync_selection ();
                return;
            }
            foreach (var prefix in ctx.registry.prefixes) {
                rows[prefix.id].update (prefix);
            }
        }

        private bool move_prefix (string source_id, int dest) {
            try {
                ctx.prefixes.move_to (source_id, dest);
            } catch (Error e) {
                ctx.show_toast (user_error (e));
                return false;
            }
            return true;
        }

        private void on_prefix_activated (Gtk.ListBoxRow row) {
            if (applying) return;
            ctx.state.select_prefix (((PrefixRow) row).prefix_id);
            sync_selection ();
            navigated ();
        }

        private void on_manage_activated (Gtk.ListBoxRow row) {
            if (applying) return;
            ctx.state.show_page (((ManageRow) row).kind);
            sync_selection ();
            navigated ();
        }

        private void sync_selection () {
            applying = true;
            prefixes_list.unselect_all ();
            manage_list.unselect_all ();
            if (ctx.state.page == Application.PageKind.PREFIX) {
                var row = rows[ctx.state.selected_prefix_id];
                if (row != null) prefixes_list.select_row (row);
            } else {
                var kind = ctx.state.page == Application.PageKind.COMPONENTS
                    ? Application.PageKind.RUNNERS
                    : ctx.state.page;
                for (int i = 0; ; i++) {
                    var row = manage_list.get_row_at_index (i) as ManageRow;
                    if (row == null) break;
                    if (row.kind == kind) {
                        manage_list.select_row (row);
                        break;
                    }
                }
            }
            applying = false;
        }
    }
}
