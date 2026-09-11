namespace Lumoria.Widgets {

    public class ScriptOverview : Object {
        public static void append (
            Gtk.Box parent,
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Models.PrefixPostInstallManifest spec,
            Gtk.Widget? extra_suffix = null,
            bool show_status = false
        ) {
            var manifest = load (entry, spec);
            var title = spec.name != "" ? spec.name : spec.manifest_id;
            var vars = Runtime.message_vars_for_prefix (entry, ctx.launcher_manifests);
            if (manifest != null) {
                parent.append (ManifestUi.intro (manifest, vars, extra_suffix));
            } else {
                parent.append (PageChrome.heading_row (title, "", extra_suffix, null, false));
            }
            if (show_status) {
                var status = spec.last_run_status != "" ? spec.last_run_status : _("never run");
                var caption = spec.last_run_at != ""
                    ? _("%s · %s").printf (status, spec.last_run_at)
                    : status;
                var status_label = new Gtk.Label (caption);
                status_label.add_css_class ("dim-label");
                status_label.add_css_class ("caption");
                status_label.xalign = 0f;
                status_label.margin_start = Ui.Metrics.PAGE_MARGIN;
                status_label.margin_end = Ui.Metrics.PAGE_MARGIN;
                status_label.margin_bottom = Ui.Metrics.HEADING_GAP;
                parent.append (status_label);
            }

            var group = PageChrome.untitled_group ();
            var have_actions = false;
            try {
                foreach (var action in ctx.actions.list_matching (entry, (target) => {
                    return target.provider_type == Models.PrefixActionProvider.POST_INSTALL_SCRIPT
                        && target.provider_id == spec.id;
                })) {
                    group.add (ActionRows.prefix_action_row (ctx, entry, action));
                    have_actions = true;
                }
            } catch (Error e) {
                group.add (PageChrome.error_row (_("Could not load actions"), e));
                have_actions = true;
            }
            if (have_actions) parent.append (group);
        }

        public static Models.PostInstallManifest? load (
            Models.PrefixEntry? entry,
            Models.PrefixPostInstallManifest spec
        ) {
            var path = spec.locate_file (entry != null ? entry.resolved_path () : "");
            if (path == null) return null;
            try {
                return Models.PostInstallManifest.load_from_file (path);
            } catch (Error e) {
                warning ("Failed to load post-install manifest %s: %s", path, e.message);
                return null;
            }
        }
    }
}
