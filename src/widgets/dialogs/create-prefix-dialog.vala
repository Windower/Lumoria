namespace Lumoria.Widgets.Dialogs {

    public class CreatePrefixDialog : Adw.Dialog {
        public signal void prefix_created ();

        private Models.PrefixRegistry registry;
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Gee.ArrayList<Models.LauncherSpec> launcher_specs;

        private Adw.EntryRow name_entry;
        private Adw.ToastOverlay toast_overlay;
        private Adw.ActionRow dir_row;
        private OptionListRow runner_combo;
        private OptionListRow variant_combo;
        private OptionListRow sync_combo;
        private OptionListRow debug_combo;
        private OptionListRow wayland_combo;
        private OptionListRow laa_combo;
        private OptionListRow launcher_combo;
        private OptionListRow region_combo;
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
            this.runner_specs = runner_specs;
            this.launcher_specs = launcher_specs;
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

            general_content.append (general_group);

            if (Utils.EnvironmentInfo.is_gamescope ()) {
                var warn_group = SettingsShared.build_group (_("Warning"), 12, 12);
                var warn_row = new Adw.ActionRow ();
                warn_row.title = _("Prefix installation is disabled in gamescope sessions");
                warn_row.subtitle = _("Enter desktop mode to create and install a new prefix.");
                warn_group.add (warn_row);
                general_content.append (warn_group);
            }

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
            rebuild_variant_combo ();

            runner_content.append (runner_group);

            var runner_opts_group = SettingsShared.build_group (_("Runner Options"), 12, 12);

            sync_combo = RunnerSettingsShared.build_sync_override_combo ();
            runner_opts_group.add (sync_combo);

            wayland_combo = RunnerSettingsShared.build_wayland_combo ();
            runner_opts_group.add (wayland_combo);

            debug_combo = RunnerSettingsShared.build_debug_override_combo ();
            runner_opts_group.add (debug_combo);

            runner_content.append (runner_opts_group);

            SettingsShared.add_scrolled_settings_page (stack, runner_content, SettingsShared.PAGE_RUNNERS, _("Runner"));

            var game_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            if (launcher_specs.size > 0) {
                var launcher_group = SettingsShared.build_group (_("Launcher"), 12);
                var launcher_model = new Gtk.StringList (null);
                launcher_model.append (_("None"));
                int default_launcher = 0;
                for (int i = 0; i < launcher_specs.size; i++) {
                    launcher_model.append (launcher_specs[i].display_label ());
                    if (launcher_specs[i].is_default) default_launcher = i + 1;
                }
                launcher_combo = new OptionListRow ();
                launcher_combo.title = _("Launcher");
                launcher_combo.model = launcher_model;
                launcher_combo.selected = default_launcher;
                launcher_group.add (launcher_combo);
                game_content.append (launcher_group);
            }

            var region_group = SettingsShared.build_group (_("Region"), 12, 12);
            var region_model = new Gtk.StringList (null);
            region_model.append (_("US (North America)"));
            region_model.append (_("EU (Europe)"));
            region_model.append (_("JP (Japan)"));
            region_combo = new OptionListRow ();
            region_combo.title = _("Region");
            region_combo.model = region_model;
            region_combo.selected = 0;
            region_group.add (region_combo);
            game_content.append (region_group);

            var component_specs = Models.ComponentSpec.load_all_from_resource ();
            if (component_specs.size > 0) {
                var components_group = SettingsShared.build_group (_("Runtime Components"), 12, 12);
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
                game_content.append (components_group);
            }

            if (Utils.Preferences.instance ().experimental_features) {
                var patches_group = SettingsShared.build_group (_("Patches"), 12, 12);
                var laa_default = Utils.Preferences.instance ().large_address_aware ? _("enabled") : _("disabled");
                laa_combo = SettingsShared.build_toggle_override_combo (
                    _("Large Address Aware"),
                    null,
                    laa_default
                );
                patches_group.add (laa_combo);
                game_content.append (patches_group);
            }

            SettingsShared.add_scrolled_settings_page (stack, game_content, SettingsShared.PAGE_LAUNCH, _("Game"));

            var advanced_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var post_install_group = SettingsShared.build_group (_("Post Install"), 12);

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
            rebuild_variant_combo ();
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
            bool? large_address_aware = laa_combo != null
                ? ((ToggleOverrideState) laa_combo.selected).to_nullable_bool ()
                : null;

            var launcher_id = "";
            if (launcher_combo != null && launcher_combo.selected > 0) {
                var li = (int) launcher_combo.selected - 1;
                if (li >= 0 && li < launcher_specs.size) {
                    launcher_id = launcher_specs[li].id;
                }
            }

            string[] region_values = { "us", "eu", "jp" };
            var region = region_combo != null && region_combo.selected < region_values.length
                ? region_values[region_combo.selected]
                : "us";

            var runner_version = Utils.Preferences.resolve_version (runner_id, "");

            var entry = new Models.PrefixEntry ();
            entry.id = id;
            entry.name = name;
            entry.path = resolved;
            entry.uri = selected_uri;
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
            prefix_created ();

            var parent_win = (Gtk.Window) ((Gtk.Widget) this).get_root ();
            close ();

            var install_opts = new Runtime.InstallOptions ();
            install_opts.prefix_path = resolved;
            install_opts.prefix_entry = entry;
            install_opts.runner_id = runner_id;
            install_opts.runner_version = runner_version;
            install_opts.variant_id = variant_id;
            install_opts.wine_arch = "";
            install_opts.wine_debug = wine_debug;
            install_opts.launcher_id = launcher_id;
            install_opts.wine_wayland = wine_wayland;
            install_opts.post_install_spec_path = selected_post_install_path;
            install_opts.post_install_spec_uri = selected_post_install_uri;

            var install_dlg = new InstallDialog ();
            install_dlg.install_completed.connect ((success) => {
                if (success) {
                    prefix_created ();
                }
            });
            install_dlg.prefix_delete_requested.connect (() => {
                var reg_entry = registry.by_path (resolved);
                if (reg_entry != null) {
                    var idx = registry.prefixes.index_of (reg_entry);
                    if (idx >= 0) registry.remove_at (idx);
                }
                Utils.remove_recursive (resolved);
                prefix_created ();
            });
            install_dlg.present (parent_win);
            install_dlg.start_install (install_opts);
        }
    }
}
