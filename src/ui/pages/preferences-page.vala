namespace Lumoria.Ui {

    public class PreferencesPage : Gtk.Box {
        private const int PORTAL_PROBE_TIMEOUT_MS = 1500;

        private delegate bool SupportProbe (int timeout_ms, out string error);
        private delegate bool UpdateReady ();
        private delegate void UpdateCheck (owned Application.ManifestCheckReport report);

        private class UpdateCheckRow : Adw.ActionRow {
            private Gtk.Switch toggle = new Gtk.Switch ();
            private Gtk.Button check_btn;
            private UpdateReady ready;
            private UpdateCheck check;

            public UpdateCheckRow (
                Application.Context ctx,
                string title,
                string subtitle,
                string property,
                owned UpdateReady ready,
                owned UpdateCheck check,
                Object? extra_source
            ) {
                this.title = title;
                this.subtitle = subtitle;
                this.ready = (owned) ready;
                this.check = (owned) check;
                toggle.valign = Gtk.Align.CENTER;
                bind_preference (property, toggle);
                toggle.notify["active"].connect (refresh);
                add_suffix (toggle);
                activatable_widget = toggle;

                ctx.exclusive_changed.connect (refresh);
                if (extra_source != null) extra_source.notify.connect (refresh);
                check_btn = new Gtk.Button.from_icon_name (Widgets.IconRegistry.REFRESH);
                check_btn.valign = Gtk.Align.CENTER;
                check_btn.add_css_class ("flat");
                Widgets.PageChrome.set_icon_label (check_btn, _("Check for updates"));
                check_btn.clicked.connect (run_check);
                add_suffix (check_btn);
                refresh ();
            }

            private void refresh () {
                check_btn.sensitive = toggle.active && ready ();
            }

            private void run_check () {
                check_btn.sensitive = false;
                check ((message, error) => {
                    subtitle = message;
                    if (error) add_css_class ("error");
                    else remove_css_class ("error");
                    refresh ();
                });
            }
        }

        private static void bind_preference (string property, Object toggle) {
            Utils.Preferences.instance ().bind_property (
                property, toggle, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE
            );
        }

        private static Adw.SwitchRow switch_row (string title, string subtitle, string property) {
            var row = new Adw.SwitchRow ();
            row.title = title;
            if (subtitle != "") row.subtitle = subtitle;
            bind_preference (property, row);
            return row;
        }

        private Application.Context ctx;
        private Utils.Preferences prefs;
        private Widgets.OptionListRow startup_row;
        private Adw.ActionRow ql_row;
        private Widgets.ShortcutToggles ql_toggles;
        private Adw.ActionRow steam_row;

        public PreferencesPage (Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            prefs = Utils.Preferences.instance ();

            var lumoria = new Widgets.PageSection (_("Lumoria"));
            startup_row = new Widgets.OptionListRow ();
            startup_row.title = _("Open To");
            startup_row.model = Widgets.StartupViewControl.model ();
            startup_row.selected = Widgets.StartupViewControl.index_of (prefs.startup_view);
            startup_row.notify["selected"].connect (on_startup_selected);
            prefs.notify["startup-view"].connect (sync_startup_row);
            lumoria.add (startup_row);
            lumoria.add (switch_row (_("Close Lumoria After Launch"), "", "close-after-launch"));
            lumoria.add (switch_row (_("Enable Logging"), "", "keep-runtime-logs"));
            lumoria.add (switch_row (
                _("Gamepad Navigation"), _("Use a connected gamepad to navigate Lumoria."), "gamepad-navigation"
            ));
            lumoria.add (switch_row (
                _("Session Manager"), _("Enables multiboxing in sandboxed environments."), "session-manager"
            ));
            var about = Widgets.PageChrome.navigation_row (_("About Lumoria"));
            about.activated.connect (show_about);
            lumoria.add (about);
            append (lumoria);

            var display = new Widgets.PageSection (_("Display"));
            add_probed_switch (
                display,
                _("Keep Display Awake While Playing"),
                "screen-inhibitor",
                Utils.ScreenInhibitor.probe,
                _("Idle inhibit is not available through the desktop portal")
            );
            add_probed_switch (
                display,
                _("Enable Feral GameMode"),
                "feral-game-mode",
                Utils.FeralGameModePortal.probe,
                _("Feral GameMode is not available through the desktop portal")
            );
            append (display);

            var updates = new Widgets.PageSection (_("Updates"));
            add_update_check (
                updates,
                _("Lumoria Manifests"),
                _("Installer, launcher, redist, runner, and component definitions."),
                "updates-lumoria",
                () => !ctx.manifest_updates.busy && !ctx.busy,
                (report) => ctx.manifest_updates.check_async (true, (owned) report)
            );
            add_update_check (
                updates,
                _("Required Resources"),
                _("Downloaded files used by Lumoria, such as icon packs."),
                "updates-resources",
                () => !Application.ResourceStore.instance ().busy && !ctx.busy,
                (report) => {
                    Application.ResourceStore.instance ().ensure_async (true, (error) => {
                        if (error != null) report (user_error (error), true);
                        else report (_("Required resources are up to date"), false);
                    });
                },
                Application.ResourceStore.instance ()
            );
            add_update_check (
                updates,
                _("Runner Updates"),
                _("Newest runner versions from GitHub."),
                "updates-runners",
                () => !ctx.manifest_updates.catalog_refresh_busy && !ctx.busy,
                (report) => ctx.manifest_updates.refresh_tool_release_indexes (true, false, true, (owned) report)
            );
            add_update_check (
                updates,
                _("Component Updates"),
                _("Newest component versions from GitHub."),
                "updates-components",
                () => !ctx.manifest_updates.catalog_refresh_busy && !ctx.busy,
                (report) => ctx.manifest_updates.refresh_tool_release_indexes (false, true, true, (owned) report)
            );
            append (updates);

            var shortcuts = new Widgets.PageSection (_("Shortcuts"));
            ql_row = new Adw.ActionRow ();
            ql_row.title = _("Quick Launch");
            ql_toggles = new Widgets.ShortcutToggles ();
            ql_toggles.menu.clicked.connect (toggle_quick_launch_menu);
            ql_toggles.steam.clicked.connect (toggle_quick_launch_steam);
            ql_row.add_suffix (ql_toggles);
            shortcuts.add (ql_row);
            ctx.state.changed.connect (sync_quick_launch);
            ctx.prefixes.changed.connect (sync_quick_launch);
            sync_quick_launch ();

            steam_row = new Adw.ActionRow ();
            steam_row.title = _("Steam Installation");
            var steam_path = prefs.resolved_steam_userdata_dir ();
            steam_row.subtitle = steam_path != "" ? steam_path : _("Not set");
            if (!Utils.EnvironmentInfo.is_gamescope ()) {
                var browse = Widgets.PageChrome.browse_button ();
                browse.clicked.connect (pick_steam_folder);
                steam_row.add_suffix (browse);
            }
            shortcuts.add (steam_row);
            append (shortcuts);

            var reset = new Widgets.PageSection (_("Reset"));
            var reset_row = Widgets.PageChrome.action_row (
                _("Reset Preferences To Defaults"),
                _("Reset"),
                _("Restore runner defaults, component defaults, runtime env settings, and global Wine/patch settings."),
                "destructive"
            );
            reset_row.button.clicked.connect (confirm_reset);
            reset.add (reset_row);
            append (reset);
        }

        private void show_about () {
            activate_action ("app.about", null);
        }

        private void on_startup_selected () {
            prefs.startup_view = Widgets.StartupViewControl.from_index (startup_row.selected);
        }

        private void sync_startup_row () {
            var idx = Widgets.StartupViewControl.index_of (prefs.startup_view);
            if (startup_row.selected != idx) startup_row.selected = idx;
        }

        private void toggle_quick_launch_menu () {
            ctx.shortcuts.toggle_quick_launch_menu ();
        }

        private void toggle_quick_launch_steam () {
            ctx.shortcuts.toggle_quick_launch_steam ();
        }

        private void pick_steam_folder () {
            ctx.shortcuts.pick_steam_folder ((config) => {
                steam_row.subtitle = config.steam_dir;
            });
        }

        private void confirm_reset () {
            Widgets.Dialogs.DialogHelpers.present_destructive_confirmation (
                this,
                _("Reset to Defaults?"),
                _("This will reset global runner defaults, component defaults, runtime environment settings, and global Wine/patch preferences."),
                "reset",
                _("Reset"),
                () => {
                    prefs.reset_to_defaults ();
                    ctx.show_toast (_("Preferences reset to defaults."));
                }
            );
        }

        /* The switch stays disabled until the portal probe confirms the feature exists on this desktop. */
        private void add_probed_switch (
            Widgets.PageSection group,
            string title,
            string property,
            owned SupportProbe probe,
            string unsupported_subtitle
        ) {
            var row = new Adw.SwitchRow ();
            row.title = title;
            row.sensitive = false;
            group.add (row);

            bool supported = false;
            Utils.run_background (property + "-probe", () => {
                string unused;
                supported = probe (PORTAL_PROBE_TIMEOUT_MS, out unused);
            }, (error) => {
                if (error != null) return;
                if (supported) {
                    bind_preference (property, row);
                    row.sensitive = true;
                } else {
                    row.subtitle = unsupported_subtitle;
                }
            });
        }

        private void add_update_check (
            Widgets.PageSection group,
            string title,
            string subtitle,
            string property,
            owned UpdateReady ready,
            owned UpdateCheck check,
            Object? extra_source = null
        ) {
            group.add (new UpdateCheckRow (ctx, title, subtitle, property, (owned) ready, (owned) check, extra_source));
        }

        private void sync_quick_launch () {
            ql_row.subtitle = quick_launch_subtitle ();
            var have_target = !ctx.state.quick_launch.is_empty ();
            var have_menu = ctx.state.quick_launch_desktop_id != "";
            var have_steam = ctx.state.quick_launch_steam_app_id != "";
            ql_toggles.sync (have_menu, have_steam);
            ql_toggles.menu.sensitive = have_target || have_menu;
            ql_toggles.steam.sensitive = have_target || have_steam;
        }

        private string quick_launch_subtitle () {
            var target = ctx.state.quick_launch;
            if (target.is_empty ()) return _("Not set");
            var entry = ctx.registry.by_id (target.prefix_id);
            if (entry == null) return _("Not set");
            return entry.display_name ();
        }
    }
}
