namespace Lumoria.Widgets.Dialogs {

    public class ManagePrefixDialog : Adw.Dialog {
        public signal void saved ();
        public signal void removed ();

        private Models.PrefixRegistry registry;
        private int prefix_index;
        private Gee.ArrayList<Models.RunnerSpec> runner_specs;
        private Gee.ArrayList<Models.LauncherSpec> launcher_specs;

        private OptionListRow runner_combo;
        private OptionListRow variant_combo;
        private OptionListRow version_combo;
        private OptionListRow sync_combo;
        private OptionListRow debug_combo;
        private OptionListRow wayland_combo;
        private OptionListRow laa_combo;

        private Gee.ArrayList<string> version_values;
        private Gee.ArrayList<Models.RunnerVariant> visible_variants;
        private Gee.HashMap<string, OptionListRow> component_mode_rows;
        private OptionListRow entrypoint_combo;
        private Gee.ArrayList<string> entrypoint_values;
        private Adw.ActionRow prelaunch_row;
        private string prelaunch_script_path;
        private Gee.ArrayList<Models.Entrypoint> custom_entries;
        private Adw.PreferencesGroup custom_entries_group;
        private Gee.ArrayList<Gtk.Widget> custom_entry_rows;
        private Lumoria.Widgets.EnvVarsEditor prefix_env_editor;
        private Gtk.Label env_validation_label;
        private Adw.ToastOverlay toast_overlay;

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
            component_mode_rows = new Gee.HashMap<string, OptionListRow> ();
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
                default_btn.label = _("Quick Launch");
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

            entrypoint_combo = new OptionListRow ();
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
            
            custom_entries = new Gee.ArrayList<Models.Entrypoint> ();
            foreach (var ep in entry.custom_entrypoints) {
                var copy = new Models.Entrypoint ();
                copy.id = ep.id;
                copy.name = ep.name;
                copy.exe = ep.exe;
                copy.args = new Gee.ArrayList<string> ();
                copy.args.add_all (ep.args);
                custom_entries.add (copy);
            }
            custom_entry_rows = new Gee.ArrayList<Gtk.Widget> ();

            custom_entries_group = SettingsShared.build_group (_("Custom Launch Entries"), 12, 12);
            rebuild_custom_entries_ui ();
            general_content.append (custom_entries_group);

            var prelaunch_group = SettingsShared.build_group (_("Prelaunch"), 12, 12);
            prelaunch_script_path = entry.prelaunch_script;

            prelaunch_row = new Adw.ActionRow ();
            prelaunch_row.title = _("Prelaunch Script");
            prelaunch_row.subtitle = prelaunch_script_path != ""
                ? prelaunch_script_path
                : _("None");

            var prelaunch_browse_btn = new Gtk.Button.with_label (_("Browse\u2026"));
            prelaunch_browse_btn.valign = Gtk.Align.CENTER;
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
            general_content.append (prelaunch_group);


            var runner_group = SettingsShared.build_group (_("Runner"), 12);

            var runner_model = RunnerSettingsShared.build_runner_model (runner_specs);
            runner_combo = new OptionListRow ();
            runner_combo.title = _("Runner");
            runner_combo.model = runner_model;
            runner_combo.selected = RunnerSettingsShared.select_runner_index (runner_specs, entry.runner_id);
            runner_combo.notify["selected"].connect (on_runner_changed);
            runner_group.add (runner_combo);

            variant_combo = new OptionListRow ();
            variant_combo.title = _("Variant");
            runner_group.add (variant_combo);
            rebuild_variant_combo (entry.variant_id);

            version_combo = new OptionListRow ();
            version_combo.title = _("Version");
            version_values = new Gee.ArrayList<string> ();
            runner_group.add (version_combo);
            rebuild_version_combo (entry.runner_version);

            sync_combo = RunnerSettingsShared.build_sync_override_combo (entry.sync_mode);
            runner_group.add (sync_combo);

            debug_combo = RunnerSettingsShared.build_debug_override_combo (entry.wine_debug);
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

            if (Utils.Preferences.instance ().experimental_features) {
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

        private void rebuild_version_combo (string preselect = "default") {
            var model = new Gtk.StringList (null);
            version_values.clear ();

            var sel_idx = (int) runner_combo.selected;
            var runner_id = (sel_idx >= 0 && sel_idx < runner_specs.size) ? runner_specs[sel_idx].id : "";

            var defaults = Utils.Preferences.instance ();
            var default_id = defaults.runner_id;
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
        }

        private void show_custom_entry_editor (int index) {
            if (index < 0) {
                if (SettingsShared.file_browse_blocked (toast_overlay)) return;
                var file_dialog = build_file_dialog (_("Select Executable"), build_exe_filter ());
                file_dialog.open.begin (null, null, (obj, res) => {
                    try {
                        var file = file_dialog.open.end (res);
                        if (file == null) return;
                        var path = file.get_path ();
                        if (path == null || path == "") return;
                        present_entry_editor (-1, path);
                    } catch (Error e) {
                        warning ("Browse failed: %s", e.message);
                    }
                });
            } else {
                present_entry_editor (index, null);
            }
        }

        private void present_entry_editor (int index, string? initial_exe) {
            Models.Entrypoint? existing = (index >= 0 && index < custom_entries.size)
                ? custom_entries[index] : null;

            var dialog = new Adw.Dialog ();
            dialog.title = existing != null ? _("Edit Custom Entry") : _("Add Custom Entry");
            dialog.content_width = 460;

            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = true;
            toolbar.add_top_bar (header);

            var group = new Adw.PreferencesGroup ();
            group.margin_start = 16;
            group.margin_end = 16;
            group.margin_top = 16;
            group.margin_bottom = 8;

            var name_row = new Adw.EntryRow ();
            name_row.title = _("Name");
            if (existing != null) {
                name_row.text = existing.name;
            } else if (initial_exe != null) {
                name_row.text = Path.get_basename (initial_exe);
            }
            group.add (name_row);

            var exe_path = initial_exe ?? (existing != null ? existing.exe : "");

            var exe_row = new Adw.ActionRow ();
            exe_row.title = _("Executable");
            exe_row.subtitle = exe_path != "" ? exe_path : _("None selected");
            exe_row.subtitle_lines = 2;

            var browse_btn = new Gtk.Button.with_label (_("Browse\u2026"));
            browse_btn.valign = Gtk.Align.CENTER;
            browse_btn.clicked.connect (() => {
                if (SettingsShared.file_browse_blocked (toast_overlay)) return;
                var file_dialog = build_file_dialog (_("Select Executable"), build_exe_filter ());
                file_dialog.open.begin (null, null, (obj, res) => {
                    try {
                        var file = file_dialog.open.end (res);
                        if (file == null) return;
                        var path = file.get_path ();
                        if (path == null || path == "") return;
                        exe_path = path;
                        exe_row.subtitle = path;
                        if (name_row.text.strip () == "") {
                            name_row.text = Path.get_basename (path);
                        }
                    } catch (Error e) {
                        warning ("Browse failed: %s", e.message);
                    }
                });
            });
            exe_row.add_suffix (browse_btn);
            group.add (exe_row);

            var args_row = new Adw.EntryRow ();
            args_row.title = _("Arguments (space-separated)");
            args_row.text = existing != null && existing.args.size > 0
                ? string.joinv (" ", existing.args.to_array ()) : "";
            group.add (args_row);

            var entry_prelaunch_path = existing != null ? existing.prelaunch_script : "";

            var entry_prelaunch_row = new Adw.ActionRow ();
            entry_prelaunch_row.title = _("Prelaunch Script");
            entry_prelaunch_row.subtitle = entry_prelaunch_path != "" ? entry_prelaunch_path : _("None");
            entry_prelaunch_row.subtitle_lines = 2;

            var ep_browse_btn = new Gtk.Button.with_label (_("Browse\u2026"));
            ep_browse_btn.valign = Gtk.Align.CENTER;
            ep_browse_btn.clicked.connect (() => {
                if (SettingsShared.file_browse_blocked (toast_overlay)) return;
                var fd = build_file_dialog (_("Select Prelaunch Script"), build_script_filter ());
                fd.open.begin (null, null, (obj, res) => {
                    try {
                        var file = fd.open.end (res);
                        if (file == null) return;
                        var path = file.get_path ();
                        if (path == null || path == "") return;
                        entry_prelaunch_path = path;
                        entry_prelaunch_row.subtitle = path;
                    } catch (Error e) {
                        warning ("Browse failed: %s", e.message);
                    }
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
            entry_prelaunch_row.add_suffix (ep_clear_btn);
            group.add (entry_prelaunch_row);

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

                var ep = existing ?? new Models.Entrypoint ();
                ep.name = name_row.text.strip ();
                ep.exe = exe_path;
                ep.prelaunch_script = entry_prelaunch_path;
                ep.args = new Gee.ArrayList<string> ();
                foreach (var arg in args_row.text.split (" ")) {
                    var a = arg.strip ();
                    if (a != "") ep.args.add (a);
                }
                if (ep.id == "") {
                    ep.id = "custom-%s".printf (Checksum.compute_for_string (ChecksumType.MD5, ep.exe));
                }

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
            content.append (group);
            content.append (actions);
            toolbar.content = content;
            dialog.child = toolbar;

            dialog.present (this);
        }

        private void on_browse_prelaunch () {
            if (SettingsShared.file_browse_blocked (toast_overlay)) return;
            var dialog = build_file_dialog (_("Select prelaunch script"), build_script_filter ());
            dialog.open.begin (null, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file == null) return;
                    var path = file.get_path ();
                    if (path != null && path != "") {
                        prelaunch_script_path = path;
                        prelaunch_row.subtitle = path;
                    }
                } catch (Error e) {
                    warning ("Failed to select prelaunch script: %s", e.message);
                }
            });
        }

        private Gtk.FileDialog build_file_dialog (string title, Gtk.FileFilter primary) {
            var all = new Gtk.FileFilter ();
            all.name = _("All Files");
            all.add_pattern ("*");

            var store = new GLib.ListStore (typeof (Gtk.FileFilter));
            store.append (primary);
            store.append (all);

            var d = new Gtk.FileDialog ();
            d.title = title;
            d.modal = true;
            d.filters = store;
            d.default_filter = primary;
            return d;
        }

        private Gtk.FileFilter build_exe_filter () {
            var f = new Gtk.FileFilter ();
            f.name = _("Windows Executables");
            f.add_mime_type ("application/x-ms-dos-executable");
            f.add_mime_type ("application/x-msi");
            f.add_pattern ("*.exe");
            f.add_pattern ("*.bat");
            f.add_pattern ("*.msi");
            f.add_pattern ("*.com");
            return f;
        }

        private Gtk.FileFilter build_script_filter () {
            var f = new Gtk.FileFilter ();
            f.name = _("Shell Scripts");
            f.add_mime_type ("application/x-shellscript");
            f.add_mime_type ("text/x-shellscript");
            f.add_pattern ("*.sh");
            f.add_pattern ("*.bash");
            return f;
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

            registry.prefixes[prefix_index].sync_mode = RunnerSettingsShared.sync_override_value_for_index (sync_combo.selected);

            registry.prefixes[prefix_index].wine_debug = RunnerSettingsShared.debug_override_value_for_index (debug_combo.selected);

            var wayland_override = RunnerSettingsShared.wayland_value_for_index (wayland_combo.selected);
            registry.prefixes[prefix_index].wine_wayland = wayland_override;
            if (laa_combo != null) {
                registry.prefixes[prefix_index].large_address_aware =
                    ((ToggleOverrideState) laa_combo.selected).to_nullable_bool ();
            }
            registry.prefixes[prefix_index].prelaunch_script = prelaunch_script_path;
            registry.prefixes[prefix_index].custom_entrypoints = custom_entries;
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
