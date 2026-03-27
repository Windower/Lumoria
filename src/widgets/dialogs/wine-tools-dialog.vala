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

        private Gtk.Button build_tool_button (string label) {
            var btn = new Gtk.Button.with_label (label);
            btn.halign = Gtk.Align.FILL;
            btn.sensitive = !tools_blocked;
            return btn;
        }

        public WineToolsDialog (Gtk.Window parent, bool tools_blocked) {
            Object (
                title: _("Wine Tools"),
                content_width: 420
            );
            this.tools_blocked = tools_blocked;
            build_ui ();
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

            var run_exe_btn = build_tool_button (_("Run EXE inside Wine prefix"));
            run_exe_btn.clicked.connect (() => { close (); run_exe_requested (); });
            content.append (run_exe_btn);

            var bash_btn = build_tool_button (_("Open Bash terminal"));
            bash_btn.clicked.connect (() => { close (); open_bash_requested (); });
            content.append (bash_btn);

            var cmd_btn = build_tool_button (_("Open Wine console"));
            cmd_btn.clicked.connect (() => { close (); open_wine_console_requested (); });
            content.append (cmd_btn);

            content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var taskmgr_btn = build_tool_button (_("Wine Task Manager"));
            taskmgr_btn.clicked.connect (() => { close (); open_taskmgr_requested (); });
            content.append (taskmgr_btn);

            var control_btn = build_tool_button (_("Wine Control Panel"));
            control_btn.clicked.connect (() => { close (); open_control_requested (); });
            content.append (control_btn);

            var regedit_btn = build_tool_button (_("Wine registry"));
            regedit_btn.clicked.connect (() => { close (); open_regedit_requested (); });
            content.append (regedit_btn);

            var winecfg_btn = build_tool_button (_("Wine configuration"));
            winecfg_btn.clicked.connect (() => { close (); open_winecfg_requested (); });
            content.append (winecfg_btn);

            toolbar.content = content;
            this.child = toolbar;
        }
    }
}
