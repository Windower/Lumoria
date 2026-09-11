namespace Lumoria.Cli {

    private void print_usage () {
        stdout.printf (_("Usage: lumoria <command> [options]\n\n"));
        stdout.printf (_("Commands:\n"));
        stdout.printf ("  version                    %s\n", _("Print version"));
        stdout.printf ("  help                       %s\n", _("Show this help"));
        stdout.printf ("  list                       %s\n", _("List configured prefixes"));
        stdout.printf ("  launch <prefix-id|--quick> [--entrypoint ID] [--exe PATH] [--offline|--interactive]\n");
        stdout.printf ("                             %s\n", _("Launch a prefix or the Quick Launch target"));
        stdout.printf ("  action <prefix-id> <action-id>\n");
        stdout.printf ("                             %s\n", _("Run a prefix action"));
        stdout.printf ("  remove <prefix-id> [--delete-files]\n");
        stdout.printf ("                             %s\n", _("Remove a prefix from the list"));
        stdout.printf ("  stop [<prefix-id>|--pid N]  %s\n", _("Stop a running prefix or wrap process"));
        stdout.printf ("  update-manifests            %s\n", _("Fetch and apply Lumoria manifest updates"));
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
                return run_with_context (cmd_list);
            case "launch":
                return run_with_context ((ctx) => cmd_launch (ctx, args));
            case "action":
                return run_with_context ((ctx) => cmd_action (ctx, args));
            case "remove":
                return run_with_context ((ctx) => cmd_remove (ctx, args));
            case "stop":
                return run_with_context ((ctx) => cmd_stop (ctx, args));
            case "update-manifests":
                return run_with_context (cmd_update_manifests);
            default:
                stderr.printf (_("Unknown command: %s\n"), cmd);
                print_usage ();
                return 1;
        }
    }

    private delegate int ContextCommand (Application.Context ctx);

    private int run_with_context (owned ContextCommand command) {
        Application.Context? ctx = null;
        try {
            ctx = new Application.Context ();
            return command (ctx);
        } catch (Error e) {
            stderr.printf ("%s\n", user_error (e));
            return 1;
        } finally {
            if (ctx != null) ctx.shutdown ();
        }
    }

    private int cmd_list (Application.Context ctx) {
        foreach (var p in ctx.registry.prefixes) {
            stdout.printf ("%s\t%s\t%s\n", p.id, p.display_name (), p.resolved_path ());
            try {
                var default_target = ctx.actions.default_launch (p);
                var default_id = default_target != null ? default_target.id : "";
                foreach (var target in ctx.actions.list (p)) {
                    var default_suffix = target.id == default_id ? " [default]" : "";
                    stdout.printf ("  %s\t%s%s\n", target.id, target.selector_label, default_suffix);
                }
            } catch (Error e) {
                stderr.printf ("%s: %s\n", p.id, user_error (e));
            }
        }
        return 0;
    }

    private int cmd_launch (Application.Context ctx, string[] args) {
        bool quick = false;
        string prefix_id = "";
        bool ep_set = false;
        string ep_arg = "";
        string exe_path = "";
        var policy = Runtime.LaunchPolicy.OFFLINE_FAST_START;
        for (int i = 2; i < args.length; i++) {
            if (args[i] == "--quick") {
                quick = true;
            } else if (args[i] == "--offline") {
                policy = Runtime.LaunchPolicy.OFFLINE_FAST_START;
            } else if (args[i] == "--interactive") {
                policy = Runtime.LaunchPolicy.INTERACTIVE;
            } else if (args[i] == "--entrypoint" && i + 1 < args.length) {
                ep_set = true;
                ep_arg = args[i + 1];
                i++;
            } else if (args[i] == "--exe" && i + 1 < args.length) {
                exe_path = args[i + 1];
                i++;
            } else if (args[i] == "--lumoria-shortcut-id" && i + 1 < args.length) {
                i++;
            } else if (!args[i].has_prefix ("-") && prefix_id == "") {
                prefix_id = args[i];
            } else {
                return launch_usage ();
            }
        }

        if (quick) {
            if (ctx.state.quick_launch.is_empty ()) {
                stderr.printf ("%s\n", _("No Quick Launch target is set."));
                return 1;
            }
            prefix_id = ctx.state.quick_launch.prefix_id;
        } else if (prefix_id == "") {
            return launch_usage ();
        }

        var entry = ctx.registry.by_id (prefix_id);
        if (entry == null) {
            stderr.printf ("%s\n", _("Prefix not found: %s").printf (prefix_id));
            return 1;
        }

        try {
            ctx.prefixes.require_access (entry);
            if (ep_set && exe_path == "") {
                return dispatch_entrypoint (ctx, entry, ep_arg, policy);
            }
            ctx.launches.launch_now (entry, ep_set ? ep_arg : "", exe_path, policy);
        } catch (Error e) {
            stderr.printf ("%s\n", user_error (e));
            return 1;
        }
        return 0;
    }

    private int dispatch_entrypoint (
        Application.Context ctx,
        Models.PrefixEntry entry,
        string entrypoint_id,
        Runtime.LaunchPolicy policy
    ) throws Error {
        Runtime.LaunchTarget? found = null;
        try {
            found = ctx.actions.find (entry, entrypoint_id);
            if (found == null) found = find_local_target (ctx, entry, entrypoint_id);
        } catch (Error e) {
            warning ("Launch catalog lookup failed for %s: %s", entrypoint_id, e.message);
        }
        if (found != null && found.is_action) {
            return run_cli_action (ctx, entry, found.id);
        }
        ctx.launches.launch_now (entry, found != null ? found.id : entrypoint_id, "", policy);
        return 0;
    }

    private Runtime.LaunchTarget? find_local_target (
        Application.Context ctx,
        Models.PrefixEntry entry,
        string entrypoint_id
    ) throws Error {
        foreach (var target in ctx.actions.list (entry)) {
            string instance_id;
            string local_id;
            if (Models.PrefixAction.parse_script_id (target.id, out instance_id, out local_id)
                && local_id == entrypoint_id) {
                return target;
            }
        }
        return null;
    }

    private int run_cli_action (
        Application.Context ctx,
        Models.PrefixEntry entry,
        string action_id
    ) {
        var progress = new Runtime.InstallProgress ();
        var ok = false;
        var message = "";
        progress.step_changed.connect ((desc) => {
            if (desc != "") stdout.printf ("%s\n", desc);
        });
        progress.install_finished.connect ((success, msg) => {
            ok = success;
            message = msg;
        });
        try {
            ctx.installs.run_action_now (entry, action_id, progress);
        } catch (Error e) {
            stderr.printf ("%s\n", user_error (e));
            return 1;
        }
        if (!ok) {
            if (message != "") stderr.printf ("%s\n", message);
            return 1;
        }
        return 0;
    }

    private int launch_usage () {
        stderr.printf (_("Usage: lumoria launch <prefix-id|--quick> [--entrypoint ID] [--exe PATH] [--offline|--interactive]\n"));
        return 1;
    }

    private int cmd_action (Application.Context ctx, string[] args) {
        if (args.length < 4) {
            stderr.printf (_("Usage: lumoria action <prefix-id> <action-id>\n"));
            return 1;
        }
        var entry = ctx.registry.by_id (args[2]);
        if (entry == null) {
            stderr.printf ("%s\n", _("Prefix not found: %s").printf (args[2]));
            return 1;
        }
        try {
            ctx.prefixes.require_access (entry);
        } catch (Error e) {
            stderr.printf ("%s\n", user_error (e));
            return 1;
        }
        return run_cli_action (ctx, entry, args[3]);
    }

    private int cmd_remove (Application.Context ctx, string[] args) {
        string prefix_id = "";
        bool delete_files = false;
        for (int i = 2; i < args.length; i++) {
            if (args[i] == "--delete-files") {
                delete_files = true;
            } else if (!args[i].has_prefix ("-") && prefix_id == "") {
                prefix_id = args[i];
            } else {
                stderr.printf (_("Usage: lumoria remove <prefix-id> [--delete-files]\n"));
                return 1;
            }
        }
        if (prefix_id == "") {
            stderr.printf (_("Usage: lumoria remove <prefix-id> [--delete-files]\n"));
            return 1;
        }
        var entry = ctx.registry.by_id (prefix_id);
        if (entry == null) {
            stderr.printf ("%s\n", _("Prefix not found: %s").printf (prefix_id));
            return 1;
        }
        try {
            ctx.prefixes.require_access (entry);
        } catch (Error e) {
            stderr.printf ("%s\n", user_error (e));
            return 1;
        }
        var loop = new MainLoop ();
        Error? err = null;
        ctx.prefixes.remove (entry, delete_files, (e) => {
            err = e;
            loop.quit ();
        });
        loop.run ();
        if (err != null) {
            stderr.printf ("%s\n", user_error (err));
            return 1;
        }
        return 0;
    }

    private int cmd_stop (Application.Context ctx, string[] args) {
        string prefix_id = "";
        int pid = 0;
        bool pid_set = false;
        for (int i = 2; i < args.length; i++) {
            if (args[i] == "--pid" && i + 1 < args.length) {
                int64 parsed;
                if (!int64.try_parse (args[i + 1], out parsed) || parsed <= 0 || parsed > int.MAX) {
                    stderr.printf ("%s\n", _("Invalid pid: %s").printf (args[i + 1]));
                    return 1;
                }
                pid = (int) parsed;
                pid_set = true;
                i++;
            } else if (!args[i].has_prefix ("-") && prefix_id == "") {
                prefix_id = args[i];
            } else {
                stderr.printf (_("Usage: lumoria stop [<prefix-id>|--pid N]\n"));
                return 1;
            }
        }
        try {
            if (pid_set) {
                session_stop_pid (pid);
                return 0;
            }
            if (prefix_id != "") {
                var entry = ctx.registry.by_id (prefix_id);
                if (entry == null) {
                    stderr.printf ("%s\n", _("Prefix not found: %s").printf (prefix_id));
                    return 1;
                }
                if (Utils.Preferences.instance ().session_manager) {
                    session_stop_prefix (prefix_id);
                } else {
                    Runtime.try_stop_prefix_wineserver (entry, ctx.runner_manifests);
                }
                return 0;
            }
            if (Utils.Preferences.instance ().session_manager) {
                session_stop_all ();
                return 0;
            }
            stderr.printf ("%s\n", _("Specify a prefix id or --pid when Session Manager is off."));
            return 1;
        } catch (Error e) {
            stderr.printf ("%s\n", user_error (e));
            return 1;
        }
    }

    private int cmd_update_manifests (Application.Context ctx) {
        try {
            var result = ctx.manifest_updates.check (true);
            stdout.printf ("%s\n", result.message);
            if (result.status != Application.ManifestUpdateStatus.AVAILABLE || result.remote == null) {
                return result.status == Application.ManifestUpdateStatus.DISABLED ? 1 : 0;
            }
            ctx.manifest_updates.apply (result.remote);
            stdout.printf ("%s\n", _("Manifests updated"));
            return 0;
        } catch (Error e) {
            stderr.printf ("%s\n", user_error (e));
            return 1;
        }
    }
}
