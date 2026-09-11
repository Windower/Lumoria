namespace Lumoria.Widgets.Preferences {

    public class RunnersPage : Gtk.Box {
        private Gee.ArrayList<ToolGroupWidget> groups;

        public RunnersPage (Lumoria.Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            groups = new Gee.ArrayList<ToolGroupWidget> ();
            var first = true;
            foreach (var spec in ctx.runner_manifests) {
                var adapter = new Runtime.RunnerToolAdapter (spec);
                var group = new ToolGroupWidget (ctx, adapter, first);
                groups.add (group);
                group.defaults_changed.connect (() => {
                    foreach (var other in groups) {
                        other.refresh_heading ();
                    }
                });
                append (group);
                first = false;
            }

            var spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            spacer.vexpand = true;
            spacer.margin_bottom = Ui.Metrics.GROUP_SPACING;
            append (spacer);
        }
    }
}
