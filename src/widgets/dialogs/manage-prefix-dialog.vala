namespace Lumoria.Widgets.Dialogs {

    public class ManagePrefixDialog : Adw.Dialog {
        public signal void saved ();
        public signal void removed ();

        private delegate void CustomExecutableSelectedCallback (string path);

        private Models.PrefixRegistry registry;
        private int prefix_index;
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Gee.ArrayList<Models.LauncherSpec> launcher_specs;
        private Models.InstallerSpec? installer_spec;

        private OptionListRow runner_combo;
        private OptionListRow variant_combo;
        private Adw.ActionRow version_row;
        private Gtk.Widget latest_runner_warning;
        private OptionListRow sync_combo;
        private OptionListRow debug_combo;
        private OptionListRow wayland_combo;
        private OptionListRow wayland_monitor_combo;
        private OptionListRow laa_combo;
        private Adw.SwitchRow advanced_dxvk_row;
        private Gtk.Box dxvk_config_box;
        private Adw.SwitchRow dxvk_show_fps_row;
        private Adw.SwitchRow dxvk_hide_integrated_graphics_row;
        private Adw.EntryRow dxvk_anisotropy_row;
        private Adw.EntryRow dxvk_max_frame_rate_row;
        private Adw.EntryRow dxvk_sync_interval_row;
        private Gtk.TextBuffer dxvk_custom_buffer;

        private Gee.ArrayList<Models.RunnerVariant> visible_variants;
        private Gee.ArrayList<string> wayland_monitor_values;
        private Gee.HashMap<string, OptionListRow> component_mode_rows;
        private OptionListRow entrypoint_combo;
        private Gee.ArrayList<string> entrypoint_values;
        private Adw.ActionRow prelaunch_row;
        private string prelaunch_script_path;
        private Gee.ArrayList<Models.Entrypoint> custom_entries;
        private Adw.PreferencesGroup custom_entries_group;
        private Gee.ArrayList<Gtk.Widget> custom_entry_rows;
        private Lumoria.Widgets.EnvVarsEditor prefix_env_editor;
        private Adw.EntryRow prefix_dll_row;
        private Gtk.Label env_validation_label;
        private Adw.ToastOverlay toast_overlay;
        private Gtk.Window host_window;
        private ulong host_width_handler = 0;
        private ulong host_height_handler = 0;
        private Services.DynamicLauncherService shortcut_service;
        private Services.SteamShortcutService steam_shortcut_service;
        private Gtk.Box shortcuts_content;
        private Gtk.Box packages_content;
        private Gee.HashMap<string, Models.RedistSpec> package_specs;
        private Gee.HashMap<string, Gtk.Widget> package_installed_rows;
        private Gee.HashMap<string, Gtk.Widget> package_available_rows;
        private Adw.PreferencesGroup packages_installed_group;
        private Adw.PreferencesGroup packages_available_group;
        private Adw.ViewStack packages_inner_stack;
        private Adw.ViewStackPage packages_installed_page;
        private Adw.ViewStackPage packages_available_page;
        private Gtk.ToggleButton packages_installed_button;
        private Gtk.ToggleButton packages_available_button;
        private Gtk.Widget packages_installed_empty_row;
        private Gtk.Widget packages_available_empty_row;
        private int packages_installed_count = 0;
        private int packages_available_count = 0;
        private string packages_visible_page = "installed";
        private string selected_runner_version = "default";
        private string selected_runner_version_label = "";

        public ManagePrefixDialog (
            Gtk.Window parent,
            Models.PrefixRegistry registry,
            int prefix_index,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs
        ) {
            Object (
                title: _("Manage Prefix"),
                content_width: 540,
                content_height: 600
            );
            this.host_window = parent;
            this.registry = registry;
            this.prefix_index = prefix_index;
            this.runner_specs = Models.RunnerSpec.filter_for_environment (runner_specs, Utils.is_sandboxed ());
            this.launcher_specs = launcher_specs;
            this.installer_spec = Models.SpecRepository.shared ().installer (
                registry.prefixes[prefix_index].installer_id
            );
            update_dialog_size ();
            bind_host_size ();
            selected_runner_version = registry.prefixes[prefix_index].runner_version != ""
                ? registry.prefixes[prefix_index].runner_version
                : "default";
            visible_variants = new Gee.ArrayList<Models.RunnerVariant> ();
            wayland_monitor_values = new Gee.ArrayList<string> ();
            component_mode_rows = new Gee.HashMap<string, OptionListRow> ();
            entrypoint_values = new Gee.ArrayList<string> ();
            shortcut_service = new Services.DynamicLauncherService ();
            steam_shortcut_service = new Services.SteamShortcutService ();
            build_ui ();
        }

        ~ManagePrefixDialog () {
            unbind_host_size ();
        }

        private void bind_host_size () {
            host_width_handler = host_window.notify["width"].connect (() => update_dialog_size ());
            host_height_handler = host_window.notify["height"].connect (() => update_dialog_size ());
            closed.connect (() => unbind_host_size ());
        }

        private void unbind_host_size () {
            if (host_width_handler != 0) {
                host_window.disconnect (host_width_handler);
                host_width_handler = 0;
            }
            if (host_height_handler != 0) {
                host_window.disconnect (host_height_handler);
                host_height_handler = 0;
            }
        }

        private void update_dialog_size () {
            var pw = host_window.get_width ();
            var ph = host_window.get_height ();
            if (pw <= 0 || ph <= 0) return;
            content_width = (int) (pw * 0.9).clamp (540, 1200);
            content_height = (int) (ph * 0.92).clamp (600, 1100);
        }

        private void build_ui () {
            var entry = registry.prefixes[prefix_index];
            var is_gamescope = Utils.EnvironmentInfo.is_gamescope ();

            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = true;
            header.show_start_title_buttons = false;

            toolbar.add_top_bar (header);

            var stack = new Adw.ViewStack ();
            stack.vexpand = true;

            var general_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var info_group = SettingsShared.build_group (_("General"), 12);

            var name_row = new Adw.ActionRow ();
            name_row.title = _("Name");
            name_row.subtitle = entry.display_name ();
            info_group.add (name_row);

            var path_row = new Adw.ActionRow ();
            path_row.title = _("Path");
            path_row.subtitle = entry.resolved_path ();
            path_row.subtitle_selectable = true;
            info_group.add (path_row);

            var installer_row = new Adw.ActionRow ();
            installer_row.title = _("Installation");
            installer_row.subtitle = installer_spec != null
                ? installer_spec.display_label ()
                : _("Unknown installer: %s").printf (entry.installer_id);
            info_group.add (installer_row);

            var default_row = new Adw.ActionRow ();
            default_row.title = _("Quick Launch");
            default_row.subtitle = _("Launched from the play button at the bottom of the window");
            var is_already_default = registry.is_default (entry);
            var default_btn = new Gtk.Button.with_label (is_already_default ? _("Quick Launch") : _("Set as Quick Launch"));
            default_btn.valign = Gtk.Align.CENTER;
            default_btn.sensitive = !is_already_default;
            default_btn.clicked.connect (() => {
                registry.default_prefix_id = entry.id;
                default_btn.label = _("Quick Launch");
                default_btn.sensitive = false;
                saved ();
            });
            default_row.add_suffix (default_btn);
            default_row.activatable_widget = default_btn;
            info_group.add (default_row);

            general_content.append (info_group);

            custom_entries = new Gee.ArrayList<Models.Entrypoint> ();
            foreach (var ep in entry.custom_entrypoints) {
                var copy = new Models.Entrypoint ();
                copy.id = ep.id;
                copy.name = ep.name;
                copy.exe = ep.exe;
                copy.exe_portal = ep.exe_portal;
                copy.args = new Gee.ArrayList<string> ();
                copy.args.add_all (ep.args);
                copy.prelaunch_script = ep.prelaunch_script;
                copy.prelaunch_script_portal = ep.prelaunch_script_portal;
                copy.component_overrides = new Gee.HashMap<string, Models.RuntimeComponentOverride> ();
                foreach (var ov in ep.component_overrides.entries) {
                    var ov_copy = new Models.RuntimeComponentOverride ();
                    ov_copy.enabled = ov.value.enabled;
                    ov_copy.version = ov.value.version;
                    ov_copy.system_env = new Gee.HashMap<string, string> ();
                    foreach (var env in ov.value.system_env.entries) {
                        ov_copy.system_env[env.key] = env.value;
                    }
                    copy.component_overrides[ov.key] = ov_copy;
                }
                copy.runtime_dll_overrides = new Gee.HashMap<string, string> ();
                foreach (var dll in ep.runtime_dll_overrides.entries) {
                    copy.runtime_dll_overrides[dll.key] = dll.value;
                }
                copy.runtime_env_overrides = new Gee.HashMap<string, string> ();
                foreach (var env in ep.runtime_env_overrides.entries) {
                    copy.runtime_env_overrides[env.key] = env.value;
                }
                custom_entries.add (copy);
            }
            custom_entry_rows = new Gee.ArrayList<Gtk.Widget> ();

            var launch_group = SettingsShared.build_group (_("Default Launch Entrypoint"), 12);

            entrypoint_combo = new OptionListRow ();
            entrypoint_combo.title = _("Entrypoint");
            entrypoint_combo.notify["selected"].connect (() => {
                update_entrypoint_combo_subtitle ();
                if (shortcuts_content != null) rebuild_shortcuts_ui ();
            });
            launch_group.add (entrypoint_combo);

            general_content.append (launch_group);

            custom_entries_group = SettingsShared.build_group (_("Custom Launch Entries"), 12, 12);
            rebuild_custom_entries_ui ();
            general_content.append (custom_entries_group);

            SettingsShared.add_scrolled_settings_page (stack, general_content, SettingsShared.PAGE_GENERAL, _("General"));

            var runner_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var runner_group = SettingsShared.build_group (_("Runner"), 12);

            var runner_model = RunnerSettingsShared.build_runner_model (runner_specs);
            runner_combo = new OptionListRow ();
            runner_combo.title = _("Runner");
            runner_combo.model = runner_model;
            runner_combo.selected = RunnerSettingsShared.select_runner_index (runner_specs, entry.runner_id);
            runner_combo.notify["selected"].connect (on_runner_changed);
            runner_group.add (runner_combo);
            runner_content.append (runner_group);

            runner_content.append (SettingsShared.build_warning_card (
                _("Changing the runner type for an existing prefix may not work correctly. Some runners set up the prefix differently when it is created, so switching between runner families later can break games or tools. Creating a new prefix is safer when changing runner families.")
            ));

            var variant_group = SettingsShared.build_group (_("Variant"), 12, 12);

            variant_combo = new OptionListRow ();
            variant_combo.title = _("Variant");
            variant_group.add (variant_combo);
            rebuild_variant_combo (entry.variant_id);
            runner_content.append (variant_group);

            var version_group = SettingsShared.build_group (_("Version"), 12, 12);

            version_row = new Adw.ActionRow ();
            version_row.title = _("Version");
            version_row.activatable = true;
            version_row.activated.connect (open_version_picker);
            version_group.add (version_row);
            update_version_row ();
            variant_combo.notify["selected"].connect (on_variant_changed);
            runner_content.append (version_group);

            latest_runner_warning = SettingsShared.build_warning_card (
                _("Latest keeps this prefix on the newest runner automatically. Updates may change compatibility or behavior without notice.")
            );
            latest_runner_warning.visible = false;
            runner_content.append (latest_runner_warning);
            update_latest_runner_warning ();

            var runner_opts_group = SettingsShared.build_group (_("Runner Options"), 12, 12);

            wayland_combo = RunnerSettingsShared.build_wayland_combo (entry.wine_wayland);
            runner_opts_group.add (wayland_combo);

            wayland_monitor_combo = new OptionListRow ();
            wayland_monitor_combo.title = _("Primary Wayland Monitor");
            runner_opts_group.add (wayland_monitor_combo);
            rebuild_wayland_monitor_combo (entry.wayland_primary_monitor);

            sync_combo = RunnerSettingsShared.build_sync_override_combo (entry.sync_mode);
            runner_opts_group.add (sync_combo);

            debug_combo = RunnerSettingsShared.build_debug_override_combo (entry.wine_debug);
            RunnerSettingsShared.update_debug_combo_logging_state (
                debug_combo,
                Utils.Preferences.instance ().keep_runtime_logs
            );
            runner_opts_group.add (debug_combo);

            runner_content.append (runner_opts_group);

            var component_specs = Models.SpecRepository.shared ().components;
            if (component_specs.size > 0) {
                var comp_group = SettingsShared.build_group (_("Runtime Components"), 12, 12, 12);

                foreach (var spec in component_specs) {
                    if (installer_spec == null
                        || !spec.supports_installer (installer_spec.id)) continue;
                    var override_entry = entry.runtime_component_overrides.has_key (spec.id)
                        ? entry.runtime_component_overrides[spec.id]
                        : new Models.RuntimeComponentOverride ();

                    var default_label = Utils.Preferences.instance ().is_component_enabled (spec.id) ? _("enabled") : _("disabled");
                    var mode_row = SettingsShared.build_toggle_override_combo (
                        spec.display_label (),
                        override_entry.enabled,
                        default_label
                    );
                    if (spec.id == "dxvk") {
                        mode_row.notify["selected"].connect (() => {
                            update_dxvk_config_visibility ();
                        });
                    }
                    component_mode_rows[spec.id] = mode_row;
                    comp_group.add (mode_row);
                }
                runner_content.append (comp_group);
            }

            var dxvk_group = SettingsShared.build_group (_("DXVK Configuration"), 12, 12, 12);
            dxvk_group.description = _("Leave fields blank to use DXVK defaults.");

            advanced_dxvk_row = new Adw.SwitchRow ();
            advanced_dxvk_row.title = _("Advanced DXVK");
            advanced_dxvk_row.subtitle = _("Write a managed dxvk.conf for this prefix when DXVK is active.");
            advanced_dxvk_row.active = entry.advanced_dxvk;
            advanced_dxvk_row.notify["active"].connect (() => {
                update_dxvk_config_visibility ();
            });
            dxvk_group.add (advanced_dxvk_row);

            dxvk_config_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            dxvk_config_box.margin_top = 6;

            dxvk_show_fps_row = new Adw.SwitchRow ();
            dxvk_show_fps_row.title = _("Show FPS");
            dxvk_show_fps_row.active = entry.dxvk_show_fps;
            dxvk_config_box.append (dxvk_show_fps_row);

            dxvk_hide_integrated_graphics_row = new Adw.SwitchRow ();
            dxvk_hide_integrated_graphics_row.title = _("Hide Integrated Graphics");
            dxvk_hide_integrated_graphics_row.subtitle = _("Only use when a dedicated GPU is present. It is recommended to use the DXVK_FILTER_DEVICE_NAME environment variable when possible.");
            dxvk_hide_integrated_graphics_row.active = entry.dxvk_hide_integrated_graphics;
            dxvk_config_box.append (dxvk_hide_integrated_graphics_row);

            var anisotropy_info_row = new Adw.ActionRow ();
            anisotropy_info_row.title = _("Anisotropic Filtering");
            anisotropy_info_row.subtitle = _("Overrides texture filtering for D3D9. Use 0 to disable forced filtering, or 1-16 to force that anisotropy level.");
            anisotropy_info_row.activatable = false;
            dxvk_config_box.append (anisotropy_info_row);

            dxvk_anisotropy_row = new Adw.EntryRow ();
            dxvk_anisotropy_row.title = _("d3d9.samplerAnisotropy");
            dxvk_anisotropy_row.text = entry.dxvk_sampler_anisotropy;
            dxvk_anisotropy_row.input_purpose = Gtk.InputPurpose.NUMBER;
            dxvk_config_box.append (dxvk_anisotropy_row);

            var max_frame_rate_info_row = new Adw.ActionRow ();
            max_frame_rate_info_row.title = _("Frame Rate Limit");
            max_frame_rate_info_row.subtitle = _("Limits presentation frame rate for D3D9. Use any integer; -1 disables DXVK's limiter.");
            max_frame_rate_info_row.activatable = false;
            dxvk_config_box.append (max_frame_rate_info_row);

            dxvk_max_frame_rate_row = new Adw.EntryRow ();
            dxvk_max_frame_rate_row.title = _("d3d9.maxFrameRate");
            dxvk_max_frame_rate_row.text = entry.dxvk_max_frame_rate;
            dxvk_max_frame_rate_row.input_purpose = Gtk.InputPurpose.NUMBER;
            dxvk_config_box.append (dxvk_max_frame_rate_row);

            var sync_interval_info_row = new Adw.ActionRow ();
            sync_interval_info_row.title = _("Vsync Interval");
            sync_interval_info_row.subtitle = _("Overrides presentation sync interval for D3D9. Use 0 to disable Vsync, or a positive number to repeat frames.");
            sync_interval_info_row.activatable = false;
            dxvk_config_box.append (sync_interval_info_row);

            dxvk_sync_interval_row = new Adw.EntryRow ();
            dxvk_sync_interval_row.title = _("d3d9.presentInterval");
            dxvk_sync_interval_row.text = entry.dxvk_sync_interval;
            dxvk_sync_interval_row.input_purpose = Gtk.InputPurpose.NUMBER;
            dxvk_config_box.append (dxvk_sync_interval_row);

            var custom_label = new Gtk.Label (_("Custom Configuration"));
            custom_label.xalign = 0f;
            custom_label.add_css_class ("heading");
            custom_label.margin_top = 12;
            custom_label.margin_start = 12;
            custom_label.margin_end = 12;
            dxvk_config_box.append (custom_label);

            dxvk_custom_buffer = new Gtk.TextBuffer (null);
            dxvk_custom_buffer.set_text (entry.dxvk_config_custom, -1);
            var dxvk_custom_view = new Gtk.TextView.with_buffer (dxvk_custom_buffer);
            dxvk_custom_view.monospace = true;
            dxvk_custom_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            dxvk_custom_view.top_margin = 8;
            dxvk_custom_view.bottom_margin = 8;
            dxvk_custom_view.left_margin = 8;
            dxvk_custom_view.right_margin = 8;

            var dxvk_custom_scroll = new Gtk.ScrolledWindow ();
            dxvk_custom_scroll.child = dxvk_custom_view;
            dxvk_custom_scroll.min_content_height = 120;
            dxvk_custom_scroll.margin_start = 12;
            dxvk_custom_scroll.margin_end = 12;
            dxvk_custom_scroll.margin_bottom = 8;
            dxvk_custom_scroll.add_css_class ("card");
            dxvk_config_box.append (dxvk_custom_scroll);

            dxvk_group.add (dxvk_config_box);
            update_dxvk_config_visibility ();
            runner_content.append (dxvk_group);

            SettingsShared.add_scrolled_settings_page (stack, runner_content, SettingsShared.PAGE_RUNNERS, _("Runner"));

            shortcuts_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            SettingsShared.add_scrolled_settings_page (stack, shortcuts_content, SettingsShared.PAGE_SHORTCUTS, _("Shortcuts"));
            rebuild_shortcuts_ui ();

            packages_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            build_packages_page (packages_content, entry);
            SettingsShared.add_scrolled_settings_page (stack, packages_content, SettingsShared.PAGE_PACKAGES, _("Packages"));

            var advanced_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var env_group = SettingsShared.build_group (_("Environment Variables"), 12, 12, 0);
            env_group.description = _("These override global environment variables.");

            prefix_env_editor = new Lumoria.Widgets.EnvVarsEditor (entry.runtime_env_vars);
            prefix_env_editor.margin_top = 8;
            prefix_env_editor.margin_start = 8;
            prefix_env_editor.margin_end = 8;
            prefix_env_editor.margin_bottom = 6;
            prefix_env_editor.changed.connect (() => {
                string message;
                var valid = prefix_env_editor.validate (out message);
                env_validation_label.label = message;
                env_validation_label.visible = !valid;
            });
            env_group.add (prefix_env_editor);

            env_validation_label = new Gtk.Label ("");
            env_validation_label.xalign = 0f;
            env_validation_label.wrap = true;
            env_validation_label.add_css_class ("error");
            env_validation_label.visible = false;
            env_validation_label.margin_start = 8;
            env_validation_label.margin_end = 8;
            env_validation_label.margin_bottom = 4;
            env_group.add (env_validation_label);
            advanced_content.append (env_group);

            var dll_group = SettingsShared.build_group (_("DLL Overrides"), 12, 12, 0);
            dll_group.description = _("Use dll=mode entries separated by semicolons.");
            prefix_dll_row = new Adw.EntryRow ();
            prefix_dll_row.title = _("DLL Overrides");
            prefix_dll_row.text = stringify_dll_overrides (entry.runtime_dll_overrides);
            dll_group.add (prefix_dll_row);
            advanced_content.append (dll_group);

            var prelaunch_group = SettingsShared.build_group (_("Prelaunch"), 12, 12, 12);
            prelaunch_script_path = entry.prelaunch_script;

            prelaunch_row = new Adw.ActionRow ();
            prelaunch_row.title = _("Prelaunch Script");
            prelaunch_row.subtitle = prelaunch_script_path != ""
                ? prelaunch_script_path
                : _("None");

            var prelaunch_browse_btn = new Gtk.Button.with_label (_("Browse…"));
            prelaunch_browse_btn.valign = Gtk.Align.CENTER;
            prelaunch_browse_btn.sensitive = !is_gamescope;
            prelaunch_browse_btn.clicked.connect (on_browse_prelaunch);
            prelaunch_row.add_suffix (prelaunch_browse_btn);

            if (prelaunch_script_path != "") {
                var prelaunch_clear_btn = new Gtk.Button.from_icon_name (IconRegistry.CLOSE);
                prelaunch_clear_btn.valign = Gtk.Align.CENTER;
                prelaunch_clear_btn.tooltip_text = _("Clear");
                prelaunch_clear_btn.add_css_class ("flat");
                prelaunch_clear_btn.clicked.connect (() => {
                    prelaunch_script_path = "";
                    prelaunch_row.subtitle = _("None");
                });
                prelaunch_row.add_suffix (prelaunch_clear_btn);
            }

            prelaunch_group.add (prelaunch_row);
            prelaunch_group.add (SettingsShared.build_warning_card (
                _("Prelaunch scripts are skipped in gamescope sessions. They still run when launching from desktop mode."),
                8,
                8,
                8,
                8
            ));

            advanced_content.append (prelaunch_group);

            var large_address_patch = installer_patch_for_setting (
                "large_address_aware"
            );
            if (large_address_patch != null
                && Utils.Preferences.instance ().experimental_features) {
                var patches_group = SettingsShared.build_group (_("Patches"), 12, 12, 12);
                var laa_default = Utils.Preferences.instance ().large_address_aware ? _("enabled") : _("disabled");
                laa_combo = SettingsShared.build_toggle_override_combo (
                    large_address_patch.name,
                    entry.large_address_aware,
                    laa_default,
                    _("Toggle the Large Address Aware flag on the installer target before launch by default.")
                );
                patches_group.add (laa_combo);
                advanced_content.append (patches_group);
            }

            var advanced_group = SettingsShared.build_group (_("Advanced"), 12, 12, 0);

            var reset_row = new Adw.ActionRow ();
            reset_row.title = _("Reset to Global Defaults");
            reset_row.subtitle = _("This will reset the prefix to the global default settings.");
            var reset_btn = new Gtk.Button.with_label (_("Reset"));
            reset_btn.add_css_class ("destructive-action");
            reset_btn.valign = Gtk.Align.CENTER;
            reset_btn.clicked.connect (on_reset_prefix);
            reset_row.add_suffix (reset_btn);
            reset_row.activatable_widget = reset_btn;
            advanced_group.add (reset_row);

            var remove_row = new Adw.ActionRow ();
            remove_row.title = _("Remove Prefix");
            remove_row.subtitle = _("Remove this prefix from the list, optionally deleting its files.");
            var remove_btn = new Gtk.Button.with_label (_("Remove\u2026"));
            remove_btn.add_css_class ("destructive-action");
            remove_btn.valign = Gtk.Align.CENTER;
            remove_btn.clicked.connect (on_remove_prefix);
            remove_row.add_suffix (remove_btn);
            remove_row.activatable_widget = remove_btn;
            advanced_group.add (remove_row);

            advanced_content.append (advanced_group);

            SettingsShared.add_scrolled_settings_page (stack, advanced_content, SettingsShared.PAGE_ADVANCED, _("Advanced"));

            var container = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            container.vexpand = true;
            var switcher_bar = new Adw.ViewSwitcherBar ();
            switcher_bar.stack = stack;
            switcher_bar.reveal = true;
            container.append (switcher_bar);
            container.append (stack);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.margin_start = 12;
            actions.margin_end = 12;
            actions.margin_top = 10;
            actions.margin_bottom = 12;

            var save_btn = new Gtk.Button.with_label (_("Save"));
            save_btn.add_css_class ("suggested-action");
            save_btn.hexpand = true;
            save_btn.halign = Gtk.Align.FILL;
            save_btn.clicked.connect (on_save);
            actions.append (save_btn);

            container.append (actions);
            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.child = container;
            toolbar.content = toast_overlay;
            this.child = toolbar;
        }

        private void rebuild_variant_combo (string preselect = "") {
            RunnerSettingsShared.rebuild_variant_combo (
                runner_combo,
                variant_combo,
                runner_specs,
                visible_variants,
                preselect
            );
        }

        private void on_runner_changed () {
            selected_runner_version = "default";
            selected_runner_version_label = "";
            rebuild_variant_combo ();
            rebuild_wayland_monitor_combo ();
            update_version_row ();
        }

        private void on_variant_changed () {
            selected_runner_version = "default";
            selected_runner_version_label = "";
            rebuild_wayland_monitor_combo ();
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
            } else {
                version_row.subtitle = RunnerSettingsShared.version_label_for_value (
                    selected_runner (),
                    selected_runner_version
                );
            }
            update_latest_runner_warning ();
        }

        private void update_latest_runner_warning () {
            if (latest_runner_warning == null) return;
            latest_runner_warning.visible = RunnerSettingsShared.is_effective_latest (
                selected_runner (), selected_runner_version
            );
        }

        private bool selected_runner_supports_feature (string feature) {
            var variant = selected_variant ();
            return variant != null && variant.supports_feature (feature);
        }

        private void rebuild_wayland_monitor_combo (string preselect = "") {
            if (wayland_monitor_combo == null) return;

            var supported = selected_runner_supports_feature ("wayland-primary-monitor");
            wayland_monitor_combo.visible = supported;
            wayland_monitor_combo.sensitive = supported;
            wayland_monitor_values.clear ();

            var model = new Gtk.StringList (null);
            model.append (_("Default"));
            wayland_monitor_values.add ("");

            var monitors = Services.list_monitors ();
            bool selected_found = preselect == "";
            int selected_idx = 0;
            var normalized_preselect = preselect.strip ();
            foreach (var monitor in monitors) {
                model.append (monitor.label);
                wayland_monitor_values.add (monitor.connector);
                if (normalized_preselect != "" && monitor.connector == normalized_preselect) {
                    selected_found = true;
                    selected_idx = wayland_monitor_values.size - 1;
                }
            }

            if (!selected_found && normalized_preselect != "") {
                model.append (_("%s (saved)").printf (normalized_preselect));
                wayland_monitor_values.add (normalized_preselect);
                selected_idx = wayland_monitor_values.size - 1;
            }

            wayland_monitor_combo.model = model;
            wayland_monitor_combo.selected = (uint) selected_idx;
        }

        private string selected_wayland_monitor () {
            if (wayland_monitor_combo == null || !wayland_monitor_combo.visible) return "";
            var idx = (int) wayland_monitor_combo.selected;
            if (idx < 0 || idx >= wayland_monitor_values.size) return "";
            return wayland_monitor_values[idx].strip ();
        }

        private string dxvk_custom_text () {
            Gtk.TextIter start;
            Gtk.TextIter end;
            dxvk_custom_buffer.get_bounds (out start, out end);
            return dxvk_custom_buffer.get_text (start, end, false).strip ();
        }

        private void update_dxvk_config_visibility () {
            if (advanced_dxvk_row == null) return;

            var active = is_dxvk_active_in_dialog ();
            advanced_dxvk_row.sensitive = active;
            advanced_dxvk_row.subtitle = active
                ? _("Write a managed dxvk.conf for this prefix when DXVK is active.")
                : _("Enable DXVK in Runtime Components to configure dxvk.conf.");
            if (!active && advanced_dxvk_row.active) {
                advanced_dxvk_row.active = false;
            }
            if (dxvk_config_box != null) {
                dxvk_config_box.visible = active && advanced_dxvk_row.active;
            }
        }

        private bool is_dxvk_active_in_dialog () {
            if (!component_mode_rows.has_key ("dxvk")) {
                return Utils.Preferences.instance ().is_component_enabled ("dxvk");
            }

            var state = (ToggleOverrideState) component_mode_rows["dxvk"].selected;
            switch (state) {
                case ToggleOverrideState.ENABLED:
                    return true;
                case ToggleOverrideState.DISABLED:
                    return false;
                default:
                    return Utils.Preferences.instance ().is_component_enabled ("dxvk");
            }
        }

        private bool validate_dxvk_integer (
            string value,
            bool allow_negative,
            string title,
            out string message
        ) {
            var trimmed = value.strip ();
            message = "";
            if (trimmed == "") return true;

            int parsed;
            if (!int.try_parse (trimmed, out parsed)) {
                message = _("%s must be Default or a whole number.").printf (title);
                return false;
            }
            if (!allow_negative && parsed < 0) {
                message = _("%s must be Default or a non-negative whole number.").printf (title);
                return false;
            }
            return true;
        }

        private bool validate_dxvk_range (
            string value,
            int min,
            int max,
            string title,
            out string message
        ) {
            var trimmed = value.strip ();
            message = "";
            if (trimmed == "") return true;

            int parsed;
            if (!int.try_parse (trimmed, out parsed) || parsed < min || parsed > max) {
                message = _("%s must be Default or a whole number from %d to %d.").printf (title, min, max);
                return false;
            }
            return true;
        }

        private void rebuild_custom_entries_ui () {
            foreach (var w in custom_entry_rows) custom_entries_group.remove (w);
            custom_entry_rows.clear ();

            for (int i = 0; i < custom_entries.size; i++) {
                var ep = custom_entries[i];
                var row = new Adw.ActionRow ();
                row.title = ep.name != "" ? ep.name : Path.get_basename (ep.exe);
                row.subtitle = ep.exe;
                if (ep.args.size > 0) {
                    row.subtitle += "  " + string.joinv (" ", ep.args.to_array ());
                }
                row.activatable = true;
                row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));

                var idx = i;
                row.activated.connect (() => show_custom_entry_editor (idx));

                custom_entries_group.add (row);
                custom_entry_rows.add (row);
            }

            var add_row = new Adw.ActionRow ();
            add_row.title = _("Add Custom Entry");
            add_row.activatable = true;
            add_row.add_prefix (new Gtk.Image.from_icon_name (IconRegistry.ADD));
            add_row.activated.connect (() => show_custom_entry_editor (-1));
            custom_entries_group.add (add_row);
            custom_entry_rows.add (add_row);
            refresh_entrypoint_models ();
            if (shortcuts_content != null) rebuild_shortcuts_ui ();
        }

        private Gee.ArrayList<Runtime.LaunchTarget> current_launch_targets () {
            var manifest_warnings = new Gee.ArrayList<string> ();
            var targets = new Gee.ArrayList<Runtime.LaunchTarget> ();
            try {
                targets = Runtime.list_launch_targets (
                    registry.prefixes[prefix_index],
                    launcher_specs,
                    custom_entries,
                    manifest_warnings
                );
            } catch (Error e) {
                manifest_warnings.add (e.message);
            }
            foreach (var msg in manifest_warnings) {
                if (toast_overlay != null) {
                    toast_overlay.add_toast (new Adw.Toast (msg));
                }
            }
            return targets;
        }

        private string current_selected_entrypoint_id () {
            int ep_idx = (int) entrypoint_combo.selected;
            if (ep_idx >= 0 && ep_idx < entrypoint_values.size) {
                var selected_id = entrypoint_values[ep_idx];
                if (selected_id != "") return selected_id;
            }
            var entry = registry.prefixes[prefix_index];
            if (entry.launch_entrypoint_id != "") return entry.launch_entrypoint_id;
            try {
                return Runtime.resolve_effective_entrypoint_id (
                    entry, launcher_specs
                );
            } catch (Error e) {
                return "";
            }
        }

        private void refresh_entrypoint_models () {
            var entrypoint_model = new Gtk.StringList (null);
            entrypoint_values.clear ();
            entrypoint_model.append (automatic_entrypoint_label ());
            entrypoint_values.add ("");
            foreach (var target in current_launch_targets ()) {
                entrypoint_model.append (target.selector_label);
                entrypoint_values.add (target.id);
            }
            entrypoint_combo.model = entrypoint_model;
            int entrypoint_selected = 0;
            for (int i = 0; i < entrypoint_values.size; i++) {
                if (entrypoint_values[i] == registry.prefixes[prefix_index].launch_entrypoint_id) {
                    entrypoint_selected = i;
                    break;
                }
            }
            entrypoint_combo.selected = entrypoint_selected;
            update_entrypoint_combo_subtitle ();
        }

        private void update_entrypoint_combo_subtitle () {
            var selected_id = current_selected_entrypoint_id ();
            if (selected_id == "") {
                entrypoint_combo.subtitle = automatic_entrypoint_label ();
                return;
            }

            foreach (var target in current_launch_targets ()) {
                if (target.id != selected_id) continue;
                entrypoint_combo.subtitle = target.selector_label;
                return;
            }
        }

        private string automatic_entrypoint_label () {
            var entry = registry.prefixes[prefix_index];
            if (entry.launcher_id != "" && installer_spec != null
                && installer_spec.supports_launcher (entry.launcher_id)) {
                return _("Automatic (launcher default)");
            }
            if (installer_spec != null && installer_spec.entrypoints.size > 0) {
                return _("Automatic (installation default)");
            }
            return _("Automatic (first custom entrypoint)");
        }

        private Models.InstallerPatch? installer_patch_for_setting (
            string setting
        ) {
            if (installer_spec == null) return null;
            foreach (var patch in installer_spec.patches) {
                if (patch.setting == setting) return patch;
            }
            return null;
        }

        private void rebuild_shortcuts_ui () {
            Gtk.Widget? child;
            while ((child = shortcuts_content.get_first_child ()) != null) {
                shortcuts_content.remove (child);
            }

            var entry = registry.prefixes[prefix_index];
            var targets = current_launch_targets ();
            if (targets.size == 0) {
                var empty_group = SettingsShared.build_group (_("Shortcuts"), 12);
                var empty_row = new Adw.ActionRow ();
                empty_row.title = _("No launch targets available");
                empty_row.activatable = false;
                empty_group.add (empty_row);
                shortcuts_content.append (empty_group);
                return;
            }

            Runtime.LaunchTargetSection? current_section = null;
            Adw.PreferencesGroup? group = null;
            var active_target_id = current_selected_entrypoint_id ();
            foreach (var target in targets) {
                if (current_section == null || current_section != target.section) {
                    group = SettingsShared.build_group (Runtime.launch_target_section_title (target.section), 12, 12, 0);
                    shortcuts_content.append (group);
                    current_section = target.section;
                }

                var row = new Adw.ActionRow ();
                row.title = target.label;
                var subtitle = Runtime.launch_target_subtitle (target, active_target_id);
                if (subtitle != "") row.subtitle = subtitle;

                var has_menu_shortcut = shortcut_service.has_menu_shortcut (entry, target.id);
                var has_steam_shortcut = steam_shortcut_service.has_steam_shortcut (entry, target.id);

                var menu_btn = new Gtk.Button.from_icon_name ("view-app-grid-symbolic");
                menu_btn.valign = Gtk.Align.CENTER;
                menu_btn.tooltip_text = has_menu_shortcut ? _("Remove from App Launcher") : _("Add to App Launcher");
                menu_btn.add_css_class ("flat");
                menu_btn.add_css_class ("shortcut-toggle");
                if (has_menu_shortcut) menu_btn.add_css_class ("shortcut-active");

                var steam_icon = new Gtk.Image.from_resource ("/net/windower/Lumoria/images/steam.svg");
                var steam_btn = new Gtk.Button ();
                steam_btn.child = steam_icon;
                steam_btn.valign = Gtk.Align.CENTER;
                steam_btn.tooltip_text = has_steam_shortcut ? _("Remove from Steam") : _("Add to Steam");
                steam_btn.add_css_class ("flat");
                steam_btn.add_css_class ("shortcut-toggle");
                if (has_steam_shortcut) steam_btn.add_css_class ("shortcut-active");

                var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
                button_box.append (menu_btn);
                button_box.append (steam_btn);
                row.add_suffix (button_box);

                var captured_target = target;
                menu_btn.clicked.connect (() => {
                    if (has_menu_shortcut) {
                        remove_shortcut_for_target (captured_target.id);
                    } else {
                        install_shortcut_for_target (captured_target);
                    }
                });
                steam_btn.clicked.connect (() => {
                    if (has_steam_shortcut) {
                        remove_steam_shortcut_for_target (captured_target.id);
                    } else {
                        install_steam_shortcut_for_target (captured_target);
                    }
                });

                group.add (row);
            }
        }

        private Gee.ArrayList<string> invalid_shortcut_ids () {
            var valid_ids = new Gee.HashSet<string> ();
            foreach (var target in current_launch_targets ()) valid_ids.add (target.id);

            var stale_ids = new Gee.ArrayList<string> ();
            foreach (var shortcut in registry.prefixes[prefix_index].dynamic_launcher_desktop_ids.entries) {
                if (!valid_ids.contains (shortcut.key)) stale_ids.add (shortcut.key);
            }
            return stale_ids;
        }

        private bool prune_orphaned_shortcuts () {
            foreach (var entrypoint_id in invalid_shortcut_ids ()) {
                try {
                    shortcut_service.remove_menu_shortcut (registry.prefixes[prefix_index], entrypoint_id);
                } catch (Error e) {
                    toast_overlay.add_toast (new Adw.Toast (e.message));
                    return false;
                }
            }
            return true;
        }

        private bool uninstall_all_shortcuts (Models.PrefixEntry entry) {
            var ids = new Gee.ArrayList<string> ();
            foreach (var shortcut in entry.dynamic_launcher_desktop_ids.entries) ids.add (shortcut.key);
            foreach (var entrypoint_id in ids) {
                try {
                    shortcut_service.remove_menu_shortcut (entry, entrypoint_id);
                } catch (Error e) {
                    toast_overlay.add_toast (new Adw.Toast (e.message));
                    return false;
                }
            }
            return true;
        }

        private void install_shortcut_for_target (Runtime.LaunchTarget target) {
            shortcut_service.install_menu_shortcut.begin (host_window, registry.prefixes[prefix_index], launcher_specs, target, (obj, res) => {
                try {
                    if (shortcut_service.install_menu_shortcut.end (res)) {
                        registry.save (Utils.prefix_registry_path ());
                        toast_overlay.add_toast (new Adw.Toast (_("Menu shortcut added")));
                    } else {
                        toast_overlay.add_toast (new Adw.Toast (_("Shortcut install was cancelled or failed")));
                    }
                } catch (Error e) {
                    toast_overlay.add_toast (new Adw.Toast (e.message));
                }
                rebuild_shortcuts_ui ();
            });
        }

        private void remove_shortcut_for_target (string entrypoint_id) {
            try {
                shortcut_service.remove_menu_shortcut (registry.prefixes[prefix_index], entrypoint_id);
                registry.save (Utils.prefix_registry_path ());
                toast_overlay.add_toast (new Adw.Toast (_("Menu shortcut removed")));
            } catch (Error e) {
                toast_overlay.add_toast (new Adw.Toast (e.message));
            }
            rebuild_shortcuts_ui ();
        }

        private void install_steam_shortcut_for_target (Runtime.LaunchTarget target) {
            resolve_steam_config ((config) => install_steam_shortcut_with_config (target, config));
        }

        private void install_steam_shortcut_with_config (
            Runtime.LaunchTarget target,
            Utils.SteamConfig.UserConfig config
        ) {
            try {
                steam_shortcut_service.install_steam_shortcut (registry.prefixes[prefix_index], target, config);
                registry.save (Utils.prefix_registry_path ());
                toast_overlay.add_toast (new Adw.Toast (_("Steam shortcut added. Restart Steam if it does not appear.")));
            } catch (Error e) {
                toast_overlay.add_toast (new Adw.Toast (_("Steam shortcut failed: %s").printf (e.message)));
            }
            rebuild_shortcuts_ui ();
        }

        private void remove_steam_shortcut_for_target (string entrypoint_id) {
            resolve_steam_config ((config) => remove_steam_shortcut_with_config (entrypoint_id, config));
        }

        private void remove_steam_shortcut_with_config (
            string entrypoint_id,
            Utils.SteamConfig.UserConfig config
        ) {
            try {
                steam_shortcut_service.remove_steam_shortcut (registry.prefixes[prefix_index], entrypoint_id, config);
                registry.save (Utils.prefix_registry_path ());
                toast_overlay.add_toast (new Adw.Toast (_("Steam shortcut removed. Restart Steam if it still appears.")));
            } catch (Error e) {
                toast_overlay.add_toast (new Adw.Toast (_("Steam shortcut removal failed: %s").printf (e.message)));
            }
            rebuild_shortcuts_ui ();
        }

        private delegate void SteamConfigSelectedCallback (Utils.SteamConfig.UserConfig config);

        private void resolve_steam_config (owned SteamConfigSelectedCallback on_resolved) {
            var config = steam_shortcut_service.detect_config ();
            if (config != null) {
                on_resolved (config);
                return;
            }

            var saved_dir = Utils.Preferences.instance ().resolved_steam_userdata_dir ();
            if (saved_dir != "") {
                config = steam_shortcut_service.resolve_config_from_folder (saved_dir);
                if (config != null) {
                    on_resolved (config);
                    return;
                }
                Utils.Preferences.instance ().set_steam_userdata_dir ("", null);
                toast_overlay.add_toast (new Adw.Toast (_("Steam folder access was lost. Please grant access again.")));
            }

            if (Utils.EnvironmentInfo.is_sandboxed ()) {
                present_steam_access_explanation (() => browse_for_steam_folder ((owned) on_resolved));
            } else {
                browse_for_steam_folder ((owned) on_resolved);
            }
        }

        private void browse_for_steam_folder (owned SteamConfigSelectedCallback on_selected) {
            if (SettingsShared.file_browse_blocked (toast_overlay)) return;

            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Select Steam Installation Folder");
            dialog.modal = true;
            if (FileUtils.test (Environment.get_home_dir (), FileTest.IS_DIR))
                dialog.initial_folder = File.new_for_path (Environment.get_home_dir ());

            dialog.select_folder.begin (host_window, null, (obj, res) => {
                try {
                    var file = dialog.select_folder.end (res);
                    if (file == null) return;
                    var raw_path = file.get_path () ?? "";
                    var raw_uri = file.get_uri () ?? "";
                    if (raw_path == "" && raw_uri == "") return;
                    var portal_ref = Utils.portal_path_ref_from_path_uri (raw_path, raw_uri);
                    var path = Utils.resolve_user_path (raw_path, portal_ref, raw_uri);
                    var config = steam_shortcut_service.resolve_config_from_folder (path);
                    if (config == null) {
                        toast_overlay.add_toast (new Adw.Toast (_("Selected folder does not look like a Steam installation folder.")));
                        return;
                    }
                    if (Utils.EnvironmentInfo.is_sandboxed ())
                        Utils.Preferences.instance ().set_steam_userdata_dir (raw_path, portal_ref);
                    on_selected (config);
                } catch (Error e) {
                    toast_overlay.add_toast (new Adw.Toast (_("Steam folder selection failed: %s").printf (e.message)));
                }
            });
        }

        private void present_steam_access_explanation (owned SettingsShared.ConfirmationCallback on_continue) {
            var dialog = new Adw.AlertDialog (
                _("Steam Installation Access Required"),
                _("Select your Steam installation folder. Common locations:\n\n.local/share/Steam\n.var/app/com.valvesoftware.Steam/.local/share/Steam (Steam Flatpak)\n\nAvoid selecting .steam or .steam/steam as they are symlinks and may not work.\nEnable \"Show Hidden Files\" in the file picker to see these folders.\n\nSee the Lumoria wiki for step-by-step screenshots.")
            );
            dialog.content_width = 600;
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("continue", _("Browse\u2026"));
            dialog.set_response_appearance ("continue", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "continue";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == "continue") on_continue ();
            });
            dialog.present (this);
        }

        private void show_custom_entry_editor (int index) {
            if (index < 0) {
                if (SettingsShared.file_browse_blocked (toast_overlay)) return;
                browse_custom_entry_executable (registry.prefixes[prefix_index].resolved_path (), (path) => {
                    present_entry_editor (-1, path);
                });
            } else {
                present_entry_editor (index, null);
            }
        }

        private void browse_custom_entry_executable (
            string? initial_folder,
            owned CustomExecutableSelectedCallback on_selected
        ) {
            if (Utils.is_sandboxed ()) {
                SettingsShared.present_sandbox_executable_browse_dialog (
                    host_window,
                    initial_folder,
                    (path) => on_selected (path),
                    (message) => {
                        toast_overlay.add_toast (new Adw.Toast (_("Browse failed: %s").printf (message)));
                    }
                );
                return;
            }

            var file_dialog = SettingsShared.build_file_dialog (
                _("Select Executable"),
                SettingsShared.build_windows_executable_filter ()
            );
            SettingsShared.open_file_dialog (host_window, file_dialog, initial_folder, (path) => {
                if (!SettingsShared.is_windows_executable_path (path)) {
                    toast_overlay.add_toast (new Adw.Toast (_("Please choose a Windows executable file.")));
                    return;
                }
                on_selected (path);
            }, (message) => {
                toast_overlay.add_toast (new Adw.Toast (_("Browse failed: %s").printf (message)));
            });
        }

        private void present_entry_editor (int index, string? initial_exe) {
            Models.Entrypoint? existing = (index >= 0 && index < custom_entries.size)
                ? custom_entries[index] : null;
            var is_gamescope = Utils.EnvironmentInfo.is_gamescope ();

            var dialog = new Adw.Dialog ();
            dialog.title = existing != null ? _("Edit Custom Entry") : _("Add Custom Entry");
            dialog.content_width = 460;
            dialog.content_height = 620;

            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = true;
            toolbar.add_top_bar (header);

            var editor_body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var launch_group = SettingsShared.build_group (_("Launch"), 12, 12);

            var name_row = new Adw.EntryRow ();
            name_row.title = _("Name");
            if (existing != null) {
                name_row.text = existing.name;
            } else if (initial_exe != null) {
                name_row.text = Path.get_basename (initial_exe);
            }
            launch_group.add (name_row);

            var exe_path = initial_exe ?? (existing != null ? existing.exe : "");

            var exe_row = new Adw.ActionRow ();
            exe_row.title = _("Executable");
            exe_row.subtitle = exe_path != "" ? exe_path : _("None selected");
            exe_row.subtitle_lines = 2;

            var browse_btn = new Gtk.Button.with_label (_("Browse\u2026"));
            browse_btn.valign = Gtk.Align.CENTER;
            browse_btn.clicked.connect (() => {
                if (SettingsShared.file_browse_blocked (toast_overlay)) return;
                var browse_start = exe_path != "" ? Path.get_dirname (exe_path) : registry.prefixes[prefix_index].resolved_path ();
                browse_custom_entry_executable (browse_start, (path) => {
                    exe_path = path;
                    exe_row.subtitle = path;
                    if (name_row.text.strip () == "") {
                        name_row.text = Path.get_basename (path);
                    }
                });
            });
            exe_row.add_suffix (browse_btn);
            launch_group.add (exe_row);

            var args_row = new Adw.EntryRow ();
            args_row.title = _("Arguments (space-separated)");
            args_row.text = existing != null && existing.args.size > 0
                ? string.joinv (" ", existing.args.to_array ()) : "";
            launch_group.add (args_row);
            editor_body.append (launch_group);

            var entry_prelaunch_path = existing != null ? existing.prelaunch_script : "";
            var prelaunch_group = SettingsShared.build_group (_("Prelaunch"), 12, 12);

            var entry_prelaunch_row = new Adw.ActionRow ();
            entry_prelaunch_row.title = _("Prelaunch Script");
            entry_prelaunch_row.subtitle = entry_prelaunch_path != "" ? entry_prelaunch_path : _("None");
            entry_prelaunch_row.subtitle_lines = 2;

            var ep_browse_btn = new Gtk.Button.with_label (_("Browse\u2026"));
            ep_browse_btn.valign = Gtk.Align.CENTER;
            ep_browse_btn.sensitive = !is_gamescope;
            ep_browse_btn.clicked.connect (() => {
                if (SettingsShared.file_browse_blocked (toast_overlay)) return;
                var fd = SettingsShared.build_file_dialog (
                    _("Select Prelaunch Script"),
                    SettingsShared.build_shell_script_filter ()
                );
                SettingsShared.open_file_dialog (null, fd, null, (path) => {
                    entry_prelaunch_path = path;
                    entry_prelaunch_row.subtitle = path;
                }, (message) => {
                    toast_overlay.add_toast (new Adw.Toast (_("Browse failed: %s").printf (message)));
                });
            });
            entry_prelaunch_row.add_suffix (ep_browse_btn);

            var ep_clear_btn = new Gtk.Button.from_icon_name (IconRegistry.CLOSE);
            ep_clear_btn.valign = Gtk.Align.CENTER;
            ep_clear_btn.tooltip_text = _("Clear");
            ep_clear_btn.add_css_class ("flat");
            ep_clear_btn.clicked.connect (() => {
                entry_prelaunch_path = "";
                entry_prelaunch_row.subtitle = _("None");
            });
            if (entry_prelaunch_path != "") {
                entry_prelaunch_row.add_suffix (ep_clear_btn);
            }
            prelaunch_group.add (entry_prelaunch_row);
            editor_body.append (prelaunch_group);
            editor_body.append (SettingsShared.build_warning_card (
                _("Prelaunch scripts are skipped in gamescope sessions. They still run when launching from desktop mode."),
                8,
                8,
                12,
                12
            ));

            var env_group = SettingsShared.build_group (_("Environment Variables"), 12, 12, 8);
            env_group.description = _("Applied to this custom entry. These override prefix and global variables.");
            var entry_env_editor = new Lumoria.Widgets.EnvVarsEditor (
                existing != null ? existing.runtime_env_overrides : null
            );
            entry_env_editor.margin_top = 8;
            entry_env_editor.margin_start = 8;
            entry_env_editor.margin_end = 8;
            entry_env_editor.margin_bottom = 8;
            env_group.add (entry_env_editor);
            editor_body.append (env_group);

            var dll_group = SettingsShared.build_group (_("DLL Overrides"), 12, 12);
            dll_group.description = _("Use dll=mode entries separated by semicolons.");
            var dll_row = new Adw.EntryRow ();
            dll_row.title = _("DLL Overrides");
            dll_row.text = stringify_dll_overrides (
                existing != null ? existing.runtime_dll_overrides : null
            );
            dll_group.add (dll_row);
            editor_body.append (dll_group);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.margin_start = 16;
            actions.margin_end = 16;
            actions.margin_top = 8;
            actions.margin_bottom = 16;
            actions.homogeneous = true;

            if (existing != null) {
                var delete_btn = new Gtk.Button.with_label (_("Delete"));
                delete_btn.add_css_class ("destructive-action");
                delete_btn.clicked.connect (() => {
                    if (shortcut_service.has_menu_shortcut (registry.prefixes[prefix_index], existing.id)) {
                        try {
                            shortcut_service.remove_menu_shortcut (registry.prefixes[prefix_index], existing.id);
                            registry.save (Utils.prefix_registry_path ());
                        } catch (Error e) {
                            toast_overlay.add_toast (new Adw.Toast (e.message));
                            return;
                        }
                    }
                    custom_entries.remove_at (index);
                    rebuild_custom_entries_ui ();
                    dialog.close ();
                });
                actions.append (delete_btn);
            }

            var cancel_btn = new Gtk.Button.with_label (_("Cancel"));
            cancel_btn.clicked.connect (() => dialog.close ());
            actions.append (cancel_btn);

            var save_btn = new Gtk.Button.with_label (existing != null ? _("Save") : _("Add"));
            save_btn.add_css_class ("suggested-action");
            save_btn.clicked.connect (() => {
                if (exe_path == "") return;
                string entry_env_error;
                if (!entry_env_editor.validate (out entry_env_error)) {
                    toast_overlay.add_toast (new Adw.Toast (entry_env_error));
                    return;
                }
                string dll_error;
                var parsed_dll_overrides = parse_dll_overrides (dll_row.text, out dll_error);
                if (parsed_dll_overrides == null) {
                    toast_overlay.add_toast (new Adw.Toast (dll_error));
                    return;
                }

                var ep = existing ?? new Models.Entrypoint ();
                ep.name = name_row.text.strip ();
                ep.exe = exe_path;
                ep.exe_portal = Utils.portal_path_ref_from_path_uri (exe_path);
                ep.prelaunch_script = entry_prelaunch_path;
                ep.prelaunch_script_portal = Utils.portal_path_ref_from_path_uri (entry_prelaunch_path);
                ep.args = new Gee.ArrayList<string> ();
                foreach (var arg in args_row.text.split (" ")) {
                    var a = arg.strip ();
                    if (a != "") ep.args.add (a);
                }
                if (ep.id == "") {
                    ep.id = generate_unique_custom_entry_id ();
                }
                ep.runtime_dll_overrides = (Gee.HashMap<string, string>) parsed_dll_overrides;
                ep.runtime_env_overrides = entry_env_editor.values ();

                if (index >= 0) {
                    custom_entries[index] = ep;
                } else {
                    custom_entries.add (ep);
                }
                rebuild_custom_entries_ui ();
                dialog.close ();
            });
            actions.append (save_btn);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.vexpand = true;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.child = editor_body;
            scroll.vexpand = true;
            content.append (scroll);
            content.append (actions);
            toolbar.content = content;
            dialog.child = toolbar;

            dialog.present (this);
        }

        private string generate_unique_custom_entry_id () {
            while (true) {
                var id = Models.PrefixEntry.generate_custom_entry_id ();
                var exists = false;
                foreach (var ep in custom_entries) {
                    if (ep.id == id) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) return id;
            }
        }

        private string stringify_dll_overrides (Gee.HashMap<string, string>? overrides) {
            if (overrides == null || overrides.size == 0) return "";
            var parts = new Gee.ArrayList<string> ();
            foreach (var ov in overrides.entries) {
                var dll = ov.key.strip ();
                var mode = ov.value.strip ();
                if (dll == "" || mode == "") continue;
                parts.add ("%s=%s".printf (dll, mode));
            }
            return string.joinv (";", Utils.arraylist_to_strv (parts));
        }

        private Gee.HashMap<string, string>? parse_dll_overrides (string raw, out string error) {
            error = "";
            var map = new Gee.HashMap<string, string> ();
            var text = raw.strip ();
            if (text == "") return map;
            foreach (var part in text.split (";")) {
                var trimmed = part.strip ();
                if (trimmed == "") continue;
                var eq = trimmed.index_of ("=");
                if (eq <= 0 || eq == trimmed.length - 1) {
                    error = _("Invalid DLL override entry: %s").printf (trimmed);
                    return null;
                }
                var dll = trimmed.substring (0, eq).strip ();
                var mode = trimmed.substring (eq + 1).strip ();
                if (dll == "" || mode == "") {
                    error = _("Invalid DLL override entry: %s").printf (trimmed);
                    return null;
                }
                map[dll] = mode;
            }
            return map;
        }

        private void on_browse_prelaunch () {
            if (SettingsShared.file_browse_blocked (toast_overlay)) return;
            var dialog = SettingsShared.build_file_dialog (
                _("Select prelaunch script"),
                SettingsShared.build_shell_script_filter ()
            );
            SettingsShared.open_file_dialog (null, dialog, null, (path) => {
                prelaunch_script_path = path;
                prelaunch_row.subtitle = path;
            }, (message) => {
                toast_overlay.add_toast (new Adw.Toast (_("Failed to select prelaunch script: %s").printf (message)));
            });
        }

        private void on_save () {
            var sel = (int) runner_combo.selected;
            if (sel < 0 || sel >= runner_specs.size) {
                SettingsShared.present_alert (this,
                    _("No Compatible Runner"),
                    _("No Wine runners are compatible with this environment."));
                return;
            }
            string env_error;
            if (!prefix_env_editor.validate (out env_error)) {
                SettingsShared.present_alert (this, _("Invalid Environment Variables"), env_error);
                return;
            }
            string dxvk_error;
            if (!validate_dxvk_range (dxvk_anisotropy_row.text, 0, 16, _("Anisotropic Filtering"), out dxvk_error)) {
                SettingsShared.present_alert (this, _("Invalid DXVK Configuration"), dxvk_error);
                return;
            }
            if (!validate_dxvk_integer (dxvk_max_frame_rate_row.text, true, _("Frame Rate Limit"), out dxvk_error)) {
                SettingsShared.present_alert (this, _("Invalid DXVK Configuration"), dxvk_error);
                return;
            }
            if (!validate_dxvk_integer (dxvk_sync_interval_row.text, false, _("Vsync Interval"), out dxvk_error)) {
                SettingsShared.present_alert (this, _("Invalid DXVK Configuration"), dxvk_error);
                return;
            }
            string dll_error;
            var parsed_dll_overrides = parse_dll_overrides (prefix_dll_row.text, out dll_error);
            if (parsed_dll_overrides == null) {
                SettingsShared.present_alert (this, _("Invalid DLL Overrides"), dll_error);
                return;
            }
            if (runner_specs[sel].selectable_variants (Utils.is_sandboxed ()).size == 0) {
                SettingsShared.present_alert (this,
                    _("Runner Not Supported"),
                    _("The selected runner has no compatible variants in this environment."));
                return;
            }

            var runner_version = selected_runner_version;

            registry.update_runner (prefix_index, runner_specs[sel].id, runner_version);

            if (variant_combo.visible) {
                var vi = (int) variant_combo.selected;
                if (vi >= 0 && vi < visible_variants.size) {
                    registry.prefixes[prefix_index].variant_id = visible_variants[vi].id;
                }
            }

            registry.prefixes[prefix_index].sync_mode = RunnerSettingsShared.sync_override_value_for_index (sync_combo.selected);

            registry.prefixes[prefix_index].wine_debug = RunnerSettingsShared.debug_override_value_for_index (debug_combo.selected);

            var wayland_override = RunnerSettingsShared.wayland_value_for_index (wayland_combo.selected);
            registry.prefixes[prefix_index].wine_wayland = wayland_override;
            registry.prefixes[prefix_index].wayland_primary_monitor = selected_runner_supports_feature ("wayland-primary-monitor")
                ? selected_wayland_monitor ()
                : "";
            if (laa_combo != null) {
                registry.prefixes[prefix_index].large_address_aware =
                    ((ToggleOverrideState) laa_combo.selected).to_nullable_bool ();
            }
            registry.prefixes[prefix_index].prelaunch_script = prelaunch_script_path;
            registry.prefixes[prefix_index].prelaunch_script_portal =
                Utils.portal_path_ref_from_path_uri (prelaunch_script_path);
            registry.prefixes[prefix_index].custom_entrypoints = custom_entries;
            registry.prefixes[prefix_index].runtime_env_vars = prefix_env_editor.values ();
            registry.prefixes[prefix_index].runtime_dll_overrides =
                (Gee.HashMap<string, string>) parsed_dll_overrides;
            var pfx = registry.prefixes[prefix_index];
            var dxvk_active = is_dxvk_active_in_dialog ();
            pfx.advanced_dxvk = dxvk_active && advanced_dxvk_row.active;
            pfx.dxvk_show_fps = dxvk_show_fps_row.active;
            pfx.dxvk_hide_integrated_graphics = dxvk_hide_integrated_graphics_row.active;
            pfx.dxvk_sampler_anisotropy = dxvk_anisotropy_row.text.strip ();
            pfx.dxvk_max_frame_rate = dxvk_max_frame_rate_row.text.strip ();
            pfx.dxvk_sync_interval = dxvk_sync_interval_row.text.strip ();
            pfx.dxvk_config_custom = dxvk_custom_text ();
            if (!pfx.advanced_dxvk) {
                Runtime.cleanup_managed_dxvk_config (pfx.resolved_path ());
            }
            int ep_idx = (int) entrypoint_combo.selected;
            if (ep_idx < 0 || ep_idx >= entrypoint_values.size) ep_idx = 0;
            pfx.launch_entrypoint_id = entrypoint_values[ep_idx];
            if (!prune_orphaned_shortcuts ()) return;

            var prefix = registry.prefixes[prefix_index];
            foreach (var entry in component_mode_rows.entries) {
                var spec_id = entry.key;
                var mode_row = entry.value;
                var selected_mode = (int) mode_row.selected;

                Models.RuntimeComponentOverride? ov = null;
                if (prefix.runtime_component_overrides.has_key (spec_id)) {
                    ov = prefix.runtime_component_overrides[spec_id];
                }

                if ((ToggleOverrideState) selected_mode == ToggleOverrideState.INHERIT) {
                    if (ov == null) continue;
                    ov.enabled = null;
                    if (ov.version == "" && ov.system_env.size == 0) {
                        prefix.runtime_component_overrides.unset (spec_id);
                    } else {
                        prefix.runtime_component_overrides[spec_id] = ov;
                    }
                    continue;
                }

                if (ov == null) ov = new Models.RuntimeComponentOverride ();
                ov.enabled = ((ToggleOverrideState) selected_mode).to_nullable_bool ();
                prefix.runtime_component_overrides[spec_id] = ov;
            }

            saved ();
            close ();
        }

        private void on_reset_prefix () {
            SettingsShared.present_destructive_confirmation (
                this,
                _("Reset to Global Defaults?"),
                _("This will reset the prefix to the global default settings."),
                "reset",
                _("Reset"),
                () => {
                var entry = registry.prefixes[prefix_index];
                entry.runner_version = "default";
                entry.launch_entrypoint_id = "";
                entry.sync_mode = "";
                entry.wine_debug = "";
                entry.wine_wayland = null;
                entry.wayland_primary_monitor = "";
                entry.large_address_aware = null;
                entry.advanced_dxvk = false;
                entry.dxvk_show_fps = false;
                entry.dxvk_sampler_anisotropy = "";
                entry.dxvk_max_frame_rate = "";
                entry.dxvk_sync_interval = "";
                entry.dxvk_config_custom = "";
                entry.runtime_env_vars.clear ();
                entry.runtime_component_overrides.clear ();
                Runtime.cleanup_managed_dxvk_config (entry.resolved_path ());
                saved ();
                close ();
            });
        }

        private void on_remove_prefix () {
            var entry = registry.prefixes[prefix_index];
            SettingsShared.present_remove_prefix_dialog (this, entry, (deleted_files) => {
                if (!uninstall_all_shortcuts (entry)) return;
                registry.remove_at (prefix_index);
                removed ();
                close ();
            });
        }

        private void build_packages_page (Gtk.Box content, Models.PrefixEntry entry) {
            package_specs = Models.SpecRepository.shared ().redists;
            package_installed_rows = new Gee.HashMap<string, Gtk.Widget> ();
            package_available_rows = new Gee.HashMap<string, Gtk.Widget> ();
            packages_installed_empty_row = null;
            packages_available_empty_row = null;
            packages_installed_count = 0;
            packages_available_count = 0;

            var installed = new Gee.HashSet<string> ();
            installed.add_all (entry.installed_redists);

            var installed_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var available_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            packages_installed_group = new Adw.PreferencesGroup ();
            packages_installed_group.margin_start = 12;
            packages_installed_group.margin_end = 12;
            packages_installed_group.margin_top = 6;
            packages_available_group = new Adw.PreferencesGroup ();
            packages_available_group.margin_start = 12;
            packages_available_group.margin_end = 12;
            packages_available_group.margin_top = 6;

            var sorted_ids = new Gee.ArrayList<string> ();
            sorted_ids.add_all (package_specs.keys);
            sorted_ids.sort ((a, b) => {
                return package_specs[a].name.collate (package_specs[b].name);
            });

            foreach (var id in sorted_ids) {
                add_package_row (entry, id, package_specs[id], installed.contains (id));
            }

            update_package_empty_rows ();

            installed_box.append (packages_installed_group);
            available_box.append (packages_available_group);

            packages_inner_stack = new Adw.ViewStack ();
            packages_inner_stack.vexpand = true;
            packages_installed_page = packages_inner_stack.add_titled (installed_box, "installed", "");
            packages_available_page = packages_inner_stack.add_titled (available_box, "available", "");
            update_package_page_titles ();
            packages_inner_stack.visible_child_name = resolve_packages_visible_page ();
            packages_inner_stack.notify["visible-child-name"].connect (() => {
                var visible = packages_inner_stack.visible_child_name;
                if (visible != null && visible != "") packages_visible_page = visible;
                update_package_switcher_state ();
            });

            var switcher = build_package_switcher ();
            switcher.margin_start = 12;
            switcher.margin_end = 12;
            switcher.margin_top = 12;

            content.append (build_packages_warning ());
            content.append (switcher);
            content.append (packages_inner_stack);
        }

        private Gtk.Widget build_package_switcher () {
            var switcher = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            switcher.halign = Gtk.Align.CENTER;
            switcher.add_css_class ("linked");

            packages_installed_button = new Gtk.ToggleButton.with_label ("");
            packages_installed_button.clicked.connect (() => {
                if (packages_installed_button.active) packages_inner_stack.visible_child_name = "installed";
                update_package_switcher_state ();
            });
            switcher.append (packages_installed_button);

            packages_available_button = new Gtk.ToggleButton.with_label ("");
            packages_available_button.clicked.connect (() => {
                if (packages_available_button.active) packages_inner_stack.visible_child_name = "available";
                update_package_switcher_state ();
            });
            switcher.append (packages_available_button);

            update_package_switcher_labels ();
            update_package_switcher_state ();
            return switcher;
        }

        private Gtk.Widget build_packages_warning () {
            return SettingsShared.build_warning_card (
                _("Install additional packages at your own risk. Changing the default install can break this prefix.")
            );
        }

        private void add_package_row (
            Models.PrefixEntry entry,
            string id,
            Models.RedistSpec spec,
            bool installed
        ) {
            var row = build_package_row (entry, id, spec, installed);
            if (installed) {
                packages_installed_group.add (row);
                package_installed_rows[id] = row;
                packages_installed_count++;
            } else {
                packages_available_group.add (row);
                package_available_rows[id] = row;
                packages_available_count++;
            }
        }

        private Adw.ActionRow build_package_row (
            Models.PrefixEntry entry,
            string id,
            Models.RedistSpec spec,
            bool installed
        ) {
            var row = new Adw.ActionRow ();
            row.title = spec.name;

            if (installed) {
                if (spec.reinstallable) {
                    var reinstall_btn = new Gtk.Button.with_label (_("Reinstall"));
                    reinstall_btn.valign = Gtk.Align.CENTER;
                    reinstall_btn.clicked.connect (() => {
                        on_install_redist (entry, id);
                    });
                    row.add_suffix (reinstall_btn);
                    row.activatable_widget = reinstall_btn;
                } else {
                    var check = new Gtk.Image.from_icon_name ("emblem-ok-symbolic");
                    check.valign = Gtk.Align.CENTER;
                    row.add_suffix (check);
                }
            } else {
                var install_btn = new Gtk.Button.with_label (_("Install"));
                install_btn.valign = Gtk.Align.CENTER;
                install_btn.add_css_class ("suggested-action");
                install_btn.clicked.connect (() => {
                    on_install_redist (entry, id);
                });
                row.add_suffix (install_btn);
                row.activatable_widget = install_btn;
            }

            return row;
        }

        private void update_package_empty_rows () {
            if (packages_installed_count == 0) {
                if (packages_installed_empty_row == null) {
                    var empty_row = new Adw.ActionRow ();
                    empty_row.title = _("No packages installed yet");
                    empty_row.activatable = false;
                    packages_installed_empty_row = empty_row;
                    packages_installed_group.add (empty_row);
                }
            } else if (packages_installed_empty_row != null) {
                packages_installed_group.remove (packages_installed_empty_row);
                packages_installed_empty_row = null;
            }

            if (packages_available_count == 0) {
                if (packages_available_empty_row == null) {
                    var empty_row = new Adw.ActionRow ();
                    empty_row.title = _("All packages are installed");
                    empty_row.activatable = false;
                    packages_available_empty_row = empty_row;
                    packages_available_group.add (empty_row);
                }
            } else if (packages_available_empty_row != null) {
                packages_available_group.remove (packages_available_empty_row);
                packages_available_empty_row = null;
            }
        }

        private void update_package_page_titles () {
            if (packages_installed_page != null) {
                packages_installed_page.title = _("Installed (%d)").printf (packages_installed_count);
            }
            if (packages_available_page != null) {
                packages_available_page.title = _("Available (%d)").printf (packages_available_count);
            }
            update_package_switcher_labels ();
        }

        private void update_package_switcher_labels () {
            if (packages_installed_button != null) {
                packages_installed_button.label = _("Installed (%d)").printf (packages_installed_count);
            }
            if (packages_available_button != null) {
                packages_available_button.label = _("Available (%d)").printf (packages_available_count);
            }
        }

        private void update_package_switcher_state () {
            if (packages_inner_stack == null) return;
            var visible = packages_inner_stack.visible_child_name;
            if (packages_installed_button != null) {
                packages_installed_button.active = visible == "installed";
            }
            if (packages_available_button != null) {
                packages_available_button.active = visible == "available";
            }
        }

        private string resolve_packages_visible_page () {
            if (packages_visible_page == "available" && packages_available_count > 0) return "available";
            if (packages_visible_page == "installed" && packages_installed_count > 0) return "installed";
            return packages_available_count > 0 ? "available" : "installed";
        }

        private void update_packages_after_install (
            Models.PrefixEntry entry,
            Gee.HashSet<string> previously_installed
        ) {
            bool changed = false;
            foreach (var id in entry.installed_redists) {
                if (previously_installed.contains (id)) continue;
                if (!package_specs.has_key (id)) continue;
                move_package_to_installed (entry, id, package_specs[id]);
                changed = true;
            }
            if (!changed) return;

            update_package_empty_rows ();
            update_package_page_titles ();
            packages_inner_stack.visible_child_name = resolve_packages_visible_page ();
        }

        private void move_package_to_installed (
            Models.PrefixEntry entry,
            string id,
            Models.RedistSpec spec
        ) {
            if (package_available_rows.has_key (id)) {
                var available_row = package_available_rows[id];
                packages_available_group.remove (available_row);
                package_available_rows.unset (id);
                packages_available_count--;
            }

            if (!package_installed_rows.has_key (id)) {
                var installed_row = build_package_row (entry, id, spec, true);
                packages_installed_group.add (installed_row);
                package_installed_rows[id] = installed_row;
                packages_installed_count++;
            }
        }

        private void on_install_redist (Models.PrefixEntry entry, string redist_id) {
            var name = package_specs.has_key (redist_id) ? package_specs[redist_id].name : redist_id;
            SettingsShared.present_confirmation (
                this,
                _("Install Package?"),
                _("Installing %s will close any programs currently running in this prefix.").printf (name),
                "install",
                _("Install"),
                Adw.ResponseAppearance.SUGGESTED,
                () => run_redist_install_flow (entry, redist_id)
            );
        }

        private void run_redist_install_flow (Models.PrefixEntry entry, string redist_id) {
            var previously_installed = new Gee.HashSet<string> ();
            previously_installed.add_all (entry.installed_redists);

            var dialog = new InstallDialog ();
            dialog.install_completed.connect ((success) => {
                if (success) {
                    registry.save (Utils.prefix_registry_path ());
                    saved ();
                    update_packages_after_install (entry, previously_installed);
                    toast_overlay.add_toast (new Adw.Toast (_("Package installed")));
                }
            });
            dialog.present (host_window);
            dialog.start_redist_install (entry, this.runner_specs, redist_id);
        }
    }
}
