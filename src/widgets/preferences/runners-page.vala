namespace Lumoria.Widgets.Preferences {

    public class RunnersPage : Gtk.Box {
        public signal void toast_message (string message);

        private Adw.ActionRow default_row;

        private Gee.ArrayList<ToolGroupWidget> groups;

        public RunnersPage (Gee.ArrayList<Models.RunnerSpec> specs) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            groups = new Gee.ArrayList<ToolGroupWidget> ();

            var default_group = new Adw.PreferencesGroup ();
            default_group.margin_start = 24;
            default_group.margin_end = 24;
            default_group.margin_top = 12;

            default_row = new Adw.ActionRow ();
            default_row.title = _("Default Runner");
            update_default_label ();
            default_group.add (default_row);
            append (default_group);

            foreach (var spec in specs) {
                var adapter = new Models.RunnerToolAdapter (spec);
                var group = new ToolGroupWidget (adapter);
                groups.add (group);
                group.toast_message.connect ((msg) => {
                    update_default_label ();
                    foreach (var g in groups) {
                        g.refresh_all_stars ();
                    }
                    toast_message (msg);
                });
                append (group);
            }

            var spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            spacer.vexpand = true;
            spacer.margin_bottom = 12;
            append (spacer);
        }

        private void update_default_label () {
            var defaults = Utils.Preferences.instance ();
            var def_id = defaults.get_default_runner_id ();
            var def_ver = defaults.get_default_runner_version ();
            if (def_id != "") {
                default_row.subtitle = "%s %s".printf (def_id, def_ver);
            } else {
                default_row.subtitle = _("Not set");
            }
        }
    }
}
