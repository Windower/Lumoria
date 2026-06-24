namespace Lumoria.Widgets {

    public class IconRegistry : Object {
        public const string ADD = "list-add-symbolic";
        public const string MENU = "open-menu-symbolic";
        public const string DOWNLOAD = "folder-download-symbolic";
        public const string OPEN_FOLDER = "folder-open-symbolic";
        public const string OPEN_DIRECTORY = "folder-symbolic";
        public const string DELETE = "user-trash-symbolic";
        public const string CHECKMARK = "object-select-symbolic";
        public const string COPY = "edit-copy-symbolic";
        public const string PASTE = "edit-paste-symbolic";
        public const string REFRESH = "view-refresh-symbolic";
        public const string CLOSE = "window-close-symbolic";
        public const string SESSIONS = "view-list-symbolic";
        public const string MANAGE = "preferences-system-symbolic";
        public const string TOOLS = "applications-engineering-symbolic";
        public const string INFO = "dialog-information-symbolic";
        public const string WARNING = "dialog-warning-symbolic";
        public const string SUCCESS = "emblem-ok-symbolic";
        public const string ERROR = "dialog-error-symbolic";
        public const string PENDING = "emblem-system-symbolic";
        public const string STARRED = "starred-symbolic";
        public const string UNSTARRED = "non-starred-symbolic";

        public static string resolve_action_icon (string name) {
            switch (name) {
                case "add":           return ADD;
                case "menu":          return MENU;
                case "download":      return DOWNLOAD;
                case "open_folder":   return OPEN_FOLDER;
                case "open_dir":      return OPEN_DIRECTORY;
                case "delete":        return DELETE;
                case "checkmark":     return CHECKMARK;
                case "copy":          return COPY;
                case "paste":         return PASTE;
                case "refresh":       return REFRESH;
                case "close":         return CLOSE;
                case "sessions":      return SESSIONS;
                case "manage":        return MANAGE;
                case "tools":         return TOOLS;
                case "info":          return INFO;
                case "warning":       return WARNING;
                case "success":       return SUCCESS;
                case "error":         return ERROR;
                case "pending":       return PENDING;
                case "starred":       return STARRED;
                case "unstarred":     return UNSTARRED;
                case "play":          return PAGE_LAUNCH;
                case "install":       return PAGE_PACKAGES;
                case "runners":       return PAGE_RUNNERS;
                case "components":    return PAGE_COMPONENTS;
                case "shortcuts":     return PAGE_SHORTCUTS;
                case "storage":       return PAGE_STORAGE;
                case "advanced":      return PAGE_ADVANCED;
                case "about":         return PAGE_ABOUT;
                default:              return TOOLS;
            }
        }

        public const string PAGE_GENERAL = MANAGE;
        public const string PAGE_RUNTIME = TOOLS;
        public const string PAGE_RUNNERS = "system-run-symbolic";
        public const string PAGE_COMPONENTS = "applications-utilities-symbolic";
        public const string PAGE_LAUNCH = "media-playback-start-symbolic";
        public const string PAGE_SHORTCUTS = MENU;
        public const string PAGE_PACKAGES = "system-software-install-symbolic";
        public const string PAGE_STORAGE = "drive-harddisk-symbolic";
        public const string PAGE_ADVANCED = "applications-system-symbolic";
        public const string PAGE_ABOUT = "help-about-symbolic";

        public static string settings_page_icon (string page_id) {
            switch (page_id) {
                case SettingsShared.PAGE_GENERAL:
                    return PAGE_GENERAL;
                case SettingsShared.PAGE_RUNTIME:
                    return PAGE_RUNTIME;
                case SettingsShared.PAGE_RUNNERS:
                    return PAGE_RUNNERS;
                case SettingsShared.PAGE_COMPONENTS:
                    return PAGE_COMPONENTS;
                case SettingsShared.PAGE_LAUNCH:
                    return PAGE_LAUNCH;
                case SettingsShared.PAGE_SHORTCUTS:
                    return PAGE_SHORTCUTS;
                case SettingsShared.PAGE_PACKAGES:
                    return PAGE_PACKAGES;
                case SettingsShared.PAGE_STORAGE:
                    return PAGE_STORAGE;
                case SettingsShared.PAGE_ADVANCED:
                    return PAGE_ADVANCED;
                case SettingsShared.PAGE_ABOUT:
                    return PAGE_ABOUT;
                default:
                    return PAGE_GENERAL;
            }
        }
    }
}
