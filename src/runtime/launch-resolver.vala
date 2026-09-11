namespace Lumoria.Runtime {

    public LaunchPlan resolve_launch_plan (
        ManifestContext ctx,
        string entrypoint_id,
        string custom_exe = "",
        string[]? custom_args = null
    ) throws Error {
        var plan = new LaunchPlan ();
        plan.entrypoint_id = entrypoint_id != "" ? entrypoint_id : resolve_effective_entrypoint_id (ctx);
        if (custom_exe != "") {
            plan.executable = resolve_host_path (custom_exe, ctx.pfx_path);
            plan.args = custom_args != null ? custom_args : new string[0];
            return plan;
        }

        string resolved_exe;
        string[] resolved_args;
        resolve_launcher_exe (ctx, plan.entrypoint_id, out resolved_exe, out resolved_args);
        plan.executable = resolved_exe;
        plan.args = resolved_args;
        plan.entrypoint = find_launch_entrypoint (ctx, plan.entrypoint_id);
        return plan;
    }

    public string effective_wine_arch (Models.PrefixEntry entry) throws Error {
        var spec = Models.RunnerManifest.resolve_for_entry (Models.ManifestRepository.shared ().host_runners, entry);
        return spec.effective_variant (entry.variant_id).effective_arch (entry.wine_arch);
    }

    /* Everything a launch needs from the manifests, loaded once and handed to each resolver. */
    public class ManifestContext : Object {
        public Models.PrefixEntry entry;
        public string pfx_path = "";
        public Models.InstallerManifest installer_manifest;
        public Models.LauncherManifest? launcher;
        public Gee.ArrayList<Models.LoadedPostInstall> post_installs;
        public string arch = "";
        public Gee.HashMap<string, string> vars;
    }

    public ManifestContext make_manifest_context (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest>? launcher_manifests
    ) throws Error {
        var ctx = new ManifestContext ();
        ctx.entry = entry;
        ctx.pfx_path = PrefixPaths.from_entry (entry).wine_prefix;
        var repository = Models.ManifestRepository.shared ();
        ctx.installer_manifest = repository.require_installer (entry.installer_id);
        var specs = launcher_manifests ?? repository.launchers;
        ctx.launcher = Models.find_by_id<Models.LauncherManifest> (specs, entry.launcher_id);
        ctx.post_installs = load_prefix_post_installs (entry);
        ctx.arch = effective_wine_arch (entry);
        ctx.vars = build_launch_vars (ctx.pfx_path, entry, ctx.installer_manifest, ctx.arch, ctx.launcher, ctx.post_installs);
        return ctx;
    }

    private void resolve_launcher_exe (
        ManifestContext ctx,
        string entrypoint_id,
        out string exe,
        out string[] args
    ) throws Error {
        exe = "";
        args = {};
        var entry = ctx.entry;

        if (entrypoint_id != "") {
            var custom_ep = entry.custom_entrypoint (entrypoint_id);
            if (custom_ep != null) {
                apply_custom_entrypoint (custom_ep, out exe, out args);
                return;
            }

            var profile_name = launcher_profile_name_from_entry_id (entrypoint_id);
            if (profile_name != null
                && ctx.launcher != null
                && ctx.launcher.supports_feature (FEATURE_PROFILES)) {
                var wep = find_entrypoint (ctx.launcher.entrypoints, "");
                if (wep != null) {
                    apply_entrypoint (wep, ctx.vars, out exe, out args);
                    var wl = new Gee.ArrayList<string> ();
                    foreach (var a in args) wl.add (a);
                    wl.add ("-p");
                    wl.add (profile_name.strip () == "" ? "Default" : profile_name);
                    args = Utils.strv (wl);
                    return;
                }
            }

            var ep = find_launch_entrypoint (ctx, entrypoint_id);
            if (ep != null) {
                apply_entrypoint (ep, ctx.vars, out exe, out args);
                return;
            }

            throw new LumoriaError.NOT_FOUND (_("Launch target not found: %s").printf (entrypoint_id));
        }

        if (ctx.launcher != null) {
            var launcher_entrypoint = find_entrypoint (ctx.launcher.entrypoints, "");
            if (launcher_entrypoint == null) {
                throw new LumoriaError.INVALID_MANIFEST (
                    _("Launcher '%s' has no default entrypoint").printf (ctx.launcher.id)
                );
            }
            apply_entrypoint (launcher_entrypoint, ctx.vars, out exe, out args);
            return;
        }

        var installer_entrypoint = find_entrypoint (
            ctx.installer_manifest.entrypoints, ""
        );
        if (installer_entrypoint != null) {
            apply_entrypoint (installer_entrypoint, ctx.vars, out exe, out args);
            return;
        }

        if (entry.custom_entrypoints.size > 0) {
            apply_custom_entrypoint (entry.custom_entrypoints[0], out exe, out args);
            return;
        }

        throw new LumoriaError.NOT_FOUND (
            _("No default launch target is available. Configure an entrypoint or choose an executable.")
        );
    }

    private void apply_custom_entrypoint (Models.Entrypoint custom, out string exe, out string[] args) {
        exe = Utils.resolve_user_path (custom.exe, custom.exe_portal);
        args = Utils.strv (custom.args);
    }

    public void apply_launch_env (
        ManifestContext ctx,
        string entrypoint_id,
        WineEnv env,
        WinePaths? paths = null,
        RuntimeLog? logger = null
    ) {
        finalize_manifest_vars (ctx.vars, paths, env, logger);

        apply_env_rules (env, ctx.installer_manifest.env, ctx.vars);
        if (ctx.launcher != null) apply_env_rules (env, ctx.launcher.env, ctx.vars);
        foreach (var loaded in ctx.post_installs) {
            apply_env_rules (env, loaded.spec.env, ctx.vars);
        }

        var ep = find_launch_entrypoint (ctx, entrypoint_id);
        if (ep != null) apply_env_rules (env, ep.env, ctx.vars);
    }

    public string finalize_launch_text (
        string? text,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger
    ) {
        if (text == null || !text.contains ("${winepath:")) return text ?? "";
        var vars = new Gee.HashMap<string, string> ();
        vars["__launch"] = text;
        finalize_manifest_vars (vars, paths, env, logger);
        return vars["__launch"];
    }

    private Models.Entrypoint? find_launch_entrypoint (ManifestContext ctx, string entrypoint_id) {
        if (entrypoint_id == "") return null;
        var custom = ctx.entry.custom_entrypoint (entrypoint_id);
        if (custom != null) return custom;
        var ep = find_active_entrypoint (ctx.installer_manifest.entrypoints, entrypoint_id, ctx.vars);
        if (ep == null && ctx.launcher != null) {
            ep = find_active_entrypoint (ctx.launcher.entrypoints, entrypoint_id, ctx.vars);
        }
        if (ep != null) return ep;

        string script_instance;
        string script_local;
        var scoped = Models.PrefixAction.parse_script_id (entrypoint_id, out script_instance, out script_local);
        foreach (var loaded in ctx.post_installs) {
            if (scoped && loaded.metadata.id != script_instance) continue;
            ep = find_active_entrypoint (loaded.spec.entrypoints, scoped ? script_local : entrypoint_id, ctx.vars);
            if (ep != null) return ep;
        }
        return null;
    }

    /* The entrypoint with id whose when clause holds for vars. */
    private Models.Entrypoint? find_active_entrypoint (
        Gee.ArrayList<Models.Entrypoint> eps,
        string id,
        Gee.HashMap<string, string> vars
    ) {
        foreach (var ep in eps) {
            if (ep.id == id && (ep.when == null || ep.when.evaluate (vars))) return ep;
        }
        return null;
    }

    internal Gee.ArrayList<Models.Entrypoint> entrypoints_from_context (
        ManifestContext ctx,
        Gee.ArrayList<Models.Entrypoint> custom_list
    ) {
        var all = new Gee.ArrayList<Models.Entrypoint> ();
        expand_entrypoints (all, ctx.installer_manifest.entrypoints, ctx.vars);
        if (ctx.launcher != null) expand_entrypoints (all, ctx.launcher.entrypoints, ctx.vars);
        foreach (var loaded in ctx.post_installs) {
            expand_entrypoints (all, loaded.spec.entrypoints, ctx.vars, loaded.metadata.id);
        }
        all.add_all (custom_list);
        return all;
    }

    public string launcher_dir (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests
    ) {
        try {
            return launcher_dir_from_context (make_manifest_context (entry, launcher_manifests));
        } catch (Error e) {
            warning ("Failed to resolve launcher directory for %s: %s", entry.id, e.message);
            return "";
        }
    }

    public string launcher_dir_from_context (ManifestContext ctx) {
        if (ctx.launcher == null) return "";
        var ep = find_entrypoint (ctx.launcher.entrypoints, "");
        if (ep == null || ep.exe == "") return "";
        string exe;
        string[] args;
        apply_entrypoint (ep, ctx.vars, out exe, out args);
        if (exe.strip () == "") return "";
        return Path.get_dirname (resolve_host_path (exe, ctx.pfx_path));
    }

    internal Models.Entrypoint? find_local_entrypoint (
        string id,
        Models.LauncherManifest? launcher,
        Models.InstallerManifest? installer,
        Gee.ArrayList<Models.Entrypoint> custom,
        Models.PrefixEntry? entry = null
    ) {
        if (id == "") return null;
        var ep = launcher != null ? Models.find_by_id<Models.Entrypoint> (launcher.entrypoints, id) : null;
        ep = ep ?? (installer != null ? Models.find_by_id<Models.Entrypoint> (installer.entrypoints, id) : null);
        ep = ep ?? Models.find_by_id<Models.Entrypoint> (custom, id);
        if (ep != null || entry == null) return ep;
        string script_instance;
        string script_local;
        var script = Models.PrefixAction.parse_script_id (id, out script_instance, out script_local);
        foreach (var loaded in load_prefix_post_installs (entry)) {
            if (script && loaded.metadata.id != script_instance) continue;
            ep = Models.find_by_id<Models.Entrypoint> (loaded.spec.entrypoints, script ? script_local : id);
            if (ep != null) return ep;
        }
        return null;
    }

    internal LaunchTarget launch_target_from_entrypoint (
        Models.Entrypoint ep,
        Models.LauncherManifest? launcher
    ) {
        var target = new LaunchTarget ();
        target.id = ep.id;
        target.label = ep.display_label ();
        target.selector_label = target.label;
        if (ep.icon != "") target.icon = ep.icon;
        if (Models.PrefixEntry.is_custom_entry_id (ep.id)) {
            target.section = LaunchTargetSection.CUSTOM;
        } else if (is_launcher_target_id (launcher, ep.id)) {
            target.section = LaunchTargetSection.LAUNCHER;
            if (target.icon == "" && launcher != null && launcher.icon != "") target.icon = launcher.icon;
        } else {
            target.section = LaunchTargetSection.LAUNCH;
        }
        return target;
    }

    internal LaunchTarget launch_target_from_profile (
        string id,
        string profile_name,
        Models.LauncherManifest launcher
    ) {
        var target = new LaunchTarget ();
        target.id = id;
        target.label = launcher_profile_display_label (profile_name);
        target.selector_label = _("Profile (%s)").printf (target.label);
        target.section = LaunchTargetSection.LAUNCHER_PROFILES;
        if (launcher.icon != "") target.icon = launcher.icon;
        return target;
    }

    internal bool is_launcher_target_id (Models.LauncherManifest? launcher, string id) {
        if (launcher == null || id == "") return false;
        foreach (var ep in launcher.entrypoints) {
            if (ep.id == id) return true;
        }
        foreach (var action in launcher.actions) {
            if (action.id == id) return true;
        }
        return false;
    }

    internal string post_install_group_title (Models.PrefixEntry entry, string instance_id) {
        foreach (var spec in entry.post_install_manifests) {
            if (spec.id != instance_id) continue;
            return spec.name != "" ? spec.name : spec.manifest_id;
        }
        return _("Scripts");
    }

    internal Gee.ArrayList<Models.ManifestAction> actions_from_context (
        ManifestContext ctx,
        Gee.ArrayList<string>? warnings,
        bool allow_network
    ) {
        var actions = new Gee.ArrayList<Models.ManifestAction> ();
        var seen = new Gee.HashSet<string> ();

        append_unique_actions (actions, seen, ctx.installer_manifest.actions);
        if (ctx.launcher != null) {
            append_unique_actions (actions, seen, ctx.launcher.actions);
        }
        foreach (var loaded in ctx.post_installs) {
            append_script_actions (actions, seen, loaded);
        }

        expand_remote_manifest_actions (
            ctx.installer_manifest, seen, actions, ctx.vars, warnings, allow_network
        );
        if (ctx.launcher != null) {
            expand_remote_manifest_actions (ctx.launcher, seen, actions, ctx.vars, warnings, allow_network);
        }
        foreach (var loaded in ctx.post_installs) {
            expand_remote_manifest_actions (
                loaded.spec, seen, actions, ctx.vars, warnings, allow_network, loaded.metadata.id
            );
        }

        return actions;
    }

    internal Models.ManifestAction? find_manifest_action_in_context (
        ManifestContext ctx,
        string action_id
    ) {
        foreach (var action in actions_from_context (ctx, null, true)) {
            if (action.id == action_id) return action;
        }
        return null;
    }

    private void append_script_actions (
        Gee.ArrayList<Models.ManifestAction> target,
        Gee.HashSet<string> seen,
        Models.LoadedPostInstall loaded
    ) {
        foreach (var action in loaded.spec.actions) {
            if (action.id == "") continue;
            var remapped = action.copy (
                Models.PrefixAction.compose_id (
                    Models.PrefixActionProvider.POST_INSTALL_SCRIPT,
                    loaded.metadata.id,
                    action.id
                )
            );
            if (seen.contains (remapped.id)) continue;
            target.add (remapped);
            seen.add (remapped.id);
        }
    }

    private void append_unique_actions (
        Gee.ArrayList<Models.ManifestAction> target,
        Gee.HashSet<string> seen,
        Gee.ArrayList<Models.ManifestAction> source
    ) {
        foreach (var action in source) {
            if (action.id == "" || seen.contains (action.id)) continue;
            target.add (action);
            seen.add (action.id);
        }
    }

    public string resolve_default_entrypoint_id (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests
    ) {
        try {
            return resolve_effective_entrypoint_id (make_manifest_context (entry, launcher_manifests));
        } catch (Error e) {
            warning ("Failed to resolve default entrypoint for %s: %s", entry.id, e.message);
            return fallback_entrypoint_id (entry, launcher_manifests);
        }
    }

    private string resolve_effective_entrypoint_id (ManifestContext ctx) {
        var entry = ctx.entry;
        if (entry.launch_entrypoint_id != "") {
            if (launcher_profile_name_from_entry_id (entry.launch_entrypoint_id) != null
                && ctx.launcher != null
                && ctx.launcher.supports_feature (FEATURE_PROFILES)) {
                return entry.launch_entrypoint_id;
            }
            if (find_launch_entrypoint (ctx, entry.launch_entrypoint_id) != null) {
                return entry.launch_entrypoint_id;
            }
        }
        return fallback_entrypoint_id (entry, null, ctx);
    }

    private string fallback_entrypoint_id (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest>? launcher_manifests,
        ManifestContext? ctx = null
    ) {
        var launcher = ctx != null
            ? ctx.launcher
            : Models.find_by_id<Models.LauncherManifest> (launcher_manifests, entry.launcher_id);
        if (launcher != null) {
            var launcher_ep = find_entrypoint (launcher.entrypoints, "");
            if (launcher_ep != null) return launcher_ep.id;
        }
        var installer = ctx != null
            ? ctx.installer_manifest
            : Models.ManifestRepository.shared ().installer (entry.installer_id);
        if (installer != null) {
            var ep = find_entrypoint (installer.entrypoints, "");
            if (ep != null) return ep.id;
        }
        if (entry.custom_entrypoints.size > 0) {
            return entry.custom_entrypoints[0].id;
        }
        return "";
    }

    public Gee.HashMap<string, string> message_vars_for_prefix (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest>? launcher_manifests = null
    ) {
        try {
            return make_manifest_context (entry, launcher_manifests).vars;
        } catch (Error e) {
            warning ("Failed to build message variables for %s: %s", entry.id, e.message);
            return new Gee.HashMap<string, string> ();
        }
    }

    public Gee.HashMap<string, string> message_vars_for_draft (
        Models.InstallerManifest? installer,
        Models.LauncherManifest? launcher,
        string region = ""
    ) {
        var vars = new Gee.HashMap<string, string> ();
        set_arch_vars (vars, "win64");
        if (installer != null) {
            merge_vars (vars, installer.variables);
            apply_variable_rules (vars, installer.variable_rules);
        }
        if (launcher != null) {
            merge_vars (vars, launcher.variables);
            apply_variable_rules (vars, launcher.variable_rules);
        }
        var draft = new Models.PrefixEntry ();
        draft.region = region;
        draft.launcher_id = launcher != null ? launcher.id : "";
        draft.installer_id = installer != null ? installer.id : "";
        resolve_prefix_vars (vars, draft);
        finalize_manifest_vars (vars);
        return vars;
    }

    public Gee.HashMap<string, string> build_launch_vars (
        string pfx_path,
        Models.PrefixEntry entry,
        Models.InstallerManifest installer_manifest,
        string arch,
        Models.LauncherManifest? launcher = null,
        Gee.ArrayList<Models.LoadedPostInstall>? post_installs = null
    ) {
        var vars = new Gee.HashMap<string, string> ();
        seed_manifest_vars (vars, pfx_path, installer_manifest);
        set_arch_vars (vars, arch);
        apply_variable_rules (vars, installer_manifest.variable_rules);
        if (launcher != null) {
            merge_vars (vars, launcher.variables);
            apply_variable_rules (vars, launcher.variable_rules);
        }
        if (post_installs != null) {
            foreach (var loaded in post_installs) merge_vars (vars, loaded.spec.variables);
        }
        resolve_prefix_vars (vars, entry);
        finalize_manifest_vars (vars);
        return vars;
    }

    private void apply_entrypoint (
        Models.Entrypoint ep,
        Gee.HashMap<string, string> vars,
        out string exe,
        out string[] args
    ) {
        exe = Utils.expand_vars (ep.exe, vars);
        var arg_list = new string[ep.args.size];
        for (int i = 0; i < ep.args.size; i++) {
            arg_list[i] = Utils.expand_vars (ep.args[i], vars);
        }
        args = arg_list;
    }

    private void expand_entrypoints (
        Gee.ArrayList<Models.Entrypoint> target,
        Gee.ArrayList<Models.Entrypoint> source,
        Gee.HashMap<string, string> vars,
        string script_instance_id = ""
    ) {
        foreach (var ep in source) {
            if (ep.when != null && !ep.when.evaluate (vars)) continue;
            var copy = ep.copy ();
            if (script_instance_id != "") {
                copy.id = Models.PrefixAction.compose_id (
                    Models.PrefixActionProvider.POST_INSTALL_SCRIPT,
                    script_instance_id,
                    ep.id
                );
            }
            copy.exe = Utils.expand_vars (ep.exe, vars);
            copy.name = Utils.expand_vars (ep.name, vars);
            copy.label = Utils.expand_vars (ep.label, vars);
            copy.icon = Utils.expand_vars (ep.icon, vars);
            target.add (copy);
        }
    }

    private Models.Entrypoint? find_entrypoint (Gee.ArrayList<Models.Entrypoint> eps, string id) {
        var matched = Models.find_by_id<Models.Entrypoint> (eps, id);
        if (matched != null) return matched;
        foreach (var ep in eps) {
            if (ep.is_default) return ep;
        }
        return eps.size > 0 ? eps[0] : null;
    }
}
