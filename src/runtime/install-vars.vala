namespace Lumoria.Runtime {

    string ensure_cache_subdir (string category, string id) throws Error {
        var path = Path.build_filename (Utils.cache_dir (), category, id);
        Utils.ensure_dir (path);
        return path;
    }

    Gee.HashMap<string, string> build_prefix_vars (
        string pfx_path,
        string cache_path,
        Gee.HashMap<string, string>? spec_vars
    ) {
        var vars = new Gee.HashMap<string, string> ();
        seed_manifest_vars (vars, pfx_path, null, cache_path);
        if (spec_vars != null) merge_vars (vars, spec_vars);
        finalize_manifest_vars (vars);
        return vars;
    }

    void seed_phase_vars (
        Gee.HashMap<string, string> vars,
        string mscoree_policy,
        ResolvedRedistSet redists,
        WineRuntime runtime,
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.EnvRule>? variable_rules,
        Gee.ArrayList<Models.EnvRule> env_rules,
        RuntimeLog logger
    ) {
        vars[VAR_WINEBOOT_MSCOREE] = mscoree_policy;
        foreach (var spec in redists.specs) {
            vars["REDIST_%s".printf (spec.id)] = "1";
        }
        foreach (var step in redists.code_steps) {
            vars["REDIST_%s".printf (step.command)] = "1";
        }
        inject_prefix_context (vars, runtime, entry, logger, variable_rules);
        apply_env_rules (runtime.env, env_rules, vars);
    }

    void inject_prefix_context (
        Gee.HashMap<string, string> vars,
        WineRuntime runtime,
        Models.PrefixEntry? entry,
        RuntimeLog logger,
        Gee.ArrayList<Models.EnvRule>? variable_rules = null
    ) {
        set_arch_vars (vars, runtime.wine_arch);
        resolve_prefix_vars (vars, entry, logger);
        if (variable_rules != null) {
            apply_variable_rules (vars, variable_rules);
        }
    }

    void apply_install_vars (
        Gee.HashMap<string, string> vars,
        WineRuntime runtime,
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.EnvRule>? variable_rules,
        Gee.ArrayList<Models.EnvRule> env_rules,
        RuntimeLog logger
    ) {
        inject_prefix_context (vars, runtime, entry, logger, variable_rules);
        apply_env_rules (runtime.env, env_rules, vars);
        finalize_manifest_vars (vars, runtime.paths, runtime.env, logger);
    }

    Gee.ArrayList<Models.EnvRule> merged_variable_rules (
        Models.InstallerManifest installer_manifest,
        Models.LauncherManifest? launcher
    ) {
        var rules = new Gee.ArrayList<Models.EnvRule> ();
        rules.add_all (installer_manifest.variable_rules);
        if (launcher != null) rules.add_all (launcher.variable_rules);
        return rules;
    }

    Gee.HashMap<string, string> build_post_install_vars (
        string pfx_path,
        string cache_path,
        Models.InstallerManifest installer_manifest,
        Models.LauncherManifest? launcher,
        Models.PostInstallManifest post_install_manifest
    ) {
        var vars = build_prefix_vars (
            pfx_path,
            cache_path,
            installer_manifest.variables
        );
        if (launcher != null) merge_vars (vars, launcher.variables);
        merge_vars (vars, post_install_manifest.variables);
        return vars;
    }

    Gee.HashMap<string, string> build_action_vars (
        string pfx_path,
        string cache_path,
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests,
        Models.ManifestAction action
    ) throws Error {
        var installer_manifest = Models.ManifestRepository.shared ().require_installer (
            entry.installer_id
        );
        var launcher = Models.find_by_id<Models.LauncherManifest> (launcher_manifests, entry.launcher_id);
        var vars = build_prefix_vars (
            pfx_path,
            cache_path,
            installer_manifest.variables
        );
        if (launcher != null) merge_vars (vars, launcher.variables);
        foreach (var loaded in load_prefix_post_installs (entry)) {
            merge_vars (vars, loaded.spec.variables);
        }
        merge_vars (vars, action.variables);
        return vars;
    }
}
