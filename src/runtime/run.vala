namespace Lumoria.Runtime {
    private const string FEATURE_WAYLAND_PRIMARY_MONITOR = "wayland-primary-monitor";

    public class RunResult : Object {
        public int pid { get; set; default = 0; }
        public string executable { get; set; default = ""; }
        public string log_path { get; set; default = ""; }
    }

    public enum UpdateDecision {
        UPDATE,
        STAY,
        CANCEL
    }

    public class PendingUpdate : Object {
        public string label { get; set; default = ""; }
        public string current_version { get; set; default = ""; }
        public string new_version { get; set; default = ""; }
        public bool is_runner { get; set; default = false; }
        public string component_id { get; set; default = ""; }
    }

    public delegate UpdateDecision UpdateDecisionCallback (Gee.ArrayList<PendingUpdate> updates);
    public delegate void UpdateDecisionHandler (UpdateDecision decision);

    private void require_prefix_path (Models.PrefixEntry entry) throws Error {
        if (entry.resolved_path () == "")
            throw new LumoriaError.NOT_FOUND (_("Prefix path is required"));
    }

    public RunResult run_prefix (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        Gee.ArrayList<Models.LauncherManifest> launcher_manifests,
        string entrypoint_id = "",
        string custom_exe = "",
        string[]? custom_wine_args = null,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        RuntimeStatusCallback? status_cb = null,
        UpdateDecisionCallback? update_decision_cb = null
    ) throws Error {
        var manifests = make_manifest_context (entry, launcher_manifests);
        var launch_plan = resolve_launch_plan (manifests, entrypoint_id, custom_exe, custom_wine_args);
        var exe = launch_plan.executable;
        var wine_args = launch_plan.args;
        var active_entrypoint = launch_plan.entrypoint;
        var active_entrypoint_id = launch_plan.entrypoint_id;
        RuntimeLog logger;
        var ctx = begin_run_session (
            entry, runner_manifests, false, active_entrypoint,
            launch_policy, status_cb, update_decision_cb, out logger
        );
        apply_launch_env (manifests, custom_exe != "" ? "" : active_entrypoint_id, ctx.env, ctx.paths, logger);
        apply_entrypoint_runtime_overrides (active_entrypoint, ctx.env, logger);
        apply_wayland_primary_monitor (entry, runner_manifests, ctx.env, logger);
        apply_runtime_logging_policy (ctx.env);
        apply_dxvk_config (entry.resolved_path (), entry, active_entrypoint, ctx.env, logger);

        exe = finalize_launch_text (exe, ctx.paths, ctx.env, logger);
        for (int i = 0; i < wine_args.length; i++) {
            wine_args[i] = finalize_launch_text (wine_args[i], ctx.paths, ctx.env, logger);
        }
        var host_exe = resolve_host_path (exe, ctx.prefix_path);
        var wine_path = to_wine_path (ctx.prefix_path, host_exe);
        var wine_argv = new Gee.ArrayList<string> ();
        wine_argv.add (ctx.paths.wine);

        var work_dir = Path.get_dirname (host_exe);
        if (!FileUtils.test (work_dir, FileTest.IS_DIR)) {
            work_dir = ctx.prefix_path;
        }
        wine_argv.add (host_exe);
        foreach (var arg in wine_args) wine_argv.add (arg);

        write_run_log_header (logger, entry, host_exe, wine_path, work_dir, wine_argv, ctx.env);

        if (!FileUtils.test (host_exe, FileTest.EXISTS)) {
            var err_msg = _("Executable not found: %s").printf (host_exe);
            logger.typed (LogType.ERROR, err_msg);
            throw new LumoriaError.NOT_FOUND ("%s", err_msg);
        }

        if (custom_exe == "") {
            apply_prelaunch_patches (entry, host_exe, logger);
        }

        var argv = wine_argv;
        if (!Utils.EnvironmentInfo.is_gamescope ()) {
            var prelaunch_work_dir = ctx.prefix_path;
            argv = wrap_with_prelaunch (
                entrypoint_prelaunch_script (manifests, active_entrypoint, active_entrypoint_id),
                prelaunch_work_dir,
                argv
            );
            argv = wrap_with_prelaunch (
                Utils.resolve_user_path (entry.prelaunch_script, entry.prelaunch_script_portal),
                prelaunch_work_dir,
                argv
            );
        }

        return spawn_wrapped_process (
            host_exe, work_dir, argv, ctx.env, logger,
            entry.id, ctx.paths.wineserver
        );
    }

    public RunResult run_prefix_command (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        Gee.ArrayList<string> wine_args,
        string command_label,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        RuntimeStatusCallback? status_cb = null,
        UpdateDecisionCallback? update_decision_cb = null
    ) throws Error {
        RuntimeLog logger;
        var ctx = begin_run_session (
            entry, runner_manifests, true, null,
            launch_policy, status_cb, update_decision_cb, out logger
        );
        apply_launch_env (make_manifest_context (entry, null), "", ctx.env, ctx.paths, logger);
        apply_runtime_logging_policy (ctx.env);
        var argv = new Gee.ArrayList<string> ();
        argv.add (ctx.paths.wine);
        argv.add_all (wine_args);

        write_run_command_log_header (logger, entry, command_label, argv, ctx.env);

        var work_dir = ctx.prefix_path;
        if (!FileUtils.test (work_dir, FileTest.IS_DIR)) {
            work_dir = entry.resolved_path ();
        }

        return spawn_wrapped_process (
            command_label, work_dir, argv, ctx.env, logger,
            entry.id, ctx.paths.wineserver
        );
    }

    public class TerminalContext : Object {
        public string working_directory { get; set; default = ""; }
        public Gee.HashMap<string, string> env_vars { get; set; }
    }

    public TerminalContext prepare_prefix_terminal_context (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        UpdateDecisionCallback? update_decision_cb = null
    ) throws Error {
        RuntimeLog logger;
        var ctx = begin_run_session (
            entry, runner_manifests, false, null,
            LaunchPolicy.INTERACTIVE, null, update_decision_cb, out logger
        );
        apply_launch_env (make_manifest_context (entry, null), "", ctx.env, ctx.paths, logger);
        apply_runtime_logging_policy (ctx.env);

        var result = new TerminalContext ();
        result.working_directory = entry.resolved_path ();
        result.env_vars = ctx.env.snapshot_vars ();
        return result;
    }

    /* Custom entries carry literal picker paths; manifest entries may use ${var.*} and prefix-relative paths. */
    private string entrypoint_prelaunch_script (
        ManifestContext manifests,
        Models.Entrypoint? ep,
        string entrypoint_id
    ) {
        if (ep == null || ep.prelaunch_script == "") return "";
        if (manifests.entry.custom_entrypoint (entrypoint_id) != null) {
            return Utils.resolve_user_path (ep.prelaunch_script, ep.prelaunch_script_portal);
        }
        return resolve_host_path (Utils.expand_vars (ep.prelaunch_script, manifests.vars), manifests.pfx_path);
    }

    private Gee.ArrayList<string> wrap_with_prelaunch (
        string prelaunch_script,
        string prelaunch_work_dir,
        Gee.ArrayList<string> wine_argv
    ) {
        if (prelaunch_script == "" || !FileUtils.test (prelaunch_script, FileTest.EXISTS)) {
            return wine_argv;
        }

        var argv = new Gee.ArrayList<string> ();
        argv.add ("bash");
        argv.add ("-c");
        argv.add ("__lumoria_script=\"$1\"; __lumoria_cwd=\"$2\"; __lumoria_launch_cwd=\"$PWD\"; shift 2; __lumoria_argv=(\"$@\"); cd \"$__lumoria_cwd\" && source \"$__lumoria_script\" && cd \"$__lumoria_launch_cwd\" && exec \"${__lumoria_argv[@]}\"");
        argv.add ("--");
        argv.add (prelaunch_script);
        argv.add (prelaunch_work_dir);
        foreach (var arg in wine_argv) argv.add (arg);
        return argv;
    }

    private WineRuntime begin_run_session (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        bool disable_mscoree,
        Models.Entrypoint? active_entrypoint,
        LaunchPolicy launch_policy,
        RuntimeStatusCallback? status_cb,
        UpdateDecisionCallback? update_decision_cb,
        out RuntimeLog logger
    ) throws Error {
        require_prefix_path (entry);
        logger = RuntimeLog.for_run (entry.resolved_path (), generate_session_id ());
        return prepare_runtime_context (
            entry, runner_manifests, disable_mscoree, logger, active_entrypoint,
            launch_policy, status_cb, update_decision_cb
        );
    }

    private WineRuntime prepare_runtime_context (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        bool disable_mscoree,
        RuntimeLog logger,
        Models.Entrypoint? active_entrypoint,
        LaunchPolicy launch_policy = LaunchPolicy.INTERACTIVE,
        RuntimeStatusCallback? status_cb = null,
        UpdateDecisionCallback? update_decision_cb = null
    ) throws Error {
        var runner_manifest = Models.RunnerManifest.resolve_for_entry (runner_manifests, entry);
        confirm_pending_updates (entry, runner_manifest, logger, launch_policy, update_decision_cb);
        var runtime_request = WineRuntimeRequest.from_prefix (entry, runner_manifest, launch_policy);
        var runtime = prepare_wine_runtime (runtime_request, logger);
        ensure_prefix_runner_ready (entry, runtime, logger, true, launch_policy, status_cb);

        if (disable_mscoree) {
            runtime.env.set_dll_override ("mscoree", DLL_DISABLED);
        }
        runtime.env.set_dll_overrides (apply_enabled_components (
            runtime.paths,
            runtime.prefix_path,
            entry,
            active_entrypoint,
            logger,
            launch_policy
        ).dll_overrides);
        runtime.env.set_dll_overrides (entry.runtime_dll_overrides);
        if (entry.runtime_dll_overrides.size > 0) {
            logger.typed (LogType.DEBUG, "applied prefix runtime dll overrides");
        }
        return runtime;
    }

    public Gee.ArrayList<PendingUpdate> list_pending_updates (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        RuntimeLog? logger = null
    ) throws Error {
        var log = logger ?? new RuntimeLog ();
        var runner_manifest = Models.RunnerManifest.resolve_for_entry (runner_manifests, entry);
        return collect_pending_updates (entry, runner_manifest, log);
    }

    private Gee.ArrayList<PendingUpdate> collect_pending_updates (
        Models.PrefixEntry entry,
        Models.RunnerManifest runner_manifest,
        RuntimeLog logger
    ) {
        var pending = new Gee.ArrayList<PendingUpdate> ();
        var prefs = Utils.Preferences.instance ();
        if (prefs.updates_runners) {
            var runner_update = pending_runner_update (entry, runner_manifest, logger);
            if (runner_update != null) pending.add (runner_update);
        }
        if (prefs.updates_components) {
            collect_pending_component_updates (entry, pending, logger);
        }
        return pending;
    }

    private void confirm_pending_updates (
        Models.PrefixEntry entry,
        Models.RunnerManifest runner_manifest,
        RuntimeLog logger,
        LaunchPolicy launch_policy,
        UpdateDecisionCallback? decision_cb
    ) throws Error {
        if (decision_cb == null || launch_policy != LaunchPolicy.INTERACTIVE) return;

        var pending = collect_pending_updates (entry, runner_manifest, logger);
        if (pending.size == 0) return;

        switch (decision_cb (pending)) {
            case UpdateDecision.STAY:
                pin_current_versions (entry, pending, logger);
                break;
            case UpdateDecision.CANCEL:
                throw new IOError.CANCELLED ("Launch cancelled");
            default:
                break;
        }
    }

    private PendingUpdate? pending_runner_update (
        Models.PrefixEntry entry,
        Models.RunnerManifest runner_manifest,
        RuntimeLog logger
    ) {
        var state = entry.runner_state;
        if (state == null || state.resolved_version == "") return null;
        if (state.runner_id != runner_manifest.id) return null;

        var requested = Utils.Preferences.resolve_version (runner_manifest.id, entry.runner_version);
        if (Models.ToolVersionRef.is_pinned (requested)) return null;

        string latest;
        try {
            var variant = runner_manifest.effective_variant (entry.variant_id);
            if (state.variant_id != "" && state.variant_id != variant.id) return null;
            latest = new Runtime.RunnerToolAdapter (runner_manifest, entry.variant_id).resolve_latest_tag ();
        } catch (Error e) {
            logger.typed (LogType.WARN, "Update check failed for %s: %s".printf (runner_manifest.id, e.message));
            return null;
        }
        if (latest == "" || latest == state.resolved_version) return null;

        var update = new PendingUpdate ();
        update.is_runner = true;
        update.label = runner_manifest.display_label ();
        update.current_version = state.resolved_version;
        update.new_version = latest;
        return update;
    }

    private void pin_current_versions (
        Models.PrefixEntry entry,
        Gee.ArrayList<PendingUpdate> pending,
        RuntimeLog logger
    ) throws Error {
        foreach (var update in pending) {
            apply_version_pin (entry, update);
            logger.typed (LogType.DEBUG, "pinned %s to %s".printf (update.label, update.current_version));
        }

        persist_prefix_now (entry);
    }

    private void apply_version_pin (Models.PrefixEntry entry, PendingUpdate update) {
        if (update.is_runner) {
            entry.runner_version = update.current_version;
            return;
        }
        entry.apply_component_version (update.component_id, update.current_version);
    }

    private void apply_wayland_primary_monitor (
        Models.PrefixEntry entry,
        Gee.ArrayList<Models.RunnerManifest> runner_manifests,
        WineEnv env,
        RuntimeLog logger
    ) {
        var connector = entry.wayland_primary_monitor.strip ();
        if (connector == "") return;

        try {
            var runner = Models.RunnerManifest.resolve_for_entry (runner_manifests, entry);
            var variant = runner.effective_variant (entry.variant_id);
            if (!variant.supports_feature (FEATURE_WAYLAND_PRIMARY_MONITOR)) return;

            env.set_var ("WAYLANDDRV_PRIMARY_MONITOR", connector);
            logger.typed (LogType.DEBUG, "applied Wayland primary monitor: %s".printf (connector));
        } catch (Error e) {
            logger.typed (LogType.WARN, "Failed to resolve Wayland primary monitor support: %s".printf (e.message));
        }
    }

    private void apply_entrypoint_runtime_overrides (
        Models.Entrypoint? entrypoint,
        WineEnv env,
        RuntimeLog logger
    ) {
        if (entrypoint == null) return;
        if (entrypoint.runtime_env_overrides.size > 0) {
            apply_env_overrides (env, entrypoint.runtime_env_overrides);
            logger.typed (LogType.DEBUG, "applied entrypoint runtime env overrides");
        }
        env.set_dll_overrides (entrypoint.runtime_dll_overrides);
        if (entrypoint.runtime_dll_overrides.size > 0) {
            logger.typed (LogType.DEBUG, "applied entrypoint runtime dll overrides");
        }
    }

    private void write_log_header_common (
        RuntimeLog logger,
        Models.PrefixEntry entry,
        Gee.ArrayList<string> detail_lines,
        string cmd_line,
        WineEnv env
    ) {
        var sandbox_kind = Utils.EnvironmentInfo.is_flatpak () ? "flatpak" : "none";
        logger.banner ("Lumoria Run Log", false);
        logger.emit_line ("Version: %s\n".printf (Config.APP_VERSION));
        var uts = Posix.utsname ();
        var os_name = release_file_value ("os-release", "PRETTY_NAME")
            ?? release_file_value ("os-release", "NAME")
            ?? release_file_value ("lsb-release", "DISTRIB_DESCRIPTION")
            ?? uts.sysname;
        var os_build = release_file_value ("os-release", "BUILD_ID");
        var os_line = os_build != null ? "%s (build: %s)".printf (os_name, os_build) : os_name;
        logger.emit_line ("OS: %s\n".printf (os_line));
        logger.emit_line ("Kernel: %s %s (%s)\n".printf (uts.sysname, uts.release, uts.machine));
        logger.emit_line ("Started: %s\n".printf (Utils.log_time ()));
        logger.emit_line ("Prefix: %s\n".printf (entry.resolved_path ()));
        logger.emit_line ("Context: gamescope=%s sandbox=%s\n".printf (
            Utils.EnvironmentInfo.is_gamescope () ? "yes" : "no",
            sandbox_kind
        ));
        logger.emit_line ("Session: DESKTOP_SESSION=%s XDG_SESSION_DESKTOP=%s XDG_CURRENT_DESKTOP=%s\n".printf (
            Environment.get_variable ("DESKTOP_SESSION") ?? "",
            Environment.get_variable ("XDG_SESSION_DESKTOP") ?? "",
            Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? ""
        ));
        foreach (var line in detail_lines) {
            logger.emit_line ("%s\n".printf (line));
        }
        logger.typed (LogType.CMD, cmd_line);
        env.log_wine_vars (logger);
        logger.emit_line ("\n");
    }

    private string? release_file_value (string filename, string key) {
        var path = Utils.EnvironmentInfo.host_etc_path (filename);
        return Utils.key_value_file_value (path, key, unquote_os_release_value);
    }

    private string unquote_os_release_value (string value) {
        var trimmed = value.strip ();
        if (trimmed.length >= 2) {
            var first = trimmed[0];
            var last = trimmed[trimmed.length - 1];
            if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
                return trimmed.substring (1, trimmed.length - 2);
            }
        }
        return trimmed;
    }

    private void write_run_log_header (
        RuntimeLog logger,
        Models.PrefixEntry entry,
        string host_exe,
        string wine_path,
        string work_dir,
        Gee.ArrayList<string> argv,
        WineEnv env
    ) {
        var detail_lines = new Gee.ArrayList<string> ();
        detail_lines.add ("Executable: %s".printf (host_exe));
        detail_lines.add ("Wine path: %s".printf (wine_path));
        detail_lines.add ("Working dir: %s".printf (work_dir));
        write_log_header_common (
            logger, entry, detail_lines,
            string.joinv (" ", Utils.strv (argv)),
            env
        );
    }

    private void write_run_command_log_header (
        RuntimeLog logger,
        Models.PrefixEntry entry,
        string command_label,
        Gee.ArrayList<string> argv,
        WineEnv env
    ) {
        var detail_lines = new Gee.ArrayList<string> ();
        detail_lines.add ("Command: %s".printf (command_label));
        write_log_header_common (
            logger, entry, detail_lines,
            string.joinv (" ", Utils.strv (argv)),
            env
        );
    }

    private bool ensure_session_manager () {
        if (Cli.session_ping ()) return true;

        var socket_path = Cli.session_socket_path ();
        try {
            Utils.ensure_private_dir (Path.get_dirname (socket_path));
        } catch (Error e) {
            warning ("Failed to create session manager socket directory: %s", e.message);
            return false;
        }
        FileUtils.unlink (socket_path);
        try {
            Pid session_pid;
            Process.spawn_async (
                null,
                session_manager_spawn_argv (),
                null,
                SpawnFlags.SEARCH_PATH,
                null,
                out session_pid
            );
        } catch (Error e) {
            warning ("Session manager self-spawn failed: %s", e.message);
            return false;
        }

        for (int i = 0; i < 10; i++) {
            Posix.usleep (100 * 1000);
            if (Cli.session_ping ()) return true;
        }

        warning ("Session manager did not respond after 1s");
        return false;
    }

    private string[] session_manager_spawn_argv () throws Error {
        var self_exe = Utils.current_executable_path ();
        if (self_exe == null)
            throw new IOError.FAILED ("could not resolve self executable path");

        return { self_exe, "session-manager" };
    }

    private int session_launch (
        string prefix_id,
        string wineserver_path,
        string log_path,
        string[] env,
        string work_dir,
        string[] argv
    ) throws Error {
        var data = Cli.session_call ("launch", (obj) => {
            obj.set_string_member ("prefix_id", prefix_id);
            obj.set_string_member ("wineserver", wineserver_path);
            obj.set_string_member ("log_path", log_path);
            obj.set_string_member ("cwd", work_dir);
            obj.set_array_member ("env", Models.strv_to_json_array (env));
            obj.set_array_member ("argv", Models.strv_to_json_array (argv));
        });
        return (int) data.get_int_member ("pid");
    }

    private string[] wine_env_lines (WineEnv env) {
        var lines = new Gee.ArrayList<string> ();
        foreach (var e in env.snapshot_vars ().entries) {
            lines.add ("%s=%s".printf (e.key, e.value));
        }
        return Utils.strv (lines);
    }

    private RunResult spawn_wrapped_process (
        string executable_label,
        string work_dir,
        Gee.ArrayList<string> argv,
        WineEnv env,
        RuntimeLog logger,
        string prefix_id = "",
        string wineserver_path = ""
    ) throws Error {
        var log_path = logger.log_path;

        logger.close ();

        if (Utils.Preferences.instance ().session_manager) {
            if (!ensure_session_manager ()) {
                throw new LumoriaError.FAILED (_("Session manager is enabled but could not be started."));
            }
            var pid = session_launch (
                prefix_id, wineserver_path,
                log_path, wine_env_lines (env), work_dir,
                Utils.strv (argv)
            );
            var managed = new RunResult ();
            managed.pid = pid;
            managed.executable = executable_label;
            managed.log_path = log_path;
            return managed;
        }

        var child = Utils.spawn_wrap (
            log_path, work_dir, string.joinv ("\n", wine_env_lines (env)), Utils.strv (argv)
        );

        var run_result = new RunResult ();
        run_result.pid = int.parse (child.get_identifier ());
        run_result.executable = executable_label;
        run_result.log_path = log_path;
        return run_result;
    }

    private string generate_session_id () {
        return "%08x-%04x".printf (
            (uint32) GLib.get_real_time (),
            (uint16) GLib.Random.next_int ()
        );
    }

}
