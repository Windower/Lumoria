namespace Lumoria.Widgets.Dialogs {

    public class WineToolsDialog : DialogHelpers.GamepadDialog {
        public const string TOOL_RUN_EXE = "run-exe";
        public const string TOOL_BASH = "bash";

        public signal void tool_requested (string id);

        private bool tools_blocked;
        private Gee.ArrayList<Gtk.Widget> gamepad_targets;

        public WineToolsDialog (bool tools_blocked) {
            Object (
                title: _("Wine Tools"),
                content_width: Lumoria.Ui.Metrics.DIALOG_WIDTH_NARROW
            );
            this.tools_blocked = tools_blocked;
            gamepad_targets = new Gee.ArrayList<Gtk.Widget> ();
            build_ui ();
        }

        protected override Services.GamepadListNavigator create_navigator () {
            return new Services.GamepadListNavigator ((Gtk.Widget) this, gamepad_targets);
        }

        private void build_ui () {
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, Lumoria.Ui.Metrics.GROUP_SPACING);
            PageChrome.margins (content, Lumoria.Ui.Metrics.PAGE_MARGIN, Lumoria.Ui.Metrics.GROUP_SPACING);

            if (tools_blocked) {
                content.append (Messages.warning (
                    _("Disabled while in a gamescope session."),
                    4, 4, 4, 4
                ));
                content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            }

            var primary = new Adw.PreferencesGroup ();
            add_tool (primary, TOOL_RUN_EXE, _("Run EXE inside Wine prefix"));
            add_tool (primary, TOOL_BASH, _("Open Bash Terminal"));
            add_tool (primary, Lumoria.Application.LaunchService.WINE_CONSOLE, _("Open Wine Console"));
            content.append (primary);

            var tools = new Adw.PreferencesGroup ();
            add_tool (tools, Lumoria.Application.LaunchService.WINE_TASKMGR, _("Wine Task Manager"));
            add_tool (tools, Lumoria.Application.LaunchService.WINE_CONTROL, _("Wine Control Panel"));
            add_tool (tools, Lumoria.Application.LaunchService.WINE_REGEDIT, _("Wine Registry"));
            add_tool (tools, Lumoria.Application.LaunchService.WINE_CFG, _("Wine Configuration"));
            content.append (tools);

            set_body (DialogHelpers.dialog_body (content));
        }

        private void add_tool (Adw.PreferencesGroup group, string id, string label) {
            var row = new ChoiceRow (id, label);
            row.sensitive = !tools_blocked;
            row.add_suffix (new Gtk.Image.from_icon_name (IconRegistry.NEXT));
            row.activated.connect (on_tool_chosen);
            if (row.sensitive) gamepad_targets.add (row);
            group.add (row);
        }

        private void on_tool_chosen (Adw.ActionRow row) {
            if (tools_blocked) return;
            Idle.add (() => { close (); return false; });
            tool_requested (((ChoiceRow) row).value);
        }
    }
}
