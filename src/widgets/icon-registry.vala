namespace Lumoria.Widgets {

    public class IconRegistry : Object {
        public const string ADD = "list-add-symbolic";
        public const string MENU = "open-menu-symbolic";
        public const string DOWNLOAD = "folder-download-symbolic";
        public const string OPEN_FOLDER = "folder-open-symbolic";
        public const string OPEN_DIRECTORY = "folder-symbolic";
        public const string DELETE = "user-trash-symbolic";
        public const string CHECKMARK = "object-select-symbolic";
        public const string EDIT = "document-edit-symbolic";
        public const string COPY = "edit-copy-symbolic";
        public const string PASTE = "edit-paste-symbolic";
        public const string REFRESH = "view-refresh-symbolic";
        public const string CLOSE = "window-close-symbolic";
        public const string NEXT = "go-next-symbolic";
        public const string MOVE_UP = "go-up-symbolic";
        public const string MOVE_DOWN = "go-down-symbolic";
        public const string APP_GRID = "view-app-grid-symbolic";
        public const string SIDEBAR = "sidebar-show-symbolic";
        public const string SEARCH = "system-search-symbolic";
        public const string DROPDOWN = "pan-down-symbolic";
        public const string STOP = "process-stop-symbolic";
        public const string SESSIONS = "view-list-symbolic";
        public const string MANAGE = "preferences-system-symbolic";
        public const string TOOLS = "applications-engineering-symbolic";
        public const string INFO = "dialog-information-symbolic";
        public const string HELP = "help-about-symbolic";
        public const string WEB = "web-browser-symbolic";
        public const string WEB_RESOURCE = Config.RESOURCE_BASE + "/icons/scalable/actions/web-browser-symbolic.svg";
        public const string DISCORD = "discord-symbolic";
        public const string DISCORD_RESOURCE = Config.RESOURCE_BASE + "/icons/scalable/actions/discord-symbolic.svg";
        public const string WARNING = "dialog-warning-symbolic";
        public const string SUCCESS = CHECKMARK;
        public const string ERROR = "dialog-error-symbolic";
        public const string PENDING = "emblem-system-symbolic";
        public const string STARRED = "starred-symbolic";
        public const string UNSTARRED = "non-starred-symbolic";
        public const string BOOKMARK = "bookmark-new-symbolic";
        public const string BOOKMARKED = "user-bookmarks-symbolic";
        public const string BOOKMARKED_ALT = "bookmarks-bookmarked-symbolic";
        public const string MASCOT_RESOURCE = Config.RESOURCE_BASE + "/ui/lumoria-mascot.svg";

        public static Gtk.Image mascot_image (int pixel_size) {
            var image = new Gtk.Image.from_resource (MASCOT_RESOURCE);
            image.pixel_size = pixel_size;
            image.halign = Gtk.Align.CENTER;
            return image;
        }

        public static Gtk.Image discord_image (int pixel_size) {
            return themed_or_resource ({ DISCORD }, DISCORD_RESOURCE, pixel_size);
        }

        public static Gtk.Image web_image (int pixel_size) {
            var image = new Gtk.Image ();
            image.pixel_size = pixel_size;
            var file = File.new_for_uri ("resource://" + WEB_RESOURCE);
            image.set_from_paintable (new Gtk.IconPaintable.for_file (file, pixel_size, 1));
            return image;
        }

        private static Gtk.Image themed_or_resource (string[] names, string resource, int pixel_size) {
            var name = first_themed_icon (names);
            var icon = name != null
                ? new Gtk.Image.from_icon_name (name)
                : new Gtk.Image.from_resource (resource);
            icon.pixel_size = pixel_size;
            return icon;
        }

        private static Gtk.IconTheme? icon_theme (Gdk.Display? display = null) {
            var target = display ?? Gdk.Display.get_default ();
            return target != null ? Gtk.IconTheme.get_for_display (target) : null;
        }

        private static string? first_themed_icon (string[] names, Gdk.Display? display = null) {
            var theme = icon_theme (display);
            if (theme == null) return null;
            foreach (var name in names) {
                if (theme.has_icon (name)) return name;
            }
            return null;
        }

        public static string bookmark_icon_name (bool bookmarked) {
            if (!bookmarked) return BOOKMARK;
            return first_themed_icon ({ BOOKMARKED_ALT }) ?? BOOKMARKED;
        }

        public static Gtk.Image bookmark_image (bool bookmarked, int pixel_size) {
            var image = new Gtk.Image.from_icon_name (bookmark_icon_name (bookmarked));
            image.pixel_size = pixel_size;
            return image;
        }

        public static void apply_bookmark (Gtk.Image image, bool bookmarked, int pixel_size) {
            image.set_from_icon_name (bookmark_icon_name (bookmarked));
            image.pixel_size = pixel_size;
        }

        private static void clear_slot_style (Gtk.Image image) {
            foreach (var slot in Models.IconSlots.all ()) {
                if (slot.css_class != "") image.remove_css_class (slot.css_class);
            }
        }

        private static void apply_slot (Gtk.Image image, Models.IconSlot slot, int pixel_size) {
            image.pixel_size = pixel_size;
            if (slot.css_class != "") image.add_css_class (slot.css_class);
            if (slot.symbolic != "" && apply_symbolic (image, slot.symbolic, pixel_size)) return;
            if (slot.resource != "") image.set_from_resource (slot.resource);
        }

        private static bool apply_symbolic (Gtk.Image image, string name, int pixel_size) {
            var theme = icon_theme (image.get_display ());
            if (theme == null || !theme.has_icon (name)) return false;
            image.set_from_paintable (theme.lookup_icon (
                name,
                null,
                pixel_size,
                1,
                Gtk.TextDirection.NONE,
                Gtk.IconLookupFlags.FORCE_SYMBOLIC
            ));
            return true;
        }

        public static string resolve_action_icon (string name) {
            switch (name) {
                case "add":           return ADD;
                case "menu":          return MENU;
                case "download":      return DOWNLOAD;
                case "open_folder":   return OPEN_FOLDER;
                case "open_dir":      return OPEN_DIRECTORY;
                case "delete":        return DELETE;
                case "checkmark":     return CHECKMARK;
                case "edit":          return EDIT;
                case "copy":          return COPY;
                case "paste":         return PASTE;
                case "refresh":       return REFRESH;
                case "close":         return CLOSE;
                case "sessions":      return SESSIONS;
                case "manage":        return MANAGE;
                case "tools":         return TOOLS;
                case "info":          return INFO;
                case "help":          return HELP;
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
                default:
                    if (name.has_suffix ("-symbolic")) return name;
                    return TOOLS;
            }
        }

        public static bool apply_icon_key (Gtk.Image image, string key, int pixel_size) {
            var resolved_key = Models.FfxiIconCatalog.sanitize_slot_key (key);
            clear_slot_style (image);
            image.pixel_size = pixel_size;
            if (resolved_key == "") {
                image.clear ();
                return false;
            }
            var slot = Models.IconSlots.lookup (resolved_key);
            if (slot != null) {
                apply_slot (image, slot, pixel_size);
                return true;
            }
            var ffxi_id = Models.FfxiIconCatalog.id_from_key (resolved_key);
            if (ffxi_id != null) {
                var texture = FfxiIconTextures.instance ().texture (ffxi_id);
                if (texture == null) {
                    image.clear ();
                    return false;
                }
                image.set_from_paintable (texture);
                return true;
            }
            var resolved = resolve_action_icon (resolved_key);
            if (resolved == TOOLS && resolved_key != "tools") {
                image.clear ();
                return false;
            }
            image.set_from_icon_name (resolved);
            return true;
        }

        public static Gtk.Widget icon_key_image (string key, int pixel_size) {
            var image = new Gtk.Image ();
            if (!apply_icon_key (image, key, pixel_size)) return blank_icon (pixel_size);
            return image;
        }

        private static Gtk.Widget blank_icon (int pixel_size) {
            var empty = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            empty.set_size_request (pixel_size, pixel_size);
            return empty;
        }

        public const string PAGE_GENERAL = MANAGE;
        public const string PAGE_RUNTIME = TOOLS;
        public const string PAGE_RUNNERS = "system-run-symbolic";
        public const string PAGE_COMPONENTS = "applications-utilities-symbolic";
        public const string PAGE_LAUNCH = "media-playback-start-symbolic";
        public const string HOME = "go-home-symbolic";
        public const string PAGE_SHORTCUTS = MENU;
        public const string PAGE_PACKAGES = "system-software-install-symbolic";
        public const string PAGE_STORAGE = "drive-harddisk-symbolic";
        public const string PAGE_ADVANCED = "applications-system-symbolic";
        public const string PAGE_ABOUT = "help-about-symbolic";
        public const string PAGE_SCRIPTS = "text-x-script-symbolic";

        public static string settings_page_icon (string page_id) {
            switch (page_id) {
                case PageChrome.PAGE_GENERAL:
                    return PAGE_GENERAL;
                case PageChrome.PAGE_RUNTIME:
                    return PAGE_RUNTIME;
                case PageChrome.PAGE_SHORTCUTS:
                    return PAGE_SHORTCUTS;
                case PageChrome.PAGE_PACKAGES:
                    return PAGE_PACKAGES;
                case PageChrome.PAGE_ADVANCED:
                    return PAGE_ADVANCED;
                case PageChrome.PAGE_SCRIPTS:
                    return PAGE_SCRIPTS;
                default:
                    return PAGE_GENERAL;
            }
        }
    }
}
