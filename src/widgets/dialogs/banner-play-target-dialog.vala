namespace Lumoria.Widgets.Dialogs {

    public class BannerPlayTargetDialog : DialogHelpers.GamepadDialog {
        private Lumoria.Application.Context ctx;
        private Models.PrefixEntry entry;
        private Gtk.SearchEntry search;
        private Gee.ArrayList<Adw.PreferencesGroup> groups;
        private Gee.HashMap<Adw.ActionRow, Adw.PreferencesGroup> row_groups;

        public BannerPlayTargetDialog (Lumoria.Application.Context ctx, Models.PrefixEntry entry) {
            Object (
                title: _("Prefix Default"),
                content_width: Lumoria.Ui.Metrics.DIALOG_WIDTH_NARROW,
                content_height: 520
            );
            this.ctx = ctx;
            this.entry = entry;
            groups = new Gee.ArrayList<Adw.PreferencesGroup> ();
            row_groups = new Gee.HashMap<Adw.ActionRow, Adw.PreferencesGroup> ();
            build_ui ();
        }

        private void build_ui () {
            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var current = Widgets.PageChrome.untitled_group ();
            add_row (current, "", automatic_label ());
            groups.add (current);
            body.append (current);

            try {
                foreach (var target in ctx.actions.list (entry)) {
                    if (!target.pinnable) continue;
                    var title = Widgets.ManifestUi.target_group_title (
                        entry, target, ctx.launcher_manifests
                    );
                    Adw.PreferencesGroup? group = null;
                    foreach (var existing in groups) {
                        if (existing.title == title) {
                            group = existing;
                            break;
                        }
                    }
                    if (group == null) {
                        group = Widgets.PageChrome.build_group (title);
                        groups.add (group);
                        body.append (group);
                    }
                    add_row (group, target.id, target.selector_label);
                }
            } catch (Error e) {
                ctx.show_toast (user_error (e));
            }

            search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search");
            search.hexpand = true;
            search.margin_start = Lumoria.Ui.Metrics.PAGE_MARGIN;
            search.margin_end = Lumoria.Ui.Metrics.PAGE_MARGIN;
            search.margin_top = Lumoria.Ui.Metrics.EDITOR_INSET;
            search.search_changed.connect (apply_filter);

            var page = new Gtk.Box (Gtk.Orientation.VERTICAL, Lumoria.Ui.Metrics.GROUP_SPACING);
            page.append (search);
            page.append (PageChrome.scrolled (body));
            set_body (DialogHelpers.dialog_body (page));
        }

        private void add_row (Adw.PreferencesGroup group, string id, string label) {
            var row = new ChoiceRow (id, label);
            row.mark_current (entry.launch_entrypoint_id == id);
            row.activated.connect (on_target_chosen);
            group.add (row);
            row_groups[row] = group;
        }

        private void on_target_chosen (Adw.ActionRow row) {
            var id = ((ChoiceRow) row).value;
            if (entry.launch_entrypoint_id != id) {
                entry.launch_entrypoint_id = id;
                ctx.prefixes.schedule_save ();
            }
            close ();
        }

        private void apply_filter () {
            var query = search.text.down ().strip ();
            var visible_in = new Gee.HashMap<Adw.PreferencesGroup, int> ();
            foreach (var group in groups) {
                visible_in[group] = 0;
            }
            foreach (var row in row_groups.keys) {
                var group = row_groups[row];
                var match = query == "" || row.title.down ().contains (query);
                row.visible = match;
                if (match) visible_in[group] = visible_in[group] + 1;
            }
            foreach (var group in groups) {
                group.visible = visible_in[group] > 0;
            }
        }

        private string automatic_label () {
            Models.InstallerManifest? installer = null;
            try {
                installer = Models.ManifestRepository.shared ().require_installer (entry.installer_id);
            } catch (Error e) {
                ctx.show_toast (user_error (e));
            }
            if (entry.launcher_id != "" && installer != null && installer.supports_launcher (entry.launcher_id)) {
                return _("Automatic (launcher default)");
            }
            if (installer != null && installer.entrypoints.size > 0) {
                return _("Automatic (installation default)");
            }
            return _("Automatic (first custom entrypoint)");
        }
    }
}
