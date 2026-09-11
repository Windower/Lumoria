namespace Lumoria.Runtime {

    public class PostInstallRequest : Object {
        public string path { get; set; default = ""; }
        public string uri { get; set; default = ""; }
        public string instance_id { get; set; default = ""; }
    }

    public class InstallOptions : Object {
        public string prefix_path { get; set; default = ""; }
        public Gee.ArrayList<PostInstallRequest> post_installs {
            get; owned set; default = new Gee.ArrayList<PostInstallRequest> ();
        }
        public Models.PrefixEntry prefix_entry { get; set; }

        public static InstallOptions from_prefix (Models.PrefixEntry entry) {
            var opts = new InstallOptions ();
            opts.prefix_path = entry.resolved_path ();
            opts.prefix_entry = entry;
            foreach (var spec in entry.post_install_manifests) {
                var req = new PostInstallRequest ();
                req.path = spec.locate_file (entry.resolved_path ()) ?? spec.original_path;
                req.uri = spec.original_uri;
                req.instance_id = spec.id;
                opts.post_installs.add (req);
            }
            return opts;
        }
    }

    public class InstallProgress : Object {
        public signal void step_changed (string description);
        public signal void progress_changed (double fraction);
        public signal void log_ready (string path);
        public signal void install_finished (bool success, string message);
    }

    private const int CONTROL_STEP_COUNT = 5;

    public void run_full_install (
        InstallOptions opts,
        InstallProgress progress,
        Cancellable? cancellable
    ) throws Error {
        run_logged_install (opts.prefix_entry, progress, "INSTALL CANCELLED", "Installation cancelled.", "INSTALL FAILED", (logger, scope) => {
            write_install_header (logger, opts);
            var rep = new StepReporter (CONTROL_STEP_COUNT, progress, logger, cancellable);

            var plan = prepare_install_phases (opts, rep, logger, cancellable);
            scope.runtime = plan.runtime;
            rep.total = CONTROL_STEP_COUNT + plan.step_count;
            plan.run_downloads (rep);

            rep.label (_("Predownloading enabled components..."));
            logger.banner ("Predownloading enabled components");
            predownload_enabled_components (plan.entry, logger, cancellable);

            rep.label (_("Creating wine prefix..."));
            create_prefix_stage (plan, scope, logger, cancellable);

            rep.total = rep.idx + 1 + plan.exec_count;
            rep.label (_("Applying components..."));
            run_install_phases (plan, rep, logger, cancellable);

            finish_install_success (plan.runtime, progress, logger, "Install completed successfully", "Install complete.");
        });
    }

    /* Manifests, runtime, variables and phases resolved before any prefix exists on disk. */
    private class InstallPlan : Object {
        public Models.PrefixEntry entry;
        public Models.InstallerManifest installer;
        public Models.LauncherManifest? launcher;
        public WineRuntime runtime;
        public string wineboot_mscoree_policy = "";
        public Gee.HashMap<string, string> installer_vars;
        public Gee.HashMap<string, string>? launcher_vars;
        public InstallPhase installer_phase;
        public InstallPhase? launcher_phase;
        public Gee.ArrayList<PostInstallJob> script_jobs = new Gee.ArrayList<PostInstallJob> ();

        public int step_count {
            get {
                var n = installer_phase.step_count;
                if (launcher_phase != null) n += launcher_phase.step_count;
                foreach (var job in script_jobs) n += 1 + job.phase.step_count;
                return n;
            }
        }

        public int exec_count {
            get {
                var n = installer_phase.exec_count;
                if (launcher_phase != null) n += launcher_phase.exec_count;
                foreach (var job in script_jobs) n += 1 + job.phase.exec_count;
                return n;
            }
        }

        public void run_downloads (StepReporter rep) throws Error {
            installer_phase.run_downloads (rep, "Downloading installer artifacts");
            if (launcher_phase != null) launcher_phase.run_downloads (rep, "Downloading launcher artifacts");
            foreach (var job in script_jobs) job.phase.run_downloads (rep, "Downloading post install artifacts");
        }

        public void finalize_vars (RuntimeLog logger) {
            finalize_manifest_vars (installer_vars, runtime.paths, runtime.env, logger);
            if (launcher_vars != null) finalize_manifest_vars (launcher_vars, runtime.paths, runtime.env, logger);
            foreach (var job in script_jobs) finalize_manifest_vars (job.vars, runtime.paths, runtime.env, logger);
        }
    }

    private InstallPlan prepare_install_phases (
        InstallOptions opts,
        StepReporter rep,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var plan = new InstallPlan ();
        plan.entry = opts.prefix_entry;
        var repository = Models.ManifestRepository.shared ();
        plan.installer = repository.require_installer (plan.entry.installer_id);
        plan.launcher = plan.installer.supports_launcher (plan.entry.launcher_id)
            ? Models.find_by_id<Models.LauncherManifest> (repository.launchers, plan.entry.launcher_id)
            : null;
        var loaded_scripts = load_post_install_requests (opts);

        var redist_ids = merged_redist_ids (plan.installer.redists, plan.launcher);
        foreach (var loaded in loaded_scripts) redist_ids.add_all (loaded.spec.redists);
        var redists = ResolvedRedistSet.resolve (redist_ids, repository.all_redists);

        rep.label (_("Preparing runner..."));
        var runner_manifest = Models.RunnerManifest.resolve_for_entry (
            Models.ManifestRepository.shared ().host_runners, plan.entry
        );
        logger.emit_line ("Using runner: %s %s\n".printf (
            runner_manifest.display_label (),
            Utils.Preferences.resolve_version (plan.entry.runner_id, plan.entry.runner_version)
        ));

        rep.label (_("Downloading %s...").printf (runner_manifest.display_label ()));
        var runtime_request = WineRuntimeRequest.from_prefix (plan.entry, runner_manifest);
        runtime_request.download_progress = rep.download_progress_cb ();
        plan.runtime = prepare_wine_runtime (runtime_request, logger, cancellable);
        log_runtime_paths (logger, plan.runtime);

        var pfx_path = plan.runtime.prefix_path;
        plan.wineboot_mscoree_policy = resolve_wineboot_mscoree_policy (plan.installer, plan.launcher);

        plan.installer_vars = build_prefix_vars (
            pfx_path, ensure_cache_subdir ("installer", plan.installer.id), plan.installer.variables
        );
        seed_phase_vars (
            plan.installer_vars, plan.wineboot_mscoree_policy, redists,
            plan.runtime, plan.entry, plan.installer.variable_rules, plan.installer.env, logger
        );
        plan.installer_phase = new InstallPhase (
            plan.installer.downloads, plan.installer.steps, redists, plan.installer_vars, plan.entry
        );

        if (plan.launcher != null) {
            plan.launcher_vars = build_prefix_vars (
                pfx_path, ensure_cache_subdir ("launchers", plan.launcher.id), plan.launcher.variables
            );
            seed_phase_vars (
                plan.launcher_vars, plan.wineboot_mscoree_policy, redists,
                plan.runtime, plan.entry, plan.launcher.variable_rules, plan.launcher.env, logger
            );
            plan.launcher_phase = new InstallPhase (
                plan.launcher.downloads, plan.launcher.steps, new ResolvedRedistSet (), plan.launcher_vars, plan.entry
            );
        }

        foreach (var loaded in loaded_scripts) {
            var vars = post_install_vars (pfx_path, plan.installer, plan.launcher, loaded);
            seed_phase_vars (
                vars, plan.wineboot_mscoree_policy, redists, plan.runtime, plan.entry,
                post_install_rules (plan.installer, plan.launcher, loaded.spec), loaded.spec.env, logger
            );
            plan.script_jobs.add (make_post_install_job (loaded, plan.entry, vars));
        }
        return plan;
    }

    private void create_prefix_stage (
        InstallPlan plan,
        InstallScope scope,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var pfx_path = plan.runtime.prefix_path;
        guard_against_existing_prefix (pfx_path);
        scope.created_prefix = pfx_path;
        logger.banner ("Creating wine prefix");
        create_wine_prefix (plan.runtime.paths, plan.runtime.env, logger, cancellable, plan.wineboot_mscoree_policy);
        ensure_prefix_runner_ready (plan.entry, plan.runtime, logger, false);
        logger.emit_line ("Wine prefix created at: %s\n\n".printf (pfx_path));

        plan.finalize_vars (logger);
        log_install_vars (logger, plan.installer_vars);
    }

    private void run_install_phases (
        InstallPlan plan,
        StepReporter rep,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var paths = plan.runtime.paths;
        var env = plan.runtime.env;
        logger.banner ("Applying enabled components");
        apply_components (paths, env, plan.entry, plan.runtime.prefix_path, logger, cancellable);

        plan.installer_phase.run_steps (rep, paths, env, "Run installer steps");
        if (plan.launcher_phase != null) {
            logger.banner ("Setting up launcher: %s".printf (plan.launcher.display_label ()));
            plan.launcher_phase.run_steps (rep, paths, env, null);
        }
        foreach (var job in plan.script_jobs) {
            run_post_install (job, rep, paths, env, plan.entry, logger);
        }
    }

    WineRuntime prepare_entry_runtime (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var runner_manifest = Models.RunnerManifest.resolve_for_entry (runner_manifests, entry);
        var runtime = prepare_wine_runtime (
            WineRuntimeRequest.from_prefix (entry, runner_manifest),
            logger,
            cancellable
        );
        ensure_prefix_runner_ready (entry, runtime, logger);
        return runtime;
    }

    void finish_install_success (
        WineRuntime runtime,
        InstallProgress progress,
        RuntimeLog logger,
        string banner,
        string user
    ) {
        shutdown_wineserver (runtime.paths, runtime.env, logger);
        progress.progress_changed (1.0);
        logger.banner (banner);
        progress.install_finished (true, user);
    }

    private void write_install_header (RuntimeLog logger, InstallOptions opts) {
        logger.banner ("Lumoria Install Log", false);
        logger.emit_line ("Prefix: %s\n".printf (opts.prefix_path));
        logger.emit_line ("Runner: %s variant=%s version=%s\n".printf (
            opts.prefix_entry.runner_id,
            opts.prefix_entry.variant_id,
            opts.prefix_entry.runner_version
        ));
        if (logger.is_disk_enabled ()) {
            logger.emit_line ("Log file: %s\n".printf (logger.log_path));
        }
        logger.emit_line ("\n");
    }

    private Gee.ArrayList<string> merged_redist_ids (
        Gee.ArrayList<string> installer_redists,
        Models.LauncherManifest? launcher
    ) {
        var merged = new Gee.ArrayList<string> ();
        merged.add_all (installer_redists);
        if (launcher != null) merged.add_all (launcher.redists);
        return merged;
    }

    private string resolve_wineboot_mscoree_policy (
        Models.InstallerManifest installer_manifest,
        Models.LauncherManifest? launcher
    ) {
        var policy = installer_manifest.wineboot_mscoree;
        if (launcher != null && launcher.has_wineboot_mscoree) {
            policy = launcher.wineboot_mscoree;
        }
        policy = policy.down ().strip ();
        switch (policy) {
            case "default":
            case "disabled":
                return policy;
            default:
                return "disabled";
        }
    }

    private void log_runtime_paths (RuntimeLog logger, WineRuntime runtime) {
        logger.emit_line ("Runner extracted to: %s\n".printf (runtime.extract_result.extracted_to));
        logger.emit_line ("Wine binary: %s\n".printf (runtime.paths.wine));
        logger.emit_line ("Wineboot: via wine wineboot\n");
        logger.emit_line ("Wineserver: %s\n".printf (runtime.paths.wineserver));
        logger.emit_line ("Runner root: %s\n\n".printf (runtime.paths.root));
    }

    private void log_install_vars (RuntimeLog logger, Gee.HashMap<string, string> vars) {
        logger.emit_line ("Installer variables:\n");
        foreach (var e in vars.entries) {
            logger.emit_line ("  %s = %s\n".printf (e.key, e.value));
        }
        logger.emit_line ("\n");
    }

    private void guard_against_existing_prefix (string pfx_path) throws Error {
        if (wine_prefix_drive_c_exists (pfx_path)) {
            throw new LumoriaError.FAILED (
                _("A Wine prefix already exists at:\n%s\n\nRemove it first or choose a different path.").printf (
                    pfx_path
                )
            );
        }
    }

    private void apply_components (
        WinePaths paths,
        WineEnv env,
        Models.PrefixEntry? prefix_entry,
        string pfx_path,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        env.set_dll_overrides (apply_enabled_components (
            paths, pfx_path, prefix_entry, null, logger, LaunchPolicy.INTERACTIVE, cancellable
        ).dll_overrides);
        seed_component_env_defaults (prefix_entry, pfx_path, logger);
        apply_env_overrides (env, Utils.Preferences.instance ().get_runtime_env_vars ());
        if (prefix_entry != null) apply_env_overrides (env, prefix_entry.runtime_env_vars);
    }

    private void seed_component_env_defaults (
        Models.PrefixEntry? entry,
        string pfx_path,
        RuntimeLog logger
    ) throws Error {
        if (entry == null) return;
        var defaults = resolve_component_env_defaults (pfx_path, entry);
        if (defaults.size == 0) return;
        foreach (var ce in defaults.entries) {
            if (!entry.runtime_env_vars.has_key (ce.key)) {
                entry.runtime_env_vars[ce.key] = ce.value;
            }
        }
        persist_prefix (entry);
        logger.emit_line ("Seeded %d component env default(s) into prefix runtime_env_vars\n".printf (defaults.size));
    }

    class PostInstallJob : Object {
        public Models.LoadedPostInstall loaded;
        public Gee.HashMap<string, string> vars;
        public InstallPhase phase;
    }

    PostInstallJob make_post_install_job (
        Models.LoadedPostInstall loaded,
        Models.PrefixEntry entry,
        Gee.HashMap<string, string> vars
    ) {
        var job = new PostInstallJob ();
        job.loaded = loaded;
        job.vars = vars;
        job.phase = new InstallPhase (loaded.spec.downloads, loaded.spec.steps, new ResolvedRedistSet (), vars, entry);
        return job;
    }

    Gee.HashMap<string, string> post_install_vars (
        string pfx_path,
        Models.InstallerManifest installer,
        Models.LauncherManifest? launcher,
        Models.LoadedPostInstall loaded
    ) throws Error {
        var cache_token = loaded.metadata.id != "" ? loaded.metadata.id : loaded.spec.id;
        return build_post_install_vars (
            pfx_path, ensure_cache_subdir ("post-install", cache_token), installer, launcher, loaded.spec
        );
    }

    Gee.ArrayList<Models.EnvRule> post_install_rules (
        Models.InstallerManifest installer,
        Models.LauncherManifest? launcher,
        Models.PostInstallManifest spec
    ) {
        var rules = merged_variable_rules (installer, launcher);
        rules.add_all (spec.variable_rules);
        return rules;
    }

    private Gee.ArrayList<Models.LoadedPostInstall> load_post_install_requests (InstallOptions opts) throws Error {
        var loaded = new Gee.ArrayList<Models.LoadedPostInstall> ();
        foreach (var req in opts.post_installs) {
            if (req.path == "") continue;
            var spec = Models.PostInstallManifest.load_from_file (req.path);
            var meta = opts.prefix_entry != null
                ? opts.prefix_entry.find_post_install_metadata (req.instance_id)
                : null;
            if (meta == null) {
                throw new LumoriaError.NOT_FOUND (
                    _("Post-install script not found: %s").printf (
                        req.instance_id != "" ? req.instance_id : req.path
                    )
                );
            }
            var item = new Models.LoadedPostInstall ();
            item.metadata = meta;
            item.spec = spec;
            loaded.add (item);
        }
        return loaded;
    }

    void run_post_install (
        PostInstallJob job,
        StepReporter rep,
        WinePaths paths,
        WineEnv env,
        Models.PrefixEntry? prefix_entry,
        RuntimeLog logger
    ) throws Error {
        var spec = job.loaded.spec;
        var meta = job.loaded.metadata;
        try {
            logger.banner ("Post install: %s".printf (spec.display_label ()));
            rep.label (_("Storing post-install manifest..."));
            var prefix_root = prefix_entry != null ? prefix_entry.resolved_path () : "";
            var source = meta.locate_file (prefix_root) ?? meta.original_path;
            if (source == "" || !FileUtils.test (source, FileTest.IS_REGULAR)) {
                throw new LumoriaError.NOT_FOUND (
                    _("Post-install manifest not found: %s").printf (
                        meta.name != "" ? meta.name : meta.id
                    )
                );
            }
            var stored = store_post_install_manifest (prefix_root, source, meta.id);
            logger.typed (LogType.COPY, "%s -> %s".printf (source, stored));

            job.phase.run_steps (rep, paths, env, null);

            update_post_install_metadata (prefix_entry, spec, meta, "success");
        } catch (Error e) {
            update_post_install_metadata (prefix_entry, spec, meta, "failed");
            throw e;
        }
    }

    private void announce_install_failure (
        InstallProgress progress,
        RuntimeLog logger,
        string banner_title,
        string user_message,
        string log_message
    ) {
        logger.banner (banner_title);
        logger.emit_line ("%s\n".printf (log_message));
        progress.install_finished (false, user_message);
    }

    public string store_post_install_manifest (
        string prefix_root,
        string source_path,
        string instance_id
    ) throws Error {
        var dest = Models.PrefixPostInstallManifest.path_for (prefix_root, instance_id);
        string contents;
        FileUtils.get_contents (source_path, out contents);
        Utils.write_text_atomic (dest, contents);
        return dest;
    }

    private void update_post_install_metadata (
        Models.PrefixEntry? prefix_entry,
        Models.PostInstallManifest spec,
        Models.PrefixPostInstallManifest meta,
        string status
    ) throws Error {
        if (prefix_entry == null) return;

        var existing = prefix_entry.find_post_install_metadata (meta.id);
        if (existing == null) {
            warning ("Post-install metadata missing for %s", meta.id);
            return;
        }
        existing.manifest_id = spec.id;
        existing.name = spec.display_label ();
        existing.last_run_status = status;
        existing.last_run_at = new DateTime.now_utc ().format_iso8601 ();

        persist_prefix (prefix_entry);
    }
}

