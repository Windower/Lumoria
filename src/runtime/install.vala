namespace Lumoria.Runtime {

    public class InstallOptions : Object {
        public string prefix_path { get; set; default = ""; }
        public string runner_id { get; set; default = ""; }
        public string runner_version { get; set; default = "latest"; }
        public string variant_id { get; set; default = ""; }
        public string wine_arch { get; set; default = ""; }
        public string wine_debug { get; set; default = ""; }
        public bool? wine_wayland = null;
        public string launcher_id { get; set; default = ""; }
        public string post_install_spec_path { get; set; default = ""; }
        public string post_install_spec_uri { get; set; default = ""; }
        public Models.PrefixEntry? prefix_entry { get; set; default = null; }
    }

    public class InstallProgress : Object {
        public signal void step_changed (string description);
        public signal void progress_changed (double fraction);
        public signal void log_message (string message);
        public signal void install_finished (bool success, string message);
    }

    public void run_full_install (
        InstallOptions opts,
        InstallProgress progress,
        Cancellable? cancellable
    ) {
        var logger = RuntimeLog.for_install (opts.prefix_path, (msg) => {
            progress.log_message (msg);
        });
        var log_path = logger.log_path;

        try {

            logger.banner ("Lumoria Install Log", false);
            logger.emit_line ("Prefix: %s\n".printf (opts.prefix_path));
            logger.emit_line ("Runner: %s variant=%s version=%s\n".printf (opts.runner_id, opts.variant_id, opts.runner_version));
            if (logger.is_disk_enabled ()) {
                logger.emit_line ("Log file: %s\n".printf (log_path));
            }
            logger.emit_line ("\n");

            var installer_spec = Models.InstallerSpec.load_from_resource ();
            Models.LauncherSpec? launcher = null;
            if (opts.launcher_id != "") {
                var launcher_specs = Models.LauncherSpec.load_all_from_resource ();
                foreach (var ls in launcher_specs) {
                    if (ls.id == opts.launcher_id) { launcher = ls; break; }
                }
            }

            Models.PostInstallSpec? post_install_spec = null;
            if (opts.post_install_spec_path != "") {
                post_install_spec = Models.PostInstallSpec.load_from_file (opts.post_install_spec_path);
            }

            var all_redist_specs = Models.RedistSpec.load_all_from_resource ();
            var resolved_redists = new Gee.ArrayList<Models.RedistSpec> ();
            var code_redists = new Gee.ArrayList<string> ();
            var requested_redists = new Gee.ArrayList<string> ();
            var seen_redists = new Gee.HashSet<string> ();
            var post_resolved_redists = new Gee.ArrayList<Models.RedistSpec> ();
            var post_code_redists = new Gee.ArrayList<string> ();

            foreach (var rid in installer_spec.redists) {
                if (!seen_redists.contains (rid)) {
                    requested_redists.add (rid);
                    seen_redists.add (rid);
                }
            }
            if (launcher != null) {
                foreach (var rid in launcher.redists) {
                    if (!seen_redists.contains (rid)) {
                        requested_redists.add (rid);
                        seen_redists.add (rid);
                    }
                }
            }

            foreach (var rid in requested_redists) {
                if (all_redist_specs.has_key (rid)) {
                    resolved_redists.add (all_redist_specs[rid]);
                } else {
                    code_redists.add (rid);
                }
            }

            if (post_install_spec != null) {
                foreach (var rid in post_install_spec.redists) {
                    if (all_redist_specs.has_key (rid)) {
                        post_resolved_redists.add (all_redist_specs[rid]);
                    } else {
                        post_code_redists.add (rid);
                    }
                }
            }

            int redist_downloads = 0;
            int redist_steps = 0;
            foreach (var rs in resolved_redists) {
                redist_downloads += rs.downloads.size;
                redist_steps += rs.steps.size;
            }
            int post_redist_downloads = 0;
            int post_redist_steps = 0;
            foreach (var rs in post_resolved_redists) {
                post_redist_downloads += rs.downloads.size;
                post_redist_steps += rs.steps.size;
            }

            int total_steps = 3
                + installer_spec.downloads.size
                + (launcher != null ? launcher.downloads.size : 0)
                + (launcher != null ? launcher.steps.size : 0)
                + redist_downloads + redist_steps
                + code_redists.size
                + (post_install_spec != null ? post_install_spec.downloads.size : 0)
                + (post_install_spec != null ? post_install_spec.steps.size : 0)
                + post_redist_downloads + post_redist_steps
                + post_code_redists.size
                + (post_install_spec != null ? 1 : 0)
                + 1
                + installer_spec.steps.size
                + 1;
            int step_idx = 0;

            logger.phase ("Prepare runner");
            step_idx++;
            progress.step_changed ("(%d/%d) Preparing runner\u2026".printf (step_idx, total_steps));
            progress.progress_changed ((double) (step_idx - 1) / total_steps);

            var runner_specs = Models.RunnerSpec.filter_for_host (Models.RunnerSpec.load_all_from_resource ());
            var runner_spec = Models.RunnerSpec.find_or_default (runner_specs, opts.runner_id);

            var resolved_version = Utils.Preferences.resolve_version (opts.runner_id, opts.runner_version);
            logger.emit_line ("Using runner: %s %s\n".printf (runner_spec.display_label (), resolved_version));

            check_cancelled (cancellable);

            step_idx++;
            progress.step_changed ("(%d/%d) Downloading %s\u2026".printf (step_idx, total_steps, runner_spec.display_label ()));
            var dl_base = (double) (step_idx - 1) / total_steps;
            var dl_range = 1.0 / total_steps;
            var result = download_and_extract_runner (
                runner_spec, opts.variant_id, resolved_version,
                (downloaded, total) => {
                    if (total > 0) {
                        progress.progress_changed (dl_base + (double) downloaded / (double) total * dl_range);
                    }
                },
                logger
            );
            logger.emit_line ("Runner extracted to: %s\n".printf (result.extracted_to));

            check_cancelled (cancellable);

            var paths = resolve_wine_paths (result.extracted_to, runner_spec, opts.variant_id);
            logger.emit_line ("Wine binary: %s\n".printf (paths.wine));
            logger.emit_line ("Wineboot: via wine wineboot\n");
            logger.emit_line ("Wineserver: %s\n".printf (paths.wineserver));
            logger.emit_line ("Runner root: %s\n\n".printf (paths.root));

            var variant = runner_spec.effective_variant (opts.variant_id);
            var wine_arch = opts.wine_arch;
            if (wine_arch == "") wine_arch = variant.wine_arch;
            var pfx_path = install_prefix_path (opts.prefix_path);
            var prefs = Utils.Preferences.instance ();
            Models.PrefixEntry? prefix_entry = opts.prefix_entry;
            if (prefix_entry == null) {
                var registry = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
                prefix_entry = registry.by_path (opts.prefix_path);
            }

            var env = build_wine_env (
                paths, runner_spec, opts.variant_id,
                pfx_path, wine_arch,
                Utils.Preferences.resolve_sync_mode (opts.prefix_entry != null ? opts.prefix_entry.sync_mode : ""),
                Utils.Preferences.resolve_wine_debug (opts.wine_debug),
                false,
                Utils.Preferences.resolve_wine_wayland (opts.wine_wayland)
            );
            apply_env_overrides (env, prefs.get_runtime_env_vars ());
            if (prefix_entry != null) {
                apply_env_overrides (env, prefix_entry.runtime_env_vars);
            }

            var cache_root = Path.build_filename (Utils.cache_dir (), "installer", installer_spec.id);
            Utils.ensure_dir (cache_root);
            var vars = build_prefix_vars (pfx_path, cache_root, installer_spec.variables);

            logger.emit_line ("Installer variables:\n");
            foreach (var e in vars.entries) {
                logger.emit_line ("  %s = %s\n".printf (e.key, e.value));
            }
            logger.emit_line ("\n");

            Gee.HashMap<string, string>? launcher_vars = null;
            if (launcher != null) {
                var launcher_cache = Path.build_filename (Utils.cache_dir (), "launchers", launcher.id);
                Utils.ensure_dir (launcher_cache);
                launcher_vars = build_prefix_vars (pfx_path, launcher_cache, launcher.variables);
            }

            Gee.HashMap<string, string>? post_install_vars = null;
            if (post_install_spec != null) {
                var post_cache = Path.build_filename (Utils.cache_dir (), "post-install", post_install_spec.id);
                Utils.ensure_dir (post_cache);
                post_install_vars = build_post_install_vars (pfx_path, post_cache, installer_spec, launcher, post_install_spec);
            }

            logger.phase ("Downloading installer artifacts");
            foreach (var dl in installer_spec.downloads) {
                check_cancelled (cancellable);

                step_idx++;
                var dest = expand_path (dl.dest, vars);

                ensure_download_item (dl, dest, step_idx, total_steps, progress, logger);
            }

            if (launcher_vars != null) {
                foreach (var rs in resolved_redists) {
                    foreach (var dl in rs.downloads) {
                        check_cancelled (cancellable);

                        step_idx++;
                        var dest = expand_path (dl.dest, launcher_vars);
                        ensure_download_item (dl, dest, step_idx, total_steps, progress, logger);
                    }
                }

                foreach (var dl in launcher.downloads) {
                    check_cancelled (cancellable);

                    step_idx++;
                    var dest = expand_path (dl.dest, launcher_vars);
                    ensure_download_item (dl, dest, step_idx, total_steps, progress, logger);
                }
            }

            if (post_install_vars != null) {
                logger.phase ("Downloading post install artifacts");
                foreach (var rs in post_resolved_redists) {
                    foreach (var dl in rs.downloads) {
                        check_cancelled (cancellable);

                        step_idx++;
                        var dest = expand_path (dl.dest, post_install_vars);
                        ensure_download_item (dl, dest, step_idx, total_steps, progress, logger);
                    }
                }

                foreach (var dl in post_install_spec.downloads) {
                    check_cancelled (cancellable);

                    step_idx++;
                    var dest = expand_path (dl.dest, post_install_vars);
                    ensure_download_item (dl, dest, step_idx, total_steps, progress, logger);
                }
            }

            logger.phase ("Predownload enabled components");
            step_idx++;
            progress.step_changed ("(%d/%d) Predownloading enabled components\u2026".printf (step_idx, total_steps));
            progress.progress_changed ((double) (step_idx - 1) / total_steps);
            logger.banner ("Predownloading enabled components");
            predownload_enabled_components (null, logger);

            check_cancelled (cancellable);

            logger.phase ("Create wine prefix");
            step_idx++;
            progress.step_changed ("(%d/%d) Creating wine prefix\u2026".printf (step_idx, total_steps));
            progress.progress_changed ((double) (step_idx - 1) / total_steps);

            var drive_c = Path.build_filename (pfx_path, "drive_c");
            if (FileUtils.test (drive_c, FileTest.EXISTS)) {
                throw new IOError.FAILED (
                    "A Wine prefix already exists at:\n%s\n\nRemove it first or choose a different path.",
                    pfx_path
                );
            }

            logger.banner ("Creating wine prefix");
            create_wine_prefix (paths, env, logger, cancellable);
            logger.emit_line ("Wine prefix created at: %s\n\n".printf (pfx_path));

            logger.phase ("Apply components");
            step_idx++;
            progress.step_changed ("(%d/%d) Applying components\u2026".printf (step_idx, total_steps));
            progress.progress_changed ((double) (step_idx - 1) / total_steps);
            logger.banner ("Applying enabled components");
            string? component_warning = null;
            try {
                var comp_result = apply_enabled_components (pfx_path, prefix_entry, logger);
                foreach (var ov in comp_result.dll_overrides.entries) {
                    env.add_dll_override (ov.key, ov.value);
                }

                var comp_env_defaults = resolve_component_env_defaults (pfx_path, prefix_entry);
                if (prefix_entry != null && comp_env_defaults.size > 0) {
                    foreach (var ce in comp_env_defaults.entries) {
                        if (!prefix_entry.runtime_env_vars.has_key (ce.key)) {
                            prefix_entry.runtime_env_vars[ce.key] = ce.value;
                        }
                    }
                    var reg = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
                    reg.update_entry (prefix_entry);
                    reg.save (Utils.prefix_registry_path ());
                    logger.emit_line ("Seeded %d component env default(s) into prefix runtime_env_vars\n".printf (comp_env_defaults.size));
                }

                apply_env_overrides (env, prefs.get_runtime_env_vars ());
                if (prefix_entry != null) {
                    apply_env_overrides (env, prefix_entry.runtime_env_vars);
                }
            } catch (Error comp_err) {
                logger.typed (LogType.WARN, "Component application failed: %s".printf (comp_err.message));
                component_warning = "Component setup failed: %s".printf (comp_err.message);
            }

            logger.phase ("Run installer steps");
            foreach (var step in installer_spec.steps) {
                check_cancelled (cancellable);

                step_idx++;
                progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                progress.progress_changed ((double) (step_idx - 1) / total_steps);
                logger.step (step_idx, total_steps, step.description, step.step_type);

                run_install_step (step, vars, paths, env, logger, cancellable);
            }

            if (launcher_vars != null) {
                var launcher_name = launcher != null ? launcher.display_label () : "launcher";
                logger.banner ("Setting up launcher: %s".printf (launcher_name));

                foreach (var rs in resolved_redists) {
                    logger.banner ("Redist: %s".printf (rs.display_label ()));
                    foreach (var step in rs.steps) {
                        check_cancelled (cancellable);

                        step_idx++;
                        progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                        progress.progress_changed ((double) (step_idx - 1) / total_steps);
                        logger.step (step_idx, total_steps, step.description, step.step_type);
                        run_install_step (step, launcher_vars, paths, env, logger, cancellable);
                    }
                }

                foreach (var rid in code_redists) {
                    check_cancelled (cancellable);

                    step_idx++;
                    progress.step_changed ("(%d/%d) Installing %s\u2026".printf (step_idx, total_steps, rid));
                    progress.progress_changed ((double) (step_idx - 1) / total_steps);
                    logger.banner ("Redist: %s (code)".printf (rid));

                    var redist_opts = build_redist_options (
                        launcher_vars.has_key ("PREFIX") ? launcher_vars["PREFIX"] : "",
                        paths,
                        env,
                        cancellable
                    );
                    install_redist (rid, redist_opts, logger);
                }

                foreach (var step in launcher.steps) {
                    check_cancelled (cancellable);

                    step_idx++;
                    progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                    progress.progress_changed ((double) (step_idx - 1) / total_steps);
                    logger.step (step_idx, total_steps, step.description, step.step_type);
                    run_install_step (step, launcher_vars, paths, env, logger, cancellable);
                }
            }

            if (post_install_spec != null && post_install_vars != null) {
                string post_backup_path = "";
                try {
                    logger.banner ("Post install: %s".printf (post_install_spec.display_label ()));

                    check_cancelled (cancellable);
                    step_idx++;
                    progress.step_changed ("(%d/%d) Backing up post install spec\u2026".printf (step_idx, total_steps));
                    progress.progress_changed ((double) (step_idx - 1) / total_steps);
                    post_backup_path = backup_post_install_spec (opts.prefix_path, opts.post_install_spec_path, post_install_spec);
                    logger.typed (LogType.COPY, "%s -> %s".printf (opts.post_install_spec_path, post_backup_path));

                    foreach (var rs in post_resolved_redists) {
                        logger.banner ("Post install redist: %s".printf (rs.display_label ()));
                        foreach (var step in rs.steps) {
                            check_cancelled (cancellable);

                            step_idx++;
                            progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                            progress.progress_changed ((double) (step_idx - 1) / total_steps);
                            logger.step (step_idx, total_steps, step.description, step.step_type);
                            run_install_step (step, post_install_vars, paths, env, logger, cancellable);
                        }
                    }

                    foreach (var rid in post_code_redists) {
                        check_cancelled (cancellable);

                        step_idx++;
                        progress.step_changed ("(%d/%d) Installing %s\u2026".printf (step_idx, total_steps, rid));
                        progress.progress_changed ((double) (step_idx - 1) / total_steps);
                        logger.banner ("Post install redist: %s (code)".printf (rid));

                        var redist_opts = build_redist_options (
                            post_install_vars.has_key ("PREFIX") ? post_install_vars["PREFIX"] : "",
                            paths,
                            env,
                            cancellable
                        );
                        install_redist (rid, redist_opts, logger);
                    }

                    foreach (var step in post_install_spec.steps) {
                        check_cancelled (cancellable);

                        step_idx++;
                        progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                        progress.progress_changed ((double) (step_idx - 1) / total_steps);
                        logger.step (step_idx, total_steps, step.description, step.step_type);
                        run_install_step (step, post_install_vars, paths, env, logger, cancellable);
                    }

                    update_post_install_metadata (
                        prefix_entry,
                        post_install_spec,
                        opts.post_install_spec_path,
                        opts.post_install_spec_uri,
                        post_backup_path,
                        "success",
                        logger
                    );
                } catch (Error post_install_error) {
                    update_post_install_metadata (
                        prefix_entry,
                        post_install_spec,
                        opts.post_install_spec_path,
                        opts.post_install_spec_uri,
                        post_backup_path,
                        "failed",
                        logger
                    );
                    throw post_install_error;
                }
            }

            shutdown_wineserver (paths, env, logger);
            progress.progress_changed (1.0);
            if (component_warning != null) {
                logger.banner ("Install completed with warnings");
                progress.install_finished (true, "Install complete with warnings.\n%s".printf (component_warning));
            } else {
                logger.banner ("Install completed successfully");
                progress.install_finished (true, "Install complete.");
            }

        } catch (IOError.CANCELLED e) {
            logger.banner ("INSTALL CANCELLED");
            logger.emit_line ("%s\n".printf (e.message));
            progress.install_finished (false, "Installation cancelled.");
        } catch (Error e) {
            logger.banner ("INSTALL FAILED");
            logger.emit_line ("%s\n".printf (e.message));
            progress.install_finished (false, e.message);
        } finally {
            logger.close ();
        }
    }

    public void run_spec_action (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerSpec> runner_specs,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        string action_id,
        InstallProgress progress,
        Cancellable? cancellable
    ) {
        var logger = RuntimeLog.for_install (entry.resolved_path (), (msg) => {
            progress.log_message (msg);
        });

        try {
            var action = find_spec_action (entry, launcher_specs, action_id);
            if (action == null) {
                throw new IOError.FAILED ("Spec action not found: %s", action_id);
            }

            logger.banner ("Lumoria Action Log", false);
            logger.emit_line ("Prefix: %s\n".printf (entry.resolved_path ()));
            logger.emit_line ("Action: %s\n\n".printf (action.display_label ()));

            var all_redist_specs = Models.RedistSpec.load_all_from_resource ();
            var resolved_redists = new Gee.ArrayList<Models.RedistSpec> ();
            var code_redists = new Gee.ArrayList<string> ();
            foreach (var rid in action.redists) {
                if (all_redist_specs.has_key (rid)) {
                    resolved_redists.add (all_redist_specs[rid]);
                } else {
                    code_redists.add (rid);
                }
            }

            int redist_downloads = 0;
            int redist_steps = 0;
            foreach (var rs in resolved_redists) {
                redist_downloads += rs.downloads.size;
                redist_steps += rs.steps.size;
            }

            int total_steps = 1 + action.downloads.size + action.steps.size
                + redist_downloads + redist_steps + code_redists.size;
            int step_idx = 0;

            check_cancelled (cancellable);
            step_idx++;
            progress.step_changed ("(%d/%d) Preparing action\u2026".printf (step_idx, total_steps));
            progress.progress_changed ((double) (step_idx - 1) / total_steps);

            var runner_spec = Models.RunnerSpec.find_or_default (runner_specs, entry.runner_id);
            var resolved_version = Utils.Preferences.resolve_version (entry.runner_id, entry.runner_version);
            var result = download_and_extract_runner (runner_spec, entry.variant_id, resolved_version, null, logger);
            var paths = resolve_wine_paths (result.extracted_to, runner_spec, entry.variant_id);
            var pfx_path = install_prefix_path (entry.path);
            var variant = runner_spec.effective_variant (entry.variant_id);
            var wine_arch = entry.wine_arch != "" ? entry.wine_arch : variant.wine_arch;
            var env = build_wine_env (
                paths, runner_spec, entry.variant_id,
                pfx_path, wine_arch,
                Utils.Preferences.resolve_sync_mode (entry.sync_mode),
                Utils.Preferences.resolve_wine_debug (entry.wine_debug),
                false,
                Utils.Preferences.resolve_wine_wayland (entry.wine_wayland)
            );
            var prefs = Utils.Preferences.instance ();
            apply_env_overrides (env, prefs.get_runtime_env_vars ());
            apply_env_overrides (env, entry.runtime_env_vars);

            var cache_root = Path.build_filename (Utils.cache_dir (), "actions", entry.id, action.id);
            Utils.ensure_dir (cache_root);
            var vars = build_action_vars (pfx_path, cache_root, entry, launcher_specs, action);

            logger.phase ("Downloading action artifacts");
            foreach (var rs in resolved_redists) {
                foreach (var dl in rs.downloads) {
                    check_cancelled (cancellable);
                    step_idx++;
                    ensure_download_item (dl, expand_path (dl.dest, vars), step_idx, total_steps, progress, logger);
                }
            }
            foreach (var dl in action.downloads) {
                check_cancelled (cancellable);
                step_idx++;
                ensure_download_item (dl, expand_path (dl.dest, vars), step_idx, total_steps, progress, logger);
            }

            logger.phase ("Run action steps");
            foreach (var rs in resolved_redists) {
                logger.banner ("Action redist: %s".printf (rs.display_label ()));
                foreach (var step in rs.steps) {
                    check_cancelled (cancellable);
                    step_idx++;
                    progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                    progress.progress_changed ((double) (step_idx - 1) / total_steps);
                    logger.step (step_idx, total_steps, step.description, step.step_type);
                    run_install_step (step, vars, paths, env, logger, cancellable);
                }
            }
            foreach (var rid in code_redists) {
                check_cancelled (cancellable);
                step_idx++;
                progress.step_changed ("(%d/%d) Installing %s\u2026".printf (step_idx, total_steps, rid));
                progress.progress_changed ((double) (step_idx - 1) / total_steps);
                logger.banner ("Action redist: %s (code)".printf (rid));
                install_redist (rid, build_redist_options (pfx_path, paths, env, cancellable), logger);
            }
            foreach (var step in action.steps) {
                check_cancelled (cancellable);
                step_idx++;
                progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                progress.progress_changed ((double) (step_idx - 1) / total_steps);
                logger.step (step_idx, total_steps, step.description, step.step_type);
                run_install_step (step, vars, paths, env, logger, cancellable);
            }

            shutdown_wineserver (paths, env, logger);
            progress.progress_changed (1.0);
            logger.banner ("Action completed successfully");
            progress.install_finished (true, "Action complete.");
        } catch (IOError.CANCELLED e) {
            logger.banner ("ACTION CANCELLED");
            logger.emit_line ("%s\n".printf (e.message));
            progress.install_finished (false, "Action cancelled.");
        } catch (Error e) {
            logger.banner ("ACTION FAILED");
            logger.emit_line ("%s\n".printf (e.message));
            progress.install_finished (false, e.message);
        } finally {
            logger.close ();
        }
    }

    private void ensure_download_item (
        Models.DownloadItem dl,
        string dest,
        int step_idx,
        int total_steps,
        InstallProgress progress,
        RuntimeLog logger
    ) throws Error {
        Utils.ensure_dir (Path.get_dirname (dest));
        progress.step_changed ("(%d/%d) Downloading %s\u2026".printf (step_idx, total_steps, dl.id));

        if (download_item_is_valid (dl, dest, logger)) {
            progress.progress_changed ((double) step_idx / total_steps);
            logger.typed (LogType.CACHED, dest);
            return;
        }

        var s_base = (double) (step_idx - 1) / total_steps;
        var s_range = 1.0 / total_steps;
        logger.emit_line ("Downloading: %s\n  -> %s\n".printf (dl.url, dest));
        Utils.ensure_downloaded_file (
            dl.url,
            dest,
            0,
            dl.sha256,
            dl.id,
            (downloaded, total) => {
                if (total > 0) {
                    progress.progress_changed (s_base + (double) downloaded / (double) total * s_range);
                }
            }
        );
        logger.typed (LogType.DONE, dl.id);
    }

    private bool download_item_is_valid (Models.DownloadItem dl, string path, RuntimeLog logger) {
        if (!FileUtils.test (path, FileTest.EXISTS)) return false;

        if (dl.sha256 == "") {
            logger.typed (LogType.WARN, "%s has no checksum; using size-only cache validation".printf (dl.id));
        }

        var valid = Utils.validate_downloaded_file (path, 0, dl.sha256, dl.id);
        if (!valid && FileUtils.test (path, FileTest.EXISTS)) {
            FileUtils.remove (path);
        }
        return valid;
    }

    private void run_install_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable = null
    ) throws Error {
        check_cancelled (cancellable);

        if (step.condition != "") {
            if (!evaluate_condition (step.condition, env, logger)) {
                logger.typed (LogType.SKIP, "condition '%s' not met".printf (step.condition));
                return;
            }
        }

        foreach (var skip in step.skip_if_exists) {
            var expanded = expand_path (skip, vars);
            if (FileUtils.test (expanded, FileTest.EXISTS)) {
                logger.typed (LogType.SKIP, "%s exists, skipping step".printf (expanded));
                return;
            }
        }

        switch (step.step_type) {
            case "task":
                if (step.command == "create_prefix") {
                    var pfx = vars.has_key ("PREFIX") ? vars["PREFIX"] : "";
                    var drive_c = pfx != "" ? Path.build_filename (pfx, "drive_c") : "";
                    if (drive_c != "" && FileUtils.test (drive_c, FileTest.EXISTS)) {
                        logger.typed (LogType.SKIP, "wine prefix already exists: %s".printf (pfx));
                        break;
                    }
                    create_wine_prefix (paths, env, logger, cancellable);
                } else {
                    throw new IOError.FAILED ("Unknown task: %s", step.command);
                }
                break;

            case "wineexec":
                run_wineexec_step (step, vars, paths, env, logger, cancellable);
                break;

            case "copy":
                var src = expand_path (step.src, vars);
                var dst = expand_path (step.dst, vars);
                logger.typed (LogType.COPY, "%s -> %s".printf (src, dst));
                Utils.copy_path (src, dst, null);
                break;

            case "write":
                run_write_step (step, vars, logger);
                break;

            case "xml_upsert":
                run_xml_upsert_step (step, vars, logger);
                break;

            case "text_upsert":
                run_text_upsert_step (step, vars, logger);
                break;

            case "link":
                run_link_step (step, vars, logger);
                break;

            case "redist":
                var redist_opts = build_redist_options (
                    vars.has_key ("PREFIX") ? vars["PREFIX"] : "",
                    paths,
                    env,
                    cancellable
                );
                install_redist (step.command, redist_opts, logger);
                break;

            case "extract":
                var src = expand_path (step.src, vars);
                var dst = expand_path (step.dst, vars);
                logger.typed (LogType.EXTRACT, "%s -> %s".printf (src, dst));
                Utils.extract_archive (src, dst);
                verify_step_paths (step.verify_paths, vars);
                break;

            case "extract_multi":
                run_extract_multi_step (step, vars, logger);
                break;

            case "fonts":
                install_fonts_step (step, vars, paths, env, logger, cancellable);
                break;

            case "cabextract":
                var cab_src = expand_path (step.src, vars);
                var cab_filter = step.args.size > 0 ? step.args[0] : "";
                var cab_dst = expand_path (step.dst, vars);
                if (!FileUtils.test (cab_src, FileTest.EXISTS) || Utils.file_size_or_zero (cab_src) <= 0) {
                    throw new IOError.FAILED ("cabextract source missing or empty: %s", cab_src);
                }
                logger.typed (LogType.CABEXTRACT, "%s -> %s".printf (Path.get_basename (cab_src), cab_dst));
                cabextract_file (cab_src, cab_filter, cab_dst, logger);
                break;

            case "dll_override":
                logger.typed (LogType.DLL_OVERRIDE, "%s=%s".printf (step.command, step.mode));
                set_dll_override (
                    build_redist_options (
                        vars.has_key ("PREFIX") ? vars["PREFIX"] : "",
                        paths, env, cancellable
                    ),
                    step.command, step.mode, logger
                );
                break;

            default:
                throw new IOError.FAILED ("Unknown install step type: %s", step.step_type);
        }
    }

    private void run_write_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        var content = Utils.expand_vars (step.content, vars);
        Utils.ensure_dir (Path.get_dirname (dst));
        FileUtils.set_contents (dst, content);
        logger.typed (LogType.COPY, "wrote %s".printf (dst));
        verify_step_paths (step.verify_paths, vars);
    }

    private void run_text_upsert_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        Utils.ensure_dir (Path.get_dirname (dst));

        string existing = "";
        if (FileUtils.test (dst, FileTest.EXISTS)) {
            FileUtils.get_contents (dst, out existing);
        }

        var content = Utils.expand_vars (step.content, vars);
        if (content == "") {
            content = build_text_block_from_args (step.args, vars);
        }
        if (content == "") {
            throw new IOError.FAILED ("text_upsert requires content or args");
        }

        var normalized_existing = normalize_text_block (existing);
        var normalized_content = normalize_text_block (content);
        if (normalized_existing.contains (normalized_content)) {
            logger.typed (LogType.SKIP, "text already exists in %s".printf (dst));
            verify_step_paths (step.verify_paths, vars);
            return;
        }

        var newline = detect_newline_style (existing);
        string output;
        if (step.mode == "append") {
            output = ensure_trailing_newline (normalize_newlines (existing), newline)
                + ensure_trailing_newline (normalize_newlines (content), newline);
        } else {
            output = ensure_trailing_newline (normalize_newlines (content), newline)
                + ensure_trailing_newline (normalize_newlines (existing), newline);
        }

        FileUtils.set_contents (dst, output);
        logger.typed (LogType.COPY, "upserted text in %s".printf (dst));
        verify_step_paths (step.verify_paths, vars);
    }

    private string build_text_block_from_args (
        Gee.ArrayList<string> args,
        Gee.HashMap<string, string> vars
    ) {
        var lines = new Gee.ArrayList<string> ();
        foreach (var arg in args) {
            lines.add (Utils.expand_vars (arg, vars));
        }
        if (lines.size == 0) return "";
        return string.joinv ("\n", Utils.arraylist_to_strv (lines));
    }

    private string normalize_text_block (string value) {
        return normalize_newlines (value).strip ();
    }

    private string normalize_newlines (string value) {
        return value.replace ("\r\n", "\n").replace ("\r", "\n");
    }

    private string detect_newline_style (string existing) {
        if (existing.contains ("\r\n")) return "\r\n";
        return "\r\n";
    }

    private string ensure_trailing_newline (string value, string newline) {
        if (value == "") return "";
        var normalized = normalize_newlines (value);
        if (!normalized.has_suffix ("\n")) normalized += "\n";
        return normalized.replace ("\n", newline);
    }

    private void run_xml_upsert_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        var root_name = step.root.strip ();
        var element_name = step.element.strip ();
        if (root_name == "" || element_name == "") {
            throw new IOError.FAILED ("xml_upsert requires root and element");
        }

        Utils.ensure_dir (Path.get_dirname (dst));

        Xml.Doc* doc;
        Xml.Node* root;
        if (FileUtils.test (dst, FileTest.EXISTS)) {
            doc = Xml.Parser.parse_file (dst);
            if (doc == null) {
                throw new IOError.FAILED ("Failed to parse XML file: %s", dst);
            }
            root = doc->get_root_element ();
            if (root == null) {
                throw new IOError.FAILED ("XML file has no root element: %s", dst);
            }
            if (root->name != root_name) {
                throw new IOError.FAILED ("XML root mismatch in %s: expected %s, got %s", dst, root_name, root->name);
            }
        } else {
            doc = new Xml.Doc ("1.0");
            root = doc->new_node (null, root_name);
            doc->set_root_element (root);
        }

        var target = find_matching_xml_child (root, element_name, step.match, vars);
        if (target == null) {
            if (!step.create_if_missing) {
                throw new IOError.FAILED ("XML element not found: %s", element_name);
            }
            target = root->new_child (null, element_name, null);
            foreach (var entry in step.match.entries) {
                target->set_prop (entry.key, Utils.expand_vars (entry.value, vars));
            }
        }

        foreach (var entry in step.children.entries) {
            var value = Utils.expand_vars (entry.value, vars);
            var child = find_xml_element_child (target, entry.key);
            if (child == null) {
                target->new_text_child (null, entry.key, value);
            } else if (step.overwrite_existing) {
                child->set_content (value);
            }
        }

        if (doc->save_format_file (dst, 1) < 0) {
            throw new IOError.FAILED ("Failed to write XML file: %s", dst);
        }
        logger.typed (LogType.COPY, "updated XML %s".printf (dst));
        verify_step_paths (step.verify_paths, vars);
    }

    private Xml.Node* find_matching_xml_child (
        Xml.Node* root,
        string element_name,
        Gee.HashMap<string, string> match,
        Gee.HashMap<string, string> vars
    ) {
        for (Xml.Node* child = root->children; child != null; child = child->next) {
            if (child->type != Xml.ElementType.ELEMENT_NODE || child->name != element_name) continue;
            bool matched = true;
            foreach (var entry in match.entries) {
                var expected = Utils.expand_vars (entry.value, vars);
                var actual = child->get_prop (entry.key);
                if (actual == null || actual != expected) {
                    matched = false;
                    break;
                }
            }
            if (matched) return child;
        }
        return null;
    }

    private Xml.Node* find_xml_element_child (Xml.Node* parent, string name) {
        for (Xml.Node* child = parent->children; child != null; child = child->next) {
            if (child->type == Xml.ElementType.ELEMENT_NODE && child->name == name) return child;
        }
        return null;
    }

    private void run_wineexec_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var raw_exe = expand_path (step.command, vars);
        bool is_builtin_command = is_builtin_wine_command (raw_exe);
        bool is_msiexec = raw_exe == "msiexec";
        string? host_exe = null;
        var exe = raw_exe;
        if (!is_builtin_command) {
            host_exe = normalize_wineexec_host_path (raw_exe, vars);
            exe = to_wine_path (vars["PREFIX"], host_exe);
        }
        var expanded_args = new Gee.ArrayList<string> ();
        for (int i = 0; i < step.args.size; i++) {
            expanded_args.add (expand_path (step.args[i], vars));
        }
        if (is_msiexec && !has_msiexec_logging_flag (expanded_args) && logger.is_disk_enabled ()) {
            var msi_log_path = create_msiexec_log_path (step, vars);
            expanded_args.add ("/l*v");
            expanded_args.add (msi_log_path);
            logger.typed (LogType.WINEEXEC, "msi_log=%s".printf (msi_log_path));
        }
        var args = new string[expanded_args.size + 1];
        args[0] = exe;
        for (int i = 0; i < expanded_args.size; i++) {
            args[i + 1] = expanded_args[i];
        }
        var working = step.working_dir != ""
            ? normalize_wineexec_host_path (expand_path (step.working_dir, vars), vars)
            : null;

        logger.typed (LogType.WINEEXEC, "exe=%s".printf (raw_exe));
        if (host_exe != null) {
            logger.typed (LogType.WINEEXEC, "resolved_exe=%s".printf (host_exe));
        }
        for (int i = 0; i < expanded_args.size; i++) {
            logger.typed (LogType.WINEEXEC, "arg[%d]=%s".printf (i, expanded_args[i]));
        }
        if (working != null) logger.typed (LogType.WINEEXEC, "cwd=%s".printf (working));

        if (!is_builtin_command) {
            if (host_exe == null || !FileUtils.test (host_exe, FileTest.EXISTS)) {
                throw new IOError.FAILED ("wineexec: exe not found on host: %s", host_exe ?? raw_exe);
            }
        }
        validate_wineexec_file_args (args, logger);

        try {
            run_wine_command (paths.wine, args, env, working, logger, cancellable);
        } catch (Error e) {
            if (e is IOError.CANCELLED) throw e;
            bool all_verified = verify_paths_with_logging (step.verify_paths, vars, logger);
            if (!all_verified && is_msiexec) {
                logger.typed (LogType.WARN, "msiexec failed; retrying once after wineserver shutdown");
                shutdown_wineserver (paths, env, logger);
                Thread.usleep (750000);
                try {
                    run_wine_command (paths.wine, args, env, working, logger, cancellable);
                } catch (Error retry_e) {
                    if (retry_e is IOError.CANCELLED) throw retry_e;
                    all_verified = verify_paths_with_logging (step.verify_paths, vars, logger);
                    if (!all_verified) throw retry_e;
                    logger.typed (LogType.WARN, "retry failed (exit non-zero) but verify_paths all exist, continuing");
                    return;
                }
            }
            if (!all_verified) {
                all_verified = verify_paths_with_logging (step.verify_paths, vars, logger);
            }
            if (!all_verified) throw e;
            logger.typed (LogType.WARN, "command failed (exit non-zero) but verify_paths all exist, continuing");
        }
    }

    private void validate_wineexec_file_args (string[] args, RuntimeLog logger) throws Error {
        foreach (var arg in args) {
            if (arg == null || !arg.has_prefix ("/")) continue;
            if (!arg.has_suffix (".msi") && !arg.has_suffix (".exe") && !arg.has_suffix (".reg")) continue;
            if (FileUtils.test (arg, FileTest.EXISTS)) continue;

            logger.typed (LogType.ERROR, "file argument does not exist: %s".printf (arg));
            var parent = Path.get_dirname (arg);
            if (FileUtils.test (parent, FileTest.IS_DIR)) {
                logger.typed (LogType.DEBUG, "contents of %s:".printf (parent));
                try {
                    var dir = Dir.open (parent);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        logger.emit_line ("  %s\n".printf (name));
                    }
                } catch (FileError fe) {
                    logger.emit_line ("  (could not list: %s)\n".printf (fe.message));
                }
            } else {
                logger.typed (LogType.DEBUG, "parent directory does not exist: %s".printf (parent));
            }
            throw new IOError.FAILED ("wineexec: file argument not found: %s", arg);
        }
    }

    private void run_link_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        Utils.ensure_dir (dst);
        var mode = step.mode != "" ? step.mode : "symlink";
        foreach (var raw in step.args) {
            var src = expand_path (raw, vars);
            var name = Path.get_basename (src);
            var target = Path.build_filename (dst, name);
            if (FileUtils.test (target, FileTest.EXISTS) || FileUtils.test (target, FileTest.IS_SYMLINK)) {
                logger.typed (LogType.LINK, "%s already exists, replacing".printf (target));
                FileUtils.remove (target);
            }
            var src_exists = FileUtils.test (src, FileTest.EXISTS);
            logger.typed (LogType.LINK, "%s %s -> %s (source %s)".printf (
                mode, src, target, src_exists ? "exists" : "MISSING"));
            if (!src_exists) {
                throw new IOError.FAILED ("Link source missing: %s", src);
            }
            if (mode == "hardlink") {
                if (Posix.link (src, target) != 0) {
                    throw new IOError.FAILED (
                        "Hardlink failed: %s -> %s: %s",
                        src, target, Posix.strerror (Posix.errno)
                    );
                }
            } else {
                FileUtils.symlink (src, target);
            }
        }
    }

    private void run_extract_multi_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        var volumes = new Gee.ArrayList<string> ();

        if (step.src != "") {
            volumes.add (expand_path (step.src, vars));
        }
        foreach (var arg in step.args) {
            volumes.add (expand_path (arg, vars));
        }
        if (volumes.size == 0) {
            throw new IOError.FAILED ("extract_multi requires at least one source volume");
        }

        foreach (var vol in volumes) {
            if (!FileUtils.test (vol, FileTest.EXISTS) || Utils.file_size_or_zero (vol) <= 0) {
                throw new IOError.FAILED ("extract_multi volume missing or empty: %s", vol);
            }
            logger.typed (LogType.EXTRACT, "volume: %s".printf (vol));
        }

        logger.typed (LogType.EXTRACT, "multi-volume -> %s".printf (dst));
        Utils.extract_archive_multi (Utils.arraylist_to_strv (volumes), dst);
        verify_step_paths (step.verify_paths, vars);
    }

    private void install_fonts_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var fonts_dir = expand_path (step.dst, vars);
        Utils.ensure_dir (fonts_dir);

        var tmp_dir = DirUtils.make_tmp ("fonts-XXXXXX");
        int packages_processed = 0;
        int fonts_copied_total = 0;

        foreach (var raw_path in step.args) {
            packages_processed++;
            var exe_path = expand_path (raw_path, vars);
            var basename = Path.get_basename (exe_path).replace (".exe", "");
            var extract_dir = Path.build_filename (tmp_dir, basename);
            Utils.ensure_dir (extract_dir);

            logger.typed (LogType.FONTS, "extracting %s".printf (Path.get_basename (exe_path)));
            Utils.extract_archive (exe_path, extract_dir);

            bool copied_any = false;
            try {
                var dir = Dir.open (extract_dir);
                string? name;
                while ((name = dir.read_name ()) != null) {
                    if (!name.down ().has_suffix (".ttf")) continue;
                    var src = Path.build_filename (extract_dir, name);
                    var dst = Path.build_filename (fonts_dir, name.down ());
                    uint8[] data;
                    FileUtils.get_data (src, out data);
                    FileUtils.set_data (dst, data);
                    copied_any = true;
                    fonts_copied_total++;
                    logger.typed (LogType.FONTS, "copied %s".printf (dst));
                }
            } catch (Error e) {
                logger.typed (LogType.FONTS, "warning: %s".printf (e.message));
            }

            if (!copied_any) {
                throw new IOError.FAILED ("No .ttf files found in extracted font package: %s", exe_path);
            }
        }

        register_fonts_into_prefix (fonts_dir, tmp_dir, step, vars, paths, env, cancellable, logger);

        Utils.remove_recursive (tmp_dir);
        logger.typed (LogType.FONTS, "summary: packages=%d, fonts_copied=%d".printf (packages_processed, fonts_copied_total));
        logger.typed (LogType.FONTS, "installed to %s".printf (fonts_dir));
    }

    private void register_fonts_into_prefix (
        string fonts_dir,
        string tmp_dir,
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        Cancellable? cancellable,
        RuntimeLog logger
    ) throws Error {
        int declared = step.font_registrations.size;
        if (declared == 0) return;

        var entries = new Gee.ArrayList<string> ();
        foreach (var raw in step.font_registrations) {
            var parts = raw.split ("|", 2);
            if (parts.length != 2) continue;
            var file = parts[0].strip ();
            var face = parts[1].strip ();
            if (file == "" || face == "") continue;
            if (!FileUtils.test (Path.build_filename (fonts_dir, file), FileTest.EXISTS)) continue;
            var lower = file.down ();
            var suffix = (lower.has_suffix (".ttf") || lower.has_suffix (".ttc")) ? " (TrueType)" : "";
            entries.add ("\"%s%s\"=\"%s\"\r\n".printf (face, suffix, file));
        }

        if (entries.size == 0) {
            logger.typed (LogType.FONTS, "no registerable fonts (0/%d declared)".printf (declared));
            return;
        }

        string[] sections = {
            "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts",
            "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Fonts"
        };

        var payload = new StringBuilder ("REGEDIT4\r\n\r\n");
        foreach (var section in sections) {
            payload.append ("[%s]\r\n".printf (section));
            foreach (var line in entries) payload.append (line);
            payload.append ("\r\n");
        }

        var reg_path = Path.build_filename (tmp_dir, "fonts.reg");
        FileUtils.set_contents (reg_path, payload.str);

        var pfx = vars.has_key ("PREFIX") ? vars["PREFIX"] : "";
        wine_reg (
            build_redist_options (pfx, paths, env, cancellable),
            { "import", reg_path },
            logger
        );

        logger.typed (LogType.FONTS, "registered %d/%d font(s)".printf (entries.size, declared));
    }

    private bool evaluate_condition (string condition, WineEnv env, RuntimeLog logger) {
        if (condition.has_prefix ("arch:")) {
            var expected = condition.substring (5).down ().strip ();
            var actual_arch = env.get_var ("WINEARCH") ?? "win64";
            var norm = (actual_arch == "win32") ? "win32" : "win64";
            return norm == expected;
        }
        logger.typed (LogType.WARN, "Unknown condition: %s; skipping step".printf (condition));
        return false;
    }

    private void cabextract_file (string archive, string cab_filter, string dest, RuntimeLog logger) throws Error {
        var decomp = new MsPack.CabDecompressor ();

        var cab = decomp.search (archive);
        if (cab == null) {
            cab = decomp.open (archive);
        }
        if (cab == null) {
            throw new IOError.FAILED ("mspack: cannot open %s (error %d)", archive, decomp.last_error ());
        }

        var filter_normalized = cab_filter.down ().replace ("\\", "/");
        unowned MsPack.CabFile? match = null;
        uint expected_length = 0;
        int cab_count = 0;
        int file_count = 0;

        for (unowned var c = cab; c != null; c = c.get_next ()) {
            cab_count++;
            for (unowned var f = c.get_files (); f != null; f = f.get_next ()) {
                file_count++;
                var fname = f.get_filename ();
                if (fname == null) continue;
                var fname_normalized = fname.down ().replace ("\\", "/");
                if (fname_normalized == filter_normalized
                    || fname_normalized.has_suffix ("/" + filter_normalized)) {
                    match = f;
                    expected_length = f.get_length ();
                    break;
                }
            }
            if (match != null) break;
        }

        if (match == null) {
            logger.typed (LogType.MSPACK, "filter: %s".printf (filter_normalized));
            logger.typed (LogType.MSPACK, "scanned %d cab(s), %d file(s) in %s".printf (cab_count, file_count, Path.get_basename (archive)));
            int shown = 0;
            for (unowned var c = cab; c != null; c = c.get_next ()) {
                for (unowned var f = c.get_files (); f != null; f = f.get_next ()) {
                    var fname = f.get_filename ();
                    if (fname != null) {
                        logger.typed (LogType.MSPACK, "  %s".printf (fname));
                    }
                    shown++;
                    if (shown >= 50) {
                        logger.typed (LogType.MSPACK, "  ... (%d more)".printf (file_count - shown));
                        break;
                    }
                }
                if (shown >= 50) break;
            }
            decomp.close (cab);
            throw new IOError.FAILED ("mspack: %s not found in %s", cab_filter, archive);
        }

        Utils.ensure_dir (Path.get_dirname (dest));

        if (FileUtils.test (dest, FileTest.EXISTS) || FileUtils.test (dest, FileTest.IS_SYMLINK)) {
            if (FileUtils.unlink (dest) != 0 && FileUtils.test (dest, FileTest.EXISTS)) {
                logger.typed (LogType.WARN, "mspack: could not unlink %s before extract".printf (dest));
            }
        }

        int r = decomp.extract (match, dest);
        decomp.close (cab);

        if (r != MsPack.ERR_OK) {
            throw new IOError.FAILED ("mspack: extract failed for %s (error %d)", cab_filter, r);
        }

        int64 dest_size = Utils.file_size_or_zero (dest);
        logger.typed (LogType.MSPACK, "extracted %lld bytes to %s (expected %u)".printf (dest_size, dest, expected_length));

        if (dest_size <= 0) {
            throw new IOError.FAILED ("mspack: extract produced empty/missing %s", dest);
        }
        if (expected_length > 0 && dest_size != (int64) expected_length) {
            throw new IOError.FAILED (
                "mspack: size mismatch for %s (got %lld, expected %u)",
                dest, dest_size, expected_length
            );
        }
    }

    private Gee.HashMap<string, string> build_prefix_vars (
        string pfx_path,
        string cache_path,
        Gee.HashMap<string, string>? spec_vars
    ) {
        var vars = new Gee.HashMap<string, string> ();
        vars["CACHE_BASE"] = Utils.cache_dir ();
        vars["CACHE_REDIST"] = Path.build_filename (Utils.cache_dir (), "redist");
        vars["CACHE"] = cache_path;
        vars["PREFIX"] = pfx_path;
        vars["WINDOWS"] = Path.build_filename (pfx_path, "drive_c", "windows");
        vars["SYSTEM32"] = Path.build_filename (pfx_path, "drive_c", "windows", "system32");
        vars["SYSWOW64"] = Path.build_filename (pfx_path, "drive_c", "windows", "syswow64");
        vars["FONTS"] = Path.build_filename (pfx_path, "drive_c", "windows", "Fonts");
        if (spec_vars != null) {
            foreach (var e in spec_vars.entries) {
                vars[e.key] = e.value;
            }
        }
        return vars;
    }

    private Gee.HashMap<string, string> build_post_install_vars (
        string pfx_path,
        string cache_path,
        Models.InstallerSpec installer_spec,
        Models.LauncherSpec? launcher,
        Models.PostInstallSpec post_install_spec
    ) {
        var vars = build_prefix_vars (pfx_path, cache_path, installer_spec.variables);
        if (launcher != null) {
            foreach (var e in launcher.variables.entries) {
                vars[e.key] = e.value;
            }
        }
        foreach (var e in post_install_spec.variables.entries) {
            vars[e.key] = e.value;
        }
        return vars;
    }

    private Gee.HashMap<string, string> build_action_vars (
        string pfx_path,
        string cache_path,
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        Models.SpecAction action
    ) {
        var installer_spec = Models.InstallerSpec.load_from_resource ();
        Models.LauncherSpec? launcher = null;
        if (entry.launcher_id != "") {
            foreach (var spec in launcher_specs) {
                if (spec.id == entry.launcher_id) {
                    launcher = spec;
                    break;
                }
            }
        }
        var post_install_spec = Runtime.load_prefix_post_install_spec (entry);
        var vars = build_prefix_vars (pfx_path, cache_path, installer_spec.variables);
        if (launcher != null) {
            foreach (var e in launcher.variables.entries) vars[e.key] = e.value;
        }
        if (post_install_spec != null) {
            foreach (var e in post_install_spec.variables.entries) vars[e.key] = e.value;
        }
        foreach (var e in action.variables.entries) vars[e.key] = e.value;
        return vars;
    }

    private Models.SpecAction? find_spec_action (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        string action_id
    ) {
        foreach (var action in Runtime.list_spec_actions (entry, launcher_specs)) {
            if (action.id == action_id) return action;
        }
        return null;
    }

    private string backup_post_install_spec (
        string prefix_root,
        string source_path,
        Models.PostInstallSpec spec
    ) throws Error {
        var backup_dir = Path.build_filename (prefix_root, "lumoria", "post-install");
        Utils.ensure_dir (backup_dir);

        var token = sanitize_filename_token (spec.id != "" ? spec.id : Path.get_basename (source_path));
        if (token == "") token = "post-install";
        var backup_path = Path.build_filename (backup_dir, token + ".json");
        Utils.copy_path (source_path, backup_path);
        return backup_path;
    }

    private void update_post_install_metadata (
        Models.PrefixEntry? prefix_entry,
        Models.PostInstallSpec spec,
        string original_path,
        string original_uri,
        string backup_path,
        string status,
        RuntimeLog logger
    ) {
        if (prefix_entry == null) return;

        var metadata = prefix_entry.post_install_spec;
        if (metadata == null) metadata = new Models.PrefixPostInstallSpec ();

        if (original_path != "") metadata.original_path = original_path;
        if (original_uri != "") metadata.original_uri = original_uri;
        if (backup_path != "") metadata.backup_path = backup_path;
        metadata.spec_id = spec.id;
        metadata.name = spec.display_label ();
        metadata.last_run_status = status;
        metadata.last_run_at = new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ");
        prefix_entry.post_install_spec = metadata;

        var reg = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
        reg.update_entry (prefix_entry);
        if (!reg.save (Utils.prefix_registry_path ())) {
            logger.typed (LogType.WARN, "Failed to save post install metadata");
        }
    }

    private void check_cancelled (Cancellable? cancellable) throws IOError {
        if (cancellable != null && cancellable.is_cancelled ()) {
            throw new IOError.CANCELLED ("Installation cancelled");
        }
    }

    private void verify_step_paths (Gee.ArrayList<string> verify_paths, Gee.HashMap<string, string> vars) throws IOError {
        var missing = new Gee.ArrayList<string> ();
        foreach (var vp in verify_paths) {
            var expanded = expand_path (vp, vars);
            if (!FileUtils.test (expanded, FileTest.EXISTS)) {
                missing.add (expanded);
            }
        }
        if (missing.size > 0) {
            throw new IOError.FAILED ("Extract verify failed, missing: %s", missing[0]);
        }
    }

    private bool has_msiexec_logging_flag (Gee.ArrayList<string> args) {
        foreach (var arg in args) {
            if (arg == null) continue;
            var lower = arg.down ();
            if (lower.has_prefix ("/l")) return true;
        }
        return false;
    }

    private bool verify_paths_with_logging (
        Gee.ArrayList<string> verify_paths,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) {
        if (verify_paths.size == 0) return false;
        bool all_verified = true;
        foreach (var vp in verify_paths) {
            var expanded = expand_path (vp, vars);
            var exists = FileUtils.test (expanded, FileTest.EXISTS);
            logger.typed (LogType.VERIFY, "%s -> %s".printf (expanded, exists ? "EXISTS" : "MISSING"));
            if (!exists) all_verified = false;
        }
        return all_verified;
    }

    private string create_msiexec_log_path (Models.InstallStep step, Gee.HashMap<string, string> vars) {
        string logs_dir;
        if (vars.has_key ("PREFIX") && vars["PREFIX"] != "") {
            logs_dir = Path.build_filename (vars["PREFIX"], "logs");
        } else {
            logs_dir = Path.build_filename (Utils.cache_dir (), "install-logs");
        }
        Utils.ensure_dir (logs_dir);

        var stamp = new DateTime.now_local ().format ("%Y%m%d-%H%M%S");
        var label = sanitize_filename_token (step.description != "" ? step.description : step.command);
        if (label == "") label = "step";
        return Path.build_filename (logs_dir, "msiexec-%s-%s.log".printf (label, stamp));
    }

    private string sanitize_filename_token (string input) {
        var sb = new StringBuilder ();
        for (int i = 0; i < input.length; i++) {
            var c = input[i];
            bool keep = (c >= 'a' && c <= 'z')
                || (c >= 'A' && c <= 'Z')
                || (c >= '0' && c <= '9')
                || c == '-'
                || c == '_';
            sb.append_c (keep ? c : '_');
        }
        return sb.str;
    }

    private string expand_path (string input, Gee.HashMap<string, string> vars) {
        return Utils.expand_vars (input, vars);
    }

    private bool is_builtin_wine_command (string command) {
        switch (command) {
            case "msiexec":
            case "regedit":
            case "regsvr32":
            case "wineboot":
                return true;
            default:
                return false;
        }
    }

    private string normalize_wineexec_host_path (string value, Gee.HashMap<string, string> vars) {
        if (value == "") return value;
        if (Path.is_absolute (value)) return value;
        if (!vars.has_key ("PREFIX")) return value;

        var lower = value.down ();
        if (lower.has_prefix ("drive_c/")
            || lower.has_prefix ("drive_c\\")
            || lower.has_prefix ("c:\\")
            || lower.has_prefix ("c:/")
            || lower == "c:") {
            return resolve_host_path (value, vars["PREFIX"]);
        }

        return value;
    }

}
