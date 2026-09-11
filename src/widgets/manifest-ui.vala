namespace Lumoria.Widgets {

    public class ManifestUi : Object {
        public static string prose_markdown (Models.BaseManifest spec) {
            var bodies = alert_bodies (spec.messages.alerts (Models.ManifestMessages.DESCRIPTION));
            if (bodies.length == 0) bodies = alert_bodies (spec.messages.alerts (Models.ManifestMessages.ABOUT));
            return string.joinv ("\n\n", bodies);
        }

        public static string subtitle (Models.BaseManifest spec) {
            var text = prose_markdown (spec).replace ("\n", " ").strip ();
            if (text == "") return "";
            return Markup.inline_to_pango (text);
        }

        public static Gtk.Widget? prose (
            Models.BaseManifest spec,
            Gee.HashMap<string, string>? vars = null,
            string kind = Models.ManifestMessages.DESCRIPTION
        ) {
            var markdown = join_alert_bodies (spec.messages.alerts (kind));
            if (markdown.strip () == "") return null;
            if (vars != null) markdown = Utils.expand_vars (markdown, vars);
            var content = new MarkupContent (markdown);
            content.add_css_class ("dim-label");
            content.margin_start = Ui.Metrics.PAGE_MARGIN;
            content.margin_end = Ui.Metrics.PAGE_MARGIN;
            content.margin_bottom = Ui.Metrics.HEADING_GAP;
            return content;
        }

        public static void populate_about (
            Gtk.Box box,
            Models.BaseManifest? spec,
            Gee.HashMap<string, string>? vars = null,
            string icon = "",
            string[] cards = {},
            bool first = false
        ) {
            PageChrome.clear_children (box);
            if (spec == null) return;
            box.append (intro (spec, vars, null, first, "", icon, cards));
            var footer = Messages.footer_row (spec, vars);
            if (footer != null) {
                var group = PageChrome.untitled_group ();
                group.add (footer);
                box.append (group);
            }
        }

        public static Gtk.Widget intro (
            Models.BaseManifest spec,
            Gee.HashMap<string, string>? vars = null,
            Gtk.Widget? extra_suffix = null,
            bool first = false,
            string default_version = "",
            string icon = "",
            string[] cards = {}
        ) {
            var pill_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            pill_box.valign = Gtk.Align.CENTER;
            PageChrome.append_item_pills (pill_box, spec.recommended, spec.support);
            if (default_version.strip () != "") {
                pill_box.append (PageChrome.status_pill (_("Default"), "success"));
                var version = new Gtk.Label (default_version);
                version.add_css_class ("dim-label");
                version.add_css_class ("caption");
                version.valign = Gtk.Align.CENTER;
                version.ellipsize = Pango.EllipsizeMode.END;
                version.max_width_chars = 24;
                pill_box.append (version);
            }
            Gtk.Widget? after_title = pill_box.get_first_child () != null ? pill_box : null;

            var intro = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            intro.append (PageChrome.heading_row (
                spec.display_label (),
                icon,
                extra_suffix,
                after_title,
                first
            ));
            var body = prose (spec, vars);
            if (body != null) intro.append (body);
            if (cards.length > 0) {
                Messages.fill (intro, spec.messages, vars, cards, 0, Ui.Metrics.HEADING_GAP);
            }
            return intro;
        }

        public static Gtk.Widget components_disable_note () {
            return new Messages.Card (
                Models.MessageAlert.from_text (
                    _("Disabling these will use Wine's built-in Direct3D and DDraw, which can lead to slower performance.")
                )
            );
        }

        public static string launcher_display_name (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.LauncherManifest> launchers
        ) {
            var launcher = Models.find_by_id<Models.LauncherManifest> (launchers, entry.launcher_id);
            return launcher != null ? launcher.display_label () : _("Launcher");
        }

        public static Gtk.Widget launcher_heading (
            Models.PrefixEntry entry,
            Gee.ArrayList<Models.LauncherManifest> launchers,
            Gtk.Widget? extra_suffix = null
        ) {
            var launcher = Models.find_by_id<Models.LauncherManifest> (launchers, entry.launcher_id);
            return PageChrome.heading_row (
                launcher_display_name (entry, launchers),
                launcher != null ? launcher.icon : "",
                extra_suffix
            );
        }

        public static string join_alert_bodies (Gee.ArrayList<Models.MessageAlert> alerts) {
            return string.joinv ("\n\n", alert_bodies (alerts));
        }

        public static string installer_display_name (Models.PrefixEntry entry) {
            var installer = Models.ManifestRepository.shared ().installer (entry.installer_id);
            return installer != null ? installer.display_label () : _("Game");
        }

        public static string target_group_title (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target,
            Gee.ArrayList<Models.LauncherManifest> launchers
        ) {
            if (target.section == Runtime.LaunchTargetSection.POST_INSTALL && target.group_title != "") {
                return target.group_title;
            }
            if (target.section == Runtime.LaunchTargetSection.LAUNCHER) {
                return launcher_display_name (entry, launchers);
            }
            if (target.section == Runtime.LaunchTargetSection.LAUNCH) {
                return installer_display_name (entry);
            }
            return Runtime.launch_target_section_title (target.section);
        }

        private static string[] alert_bodies (Gee.ArrayList<Models.MessageAlert> alerts) {
            var parts = new Gee.ArrayList<string> ();
            foreach (var alert in alerts) {
                var body = alert.body.strip ();
                if (body != "") parts.add (body);
            }
            return Utils.strv (parts);
        }
    }
}
