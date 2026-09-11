namespace Lumoria.Widgets {

    private class IconCell : Gtk.Button {
        private const int PIXEL_SIZE = 32;

        public signal void picked (string key);

        public string bound_key { get; private set; default = ""; }

        private Gtk.Image image = new Gtk.Image ();
        private Gtk.Label caption = new Gtk.Label (_("Default"));
        private string pending_id = "";

        construct {
            add_css_class ("icon-pick-cell");
            add_css_class ("flat");
            image.pixel_size = PIXEL_SIZE;
            image.hexpand = true;
            image.vexpand = true;
            caption.add_css_class ("caption");
            caption.hexpand = true;
            caption.vexpand = true;
            var column = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            column.append (image);
            column.append (caption);
            child = column;
        }

        public override void clicked () {
            picked (bound_key);
        }

        public void bind (Models.FfxiIconPick pick, bool selected) {
            bound_key = pick.key;
            var label = Utils.sanitize_ui_text (pick.label);
            tooltip_markup = pick.key == ""
                ? Markup.escape_text (label)
                : "%s\n<tt><small>id: %s</small></tt>".printf (Markup.escape_text (label), Markup.escape_text (pick.key));
            update_property (Gtk.AccessibleProperty.LABEL, label);
            show_selected (selected);
            caption.visible = pick.key == "";
            image.visible = !caption.visible;
            pending_id = Models.FfxiIconCatalog.id_from_key (pick.key) ?? "";
            IconRegistry.apply_icon_key (image, pending_id != "" ? "" : pick.key, PIXEL_SIZE);
            load_pending_texture ();
        }

        public void unbind () {
            bound_key = "";
            pending_id = "";
            show_selected (false);
        }

        public void show_selected (bool selected) {
            if (selected) add_css_class ("selected");
            else remove_css_class ("selected");
        }

        public void load_pending_texture () {
            if (pending_id == "") return;
            var texture = FfxiIconTextures.instance ().request (pending_id);
            if (texture == null) return;
            image.set_from_paintable (texture);
            pending_id = "";
        }
    }

    public class IconPicker : Gtk.Box {
        public signal void icon_changed (string key);

        public string selected_icon { get; private set; default = ""; }
        public string default_icon { get; private set; default = ""; }

        private Lumoria.Application.Context ctx;
        private Gtk.SearchEntry search;
        private IconGroupList groups;
        private Gtk.Stack body_stack;
        private Gtk.Spinner spinner;
        private Gtk.Label status;
        private Gtk.Button retry;
        private GLib.ListStore store;
        private Gtk.SingleSelection selection;
        private Gtk.GridView grid;
        private Utils.Debouncer search_refill;
        private ulong catalog_changed_id = 0;
        private ulong resources_changed_id = 0;
        private ulong textures_decoded_id = 0;

        public IconPicker (
            Lumoria.Application.Context ctx,
            string icon,
            string default_icon
        ) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
            this.ctx = ctx;
            this.default_icon = Models.FfxiIconCatalog.sanitize_slot_key (default_icon);
            selected_icon = icon;
            search_refill = new Utils.Debouncer (80, refill);
            build_ui ();
        }

        private void build_ui () {
            add_css_class ("card");
            overflow = Gtk.Overflow.HIDDEN;
            hexpand = true;
            vexpand = true;
            margin_start = Lumoria.Ui.Metrics.PAGE_MARGIN;
            margin_end = Lumoria.Ui.Metrics.PAGE_MARGIN;
            margin_top = Lumoria.Ui.Metrics.GROUP_SPACING;

            search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search icons");
            search.hexpand = true;
            search.search_changed.connect (search_refill.schedule);

            groups = new IconGroupList ();
            groups.selection_changed.connect (refill);
            groups.select_for_icon (selected_icon);

            spinner = new Gtk.Spinner ();
            spinner.spinning = true;
            spinner.halign = Gtk.Align.CENTER;
            spinner.valign = Gtk.Align.CENTER;
            spinner.width_request = 32;
            spinner.height_request = 32;
            status = new Gtk.Label ("");
            status.add_css_class ("dim-label");
            status.wrap = true;
            status.justify = Gtk.Justification.CENTER;
            retry = new Gtk.Button.with_label (_("Retry"));
            retry.halign = Gtk.Align.CENTER;
            retry.clicked.connect (() => {
                Lumoria.Application.ResourceStore.instance ().ensure_async (true, (error) => sync_status ());
            });
            var loading = new Gtk.Box (Gtk.Orientation.VERTICAL, Lumoria.Ui.Metrics.GROUP_SPACING);
            loading.valign = Gtk.Align.CENTER;
            loading.halign = Gtk.Align.CENTER;
            loading.hexpand = true;
            loading.vexpand = true;
            loading.append (spinner);
            loading.append (status);
            loading.append (retry);

            store = new GLib.ListStore (typeof (Models.FfxiIconPick));
            selection = new Gtk.SingleSelection (store);
            selection.autoselect = false;
            selection.can_unselect = true;

            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect (on_setup);
            factory.bind.connect (on_bind);
            factory.unbind.connect ((obj) => ((IconCell) ((Gtk.ListItem) obj).child).unbind ());
            grid = new Gtk.GridView (selection, factory);
            grid.add_css_class ("icon-pick-grid");
            grid.max_columns = 8;
            grid.min_columns = 4;
            grid.single_click_activate = false;
            grid.enable_rubberband = false;
            grid.activate.connect (on_activate);

            var icon_scroll = new Gtk.ScrolledWindow ();
            icon_scroll.vexpand = true;
            icon_scroll.hexpand = true;
            icon_scroll.has_frame = false;
            icon_scroll.child = grid;

            body_stack = new Gtk.Stack ();
            body_stack.hexpand = true;
            body_stack.vexpand = true;
            body_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            body_stack.transition_duration = 220;
            body_stack.add_named (loading, "loading");
            body_stack.add_named (icon_scroll, "grid");

            var right = new Gtk.Box (Gtk.Orientation.VERTICAL, Lumoria.Ui.Metrics.EDITOR_INSET);
            right.add_css_class ("icon-pick-icons");
            right.hexpand = true;
            right.vexpand = true;
            right.append (search);
            right.append (body_stack);

            append (groups);
            append (new Gtk.Separator (Gtk.Orientation.VERTICAL));
            append (right);

            catalog_changed_id = Models.FfxiIconCatalog.instance ().changed.connect (on_catalog_changed);
            resources_changed_id = Lumoria.Application.ResourceStore.instance ().changed.connect (sync_status);
            textures_decoded_id = FfxiIconTextures.instance ().decoded.connect (load_visible_textures);
            destroy.connect (release_sources);

            groups.rebuild (visible_recents ().size > 0);
            refill ();
            Idle.add (() => {
                groups.grab_focus ();
                return false;
            });
        }

        public void release_sources () {
            search_refill.release ();
            groups.release ();
            if (catalog_changed_id != 0) {
                Models.FfxiIconCatalog.instance ().disconnect (catalog_changed_id);
                catalog_changed_id = 0;
            }
            if (resources_changed_id != 0) {
                Lumoria.Application.ResourceStore.instance ().disconnect (resources_changed_id);
                resources_changed_id = 0;
            }
            if (textures_decoded_id != 0) {
                FfxiIconTextures.instance ().disconnect (textures_decoded_id);
                textures_decoded_id = 0;
            }
        }

        public void reset_to_default () {
            groups.select_for_icon (default_icon);
            groups.rebuild (visible_recents ().size > 0);
            pick_icon (default_icon);
            refill ();
        }

        private void on_catalog_changed () {
            groups.select_for_icon (selected_icon);
            groups.rebuild (visible_recents ().size > 0);
            refill ();
        }

        private void show_loading (string label, bool can_retry) {
            status.label = label;
            retry.visible = can_retry;
            spinner.spinning = !can_retry;
            spinner.visible = !can_retry;
            body_stack.visible_child_name = "loading";
        }

        private void sync_status () {
            var resources = Lumoria.Application.ResourceStore.instance ();
            var catalog = Models.FfxiIconCatalog.instance ();
            if (resources.busy) {
                show_loading (_("Downloading icons…"), false);
            } else if (resources.last_error != "") {
                show_loading (resources.last_error, true);
            } else if (!catalog.ready) {
                show_loading (_("Icons are not available yet."), true);
            } else {
                body_stack.visible_child_name = "grid";
            }
        }

        private void refill () {
            var query = search.text.strip ().down ();
            groups.apply_hits (query != "" ? hits_for (query) : null);

            var picks = new Gee.ArrayList<Object> ();
            var catalog = Models.FfxiIconCatalog.instance ();
            if (groups.group == Models.FfxiIconCatalog.GROUP_RECENT) {
                foreach (var key in visible_recents ()) {
                    var pick = pick_for_key (key);
                    if (pick != null && item_matches (pick, query)) picks.add (pick);
                }
            } else {
                if (groups.subgroup == ""
                    && (groups.group == Models.FfxiIconCatalog.GROUP_ALL
                        || groups.group == Models.FfxiIconCatalog.GROUP_APP)) {
                    foreach (var pick in app_picks ()) {
                        if (item_matches (pick, query)) picks.add (pick);
                    }
                }
                foreach (var icon in catalog.icons) {
                    if (catalog.matches (icon, groups.group, groups.subgroup, query)) {
                        picks.add (new Models.FfxiIconPick.from_icon (icon));
                    }
                }
            }
            store.splice (0, store.get_n_items (), picks.to_array ());
            highlight_current ();
            sync_status ();
        }

        /* Catalog hits plus the two synthetic groups the catalog knows nothing about. */
        private Models.FfxiIconHits hits_for (string query) {
            var hits = Models.FfxiIconCatalog.instance ().hits_for (query);
            foreach (var pick in app_picks ()) {
                if (!item_matches (pick, query)) continue;
                hits.add (Models.FfxiIconCatalog.GROUP_APP, "");
                break;
            }
            foreach (var key in visible_recents ()) {
                var pick = pick_for_key (key);
                if (pick == null || !item_matches (pick, query)) continue;
                hits.add (Models.FfxiIconCatalog.GROUP_RECENT, "");
                break;
            }
            return hits;
        }

        private static bool item_matches (Models.FfxiIconPick item, string query) {
            return query == "" || item.search_text.contains (query);
        }

        private Gee.ArrayList<string> visible_recents () {
            return ctx.state.visible_recent_icons ();
        }

        private Models.FfxiIconPick? pick_for_key (string key) {
            foreach (var item in app_picks ()) {
                if (item.key == key) return item;
            }
            var icon = Models.FfxiIconCatalog.instance ().by_key (key);
            return icon != null ? new Models.FfxiIconPick.from_icon (icon) : null;
        }

        private Models.FfxiIconPick[] app_picks () {
            return Models.IconSlots.picker_slots (default_icon == "");
        }

        private void pick_icon (string key) {
            selected_icon = key;
            icon_changed (key);
            highlight_current ();
        }

        private void highlight_current () {
            var n = store.get_n_items ();
            var found = Gtk.INVALID_LIST_POSITION;
            for (uint i = 0; i < n; i++) {
                if (((Models.FfxiIconPick) store.get_item (i)).key == selected_icon) {
                    found = i;
                    break;
                }
            }
            if (found != Gtk.INVALID_LIST_POSITION) {
                selection.selected = found;
                grid.scroll_to (found, Gtk.ListScrollFlags.FOCUS | Gtk.ListScrollFlags.SELECT, null);
            } else {
                selection.unselect_all ();
            }
            foreach_cell ((cell) => cell.show_selected (cell.bound_key == selected_icon));
        }

        private void load_visible_textures () {
            foreach_cell ((cell) => cell.load_pending_texture ());
        }

        private delegate void CellVisitor (IconCell cell);

        private void foreach_cell (CellVisitor visit) {
            for (var child = grid.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var cell = child.get_first_child () as IconCell;
                if (cell != null) visit (cell);
            }
        }

        private void on_activate (uint pos) {
            var item = store.get_item (pos) as Models.FfxiIconPick;
            if (item != null) pick_icon (item.key);
        }

        private void on_setup (Object obj) {
            var cell = new IconCell ();
            cell.picked.connect (pick_icon);
            ((Gtk.ListItem) obj).child = cell;
        }

        private void on_bind (Object obj) {
            var list_item = (Gtk.ListItem) obj;
            var pick = (Models.FfxiIconPick) list_item.item;
            ((IconCell) list_item.child).bind (pick, pick.key == selected_icon);
        }
    }
}
