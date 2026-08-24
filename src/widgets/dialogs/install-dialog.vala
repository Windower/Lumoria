namespace Lumoria.Widgets.Dialogs {

    public class InstallDialog : Adw.Dialog {
        private const int LOG_POLL_MS = 200;
        private const int LOG_MAX_LINES = 3000;
        private const int64 LOG_TAIL_BYTES = 256 * 1024;
        private const int64 LOG_COPY_MAX_BYTES = 256 * 1024;

        public signal void install_completed (bool success);
        public signal void prefix_delete_requested ();

        private Gtk.Image status_icon;
        private Gtk.Label status_label;
        private Gtk.ProgressBar progress_bar;
        private Gtk.TextView log_view;
        private Gtk.ScrolledWindow log_scroll;
        private Gtk.Revealer log_revealer;
        private Gtk.Revealer install_notice_revealer;
        private Gtk.ToggleButton show_log_btn;
        private Gtk.Button close_btn;
        private Gtk.Button close_primary_btn;
        private Gtk.Button cancel_btn;
        private Gtk.Button open_logs_btn;
        private Gtk.Button copy_log_btn;
        private Gtk.Label result_label;

        private Cancellable cancellable;
        private Runtime.InstallProgress install_progress;
        private string prefix_path;
        private string log_path = "";
        private int64 log_offset = 0;
        private uint log_poll_source_id = 0;
        private uint cancel_pulse_source_id = 0;
        private bool dialog_alive = true;
        private bool install_failed = false;
        private bool install_cancelled = false;
        private bool action_mode = false;

        public InstallDialog () {
            Object (
                content_width: 600,
                follows_content_size: true
            );
            this.cancellable = new Cancellable ();
            build_ui ();
            closed.connect (() => {
                dialog_alive = false;
                stop_log_tail (true);
                if (cancel_pulse_source_id != 0) {
                    Source.remove (cancel_pulse_source_id);
                    cancel_pulse_source_id = 0;
                }
            });
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
                install_notice_revealer.visible = false;
                if (log_revealer.reveal_child) {
                    scroll_log_to_bottom ();
                }
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

            show_log_btn = new Gtk.ToggleButton.with_label (_("Show Log"));
            show_log_btn.toggled.connect (on_show_log_toggled);

            open_logs_btn = new Gtk.Button.from_icon_name (IconRegistry.OPEN_FOLDER);
            open_logs_btn.tooltip_text = _("Open Logs");
            open_logs_btn.sensitive = false;
            open_logs_btn.clicked.connect (on_open_logs);

            copy_log_btn = new Gtk.Button.from_icon_name (IconRegistry.COPY);
            copy_log_btn.tooltip_text = _("Copy Log");
            copy_log_btn.sensitive = false;
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
            result_label.max_width_chars = 56;
            result_label.xalign = 0f;
            result_label.hexpand = true;
            result_label.selectable = true;
            result_label.margin_start = 24;
            result_label.margin_end = 24;
            result_label.visible = false;
            result_label.add_css_class ("dim-label");
            content.append (result_label);

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
            notice_label.max_width_chars = 56;
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

            var log_frame = new Gtk.Frame (null);
            log_frame.add_css_class ("install-log");
            log_frame.hexpand = true;

            log_scroll = new Gtk.ScrolledWindow ();
            log_scroll.min_content_height = 220;
            log_scroll.max_content_height = 360;
            log_scroll.hexpand = true;
            log_scroll.propagate_natural_height = true;

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

            log_revealer = new Gtk.Revealer ();
            log_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            log_revealer.reveal_child = false;
            log_revealer.hexpand = true;
            log_revealer.vexpand = false;
            log_revealer.child = log_frame;
            content.append (log_revealer);

            var actions_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions_row.halign = Gtk.Align.FILL;

            var log_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            log_actions.add_css_class ("linked");
            log_actions.append (show_log_btn);
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
            action_mode = false;
            this.prefix_path = opts.prefix_path;
            if (Utils.is_prefixes_root_path (opts.prefix_path)) {
                on_finished (false, _("Install blocked: choose a subdirectory inside %s, not the prefixes root.").printf (Utils.default_prefix_dir ()));
                return;
            }
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                on_finished (false, _("Install blocked in gamescope"));
                return;
            }
            install_progress = new Runtime.InstallProgress ();
            bind_progress_handlers ();

            new Thread<bool> ("install-worker", () => {
                Runtime.run_full_install (opts, install_progress, cancellable);
                return true;
            });
        }

        public void start_action (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs,
            string action_id
        ) {
            action_mode = true;
            this.prefix_path = entry.resolved_path ();
            install_progress = new Runtime.InstallProgress ();
            bind_progress_handlers ();

            new Thread<bool> ("spec-action-worker", () => {
                Runtime.run_spec_action (entry, runner_specs, launcher_specs, action_id, install_progress, cancellable);
                return true;
            });
        }

        public void start_redist_install (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            string redist_id
        ) {
            action_mode = true;
            this.prefix_path = entry.resolved_path ();
            install_progress = new Runtime.InstallProgress ();
            bind_progress_handlers ();

            new Thread<bool> ("redist-install-worker", () => {
                Runtime.run_redist_install (entry, runner_specs, redist_id, install_progress, cancellable);
                return true;
            });
        }

        private void bind_progress_handlers () {
            install_progress.step_changed.connect ((desc) => {
                Idle.add (() => {
                    if (!dialog_alive) {
                        return false;
                    }
                    status_label.label = desc;
                    return false;
                });
            });

            install_progress.progress_changed.connect ((frac) => {
                Idle.add (() => {
                    if (!dialog_alive) {
                        return false;
                    }
                    progress_bar.fraction = frac;
                    progress_bar.text = "%.0f%%".printf (frac * 100);
                    return false;
                });
            });

            install_progress.log_ready.connect ((path) => {
                Idle.add (() => {
                    if (!dialog_alive) {
                        return false;
                    }
                    log_path = path;
                    var have_log = path != "";
                    open_logs_btn.sensitive = have_log;
                    copy_log_btn.sensitive = have_log;
                    if (show_log_btn.active) {
                        start_log_tail ();
                    }
                    return false;
                });
            });

            install_progress.install_finished.connect ((success, msg) => {
                Idle.add (() => {
                    if (!dialog_alive) {
                        return false;
                    }
                    on_finished (success, msg);
                    return false;
                });
            });
        }

        private void on_finished (bool success, string message) {
            if (cancel_pulse_source_id != 0) {
                Source.remove (cancel_pulse_source_id);
                cancel_pulse_source_id = 0;
            }
            install_notice_revealer.reveal_child = false;
            install_notice_revealer.visible = false;
            cancel_btn.visible = false;
            close_primary_btn.visible = true;
            close_btn.sensitive = true;
            install_failed = false;
            install_cancelled = false;

            if (success) {
                status_icon.icon_name = IconRegistry.SUCCESS;
                status_label.label = action_mode ? _("Action Complete") : _("Installation Complete");
                progress_bar.fraction = 1.0;
                progress_bar.text = "100%";
            } else {
                install_cancelled = cancellable.is_cancelled ();
                if (install_cancelled) {
                    status_icon.icon_name = IconRegistry.WARNING;
                    status_label.label = action_mode ? _("Action Cancelled") : _("Installation Cancelled");
                } else {
                    status_icon.icon_name = IconRegistry.ERROR;
                    status_label.label = action_mode ? _("Action Failed") : _("Installation Failed");
                    install_failed = true;
                }
            }

            result_label.label = message;
            result_label.visible = message.strip () != "";
            if (install_failed && log_path != "") {
                show_log_btn.active = true;
            }
            if (log_revealer.reveal_child) {
                poll_log_tail ();
                scroll_log_to_bottom ();
            }
            install_completed (success);
        }

        private void on_close_requested () {
            if (action_mode) {
                close ();
                return;
            }

            if (!install_failed && !install_cancelled) {
                var cache_dialog = new Adw.AlertDialog (
                    _("Clear Install Cache?"),
                    _("Cached downloads will save time if you need to reinstall.")
                );
                cache_dialog.add_response ("remove", _("Remove Files"));
                cache_dialog.add_response ("keep", _("Keep Files"));
                cache_dialog.set_response_appearance ("remove", Adw.ResponseAppearance.DESTRUCTIVE);
                cache_dialog.set_response_appearance ("keep", Adw.ResponseAppearance.SUGGESTED);
                cache_dialog.default_response = "keep";
                cache_dialog.close_response = "keep";
                cache_dialog.response.connect ((response) => {
                    if (response == "remove") {
                        Utils.remove_recursive (Utils.cache_dir ());
                        var cache = Utils.StorageCache.instance ();
                        cache.invalidate_all_cache ();
                        cache.invalidate (Utils.StorageCategory.APP_DATA);
                    }
                    close ();
                });
                cache_dialog.present (this);
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
            if (log_path != "") {
                dialog.add_response ("logs", _("Open Logs"));
            }
            dialog.add_response ("close", _("Keep Prefix"));
            dialog.add_response ("delete", _("Delete Prefix"));
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "close";
            dialog.close_response = "close";
            dialog.response.connect ((response) => {
                if (response == "logs") {
                    on_open_logs ();
                    return;
                }
                if (response == "delete") {
                    prefix_delete_requested ();
                }
                close ();
            });
            dialog.present (this);
        }

        private void on_show_log_toggled () {
            var show = show_log_btn.active;
            show_log_btn.label = show ? _("Hide Log") : _("Show Log");
            log_revealer.reveal_child = show;
            if (show) {
                start_log_tail ();
            } else {
                stop_log_tail (true);
            }
        }

        private void start_log_tail () {
            stop_log_tail (true);
            if (log_path == "") {
                return;
            }
            var size = Utils.file_size_or_zero (log_path);
            log_offset = size > LOG_TAIL_BYTES ? size - LOG_TAIL_BYTES : 0;
            string chunk;
            int64 end_offset;
            if (read_log_range (log_offset, -1, log_offset > 0, out chunk, out end_offset)) {
                replace_log_view (chunk);
                log_offset = end_offset;
            }
            trim_log_buffer ();
            scroll_log_to_bottom ();
            if (log_poll_source_id == 0) {
                log_poll_source_id = Timeout.add (LOG_POLL_MS, () => {
                    poll_log_tail ();
                    return true;
                });
            }
        }

        private void stop_log_tail (bool clear) {
            if (log_poll_source_id != 0) {
                Source.remove (log_poll_source_id);
                log_poll_source_id = 0;
            }
            if (clear) {
                log_view.buffer.set_text ("", 0);
                log_offset = 0;
            }
        }

        private void poll_log_tail () {
            if (log_path == "") {
                return;
            }
            var size = Utils.file_size_or_zero (log_path);
            if (size < log_offset) {
                log_offset = 0;
                log_view.buffer.set_text ("", 0);
            }
            string chunk;
            int64 end_offset;
            if (!read_log_range (log_offset, -1, false, out chunk, out end_offset)) {
                return;
            }
            append_log_view (chunk);
            log_offset = end_offset;
            trim_log_buffer ();
            scroll_log_to_bottom ();
        }

        private void replace_log_view (string text) {
            log_view.buffer.set_text (text, text.length);
        }

        private void append_log_view (string text) {
            var buf = log_view.buffer;
            Gtk.TextIter end_iter;
            buf.get_end_iter (out end_iter);
            buf.insert (ref end_iter, text, text.length);
        }

        private void trim_log_buffer () {
            var buf = log_view.buffer;
            var extra = buf.get_line_count () - LOG_MAX_LINES;
            if (extra <= 0) {
                return;
            }
            Gtk.TextIter start;
            Gtk.TextIter cut;
            buf.get_start_iter (out start);
            buf.get_iter_at_line (out cut, extra);
            buf.delete (ref start, ref cut);
        }

        private void scroll_log_to_bottom () {
            Gtk.TextIter end_iter;
            log_view.buffer.get_end_iter (out end_iter);
            log_view.scroll_to_iter (end_iter, 0, false, 0, 1.0);

            var adj = log_scroll.vadjustment;
            adj.value = double.max (adj.lower, adj.upper - adj.page_size);

            Idle.add (() => {
                Gtk.TextIter end;
                log_view.buffer.get_end_iter (out end);
                log_view.scroll_to_iter (end, 0, false, 0, 1.0);
                var later = log_scroll.vadjustment;
                later.value = double.max (later.lower, later.upper - later.page_size);
                return false;
            });
        }

        private bool read_log_range (
            int64 start,
            int64 max_bytes,
            bool skip_partial,
            out string text,
            out int64 end_offset
        ) {
            text = "";
            end_offset = start;
            if (log_path == "" || !FileUtils.test (log_path, FileTest.IS_REGULAR)) {
                return false;
            }
            var size = Utils.file_size_or_zero (log_path);
            if (size <= start) {
                return false;
            }
            var from = start;
            var to_read = size - from;
            if (max_bytes > 0 && to_read > max_bytes) {
                from = size - max_bytes;
                to_read = max_bytes;
            }
            var fs = FileStream.open (log_path, "rb");
            if (fs == null) {
                return false;
            }
            if (from > 0 && fs.seek ((long) from, FileSeek.SET) != 0) {
                return false;
            }
            var count = (int) to_read;
            var buf = new uint8[count + 1];
            var n = (int) fs.read (buf);
            if (n <= 0) {
                return false;
            }
            if (n > count) {
                n = count;
            }
            buf[n] = 0;
            text = ((string) buf).make_valid ();
            end_offset = from + (int64) n;
            if (skip_partial && from > 0) {
                var nl = text.index_of_char ('\n');
                if (nl >= 0) {
                    text = text.substring (nl + 1);
                }
            }
            return text.length > 0;
        }

        private void on_open_logs () {
            var log_dir = log_path != "" ? Path.get_dirname (log_path) : Utils.prefix_log_dir (prefix_path);
            Utils.ensure_dir (log_dir);
            SettingsShared.open_directory (null, log_dir, (message) => {
                SettingsShared.present_alert (this, _("Could not open log directory"), message);
            });
        }

        private void on_copy_log () {
            string text = "";
            int64 ignored;
            if (log_path == "" || !read_log_range (0, LOG_COPY_MAX_BYTES, true, out text, out ignored)) {
                return;
            }

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
    }
}
