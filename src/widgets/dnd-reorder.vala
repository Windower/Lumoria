namespace Lumoria.Widgets {

    public delegate bool ReorderHandler (string payload, int dest_index);

    /*
     * Drag-to-reorder for one container. The container and every item are drop targets; the
     * controller turns the pointer position into an insertion index, paints the drop indicator
     * and hands the owner only (payload, index). Item widgets never own a closure over their page.
     */
    public abstract class ReorderController : Object {
        private const string DRAGGING_CLASS = "prefix-dragging";

        protected Gtk.Widget container;
        private ReorderHandler on_move;
        private Gee.ArrayList<Gtk.EventController> controllers = new Gee.ArrayList<Gtk.EventController> ();
        private bool _enabled = true;

        public bool enabled {
            get { return _enabled; }
            set {
                _enabled = value;
                var phase = value ? Gtk.PropagationPhase.BUBBLE : Gtk.PropagationPhase.NONE;
                foreach (var controller in controllers) controller.propagation_phase = phase;
            }
        }

        protected ReorderController (Gtk.Widget container, owned ReorderHandler on_move) {
            this.container = container;
            this.on_move = (owned) on_move;
            attach_drop (container);
        }

        public void add_item (Gtk.Widget widget, string payload) {
            var source = new Gtk.DragSource ();
            source.actions = Gdk.DragAction.MOVE;
            source.prepare.connect ((src, x, y) => {
                var val = Value (typeof (string));
                val.set_string (payload);
                return new Gdk.ContentProvider.for_value (val);
            });
            source.drag_begin.connect (on_drag_begin);
            source.drag_end.connect (on_drag_end);
            widget.add_controller (source);
            controllers.add (source);
            attach_drop (widget);
            enabled = _enabled;
        }

        public void remove_item (Gtk.Widget widget) {
            var stale = new Gee.ArrayList<Gtk.EventController> ();
            foreach (var controller in controllers) {
                if (controller.widget == widget) stale.add (controller);
            }
            foreach (var controller in stale) {
                widget.remove_controller (controller);
                controllers.remove (controller);
            }
        }

        public void clear_items () {
            controllers.clear ();
        }

        /* The item (row or flow child) a drop-target widget stands for; null for the container itself. */
        protected abstract Gtk.Widget? item_of (Gtk.Widget widget);
        protected abstract Gtk.Widget? item_at (double x, double y);
        protected abstract int index_of (Gtk.Widget item);
        protected abstract int item_count ();
        protected abstract bool past_midpoint (Gtk.Widget item, double x, double y);
        protected abstract void mark (Gtk.Widget item, bool after);
        protected abstract void unmark (Gtk.Widget item);
        protected abstract void each_item (Func<Gtk.Widget> visit);

        private void attach_drop (Gtk.Widget widget) {
            var drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            drop.motion.connect (on_motion);
            drop.leave.connect (clear_marks);
            drop.drop.connect (on_drop);
            widget.add_controller (drop);
            controllers.add (drop);
        }

        private void on_drag_begin (Gtk.DragSource source, Gdk.Drag drag) {
            source.set_icon (new Gtk.WidgetPaintable (source.widget), 0, 0);
            (item_of (source.widget) ?? source.widget).add_css_class (DRAGGING_CLASS);
        }

        private void on_drag_end (Gtk.DragSource source, Gdk.Drag drag, bool delete_data) {
            (item_of (source.widget) ?? source.widget).remove_css_class (DRAGGING_CLASS);
        }

        private bool locate (Gtk.Widget target, double x, double y, out Gtk.Widget? item, out bool after) {
            after = false;
            item = item_of (target);
            if (item == null) {
                item = item_at (x, y);
                if (item == null) return false;
                Graphene.Rect bounds;
                if (item.compute_bounds (container, out bounds)) {
                    x -= bounds.origin.x;
                    y -= bounds.origin.y;
                }
            }
            after = past_midpoint (item, x, y);
            return true;
        }

        private Gdk.DragAction on_motion (Gtk.DropTarget target, double x, double y) {
            clear_marks ();
            Gtk.Widget? item;
            bool after;
            if (locate (target.widget, x, y, out item, out after)) mark (item, after);
            return Gdk.DragAction.MOVE;
        }

        private bool on_drop (Gtk.DropTarget target, Value value, double x, double y) {
            if (!value.holds (typeof (string))) return false;
            var payload = value.get_string ();
            if (payload == "") return false;
            Gtk.Widget? item;
            bool after;
            var dest = locate (target.widget, x, y, out item, out after)
                ? index_of (item) + (after ? 1 : 0)
                : item_count ();
            return on_move (payload, dest);
        }

        private void clear_marks () {
            each_item (unmark);
        }
    }

    public class ListReorder : ReorderController {
        private Gtk.ListBox list;

        public ListReorder (Gtk.ListBox list, owned ReorderHandler on_move) {
            base (list, (owned) on_move);
            this.list = list;
        }

        protected override Gtk.Widget? item_of (Gtk.Widget widget) {
            return widget as Gtk.ListBoxRow;
        }

        protected override Gtk.Widget? item_at (double x, double y) {
            return list.get_row_at_y ((int) y);
        }

        protected override int index_of (Gtk.Widget item) {
            return ((Gtk.ListBoxRow) item).get_index ();
        }

        protected override int item_count () {
            int n = 0;
            while (list.get_row_at_index (n) != null) n++;
            return n;
        }

        protected override bool past_midpoint (Gtk.Widget item, double x, double y) {
            return y > item.get_height () / 2.0;
        }

        protected override void mark (Gtk.Widget item, bool after) {
            item.add_css_class (after ? "drop-below" : "drop-above");
        }

        protected override void unmark (Gtk.Widget item) {
            item.remove_css_class ("drop-above");
            item.remove_css_class ("drop-below");
        }

        protected override void each_item (Func<Gtk.Widget> visit) {
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i);
                if (row == null) break;
                visit (row);
            }
        }
    }

    public class FlowReorder : ReorderController {
        private Gtk.FlowBox flow;

        public FlowReorder (Gtk.FlowBox flow, owned ReorderHandler on_move) {
            base (flow, (owned) on_move);
            this.flow = flow;
        }

        protected override Gtk.Widget? item_of (Gtk.Widget widget) {
            return widget.get_parent () as Gtk.FlowBoxChild;
        }

        protected override Gtk.Widget? item_at (double x, double y) {
            return flow.get_child_at_pos ((int) x, (int) y);
        }

        protected override int index_of (Gtk.Widget item) {
            return ((Gtk.FlowBoxChild) item).get_index ();
        }

        protected override int item_count () {
            int n = 0;
            while (flow.get_child_at_index (n) != null) n++;
            return n;
        }

        protected override bool past_midpoint (Gtk.Widget item, double x, double y) {
            return x > item.get_width () / 2.0;
        }

        protected override void mark (Gtk.Widget item, bool after) {
            item.add_css_class (after ? "drop-after" : "drop-before");
        }

        protected override void unmark (Gtk.Widget item) {
            item.remove_css_class ("drop-before");
            item.remove_css_class ("drop-after");
        }

        protected override void each_item (Func<Gtk.Widget> visit) {
            for (int i = 0; ; i++) {
                var child = flow.get_child_at_index (i);
                if (child == null) break;
                visit (child);
            }
        }
    }
}
