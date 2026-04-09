namespace Lumoria.Cli {

    private void print_usage () {
        stdout.printf (_("Usage: lumoria <command> [options]\n\n"));
        stdout.printf (_("Commands:\n"));
        stdout.printf ("  version                    %s\n", _("Print version"));
        stdout.printf ("  help                       %s\n", _("Show this help"));
        stdout.printf ("  list                       %s\n", _("List configured prefixes"));
        stdout.printf ("  launch <prefix-id> [--entrypoint ID] [--exe PATH]\n");
        stdout.printf ("                             %s\n", _("Launch a prefix"));
    }

    public int run (string[] args) {
        if (args.length < 2) {
            print_usage ();
            return 1;
        }
        var cmd = args[1];
        switch (cmd) {
            case "version":
                stdout.printf ("%s %s\n", Config.APP_NAME, Config.APP_VERSION);
                return 0;
            case "help":
            case "--help":
            case "-h":
                print_usage ();
                return 0;
            case "list":
                return cmd_list ();
            case "launch":
                return cmd_launch (args);
            default:
                stderr.printf (_("Unknown command: %s\n"), cmd);
                print_usage ();
                return 1;
        }
    }

    private int cmd_list () {
        var reg = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
        var launcher_specs = Models.LauncherSpec.load_all_from_resource ();
        foreach (var p in reg.prefixes) {
            stdout.printf ("%s\t%s\t%s\n", p.id, p.display_name (), p.resolved_path ());
            var active_target_id = Runtime.resolve_effective_entrypoint_id (p, launcher_specs);
            foreach (var target in Runtime.list_launch_targets (p, launcher_specs)) {
                var default_suffix = target.id == active_target_id ? " [default]" : "";
                stdout.printf ("  %s\t%s%s\n", target.id, target.selector_label, default_suffix);
            }
        }
        return 0;
    }

    private int cmd_launch (string[] args) {
        if (args.length < 3) {
            stderr.printf (_("Usage: lumoria launch <prefix-id> [--entrypoint ID] [--exe PATH]\n"));
            return 1;
        }
        var prefix_id = args[2];
        bool ep_set = false;
        string ep_arg = "";
        string exe_path = "";
        for (int i = 3; i < args.length; i++) {
            if (args[i] == "--entrypoint" && i + 1 < args.length) {
                ep_set = true;
                ep_arg = args[i + 1];
                i++;
            } else if (args[i] == "--exe" && i + 1 < args.length) {
                exe_path = args[i + 1];
                i++;
            }
        }

        var reg = Models.PrefixRegistry.load (Utils.prefix_registry_path ());
        var entry = reg.by_id (prefix_id);
        if (entry == null) {
            stderr.printf (_("Prefix not found: %s\n"), prefix_id);
            return 1;
        }
        if (entry.runner_id == "") {
            stderr.printf (_("No runner configured for this prefix.\n"));
            return 1;
        }

        var runner_specs = Models.RunnerSpec.filter_for_host (Models.RunnerSpec.load_all_from_resource ());
        var launcher_specs = Models.LauncherSpec.load_all_from_resource ();

        try {
            Runtime.run_prefix (
                entry,
                runner_specs,
                launcher_specs,
                ep_set ? ep_arg : "",
                exe_path
            );
        } catch (Error e) {
            stderr.printf ("%s\n", e.message);
            return 1;
        }
        return 0;
    }
}
