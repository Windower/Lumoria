namespace Lumoria.Ui {

    public class Window : Adw.ApplicationWindow, Widgets.DialogHost {
        private Application.Context ctx;
        private Adw.OverlaySplitView split;
        private Content host;
        private NavigationSidebar sidebar;
        private Widgets.ToastStack toasts;
        private SimpleAction play_action;
        private SimpleAction show_sidebar_action;
        private SimpleAction show_home_action;
        private Widgets.Services.GamepadService gamepad;
        private Gee.ArrayList<Adw.Dialog> active_dialogs;
        private Widgets.Services.GamepadListNavigator gamepad_focus;
        private bool allow_window_close = false;
        private Application.ManifestUpdatePresenter? manifest_updates;

        public Window (Widgets.Application app) {
            Object (application: app, title: Config.APP_NAME);
        }

        construct {
            var app = this.application as Widgets.Application;
            if (app != null && app.flathub_screenshots) {
                default_width = Metrics.WINDOW_WIDTH_SCREENSHOTS;
                default_height = Metrics.WINDOW_HEIGHT_SCREENSHOTS;
            } else {
                default_width = Metrics.WINDOW_WIDTH;
                default_height = Metrics.WINDOW_HEIGHT;
            }

            try {
                ctx = new Application.Context ();
            } catch (Error e) {
                present_startup_failure (user_error (e));
                return;
            }
            ctx.ui = new WindowUiHost (ctx, this);
            ctx.installs.session_started.connect (present_install_session);
            manifest_updates = new Application.ManifestUpdatePresenter (ctx, ctx.ui);
            active_dialogs = new Gee.ArrayList<Adw.Dialog> ();

            gamepad = Widgets.Services.GamepadService.instance ();
            gamepad.action_pressed.connect (on_gamepad_action);
            gamepad_focus = new Widgets.Services.GamepadListNavigator.live (
                this, (widget) => !(widget is Gtk.Button && ((Gtk.Button) widget).action_name == "win.quit")
            );
            Utils.Preferences.instance ().gamepad_navigation_changed.connect ((enabled) => {
                if (enabled) gamepad_focus.focus_first ();
                else gamepad_focus.clear_focus ();
            });
            close_request.connect (() => on_close_request ());

            play_action = new SimpleAction ("play", null);
            play_action.activate.connect (play_quick_target);
            add_action (play_action);

            show_home_action = new SimpleAction.stateful (
                "show-home", null, new Variant.boolean (ctx.state.page == Application.PageKind.HOME)
            );
            show_home_action.change_state.connect (on_show_home_change);
            add_action (show_home_action);
            ctx.state.changed.connect (sync_show_home);
            ctx.prefixes.list_changed.connect (sync_show_home);
            sync_show_home ();

            var session_action = new SimpleAction ("session-manager", null);
            session_action.activate.connect (() => show_session_manager ());
            add_action (session_action);

            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (request_quit);
            add_action (quit_action);

            Models.FfxiIconCatalog.instance ().reload ();
            build_ui ();
            surface_load_errors ();
            update_play_sensitivity ();
            ctx.state.changed.connect (update_play_sensitivity);
            ctx.launches.changed.connect (update_play_sensitivity);
            ctx.exclusive_changed.connect (update_play_sensitivity);
            download_required_resources ();
            ctx.manifest_updates.check_startup ();
            Idle.add (() => {
                if (Utils.Preferences.instance ().gamepad_navigation) gamepad_focus.focus_first ();
                return false;
            });
        }

        private void surface_load_errors () {
            if (ctx.registry.load_error != "") show_toast (ctx.registry.load_error);
            if (ctx.state.load_error != "") show_toast (ctx.state.load_error);
            if (Utils.Preferences.instance ().load_error != "") {
                show_toast (Utils.Preferences.instance ().load_error);
            }
        }

        private void download_required_resources () {
            var store = Application.ResourceStore.instance ();
            if (store.pending_auto_required ().size == 0) return;
            var missing_only = !Utils.Preferences.instance ().updates_resources;
            store.ensure_async (true, (error) => {
                if (error != null) show_toast (user_error (error));
            }, null, missing_only);
        }

        private void present_startup_failure (string message) {
            critical ("%s", message);
            var status = new Adw.StatusPage ();
            status.title = _("Cannot start Lumoria");
            status.description = message;
            status.icon_name = Widgets.IconRegistry.ERROR;
            content = status;

            var dialog = new Adw.AlertDialog (_("Cannot start Lumoria"), message);
            dialog.add_response ("quit", _("Quit"));
            dialog.default_response = "quit";
            dialog.close_response = "quit";
            dialog.response.connect (() => {
                if (application != null) application.quit ();
            });
            dialog.present (this);
        }

        public void show_preferences () {
            if (ctx == null) return;
            ctx.state.show_page (Application.PageKind.PREFERENCES);
        }

        public void show_session_manager () {
            if (ctx == null) return;
            if (!Utils.Preferences.instance ().session_manager) return;
            show_dialog (new Widgets.Dialogs.SessionManagerDialog (ctx.registry));
        }

        public void show_dialog (Adw.Dialog dialog) {
            track_dialog (dialog);
            dialog.present (this);
        }

        public void show_toast (string message) {
            var host = get_visible_dialog () as Widgets.ToastHost;
            if (host != null) {
                host.push_toast (message);
                return;
            }
            if (toasts != null) toasts.push (message);
        }

        private void build_ui () {
            split = new Adw.OverlaySplitView ();
            split.min_sidebar_width = Metrics.SIDEBAR_MIN;
            split.max_sidebar_width = Metrics.SIDEBAR_MAX;
            split.sidebar_width_fraction = Metrics.SIDEBAR_FRACTION;
            split.show_sidebar = Utils.Preferences.instance ().show_sidebar;

            show_sidebar_action = new SimpleAction.stateful (
                "show-sidebar", null, new Variant.boolean (split.show_sidebar)
            );
            show_sidebar_action.change_state.connect (on_show_sidebar_change);
            add_action (show_sidebar_action);
            split.notify["show-sidebar"].connect (sync_show_sidebar_action);

            sidebar = new NavigationSidebar (ctx);
            sidebar.navigated.connect (dismiss_overlay);
            host = new Content (ctx);
            split.sidebar = sidebar;
            split.content = host;

            var compact = new Adw.Breakpoint (Adw.BreakpointCondition.parse (Metrics.compact_condition ()));
            compact.add_setter (split, "collapsed", true_value ());
            add_breakpoint ((owned) compact);
            split.notify["collapsed"].connect (on_split_collapsed);

            var narrow = new Adw.Breakpoint (Adw.BreakpointCondition.parse (Metrics.banner_stack_condition ()));
            narrow.add_setter (split, "collapsed", true_value ());
            narrow.apply.connect (() => add_css_class ("narrow-banner"));
            narrow.unapply.connect (() => remove_css_class ("narrow-banner"));
            add_breakpoint ((owned) narrow);

            var icons = new Adw.Breakpoint (Adw.BreakpointCondition.parse (Metrics.toolbar_icons_condition ()));
            icons.add_setter (split, "collapsed", true_value ());
            icons.apply.connect (() => {
                add_css_class ("narrow-banner");
                add_css_class ("compact-toolbar");
            });
            icons.unapply.connect (() => {
                remove_css_class ("narrow-banner");
                remove_css_class ("compact-toolbar");
            });
            add_breakpoint ((owned) icons);

            content = Widgets.ToastStack.attach (split, out toasts);
        }

        private static GLib.Value true_value () {
            var value = GLib.Value (typeof (bool));
            value.set_boolean (true);
            return value;
        }

        private void on_show_sidebar_change (Variant? value) {
            if (value == null) return;
            split.show_sidebar = value.get_boolean ();
            show_sidebar_action.set_state (new Variant.boolean (split.show_sidebar));
        }

        private void sync_show_sidebar_action () {
            var visible = split.show_sidebar;
            if (show_sidebar_action.state.get_boolean () != visible) {
                show_sidebar_action.set_state (new Variant.boolean (visible));
            }
            if (!split.collapsed) {
                Utils.Preferences.instance ().show_sidebar = visible;
            }
        }

        private void dismiss_overlay () {
            if (split.collapsed && split.show_sidebar) {
                split.show_sidebar = false;
            }
        }

        private void on_split_collapsed () {
            if (!split.collapsed) {
                split.show_sidebar = Utils.Preferences.instance ().show_sidebar;
            }
        }

        private void play_quick_target () {
            ctx.actions.run_quick_launch ();
        }

        private void update_play_sensitivity () {
            play_action.set_enabled (
                !ctx.busy && !ctx.launches.is_launching && !ctx.state.quick_launch.is_empty ()
            );
        }

        private void present_install_session (Application.InstallSession session) {
            var dialog = new Widgets.Dialogs.InstallProgressDialog (ctx, session);
            dialog.closed.connect (() => finish_install_navigation (session));
            ctx.show_dialog (dialog);
        }

        private void finish_install_navigation (Application.InstallSession session) {
            if (session.status == Application.InstallStatus.SUCCEEDED && session.prefix_id != "") {
                ctx.state.select_prefix (session.prefix_id);
                return;
            }
            if (ctx.registry.prefixes.size == 0) {
                ctx.state.show_page (Application.PageKind.EMPTY);
                return;
            }
            if (ctx.state.selected_prefix_id != "" && ctx.registry.by_id (ctx.state.selected_prefix_id) != null) {
                ctx.state.select_prefix (ctx.state.selected_prefix_id);
                return;
            }
            ctx.state.select_prefix (ctx.registry.prefixes[0].id);
        }

        private void on_show_home_change (Variant? value) {
            if (value == null) return;
            var show = value.get_boolean ();
            if (show) {
                ctx.state.show_page (ctx.registry.prefixes.size == 0
                    ? Application.PageKind.EMPTY
                    : Application.PageKind.HOME);
                return;
            }
            if (ctx.state.selected_prefix_id != "") {
                ctx.state.select_prefix (ctx.state.selected_prefix_id);
                return;
            }
            if (ctx.registry.prefixes.size > 0) {
                ctx.state.select_prefix (ctx.registry.prefixes[0].id);
                return;
            }
            ctx.state.show_page (Application.PageKind.EMPTY);
        }

        private void sync_show_home () {
            show_home_action.set_enabled (true);
            var active = ctx.state.page == Application.PageKind.HOME
                || (ctx.registry.prefixes.size == 0 && ctx.state.page == Application.PageKind.EMPTY);
            if (show_home_action.state.get_boolean () != active) {
                show_home_action.set_state (new Variant.boolean (active));
            }
        }

        private void track_dialog (Adw.Dialog dialog) {
            active_dialogs.add (dialog);
            dialog.closed.connect (untrack_dialog);
        }

        private void untrack_dialog (Adw.Dialog dialog) {
            active_dialogs.remove (dialog);
        }

        private void on_gamepad_action (Widgets.Services.GamepadAction action) {
            if (!is_active) return;
            if (!Utils.Preferences.instance ().gamepad_navigation) return;
            focus_visible = true;

            if (active_dialogs.size > 0) {
                var top = active_dialogs[active_dialogs.size - 1];
                if (top is Adw.AlertDialog) {
                    answer_alert ((Adw.AlertDialog) top, action);
                    return;
                }
                if (top is Widgets.Services.GamepadNavigable) {
                    if (((Widgets.Services.GamepadNavigable) top).handle_gamepad_action (action)) {
                        return;
                    }
                }
            }

            switch (action) {
                case Widgets.Services.GamepadAction.NAVIGATE_DOWN:
                case Widgets.Services.GamepadAction.NAVIGATE_RIGHT:
                    gamepad_focus.move (1);
                    break;
                case Widgets.Services.GamepadAction.NAVIGATE_UP:
                case Widgets.Services.GamepadAction.NAVIGATE_LEFT:
                    gamepad_focus.move (-1);
                    break;
                case Widgets.Services.GamepadAction.TAB_PREV:
                    host.cycle_tabs (-1);
                    break;
                case Widgets.Services.GamepadAction.TAB_NEXT:
                    host.cycle_tabs (1);
                    break;
                case Widgets.Services.GamepadAction.ACTIVATE:
                    if (!gamepad_focus.activate_current ()) {
                        var focused = get_focus ();
                        if (focused != null) focused.activate ();
                    }
                    break;
                case Widgets.Services.GamepadAction.BACK:
                    handle_back ();
                    break;
                case Widgets.Services.GamepadAction.GLOBAL_PLAY:
                    if (play_action.get_enabled ()) play_quick_target ();
                    break;
                case Widgets.Services.GamepadAction.OPEN_PREFERENCES:
                    show_preferences ();
                    break;
            }
        }

        private static void answer_alert (Adw.AlertDialog alert, Widgets.Services.GamepadAction action) {
            switch (action) {
                case Widgets.Services.GamepadAction.ACTIVATE:
                    if (alert.default_response != null) alert.response (alert.default_response);
                    break;
                case Widgets.Services.GamepadAction.BACK:
                    alert.response (alert.close_response);
                    break;
                default:
                    break;
            }
        }

        private void handle_back () {
            if (active_dialogs.size > 0) {
                active_dialogs[active_dialogs.size - 1].close ();
                return;
            }
            request_quit ();
        }

        public void persist_and_shutdown () {
            if (ctx == null) return;
            ctx.shutdown ();
        }

        /* Closing only flushes state and cancels in-process jobs; Wine runs under its own subreaper and keeps going. */
        private bool on_close_request () {
            if (ctx != null && !allow_window_close && Utils.EnvironmentInfo.is_gamescope ()) {
                request_quit_confirmation ();
                return true;
            }
            persist_and_shutdown ();
            return false;
        }

        public void force_close () {
            allow_window_close = true;
            close ();
        }

        private void request_quit () {
            if (ctx != null && Utils.EnvironmentInfo.is_gamescope ()) {
                request_quit_confirmation ();
                return;
            }
            force_close ();
        }

        private void request_quit_confirmation () {
            Widgets.Dialogs.DialogHelpers.present_destructive_confirmation (
                this,
                _("Quit Lumoria?"),
                _("Any running Wine processes will continue in the background."),
                "quit",
                _("Quit"),
                force_close
            );
        }
    }
}
