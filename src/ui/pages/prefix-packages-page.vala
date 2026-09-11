namespace Lumoria.Ui {

    public class PrefixPackagesPage : Gtk.Box {
        private class PackageRow : Adw.ActionRow {
            public unowned Widgets.PageSection section;
            public string haystack;

            private Application.Context ctx;
            private Models.PrefixEntry entry;
            private Models.RedistManifest spec;
            private bool is_installed;
            private Gtk.Button install_btn;

            public PackageRow (
                Application.Context ctx,
                Models.PrefixEntry entry,
                Models.RedistManifest spec,
                bool is_installed,
                Widgets.PageSection section
            ) {
                this.ctx = ctx;
                this.entry = entry;
                this.spec = spec;
                this.is_installed = is_installed;
                this.section = section;
                title = spec.display_label ();
                var text = Widgets.ManifestUi.subtitle (spec);
                if (text != "") subtitle = text;
                haystack = "%s %s %s %s".printf (
                    spec.display_label (),
                    spec.id,
                    Models.RedistManifest.package_category_label (spec.package_category ()),
                    Widgets.ManifestUi.prose_markdown (spec)
                ).down ();

                install_btn = new Gtk.Button.with_label (is_installed ? _("Reinstall") : _("Install"));
                install_btn.valign = Gtk.Align.CENTER;
                if (!is_installed) install_btn.add_css_class ("suggested-action");
                install_btn.clicked.connect (confirm_install);
                sync_sensitive ();
                ctx.exclusive_changed.connect (sync_sensitive);

                var links = Widgets.Messages.link_icons (spec.links, null);
                if (links != null) add_suffix (links);
                add_suffix (install_btn);
                activatable_widget = install_btn;
            }

            private void sync_sensitive () {
                install_btn.sensitive = (!is_installed || spec.reinstallable) && !ctx.busy;
            }

            private void confirm_install () {
                Widgets.Dialogs.DialogHelpers.present_confirmation (
                    this,
                    is_installed ? _("Reinstall Package?") : _("Install Package?"),
                    _("Installing %s will close any programs currently running in this prefix.").printf (
                        spec.display_label ()
                    ),
                    "install",
                    is_installed ? _("Reinstall") : _("Install"),
                    Adw.ResponseAppearance.SUGGESTED,
                    () => ctx.installs.run_redist (entry, spec.id)
                );
            }
        }

        private class PackageGroup {
            public string idle_empty;
            public Adw.ActionRow empty;
            public Gtk.Widget empty_group;
            public Gee.ArrayList<PackageRow> rows;

            public PackageGroup (string idle_empty) {
                this.idle_empty = idle_empty;
                rows = new Gee.ArrayList<PackageRow> ();
            }

            public void apply_filter (string query) {
                var visible_sections = new Gee.HashSet<Widgets.PageSection> ();
                var any = false;
                foreach (var row in rows) {
                    var show = query == "" || row.haystack.contains (query);
                    row.visible = show;
                    if (!show) continue;
                    visible_sections.add (row.section);
                    any = true;
                }
                foreach (var row in rows) {
                    row.section.visible = visible_sections.contains (row.section);
                }
                empty.title = query == "" ? idle_empty : _("No matching packages");
                empty_group.visible = !any;
            }
        }

        private Application.Context ctx;
        private Models.PrefixEntry entry;
        private Gtk.SearchEntry search;
        private PackageGroup installed;
        private PackageGroup available;

        public PrefixPackagesPage (Application.Context ctx, Models.PrefixEntry entry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: Metrics.GROUP_SPACING);
            this.ctx = ctx;
            this.entry = entry;
            hexpand = true;
            vexpand = true;

            var specs = sorted_manifests ();
            installed = new PackageGroup (_("No packages installed yet"));
            available = new PackageGroup (_("All packages are installed"));
            var list = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            list.append (Widgets.PageChrome.section_caption (_("Installed")));
            fill_group (specs, true, installed, list);
            list.append (Widgets.PageChrome.section_caption (_("Available")));
            fill_group (specs, false, available, list);

            search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search packages");
            search.hexpand = true;
            search.margin_start = Metrics.PAGE_MARGIN;
            search.margin_end = Metrics.PAGE_MARGIN;
            search.margin_top = Metrics.EDITOR_INSET;
            search.search_changed.connect (apply_filter);

            append (search);
            append (Widgets.PageChrome.scrolled (list));
            apply_filter ();
        }

        private void apply_filter () {
            var query = search.text.down ().strip ();
            installed.apply_filter (query);
            available.apply_filter (query);
        }

        private static Gee.ArrayList<Models.RedistManifest> sorted_manifests () {
            var listed = Models.ManifestRepository.shared ().redists;
            if (listed.size > 0) return listed;
            var specs = new Gee.ArrayList<Models.RedistManifest> ();
            foreach (var spec in Models.ManifestRepository.shared ().all_redists.values) {
                specs.add (spec);
            }
            specs.sort ((a, b) => {
                int rank = Models.RedistManifest.package_category_rank (a.package_category ())
                    - Models.RedistManifest.package_category_rank (b.package_category ());
                if (rank != 0) return rank;
                return a.display_label ().collate (b.display_label ());
            });
            return specs;
        }

        private void fill_group (
            Gee.ArrayList<Models.RedistManifest> specs,
            bool want_installed,
            PackageGroup group,
            Gtk.Box list
        ) {
            Widgets.PageSection? current = null;
            string current_key = "";
            foreach (var spec in specs) {
                var is_installed = entry.installed_redists.contains (spec.id);
                if (is_installed != want_installed) continue;

                var key = spec.package_category ();
                if (current == null || current_key != key) {
                    current = new Widgets.PageSection (Models.RedistManifest.package_category_label (key));
                    current_key = key;
                    list.append (current);
                }

                var row = new PackageRow (ctx, entry, spec, is_installed, current);
                current.add (row);
                group.rows.add (row);
            }

            var empty_group = Widgets.PageChrome.untitled_group ();
            group.empty = Widgets.PageChrome.placeholder_row ("");
            empty_group.add (group.empty);
            list.append (empty_group);
            group.empty_group = empty_group;
        }
    }
}
