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
        string pfx_path,
        Models.PrefixEntry? entry,
        RuntimeLog logger
    ) throws Error {
        var result = new ComponentResult ();

        foreach (var component in resolve_component_selections (entry)) {
            logger.typed (LogType.COMPONENT, "%s: enabled, version=%s".printf (
                component.spec.id, component.version
            ));

            if (component.installed_path == "" || !FileUtils.test (component.installed_path, FileTest.IS_DIR)) {
                logger.typed (LogType.COMPONENT, "%s: installed path not found (predownload required), skipping steps".printf (
                    component.spec.id
                ));
                continue;
            }

            if (!run_component_steps (component.spec, component.installed_path, pfx_path, logger)) {
                logger.typed (LogType.COMPONENT, "%s: component steps failed, skipping overrides/env".printf (
                    component.spec.id
                ));
                continue;
            }

            foreach (var ov_entry in component.spec.overrides.entries) {
                result.dll_overrides[ov_entry.key] = ov_entry.value;
            }
        }

        return result;
    }

    /**
     * Resolve the expanded env defaults from all active component specs.
     * Used at install time to seed prefix runtime_env_vars.
     */
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
            if (!is_component_active (spec, entry, defaults)) continue;

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
        Utils.Preferences defaults
    ) {
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

    private bool run_component_steps (
        Models.ComponentSpec spec,
        string component_path,
        string pfx_path,
        RuntimeLog logger
    ) throws Error {
        bool ok = true;
        var vars = new Gee.HashMap<string, string> ();
        vars["COMPONENT"] = component_path;
        vars["PREFIX"] = pfx_path;
        foreach (var step in spec.steps) {
            var src = resolve_component_src (step.src, vars);
            var dst = Utils.expand_vars (step.dst, vars);

            logger.typed (LogType.COMPONENT, "%s: %s %s -> %s".printf (spec.id, step.step_type, src, dst));

            switch (step.step_type) {
                case "copy":
                    if (!copy_component_files (src, dst, logger)) ok = false;
                    break;
                default:
                    logger.typed (LogType.COMPONENT, "%s: unknown step type '%s', skipping".printf (spec.id, step.step_type));
                    break;
            }
        }
        return ok;
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

    private bool copy_component_files (string src, string dst, RuntimeLog logger) throws Error {
        if (!FileUtils.test (src, FileTest.EXISTS)) {
            logger.typed (LogType.COMPONENT, "source not found: %s".printf (src));
            return false;
        }
        Utils.copy_path (src, dst, (copied_src, _) => {
            logger.typed (LogType.COMPONENT, "  copied %s".printf (Path.get_basename (copied_src)));
        });
        return true;
    }

}
