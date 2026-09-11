namespace Lumoria.Application {

    public class ActionService : Object {
        public signal void changed ();

        private Context ctx;
        private Gee.HashSet<string> loading_ids = new Gee.HashSet<string> ();
        private Gee.HashMap<string, Gee.ArrayList<Runtime.LaunchTarget>> cached =
            new Gee.HashMap<string, Gee.ArrayList<Runtime.LaunchTarget>> ();
        private Gee.HashMap<string, Gee.HashMap<string, Runtime.LaunchTarget>> indexed =
            new Gee.HashMap<string, Gee.HashMap<string, Runtime.LaunchTarget>> ();
        private Gee.HashSet<string> reported_script_errors = new Gee.HashSet<string> ();

        public ActionService (Context ctx) {
            this.ctx = ctx;
        }

        public bool is_loading (string prefix_id) {
            return loading_ids.contains (prefix_id);
        }

        public bool has_cached (string prefix_id) {
            return !loading_ids.contains (prefix_id) && cached.has_key (prefix_id);
        }

        public void invalidate (string prefix_id = "") {
            if (prefix_id == "") {
                cached.clear ();
                indexed.clear ();
                return;
            }
            cached.unset (prefix_id);
            indexed.unset (prefix_id);
        }

        public void invalidate_and_prune (Models.PrefixEntry entry) {
            invalidate (entry.id);
            prune_favorites (entry);
        }

        public void refresh_remotes (Models.PrefixEntry entry) {
            bool stale = true;
            try {
                stale = Runtime.prefix_remote_manifests_stale (entry, ctx.launcher_manifests);
            } catch (Error e) {
                warning ("Remote manifest check failed for %s: %s", entry.id, e.message);
            }

            invalidate (entry.id);
            if (!stale) {
                changed ();
                return;
            }
            if (!loading_ids.add (entry.id)) {
                changed ();
                return;
            }
            changed ();

            var prefix_id = entry.id;
            Utils.run_background ("remote-manifests", () => {
                Runtime.refresh_remote_manifests (entry, ctx.launcher_manifests);
            }, (error) => {
                if (error != null) {
                    warning ("Remote manifest refresh failed for %s: %s", prefix_id, error.message);
                }
                invalidate (prefix_id);
                loading_ids.remove (prefix_id);
                changed ();
            });
        }

        public Gee.ArrayList<Runtime.LaunchTarget> list (Models.PrefixEntry entry) throws Error {
            if (!loading_ids.contains (entry.id)) {
                var existing = cached.get (entry.id);
                if (existing != null) {
                    if (!indexed.has_key (entry.id)) index_actions (entry.id, existing);
                    return existing;
                }
            }

            var actions = Runtime.list_launch_targets (entry, ctx.launcher_manifests, null, null, false);
            if (!loading_ids.contains (entry.id)) {
                cached[entry.id] = actions;
                index_actions (entry.id, actions);
            }
            report_post_install_load_errors (entry);
            return actions;
        }

        public Runtime.LaunchTarget? default_launch (Models.PrefixEntry entry) throws Error {
            if (entry.launch_entrypoint_id != "") {
                var stored = find (entry, entry.launch_entrypoint_id);
                if (stored != null && stored.pinnable) return stored;
            }
            var id = Runtime.resolve_default_entrypoint_id (entry, ctx.launcher_manifests);
            var existing = peek_cached (entry);
            if (existing != null && id != "") {
                var found = action_by_id (existing, id);
                if (found != null) return found;
            }
            return Runtime.local_default_launch (entry, ctx.launcher_manifests);
        }

        public Runtime.LaunchTarget? find (Models.PrefixEntry entry, string action_id) throws Error {
            var actions = list (entry);
            var map = indexed.get (entry.id);
            if (map != null) return map.get (action_id);
            return action_by_id (actions, action_id);
        }

        private Gee.ArrayList<Runtime.LaunchTarget>? peek_cached (Models.PrefixEntry entry) {
            if (loading_ids.contains (entry.id)) return null;
            var existing = cached.get (entry.id);
            if (existing == null) return null;
            if (!indexed.has_key (entry.id)) index_actions (entry.id, existing);
            return existing;
        }

        public delegate bool TargetMatch (Runtime.LaunchTarget target);

        public Gee.ArrayList<Runtime.LaunchTarget> list_matching (
            Models.PrefixEntry entry,
            TargetMatch match
        ) throws Error {
            var matches = new Gee.ArrayList<Runtime.LaunchTarget> ();
            foreach (var target in list (entry)) {
                if (match (target)) matches.add (target);
            }
            return matches;
        }

        public void save_custom_entry (Models.PrefixEntry entry, Models.Entrypoint ep, bool created) {
            if (created) entry.custom_entrypoints.add (ep);
            invalidate (entry.id);
            ctx.prefixes.schedule_save ();
            changed ();
        }

        public void remove_custom_entry (Models.PrefixEntry entry, Models.Entrypoint existing) throws Error {
            ctx.shortcuts.remove_entry_shortcuts (entry, existing.id);
            entry.custom_entrypoints.remove (existing);
            invalidate_and_prune (entry);
            ctx.prefixes.save ();
            changed ();
        }

        public void prune_favorites (Models.PrefixEntry entry) {
            Gee.ArrayList<Runtime.LaunchTarget> actions;
            try {
                actions = list (entry);
            } catch (Error e) {
                warning ("Failed to list launch actions for %s: %s", entry.id, e.message);
                return;
            }
            ctx.state.prune_invalid_favorites (entry.id, (action_id) => {
                return action_by_id (actions, action_id) != null;
            });
        }

        private void index_actions (string prefix_id, Gee.ArrayList<Runtime.LaunchTarget> actions) {
            var map = new Gee.HashMap<string, Runtime.LaunchTarget> ();
            foreach (var action in actions) map[action.id] = action;
            indexed[prefix_id] = map;
        }

        public void run_default (Models.PrefixEntry entry) {
            Runtime.LaunchTarget? found = null;
            try {
                found = default_launch (entry);
            } catch (Error e) {
                ctx.show_toast (user_error (e));
                return;
            }
            if (found == null) {
                ctx.show_toast (_("No default launch entry is available."));
                return;
            }
            run (entry, found.id);
        }

        public void run_quick_launch () {
            var target = ctx.state.quick_launch;
            if (target.is_empty ()) {
                ctx.show_toast (_("No Quick Launch target is set."));
                return;
            }
            var entry = ctx.registry.by_id (target.prefix_id);
            if (entry == null) {
                ctx.state.clear_quick_launch ();
                ctx.show_toast (_("Quick Launch target is no longer available."));
                return;
            }
            run_default (entry);
        }

        public void run (Models.PrefixEntry entry, string action_id) {
            Runtime.LaunchTarget? found = null;
            try {
                found = find (entry, action_id);
            } catch (Error e) {
                ctx.show_toast (user_error (e));
                return;
            }
            if (found == null) {
                ctx.show_toast (_("Action not found."));
                return;
            }
            if (found.kind != Models.PrefixActionKind.MAINTENANCE
                && !ctx.ensure_prefix_access (entry)) {
                return;
            }

            switch (found.kind) {
                case Models.PrefixActionKind.LAUNCH:
                    ctx.launches.launch_prefix (entry, found.id);
                    break;
                case Models.PrefixActionKind.OPEN_LOCATION:
                    open_location (entry, found);
                    break;
                default:
                    if (confirm_action (entry, found)) {
                        ctx.installs.run_action (entry, found.id, found.spec);
                    }
                    break;
            }
        }

        private static Runtime.LaunchTarget? action_by_id (
            Gee.List<Runtime.LaunchTarget> actions,
            string action_id
        ) {
            foreach (var action in actions) {
                if (action.id == action_id) return action;
            }
            return null;
        }

        private void open_location (Models.PrefixEntry entry, Runtime.LaunchTarget found) {
            if (ctx.ui == null) return;
            var path = found.location != "" ? found.location : entry.resolved_path ();
            ctx.ui.open_directory (path, (message) => {
                ctx.show_toast (_("Could not open folder: %s").printf (message));
            });
        }

        private bool confirm_action (Models.PrefixEntry entry, Runtime.LaunchTarget found) {
            if (ctx.ui == null) return true;

            var spec = found.spec;
            if (spec == null || !spec.confirm.requested) return true;

            var vars = Runtime.message_vars_for_prefix (entry, ctx.launcher_manifests);
            var confirm = spec.confirm.expand (vars);
            var title = confirm.title != "" ? confirm.title : spec.display_label ();
            var body = confirm.body != "" ? confirm.body : Utils.expand_vars (spec.description, vars);
            var confirm_label = confirm.confirm_label != ""
                ? confirm.confirm_label
                : (spec.display_label () != "" ? spec.display_label () : _("Continue"));
            var cancel_label = confirm.cancel_label != "" ? confirm.cancel_label : _("Cancel");
            ctx.ui.confirm (
                title,
                body,
                confirm_label,
                confirm.destructive,
                () => ctx.installs.run_action (entry, found.id, found.spec),
                cancel_label
            );
            return false;
        }

        private void report_post_install_load_errors (Models.PrefixEntry entry) {
            foreach (var err in Runtime.collect_post_install_load_errors (entry)) {
                var key = "%s:%s:%s".printf (entry.id, err.name, err.reason);
                if (!reported_script_errors.add (key)) continue;
                var line = _("Failed to load script %s: %s").printf (err.name, err.reason);
                if (ctx.ui != null) ctx.show_toast (line);
                else stderr.printf ("%s\n", line);
            }
        }
    }
}
