namespace Lumoria.Widgets.Dialogs {

    public class FileDialogs : Object {
        public static bool file_browse_blocked (Lumoria.Application.Context? ctx = null) {
            if (!Utils.EnvironmentInfo.is_gamescope ()) return false;
            if (ctx != null) {
                ctx.show_toast (_("File browsing is not available in a gamescope session."));
            }
            return true;
        }

        public static Gtk.FileDialog build_file_dialog (string title, Gtk.FileFilter primary) {
            var all = new Gtk.FileFilter ();
            all.name = _("All Files");
            all.add_pattern ("*");

            var store = new GLib.ListStore (typeof (Gtk.FileFilter));
            store.append (primary);
            store.append (all);

            var dialog = build_folder_dialog (title);
            dialog.filters = store;
            dialog.default_filter = primary;
            return dialog;
        }

        public static Gtk.FileFilter build_windows_executable_filter () {
            var filter = new Gtk.FileFilter ();
            filter.name = _("Windows Executables");
            filter.add_mime_type ("application/x-ms-dos-executable");
            filter.add_mime_type ("application/x-msi");
            filter.add_pattern ("*.exe");
            filter.add_pattern ("*.bat");
            filter.add_pattern ("*.msi");
            filter.add_pattern ("*.com");
            return filter;
        }

        public static void browse_shell_script (
            Gtk.Window? parent,
            Lumoria.Application.Context? ctx,
            owned DialogHelpers.PathSelectedCallback on_selected
        ) {
            if (file_browse_blocked (ctx)) return;
            var dialog = build_file_dialog (_("Select Prelaunch Script"), build_shell_script_filter ());
            open_file_dialog (parent, dialog, null, (owned) on_selected, (message) => {
                if (ctx != null) ctx.show_toast (message);
            });
        }

        public static Gtk.FileFilter build_shell_script_filter () {
            var filter = new Gtk.FileFilter ();
            filter.name = _("Shell Scripts");
            filter.add_mime_type ("application/x-shellscript");
            filter.add_mime_type ("text/x-shellscript");
            filter.add_pattern ("*.sh");
            filter.add_pattern ("*.bash");
            return filter;
        }

        public static bool is_windows_executable_path (string path) {
            var lower = path.down ();
            return lower.has_suffix (".exe")
                || lower.has_suffix (".bat")
                || lower.has_suffix (".msi")
                || lower.has_suffix (".com");
        }

        public static string resolve_folder_granted_executable (string folder, string selected_path) {
            if (!is_windows_executable_path (selected_path)) return "";

            var folder_path = Utils.normalize_dir_path (folder);
            var selected_dir = Utils.normalize_dir_path (Path.get_dirname (selected_path));
            if (selected_dir == folder_path) {
                return selected_path;
            }

            return Path.build_filename (folder, Path.get_basename (selected_path));
        }

        public static void present_executable_browse_dialog (
            Lumoria.Application.Context ctx,
            string? initial_folder,
            owned DialogHelpers.PathSelectedCallback on_selected,
            owned DialogHelpers.ErrorMessageCallback? on_error = null
        ) {
            if (ctx.ui == null) {
                if (on_error != null) on_error (_("A window is required to browse for an executable."));
                return;
            }
            var parent = ctx.ui.window;
            if (Utils.EnvironmentInfo.is_sandboxed ()) {
                present_sandbox_executable_browse_dialog (
                    ctx, parent, initial_folder, (owned) on_selected, (owned) on_error
                );
                return;
            }

            var dialog = build_file_dialog (
                _("Select Executable"),
                build_windows_executable_filter ()
            );
            open_file_dialog (parent, dialog, initial_folder, (path) => {
                if (!is_windows_executable_path (path)) {
                    if (on_error != null) {
                        on_error (_("Please choose a Windows executable file."));
                    }
                    return;
                }
                on_selected (path);
            }, (owned) on_error);
        }

        private static void present_sandbox_executable_browse_dialog (
            Lumoria.Application.Context ctx,
            Gtk.Window parent,
            string? initial_folder,
            owned DialogHelpers.PathSelectedCallback on_selected,
            owned DialogHelpers.ErrorMessageCallback? on_error = null
        ) {
            ctx.show_dialog (new SandboxExecutableDialog (parent, initial_folder, (owned) on_selected, (owned) on_error));
        }

        public static Gtk.FileDialog build_folder_dialog (string title) {
            var dialog = new Gtk.FileDialog ();
            dialog.title = title;
            dialog.modal = true;
            return dialog;
        }

        public static void open_file_dialog (
            Gtk.Window? parent,
            Gtk.FileDialog dialog,
            string? initial_folder,
            owned DialogHelpers.PathSelectedCallback on_selected,
            owned DialogHelpers.ErrorMessageCallback? on_error = null
        ) {
            if (initial_folder != null && FileUtils.test (initial_folder, FileTest.IS_DIR)) {
                dialog.initial_folder = File.new_for_path (initial_folder);
            }

            dialog.open.begin (parent, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file == null) return;
                    var path = file.get_path ();
                    if (path == null || path == "") return;
                    on_selected (path);
                } catch (Error e) {
                    report_unless_dismissed (e, on_error);
                }
            });
        }

        private static void report_unless_dismissed (Error e, DialogHelpers.ErrorMessageCallback? on_error) {
            if (e is Gtk.DialogError.DISMISSED || e is Gtk.DialogError.CANCELLED || e is IOError.CANCELLED) return;
            if (on_error != null) on_error (user_error (e));
        }

        public static void open_folder_dialog (
            Gtk.Window? parent,
            Gtk.FileDialog dialog,
            string? initial_folder,
            owned DialogHelpers.PathSelectedCallback on_selected,
            owned DialogHelpers.ErrorMessageCallback? on_error = null
        ) {
            select_folder (parent, dialog, initial_folder, (path, uri) => {
                on_selected (path);
            }, (owned) on_error);
        }

        public static void select_folder (
            Gtk.Window? parent,
            Gtk.FileDialog dialog,
            string? initial_folder,
            owned DialogHelpers.FolderSelectedCallback on_selected,
            owned DialogHelpers.ErrorMessageCallback? on_error = null
        ) {
            if (initial_folder != null && FileUtils.test (initial_folder, FileTest.IS_DIR)) {
                dialog.initial_folder = File.new_for_path (initial_folder);
            }

            dialog.select_folder.begin (parent, null, (obj, res) => {
                try {
                    var file = dialog.select_folder.end (res);
                    if (file == null) return;
                    var path = file.get_path () ?? "";
                    var uri = file.get_uri () ?? "";
                    if (path == "" && uri == "") return;
                    on_selected (path, uri);
                } catch (Error e) {
                    report_unless_dismissed (e, on_error);
                }
            });
        }

        public static void open_directory (
            Gtk.Window? parent,
            string path,
            owned DialogHelpers.ErrorMessageCallback? on_error = null
        ) {
            var launcher = new Gtk.FileLauncher (File.new_for_path (path));
            launcher.launch.begin (parent, null, (obj, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    report_unless_dismissed (e, on_error);
                }
            });
        }

        public static void open_http_uri (Gtk.Widget? widget, string uri) {
            if (!Markup.is_http_url (uri)) return;
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                var root = widget != null ? widget.get_root () : null;
                if (root is Lumoria.Ui.Window) {
                    ((Lumoria.Ui.Window) root).show_toast (
                        _("Browsing is not available in a gamescope session.")
                    );
                }
                return;
            }
            var parent = widget != null ? widget.get_root () as Gtk.Window : null;
            var launcher = new Gtk.UriLauncher (uri);
            launcher.launch.begin (parent, null, (obj, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    warning ("Failed to open URI: %s", e.message);
                }
            });
        }
    }

    /* Sandboxed picks grant the containing folder first so support files beside the EXE stay reachable. */
    private class SandboxExecutableDialog : DialogHelpers.GamepadDialog {
        private Gtk.Window host;
        private string? initial_folder;
        private DialogHelpers.PathSelectedCallback on_selected;
        private DialogHelpers.ErrorMessageCallback? on_error;
        private string folder_path = "";
        private string executable_path = "";
        private Adw.ActionRow folder_row;
        private Adw.ActionRow executable_row;
        private Gtk.Button executable_btn;
        private DialogHelpers.FormFooter footer;

        public SandboxExecutableDialog (
            Gtk.Window parent,
            string? initial_folder,
            owned DialogHelpers.PathSelectedCallback on_selected,
            owned DialogHelpers.ErrorMessageCallback? on_error
        ) {
            Object (title: _("Select Executable"), content_width: 440);
            host = parent;
            this.initial_folder = initial_folder;
            this.on_selected = (owned) on_selected;
            this.on_error = (owned) on_error;

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, Lumoria.Ui.Metrics.GROUP_SPACING);
            PageChrome.margins (content, Lumoria.Ui.Metrics.PAGE_MARGIN, Lumoria.Ui.Metrics.GROUP_SPACING);
            content.append (Messages.warning (
                _("Sandboxed apps can only use files you grant access to. Many Windows programs need DLLs, configuration, or data beside the EXE, so choose the containing folder first, then choose the EXE inside it."),
                0, 0, 0, 0
            ));

            var group = new Adw.PreferencesGroup ();
            folder_row = new Adw.ActionRow ();
            folder_row.title = _("Containing Folder");
            folder_row.subtitle = _("Choose the folder that contains the executable and its support files.");
            folder_row.subtitle_lines = 2;
            var folder_btn = PageChrome.browse_button ();
            folder_btn.clicked.connect (pick_folder);
            folder_row.add_suffix (folder_btn);
            group.add (folder_row);

            executable_row = new Adw.ActionRow ();
            executable_row.title = _("Executable");
            executable_row.subtitle = _("Choose the EXE inside the selected folder.");
            executable_row.subtitle_lines = 2;
            executable_btn = PageChrome.browse_button ();
            executable_btn.sensitive = false;
            executable_btn.clicked.connect (pick_executable);
            executable_row.add_suffix (executable_btn);
            group.add (executable_row);
            content.append (group);

            footer = new DialogHelpers.FormFooter (_("Use Executable"));
            footer.save_button.sensitive = false;
            footer.save_button.clicked.connect (accept);
            footer.cancel_button.clicked.connect (() => close ());
            PageChrome.margins (footer, 0, 0);
            content.append (footer);

            set_body (DialogHelpers.dialog_body (content));
        }

        private void report (string message) {
            if (on_error != null) on_error (message);
        }

        private void pick_folder () {
            var dialog = FileDialogs.build_folder_dialog (_("Select Folder Containing EXE"));
            FileDialogs.open_folder_dialog (host, dialog, initial_folder, (path) => {
                folder_path = path;
                executable_path = "";
                folder_row.subtitle = folder_path;
                executable_row.subtitle = _("Choose the EXE inside the selected folder.");
                executable_btn.sensitive = true;
                footer.save_button.sensitive = false;
            }, report);
        }

        private void pick_executable () {
            if (folder_path == "") return;
            var dialog = FileDialogs.build_file_dialog (
                _("Select EXE In Folder"),
                FileDialogs.build_windows_executable_filter ()
            );
            FileDialogs.open_file_dialog (host, dialog, folder_path, (path) => {
                var resolved = FileDialogs.resolve_folder_granted_executable (folder_path, path);
                if (resolved == "") {
                    executable_path = "";
                    executable_row.subtitle = _("Please choose a Windows executable in the selected folder.");
                    footer.save_button.sensitive = false;
                    return;
                }
                executable_path = resolved;
                executable_row.subtitle = executable_path;
                footer.save_button.sensitive = true;
            }, report);
        }

        private void accept () {
            if (executable_path == "") return;
            on_selected (executable_path);
            close ();
        }
    }
}
