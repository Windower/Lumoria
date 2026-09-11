namespace Lumoria.Ui {

    public class CreatePrefixView : Gtk.Box, TabHost {
        public signal void create_requested (Models.PrefixEntry draft);

        private Application.Context ctx;
        private Models.PrefixEntry draft;
        private Gee.ArrayList<Models.InstallerManifest> installer_manifests;
        private Gee.ArrayList<Models.LauncherManifest> visible_launchers;
        private Gee.HashMap<string, Widgets.ComponentBlock> component_rows;

        private Adw.EntryRow name_entry;
        private Adw.ActionRow dir_row;
        private Widgets.OptionListRow installer_combo;
        private Widgets.OptionListRow launcher_combo;
        private Widgets.OptionListRow region_combo;
        private Gtk.Box notes;
        private Adw.SwitchRow? laa_row;
        private Widgets.PageSection? patches_group;
        private RunnerOverrideRows runner_rows;
        private Gtk.Button create_btn;
        private Adw.ViewStack stack;

        public CreatePrefixView (Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            draft = new Models.PrefixEntry ();
            draft.path = Utils.next_available_prefix_path (ctx.registry);
            installer_manifests = Models.ManifestRepository.shared ().installers;
            visible_launchers = new Gee.ArrayList<Models.LauncherManifest> ();
            component_rows = new Gee.HashMap<string, Widgets.ComponentBlock> ();
            build_ui ();
            update_installer_ui ();
        }

        public bool cycle_tabs (int delta) {
            return Widgets.PageChrome.cycle_stack (stack, delta);
        }

        private void build_ui () {
            stack = Widgets.PageChrome.settings_stack ();
            var general = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var identity = new Widgets.PageSection (_("General"));

            dir_row = new Adw.ActionRow ();
            dir_row.title = _("Directory");
            dir_row.subtitle = draft.path;
            dir_row.subtitle_selectable = true;
            if (!Utils.EnvironmentInfo.is_gamescope ()) {
                var browse = Widgets.PageChrome.browse_button ();
                browse.clicked.connect (on_browse);
                dir_row.add_suffix (browse);
            }
            identity.add (dir_row);

            name_entry = new Adw.EntryRow ();
            name_entry.title = _("Name");
            identity.add (name_entry);

            installer_combo = new Widgets.OptionListRow ();
            installer_combo.title = _("Installation");
            var installer_items = new Gee.ArrayList<Widgets.OptionListItem> ();
            foreach (var spec in installer_manifests) {
                installer_items.add (manifest_option (spec));
            }
            installer_combo.set_items (installer_items);
            installer_combo.selected = default_installer_index ();
            installer_combo.notify["selected"].connect (update_installer_ui);
            identity.add (installer_combo);

            region_combo = new Widgets.OptionListRow ();
            region_combo.title = _("Region");
            region_combo.notify["selected"].connect (update_notes);
            identity.add (region_combo);

            launcher_combo = new Widgets.OptionListRow ();
            launcher_combo.title = _("Launcher");
            launcher_combo.notify["selected"].connect (update_notes);
            identity.add (launcher_combo);
            general.append (identity);
            notes = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            general.append (notes);

            if (Utils.EnvironmentInfo.is_gamescope ()) {
                general.append (Widgets.Messages.warning (
                    _("Prefix installation is disabled in gamescope sessions. Enter desktop mode to create a new prefix.")
                ));
            }

            patches_group = new Widgets.PageSection (_("Patches"));
            laa_row = new Adw.SwitchRow ();
            laa_row.title = _("Large Address Aware");
            laa_row.active = false;
            patches_group.add (laa_row);
            general.append (patches_group);

            Widgets.PageChrome.add_scrolled_settings_page (stack, general, Widgets.PageChrome.PAGE_GENERAL, _("General"));

            var runtime = new SettingsTabs ();
            runtime.add_scrolled (runner_tab (), "runner", _("Runner"));
            runtime.add_scrolled (components_tab (), "components", _("Components"));
            runtime.add_scrolled (wine_tab (), "wine", _("Wine"));
            runtime.add_scrolled (environment_tab (), "environment", _("Environment"));
            Widgets.PageChrome.add_settings_page (stack, runtime, Widgets.PageChrome.PAGE_RUNTIME, _("Runtime"));

            Widgets.PageChrome.add_settings_page (
                stack,
                new ScriptListEditor (ctx, draft.post_install_manifests),
                Widgets.PageChrome.PAGE_SCRIPTS,
                _("Scripts")
            );

            create_btn = new Gtk.Button.with_label (_("Create"));
            create_btn.add_css_class ("suggested-action");
            Widgets.PageChrome.margins (create_btn, Metrics.PAGE_MARGIN, Metrics.EDITOR_INSET);
            create_btn.sensitive = !Utils.EnvironmentInfo.is_gamescope ();
            create_btn.clicked.connect (on_create);

            hexpand = true;
            vexpand = true;
            append (Widgets.PageChrome.page_with_stack (stack, Widgets.PageChrome.page_title (_("New Prefix")), null, create_btn));
        }

        private Gtk.Widget runner_tab () {
            runner_rows = new RunnerOverrideRows (ctx);
            runner_rows.bind ("", Models.ToolVersionRef.INHERIT.id (), "");
            return runner_rows;
        }

        private Gtk.Widget components_tab () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.append (Widgets.ManifestUi.components_disable_note ());
            var first = true;
            foreach (var spec in Models.ManifestRepository.shared ().components) {
                var block = new Widgets.ComponentBlock (ctx, spec, null, "", null, first);
                component_rows[spec.id] = block;
                box.append (block);
                first = false;
            }
            box.append (new Widgets.DxvkConfigGroup.for_entry (ctx, draft));
            return box;
        }

        private Gtk.Widget wine_tab () {
            return new Widgets.WineOverrideSection.for_entry (draft);
        }

        private Gtk.Widget environment_tab () {
            return new Widgets.EnvironmentSettings.for_entry (ctx, draft);
        }

        private uint default_installer_index () {
            for (int i = 0; i < installer_manifests.size; i++) {
                if (installer_manifests[i].id == Models.ManifestRepository.shared ().default_installer_id ()) return (uint) i;
            }
            return 0;
        }

        private Models.InstallerManifest? selected_installer () {
            var index = (int) installer_combo.selected;
            if (index < 0 || index >= installer_manifests.size) return null;
            return installer_manifests[index];
        }

        private void update_installer_ui () {
            var installer = selected_installer ();
            rebuild_region (installer);
            rebuild_launcher (installer);
            var has_launchers = installer != null && installer.launcher_ids.size > 0;
            var has_regions = installer != null && installer.regions.size > 0;
            var patch = Widgets.PageChrome.installer_patch_for_setting (installer, Models.InstallerPatch.SETTING_LARGE_ADDRESS_AWARE);
            launcher_combo.visible = has_launchers;
            region_combo.visible = has_regions;
            if (patches_group != null) patches_group.visible = patch != null;
            if (laa_row != null && patch != null) laa_row.title = patch.name;
            foreach (var component in Models.ManifestRepository.shared ().components) {
                if (!component_rows.has_key (component.id)) continue;
                component_rows[component.id].visible = installer != null && component.supports_installer (installer.id);
            }
        }

        private void rebuild_region (Models.InstallerManifest? installer) {
            var model = new Gtk.StringList (null);
            uint selected = 0;
            if (installer != null) {
                for (int i = 0; i < installer.regions.size; i++) {
                    model.append (installer.regions[i].name);
                    if (installer.regions[i].id == installer.effective_default_region_id ()) {
                        selected = (uint) i;
                    }
                }
            }
            region_combo.model = model;
            region_combo.selected = selected;
        }

        private void rebuild_launcher (Models.InstallerManifest? installer) {
            visible_launchers.clear ();
            if (installer != null) {
                visible_launchers.add_all (installer.ordered_launchers (ctx.launcher_manifests));
            } else {
                visible_launchers.add_all (ctx.launcher_manifests);
            }
            var items = new Gee.ArrayList<Widgets.OptionListItem> ();
            var none = new Widgets.OptionListItem ();
            none.label = _("None");
            items.add (none);
            var default_index = 0;
            var installer_default = installer != null ? installer.default_launcher_id : "";
            for (int i = 0; i < visible_launchers.size; i++) {
                var launcher = visible_launchers[i];
                var item = manifest_option (launcher);
                item.is_default = launcher.id == installer_default
                    || (installer_default == "" && launcher.is_default);
                items.add (item);
                if (item.is_default) default_index = i + 1;
            }
            launcher_combo.set_items (items);
            launcher_combo.selected = default_index;
            update_notes ();
        }

        private Models.LauncherManifest? selected_launcher () {
            var index = (int) launcher_combo.selected - 1;
            if (index < 0 || index >= visible_launchers.size) return null;
            return visible_launchers[index];
        }

        private Gee.HashMap<string, string> message_vars_for_draft () {
            var installer = selected_installer ();
            var region = "";
            if (installer != null && region_combo.visible) {
                var ri = (int) region_combo.selected;
                if (ri >= 0 && ri < installer.regions.size) region = installer.regions[ri].id;
            }
            return Runtime.message_vars_for_draft (installer, selected_launcher (), region);
        }

        private void update_notes () {
            if (notes == null) return;
            Widgets.PageChrome.clear_children (notes);
            var launcher = selected_launcher ();
            var spec = launcher != null ? (Models.BaseManifest) launcher : selected_installer ();
            if (spec == null) return;
            Widgets.Messages.fill (
                notes,
                spec.messages,
                message_vars_for_draft (),
                { Models.ManifestMessages.NEW_PREFIX }
            );
        }

        private void on_browse () {
            if (Widgets.Dialogs.FileDialogs.file_browse_blocked (ctx)) return;
            Widgets.Dialogs.FileDialogs.open_folder_dialog (
                get_root () as Gtk.Window,
                Widgets.Dialogs.FileDialogs.build_folder_dialog (_("Select Prefix Directory")),
                draft.path,
                (path) => {
                    draft.path = path;
                    draft.uri = File.new_for_path (path).get_uri () ?? "";
                    dir_row.subtitle = path;
                },
                (message) => ctx.show_toast (message)
            );
        }

        private void on_create () {
            var installer = selected_installer ();
            if (installer == null) {
                ctx.show_toast (_("No installer manifest is selected."));
                return;
            }
            draft.name = name_entry.text.strip ();
            draft.installer_id = installer.id;
            draft.set_runner_identity (runner_rows.runner_id (), runner_rows.variant_id ());
            draft.runner_version = runner_rows.version ();
            draft.large_address_aware = laa_row != null && patches_group != null && patches_group.visible && laa_row.active;
            draft.launcher_id = "";
            if (launcher_combo.visible && launcher_combo.selected > 0) {
                var li = (int) launcher_combo.selected - 1;
                if (li >= 0 && li < visible_launchers.size) draft.launcher_id = visible_launchers[li].id;
            }
            draft.region = "";
            if (region_combo.visible) {
                var ri = (int) region_combo.selected;
                if (ri >= 0 && ri < installer.regions.size) draft.region = installer.regions[ri].id;
            }
            draft.runtime_component_overrides.clear ();
            foreach (var entry in component_rows.entries) {
                if (!entry.value.visible) continue;
                var enabled = entry.value.enabled ();
                var version = entry.value.version ();
                if (enabled == null && version == "") continue;
                var ov = new Models.RuntimeComponentOverride ();
                ov.enabled = enabled;
                ov.version = version;
                draft.runtime_component_overrides[entry.key] = ov;
            }
            create_requested (draft);
        }

        private Widgets.OptionListItem manifest_option (Models.BaseManifest spec) {
            var item = new Widgets.OptionListItem ();
            item.label = spec.display_label ();
            item.recommended = spec.recommended;
            item.support = spec.support;
            return item;
        }
    }
}
