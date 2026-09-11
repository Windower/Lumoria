namespace Lumoria.Widgets {

    public abstract class FadeSlot : Gtk.Box {
        private Gtk.Stack stack;
        private string current = "";
        private uint prune_id = 0;

        construct {
            orientation = Gtk.Orientation.HORIZONTAL;
            spacing = 0;
            overflow = Gtk.Overflow.HIDDEN;
            stack = new Gtk.Stack ();
            stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            stack.transition_duration = 220;
            stack.hexpand = true;
            stack.vexpand = false;
            stack.interpolate_size = true;
            append (stack);
            destroy.connect (() => cancel_prune (ref prune_id));
        }

        public static void cancel_prune (ref uint prune_id) {
            if (prune_id == 0) return;
            var id = prune_id;
            prune_id = 0;
            if (MainContext.default ().find_source_by_id (id) != null) {
                Source.remove (id);
            }
        }

        public static void prune_hidden (Gtk.Stack stack) {
            var keep = stack.visible_child;
            var widget = stack.get_first_child ();
            while (widget != null) {
                var next = widget.get_next_sibling ();
                if (widget != keep) stack.remove (widget);
                widget = next;
            }
        }


        public static void present_child (
            Gtk.Stack stack,
            Gtk.Widget page,
            ref uint prune_id,
            owned Utils.Action? after = null
        ) {
            if (stack.visible_child == null) {
                stack.transition_type = Gtk.StackTransitionType.NONE;
            }
            stack.add_child (page);
            page.visible = true;
            stack.visible_child = page;
            cancel_prune (ref prune_id);
            var delay = stack.transition_type == Gtk.StackTransitionType.NONE
                ? 10
                : stack.transition_duration + 40;
            Utils.Action? done = (owned) after;
            prune_id = Timeout.add (delay, () => {
                prune_hidden (stack);
                if (done != null) done ();
                return false;
            });
        }

        public void set_key (string key, bool instant = false) {
            present (key, instant, false);
        }

        public void reload () {
            if (collapses (current)) return;
            if (reapply (stack.visible_child, current)) return;
            present (current, false, true);
        }

        private void present (string key, bool instant, bool force) {
            if (!force && key == current && stack.visible_child != null) return;
            current = key;
            if (collapses (key) && (instant || stack.visible_child == null)) {
                apply_collapsed ();
                hold_empty ();
                return;
            }
            apply_shown (key);
            if (!instant && stack.visible_child == null) hold_empty ();
            stack.transition_type = instant
                ? Gtk.StackTransitionType.NONE
                : Gtk.StackTransitionType.CROSSFADE;
            present_child (stack, make_child (key), ref prune_id, () => {
                if (collapses (current)) apply_collapsed ();
            });
        }

        private void hold_empty () {
            if (stack.visible_child != null) return;
            stack.transition_type = Gtk.StackTransitionType.NONE;
            var empty = make_child ("");
            stack.add_child (empty);
            empty.visible = true;
            stack.visible_child = empty;
        }

        protected abstract Gtk.Widget make_child (string key);

        protected virtual bool reapply (Gtk.Widget? child, string key) {
            return false;
        }

        protected virtual bool collapses (string key) {
            return false;
        }

        protected virtual void apply_shown (string key) {
            visible = true;
        }

        protected virtual void apply_collapsed () {
            visible = false;
        }
    }

    public class IconKeySlot : FadeSlot {
        public int pixel_size { get; construct; }

        public IconKeySlot (string key, int pixel_size = 32) {
            Object (pixel_size: pixel_size);
            hexpand = false;
            vexpand = false;
            valign = Gtk.Align.CENTER;
            set_key (key, true);
        }

        protected override Gtk.Widget make_child (string key) {
            var image = new Gtk.Image ();
            IconRegistry.apply_icon_key (image, key, pixel_size);
            image.valign = Gtk.Align.CENTER;
            return image;
        }

        protected override bool reapply (Gtk.Widget? child, string key) {
            var image = child as Gtk.Image;
            if (image == null) return false;
            IconRegistry.apply_icon_key (image, key, pixel_size);
            return true;
        }

        protected override bool collapses (string key) {
            return Models.FfxiIconCatalog.sanitize_slot_key (key) == "";
        }

        protected override void apply_shown (string key) {
            visible = true;
            width_request = pixel_size;
            height_request = pixel_size;
        }

        protected override void apply_collapsed () {
            width_request = 0;
            height_request = 0;
            visible = false;
        }
    }

    public enum FadeLabelStyle {
        TILE_TITLE,
        TILE_META,
        ROW_TITLE,
        ROW_SUBTITLE
    }

    public class FadeLabel : FadeSlot {
        public FadeLabelStyle style { get; construct; }
        public bool underline { get; construct; }

        public FadeLabel.title (string text) {
            Object (style: FadeLabelStyle.TILE_TITLE, underline: false);
            hexpand = true;
            valign = Gtk.Align.CENTER;
            set_key (text, true);
        }

        public FadeLabel.meta (string text, bool underline = false) {
            Object (style: FadeLabelStyle.TILE_META, underline: underline);
            hexpand = true;
            valign = Gtk.Align.FILL;
            set_key (text, true);
        }

        public FadeLabel.row_title (string text) {
            Object (style: FadeLabelStyle.ROW_TITLE, underline: false);
            hexpand = true;
            valign = Gtk.Align.CENTER;
            set_key (text, true);
        }

        public FadeLabel.row_subtitle (string text) {
            Object (style: FadeLabelStyle.ROW_SUBTITLE, underline: false);
            hexpand = true;
            valign = Gtk.Align.CENTER;
            set_key (text, true);
        }

        protected override bool collapses (string key) {
            return style == FadeLabelStyle.ROW_SUBTITLE && key == "";
        }

        protected override Gtk.Widget make_child (string key) {
            var name = new Gtk.Label (key);
            name.xalign = 0f;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.hexpand = true;
            name.single_line_mode = true;
            switch (style) {
                case FadeLabelStyle.TILE_META:
                    name.add_css_class ("dim-label");
                    name.add_css_class ("caption");
                    name.halign = Gtk.Align.FILL;
                    break;
                case FadeLabelStyle.ROW_TITLE:
                    name.add_css_class ("title");
                    break;
                case FadeLabelStyle.ROW_SUBTITLE:
                    name.add_css_class ("subtitle");
                    break;
                default:
                    name.add_css_class ("title-3");
                    break;
            }
            if (underline) {
                var attrs = new Pango.AttrList ();
                attrs.insert (Pango.attr_underline_new (Pango.Underline.SINGLE));
                name.attributes = attrs;
            }
            return name;
        }
    }

    public class FadeMarkup : FadeSlot {
        public FadeMarkup (string source) {
            hexpand = true;
            valign = Gtk.Align.CENTER;
            set_key (source, true);
        }

        protected override bool collapses (string key) {
            return key == "";
        }

        protected override Gtk.Widget make_child (string key) {
            return new MarkupContent (key, true);
        }
    }
}
