namespace Lumoria.Widgets.Dialogs {

    public class ManagePrefixDialog : Adw.Dialog {
        public signal void saved ();
        public signal void removed ();

        private Models.PrefixRegistry registry;
        private int prefix_index;
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Gee.ArrayList<Models.LauncherSpec> launcher_specs;

        private Adw.ComboRow runner_combo;
        private Adw.ComboRow variant_combo;
        private Adw.ComboRow version_combo;
        private Adw.ComboRow sync_combo;
        private Adw.ComboRow debug_combo;
        private Adw.ComboRow wayland_combo;
        private Adw.ComboRow laa_combo;

        private Gee.ArrayList<string> version_values;
        private Gee.ArrayList<Models.RunnerVariant> visible_variants;
        private Gee.HashMap<string, Adw.ComboRow> component_mode_rows;
        private Adw.ComboRow entrypoint_combo;
        private Gee.ArrayList<string> entrypoint_values;
        private Lumoria.Widgets.EnvVarsEditor prefix_env_editor;
        private Gtk.Label env_validation_label;

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
            this.registry = registry;
            this.prefix_index = prefix_index;
            this.runner_specs = runner_specs;
            this.launcher_specs = launcher_specs;
            visible_variants = new Gee.ArrayList<Models.RunnerVariant> ();
            component_mode_rows = new Gee.HashMap<string, Adw.ComboRow> ();
            entrypoint_values = new Gee.ArrayList<string> ();
            build_ui ();
        }

        private void build_ui () {
            var entry = registry.prefixes[prefix_index];

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

            var default_row = new Adw.ActionRow ();
            default_row.title = _("Quick Launch");
            default_row.subtitle = _("Launched from the play button at the bottom of the window");
            var is_already_default = registry.is_default (entry);
            var default_btn = new Gtk.Button.with_label (is_already_default ? _("Quick Launch") : _("Set as Quick Launch"));
            default_btn.valign = Gtk.Align.CENTER;
            default_btn.sensitive = !is_already_default;
            default_btn.clicked.connect (() => {
                registry.default_prefix_id = entry.id;
                default_btn.label = _("Default");
                default_btn.sensitive = false;
                saved ();
            });
            default_row.add_suffix (default_btn);
            default_row.activatable_widget = default_btn;
            info_group.add (default_row);

            general_content.append (info_group);

            var launch_group = SettingsShared.build_group (_("Default Launch Entrypoint"), 12);

            var entrypoint_model = new Gtk.StringList (null);
            entrypoint_model.append (_("Automatic (launcher/installer default)"));
            entrypoint_values.add ("");
            var entrypoints = Runtime.list_entrypoints (entry, launcher_specs);
            foreach (var ep in entrypoints) {
                entrypoint_model.append (ep.display_label ());
                entrypoint_values.add (ep.id);
            }

            entrypoint_combo = new Adw.ComboRow ();
            entrypoint_combo.title = _("Entrypoint");
            entrypoint_combo.model = entrypoint_model;
            int entrypoint_selected = 0;
            for (int i = 0; i < entrypoint_values.size; i++) {
                if (entrypoint_values[i] == entry.launch_entrypoint_id) {
                    entrypoint_selected = i;
                    break;
                }
            }
            entrypoint_combo.selected = entrypoint_selected;
            launch_group.add (entrypoint_combo);

            general_content.append (launch_group);

            var runner_group = SettingsShared.build_group (_("Runner"), 12);

            var runner_model = new Gtk.StringList (null);
            for (int i = 0; i < runner_specs.size; i++) {
                var spec = runner_specs[i];
                runner_model.append (spec.display_label ());
            }
            runner_combo = new Adw.ComboRow ();
            runner_combo.title = _("Runner");
            runner_combo.model = runner_model;
            runner_combo.selected = RunnerSettingsShared.select_runner_index (runner_specs, entry.runner_id);
            runner_combo.notify["selected"].connect (on_runner_changed);
            runner_group.add (runner_combo);

            var variant_model = new Gtk.StringList (null);
            variant_combo = new Adw.ComboRow ();
            variant_combo.title = _("Variant");
            variant_combo.model = variant_model;
            runner_group.add (variant_combo);
            rebuild_variant_combo (entry.variant_id);

            version_combo = new Adw.ComboRow ();
            version_combo.title = _("Version");
            version_values = new Gee.ArrayList<string> ();
            runner_group.add (version_combo);
            rebuild_version_combo (entry.runner_version);

            sync_combo = RunnerSettingsShared.build_sync_combo (entry.sync_mode);
            runner_group.add (sync_combo);

            debug_combo = RunnerSettingsShared.build_debug_combo (entry.wine_debug);
            runner_group.add (debug_combo);

            wayland_combo = RunnerSettingsShared.build_wayland_combo (entry.wine_wayland);
            runner_group.add (wayland_combo);

            general_content.append (runner_group);

            var component_specs = Models.ComponentSpec.load_all_from_resource ();
            if (component_specs.size > 0) {
                var comp_group = SettingsShared.build_group (_("Runtime Components"), 12, 12, 12);

                foreach (var spec in component_specs) {
                    var override_entry = entry.runtime_component_overrides.has_key (spec.id)
                        ? entry.runtime_component_overrides[spec.id]
                        : new Models.RuntimeComponentOverride ();

                    var default_label = Utils.Preferences.instance ().default_component_enabled (spec.id) ? _("enabled") : _("disabled");
                    var mode_row = SettingsShared.build_toggle_override_combo (
                        spec.display_label (),
                        override_entry.enabled,
                        default_label
                    );
                    component_mode_rows[spec.id] = mode_row;
                    comp_group.add (mode_row);
                }
                general_content.append (comp_group);
            }

            SettingsShared.add_scrolled_settings_page (stack, general_content, SettingsShared.PAGE_GENERAL, _("General"));

            var advanced_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var env_group = SettingsShared.build_group (_("Environment Variables"), 12, 12, 0);

            var env_info_row = new Adw.ActionRow ();
            env_info_row.title = _("Prefix Runtime Variables");
            env_info_row.subtitle = _("Per-prefix env variables (includes component defaults seeded at install). These override global variables.");
            env_info_row.activatable = false;
            env_group.add (env_info_row);

            prefix_env_editor = new Lumoria.Widgets.EnvVarsEditor (entry.runtime_env_vars);
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

            var patches_group = SettingsShared.build_group (_("Patches"), 12, 12, 12);

            var laa_default = Utils.Preferences.instance ().large_address_aware ? _("enabled") : _("disabled");
            laa_combo = SettingsShared.build_toggle_override_combo (
                _("Large Address Aware"),
                entry.large_address_aware,
                laa_default,
                _("Toggle the Large Address Aware flag on PlayOnline before launch by default.")
            );
            patches_group.add (laa_combo);
            advanced_content.append (patches_group);

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
            toolbar.content = container;
            this.child = toolbar;
        }

        private void rebuild_version_combo (string preselect = "default") {
            var model = new Gtk.StringList (null);
            version_values.clear ();

            var sel_idx = (int) runner_combo.selected;
            var runner_id = (sel_idx >= 0 && sel_idx < runner_specs.size) ? runner_specs[sel_idx].id : "";

            var defaults = Utils.Preferences.instance ();
            var default_id = defaults.get_default_runner_id ();
            var default_ver = defaults.get_default_runner_version ();
            var default_label = default_id != "" ? "%s %s".printf (default_id, default_ver) : default_ver;
            model.append (_("Use Global Default (%s)").printf (default_label));
            version_values.add ("default");

            model.append (_("Latest (always newest)"));
            version_values.add ("latest");

            if (runner_id != "") {
                var base_dir = Path.build_filename (Utils.runner_dir (), runner_id);
                var installed = Utils.list_dirs (base_dir);
                foreach (var dir_name in installed) {
                    model.append (dir_name);
                    version_values.add (dir_name);
                }
            }

            version_combo.model = model;

            int selected = 0;
            for (int i = 0; i < version_values.size; i++) {
                if (version_values[i] == preselect) {
                    selected = i;
                    break;
                }
            }
            version_combo.selected = selected;
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
            rebuild_variant_combo ();
            rebuild_version_combo ();
        }

        private void on_save () {
            var sel = (int) runner_combo.selected;
            if (sel < 0 || sel >= runner_specs.size) return;
            string env_error;
            if (!prefix_env_editor.validate (out env_error)) {
                SettingsShared.present_alert (this, _("Invalid Environment Variables"), env_error);
                return;
            }
            if (runner_specs[sel].selectable_variants (Utils.is_sandboxed ()).size == 0) {
                SettingsShared.present_alert (this,
                    _("Runner Not Supported"),
                    _("The selected runner has no compatible variants in this environment."));
                return;
            }

            var ver_idx = (int) version_combo.selected;
            var runner_version = "default";
            if (ver_idx >= 0 && ver_idx < version_values.size) {
                runner_version = version_values[ver_idx];
            }

            registry.update_runner (prefix_index, runner_specs[sel].id, runner_version);

            if (variant_combo.visible) {
                var vi = (int) variant_combo.selected;
                if (vi >= 0 && vi < visible_variants.size) {
                    registry.prefixes[prefix_index].variant_id = visible_variants[vi].id;
                }
            }

            registry.prefixes[prefix_index].sync_mode = RunnerSettingsShared.sync_mode_value_for_index (sync_combo.selected);

            registry.prefixes[prefix_index].wine_debug = Runtime.wine_debug_value_for_index (debug_combo.selected);

            var wayland_override = RunnerSettingsShared.wayland_value_for_index (wayland_combo.selected);
            registry.prefixes[prefix_index].wine_wayland = wayland_override;
            registry.prefixes[prefix_index].large_address_aware =
                ((ToggleOverrideState) laa_combo.selected).to_nullable_bool ();
            registry.prefixes[prefix_index].runtime_env_vars = prefix_env_editor.values ();
            int ep_idx = (int) entrypoint_combo.selected;
            if (ep_idx < 0 || ep_idx >= entrypoint_values.size) ep_idx = 0;
            registry.prefixes[prefix_index].launch_entrypoint_id = entrypoint_values[ep_idx];

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
            var dialog = new Adw.AlertDialog (
                _("Reset to Global Defaults?"),
                _("This will reset the prefix to the global default settings.")
            );
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("reset", _("Reset"));
            dialog.set_response_appearance ("reset", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response != "reset") return;
                var entry = registry.prefixes[prefix_index];
                entry.runner_version = "default";
                entry.launch_entrypoint_id = "";
                entry.sync_mode = "";
                entry.wine_debug = "";
                entry.wine_wayland = null;
                entry.large_address_aware = null;
                entry.runtime_env_vars.clear ();
                entry.runtime_component_overrides.clear ();
                saved ();
                close ();
            });
            dialog.present (this);
        }

        private void on_remove_prefix () {
            var entry = registry.prefixes[prefix_index];
            SettingsShared.present_remove_prefix_dialog (this, entry, (deleted_files) => {
                registry.remove_at (prefix_index);
                removed ();
                close ();
            });
        }
    }
}
