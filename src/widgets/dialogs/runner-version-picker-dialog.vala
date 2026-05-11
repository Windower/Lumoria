namespace Lumoria.Widgets.Dialogs {

    public class RunnerVersionPickerDialog : Adw.Dialog {
        private const int RELEASE_PAGE_SIZE = 30;

        public signal void version_selected (string label, string value);

        private Models.RunnerSpec runner;
        private Models.RunnerVariant? variant;
        private string current_value;

        private Adw.EntryRow search_row;
        private Adw.PreferencesGroup versions_group;
        private Gtk.Button previous_btn;
        private Gtk.Button next_btn;
        private Gtk.Label page_label;
        private Gtk.Spinner spinner;

        private Gee.ArrayList<Adw.ActionRow> release_rows;
        private Gee.HashSet<string> installed_set;
        private int current_page = 1;
        private bool has_more = true;
        private bool loading = false;
        private uint search_timeout_id = 0;
        private string last_searched_query = "";

        public RunnerVersionPickerDialog (
            Models.RunnerSpec runner,
            Models.RunnerVariant? variant,
            string current_value
        ) {
            Object (
                title: _("Select Version"),
                content_width: 560,
                content_height: 640
            );

            this.runner = runner;
            this.variant = variant;
            this.current_value = current_value != "" ? current_value : "default";
            release_rows = new Gee.ArrayList<Adw.ActionRow> ();
            installed_set = new Gee.HashSet<string> ();
            foreach (var dir in Utils.list_dirs (Path.build_filename (Utils.runner_dir (), runner.id))) {
                installed_set.add (dir);
            }

            build_ui ();
            load_page (1, false);
        }

        private void build_ui () {
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = true;
            toolbar.add_top_bar (header);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var search_group = SettingsShared.build_group (_("Search"), 12);
            search_row = new Adw.EntryRow ();
            search_row.title = _("Version");
            search_row.notify["text"].connect (() => {
                schedule_search ();
            });
            search_group.add (search_row);
            content.append (search_group);

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;
            versions_group = SettingsShared.build_group (_("Versions"), 12, 12);
            add_fixed_row (default_label (), "default", _("Use the global/default runner version"));
            add_fixed_row (_("Latest (always newest)"), "latest", "");
            scroller.child = versions_group;
            content.append (scroller);

            var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            controls.margin_start = 12;
            controls.margin_end = 12;
            controls.margin_top = 8;
            controls.margin_bottom = 8;
            controls.valign = Gtk.Align.CENTER;

            previous_btn = new Gtk.Button.with_label (_("Previous"));
            previous_btn.clicked.connect (() => {
                if (current_page > 1) load_page (current_page - 1, false);
            });
            controls.append (previous_btn);

            page_label = new Gtk.Label ("");
            page_label.hexpand = true;
            page_label.halign = Gtk.Align.CENTER;
            controls.append (page_label);

            spinner = new Gtk.Spinner ();
            controls.append (spinner);

            next_btn = new Gtk.Button.with_label (_("Next"));
            next_btn.clicked.connect (() => {
                if (has_more) load_page (current_page + 1, false);
            });
            controls.append (next_btn);

            content.append (controls);
            toolbar.content = content;
            child = toolbar;
        }

        private void add_fixed_row (string label, string value, string subtitle) {
            var row = new Adw.ActionRow ();
            row.title = label;
            row.subtitle = subtitle;
            row.activatable = true;
            if (value == current_value) {
                var check = new Gtk.Image.from_icon_name (IconRegistry.CHECKMARK);
                row.add_suffix (check);
            }
            row.activated.connect (() => {
                version_selected (label, value);
                close ();
            });
            versions_group.add (row);
        }

        private string default_label () {
            var defaults = Utils.Preferences.instance ();
            var default_id = defaults.runner_id;
            var default_ver = defaults.get_default_runner_version ();
            if (runner.id != "" && runner.id != default_id) {
                return _("Use Runner Default (%s latest)").printf (runner.id);
            }
            var default_text = default_id != "" ? "%s %s".printf (default_id, default_ver) : default_ver;
            return _("Use Global Default (%s)").printf (default_text);
        }

        private void load_page (int page, bool search_until_match) {
            if (loading || variant == null || runner.github_repo == "") return;
            loading = true;
            spinner.visible = true;
            spinner.spinning = true;
            update_controls ();

            var query = search_row.text.down ().strip ();
            last_searched_query = query;
            var selected_variant = (Models.RunnerVariant) variant;

            new Thread<bool> ("runner-version-picker-%s".printf (runner.id), () => {
                var result = new ReleasePageResult ();
                try {
                    var next_page = page;
                    while (true) {
                        var cache_dir = Path.build_filename (Utils.cache_dir (), "runners", runner.id);
                        var releases = Utils.fetch_github_releases_page_sync (
                            runner.github_repo,
                            cache_dir,
                            next_page,
                            RELEASE_PAGE_SIZE,
                            6 * 3600
                        );
                        result.page = next_page;
                        result.has_more = releases.has_more;
                        foreach (var release in releases.releases) {
                            if (runner.skips_version (release.tag_name)) continue;
                            if (!release_has_variant_asset (release, selected_variant)) continue;
                            if (query != "" && !release.tag_name.down ().contains (query)) continue;
                            result.labels.add (release.tag_name);
                            result.values.add (release.tag_name);
                        }

                        if (!search_until_match || result.labels.size > 0 || !releases.has_more) break;
                        next_page++;
                    }
                } catch (Error e) {
                    result.error_message = e.message;
                }

                Idle.add (() => {
                    loading = false;
                    spinner.spinning = false;
                    spinner.visible = false;
                    if (result.error_message != null) {
                        page_label.label = _("Failed: %s").printf (result.error_message);
                        update_controls ();
                        return false;
                    }
                    current_page = result.page;
                    has_more = result.has_more;
                    replace_release_rows (result);
                    update_controls ();
                    var current_query = search_row.text.down ().strip ();
                    if (current_query != last_searched_query) {
                        schedule_search ();
                    }
                    return false;
                });
                return true;
            });
        }

        private bool release_has_variant_asset (Utils.GitHubRelease release, Models.RunnerVariant selected_variant) {
            try {
                return Utils.find_github_asset_by_regex (release, selected_variant.asset_regex) != null;
            } catch (RegexError e) {
                warning ("Invalid runner variant asset regex '%s': %s", selected_variant.asset_regex, e.message);
                return false;
            }
        }

        private void replace_release_rows (ReleasePageResult result) {
            clear_release_rows ();
            for (int i = 0; i < result.labels.size; i++) {
                if (installed_set.contains (result.values[i])) {
                    add_release_row (result.labels[i], result.values[i], _("Installed"));
                }
            }
            for (int i = 0; i < result.labels.size; i++) {
                if (!installed_set.contains (result.values[i])) {
                    add_release_row (result.labels[i], result.values[i], "");
                }
            }
            if (result.labels.size == 0) {
                var row = new Adw.ActionRow ();
                row.title = _("No matching releases on this page");
                row.activatable = false;
                versions_group.add (row);
                release_rows.add (row);
            }
        }

        private void clear_release_rows () {
            foreach (var row in release_rows) {
                versions_group.remove (row);
            }
            release_rows.clear ();
        }

        private void schedule_search () {
            if (search_timeout_id != 0) {
                GLib.Source.remove (search_timeout_id);
                search_timeout_id = 0;
            }
            update_controls ();
            search_timeout_id = GLib.Timeout.add (300, () => {
                search_timeout_id = 0;
                var query = search_row.text.down ().strip ();
                if (query == last_searched_query) return false;
                if (query != "") {
                    load_page (1, true);
                } else {
                    load_page (1, false);
                }
                return false;
            });
        }

        private void update_controls () {
            previous_btn.sensitive = !loading && current_page > 1;
            next_btn.sensitive = !loading && has_more && search_row.text.strip () == "";
            if (!loading && !page_label.label.has_prefix (_("Failed:"))) {
                page_label.label = _("Page %d").printf (current_page);
            }
        }

        private void add_release_row (string label, string value, string subtitle) {
            var row = new Adw.ActionRow ();
            row.title = label;
            row.subtitle = subtitle;
            row.activatable = true;
            if (value == current_value) {
                var check = new Gtk.Image.from_icon_name (IconRegistry.CHECKMARK);
                row.add_suffix (check);
            }
            row.activated.connect (() => {
                version_selected (label, value);
                close ();
            });
            versions_group.add (row);
            release_rows.add (row);
        }

        private class ReleasePageResult : Object {
            public Gee.ArrayList<string> labels { get; owned set; default = new Gee.ArrayList<string> (); }
            public Gee.ArrayList<string> values { get; owned set; default = new Gee.ArrayList<string> (); }
            public int page { get; set; default = 1; }
            public bool has_more { get; set; default = false; }
            public string? error_message { get; set; default = null; }
        }
    }
}
