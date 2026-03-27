namespace Lumoria.Widgets {

    public class Window : Adw.ApplicationWindow {
        private Models.PrefixRegistry registry;
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Gee.ArrayList<Models.LauncherSpec> launcher_specs;

        private Gtk.ListBox prefix_list;
        private Gtk.Stack root_stack;
        private Adw.StatusPage empty_page;
        private Gtk.Button global_play_btn;

        private Adw.ToastOverlay toast_overlay;
        private Services.PrefixLaunchService launch_service;

        public Window (Application app) {
            Object (
                application: app,
                title: Config.APP_NAME
            );
        }

        construct {
            default_width = 860;
            default_height = 540;

            registry = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
            runner_specs = Models.RunnerSpec.filter_for_host (Models.RunnerSpec.load_all_from_resource ());
            launcher_specs = Models.LauncherSpec.load_all_from_resource ();
            launch_service = new Services.PrefixLaunchService ();

            build_ui ();
            refresh_list ();
        }

        private void build_ui () {
            var app_menu = new GLib.Menu ();
            app_menu.append (_("Preferences"), "app.preferences");
            app_menu.append (_("About"), "app.about");

            var main_toolbar = new Adw.ToolbarView ();
            var main_header = new Adw.HeaderBar ();

            var add_btn = new Gtk.Button.from_icon_name (IconRegistry.ADD);
            add_btn.tooltip_text = _("Add new prefix");
            add_btn.clicked.connect (on_add_prefix);
            main_header.pack_start (add_btn);

            var menu_btn = new Gtk.MenuButton ();
            menu_btn.icon_name = IconRegistry.MENU;
            menu_btn.tooltip_text = _("App Menu");
            menu_btn.menu_model = app_menu;
            main_header.pack_end (menu_btn);

            main_toolbar.add_top_bar (main_header);

            prefix_list = new Gtk.ListBox ();
            prefix_list.selection_mode = Gtk.SelectionMode.NONE;
            prefix_list.add_css_class ("boxed-list");

            var prefix_group = new Adw.PreferencesGroup ();
            prefix_group.title = _("Prefixes");
            prefix_group.margin_start = 24;
            prefix_group.margin_end = 24;
            prefix_group.margin_top = 12;
            prefix_group.margin_bottom = 12;
            prefix_group.add (prefix_list);

            var list_scroll = new Gtk.ScrolledWindow ();
            list_scroll.child = prefix_group;
            list_scroll.vexpand = true;
            main_toolbar.content = list_scroll;

            global_play_btn = new Gtk.Button.with_label (_("Play"));
            global_play_btn.add_css_class ("suggested-action");
            global_play_btn.margin_start = 12;
            global_play_btn.margin_end = 12;
            global_play_btn.margin_top = 8;
            global_play_btn.margin_bottom = 8;
            global_play_btn.clicked.connect (on_global_play);
            main_toolbar.add_bottom_bar (global_play_btn);

            var mascot_image = new Gtk.Image.from_resource (Config.RESOURCE_BASE + "/ui/lumoria-mascot.svg");
            mascot_image.pixel_size = 180;

            empty_page = new Adw.StatusPage () {
                title = _("Get Started"),
                description = _("Create a Wine prefix to play.")
            };
            empty_page.paintable = mascot_image.get_paintable ();
            var get_started_btn = new Gtk.Button.with_label (_("Set Up Prefix"));
            get_started_btn.add_css_class ("suggested-action");
            get_started_btn.add_css_class ("pill");
            get_started_btn.halign = Gtk.Align.CENTER;
            get_started_btn.clicked.connect (on_add_prefix);
            empty_page.child = get_started_btn;

            var empty_toolbar = new Adw.ToolbarView ();
            var empty_header = new Adw.HeaderBar ();
            var empty_menu_btn = new Gtk.MenuButton ();
            empty_menu_btn.icon_name = IconRegistry.MENU;
            empty_menu_btn.tooltip_text = _("App Menu");
            empty_menu_btn.menu_model = app_menu;
            empty_header.pack_end (empty_menu_btn);
            empty_toolbar.add_top_bar (empty_header);
            empty_toolbar.content = empty_page;

            root_stack = new Gtk.Stack ();
            root_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            root_stack.add_named (empty_toolbar, "empty");
            root_stack.add_named (main_toolbar, "main");

            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.child = root_stack;
            this.content = toast_overlay;
        }

        public void refresh_list () {
            string? expanded_prefix_id = null;
            for (int i = 0; i < registry.prefixes.size; i++) {
                var existing_row = prefix_list.get_row_at_index (i) as PrefixRowWidget;
                if (existing_row != null && existing_row.expanded) {
                    expanded_prefix_id = registry.prefixes[i].id;
                    break;
                }
            }

            Gtk.ListBoxRow? child;
            while ((child = prefix_list.get_row_at_index (0)) != null) {
                prefix_list.remove (child);
            }

            var is_gamescope = Utils.EnvironmentInfo.is_gamescope ();
            bool restored_expanded = false;
            for (int i = 0; i < registry.prefixes.size; i++) {
                var entry = registry.prefixes[i];
                var row = new PrefixRowWidget (entry, i, runner_specs, launcher_specs, is_gamescope, registry.is_default (entry));
                row.play_requested.connect (on_play);
                row.play_entrypoint_requested.connect (on_play_entrypoint);
                row.manage_requested.connect (on_manage_prefix);
                row.wine_tools_requested.connect (on_wine_tools);
                row.open_logs_requested.connect (on_open_logs);
                row.set_default_requested.connect (on_set_default);
                int row_index = i;
                row.notify["expanded"].connect (() => {
                    if (!row.expanded) return;
                    this.collapse_other_prefix_rows (row_index);
                });
                prefix_list.append (row);
                if (!restored_expanded && expanded_prefix_id != null && entry.id == expanded_prefix_id) {
                    row.expanded = true;
                    restored_expanded = true;
                }
            }

            if (!restored_expanded && registry.prefixes.size == 1) {
                var first = prefix_list.get_row_at_index (0) as PrefixRowWidget;
                if (first != null) first.expanded = true;
            }

            var def = registry.default_prefix ();
            var can_play = def != null && def.runner_id != "" && !is_gamescope;
            global_play_btn.sensitive = can_play;

            update_stack ();
        }

        private void collapse_other_prefix_rows (int except_index) {
            for (int j = 0; j < registry.prefixes.size; j++) {
                if (j == except_index) continue;
                var expander = prefix_list.get_row_at_index (j) as PrefixRowWidget;
                if (expander != null) expander.expanded = false;
            }
        }

        private void update_stack () {
            root_stack.visible_child_name = registry.prefixes.size == 0 ? "empty" : "main";
        }

        public void show_toast (string message) {
            toast_overlay.add_toast (new Adw.Toast (message));
        }

        private Models.PrefixEntry? entry_at (int index) {
            if (index < 0 || index >= registry.prefixes.size) return null;
            return registry.prefixes[index];
        }

        private Models.PrefixEntry? require_runnable (int index) {
            var entry = entry_at (index);
            if (entry == null) return null;
            if (entry.runner_id == "") {
                show_toast (_("Set a runner for this prefix in Manage Prefix."));
                return null;
            }
            return entry;
        }

        private void on_global_play () {
            var idx = registry.default_prefix_index ();
            if (idx < 0) return;
            on_play (idx);
        }

        private void on_set_default (int index) {
            var entry = entry_at (index);
            if (entry == null) return;
            registry.default_prefix_id = entry.id;
            registry.save (Utils.prefix_registry_path ());

            var is_gamescope = Utils.EnvironmentInfo.is_gamescope ();
            for (int i = 0; i < registry.prefixes.size; i++) {
                var row = prefix_list.get_row_at_index (i) as PrefixRowWidget;
                if (row == null) continue;
                row.refresh (
                    registry.prefixes[i],
                    runner_specs,
                    is_gamescope,
                    registry.is_default (registry.prefixes[i])
                );
            }

            var def = registry.default_prefix ();
            global_play_btn.sensitive = def != null && def.runner_id != "" && !is_gamescope;
        }

        private void on_add_prefix () {
            var dialog = new Dialogs.CreatePrefixDialog (this, registry, runner_specs, launcher_specs);
            dialog.prefix_created.connect (() => {
                registry.save (Utils.prefix_registry_path ());
                refresh_list ();
            });
            dialog.present (this);
        }

        private void on_play (int index) {
            on_play_entrypoint (index, "");
        }

        private void on_play_entrypoint (int index, string entrypoint_id) {
            var entry = require_runnable (index);
            if (entry == null) return;

            launch_service.launch_prefix (
                entry,
                runner_specs,
                launcher_specs,
                entrypoint_id,
                (msg) => show_toast (msg)
            );
        }

        private void on_manage_prefix (int index) {
            var entry = entry_at (index);
            if (entry == null) return;

            var dialog = new Dialogs.ManagePrefixDialog (this, registry, index, runner_specs, launcher_specs);
            dialog.saved.connect (() => {
                registry.save (Utils.prefix_registry_path ());
                refresh_list ();
            });
            dialog.removed.connect (() => {
                registry.save (Utils.prefix_registry_path ());
                refresh_list ();
            });
            dialog.present (this);
        }

        private void on_wine_tools (int index) {
            var entry = require_runnable (index);
            if (entry == null) return;

            var dialog = new Dialogs.WineToolsDialog (this, are_wine_tools_blocked ());
            dialog.run_exe_requested.connect (() => on_launch_exe (index));
            dialog.open_bash_requested.connect (() => launch_bash_terminal (index));
            dialog.open_wine_console_requested.connect (() => launch_wine_tool (index, { "wineconsole" }, "wineconsole"));
            dialog.open_taskmgr_requested.connect (() => launch_wine_tool (index, { "taskmgr" }, "taskmgr"));
            dialog.open_control_requested.connect (() => launch_wine_tool (index, { "control" }, "control"));
            dialog.open_regedit_requested.connect (() => launch_wine_tool (index, { "regedit" }, "regedit"));
            dialog.open_winecfg_requested.connect (() => launch_wine_tool (index, { "winecfg" }, "winecfg"));
            dialog.present (this);
        }

        private void on_open_logs (int index) {
            var entry = entry_at (index);
            if (entry == null) return;

            var log_dir = Path.build_filename (entry.resolved_path (), "logs");
            Utils.ensure_dir (log_dir);
            var launcher = new Gtk.FileLauncher (File.new_for_path (log_dir));
            launcher.launch.begin (this, null, (obj, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    show_toast (_("Could not open logs folder: %s").printf (e.message));
                }
            });
        }

        private void on_launch_exe (int index) {
            if (!ensure_wine_tools_allowed ()) return;
            var entry = require_runnable (index);
            if (entry == null) return;

            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Launch EXE In Prefix");
            dialog.modal = true;

            var initial = entry.resolved_path ();
            if (FileUtils.test (initial, FileTest.IS_DIR)) {
                dialog.initial_folder = File.new_for_path (initial);
            }

            dialog.open.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file == null) return;
                    var exe_path = file.get_path ();
                    if (exe_path == null || exe_path == "") return;
                    if (!exe_path.down ().has_suffix (".exe")) {
                        show_toast (_("Please choose a .exe file."));
                        return;
                    }
                    launch_prefix_exe (index, exe_path);
                } catch (Error e) {
                    warning ("Failed to select EXE file: %s", e.message);
                }
            });
        }

        private void launch_prefix_exe (int index, string exe_path) {
            var entry = require_runnable (index);
            if (entry == null) return;

            launch_service.launch_exe (
                entry,
                runner_specs,
                launcher_specs,
                exe_path,
                (msg) => show_toast (msg)
            );
        }

        private void launch_wine_tool (int index, string[] wine_args, string label) {
            if (!ensure_wine_tools_allowed ()) return;
            var entry = require_runnable (index);
            if (entry == null) return;

            launch_service.launch_wine_tool (
                entry,
                runner_specs,
                wine_args,
                label,
                (msg) => show_toast (msg)
            );
        }

        private void launch_bash_terminal (int index) {
            if (!ensure_wine_tools_allowed ()) return;
            var entry = require_runnable (index);
            if (entry == null) return;

            new Thread<bool> ("prepare-terminal", () => {
                try {
                    var ctx = Runtime.prepare_prefix_terminal_context (entry, runner_specs);
                    var work_dir = ctx.working_directory;
                    var env_vars = ctx.env_vars;
                    Idle.add (() => {
                        var dialog = new Dialogs.TerminalDialog (work_dir, env_vars);
                        dialog.present (this);
                        return false;
                    });
                } catch (Error e) {
                    var msg = _("Open terminal failed: %s").printf (e.message);
                    Idle.add (() => {
                        show_toast (msg);
                        return false;
                    });
                }
                return true;
            });
        }

        private bool are_wine_tools_blocked () {
            return Utils.EnvironmentInfo.is_gamescope ();
        }

        private bool ensure_wine_tools_allowed () {
            if (!are_wine_tools_blocked ()) return true;
            show_toast (_("These tools are disabled while in a gamescope session."));
            return false;
        }

        public void show_preferences () {
            var dialog = new Dialogs.PreferencesDialog (this, runner_specs);
            dialog.present (this);
        }
    }
}
