namespace Lumoria.Ui {

    public class Content : Gtk.Box {
        private Application.Context ctx;
        private Gtk.Stack stack;
        private Gee.HashMap<string, Gtk.Widget> pages;
        private Gtk.Widget? create_page;
        private ManageRunnersPage? runtime_host;
        private TabHost? tabs;
        private Application.PageKind last_kind = Application.PageKind.EMPTY;
        private string last_prefix_id = "";
        private Gee.ArrayList<Gtk.Widget> doomed;
        private bool dismantling = false;

        public Content (Application.Context ctx) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            pages = new Gee.HashMap<string, Gtk.Widget> ();
            doomed = new Gee.ArrayList<Gtk.Widget> ();
            add_css_class ("content");
            hexpand = true;
            vexpand = true;
            stack = new Gtk.Stack ();
            stack.hexpand = true;
            stack.vexpand = true;
            stack.transition_duration = 200;
            append (stack);
            ctx.state.changed.connect (refresh);
            ctx.prefixes.list_changed.connect (refresh);
            ctx.installs.session_finished.connect (on_install_session_finished);
            refresh ();
        }

        public void refresh () {
            var kind = ctx.state.page;
            var prefix_id = ctx.state.selected_prefix_id;
            var same = stack.visible_child != null
                && kind == last_kind
                && (kind != Application.PageKind.PREFIX || prefix_id == last_prefix_id);
            if (!same) {
                show_page (kind, prefix_id);
            }
            evict_missing_prefixes ();
        }

        public bool cycle_tabs (int delta) {
            return tabs != null && tabs.cycle_tabs (delta);
        }

        private void show_page (Application.PageKind kind, string prefix_id) {
            tabs = null;

            Gtk.Widget page;
            switch (kind) {
                case Application.PageKind.HOME:
                    page = cached ("home", () => {
                        return Widgets.PageChrome.page (
                            _("Lumoria"), Widgets.PageChrome.scrolled (new HomePage (ctx))
                        );
                    });
                    break;
                case Application.PageKind.CREATE_PREFIX:
                    page = fresh_create ();
                    break;
                case Application.PageKind.COMPONENTS:
                case Application.PageKind.RUNNERS:
                    page = runtime_page (kind);
                    break;
                case Application.PageKind.STORAGE:
                    page = cached ("storage", () => {
                        return Widgets.PageChrome.page (
                            _("Storage"), Widgets.PageChrome.scrolled (new Widgets.Preferences.StoragePage (ctx))
                        );
                    });
                    break;
                case Application.PageKind.PREFERENCES:
                    page = cached ("preferences", () => {
                        return Widgets.PageChrome.page (
                            _("Preferences"), Widgets.PageChrome.scrolled (new PreferencesPage (ctx))
                        );
                    });
                    break;
                case Application.PageKind.PREFIX:
                    page = prefix_page (prefix_id);
                    break;
                default:
                    page = cached ("empty", () => empty_page ());
                    break;
            }

            prepare_transition ();
            last_kind = kind;
            last_prefix_id = prefix_id;
            page.visible = true;
            stack.visible_child = page;
        }

        private void prepare_transition () {
            if (stack.visible_child == null) {
                stack.transition_type = Gtk.StackTransitionType.NONE;
                return;
            }
            stack.transition_duration = 250;
            stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
        }

        private delegate Gtk.Widget PageFactory ();

        private Gtk.Widget cached (string key, owned PageFactory factory) {
            var existing = pages.get (key);
            if (existing != null) return existing;
            var page = factory ();
            pages.set (key, page);
            stack.add_child (page);
            return page;
        }

        private Gtk.Widget prefix_page (string prefix_id) {
            var entry = ctx.registry.by_id (prefix_id);
            if (entry == null) return cached ("empty", () => empty_page ());
            var key = "prefix:" + prefix_id;
            var existing = pages.get (key);
            if (existing != null) {
                tabs = (PrefixView) existing;
                return existing;
            }
            var prefix = new PrefixView (ctx, entry);
            tabs = prefix;
            pages.set (key, prefix);
            stack.add_child (prefix);
            return prefix;
        }

        private Gtk.Widget fresh_create () {
            if (create_page != null) {
                stack.remove (create_page);
                create_page = null;
            }
            var create = new CreatePrefixView (ctx);
            create.create_requested.connect (on_create);
            create_page = create;
            tabs = create;
            stack.add_child (create);
            return create;
        }

        private Gtk.Widget runtime_page (Application.PageKind kind) {
            var page = cached ("runtime", () => {
                var host = new ManageRunnersPage (ctx);
                runtime_host = host;
                return Widgets.PageChrome.page (_("Runtime"), host);
            });
            if (runtime_host != null) runtime_host.show_kind (kind);
            tabs = runtime_host;
            return page;
        }

        private void on_install_session_finished (Application.InstallSession session, bool success) {
            var key = "prefix:" + session.prefix_id;
            if (!pages.has_key (key)) return;

            var showing = last_kind == Application.PageKind.PREFIX && last_prefix_id == session.prefix_id;
            string? tab = null;
            if (showing && pages.has_key (key) && pages[key] is PrefixView) {
                tab = ((PrefixView) pages[key]).selected_tab ();
            }
            evict_cached (key);
            if (!showing) return;
            show_page (last_kind, last_prefix_id);
            if (tab != null && stack.visible_child is PrefixView) {
                ((PrefixView) stack.visible_child).restore_tab (tab);
            }
        }

        private void evict_cached (string key) {
            Gtk.Widget page;
            if (!pages.unset (key, out page)) return;
            if (key == "runtime") runtime_host = null;
            stack.remove (page);
        }

        private void evict_missing_prefixes () {
            var stale = new Gee.ArrayList<string> ();
            foreach (var key in pages.keys) {
                if (!key.has_prefix ("prefix:")) continue;
                if (ctx.registry.by_id (key.substring (7)) == null) stale.add (key);
            }
            foreach (var key in stale) {
                Gtk.Widget page;
                if (!pages.unset (key, out page)) continue;
                if (stack.visible_child == page) continue;
                page.visible = false;
                if (page is PrefixView) {
                    ((PrefixView) page).stack.enable_transitions = false;
                }
                doomed.add (page);
            }
            start_dismantle ();
            if (!dismantling && ctx.ui != null) ctx.ui.finish_remove_ui ();
        }

        private void start_dismantle () {
            if (dismantling || doomed.size == 0) return;
            dismantling = true;
            Idle.add_full (Priority.DEFAULT_IDLE, dismantle_step);
        }

        private bool dismantle_step () {
            if (doomed.size == 0) {
                dismantling = false;
                if (ctx.ui != null) ctx.ui.finish_remove_ui ();
                return false;
            }
            var victim = doomed[0];
            if (victim is PrefixView) {
                var tabs = ((PrefixView) victim).stack;
                var n = tabs.pages.get_n_items ();
                if (n > 0) {
                    var page = tabs.pages.get_item (n - 1) as Adw.ViewStackPage;
                    if (page != null) tabs.remove (page.child);
                    return true;
                }
            }
            doomed.remove_at (0);
            if (victim.get_parent () == stack) stack.remove (victim);
            if (doomed.size > 0) return true;
            dismantling = false;
            if (ctx.ui != null) ctx.ui.finish_remove_ui ();
            return false;
        }

        private Gtk.Widget empty_page () {
            var empty = new EmptyPage ();
            empty.create_requested.connect (() => {
                ctx.state.show_page (Application.PageKind.CREATE_PREFIX);
            });
            return Widgets.PageChrome.page ("", empty);
        }

        private void on_create (Models.PrefixEntry draft) {
            try {
                var entry = ctx.prefixes.create (draft);
                ctx.state.select_prefix (entry.id);
                ctx.installs.install (entry, true);
            } catch (Error e) {
                ctx.show_toast (user_error (e));
            }
        }
    }
}
