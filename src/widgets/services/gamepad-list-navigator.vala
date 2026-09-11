namespace Lumoria.Widgets.Services {

    public interface GamepadNavigable : Object {
        public abstract bool handle_gamepad_action (GamepadAction action);
    }

    public class GamepadFocus : Object {
        private const string CSS_CLASS = "gamepad-focus";

        public static void clear (Gtk.Widget? widget) {
            if (widget != null) {
                widget.remove_css_class (CSS_CLASS);
            }
        }

        public static void apply (Gtk.Widget widget) {
            widget.add_css_class (CSS_CLASS);
            widget.grab_focus ();
        }
    }

    public delegate bool GamepadTargetFilter (Gtk.Widget widget);

    public class GamepadListNavigator : Object {
        private Gee.ArrayList<Gtk.Widget> targets;
        private Gtk.Widget? focused_widget;
        private Gtk.Widget root;
        private bool rescan_on_move;
        private bool wrap;
        private bool descend_into_rows;
        private GamepadTargetFilter? filter;

        public unowned Gtk.Widget? focused {
            get { return current_target (); }
        }

        public GamepadListNavigator (Gtk.Widget root, Gee.ArrayList<Gtk.Widget>? targets = null) {
            this.root = root;
            wrap = true;
            this.targets = targets ?? collect ();
        }

        /* Re-scans the tree on every move, walks into row suffixes and clamps at the ends. */
        public GamepadListNavigator.live (Gtk.Widget root, owned GamepadTargetFilter? filter = null) {
            this.root = root;
            this.filter = (owned) filter;
            rescan_on_move = true;
            descend_into_rows = true;
            targets = new Gee.ArrayList<Gtk.Widget> ();
        }

        public void refresh () {
            set_targets (collect ());
        }

        private Gee.ArrayList<Gtk.Widget> collect () {
            var found = new Gee.ArrayList<Gtk.Widget> ();
            collect_from (root, found);
            return found;
        }

        private void collect_from (Gtk.Widget widget, Gee.ArrayList<Gtk.Widget> found) {
            if (!widget.get_visible ()) return;
            if (filter != null && !filter (widget)) return;
            if (widget is Gtk.ListBoxRow) {
                if (widget.sensitive) found.add (widget);
                if (!descend_into_rows) return;
            } else if (widget is Gtk.Button || widget is Gtk.CheckButton || widget is Gtk.MenuButton) {
                if (widget.sensitive) found.add (widget);
            } else if (widget is Gtk.Entry || widget is Gtk.SearchEntry) {
                found.add (widget);
            }
            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
                collect_from (child, found);
            }
        }

        public void set_targets (Gee.ArrayList<Gtk.Widget> targets) {
            clear_focus ();
            this.targets = targets;
        }

        private Gee.ArrayList<Gtk.Widget> current_targets () {
            if (rescan_on_move) targets = collect ();
            return targets;
        }

        public bool move (int delta) {
            var list = current_targets ();
            if (list.size == 0) return false;

            int current = focused_widget != null ? list.index_of (focused_widget) : -1;
            if (current < 0) current = delta >= 0 ? 0 : list.size - 1;
            else if (wrap) current = (current + delta + list.size) % list.size;
            else current = (current + delta).clamp (0, list.size - 1);

            set_focus (list[current]);
            return true;
        }

        public bool activate_current () {
            var target = current_target ();
            if (target == null) return false;
            if (target is Gtk.ListBoxRow) {
                var row = (Gtk.ListBoxRow) target;
                var list = row.get_parent () as Gtk.ListBox;
                if (list != null) list.select_row (row);
                row.activate ();
                return true;
            }
            if (target is Adw.EntryRow || target is Gtk.Entry || target is Gtk.SearchEntry) {
                target.can_focus = true;
                Gtk.Widget? inner = null;
                if (target is Gtk.Editable) {
                    inner = ((Gtk.Editable) target).get_delegate () as Gtk.Widget;
                }
                if (inner != null) inner.grab_focus ();
                else if (target is Gtk.Entry) {
                    ((Gtk.Entry) target).grab_focus_without_selecting ();
                } else {
                    target.grab_focus ();
                }
                return true;
            }
            return target.activate ();
        }

        public bool handle_action (GamepadAction action) {
            switch (action) {
                case GamepadAction.NAVIGATE_UP:
                case GamepadAction.NAVIGATE_LEFT:
                    return move (-1);
                case GamepadAction.NAVIGATE_DOWN:
                case GamepadAction.NAVIGATE_RIGHT:
                    return move (1);
                case GamepadAction.ACTIVATE:
                    if (!activate_current ()) return focus_first ();
                    return true;
                default:
                    return false;
            }
        }

        public bool focus_first () {
            var list = current_targets ();
            if (list.size == 0) return false;
            set_focus (list[0]);
            return true;
        }

        public void clear_focus () {
            if (focused_widget != null) {
                GamepadFocus.clear (focused_widget);
                focused_widget = null;
            }
        }

        private unowned Gtk.Widget? current_target () {
            if (focused_widget != null
                && focused_widget.get_visible ()
                && (focused_widget == root || focused_widget.is_ancestor (root))) {
                return focused_widget;
            }
            return null;
        }

        private void set_focus (Gtk.Widget widget) {
            if (focused_widget != null && focused_widget != widget) {
                GamepadFocus.clear (focused_widget);
            }
            focused_widget = widget;
            GamepadFocus.apply (focused_widget);
        }
    }
}
