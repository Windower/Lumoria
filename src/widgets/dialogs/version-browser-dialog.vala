namespace Lumoria.Widgets.Dialogs {

    public class VersionBrowserDialog : DialogHelpers.GamepadDialog {
        private const int RELEASE_PAGE_SIZE = 30;

        public signal void version_selected (string value);
        public signal void defaults_changed (string message);

        private Runtime.ToolAdapter tool;
        private bool pick_mode;
        private string current_value;
        private string inherit_label;
        private string inherit_value;

        private Adw.EntryRow search_row;
        private Adw.SwitchRow hidden_row;
        private Adw.PreferencesGroup versions_group;
        private Gtk.Button previous_btn;
        private Gtk.Button next_btn;
        private Gtk.Label page_label;
        private Gtk.Spinner spinner;

        private Adw.ActionRow? latest_row;
        private Gee.ArrayList<Adw.ActionRow> release_rows;
        private Gee.ArrayList<Preferences.VersionRow> manage_rows;
        private int current_page = 1;
        private bool has_more = true;
        private bool loading = false;
        private bool load_failed = false;
        private Utils.Debouncer search;
        private string last_searched_query = "";

        public VersionBrowserDialog.pick (
            Runtime.ToolAdapter tool,
            string current_value,
            string inherit_label,
            string inherit_value = ""
        ) {
            Object (
                title: _("Select Version"),
                content_width: Lumoria.Ui.Metrics.DIALOG_WIDTH_WIDE,
                content_height: 640
            );
            this.tool = tool;
            this.pick_mode = true;
            this.inherit_label = inherit_label;
            this.inherit_value = inherit_value;
            var current = current_value.strip ();
            this.current_value = Models.ToolVersionRef.is_inherit (current) ? inherit_value : current;
            finish_init ();
        }

        public VersionBrowserDialog.manage (Runtime.ToolAdapter tool) {
            Object (
                title: _("Versions"),
                content_width: Lumoria.Ui.Metrics.DIALOG_WIDTH_WIDE,
                content_height: 640
            );
            this.tool = tool;
            this.pick_mode = false;
            this.inherit_label = "";
            this.inherit_value = "";
            this.current_value = "";
            finish_init ();
        }

        private void finish_init () {
            search = new Utils.Debouncer (300, run_search);
            release_rows = new Gee.ArrayList<Adw.ActionRow> ();
            manage_rows = new Gee.ArrayList<Preferences.VersionRow> ();
            build_ui ();
            load_page (1, false);
        }

        private void build_ui () {
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var search_group = PageChrome.build_group (_("Search"));
            search_row = new Adw.EntryRow ();
            search_row.title = _("Version");
            search_row.notify["text"].connect (schedule_search);
            var refresh = new Gtk.Button.from_icon_name (IconRegistry.REFRESH);
            refresh.add_css_class ("flat");
            refresh.valign = Gtk.Align.CENTER;
            PageChrome.set_icon_label (refresh, _("Refresh releases"));
            refresh.clicked.connect (on_refresh);
            search_row.add_suffix (refresh);
            search_group.add (search_row);

            hidden_row = new Adw.SwitchRow ();
            hidden_row.title = _("Show Hidden Versions");
            hidden_row.subtitle = _("Include releases hidden by the manifest.");
            hidden_row.active = Utils.Preferences.instance ().show_hidden_tool_versions;
            hidden_row.notify["active"].connect (on_hidden_toggled);
            search_group.add (hidden_row);
            content.append (search_group);

            versions_group = PageChrome.build_group (_("Versions"));
            if (inherit_label != "") {
                add_pick_row (inherit_label, inherit_value, "");
            }
            if (pick_mode) {
                latest_row = add_pick_row (_("Latest (always newest)"), Models.ToolVersionRef.LATEST.id (), "");
            } else {
                latest_row = add_manage_row (new Models.ToolVersion.latest (""));
            }
            content.append (PageChrome.scrolled (versions_group));

            var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, Lumoria.Ui.Metrics.EDITOR_INSET);
            PageChrome.margins (controls, Lumoria.Ui.Metrics.PAGE_MARGIN, Lumoria.Ui.Metrics.EDITOR_INSET);
            controls.valign = Gtk.Align.CENTER;

            previous_btn = new Gtk.Button.with_label (_("Previous"));
            previous_btn.clicked.connect (load_previous);
            controls.append (previous_btn);

            page_label = new Gtk.Label ("");
            page_label.hexpand = true;
            page_label.halign = Gtk.Align.CENTER;
            controls.append (page_label);

            spinner = new Gtk.Spinner ();
            controls.append (spinner);

            next_btn = new Gtk.Button.with_label (_("Next"));
            next_btn.clicked.connect (load_next);
            controls.append (next_btn);

            content.append (controls);
            set_body (DialogHelpers.dialog_body (content));
            closed.connect (search.release);
        }

        private void on_hidden_toggled () {
            var prefs = Utils.Preferences.instance ();
            if (prefs.show_hidden_tool_versions == hidden_row.active) return;
            prefs.show_hidden_tool_versions = hidden_row.active;
            load_page (1, false);
        }

        private void load_previous () {
            if (current_page > 1) load_page (current_page - 1, false);
        }

        private void load_next () {
            if (has_more) load_page (current_page + 1, false);
        }

        private void on_refresh () {
            Utils.run_background ("invalidate-%s".printf (tool.tool_id), () => {
                tool.invalidate_cache ();
            }, (_) => {
                load_page (1, false);
            });
        }

        private Adw.ActionRow add_pick_row (string label, string value, string subtitle) {
            var row = new ChoiceRow (value, label, subtitle);
            row.mark_current (value == current_value);
            row.activated.connect (on_pick_activated);
            versions_group.add (row);
            return row;
        }

        private void on_pick_activated (Adw.ActionRow row) {
            version_selected (((ChoiceRow) row).value);
            close ();
        }

        private Preferences.VersionRow add_manage_row (Models.ToolVersion version) {
            var row = new Preferences.VersionRow (tool, version);
            row.default_set.connect ((msg) => {
                foreach (var other in manage_rows) {
                    other.update_state ();
                }
                defaults_changed (msg);
            });
            versions_group.add (row);
            manage_rows.add (row);
            return row;
        }

        private void add_release_row (Models.ToolVersion version, string subtitle) {
            release_rows.add (pick_mode ? add_pick_row (version.tag, version.tag, subtitle) : add_manage_row (version));
        }

        private void load_page (int page, bool search_until_match) {
            if (loading) return;
            if (tool.github_repo == "") {
                show_installed_only ();
                return;
            }

            loading = true;
            spinner.visible = true;
            spinner.spinning = true;
            update_controls ();

            var query = search_row.text.down ().strip ();
            last_searched_query = query;

            var result = new ReleasePageResult ();
            Utils.run_background ("version-browser-%s".printf (tool.tool_id), () => {
                var next_page = page;
                while (true) {
                    var version_page = tool.list_version_page (next_page, RELEASE_PAGE_SIZE);
                    result.page = version_page.page;
                    result.has_more = version_page.has_more;
                    foreach (var version in version_page.versions) {
                        if (version.is_latest) {
                            if (next_page == 1) result.latest = version;
                            continue;
                        }
                        if (query != "" && !version.tag.down ().contains (query)) continue;
                        result.versions.add (version);
                    }
                    if (!search_until_match || result.versions.size > 0 || !version_page.has_more) break;
                    next_page++;
                }
            }, (error) => {
                loading = false;
                spinner.spinning = false;
                spinner.visible = false;
                load_failed = error != null;
                if (load_failed) {
                    page_label.label = _("Failed: %s").printf (user_error (error));
                    update_controls ();
                    return;
                }
                current_page = result.page;
                has_more = result.has_more;
                apply_latest (result.latest);
                replace_release_rows (result);
                navigator.refresh ();
                update_controls ();
                if (search_row.text.down ().strip () != last_searched_query) {
                    schedule_search ();
                }
            });
        }

        private void show_installed_only () {
            var result = new ReleasePageResult ();
            result.page = 1;
            result.has_more = false;
            var query = search_row.text.down ().strip ();
            foreach (var dir in Utils.list_dirs (tool.install_base_dir)) {
                if (dir.strip () == "") continue;
                if (query != "" && !dir.down ().contains (query)) continue;
                result.versions.add (new Models.ToolVersion (dir));
            }
            current_page = 1;
            has_more = false;
            replace_release_rows (result);
            update_controls ();
        }

        private void apply_latest (Models.ToolVersion? latest) {
            if (latest_row == null || latest == null) return;
            latest_row.subtitle = latest.description;
            var managed = latest_row as Preferences.VersionRow;
            if (managed != null) managed.update_state ();
        }

        private void replace_release_rows (ReleasePageResult result) {
            clear_release_rows ();
            foreach (var version in result.versions) {
                if (!tool.is_installed (version)) continue;
                add_release_row (version, _("Installed"));
            }
            foreach (var version in result.versions) {
                if (tool.is_installed (version)) continue;
                add_release_row (version, "");
            }
            if (result.versions.size == 0) {
                var row = PageChrome.placeholder_row (_("No matching releases on this page"));
                versions_group.add (row);
                release_rows.add (row);
            }
        }

        private void clear_release_rows () {
            foreach (var row in release_rows) {
                versions_group.remove (row);
                var managed = row as Preferences.VersionRow;
                if (managed != null) manage_rows.remove (managed);
            }
            release_rows.clear ();
        }

        private void schedule_search () {
            update_controls ();
            search.schedule ();
        }

        private void run_search () {
            var query = search_row.text.down ().strip ();
            if (query != last_searched_query) load_page (1, query != "");
        }

        private void update_controls () {
            previous_btn.sensitive = !loading && current_page > 1;
            next_btn.sensitive = !loading && has_more && search_row.text.strip () == "";
            if (!loading && !load_failed) {
                page_label.label = _("Page %d").printf (current_page);
            }
        }

        private class ReleasePageResult : Object {
            public Gee.ArrayList<Models.ToolVersion> versions {
                get; owned set; default = new Gee.ArrayList<Models.ToolVersion> ();
            }
            public Models.ToolVersion? latest { get; set; default = null; }
            public int page { get; set; default = 1; }
            public bool has_more { get; set; default = false; }
        }
    }
}
