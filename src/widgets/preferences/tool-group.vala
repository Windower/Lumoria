namespace Lumoria.Widgets.Preferences {

    public class ToolGroupWidget : Adw.PreferencesGroup {
        private const int MAX_VISIBLE_RELEASES = 20;

        public signal void toast_message (string message);

        private Models.ToolSpec tool;
        private Adw.ExpanderRow expander;
        private Adw.ActionRow? default_row = null;
        private Adw.SwitchRow? enabled_row = null;
        private Gtk.Spinner spinner;
        private Gtk.Button refresh_btn;
        private Gee.ArrayList<VersionRow> version_rows;
        private bool loaded = false;

        public ToolGroupWidget (Models.ToolSpec tool) {
            this.tool = tool;

            version_rows = new Gee.ArrayList<VersionRow> ();

            title = tool.tool_name;
            description = tool.tool_description;
            margin_start = 24;
            margin_end = 24;
            margin_top = 12;

            if (tool.tool_kind == Utils.ToolKind.COMPONENT) {
                enabled_row = new Adw.SwitchRow ();
                enabled_row.title = _("Enabled");
                enabled_row.subtitle = _("Apply this component to prefixes during install and launch");
                var defaults = Utils.Preferences.instance ();
                enabled_row.active = defaults.is_component_enabled (tool.tool_id);
                enabled_row.notify["active"].connect (() => {
                    Utils.Preferences.instance ().set_component_enabled (tool.tool_id, enabled_row.active);
                });
                add (enabled_row);
            }

            if (tool.tool_kind != Utils.ToolKind.RUNNER) {
                default_row = new Adw.ActionRow ();
                default_row.title = _("Default Version");
                update_default_label ();
                add (default_row);
            }

            expander = new Adw.ExpanderRow ();
            expander.title = _("Available Versions");
            expander.subtitle = _("Expand to browse releases");

            var suffix_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            suffix_box.valign = Gtk.Align.CENTER;

            spinner = new Gtk.Spinner ();
            spinner.visible = false;
            suffix_box.append (spinner);

            refresh_btn = new Gtk.Button.from_icon_name (IconRegistry.REFRESH);
            refresh_btn.add_css_class ("flat");
            refresh_btn.tooltip_text = _("Refresh releases");
            refresh_btn.clicked.connect (on_refresh);
            suffix_box.append (refresh_btn);

            expander.add_suffix (suffix_box);

            expander.notify["expanded"].connect (() => {
                if (expander.expanded && !loaded) {
                    load_versions ();
                }
            });

            add (expander);
        }

        public void refresh_all_stars () {
            foreach (var r in version_rows) {
                r.update_state ();
            }
        }

        private void update_default_label () {
            if (default_row == null) return;
            var defaults = Utils.Preferences.instance ();

            switch (tool.tool_kind) {
                case Utils.ToolKind.RUNNER:
                    var def_id = defaults.runner_id;
                    var def_ver = defaults.get_default_runner_version ();
                    if (def_id == tool.tool_id) {
                        default_row.subtitle = def_ver;
                    } else if (def_id == "") {
                        default_row.subtitle = _("Not set");
                    } else {
                        default_row.subtitle = _("Other runner (%s %s)").printf (def_id, def_ver);
                    }
                    break;
                case Utils.ToolKind.COMPONENT:
                    default_row.subtitle = defaults.get_tool_version (tool.tool_kind, tool.tool_id);
                    break;
            }
        }

        private void on_refresh () {
            refresh_btn.sensitive = false;
            loaded = false;

            new Thread<bool> ("invalidate-%s".printf (tool.tool_id), () => {
                tool.invalidate_cache ();
                Idle.add (() => {
                    clear_version_rows ();
                    load_versions ();
                    return false;
                });
                return true;
            });
        }

        private void clear_version_rows () {
            foreach (var row in version_rows) {
                expander.remove (row);
            }
            version_rows.clear ();
        }

        private void wire_row_signals (VersionRow row) {
            row.default_set.connect ((msg) => {
                update_default_label ();
                foreach (var r in version_rows) {
                    r.update_state ();
                }
                toast_message (msg);
            });
        }

        private void load_versions () {
            spinner.visible = true;
            spinner.spinning = true;
            expander.subtitle = _("Loading releases\u2026");

            new Thread<bool> ("load-versions-%s".printf (tool.tool_id), () => {
                Gee.ArrayList<Models.ToolVersion>? versions = null;
                string? error_msg = null;
                try {
                    versions = tool.list_versions ();
                } catch (Error e) {
                    error_msg = e.message;
                }

                var vers = versions;
                var err = error_msg;
                Idle.add (() => {
                    spinner.visible = false;
                    spinner.spinning = false;
                    refresh_btn.sensitive = true;

                    if (err != null) {
                        expander.subtitle = _("Failed: %s").printf (err);
                        return false;
                    }

                    if (vers == null || vers.size == 0) {
                        expander.subtitle = _("No releases found");
                        loaded = true;
                        return false;
                    }

                    int release_count = 0;
                    foreach (var ver in vers) {
                        var row = new VersionRow (tool, ver);
                        wire_row_signals (row);
                        version_rows.add (row);
                        expander.add_row (row);
                        if (!ver.is_latest) {
                            release_count++;
                        }
                        if (release_count >= MAX_VISIBLE_RELEASES && !ver.is_latest) break;
                    }

                    expander.subtitle = _("%d release(s)").printf (release_count);
                    loaded = true;
                    return false;
                });
                return true;
            });
        }
    }
}
