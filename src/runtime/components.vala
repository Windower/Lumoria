namespace Lumoria.Runtime {
    private class ResolvedComponentSelection : Object {
        public Models.ComponentSpec spec { get; set; }
        public string version { get; set; default = "latest"; }
        public Models.ComponentToolAdapter adapter { get; set; }
        public Models.ToolVersion version_obj { get; set; }
        public string installed_path { get; set; default = ""; }
    }

    public class ComponentResult : Object {
        public Gee.HashMap<string, string> dll_overrides {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
    }

    public int predownload_enabled_components (
        Models.PrefixEntry? entry,
        RuntimeLog logger
    ) throws Error {
        int downloaded = 0;
        foreach (var component in resolve_component_selections (entry)) {
            if (!component.adapter.is_installed (component.version_obj)) {
                logger.typed (LogType.COMPONENT, "%s %s not installed, predownloading...".printf (
                    component.spec.id, component.version
                ));
                component.adapter.install_version (component.version_obj, null);
                downloaded++;
            } else {
                logger.typed (LogType.COMPONENT, "%s %s already cached/installed".printf (
                    component.spec.id, component.version
                ));
            }
        }

        return downloaded;
    }

    public ComponentResult apply_enabled_components (
        WinePaths wine_paths,
        string pfx_path,
        Models.PrefixEntry? entry,
        Models.Entrypoint? entrypoint,
        RuntimeLog logger
    ) throws Error {
        var result = new ComponentResult ();
        var specs = Models.ComponentSpec.load_all_from_resource ();
        var defaults = Utils.Preferences.instance ();
        var arch = entry != null ? Utils.normalize_wine_arch (entry.wine_arch) : "";
        if (arch == "") arch = "win64";
        bool dirty = false;

        foreach (var spec in specs) {
            var prefix_active = is_component_active (spec, entry, defaults, null);
            var runtime_active = is_component_active (
                spec,
                entry,
                defaults,
                entrypoint != null ? entrypoint.component_overrides : null
            );
            var desired_version = resolve_component_version (spec, entry, defaults);
            Models.AppliedComponentRecord? applied = null;
            if (entry != null && entry.applied_components.has_key (spec.id)) {
                applied = entry.applied_components[spec.id];
            }

            if (runtime_active) {
                foreach (var ov in spec.overrides.entries) {
                    result.dll_overrides[ov.key] = ov.value;
                }
            }

            if (prefix_active) {

                if (applied != null && applied.version == desired_version) {
                    logger.typed (LogType.COMPONENT, "%s: %s already applied".printf (spec.id, desired_version));
                    continue;
                }

                if (applied != null) {
                    logger.typed (LogType.COMPONENT, "%s: replacing %s with %s".printf (
                        spec.id, applied.version, desired_version
                    ));
                    sweep_component_files (applied, wine_paths, arch, logger);
                    if (entry != null) entry.applied_components.unset (spec.id);
                }

                var record = run_component_install (spec, desired_version, pfx_path, entry, logger);
                if (record != null && entry != null) {
                    entry.applied_components[spec.id] = record;
                    dirty = true;
                }
                continue;
            }

            if (applied != null) {
                logger.typed (LogType.COMPONENT, "%s: disabled, removing %s".printf (spec.id, applied.version));
                sweep_component_files (applied, wine_paths, arch, logger);
                if (entry != null) {
                    entry.applied_components.unset (spec.id);
                    dirty = true;
                }
            }
        }

        if (dirty && entry != null) {
            var reg = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
            reg.update_entry (entry);
            reg.save (Utils.prefix_registry_path ());
        }

        return result;
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

            var vars = new Gee.HashMap<string, string> ();
            vars["COMPONENT"] = component.installed_path;
            vars["PREFIX"] = pfx_path;
            foreach (var env_entry in component.spec.system_env_defaults.entries) {
                merged[env_entry.key] = Utils.expand_vars (env_entry.value, vars);
            }
        }

        return merged;
    }

    private Gee.ArrayList<ResolvedComponentSelection> resolve_component_selections (Models.PrefixEntry? entry) {
        var selections = new Gee.ArrayList<ResolvedComponentSelection> ();
        var specs = Models.ComponentSpec.load_all_from_resource ();
        var defaults = Utils.Preferences.instance ();

        foreach (var spec in specs) {
            if (!is_component_active (spec, entry, defaults, null)) continue;

            var selection = new ResolvedComponentSelection ();
            selection.spec = spec;
            selection.version = resolve_component_version (spec, entry, defaults);
            selection.adapter = new Models.ComponentToolAdapter (spec);
            selection.version_obj = selection.version == "latest"
                ? new Models.ToolVersion.latest ("")
                : new Models.ToolVersion (selection.version);
            selection.installed_path = selection.adapter.installed_path (selection.version_obj);
            selections.add (selection);
        }

        return selections;
    }

    private bool is_component_active (
        Models.ComponentSpec spec,
        Models.PrefixEntry? entry,
        Utils.Preferences defaults,
        Gee.HashMap<string, Models.RuntimeComponentOverride>? entrypoint_overrides
    ) {
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

    private string resolve_component_version (
        Models.ComponentSpec spec,
        Models.PrefixEntry? entry,
        Utils.Preferences defaults
    ) {
        if (entry != null && entry.runtime_component_overrides.has_key (spec.id)) {
            var ov = entry.runtime_component_overrides[spec.id];
            if (ov.version != "" && ov.version != "default") return ov.version;
        }
        return defaults.get_tool_version (Utils.ToolKind.COMPONENT, spec.id);
    }

    private Models.AppliedComponentRecord? run_component_install (
        Models.ComponentSpec spec,
        string version,
        string pfx_path,
        Models.PrefixEntry? entry,
        RuntimeLog logger
    ) throws Error {
        var adapter = new Models.ComponentToolAdapter (spec);
        var version_obj = (version == "latest")
            ? new Models.ToolVersion.latest ("")
            : new Models.ToolVersion (version);

        if (!adapter.is_installed (version_obj)) {
            logger.typed (LogType.COMPONENT, "%s: cache miss, fetching %s".printf (spec.id, version));
            adapter.install_version (version_obj, null);
        }
        var installed_path = adapter.installed_path (version_obj);
        if (installed_path == "" || !FileUtils.test (installed_path, FileTest.IS_DIR)) {
            logger.typed (LogType.COMPONENT, "%s: install path missing, aborting apply".printf (spec.id));
            return null;
        }
        logger.typed (LogType.COMPONENT, "%s: applying %s".printf (spec.id, version));

        var record = new Models.AppliedComponentRecord ();
        record.version = version;

        var vars = new Gee.HashMap<string, string> ();
        vars["COMPONENT"] = installed_path;
        vars["PREFIX"] = pfx_path;
        if (entry != null) {
            vars["ARCH"] = Utils.normalize_wine_arch (entry.wine_arch) != "" ? Utils.normalize_wine_arch (entry.wine_arch) : "win64";
            vars["REGION"] = entry.region;
        }

        foreach (var step in spec.steps) {
            if (step.when != null && !step.when.evaluate (vars)) continue;
            var src = resolve_component_src (step.src, vars);
            var dst = Utils.expand_vars (step.dst, vars);
            logger.typed (LogType.COMPONENT, "%s: %s %s -> %s".printf (spec.id, step.step_type, src, dst));

            switch (step.step_type) {
                case "copy":
                    if (!FileUtils.test (src, FileTest.EXISTS)) {
                        logger.typed (LogType.COMPONENT, "  source missing: %s".printf (src));
                        break;
                    }
                    Utils.copy_path (src, dst, (copied_src, copied_dst) => {
                        logger.typed (LogType.COMPONENT, "  copied %s".printf (Path.get_basename (copied_src)));
                        record.installed_files.add (copied_dst);
                    });
                    break;
                case "rename":
                    if (!FileUtils.test (src, FileTest.EXISTS)) {
                        if (step.idempotent && FileUtils.test (dst, FileTest.EXISTS)) {
                            logger.typed (LogType.COMPONENT, "  rename target already present: %s".printf (dst));
                            record.installed_files.add (dst);
                            break;
                        }
                        logger.typed (LogType.COMPONENT, "  source missing: %s".printf (src));
                        break;
                    }
                    Utils.ensure_dir (Path.get_dirname (dst));
                    if (FileUtils.rename (src, dst) != 0) {
                        throw new IOError.FAILED ("rename failed: %s -> %s".printf (src, dst));
                    }
                    logger.typed (LogType.COMPONENT, "  renamed %s -> %s".printf (src, dst));
                    record.installed_files.add (dst);
                    break;
                default:
                    logger.typed (LogType.COMPONENT, "%s: unknown step type '%s'".printf (spec.id, step.step_type));
                    break;
            }
        }
        return record;
    }

    private void sweep_component_files (
        Models.AppliedComponentRecord record,
        WinePaths wine_paths,
        string arch,
        RuntimeLog logger
    ) {
        foreach (var path in record.installed_files) {
            if (!FileUtils.test (path, FileTest.EXISTS)) continue;
            if (FileUtils.unlink (path) != 0) {
                logger.typed (LogType.COMPONENT, "  failed to remove %s".printf (path));
                continue;
            }
            logger.typed (LogType.COMPONENT, "  removed %s".printf (path));

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
        var component_path = vars["COMPONENT"];
        var src = Utils.expand_vars (step_src, vars);
        if (FileUtils.test (src, FileTest.EXISTS)) return src;

        // Some archives add one extra top-level directory before the real payload.
        if (!src.has_prefix (component_path + "/")) return src;

        string? nested = single_child_dir (component_path);
        if (nested == null) return src;

        var suffix = src.substring (component_path.length + 1);
        var fallback = Path.build_filename (nested, suffix);
        if (FileUtils.test (fallback, FileTest.EXISTS)) return fallback;
        return src;
    }

    private string? single_child_dir (string path) throws Error {
        var dir = Dir.open (path);
        string? name;
        string? only = null;
        while ((name = dir.read_name ()) != null) {
            if (name == "." || name == "..") continue;
            var full = Path.build_filename (path, name);
            if (!FileUtils.test (full, FileTest.IS_DIR)) continue;
            if (only != null) return null;
            only = full;
        }
        return only;
    }

}
