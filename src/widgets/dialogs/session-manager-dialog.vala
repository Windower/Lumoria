namespace Lumoria.Widgets.Dialogs {

    public class SessionManagerDialog : Adw.Dialog {
        private Models.PrefixRegistry registry;
        private Services.SessionManagerService service;
        private Adw.ToastOverlay toast_overlay;
        private Gtk.Stack content_stack;
        private Gtk.ListBox launch_list;
        private Adw.StatusPage not_running_page;
        private Adw.StatusPage empty_page;
        private Gtk.Button refresh_btn;
        private Gtk.Button? session_logs_btn = null;
        private Gtk.Button stop_all_btn;
        private uint refresh_source_id = 0;
        private bool refresh_pending = false;

        public SessionManagerDialog (Models.PrefixRegistry registry) {
            Object (
                title: _("Session Manager"),
                content_width: 520,
                content_height: 420
            );
            this.registry = registry;
            this.service = new Services.SessionManagerService ();
            build_ui ();
        }

        private void build_ui () {
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = true;

            refresh_btn = new Gtk.Button.from_icon_name (IconRegistry.REFRESH);
            refresh_btn.tooltip_text = _("Refresh");
            refresh_btn.clicked.connect (() => refresh_launches ());
            header.pack_start (refresh_btn);

            if (!Utils.EnvironmentInfo.is_gamescope ()) {
                session_logs_btn = new Gtk.Button.from_icon_name (IconRegistry.OPEN_FOLDER);
                session_logs_btn.tooltip_text = _("Open Session Manager Logs");
                session_logs_btn.clicked.connect (open_session_manager_logs);
                header.pack_start (session_logs_btn);
                update_session_logs_button ();
            }

            toolbar.add_top_bar (header);

            not_running_page = new Adw.StatusPage () {
                icon_name = IconRegistry.WARNING,
                title = _("Session Manager Not Running")
            };

            empty_page = new Adw.StatusPage () {
                icon_name = IconRegistry.INFO,
                title = _("No Active Launches"),
                description = _("No active launches are being managed by Lumoria.")
            };

            launch_list = new Gtk.ListBox ();
            launch_list.selection_mode = Gtk.SelectionMode.NONE;
            launch_list.add_css_class ("boxed-list");

            var list_scroll = new Gtk.ScrolledWindow ();
            list_scroll.vexpand = true;
            list_scroll.child = launch_list;

            content_stack = new Gtk.Stack ();
            content_stack.vexpand = true;
            content_stack.add_named (not_running_page, "not_running");
            content_stack.add_named (empty_page, "empty");
            content_stack.add_named (list_scroll, "list");

            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.vexpand = true;
            toast_overlay.child = content_stack;
            toolbar.content = toast_overlay;

            stop_all_btn = new Gtk.Button.with_label (_("Stop All"));
            stop_all_btn.add_css_class ("destructive-action");
            stop_all_btn.margin_start = 12;
            stop_all_btn.margin_end = 12;
            stop_all_btn.margin_top = 8;
            stop_all_btn.margin_bottom = 8;
            stop_all_btn.clicked.connect (on_stop_all);
            toolbar.add_bottom_bar (stop_all_btn);

            this.child = toolbar;

            map.connect (on_mapped);
            unmap.connect (on_unmapped);
        }

        private void on_mapped () {
            refresh_launches ();
            if (refresh_source_id != 0) return;
            refresh_source_id = Timeout.add_seconds (3, () => {
                refresh_launches ();
                return Source.CONTINUE;
            });
        }

        private void on_unmapped () {
            if (refresh_source_id == 0) return;
            Source.remove (refresh_source_id);
            refresh_source_id = 0;
        }

        private void refresh_launches () {
            if (refresh_pending) return;
            refresh_pending = true;
            update_session_logs_button ();
            refresh_btn.sensitive = false;
            stop_all_btn.sensitive = false;

            service.ping_async ((running) => {
                if (!running) {
                    show_state ("not_running");
                    refresh_pending = false;
                    refresh_btn.sensitive = true;
                    stop_all_btn.sensitive = false;
                    return;
                }

                service.list_launches_async (
                    (launches) => {
                        rebuild_launch_list (launches);
                        refresh_pending = false;
                        refresh_btn.sensitive = true;
                        stop_all_btn.sensitive = launches.size > 0;
                    },
                    (error) => {
                        show_toast (_("Failed to list launches: %s").printf (error));
                        show_state ("not_running");
                        refresh_pending = false;
                        refresh_btn.sensitive = true;
                        stop_all_btn.sensitive = false;
                    }
                );
            });
        }

        private void rebuild_launch_list (Gee.ArrayList<Cli.SessionLaunchInfo> launches) {
            Gtk.ListBoxRow? row;
            while ((row = launch_list.get_row_at_index (0)) != null) {
                launch_list.remove (row);
            }

            if (launches.size == 0) {
                show_state ("empty");
                return;
            }

            launches.sort ((a, b) => {
                var prefix_cmp = strcmp (a.prefix_id, b.prefix_id);
                if (prefix_cmp != 0) return prefix_cmp;
                return strcmp (a.label, b.label);
            });

            foreach (var info in launches) {
                launch_list.append (build_launch_row (info));
            }

            show_state ("list");
        }

        private Gtk.ListBoxRow build_launch_row (Cli.SessionLaunchInfo info) {
            var row = new Adw.ActionRow ();
            row.title = info.label != "" ? info.label : _("Unknown");
            row.subtitle = "%s · PID %d".printf (prefix_display_name (info.prefix_id), info.pid);

            if (!Utils.EnvironmentInfo.is_gamescope () && info.log_path != "") {
                var logs_btn = new Gtk.Button.from_icon_name (IconRegistry.OPEN_FOLDER);
                logs_btn.tooltip_text = _("Open Logs");
                logs_btn.add_css_class ("flat");
                logs_btn.valign = Gtk.Align.CENTER;
                logs_btn.clicked.connect (() => open_launch_logs (info));
                row.add_suffix (logs_btn);
            }

            var stop_btn = new Gtk.Button ();
            stop_btn.icon_name = "process-stop-symbolic";
            stop_btn.tooltip_text = _("Stop");
            stop_btn.add_css_class ("flat");
            stop_btn.valign = Gtk.Align.CENTER;
            stop_btn.clicked.connect (() => confirm_stop_launch (info));
            row.add_suffix (stop_btn);

            return row;
        }

        private string prefix_display_name (string prefix_id) {
            var entry = registry.by_id (prefix_id);
            if (entry != null) return entry.display_name ();
            return prefix_id;
        }

        private void open_launch_logs (Cli.SessionLaunchInfo info) {
            var log_dir = Path.get_dirname (info.log_path);
            if (log_dir == null || log_dir == ".") {
                show_toast (_("Log directory is unavailable."));
                return;
            }

            SettingsShared.open_directory (null, log_dir, (message) => {
                show_toast (_("Could not open log directory: %s").printf (message));
            });
        }

        private void open_session_manager_logs () {
            var log_dir = Utils.session_manager_log_dir ();
            if (!FileUtils.test (log_dir, FileTest.IS_DIR)) {
                update_session_logs_button ();
                show_toast (_("Session manager log directory is unavailable."));
                return;
            }
            SettingsShared.open_directory (null, log_dir, (message) => {
                show_toast (_("Could not open session manager log directory: %s").printf (message));
            });
        }

        private void update_session_logs_button () {
            if (session_logs_btn == null) return;
            session_logs_btn.visible = FileUtils.test (Utils.session_manager_log_dir (), FileTest.IS_DIR);
        }

        private void confirm_stop_launch (Cli.SessionLaunchInfo info) {
            var target = info.label != "" ? info.label : _("this launch");
            SettingsShared.present_destructive_confirmation (
                this,
                _("Stop Launch?"),
                _("Stop %s?").printf (target),
                "stop",
                _("Stop"),
                () => {
                    stop_all_btn.sensitive = false;
                    service.stop_pid_async (
                        info.pid,
                        () => {
                            show_toast (_("Launch stopped."));
                            refresh_launches ();
                        },
                        (error) => {
                            show_toast (_("Stop failed: %s").printf (error));
                            refresh_launches ();
                        }
                    );
                }
            );
        }

        private void on_stop_all () {
            SettingsShared.present_destructive_confirmation (
                this,
                _("Stop All Launches?"),
                _("Stop every session-managed launch?"),
                "stop_all",
                _("Stop All"),
                () => {
                    refresh_btn.sensitive = false;
                    stop_all_btn.sensitive = false;
                    service.stop_all_async (
                        () => {
                            show_toast (_("All launches stopped."));
                            refresh_launches ();
                        },
                        (error) => {
                            show_toast (_("Stop all failed: %s").printf (error));
                            refresh_launches ();
                        }
                    );
                }
            );
        }

        private void show_state (string name) {
            content_stack.visible_child_name = name;
        }

        private void show_toast (string message) {
            toast_overlay.add_toast (new Adw.Toast (message));
        }
    }
}
