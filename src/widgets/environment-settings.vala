namespace Lumoria.Widgets {

    public class EnvironmentSettings : Gtk.Box {
        /* With for_entry, emitted only after the entry has been updated. */
        public signal void changed ();

        public Gee.HashMap<string, string> runtime_env_vars { get; private set; }
        public Gee.HashMap<string, string> runtime_dll_overrides { get; private set; }
        public string prelaunch_script { get; private set; }
        public Models.PortalPathRef? prelaunch_script_portal { get; private set; }

        private Lumoria.Application.Context ctx;
        private Models.PrefixEntry? entry;
        private EnvVarsEditor editor;
        private DllOverridesEditor dll_editor;
        private Adw.ActionRow prelaunch_row;

        public EnvironmentSettings (
            Lumoria.Application.Context ctx,
            Gee.HashMap<string, string> env_vars,
            Gee.HashMap<string, string> dll_overrides,
            string prelaunch_script,
            Models.PortalPathRef? prelaunch_script_portal,
            string env_description = ""
        ) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            runtime_env_vars = env_vars;
            runtime_dll_overrides = dll_overrides;
            this.prelaunch_script = prelaunch_script;
            this.prelaunch_script_portal = prelaunch_script_portal;
            build_ui (env_description != ""
                ? env_description
                : _("Overrides and additions on top of the shared map on Manage → Runtime → Environment."));
        }

        public EnvironmentSettings.for_entry (Lumoria.Application.Context ctx, Models.PrefixEntry entry) {
            this (
                ctx,
                entry.runtime_env_vars,
                entry.runtime_dll_overrides,
                entry.prelaunch_script,
                entry.prelaunch_script_portal
            );
            this.entry = entry;
        }

        public bool validate (out string message) {
            return editor.validate (out message) && dll_editor.validate (out message);
        }

        private void build_ui (string env_description) {
            var env = new PageSection (_("Environment Variables"), env_description);
            editor = new EnvVarsEditor (runtime_env_vars);
            PageChrome.inset_editor (editor);
            var validation = PageChrome.validation_label ();
            editor.bind_validated (validation);
            editor.committed.connect (on_env_committed);
            env.add (editor);
            env.add (validation);
            append (env);

            var dll = new PageSection (_("DLL Overrides"), ActionRows.dll_overrides_hint ());
            dll_editor = new DllOverridesEditor (runtime_dll_overrides);
            PageChrome.inset_editor (dll_editor);
            var dll_validation = PageChrome.validation_label ();
            dll_editor.bind_validated (dll_validation);
            dll_editor.committed.connect (on_dll_committed);
            dll.add (dll_editor);
            dll.add (dll_validation);
            append (dll);

            var prelaunch = new PageSection (_("Prelaunch"));
            Gtk.Button browse;
            Gtk.Button clear;
            prelaunch_row = ActionRows.prelaunch_row (prelaunch_script, out browse, out clear);
            browse.clicked.connect (browse_prelaunch);
            clear.clicked.connect (clear_prelaunch);
            prelaunch.add (prelaunch_row);
            prelaunch.add (ActionRows.prelaunch_gamescope_note ());
            append (prelaunch);
        }

        private void on_env_committed (Gee.HashMap<string, string> values) {
            runtime_env_vars = values;
            commit ();
        }

        private void on_dll_committed (Gee.HashMap<string, string> values) {
            runtime_dll_overrides = values;
            commit ();
        }

        private void browse_prelaunch () {
            Dialogs.FileDialogs.browse_shell_script (get_root () as Gtk.Window, ctx, set_prelaunch);
        }

        private void clear_prelaunch () {
            set_prelaunch ("");
        }

        private void set_prelaunch (string path) {
            prelaunch_script = path;
            prelaunch_script_portal = path != "" ? Utils.portal_path_ref_from_path_uri (path) : null;
            ActionRows.set_prelaunch_path (prelaunch_row, path);
            commit ();
        }

        private void commit () {
            if (entry != null) {
                entry.runtime_env_vars = runtime_env_vars;
                entry.runtime_dll_overrides = runtime_dll_overrides;
                entry.prelaunch_script = prelaunch_script;
                entry.prelaunch_script_portal = prelaunch_script_portal;
            }
            changed ();
        }
    }
}
