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
        public const string MANAGE = "preferences-system-symbolic";
        public const string TOOLS = "applications-engineering-symbolic";
        public const string INFO = "dialog-information-symbolic";
        public const string WARNING = "dialog-warning-symbolic";
        public const string SUCCESS = "emblem-ok-symbolic";
        public const string ERROR = "dialog-error-symbolic";
        public const string PENDING = "emblem-system-symbolic";
        public const string STARRED = "starred-symbolic";
        public const string UNSTARRED = "non-starred-symbolic";

        public const string PAGE_GENERAL = MANAGE;
        public const string PAGE_RUNTIME = TOOLS;
        public const string PAGE_RUNNERS = "system-run-symbolic";
        public const string PAGE_COMPONENTS = "applications-utilities-symbolic";
        public const string PAGE_LAUNCH = "media-playback-start-symbolic";
        public const string PAGE_SHORTCUTS = MENU;
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
