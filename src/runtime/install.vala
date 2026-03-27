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
        LogFunc emit = logger.emitter ();

        try {

            logger.banner ("Lumoria Install Log", false);
            emit ("Prefix: %s\n".printf (opts.prefix_path));
            emit ("Runner: %s variant=%s version=%s\n".printf (opts.runner_id, opts.variant_id, opts.runner_version));
            emit ("Log file: %s\n\n".printf (log_path));

            var installer_spec = Models.InstallerSpec.load_from_resource ();
            Models.LauncherSpec? launcher = null;
            if (opts.launcher_id != "") {
                var launcher_specs = Models.LauncherSpec.load_all_from_resource ();
                foreach (var ls in launcher_specs) {
                    if (ls.id == opts.launcher_id) { launcher = ls; break; }
                }
            }

            var all_redist_specs = Models.RedistSpec.load_all_from_resource ();
            var resolved_redists = new Gee.ArrayList<Models.RedistSpec> ();
            var code_redists = new Gee.ArrayList<string> ();
            var requested_redists = new Gee.ArrayList<string> ();
            var seen_redists = new Gee.HashSet<string> ();

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

            int redist_downloads = 0;
            int redist_steps = 0;
            foreach (var rs in resolved_redists) {
                redist_downloads += rs.downloads.size;
                redist_steps += rs.steps.size;
            }

            int total_steps = 3
                + installer_spec.downloads.size
                + (launcher != null ? launcher.downloads.size : 0)
                + (launcher != null ? launcher.steps.size : 0)
                + redist_downloads + redist_steps
                + code_redists.size
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
            emit ("Using runner: %s %s\n".printf (runner_spec.display_label (), resolved_version));

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
                }
            );
            emit ("Runner extracted to: %s\n".printf (result.extracted_to));

            check_cancelled (cancellable);

            var paths = resolve_wine_paths (result.extracted_to, runner_spec, opts.variant_id);
            emit ("Wine binary: %s\n".printf (paths.wine));
            emit ("Wineboot: via wine wineboot\n");
            emit ("Wineserver: %s\n".printf (paths.wineserver));
            emit ("Runner root: %s\n\n".printf (paths.root));

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
                pfx_path, wine_arch, "ntsync", opts.wine_debug, false,
                Utils.Preferences.resolve_wine_wayland (opts.wine_wayland)
            );
            apply_env_overrides (env, prefs.get_runtime_env_vars ());
            if (prefix_entry != null) {
                apply_env_overrides (env, prefix_entry.runtime_env_vars);
            }

            var cache_root = Path.build_filename (Utils.cache_dir (), "installer", installer_spec.id);
            Utils.ensure_dir (cache_root);
            var vars = build_prefix_vars (pfx_path, cache_root, installer_spec.variables);

            emit ("Installer variables:\n");
            foreach (var e in vars.entries) {
                emit ("  %s = %s\n".printf (e.key, e.value));
            }
            emit ("\n");

            Gee.HashMap<string, string>? launcher_vars = null;
            if (launcher != null) {
                var launcher_cache = Path.build_filename (Utils.cache_dir (), "launchers", launcher.id);
                Utils.ensure_dir (launcher_cache);
                launcher_vars = build_prefix_vars (pfx_path, launcher_cache, launcher.variables);
            }

            logger.phase ("Downloading installer artifacts");
            foreach (var dl in installer_spec.downloads) {
                check_cancelled (cancellable);

                step_idx++;
                var dest = expand_path (dl.dest, vars);

                ensure_download_item (dl, dest, step_idx, total_steps, progress, emit);
            }

            if (launcher_vars != null) {
                foreach (var rs in resolved_redists) {
                    foreach (var dl in rs.downloads) {
                        check_cancelled (cancellable);

                        step_idx++;
                        var dest = expand_path (dl.dest, launcher_vars);
                        ensure_download_item (dl, dest, step_idx, total_steps, progress, emit);
                    }
                }

                foreach (var dl in launcher.downloads) {
                    check_cancelled (cancellable);

                    step_idx++;
                    var dest = expand_path (dl.dest, launcher_vars);
                    ensure_download_item (dl, dest, step_idx, total_steps, progress, emit);
                }
            }

            logger.phase ("Predownload enabled components");
            step_idx++;
            progress.step_changed ("(%d/%d) Predownloading enabled components\u2026".printf (step_idx, total_steps));
            progress.progress_changed ((double) (step_idx - 1) / total_steps);
            logger.banner ("Predownloading enabled components");
            predownload_enabled_components (null, emit);

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
            var wine_emit = RuntimeLog.tagged_emitter (emit, LogType.WINE);
            create_wine_prefix (paths, env, wine_emit, cancellable);
            emit ("Wine prefix created at: %s\n\n".printf (pfx_path));

            logger.phase ("Apply components");
            step_idx++;
            progress.step_changed ("(%d/%d) Applying components\u2026".printf (step_idx, total_steps));
            progress.progress_changed ((double) (step_idx - 1) / total_steps);
            logger.banner ("Applying enabled components");
            string? component_warning = null;
            try {
                var comp_result = apply_enabled_components (pfx_path, prefix_entry, emit);
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
                    emit ("Seeded %d component env default(s) into prefix runtime_env_vars\n".printf (comp_env_defaults.size));
                }

                apply_env_overrides (env, prefs.get_runtime_env_vars ());
                if (prefix_entry != null) {
                    apply_env_overrides (env, prefix_entry.runtime_env_vars);
                }
            } catch (Error comp_err) {
                logger.warn ("Component application failed: %s".printf (comp_err.message));
                component_warning = "Component setup failed: %s".printf (comp_err.message);
            }

            logger.phase ("Run installer steps");
            foreach (var step in installer_spec.steps) {
                check_cancelled (cancellable);

                step_idx++;
                progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                progress.progress_changed ((double) (step_idx - 1) / total_steps);
                logger.step (step_idx, total_steps, step.description, step.step_type);

                run_install_step (step, vars, paths, env, emit, cancellable);
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
                        run_install_step (step, launcher_vars, paths, env, emit, cancellable);
                    }
                }

                foreach (var rid in code_redists) {
                    check_cancelled (cancellable);

                    step_idx++;
                    progress.step_changed ("(%d/%d) Installing %s\u2026".printf (step_idx, total_steps, rid));
                    progress.progress_changed ((double) (step_idx - 1) / total_steps);
                    logger.banner ("Redist: %s (code)".printf (rid));

                    var redist_opts = new RedistOptions ();
                    redist_opts.cache_dir = Utils.cache_dir ();
                    redist_opts.prefix_path = launcher_vars.has_key ("PREFIX") ? launcher_vars["PREFIX"] : "";
                    redist_opts.wine_arch = env.get_var ("WINEARCH") ?? "win64";
                    redist_opts.wine_bin = paths.wine;
                    redist_opts.wine_env = env;
                    redist_opts.paths = paths;
                    redist_opts.cancellable = cancellable;
                    install_redist (rid, redist_opts, emit);
                }

                foreach (var step in launcher.steps) {
                    check_cancelled (cancellable);

                    step_idx++;
                    progress.step_changed ("(%d/%d) %s".printf (step_idx, total_steps, step.description));
                    progress.progress_changed ((double) (step_idx - 1) / total_steps);
                    logger.step (step_idx, total_steps, step.description, step.step_type);
                    run_install_step (step, launcher_vars, paths, env, emit, cancellable);
                }
            }

            shutdown_wineserver (paths, env, wine_emit);
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
            emit ("%s\n".printf (e.message));
            progress.install_finished (false, "Installation cancelled.");
        } catch (Error e) {
            logger.banner ("INSTALL FAILED");
            emit ("%s\n".printf (e.message));
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
        LogFunc emit
    ) throws Error {
        Utils.ensure_dir (Path.get_dirname (dest));
        progress.step_changed ("(%d/%d) Downloading %s\u2026".printf (step_idx, total_steps, dl.id));

        if (download_item_is_valid (dl, dest, emit)) {
            progress.progress_changed ((double) step_idx / total_steps);
            RuntimeLog.emit_typed (emit, LogType.CACHED, dest);
            return;
        }

        var s_base = (double) (step_idx - 1) / total_steps;
        var s_range = 1.0 / total_steps;
        emit ("Downloading: %s\n  -> %s\n".printf (dl.url, dest));
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
        RuntimeLog.emit_typed (emit, LogType.DONE, dl.id);
    }

    private bool download_item_is_valid (Models.DownloadItem dl, string path, LogFunc emit) {
        if (!FileUtils.test (path, FileTest.EXISTS)) return false;

        if (dl.sha256 == "") {
            RuntimeLog.emit_typed (emit, LogType.WARN, "%s has no checksum; using size-only cache validation".printf (dl.id));
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
        LogFunc emit,
        Cancellable? cancellable = null
    ) throws Error {
        check_cancelled (cancellable);

        if (step.condition != "") {
            if (!evaluate_condition (step.condition, env)) {
                RuntimeLog.emit_typed (emit, LogType.SKIP, "condition '%s' not met".printf (step.condition));
                return;
            }
        }

        foreach (var skip in step.skip_if_exists) {
            var expanded = expand_path (skip, vars);
            if (FileUtils.test (expanded, FileTest.EXISTS)) {
                RuntimeLog.emit_typed (emit, LogType.SKIP, "%s exists, skipping step".printf (expanded));
                return;
            }
        }

        switch (step.step_type) {
            case "task":
                if (step.command == "create_prefix") {
                    var pfx = vars.has_key ("PREFIX") ? vars["PREFIX"] : "";
                    var drive_c = pfx != "" ? Path.build_filename (pfx, "drive_c") : "";
                    if (drive_c != "" && FileUtils.test (drive_c, FileTest.EXISTS)) {
                        RuntimeLog.emit_typed (emit, LogType.SKIP, "wine prefix already exists: %s".printf (pfx));
                        break;
                    }
                    create_wine_prefix (paths, env, emit, cancellable);
                } else {
                    throw new IOError.FAILED ("Unknown task: %s", step.command);
                }
                break;

            case "wineexec":
                run_wineexec_step (step, vars, paths, env, emit, cancellable);
                break;

            case "copy":
                var src = expand_path (step.src, vars);
                var dst = expand_path (step.dst, vars);
                RuntimeLog.emit_typed (emit, LogType.COPY, "%s -> %s".printf (src, dst));
                Utils.copy_path (src, dst, null);
                break;

            case "link":
                run_link_step (step, vars, emit);
                break;

            case "redist":
                var redist_opts = new RedistOptions ();
                redist_opts.cache_dir = Utils.cache_dir ();
                redist_opts.prefix_path = vars.has_key ("PREFIX") ? vars["PREFIX"] : "";
                redist_opts.wine_arch = env.get_var ("WINEARCH") ?? "win64";
                redist_opts.wine_bin = paths.wine;
                redist_opts.wine_env = env;
                redist_opts.paths = paths;
                redist_opts.cancellable = cancellable;
                install_redist (step.command, redist_opts, emit);
                break;

            case "extract":
                var src = expand_path (step.src, vars);
                var dst = expand_path (step.dst, vars);
                RuntimeLog.emit_typed (emit, LogType.EXTRACT, "%s -> %s".printf (src, dst));
                Utils.extract_archive (src, dst);
                verify_step_paths (step.verify_paths, vars);
                break;

            case "extract_multi":
                run_extract_multi_step (step, vars, emit);
                break;

            case "fonts":
                install_fonts_step (step, vars, paths, env, emit, cancellable);
                break;

            case "cabextract":
                var cab_src = expand_path (step.src, vars);
                var cab_filter = step.args.size > 0 ? step.args[0] : "";
                var cab_dst = expand_path (step.dst, vars);
                if (!FileUtils.test (cab_src, FileTest.EXISTS) || Utils.file_size_or_zero (cab_src) <= 0) {
                    throw new IOError.FAILED ("cabextract source missing or empty: %s", cab_src);
                }
                RuntimeLog.emit_typed (emit, LogType.CABEXTRACT, "%s -> %s".printf (Path.get_basename (cab_src), cab_dst));
                cabextract_file (cab_src, cab_filter, cab_dst, emit);
                break;

            case "dll_override":
                var dll = step.command;
                var mode = step.mode;
                RuntimeLog.emit_typed (emit, LogType.DLL_OVERRIDE, "%s=%s".printf (dll, mode));
                try {
                    run_wine_command (paths.wine,
                        { "reg", "add", "HKCU\\Software\\Wine\\DllOverrides",
                          "/v", dll, "/t", "REG_SZ", "/d", mode, "/f" },
                        env, null, emit, cancellable);
                } catch (Error e) {
                    warning ("DLL override reg command failed: %s", e.message);
                }
                break;

            default:
                throw new IOError.FAILED ("Unknown install step type: %s", step.step_type);
        }
    }

    private void run_wineexec_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        LogFunc emit,
        Cancellable? cancellable
    ) throws Error {
        var exe = expand_path (step.command, vars);
        bool is_msiexec = exe == "msiexec";
        var expanded_args = new Gee.ArrayList<string> ();
        for (int i = 0; i < step.args.size; i++) {
            expanded_args.add (expand_path (step.args[i], vars));
        }
        if (is_msiexec && !has_msiexec_logging_flag (expanded_args)) {
            var msi_log_path = create_msiexec_log_path (step, vars);
            expanded_args.add ("/l*v");
            expanded_args.add (msi_log_path);
            RuntimeLog.emit_typed (emit, LogType.WINEEXEC, "msi_log=%s".printf (msi_log_path));
        }
        var args = new string[expanded_args.size + 1];
        args[0] = exe;
        for (int i = 0; i < expanded_args.size; i++) {
            args[i + 1] = expanded_args[i];
        }
        var working = step.working_dir != "" ? expand_path (step.working_dir, vars) : null;

        RuntimeLog.emit_typed (emit, LogType.WINEEXEC, "exe=%s".printf (exe));
        for (int i = 0; i < expanded_args.size; i++) {
            RuntimeLog.emit_typed (emit, LogType.WINEEXEC, "arg[%d]=%s".printf (i, expanded_args[i]));
        }
        if (working != null) RuntimeLog.emit_typed (emit, LogType.WINEEXEC, "cwd=%s".printf (working));

        if (exe != "msiexec" && exe != "regedit" && exe != "regsvr32" && exe != "wineboot") {
            if (!FileUtils.test (exe, FileTest.EXISTS)) {
                throw new IOError.FAILED ("wineexec: exe not found on host: %s", exe);
            }
        }
        validate_wineexec_file_args (args, emit);

        try {
            run_wine_command (paths.wine, args, env, working, emit, cancellable);
        } catch (Error e) {
            if (e is IOError.CANCELLED) throw e;
            bool all_verified = verify_paths_with_logging (step.verify_paths, vars, emit);
            if (!all_verified && is_msiexec) {
                RuntimeLog.emit_typed (emit, LogType.WARN, "msiexec failed; retrying once after wineserver shutdown");
                shutdown_wineserver (paths, env, emit);
                Thread.usleep (750000);
                try {
                    run_wine_command (paths.wine, args, env, working, emit, cancellable);
                } catch (Error retry_e) {
                    if (retry_e is IOError.CANCELLED) throw retry_e;
                    all_verified = verify_paths_with_logging (step.verify_paths, vars, emit);
                    if (!all_verified) throw retry_e;
                    RuntimeLog.emit_typed (emit, LogType.WARN, "retry failed (exit non-zero) but verify_paths all exist, continuing");
                    return;
                }
            }
            if (!all_verified) {
                all_verified = verify_paths_with_logging (step.verify_paths, vars, emit);
            }
            if (!all_verified) throw e;
            RuntimeLog.emit_typed (emit, LogType.WARN, "command failed (exit non-zero) but verify_paths all exist, continuing");
        }
    }

    private void validate_wineexec_file_args (string[] args, LogFunc emit) throws Error {
        foreach (var arg in args) {
            if (arg == null || !arg.has_prefix ("/")) continue;
            if (!arg.has_suffix (".msi") && !arg.has_suffix (".exe") && !arg.has_suffix (".reg")) continue;
            if (FileUtils.test (arg, FileTest.EXISTS)) continue;

            RuntimeLog.emit_typed (emit, LogType.ERROR, "file argument does not exist: %s".printf (arg));
            var parent = Path.get_dirname (arg);
            if (FileUtils.test (parent, FileTest.IS_DIR)) {
                RuntimeLog.emit_typed (emit, LogType.DEBUG, "contents of %s:".printf (parent));
                try {
                    var dir = Dir.open (parent);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        emit ("  %s\n".printf (name));
                    }
                } catch (FileError fe) {
                    emit ("  (could not list: %s)\n".printf (fe.message));
                }
            } else {
                RuntimeLog.emit_typed (emit, LogType.DEBUG, "parent directory does not exist: %s".printf (parent));
            }
            throw new IOError.FAILED ("wineexec: file argument not found: %s", arg);
        }
    }

    private void run_link_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        LogFunc emit
    ) throws Error {
        var dst = expand_path (step.dst, vars);
        Utils.ensure_dir (dst);
        var mode = step.mode != "" ? step.mode : "symlink";
        foreach (var raw in step.args) {
            var src = expand_path (raw, vars);
            var name = Path.get_basename (src);
            var target = Path.build_filename (dst, name);
            if (FileUtils.test (target, FileTest.EXISTS) || FileUtils.test (target, FileTest.IS_SYMLINK)) {
                RuntimeLog.emit_typed (emit, LogType.LINK, "%s already exists, replacing".printf (target));
                FileUtils.remove (target);
            }
            var src_exists = FileUtils.test (src, FileTest.EXISTS);
            RuntimeLog.emit_typed (emit, LogType.LINK, "%s %s -> %s (source %s)".printf (
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
        LogFunc emit
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
            RuntimeLog.emit_typed (emit, LogType.EXTRACT, "volume: %s".printf (vol));
        }

        RuntimeLog.emit_typed (emit, LogType.EXTRACT, "multi-volume -> %s".printf (dst));
        Utils.extract_archive_multi (Utils.arraylist_to_strv (volumes), dst);
        verify_step_paths (step.verify_paths, vars);
    }

    private void install_fonts_step (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        WinePaths paths,
        WineEnv env,
        LogFunc emit,
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

            RuntimeLog.emit_typed (emit, LogType.FONTS, "extracting %s".printf (Path.get_basename (exe_path)));
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
                    RuntimeLog.emit_typed (emit, LogType.FONTS, "copied %s".printf (dst));
                }
            } catch (Error e) {
                RuntimeLog.emit_typed (emit, LogType.FONTS, "warning: %s".printf (e.message));
            }

            if (!copied_any) {
                throw new IOError.FAILED ("No .ttf files found in extracted font package: %s", exe_path);
            }
        }

        Utils.remove_recursive (tmp_dir);
        RuntimeLog.emit_typed (
            emit,
            LogType.FONTS,
            "summary: packages=%d, fonts_copied=%d".printf (packages_processed, fonts_copied_total)
        );
        RuntimeLog.emit_typed (emit, LogType.FONTS, "installed to %s".printf (fonts_dir));
    }

    private bool evaluate_condition (string condition, WineEnv env) {
        if (condition.has_prefix ("arch:")) {
            var expected = condition.substring (5).down ().strip ();
            var actual_arch = env.get_var ("WINEARCH") ?? "win64";
            var norm = (actual_arch == "win32") ? "win32" : "win64";
            return norm == expected;
        }
        warning ("Unknown condition: %s — skipping step", condition);
        return false;
    }

    private void cabextract_file (string archive, string cab_filter, string dest, LogFunc? emit) throws Error {
        var decomp = new MsPack.CabDecompressor ();

        var cab = decomp.search (archive);
        if (cab == null) {
            cab = decomp.open (archive);
        }
        if (cab == null) {
            throw new IOError.FAILED ("mspack: cannot open %s (error %d)", archive, decomp.last_error ());
        }

        var filter_normalized = cab_filter.down ().replace ("\\", "/");
        var filter_basename = Path.get_basename (filter_normalized);
        unowned MsPack.CabFile? match = null;
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
                    || fname_normalized.has_suffix ("/" + filter_normalized)
                    || fname_normalized.has_suffix ("/" + filter_basename)) {
                    match = f;
                    break;
                }
            }
            if (match != null) break;
        }

        if (match == null) {
            if (emit != null) {
                RuntimeLog.emit_typed (emit, LogType.MSPACK, "filter: %s".printf (filter_normalized));
                RuntimeLog.emit_typed (emit, LogType.MSPACK, "scanned %d cab(s), %d file(s) in %s".printf (cab_count, file_count, Path.get_basename (archive)));
                int shown = 0;
                for (unowned var c = cab; c != null; c = c.get_next ()) {
                    for (unowned var f = c.get_files (); f != null; f = f.get_next ()) {
                        var fname = f.get_filename ();
                        if (fname != null) {
                            RuntimeLog.emit_typed (emit, LogType.MSPACK, "  %s".printf (fname));
                        }
                        shown++;
                        if (shown >= 50) {
                            RuntimeLog.emit_typed (emit, LogType.MSPACK, "  ... (%d more)".printf (file_count - shown));
                            break;
                        }
                    }
                    if (shown >= 50) break;
                }
            }
            decomp.close (cab);
            throw new IOError.FAILED ("mspack: %s not found in %s", cab_filter, archive);
        }

        var tmp_dir = DirUtils.make_tmp ("mspack-XXXXXX");
        var tmp_out = Path.build_filename (tmp_dir, Path.get_basename (cab_filter));
        int r = decomp.extract (match, tmp_out);
        decomp.close (cab);

        if (r != MsPack.ERR_OK) {
            Utils.remove_recursive (tmp_dir);
            throw new IOError.FAILED ("mspack: extract failed for %s (error %d)", cab_filter, r);
        }

        Utils.ensure_dir (Path.get_dirname (dest));
        uint8[] data;
        FileUtils.get_data (tmp_out, out data);
        FileUtils.set_data (dest, data);

        Utils.remove_recursive (tmp_dir);
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
        LogFunc emit
    ) {
        if (verify_paths.size == 0) return false;
        bool all_verified = true;
        foreach (var vp in verify_paths) {
            var expanded = expand_path (vp, vars);
            var exists = FileUtils.test (expanded, FileTest.EXISTS);
            RuntimeLog.emit_typed (emit, LogType.VERIFY, "%s -> %s".printf (expanded, exists ? "EXISTS" : "MISSING"));
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

}
