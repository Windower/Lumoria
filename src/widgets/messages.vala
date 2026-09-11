namespace Lumoria.Widgets {

    public class Messages : Object {
        public class Card : Gtk.Box {
            public Card (
                Models.MessageAlert alert,
                int margin_top = Ui.Metrics.GROUP_SPACING,
                int margin_bottom = 4,
                int margin_start = Ui.Metrics.PAGE_MARGIN,
                int margin_end = Ui.Metrics.PAGE_MARGIN
            ) {
                Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 8);
                add_css_class ("card");
                add_css_class ("message-card");
                if (!is_hex_color (alert.colors.background)) add_css_class (style_class (alert.style));
                apply_custom_colors (this, alert.colors);
                this.margin_top = margin_top;
                this.margin_bottom = margin_bottom;
                this.margin_start = margin_start;
                this.margin_end = margin_end;
                hexpand = true;

                var icon = new Gtk.Image.from_icon_name (icon_name (alert));
                icon.valign = Gtk.Align.START;
                icon.margin_top = 10;
                icon.margin_start = 10;
                append (icon);

                var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
                body.hexpand = true;
                body.margin_top = 10;
                body.margin_bottom = 10;
                body.margin_end = 10;
                if (alert.title.strip () != "") {
                    var title = new Gtk.Label (alert.title);
                    title.wrap = true;
                    title.xalign = 0f;
                    title.add_css_class ("heading");
                    body.append (title);
                }
                if (alert.body.strip () != "") body.append (new MarkupContent (alert.body));
                var links = build_links_box (alert.links, link_text_button);
                if (links != null) {
                    links.add_css_class ("message-card-links");
                    body.append (links);
                }
                append (body);
            }
        }

        public static Gtk.Widget warning (
            string message,
            int margin_top = Ui.Metrics.GROUP_SPACING,
            int margin_bottom = 4,
            int margin_start = Ui.Metrics.PAGE_MARGIN,
            int margin_end = Ui.Metrics.PAGE_MARGIN
        ) {
            return new Card (
                Models.MessageAlert.from_text (message, Models.MessageStyle.WARNING),
                margin_top,
                margin_bottom,
                margin_start,
                margin_end
            );
        }

        public static Gtk.Widget info (
            string message,
            int margin_top = Ui.Metrics.GROUP_SPACING,
            int margin_bottom = 4,
            int margin_start = Ui.Metrics.PAGE_MARGIN,
            int margin_end = Ui.Metrics.PAGE_MARGIN
        ) {
            return new Card (
                Models.MessageAlert.from_text (message, Models.MessageStyle.INFO),
                margin_top,
                margin_bottom,
                margin_start,
                margin_end
            );
        }

        private static Gtk.Widget list (
            Gee.ArrayList<Models.MessageAlert> alerts,
            Gee.HashMap<string, string>? vars = null,
            int margin_top = Ui.Metrics.GROUP_SPACING,
            int margin_bottom = 4,
            int margin_start = Ui.Metrics.PAGE_MARGIN,
            int margin_end = Ui.Metrics.PAGE_MARGIN
        ) {
            var expanded = new Gee.ArrayList<Models.MessageAlert> ();
            foreach (var alert in alerts) {
                expanded.add (alert.expand (vars));
            }
            return list_expanded (expanded, margin_top, margin_bottom, margin_start, margin_end);
        }

        private static Gtk.Widget list_expanded (
            Gee.ArrayList<Models.MessageAlert> alerts,
            int margin_top,
            int margin_bottom,
            int margin_start,
            int margin_end
        ) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            box.hexpand = true;
            for (int i = 0; i < alerts.size; i++) {
                box.append (new Card (
                    alerts[i],
                    i == 0 ? margin_top : 0,
                    i == alerts.size - 1 ? margin_bottom : 0,
                    margin_start,
                    margin_end
                ));
            }
            return box;
        }

        public static void fill (
            Gtk.Box parent,
            Models.ManifestMessages messages,
            Gee.HashMap<string, string>? vars,
            string[] keys,
            int margin_top = Ui.Metrics.GROUP_SPACING,
            int margin_bottom = 0,
            int margin_start = Ui.Metrics.PAGE_MARGIN,
            int margin_end = Ui.Metrics.PAGE_MARGIN
        ) {
            var alerts = messages.first (keys);
            if (alerts.size == 0) return;
            parent.append (list (alerts, vars, margin_top, margin_bottom, margin_start, margin_end));
        }

        public static Gtk.Widget? link_icons (
            Models.ManifestLinks? links,
            Gee.HashMap<string, string>? vars
        ) {
            if (links == null || links.empty) return null;
            var items = links.expand (vars).to_message_links ();
            if (items.size == 0) return null;
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box.add_css_class ("manifest-link-tray");
            box.valign = Gtk.Align.CENTER;
            var added = 0;
            foreach (var link in items) {
                if (link.kind == Models.MessageLinkKind.LICENSE) continue;
                box.append (link_icon_button (link));
                added++;
            }
            if (added == 0) return null;
            return box;
        }

        public static Adw.PreferencesRow? footer_row (
            Models.BaseManifest spec,
            Gee.HashMap<string, string>? vars
        ) {
            var links = link_labels (spec.links, vars);
            if (links == null) return null;
            var row = new Adw.ActionRow ();
            row.activatable = false;
            row.add_prefix (links);
            return row;
        }

        public static string style_class (Models.MessageStyle style) {
            switch (style) {
                case Models.MessageStyle.WARNING:
                    return "warning";
                case Models.MessageStyle.DANGER:
                    return "danger";
                case Models.MessageStyle.SUCCESS:
                    return "success";
                default:
                    return "info";
            }
        }

        public static bool is_hex_color (string value) {
            var hex = value.strip ();
            if (!hex.has_prefix ("#")) return false;
            var digits = hex.substring (1);
            if (digits.length != 3 && digits.length != 6) return false;
            for (int i = 0; i < digits.length; i++) {
                if (!digits[i].isxdigit ()) return false;
            }
            return true;
        }

        private static Gtk.CssProvider? color_provider;
        private static StringBuilder color_css = new StringBuilder ();
        private static Gee.HashSet<string> color_classes = new Gee.HashSet<string> ();

        private static void apply_custom_colors (Gtk.Widget widget, Models.MessageColors colors) {
            var background = colors.background.strip ();
            var text = colors.text.strip ();
            var has_bg = is_hex_color (background);
            var has_text = is_hex_color (text);
            if (!has_bg && !has_text) return;

            var css_class = "message-colors-%s-%s".printf (
                has_bg ? background.substring (1).down () : "x",
                has_text ? text.substring (1).down () : "x"
            );
            if (color_classes.add (css_class)) {
                color_css.append_printf (".message-card.%s {", css_class);
                if (has_bg) color_css.append_printf ("background-color: alpha(%s, 0.18);", background);
                if (has_text) color_css.append_printf ("color: %s;", text);
                color_css.append ("}\n");
                if (color_provider == null) {
                    color_provider = new Gtk.CssProvider ();
                    Gtk.StyleContext.add_provider_for_display (
                        widget.get_display (), color_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                    );
                }
                color_provider.load_from_string (color_css.str);
            }
            widget.add_css_class (css_class);
        }

        private delegate Gtk.Widget LinkFactory (Models.MessageLink link);

        private static Gtk.Box? build_links_box (
            Gee.List<Models.MessageLink> links,
            owned LinkFactory make_button
        ) {
            if (links.size == 0) return null;
            var gamescope = Utils.EnvironmentInfo.is_gamescope ();
            var box = new Gtk.Box (
                gamescope ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL,
                gamescope ? 4 : 8
            );
            foreach (var link in links) {
                if (gamescope) {
                    box.append (Markup.markup_label (Markup.inline_to_pango (link.url), ""));
                } else {
                    box.append (make_button (link));
                }
            }
            return box;
        }

        private static Gtk.Widget? link_labels (
            Models.ManifestLinks? links,
            Gee.HashMap<string, string>? vars
        ) {
            if (links == null || links.empty) return null;
            var items = new Gee.ArrayList<Models.MessageLink> ();
            foreach (var link in links.expand (vars).to_message_links ()) {
                if (link.kind != Models.MessageLinkKind.LICENSE) items.add (link);
            }
            var box = build_links_box (items, link_label_button);
            if (box != null) box.valign = Gtk.Align.CENTER;
            return box;
        }

        private static Gtk.Button link_button (Models.MessageLink link, Gtk.Widget? child = null) {
            var button = new UrlButton (link.url);
            if (child != null) button.child = child;
            else button.label = Models.ManifestLinks.display_label (link);
            return button;
        }

        private class UrlButton : Gtk.Button {
            private string url;

            public UrlButton (string url) {
                this.url = url;
                clicked.connect (open);
            }

            private void open () {
                Dialogs.FileDialogs.open_http_uri (this, url);
            }
        }

        private static Gtk.Button link_text_button (Models.MessageLink link) {
            var button = link_button (link);
            button.add_css_class ("flat");
            button.add_css_class ("link");
            return button;
        }

        private static Gtk.Button link_label_button (Models.MessageLink link) {
            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            content.append (link_icon_image (link));
            content.append (new Gtk.Label (Models.ManifestLinks.display_label (link)));
            var button = link_button (link, content);
            button.add_css_class ("flat");
            button.add_css_class ("link");
            button.valign = Gtk.Align.CENTER;
            return button;
        }

        private static Gtk.Button link_icon_button (Models.MessageLink link) {
            var button = link_button (link, link_icon_image (link));
            button.tooltip_text = Models.ManifestLinks.display_label (link);
            PageChrome.style_icon_button (button);
            button.valign = Gtk.Align.CENTER;
            return button;
        }

        private static Gtk.Image link_icon_image (Models.MessageLink link) {
            if (Models.ManifestLinks.is_discord_url (link.url)) {
                return IconRegistry.discord_image (16);
            }
            if (link_icon_name (link) == IconRegistry.WEB) {
                return IconRegistry.web_image (16);
            }
            var image = new Gtk.Image.from_icon_name (link_icon_name (link));
            image.pixel_size = 16;
            return image;
        }

        private static string link_icon_name (Models.MessageLink link) {
            switch (link.kind) {
                case Models.MessageLinkKind.DOCS:
                case Models.MessageLinkKind.HELP:
                    return IconRegistry.HELP;
                case Models.MessageLinkKind.SOURCE:
                    return IconRegistry.TOOLS;
                case Models.MessageLinkKind.LICENSE:
                    return IconRegistry.PAGE_ABOUT;
                default:
                    return IconRegistry.WEB;
            }
        }

        public static string icon_name (Models.MessageAlert alert) {
            if (alert.icon.strip () != "") return IconRegistry.resolve_action_icon (alert.icon);
            switch (alert.style) {
                case Models.MessageStyle.WARNING:
                    return IconRegistry.WARNING;
                case Models.MessageStyle.DANGER:
                    return IconRegistry.ERROR;
                case Models.MessageStyle.SUCCESS:
                    return IconRegistry.SUCCESS;
                default:
                    return IconRegistry.INFO;
            }
        }
    }
}
