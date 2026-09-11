namespace Lumoria.Ui {

    public class PrefixView : Gtk.Box, TabHost {
        public Adw.ViewStack stack { get; private set; }

        private PrefixRuntimePage? runtime_page;

        private Application.Context ctx;
        private Models.PrefixEntry entry;
        private Gtk.Box shortcuts_host;
        private Gtk.Box runtime_host;
        private Gtk.Box scripts_host;
        private Gtk.Box advanced_host;
        private bool remotes_refreshed = false;

        public PrefixView (Application.Context ctx, Models.PrefixEntry entry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            hexpand = true;
            vexpand = true;
            this.ctx = ctx;
            this.entry = entry;

            var banner = new PrefixBanner (ctx, entry);

            stack = Widgets.PageChrome.settings_stack ();

            var general = new PrefixGeneralPage (ctx, entry);
            Widgets.PageChrome.add_scrolled_settings_page (
                stack, general, Widgets.PageChrome.PAGE_GENERAL, _("Overview")
            );

            shortcuts_host = lazy_scrolled_tab (stack, Widgets.PageChrome.PAGE_SHORTCUTS, _("Shortcuts"));
            runtime_host = lazy_tab (stack, Widgets.PageChrome.PAGE_RUNTIME, _("Runtime"));
            scripts_host = lazy_tab (stack, Widgets.PageChrome.PAGE_SCRIPTS, _("Scripts"));
            advanced_host = lazy_scrolled_tab (stack, Widgets.PageChrome.PAGE_ADVANCED, _("Advanced"));

            stack.notify["visible-child-name"].connect (() => realize_tab (stack.visible_child_name));

            append (Widgets.PageChrome.page_with_stack (stack, Widgets.PageChrome.page_title (Config.APP_NAME), banner));
            map.connect (refresh_remotes_once);
        }

        private void refresh_remotes_once () {
            if (remotes_refreshed) return;
            remotes_refreshed = true;
            ctx.actions.refresh_remotes (entry);
        }

        /* Inside the Runtime tab the shoulder buttons step its inner tabs instead of the outer ones. */
        public bool cycle_tabs (int delta) {
            if (runtime_page != null && stack.visible_child_name == Widgets.PageChrome.PAGE_RUNTIME) {
                return runtime_page.cycle_tabs (delta);
            }
            return Widgets.PageChrome.cycle_stack (stack, delta);
        }

        public string selected_tab () {
            var outer = stack.visible_child_name ?? "";
            if (outer == Widgets.PageChrome.PAGE_RUNTIME
                && runtime_page != null
                && runtime_page.inner_tab () == "packages") {
                return Widgets.PageChrome.PAGE_PACKAGES;
            }
            return outer;
        }

        public void restore_tab (string? name) {
            if (name == null || name == "") return;
            if (name == Widgets.PageChrome.PAGE_PACKAGES) {
                stack.visible_child_name = Widgets.PageChrome.PAGE_RUNTIME;
                realize_tab (Widgets.PageChrome.PAGE_RUNTIME);
                if (runtime_page != null) runtime_page.show_inner ("packages");
                return;
            }
            if (stack.get_child_by_name (name) != null) {
                stack.visible_child_name = name;
                realize_tab (name);
            }
        }

        private static Gtk.Box lazy_scrolled_tab (Adw.ViewStack stack, string id, string title) {
            var host = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            host.hexpand = true;
            Widgets.PageChrome.add_scrolled_settings_page (stack, host, id, title);
            return host;
        }

        private static Gtk.Box lazy_tab (Adw.ViewStack stack, string id, string title) {
            var host = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            host.hexpand = true;
            host.vexpand = true;
            Widgets.PageChrome.add_settings_page (stack, host, id, title);
            return host;
        }

        private void realize_tab (string? id) {
            if (id == null || id == "") return;
            if (id == Widgets.PageChrome.PAGE_SHORTCUTS && shortcuts_host.get_first_child () == null) {
                shortcuts_host.append (new PrefixShortcutsPage (ctx, entry));
            } else if (id == Widgets.PageChrome.PAGE_RUNTIME && runtime_page == null) {
                runtime_page = new PrefixRuntimePage (ctx, entry);
                runtime_host.append (runtime_page);
            } else if (id == Widgets.PageChrome.PAGE_SCRIPTS && scripts_host.get_first_child () == null) {
                scripts_host.append (new ScriptListEditor (ctx, entry.post_install_manifests, entry));
            } else if (id == Widgets.PageChrome.PAGE_ADVANCED && advanced_host.get_first_child () == null) {
                advanced_host.append (new PrefixAdvancedPage (ctx, entry));
            }
        }
    }
}
