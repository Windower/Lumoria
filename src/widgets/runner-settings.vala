namespace Lumoria.Widgets {

    public class RunnerSettings : Object {
        public static uint select_runner_override_index (
            Gee.ArrayList<Models.RunnerManifest> runner_manifests,
            string current_runner_id
        ) {
            if (current_runner_id == "") return 0;
            for (int i = 0; i < runner_manifests.size; i++) {
                if (runner_manifests[i].id == current_runner_id) return (uint) (i + 1);
            }
            return 0;
        }

        public static string runner_id_for_override_index (
            Gee.ArrayList<Models.RunnerManifest> runner_manifests,
            uint selected
        ) {
            if (selected == 0) return "";
            var index = (int) selected - 1;
            if (index < 0 || index >= runner_manifests.size) return "";
            return runner_manifests[index].id;
        }

        public static void fill_variant_combo (
            OptionListRow variant_combo,
            Models.RunnerManifest? runner,
            Gee.ArrayList<Models.RunnerVariant> visible_variants,
            string preselect = ""
        ) {
            visible_variants.clear ();
            var candidates = runner != null
                ? runner.selectable_variants (Utils.EnvironmentInfo.is_sandboxed ())
                : new Gee.ArrayList<Models.RunnerVariant> ();
            variant_combo.visible = candidates.size > 0;
            if (candidates.size == 0) return;

            var model = new Gtk.StringList (null);
            int selected_idx = 0;
            for (int i = 0; i < candidates.size; i++) {
                var variant = candidates[i];
                visible_variants.add (variant);
                model.append (variant.display_label ());
                if (preselect != "" ? variant.id == preselect : variant.is_default) selected_idx = i;
            }
            variant_combo.model = model;
            variant_combo.selected = selected_idx;
        }

        public static bool is_effective_latest (Models.RunnerManifest? runner, string value) {
            if (Models.ToolVersionRef.is_latest (value)) return true;
            if (!Models.ToolVersionRef.is_inherit (value)) return false;

            var defaults = Utils.Preferences.instance ();
            var runner_id = runner != null ? runner.id : "";
            if (runner_id != "" && runner_id != defaults.runner_id) return true;
            return Models.ToolVersionRef.is_latest (defaults.get_default_runner_version ());
        }

        public static string version_label_for_value (Models.RunnerManifest? runner, string value) {
            if (Models.ToolVersionRef.is_latest (value)) return _("Latest (always newest)");
            if (!Models.ToolVersionRef.is_inherit (value)) return value;

            var defaults = Utils.Preferences.instance ();
            var default_id = defaults.runner_id;
            var default_ver = defaults.get_default_runner_version ();
            var runner_id = runner != null ? runner.id : "";
            if (runner_id != "" && runner_id != default_id) {
                return _("Use Runner Default (%s latest)").printf (runner_id);
            }
            var default_label = default_id != "" ? _("%s %s").printf (default_id, default_ver) : default_ver;
            return _("Use Global Default (%s)").printf (default_label);
        }

        public static Gee.ArrayList<OptionListItem> build_runner_override_items (
            Gee.ArrayList<Models.RunnerManifest> runner_manifests
        ) {
            var items = new Gee.ArrayList<OptionListItem> ();
            var prefs = Utils.Preferences.instance ();
            var def = prefs.runner_id != "" ? prefs.runner_id : _("not set");
            var inherit = new OptionListItem ();
            inherit.label = PageChrome.inherit_default_label (def);
            items.add (inherit);
            foreach (var spec in runner_manifests) {
                var item = new OptionListItem ();
                item.label = spec.display_label ();
                item.recommended = spec.recommended;
                item.support = spec.support;
                items.add (item);
            }
            return items;
        }
    }

    public class WineOverrideSection : Gtk.Box {
        /* With for_entry, emitted only after the entry has been updated. */
        public signal void changed ();

        public OptionListRow wayland { get; private set; }
        public OptionListRow monitor { get; private set; }
        public OptionListRow sync { get; private set; }
        public OptionListRow debug { get; private set; }
        private Gee.ArrayList<string> monitor_values;
        private Models.PrefixEntry? entry;

        private const string[] SYNC_VALUES = { "ntsync", "fsync", "esync" };

        private static string[] sync_labels () {
            return { _("NTSync"), _("Fsync"), _("Esync") };
        }

        private static string[] sync_combo_labels () {
            var labels = sync_labels ();
            labels[0] = _("%s (recommended)").printf (labels[0]);
            return labels;
        }

        private static string[] debug_labels () {
            return { _("Default"), _("General"), _("Full") };
        }

        private static uint debug_index_for_value (string value) {
            switch (Runtime.WineDebugMode.parse (value)) {
                case Runtime.WineDebugMode.GENERAL: return 1;
                case Runtime.WineDebugMode.FULL: return 2;
                default: return 0;
            }
        }

        private static string debug_value_for_index (uint index) {
            switch (index) {
                case 1: return Runtime.WineDebugMode.GENERAL.id ();
                case 2: return Runtime.WineDebugMode.FULL.id ();
                default: return Runtime.WineDebugMode.DEFAULT.id ();
            }
        }

        private static uint index_of_value (string[] values, string value) {
            for (uint i = 0; i < values.length; i++) {
                if (values[i] == value) return i;
            }
            return 0;
        }

        private static OptionListRow build_combo (
            string title,
            string[] labels,
            uint selected,
            string? inherit_label = null
        ) {
            var model = new Gtk.StringList (null);
            if (inherit_label != null) model.append (PageChrome.inherit_default_label (inherit_label));
            foreach (var label in labels) model.append (label);

            var row = new OptionListRow ();
            row.title = title;
            row.model = model;
            row.selected = selected;
            return row;
        }

        private static OptionListRow build_sync_combo (string selected_mode) {
            return build_combo (_("Sync Mode"), sync_combo_labels (), index_of_value (SYNC_VALUES, selected_mode));
        }

        private static string sync_mode_value_for_index (uint selected) {
            return selected < SYNC_VALUES.length ? SYNC_VALUES[selected] : SYNC_VALUES[0];
        }

        private static OptionListRow build_debug_combo (string current_debug) {
            return build_combo (_("Debug Level"), debug_labels (), debug_index_for_value (current_debug));
        }

        private static OptionListRow build_sync_override_combo (string prefix_sync_mode) {
            var global = sync_labels ()[index_of_value (SYNC_VALUES, Utils.Preferences.instance ().sync_mode)];
            var selected = prefix_sync_mode == "" ? 0 : index_of_value (SYNC_VALUES, prefix_sync_mode) + 1;
            return build_combo (_("Sync Mode"), sync_combo_labels (), selected, global);
        }

        private static string sync_override_value_for_index (uint selected) {
            return selected == 0 ? "" : sync_mode_value_for_index (selected - 1);
        }

        private static OptionListRow build_debug_override_combo (string prefix_wine_debug) {
            var global = debug_labels ()[debug_index_for_value (Utils.Preferences.instance ().wine_debug)];
            var selected = prefix_wine_debug == "" ? 0 : debug_index_for_value (prefix_wine_debug) + 1;
            return build_combo (_("Debug Level"), debug_labels (), selected, global);
        }

        private static string debug_override_value_for_index (uint selected) {
            return selected == 0 ? "" : debug_value_for_index (selected - 1);
        }

        private static void update_debug_combo_logging_state (OptionListRow row, bool keep_runtime_logs) {
            row.sensitive = keep_runtime_logs;
            row.subtitle = keep_runtime_logs ? "" : _("Disabled when logging is not enabled.");
        }

        private static OptionListRow build_wayland_combo (bool? wayland_override = null) {
            var wayland_global = Utils.Preferences.instance ().wine_wayland ? _("enabled") : _("disabled");
            return PageChrome.build_toggle_override_combo (
                _("Wine Wayland"),
                wayland_override,
                wayland_global,
                wayland_no_x11_hint ()
            );
        }

        private static string wayland_no_x11_hint () {
            if (Utils.EnvironmentInfo.has_x11_display ()) return "";
            return Utils.EnvironmentInfo.is_sandboxed ()
                ? _("No X11 display available; disabling has no effect. Grant the X11 socket (e.g. via Flatseal) to use XWayland. Depending on your version of Flatpak, you might need to also disable Fallback X11.")
                : _("No X11 display available; disabling has no effect.");
        }

        private static void fill_monitor_combo (
            OptionListRow row,
            Gee.ArrayList<string> values,
            string current
        ) {
            values.clear ();
            var model = new Gtk.StringList (null);
            model.append (_("Default"));
            values.add ("");
            int selected = 0;
            foreach (var monitor in Lumoria.Widgets.Services.list_monitors ()) {
                model.append (monitor.label);
                values.add (monitor.connector);
                if (monitor.connector == current) {
                    selected = values.size - 1;
                }
            }
            row.model = model;
            row.selected = (uint) selected;
        }

        public WineOverrideSection (
            bool? wine_wayland,
            string sync_mode,
            string wine_debug,
            string monitor_value
        ) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            monitor_values = new Gee.ArrayList<string> ();
            var wine = new PageSection (_("Wine"));
            wayland = build_wayland_combo (wine_wayland);
            sync = build_sync_override_combo (sync_mode);
            debug = build_debug_override_combo (wine_debug);
            update_debug_combo_logging_state (debug, Utils.Preferences.instance ().keep_runtime_logs);
            monitor = new OptionListRow ();
            monitor.title = _("Primary Wayland Monitor");
            fill_monitor_combo (monitor, monitor_values, monitor_value);
            wayland.notify["selected"].connect (on_option_changed);
            monitor.notify["selected"].connect (on_option_changed);
            sync.notify["selected"].connect (on_option_changed);
            debug.notify["selected"].connect (on_option_changed);
            wine.add (wayland);
            wine.add (monitor);
            wine.add (sync);
            wine.add (debug);
            append (wine);
        }

        public WineOverrideSection.for_entry (Models.PrefixEntry entry) {
            this (entry.wine_wayland, entry.sync_mode, entry.wine_debug, entry.wayland_primary_monitor);
            this.entry = entry;
        }

        private void on_option_changed () {
            if (entry != null) apply_to_entry (entry);
            changed ();
        }

        public void apply_to_entry (Models.PrefixEntry entry) {
            entry.wine_wayland = wine_wayland_value ();
            entry.wayland_primary_monitor = monitor_value ();
            entry.sync_mode = sync_value ();
            entry.wine_debug = debug_value ();
        }

        public bool? wine_wayland_value () {
            return ((ToggleOverrideState) wayland.selected).to_nullable_bool ();
        }

        public string monitor_value () {
            var index = (int) monitor.selected;
            return index >= 0 && index < monitor_values.size ? monitor_values[index] : "";
        }

        public string sync_value () {
            return sync_override_value_for_index (sync.selected);
        }

        public string debug_value () {
            return debug_override_value_for_index (debug.selected);
        }

        public static Gtk.Widget for_preferences () {
            var prefs = Utils.Preferences.instance ();
            var wine = new PageSection (
                _("Wine"),
                _("Prefixes that still use the default pick up changes here.")
            );

            var wayland = new Adw.SwitchRow ();
            wayland.title = _("Enable Wine Wayland");
            wayland.subtitle = wayland_no_x11_hint ();
            wayland.active = prefs.wine_wayland;
            wayland.notify["active"].connect ((row, p) => {
                var active = ((Adw.SwitchRow) row).active;
                if (Utils.Preferences.instance ().wine_wayland != active) Utils.Preferences.instance ().wine_wayland = active;
            });
            wine.add (wayland);

            var sync = build_sync_combo (prefs.sync_mode);
            sync.notify["selected"].connect ((row, p) => {
                var mode = sync_mode_value_for_index (((OptionListRow) row).selected);
                if (Utils.Preferences.instance ().sync_mode != mode) Utils.Preferences.instance ().sync_mode = mode;
            });
            wine.add (sync);

            var debug = build_debug_combo (prefs.wine_debug);
            update_debug_combo_logging_state (debug, prefs.keep_runtime_logs);
            debug.notify["selected"].connect ((row, p) => {
                var value = debug_value_for_index (((OptionListRow) row).selected);
                if (Utils.Preferences.instance ().wine_debug != value) Utils.Preferences.instance ().wine_debug = value;
            });
            wine.add (debug);
            return wine;
        }
    }
}
