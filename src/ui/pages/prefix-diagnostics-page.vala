namespace Lumoria.Ui {
    public class PrefixDiagnosticsPage : Gtk.Box {
        private Application.Context ctx;
        private Models.PrefixEntry entry;
        private Utils.PrefixDiagnostics? diagnostics;
        private Gtk.TextView report_view;
        private Gtk.CheckButton sanitized_report;
        private Gtk.Box selected_logs;
        private DiagnosticsDialog log_picker;
        private DiagnosticsDialog log_viewer;
        private DiagnosticsDialog export_dialog;
        private Gtk.TextView preview_view;
        private Gtk.Label selection_status;
        private Gtk.Label privacy;
        private Gtk.Box export_panel;
        private Gtk.Box log_list;
        private Gtk.Box actions;
        private Gtk.Button refresh_button;
        private Gtk.Button save_zip_button;
        private Gtk.CheckButton include_logs;
        private Gtk.CheckButton sanitize_logs;
        private Gee.ArrayList<Gtk.CheckButton> checks = new Gee.ArrayList<Gtk.CheckButton> ();
        private Cancellable refresh_operation = new Cancellable ();
        private Cancellable export_operation = new Cancellable ();
        private Cancellable preview_operation = new Cancellable ();
        private Utils.DiagnosticLog? preview_log;

        public PrefixDiagnosticsPage (Application.Context ctx, Models.PrefixEntry entry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.entry = entry;
            build_logging_section ();
            build_report_section ();
            build_export_dialog ();
            build_log_viewer ();
            refresh ();
        }

        private void build_logging_section () {
            var logging = Widgets.PageChrome.build_group ("");
            var keep_logs = new Adw.SwitchRow ();
            keep_logs.title = _("Enable Logging");
            keep_logs.subtitle = _("This enables logging for all prefixes.");
            Utils.Preferences.instance ().bind_property (
                "keep-runtime-logs", keep_logs, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE
            );
            logging.add (keep_logs);
            append (logging);

            var logs = new Widgets.PageSection (_("Logs"));
            var prefix_logs = Widgets.PageChrome.action_row (_("Open Prefix Logs"), _("Open"));
            prefix_logs.button.clicked.connect (() => ctx.open_log_dir (Utils.prefix_log_dir (entry.resolved_path ())));
            logs.add (prefix_logs);
            var manager_logs = Widgets.PageChrome.action_row (_("Open Session Manager Logs"), _("Open"));
            manager_logs.button.clicked.connect (() => ctx.open_log_dir (Utils.session_manager_log_dir ()));
            logs.add (manager_logs);
            append (logs);
        }

        private void build_report_section () {
            actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            Widgets.PageChrome.margins (actions, Metrics.PAGE_MARGIN, Metrics.GROUP_SPACING);
            refresh_button = icon_button (Widgets.IconRegistry.REFRESH, _("Refresh"), refresh);
            actions.append (refresh_button);
            actions.append (icon_button (Widgets.IconRegistry.COPY, _("Copy"), () => {
                if (diagnostics == null) return;
                get_clipboard ().set_text (diagnostics.report_text (sanitized_report.active));
                ctx.show_toast (_("Report copied."));
            }));
            actions.append (icon_button (Widgets.IconRegistry.SAVE, _("Save Report"), save_report));
            actions.append (button (_("Export ZIP"), () => {
                export_dialog.present (this);
                include_logs.grab_focus ();
            }));
            sanitized_report = new Gtk.CheckButton.with_label (_("Sanitized"));
            sanitized_report.toggled.connect (() => {
                if (diagnostics != null) report_view.buffer.text = diagnostics.report_text (sanitized_report.active);
            });
            actions.append (sanitized_report);
            append (actions);

            report_view = text_view ();
            var report_scroll = text_scroll (report_view, 320);
            report_scroll.vexpand = true;
            Widgets.PageChrome.margins (report_scroll, Metrics.PAGE_MARGIN, Metrics.GROUP_SPACING);
            append (report_scroll);
        }

        private void build_export_dialog () {
            export_panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            Widgets.PageChrome.margins (export_panel, Metrics.PAGE_MARGIN, Metrics.GROUP_SPACING);
            export_dialog = new DiagnosticsDialog (export_panel, _("Export Diagnostics"));

            include_logs = new Gtk.CheckButton.with_label (_("Include logs"));
            include_logs.active = true;
            export_panel.append (include_logs);
            sanitize_logs = new Gtk.CheckButton.with_label (_("Sanitize logs"));
            export_panel.append (sanitize_logs);
            privacy = label ("");
            export_panel.append (privacy);
            update_privacy ();

            var picker_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            Widgets.PageChrome.margins (picker_content, Metrics.PAGE_MARGIN, Metrics.GROUP_SPACING);
            log_picker = new DiagnosticsDialog (picker_content, _("Select Logs"));
            export_panel.append (button (_("Select Logs…"), () => log_picker.present (export_panel)));

            selected_logs = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var selected_scroll = new Gtk.ScrolledWindow ();
            selected_scroll.vexpand = true;
            selected_scroll.min_content_height = 140;
            selected_scroll.child = selected_logs;
            export_panel.append (selected_scroll);

            var selection_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            selection_actions.append (button (_("Select All"), () => {
                foreach (var check in checks) check.active = true;
            }));
            selection_actions.append (button (_("Clear"), () => {
                foreach (var check in checks) check.active = false;
            }));
            picker_content.append (selection_actions);
            selection_status = label ("");
            export_panel.append (selection_status);

            log_list = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var logs_scroll = new Gtk.ScrolledWindow ();
            logs_scroll.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            logs_scroll.min_content_height = 120;
            logs_scroll.vexpand = true;
            logs_scroll.child = log_list;
            picker_content.append (logs_scroll);
            picker_content.append (button (_("Done"), () => log_picker.close ()));

            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            save_zip_button = button (_("Save ZIP…"), save_zip);
            footer.append (save_zip_button);
            footer.append (button (_("Cancel"), () => {
                export_operation.cancel ();
                export_dialog.close ();
            }));
            export_panel.append (footer);

            include_logs.toggled.connect (() => {
                log_list.sensitive = include_logs.active;
                selection_actions.sensitive = include_logs.active;
                sanitize_logs.sensitive = include_logs.active;
                update_selection ();
            });
            sanitize_logs.toggled.connect (() => {
                update_privacy ();
                if (preview_log != null) load_preview ();
            });
        }

        private void build_log_viewer () {
            preview_view = text_view ();
            var viewer_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            Widgets.PageChrome.margins (viewer_content, Metrics.PAGE_MARGIN, Metrics.GROUP_SPACING);
            log_viewer = new DiagnosticsDialog (viewer_content, _("Log Viewer"));
            var preview_scroll = text_scroll (preview_view, 160);
            preview_scroll.vexpand = true;
            viewer_content.append (preview_scroll);

            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            footer.append (icon_button (Widgets.IconRegistry.COPY, _("Copy"), () => {
                get_clipboard ().set_text (preview_view.buffer.text);
                log_viewer.push_toast (_("Log copied."));
            }));
            viewer_content.append (footer);

            log_viewer.closed.connect (() => {
                preview_operation.cancel ();
                preview_log = null;
            });
        }

        private static Gtk.Label label (string text) {
            var widget = new Gtk.Label (text);
            widget.wrap = true;
            widget.xalign = 0;
            return widget;
        }

        private static Gtk.Button icon_button (string icon, string title, owned Utils.Action action) {
            var widget = new Gtk.Button.from_icon_name (icon);
            Widgets.PageChrome.set_icon_label (widget, title);
            widget.clicked.connect (() => action ());
            return widget;
        }

        private static Gtk.Button button (string title, owned Utils.Action action) {
            var widget = new Gtk.Button.with_label (title);
            widget.clicked.connect (() => action ());
            return widget;
        }

        private static Gtk.TextView text_view () {
            var view = new Gtk.TextView ();
            view.editable = false;
            view.monospace = true;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.left_margin = 8;
            view.right_margin = 8;
            view.top_margin = 8;
            view.bottom_margin = 8;
            return view;
        }

        private static Gtk.ScrolledWindow text_scroll (Gtk.TextView view, int height) {
            var scroll = new Gtk.ScrolledWindow ();
            scroll.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scroll.min_content_height = height;
            scroll.child = view;
            scroll.add_css_class ("card");
            return scroll;
        }

        private void refresh () {
            refresh_operation.cancel ();
            refresh_operation = new Cancellable ();
            var cancel = refresh_operation;
            var next = new Utils.PrefixDiagnostics (entry);
            actions.sensitive = false;
            report_view.buffer.text = _("Collecting diagnostics…");
            Utils.run_background ("prefix-diagnostics", () => next.collect (cancel), (error) => {
                if (cancel.is_cancelled ()) return;
                if (error != null) {
                    report_view.buffer.text = _("Could not collect diagnostics: %s").printf (error.message);
                    refresh_button.sensitive = true;
                    return;
                }
                diagnostics = next;
                report_view.buffer.text = next.report_text (sanitized_report.active);
                actions.sensitive = true;
                populate_logs ();
            });
        }

        private void populate_logs () {
            preview_operation.cancel ();
            preview_log = null;
            preview_view.buffer.text = "";
            checks.clear ();
            clear_children (log_list);
            foreach (var log in diagnostics.logs) {
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                var check = new Gtk.CheckButton ();
                var date = new DateTime.from_unix_local ((int64) log.modified).format ("%Y-%m-%d %H:%M");
                check.child = label ("%s — %s\n%s · %s".printf (log.category, log.name, date, format_size (log.size)));
                check.hexpand = true;
                check.active = log.selected;
                checks.add (check);
                row.append (check);
                row.append (button (_("Preview"), () => show_log (log)));
                log_list.append (row);
                check.toggled.connect (update_selection);
            }
            if (diagnostics.logs.size == 0) log_list.append (label (_("No logs recorded yet.")));
            update_selection ();
        }

        private static void clear_children (Gtk.Box box) {
            Gtk.Widget? child;
            while ((child = box.get_first_child ()) != null) box.remove (child);
        }

        private void update_selection () {
            int count = 0;
            int64 size = 0;
            clear_children (selected_logs);
            if (diagnostics != null && include_logs.active) {
                for (int i = 0; i < checks.size; i++) {
                    if (!checks[i].active) continue;
                    var log = diagnostics.logs[i];
                    var check = checks[i];
                    count++;
                    size += log.size;
                    var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                    var name = label (log.name + " · " + format_size (log.size));
                    name.hexpand = true;
                    row.append (name);
                    row.append (button (_("View"), () => show_log (log)));
                    row.append (icon_button (Widgets.IconRegistry.CLOSE, _("Remove"), () => check.active = false));
                    selected_logs.append (row);
                }
            }
            selection_status.label = _("%d logs selected · %s").printf (count, format_size (size));
            if (count == 0) selected_logs.append (label (_("No logs selected.")));
        }

        private void update_privacy () {
            privacy.label = sanitize_logs.active
                ? _("Replaces detected usernames and hostname.")
                : _("Logs include usernames and paths.");
        }

        private void show_log (Utils.DiagnosticLog log) {
            preview_log = log;
            log_viewer.title = log.name;
            log_viewer.present (export_panel);
            load_preview ();
        }

        private void load_preview () {
            preview_operation.cancel ();
            preview_operation = new Cancellable ();
            var cancel = preview_operation;
            var log = preview_log;
            var current = diagnostics;
            bool sanitize = sanitize_logs.active;
            string content = "";
            preview_view.buffer.text = _("Loading preview…");
            Utils.run_background ("diagnostic-log-preview", () => {
                content = Utils.PrefixDiagnostics.read_text (log.path, cancel);
                if (sanitize) content = current.sanitize (content);
                if (log.size > Utils.PrefixDiagnostics.LOG_LIMIT) {
                    content += "\n" + _("[Preview truncated; export includes the complete log.]");
                }
            }, (error) => {
                if (cancel.is_cancelled ()) return;
                if (error == null) {
                    preview_view.buffer.text = content;
                } else {
                    preview_view.buffer.text = sanitize ? current.sanitize (error.message) : error.message;
                }
            });
        }

        private void save_report () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Save Diagnostics Report");
            dialog.initial_name = "lumoria-diagnostics-%s.txt".printf (Utils.log_stamp ());
            var text = diagnostics.report_text (sanitized_report.active);
            dialog.save.begin (get_root () as Gtk.Window, null, (obj, result) => {
                try {
                    var destination = dialog.save.end (result);
                    Utils.run_background ("save-diagnostics-report", () => {
                        string? etag;
                        destination.replace_contents (text.data, null, false, FileCreateFlags.PRIVATE, out etag);
                    }, (error) => ctx.show_toast (error == null ? _("Report saved.") : error.message));
                } catch (Error e) {
                    report_error (e);
                }
            });
        }

        private void save_zip () {
            var current = diagnostics;
            var selected = new Gee.ArrayList<Utils.DiagnosticLog> ();
            if (include_logs.active) {
                for (int i = 0; i < checks.size; i++) {
                    if (checks[i].active) selected.add (current.logs[i]);
                }
            }
            bool sanitize = sanitize_logs.active;
            bool sanitize_report = sanitized_report.active;
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Save Diagnostics ZIP");
            dialog.initial_name = "lumoria-diagnostics-%s.zip".printf (Utils.log_stamp ());
            dialog.save.begin (get_root () as Gtk.Window, null, (obj, result) => {
                try {
                    var destination = dialog.save.end (result);
                    export_operation = new Cancellable ();
                    var cancel = export_operation;
                    save_zip_button.sensitive = false;
                    refresh_button.sensitive = false;
                    Utils.run_background ("diagnostics-zip", () => {
                        current.export_zip (destination, selected, sanitize, cancel, sanitize_report);
                    }, (error) => {
                        save_zip_button.sensitive = true;
                        refresh_button.sensitive = true;
                        export_dialog.push_toast (error == null ? _("ZIP saved.") : error.message);
                    });
                } catch (Error e) {
                    report_error (e);
                }
            });
        }

        private void report_error (Error error) {
            if (error is Gtk.DialogError.DISMISSED
                || error is Gtk.DialogError.CANCELLED
                || error is IOError.CANCELLED) {
                return;
            }
            ctx.show_toast (error.message);
        }
    }

    private class DiagnosticsDialog : Widgets.Dialogs.DialogHelpers.GamepadDialog {
        public DiagnosticsDialog (Gtk.Widget content, string heading) {
            Object (title: heading, content_width: 720, content_height: 680);
            set_body (Widgets.Dialogs.DialogHelpers.dialog_body (content));
        }
    }
}
