namespace Lumoria.Widgets.Dialogs {

    public class InstallDialog : Adw.Dialog {
        public signal void install_completed (bool success);
        public signal void prefix_delete_requested ();

        private Gtk.Image status_icon;
        private Gtk.Label status_label;
        private Gtk.ProgressBar progress_bar;
        private Gtk.TextView log_view;
        private Gtk.ScrolledWindow log_scroll;
        private Gtk.Revealer install_notice_revealer;
        private Gtk.Button close_btn;
        private Gtk.Button close_primary_btn;
        private Gtk.Button cancel_btn;
        private Gtk.Button open_logs_btn;
        private Gtk.Button copy_log_btn;
        private Gtk.Label result_label;

        private Cancellable cancellable;
        private Runtime.InstallProgress install_progress;
        private string prefix_path;
        private uint cancel_pulse_source_id = 0;
        private bool install_failed = false;
        private bool install_cancelled = false;

        public InstallDialog () {
            Object (
                content_width: 600
            );
            this.cancellable = new Cancellable ();
            build_ui ();
        }

        private void build_ui () {
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = false;
            header.show_start_title_buttons = false;

            var header_status = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            header_status.halign = Gtk.Align.CENTER;
            header_status.hexpand = true;

            status_icon = new Gtk.Image.from_icon_name (IconRegistry.PENDING);
            status_icon.pixel_size = 14;
            header_status.append (status_icon);

            status_label = new Gtk.Label (_("Preparing…"));
            status_label.add_css_class ("heading");
            status_label.wrap = false;
            status_label.xalign = 0.5f;
            status_label.hexpand = true;
            status_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            header_status.append (status_label);
            header.title_widget = header_status;

            cancel_btn = new Gtk.Button.with_label (_("Cancel"));
            cancel_btn.add_css_class ("destructive-action");
            cancel_btn.clicked.connect (() => {
                cancellable.cancel ();
                cancel_btn.sensitive = false;
                cancel_btn.label = _("Cancelling…");
                status_label.label = _("Cancelling…");
                install_notice_revealer.reveal_child = false;
                scroll_log_to_bottom ();
                progress_bar.pulse_step = 0.06;
                if (cancel_pulse_source_id == 0) {
                    cancel_pulse_source_id = Timeout.add (120, () => {
                        progress_bar.pulse ();
                        return true;
                    });
                }
            });
            close_btn = new Gtk.Button.from_icon_name (IconRegistry.CLOSE);
            close_btn.add_css_class ("circular");
            close_btn.add_css_class ("flat");
            close_btn.tooltip_text = _("Close");
            close_btn.sensitive = false;
            close_btn.clicked.connect (on_close_requested);
            header.pack_end (close_btn);

            open_logs_btn = new Gtk.Button.from_icon_name (IconRegistry.OPEN_FOLDER);
            open_logs_btn.tooltip_text = _("Open Logs");
            open_logs_btn.clicked.connect (on_open_logs);

            copy_log_btn = new Gtk.Button.from_icon_name (IconRegistry.COPY);
            copy_log_btn.tooltip_text = _("Copy Log");
            copy_log_btn.clicked.connect (on_copy_log);

            close_primary_btn = new Gtk.Button.with_label (_("Close"));
            close_primary_btn.add_css_class ("suggested-action");
            close_primary_btn.visible = false;
            close_primary_btn.clicked.connect (on_close_requested);

            toolbar.add_top_bar (header);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            content.margin_start = 12;
            content.margin_end = 12;
            content.margin_top = 8;
            content.margin_bottom = 12;

            progress_bar = new Gtk.ProgressBar ();
            progress_bar.show_text = true;
            progress_bar.margin_start = 24;
            progress_bar.margin_end = 24;
            content.append (progress_bar);

            result_label = new Gtk.Label ("");
            result_label.wrap = true;
            result_label.xalign = 0f;
            result_label.hexpand = true;
            result_label.selectable = true;
            result_label.margin_start = 24;
            result_label.margin_end = 24;
            result_label.visible = false;
            result_label.add_css_class ("dim-label");
            content.append (result_label);

            var log_frame = new Gtk.Frame (null);
            log_frame.vexpand = true;

            log_scroll = new Gtk.ScrolledWindow ();
            log_scroll.min_content_height = 150;

            log_view = new Gtk.TextView ();
            log_view.editable = false;
            log_view.monospace = true;
            log_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            log_view.top_margin = 4;
            log_view.bottom_margin = 4;
            log_view.left_margin = 8;
            log_view.right_margin = 8;
            log_view.add_css_class ("dim-label");
            log_scroll.child = log_view;
            log_frame.child = log_scroll;
            content.append (log_frame);

            var install_notice = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            install_notice.add_css_class ("card");
            install_notice.margin_top = 6;
            install_notice.margin_bottom = 4;
            install_notice.margin_start = 2;
            install_notice.margin_end = 2;
            install_notice.hexpand = true;

            var notice_icon = new Gtk.Image.from_icon_name (IconRegistry.INFO);
            notice_icon.valign = Gtk.Align.START;
            notice_icon.margin_top = 10;
            notice_icon.margin_start = 10;
            install_notice.append (notice_icon);

            var notice_label = new Gtk.Label (
                _("Installation can take a while… It may look idle at times, but work is still in progress. If anything fails, Lumoria will clearly show it here.")
            );
            notice_label.wrap = true;
            notice_label.xalign = 0f;
            notice_label.hexpand = true;
            notice_label.margin_top = 10;
            notice_label.margin_bottom = 10;
            notice_label.margin_end = 10;
            notice_label.add_css_class ("dim-label");
            install_notice.append (notice_label);

            install_notice_revealer = new Gtk.Revealer ();
            install_notice_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            install_notice_revealer.reveal_child = true;
            install_notice_revealer.child = install_notice;
            content.append (install_notice_revealer);

            var actions_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions_row.halign = Gtk.Align.FILL;

            var log_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            log_actions.add_css_class ("linked");
            log_actions.append (copy_log_btn);
            log_actions.append (open_logs_btn);
            actions_row.append (log_actions);

            var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            actions_row.append (spacer);

            actions_row.append (cancel_btn);
            actions_row.append (close_primary_btn);
            content.append (actions_row);

            toolbar.content = content;
            this.child = toolbar;
        }

        public void start_install (Runtime.InstallOptions opts) {
            this.prefix_path = opts.prefix_path;
            if (Utils.is_prefixes_root_path (opts.prefix_path)) {
                append_log (_("You cannot install directly into the prefixes root.\n"));
                append_log (_("Choose a subdirectory inside: %s\n").printf (Utils.default_prefix_dir ()));
                on_finished (false, _("Install blocked: invalid prefix directory"));
                return;
            }
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                append_log (_("Prefix installation is disabled while in a gamescope session.\n"));
                on_finished (false, _("Install blocked in gamescope"));
                return;
            }
            install_progress = new Runtime.InstallProgress ();

            install_progress.step_changed.connect ((desc) => {
                Idle.add (() => {
                    status_label.label = desc;
                    return false;
                });
            });

            install_progress.progress_changed.connect ((frac) => {
                Idle.add (() => {
                    progress_bar.fraction = frac;
                    progress_bar.text = "%.0f%%".printf (frac * 100);
                    return false;
                });
            });

            install_progress.log_message.connect ((msg) => {
                Idle.add (() => {
                    var buf = log_view.buffer;
                    Gtk.TextIter end_iter;
                    buf.get_end_iter (out end_iter);
                    buf.insert (ref end_iter, msg, msg.length);
                    scroll_log_to_bottom ();
                    return false;
                });
            });

            install_progress.install_finished.connect ((success, msg) => {
                Idle.add (() => {
                    on_finished (success, msg);
                    return false;
                });
            });

            new Thread<bool> ("install-worker", () => {
                Runtime.run_full_install (opts, install_progress, cancellable);
                return true;
            });
        }

        private void on_finished (bool success, string message) {
            if (cancel_pulse_source_id != 0) {
                Source.remove (cancel_pulse_source_id);
                cancel_pulse_source_id = 0;
            }
            install_notice_revealer.reveal_child = false;
            cancel_btn.visible = false;
            close_primary_btn.visible = true;
            close_btn.sensitive = true;
            install_failed = false;
            install_cancelled = false;

            if (success) {
                status_icon.icon_name = IconRegistry.SUCCESS;
                status_label.label = _("Installation Complete");
                progress_bar.fraction = 1.0;
                progress_bar.text = "100%";
            } else {
                install_cancelled = cancellable.is_cancelled ();
                if (install_cancelled) {
                    status_icon.icon_name = IconRegistry.WARNING;
                    status_label.label = _("Installation Cancelled");
                } else {
                    status_icon.icon_name = IconRegistry.ERROR;
                    status_label.label = _("Installation Failed");
                    install_failed = true;
                }
            }

            result_label.label = message;
            result_label.visible = message.strip () != "";
            scroll_log_to_bottom ();
            install_completed (success);
        }

        private void on_close_requested () {
            if (!install_failed && !install_cancelled) {
                close ();
                return;
            }
            var title = install_cancelled ? _("Installation Cancelled") : _("Installation Failed");
            var body = install_cancelled
                ? _("The prefix at %s may be incomplete because installation was cancelled. Would you like to delete it?").printf (prefix_path)
                : _("The prefix at %s may be incomplete. Would you like to delete it?").printf (prefix_path);
            var dialog = new Adw.AlertDialog (
                title,
                body
            );
            dialog.add_response ("close", _("Keep Prefix"));
            dialog.add_response ("delete", _("Delete Prefix"));
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "close";
            dialog.close_response = "close";
            dialog.response.connect ((response) => {
                if (response == "delete") {
                    prefix_delete_requested ();
                }
                close ();
            });
            dialog.present (this);
        }

        private void on_open_logs () {
            var log_dir = Path.build_filename (prefix_path, "logs");
            Utils.ensure_dir (log_dir);
            var file = File.new_for_path (log_dir);
            var launcher = new Gtk.FileLauncher (file);
            launcher.launch.begin (null, null);
        }

        private void on_copy_log () {
            var buf = log_view.buffer;
            Gtk.TextIter start, end;
            buf.get_start_iter (out start);
            buf.get_end_iter (out end);
            var text = buf.get_text (start, end, false);

            var clipboard = get_clipboard ();
            clipboard.set_text (text);

            copy_log_btn.icon_name = IconRegistry.CHECKMARK;
            copy_log_btn.tooltip_text = _("Copied!");
            Timeout.add (2000, () => {
                copy_log_btn.icon_name = IconRegistry.COPY;
                copy_log_btn.tooltip_text = _("Copy Log");
                return false;
            });
        }

        private void append_log (string text) {
            var buf = log_view.buffer;
            Gtk.TextIter end_iter;
            buf.get_end_iter (out end_iter);
            buf.insert (ref end_iter, text, text.length);
            scroll_log_to_bottom ();
        }

        private void scroll_log_to_bottom () {
            Gtk.TextIter end_iter;
            log_view.buffer.get_end_iter (out end_iter);
            log_view.scroll_to_iter (end_iter, 0, false, 0, 1.0);

            Idle.add (() => {
                Gtk.TextIter end_iter2;
                log_view.buffer.get_end_iter (out end_iter2);
                log_view.scroll_to_iter (end_iter2, 0, false, 0, 1.0);
                return false;
            });
        }
    }
}
