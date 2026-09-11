namespace Lumoria.Widgets {

    public class StartupViewControl : Object {
        public static string label (Utils.StartupView view) {
            switch (view) {
                case Utils.StartupView.HOME:
                    return _("Home");
                default:
                    return _("Last selected prefix");
            }
        }

        public static Gtk.StringList model () {
            var list = new Gtk.StringList (null);
            list.append (label (Utils.StartupView.LAST_PREFIX));
            list.append (label (Utils.StartupView.HOME));
            return list;
        }

        public static uint index_of (Utils.StartupView view) {
            return view == Utils.StartupView.HOME ? 1 : 0;
        }

        public static Utils.StartupView from_index (uint selected) {
            return selected == 1 ? Utils.StartupView.HOME : Utils.StartupView.LAST_PREFIX;
        }

        public static Menu menu (string action) {
            var menu = new Menu ();
            var last_item = new MenuItem (label (Utils.StartupView.LAST_PREFIX), action);
            last_item.set_attribute_value (
                Menu.ATTRIBUTE_TARGET,
                new Variant.string (Utils.StartupView.LAST_PREFIX.to_key ())
            );
            menu.append_item (last_item);
            var home_item = new MenuItem (label (Utils.StartupView.HOME), action);
            home_item.set_attribute_value (
                Menu.ATTRIBUTE_TARGET,
                new Variant.string (Utils.StartupView.HOME.to_key ())
            );
            menu.append_item (home_item);
            return menu;
        }
    }
}
