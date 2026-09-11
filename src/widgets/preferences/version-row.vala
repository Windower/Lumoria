namespace Lumoria.Widgets.Preferences {

    public class VersionRow : Adw.ActionRow {
        public signal void default_set (string message);

        private Runtime.ToolAdapter tool;
        private Models.ToolVersion version;

        private Gtk.Button install_btn;
        private Gtk.Button open_btn;
        private Gtk.Button remove_btn;
        private Gtk.Button default_btn;
        private Gtk.Spinner spinner;

        public VersionRow (Runtime.ToolAdapter tool, Models.ToolVersion version) {
            this.tool = tool;
            this.version = version;

            if (version.is_latest) {
                title = _("Latest");
                subtitle = version.description;
            } else {
                title = version.tag;
                if (version.date != "") {
                    subtitle = Utils.format_release_date (version.date);
                }
            }

            var suffix_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            suffix_box.valign = Gtk.Align.CENTER;

            spinner = new Gtk.Spinner ();
            spinner.visible = false;
            suffix_box.append (spinner);

            default_btn = new Gtk.Button ();
            default_btn.add_css_class ("flat");
            default_btn.clicked.connect (on_set_default);
            suffix_box.append (default_btn);

            install_btn = new Gtk.Button.from_icon_name (IconRegistry.DOWNLOAD);
            install_btn.add_css_class ("flat");
            PageChrome.set_icon_label (install_btn, _("Install"));
            install_btn.clicked.connect (on_install);
            suffix_box.append (install_btn);

            open_btn = new Gtk.Button.from_icon_name (IconRegistry.OPEN_DIRECTORY);
            open_btn.add_css_class ("flat");
            PageChrome.set_icon_label (open_btn, _("Open directory"));
            open_btn.clicked.connect (on_open);
            suffix_box.append (open_btn);

            remove_btn = new Gtk.Button.from_icon_name (IconRegistry.DELETE);
            remove_btn.add_css_class ("flat");
            PageChrome.set_icon_label (remove_btn, _("Remove"));
            remove_btn.clicked.connect (on_remove);
            suffix_box.append (remove_btn);

            add_suffix (suffix_box);
            update_state ();
        }

        public void update_state () {
            var installed = tool.is_installed (version);
            install_btn.visible = !installed;
            open_btn.visible = installed;
            remove_btn.visible = installed;

            var effective_tag = version.is_latest ? Models.ToolVersionRef.LATEST.id () : version.tag;
            var defaults = Utils.Preferences.instance ();

            switch (tool.tool_kind) {
                case Utils.ToolKind.RUNNER:
                    var is_current = defaults.is_default_runner (tool.tool_id, effective_tag);
                    default_btn.icon_name = is_current ? IconRegistry.STARRED : IconRegistry.UNSTARRED;
                    PageChrome.set_icon_label (default_btn, is_current ? _("Current default runner") : _("Set as default runner"));
                    default_btn.visible = true;
                    break;
                case Utils.ToolKind.COMPONENT:
                    var is_current = defaults.is_tool_default (tool.tool_kind, tool.tool_id, effective_tag);
                    default_btn.icon_name = is_current ? IconRegistry.STARRED : IconRegistry.UNSTARRED;
                    PageChrome.set_icon_label (default_btn, is_current ? _("Current default version") : _("Set as default version"));
                    default_btn.visible = true;
                    break;
            }
        }

        private void on_set_default () {
            var effective_tag = version.is_latest ? Models.ToolVersionRef.LATEST.id () : version.tag;
            var defaults = Utils.Preferences.instance ();

            switch (tool.tool_kind) {
                case Utils.ToolKind.RUNNER:
                    defaults.set_default_runner (tool.tool_id, effective_tag);
                    default_set (_("Default runner set to %s %s").printf (tool.tool_name, effective_tag));
                    break;
                case Utils.ToolKind.COMPONENT:
                    defaults.set_tool_version (tool.tool_kind, tool.tool_id, effective_tag);
                    default_set (_("Default %s version set to %s").printf (tool.tool_name, effective_tag));
                    break;
            }
            update_state ();
        }

        private void on_install () {
            install_btn.sensitive = false;
            spinner.visible = true;
            spinner.spinning = true;

            var kind = tool.tool_kind;
            Utils.run_background ("install-version", () => {
                tool.install_version (version, null);
            }, (error) => {
                spinner.visible = false;
                spinner.spinning = false;
                install_btn.sensitive = true;
                update_state ();
                if (error != null) {
                    subtitle = _("Install failed: %s").printf (user_error (error));
                } else {
                    invalidate_storage (kind);
                }
            });
        }

        private void on_open () {
            var path = tool.installed_path (version);
            if (path == "") return;
            try {
                AppInfo.launch_default_for_uri (File.new_for_path (path).get_uri (), null);
            } catch (Error e) {
                subtitle = _("Could not open directory: %s").printf (user_error (e));
            }
        }

        private void on_remove () {
            remove_btn.sensitive = false;
            var kind = tool.tool_kind;
            Utils.run_background ("remove-version", () => {
                tool.remove_version (version);
            }, (error) => {
                if (error != null) subtitle = _("Remove failed: %s").printf (user_error (error));
                remove_btn.sensitive = true;
                update_state ();
                invalidate_storage (kind);
            });
        }

        private static void invalidate_storage (Utils.ToolKind kind) {
            var cache = Utils.StorageCache.instance ();
            switch (kind) {
                case Utils.ToolKind.RUNNER:
                    cache.invalidate (Utils.StorageCategory.RUNNERS);
                    cache.invalidate (Utils.StorageCategory.CACHE_RUNNERS);
                    if (is_inside_data_dir (Utils.runner_dir ())) {
                        cache.invalidate (Utils.StorageCategory.APP_DATA);
                    }
                    break;
                case Utils.ToolKind.COMPONENT:
                    cache.invalidate (Utils.StorageCategory.COMPONENTS);
                    cache.invalidate (Utils.StorageCategory.CACHE_COMPONENTS);
                    if (is_inside_data_dir (Utils.component_dir ())) {
                        cache.invalidate (Utils.StorageCategory.APP_DATA);
                    }
                    break;
            }
        }

        private static bool is_inside_data_dir (string path) {
            return Utils.path_within (Utils.normalize_dir_path (path), Utils.normalize_dir_path (Utils.data_dir ()));
        }
    }
}
