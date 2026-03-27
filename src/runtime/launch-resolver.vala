namespace Lumoria.Runtime {

    private const string DEFAULT_EXE = "drive_c/Program Files (x86)/PlayOnline/SquareEnix/FINAL FANTASY XI/polboot.exe";

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
        var installer_vars = new Gee.HashMap<string, string> ();
        installer_vars["PREFIX"] = pfx_path;
        foreach (var e in installer_spec.variables.entries) {
            installer_vars[e.key] = e.value;
        }

        if (entrypoint_id != "") {
            Models.Entrypoint? installer_ep = null;
            foreach (var ep in installer_spec.entrypoints) {
                if (ep.id == entrypoint_id) { installer_ep = ep; break; }
            }
            if (installer_ep != null) {
                exe = Utils.expand_vars (installer_ep.exe, installer_vars);
                var installer_arg_list = new string[installer_ep.args.size];
                for (int i = 0; i < installer_ep.args.size; i++) {
                    installer_arg_list[i] = Utils.expand_vars (installer_ep.args[i], installer_vars);
                }
                args = installer_arg_list;
                return;
            }
        }

        if (entry.launcher_id == "") return;

        Models.LauncherSpec? launcher = null;
        foreach (var spec in launcher_specs) {
            if (spec.id == entry.launcher_id) { launcher = spec; break; }
        }
        if (launcher == null) return;

        var vars = new Gee.HashMap<string, string> ();
        vars["PREFIX"] = pfx_path;
        foreach (var e in launcher.variables.entries) {
            vars[e.key] = e.value;
        }

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

        exe = Utils.expand_vars (ep.exe, vars);
        var arg_list = new string[ep.args.size];
        for (int i = 0; i < ep.args.size; i++) {
            arg_list[i] = Utils.expand_vars (ep.args[i], vars);
        }
        args = arg_list;
    }

    public Gee.ArrayList<Models.Entrypoint> list_entrypoints (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherSpec> launcher_specs
    ) {
        var all = new Gee.ArrayList<Models.Entrypoint> ();
        var pfx_path = install_prefix_path (entry.path);

        var installer_spec = Models.InstallerSpec.load_from_resource ();
        var base_vars = new Gee.HashMap<string, string> ();
        base_vars["PREFIX"] = pfx_path;
        foreach (var e in installer_spec.variables.entries) {
            base_vars[e.key] = e.value;
        }
        foreach (var ep in installer_spec.entrypoints) {
            var copy = new Models.Entrypoint ();
            copy.id = ep.id;
            copy.name = ep.name;
            copy.exe = Utils.expand_vars (ep.exe, base_vars);
            copy.is_default = ep.is_default;
            copy.args = ep.args;
            all.add (copy);
        }

        if (entry.launcher_id != "") {
            Models.LauncherSpec? launcher = null;
            foreach (var spec in launcher_specs) {
                if (spec.id == entry.launcher_id) { launcher = spec; break; }
            }
            if (launcher != null) {
                var vars = new Gee.HashMap<string, string> ();
                vars["PREFIX"] = pfx_path;
                foreach (var e in launcher.variables.entries) {
                    vars[e.key] = e.value;
                }
                foreach (var ep in launcher.entrypoints) {
                    var copy = new Models.Entrypoint ();
                    copy.id = ep.id;
                    copy.name = ep.name;
                    copy.exe = Utils.expand_vars (ep.exe, vars);
                    copy.is_default = ep.is_default;
                    copy.args = ep.args;
                    all.add (copy);
                }
            }
        }

        return all;
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
            Models.LauncherSpec? launcher = null;
            foreach (var spec in launcher_specs) {
                if (spec.id == entry.launcher_id) { launcher = spec; break; }
            }
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
