namespace Lumoria.Models {

    public enum SupportStatus {
        SUPPORTED,
        EXPERIMENTAL,
        UNSUPPORTED;

        public static SupportStatus parse (string value) {
            switch (value.strip ().down ()) {
                case "experimental":
                    return EXPERIMENTAL;
                case "unsupported":
                    return UNSUPPORTED;
                default:
                    return SUPPORTED;
            }
        }
    }

    public enum MessageStyle {
        INFO,
        WARNING,
        DANGER,
        SUCCESS;

        public static MessageStyle parse (string value) {
            switch (value.strip ().down ()) {
                case "warning":
                    return WARNING;
                case "danger":
                    return DANGER;
                case "success":
                    return SUCCESS;
                default:
                    return INFO;
            }
        }
    }

    public enum MessageLinkKind {
        CUSTOM,
        WEBSITE,
        DOCS,
        HELP,
        SOURCE,
        LICENSE
    }

    public class MessageLink : Object {
        public string label { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public MessageLinkKind kind { get; set; default = MessageLinkKind.CUSTOM; }
    }

    public class MessageColors : Object {
        public string background { get; set; default = ""; }
        public string text { get; set; default = ""; }

        public bool empty {
            get { return background.strip () == "" && text.strip () == ""; }
        }

        public MessageColors expand (Gee.HashMap<string, string> vars) {
            var copy = new MessageColors ();
            copy.background = Utils.expand_vars (background, vars);
            copy.text = Utils.expand_vars (text, vars);
            return copy;
        }

        public static MessageColors from_json (Json.Object obj) {
            var fields = json_object (obj, "colors");
            if (fields == null) return new MessageColors ();
            var colors = new MessageColors ();
            colors.background = json_string (fields, "background");
            colors.text = json_string (fields, "text");
            return colors;
        }
    }

    public class ManifestLinks : Object {
        public string website { get; set; default = ""; }
        public string docs { get; set; default = ""; }
        public string help { get; set; default = ""; }
        public string source { get; set; default = ""; }
        public string license { get; set; default = ""; }

        public bool empty {
            get {
                return website.strip () == ""
                    && docs.strip () == ""
                    && help.strip () == ""
                    && source.strip () == ""
                    && license.strip () == "";
            }
        }

        public ManifestLinks expand (Gee.HashMap<string, string>? vars) {
            var map = vars ?? new Gee.HashMap<string, string> ();
            var copy = new ManifestLinks ();
            copy.website = Utils.expand_vars (website, map);
            copy.docs = Utils.expand_vars (docs, map);
            copy.help = Utils.expand_vars (help, map);
            copy.source = Utils.expand_vars (source, map);
            copy.license = Utils.expand_vars (license, map);
            return copy;
        }

        public Gee.ArrayList<MessageLink> to_message_links () {
            var list = new Gee.ArrayList<MessageLink> ();
            add_link (list, _("Website"), website, MessageLinkKind.WEBSITE);
            add_link (list, _("Docs"), docs, MessageLinkKind.DOCS);
            add_link (list, _("Help"), help, MessageLinkKind.HELP);
            add_link (list, _("Source"), source, MessageLinkKind.SOURCE);
            add_link (list, _("License"), license, MessageLinkKind.LICENSE);
            return list;
        }

        public static bool is_discord_url (string url) {
            try {
                var uri = Uri.parse (url.strip (), UriFlags.NONE);
                var host = (uri.get_host () ?? "").down ();
                if (host.has_prefix ("www.")) host = host.substring (4);
                return host == "discord.gg"
                    || host == "discord.com"
                    || host.has_suffix (".discord.com")
                    || host == "discordapp.com"
                    || host.has_suffix (".discordapp.com");
            } catch (Error e) {
                var lower = url.strip ().down ();
                return lower.contains ("discord.gg/")
                    || lower.contains ("discord.com/")
                    || lower.contains ("discordapp.com/");
            }
        }

        public static string display_label (MessageLink link) {
            if (is_discord_url (link.url)) return _("Discord");
            return link.label;
        }

        public static ManifestLinks from_json (Json.Object obj) {
            var links = new ManifestLinks ();
            var fields = json_object (obj, "links");
            if (fields == null) return links;
            links.website = json_string (fields, "website");
            links.docs = json_string (fields, "docs");
            links.help = json_string (fields, "help");
            links.source = json_string (fields, "source");
            links.license = json_string (fields, "license");
            return links;
        }

        private static void add_link (
            Gee.ArrayList<MessageLink> list,
            string label,
            string url,
            MessageLinkKind kind
        ) {
            var href = url.strip ();
            if (href == "") return;
            var link = new MessageLink ();
            link.label = label;
            link.url = href;
            link.kind = kind;
            list.add (link);
        }
    }

    public class MessageAlert : Object {
        public string body { get; set; default = ""; }
        public MessageStyle style { get; set; default = MessageStyle.INFO; }
        public string icon { get; set; default = ""; }
        public string title { get; set; default = ""; }
        public MessageColors colors { get; owned set; default = new MessageColors (); }
        public Gee.ArrayList<MessageLink> links {
            get; owned set; default = new Gee.ArrayList<MessageLink> ();
        }

        public static MessageAlert from_text (string body, MessageStyle style = MessageStyle.INFO) {
            var alert = new MessageAlert ();
            alert.body = body;
            alert.style = style;
            return alert;
        }

        public MessageAlert expand (Gee.HashMap<string, string>? vars) {
            var map = vars ?? new Gee.HashMap<string, string> ();
            var copy = new MessageAlert ();
            copy.style = style;
            copy.icon = Utils.expand_vars (icon, map);
            copy.title = Utils.expand_vars (title, map);
            copy.body = Utils.expand_vars (body, map);
            copy.colors = colors.expand (map);
            foreach (var link in links) {
                var expanded = new MessageLink ();
                expanded.label = Utils.expand_vars (link.label, map);
                expanded.url = Utils.expand_vars (link.url, map);
                if (expanded.label != "" && expanded.url != "") copy.links.add (expanded);
            }
            return copy;
        }

        public static MessageAlert from_json (Json.Object obj) {
            var alert = new MessageAlert ();
            alert.body = json_string (obj, "body");
            alert.style = MessageStyle.parse (json_string (obj, "style"));
            alert.icon = json_string (obj, "icon");
            alert.title = json_string (obj, "title");
            alert.colors = MessageColors.from_json (obj);
            if (obj.has_member ("links")) {
                var arr = obj.get_array_member ("links");
                for (uint i = 0; i < arr.get_length (); i++) {
                    var node = arr.get_element (i);
                    if (node.get_node_type () != Json.NodeType.OBJECT) continue;
                    var link_obj = node.get_object ();
                    var link = new MessageLink ();
                    link.label = json_string (link_obj, "label");
                    link.url = json_string (link_obj, "url");
                    if (link.label != "" && link.url != "") alert.links.add (link);
                }
            }
            return alert;
        }
    }

    public class ManifestMessages : Object {
        public const string ABOUT = "about";
        public const string NEW_PREFIX = "new-prefix";
        public const string MANAGE = "manage";
        public const string DESCRIPTION = "description";
        public const string INSTRUCTIONS = "instructions";

        public Gee.HashMap<string, Gee.ArrayList<MessageAlert>> keys {
            get; owned set; default = new Gee.HashMap<string, Gee.ArrayList<MessageAlert>> ();
        }

        public bool empty {
            get { return keys.size == 0; }
        }

        public bool has (string key) {
            return keys.has_key (key) && keys[key].size > 0;
        }

        public Gee.ArrayList<MessageAlert> alerts (string key) {
            if (keys.has_key (key)) return keys[key];
            return new Gee.ArrayList<MessageAlert> ();
        }

        public Gee.ArrayList<MessageAlert> first (string[] names) {
            foreach (var name in names) {
                var found = alerts (name);
                if (found.size > 0) return found;
            }
            return new Gee.ArrayList<MessageAlert> ();
        }

        public static ManifestMessages from_json (Json.Object obj) {
            var messages = new ManifestMessages ();
            var fields = json_object (obj, "messages");
            if (fields == null) return messages;
            fields.foreach_member ((_, key, value) => {
                var parsed = parse_value (value);
                if (parsed.size > 0) messages.keys[key] = parsed;
            });
            return messages;
        }

        private static Gee.ArrayList<MessageAlert> parse_value (Json.Node node) {
            var list = new Gee.ArrayList<MessageAlert> ();
            switch (node.get_node_type ()) {
                case Json.NodeType.VALUE:
                    var text = node.get_string ();
                    if (text != null && text.strip () != "") {
                        list.add (MessageAlert.from_text (text));
                    }
                    break;
                case Json.NodeType.OBJECT:
                    list.add (MessageAlert.from_json (node.get_object ()));
                    break;
                case Json.NodeType.ARRAY:
                    var arr = node.get_array ();
                    for (uint i = 0; i < arr.get_length (); i++) {
                        foreach (var alert in parse_value (arr.get_element (i))) {
                            list.add (alert);
                        }
                    }
                    break;
                default:
                    break;
            }
            return list;
        }
    }

    public class ActionConfirm : Object {
        public bool requested { get; set; default = false; }
        public string title { get; set; default = ""; }
        public string body { get; set; default = ""; }
        public string confirm_label { get; set; default = ""; }
        public string cancel_label { get; set; default = ""; }
        public bool destructive { get; set; default = false; }

        public ActionConfirm expand (Gee.HashMap<string, string>? vars) {
            var map = vars ?? new Gee.HashMap<string, string> ();
            var copy = new ActionConfirm ();
            copy.requested = requested;
            copy.title = Utils.expand_vars (title, map);
            copy.body = Utils.expand_vars (body, map);
            copy.confirm_label = Utils.expand_vars (confirm_label, map);
            copy.cancel_label = Utils.expand_vars (cancel_label, map);
            copy.destructive = destructive;
            return copy;
        }

        public static ActionConfirm from_json (Json.Object obj) {
            if (!obj.has_member ("confirm")) return new ActionConfirm ();
            var node = obj.get_member ("confirm");
            if (node.get_node_type () == Json.NodeType.VALUE) {
                var confirm = new ActionConfirm ();
                confirm.requested = node.get_value_type () == typeof (bool) && node.get_boolean ();
                return confirm;
            }
            if (node.get_node_type () != Json.NodeType.OBJECT) return new ActionConfirm ();
            var fields = node.get_object ();
            var confirm = new ActionConfirm ();
            confirm.requested = true;
            confirm.title = json_string (fields, "title");
            confirm.body = json_string (fields, "body");
            confirm.confirm_label = json_string (fields, "confirm");
            confirm.cancel_label = json_string (fields, "cancel");
            confirm.destructive = json_bool (fields, "destructive");
            return confirm;
        }
    }

    public class ActionButton : Object {
        public bool specified { get; set; default = false; }
        public string label { get; set; default = ""; }
        public string style { get; set; default = ""; }
        public string icon { get; set; default = ""; }

        public static ActionButton from_json (Json.Object obj) {
            var fields = json_object (obj, "button");
            if (fields == null) return new ActionButton ();
            var button = new ActionButton ();
            button.specified = true;
            button.label = json_string (fields, "label");
            button.style = json_string (fields, "style");
            button.icon = json_string (fields, "icon");
            return button;
        }
    }
}
