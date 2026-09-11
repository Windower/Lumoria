namespace Lumoria.Models {

    public enum InstallStepKind {
        TASK,
        WINEEXEC,
        COPY,
        RENAME,
        DELETE,
        WRITE,
        XML_UPSERT,
        TEXT_UPSERT,
        LINK,
        REDIST,
        EXTRACT,
        EXTRACT_MULTI,
        MSI_INSTALL,
        FONTS,
        FONT_REPLACEMENT,
        CABEXTRACT,
        DLL_OVERRIDE,
        GIT,
        SET_COMPONENT_OVERRIDE,
        MANIFEST_EXTRACT,
        MANIFEST_CACHE_CLEAR,
        MANIFEST_DOWNLOADS_CLEAR,
        OPEN;

        public static InstallStepKind parse (string type) throws Error {
            switch (type) {
                case "task": return TASK;
                case "wineexec": return WINEEXEC;
                case "copy": return COPY;
                case "rename": return RENAME;
                case "delete": return DELETE;
                case "write": return WRITE;
                case "xml_upsert": return XML_UPSERT;
                case "text_upsert": return TEXT_UPSERT;
                case "link": return LINK;
                case "redist": return REDIST;
                case "extract": return EXTRACT;
                case "extract_multi": return EXTRACT_MULTI;
                case "msi_install": return MSI_INSTALL;
                case "fonts": return FONTS;
                case "font_replacement": return FONT_REPLACEMENT;
                case "cabextract": return CABEXTRACT;
                case "dll_override": return DLL_OVERRIDE;
                case "git": return GIT;
                case "set_component_override": return SET_COMPONENT_OVERRIDE;
                case "manifest_extract": return MANIFEST_EXTRACT;
                case "manifest_cache_clear": return MANIFEST_CACHE_CLEAR;
                case "manifest_downloads_clear": return MANIFEST_DOWNLOADS_CLEAR;
                case "open": return OPEN;
                default:
                    throw new LumoriaError.INVALID_MANIFEST ("Unknown install step type: %s", type);
            }
        }

        public unowned string id () {
            switch (this) {
                case WINEEXEC: return "wineexec";
                case COPY: return "copy";
                case RENAME: return "rename";
                case DELETE: return "delete";
                case WRITE: return "write";
                case XML_UPSERT: return "xml_upsert";
                case TEXT_UPSERT: return "text_upsert";
                case LINK: return "link";
                case REDIST: return "redist";
                case EXTRACT: return "extract";
                case EXTRACT_MULTI: return "extract_multi";
                case MSI_INSTALL: return "msi_install";
                case FONTS: return "fonts";
                case FONT_REPLACEMENT: return "font_replacement";
                case CABEXTRACT: return "cabextract";
                case DLL_OVERRIDE: return "dll_override";
                case GIT: return "git";
                case SET_COMPONENT_OVERRIDE: return "set_component_override";
                case MANIFEST_EXTRACT: return "manifest_extract";
                case MANIFEST_CACHE_CLEAR: return "manifest_cache_clear";
                case MANIFEST_DOWNLOADS_CLEAR: return "manifest_downloads_clear";
                case OPEN: return "open";
                default: return "task";
            }
        }
    }

    public class InstallStep : Object {
        public const string TASK_CREATE_PREFIX = "create_prefix";
        public InstallStepKind step_type { get; set; default = InstallStepKind.TASK; }
        public string description { get; set; default = ""; }
        public string command { get; set; default = ""; }
        public string mode { get; set; default = ""; }
        public string src { get; set; default = ""; }
        public string dst { get; set; default = ""; }
        public string working_dir { get; set; default = ""; }
        public string content { get; set; default = ""; }
        public string root { get; set; default = ""; }
        public string element { get; set; default = ""; }
        public string git_branch { get; set; default = ""; }
        public string git_tag { get; set; default = ""; }
        public string git_commit { get; set; default = ""; }
        public bool create_if_missing { get; set; default = true; }
        public bool overwrite_existing { get; set; default = false; }
        public bool idempotent { get; set; default = true; }
        public bool allow_nonzero_exit { get; set; default = false; }
        public bool allow_external_src { get; set; default = false; }
        public string manifest_url { get; set; default = ""; }
        public RemoteManifestSchema? manifest_schema { get; set; default = null; }
        public WhenClause? when { get; set; default = null; }
        public string for_each { get; set; default = ""; }
        public Gee.HashMap<string, string> match { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.HashMap<string, string> children { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<string> args { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> verify_paths { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> font_registrations { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<EnvRule> env { get; owned set; default = new Gee.ArrayList<EnvRule> (); }

        public static InstallStep from_json (Json.Object obj) throws Error {
            var s = new InstallStep ();
            s.step_type = InstallStepKind.parse (json_string (obj, "type"));
            s.description = json_string (obj, "description");
            s.command = json_string (obj, "command");
            s.mode = json_string (obj, "mode");
            s.src = json_string (obj, "src");
            s.dst = json_string (obj, "dst");
            s.working_dir = json_string (obj, "working_dir");
            s.content = json_string_or_array (obj, "content");
            s.root = json_string (obj, "root");
            s.element = json_string (obj, "element");
            s.git_branch = json_string (obj, "branch");
            s.git_tag = json_string (obj, "tag");
            s.git_commit = json_string (obj, "commit");
            s.create_if_missing = json_bool (obj, "create_if_missing", true);
            s.overwrite_existing = json_bool (obj, "overwrite_existing");
            s.idempotent = json_bool (obj, "idempotent", true);
            s.allow_nonzero_exit = json_bool (obj, "allow_nonzero_exit");
            s.allow_external_src = json_bool (obj, "allow_external_src");
            s.manifest_url = json_string (obj, "manifest_url");
            s.manifest_schema = json_parse_member<RemoteManifestSchema> (
                obj, "manifest_schema", RemoteManifestSchema.from_json
            );
            s.when = WhenClause.from_json_member (obj);
            s.for_each = json_string_or_array (obj, "for_each");
            s.match = json_string_map (obj, "match");
            s.children = json_string_map (obj, "children");
            s.args = json_string_array (obj, "args");
            s.verify_paths = json_string_array (obj, "verify_paths");
            s.font_registrations = json_string_array (obj, "font_registrations");
            s.env = parse_env_rules (obj);
            s.require_fields ();
            return s;
        }

        /* The schema checks presence and shape; only these two cross-field rules live here. */
        private void require_fields () throws Error {
            if (step_type == InstallStepKind.WINEEXEC && allow_nonzero_exit) {
                require (verify_paths.size > 0, "verify_paths when allow_nonzero_exit is true");
            }
            if (step_type == InstallStepKind.GIT && command == "clone") {
                require (src != "", "src");
            }
        }

        private void require (bool ok, string field) throws Error {
            if (ok) return;
            throw new LumoriaError.INVALID_MANIFEST (
                _("Install step '%s' requires %s").printf (step_type.id (), field)
            );
        }
    }

}
