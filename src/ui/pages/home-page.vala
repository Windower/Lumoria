namespace Lumoria.Ui {

    public class HomePage : Gtk.Box {
        private Application.Context ctx;
        private Gtk.Box content;
        private Gtk.Stack body_stack;
        private Widgets.FlowReorder? favorites_reorder;
        private uint prune_id = 0;
        private Gee.HashMap<string, Widgets.LaunchTile> tiles;
        private Gtk.MenuButton open_to_btn;
        private SimpleAction open_to_action;
        private string last_pins = "";
        private Utils.Debouncer favorites_fill;

        public HomePage (Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            tiles = new Gee.HashMap<string, Widgets.LaunchTile> ();
            favorites_fill = new Utils.Debouncer (0, fill_favorites);
            hexpand = true;
            vexpand = true;
            content = new Gtk.Box (Gtk.Orientation.VERTICAL, Metrics.GROUP_SPACING);
            content.margin_start = Metrics.PAGE_MARGIN;
            content.margin_end = Metrics.PAGE_MARGIN;
            content.margin_top = Metrics.PAGE_MARGIN;
            append (content);
            build_chrome ();
            ctx.state.changed.connect (refresh_tiles);
            ctx.prefixes.changed.connect (refresh_tiles);
            ctx.actions.changed.connect (refresh_tiles);
            Models.FfxiIconCatalog.instance ().changed.connect (reload_icons);
            Utils.Preferences.instance ().gamepad_navigation_changed.connect (rebuild_cards);
            Utils.Preferences.instance ().notify["startup-view"].connect (sync_open_to);
            map.connect (on_map);
            destroy.connect (cancel_pending);
            rebuild_cards ();
        }

        private void on_map () {
            reload_icons ();
            refresh_tiles ();
        }

        private void cancel_pending () {
            favorites_fill.cancel ();
            Widgets.FadeSlot.cancel_prune (ref prune_id);
        }

        private void reload_icons () {
            foreach (var tile in tiles.values) tile.reload_icon ();
        }

        private void refresh_tiles () {
            if (pins_key () == last_pins && patch_tiles ()) return;
            rebuild_cards ();
        }

        private string pins_key () {
            var key = new StringBuilder ();
            if (Utils.Preferences.instance ().gamepad_navigation) key.append ("g");
            var ql = ctx.state.quick_launch;
            key.append (ql.prefix_id);
            foreach (var fav in ctx.state.favorites) {
                key.append_c ('\n');
                key.append (fav.tile_key ());
            }
            return key.str;
        }

        private bool patch_tiles () {
            if (!patch_tile (Widgets.LaunchTile.QUICK_LAUNCH_ID, ctx.state.quick_launch, true)) return false;
            foreach (var fav in ctx.state.favorites) {
                if (!patch_tile (fav.tile_key (), fav, false)) return false;
            }
            return true;
        }

        private bool resolve_target (
            Models.LaunchRef target,
            bool use_default,
            bool allow_list,
            out Models.PrefixEntry? entry,
            out Runtime.LaunchTarget? action
        ) throws Error {
            entry = ctx.registry.by_id (target.prefix_id);
            action = null;
            if (entry == null) return false;
            if (use_default) {
                action = ctx.actions.default_launch (entry);
            } else if (allow_list || ctx.actions.has_cached (entry.id)) {
                action = ctx.actions.find (entry, target.action_id);
                if (action != null && !action.pinnable) action = null;
            }
            return action != null;
        }

        /* Quick Launch resolves the prefix default and may legitimately have no tile; favorites are exact. */
        private bool patch_tile (string tile_id, Models.LaunchRef target, bool is_quick_launch) {
            Models.PrefixEntry? entry;
            Runtime.LaunchTarget? action;
            try {
                if (!resolve_target (target, is_quick_launch, true, out entry, out action)) {
                    return is_quick_launch && !tiles.has_key (tile_id);
                }
            } catch (Error e) {
                warning ("Failed to refresh launch tile %s: %s", tile_id, e.message);
                return false;
            }
            var tile = tiles.get (tile_id);
            if (tile == null) return false;
            tile.apply (entry, action);
            return true;
        }

        private void build_chrome () {
            content.append (quick_launch_heading ());
            body_stack = new Gtk.Stack ();
            body_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            body_stack.transition_duration = 480;
            body_stack.interpolate_size = true;
            body_stack.hexpand = true;
            content.append (body_stack);
        }

        private void present_page (Gtk.Widget page) {
            if (body_stack.visible_child != null) {
                body_stack.transition_duration = 480;
                body_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            }
            Widgets.FadeSlot.present_child (body_stack, page, ref prune_id);
        }

        private void rebuild_cards () {
            last_pins = pins_key ();
            favorites_fill.cancel ();
            present_body (false);
        }

        private void present_body (bool allow_list) {
            var ready = ctx.state.favorites.size == 0 || allow_list || favorites_cached ();
            if (!ready) {
                favorites_fill.schedule ();
                if (body_stack.visible_child != null) {
                    replace_quick_launch ();
                    return;
                }
            }

            tiles.clear ();
            var page = new Gtk.Box (Gtk.Orientation.VERTICAL, Metrics.GROUP_SPACING);
            page.hexpand = true;
            page.append (quick_launch_flow ());
            page.append (section_label (_("Favorites")));
            page.append (favorites_child (ready));
            present_page (page);
        }

        private void replace_quick_launch () {
            var page = body_stack.visible_child as Gtk.Box;
            if (page == null) return;
            tiles.unset (Widgets.LaunchTile.QUICK_LAUNCH_ID);
            var old = page.get_first_child ();
            page.prepend (quick_launch_flow ());
            if (old != null) page.remove (old);
        }

        private Gtk.Widget quick_launch_flow () {
            var top = make_flow ();
            var ql = card_for_target (ctx.state.quick_launch, true, false, _("Could not load Quick Launch"));
            if (ql != null) top.append (ql);
            top.append (create_prefix_card ());
            return top;
        }

        private Gtk.Widget favorites_child (bool allow_list) {
            favorites_reorder = null;
            if (ctx.state.favorites.size == 0) return empty_favorites ();

            var grid = make_flow ();
            var reorder = new Widgets.FlowReorder (grid, move_favorite);
            var added = 0;
            foreach (var fav in ctx.state.favorites) {
                var card = card_for_target (fav, allow_list, true, _("Could not load favorite"));
                if (card == null) continue;
                grid.append (card);
                var tile = card as Widgets.LaunchTile;
                if (tile != null) reorder.add_item (tile, tile.tile_id);
                added++;
            }
            if (added == 0) {
                var failed = new Gtk.Label (_("Some favorites could not be loaded."));
                failed.add_css_class ("dim-label");
                failed.wrap = true;
                failed.xalign = 0f;
                return failed;
            }
            favorites_reorder = reorder;
            return grid;
        }

        private bool favorites_cached () {
            var seen = new Gee.HashSet<string> ();
            foreach (var fav in ctx.state.favorites) {
                if (fav.prefix_id == "" || !seen.add (fav.prefix_id)) continue;
                if (!ctx.actions.has_cached (fav.prefix_id)) return false;
            }
            return true;
        }

        private void fill_favorites () {
            if (ctx.state.page == Application.PageKind.HOME) present_body (true);
        }

        private Gtk.FlowBox make_flow () {
            var grid = new Gtk.FlowBox ();
            grid.selection_mode = Gtk.SelectionMode.NONE;
            grid.homogeneous = true;
            grid.max_children_per_line = 6;
            grid.min_children_per_line = 1;
            grid.row_spacing = 12;
            grid.column_spacing = 12;
            grid.add_css_class ("launch-tiles-flow");
            return grid;
        }

        private Gtk.Widget empty_favorites () {
            var empty = new Gtk.Label (_("Favorite a launch entry from a prefix."));
            empty.add_css_class ("dim-label");
            empty.wrap = true;
            empty.xalign = 0f;
            return empty;
        }

        private Gtk.Label section_label (string title) {
            var label = new Gtk.Label (title);
            label.add_css_class ("heading");
            label.xalign = 0f;
            label.margin_top = 4;
            return label;
        }

        private Gtk.Widget quick_launch_heading () {
            var heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            heading.margin_top = 4;
            var label = new Gtk.Label (_("Quick Launch"));
            label.add_css_class ("heading");
            label.xalign = 0f;
            label.valign = Gtk.Align.CENTER;
            heading.append (label);
            var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            heading.append (spacer);

            var caption = new Gtk.Label (_("Open To"));
            caption.add_css_class ("caption");
            caption.add_css_class ("dim-label");
            caption.valign = Gtk.Align.CENTER;

            open_to_btn = new Gtk.MenuButton ();
            open_to_btn.add_css_class ("flat");
            open_to_btn.add_css_class ("home-open-to");
            open_to_btn.valign = Gtk.Align.CENTER;
            open_to_btn.has_frame = false;
            open_to_btn.always_show_arrow = true;
            Widgets.PageChrome.set_icon_label (open_to_btn, _("Open To"));

            var group = new SimpleActionGroup ();
            open_to_action = new SimpleAction.stateful (
                "open-to",
                new VariantType ("s"),
                new Variant.string (Utils.Preferences.instance ().startup_view.to_key ())
            );
            open_to_action.activate.connect (on_open_to_activated);
            group.add_action (open_to_action);
            heading.insert_action_group ("home", group);
            open_to_btn.menu_model = Widgets.StartupViewControl.menu ("home.open-to");
            sync_open_to ();

            heading.append (caption);
            heading.append (open_to_btn);
            return heading;
        }

        private void on_open_to_activated (Variant? target) {
            if (target == null) return;
            open_to_action.set_state (target);
            var prefs = Utils.Preferences.instance ();
            prefs.startup_view = Utils.StartupView.from_key (target.get_string ());
            open_to_btn.label = Widgets.StartupViewControl.label (prefs.startup_view);
        }

        private void sync_open_to () {
            var view = Utils.Preferences.instance ().startup_view;
            if (open_to_action != null) open_to_action.set_state (new Variant.string (view.to_key ()));
            if (open_to_btn != null) open_to_btn.label = Widgets.StartupViewControl.label (view);
        }

        private Gtk.Widget create_prefix_card () {
            var logo = Widgets.IconRegistry.mascot_image (40);
            logo.valign = Gtk.Align.CENTER;

            var title = new Gtk.Label (_("Create a Prefix"));
            title.add_css_class ("title-3");
            title.xalign = 0f;
            title.wrap = true;
            title.hexpand = true;
            title.valign = Gtk.Align.CENTER;

            var inner = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            inner.append (logo);
            inner.append (title);

            var card = new Gtk.Button ();
            card.child = inner;
            card.add_css_class ("launch-tile");
            card.add_css_class ("flat");
            card.add_css_class ("create-prefix-tile");
            card.halign = Gtk.Align.FILL;
            card.valign = Gtk.Align.FILL;
            card.sensitive = !Utils.EnvironmentInfo.is_gamescope ();
            Widgets.PageChrome.set_icon_label (card, _("Create a Prefix"));
            card.clicked.connect (show_create_prefix);
            return card;
        }

        private Gtk.Widget? card_for_target (
            Models.LaunchRef target,
            bool allow_list,
            bool favorite,
            string error_title
        ) {
            Models.PrefixEntry? entry;
            Runtime.LaunchTarget? action;
            try {
                if (!resolve_target (target, !favorite, allow_list, out entry, out action)) return null;
            } catch (Error e) {
                return resolve_error_card (error_title, e);
            }
            var tile = new Widgets.LaunchTile (ctx, entry, action, favorite);
            tiles[tile.tile_id] = tile;
            if (favorite) tile.reorder.connect (on_tile_reorder);
            return tile;
        }

        private void show_create_prefix () {
            ctx.state.show_page (Application.PageKind.CREATE_PREFIX);
        }

        private void on_tile_reorder (Widgets.LaunchTile tile, int delta) {
            ctx.state.move_favorite_by (tile.prefix_id, tile.action_id, delta);
        }

        private Gtk.Widget resolve_error_card (string title, Error e) {
            var row = Widgets.PageChrome.error_row (title, e);
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            card.add_css_class ("launch-tile");
            var group = Widgets.PageChrome.untitled_group ();
            group.add (row);
            card.append (group);
            return card;
        }

        private bool move_favorite (string raw, int dest) {
            string prefix_id;
            string action_id;
            if (!Models.LaunchRef.parse_tile_key (raw, out prefix_id, out action_id)) {
                return false;
            }
            ctx.state.move_favorite (prefix_id, action_id, dest);
            return true;
        }

    }
}
