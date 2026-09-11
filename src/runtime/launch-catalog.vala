namespace Lumoria.Runtime {

    private delegate void AddPostInstallTarget (LaunchTarget target, string instance_id);

    public Gee.ArrayList<LaunchTarget> list_launch_targets (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests,
        Gee.ArrayList<Models.Entrypoint>? custom_list = null,
        Gee.ArrayList<string>? warnings = null,
        bool allow_network = true
    ) throws Error {
        var launcher_targets = new Gee.ArrayList<LaunchTarget> ();
        var profiles = new Gee.ArrayList<LaunchTarget> ();
        var launch = new Gee.ArrayList<LaunchTarget> ();
        var custom = new Gee.ArrayList<LaunchTarget> ();
        var post_by_manifest = new Gee.HashMap<string, Gee.ArrayList<LaunchTarget>> ();
        var ctx = make_manifest_context (entry, launcher_manifests);

        AddPostInstallTarget add_post_install = (target, instance_id) => {
            target.section = LaunchTargetSection.POST_INSTALL;
            target.group_title = post_install_group_title (entry, instance_id);
            var list = post_by_manifest.get (instance_id);
            if (list == null) {
                list = new Gee.ArrayList<LaunchTarget> ();
                post_by_manifest[instance_id] = list;
            }
            list.add (target);
        };

        var entrypoints = entrypoints_from_context (
            ctx,
            custom_list ?? entry.custom_entrypoints
        );
        foreach (var ep in entrypoints) {
            var target = launch_target_from_entrypoint (ep, ctx.launcher);
            string instance_id;
            string local_id;
            if (Models.PrefixAction.parse_script_id (ep.id, out instance_id, out local_id)) {
                add_post_install (target, instance_id);
                continue;
            }
            switch (target.section) {
                case LaunchTargetSection.CUSTOM:
                    custom.add (target);
                    break;
                case LaunchTargetSection.LAUNCHER:
                    launcher_targets.add (target);
                    break;
                default:
                    launch.add (target);
                    break;
            }
        }

        foreach (var ep in list_launcher_profile_entrypoints (ctx)) {
            var profile_name = launcher_profile_name_from_entry_id (ep.id) ?? ep.display_label ();
            profiles.add (launch_target_from_profile (ep.id, profile_name, ctx.launcher));
        }

        foreach (var action in actions_from_context (ctx, warnings, allow_network)) {
            var target = new LaunchTarget ();
            target.id = action.id;
            target.label = action.display_label ();
            target.selector_label = target.label;
            target.description = action.description;
            target.icon = action.icon;
            target.has_button = action.button.specified;
            target.button_label = action.button.label;
            target.button_style = action.button.style;
            target.button_icon = action.button.icon;
            target.is_action = true;
            target.spec = action;
            string instance_id;
            string local_id;
            if (Models.PrefixAction.parse_script_id (action.id, out instance_id, out local_id)) {
                add_post_install (target, instance_id);
            } else if (is_launcher_target_id (ctx.launcher, action.id)) {
                target.section = LaunchTargetSection.LAUNCHER;
                if (target.icon == "" && ctx.launcher != null && ctx.launcher.icon != "") {
                    target.icon = ctx.launcher.icon;
                }
                launcher_targets.add (target);
            } else {
                target.section = LaunchTargetSection.LAUNCH;
                launch.add (target);
            }
        }

        var targets = new Gee.ArrayList<LaunchTarget> ();
        foreach (var target in launcher_targets) targets.add (target);
        foreach (var target in profiles) targets.add (target);
        foreach (var target in custom) targets.add (target);
        foreach (var target in launch) targets.add (target);
        foreach (var spec in entry.post_install_manifests) {
            var list = post_by_manifest.get (spec.id);
            if (list == null) continue;
            foreach (var target in list) targets.add (target);
        }
        targets.add (LaunchTarget.open_folder (
            Models.PrefixAction.BUILTIN_OPEN_PREFIX,
            _("Open Prefix Folder"),
            entry.resolved_path ()
        ));
        var launcher_dir = launcher_dir_from_context (ctx);
        if (launcher_dir != "") {
            targets.add (LaunchTarget.open_folder (
                Models.PrefixAction.BUILTIN_OPEN_LAUNCHER,
                _("%s Folder").printf (
                    ctx.launcher != null ? ctx.launcher.display_label () : _("Launcher")
                ),
                launcher_dir
            ));
        }
        return targets;
    }

    public LaunchTarget? local_default_launch (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests
    ) {
        var installer = Models.ManifestRepository.shared ().installer (entry.installer_id);
        var launcher = Models.find_by_id<Models.LauncherManifest> (launcher_manifests, entry.launcher_id);
        var wanted = resolve_default_entrypoint_id (entry, launcher_manifests);
        if (wanted == "") return null;

        var profile_name = launcher_profile_name_from_entry_id (wanted);
        if (profile_name != null && launcher != null) {
            return launch_target_from_profile (wanted, profile_name, launcher);
        }
        var matched = find_local_entrypoint (
            wanted, launcher, installer, entry.custom_entrypoints, entry
        );
        if (matched == null) return null;
        var target = launch_target_from_entrypoint (matched, launcher);
        target.id = wanted;
        return target;
    }
}
