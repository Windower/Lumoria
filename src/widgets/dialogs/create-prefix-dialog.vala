namespace Lumoria.Widgets.Dialogs {

    public class CreatePrefixDialog : Adw.Dialog {
        public signal void prefix_created (string prefix_id);

        private Models.PrefixRegistry registry;
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Gee.ArrayList<Models.LauncherSpec> launcher_specs;
        private Gee.ArrayList<Models.InstallerSpec> installer_specs;
        private Gee.ArrayList<Models.LauncherSpec> visible_launcher_specs;

        private Adw.EntryRow name_entry;
        private Adw.ToastOverlay toast_overlay;
        private Adw.ActionRow dir_row;
        private OptionListRow runner_combo;
        private OptionListRow variant_combo;
        private Adw.ActionRow version_row;
        private Gtk.Widget latest_runner_warning;
        private OptionListRow sync_combo;
        private OptionListRow debug_combo;
        private OptionListRow wayland_combo;
        private OptionListRow laa_combo;
        private OptionListRow launcher_combo;
        private OptionListRow region_combo;
        private OptionListRow installer_combo;
        private Adw.PreferencesGroup? launcher_group;
        private Adw.PreferencesGroup? region_group;
        private Adw.PreferencesGroup? patches_group;
        private Adw.ActionRow post_install_row;
        private Gtk.Button clear_post_install_btn;
        private Gtk.Button create_btn;
        private Gee.ArrayList<Models.RunnerVariant> visible_variants;
        private Gee.HashMap<string, OptionListRow> component_mode_rows;

        private string selected_path;
        private string selected_uri = "";
        private string selected_post_install_path = "";
        private string selected_post_install_uri = "";
        private string selected_post_install_id = "";
        private string selected_post_install_name = "";
        private string selected_runner_version = "default";
        private string selected_runner_version_label = "";

        public CreatePrefixDialog (
            Gtk.Window parent,
            Models.PrefixRegistry registry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs
        ) {
            Object (
                title: _("Set Up Prefix"),
                content_width: 640,
                content_height: 600
            );
            this.registry = registry;
            this.runner_specs = Models.RunnerSpec.filter_for_environment (runner_specs, Utils.is_sandboxed ());
            this.launcher_specs = launcher_specs;
            this.installer_specs = Models.SpecRepository.shared ().installers;
            this.visible_launcher_specs = new Gee.ArrayList<Models.LauncherSpec> ();
            visible_variants = new Gee.ArrayList<Models.RunnerVariant> ();
            component_mode_rows = new Gee.HashMap<string, OptionListRow> ();

            selected_path = Utils.next_available_prefix_path (registry);
            build_ui ();

            var pw = parent.get_width ();
            var ph = parent.get_height ();
            if (pw > 0 && ph > 0) {
                content_width = (int) (pw * 0.75).clamp (580, 900);
                content_height = (int) (ph * 0.85).clamp (550, 1000);
            }
        }

        private void build_ui () {
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = true;
            header.show_start_title_buttons = false;
            toolbar.add_top_bar (header);

            var stack = new Adw.ViewStack ();
            stack.vexpand = true;

            var general_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var general_group = SettingsShared.build_group (_("General"), 12);

            dir_row = new Adw.ActionRow ();
            dir_row.title = _("Directory");
            dir_row.subtitle = selected_path;
            dir_row.subtitle_selectable = true;
            var browse_btn = new Gtk.Button.with_label (_("Browse\u2026"));
            browse_btn.valign = Gtk.Align.CENTER;
            browse_btn.clicked.connect (on_browse);
            dir_row.add_suffix (browse_btn);
            dir_row.activatable_widget = browse_btn;
            general_group.add (dir_row);

            if (Utils.is_sandboxed ()) {
                var sandbox_row = new Adw.ActionRow ();
                sandbox_row.title = _("Default location is inside the app sandbox");
                sandbox_row.subtitle = _("Use Browse to select an external directory.");
                general_group.add (sandbox_row);
            }

            name_entry = new Adw.EntryRow ();
            name_entry.title = _("Name");
            general_group.add (name_entry);

            var installer_model = new Gtk.StringList (null);
            foreach (var spec in installer_specs) {
                installer_model.append (spec.display_label ());
            }
            installer_combo = new OptionListRow ();
            installer_combo.title = _("Installation");
            installer_combo.model = installer_model;
            installer_combo.selected = default_installer_index ();
            installer_combo.notify["selected"].connect (update_installer_ui);
            general_group.add (installer_combo);

            general_content.append (general_group);

            if (Utils.EnvironmentInfo.is_gamescope ()) {
                general_content.append (SettingsShared.build_warning_card (
                    _("Prefix installation is disabled in gamescope sessions. Enter desktop mode to create and install a new prefix.")
                ));
            }

            if (launcher_specs.size > 0) {
                launcher_group = SettingsShared.build_group (_("Launcher"), 12);
                var launcher_model = new Gtk.StringList (null);
                launcher_model.append (_("None"));
                launcher_combo = new OptionListRow ();
                launcher_combo.title = _("Launcher");
                launcher_combo.model = launcher_model;
                launcher_group.add (launcher_combo);
                general_content.append (launcher_group);
            }

            region_group = SettingsShared.build_group (_("Region"), 12, 12);
            var region_model = new Gtk.StringList (null);
            region_combo = new OptionListRow ();
            region_combo.title = _("Region");
            region_combo.model = region_model;
            region_group.add (region_combo);
            general_content.append (region_group);

            SettingsShared.add_scrolled_settings_page (stack, general_content, SettingsShared.PAGE_GENERAL, _("General"));

            var runner_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var runner_group = SettingsShared.build_group (_("Wine Runner"), 12);

            var runner_model = RunnerSettingsShared.build_runner_model (runner_specs);
            runner_combo = new OptionListRow ();
            runner_combo.title = _("Runner");
            runner_combo.model = runner_model;
            runner_combo.selected = RunnerSettingsShared.select_runner_index (runner_specs);
            runner_combo.notify["selected"].connect (on_runner_changed);
            runner_group.add (runner_combo);

            variant_combo = new OptionListRow ();
            variant_combo.title = _("Variant");
            runner_group.add (variant_combo);

            version_row = new Adw.ActionRow ();
            version_row.title = _("Version");
            version_row.activatable = true;
            version_row.activated.connect (open_version_picker);
            version_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            runner_group.add (version_row);
            rebuild_variant_combo ();
            update_version_row ();
            variant_combo.notify["selected"].connect (on_variant_changed);

            runner_content.append (runner_group);

            latest_runner_warning = SettingsShared.build_warning_card (
                _("Latest keeps this prefix on the newest runner automatically. Updates may change compatibility or behavior without notice.")
            );
            latest_runner_warning.visible = false;
            runner_content.append (latest_runner_warning);
            update_latest_runner_warning ();

            var runner_opts_group = SettingsShared.build_group (_("Runner Options"), 12, 12);

            wayland_combo = RunnerSettingsShared.build_wayland_combo ();
            runner_opts_group.add (wayland_combo);

            sync_combo = RunnerSettingsShared.build_sync_override_combo ();
            runner_opts_group.add (sync_combo);

            debug_combo = RunnerSettingsShared.build_debug_override_combo ();
            RunnerSettingsShared.update_debug_combo_logging_state (
                debug_combo,
                Utils.Preferences.instance ().keep_runtime_logs
            );
            runner_opts_group.add (debug_combo);

            runner_content.append (runner_opts_group);

            var component_specs = Models.SpecRepository.shared ().components;
            if (component_specs.size > 0) {
                var components_group = SettingsShared.build_group (_("Runtime Components"), 12, 12);
                components_group.add (SettingsShared.build_warning_card (
                    _("Changing runtime components can alter the default prefix behavior."),
                    8,
                    8,
                    8,
                    8
                ));
                foreach (var spec in component_specs) {
                    var default_label = Utils.Preferences.instance ().default_component_enabled (spec.id)
                        ? _("enabled")
                        : _("disabled");
                    var mode_row = SettingsShared.build_toggle_override_combo (
                        spec.display_label (),
                        null,
                        default_label
                    );
                    component_mode_rows[spec.id] = mode_row;
                    components_group.add (mode_row);
                }
                runner_content.append (components_group);
            }

            SettingsShared.add_scrolled_settings_page (stack, runner_content, SettingsShared.PAGE_RUNNERS, _("Runner"));

            var advanced_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var post_install_group = SettingsShared.build_group (_("Post Install"), 12);
            post_install_group.add (SettingsShared.build_warning_card (
                _("Post-install specs can make breaking changes to your prefix. Use at your own risk."),
                8,
                8,
                8,
                8
            ));

            post_install_row = new Adw.ActionRow ();
            post_install_row.title = _("Post Install Spec");
            post_install_row.subtitle = _("None selected");
            post_install_row.subtitle_selectable = true;

            var post_install_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            post_install_actions.valign = Gtk.Align.CENTER;

            clear_post_install_btn = new Gtk.Button.with_label (_("Clear"));
            clear_post_install_btn.clicked.connect (clear_post_install_spec);
            clear_post_install_btn.visible = false;
            post_install_actions.append (clear_post_install_btn);

            var browse_post_install_btn = new Gtk.Button.with_label (_("Browse\u2026"));
            browse_post_install_btn.clicked.connect (on_browse_post_install_spec);
            post_install_actions.append (browse_post_install_btn);

            post_install_row.add_suffix (post_install_actions);
            post_install_row.activatable_widget = browse_post_install_btn;
            post_install_group.add (post_install_row);
            advanced_content.append (post_install_group);

            if (Utils.Preferences.instance ().experimental_features) {
                patches_group = SettingsShared.build_group (_("Patches"), 12, 12);
                var laa_default = Utils.Preferences.instance ().large_address_aware ? _("enabled") : _("disabled");
                laa_combo = SettingsShared.build_toggle_override_combo (
                    _("Large Address Aware"),
                    null,
                    laa_default
                );
                patches_group.add (laa_combo);
                advanced_content.append (patches_group);
            }

            SettingsShared.add_scrolled_settings_page (stack, advanced_content, SettingsShared.PAGE_ADVANCED, _("Advanced"));

            var switcher_bar = new Adw.ViewSwitcherBar ();
            switcher_bar.stack = stack;
            switcher_bar.reveal = true;

            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            body.append (switcher_bar);
            body.append (stack);
            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.child = body;
            toolbar.content = toast_overlay;

            create_btn = new Gtk.Button.with_label (_("Create"));
            create_btn.add_css_class ("suggested-action");
            create_btn.margin_start = 12;
            create_btn.margin_end = 12;
            create_btn.margin_top = 8;
            create_btn.margin_bottom = 8;
            create_btn.clicked.connect (on_create);
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                create_btn.sensitive = false;
            }
            toolbar.add_bottom_bar (create_btn);

            this.child = toolbar;
            update_installer_ui ();
        }

        private Models.InstallerSpec? selected_installer () {
            if (installer_combo == null) return null;
            var index = (int) installer_combo.selected;
            if (index < 0 || index >= installer_specs.size) return null;
            return installer_specs[index];
        }

        private uint default_installer_index () {
            for (int i = 0; i < installer_specs.size; i++) {
                if (installer_specs[i].id == "ffxi") return (uint) i;
            }
            return 0;
        }

        private void rebuild_region_combo () {
            if (region_combo == null) return;
            var model = new Gtk.StringList (null);
            var installer = selected_installer ();
            uint selected = 0;
            if (installer != null) {
                for (int i = 0; i < installer.regions.size; i++) {
                    var region = installer.regions[i];
                    model.append (region.name);
                    if (region.id == installer.effective_default_region_id ()) {
                        selected = (uint) i;
                    }
                }
            }
            region_combo.model = model;
            region_combo.selected = selected;
        }

        private void rebuild_launcher_combo () {
            if (launcher_combo == null) return;
            visible_launcher_specs.clear ();
            var installer = selected_installer ();
            foreach (var launcher in launcher_specs) {
                if (installer == null || installer.supports_launcher (launcher.id)) {
                    visible_launcher_specs.add (launcher);
                }
            }

            var model = new Gtk.StringList (null);
            model.append (_("None"));
            var default_index = 0;
            var installer_default = installer != null ? installer.default_launcher_id : "";
            for (int i = 0; i < visible_launcher_specs.size; i++) {
                var launcher = visible_launcher_specs[i];
                model.append (launcher.display_label ());
                if (launcher.id == installer_default
                    || (installer_default == "" && launcher.is_default)) {
                    default_index = i + 1;
                }
            }
            launcher_combo.model = model;
            launcher_combo.selected = default_index;
        }

        private void update_installer_ui () {
            var installer = selected_installer ();
            rebuild_region_combo ();
            rebuild_launcher_combo ();
            var has_launchers = installer != null && installer.launcher_ids.size > 0;
            var has_regions = installer != null && installer.regions.size > 0;
            var has_patches = installer != null && installer.patches.size > 0;
            if (launcher_group != null) launcher_group.visible = has_launchers;
            if (region_group != null) region_group.visible = has_regions;
            if (launcher_combo != null) launcher_combo.visible = has_launchers;
            if (region_combo != null) region_combo.visible = has_regions;
            if (patches_group != null) patches_group.visible = has_patches;
            if (laa_combo != null) {
                var patch = installer_patch_for_setting (
                    installer, "large_address_aware"
                );
                laa_combo.visible = patch != null;
                if (patch != null) laa_combo.title = patch.name;
            }
            foreach (var component in Models.SpecRepository.shared ().components) {
                if (!component_mode_rows.has_key (component.id)) continue;
                component_mode_rows[component.id].visible =
                    installer != null && component.supports_installer (installer.id);
            }
        }

        private bool installer_supports_patch_setting (
            Models.InstallerSpec? installer,
            string setting
        ) {
            return installer_patch_for_setting (installer, setting) != null;
        }

        private Models.InstallerPatch? installer_patch_for_setting (
            Models.InstallerSpec? installer,
            string setting
        ) {
            if (installer == null) return null;
            foreach (var patch in installer.patches) {
                if (patch.setting == setting) return patch;
            }
            return null;
        }

        private void rebuild_variant_combo () {
            RunnerSettingsShared.rebuild_variant_combo (
                runner_combo,
                variant_combo,
                runner_specs,
                visible_variants
            );
        }

        private void on_runner_changed () {
            selected_runner_version = "default";
            selected_runner_version_label = "";
            rebuild_variant_combo ();
            update_version_row ();
        }

        private void on_variant_changed () {
            selected_runner_version = "default";
            selected_runner_version_label = "";
            update_version_row ();
        }

        private void open_version_picker () {
            var runner = selected_runner ();
            if (runner == null) return;
            var picker = new RunnerVersionPickerDialog (
                runner,
                selected_variant (),
                selected_runner_version
            );
            picker.version_selected.connect ((label, value) => {
                selected_runner_version = value;
                selected_runner_version_label = label;
                update_version_row ();
            });
            picker.present ((Gtk.Widget) this);
        }

        private Models.RunnerSpec? selected_runner () {
            var sel = (int) runner_combo.selected;
            if (sel < 0 || sel >= runner_specs.size) return null;
            return runner_specs[sel];
        }

        private Models.RunnerVariant? selected_variant () {
            if (visible_variants.size == 0) return null;
            var sel = (int) variant_combo.selected;
            if (sel < 0 || sel >= visible_variants.size) return visible_variants[0];
            return visible_variants[sel];
        }

        private void update_version_row () {
            if (selected_runner_version_label != "") {
                version_row.subtitle = selected_runner_version_label;
                update_latest_runner_warning ();
                return;
            }
            version_row.subtitle = RunnerSettingsShared.version_label_for_value (
                selected_runner (),
                selected_runner_version
            );
            update_latest_runner_warning ();
        }

        private void update_latest_runner_warning () {
            if (latest_runner_warning == null) return;
            latest_runner_warning.visible = RunnerSettingsShared.is_effective_latest (
                selected_runner (), selected_runner_version
            );
        }

        private void on_browse () {
            if (SettingsShared.file_browse_blocked (toast_overlay)) return;
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Choose prefix directory");
            dialog.modal = true;
            dialog.initial_folder = File.new_for_path (Utils.suggested_prefix_dir ());

            dialog.select_folder.begin (null, null, (obj, res) => {
                try {
                    var file = dialog.select_folder.end (res);
                    if (file == null) return;
                    selected_uri = file.get_uri ();
                    var path = file.get_path ();
                    if (path != null && path != "") {
                        selected_path = path;
                    }
                    dir_row.subtitle = selected_path;
                    if (name_entry.text.strip () == "") {
                        name_entry.text = Path.get_basename (selected_path);
                    }
                } catch (Error e) {
                    warning ("Failed to select prefix directory: %s", e.message);
                }
            });
        }

        private void on_browse_post_install_spec () {
            if (SettingsShared.file_browse_blocked (toast_overlay)) return;

            var filter = new Gtk.FileFilter ();
            filter.name = _("JSON Specs");
            filter.add_mime_type ("application/json");
            filter.add_pattern ("*.json");

            var dialog = SettingsShared.build_file_dialog (_("Choose post install spec"), filter);
            dialog.open.begin (null, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file == null) return;
                    var path = file.get_path ();
                    if (path == null || path == "") return;

                    var spec = Models.PostInstallSpec.load_from_file (path);
                    selected_post_install_path = path;
                    selected_post_install_uri = file.get_uri ();
                    selected_post_install_id = spec.id;
                    selected_post_install_name = spec.display_label ();
                    update_post_install_row ();
                } catch (Error e) {
                    clear_post_install_spec ();
                    SettingsShared.present_alert (
                        this,
                        _("Invalid Post Install Spec"),
                        e.message
                    );
                }
            });
        }

        private void clear_post_install_spec () {
            selected_post_install_path = "";
            selected_post_install_uri = "";
            selected_post_install_id = "";
            selected_post_install_name = "";
            update_post_install_row ();
        }

        private void update_post_install_row () {
            if (selected_post_install_path == "") {
                post_install_row.subtitle = _("None selected");
                clear_post_install_btn.visible = false;
                return;
            }

            var label = selected_post_install_name != "" ? selected_post_install_name : Path.get_basename (selected_post_install_path);
            post_install_row.subtitle = "%s\n%s".printf (label, selected_post_install_path);
            clear_post_install_btn.visible = true;
        }

        private void on_create () {
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                SettingsShared.present_alert (this,
                    _("Install Disabled In Gamescope"),
                    _("Prefix installation is disabled while running in a gamescope session."));
                return;
            }

            var resolved = selected_path;
            if (Utils.is_prefixes_root_path (resolved)) {
                SettingsShared.present_alert (this,
                    _("Invalid Prefix Directory"),
                    _("You cannot install directly into the prefixes root.\n\nChoose a subdirectory inside:\n%s").printf (Utils.default_prefix_dir ()));
                return;
            }

            if (registry.by_path (resolved) != null) {
                SettingsShared.present_alert (this, _("Already Registered"), _("This path is already in your prefix list."));
                return;
            }

            var drive_c = Path.build_filename (resolved, "drive_c");
            var wine_prefix_drive_c = Path.build_filename (resolved, "pfx", "drive_c");
            if (FileUtils.test (drive_c, FileTest.EXISTS) ||
                FileUtils.test (wine_prefix_drive_c, FileTest.EXISTS)) {
                SettingsShared.present_alert (this,
                    _("Prefix Exists"),
                    _("A Wine prefix already exists at:\n%s\n\nChoose a different path or remove it first.").printf (resolved));
                return;
            }

            var name = name_entry.text.strip ();
            if (name == "") name = Path.get_basename (resolved);
            var id = Utils.slugify (name);
            if (id == "") id = Utils.slugify (resolved);

            if (registry.by_id (id) != null) {
                SettingsShared.present_alert (this,
                    _("Name Already Used"),
                    _("A prefix named \"%s\" already exists. Choose a different name.").printf (name));
                return;
            }

            var runner_id = "";
            var sel = (int) runner_combo.selected;
            if (sel >= 0 && sel < runner_specs.size) {
                var selected_runner = runner_specs[sel];
                runner_id = selected_runner.id;
                if (selected_runner.selectable_variants (Utils.is_sandboxed ()).size == 0) {
                    SettingsShared.present_alert (this,
                        _("Runner Not Supported"),
                        _("The selected runner has no compatible variants in this environment."));
                    return;
                }
            } else {
                SettingsShared.present_alert (this,
                    _("No Compatible Runner"),
                    _("No Wine runners are compatible with this environment."));
                return;
            }

            var variant_id = "";
            if (variant_combo.visible) {
                var vi = (int) variant_combo.selected;
                if (vi >= 0 && vi < visible_variants.size) {
                    variant_id = visible_variants[vi].id;
                }
            }

            var sync_mode = RunnerSettingsShared.sync_override_value_for_index (sync_combo.selected);
            var wine_debug = RunnerSettingsShared.debug_override_value_for_index (debug_combo.selected);
            var wine_wayland = RunnerSettingsShared.wayland_value_for_index (wayland_combo.selected);
            var installer = selected_installer ();
            if (installer == null) {
                SettingsShared.present_alert (
                    this,
                    _("Invalid Installation"),
                    _("No installer specification is selected.")
                );
                return;
            }
            bool? large_address_aware =
                installer_supports_patch_setting (installer, "large_address_aware")
                && laa_combo != null
                ? ((ToggleOverrideState) laa_combo.selected).to_nullable_bool ()
                : null;

            var launcher_id = "";
            if (launcher_combo != null && launcher_combo.visible && launcher_combo.selected > 0) {
                var li = (int) launcher_combo.selected - 1;
                if (li >= 0 && li < visible_launcher_specs.size) {
                    launcher_id = visible_launcher_specs[li].id;
                }
            }

            var region = "";
            if (region_combo != null && region_combo.visible) {
                var region_index = (int) region_combo.selected;
                if (region_index >= 0 && region_index < installer.regions.size) {
                    region = installer.regions[region_index].id;
                } else if (installer.effective_default_region_id () != "") {
                    region = installer.effective_default_region_id ();
                }
            }

            var runner_version = selected_runner_version;

            var entry = new Models.PrefixEntry ();
            entry.id = id;
            entry.name = name;
            entry.path = resolved;
            entry.uri = selected_uri;
            entry.path_portal = Utils.portal_path_ref_from_path_uri (resolved, selected_uri);
            entry.installer_id = installer.id;
            entry.runner_id = runner_id;
            entry.runner_version = runner_version;
            entry.variant_id = variant_id;
            entry.wine_debug = wine_debug;
            entry.wine_wayland = wine_wayland;
            entry.sync_mode = sync_mode;
            entry.launcher_id = launcher_id;
            entry.region = region;
            entry.large_address_aware = large_address_aware;
            foreach (var mode_entry in component_mode_rows.entries) {
                var spec_id = mode_entry.key;
                var selected_mode = (ToggleOverrideState) ((int) mode_entry.value.selected);
                if (selected_mode == ToggleOverrideState.INHERIT) continue;
                var ov = new Models.RuntimeComponentOverride ();
                ov.enabled = selected_mode.to_nullable_bool ();
                entry.runtime_component_overrides[spec_id] = ov;
            }
            if (selected_post_install_path != "") {
                var post_install = new Models.PrefixPostInstallSpec ();
                post_install.original_path = selected_post_install_path;
                post_install.original_uri = selected_post_install_uri;
                post_install.spec_id = selected_post_install_id;
                post_install.name = selected_post_install_name;
                entry.post_install_spec = post_install;
            }

            registry.add_prefix (entry);
            prefix_created (entry.id);

            var parent_win = (Gtk.Window) ((Gtk.Widget) this).get_root ();
            close ();

            var install_opts = new Runtime.InstallOptions ();
            install_opts.prefix_path = resolved;
            install_opts.prefix_entry = entry;
            install_opts.post_install_spec_path = selected_post_install_path;
            install_opts.post_install_spec_uri = selected_post_install_uri;

            var install_dlg = new InstallDialog ();
            install_dlg.install_completed.connect ((success) => {
                if (success) {
                    prefix_created (entry.id);
                }
            });
            install_dlg.prefix_delete_requested.connect (() => {
                var reg_entry = registry.by_path (resolved);
                if (reg_entry != null) {
                    var idx = registry.prefixes.index_of (reg_entry);
                    if (idx >= 0) registry.remove_at (idx);
                }
                Utils.remove_recursive (resolved);
                prefix_created ("");
            });
            install_dlg.present (parent_win);
            install_dlg.start_install (install_opts);
        }
    }
}
