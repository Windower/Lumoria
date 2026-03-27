namespace Lumoria.Widgets.Preferences {

    public class GeneralPage : Gtk.Box {
        private Adw.SwitchRow update_row;
        private Adw.SwitchRow runner_row;
        private Adw.SwitchRow comp_row;

        public GeneralPage () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            build_ui ();
        }

        private void build_ui () {
            var prefs = Utils.Preferences.instance ();

            var updates_group = SettingsShared.build_group (_("Check for Updates"));

            update_row = new Adw.SwitchRow ();
            update_row.title = _("Lumoria");
            update_row.active = prefs.updates_lumoria;
            update_row.notify["active"].connect (() => {
                var inst = Utils.Preferences.instance ();
                if (inst.updates_lumoria != update_row.active) {
                    inst.set_updates_lumoria (update_row.active);
                }
            });
            updates_group.add (update_row);

            runner_row = new Adw.SwitchRow ();
            runner_row.title = _("Runners");
            runner_row.active = prefs.updates_runners;
            runner_row.notify["active"].connect (() => {
                var inst = Utils.Preferences.instance ();
                if (inst.updates_runners != runner_row.active) {
                    inst.set_updates_runners (runner_row.active);
                }
            });
            updates_group.add (runner_row);

            comp_row = new Adw.SwitchRow ();
            comp_row.title = _("Components");
            comp_row.active = prefs.updates_components;
            comp_row.notify["active"].connect (() => {
                var inst = Utils.Preferences.instance ();
                if (inst.updates_components != comp_row.active) {
                    inst.set_updates_components (comp_row.active);
                }
            });
            updates_group.add (comp_row);

            append (updates_group);
        }
    }
}
