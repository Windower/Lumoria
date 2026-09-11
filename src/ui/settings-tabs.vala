namespace Lumoria.Ui {

    /* A page whose tabs the gamepad shoulder buttons can step through. */
    public interface TabHost : Object {
        public abstract bool cycle_tabs (int delta);
    }

    public class SettingsTabs : Gtk.Box {
        public Adw.ViewStack stack { get; private set; }

        public SettingsTabs () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            stack = Widgets.PageChrome.settings_stack ();
            append (Widgets.PageChrome.inline_tab_switcher (stack));
            append (stack);
        }

        public void add_scrolled (Gtk.Widget child, string id, string title) {
            stack.add_titled (Widgets.PageChrome.scrolled (child), id, title);
        }

        public void add_page (Gtk.Widget child, string id, string title) {
            stack.add_titled (child, id, title);
        }

        public string visible_name () {
            return stack.visible_child_name ?? "";
        }

        public void show_name (string name) {
            if (stack.get_child_by_name (name) != null) {
                stack.visible_child_name = name;
            }
        }

        public bool cycle (int delta) {
            return Widgets.PageChrome.cycle_stack (stack, delta);
        }
    }
}
