namespace Lumoria.Ui {

    public class PrefixShortcutsPage : Gtk.Box {
        private Application.Context ctx;
        private Models.PrefixEntry entry;
        private Gtk.Box content;

        public PrefixShortcutsPage (Application.Context ctx, Models.PrefixEntry entry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.entry = entry;
            content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            append (content);
            map.connect (rebuild);
            ctx.prefixes.changed.connect (on_prefixes_changed);
            ctx.actions.changed.connect (on_actions_changed);
        }

        private void on_prefixes_changed () {
            if (!get_mapped ()) return;
            if (ctx.state.page != Application.PageKind.PREFIX) return;
            if (ctx.state.selected_prefix_id != entry.id) return;
            rebuild ();
        }

        private void on_actions_changed () {
            if (get_mapped ()) rebuild ();
        }

        public void rebuild () {
            Widgets.PageChrome.clear_children (content);

            var heading_first = entry.launcher_id != "";
            if (heading_first) append_launcher_heading ();
            if (ctx.actions.is_loading (entry.id)) {
                content.append (Widgets.PageChrome.remote_actions_loading_group ());
                return;
            }

            Gee.ArrayList<Runtime.LaunchTarget> targets;
            try {
                targets = ctx.actions.list_matching (entry, (target) => target.pinnable);
            } catch (Error e) {
                var group = new Widgets.PageSection (_("Shortcuts"));
                group.add (Widgets.PageChrome.error_row (_("Could not load launch targets"), e));
                content.append (group);
                return;
            }
            var vars = Runtime.message_vars_for_prefix (entry, ctx.launcher_manifests);

            if (targets.size == 0) {
                var empty = new Widgets.PageSection (_("Shortcuts"));
                empty.add (Widgets.PageChrome.placeholder_row (_("No launch targets available")));
                content.append (empty);
                return;
            }

            var launcher_section = false;
            Adw.PreferencesGroup? launcher_main = null;
            Adw.PreferencesGroup? launcher_profiles = null;
            string current_title = "";
            Widgets.PageSection? group = null;
            foreach (var target in targets) {
                if (Widgets.LaunchTargetGrouper.is_launcher_section (target)) {
                    if (!launcher_section) {
                        if (!heading_first) append_launcher_heading ();
                        launcher_section = true;
                    }
                    if (target.section == Runtime.LaunchTargetSection.LAUNCHER_PROFILES) {
                        if (launcher_profiles == null) {
                            content.append (Widgets.PageChrome.section_caption (_("Profiles")));
                            launcher_profiles = Widgets.PageChrome.untitled_group ();
                            content.append (launcher_profiles);
                        }
                        add_shortcut_row (launcher_profiles, target, vars);
                    } else {
                        if (launcher_main == null) {
                            launcher_main = Widgets.PageChrome.untitled_group ();
                            content.append (launcher_main);
                        }
                        add_shortcut_row (launcher_main, target, vars);
                    }
                    continue;
                }

                var title = Widgets.ManifestUi.target_group_title (
                    entry, target, ctx.launcher_manifests
                );
                if (group == null || current_title != title) {
                    group = new Widgets.PageSection (title);
                    content.append (group);
                    current_title = title;
                }
                add_shortcut_row (group.group, target, vars);
            }
        }

        private void append_launcher_heading () {
            content.append (Widgets.ManifestUi.launcher_heading (entry, ctx.launcher_manifests));
        }

        private void add_shortcut_row (
            Adw.PreferencesGroup group,
            Runtime.LaunchTarget target,
            Gee.HashMap<string, string> vars
        ) {
            var row = new Widgets.LaunchDisplayRow (ctx, entry, target, vars);
            row.add_suffix (new Widgets.ShortcutToggles.for_target (ctx, entry, target));
            group.add (row);
        }
    }
}
