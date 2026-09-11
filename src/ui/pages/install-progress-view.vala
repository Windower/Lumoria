namespace Lumoria.Ui {

    public class InstallProgressView : Gtk.Box {
        public signal void close_requested ();

        private Application.InstallSession session;
        private Widgets.Busy busy;
        private Gtk.TextView log_view;
        private Gtk.ScrolledWindow log_scroll;
        private Gtk.Revealer log_revealer;
        private Gtk.Revealer notice_revealer;
        private Gtk.ToggleButton show_log_btn;
        private Gtk.Button cancel_btn;
        private Gtk.Button close_btn;
        private Gtk.Button open_logs_btn;
        private Gtk.Button copy_log_btn;
        private Gtk.Label result_label;
        private uint log_poll_id = 0;
        private int64 log_offset = 0;

        public InstallProgressView (Application.InstallSession session) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: Metrics.EDITOR_INSET);
            this.session = session;
            margin_start = Metrics.PAGE_MARGIN;
            margin_end = Metrics.PAGE_MARGIN;
            margin_top = Metrics.EDITOR_INSET;
            margin_bottom = Metrics.PAGE_MARGIN;
            build_ui ();
            bind_session ();
            refresh ();
        }

        private void build_ui () {
            busy = new Widgets.Busy (session.label);
            busy.margin_start = Metrics.PAGE_MARGIN;
            busy.margin_end = Metrics.PAGE_MARGIN;
            append (busy);

            result_label = new Gtk.Label ("");
            result_label.wrap = true;
            result_label.xalign = 0f;
            result_label.selectable = true;
            result_label.visible = false;
            result_label.add_css_class ("dim-label");
            result_label.margin_start = Metrics.PAGE_MARGIN_WIDE;
            result_label.margin_end = Metrics.PAGE_MARGIN_WIDE;
            append (result_label);

            notice_revealer = new Gtk.Revealer ();
            notice_revealer.reveal_child = true;
            notice_revealer.child = Widgets.Messages.info (
                _("This can take a while. If anything fails, Lumoria will show it here."), 0, 0, 0, 0
            );
            append (notice_revealer);

            log_view = new Gtk.TextView ();
            log_view.editable = false;
            log_view.monospace = true;
            log_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            log_scroll = new Gtk.ScrolledWindow ();
            log_scroll.min_content_height = 220;
            log_scroll.child = log_view;
            var log_frame = new Gtk.Frame (null);
            log_frame.add_css_class ("install-log");
            log_frame.child = log_scroll;
            log_revealer = new Gtk.Revealer ();
            log_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            log_revealer.reveal_child = false;
            log_revealer.child = log_frame;
            append (log_revealer);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            show_log_btn = new Gtk.ToggleButton.with_label (_("Show Log"));
            show_log_btn.toggled.connect (on_show_log_toggled);
            copy_log_btn = new Gtk.Button.from_icon_name (Widgets.IconRegistry.COPY);
            Widgets.PageChrome.set_icon_label (copy_log_btn, _("Copy Log"));
            copy_log_btn.sensitive = false;
            copy_log_btn.clicked.connect (copy_log);
            open_logs_btn = new Gtk.Button.from_icon_name (Widgets.IconRegistry.OPEN_FOLDER);
            Widgets.PageChrome.set_icon_label (open_logs_btn, _("Open Logs"));
            open_logs_btn.sensitive = false;
            open_logs_btn.clicked.connect (open_logs);
            var log_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            log_actions.add_css_class ("linked");
            log_actions.append (show_log_btn);
            log_actions.append (copy_log_btn);
            log_actions.append (open_logs_btn);
            actions.append (log_actions);
            var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            actions.append (spacer);

            cancel_btn = new Gtk.Button.with_label (_("Cancel"));
            cancel_btn.add_css_class ("destructive-action");
            cancel_btn.clicked.connect (session.cancel);
            actions.append (cancel_btn);

            close_btn = new Gtk.Button.with_label (_("Close"));
            close_btn.add_css_class ("suggested-action");
            close_btn.visible = false;
            close_btn.clicked.connect (() => close_requested ());
            actions.append (close_btn);
            append (actions);
        }

        private void bind_session () {
            session.changed.connect (refresh);
            session.finished.connect (refresh);
            destroy.connect (stop_log_tail);
        }

        private void on_show_log_toggled () {
            show_log_btn.label = show_log_btn.active ? _("Hide Log") : _("Show Log");
            log_revealer.reveal_child = show_log_btn.active;
            if (show_log_btn.active) start_log_tail ();
            else stop_log_tail ();
        }

        private void refresh () {
            var done = !session.is_active;
            var cancelling = !done && session.cancellable.is_cancelled ();
            var have_log = session.log_path != "";
            result_label.label = session.message;
            result_label.visible = session.message.strip () != "";
            open_logs_btn.sensitive = have_log;
            copy_log_btn.sensitive = have_log;
            cancel_btn.visible = !done;
            cancel_btn.sensitive = !cancelling;
            close_btn.visible = done;
            notice_revealer.reveal_child = !done && !cancelling;
            busy.show_progress (session.fraction, "%.0f%%".printf (session.fraction * 100));

            if (done) {
                if (session.status == Application.InstallStatus.SUCCEEDED) {
                    busy.set_status (_("Complete"));
                } else if (session.status == Application.InstallStatus.CANCELLED) {
                    busy.set_status (_("Cancelled"));
                } else {
                    busy.set_status (_("Failed"));
                    show_log_btn.active = have_log;
                }
                busy.set_detail (null);
                return;
            }

            busy.set_status (session.label);
            busy.set_detail (cancelling
                ? _("Cancelling...")
                : (session.step != "" ? session.step : null));
        }

        private void start_log_tail () {
            stop_log_tail ();
            if (session.log_path == "") return;
            poll_log ();
            log_poll_id = Timeout.add (200, () => {
                poll_log ();
                return true;
            });
        }

        private void stop_log_tail () {
            if (log_poll_id != 0) {
                Source.remove (log_poll_id);
                log_poll_id = 0;
            }
        }

        private void poll_log () {
            if (session.log_path == "" || !FileUtils.test (session.log_path, FileTest.IS_REGULAR)) return;
            var size = Utils.file_size_or_zero (session.log_path);
            if (size < log_offset) {
                log_offset = 0;
                log_view.buffer.set_text ("", 0);
            }
            if (size <= log_offset) return;
            var fs = FileStream.open (session.log_path, "rb");
            if (fs == null) return;
            if (log_offset > 0 && fs.seek ((long) log_offset, FileSeek.SET) != 0) return;
            var count = (int) (size - log_offset);
            var buf = new uint8[count + 1];
            var n = (int) fs.read (buf);
            if (n <= 0) return;
            buf[n] = 0;
            var text = ((string) buf).make_valid ();
            Gtk.TextIter end;
            log_view.buffer.get_end_iter (out end);
            log_view.buffer.insert (ref end, text, text.length);
            log_offset += n;
            log_view.scroll_to_iter (end, 0, false, 0, 1.0);
        }

        private void open_logs () {
            var dir = session.log_path != "" ? Path.get_dirname (session.log_path) : "";
            if (dir == "") return;
            Widgets.Dialogs.FileDialogs.open_directory (get_root () as Gtk.Window, dir, null);
        }

        private void copy_log () {
            if (session.log_path == "") return;
            try {
                string contents;
                FileUtils.get_contents (session.log_path, out contents);
                get_clipboard ().set_text (contents);
            } catch (Error e) {
                var win = get_root () as Window;
                if (win != null) win.show_toast (user_error (e));
            }
        }
    }
}
