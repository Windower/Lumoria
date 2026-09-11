namespace Lumoria.Runtime {

    /* What a failed install has to undo: stop the wineserver it started and drop a prefix it created. */
    private class InstallScope : Object {
        public WineRuntime? runtime = null;
        public string created_prefix = "";
    }

    private delegate void LoggedInstall (RuntimeLog logger, InstallScope scope) throws Error;

    private void run_logged_install (
        Models.PrefixEntry entry,
        InstallProgress progress,
        string cancel_banner,
        string cancel_message,
        string fail_banner,
        owned LoggedInstall body
    ) throws Error {
        var session = peek_session ();
        if (session == null) {
            var message = _("Runtime session is not available");
            progress.install_finished (false, message);
            throw new LumoriaError.FAILED ("%s", message);
        }
        session.set_worker_prefix (entry);
        var logger = RuntimeLog.for_install (entry.resolved_path ());
        if (logger.is_disk_enabled ()) progress.log_ready (logger.log_path);
        var scope = new InstallScope ();
        try {
            body (logger, scope);
        } catch (IOError.CANCELLED e) {
            undo_failed_install (scope, logger);
            announce_install_failure (progress, logger, cancel_banner, cancel_message, e.message);
        } catch (Error e) {
            undo_failed_install (scope, logger);
            announce_install_failure (progress, logger, fail_banner, user_error (e), e.message);
        } finally {
            logger.close ();
            session.set_worker_prefix (null);
        }
    }

    private void undo_failed_install (InstallScope scope, RuntimeLog logger) {
        if (scope.runtime != null) shutdown_wineserver (scope.runtime.paths, scope.runtime.env, logger);
        if (scope.created_prefix == "") return;
        if (Utils.remove_recursive (scope.created_prefix)) {
            logger.emit_line ("Removed incomplete wine prefix at: %s\n".printf (scope.created_prefix));
        } else {
            logger.typed (LogType.WARN, "could not remove incomplete wine prefix %s".printf (scope.created_prefix));
        }
    }

    public void run_manifest_action (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests,
        string action_id,
        InstallProgress progress,
        Cancellable? cancellable,
        Models.ManifestAction? spec = null
    ) throws Error {
        run_logged_install (entry, progress, "ACTION CANCELLED", "Action cancelled.", "ACTION FAILED", (logger, scope) => {
                var action = spec ?? find_manifest_action_in_context (
                    make_manifest_context (entry, launcher_manifests), action_id
                );
                if (action == null) {
                    throw new LumoriaError.NOT_FOUND (_("Manifest action not found: %s").printf (action_id));
                }

                logger.banner ("Lumoria Action Log", false);
                logger.emit_line ("Prefix: %s\n".printf (entry.resolved_path ()));
                logger.emit_line ("Action: %s\n\n".printf (action.display_label ()));

                var action_redists = ResolvedRedistSet.resolve (
                    action.redists, Models.ManifestRepository.shared ().all_redists
                );
                var installer_manifest = Models.ManifestRepository.shared ().require_installer (
                    entry.installer_id
                );
                var launcher = Models.find_by_id<Models.LauncherManifest> (launcher_manifests, entry.launcher_id);
                var action_rules = merged_variable_rules (installer_manifest, launcher);
                foreach (var loaded in Runtime.load_prefix_post_installs (entry)) {
                    action_rules.add_all (loaded.spec.variable_rules);
                }
                run_prepared_phase (
                    entry, runner_manifests, progress, cancellable, logger, scope,
                    _("Preparing action..."),
                    action_rules, action.env,
                    (runtime) => build_action_vars (
                        runtime.prefix_path,
                        ensure_cache_subdir (Path.build_filename ("actions", entry.id), action.id),
                        entry, launcher_manifests, action
                    ),
                    (runtime, vars) => new InstallPhase (
                        action.downloads, action.steps, action_redists, vars, entry
                    ),
                    "Downloading action artifacts",
                    "Run action steps",
                    "Action completed successfully",
                    "Action complete."
                );
        });
    }

    public void run_redist_install (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        string redist_id,
        InstallProgress progress,
        Cancellable? cancellable
    ) throws Error {
        run_logged_install (entry, progress, "INSTALL CANCELLED", "Install cancelled.", "INSTALL FAILED", (logger, scope) => {
                var installer_manifest = Models.ManifestRepository.shared ().require_installer (
                    entry.installer_id
                );
                logger.banner ("Lumoria Redist Install", false);
                logger.emit_line ("Prefix: %s\n".printf (entry.resolved_path ()));
                logger.emit_line ("Redist: %s\n\n".printf (redist_id));

                var all_redists = Models.ManifestRepository.shared ().all_redists;
                var ids = new Gee.ArrayList<string> ();
                ids.add (redist_id);
                var resolved = ResolvedRedistSet.resolve (ids, all_redists);

                run_prepared_phase (
                    entry, runner_manifests, progress, cancellable, logger, scope,
                    _("Preparing runner..."),
                    installer_manifest.variable_rules, installer_manifest.env,
                    (runtime) => build_prefix_vars (
                        runtime.prefix_path, ensure_cache_subdir ("redist", redist_id), installer_manifest.variables
                    ),
                    (runtime, vars) => new InstallPhase (
                        new Gee.ArrayList<Models.DownloadItem> (),
                        new Gee.ArrayList<Models.InstallStep> (),
                        resolved, vars, entry, true
                    ),
                    "Downloading redist artifacts",
                    "Installing redist",
                    "Redist install completed successfully",
                    "Install complete."
                );
        });
    }

    public void run_post_install_script (
        Models.PrefixEntry entry,
        string instance_id,
        InstallProgress progress,
        Cancellable? cancellable
    ) throws Error {
        run_logged_install (entry, progress, "SCRIPT CANCELLED", "Script cancelled.", "SCRIPT FAILED", (logger, scope) => {
                var loaded = load_post_install (entry, instance_id);
                if (loaded == null) {
                    throw new LumoriaError.NOT_FOUND (_("Post-install script not found: %s").printf (instance_id));
                }

                logger.banner ("Lumoria Script Log", false);
                logger.emit_line ("Prefix: %s\n".printf (entry.resolved_path ()));
                logger.emit_line ("Script: %s\n\n".printf (loaded.spec.display_label ()));

                var installer_manifest = Models.ManifestRepository.shared ().require_installer (entry.installer_id);
                var launcher = Models.find_by_id<Models.LauncherManifest> (
                    Models.ManifestRepository.shared ().launchers,
                    entry.launcher_id
                );

                Gee.HashMap<string, string> vars;
                StepReporter rep;
                var runtime = prepare_runtime_for_phase (
                    entry, Models.ManifestRepository.shared ().host_runners, progress, cancellable, logger, scope,
                    _("Preparing script..."),
                    post_install_rules (installer_manifest, launcher, loaded.spec), loaded.spec.env,
                    (prepared) => post_install_vars (prepared.prefix_path, installer_manifest, launcher, loaded),
                    out vars, out rep
                );

                var job = make_post_install_job (loaded, entry, vars);
                rep.total = 2 + job.phase.step_count;
                job.phase.run_downloads (rep, "Downloading post install artifacts");
                run_post_install (job, rep, runtime.paths, runtime.env, entry, logger);

                finish_install_success (runtime, progress, logger, "Script completed successfully", "Script complete.");
        });
    }

    private delegate Gee.HashMap<string, string> BuildInstallVars (WineRuntime runtime) throws Error;
    private delegate InstallPhase BuildInstallPhase (WineRuntime runtime, Gee.HashMap<string, string> vars);

    private WineRuntime prepare_runtime_for_phase (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        InstallProgress progress,
        Cancellable? cancellable,
        RuntimeLog logger,
        InstallScope scope,
        string prepare_label,
        Gee.ArrayList<Models.EnvRule> rules,
        Gee.ArrayList<Models.EnvRule> env_rules,
        BuildInstallVars build_vars,
        out Gee.HashMap<string, string> vars,
        out StepReporter rep
    ) throws Error {
        rep = new StepReporter (1, progress, logger, cancellable);
        rep.label (prepare_label);
        var runtime = prepare_entry_runtime (entry, runner_manifests, logger, cancellable);
        scope.runtime = runtime;
        vars = build_vars (runtime);
        apply_install_vars (vars, runtime, entry, rules, env_rules, logger);
        return runtime;
    }

    private void run_prepared_phase (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        InstallProgress progress,
        Cancellable? cancellable,
        RuntimeLog logger,
        InstallScope scope,
        string prepare_label,
        Gee.ArrayList<Models.EnvRule> rules,
        Gee.ArrayList<Models.EnvRule> env_rules,
        BuildInstallVars build_vars,
        BuildInstallPhase build_phase,
        string download_banner,
        string? step_banner,
        string success_banner,
        string success_user
    ) throws Error {
        Gee.HashMap<string, string> vars;
        StepReporter rep;
        var runtime = prepare_runtime_for_phase (
            entry, runner_manifests, progress, cancellable, logger, scope,
            prepare_label, rules, env_rules, build_vars, out vars, out rep
        );
        var phase = build_phase (runtime, vars);
        rep.total = 1 + phase.step_count;
        phase.run_downloads (rep, download_banner);
        phase.run_steps (rep, runtime.paths, runtime.env, step_banner);
        finish_install_success (runtime, progress, logger, success_banner, success_user);
    }
}
