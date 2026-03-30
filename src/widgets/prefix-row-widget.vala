namespace Lumoria.Widgets {

    public class PrefixRowWidget : Adw.ExpanderRow {
        public signal void play_requested (int index);
        public signal void play_entrypoint_requested (int index, string entrypoint_id);
        public signal void manage_requested (int index);
        public signal void wine_tools_requested (int index);
        public signal void open_logs_requested (int index);
        public signal void set_default_requested (int index);

        private int prefix_index;
        private Gtk.Button play_btn;
        private Gtk.Button default_btn;
        private Adw.ActionRow default_row;
        private Adw.ActionRow wine_tools_row;
        private Adw.ActionRow path_row;
        private Adw.ActionRow browse_row;

        public PrefixRowWidget (
            Models.PrefixEntry entry,
            int index,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs,
            bool is_gamescope,
            bool is_default
        ) {
            this.prefix_index = index;
            build_ui (entry, runner_specs, launcher_specs, is_gamescope, is_default);
        }

        private const string SUBTITLE_DEFAULT_PREFIX = "★ ";

        private string collapsed_subtitle_text (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            bool is_default
        ) {
            var s = entry.runner_summary (runner_specs);
            if (is_default) return SUBTITLE_DEFAULT_PREFIX + s;
            return s;
        }

        private string default_action_subtitle (bool is_default) {
            var text = _("Launched from the play button at the bottom of the window");
            if (is_default) return SUBTITLE_DEFAULT_PREFIX + text;
            return text;
        }

        private void build_ui (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            Gee.ArrayList<Models.LauncherSpec> launcher_specs,
            bool is_gamescope,
            bool is_default
        ) {
            title = entry.display_name ();
            subtitle = collapsed_subtitle_text (entry, runner_specs, is_default);
            show_enable_switch = false;

            play_btn = new Gtk.Button.with_label (_("Play"));
            play_btn.add_css_class ("suggested-action");
            play_btn.valign = Gtk.Align.CENTER;
            play_btn.focusable = true;
            play_btn.sensitive = entry.runner_id != "";
            play_btn.clicked.connect (() => play_requested (prefix_index));
            add_suffix (play_btn);

            path_row = new Adw.ActionRow ();
            path_row.title = _("Path");
            path_row.subtitle = entry.resolved_path ();
            path_row.subtitle_selectable = true;
            add_row (path_row);

            default_row = new Adw.ActionRow ();
            default_row.title = _("Quick Launch");
            default_row.subtitle = default_action_subtitle (is_default);
            default_btn = new Gtk.Button.with_label (
                is_default ? _("Quick Launch") : _("Set as Quick Launch")
            );
            default_btn.valign = Gtk.Align.CENTER;
            default_btn.sensitive = !is_default;
            default_btn.clicked.connect (() => set_default_requested (prefix_index));
            default_row.add_suffix (default_btn);
            default_row.activatable_widget = default_btn;
            add_row (default_row);

            var has_runner = entry.runner_id != "";

            var entrypoints = Runtime.list_entrypoints (entry, launcher_specs);
            if (entrypoints.size > 0) {
                add_row (build_section_header (_("Launch")));
                var active_ep_id = Runtime.resolve_effective_entrypoint_id (entry, launcher_specs);
                foreach (var ep in entrypoints) {
                    var ep_row = new Adw.ActionRow ();
                    ep_row.title = ep.display_label ();
                    ep_row.activatable = false;

                    if (active_ep_id != "" && ep.id == active_ep_id) {
                        ep_row.subtitle = SUBTITLE_DEFAULT_PREFIX + _("Default for this prefix");
                    }

                    var ep_play_btn = new Gtk.Button.from_icon_name (IconRegistry.PAGE_LAUNCH);
                    ep_play_btn.add_css_class ("flat");
                    ep_play_btn.add_css_class ("launch-entry-play-btn");
                    ep_play_btn.valign = Gtk.Align.CENTER;
                    ep_play_btn.focusable = true;
                    ep_play_btn.tooltip_text = _("Launch %s").printf (ep.display_label ());
                    ep_play_btn.sensitive = has_runner;
                    var ep_id = ep.id;
                    ep_play_btn.clicked.connect (() => play_entrypoint_requested (prefix_index, ep_id));
                    ep_row.add_suffix (ep_play_btn);

                    add_row (ep_row);
                }
            }

            add_row (build_section_header (_("Tools")));

            var manage_row = new Adw.ActionRow ();
            manage_row.title = _("Manage Prefix");
            manage_row.subtitle = _("Configure runner, patches, and settings");
            manage_row.add_prefix (new Gtk.Image.from_icon_name (IconRegistry.MANAGE));
            manage_row.activatable = true;
            manage_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            manage_row.activated.connect (() => manage_requested (prefix_index));
            add_row (manage_row);

            wine_tools_row = new Adw.ActionRow ();
            wine_tools_row.title = _("Wine Tools");
            wine_tools_row.subtitle = _("Run Wine utilities in this prefix");
            wine_tools_row.add_prefix (new Gtk.Image.from_icon_name (IconRegistry.TOOLS));
            wine_tools_row.activatable = true;
            wine_tools_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            wine_tools_row.activated.connect (() => wine_tools_requested (prefix_index));
            add_row (wine_tools_row);

            browse_row = new Adw.ActionRow ();
            browse_row.title = _("Browse Prefix");
            browse_row.subtitle = _("Open the prefix root directory");
            browse_row.add_prefix (new Gtk.Image.from_icon_name (IconRegistry.OPEN_FOLDER));
            browse_row.activatable = true;
            browse_row.sensitive = !is_gamescope;
            browse_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            browse_row.activated.connect (() => open_logs_requested (prefix_index));
            add_row (browse_row);
        }

        private Gtk.Widget build_section_header (string label) {
            var header = new Gtk.Label (label);
            header.xalign = 0;
            header.margin_start = 12;
            header.margin_top = 8;
            header.margin_bottom = 4;
            header.add_css_class ("dim-label");
            header.add_css_class ("caption");
            return header;
        }

        public void refresh (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.RunnerSpec> runner_specs,
            bool is_gamescope,
            bool is_default
        ) {
            title = entry.display_name ();
            subtitle = collapsed_subtitle_text (entry, runner_specs, is_default);
            path_row.subtitle = entry.resolved_path ();
            default_row.subtitle = default_action_subtitle (is_default);
            default_btn.label = is_default ? _("Quick Launch") : _("Set as Quick Launch");
            default_btn.sensitive = !is_default;
            var has_runner = entry.runner_id != "";
            play_btn.sensitive = has_runner;
            wine_tools_row.sensitive = has_runner && !is_gamescope;
            browse_row.sensitive = !is_gamescope;
        }

        public bool activate_primary_action () {
            if (!play_btn.sensitive) return false;
            play_btn.activate ();
            return true;
        }
    }
}
