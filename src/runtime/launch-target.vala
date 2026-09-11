namespace Lumoria.Runtime {

    public enum LaunchTargetSection {
        LAUNCHER,
        LAUNCHER_PROFILES,
        LAUNCH,
        POST_INSTALL,
        CUSTOM
    }

    public class LaunchTarget : Object {
        public string id { get; set; default = ""; }
        public string label { get; set; default = ""; }
        public string selector_label { get; set; default = ""; }
        public string description { get; set; default = ""; }
        public string icon { get; set; default = ""; }
        public bool has_button { get; set; default = false; }
        public string button_label { get; set; default = ""; }
        public string button_style { get; set; default = ""; }
        public string button_icon { get; set; default = ""; }
        public bool is_action { get; set; default = false; }
        public LaunchTargetSection section { get; set; default = LaunchTargetSection.LAUNCH; }
        public string group_title { get; set; default = ""; }
        public string location { get; set; default = ""; }
        public Models.ManifestAction? spec { get; set; default = null; }
        public Models.PrefixActionKind kind {
            get {
                if (location != "" || id == Models.PrefixAction.BUILTIN_OPEN_PREFIX
                    || id == Models.PrefixAction.BUILTIN_OPEN_LAUNCHER) {
                    return Models.PrefixActionKind.OPEN_LOCATION;
                }
                return is_action ? Models.PrefixActionKind.MAINTENANCE : Models.PrefixActionKind.LAUNCH;
            }
        }

        public bool pinnable {
            get { return kind != Models.PrefixActionKind.OPEN_LOCATION; }
        }

        public Models.PrefixActionProvider provider_type {
            get {
                string instance_id;
                string local_id;
                if (Models.PrefixAction.parse_script_id (id, out instance_id, out local_id)) {
                    return Models.PrefixActionProvider.POST_INSTALL_SCRIPT;
                }
                if (Models.PrefixEntry.is_custom_entry_id (id)) return Models.PrefixActionProvider.USER;
                if (id == Models.PrefixAction.BUILTIN_OPEN_PREFIX) return Models.PrefixActionProvider.BUILTIN;
                if (section == LaunchTargetSection.LAUNCHER
                    || section == LaunchTargetSection.LAUNCHER_PROFILES
                    || id == Models.PrefixAction.BUILTIN_OPEN_LAUNCHER) {
                    return Models.PrefixActionProvider.LAUNCHER;
                }
                return Models.PrefixActionProvider.INSTALLER;
            }
        }

        public string provider_id {
            owned get {
                string instance_id;
                string local_id;
                if (Models.PrefixAction.parse_script_id (id, out instance_id, out local_id)) return instance_id;
                return "";
            }
        }

        public string shortcut_label (Models.PrefixEntry entry) {
            return "%s (%s) - %s".printf (Config.APP_NAME, entry.display_name (), selector_label);
        }

        public static LaunchTarget open_folder (string id, string label, string location) {
            var target = new LaunchTarget ();
            target.id = id;
            target.label = label;
            target.selector_label = label;
            target.icon = "open_folder";
            target.location = location;
            if (id == Models.PrefixAction.BUILTIN_OPEN_LAUNCHER) {
                target.section = LaunchTargetSection.LAUNCHER;
                target.has_button = true;
                target.button_label = _("Open");
            }
            return target;
        }
    }

    public class LaunchPlan : Object {
        public string entrypoint_id { get; set; default = ""; }
        public string executable { get; set; default = ""; }
        public string[] args { get; set; default = {}; }
        public Models.Entrypoint? entrypoint { get; set; default = null; }
    }

    public string launch_target_section_title (LaunchTargetSection section) {
        switch (section) {
            case LaunchTargetSection.LAUNCHER:
                return _("Launcher");
            case LaunchTargetSection.LAUNCHER_PROFILES:
                return _("Profiles");
            case LaunchTargetSection.POST_INSTALL:
                return _("Scripts");
            case LaunchTargetSection.CUSTOM:
                return _("Custom");
            default:
                return _("Launch");
        }
    }

}
