namespace Lumoria.Runtime {
    private class ResolvedComponentSelection : Object {
        public Models.ComponentManifest spec { get; set; }
        public string version { get; set; default = "latest"; }
        public Runtime.ComponentToolAdapter adapter { get; set; }
        public Models.ToolVersion version_obj { get; set; }
        public string installed_path { get; set; default = ""; }
    }

    public const string FEATURE_DXVK_CONFIG = "dxvk_config";

    public class ComponentResult : Object {
        public Gee.HashMap<string, string> dll_overrides {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
    }

    public int predownload_enabled_components (
        Models.PrefixEntry? entry,
        RuntimeLog logger,
        Cancellable? cancellable = null
    ) throws Error {
        int downloaded = 0;
        foreach (var component in resolve_component_selections (entry)) {
            Utils.check_cancelled (cancellable);
            if (!component.adapter.is_installed (component.version_obj)) {
                logger.typed (LogType.COMPONENT, "%s %s not installed, predownloading...".printf (
                    component.spec.id, component.version
                ));
                component.adapter.install_version (component.version_obj, null, cancellable);
                downloaded++;
            } else {
                logger.typed (LogType.COMPONENT, "%s %s already cached/installed".printf (
                    component.spec.id, component.version
                ));
            }
        }

        return downloaded;
    }

    public void collect_pending_component_updates (
        Models.PrefixEntry entry,
        Gee.ArrayList<PendingUpdate> pending,
        RuntimeLog logger
    ) {
        var defaults = Utils.Preferences.instance ();
        foreach (var spec in Models.ManifestRepository.shared ().all_components) {
            if (!is_component_active (spec, entry, defaults, null)) continue;
            if (!entry.applied_components.has_key (spec.id)) continue;
            var applied = entry.applied_components[spec.id];
            if (Models.ToolVersionRef.is_deferred (applied.version)) continue;
            if (!Models.ToolVersionRef.is_deferred (requested_component_version (spec, entry, defaults))) continue;

            string latest;
            try {
                latest = new Runtime.ComponentToolAdapter (spec).resolve_latest_tag ();
            } catch (Error e) {
                logger.typed (LogType.WARN, "Update check failed for %s: %s".printf (spec.id, e.message));
                continue;
            }
            if (latest == "" || latest == applied.version) continue;

            var update = new PendingUpdate ();
            update.component_id = spec.id;
            update.label = spec.display_label ();
            update.current_version = applied.version;
            update.new_version = latest;
            pending.add (update);
        }
    }

    /* Everything one apply pass shares across its components; entry is null for template prefixes. */
    private class ComponentApplyContext : Object {
        public WinePaths wine_paths;
        public string pfx_path;
        public Models.PrefixEntry? entry;
        public Utils.Preferences defaults;
        public string arch;
        public RuntimeLog logger;
        public LaunchPolicy launch_policy;
        public Cancellable? cancellable;

        public bool offline {
            get { return launch_policy == LaunchPolicy.OFFLINE_FAST_START; }
        }

        public void log (string component_id, string message) {
            logger.typed (LogType.COMPONENT, "%s: %s".printf (component_id, message));
        }

        public Models.AppliedComponentRecord? applied (string component_id) {
            if (entry == null || !entry.applied_components.has_key (component_id)) return null;
            return entry.applied_components[component_id];
        }

        /* Removes a record's files, keeping any that another applied component also claims. */
        public void sweep (Models.ComponentManifest spec, Models.AppliedComponentRecord record, bool restore_runner_builtins) {
            sweep_component_files (
                record, wine_paths, arch, logger, restore_runner_builtins, retained_component_files (entry, spec.id)
            );
        }
    }

    public ComponentResult apply_enabled_components (
        WinePaths wine_paths,
        string pfx_path,
        Models.PrefixEntry? entry,
        Models.Entrypoint? entrypoint,
        RuntimeLog logger,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        Cancellable? cancellable = null
    ) throws Error {
        var ctx = new ComponentApplyContext ();
        ctx.wine_paths = wine_paths;
        ctx.pfx_path = pfx_path;
        ctx.entry = entry;
        ctx.defaults = Utils.Preferences.instance ();
        ctx.arch = entry != null ? effective_wine_arch (entry) : "win64";
        ctx.logger = logger;
        ctx.launch_policy = launch_policy;
        ctx.cancellable = cancellable;

        var result = new ComponentResult ();
        var entrypoint_overrides = entrypoint != null ? entrypoint.component_overrides : null;
        bool dirty = false;

        foreach (var spec in Models.ManifestRepository.shared ().all_components) {
            try {
                var prefix_active = is_component_active (spec, entry, ctx.defaults, null);
                var runtime_active = is_component_active (spec, entry, ctx.defaults, entrypoint_overrides);

                bool dirty_component;
                var component_ready = sync_component_state (ctx, spec, prefix_active, out dirty_component);
                dirty = dirty || dirty_component;

                if (runtime_active && component_ready) {
                    foreach (var ov in spec.overrides.entries) {
                        result.dll_overrides[ov.key] = ov.value;
                    }
                }
            } catch (Error e) {
                logger.typed (LogType.ERROR, "Component %s failed: %s".printf (spec.id, e.message));
                throw e;
            }
        }

        if (dirty && entry != null) {
            persist_prefix (entry);
        }

        return result;
    }

    private bool sync_component_state (
        ComponentApplyContext ctx,
        Models.ComponentManifest spec,
        bool prefix_active,
        out bool dirty
    ) throws Error {
        dirty = false;
        var applied = ctx.applied (spec.id);
        if (!prefix_active) {
            if (applied != null) {
                ctx.log (spec.id, "disabled, removing %s".printf (applied.version));
                ctx.sweep (spec, applied, true);
                ctx.entry.applied_components.unset (spec.id);
                dirty = true;
            }
            return spec.steps.size == 0;
        }

        var desired_version = resolve_component_version (spec, ctx.entry, ctx.defaults, applied, ctx.launch_policy);

        if (applied != null && applied.version == desired_version) {
            if (component_record_matches_arch (ctx, spec, applied)) {
                ctx.log (spec.id, "%s already applied".printf (desired_version));
                return true;
            }
            if (ctx.offline) {
                throw new LumoriaError.FAILED (
                    _("Component %s files are incomplete for shortcut launch. Open Lumoria to repair this prefix.").printf (spec.id)
                );
            }
            ctx.log (spec.id, "reapplying %s for %s prefix".printf (desired_version, ctx.arch));
            commit_component_install (ctx, spec, desired_version);
            dirty = ctx.entry != null;
            return true;
        }

        if (ctx.offline) {
            throw new LumoriaError.FAILED (
                _("Component %s is not prepared for shortcut launch. Open Lumoria to prepare this prefix.").printf (spec.id)
            );
        }

        if (applied != null) {
            if (Models.ToolVersionRef.is_deferred (applied.version)) {
                ctx.log (spec.id, "preparing %s".printf (desired_version));
            } else {
                ctx.log (spec.id, "replacing %s with %s".printf (applied.version, desired_version));
                ctx.sweep (spec, applied, false);
                ctx.entry.applied_components.unset (spec.id);
                dirty = true;
            }
        }

        commit_component_install (ctx, spec, desired_version);
        dirty = dirty || ctx.entry != null;
        return true;
    }

    private void commit_component_install (
        ComponentApplyContext ctx,
        Models.ComponentManifest spec,
        string version
    ) throws Error {
        var record = run_component_install (ctx, spec, version);
        if (!component_record_matches_arch (ctx, spec, record)) {
            ctx.sweep (spec, record, false);
            throw new LumoriaError.FAILED (
                _("Component %s apply did not produce expected files").printf (spec.id)
            );
        }
        if (ctx.entry != null) {
            ctx.entry.applied_components[spec.id] = record;
        }
    }

    public bool is_dxvk_active (
        Models.PrefixEntry? entry,
        Models.Entrypoint? entrypoint = null
    ) {
        var defaults = Utils.Preferences.instance ();
        foreach (var spec in Models.ManifestRepository.shared ().all_components) {
            if (!spec.supports_feature (FEATURE_DXVK_CONFIG)) continue;
            if (is_component_active (
                spec,
                entry,
                defaults,
                entrypoint != null ? entrypoint.component_overrides : null
            )) {
                return true;
            }
        }
        return false;
    }

    private bool component_record_matches_arch (
        ComponentApplyContext ctx,
        Models.ComponentManifest spec,
        Models.AppliedComponentRecord record
    ) {
        if (spec.steps.size > 0 && record.installed_files.size == 0) return false;
        foreach (var path in record.installed_files) {
            if (!FileUtils.test (path, FileTest.EXISTS)) return false;
            var normalized = path.replace ("\\", "/");
            if (ctx.arch == "win32" && normalized.contains ("/drive_c/windows/syswow64/")) {
                return false;
            }
        }
        return component_expected_outputs_exist (ctx, spec, record);
    }

    private bool component_expected_outputs_exist (
        ComponentApplyContext ctx,
        Models.ComponentManifest spec,
        Models.AppliedComponentRecord record
    ) {
        var vars = build_component_vars (ctx.pfx_path, spec, ctx.entry, ctx.arch);
        if (vars == null) return false;

        if (Models.ToolVersionRef.is_pinned (record.version)) {
            var adapter = new Runtime.ComponentToolAdapter (spec);
            vars[VAR_COMPONENT] = adapter.installed_path (new Models.ToolVersion (record.version));
        }

        foreach (var step in spec.steps) {
            if (step.step_type != Models.InstallStepKind.COPY) continue;
            if (step.when != null && !step.when.evaluate (vars)) continue;
            if (step.src.strip ().has_suffix ("/")) continue;

            var src = Utils.expand_vars (step.src, vars);
            var dst = Utils.expand_vars (step.dst, vars);
            var expected = Utils.resolve_copy_file_destination (src, dst);
            if (expected == "") continue;
            if (!FileUtils.test (expected, FileTest.EXISTS)) return false;
        }

        return component_backup_outputs_are_valid (spec, vars);
    }

    private delegate bool BackupPayloadCallback (
        string backup,
        string payload,
        Models.InstallStep rename_step
    );

    private bool each_backup_payload_pair (
        Models.ComponentManifest spec,
        Gee.HashMap<string, string> vars,
        BackupPayloadCallback visit
    ) {
        foreach (var rename_step in spec.steps) {
            if (rename_step.step_type != Models.InstallStepKind.RENAME || !rename_step.idempotent) continue;
            if (rename_step.when != null && !rename_step.when.evaluate (vars)) continue;

            var backup = Utils.expand_vars (rename_step.dst, vars);
            if (!FileUtils.test (backup, FileTest.EXISTS)) continue;

            foreach (var copy_step in spec.steps) {
                if (copy_step.step_type != Models.InstallStepKind.COPY) continue;
                if (copy_step.when != null && !copy_step.when.evaluate (vars)) continue;
                if (copy_step.src.strip ().has_suffix ("/")) continue;

                string payload;
                try {
                    payload = resolve_component_src (copy_step.src, vars);
                } catch (Error e) {
                    debug ("Failed to resolve component backup source: %s", e.message);
                    continue;
                }
                if (!FileUtils.test (payload, FileTest.EXISTS)) continue;
                if (visit (backup, payload, rename_step)) return true;
            }
        }
        return false;
    }

    private bool component_backup_outputs_are_valid (
        Models.ComponentManifest spec,
        Gee.HashMap<string, string> vars
    ) {
        return !each_backup_payload_pair (spec, vars, (backup, payload, rename_step) => {
            return Utils.files_have_same_contents (backup, payload);
        });
    }

    public Gee.HashMap<string, string> resolve_component_env_defaults (
        string pfx_path,
        Models.PrefixEntry? entry
    ) {
        var merged = new Gee.HashMap<string, string> ();
        foreach (var component in resolve_component_selections (entry)) {
            if (component.installed_path == "" || !FileUtils.test (component.installed_path, FileTest.IS_DIR)) {
                continue;
            }

            var vars = build_component_vars (
                pfx_path, component.spec, entry, "", component.installed_path, false
            );
            foreach (var env_entry in component.spec.system_env_defaults.entries) {
                merged[env_entry.key] = Utils.expand_vars (env_entry.value, vars);
            }
        }

        return merged;
    }

    private Gee.ArrayList<ResolvedComponentSelection> resolve_component_selections (Models.PrefixEntry? entry) {
        var selections = new Gee.ArrayList<ResolvedComponentSelection> ();
        var specs = Models.ManifestRepository.shared ().all_components;
        var defaults = Utils.Preferences.instance ();

        foreach (var spec in specs) {
            if (!is_component_active (spec, entry, defaults, null)) continue;

            var selection = new ResolvedComponentSelection ();
            selection.spec = spec;
            selection.version = requested_component_version (spec, entry, defaults);
            selection.adapter = new Runtime.ComponentToolAdapter (spec);
            selection.version_obj = Models.ToolVersionRef.to_version (selection.version);
            selection.installed_path = selection.adapter.installed_path (selection.version_obj);
            selections.add (selection);
        }

        return selections;
    }

    private bool component_is_listed (Models.ComponentManifest spec, Models.PrefixEntry? entry) {
        foreach (var listed in Models.ManifestRepository.shared ().components) {
            if (listed.id == spec.id) return true;
        }
        if (Models.ManifestRepository.shared ().components.size == 0) return false;
        return entry != null && entry.applied_components.has_key (spec.id);
    }

    private bool is_component_active (
        Models.ComponentManifest spec,
        Models.PrefixEntry? entry,
        Utils.Preferences defaults,
        Gee.HashMap<string, Models.RuntimeComponentOverride>? entrypoint_overrides
    ) {
        if (!component_is_listed (spec, entry)) return false;
        if (entry != null && !spec.supports_installer (entry.installer_id)) return false;
        if (entrypoint_overrides != null && entrypoint_overrides.has_key (spec.id)) {
            var ov = entrypoint_overrides[spec.id];
            if (ov.enabled != null) return (bool) ov.enabled;
        }
        if (entry != null && entry.runtime_component_overrides.has_key (spec.id)) {
            var ov = entry.runtime_component_overrides[spec.id];
            if (ov.enabled != null) return (bool) ov.enabled;
        }
        return defaults.is_component_enabled (spec.id);
    }

    private string requested_component_version (
        Models.ComponentManifest spec,
        Models.PrefixEntry? entry,
        Utils.Preferences defaults
    ) {
        if (entry != null && entry.runtime_component_overrides.has_key (spec.id)) {
            var ov = entry.runtime_component_overrides[spec.id];
            if (Models.ToolVersionRef.is_pinned (ov.version)) return ov.version;
        }
        return defaults.get_tool_version (Utils.ToolKind.COMPONENT, spec.id);
    }

    private string resolve_component_version (
        Models.ComponentManifest spec,
        Models.PrefixEntry? entry,
        Utils.Preferences defaults,
        Models.AppliedComponentRecord? applied,
        LaunchPolicy launch_policy
    ) throws Error {
        var requested = requested_component_version (spec, entry, defaults);
        if (launch_policy == LaunchPolicy.OFFLINE_FAST_START) {
            if (applied != null && !Models.ToolVersionRef.is_deferred (applied.version)) return applied.version;
            throw new LumoriaError.FAILED (
                _("Component %s has no applied version for shortcut launch. Open Lumoria to prepare this prefix.").printf (spec.id)
            );
        }
        if (!Models.ToolVersionRef.is_deferred (requested)) return requested;

        var resolved = new Runtime.ComponentToolAdapter (spec).resolve_latest_tag ();
        if (resolved == "") {
            throw new LumoriaError.FAILED (_("Failed to resolve latest version for component %s").printf (spec.id));
        }
        return resolved;
    }

    private Models.AppliedComponentRecord run_component_install (
        ComponentApplyContext ctx,
        Models.ComponentManifest spec,
        string version
    ) throws Error {
        var adapter = new Runtime.ComponentToolAdapter (spec);
        var version_obj = Models.ToolVersionRef.to_version (version);

        if (!adapter.is_installed (version_obj)) {
            if (ctx.offline) {
                throw new LumoriaError.FAILED (
                    _("Component %s %s is not installed. Open Lumoria to download it before launching from CLI.").printf (
                        spec.id, version
                    )
                );
            }
            ctx.log (spec.id, "cache miss, fetching %s".printf (version));
            adapter.install_version (version_obj, null, ctx.cancellable);
        }
        var installed_path = adapter.installed_path (version_obj);
        if (installed_path == "" || !FileUtils.test (installed_path, FileTest.IS_DIR)) {
            throw new LumoriaError.FAILED (
                _("Component %s %s is missing its install directory").printf (spec.id, version)
            );
        }
        ctx.log (spec.id, "applying %s".printf (version));

        var record = new Models.AppliedComponentRecord ();
        record.version = version;

        var vars = build_component_vars (ctx.pfx_path, spec, ctx.entry, ctx.arch, installed_path);
        if (vars == null) {
            throw new LumoriaError.FAILED (
                _("Component '%s' is incompatible with this installation").printf (spec.id)
            );
        }

        var logger = ctx.logger;
        foreach (var step in spec.steps) {
            Utils.check_cancelled (ctx.cancellable);
            if (step.when != null && !step.when.evaluate (vars)) continue;
            var src = resolve_component_src (step.src, vars);
            var dst = require_component_dst (step.dst, vars);
            ctx.log (spec.id, "%s %s -> %s".printf (step.step_type.id (), src, dst));

            switch (step.step_type) {
                case Models.InstallStepKind.COPY:
                    if (!FileUtils.test (src, FileTest.EXISTS)) {
                        throw new LumoriaError.FAILED (_("%s: source missing: %s").printf (spec.id, src));
                    }
                    Utils.copy_path (src, dst, (copied_src, copied_dst) => {
                        logger.typed (LogType.COMPONENT, "  copied %s".printf (Path.get_basename (copied_src)));
                        record.installed_files.add (copied_dst);
                    });
                    break;
                case Models.InstallStepKind.RENAME:
                    if (step.idempotent && FileUtils.test (dst, FileTest.EXISTS)) {
                        repair_component_backup_if_needed (ctx, spec, step, vars);
                        logger.typed (LogType.COMPONENT, "  rename target already present: %s".printf (dst));
                        record.installed_files.add (dst);
                        break;
                    }
                    if (!FileUtils.test (src, FileTest.EXISTS)) {
                        var builtin = runner_builtin_for_dst (ctx.wine_paths, src, ctx.arch);
                        if (builtin == "") {
                            throw new LumoriaError.FAILED (_("%s: source missing: %s").printf (spec.id, src));
                        }
                        Utils.copy_path (builtin, dst);
                        logger.typed (LogType.COMPONENT, "  sourced %s from runner".printf (Path.get_basename (dst)));
                        record.installed_files.add (dst);
                        break;
                    }
                    Utils.ensure_dir (Path.get_dirname (dst));
                    if (FileUtils.rename (src, dst) != 0) {
                        throw new LumoriaError.FAILED (_("rename failed: %s -> %s").printf (src, dst));
                    }
                    logger.typed (LogType.COMPONENT, "  renamed %s -> %s".printf (src, dst));
                    record.installed_files.add (dst);
                    break;
                default:
                    throw new LumoriaError.FAILED (_("%s: unknown step type '%s'").printf (spec.id, step.step_type.id ()));
            }
        }
        return record;
    }

    private string require_component_dst (string raw, Gee.HashMap<string, string> vars) throws Error {
        return require_confined_path (
            raw, vars, _("Component path escapes the prefix: %s"), false
        );
    }

    private void repair_component_backup_if_needed (
        ComponentApplyContext ctx,
        Models.ComponentManifest spec,
        Models.InstallStep rename_step,
        Gee.HashMap<string, string> vars
    ) {
        var logger = ctx.logger;
        each_backup_payload_pair (spec, vars, (backup, payload, step) => {
            if (step != rename_step) return false;
            if (!Utils.files_have_same_contents (backup, payload)) return false;

            var original_dst = Utils.expand_vars (rename_step.src, vars);
            var builtin = runner_builtin_for_dst (ctx.wine_paths, original_dst, ctx.arch);
            if (builtin == "") {
                logger.typed (LogType.COMPONENT, "  backup repair skipped, runner builtin missing: %s".printf (backup));
                return true;
            }

            try {
                Utils.copy_path (builtin, backup);
                logger.typed (LogType.COMPONENT, "  repaired backup %s from runner".printf (Path.get_basename (backup)));
            } catch (Error e) {
                logger.typed (LogType.COMPONENT, "  failed to repair backup %s: %s".printf (
                    Path.get_basename (backup),
                    e.message
                ));
            }
            return true;
        });
    }

    private Gee.Set<string> retained_component_files (Models.PrefixEntry? entry, string except_id) {
        var keep = new Gee.HashSet<string> ();
        if (entry == null) return keep;
        foreach (var other in entry.applied_components.entries) {
            if (other.key == except_id) continue;
            foreach (var path in other.value.installed_files) {
                if (path != "") keep.add (path);
            }
        }
        return keep;
    }

    private void sweep_component_files (
        Models.AppliedComponentRecord record,
        WinePaths wine_paths,
        string arch,
        RuntimeLog logger,
        bool restore_runner_builtins,
        Gee.Set<string>? retain = null
    ) {
        foreach (var path in record.installed_files) {
            if (retain != null && retain.contains (path)) {
                logger.typed (LogType.COMPONENT, "  kept %s (claimed by another component)".printf (path));
                continue;
            }
            if (!FileUtils.test (path, FileTest.EXISTS)) continue;
            if (FileUtils.unlink (path) != 0) {
                logger.typed (LogType.COMPONENT, "  failed to remove %s".printf (path));
                continue;
            }
            logger.typed (LogType.COMPONENT, "  removed %s".printf (path));

            if (!restore_runner_builtins) continue;

            var src = runner_builtin_for_dst (wine_paths, path, arch);
            if (src == "") continue;
            try {
                Utils.copy_path (src, path);
                logger.typed (LogType.COMPONENT, "  restored %s from runner".printf (Path.get_basename (path)));
            } catch (Error e) {
                logger.typed (LogType.COMPONENT,
                    "  failed to restore %s: %s".printf (Path.get_basename (path), e.message));
            }
        }
    }

    private string resolve_component_src (string step_src, Gee.HashMap<string, string> vars) throws Error {
        var component_path = get_var (vars, VAR_COMPONENT);
        var src = Utils.expand_vars (step_src, vars);
        if (FileUtils.test (src, FileTest.EXISTS)) return src;
        if (component_path == "" || !src.has_prefix (component_path + "/")) return src;

        var suffix = src.substring (component_path.length + 1);
        return find_nested_component_src (component_path, suffix, 3) ?? src;
    }

    private string? find_nested_component_src (string root, string suffix, int max_depth) {
        var dirs = new Gee.ArrayList<string> ();
        var depths = new Gee.ArrayList<int> ();
        dirs.add (root);
        depths.add (0);

        for (int i = 0; i < dirs.size; i++) {
            var dir = dirs[i];
            var depth = depths[i];
            var candidate = Path.build_filename (dir, suffix);
            if (FileUtils.test (candidate, FileTest.EXISTS)) return candidate;
            if (depth >= max_depth) continue;

            foreach (var name in Utils.list_dirs (dir)) {
                dirs.add (Path.build_filename (dir, name));
                depths.add (depth + 1);
            }
        }
        return null;
    }

    private Gee.HashMap<string, string>? build_component_vars (
        string pfx_path,
        Models.ComponentManifest spec,
        Models.PrefixEntry? entry,
        string arch = "",
        string installed_path = "",
        bool populate_installer = true
    ) {
        var vars = populate_installer
            ? component_installer_vars (pfx_path, spec, entry, arch)
            : new Gee.HashMap<string, string> ();
        if (vars == null) return null;
        vars[VAR_COMPONENT] = installed_path;
        seed_prefix_paths (vars, pfx_path);
        if (arch != "") set_arch_vars (vars, arch);
        return vars;
    }

    private Gee.HashMap<string, string>? component_installer_vars (
        string pfx_path,
        Models.ComponentManifest component,
        Models.PrefixEntry? entry,
        string arch
    ) {
        if (entry == null) {
            return component.installer_ids.size == 0 ? new Gee.HashMap<string, string> () : null;
        }
        var installer = Models.ManifestRepository.shared ().installer (entry.installer_id);
        if (installer == null || !component.supports_installer (installer.id)) return null;
        return build_launch_vars (pfx_path, entry, installer, arch);
    }

    private string runner_builtin_for_dst (WinePaths paths, string dst_path, string wine_arch) {
        var parent_dir = Path.get_basename (Path.get_dirname (dst_path));
        string arch_subdir;
        if (parent_dir == "syswow64") {
            arch_subdir = "i386-windows";
        } else if (parent_dir == "system32") {
            arch_subdir = (wine_arch == "win32") ? "i386-windows" : "x86_64-windows";
        } else {
            return "";
        }
        var pe_dir = paths.find_runner_pe_dir (arch_subdir);
        if (pe_dir == "") return "";
        var candidate = Path.build_filename (pe_dir, Path.get_basename (dst_path));
        return FileUtils.test (candidate, FileTest.EXISTS) ? candidate : "";
    }
}
