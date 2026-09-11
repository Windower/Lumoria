namespace Lumoria.Application {

    public class PrefixService : Object {
        public signal void changed ();
        public signal void list_changed ();
        public signal void persist_failed (string message);

        private Context ctx;
        private Models.PrefixRegistry registry;
        private AppState state;
        private Utils.Debouncer scheduled_save;

        public PrefixService (Context ctx) {
            this.ctx = ctx;
            this.registry = ctx.registry;
            this.state = ctx.state;
            scheduled_save = new Utils.Debouncer (0, write_scheduled);
        }

        public Models.PrefixEntry create (Models.PrefixEntry entry) throws Error {
            if (Utils.EnvironmentInfo.is_gamescope ()) {
                throw new LumoriaError.BUSY (_("Prefix installation is disabled in a gamescope session."));
            }

            reject_prefixes_root (entry.path);
            if (registry.by_path (entry.path) != null) {
                throw new LumoriaError.FAILED (_("This path is already in your prefix list."));
            }

            if (Runtime.prefix_root_has_drive_c (entry.path)) {
                throw new LumoriaError.FAILED (_("A Wine prefix already exists at %s.").printf (entry.path));
            }

            entry.name = entry.name.strip ();
            if (entry.name == "") entry.name = Path.get_basename (entry.path);
            var slug = Utils.slugify (entry.name);
            entry.id = unique_id (slug != "" ? slug : Utils.slugify (entry.path));
            entry.path_portal = Utils.portal_path_ref_from_path_uri (entry.path, entry.uri);
            if (entry.installer_id == Models.InstallerManifest.EMPTY_ID) {
                entry.region = "";
                entry.launcher_id = "";
            }
            Utils.ensure_indexer_ignore (Utils.default_prefix_dir ());
            Utils.ensure_indexer_ignore (Path.get_dirname (entry.path));
            Utils.ensure_indexer_ignore (entry.path);
            foreach (var spec in entry.post_install_manifests) {
                spec.ensure_id ();
                var source = spec.locate_file ("") ?? spec.original_path;
                if (source == "") continue;
                Runtime.store_post_install_manifest (entry.resolved_path (), source, spec.id);
            }
            registry.add_prefix (entry);
            save ();
            if (state.quick_launch.is_empty ()) {
                state.update_quick_launch (entry.id);
            }
            list_changed ();
            Utils.StorageCache.instance ().refresh_prefix (entry);
            return entry;
        }

        public void move_to (string id, int dest) throws Error {
            if (!Utils.move_item<Models.PrefixEntry> (registry.prefixes, index_of (id), dest)) return;
            save ();
        }

        private int index_of (string id) {
            for (int i = 0; i < registry.prefixes.size; i++) {
                if (registry.prefixes[i].id == id) return i;
            }
            return -1;
        }

        public delegate void RemoveDone (Error? error);

        public void remove (Models.PrefixEntry entry, bool delete_files, owned RemoveDone? on_done = null) {
            if (!ctx.try_begin (ExclusiveKind.REMOVE)) {
                finish_remove ((owned) on_done, new LumoriaError.BUSY (ctx.exclusive_busy_message ()));
                return;
            }
            var idx = index_of (entry.id);
            if (idx < 0) {
                ctx.end_session (ExclusiveKind.REMOVE);
                finish_remove ((owned) on_done, null);
                return;
            }

            var removed = registry.prefixes[idx];
            var saved_default = registry.default_prefix_id;
            var path = delete_files ? entry.resolved_path () : "";
            var next_id = "";
            if (registry.prefixes.size > 1) {
                var next_idx = idx + 1 < registry.prefixes.size ? idx + 1 : idx - 1;
                next_id = registry.prefixes[next_idx].id;
            }
            registry.remove_at (idx);
            try {
                save (false);
            } catch (Error e) {
                registry.prefixes.insert (idx, removed);
                registry.default_prefix_id = saved_default;
                ctx.end_session (ExclusiveKind.REMOVE);
                finish_remove ((owned) on_done, e);
                return;
            }
            ctx.shortcuts.remove_prefix_shortcuts (removed);
            state.forget_prefix (entry.id, next_id);
            if (state.quick_launch.is_empty ()) ctx.shortcuts.remove_quick_launch_shortcuts ();
            Utils.StorageCache.instance ().drop_prefix (entry.id);
            list_changed ();
            if (path == "") {
                ctx.end_session (ExclusiveKind.REMOVE);
                finish_remove ((owned) on_done, null);
                return;
            }
            var done = (owned) on_done;
            var runners = ctx.runner_manifests;
            Utils.run_background ("remove-prefix-files", () => {
                Runtime.try_stop_prefix_wineserver (entry, runners);
                Utils.ensure_indexer_ignore (Path.get_dirname (path));
                Utils.ensure_indexer_ignore (path);
                if (!Utils.remove_recursive (path)) {
                    throw new LumoriaError.FAILED (
                        _("Could not delete prefix files at %s").printf (path)
                    );
                }
            }, (error) => {
                ctx.end_session (ExclusiveKind.REMOVE);
                if (done != null) done (error);
            });
        }

        private void finish_remove (owned RemoveDone? on_done, Error? error) {
            if (on_done == null) return;
            Idle.add (() => {
                on_done (error);
                return false;
            });
        }

        public void save (bool notify = true) throws Error {
            scheduled_save.cancel ();
            registry.save (Utils.prefix_registry_path ());
            if (!notify) return;
            Idle.add (() => {
                changed ();
                return false;
            });
        }

        public bool save_or_toast () {
            try {
                save ();
                return true;
            } catch (Error e) {
                ctx.show_toast (user_error (e));
                return false;
            }
        }

        public void schedule_save () {
            scheduled_save.schedule ();
        }

        public void flush_persist () {
            scheduled_save.flush ();
        }

        private void write_scheduled () {
            try {
                registry.save (Utils.prefix_registry_path ());
                changed ();
            } catch (Error e) {
                warning ("Failed to persist prefix registry: %s", e.message);
                persist_failed (user_error (e));
            }
        }

        public void require_access (Models.PrefixEntry entry) throws Error {
            if (!entry.needs_grant ()) return;
            throw new LumoriaError.PERMISSION (_("Permission required to access this prefix."));
        }

        public bool request_access (Models.PrefixEntry entry) throws Error {
            if (!entry.needs_grant ()) return true;
            if (ctx.ui == null) require_access (entry);
            else ctx.ui.grant_prefix_access (entry, apply_granted_folder, (msg) => ctx.show_toast (msg));
            return false;
        }

        public void apply_granted_folder (Models.PrefixEntry entry, File file, string path) {
            entry.path = path;
            entry.uri = file.get_uri ();
            entry.path_portal = Utils.portal_path_ref_from_path_uri (entry.path, entry.uri);
            save_or_toast ();
        }

        public static void reject_prefixes_root (string path) throws Error {
            if (!Utils.is_prefixes_root_path (path)) return;
            throw new LumoriaError.FAILED (
                _("You cannot install directly into the prefixes root. Choose a subdirectory inside %s.").printf (
                    Utils.default_prefix_dir ()
                )
            );
        }

        public static string expected_folder_name (Models.PrefixEntry entry) {
            if (entry.path_portal != null && entry.path_portal.document_path != "") {
                return Path.get_basename (Utils.normalize_dir_path (entry.path_portal.document_path));
            }
            var resolved = entry.resolved_path ();
            if (resolved != "") return Path.get_basename (Utils.normalize_dir_path (resolved));
            return entry.display_name ();
        }

        private string unique_id (string requested) {
            var id = requested != "" ? requested : "prefix";
            if (registry.by_id (id) == null) return id;
            for (int i = 2; i < 1000; i++) {
                var candidate = "%s-%d".printf (id, i);
                if (registry.by_id (candidate) == null) return candidate;
            }
            return "%s-%08x".printf (id, (uint32) Random.next_int ());
        }
    }
}
