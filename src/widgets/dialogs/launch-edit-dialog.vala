namespace Lumoria.Widgets.Dialogs {

    public class LaunchEditDialog : DialogHelpers.GamepadDialog {
        private Lumoria.Application.Context ctx;
        private Models.PrefixEntry entry;
        private Runtime.LaunchTarget action;
        private Models.Entrypoint? custom;
        private bool creating;

        private Adw.EntryRow name_entry;
        private IconPicker picker;
        private Adw.SwitchRow shortcut_check;
        private Lumoria.Ui.SettingsTabs? tabs;

        private Adw.ActionRow exe_row;
        private Adw.EntryRow args_row;
        private string exe_path = "";
        private EnvironmentSettings runtime;

        private DialogHelpers.FormFooter footer;

        public LaunchEditDialog (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action
        ) {
            this.with_target (ctx, entry, action, entry.custom_entrypoint (action.id), false);
        }

        public LaunchEditDialog.for_new_entry (Lumoria.Application.Context ctx, Models.PrefixEntry entry) {
            var ep = new Models.Entrypoint ();
            this.with_target (ctx, entry, Runtime.launch_target_from_entrypoint (ep, null), ep, true);
        }

        private LaunchEditDialog.with_target (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action,
            Models.Entrypoint? custom,
            bool creating
        ) {
            Object (
                title: creating ? _("Add Custom Entry") : _("Edit Launch"),
                content_width: 760,
                content_height: custom != null ? 640 : 580
            );
            this.ctx = ctx;
            this.entry = entry;
            this.action = action;
            this.custom = custom;
            this.creating = creating;
            if (custom != null) exe_path = custom.exe;
            build_ui ();
        }

        private void build_ui () {
            var display = build_display_page ();
            var page = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            if (custom != null) {
                tabs = new Lumoria.Ui.SettingsTabs ();
                tabs.add_scrolled (build_launch_page (), "launch", _("Launch"));
                tabs.add_page (display, "display", _("Display"));
                page.append (tabs);
            } else {
                page.append (display);
            }

            footer = new DialogHelpers.FormFooter (
                creating ? _("Add") : _("Save"),
                custom != null && !creating ? _("Delete") : null
            );
            footer.save_button.clicked.connect (on_save);
            footer.cancel_button.clicked.connect (() => close ());
            if (footer.delete_button != null) footer.delete_button.clicked.connect (on_delete);
            page.append (footer);
            set_body (DialogHelpers.dialog_body (page));
            closed.connect (release_picker);
        }

        private void release_picker () {
            picker.release_sources ();
        }

        private void reset_icon () {
            shortcut_check.active = true;
            picker.reset_to_default ();
        }

        private Gtk.Widget build_display_page () {
            name_entry = new Adw.EntryRow ();
            name_entry.title = custom != null ? _("Name") : _("Nickname");
            name_entry.text = custom != null ? custom.name : entry.display_nickname (action.id);
            var names = PageChrome.untitled_group ();
            names.margin_top = Lumoria.Ui.Metrics.GROUP_SPACING;
            if (custom == null && action.label != "") names.description = action.label;
            names.add (name_entry);

            picker = new IconPicker (ctx, entry.display_icon (action.id, action.icon), action.icon);
            picker.icon_changed.connect (sync_shortcut_check);

            shortcut_check = new Adw.SwitchRow ();
            shortcut_check.title = _("Use this icon for shortcuts");
            shortcut_check.active = entry.shortcut_icon_preference (action.id) != Models.IconSlots.LUMORIA;
            var options = PageChrome.untitled_group ();
            options.margin_top = Lumoria.Ui.Metrics.GROUP_SPACING;
            options.add (shortcut_check);
            var reset = PageChrome.action_row (_("Reset Icon To Default"), _("Reset"));
            reset.button.clicked.connect (reset_icon);
            options.add (reset);
            sync_shortcut_check ();

            var page = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            page.vexpand = true;
            page.append (names);
            page.append (picker);
            page.append (options);
            return page;
        }

        private Gtk.Widget build_launch_page () {
            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var launch_group = PageChrome.build_group (_("Launch"));

            var launch_name = new Adw.EntryRow ();
            launch_name.title = name_entry.title;
            name_entry.bind_property ("text", launch_name, "text", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            launch_group.add (launch_name);

            exe_row = new Adw.ActionRow ();
            exe_row.title = _("Executable");
            exe_row.subtitle = exe_path != "" ? exe_path : _("None selected");
            exe_row.subtitle_lines = 2;
            var browse = PageChrome.browse_button ();
            browse.clicked.connect (browse_exe);
            exe_row.add_suffix (browse);
            launch_group.add (exe_row);

            args_row = new Adw.EntryRow ();
            args_row.title = _("Arguments");
            if (custom.args.size > 0) args_row.text = format_args (custom.args);
            launch_group.add (args_row);
            body.append (launch_group);

            runtime = new EnvironmentSettings (
                ctx,
                custom.runtime_env_overrides,
                custom.runtime_dll_overrides,
                custom.prelaunch_script,
                custom.prelaunch_script_portal,
                _("Applied to this custom entry. These override prefix and shared variables.")
            );
            body.append (runtime);
            return body;
        }

        protected override Services.GamepadListNavigator create_navigator () {
            return new Services.GamepadListNavigator.live ((Gtk.Widget) this, (widget) => widget.get_mapped ());
        }

        public override bool handle_gamepad_action (Services.GamepadAction action) {
            switch (action) {
                case Services.GamepadAction.TAB_PREV:
                    return tabs != null && PageChrome.cycle_stack (tabs.stack, -1);
                case Services.GamepadAction.TAB_NEXT:
                    return tabs != null && PageChrome.cycle_stack (tabs.stack, 1);
                default:
                    break;
            }
            return base.handle_gamepad_action (action);
        }

        private void sync_shortcut_check () {
            shortcut_check.visible = Lumoria.Application.ShortcutArtwork.can_use_launch_art (picker.selected_icon);
        }

        private void browse_exe () {
            if (FileDialogs.file_browse_blocked (ctx)) return;
            var start = exe_path != "" ? Path.get_dirname (exe_path) : entry.resolved_path ();
            FileDialogs.present_executable_browse_dialog (
                ctx,
                start,
                (path) => {
                    exe_path = path;
                    exe_row.subtitle = path;
                    if (name_entry.text.strip () == "") name_entry.text = Path.get_basename (path);
                },
                (message) => ctx.show_toast (message)
            );
        }

        private void on_save () {
            footer.save_button.grab_focus ();
            var name = Utils.sanitize_user_text (name_entry.text ?? "");
            if (custom != null && !apply_custom_fields (name)) return;

            var icon = picker.selected_icon == picker.default_icon ? "" : picker.selected_icon;
            var key = Models.FfxiIconCatalog.sanitize_slot_key (icon);
            var shortcut = Lumoria.Application.ShortcutArtwork.can_use_launch_art (picker.selected_icon)
                && !shortcut_check.active
                ? Models.IconSlots.LUMORIA
                : "";
            var action_id = custom != null ? custom.id : action.id;
            entry.apply_launch_display (action_id, key, custom != null ? "" : name, shortcut);
            ctx.state.remember_icon (key);

            if (custom != null) {
                ctx.actions.save_custom_entry (entry, custom, creating);
            } else if (ctx.prefixes.save_or_toast ()) {
                ctx.show_toast (_("Launch display updated"));
            }
            close ();
        }

        private bool apply_custom_fields (string name) {
            if (name == "") {
                ctx.show_toast (_("Enter a name."));
                return false;
            }
            if (exe_path == "") {
                ctx.show_toast (_("Choose an executable."));
                return false;
            }
            string error;
            if (!runtime.validate (out error)) {
                ctx.show_toast (error);
                return false;
            }
            var parsed = parse_args (args_row.text);
            if (parsed == null) return false;

            custom.name = name;
            custom.exe = exe_path;
            custom.exe_portal = Utils.portal_path_ref_from_path_uri (exe_path);
            custom.prelaunch_script = runtime.prelaunch_script;
            custom.prelaunch_script_portal = runtime.prelaunch_script_portal;
            custom.args = parsed;
            if (custom.id == "") custom.id = entry.unique_custom_entry_id ();
            custom.runtime_dll_overrides = runtime.runtime_dll_overrides;
            custom.runtime_env_overrides = runtime.runtime_env_vars;
            return true;
        }

        private Gee.ArrayList<string>? parse_args (string text) {
            var args = new Gee.ArrayList<string> ();
            var raw = text.strip ();
            if (raw == "") return args;
            try {
                string[] parsed;
                Shell.parse_argv (raw, out parsed);
                foreach (var arg in parsed) args.add (arg);
            } catch (Error e) {
                ctx.show_toast (_("Could not parse arguments."));
                return null;
            }
            return args;
        }

        private static string format_args (Gee.List<string> args) {
            var parts = new Gee.ArrayList<string> ();
            foreach (var arg in args) parts.add (Utils.shell_quote (arg));
            return string.joinv (" ", Utils.strv (parts));
        }

        private void on_delete () {
            DialogHelpers.present_destructive_confirmation (
                this,
                _("Delete Custom Entry?"),
                _("Delete %s? This cannot be undone.").printf (custom.title ()),
                "delete",
                _("Delete"),
                () => {
                    try {
                        ctx.actions.remove_custom_entry (entry, custom);
                    } catch (Error e) {
                        ctx.show_toast (user_error (e));
                        return;
                    }
                    close ();
                }
            );
        }
    }
}
