namespace Lumoria.Widgets.Preferences {

    public class ComponentsPage : Gtk.Box {
        public ComponentsPage (Lumoria.Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            append (ManifestUi.components_disable_note ());
            var specs = Models.ManifestRepository.shared ().components;
            var first = true;
            foreach (var spec in specs) {
                var adapter = new Runtime.ComponentToolAdapter (spec);
                append (new ToolGroupWidget (ctx, adapter, first));
                first = false;
            }

            var spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            spacer.vexpand = true;
            spacer.margin_bottom = Ui.Metrics.GROUP_SPACING;
            append (spacer);
        }
    }
}
