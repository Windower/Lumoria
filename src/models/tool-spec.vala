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
            this.tag = "latest";
            this.is_latest = true;
            this.description = resolved_tag != "" ? "Currently: %s".printf (resolved_tag) : "";
        }
    }

    public interface ToolSpec : Object {
        public abstract Utils.ToolKind tool_kind { get; }
        public abstract string tool_id { get; }
        public abstract string tool_name { owned get; }
        public abstract string tool_description { owned get; }
        public abstract string github_repo { get; }
        public abstract string install_base_dir { owned get; }

        public abstract Gee.ArrayList<ToolVersion> list_versions () throws Error;
        public abstract void install_version (ToolVersion ver, VersionProgress? progress) throws Error;
        public abstract void remove_version (ToolVersion ver) throws Error;
        public abstract bool is_installed (ToolVersion ver);
        public abstract string installed_path (ToolVersion ver);
        public abstract string resolve_latest_tag () throws Error;
        public abstract void invalidate_cache ();
    }
}
