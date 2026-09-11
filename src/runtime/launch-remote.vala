namespace Lumoria.Runtime {

    public void refresh_remote_manifests (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests
    ) throws Error {
        var ctx = make_manifest_context (entry, launcher_manifests);
        visit_context_remote_action_templates (ctx, (tmpl, manifest_url) => {
            var cache_path = new Utils.RemoteManifestCache (manifest_url).cache_path;
            Utils.fetch_remote_manifest_sync (manifest_url, tmpl.manifest_schema, cache_path, ctx.vars);
        });
    }

    public bool prefix_remote_manifests_stale (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests
    ) throws Error {
        bool stale = false;
        var ctx = make_manifest_context (entry, launcher_manifests);
        visit_context_remote_action_templates (ctx, (tmpl, manifest_url) => {
            var cache_path = new Utils.RemoteManifestCache (manifest_url).cache_path;
            if (!Utils.remote_manifest_cache_fresh (cache_path, tmpl.manifest_schema.cache_ttl)) stale = true;
        });
        return stale;
    }

    private delegate void RemoteActionTemplateVisit (
        Models.RemoteManifestAction tmpl,
        string manifest_url
    ) throws Error;

    private void visit_context_remote_action_templates (
        ManifestContext ctx,
        RemoteActionTemplateVisit visit
    ) throws Error {
        visit_remote_action_templates (ctx.installer_manifest, ctx.vars, visit);
        if (ctx.launcher != null) visit_remote_action_templates (ctx.launcher, ctx.vars, visit);
        foreach (var loaded in ctx.post_installs) {
            visit_remote_action_templates (loaded.spec, ctx.vars, visit);
        }
    }

    private void visit_remote_action_templates (
        Models.InstallableManifest spec,
        Gee.HashMap<string, string> vars,
        RemoteActionTemplateVisit visit
    ) throws Error {
        foreach (var tmpl in spec.remote_manifest_actions) {
            var manifest_url = Utils.expand_vars (tmpl.manifest_url, vars);
            if (manifest_url == "" || tmpl.manifest_schema == null) continue;
            visit (tmpl, manifest_url);
        }
    }

    private void expand_remote_manifest_actions (
        Models.InstallableManifest spec,
        Gee.HashSet<string> seen,
        Gee.ArrayList<Models.ManifestAction> actions,
        Gee.HashMap<string, string> vars,
        Gee.ArrayList<string>? warnings,
        bool allow_network,
        string script_instance_id = ""
    ) {
        try {
            visit_remote_action_templates (spec, vars, (tmpl, manifest_url) => {
                var remote = new Utils.RemoteManifestCache (manifest_url);
                Gee.ArrayList<Utils.RemoteManifestFile>? files;
                try {
                    if (allow_network) {
                        files = Utils.fetch_remote_manifest_sync (
                            manifest_url, tmpl.manifest_schema, remote.cache_path, vars
                        );
                    } else {
                        files = Utils.load_cached_remote_manifest (tmpl.manifest_schema, remote.cache_path, vars);
                        if (files == null) return;
                    }
                } catch (Error e) {
                    var msg = "Remote manifest unavailable (%s): %s".printf (manifest_url, e.message);
                    warning (msg);
                    if (warnings != null) warnings.add (msg);
                    return;
                }
                foreach (var file in files) {
                    var action_id = remote_action_id (tmpl, file, vars, script_instance_id);
                    if (action_id == "" || seen.contains (action_id)) continue;
                    var action = remote_manifest_action (tmpl, remote, file, action_id, vars, warnings);
                    if (action == null) continue;
                    actions.add (action);
                    seen.add (action_id);
                }
            });
        } catch (Error e) {
            warning ("Remote manifest expansion failed: %s", e.message);
        }
    }

    private string remote_action_id (
        Models.RemoteManifestAction tmpl,
        Utils.RemoteManifestFile file,
        Gee.HashMap<string, string> vars,
        string script_instance_id
    ) {
        var action_id = Models.expand_manifest_template (tmpl.id_template, file.item_fields, vars);
        if (action_id == "" || script_instance_id == "") return action_id;
        return Models.PrefixAction.compose_id (
            Models.PrefixActionProvider.POST_INSTALL_SCRIPT,
            script_instance_id,
            action_id
        );
    }

    private Models.ManifestAction? remote_manifest_action (
        Models.RemoteManifestAction tmpl,
        Utils.RemoteManifestCache remote,
        Utils.RemoteManifestFile file,
        string action_id,
        Gee.HashMap<string, string> vars,
        Gee.ArrayList<string>? warnings
    ) {
        var dl = new Models.DownloadItem ();
        dl.id = action_id;
        dl.url = file.download_url;
        try {
            dl.dest = remote.download_path (file.filename);
        } catch (Error e) {
            var msg = "Remote manifest file rejected (%s): %s".printf (file.filename, e.message);
            warning (msg);
            if (warnings != null) warnings.add (msg);
            return null;
        }
        dl.sha256 = file.checksum;
        dl.checksum_algorithm = file.checksum_algorithm;

        var step = new Models.InstallStep ();
        step.step_type = Models.InstallStepKind.EXTRACT;
        step.src = dl.dest;
        step.dst = tmpl.dst;

        var action = new Models.ManifestAction ();
        action.id = action_id;
        action.name = Models.expand_manifest_template (tmpl.name_template, file.item_fields, vars);
        action.description = Models.expand_manifest_template (tmpl.description, file.item_fields, vars);
        action.icon = tmpl.icon;
        action.button = tmpl.button;
        action.downloads.add (dl);
        action.steps.add (step);
        action.confirm = tmpl.confirm;
        return action;
    }
}
