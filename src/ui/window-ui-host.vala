namespace Lumoria.Ui {

    public class WindowUiHost : Object, Application.UiHost {
        private Application.Context ctx;
        private Window win;
        private Widgets.Dialogs.BusyDialog? remove_dialog;
        private Widgets.Dialogs.BusyDialog? launch_busy;
        private bool remove_files_done;
        private bool remove_ui_done;

        public Gtk.Window window { get { return win; } }

        public WindowUiHost (Application.Context ctx, Window window) {
            this.ctx = ctx;
            this.win = window;
        }

        public void show_dialog (Adw.Dialog dialog) {
            win.show_dialog (dialog);
        }

        public void show_toast (string message) {
            win.show_toast (message);
        }

        public void present_prefix_removal (Models.PrefixEntry entry, bool delete_files) {
            var message = delete_files
                ? _("Removing prefix files...")
                : _("Removing prefix...");
            remove_files_done = false;
            remove_ui_done = false;
            remove_dialog = new Widgets.Dialogs.BusyDialog (message);
            show_dialog (remove_dialog);
            ctx.state.set_busy (message);
            Idle.add (() => {
                ctx.prefixes.remove (entry, delete_files, (error) => {
                    if (error != null) show_toast (user_error (error));
                    remove_files_done = true;
                    try_finish_remove ();
                });
                return false;
            }, Priority.LOW);
        }

        public void finish_remove_ui () {
            if (remove_dialog == null) return;
            remove_ui_done = true;
            try_finish_remove ();
        }

        private void try_finish_remove () {
            if (remove_dialog == null || !remove_files_done || !remove_ui_done) return;
            var dialog = remove_dialog;
            remove_dialog = null;
            ctx.state.clear_busy ();
            dialog.force_close ();
        }

        public void present_updates (
            Gee.ArrayList<Runtime.PendingUpdate> updates,
            owned Runtime.UpdateDecisionHandler respond
        ) {
            Widgets.Dialogs.PrefixDialogs.present_prefix_update_dialog (win, updates, (owned) respond);
        }

        public void confirm (
            string title,
            string body,
            string confirm_label,
            bool destructive,
            owned Utils.Action on_confirm,
            string cancel_label
        ) {
            Widgets.Dialogs.DialogHelpers.present_confirmation (
                win,
                title,
                body,
                "confirm",
                confirm_label,
                destructive ? Adw.ResponseAppearance.DESTRUCTIVE : Adw.ResponseAppearance.SUGGESTED,
                (owned) on_confirm,
                true,
                cancel_label
            );
        }

        public void present_busy (string status) {
            dismiss_busy ();
            launch_busy = new Widgets.Dialogs.BusyDialog (status);
            show_dialog (launch_busy);
        }

        public void set_busy_status (string status) {
            if (launch_busy == null || status == "") return;
            launch_busy.busy.set_status (status);
        }

        public void dismiss_busy () {
            if (launch_busy == null) return;
            var dialog = launch_busy;
            launch_busy = null;
            dialog.force_close ();
        }

        public void present_wine_tools (Models.PrefixEntry entry) {
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                show_toast (_("These tools are disabled while in a gamescope session."));
                return;
            }
            if (!ctx.ensure_prefix_access (entry)) return;
            var dialog = new Widgets.Dialogs.WineToolsDialog (false);
            dialog.tool_requested.connect ((id) => run_wine_tool (entry, id));
            show_dialog (dialog);
        }

        private void run_wine_tool (Models.PrefixEntry entry, string id) {
            if (id == Widgets.Dialogs.WineToolsDialog.TOOL_RUN_EXE) {
                pick_executable (
                    entry.resolved_path (),
                    (path) => ctx.launches.launch_prefix (entry, "", path),
                    (message) => show_toast (message)
                );
                return;
            }
            if (id == Widgets.Dialogs.WineToolsDialog.TOOL_BASH) {
                ctx.launches.open_prefix_shell (entry);
                return;
            }
            ctx.launches.launch_wine_tool (entry, { id }, id);
        }

        public void pick_executable (
            string dir,
            owned Widgets.Dialogs.DialogHelpers.PathSelectedCallback on_path,
            owned Widgets.Dialogs.DialogHelpers.ErrorMessageCallback on_error
        ) {
            if (Widgets.Dialogs.FileDialogs.file_browse_blocked (ctx)) {
                on_error (_("File browsing is not available in a gamescope session."));
                return;
            }
            Widgets.Dialogs.FileDialogs.present_executable_browse_dialog (
                ctx, dir, (owned) on_path, (owned) on_error
            );
        }

        public void pick_folder (
            string title,
            string? initial_folder,
            owned Widgets.Dialogs.DialogHelpers.FolderSelectedCallback on_path,
            owned Widgets.Dialogs.DialogHelpers.ErrorMessageCallback on_error
        ) {
            if (Widgets.Dialogs.FileDialogs.file_browse_blocked (ctx)) {
                on_error (_("File browsing is not available in a gamescope session."));
                return;
            }
            Widgets.Dialogs.FileDialogs.select_folder (
                win, Widgets.Dialogs.FileDialogs.build_folder_dialog (title), initial_folder, (owned) on_path, (owned) on_error
            );
        }

        public void grant_prefix_access (
            Models.PrefixEntry entry,
            owned Widgets.Dialogs.DialogHelpers.GrantFolderCallback on_granted,
            owned Widgets.Dialogs.DialogHelpers.ErrorMessageCallback on_error
        ) {
            Widgets.Dialogs.PrefixDialogs.present_grant_access (win, entry, (owned) on_granted, (owned) on_error);
        }

        public void open_directory (
            string path,
            owned Widgets.Dialogs.DialogHelpers.ErrorMessageCallback? on_error
        ) {
            Widgets.Dialogs.FileDialogs.open_directory (win, path, (owned) on_error);
        }

        public void open_http_uri (string url) {
            Widgets.Dialogs.FileDialogs.open_http_uri (win, url);
        }

        public void present_terminal (
            string working_directory,
            Gee.HashMap<string, string> env_vars
        ) {
            var dialog = new Widgets.Dialogs.TerminalDialog (working_directory, env_vars);
            dialog.failed.connect (show_toast);
            show_dialog (dialog);
        }

        public async void install_dynamic_launcher (
            string label,
            string desktop_id,
            string desktop_entry,
            Bytes icon
        ) throws Error {
            var portal = new Xdp.Portal.initable_new ();
            var prep = yield portal.dynamic_launcher_prepare_install (
                Xdp.parent_new_gtk (win),
                label,
                new BytesIcon (icon).serialize (),
                Xdp.LauncherType.APPLICATION,
                null,
                true,
                false,
                null
            );
            var tok = prep.lookup_value ("token", new VariantType ("s"));
            if (tok == null) {
                throw new LumoriaError.FAILED (_("Menu shortcut install did not complete."));
            }
            if (!portal.dynamic_launcher_install (tok.get_string (), desktop_id, desktop_entry)) {
                throw new LumoriaError.FAILED (_("Menu shortcut install did not complete."));
            }
        }

        public void close_after_successful_launch () {
            if (Utils.Preferences.instance ().close_after_launch) win.force_close ();
        }
    }
}
