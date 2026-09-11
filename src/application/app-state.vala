namespace Lumoria.Application {

    public enum PageKind {
        EMPTY,
        CREATE_PREFIX,
        PREFIX,
        HOME,
        COMPONENTS,
        RUNNERS,
        STORAGE,
        PREFERENCES;

        public string to_key () {
            switch (this) {
                case CREATE_PREFIX: return "create";
                case PREFIX: return "prefix";
                case HOME: return "home";
                case COMPONENTS: return "components";
                case RUNNERS: return "runners";
                case STORAGE: return "storage";
                case PREFERENCES: return "preferences";
                default: return "empty";
            }
        }

        public static PageKind from_key (string key) {
            switch (key) {
                case "create": return CREATE_PREFIX;
                case "prefix": return PREFIX;
                case "home": return HOME;
                case "components": return COMPONENTS;
                case "runners": return RUNNERS;
                case "storage": return STORAGE;
                case "preferences": return PREFERENCES;
                default: return EMPTY;
            }
        }
    }

    public class AppState : Object {
        public signal void changed ();
        public signal void persist_failed (string message);

        public string selected_prefix_id { get; private set; default = ""; }
        public PageKind page { get; private set; default = PageKind.EMPTY; }
        public string busy_message { get; private set; default = ""; }
        public Models.LaunchRef quick_launch { get; private set; }
        public Gee.ArrayList<Models.LaunchRef> favorites { get; private set; }
        public string quick_launch_desktop_id { get; private set; default = ""; }
        public string quick_launch_steam_app_id { get; private set; default = ""; }
        public Gee.ArrayList<string> recent_icons { get; private set; }
        public string load_error { get; private set; default = ""; }
        private const int RECENT_ICONS_LIMIT = 12;
        private Utils.Debouncer persist;

        public AppState () {
            quick_launch = new Models.LaunchRef ();
            favorites = new Gee.ArrayList<Models.LaunchRef> ();
            recent_icons = new Gee.ArrayList<string> ();
            persist = new Utils.Debouncer (0, write_state);
        }

        /* registry_dirty reports legacy display data folded into the registry; the caller persists it through PrefixService. */
        public static AppState load (Models.PrefixRegistry registry, out bool registry_dirty) {
            var state = new AppState ();
            var path = Utils.app_state_path ();
            var loaded = false;
            registry_dirty = false;
            try {
                var obj = Utils.read_validated_json (path, "app-state");
                if (obj != null) {
                    state.selected_prefix_id = Models.json_string (obj, "selected_prefix_id");
                    state.page = PageKind.from_key (Models.json_string (obj, "page"));
                    if (obj.has_member ("quick_launch")) {
                        var ql = obj.get_object_member ("quick_launch");
                        state.quick_launch = Models.LaunchRef.from_json (ql);
                        if (migrate_legacy_display (
                            registry,
                            ql,
                            state.quick_launch.prefix_id,
                            state.quick_launch.action_id
                        )) {
                            registry_dirty = true;
                        }
                    }
                    state.quick_launch_desktop_id = Models.json_string (obj, "quick_launch_desktop_id");
                    state.quick_launch_steam_app_id = Models.json_string (obj, "quick_launch_steam_app_id");
                    if (obj.has_member ("favorites")) {
                        var arr = obj.get_array_member ("favorites");
                        for (uint i = 0; i < arr.get_length (); i++) {
                            var raw = arr.get_object_element (i);
                            var fav = Models.LaunchRef.from_json (raw);
                            if (fav.is_empty ()) continue;
                            state.favorites.add (fav);
                            if (migrate_legacy_display (registry, raw, fav.prefix_id, fav.action_id)) {
                                registry_dirty = true;
                            }
                        }
                    }
                    foreach (var key in Models.json_string_array (obj, "recent_icons")) {
                        state.add_recent_icon (key);
                    }
                    loaded = true;
                }
            } catch (Error e) {
                warning ("Failed to load app state: %s", e.message);
                Utils.quarantine_broken_file (path);
                state.load_error = _("Could not load saved layout; using defaults.");
            }

            var dirty = state.normalize_after_load (registry);
            if (!loaded || dirty || registry_dirty) state.flush_persist ();
            return state;
        }

        private static bool migrate_legacy_display (
            Models.PrefixRegistry registry,
            Json.Object obj,
            string prefix_id,
            string action_id
        ) {
            if (!obj.has_member ("nickname") && !obj.has_member ("icon")) return false;
            var nickname = Models.json_string (obj, "nickname");
            var icon = Models.FfxiIconCatalog.sanitize_slot_key (Models.json_string (obj, "icon"));
            if (nickname == "" && icon == "") return false;
            var entry = registry.by_id (prefix_id);
            if (entry == null) return false;
            var target_id = action_id != "" ? action_id : entry.launch_entrypoint_id;
            if (target_id == "") return false;
            var existing = entry.launch_display.get (target_id);
            if (existing != null && (existing.icon != "" || existing.nickname != "")) return false;
            entry.apply_launch_display (target_id, icon, nickname);
            return true;
        }

        private bool normalize_after_load (Models.PrefixRegistry registry) {
            var dirty = false;
            if (quick_launch.action_id != "") {
                quick_launch.pin_prefix (quick_launch.prefix_id);
                dirty = true;
            }
            if (quick_launch.is_empty ()) {
                var prefix = registry.default_prefix ();
                if (prefix != null && quick_launch.prefix_id != prefix.id) {
                    quick_launch.pin_prefix (prefix.id);
                    dirty = true;
                }
            }

            if (selected_prefix_id != "" && registry.by_id (selected_prefix_id) == null) {
                selected_prefix_id = "";
                dirty = true;
            }
            if (selected_prefix_id == "" && registry.prefixes.size > 0) {
                selected_prefix_id = registry.prefixes[0].id;
                dirty = true;
            }
            if (drop_missing_favorites (registry)) dirty = true;

            PageKind next;
            if (registry.prefixes.size == 0) {
                next = PageKind.EMPTY;
            } else if (Utils.Preferences.instance ().startup_view == Utils.StartupView.HOME) {
                next = PageKind.HOME;
            } else {
                next = selected_prefix_id != "" ? PageKind.PREFIX : PageKind.EMPTY;
            }
            if (page != next) {
                page = next;
                dirty = true;
            }
            return dirty;
        }

        public void select_prefix (string prefix_id) {
            if (busy_message != "") return;
            var next = prefix_id == "" ? PageKind.EMPTY : PageKind.PREFIX;
            if (selected_prefix_id == prefix_id && page == next) return;
            selected_prefix_id = prefix_id;
            page = next;
            commit ();
        }

        public void show_page (PageKind kind) {
            if (busy_message != "") return;
            if (kind == PageKind.CREATE_PREFIX && Utils.EnvironmentInfo.is_gamescope ()) {
                return;
            }
            if (page == kind) return;
            page = kind;
            commit ();
        }

        public Models.LaunchRef? favorite (string prefix_id, string action_id) {
            foreach (var fav in favorites) {
                if (fav.matches (prefix_id, action_id)) return fav;
            }
            return null;
        }

        public void toggle_favorite (string prefix_id, string action_id) {
            if (favorite (prefix_id, action_id) != null) remove_favorite (prefix_id, action_id);
            else add_favorite (prefix_id, action_id);
        }

        private void add_favorite (string prefix_id, string action_id) {
            if (prefix_id == "" || favorite (prefix_id, action_id) != null) return;
            var fav = new Models.LaunchRef ();
            fav.prefix_id = prefix_id;
            fav.action_id = action_id;
            favorites.add (fav);
            commit ();
        }

        public void remove_favorite (string prefix_id, string action_id) {
            if (remove_favorites_where (fav => fav.matches (prefix_id, action_id))) commit ();
        }

        public void move_favorite (string prefix_id, string action_id, int dest) {
            var idx = favorite_index (prefix_id, action_id);
            if (idx < 0) return;
            if (Utils.move_item<Models.LaunchRef> (favorites, idx, dest)) commit ();
        }

        public void move_favorite_by (string prefix_id, string action_id, int delta) {
            var idx = favorite_index (prefix_id, action_id);
            if (idx < 0) return;
            if (Utils.move_item<Models.LaunchRef> (favorites, idx, idx + delta)) commit ();
        }

        private int favorite_index (string prefix_id, string action_id) {
            for (int i = 0; i < favorites.size; i++) {
                if (favorites[i].matches (prefix_id, action_id)) return i;
            }
            return -1;
        }

        public void prune_invalid_favorites (string prefix_id, owned FavoriteExists exists) {
            if (remove_favorites_where (fav => {
                if (fav.prefix_id != prefix_id) return false;
                return fav.action_id == "" || !exists (fav.action_id);
            })) commit ();
        }

        public delegate bool FavoriteExists (string action_id);

        public void remember_icon (string key) {
            if (!add_recent_icon (key)) return;
            commit ();
        }

        public Gee.ArrayList<string> visible_recent_icons () {
            var catalog = Models.FfxiIconCatalog.instance ();
            var list = new Gee.ArrayList<string> ();
            foreach (var key in recent_icons) {
                if (Models.IconSlots.lookup (key) != null) {
                    list.add (key);
                    continue;
                }
                if (catalog.by_key (key) != null) list.add (key);
            }
            return list;
        }

        private bool add_recent_icon (string key) {
            if (!Models.FfxiIconCatalog.is_slot_key (key)) return false;
            recent_icons.remove (key);
            recent_icons.insert (0, key);
            while (recent_icons.size > RECENT_ICONS_LIMIT) {
                recent_icons.remove_at (recent_icons.size - 1);
            }
            return true;
        }

        public void update_quick_launch (string prefix_id) {
            if (quick_launch.prefix_id == prefix_id && quick_launch.action_id == "") return;
            quick_launch.pin_prefix (prefix_id);
            commit ();
        }

        public void clear_quick_launch () {
            if (quick_launch.is_empty ()) return;
            quick_launch.pin_prefix ("");
            commit ();
        }

        public void update_quick_launch_desktop_id (string desktop_id) {
            if (quick_launch_desktop_id == desktop_id) return;
            quick_launch_desktop_id = desktop_id;
            commit ();
        }

        public void update_quick_launch_steam_app_id (string app_id) {
            if (quick_launch_steam_app_id == app_id) return;
            quick_launch_steam_app_id = app_id;
            commit ();
        }

        public void forget_prefix (string prefix_id, string next_id = "") {
            var changed_state = false;
            if (selected_prefix_id == prefix_id) {
                selected_prefix_id = next_id;
                changed_state = true;
            }
            if (quick_launch.prefix_id == prefix_id) {
                quick_launch.pin_prefix (next_id);
                changed_state = true;
            }
            if (remove_favorites_where (fav => fav.prefix_id == prefix_id)) changed_state = true;
            if (page == PageKind.PREFIX) {
                var land = selected_prefix_id != "" ? PageKind.HOME : PageKind.EMPTY;
                if (page != land) {
                    page = land;
                    changed_state = true;
                }
            }
            if (changed_state) commit ();
        }

        private bool drop_missing_favorites (Models.PrefixRegistry registry) {
            return remove_favorites_where (fav => registry.by_id (fav.prefix_id) == null);
        }

        private bool remove_favorites_where (FavoriteMatch match) {
            var changed_state = false;
            for (int i = favorites.size - 1; i >= 0; i--) {
                if (!match (favorites[i])) continue;
                favorites.remove_at (i);
                changed_state = true;
            }
            return changed_state;
        }

        private delegate bool FavoriteMatch (Models.LaunchRef fav);

        public void set_busy (string message) {
            if (busy_message == message) return;
            busy_message = message;
            changed ();
        }

        public void clear_busy () {
            if (busy_message == "") return;
            busy_message = "";
            changed ();
        }

        private void commit () {
            persist.schedule ();
            changed ();
        }

        public void flush_persist () {
            persist.flush ();
        }

        private void write_state () {
            var root = new Json.Object ();
            root.set_int_member ("format_version", Config.CONFIG_FORMAT_VERSION);
            if (selected_prefix_id != "") root.set_string_member ("selected_prefix_id", selected_prefix_id);
            root.set_string_member ("page", page.to_key ());
            if (!quick_launch.is_empty ()) {
                root.set_object_member ("quick_launch", quick_launch.to_json ());
            }
            if (favorites.size > 0) {
                var arr = new Json.Array ();
                foreach (var fav in favorites) {
                    arr.add_object_element (fav.to_json ());
                }
                root.set_array_member ("favorites", arr);
            }
            if (quick_launch_desktop_id != "") {
                root.set_string_member ("quick_launch_desktop_id", quick_launch_desktop_id);
            }
            if (quick_launch_steam_app_id != "") {
                root.set_string_member ("quick_launch_steam_app_id", quick_launch_steam_app_id);
            }
            if (recent_icons.size > 0) {
                var arr = new Json.Array ();
                foreach (var key in recent_icons) arr.add_string_element (key);
                root.set_array_member ("recent_icons", arr);
            }

            try {
                Utils.write_validated_json (Utils.app_state_path (), "app-state", root);
            } catch (Error e) {
                warning ("Failed to save app state: %s", e.message);
                persist_failed (user_error (e));
            }
        }
    }
}
