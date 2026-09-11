namespace Lumoria.Ui {

    public class PrefixGeneralPage : Gtk.Box {
        private Application.Context ctx;
        private Models.PrefixEntry entry;
        private Gtk.Box? launcher_box;
        private Adw.PreferencesGroup actions_group;
        private Gtk.Box installer_about;
        private Gtk.Box loading_host;
        private Gtk.Box script_box;
        private Widgets.PageSection custom_group;
        private Gee.ArrayList<Adw.PreferencesRow> custom_rows;
        private Gee.ArrayList<Adw.PreferencesRow> action_rows;
        private bool mapped_once = false;

        public PrefixGeneralPage (Application.Context ctx, Models.PrefixEntry entry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.entry = entry;
            action_rows = new Gee.ArrayList<Adw.PreferencesRow> ();
            custom_rows = new Gee.ArrayList<Adw.PreferencesRow> ();
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            build_ui (content);
            append (content);
            map.connect (on_map);
            ctx.actions.changed.connect (on_actions_changed);
        }

        private void on_map () {
            if (mapped_once) refresh_launch_lists ();
            mapped_once = true;
        }

        private void on_actions_changed () {
            if (get_mapped ()) refresh_launch_lists ();
        }

        private void add_custom_entry () {
            ctx.show_dialog (new Widgets.Dialogs.LaunchEditDialog.for_new_entry (ctx, entry));
        }

        private void open_prefix_folder () {
            ctx.actions.run (entry, Models.PrefixAction.BUILTIN_OPEN_PREFIX);
        }

        private void open_launcher_folder () {
            ctx.actions.run (entry, Models.PrefixAction.BUILTIN_OPEN_LAUNCHER);
        }

        private void open_wine_tools () {
            if (ctx.ui != null) ctx.ui.present_wine_tools (entry);
        }

        private void build_ui (Gtk.Box content) {
            append_launcher_group (content);

            var add = Widgets.PageChrome.icon_button (Widgets.IconRegistry.ADD, _("Add Custom Entry"));
            add.clicked.connect (add_custom_entry);
            custom_group = new Widgets.PageSection (_("Custom"), "", add);
            content.append (custom_group);
            rebuild_custom_entries ();

            installer_about = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.append (installer_about);
            actions_group = Widgets.PageChrome.untitled_group ();
            content.append (actions_group);
            populate_actions ();

            script_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.append (script_box);
            populate_script_groups ();

            var tools = new Widgets.PageSection (_("Tools"));
            if (!Utils.EnvironmentInfo.is_gamescope ()) {
                var folder = Widgets.PageChrome.action_row (_("Open Prefix Folder"), _("Open"));
                folder.button.clicked.connect (open_prefix_folder);
                tools.add (folder);
            }
            var wine_tools = Widgets.PageChrome.action_row (
                _("Wine Tools"),
                _("Open"),
                _("winecfg, regedit, and other Wine utilities")
            );
            wine_tools.button.clicked.connect (open_wine_tools);
            tools.add (wine_tools);
            content.append (tools);
            sync_loading ();
        }

        private void refresh_launch_lists () {
            rebuild_actions ();
            rebuild_custom_entries ();
        }

        private Adw.PreferencesRow? launcher_footer_row () {
            var launcher = Models.find_by_id<Models.LauncherManifest> (ctx.launcher_manifests, entry.launcher_id);
            if (launcher == null) return null;
            return Widgets.Messages.footer_row (launcher, Runtime.message_vars_for_prefix (entry, ctx.launcher_manifests));
        }

        private void append_launcher_group (Gtk.Box content) {
            if (entry.launcher_id != "") {
                content.append (Widgets.ManifestUi.launcher_heading (
                    entry,
                    ctx.launcher_manifests,
                    launcher_folder_button ()
                ));
            }

            loading_host = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.append (loading_host);
            if (entry.launcher_id == "") return;

            launcher_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.append (launcher_box);
            populate_launcher_group ();
        }

        private Gtk.Widget? launcher_folder_button () {
            if (Utils.EnvironmentInfo.is_gamescope ()) return null;
            if (Runtime.launcher_dir (entry, ctx.launcher_manifests) == "") return null;
            var folder = Widgets.PageChrome.icon_button (
                Widgets.IconRegistry.OPEN_FOLDER,
                _("%s Folder").printf (Widgets.ManifestUi.launcher_display_name (entry, ctx.launcher_manifests))
            );
            folder.clicked.connect (open_launcher_folder);
            return folder;
        }

        private void populate_launcher_group () {
            if (launcher_box == null) return;
            Widgets.PageChrome.clear_children (launcher_box);

            var main_actions = new Gee.ArrayList<Runtime.LaunchTarget> ();
            var profile_actions = new Gee.ArrayList<Runtime.LaunchTarget> ();
            try {
                Widgets.LaunchTargetGrouper.split_launcher (
                    ctx.actions.list_matching (entry, (target) => {
                        return target.pinnable
                            && target.provider_type == Models.PrefixActionProvider.LAUNCHER;
                    }),
                    main_actions,
                    profile_actions
                );
            } catch (Error e) {
                var group = Widgets.PageChrome.untitled_group ();
                group.add (Widgets.PageChrome.error_row (_("Could not load actions"), e));
                launcher_box.append (group);
            }

            var main_group = append_launcher_rows (main_actions, null);
            var footer = launcher_footer_row ();
            if (footer != null) {
                if (main_group == null) {
                    main_group = Widgets.PageChrome.untitled_group ();
                    launcher_box.append (main_group);
                }
                main_group.add (footer);
            }
            append_launcher_rows (profile_actions, _("Profiles"));
            var launcher = Models.find_by_id<Models.LauncherManifest> (ctx.launcher_manifests, entry.launcher_id);
            if (launcher != null) {
                Widgets.Messages.fill (
                    launcher_box,
                    launcher.messages,
                    Runtime.message_vars_for_prefix (entry, ctx.launcher_manifests),
                    { Models.ManifestMessages.MANAGE }
                );
            }
        }

        private Adw.PreferencesGroup? append_launcher_rows (
            Gee.ArrayList<Runtime.LaunchTarget> actions,
            string? caption
        ) {
            if (actions.size == 0) return null;
            if (caption != null) {
                launcher_box.append (Widgets.PageChrome.section_caption (caption));
            }
            var group = Widgets.PageChrome.untitled_group ();
            foreach (var action in actions) {
                add_action_row (group, action);
            }
            launcher_box.append (group);
            return group;
        }

        private void rebuild_actions () {
            sync_loading ();
            if (ctx.actions.is_loading (entry.id)) return;
            populate_launcher_group ();
            foreach (var row in action_rows) actions_group.remove (row);
            action_rows.clear ();
            populate_actions ();
            populate_script_groups ();
        }

        private void sync_loading () {
            Widgets.PageChrome.clear_children (loading_host);
            if (!ctx.actions.is_loading (entry.id)) return;
            loading_host.append (Widgets.PageChrome.remote_actions_loading_group ());
        }

        private void populate_actions () {
            try {
                foreach (var action in ctx.actions.list_matching (entry, (target) => {
                    return target.provider_type == Models.PrefixActionProvider.INSTALLER;
                })) {
                    action_rows.add (add_action_row (actions_group, action));
                }
            } catch (Error e) {
                var row = Widgets.PageChrome.error_row (_("Could not load actions"), e);
                actions_group.add (row);
                action_rows.add (row);
            }
            var installer = Models.ManifestRepository.shared ().installer (entry.installer_id);
            Widgets.ManifestUi.populate_about (
                installer_about,
                installer,
                Runtime.message_vars_for_prefix (entry, ctx.launcher_manifests),
                installer != null ? installer.icon : "",
                { Models.ManifestMessages.MANAGE }
            );
            actions_group.visible = action_rows.size > 0;
        }

        private void populate_script_groups () {
            Widgets.PageChrome.clear_children (script_box);
            foreach (var spec in entry.post_install_manifests) {
                Widgets.ScriptOverview.append (script_box, ctx, entry, spec);
            }
        }

        private Adw.PreferencesRow add_action_row (
            Adw.PreferencesGroup group,
            Runtime.LaunchTarget action
        ) {
            var row = Widgets.ActionRows.prefix_action_row (ctx, entry, action);
            group.add (row);
            return row;
        }

        private void rebuild_custom_entries () {
            foreach (var row in custom_rows) custom_group.remove_row (row);
            custom_rows.clear ();

            if (entry.custom_entrypoints.size == 0) {
                var empty = Widgets.PageChrome.placeholder_row (_("No custom launch entries. Click + to add one."));
                custom_group.add (empty);
                custom_rows.add (empty);
                return;
            }
            foreach (var ep in entry.custom_entrypoints) {
                var row = Widgets.ActionRows.prefix_action_row (
                    ctx, entry, Runtime.launch_target_from_entrypoint (ep, null)
                );
                custom_group.add (row);
                custom_rows.add (row);
            }
        }
    }
}
