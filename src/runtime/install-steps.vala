namespace Lumoria.Runtime {

    internal class InstallStepContext {
        public Models.InstallStep step;
        public Gee.HashMap<string, string> vars;
        public WinePaths paths;
        public WineEnv env;
        public RuntimeLog logger;
        public Cancellable? cancellable;

        public string expand (string raw) {
            return Utils.expand_vars (raw, vars);
        }

        public void remove_tree (string path) {
            if (!Utils.remove_recursive (path)) {
                logger.typed (LogType.WARN, "could not remove %s".printf (path));
            }
        }

        public string require_managed_path (string raw) throws Error {
            return require_confined_path (
                raw, vars, _("Install path escapes the prefix: %s"), true
            );
        }

        public string require_copy_src (string raw, bool allow_external) throws Error {
            var expanded = expand (raw);
            if (expanded == "") return expanded;
            var resolved = Utils.collapse_path (expanded);
            /* A trailing slash asks copy_path to merge the directory's contents into dst. */
            if (expanded.has_suffix ("/")) resolved += "/";
            if (allow_external || is_confined_path (resolved, vars, true)) return resolved;
            throw new LumoriaError.FAILED (
                _("Copy source is outside the prefix and cache: %s").printf (expanded)
            );
        }

        public string prefix {
            owned get { return get_var (vars, VAR_PREFIX); }
        }

        public string arch {
            owned get { return get_var (vars, VAR_ARCH); }
        }
    }

    internal void run_install_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        Utils.check_cancelled (ctx.cancellable);

        switch (step.step_type) {
            case Models.InstallStepKind.TASK:
                if (step.command == Models.InstallStep.TASK_CREATE_PREFIX) {
                    var pfx = ctx.prefix;
                    if (pfx != "" && wine_prefix_drive_c_exists (pfx)) {
                        ctx.logger.typed (LogType.SKIP, "wine prefix already exists: %s".printf (pfx));
                        break;
                    }
                    create_wine_prefix (ctx.paths, ctx.env, ctx.logger, ctx.cancellable);
                } else {
                    throw new LumoriaError.FAILED (_("Unknown task: %s").printf (step.command));
                }
                break;

            case Models.InstallStepKind.WINEEXEC:
                run_wineexec_step (ctx);
                break;

            case Models.InstallStepKind.COPY:
                var src = ctx.require_copy_src (step.src, step.allow_external_src);
                var dst = ctx.require_managed_path (step.dst);
                ctx.logger.typed (LogType.COPY, "%s -> %s".printf (src, dst));
                Utils.copy_path (src, dst, null, ctx.cancellable);
                break;

            case Models.InstallStepKind.RENAME:
                run_rename_step (ctx);
                break;

            case Models.InstallStepKind.DELETE:
                run_delete_step (ctx);
                break;

            case Models.InstallStepKind.WRITE:
                run_write_step (ctx);
                break;

            case Models.InstallStepKind.XML_UPSERT:
                run_xml_upsert_step (ctx);
                break;

            case Models.InstallStepKind.TEXT_UPSERT:
                run_text_upsert_step (ctx);
                break;

            case Models.InstallStepKind.LINK:
                run_link_step (ctx);
                break;

            case Models.InstallStepKind.REDIST:
                install_redist (step.command, ctx.paths, ctx.env, ctx.logger, ctx.cancellable);
                break;

            case Models.InstallStepKind.EXTRACT:
                var extract_src = ctx.expand (step.src);
                var extract_dst = ctx.require_managed_path (step.dst);
                ctx.logger.typed (LogType.EXTRACT, "%s -> %s".printf (extract_src, extract_dst));
                var only = new Gee.ArrayList<string> ();
                foreach (var arg in step.args) {
                    foreach (var glob in ctx.expand (arg).split ("\n")) {
                        if (glob.strip () != "") only.add (glob.strip ());
                    }
                }
                Utils.extract_archive (extract_src, extract_dst, only.to_array (), ctx.cancellable);
                verify_step_paths (ctx);
                break;

            case Models.InstallStepKind.EXTRACT_MULTI:
                run_extract_multi_step (ctx);
                break;

            case Models.InstallStepKind.MSI_INSTALL:
                new MsiInstaller (
                    ctx.expand (step.src),
                    ctx.prefix,
                    ctx.arch,
                    ctx.paths, ctx.env, ctx.logger, ctx.cancellable
                ).run ();
                verify_step_paths (ctx);
                break;

            case Models.InstallStepKind.FONTS:
                install_fonts_step (ctx);
                break;

            case Models.InstallStepKind.FONT_REPLACEMENT:
                install_font_replacements (ctx);
                break;

            case Models.InstallStepKind.CABEXTRACT:
                var cab_src = ctx.expand (step.src);
                var cab_filter = step.args.size > 0 ? step.args[0] : "";
                var cab_dst = ctx.require_managed_path (step.dst);
                if (!FileUtils.test (cab_src, FileTest.EXISTS) || Utils.file_size_or_zero (cab_src) <= 0) {
                    throw new LumoriaError.FAILED (_("Cabextract source is missing or empty: %s").printf (cab_src));
                }
                ctx.logger.typed (LogType.CABEXTRACT, "%s -> %s".printf (Path.get_basename (cab_src), cab_dst));
                cabextract_file (cab_src, cab_filter, cab_dst, ctx.logger, ctx.cancellable);
                break;

            case Models.InstallStepKind.DLL_OVERRIDE:
                ctx.logger.typed (LogType.DLL_OVERRIDE, "%s=%s".printf (step.command, step.mode));
                set_dll_override_in_registry (ctx.paths, ctx.env, step.command, step.mode, ctx.logger, ctx.cancellable);
                break;

            case Models.InstallStepKind.GIT:
                run_git_step (ctx);
                break;

            case Models.InstallStepKind.SET_COMPONENT_OVERRIDE:
                run_set_component_override_step (ctx);
                break;

            case Models.InstallStepKind.MANIFEST_EXTRACT:
                run_manifest_extract_step (ctx);
                break;

            case Models.InstallStepKind.MANIFEST_CACHE_CLEAR:
                run_manifest_cache_clear_step (ctx);
                break;

            case Models.InstallStepKind.MANIFEST_DOWNLOADS_CLEAR:
                run_manifest_downloads_clear_step (ctx);
                break;

            case Models.InstallStepKind.OPEN:
                run_open_step (ctx);
                break;

            default:
                throw new LumoriaError.FAILED (_("Unknown install step type: %s").printf (step.step_type.id ()));
        }
    }

    internal void run_open_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var src = ctx.expand (step.src).strip ();
        if (src == "") {
            throw new LumoriaError.FAILED (_("Open step is missing a target"));
        }
        ctx.logger.typed (LogType.CMD, src);
        current_session ().open_target (src, ctx.logger);
    }

    internal void run_write_step (InstallStepContext ctx) throws Error {
        var dst = ctx.require_managed_path (ctx.step.dst);
        var content = ctx.expand (ctx.step.content);
        Utils.write_text_atomic (dst, content);
        ctx.logger.typed (LogType.COPY, "wrote %s".printf (dst));
        verify_step_paths (ctx);
    }

    internal void run_delete_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var targets = new Gee.ArrayList<string> ();
        if (step.dst != "") targets.add (ctx.require_managed_path (step.dst));
        foreach (var raw in step.args) targets.add (ctx.require_managed_path (raw));
        if (targets.size == 0) {
            throw new LumoriaError.FAILED (_("Delete requires a destination"));
        }
        foreach (var target in targets) {
            if (!FileUtils.test (target, FileTest.EXISTS) && !FileUtils.test (target, FileTest.IS_SYMLINK)) {
                ctx.logger.typed (LogType.SKIP, "delete: %s not present".printf (target));
                continue;
            }
            var removed = FileUtils.test (target, FileTest.IS_DIR)
                ? Utils.remove_recursive (target)
                : FileUtils.remove (target) == 0;
            if (!removed) {
                throw new LumoriaError.FAILED (_("Failed to delete %s").printf (target));
            }
            ctx.logger.typed (LogType.COPY, "deleted %s".printf (target));
        }
    }

    internal void run_rename_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var src = ctx.require_managed_path (step.src);
        var dst = ctx.require_managed_path (step.dst);
        if (src == "" || dst == "") {
            throw new LumoriaError.FAILED (_("Rename requires a source and destination"));
        }
        if (!FileUtils.test (src, FileTest.EXISTS)) {
            if (step.idempotent && FileUtils.test (dst, FileTest.EXISTS)) {
                ctx.logger.typed (LogType.SKIP, "rename: target already present %s".printf (dst));
                return;
            }
            throw new LumoriaError.FAILED (_("Rename source is missing: %s").printf (src));
        }
        Utils.ensure_dir (Path.get_dirname (dst));
        if (FileUtils.test (dst, FileTest.EXISTS) || FileUtils.test (dst, FileTest.IS_SYMLINK)) {
            if (step.overwrite_existing) {
                if (FileUtils.remove (dst) != 0) {
                    throw new LumoriaError.FAILED (_("Failed to replace existing file: %s").printf (dst));
                }
            } else {
                throw new LumoriaError.FAILED (_("Rename target already exists: %s").printf (dst));
            }
        }
        if (FileUtils.rename (src, dst) != 0) {
            throw new LumoriaError.FAILED (_("Rename failed: %s -> %s").printf (src, dst));
        }
        ctx.logger.typed (LogType.COPY, "renamed %s -> %s".printf (src, dst));
        verify_step_paths (ctx);
    }

    internal void run_set_component_override_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var vars = ctx.vars;
        var component_id = step.command.strip ();
        var mode = step.mode.strip ().down ();
        if (component_id == "") {
            throw new LumoriaError.FAILED (_("Component override is missing a component id"));
        }
        if (mode == "") mode = "inherit";
        bool? enabled = null;
        switch (mode) {
            case "enable":
            case "enabled":
            case "true":
            case "on":
                enabled = true;
                break;
            case "disable":
            case "disabled":
            case "false":
            case "off":
                enabled = false;
                break;
            case "inherit":
            case "default":
                enabled = null;
                break;
            default:
                throw new LumoriaError.FAILED (_("Invalid component override mode: %s").printf (step.mode));
        }

        var pfx_path = get_var (vars, VAR_PREFIX);
        if (pfx_path == "") {
            throw new LumoriaError.FAILED (_("Component override is missing the prefix path"));
        }

        var target = current_session ().prefix_for_wine_path (pfx_path);
        if (target == null) {
            throw new LumoriaError.NOT_FOUND (_("Prefix not found for component override: %s").printf (pfx_path));
        }

        target.apply_component_enabled (component_id, enabled);
        persist_prefix (target);
        string label = target.display_name ();
        ctx.logger.typed (
            LogType.COMPONENT,
            "set_component_override: %s=%s for %s".printf (
                component_id,
                enabled == null ? "inherit" : ((bool) enabled ? "enabled" : "disabled"),
                label
            )
        );
    }

    internal void run_link_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var dst = ctx.require_managed_path (step.dst);
        Utils.ensure_dir (dst);
        var mode = step.mode != "" ? step.mode : "symlink";
        foreach (var raw in step.args) {
            var src = ctx.require_copy_src (raw, step.allow_external_src);
            var name = Path.get_basename (src);
            var target = ctx.require_managed_path (Path.build_filename (dst, name));
            if (FileUtils.test (target, FileTest.EXISTS) || FileUtils.test (target, FileTest.IS_SYMLINK)) {
                ctx.logger.typed (LogType.LINK, "%s already exists, replacing".printf (target));
            }
            var src_exists = FileUtils.test (src, FileTest.EXISTS);
            ctx.logger.typed (LogType.LINK, "%s %s -> %s (source %s)".printf (
                mode, src, target, src_exists ? "exists" : "MISSING"));
            Utils.link_file (src, target, mode, true);
        }
    }

    internal void run_git_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        Utils.check_cancelled (ctx.cancellable);
        var git_dst = ctx.require_managed_path (step.dst);
        if (git_dst == "") throw new LumoriaError.FAILED (_("Git step requires a destination"));

        var target = new Utils.GitTarget () {
            branch = ctx.expand (step.git_branch),
            tag = ctx.expand (step.git_tag),
            commit = ctx.expand (step.git_commit)
        };
        var summary = "%s%s%s%s".printf (
            git_dst,
            target.branch != "" ? " branch=" + target.branch : "",
            target.tag != "" ? " tag=" + target.tag : "",
            target.commit != "" ? " commit=" + target.commit : ""
        );

        switch (step.command) {
            case "clone":
                var git_url = ctx.expand (step.src);
                if (git_url == "") throw new LumoriaError.FAILED (_("Git clone requires a URL"));
                ctx.logger.typed (LogType.GIT, "clone %s -> %s".printf (git_url, summary));
                Utils.git_clone (git_url, git_dst, target, null, ctx.cancellable);
                break;

            case "pull":
                ctx.logger.typed (LogType.GIT, "pull %s".printf (summary));
                Utils.git_pull (git_dst, target, null, ctx.cancellable);
                break;

            default:
                throw new LumoriaError.FAILED (_("Unknown git command: %s").printf (step.command));
        }

        verify_step_paths (ctx);
    }

    internal void run_extract_multi_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var dst = ctx.require_managed_path (step.dst);
        var volumes = new Gee.ArrayList<string> ();

        if (step.src != "") {
            volumes.add (ctx.expand (step.src));
        }
        foreach (var arg in step.args) {
            volumes.add (ctx.expand (arg));
        }
        if (volumes.size == 0) {
            throw new LumoriaError.FAILED (_("Multi-volume extract requires at least one source"));
        }

        foreach (var vol in volumes) {
            if (!FileUtils.test (vol, FileTest.EXISTS) || Utils.file_size_or_zero (vol) <= 0) {
                throw new LumoriaError.FAILED (_("Extract volume is missing or empty: %s").printf (vol));
            }
            ctx.logger.typed (LogType.EXTRACT, "volume: %s".printf (vol));
        }

        ctx.logger.typed (LogType.EXTRACT, "multi-volume -> %s".printf (dst));
        Utils.extract_archive_multi (Utils.strv (volumes), dst, {}, ctx.cancellable);
        verify_step_paths (ctx);
    }

    internal void cabextract_file (
        string archive,
        string cab_filter,
        string dest,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var filter = cab_filter.down ().replace ("\\", "/");
        int claimed = 0;
        uint expected_length = 0;

        var extracted = Utils.extract_cab_entries ({ archive }, (name, size) => {
            var normalized = name.down ().replace ("\\", "/");
            if (normalized != filter && !normalized.has_suffix ("/" + filter)) return null;
            if (!AtomicInt.compare_and_exchange (ref claimed, 0, 1)) return null;

            expected_length = size;
            Utils.ensure_dir (Path.get_dirname (dest));
            if (FileUtils.unlink (dest) != 0 && FileUtils.test (dest, FileTest.EXISTS)) {
                logger.typed (LogType.WARN, "mspack: could not unlink %s before extract".printf (dest));
            }
            return dest;
        }, cancellable);

        if (extracted == 0) {
            var names = Utils.list_cab_entries (archive);
            logger.typed (LogType.MSPACK, "filter: %s".printf (filter));
            logger.typed (LogType.MSPACK, "scanned %d file(s) in %s".printf (names.size, Path.get_basename (archive)));
            for (int i = 0; i < names.size && i < 50; i++) {
                logger.typed (LogType.MSPACK, "  %s".printf (names[i]));
            }
            if (names.size > 50) {
                logger.typed (LogType.MSPACK, "  ... (%d more)".printf (names.size - 50));
            }
            throw new LumoriaError.NOT_FOUND (_("File %s was not found in %s").printf (cab_filter, archive));
        }

        int64 dest_size = Utils.file_size_or_zero (dest);
        logger.typed (LogType.MSPACK, "extracted %lld bytes to %s (expected %u)".printf (dest_size, dest, expected_length));

        if (dest_size <= 0) {
            throw new LumoriaError.FAILED (_("Extract produced an empty or missing file: %s").printf (dest));
        }
        if (expected_length > 0 && dest_size != (int64) expected_length) {
            throw new LumoriaError.FAILED (
                _("Extract size mismatch for %s (got %lld, expected %u)").printf (
                    dest, dest_size, expected_length
                )
            );
        }
    }

    internal void verify_step_paths (InstallStepContext ctx) throws Error {
        var missing = new Gee.ArrayList<string> ();
        foreach (var vp in ctx.step.verify_paths) {
            var expanded = ctx.expand (vp);
            if (!FileUtils.test (expanded, FileTest.EXISTS)) {
                missing.add (expanded);
            }
        }
        if (missing.size > 0) {
            throw new LumoriaError.FAILED (_("Extract verify failed, missing: %s").printf (missing[0]));
        }
    }

    internal bool verify_paths_with_logging (
        Gee.ArrayList<string> verify_paths,
        Gee.HashMap<string, string> vars,
        RuntimeLog logger
    ) {
        if (verify_paths.size == 0) return false;
        bool all_verified = true;
        foreach (var vp in verify_paths) {
            var expanded = Utils.expand_vars (vp, vars);
            var exists = FileUtils.test (expanded, FileTest.EXISTS);
            logger.typed (LogType.VERIFY, "%s -> %s".printf (expanded, exists ? "EXISTS" : "MISSING"));
            if (!exists) all_verified = false;
        }
        return all_verified;
    }

}
