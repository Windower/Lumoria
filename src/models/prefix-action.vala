namespace Lumoria.Models {

    public enum PrefixActionProvider {
        BUILTIN,
        INSTALLER,
        LAUNCHER,
        POST_INSTALL_SCRIPT,
        COMPONENT,
        USER
    }

    public enum PrefixActionKind {
        LAUNCH,
        MAINTENANCE,
        OPEN_LOCATION;
    }

    public class PrefixAction : Object {
        public const string BUILTIN_OPEN_PREFIX = "builtin:open-prefix";
        public const string BUILTIN_OPEN_LAUNCHER = "builtin:open-launcher";
        private const string SCRIPT_ID_PREFIX = "script:";

        public static string compose_id (PrefixActionProvider provider, string provider_id, string local_id) {
            if (provider == PrefixActionProvider.POST_INSTALL_SCRIPT && provider_id != "") {
                return "%s%s:%s".printf (SCRIPT_ID_PREFIX, provider_id, local_id);
            }
            return local_id;
        }

        public static bool parse_script_id (string action_id, out string instance_id, out string local_id) {
            instance_id = "";
            local_id = "";
            if (!action_id.has_prefix (SCRIPT_ID_PREFIX)) return false;
            var rest = action_id.substring (SCRIPT_ID_PREFIX.length);
            var sep = rest.index_of_char (':');
            if (sep <= 0 || sep >= rest.length - 1) return false;
            instance_id = rest.substring (0, sep);
            local_id = rest.substring (sep + 1);
            return instance_id != "" && local_id != "";
        }
    }

    public class LoadedPostInstall : Object {
        public PrefixPostInstallManifest metadata { get; set; }
        public PostInstallManifest spec { get; set; }
    }

    public class PostInstallLoadError : Object {
        public string name { get; set; default = ""; }
        public string reason { get; set; default = ""; }
    }
}
