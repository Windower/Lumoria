namespace Lumoria.Runtime {

    private const string DEFAULT_EXE = "drive_c/Program Files (x86)/PlayOnline/SquareEnix/FINAL FANTASY XI/polboot.exe";

    public enum LaunchTargetSection {
        MAIN,
        WINDOWER_PROFILES,
        ACTIONS
    }

    public class LaunchTarget : Object {
        public string id { get; set; default = ""; }
        public string label { get; set; default = ""; }
        public string selector_label { get; set; default = ""; }
        public string description { get; set; default = ""; }
        public bool is_action { get; set; default = false; }
        public LaunchTargetSection section { get; set; default = LaunchTargetSection.MAIN; }
    }

    public string launch_target_section_title (LaunchTargetSection section) {
        switch (section) {
            case LaunchTargetSection.WINDOWER_PROFILES:
                return _("Windower profiles");
            case LaunchTargetSection.ACTIONS:
                return _("Actions");
            default:
                return _("Launch");
        }
    }

    public string launch_target_subtitle (
        LaunchTarget target,
        string active_target_id
    ) {
        if (target.id == active_target_id) {
            return _("Default for this prefix");
        }
        if (target.section == LaunchTargetSection.WINDOWER_PROFILES) {
            return "";
        }
        if (target.section == LaunchTargetSection.ACTIONS) {
            return target.description;
        }
        if (target.selector_label != target.label) {
            return target.selector_label;
        }
        return "";
    }

    public void resolve_launcher_exe (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        string entrypoint_id,
        out string exe,
        out string[] args
    ) {
        exe = DEFAULT_EXE;
        args = {};

        var pfx_path = install_prefix_path (entry.path);
        var installer_spec = Models.InstallerSpec.load_from_resource ();
        var launcher = entry.launcher_id != ""
            ? find_launcher_by_id (launcher_specs, entry.launcher_id) : null;
        var installer_vars = build_launch_vars (pfx_path, entry, installer_spec, launcher, null);

        if (entrypoint_id != "") {
            foreach (var custom_ep in entry.custom_entrypoints) {
                if (custom_ep.id == entrypoint_id) {
                    exe = custom_ep.exe;
                    args = arraylist_to_strv (custom_ep.args);
                    return;
                }
            }

            var wname = windower_profile_name_from_entry_id (entrypoint_id);
            if (wname != null && entry.launcher_id == "windower4") {
                var wlauncher = find_launcher_by_id (launcher_specs, "windower4");
                if (wlauncher != null) {
                    var wvars = build_launch_vars (pfx_path, entry, installer_spec, wlauncher, null);
                    var wep = find_entrypoint (wlauncher.entrypoints, "");
                    if (wep != null) {
                        apply_entrypoint (wep, wvars, out exe, out args);
                        var wl = new Gee.ArrayList<string> ();
                        foreach (var a in args) wl.add (a);
                        wl.add ("-p");
                        wl.add (wname.strip () == "" ? "Default" : wname);
                        args = arraylist_to_strv (wl);
                        return;
                    }
                }
            }

            Models.Entrypoint? installer_ep = null;
            foreach (var ep in installer_spec.entrypoints) {
                if (ep.id == entrypoint_id) { installer_ep = ep; break; }
            }
            if (installer_ep != null) {
                apply_entrypoint (installer_ep, installer_vars, out exe, out args);
                return;
            }

            var post_install = load_prefix_post_install_spec (entry);
            if (post_install != null) {
                foreach (var ep in post_install.entrypoints) {
                    if (ep.id == entrypoint_id) {
                        var pvars = build_launch_vars (pfx_path, entry, installer_spec, launcher, post_install);
                        apply_entrypoint (ep, pvars, out exe, out args);
                        return;
                    }
                }
            }
        }

        if (launcher == null) return;

        var vars = build_launch_vars (pfx_path, entry, installer_spec, launcher, null);

        Models.Entrypoint? ep = null;
        if (entrypoint_id != "") {
            foreach (var candidate in launcher.entrypoints) {
                if (candidate.id == entrypoint_id) { ep = candidate; break; }
            }
        }
        if (ep == null) {
            ep = find_entrypoint (launcher.entrypoints, "");
        }
        if (ep == null) return;

        apply_entrypoint (ep, vars, out exe, out args);
    }

    public void apply_launch_env (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec>? launcher_specs,
        string entrypoint_id,
        WineEnv env
    ) {
        var pfx_path = install_prefix_path (entry.path);
        var installer_spec = Models.InstallerSpec.load_from_resource ();
        var specs = launcher_specs ?? Models.LauncherSpec.load_all_from_resource ();
        var launcher = entry.launcher_id != ""
            ? find_launcher_by_id (specs, entry.launcher_id) : null;
        var post_install = load_prefix_post_install_spec (entry);
        var vars = build_launch_vars (pfx_path, entry, installer_spec, launcher, post_install);

        apply_env_rules (env, installer_spec.env, vars);
        if (launcher != null) apply_env_rules (env, launcher.env, vars);
        if (post_install != null) apply_env_rules (env, post_install.env, vars);

        if (entrypoint_id == "") return;
        var ep = find_launch_entrypoint (entry, installer_spec, launcher, post_install, entrypoint_id);
        if (ep != null) apply_env_rules (env, ep.env, vars);
    }

    private Models.Entrypoint? find_launch_entrypoint (
        Models.PrefixEntry entry,
        Models.InstallerSpec installer_spec,
        Models.LauncherSpec? launcher,
        Models.PostInstallSpec? post_install,
        string entrypoint_id
    ) {
        foreach (var ep in entry.custom_entrypoints) {
            if (ep.id == entrypoint_id) return ep;
        }
        foreach (var ep in installer_spec.entrypoints) {
            if (ep.id == entrypoint_id) return ep;
        }
        if (launcher != null) {
            foreach (var ep in launcher.entrypoints) {
                if (ep.id == entrypoint_id) return ep;
            }
        }
        if (post_install != null) {
            foreach (var ep in post_install.entrypoints) {
                if (ep.id == entrypoint_id) return ep;
            }
        }
        return null;
    }

    public Gee.ArrayList<Models.Entrypoint> list_entrypoints (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs
    ) {
        return list_entrypoints_with_custom (entry, launcher_specs, entry.custom_entrypoints);
    }

    public Gee.ArrayList<Models.Entrypoint> list_entrypoints_with_custom (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        Gee.ArrayList<Models.Entrypoint> custom_list
    ) {
        var all = new Gee.ArrayList<Models.Entrypoint> ();
        var pfx_path = install_prefix_path (entry.path);

        var installer_spec = Models.InstallerSpec.load_from_resource ();
        var launcher = entry.launcher_id != ""
            ? find_launcher_by_id (launcher_specs, entry.launcher_id) : null;
        var base_vars = build_launch_vars (pfx_path, entry, installer_spec, launcher, null);
        expand_entrypoints (all, installer_spec.entrypoints, base_vars);

        if (launcher != null) {
            expand_entrypoints (all, launcher.entrypoints, base_vars);
        }

        var post_install = load_prefix_post_install_spec (entry);
        if (post_install != null) {
            var pvars = build_launch_vars (pfx_path, entry, installer_spec, launcher, post_install);
            expand_entrypoints (all, post_install.entrypoints, pvars);
        }

        foreach (var ep in custom_list) {
            all.add (ep);
        }

        return all;
    }

    public Gee.ArrayList<LaunchTarget> list_launch_targets (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs,
        Gee.ArrayList<Models.Entrypoint>? custom_list = null
    ) {
        var targets = new Gee.ArrayList<LaunchTarget> ();
        var entrypoints = list_entrypoints_with_custom (
            entry,
            launcher_specs,
            custom_list ?? entry.custom_entrypoints
        );
        foreach (var ep in entrypoints) {
            var target = new LaunchTarget ();
            target.id = ep.id;
            target.label = ep.display_label ();
            target.selector_label = target.label;
            target.section = LaunchTargetSection.MAIN;
            targets.add (target);
        }

        foreach (var ep in list_windower_profile_entrypoints (entry)) {
            var target = new LaunchTarget ();
            target.id = ep.id;
            target.label = ep.display_label ();
            target.selector_label = _("Windower - Profile (%s)").printf (target.label);
            target.section = LaunchTargetSection.WINDOWER_PROFILES;
            targets.add (target);
        }

        foreach (var action in list_spec_actions (entry, launcher_specs)) {
            var target = new LaunchTarget ();
            target.id = action.id;
            target.label = action.display_label ();
            target.selector_label = target.label;
            target.description = action.description;
            target.section = LaunchTargetSection.ACTIONS;
            target.is_action = true;
            targets.add (target);
        }

        return targets;
    }

    public Gee.ArrayList<Models.SpecAction> list_spec_actions (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs
    ) {
        var actions = new Gee.ArrayList<Models.SpecAction> ();
        var seen = new Gee.HashSet<string> ();

        var installer = Models.InstallerSpec.load_from_resource ();
        append_unique_actions (actions, seen, installer.actions);

        if (entry.launcher_id != "") {
            var launcher = find_launcher_by_id (launcher_specs, entry.launcher_id);
            if (launcher != null) {
                append_unique_actions (actions, seen, launcher.actions);
            }
        }

        var post_install = load_prefix_post_install_spec (entry);
        if (post_install != null) {
            append_unique_actions (actions, seen, post_install.actions);
        }

        return actions;
    }

    public Models.PostInstallSpec? load_prefix_post_install_spec (Models.PrefixEntry entry) {
        var metadata = entry.post_install_spec;
        if (metadata == null) return null;

        if (metadata.backup_path != "" && FileUtils.test (metadata.backup_path, FileTest.EXISTS)) {
            try {
                return Models.PostInstallSpec.load_from_file (metadata.backup_path);
            } catch (Error e) {
                warning ("Failed to load backed up post install spec: %s", e.message);
            }
        }

        if (metadata.original_path != "" && FileUtils.test (metadata.original_path, FileTest.EXISTS)) {
            try {
                return Models.PostInstallSpec.load_from_file (metadata.original_path);
            } catch (Error e) {
                warning ("Failed to load original post install spec: %s", e.message);
            }
        }

        return null;
    }

    private void append_unique_actions (
        Gee.ArrayList<Models.SpecAction> target,
        Gee.HashSet<string> seen,
        Gee.ArrayList<Models.SpecAction> source
    ) {
        foreach (var action in source) {
            if (action.id == "" || seen.contains (action.id)) continue;
            target.add (action);
            seen.add (action.id);
        }
    }

    public string resolve_host_path (string exe, string pfx_path) {
        var lower = exe.down ();
        if (lower.has_prefix ("c:\\") || lower.has_prefix ("c:")) {
            var rest = exe.substring (2);
            if (rest.has_prefix ("\\") || rest.has_prefix ("/")) rest = rest.substring (1);
            return Path.build_filename (pfx_path, "drive_c", rest.replace ("\\", "/"));
        }
        if (Path.is_absolute (exe)) return exe;
        return Path.build_filename (pfx_path, exe.replace ("\\", "/"));
    }

    public string to_wine_path (string pfx_path, string host_exe) {
        var drive_c = Path.build_filename (pfx_path, "drive_c");
        if (host_exe.has_prefix (drive_c + "/")) {
            var rel = host_exe.substring (drive_c.length + 1);
            return "C:\\" + rel.replace ("/", "\\");
        }
        return "Z:" + host_exe.replace ("/", "\\");
    }

    public string resolve_effective_entrypoint_id (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs
    ) {
        if (entry.launch_entrypoint_id != "") {
            return entry.launch_entrypoint_id;
        }

        if (entry.launcher_id != "") {
            var launcher = find_launcher_by_id (launcher_specs, entry.launcher_id);
            if (launcher != null) {
                var ep = find_entrypoint (launcher.entrypoints, "");
                if (ep != null) return ep.id;
            }
        }

        var installer_spec = Models.InstallerSpec.load_from_resource ();
        var ep = find_entrypoint (installer_spec.entrypoints, "");
        if (ep != null) return ep.id;

        return "";
    }

    private Gee.HashMap<string, string> build_launch_vars (
        string pfx_path,
        Models.PrefixEntry entry,
        Models.InstallerSpec installer_spec,
        Models.LauncherSpec? launcher,
        Models.PostInstallSpec? post_install
    ) {
        var vars = new Gee.HashMap<string, string> ();
        vars["PREFIX"] = pfx_path;
        vars["WINDOWS"] = Path.build_filename (pfx_path, "drive_c", "windows");
        vars["SYSTEM32"] = Path.build_filename (pfx_path, "drive_c", "windows", "system32");
        vars["SYSWOW64"] = Path.build_filename (pfx_path, "drive_c", "windows", "syswow64");
        vars["FONTS"] = Path.build_filename (pfx_path, "drive_c", "windows", "Fonts");
        vars["ARCH"] = Utils.normalize_wine_arch (entry.wine_arch) != "" ? Utils.normalize_wine_arch (entry.wine_arch) : "win64";
        vars["REGION"] = entry.region;
        merge_vars (vars, installer_spec.variables);
        if (launcher != null) merge_vars (vars, launcher.variables);
        if (post_install != null) merge_vars (vars, post_install.variables);
        resolve_prefix_launch_vars (vars, entry);
        Utils.resolve_var_references (vars);
        return vars;
    }

    private void resolve_prefix_launch_vars (Gee.HashMap<string, string> vars, Models.PrefixEntry entry) {
        var keys = new Gee.ArrayList<string> ();
        foreach (var k in vars.keys) keys.add (k);
        foreach (var k in keys) {
            var raw = vars[k];
            if (!raw.has_prefix ("@prefix:")) continue;
            var field = raw.substring (8);
            string? resolved = null;
            switch (field) {
                case "region":         resolved = entry.region; break;
                case "wine_arch":      resolved = entry.wine_arch; break;
                case "runner_id":      resolved = entry.runner_id; break;
                case "variant_id":     resolved = entry.variant_id; break;
                case "launcher_id":    resolved = entry.launcher_id; break;
                case "sync_mode":      resolved = entry.sync_mode; break;
                default: break;
            }
            if (resolved != null) vars[k] = resolved;
        }
    }

    private void merge_vars (Gee.HashMap<string, string> dst, Gee.HashMap<string, string> src) {
        foreach (var e in src.entries) {
            dst[e.key] = e.value;
        }
    }

    private Models.LauncherSpec? find_launcher_by_id (
        Gee.ArrayList<Models.LauncherSpec> specs,
        string id
    ) {
        foreach (var spec in specs) {
            if (spec.id == id) return spec;
        }
        return null;
    }

    private void apply_entrypoint (
        Models.Entrypoint ep,
        Gee.HashMap<string, string> vars,
        out string exe,
        out string[] args
    ) {
        exe = Utils.expand_vars (ep.exe, vars);
        var arg_list = new string[ep.args.size];
        for (int i = 0; i < ep.args.size; i++) {
            arg_list[i] = Utils.expand_vars (ep.args[i], vars);
        }
        args = arg_list;
    }

    private void expand_entrypoints (
        Gee.ArrayList<Models.Entrypoint> target,
        Gee.ArrayList<Models.Entrypoint> source,
        Gee.HashMap<string, string> vars
    ) {
        foreach (var ep in source) {
            if (ep.when != null && !ep.when.evaluate (vars)) continue;
            var copy = new Models.Entrypoint ();
            copy.id = ep.id;
            copy.name = ep.name;
            copy.label = ep.label;
            copy.exe = Utils.expand_vars (ep.exe, vars);
            copy.is_default = ep.is_default;
            copy.prelaunch_script = ep.prelaunch_script;
            copy.args = new Gee.ArrayList<string> ();
            copy.args.add_all (ep.args);
            target.add (copy);
        }
    }

    private string[] arraylist_to_strv (Gee.ArrayList<string> list) {
        var result = new string[list.size];
        for (int i = 0; i < list.size; i++) {
            result[i] = list[i];
        }
        return result;
    }

    private Models.Entrypoint? find_entrypoint (Gee.ArrayList<Models.Entrypoint> eps, string id) {
        if (id != "") {
            foreach (var ep in eps) {
                if (ep.id == id) return ep;
            }
        }
        foreach (var ep in eps) {
            if (ep.is_default) return ep;
        }
        if (eps.size > 0) return eps[0];
        return null;
    }

}
