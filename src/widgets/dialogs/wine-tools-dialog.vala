namespace Lumoria.Widgets.Dialogs {

    public class WineToolsDialog : Adw.Dialog {
        public signal void run_exe_requested ();
        public signal void open_bash_requested ();
        public signal void open_wine_console_requested ();
        public signal void open_taskmgr_requested ();
        public signal void open_control_requested ();
        public signal void open_regedit_requested ();
        public signal void open_winecfg_requested ();

        private bool tools_blocked;
        private Gee.ArrayList<Gtk.Widget> gamepad_targets;
        private Services.GamepadListNavigator? gamepad_navigator;

        private delegate void ToolAction ();

        private Adw.ActionRow build_tool_row (string label, owned ToolAction on_activate) {
            var row = new Adw.ActionRow ();
            row.title = label;
            row.activatable = true;
            row.sensitive = !tools_blocked;
            row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            row.activated.connect (() => {
                if (tools_blocked) return;
                // Close after the handler returns to avoid freeing dialog children mid-signal.
                Idle.add (() => { close (); return false; });
                on_activate ();
            });
            if (row.sensitive) gamepad_targets.add (row);
            return row;
        }

        public WineToolsDialog (Gtk.Window parent, bool tools_blocked) {
            Object (
                title: _("Wine Tools"),
                content_width: 420
            );
            this.tools_blocked = tools_blocked;
            gamepad_targets = new Gee.ArrayList<Gtk.Widget> ();
            build_ui ();
            gamepad_navigator = new Services.GamepadListNavigator ((Gtk.Widget) this, gamepad_targets);
        }

        private void build_ui () {
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = true;
            toolbar.add_top_bar (header);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            content.margin_start = 16;
            content.margin_end = 16;
            content.margin_top = 14;
            content.margin_bottom = 14;

            if (tools_blocked) {
                var warning_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                warning_box.margin_top = 4;
                warning_box.margin_bottom = 4;
                warning_box.margin_start = 4;
                warning_box.margin_end = 4;
                warning_box.add_css_class ("card");
                warning_box.add_css_class ("warning");

                var warning_icon = new Gtk.Image.from_icon_name (IconRegistry.WARNING);
                warning_icon.halign = Gtk.Align.CENTER;
                warning_icon.valign = Gtk.Align.CENTER;
                warning_icon.margin_start = 8;
                warning_icon.margin_end = 2;
                warning_icon.margin_top = 8;
                warning_icon.margin_bottom = 8;
                warning_box.append (warning_icon);

                var note = new Gtk.Label (_("Disabled while in a gamescope session."));
                note.halign = Gtk.Align.START;
                note.valign = Gtk.Align.CENTER;
                note.wrap = true;
                note.xalign = 0.0f;
                note.margin_start = 2;
                note.margin_end = 10;
                note.margin_top = 8;
                note.margin_bottom = 8;
                warning_box.append (note);

                content.append (warning_box);
                content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            }

            var primary_group = new Adw.PreferencesGroup ();
            primary_group.add (build_tool_row (_("Run EXE inside Wine prefix"), () => run_exe_requested ()));
            primary_group.add (build_tool_row (_("Open Bash terminal"), () => open_bash_requested ()));
            primary_group.add (build_tool_row (_("Open Wine console"), () => open_wine_console_requested ()));
            content.append (primary_group);

            var tools_group = new Adw.PreferencesGroup ();
            tools_group.add (build_tool_row (_("Wine Task Manager"), () => open_taskmgr_requested ()));
            tools_group.add (build_tool_row (_("Wine Control Panel"), () => open_control_requested ()));
            tools_group.add (build_tool_row (_("Wine registry"), () => open_regedit_requested ()));
            tools_group.add (build_tool_row (_("Wine configuration"), () => open_winecfg_requested ()));
            content.append (tools_group);

            toolbar.content = content;
            this.child = toolbar;
        }

        public bool handle_gamepad_action (Services.GamepadAction action) {
            if (gamepad_navigator == null) return false;

            switch (action) {
                case Services.GamepadAction.NAVIGATE_UP:
                case Services.GamepadAction.NAVIGATE_LEFT:
                    return gamepad_navigator.move (-1);
                case Services.GamepadAction.NAVIGATE_DOWN:
                case Services.GamepadAction.NAVIGATE_RIGHT:
                    return gamepad_navigator.move (1);
                case Services.GamepadAction.ACTIVATE:
                    if (!gamepad_navigator.activate_current ()) {
                        return gamepad_navigator.focus_first ();
                    }
                    return true;
                case Services.GamepadAction.BACK:
                    close ();
                    return true;
                default:
                    return false;
            }
        }
    }
}
