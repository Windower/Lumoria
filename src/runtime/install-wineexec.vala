namespace Lumoria.Runtime {

    internal void run_wineexec_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var vars = ctx.vars;
        var raw_exe = ctx.expand (step.command);
        bool is_builtin_command = is_builtin_wine_command (raw_exe);
        bool is_msiexec = raw_exe == "msiexec";
        string? host_exe = null;
        var exe = raw_exe;
        if (!is_builtin_command) {
            host_exe = normalize_wineexec_host_path (raw_exe, vars);
            exe = wine_arg_path (vars[VAR_PREFIX], host_exe);
        }
        var expanded_args = new Gee.ArrayList<string> ();
        for (int i = 0; i < step.args.size; i++) {
            expanded_args.add (ctx.expand (step.args[i]));
        }
        if (is_msiexec && !has_msiexec_logging_flag (expanded_args) && ctx.logger.is_disk_enabled ()) {
            var msi_log_path = create_msiexec_log_path (step, vars);
            expanded_args.add ("/l*v");
            expanded_args.add (msi_log_path);
            ctx.logger.typed (LogType.WINEEXEC, "msi_log=%s".printf (msi_log_path));
        }
        var args = new string[expanded_args.size + 1];
        args[0] = exe;
        for (int i = 0; i < expanded_args.size; i++) {
            args[i + 1] = expanded_args[i];
        }
        var working = step.working_dir != ""
            ? normalize_wineexec_host_path (ctx.expand (step.working_dir), vars)
            : null;

        ctx.logger.typed (LogType.WINEEXEC, "exe=%s".printf (raw_exe));
        if (host_exe != null) {
            ctx.logger.typed (LogType.WINEEXEC, "resolved_exe=%s".printf (host_exe));
        }
        for (int i = 0; i < expanded_args.size; i++) {
            ctx.logger.typed (LogType.WINEEXEC, "arg[%d]=%s".printf (i, expanded_args[i]));
        }
        if (working != null) ctx.logger.typed (LogType.WINEEXEC, "cwd=%s".printf (working));

        if (!is_builtin_command) {
            if (host_exe == null || !FileUtils.test (host_exe, FileTest.EXISTS)) {
                throw new LumoriaError.NOT_FOUND (
                    _("Executable not found: %s").printf (host_exe ?? raw_exe)
                );
            }
        }
        validate_wineexec_file_args (args, ctx.logger);

        try {
            run_wine_command (ctx.paths, args, ctx.env, working, ctx.logger, ctx.cancellable);
        } catch (Error e) {
            if (e is IOError.CANCELLED) throw e;
            bool all_verified = verify_paths_with_logging (step.verify_paths, vars, ctx.logger);
            if (!all_verified && is_msiexec) {
                ctx.logger.typed (LogType.WARN, "msiexec failed; retrying once after wineserver shutdown");
                try {
                    retry_wine_command_after_wineserver (
                        ctx.paths, args, ctx.env, working, ctx.logger, ctx.cancellable
                    );
                    verify_paths_with_logging (step.verify_paths, vars, ctx.logger);
                    return;
                } catch (Error retry_e) {
                    if (retry_e is IOError.CANCELLED) throw retry_e;
                    all_verified = verify_paths_with_logging (step.verify_paths, vars, ctx.logger);
                    if (!step.allow_nonzero_exit || !all_verified) throw retry_e;
                    ctx.logger.typed (LogType.WARN, "retry failed (exit non-zero) but verify_paths all exist, continuing");
                    return;
                }
            }
            if (!step.allow_nonzero_exit || !all_verified) throw e;
            ctx.logger.typed (LogType.WARN, "command failed (exit non-zero) but verify_paths all exist, continuing");
        }
    }

    internal void validate_wineexec_file_args (string[] args, RuntimeLog logger) throws Error {
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
            throw new LumoriaError.NOT_FOUND (_("File not found: %s").printf (arg));
        }
    }

    internal bool has_msiexec_logging_flag (Gee.ArrayList<string> args) {
        foreach (var arg in args) {
            if (arg == null) continue;
            var lower = arg.down ();
            if (lower.has_prefix ("/l")) return true;
        }
        return false;
    }

    internal string create_msiexec_log_path (Models.InstallStep step, Gee.HashMap<string, string> vars) {
        var logs_dir = Utils.resolve_log_dir (
            get_var (vars, VAR_PREFIX)
        );

        var stamp = Utils.log_stamp ();
        var label = Utils.sanitize_filename_token (step.description != "" ? step.description : step.command);
        if (label == "") label = "step";
        return Path.build_filename (logs_dir, "msiexec-%s-%s.log".printf (label, stamp));
    }

    internal bool is_builtin_wine_command (string command) {
        switch (command) {
            case "cmd":
            case "cmd.exe":
            case "msiexec":
            case "regedit":
            case "regsvr32":
            case "wineboot":
                return true;
            default:
                return false;
        }
    }

}
