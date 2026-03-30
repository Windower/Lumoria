namespace Lumoria.Widgets.Services {

    public class GamepadListNavigator : Object {
        private Gee.ArrayList<Gtk.Widget> targets;
        private Gtk.Widget? focused_widget;
        private Gtk.Widget root;

        public GamepadListNavigator (Gtk.Widget root, Gee.ArrayList<Gtk.Widget> targets) {
            this.root = root;
            this.targets = targets;
        }

        public void set_targets (Gee.ArrayList<Gtk.Widget> targets) {
            clear_focus ();
            this.targets = targets;
        }

        public bool move (int delta) {
            if (targets.size == 0) return false;

            int current = focused_widget != null ? targets.index_of (focused_widget) : -1;
            if (current < 0) current = delta >= 0 ? 0 : targets.size - 1;
            else current = (current + delta + targets.size) % targets.size;

            set_focus (targets[current]);
            return true;
        }

        public bool activate_current () {
            var target = current_target ();
            if (target == null) return false;
            return target.activate ();
        }

        public bool focus_first () {
            if (targets.size == 0) return false;
            set_focus (targets[0]);
            return true;
        }

        public void clear_focus () {
            if (focused_widget != null) {
                focused_widget.remove_css_class ("gamepad-focus");
                focused_widget = null;
            }
        }

        private Gtk.Widget? current_target () {
            if (focused_widget != null && focused_widget.get_visible () && is_descendant_of (focused_widget, root)) {
                return focused_widget;
            }
            return null;
        }

        private void set_focus (Gtk.Widget widget) {
            if (focused_widget != null && focused_widget != widget) {
                focused_widget.remove_css_class ("gamepad-focus");
            }
            focused_widget = widget;
            focused_widget.add_css_class ("gamepad-focus");
            focused_widget.grab_focus ();
        }

        private bool is_descendant_of (Gtk.Widget widget, Gtk.Widget ancestor) {
            for (var w = widget; w != null; w = w.get_parent ()) {
                if (w == ancestor) return true;
            }
            return false;
        }
    }
}
