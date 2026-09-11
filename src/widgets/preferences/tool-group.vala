namespace Lumoria.Widgets.Preferences {

    public class ToolGroupWidget : Gtk.Box {
        public signal void defaults_changed ();

        private Lumoria.Application.Context ctx;
        private Runtime.ToolAdapter tool;
        private Models.BaseManifest? spec;
        private Gtk.Widget? intro;
        private bool heading_first;
        private Adw.ActionRow default_row;
        private Adw.SwitchRow enabled_row;

        public ToolGroupWidget (Lumoria.Application.Context ctx, Runtime.ToolAdapter tool, bool first = false) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.tool = tool;
            heading_first = first;
            spec = tool_spec ();
            rebuild_intro ();

            var group = PageChrome.untitled_group ();
            if (spec == null) {
                group.title = tool.tool_name;
                group.description = tool.tool_description;
                group.margin_top = Ui.Metrics.GROUP_SPACING;
            }

            if (tool.tool_kind == Utils.ToolKind.COMPONENT) {
                enabled_row = new Adw.SwitchRow ();
                enabled_row.title = _("Enabled");
                enabled_row.subtitle = _("Apply this component to prefixes during install and launch");
                enabled_row.active = Utils.Preferences.instance ().is_component_enabled (tool.tool_id);
                enabled_row.notify["active"].connect (on_enabled_toggled);
                group.add (enabled_row);
            }

            default_row = PageChrome.navigation_row (_("Default Version"));
            default_row.activated.connect (open_versions);
            update_default_label ();
            group.add (default_row);
            if (spec != null) {
                var footer = Messages.footer_row (spec, null);
                if (footer != null) group.add (footer);
            }
            append (group);
        }

        private void on_enabled_toggled () {
            Utils.Preferences.instance ().set_component_enabled (tool.tool_id, enabled_row.active);
        }

        public void refresh_heading () {
            rebuild_intro ();
            update_default_label ();
        }

        private Models.BaseManifest? tool_spec () {
            if (tool.tool_kind == Utils.ToolKind.COMPONENT) {
                return Models.find_by_id<Models.ComponentManifest> (Models.ManifestRepository.shared ().components, tool.tool_id);
            }
            return Models.find_by_id<Models.RunnerManifest> (ctx.runner_manifests, tool.tool_id);
        }

        private void rebuild_intro () {
            if (spec == null) return;
            var next = ManifestUi.intro (
                spec, null, null, heading_first, runner_default_version ()
            );
            if (intro != null) {
                remove (intro);
                prepend (next);
            } else {
                append (next);
            }
            intro = next;
        }

        private string runner_default_version () {
            if (tool.tool_kind != Utils.ToolKind.RUNNER) return "";
            var defaults = Utils.Preferences.instance ();
            if (defaults.runner_id != tool.tool_id) return "";
            return defaults.get_default_runner_version ();
        }

        private void update_default_label () {
            var defaults = Utils.Preferences.instance ();
            switch (tool.tool_kind) {
                case Utils.ToolKind.RUNNER:
                    if (defaults.runner_id == tool.tool_id) {
                        default_row.subtitle = Models.ToolVersionRef.display_label (
                            defaults.get_default_runner_version ()
                        );
                    } else if (defaults.runner_id == "") {
                        default_row.subtitle = _("Not set");
                    } else {
                        default_row.subtitle = _("Other runner (%s %s)").printf (
                            defaults.runner_id, defaults.get_default_runner_version ()
                        );
                    }
                    break;
                default:
                    default_row.subtitle = Models.ToolVersionRef.display_label (
                        defaults.get_tool_version (tool.tool_kind, tool.tool_id)
                    );
                    break;
            }
        }

        private void open_versions () {
            var picker = new Dialogs.VersionBrowserDialog.manage (tool);
            picker.defaults_changed.connect ((msg) => {
                update_default_label ();
                ctx.show_toast (msg);
                defaults_changed ();
            });
            ctx.show_dialog (picker);
        }
    }
}
