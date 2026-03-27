namespace Lumoria.Runtime {

    public class ComponentResult : Object {
        public Gee.HashMap<string, string> dll_overrides {
            get; owned set; default = new Gee.HashMap<string, string> ();
        }
    }

    public int predownload_enabled_components (
        Models.PrefixEntry? entry,
        LogFunc? emit
    ) throws Error {
        int downloaded = 0;
        var specs = Models.ComponentSpec.load_all_from_resource ();
        var defaults = Utils.Preferences.instance ();

        foreach (var spec in specs) {
            bool enabled = is_component_active (spec, entry, defaults);
            if (!enabled) continue;

            var version = resolve_component_version (spec, entry, defaults);
            var adapter = new Models.ComponentToolAdapter (spec);
            var ver_obj = version == "latest"
                ? new Models.ToolVersion.latest ("")
                : new Models.ToolVersion (version);

            if (!adapter.is_installed (ver_obj)) {
                if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "%s %s not installed, predownloading...".printf (spec.id, version));
                adapter.install_version (ver_obj, null);
                downloaded++;
            } else if (emit != null) {
                RuntimeLog.emit_typed (emit, LogType.COMPONENT, "%s %s already cached/installed".printf (spec.id, version));
            }
        }

        return downloaded;
    }

    public ComponentResult apply_enabled_components (
        string pfx_path,
        Models.PrefixEntry? entry,
        LogFunc? emit
    ) throws Error {
        var result = new ComponentResult ();

        var specs = Models.ComponentSpec.load_all_from_resource ();
        var defaults = Utils.Preferences.instance ();

        foreach (var spec in specs) {
            bool enabled = is_component_active (spec, entry, defaults);
            if (!enabled) {
                if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "%s: disabled, skipping".printf (spec.id));
                continue;
            }

            var version = resolve_component_version (spec, entry, defaults);
            if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "%s: enabled, version=%s".printf (spec.id, version));

            var adapter = new Models.ComponentToolAdapter (spec);
            var ver_obj = version == "latest"
                ? new Models.ToolVersion.latest ("")
                : new Models.ToolVersion (version);

            var component_path = adapter.installed_path (ver_obj);
            if (component_path == "" || !FileUtils.test (component_path, FileTest.IS_DIR)) {
                if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "%s: installed path not found (predownload required), skipping steps".printf (spec.id));
                continue;
            }

            if (!run_component_steps (spec, component_path, pfx_path, emit)) {
                if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "%s: component steps failed, skipping overrides/env".printf (spec.id));
                continue;
            }

            foreach (var ov_entry in spec.overrides.entries) {
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
        var specs = Models.ComponentSpec.load_all_from_resource ();
        var defaults = Utils.Preferences.instance ();

        foreach (var spec in specs) {
            bool enabled = is_component_active (spec, entry, defaults);
            if (!enabled) continue;

            var version = resolve_component_version (spec, entry, defaults);
            var adapter = new Models.ComponentToolAdapter (spec);
            var ver_obj = version == "latest"
                ? new Models.ToolVersion.latest ("")
                : new Models.ToolVersion (version);

            var component_path = adapter.installed_path (ver_obj);
            if (component_path == "" || !FileUtils.test (component_path, FileTest.IS_DIR)) continue;

            var vars = new Gee.HashMap<string, string> ();
            vars["COMPONENT"] = component_path;
            vars["PREFIX"] = pfx_path;
            foreach (var env_entry in spec.system_env_defaults.entries) {
                merged[env_entry.key] = Utils.expand_vars (env_entry.value, vars);
            }
        }

        return merged;
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
        LogFunc? emit
    ) throws Error {
        bool ok = true;
        var vars = new Gee.HashMap<string, string> ();
        vars["COMPONENT"] = component_path;
        vars["PREFIX"] = pfx_path;
        foreach (var step in spec.steps) {
            var src = resolve_component_src (step.src, vars);
            var dst = Utils.expand_vars (step.dst, vars);

            if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "%s: %s %s -> %s".printf (spec.id, step.step_type, src, dst));

            switch (step.step_type) {
                case "copy":
                    if (!copy_component_files (src, dst, emit)) ok = false;
                    break;
                default:
                    if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "%s: unknown step type '%s', skipping".printf (spec.id, step.step_type));
                    break;
            }
        }
        return ok;
    }

    private string resolve_component_src (string step_src, Gee.HashMap<string, string> vars) throws Error {
        var component_path = vars["COMPONENT"];
        var src = Utils.expand_vars (step_src, vars);
        if (FileUtils.test (src, FileTest.EXISTS)) return src;

        // Some component archives extract into a nested top-level directory
        // (e.g. dxvk-<ver>/x32). Try that shape automatically.
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

    private bool copy_component_files (string src, string dst, LogFunc? emit) throws Error {
        if (!FileUtils.test (src, FileTest.EXISTS)) {
            if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "source not found: %s".printf (src));
            return false;
        }
        Utils.copy_path (src, dst, (copied_src, _) => {
            if (emit != null) RuntimeLog.emit_typed (emit, LogType.COMPONENT, "  copied %s".printf (Path.get_basename (copied_src)));
        });
        return true;
    }

}
