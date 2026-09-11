namespace Lumoria.Widgets {

    public class LaunchTile : Gtk.Widget {
        public const string QUICK_LAUNCH_ID = "quick-launch";
        private const int TILE_MAX = 280;

        public signal void reorder (int delta);

        public string tile_id { get; private set; }
        public string prefix_id { get { return entry.id; } }
        public string action_id { get { return action.id; } }

        private Lumoria.Application.Context ctx;
        private Models.PrefixEntry entry;
        private Runtime.LaunchTarget action;
        private bool is_favorite;
        private Gtk.Box? body;
        private IconKeySlot icon_slot;
        private FadeLabel title;
        private FadeLabel prefix;
        private Gtk.Button prefix_btn;
        private Gtk.Button play;

        public LaunchTile (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action,
            bool is_favorite
        ) {
            Object (accessible_role: Gtk.AccessibleRole.GROUP);
            this.ctx = ctx;
            this.entry = entry;
            this.action = action;
            this.is_favorite = is_favorite;
            tile_id = is_favorite
                ? Models.LaunchRef.compose_tile_key (entry.id, action.id)
                : QUICK_LAUNCH_ID;
            build ();
            apply (entry, action);
        }

        public void apply (Models.PrefixEntry entry, Runtime.LaunchTarget action) {
            this.entry = entry;
            this.action = action;
            var text = ActionRows.launch_text (entry, action, null);
            var heading = text.title;
            var prefix_name = entry.display_name ();
            icon_slot.set_key (entry.display_icon (action.id, action.icon));
            title.set_key (heading);
            title.tooltip_text = heading;
            prefix.set_key (prefix_name);
            var open_label = _("Open %s").printf (prefix_name);
            PageChrome.set_icon_label (prefix_btn, open_label);
            var play_label = Utils.sanitize_ui_text (_("Play %s").printf (heading));
            PageChrome.set_icon_label (play, play_label);
            update_property (Gtk.AccessibleProperty.LABEL, Utils.sanitize_ui_text (heading));
            update_property (
                Gtk.AccessibleProperty.DESCRIPTION,
                text.subtitle != "" ? Utils.sanitize_ui_text (text.subtitle) : ""
            );
        }

        private void play_target () {
            ctx.actions.run (entry, action.id);
        }

        public void reload_icon () {
            icon_slot.reload ();
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return body.get_request_mode ();
        }

        public override void measure (
            Gtk.Orientation orientation,
            int for_size,
            out int minimum,
            out int natural,
            out int minimum_baseline,
            out int natural_baseline
        ) {
            body.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            if (orientation == Gtk.Orientation.HORIZONTAL)
                natural = int.max (minimum, TILE_MAX);
        }

        public override void size_allocate (int width, int height, int baseline) {
            body.allocate (width, height, baseline, null);
        }

        public override void dispose () {
            if (body != null) {
                body.unparent ();
                body = null;
            }
            base.dispose ();
        }

        private void build () {
            add_css_class ("launch-tile");
            overflow = Gtk.Overflow.HIDDEN;
            hexpand = true;
            halign = Gtk.Align.FILL;
            valign = Gtk.Align.START;
            body = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            body.set_parent (this);

            title = new FadeLabel.title ("");
            var heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            heading.height_request = 32;
            heading.valign = Gtk.Align.CENTER;
            icon_slot = new IconKeySlot ("");
            heading.append (icon_slot);
            heading.append (title);

            prefix = new FadeLabel.meta ("", true);
            prefix_btn = new Gtk.Button ();
            prefix_btn.child = prefix;
            prefix_btn.add_css_class ("flat");
            prefix_btn.add_css_class ("launch-prefix");
            prefix_btn.hexpand = true;
            prefix_btn.halign = Gtk.Align.FILL;
            prefix_btn.valign = Gtk.Align.CENTER;
            prefix_btn.overflow = Gtk.Overflow.HIDDEN;
            prefix_btn.clicked.connect (() => ctx.state.select_prefix (entry.id));

            var pencil = PageChrome.icon_button (IconRegistry.EDIT, _("Edit"));
            pencil.clicked.connect (() => ActionRows.edit_launch (ctx, entry, action));

            var meta = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            meta.append (prefix_btn);
            meta.append (pencil);
            if (is_favorite) {
                meta.append (new FavoriteButton (ctx, entry, action.id));
                var keys = new Gtk.EventControllerKey ();
                keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
                keys.key_pressed.connect (on_reorder_key);
                add_controller (keys);
                if (Utils.Preferences.instance ().gamepad_navigation) {
                    var up = PageChrome.icon_button (IconRegistry.MOVE_UP, _("Move up"));
                    var down = PageChrome.icon_button (IconRegistry.MOVE_DOWN, _("Move down"));
                    up.clicked.connect (() => reorder (-1));
                    down.clicked.connect (() => reorder (1));
                    meta.append (up);
                    meta.append (down);
                }
            } else {
                var pin = PageChrome.icon_button (
                    IconRegistry.bookmark_icon_name (true),
                    _("Clear Quick Launch")
                );
                pin.add_css_class ("shortcut-active");
                pin.clicked.connect (() => {
                    ctx.state.clear_quick_launch ();
                    ctx.show_toast (_("Quick Launch cleared"));
                });
                meta.append (pin);
            }

            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            text.hexpand = true;
            text.overflow = Gtk.Overflow.HIDDEN;
            text.append (heading);
            text.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            text.append (meta);

            play = new Gtk.Button.from_icon_name (IconRegistry.PAGE_LAUNCH);
            PageChrome.style_play_button (play);
            play.valign = Gtk.Align.CENTER;
            play.clicked.connect (play_target);

            body.append (text);
            body.append (play);
        }

        private bool on_reorder_key (uint keyval, uint keycode, Gdk.ModifierType state) {
            if ((state & Gdk.ModifierType.CONTROL_MASK) == 0) return false;
            if (keyval == Gdk.Key.Up || keyval == Gdk.Key.Left) {
                reorder (-1);
                return true;
            }
            if (keyval == Gdk.Key.Down || keyval == Gdk.Key.Right) {
                reorder (1);
                return true;
            }
            return false;
        }
    }
}
