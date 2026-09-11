namespace Lumoria.Application {

    public class DynamicLauncherService : Object {

        public const string QUICK_LAUNCH_DESKTOP_ID = Config.APP_ID + ".quick-launch.desktop";

        private Context ctx;

        public DynamicLauncherService (Context ctx) {
            this.ctx = ctx;
        }

        private static string portal_error_message (Error e) {
            var msg = e.message;
            if (msg.contains ("UnknownMethod") || msg.contains ("unknown method") ||
                msg.contains ("No such interface")) {
                return _("Menu shortcuts need a desktop portal with Dynamic Launcher support (xdg-desktop-portal 1.15+ and a backend that implements it). Some minimal or older setups do not provide this.");
            }
            return msg;
        }

        private static bool is_not_found (Error e) {
            return e.matches (IOError.quark (), IOError.NOT_FOUND)
                || e.matches (FileError.quark (), FileError.NOENT);
        }

        private static bool is_missing_shortcut_error (Error e) {
            if (is_not_found (e)) return true;
            var remote = e.copy ();
            return DBusError.is_remote_error (remote)
                && DBusError.strip_remote_error (remote)
                && is_not_found (remote);
        }

        public async void install_menu_shortcut (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target
        ) throws GLib.Error {
            var desktop_id = build_desktop_id (entry, target.id);
            yield install_via_host (
                target.shortcut_label (entry),
                desktop_id,
                build_desktop_entry (
                    _("%s launcher for Linux").printf (Widgets.ManifestUi.installer_display_name (entry)),
                    Utils.host_lumoria_exec ("launch %s%s".printf (
                        Utils.shell_quote (entry.id),
                        target.id != "" ? " --entrypoint %s".printf (Utils.shell_quote (target.id)) : ""
                    ))
                ),
                ShortcutArtwork.bytes_for (entry, target),
                "install prefix_id='%s' entrypoint_id='%s'".printf (entry.id, target.id)
            );
            entry.dynamic_launcher_desktop_ids[target.id] = desktop_id;
            ctx.prefixes.schedule_save ();
        }

        public void remove_menu_shortcut (Models.PrefixEntry entry, string entrypoint_id) throws Error {
            if (!entry.dynamic_launcher_desktop_ids.has_key (entrypoint_id)) return;
            uninstall (
                entry.dynamic_launcher_desktop_ids[entrypoint_id],
                "remove prefix_id='%s' entrypoint_id='%s'".printf (entry.id, entrypoint_id)
            );
            entry.dynamic_launcher_desktop_ids.unset (entrypoint_id);
            ctx.prefixes.schedule_save ();
        }

        public async void install_quick_launch_shortcut () throws GLib.Error {
            yield install_via_host (
                _("Lumoria Quick Launch"),
                QUICK_LAUNCH_DESKTOP_ID,
                build_desktop_entry (
                    _("Launches the current Quick Launch target"),
                    Utils.host_lumoria_exec ("launch --quick")
                ),
                ShortcutArtwork.lumoria_bytes (),
                "Quick Launch install"
            );
        }

        public void remove_quick_launch_shortcut (string desktop_id) throws Error {
            if (desktop_id == "") return;
            uninstall (desktop_id, "Quick Launch remove");
        }

        private async void install_via_host (
            string label,
            string desktop_id,
            string desktop_entry,
            Bytes icon,
            string what
        ) throws Error {
            if (ctx.ui == null) {
                throw new LumoriaError.FAILED (_("A window is required to add a menu shortcut."));
            }
            try {
                yield ctx.ui.install_dynamic_launcher (label, desktop_id, desktop_entry, icon);
            } catch (Error e) {
                throw portal_failure (what, e);
            }
        }

        /* A shortcut the portal no longer knows about counts as removed. */
        private void uninstall (string desktop_id, string what) throws Error {
            try {
                var portal = new Xdp.Portal.initable_new ();
                if (!portal.dynamic_launcher_uninstall (desktop_id)) {
                    throw new LumoriaError.FAILED (_("Menu shortcut removal did not complete."));
                }
            } catch (Error e) {
                if (is_missing_shortcut_error (e)) return;
                throw portal_failure (what, e);
            }
        }

        private static Error portal_failure (string what, Error e) {
            warning ("Dynamic launcher %s failed: %s (domain=%s code=%d)", what, e.message, e.domain.to_string (), e.code);
            return new LumoriaError.FAILED ("%s", portal_error_message (e));
        }

        private string build_desktop_id (Models.PrefixEntry entry, string entrypoint_id) {
            var id_seed = "%s:%s".printf (entry.id, entrypoint_id);
            var slug = sanitize_flatpak_segment (Utils.slugify (id_seed));
            var desktop_id = "%s.%s.desktop".printf (Config.APP_ID, slug);
            if (desktop_id.length > 255 + 8) {
                var hash = Checksum.compute_for_string (ChecksumType.SHA256, id_seed).substring (0, 16);
                desktop_id = "%s.l%s.desktop".printf (Config.APP_ID, hash);
            }
            return desktop_id;
        }

        private static string sanitize_flatpak_segment (string raw) {
            if (raw == "") return "l0";
            if (raw[0].isalpha () || raw[0] == '_' || raw[0] == '-') return raw;
            return "l" + raw;
        }

        private string build_desktop_entry (string comment, string exec) throws Error {
            var key_file = new KeyFile ();
            key_file.set_string ("Desktop Entry", "Type", "Application");
            key_file.set_string ("Desktop Entry", "Comment", comment);
            key_file.set_boolean ("Desktop Entry", "Terminal", false);
            key_file.set_string_list ("Desktop Entry", "Categories", { "Game" });
            key_file.set_boolean ("Desktop Entry", "StartupNotify", true);
            key_file.set_string ("Desktop Entry", "Exec", exec);
            key_file.set_string ("Desktop Entry", "TryExec", try_exec ());
            size_t length;
            var data = key_file.to_data (out length);
            if (length == 0) {
                throw new LumoriaError.FAILED (_("Could not build a menu shortcut."));
            }
            return data;
        }

        private string try_exec () {
            if (Utils.EnvironmentInfo.is_flatpak ()) return "flatpak";
            return Utils.host_lumoria_bin ();
        }
    }
}
