namespace Lumoria.Application {

    public class ShortcutService : Object {
        public delegate void SteamReady (Utils.SteamConfig.UserConfig config);

        private Context ctx;

        public ShortcutService (Context ctx) {
            this.ctx = ctx;
        }

        /* Both removals are attempted even if one fails, so a portal error cannot orphan the Steam entry. */
        public void remove_entry_shortcuts (Models.PrefixEntry entry, string entrypoint_id) throws Error {
            var failures = new Gee.ArrayList<string> ();
            try {
                ctx.dynamic_launcher.remove_menu_shortcut (entry, entrypoint_id);
            } catch (Error e) {
                failures.add (e.message);
            }
            try {
                bool access_lost;
                var config = ctx.steam.resolve_config (out access_lost);
                if (config != null) {
                    ctx.steam.remove_steam_shortcut (entry, entrypoint_id, config);
                } else {
                    entry.steam_shortcut_app_ids.unset (entrypoint_id);
                    ctx.prefixes.schedule_save ();
                }
            } catch (Error e) {
                failures.add (e.message);
            }
            if (failures.size > 0) {
                throw new LumoriaError.FAILED ("%s", string.joinv ("; ", Utils.strv (failures)));
            }
        }

        public void remove_prefix_shortcuts (Models.PrefixEntry entry) {
            var ids = new Gee.HashSet<string> ();
            foreach (var id in entry.dynamic_launcher_desktop_ids.keys) ids.add (id);
            foreach (var id in entry.steam_shortcut_app_ids.keys) ids.add (id);
            foreach (var id in ids) {
                try {
                    remove_entry_shortcuts (entry, id);
                } catch (Error e) {
                    warning (
                        "Failed to remove shortcuts for %s/%s: %s",
                        entry.id,
                        id,
                        e.message
                    );
                }
            }
        }

        public void remove_quick_launch_shortcuts () {
            if (ctx.state.quick_launch_desktop_id != "") {
                try {
                    remove_quick_launch_menu ();
                } catch (Error e) {
                    warning ("Failed to remove Quick Launch menu shortcut: %s", e.message);
                }
            }
            if (ctx.state.quick_launch_steam_app_id == "") return;
            try {
                bool access_lost;
                var config = ctx.steam.resolve_config (out access_lost);
                if (config != null) remove_quick_launch_steam (config);
            } catch (Error e) {
                warning ("Failed to remove Quick Launch Steam shortcut: %s", e.message);
            }
        }

        private void remove_quick_launch_menu () throws Error {
            ctx.dynamic_launcher.remove_quick_launch_shortcut (ctx.state.quick_launch_desktop_id);
            ctx.state.update_quick_launch_desktop_id ("");
        }

        private void remove_quick_launch_steam (Utils.SteamConfig.UserConfig config) throws Error {
            ctx.steam.remove_quick_launch_shortcut (config);
            ctx.state.update_quick_launch_steam_app_id ("");
        }

        public void toggle_menu (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target,
            owned Utils.Action? after = null
        ) {
            if (entry.has_menu_shortcut (target.id)) {
                run_op (
                    () => ctx.dynamic_launcher.remove_menu_shortcut (entry, target.id),
                    menu_toast (false),
                    (owned) after
                );
                return;
            }
            if (ctx.ui == null) {
                ctx.show_toast (_("A window is required to add a menu shortcut."));
                return;
            }
            ctx.dynamic_launcher.install_menu_shortcut.begin (entry, target, (obj, res) => {
                run_op (
                    () => ctx.dynamic_launcher.install_menu_shortcut.end (res),
                    menu_toast (true),
                    (owned) after
                );
            });
        }

        public void toggle_steam (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target,
            owned Utils.Action? after = null
        ) {
            require_steam ((config) => {
                run_op (
                    () => {
                        if (entry.has_steam_shortcut (target.id)) {
                            ctx.steam.remove_steam_shortcut (entry, target.id, config);
                        } else {
                            ctx.steam.install_steam_shortcut (entry, target, config);
                        }
                    },
                    steam_toast (!entry.has_steam_shortcut (target.id)),
                    (owned) after
                );
            });
        }

        public void toggle_quick_launch_menu () {
            if (ctx.state.quick_launch_desktop_id != "") {
                run_op (remove_quick_launch_menu, menu_toast (false));
                return;
            }
            if (!require_quick_launch_target ()) return;
            ctx.dynamic_launcher.install_quick_launch_shortcut.begin ((obj, res) => {
                run_op (
                    () => {
                        ctx.dynamic_launcher.install_quick_launch_shortcut.end (res);
                        ctx.state.update_quick_launch_desktop_id (DynamicLauncherService.QUICK_LAUNCH_DESKTOP_ID);
                    },
                    menu_toast (true)
                );
            });
        }

        public void toggle_quick_launch_steam () {
            if (ctx.state.quick_launch_steam_app_id == "" && !require_quick_launch_target ()) return;
            require_steam ((config) => {
                var removing = ctx.state.quick_launch_steam_app_id != "";
                run_op (
                    () => {
                        if (removing) {
                            remove_quick_launch_steam (config);
                        } else {
                            ctx.state.update_quick_launch_steam_app_id (
                                ctx.steam.install_quick_launch_shortcut (config)
                            );
                        }
                    },
                    steam_toast (!removing)
                );
            });
        }

        private bool require_quick_launch_target () {
            if (!ctx.state.quick_launch.is_empty ()) return true;
            ctx.show_toast (_("Set a Quick Launch target first."));
            return false;
        }

        private static string menu_toast (bool added) {
            return added ? _("Menu shortcut added") : _("Menu shortcut removed");
        }

        private static string steam_toast (bool added) {
            return added
                ? _("Steam shortcut added. Restart Steam if it does not appear.")
                : _("Steam shortcut removed. Restart Steam if it still appears.");
        }

        private void run_op (owned Utils.FallibleAction op, string success, owned Utils.Action? after = null) {
            try {
                op ();
                ctx.show_toast (success);
            } catch (Error e) {
                ctx.show_toast (user_error (e));
            }
            if (after != null) after ();
        }

        private void require_steam (owned SteamReady on_ready) {
            bool access_lost;
            var config = ctx.steam.resolve_config (out access_lost);
            if (config != null) {
                on_ready (config);
                return;
            }
            if (access_lost) {
                ctx.show_toast (_("Steam folder access was lost. Please grant access again."));
            }
            if (ctx.ui == null || Widgets.Dialogs.FileDialogs.file_browse_blocked (ctx)) {
                if (!access_lost) {
                    ctx.show_toast (_("Could not find a Steam installation. Set the Steam path in Preferences."));
                }
                return;
            }
            if (Utils.EnvironmentInfo.is_sandboxed ()) {
                explain_steam_access (ctx.ui.window, () => pick_steam_folder ((owned) on_ready));
                return;
            }
            pick_steam_folder ((owned) on_ready);
        }

        public void pick_steam_folder (owned SteamReady? on_ready = null) {
            if (ctx.ui == null || Widgets.Dialogs.FileDialogs.file_browse_blocked (ctx)) return;
            ctx.ui.pick_folder (
                _("Select Steam Installation Folder"),
                Environment.get_home_dir (),
                (path, uri) => {
                    var config = ctx.steam.remember_folder (path, uri);
                    if (config == null) {
                        ctx.show_toast (_("Selected folder does not look like a Steam installation folder."));
                        return;
                    }
                    if (on_ready != null) on_ready (config);
                },
                (message) => ctx.show_toast (message)
            );
        }

        private static void explain_steam_access (Gtk.Window parent, owned Utils.Action on_continue) {
            Widgets.Dialogs.DialogHelpers.present_responses (
                parent,
                _("Steam Installation Access Required"),
                _("Select your Steam installation folder. Common locations:\n\n.local/share/Steam\n.var/app/com.valvesoftware.Steam/.local/share/Steam (Steam Flatpak)\n\nAvoid selecting .steam or .steam/steam as they are symlinks and may not work.\nEnable \"Show Hidden Files\" in the file picker to see these folders.\n\nSee the Lumoria wiki for step-by-step screenshots."),
                "continue",
                "cancel",
                (response) => {
                    if (response == "continue") on_continue ();
                },
                {
                    new Widgets.Dialogs.DialogHelpers.AlertResponse ("cancel", _("Cancel")),
                    new Widgets.Dialogs.DialogHelpers.AlertResponse (
                        "continue", _("Browse\u2026"), Adw.ResponseAppearance.SUGGESTED
                    )
                },
                null,
                false,
                600
            );
        }
    }
}
