namespace Lumoria.Widgets.Preferences {

    public class StoragePage : Gtk.Box {
        private Lumoria.Application.Context ctx;
        private Models.PrefixRegistry registry;
        private Cancellable? cancellable;

        private SizeRow runners_row;
        private SizeRow components_row;
        private SizeRow app_data_row;
        private SizeRow prefixes_row;
        private SizeRow total_row;
        private PageSection prefix_group;

        private Gee.HashMap<Utils.StorageCategory, CacheClearRow> cache_rows;
        private Gee.HashMap<string, SizeRow> prefix_rows;

        public StoragePage (Lumoria.Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.registry = ctx.registry;
            cache_rows = new Gee.HashMap<Utils.StorageCategory, CacheClearRow> ();
            prefix_rows = new Gee.HashMap<string, SizeRow> ();
            build_ui ();
            ctx.prefixes.list_changed.connect (rebuild_prefix_rows);

            map.connect (on_mapped);
            unmap.connect (on_unmapped);
        }

        private void build_ui () {
            var summary_group = new PageSection (
                _("Storage Summary"),
                _("Total storage used by Lumoria data and caches.")
            );

            total_row = new SizeRow (_("Total Storage"));
            total_row.add_css_class ("property");
            summary_group.add (total_row);

            append (summary_group);

            var usage_group = new PageSection (
                _("Installed Data"),
                _("Storage used by installed runners, components, and Lumoria data.")
            );

            runners_row = new SizeRow (_("Installed Runners"));
            usage_group.add (runners_row);

            components_row = new SizeRow (_("Installed Components"));
            usage_group.add (components_row);

            app_data_row = new SizeRow (_("Other Lumoria Data"));
            app_data_row.visible = false;
            usage_group.add (app_data_row);

            append (usage_group);

            prefix_group = new PageSection (
                _("Wine Prefixes"),
                _("Storage used by each registered Wine prefix.")
            );

            prefixes_row = new SizeRow (_("Total Prefix Storage"));
            prefixes_row.reserve_action ();
            prefix_group.add (prefixes_row);
            rebuild_prefix_rows ();

            append (prefix_group);

            var cache_group = new PageSection (
                _("Cache"),
                _("Clear cached metadata and downloaded archives.")
            );

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
            add_cache_row (cache_group, _("Remote Manifest Cache"), "remote-manifests",
                Utils.StorageCategory.CACHE_REMOTE_MANIFESTS, _("Remote manifest cache cleared."));
            add_cache_row (cache_group, _("Manifest Cache"), "manifests",
                Utils.StorageCategory.CACHE_MANIFESTS, _("Manifest cache cleared."));

            var clear_all = new Adw.ActionRow ();
            clear_all.title = _("Clear All Cache");
            clear_all.activatable = true;
            clear_all.add_css_class ("error");
            clear_all.activated.connect (clear_all_cache);
            cache_group.add (clear_all);

            append (cache_group);
        }

        private void clear_all_cache () {
            Utils.StorageCache.instance ().clear_all_cache_async ((error) => {
                ctx.reload_manifests ();
                finish_clear (error, _("All cache cleared."));
            });
        }

        private void finish_clear (Error? error, string success_toast) {
            refresh ();
            ctx.show_toast (error != null ? user_error (error) : success_toast);
        }

        private void add_cache_row (
            PageSection group,
            string title,
            string cache_subdir,
            Utils.StorageCategory category,
            string success_toast
        ) {
            var row = new CacheClearRow (title, cache_subdir, category, success_toast);
            row.cleared.connect (on_cache_cleared);
            cache_rows[category] = row;
            group.add (row);
        }

        private void on_cache_cleared (CacheClearRow row) {
            Utils.StorageCache.instance ().clear_cache_async (row.category, row.cache_subdir, (error) => {
                if (row.category == Utils.StorageCategory.CACHE_MANIFESTS) ctx.reload_manifests ();
                finish_clear (error, row.success_toast);
            });
        }

        private void on_mapped () {
            Utils.StorageCache.instance ().size_updated.connect (on_size_updated);
            Utils.StorageCache.instance ().prefix_size_updated.connect (on_prefix_size_updated);
            refresh ();
        }

        private void on_unmapped () {
            Utils.StorageCache.instance ().size_updated.disconnect (on_size_updated);
            Utils.StorageCache.instance ().prefix_size_updated.disconnect (on_prefix_size_updated);
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
            sync_app_data_row ();
            sync_size_row (prefixes_row, Utils.StorageCategory.PREFIXES);
            sync_prefix_rows ();
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
                case Utils.StorageCategory.APP_DATA:
                    set_app_data_size (bytes);
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

        private void sync_app_data_row () {
            var cache = Utils.StorageCache.instance ();
            if (cache.is_valid (Utils.StorageCategory.APP_DATA)) {
                set_app_data_size (cache.get_size (Utils.StorageCategory.APP_DATA));
            } else {
                app_data_row.visible = true;
                app_data_row.set_loading ();
            }
        }

        private void set_app_data_size (int64 bytes) {
            app_data_row.visible = bytes != 0;
            app_data_row.set_size (bytes);
        }

        private void rebuild_prefix_rows () {
            foreach (var row in prefix_rows.values) {
                prefix_group.remove_row (row);
            }
            prefix_rows.clear ();

            var cache = Utils.StorageCache.instance ();
            foreach (var entry in ctx.registry.prefixes) {
                var row = new SizeRow (entry.display_name ());
                row.subtitle = entry.needs_grant ()
                    ? _("Permission required to access this prefix")
                    : entry.resolved_path ();
                if (cache.is_prefix_valid (entry.id)) {
                    row.set_size (cache.get_prefix_size (entry.id));
                }

                row.add_action (new RemovePrefixButton (ctx, entry));

                prefix_rows[entry.id] = row;
                prefix_group.add (row);
            }
            sync_prefix_rows ();
        }

        private void sync_prefix_rows () {
            var cache = Utils.StorageCache.instance ();
            foreach (var entry in registry.prefixes) {
                if (!prefix_rows.has_key (entry.id)) continue;
                var row = prefix_rows[entry.id];
                if (cache.is_prefix_valid (entry.id)) {
                    row.set_size (cache.get_prefix_size (entry.id));
                } else {
                    row.set_loading ();
                }
            }
        }

        private void on_prefix_size_updated (string prefix_id, int64 bytes) {
            if (!prefix_rows.has_key (prefix_id)) return;
            prefix_rows[prefix_id].set_size (bytes);
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
        private Gtk.Box trail;
        private Gtk.Stack meter;
        private Gtk.Label size_label;
        private Gtk.Spinner spinner;
        private Gtk.Widget? action;

        public SizeRow (string row_title) {
            title = row_title;

            size_label = new Gtk.Label ("");
            size_label.xalign = 1f;
            size_label.width_chars = 8;
            size_label.max_width_chars = 8;
            size_label.ellipsize = Pango.EllipsizeMode.NONE;

            spinner = new Gtk.Spinner ();
            spinner.spinning = true;
            spinner.halign = Gtk.Align.END;

            meter = new Gtk.Stack ();
            meter.hhomogeneous = true;
            meter.add_child (size_label);
            meter.add_child (spinner);

            trail = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            trail.valign = Gtk.Align.CENTER;
            trail.append (meter);
            add_suffix (trail);
            set_loading ();
        }

        public void add_action (Gtk.Widget widget) {
            if (action != null) trail.remove (action);
            action = widget;
            action.valign = Gtk.Align.CENTER;
            trail.append (action);
        }

        public void reserve_action () {
            var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            spacer.width_request = 34;
            add_action (spacer);
        }

        public void set_size (int64 bytes) {
            size_label.label = format_bytes (bytes);
            meter.visible_child = size_label;
        }

        public void set_loading () {
            spinner.spinning = true;
            meter.visible_child = spinner;
        }

        private static string format_bytes (int64 bytes) {
            if (bytes < 0) return _("Unknown");
            return GLib.format_size ((uint64) bytes);
        }
    }

    private class RemovePrefixButton : Gtk.Button {
        private Lumoria.Application.Context ctx;
        private Models.PrefixEntry entry;

        public RemovePrefixButton (Lumoria.Application.Context ctx, Models.PrefixEntry entry) {
            Object (icon_name: IconRegistry.DELETE, valign: Gtk.Align.CENTER);
            this.ctx = ctx;
            this.entry = entry;
            PageChrome.set_icon_label (this, _("Remove Prefix"));
            PageChrome.style_icon_button (this);
            add_css_class ("destructive-action");
            clicked.connect (confirm);
        }

        private void confirm () {
            Dialogs.PrefixDialogs.present_remove_prefix_dialog (this, entry, (deleted_files) => {
                ctx.remove_prefix (entry, deleted_files);
            });
        }
    }

    private class CacheClearRow : Adw.ActionRow {
        public signal void cleared ();

        public string cache_subdir;
        public Utils.StorageCategory category;
        public string success_toast;

        public CacheClearRow (
            string row_title,
            string cache_subdir,
            Utils.StorageCategory category,
            string success_toast
        ) {
            title = row_title;
            this.cache_subdir = cache_subdir;
            this.category = category;
            this.success_toast = success_toast;

            var btn = new Gtk.Button.with_label (_("Clear"));
            btn.valign = Gtk.Align.CENTER;
            btn.clicked.connect (() => cleared ());
            add_suffix (btn);
        }

        public void set_size (int64 bytes) {
            subtitle = bytes < 0 ? _("Unknown") : GLib.format_size ((uint64) bytes);
        }

        public void set_loading () {
            subtitle = _("Calculating...");
        }
    }
}
