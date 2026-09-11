namespace Lumoria.Ui {

    public class PrefixAdvancedPage : Gtk.Box {
        private Application.Context ctx;
        private Models.PrefixEntry entry;
        private Adw.SwitchRow? laa_row;

        public PrefixAdvancedPage (Application.Context ctx, Models.PrefixEntry entry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.entry = entry;

            var installer = Models.ManifestRepository.shared ().installer (entry.installer_id);
            var patch = Widgets.PageChrome.installer_patch_for_setting (installer, Models.InstallerPatch.SETTING_LARGE_ADDRESS_AWARE);
            if (patch != null) {
                var patches = new Widgets.PageSection (_("Patches"));
                laa_row = new Adw.SwitchRow ();
                laa_row.title = patch.name;
                laa_row.active = entry.large_address_aware == true;
                laa_row.notify["active"].connect (on_laa_toggled);
                patches.add (laa_row);
                append (patches);
            }

            var danger = new Widgets.PageSection (_("Danger Zone"));
            var remove = Widgets.PageChrome.action_row (
                _("Remove Prefix"),
                _("Remove"),
                entry.resolved_path (),
                "destructive"
            );
            remove.button.clicked.connect (confirm_remove);
            danger.add (remove);
            append (danger);
        }

        private void on_laa_toggled () {
            entry.large_address_aware = laa_row.active;
            ctx.prefixes.schedule_save ();
        }

        private void confirm_remove () {
            Widgets.Dialogs.PrefixDialogs.present_remove_prefix_dialog (this, entry, (deleted_files) => {
                ctx.remove_prefix (entry, deleted_files);
            });
        }
    }
}
