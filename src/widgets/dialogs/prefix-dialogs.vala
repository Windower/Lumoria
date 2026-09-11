namespace Lumoria.Widgets.Dialogs {

    public class PrefixDialogs : Object {
        public static void present_prefix_update_dialog (
            Gtk.Widget parent,
            Gee.ArrayList<Runtime.PendingUpdate> updates,
            owned Runtime.UpdateDecisionHandler on_decision
        ) {
            DialogHelpers.present_responses (
                parent,
                _("Update Available"),
                _("Updating can cause problems. Back up the prefix first."),
                "cancel",
                "cancel",
                (response) => {
                    switch (response) {
                        case "update":
                            on_decision (Runtime.UpdateDecision.UPDATE);
                            break;
                        case "stay":
                            on_decision (Runtime.UpdateDecision.STAY);
                            break;
                        default:
                            on_decision (Runtime.UpdateDecision.CANCEL);
                            break;
                    }
                },
                {
                    new DialogHelpers.AlertResponse ("cancel", _("Cancel")),
                    new DialogHelpers.AlertResponse ("stay", _("Stay on Current Version")),
                    new DialogHelpers.AlertResponse ("update", _("Update"), Adw.ResponseAppearance.SUGGESTED)
                },
                build_update_table (updates),
                true
            );
        }

        public static void present_grant_access (
            Gtk.Widget? parent,
            Models.PrefixEntry entry,
            owned DialogHelpers.GrantFolderCallback on_granted,
            owned DialogHelpers.ErrorMessageCallback? on_error = null
        ) {
            var host = parent != null ? parent.get_root () as Gtk.Widget ?? parent : null;
            if (FileDialogs.file_browse_blocked ()) {
                if (on_error != null) {
                    on_error (_("File browsing is not available in a gamescope session."));
                }
                return;
            }

            var expected = Lumoria.Application.PrefixService.expected_folder_name (entry);
            var body = _(
                "We're sorry, there has been a problem. We need to regrant permission to your prefix.\n\n" +
                "Please select the folder named \"%s\"."
            ).printf (expected);
            if (entry.path_portal != null && !entry.path_portal.is_empty ()) {
                body = string.join ("\n\n", body, _("Saved document: %s/%s").printf (
                    entry.path_portal.document_id,
                    entry.path_portal.document_path
                ));
            }

            DialogHelpers.present_grant (
                host,
                _("Grant Prefix Access"),
                body,
                () => pick_grant_folder (host as Gtk.Window, entry, (owned) on_granted, (owned) on_error)
            );
        }

        private static void pick_grant_folder (
            Gtk.Window? parent,
            Models.PrefixEntry entry,
            owned DialogHelpers.GrantFolderCallback on_granted,
            owned DialogHelpers.ErrorMessageCallback? on_error
        ) {
            var dialog = FileDialogs.build_folder_dialog (_("Grant Prefix Access"));
            FileDialogs.select_folder (parent, dialog, null, (path, uri) => {
                if (path == "") return;
                handle_granted_folder (parent, entry, File.new_for_uri (uri), path, (owned) on_granted, (owned) on_error);
            }, (owned) on_error);
        }

        private static void handle_granted_folder (
            Gtk.Window? parent,
            Models.PrefixEntry entry,
            File file,
            string path,
            owned DialogHelpers.GrantFolderCallback on_granted,
            owned DialogHelpers.ErrorMessageCallback? on_error
        ) {
            if (!Runtime.prefix_root_has_drive_c (path)) {
                if (on_error != null) {
                    on_error (_("Selected folder does not look like a Lumoria prefix."));
                }
                return;
            }

            var expected = Lumoria.Application.PrefixService.expected_folder_name (entry);
            var selected = Path.get_basename (Utils.normalize_dir_path (path));
            if (expected != "" && selected != expected) {
                confirm_folder_mismatch (parent, entry, file, path, expected, selected, (owned) on_granted);
                return;
            }
            on_granted (entry, file, path);
        }

        private static void confirm_folder_mismatch (
            Gtk.Window? parent,
            Models.PrefixEntry entry,
            File file,
            string path,
            string expected,
            string selected,
            owned DialogHelpers.GrantFolderCallback on_granted
        ) {
            DialogHelpers.present_grant (
                parent,
                _("Use Different Folder?"),
                _("Lumoria expected the folder named \"%s\", but you selected \"%s\". Use this folder for the prefix?").printf (
                    expected,
                    selected
                ),
                () => on_granted (entry, file, path),
                "use",
                _("Use This Folder")
            );
        }

        public static void present_remove_prefix_dialog (
            Gtk.Widget parent,
            Models.PrefixEntry entry,
            owned DialogHelpers.PrefixRemoveCallback on_confirm
        ) {
            var host = parent.get_root () as Gtk.Widget ?? parent;
            DialogHelpers.present_responses (
                host,
                _("Remove Prefix?"),
                _("Remove \"%s\" from the prefix list?\n\nPath: %s\n\nDeleting this prefix will cause any active game sessions to close.").printf (
                    entry.display_name (), entry.path
                ),
                "cancel",
                "cancel",
                (response) => {
                    if (response != "remove" && response != "delete") return;
                    on_confirm (response == "delete");
                },
                {
                    new DialogHelpers.AlertResponse ("cancel", _("Cancel")),
                    new DialogHelpers.AlertResponse ("remove", _("Remove from List"), Adw.ResponseAppearance.SUGGESTED),
                    new DialogHelpers.AlertResponse ("delete", _("Remove and Delete Files"), Adw.ResponseAppearance.DESTRUCTIVE)
                }
            );
        }

        private static Gtk.Widget build_update_table (Gee.ArrayList<Runtime.PendingUpdate> updates) {
            var list = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            list.hexpand = true;

            foreach (var update in updates) {
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
                row.hexpand = true;

                var name = new Gtk.Label (update.label);
                name.xalign = 0f;
                name.hexpand = true;
                name.ellipsize = Pango.EllipsizeMode.END;

                var versions = new Gtk.Label ("%s → %s".printf (
                    update.current_version,
                    update.new_version
                ));
                versions.xalign = 1f;
                versions.ellipsize = Pango.EllipsizeMode.END;
                versions.add_css_class ("caption");
                versions.add_css_class ("numeric");
                versions.add_css_class ("dim-label");

                row.append (name);
                row.append (versions);
                list.append (row);
            }

            return list;
        }
    }
}
