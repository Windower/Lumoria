namespace Lumoria.Ui {

    public class PrefixRuntimePage : Gtk.Box, TabHost {
        private Application.Context ctx;
        private Models.PrefixEntry entry;
        private Models.InstallerManifest? installer;
        private RunnerOverrideRows runner_rows;
        private SettingsTabs tabs;

        public PrefixRuntimePage (Application.Context ctx, Models.PrefixEntry entry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.entry = entry;
            installer = Models.ManifestRepository.shared ().installer (entry.installer_id);

            tabs = new SettingsTabs ();
            tabs.add_scrolled (runner_tab (), "runner", _("Runner"));
            tabs.add_scrolled (components_tab (), "components", _("Components"));
            tabs.add_page (new PrefixPackagesPage (ctx, entry), "packages", _("Packages"));
            tabs.add_scrolled (wine_tab (), "wine", _("Wine"));
            tabs.add_scrolled (environment_tab (), "environment", _("Environment"));
            append (tabs);
        }

        public string inner_tab () {
            return tabs.visible_name ();
        }

        public void show_inner (string name) {
            tabs.show_name (name);
        }

        public bool cycle_tabs (int delta) {
            return tabs.cycle (delta);
        }

        private Gtk.Widget runner_tab () {
            runner_rows = new RunnerOverrideRows (ctx, true);
            runner_rows.bind (entry.runner_id, entry.runner_version, entry.variant_id);
            runner_rows.changed.connect (save_runner);
            return runner_rows;
        }

        private Gtk.Widget components_tab () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.append (Widgets.ManifestUi.components_disable_note ());
            var first = true;
            foreach (var spec in Models.ManifestRepository.shared ().components) {
                if (installer != null && !spec.supports_installer (installer.id)) continue;
                var ov = entry.runtime_component_overrides.has_key (spec.id)
                    ? entry.runtime_component_overrides[spec.id]
                    : null;
                var applied = entry.applied_components.has_key (spec.id)
                    ? entry.applied_components[spec.id].version
                    : null;
                var block = new Widgets.ComponentBlock (
                    ctx,
                    spec,
                    ov != null ? ov.enabled : null,
                    ov != null ? ov.version : "",
                    applied,
                    first
                );
                block.enabled_changed.connect (on_component_enabled);
                block.version_changed.connect (on_component_version);
                box.append (block);
                first = false;
            }
            var dxvk = new Widgets.DxvkConfigGroup.for_entry (ctx, entry);
            dxvk.changed.connect (save_graphics);
            box.append (dxvk);
            return box;
        }

        private Gtk.Widget environment_tab () {
            var env = new Widgets.EnvironmentSettings.for_entry (ctx, entry);
            env.changed.connect (schedule_save);
            return env;
        }

        private Gtk.Widget wine_tab () {
            var wine = new Widgets.WineOverrideSection.for_entry (entry);
            wine.changed.connect (schedule_save);
            return wine;
        }

        private void schedule_save () {
            ctx.prefixes.schedule_save ();
        }

        private void save_runner () {
            var version = runner_rows.version ();
            entry.runner_version = version != "" ? version : Models.ToolVersionRef.INHERIT.id ();
            schedule_save ();
        }

        private void on_component_enabled (Widgets.ComponentBlock block, bool? enabled) {
            entry.apply_component_enabled (block.component_id, enabled);
            schedule_save ();
        }

        private void on_component_version (Widgets.ComponentBlock block, string version) {
            entry.apply_component_version (block.component_id, version);
            schedule_save ();
        }

        private void save_graphics () {
            if (!entry.advanced_dxvk) {
                Runtime.cleanup_managed_dxvk_config (entry.resolved_path ());
            }
            schedule_save ();
        }
    }
}
