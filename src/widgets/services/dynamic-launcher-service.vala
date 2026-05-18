namespace Lumoria.Widgets.Services {

    public class DynamicLauncherService : Object {

        private static string portal_error_message (Error e) {
            var msg = e.message;
            if (msg.contains ("UnknownMethod") || msg.contains ("unknown method") ||
                msg.contains ("No such interface")) {
                return _("Menu shortcuts need a desktop portal with Dynamic Launcher support (xdg-desktop-portal 1.15+ and a backend that implements it). Some minimal or older setups do not provide this.");
            }
            return msg;
        }

        private static bool is_missing_shortcut_error (Error e) {
            if (e.matches (IOError.quark (), IOError.NOT_FOUND)) return true;

            var msg = e.message.down ();
            return msg.contains ("_g_2dio_2derror_2dquark.code1") ||
                (msg.contains ("error removing file") && msg.contains ("no such file or directory"));
        }

        private static string failure_context (Models.PrefixEntry entry, string entrypoint_id, string desktop_id) {
            return "prefix_id='%s' entrypoint_id='%s' desktop_id='%s' flatpak=%s".printf (
                entry.id,
                entrypoint_id,
                desktop_id,
                Utils.EnvironmentInfo.is_flatpak () ? "yes" : "no"
            );
        }

        public async bool install_menu_shortcut (
            Gtk.Window parent,
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs,
            Runtime.LaunchTarget target
        ) throws GLib.Error {
            var desktop_id = build_desktop_id (entry, target.id);
            try {
                var portal = new Xdp.Portal.initable_new ();
                var p = Xdp.parent_new_gtk (parent);
                var icon_v = load_launcher_icon ().serialize ();

                var label = build_shortcut_label (entry, target);
                var prep = yield portal.dynamic_launcher_prepare_install (
                    p,
                    label,
                    icon_v,
                    Xdp.LauncherType.APPLICATION,
                    null,
                    false,
                    false,
                    null
                );

                var tok = prep.lookup_value ("token", new VariantType ("s"));
                if (tok == null) {
                    throw new IOError.FAILED ("Dynamic launcher: missing token");
                }
                string token_str = tok.get_string ();

                var desktop_entry = build_desktop_entry (entry, target.id);

                if (!portal.dynamic_launcher_install (token_str, desktop_id, desktop_entry)) {
                    throw new IOError.FAILED (_("Menu shortcut install did not complete."));
                }
                entry.dynamic_launcher_desktop_ids[target.id] = desktop_id;
                return true;
            } catch (Error e) {
                warning ("Dynamic launcher install failed: %s (domain=%s code=%d); %s",
                    e.message, e.domain.to_string (), e.code,
                    failure_context (entry, target.id, desktop_id));
                throw new IOError.FAILED (portal_error_message (e));
            }
        }

        public bool remove_menu_shortcut (Models.PrefixEntry entry, string entrypoint_id) throws Error {
            if (!entry.dynamic_launcher_desktop_ids.has_key (entrypoint_id)) return true;
            var desktop_id = entry.dynamic_launcher_desktop_ids[entrypoint_id];
            try {
                var portal = new Xdp.Portal.initable_new ();
                if (!portal.dynamic_launcher_uninstall (desktop_id)) {
                    throw new IOError.FAILED (_("Menu shortcut removal did not complete."));
                }
            } catch (Error e) {
                if (is_missing_shortcut_error (e)) {
                    entry.dynamic_launcher_desktop_ids.unset (entrypoint_id);
                    return true;
                }
                warning ("Dynamic launcher remove failed: %s (domain=%s code=%d); %s",
                    e.message, e.domain.to_string (), e.code,
                    failure_context (entry, entrypoint_id, desktop_id));
                throw new IOError.FAILED (portal_error_message (e));
            }
            entry.dynamic_launcher_desktop_ids.unset (entrypoint_id);
            return true;
        }

        public bool has_menu_shortcut (Models.PrefixEntry entry, string entrypoint_id) {
            return entry.dynamic_launcher_desktop_ids.has_key (entrypoint_id);
        }

        private GLib.Icon load_launcher_icon () throws Error {
            var bytes = resources_lookup_data (
                "/net/windower/Lumoria/icons/hicolor/scalable/apps/net.windower.Lumoria.svg",
                ResourceLookupFlags.NONE
            );
            return new BytesIcon (bytes);
        }

        private string build_shortcut_label (Models.PrefixEntry entry, Runtime.LaunchTarget target) {
            var prefix_label = "%s (%s)".printf (Config.APP_NAME, entry.display_name ());
            return "%s - %s".printf (prefix_label, target.selector_label);
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

        private string build_desktop_entry (Models.PrefixEntry entry, string entrypoint_id) throws Error {
            var key_file = new KeyFile ();
            key_file.set_string ("Desktop Entry", "Type", "Application");
            key_file.set_string ("Desktop Entry", "Comment", _("Final Fantasy XI Launcher for Linux"));
            key_file.set_boolean ("Desktop Entry", "Terminal", false);
            key_file.set_string_list ("Desktop Entry", "Categories", { "Game" });
            key_file.set_boolean ("Desktop Entry", "StartupNotify", true);
            key_file.set_string ("Desktop Entry", "Exec", build_cli_exec (entry, entrypoint_id));
            key_file.set_string ("Desktop Entry", "TryExec", build_try_exec ());

            size_t length;
            var data = key_file.to_data (out length);
            if (length == 0) {
                throw new IOError.FAILED ("Dynamic launcher: empty desktop entry");
            }
            return data;
        }

        private string build_try_exec () {
            if (Utils.EnvironmentInfo.is_flatpak ()) {
                return "flatpak";
            }
            var exe = Utils.current_executable_path ();
            if (exe != null && exe != "") {
                return exe;
            }
            return "lumoria";
        }

        private string build_cli_exec (Models.PrefixEntry entry, string entrypoint_id) {
            var ep_arg = entrypoint_id != "" ? " --entrypoint %s".printf (shell_quote (entrypoint_id)) : "";
            if (Utils.EnvironmentInfo.is_flatpak ()) {
                return "lumoria launch %s%s".printf (shell_quote (entry.id), ep_arg);
            }
            var exe = Utils.current_executable_path ();
            if (exe != null && exe != "") {
                return "%s launch %s%s".printf (shell_quote (exe), shell_quote (entry.id), ep_arg);
            }
            return "lumoria launch %s%s".printf (shell_quote (entry.id), ep_arg);
        }

        private string shell_quote (string s) {
            if (s == "") return "''";
            if (s.index_of (" ") < 0 && s.index_of ("'") < 0 && s.index_of ("\"") < 0) {
                return s;
            }
            return "'%s'".printf (s.replace ("'", "'\\''"));
        }
    }
}
