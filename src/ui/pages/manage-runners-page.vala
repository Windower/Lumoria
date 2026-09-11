namespace Lumoria.Ui {

    public class ManageRunnersPage : Gtk.Box, TabHost {
        private Application.Context ctx;
        private SettingsTabs tabs;

        public ManageRunnersPage (Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            build_tabs ();
            Utils.Preferences.instance ().reset.connect (rebuild_tabs);
        }

        private void build_tabs () {
            tabs = new SettingsTabs ();
            tabs.add_scrolled (new Widgets.Preferences.RunnersPage (ctx), "runners", _("Runners"));
            tabs.add_scrolled (new Widgets.Preferences.ComponentsPage (ctx), "components", _("Components"));
            tabs.add_scrolled (wine_tab (), "wine", _("Wine"));
            tabs.add_scrolled (environment_tab (), "environment", _("Environment"));
            append (tabs);
        }

        /* The tool groups and editors hold their own copies of the settings, so a reset rebuilds them. */
        private void rebuild_tabs () {
            var shown = tabs.visible_name ();
            remove (tabs);
            build_tabs ();
            tabs.show_name (shown);
        }

        public bool cycle_tabs (int delta) {
            return tabs.cycle (delta);
        }

        public void show_kind (Application.PageKind kind) {
            if (kind == Application.PageKind.COMPONENTS) {
                tabs.show_name ("components");
            } else if (kind == Application.PageKind.RUNNERS) {
                tabs.show_name ("runners");
            }
        }

        private Gtk.Widget wine_tab () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.append (Widgets.WineOverrideSection.for_preferences ());
            return box;
        }

        private Gtk.Widget environment_tab () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var env = new Widgets.PageSection (
                _("Environment Variables"),
                _("Applied on every launch. Prefix Environment values overlay the same keys.")
            );
            var editor = new Widgets.EnvVarsEditor (Utils.Preferences.instance ().get_runtime_env_vars ());
            Widgets.PageChrome.inset_editor (editor);
            var validation = Widgets.PageChrome.validation_label ();
            editor.bind_validated (validation);
            editor.committed.connect (Utils.Preferences.instance ().set_runtime_env_vars);
            env.add (editor);
            env.add (validation);
            box.append (env);
            return box;
        }
    }
}
