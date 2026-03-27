namespace Lumoria.Widgets.Preferences {

    public class ComponentsPage : Gtk.Box {
        public signal void toast_message (string message);

        public ComponentsPage () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            var specs = Models.ComponentSpec.load_all_from_resource ();
            foreach (var spec in specs) {
                var adapter = new Models.ComponentToolAdapter (spec);
                var group = new ToolGroupWidget (adapter);
                group.toast_message.connect ((msg) => toast_message (msg));
                append (group);
            }

            var spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            spacer.vexpand = true;
            spacer.margin_bottom = 12;
            append (spacer);
        }
    }
}
