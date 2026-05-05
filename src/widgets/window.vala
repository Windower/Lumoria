namespace Lumoria.Widgets {

    public class Window : Adw.ApplicationWindow {
        private Models.PrefixRegistry registry;
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Gee.ArrayList<Models.LauncherSpec> launcher_specs;

        private Gtk.ListBox prefix_list;
        private Gtk.Stack root_stack;
        private Adw.StatusPage empty_page;
        private Gtk.Button add_prefix_btn;
        private Gtk.Button preferences_btn;
        private Gtk.Button close_btn;
        private Gtk.Button global_play_btn;

        private Adw.ToastOverlay toast_overlay;
        private Services.PrefixLaunchService launch_service;
        private Services.GamepadService gamepad;
        private Gee.ArrayList<Adw.Dialog> active_dialogs;
        private Gtk.Widget? gamepad_focus_widget;
        private bool allow_window_close = false;
        private string expand_prefix_id_on_refresh = "";

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
            active_dialogs = new Gee.ArrayList<Adw.Dialog> ();

            gamepad = Services.GamepadService.instance ();
            gamepad.action_pressed.connect (on_gamepad_action);
            close_request.connect (() => on_close_request ());

            build_ui ();
            refresh_list ();
            Idle.add (() => {
                initialize_gamepad_focus ();
                return false;
            });
        }

        private Adw.ToolbarView build_window_toolbar (
            out Adw.HeaderBar header,
            out Gtk.Button out_close_btn,
            out Gtk.Button out_prefs_btn
        ) {
            var toolbar = new Adw.ToolbarView ();
            header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = false;

            out_close_btn = new Gtk.Button.from_icon_name (IconRegistry.CLOSE);
            out_close_btn.tooltip_text = _("Quit");
            out_close_btn.focusable = true;
            out_close_btn.add_css_class ("circular");
            out_close_btn.clicked.connect (() => request_quit_confirmation ());
            header.pack_end (out_close_btn);

            out_prefs_btn = new Gtk.Button.from_icon_name (IconRegistry.MANAGE);
            out_prefs_btn.tooltip_text = _("Preferences");
            out_prefs_btn.focusable = true;
            out_prefs_btn.clicked.connect (() => show_preferences ());
            header.pack_end (out_prefs_btn);

            toolbar.add_top_bar (header);
            return toolbar;
        }

        private void build_ui () {
            Adw.HeaderBar main_header;
            Gtk.Button _close_btn;
            Gtk.Button _prefs_btn;
            var main_toolbar = build_window_toolbar (out main_header, out _close_btn, out _prefs_btn);
            close_btn = _close_btn;
            preferences_btn = _prefs_btn;

            add_prefix_btn = new Gtk.Button.from_icon_name (IconRegistry.ADD);
            add_prefix_btn.tooltip_text = _("Add new prefix");
            add_prefix_btn.focusable = true;
            add_prefix_btn.clicked.connect (on_add_prefix);
            main_header.pack_start (add_prefix_btn);

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
            global_play_btn.focusable = true;
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

            Adw.HeaderBar empty_header;
            Gtk.Button empty_close;
            Gtk.Button empty_prefs;
            var empty_toolbar = build_window_toolbar (out empty_header, out empty_close, out empty_prefs);
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
            bool forced_expand = false;
            if (expand_prefix_id_on_refresh != "") {
                expanded_prefix_id = expand_prefix_id_on_refresh;
                forced_expand = true;
                expand_prefix_id_on_refresh = "";
            }
            if (!forced_expand) {
                for (int i = 0; i < registry.prefixes.size; i++) {
                    var existing_row = prefix_list.get_row_at_index (i) as PrefixRowWidget;
                    if (existing_row != null && existing_row.expanded) {
                        expanded_prefix_id = registry.prefixes[i].id;
                        break;
                    }
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
                row.play_requested.connect ((idx) => on_play_entrypoint (idx, ""));
                row.play_entrypoint_requested.connect (on_play_entrypoint);
                row.action_requested.connect (on_run_spec_action);
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

            update_global_play_sensitivity ();
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

        private void save_and_refresh () {
            registry.save (Utils.prefix_registry_path ());
            refresh_list ();
        }

        private void update_global_play_sensitivity () {
            var def = registry.default_prefix ();
            global_play_btn.sensitive = def != null && def.runner_id != "";
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
            on_play_entrypoint (idx, "");
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

            update_global_play_sensitivity ();
        }

        private void on_add_prefix () {
            var dialog = new Dialogs.CreatePrefixDialog (this, registry, runner_specs, launcher_specs);
            track_dialog (dialog);
            dialog.prefix_created.connect ((prefix_id) => {
                expand_prefix_id_on_refresh = prefix_id;
                Utils.StorageCache.instance ().invalidate (Utils.StorageCategory.PREFIXES);
                save_and_refresh ();
            });
            dialog.present (this);
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

        private void on_run_spec_action (int index, string action_id) {
            var entry = require_runnable (index);
            if (entry == null) return;

            var dialog = new Dialogs.InstallDialog ();
            track_dialog (dialog);
            dialog.install_completed.connect ((success) => {
                if (success) save_and_refresh ();
            });
            dialog.present (this);
            dialog.start_action (entry, runner_specs, launcher_specs, action_id);
        }

        private void on_manage_prefix (int index) {
            var entry = entry_at (index);
            if (entry == null) return;

            var dialog = new Dialogs.ManagePrefixDialog (this, registry, index, runner_specs, launcher_specs);
            track_dialog (dialog);
            dialog.saved.connect (save_and_refresh);
            dialog.removed.connect (save_and_refresh);
            dialog.present (this);
        }

        private void on_wine_tools (int index) {
            var entry = require_runnable (index);
            if (entry == null) return;

            var dialog = new Dialogs.WineToolsDialog (this, Utils.EnvironmentInfo.is_gamescope ());
            track_dialog (dialog);
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

            var prefix_dir = entry.resolved_path ();
            SettingsShared.open_directory (this, prefix_dir, (message) => {
                show_toast (_("Could not open prefix directory: %s").printf (message));
            });
        }

        private void on_launch_exe (int index) {
            if (!ensure_wine_tools_allowed ()) return;
            if (SettingsShared.file_browse_blocked (toast_overlay)) return;
            var entry = require_runnable (index);
            if (entry == null) return;

            var dialog = SettingsShared.build_file_dialog (
                _("Launch EXE In Prefix"),
                SettingsShared.build_windows_executable_filter ()
            );
            SettingsShared.open_file_dialog (this, dialog, entry.resolved_path (), (path) => {
                if (!SettingsShared.is_windows_executable_path (path)) {
                    show_toast (_("Please choose a Windows executable file."));
                    return;
                }
                launch_prefix_exe (index, path);
            }, (message) => {
                show_toast (_("Failed to select executable: %s").printf (message));
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
                        track_dialog (dialog);
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

        private bool ensure_wine_tools_allowed () {
            if (!Utils.EnvironmentInfo.is_gamescope ()) return true;
            show_toast (_("These tools are disabled while in a gamescope session."));
            return false;
        }

        public void show_preferences () {
            var dialog = new Dialogs.PreferencesDialog (this, runner_specs, registry);
            track_dialog (dialog);
            dialog.present (this);
        }

        private void on_gamepad_action (Services.GamepadAction action) {
            if (!is_active) return;

            focus_visible = true;

            if (active_dialogs.size > 0) {
                var top = active_dialogs[active_dialogs.size - 1];
                if (top is Dialogs.WineToolsDialog) {
                    if (((Dialogs.WineToolsDialog) top).handle_gamepad_action (action)) {
                        return;
                    }
                }
            }

            switch (action) {
                case Services.GamepadAction.NAVIGATE_DOWN:
                    move_gamepad_focus (1);
                    break;
                case Services.GamepadAction.NAVIGATE_UP:
                    move_gamepad_focus (-1);
                    break;
                case Services.GamepadAction.NAVIGATE_LEFT:
                    navigate_left ();
                    break;
                case Services.GamepadAction.NAVIGATE_RIGHT:
                    navigate_right ();
                    break;
                case Services.GamepadAction.TAB_PREV:
                    cycle_context_tabs (-1);
                    break;
                case Services.GamepadAction.TAB_NEXT:
                    cycle_context_tabs (1);
                    break;
                case Services.GamepadAction.ACTIVATE:
                    activate_gamepad_target ();
                    break;
                case Services.GamepadAction.BACK:
                    handle_back_action ();
                    break;
                case Services.GamepadAction.GLOBAL_PLAY:
                    on_global_play ();
                    break;
                case Services.GamepadAction.OPEN_PREFERENCES:
                    show_preferences ();
                    break;
            }
        }

        private void track_dialog (Adw.Dialog dialog) {
            active_dialogs.add (dialog);
            dialog.closed.connect (() => {
                active_dialogs.remove (dialog);
                var root = current_gamepad_root ();
                if (gamepad_focus_widget != null
                    && !Services.GamepadFocus.is_descendant_of (gamepad_focus_widget, root)) {
                    Services.GamepadFocus.clear (gamepad_focus_widget);
                    gamepad_focus_widget = null;
                }
            });
        }

        private Gtk.Widget current_gamepad_root () {
            var focus_dialog = find_dialog_from_focus ();
            if (focus_dialog != null) {
                return (Gtk.Widget) focus_dialog;
            }
            if (active_dialogs.size > 0) {
                return (Gtk.Widget) active_dialogs[active_dialogs.size - 1];
            }
            return (Gtk.Widget) this;
        }

        private void navigate_left () {
            var target = current_gamepad_target ();
            if (target is Adw.ExpanderRow) {
                var row = (Adw.ExpanderRow) target;
                if (row.expanded) row.expanded = false;
                return;
            }
            var parent = find_parent_expander (target);
            if (parent != null) {
                parent.expanded = false;
                set_gamepad_focus_widget ((Gtk.Widget) parent);
                return;
            }
            move_gamepad_focus (-1);
        }

        private void navigate_right () {
            var target = current_gamepad_target ();
            if (target is Adw.ExpanderRow) {
                var row = (Adw.ExpanderRow) target;
                if (!row.expanded) row.expanded = true;
                return;
            }
            if (find_parent_expander (target) != null) return;
            move_gamepad_focus (1);
        }

        private void cycle_context_tabs (int delta) {
            var root = current_gamepad_root ();
            var stack = find_view_stack (root);
            if (stack == null) return;

            var pages = stack.get_pages ();
            int n = (int) pages.get_n_items ();
            if (n <= 1) return;

            var current_name = stack.get_visible_child_name ();
            int current_idx = 0;
            for (int i = 0; i < n; i++) {
                var page = pages.get_item (i) as Adw.ViewStackPage;
                if (page != null && page.name == current_name) {
                    current_idx = i;
                    break;
                }
            }

            int next = current_idx + delta;
            if (next < 0) next = n - 1;
            if (next >= n) next = 0;

            var next_page = pages.get_item (next) as Adw.ViewStackPage;
            if (next_page == null) return;

            stack.set_visible_child_name (next_page.name);
            if (gamepad_focus_widget != null) {
                Services.GamepadFocus.clear (gamepad_focus_widget);
                gamepad_focus_widget = null;
            }
            move_gamepad_focus (1);
        }

        private Adw.ViewStack? find_view_stack (Gtk.Widget root) {
            if (root is Adw.ViewStack) return (Adw.ViewStack) root;
            for (var child = root.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var found = find_view_stack (child);
                if (found != null) return found;
            }
            return null;
        }

        private void move_gamepad_focus (int delta) {
            var root = current_gamepad_root ();
            var targets = collect_gamepad_targets (root);
            if (targets.size == 0) return;

            var current = current_gamepad_target ();

            if (current == global_play_btn) {
                for (int i = 0; i < targets.size; i++) {
                    if (targets[i] is PrefixRowWidget) {
                        set_gamepad_focus_widget (targets[i]);
                        return;
                    }
                }
            }

            int index = current != null ? targets.index_of (current) : -1;

            if (index < 0) {
                index = delta >= 0 ? 0 : targets.size - 1;
            } else {
                index += delta;
                if (index < 0) index = 0;
                if (index >= targets.size) index = targets.size - 1;
            }

            set_gamepad_focus_widget (targets[index]);
        }

        private void activate_gamepad_target () {
            var target = current_gamepad_target ();
            if (target == null) return;

            if (target is Adw.EntryRow) {
                ((Adw.EntryRow) target).grab_focus_without_selecting ();
                return;
            }

            if (target is Gtk.Entry || target is Gtk.TextView) {
                target.grab_focus ();
                return;
            }

            if (target is Adw.ActionRow) {
                var target_row = (Adw.ActionRow) target;
                if (!target_row.activatable && target_row.activatable_widget == null) {
                    var fallback_prefix = find_parent_prefix_row (target);
                    if (fallback_prefix != null && fallback_prefix.activate_primary_action ()) {
                        return;
                    }
                }
            }

            if (target is Gtk.Button) {
                ((Gtk.Button) target).activate ();
                return;
            }

            if (target is Adw.SwitchRow) {
                var row = (Adw.SwitchRow) target;
                row.active = !row.active;
                return;
            }

            if (target is Adw.ExpanderRow) {
                if (target is PrefixRowWidget) {
                    ((PrefixRowWidget) target).activate_primary_action ();
                } else {
                    var row = (Adw.ExpanderRow) target;
                    row.expanded = !row.expanded;
                }
                return;
            }

            if (target is Adw.ActionRow) {
                var parent_expander = find_parent_expander (target);
                ((Adw.ActionRow) target).activate ();
                if (parent_expander != null && !parent_expander.expanded) {
                    set_gamepad_focus_widget ((Gtk.Widget) parent_expander);
                }
                return;
            }

            target.activate ();
        }

        private Gtk.Widget? current_gamepad_target () {
            var root = current_gamepad_root ();

            if (gamepad_focus_widget != null &&
                gamepad_focus_widget.get_visible () &&
                gamepad_focus_widget.get_mapped () &&
                Services.GamepadFocus.is_descendant_of (gamepad_focus_widget, root)) {
                return gamepad_focus_widget;
            }

            var focused = find_actionable_focus_widget (root);
            if (focused != null) {
                set_gamepad_focus_widget (focused);
                return focused;
            }

            return null;
        }

        private void set_gamepad_focus_widget (Gtk.Widget target) {
            if (gamepad_focus_widget == target) {
                target.grab_focus ();
                return;
            }

            if (gamepad_focus_widget != null) {
                Services.GamepadFocus.clear (gamepad_focus_widget);
            }

            gamepad_focus_widget = target;
            Services.GamepadFocus.apply (gamepad_focus_widget);
        }

        private Gee.ArrayList<Gtk.Widget> collect_gamepad_targets (Gtk.Widget root) {
            var targets = new Gee.ArrayList<Gtk.Widget> ();

            if (root == (Gtk.Widget) this) {
                if (add_prefix_btn != null && add_prefix_btn.get_visible () && add_prefix_btn.sensitive) {
                    add_target_if_missing (targets, add_prefix_btn);
                }
                if (preferences_btn != null && preferences_btn.get_visible () && preferences_btn.sensitive) {
                    add_target_if_missing (targets, preferences_btn);
                }
            }

            collect_gamepad_targets_from (root, root, targets);
            return targets;
        }

        private void collect_gamepad_targets_from (
            Gtk.Widget root,
            Gtk.Widget widget,
            Gee.ArrayList<Gtk.Widget> targets
        ) {
            if (!is_navigable_widget (root, widget)) return;

            if (widget != root) {
                if (widget is Adw.EntryRow) {
                    add_target_if_missing (targets, widget);
                    return;
                }

                if (widget is Gtk.Entry || widget is Gtk.TextView) {
                    add_target_if_missing (targets, widget);
                    return;
                }

                if (widget is Gtk.Button) {
                    var button = (Gtk.Button) widget;
                    if (!button.sensitive) return;
                    if (has_view_switcher_ancestor (widget, root)) return;
                    if (should_ignore_gamepad_button (button)) return;
                    add_target_if_missing (targets, widget);
                    return;
                }

                if (widget is Adw.SwitchRow) {
                    add_target_if_missing (targets, widget);
                    return;
                }

                if (widget is Adw.ExpanderRow) {
                    add_target_if_missing (targets, widget);
                } else if (widget is Adw.ActionRow) {
                    var row = (Adw.ActionRow) widget;
                    if ((row.activatable || row.activatable_widget != null) &&
                        !is_expander_header_row (widget)) {
                        add_target_if_missing (targets, widget);
                        return;
                    }
                }
            }

            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
                collect_gamepad_targets_from (root, child, targets);
            }
        }

        private Gtk.Widget? find_actionable_focus_widget (Gtk.Widget root) {
            var focus = get_focus ();
            if (focus == null || !Services.GamepadFocus.is_descendant_of (focus, root)) return null;

            for (var w = focus; w != null && w != root; w = w.get_parent ()) {
                if (is_text_input_widget (w)) return w;
                if (w is Gtk.Button && !should_ignore_gamepad_button ((Gtk.Button) w)) return w;
                if (w is Adw.SwitchRow) return w;
                if (w is Adw.ExpanderRow) return w;
                if (w is Adw.ActionRow) {
                    var row = (Adw.ActionRow) w;
                    if (row.activatable || row.activatable_widget != null) return w;
                }
            }
            return null;
        }

        private bool is_text_input_widget (Gtk.Widget widget) {
            return widget is Adw.EntryRow || widget is Gtk.Entry || widget is Gtk.TextView;
        }

        private bool should_ignore_gamepad_button (Gtk.Button button) {
            if (button == close_btn) return true;
            if (button.has_css_class ("titlebutton") || button.has_css_class ("close")) return true;
            return false;
        }

        private bool is_navigable_widget (Gtk.Widget root, Gtk.Widget widget) {
            if (!widget.get_visible ()) return false;
            if (widget != root && !widget.get_mapped ()) return false;
            return Services.GamepadFocus.is_descendant_of (widget, root);
        }

        private bool is_expander_header_row (Gtk.Widget widget) {
            for (var w = widget.get_parent (); w != null; w = w.get_parent ()) {
                if (w is Gtk.Revealer) return false;
                if (w is Adw.ExpanderRow) return true;
            }
            return false;
        }

        private bool has_view_switcher_ancestor (Gtk.Widget widget, Gtk.Widget root) {
            for (var w = widget.get_parent (); w != null && w != root; w = w.get_parent ()) {
                if (w is Adw.ViewSwitcherBar || w is Adw.ViewSwitcher) return true;
            }
            return false;
        }

        private void add_target_if_missing (Gee.ArrayList<Gtk.Widget> targets, Gtk.Widget widget) {
            if (!targets.contains (widget)) {
                targets.add (widget);
            }
        }

        private Adw.ExpanderRow? find_parent_expander (Gtk.Widget widget) {
            for (var w = widget.get_parent (); w != null; w = w.get_parent ()) {
                if (w is Adw.ExpanderRow) return (Adw.ExpanderRow) w;
            }
            return null;
        }

        private PrefixRowWidget? find_parent_prefix_row (Gtk.Widget widget) {
            for (var w = widget.get_parent (); w != null; w = w.get_parent ()) {
                if (w is PrefixRowWidget) return (PrefixRowWidget) w;
            }
            return null;
        }

        private Adw.Dialog? find_dialog_from_focus () {
            var focus = get_focus ();
            if (focus == null) return null;
            for (var w = focus; w != null && w != (Gtk.Widget) this; w = w.get_parent ()) {
                if (w is Adw.Dialog) return (Adw.Dialog) w;
            }
            return null;
        }

        private bool on_close_request () {
            if (allow_window_close) return false;
            request_quit_confirmation ();
            return true;
        }

        private void request_quit_confirmation () {
            SettingsShared.present_destructive_confirmation (
                this,
                _("Quit Lumoria?"),
                _("Any running Wine processes will continue in the background."),
                "quit",
                _("Quit"),
                () => {
                    allow_window_close = true;
                    this.close ();
                }
            );
        }

        private void initialize_gamepad_focus () {
            var targets = collect_gamepad_targets (this);
            if (targets.size == 0) return;

            if (global_play_btn != null && global_play_btn.sensitive && targets.contains (global_play_btn)) {
                set_gamepad_focus_widget (global_play_btn);
            } else {
                set_gamepad_focus_widget (targets[0]);
            }
        }

        private void handle_back_action () {
            var root = current_gamepad_root ();
            var target = current_gamepad_target ();
            if (target != null && is_text_input_widget (target)) {
                return;
            }
            if (root is Adw.Dialog) {
                ((Adw.Dialog) root).close ();
            } else {
                request_quit_confirmation ();
            }
        }
    }
}
