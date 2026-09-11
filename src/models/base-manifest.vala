namespace Lumoria.Models {

    public abstract class IdentifiedRecord : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string label { get; set; default = ""; }

        public string display_label () {
            if (label != "") return label;
            if (name != "") return name;
            return id;
        }

        protected void parse_identity (Json.Object obj) {
            id = json_string (obj, "id");
            name = json_string (obj, "name");
            label = json_string (obj, "label");
        }
    }

    public abstract class BaseManifest : IdentifiedRecord {
        public Gee.ArrayList<string> skip_versions { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> features { get; owned set; default = new Gee.ArrayList<string> (); }
        public bool recommended { get; set; default = false; }
        public SupportStatus support { get; set; default = SupportStatus.SUPPORTED; }
        public ManifestMessages messages { get; owned set; default = new ManifestMessages (); }
        public ManifestLinks links { get; owned set; default = new ManifestLinks (); }

        public bool skips_version (string tag) {
            var normalized = tag.strip ();
            if (normalized == "") return false;
            foreach (var skipped in skip_versions) {
                if (skipped.strip () == normalized) return true;
            }
            return false;
        }

        public bool supports_feature (string feature) {
            var normalized = feature.strip ();
            if (normalized == "") return false;
            foreach (var f in features) {
                if (f.strip () == normalized) return true;
            }
            return false;
        }

        protected void parse_base (Json.Object obj) {
            parse_identity (obj);
            skip_versions = json_string_array (obj, "skip_versions");
            features = json_string_array (obj, "features");
            recommended = json_bool (obj, "recommended");
            support = SupportStatus.parse (json_string (obj, "support"));
            messages = ManifestMessages.from_json (obj);
            links = ManifestLinks.from_json (obj);
        }
    }

    public abstract class InstallableManifest : BaseManifest {
        public Gee.ArrayList<DownloadItem> downloads { get; owned set; default = new Gee.ArrayList<DownloadItem> (); }
        public Gee.ArrayList<InstallStep> steps { get; owned set; default = new Gee.ArrayList<InstallStep> (); }
        public Gee.ArrayList<ManifestAction> actions { get; owned set; default = new Gee.ArrayList<ManifestAction> (); }
        public Gee.ArrayList<RemoteManifestAction> remote_manifest_actions { get; owned set; default = new Gee.ArrayList<RemoteManifestAction> (); }
        public Gee.ArrayList<EnvRule> env { get; owned set; default = new Gee.ArrayList<EnvRule> (); }
        public Gee.HashMap<string, string> variables { get; owned set; default = new Gee.HashMap<string, string> (); }
        public Gee.ArrayList<EnvRule> variable_rules { get; owned set; default = new Gee.ArrayList<EnvRule> (); }
        public Gee.ArrayList<Entrypoint> entrypoints { get; owned set; default = new Gee.ArrayList<Entrypoint> (); }
        public Gee.ArrayList<string> redists { get; owned set; default = new Gee.ArrayList<string> (); }
        public bool reinstallable { get; set; default = true; }
        public string wineboot_mscoree { get; set; default = "disabled"; }
        public bool has_wineboot_mscoree { get; set; default = false; }
        public string icon { get; set; default = ""; }

        protected void parse_installable (Json.Object obj) throws Error {
            parse_base (obj);
            icon = json_string (obj, "icon");
            downloads = parse_downloads (obj);
            steps = parse_steps (obj);
            actions = parse_manifest_actions (obj);
            remote_manifest_actions = parse_remote_manifest_actions (obj);
            env = parse_env_rules (obj);
            reinstallable = json_bool (obj, "reinstallable", true);
            has_wineboot_mscoree = obj.has_member ("wineboot_mscoree");
            wineboot_mscoree = json_string (obj, "wineboot_mscoree", "disabled");
            Gee.HashMap<string, string> parsed_variables;
            Gee.ArrayList<EnvRule> parsed_rules;
            parse_variable_definitions (obj, "variables", out parsed_variables, out parsed_rules);
            variables = parsed_variables;
            variable_rules = parsed_rules;
            entrypoints = parse_entrypoints (obj);
            redists = json_string_array (obj, "redists");
        }
    }
}
