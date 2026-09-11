namespace Lumoria.Widgets {

    public class MarkupContent : Gtk.Box {
        public bool compact { get; construct; default = false; }

        public MarkupContent (string source, bool compact = false) {
            Object (
                orientation: Gtk.Orientation.VERTICAL,
                spacing: compact ? 3 : 6,
                compact: compact
            );
            hexpand = true;
            if (compact) add_css_class ("launch-display-markup");
            foreach (var block in Markup.parse_blocks (source)) {
                var widget = block.to_widget (compact);
                if (widget != null) append (widget);
            }
        }
    }

    public class MarkupBlock {
        public enum Kind {
            PARAGRAPH,
            HEADING,
            UL,
            OL,
            QUOTE,
            HR
        }

        public Kind kind { get; set; default = Kind.PARAGRAPH; }
        public int heading_level { get; set; default = 1; }
        public Gee.ArrayList<string> lines { get; owned set; default = new Gee.ArrayList<string> (); }

        public Gtk.Widget? to_widget (bool compact = false) {
            var heading = compact ? "subtitle" : heading_css ();
            switch (kind) {
                case Kind.HR:
                    return new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
                case Kind.HEADING:
                    return Markup.markup_label (
                        Markup.inline_to_pango (joined ()),
                        heading,
                        compact
                    );
                case Kind.UL:
                    return list_box (false, compact);
                case Kind.OL:
                    return list_box (true, compact);
                case Kind.QUOTE:
                    var quote = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
                    quote.add_css_class ("dim-label");
                    quote.margin_start = 12;
                    quote.append (Markup.markup_label (Markup.inline_to_pango (joined ()), "", compact));
                    return quote;
                default:
                    return Markup.markup_label (Markup.inline_to_pango (joined ()), "", compact);
            }
        }

        private string heading_css () {
            switch (heading_level) {
                case 1:
                    return "title-4";
                case 2:
                    return "heading";
                default:
                    return "caption-heading";
            }
        }

        private string joined () {
            return string.joinv ("\n", Utils.strv (lines));
        }

        private Gtk.Widget list_box (bool ordered, bool compact) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            for (int i = 0; i < lines.size; i++) {
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                var marker = new Gtk.Label (ordered ? "%d.".printf (i + 1) : "•");
                marker.xalign = 0f;
                marker.valign = Gtk.Align.START;
                marker.add_css_class ("dim-label");
                if (compact) marker.add_css_class ("subtitle");
                row.append (marker);
                var body = Markup.markup_label (Markup.inline_to_pango (lines[i]), "", compact);
                body.hexpand = true;
                row.append (body);
                box.append (row);
            }
            return box;
        }
    }

    public class Markup : Object {
        public static Gtk.Label markup_label (string pango, string css_class, bool compact = false) {
            var label = new Gtk.Label (null);
            label.set_markup (pango);
            label.wrap = true;
            label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            label.xalign = 0f;
            label.hexpand = true;
            if (compact) {
                label.add_css_class ("subtitle");
                label.add_css_class ("dim-label");
            }
            if (css_class != "") label.add_css_class (css_class);
            if (!Utils.EnvironmentInfo.is_gamescope ()) {
                label.activate_link.connect ((src, uri) => {
                    Dialogs.FileDialogs.open_http_uri (src, uri);
                    return true;
                });
            }
            return label;
        }

        public static Gee.ArrayList<MarkupBlock> parse_blocks (string source) {
            var blocks = new Gee.ArrayList<MarkupBlock> ();
            MarkupBlock? current = null;
            foreach (var raw in source.split ("\n")) {
                var line = raw.replace ("\r", "");
                if (line.strip () == "") {
                    current = null;
                    continue;
                }
                int heading_level;
                string heading_text;
                if (match_heading (line, out heading_level, out heading_text)) {
                    current = add_block (blocks, MarkupBlock.Kind.HEADING);
                    current.heading_level = heading_level;
                    current.lines.add (heading_text);
                    current = null;
                    continue;
                }
                if (is_rule (line)) {
                    add_block (blocks, MarkupBlock.Kind.HR);
                    current = null;
                    continue;
                }
                string item;
                if (match_unordered (line, out item)) {
                    if (current == null || current.kind != MarkupBlock.Kind.UL) {
                        current = add_block (blocks, MarkupBlock.Kind.UL);
                    }
                    current.lines.add (item);
                    continue;
                }
                if (match_ordered (line, out item)) {
                    if (current == null || current.kind != MarkupBlock.Kind.OL) {
                        current = add_block (blocks, MarkupBlock.Kind.OL);
                    }
                    current.lines.add (item);
                    continue;
                }
                if (match_quote (line, out item)) {
                    if (current == null || current.kind != MarkupBlock.Kind.QUOTE) {
                        current = add_block (blocks, MarkupBlock.Kind.QUOTE);
                    }
                    current.lines.add (item);
                    continue;
                }
                if (current == null || current.kind != MarkupBlock.Kind.PARAGRAPH) {
                    current = add_block (blocks, MarkupBlock.Kind.PARAGRAPH);
                }
                current.lines.add (line);
            }
            return blocks;
        }

        public static string inline_to_pango (string source) {
            return render_inline (escape_text (source));
        }

        public static string escape_text (string text) {
            return text.replace ("&", "&amp;").replace ("<", "&lt;");
        }

        public static bool is_http_url (string url) {
            var lower = url.strip ().down ();
            return lower.has_prefix ("http://") || lower.has_prefix ("https://");
        }

        private static MarkupBlock add_block (Gee.ArrayList<MarkupBlock> blocks, MarkupBlock.Kind kind) {
            var block = new MarkupBlock ();
            block.kind = kind;
            blocks.add (block);
            return block;
        }

        private static bool is_rule (string line) {
            var trimmed = line.strip ();
            if (trimmed.length < 3) return false;
            for (int i = 0; i < trimmed.length; i++) {
                if (trimmed[i] != '-') return false;
            }
            return true;
        }

        private static bool match_heading (string line, out int level, out string text) {
            level = 0;
            text = "";
            var trimmed = line.strip ();
            while (level < 3 && level < trimmed.length && trimmed[level] == '#') {
                level++;
            }
            if (level == 0 || level >= trimmed.length || trimmed[level] != ' ') return false;
            text = trimmed.substring (level + 1).strip ();
            return text != "";
        }

        private static bool match_unordered (string line, out string text) {
            text = "";
            var trimmed = line.strip ();
            if (trimmed.length < 3) return false;
            if ((trimmed[0] != '-' && trimmed[0] != '*') || trimmed[1] != ' ') return false;
            text = trimmed.substring (2);
            return true;
        }

        private static bool match_ordered (string line, out string text) {
            text = "";
            var trimmed = line.strip ();
            int i = 0;
            while (i < trimmed.length && trimmed[i] >= '0' && trimmed[i] <= '9') {
                i++;
            }
            if (i == 0 || i + 1 >= trimmed.length || trimmed[i] != '.' || trimmed[i + 1] != ' ') {
                return false;
            }
            text = trimmed.substring (i + 2);
            return true;
        }

        private static bool match_quote (string line, out string text) {
            text = "";
            var trimmed = line.strip ();
            if (!trimmed.has_prefix ("> ")) return false;
            text = trimmed.substring (2);
            return true;
        }

        private static string render_inline (string source) {
            var builder = new StringBuilder ();
            int i = 0;
            int len = source.length;
            while (i < len) {
                string inner;
                int consumed;
                if (take_delimited (source, i, "**", out inner, out consumed)
                    || take_delimited (source, i, "__", out inner, out consumed)) {
                    var tag = source.get (i) == '*' ? "b" : "i";
                    builder.append_printf ("<%s>%s</%s>", tag, render_inline (inner), tag);
                    i += consumed;
                    continue;
                }
                if (take_delimited (source, i, "`", out inner, out consumed)) {
                    builder.append_printf ("<tt>%s</tt>", inner);
                    i += consumed;
                    continue;
                }
                if (source.get (i) == '*' && take_delimited (source, i, "*", out inner, out consumed)) {
                    builder.append_printf ("<i>%s</i>", render_inline (inner));
                    i += consumed;
                    continue;
                }
                string label;
                string url;
                if (take_link (source, i, out label, out url, out consumed)) {
                    if (is_http_url (url)) {
                        if (Utils.EnvironmentInfo.is_gamescope ()) {
                            builder.append (url);
                        } else {
                            builder.append_printf (
                                "<a href=\"%s\">%s</a>",
                                url.replace ("\"", "&quot;"),
                                render_inline (label)
                            );
                        }
                    } else {
                        builder.append (render_inline (label));
                    }
                    i += consumed;
                    continue;
                }
                var next = next_markup (source, i + 1);
                if (next < 0) {
                    builder.append (source.substring (i));
                    break;
                }
                builder.append (source.substring (i, next - i));
                i = next;
            }
            return builder.str;
        }

        private static int next_markup (string source, int start) {
            var from = source.substring (start);
            int best = -1;
            foreach (var token in new string[] { "**", "__", "`", "*", "[" }) {
                var at = from.index_of (token);
                if (at < 0) continue;
                if (best < 0 || at < best) best = at;
            }
            return best < 0 ? -1 : start + best;
        }

        private static bool take_delimited (
            string source,
            int start,
            string delim,
            out string inner,
            out int consumed
        ) {
            inner = "";
            consumed = 0;
            if (!source.substring (start).has_prefix (delim)) return false;
            var from = start + delim.length;
            var close = source.index_of (delim, from);
            if (close < 0 || close == from) return false;
            inner = source.substring (from, close - from);
            consumed = (close + delim.length) - start;
            return true;
        }

        private static bool take_link (
            string source,
            int start,
            out string label,
            out string url,
            out int consumed
        ) {
            label = "";
            url = "";
            consumed = 0;
            if (source[start] != '[') return false;
            var close_label = source.index_of ("]", start + 1);
            if (close_label < 0 || close_label + 1 >= source.length || source[close_label + 1] != '(') {
                return false;
            }
            var close_url = source.index_of (")", close_label + 2);
            if (close_url < 0) return false;
            label = source.substring (start + 1, close_label - start - 1);
            url = source.substring (close_label + 2, close_url - close_label - 2).strip ();
            consumed = close_url + 1 - start;
            return label != "";
        }
    }
}
