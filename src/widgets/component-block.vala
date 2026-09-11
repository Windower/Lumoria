namespace Lumoria.Widgets {

    public class ComponentBlock : Gtk.Box {
        public signal void enabled_changed (bool? enabled);
        public signal void version_changed (string version);

        public string component_id { get; private set; }

        private Lumoria.Application.Context ctx;
        private Models.ComponentManifest spec;
        private OptionListRow enabled_row;
        private Adw.ActionRow version_row;
        private string selected_version;
        private string? applied_version;

        public ComponentBlock (
            Lumoria.Application.Context ctx,
            Models.ComponentManifest spec,
            bool? enabled,
            string version,
            string? applied_version,
            bool first = false,
            Gtk.Widget? extra = null
        ) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.spec = spec;
            this.component_id = spec.id;
            this.selected_version = normalize_version (version);
            this.applied_version = applied_version;

            append (ManifestUi.intro (spec, null, null, first));

            var group = PageChrome.untitled_group ();
            var default_label = Utils.Preferences.instance ().is_component_enabled (spec.id)
                ? _("enabled") : _("disabled");
            enabled_row = PageChrome.build_toggle_override_combo (
                _("Enabled"),
                enabled,
                default_label
            );
            enabled_row.notify["selected"].connect (() => {
                var mode = (ToggleOverrideState) ((int) enabled_row.selected);
                enabled_changed (mode.to_nullable_bool ());
            });
            group.add (enabled_row);

            version_row = PageChrome.navigation_row (_("Version"));
            version_row.activated.connect (open_version_picker);
            group.add (version_row);
            var footer = Messages.footer_row (spec, null);
            if (footer != null) group.add (footer);
            append (group);
            update_version_row ();

            if (extra != null) append (extra);
        }

        public bool? enabled () {
            return ((ToggleOverrideState) ((int) enabled_row.selected)).to_nullable_bool ();
        }

        public string version () {
            return selected_version;
        }

        private void update_version_row () {
            var defaults = Utils.Preferences.instance ();
            var inherited = defaults.get_tool_version (Utils.ToolKind.COMPONENT, spec.id);
            if (selected_version == "") {
                version_row.subtitle = PageChrome.inherit_default_label (
                    Models.ToolVersionRef.display_label (inherited)
                );
            } else {
                version_row.subtitle = Models.ToolVersionRef.display_label (selected_version);
            }
            if (applied_version != null && applied_version.strip () != "") {
                var hint = _("Currently %s").printf (applied_version);
                if (selected_version == "" || selected_version != applied_version) {
                    version_row.subtitle = _("%s · %s").printf (version_row.subtitle, hint);
                }
            }
        }

        private void open_version_picker () {
            var defaults = Utils.Preferences.instance ();
            var inherited = defaults.get_tool_version (Utils.ToolKind.COMPONENT, spec.id);
            var current = selected_version;
            if (current == "" && Models.ToolVersionRef.is_latest (inherited)) {
                current = Models.ToolVersionRef.LATEST.id ();
            }
            var picker = new Dialogs.VersionBrowserDialog.pick (
                new Runtime.ComponentToolAdapter (spec),
                current,
                PageChrome.inherit_default_label (Models.ToolVersionRef.display_label (inherited))
            );
            picker.version_selected.connect ((value) => {
                selected_version = normalize_version (value);
                update_version_row ();
                version_changed (selected_version);
            });
            ctx.show_dialog (picker);
        }

        private static string normalize_version (string version) {
            var normalized = version.strip ();
            if (Models.ToolVersionRef.is_inherit (normalized)) return "";
            return normalized;
        }
    }
}
