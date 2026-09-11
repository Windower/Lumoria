namespace Lumoria.Models {

    public delegate void VersionProgress (int64 downloaded, int64 total);

    public class ToolVersion : Object {
        public string tag { get; set; default = ""; }
        public string date { get; set; default = ""; }
        public string description { get; set; default = ""; }
        public bool is_latest { get; set; default = false; }

        public ToolVersion (string tag, string date = "", string description = "") {
            this.tag = tag;
            this.date = date;
            this.description = description;
        }

        public ToolVersion.latest (string resolved_tag) {
            this.tag = ToolVersionRef.LATEST.id ();
            this.is_latest = true;
            this.description = resolved_tag != "" ? "Currently: %s".printf (resolved_tag) : "";
        }
    }

    public enum ToolVersionRef {
        INHERIT,
        LATEST,
        PINNED;

        public const string WIRE_INHERIT = "default";
        public const string WIRE_LATEST = "latest";

        public static ToolVersionRef parse (string version) {
            switch (version.strip ().down ()) {
                case "":
                case WIRE_INHERIT:
                    return INHERIT;
                case WIRE_LATEST:
                    return LATEST;
                default:
                    return PINNED;
            }
        }

        public static bool is_inherit (string version) {
            return parse (version) == INHERIT;
        }

        public static bool is_latest (string version) {
            return parse (version) == LATEST;
        }

        public static bool is_pinned (string version) {
            return parse (version) == PINNED;
        }

        public static bool is_deferred (string version) {
            return parse (version) != PINNED;
        }

        public static string display_label (string version) {
            switch (parse (version)) {
                case LATEST:
                    return _("Latest (always newest)");
                case INHERIT:
                    return _("Default");
                default:
                    return version;
            }
        }

        public static ToolVersion to_version (string version) {
            return is_latest (version)
                ? new ToolVersion.latest ("")
                : new ToolVersion (version);
        }

        public unowned string id () {
            switch (this) {
                case LATEST:
                    return WIRE_LATEST;
                case INHERIT:
                    return WIRE_INHERIT;
                default:
                    return "";
            }
        }
    }

    public class ToolVersionPage : Object {
        public Gee.ArrayList<ToolVersion> versions { get; owned set; default = new Gee.ArrayList<ToolVersion> (); }
        public int page { get; set; default = 1; }
        public int per_page { get; set; default = 30; }
        public bool has_more { get; set; default = false; }
    }
}
