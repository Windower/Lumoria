namespace Lumoria.Widgets.Preferences {

    public class StoragePage : Gtk.Box {
        public signal void toast_message (string message);

        private Models.PrefixRegistry registry;
        private Cancellable? cancellable;

        private SizeRow runners_row;
        private SizeRow components_row;
        private SizeRow prefixes_row;
        private SizeRow total_row;

        private Gee.HashMap<Utils.StorageCategory, CacheClearRow> cache_rows;

        public StoragePage (Models.PrefixRegistry registry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.registry = registry;
            cache_rows = new Gee.HashMap<Utils.StorageCategory, CacheClearRow> ();
            build_ui ();

            map.connect (on_mapped);
            unmap.connect (on_unmapped);
        }

        private void build_ui () {
            var usage_group = SettingsShared.build_group (_("Disk Usage"));
            usage_group.description = _("Storage used by Lumoria data and caches.");

            runners_row = new SizeRow (_("Installed Runners"));
            usage_group.add (runners_row);

            components_row = new SizeRow (_("Installed Components"));
            usage_group.add (components_row);

            prefixes_row = new SizeRow (_("Wine Prefixes"));
            usage_group.add (prefixes_row);

            total_row = new SizeRow (_("Total"));
            total_row.add_css_class ("property");
            usage_group.add (total_row);

            append (usage_group);

            var cache_group = SettingsShared.build_group (_("Cache"), 24, 12, 12);
            cache_group.description = _("Clear cached metadata and downloaded archives.");

            add_cache_row (cache_group, _("Runner Cache"), "runners",
                Utils.StorageCategory.CACHE_RUNNERS, _("Runner cache cleared."));
            add_cache_row (cache_group, _("Component Cache"), "components",
                Utils.StorageCategory.CACHE_COMPONENTS, _("Component cache cleared."));
            add_cache_row (cache_group, _("Installer Cache"), "installer",
                Utils.StorageCategory.CACHE_INSTALLER, _("Installer cache cleared."));
            add_cache_row (cache_group, _("Launcher Cache"), "launchers",
                Utils.StorageCategory.CACHE_LAUNCHERS, _("Launcher cache cleared."));
            add_cache_row (cache_group, _("Redistributable Cache"), "redist",
                Utils.StorageCategory.CACHE_REDIST, _("Redistributable cache cleared."));

            var clear_all = new Adw.ActionRow ();
            clear_all.title = _("Clear All Cache");
            clear_all.activatable = true;
            clear_all.add_css_class ("error");
            clear_all.activated.connect (() => {
                if (Utils.remove_recursive (Utils.cache_dir ())) {
                    Utils.StorageCache.instance ().invalidate_all_cache ();
                    refresh ();
                    toast_message (_("All cache cleared."));
                } else {
                    toast_message (_("Failed to clear some cache files."));
                }
            });
            cache_group.add (clear_all);

            append (cache_group);
        }

        private void add_cache_row (
            Adw.PreferencesGroup group,
            string title,
            string cache_subdir,
            Utils.StorageCategory category,
            string success_toast
        ) {
            var row = new CacheClearRow (title);
            row.cleared.connect (() => {
                if (Utils.remove_recursive (Path.build_filename (Utils.cache_dir (), cache_subdir))) {
                    Utils.StorageCache.instance ().invalidate (category);
                    refresh ();
                    toast_message (success_toast);
                } else {
                    toast_message (_("Failed to clear cache."));
                }
            });

            cache_rows[category] = row;
            group.add (row);
        }

        private void on_mapped () {
            Utils.StorageCache.instance ().size_updated.connect (on_size_updated);
            refresh ();
        }

        private void on_unmapped () {
            Utils.StorageCache.instance ().size_updated.disconnect (on_size_updated);
            if (cancellable != null) {
                cancellable.cancel ();
                cancellable = null;
            }
        }

        private void refresh () {
            if (cancellable != null) cancellable.cancel ();
            cancellable = new Cancellable ();

            var cache = Utils.StorageCache.instance ();

            sync_size_row (runners_row, Utils.StorageCategory.RUNNERS);
            sync_size_row (components_row, Utils.StorageCategory.COMPONENTS);
            sync_size_row (prefixes_row, Utils.StorageCategory.PREFIXES);
            update_total ();

            foreach (var entry in cache_rows.entries) {
                if (cache.is_valid (entry.key)) {
                    entry.value.set_size (cache.get_size (entry.key));
                } else {
                    entry.value.set_loading ();
                }
            }

            cache.refresh_if_needed (registry, cancellable);
        }

        private void sync_size_row (SizeRow row, Utils.StorageCategory category) {
            var cache = Utils.StorageCache.instance ();
            if (cache.is_valid (category)) {
                row.set_size (cache.get_size (category));
            } else {
                row.set_loading ();
            }
        }

        private void on_size_updated (Utils.StorageCategory category, int64 bytes) {
            switch (category) {
                case Utils.StorageCategory.RUNNERS:
                    runners_row.set_size (bytes);
                    break;
                case Utils.StorageCategory.COMPONENTS:
                    components_row.set_size (bytes);
                    break;
                case Utils.StorageCategory.PREFIXES:
                    prefixes_row.set_size (bytes);
                    break;
                default:
                    break;
            }

            if (cache_rows.has_key (category)) {
                cache_rows[category].set_size (bytes);
            }

            update_total ();
        }

        private void update_total () {
            var cache = Utils.StorageCache.instance ();
            if (cache.all_valid ()) {
                total_row.set_size (cache.total ());
            } else {
                total_row.set_loading ();
            }
        }
    }

    private class SizeRow : Adw.ActionRow {
        private Gtk.Widget? suffix_widget;

        public SizeRow (string row_title) {
            title = row_title;
            set_loading ();
        }

        public void set_size (int64 bytes) {
            replace_suffix (new Gtk.Label (format_bytes (bytes)));
        }

        public void set_loading () {
            var spinner = new Gtk.Spinner ();
            spinner.spinning = true;
            replace_suffix (spinner);
        }

        private void replace_suffix (Gtk.Widget widget) {
            if (suffix_widget != null) {
                remove (suffix_widget);
            }
            suffix_widget = widget;
            suffix_widget.valign = Gtk.Align.CENTER;
            add_suffix (suffix_widget);
        }

        private static string format_bytes (int64 bytes) {
            return GLib.format_size ((uint64) (bytes > 0 ? bytes : 0));
        }
    }

    private class CacheClearRow : Adw.ActionRow {
        public signal void cleared ();

        public CacheClearRow (string row_title) {
            title = row_title;

            var btn = new Gtk.Button.with_label (_("Clear"));
            btn.valign = Gtk.Align.CENTER;
            btn.clicked.connect (() => cleared ());
            add_suffix (btn);
        }

        public void set_size (int64 bytes) {
            subtitle = GLib.format_size ((uint64) (bytes > 0 ? bytes : 0));
        }

        public void set_loading () {
            subtitle = _("Calculating\u2026");
        }
    }
}
