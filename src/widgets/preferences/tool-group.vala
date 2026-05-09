namespace Lumoria.Widgets.Preferences {

    public class ToolGroupWidget : Adw.PreferencesGroup {
        private const int RELEASE_PAGE_SIZE = 30;

        public signal void toast_message (string message);

        private Models.ToolSpec tool;
        private Adw.ExpanderRow expander;
        private Adw.ActionRow? default_row = null;
        private Adw.SwitchRow? enabled_row = null;
        private Gtk.Spinner spinner;
        private Gtk.Button refresh_btn;
        private Gee.ArrayList<VersionRow> version_rows;
        private Gee.ArrayList<Models.ToolVersion> loaded_versions;
        private Adw.EntryRow? search_row = null;
        private Adw.ActionRow? load_more_row = null;
        private int next_page = 1;
        private bool has_more = true;
        private bool loading = false;
        private bool loaded = false;

        public ToolGroupWidget (Models.ToolSpec tool) {
            this.tool = tool;

            version_rows = new Gee.ArrayList<VersionRow> ();
            loaded_versions = new Gee.ArrayList<Models.ToolVersion> ();

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
            next_page = 1;
            has_more = true;

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
            loaded_versions.clear ();
            if (search_row != null) {
                expander.remove (search_row);
                search_row = null;
            }
            if (load_more_row != null) {
                expander.remove (load_more_row);
                load_more_row = null;
            }
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
            load_version_page (false);
        }

        private void load_version_page (bool search_until_match) {
            if (loading || !has_more) return;
            loading = true;
            spinner.visible = true;
            spinner.spinning = true;
            expander.subtitle = _("Loading releases\u2026");

            new Thread<bool> ("load-versions-%s".printf (tool.tool_id), () => {
                var page_versions = new Gee.ArrayList<Models.ToolVersion> ();
                string? error_msg = null;
                bool more = false;
                var page = next_page;
                try {
                    while (true) {
                        var version_page = tool.list_version_page (page, RELEASE_PAGE_SIZE);
                        foreach (var version in version_page.versions) {
                            page_versions.add (version);
                        }
                        more = version_page.has_more;
                        page++;

                        if (!search_until_match || !more || page_matches_search (page_versions)) break;
                    }
                } catch (Error e) {
                    error_msg = e.message;
                }

                var versions = page_versions;
                var err = error_msg;
                var new_next_page = page;
                var new_has_more = more;
                Idle.add (() => {
                    loading = false;
                    spinner.visible = false;
                    spinner.spinning = false;
                    refresh_btn.sensitive = true;

                    if (err != null) {
                        expander.subtitle = _("Failed: %s").printf (err);
                        return false;
                    }

                    append_loaded_versions (versions);
                    next_page = new_next_page;
                    has_more = new_has_more;

                    if (loaded_versions.size == 0) {
                        expander.subtitle = _("No releases found");
                        loaded = true;
                        return false;
                    }

                    ensure_control_rows ();
                    rebuild_version_rows ();
                    loaded = true;
                    return false;
                });
                return true;
            });
        }

        private bool page_matches_search (Gee.ArrayList<Models.ToolVersion> versions) {
            var query = current_search_query ();
            if (query == "") return true;
            foreach (var version in versions) {
                if (version.is_latest) continue;
                if (version.tag.down ().contains (query)) return true;
            }
            return false;
        }

        private void append_loaded_versions (Gee.ArrayList<Models.ToolVersion> versions) {
            foreach (var version in versions) {
                if (has_loaded_version (version)) continue;
                loaded_versions.add (version);
            }
        }

        private bool has_loaded_version (Models.ToolVersion version) {
            foreach (var loaded_version in loaded_versions) {
                if (loaded_version.is_latest == version.is_latest && loaded_version.tag == version.tag) {
                    return true;
                }
            }
            return false;
        }

        private void ensure_control_rows () {
            if (search_row == null) {
                search_row = new Adw.EntryRow ();
                search_row.title = _("Search Versions");
                search_row.notify["text"].connect (() => {
                    rebuild_version_rows ();
                });
                expander.add_row (search_row);
            }
            update_load_more_row ();
        }

        private void rebuild_version_rows () {
            foreach (var row in version_rows) {
                expander.remove (row);
            }
            version_rows.clear ();
            if (load_more_row != null) {
                expander.remove (load_more_row);
                load_more_row = null;
            }

            var query = current_search_query ();
            int release_count = 0;
            int visible_count = 0;
            foreach (var ver in loaded_versions) {
                if (!ver.is_latest) release_count++;
                if (query != "" && !ver.is_latest && !ver.tag.down ().contains (query)) continue;

                var row = new VersionRow (tool, ver);
                wire_row_signals (row);
                version_rows.add (row);
                expander.add_row (row);
                visible_count++;
            }

            update_load_more_row ();
            expander.subtitle = has_more
                ? _("%d release(s), more available").printf (release_count)
                : _("%d release(s)").printf (release_count);
            if (query != "" && visible_count == 0 && has_more) {
                expander.subtitle = _("No loaded matches; search older releases");
            }
        }

        private void update_load_more_row () {
            if (!has_more) {
                if (load_more_row != null) {
                    expander.remove (load_more_row);
                    load_more_row = null;
                }
                return;
            }

            if (load_more_row == null) {
                load_more_row = new Adw.ActionRow ();
                load_more_row.activatable = true;
                load_more_row.activated.connect (() => {
                    load_version_page (current_search_query () != "");
                });
                expander.add_row (load_more_row);
            }

            if (current_search_query () != "") {
                load_more_row.title = _("Search Older Releases");
                load_more_row.subtitle = _("Fetch more GitHub releases for this search");
            } else {
                load_more_row.title = _("Load Older Versions");
                load_more_row.subtitle = _("Fetch the next GitHub release page");
            }
        }

        private string current_search_query () {
            if (search_row == null) return "";
            return search_row.text.down ().strip ();
        }
    }
}
