namespace Lumoria.Utils {
    public class DiagnosticLog : Object {
        public string path;
        public string name;
        public string category;
        public int64 size;
        public uint64 modified;
        public bool selected;
    }

    public class PrefixDiagnostics : Object {
        public const int LOG_LIMIT = 128 * 1024;
        private const string CATEGORY_PREFIX = "Prefix";
        private const string CATEGORY_SESSION_MANAGER = "Session manager";

        private const string[] ENV_KEYS = {
            "WINEPREFIX", "WINEARCH", "WINEDLLOVERRIDES", "WINEDEBUG",
            "WINEESYNC", "WINEFSYNC", "WINENTSYNC", "WINE_LARGE_ADDRESS_AWARE",
            "PATH", "LD_LIBRARY_PATH", "WINEDLLPATH",
            "DISPLAY", "WAYLAND_DISPLAY", "WAYLANDDRV_PRIMARY_MONITOR",
            "XDG_RUNTIME_DIR", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP",
            "DXVK_HUD", "DXVK_CONFIG_FILE", "DXVK_LOG_LEVEL", "VKD3D_CONFIG", "VKD3D_DEBUG",
            "SDL_VIDEODRIVER", "PULSE_SERVER", "XLOCALEDIR",
            "WINE_USE_EGL", "WINE_DISABLE_FULLSCREEN_HACK", "WINE_MOVE_HACK",
        };
        private const string[] SECRET_MARKERS = {
            "PASSWORD", "SECRET", "TOKEN", "CREDENTIAL", "AUTHORIZATION", "API_KEY", "PRIVATE_KEY",
        };
        private const string[] REGISTRY_FILES = { "user.reg", "system.reg" };
        private const string INVENTORY_ATTRIBUTES =
            "standard::name,standard::type,standard::is-symlink,standard::symlink-target,"
            + "standard::size,owner::user,unix::mode,unix::uid,unix::nlink";

        public string report { get; private set; default = ""; }
        public Gee.ArrayList<DiagnosticLog> logs = new Gee.ArrayList<DiagnosticLog> ();

        private string raw_report = "";
        private string root;
        private string header;
        private string configuration;
        private Runtime.RunnerToolAdapter? runner_adapter;
        private Gee.ArrayList<string> identities = new Gee.ArrayList<string> ();
        private Gee.ArrayList<Regex> identity_patterns = new Gee.ArrayList<Regex> ();

        public PrefixDiagnostics (Models.PrefixEntry entry) {
            root = entry.resolved_path ();
            var prefs = Preferences.instance ();
            var repo = Models.ManifestRepository.shared ();

            var b = new StringBuilder ("# Lumoria prefix diagnostics\n\n");
            field (b, "Collected", new DateTime.now_utc ().format_iso8601 ());
            header = b.str;
            b = new StringBuilder ();
            append_prefix_summary (b, entry, repo);
            append_system (b);
            append_preferences (b, prefs);
            append_runner (b, entry, prefs, repo);
            append_components (b, entry, prefs, repo);
            append_overrides (b, entry, repo);
            append_process_environment (b);
            b.append ("\n## Installed packages\n");
            foreach (var redist in entry.installed_redists) b.append ("- " + redist + "\n");
            if (entry.installed_redists.size == 0) b.append ("- (none)\n");
            configuration = b.str;

            add_identity (Environment.get_user_name ());
            add_identity (Environment.get_host_name ());
        }

        public string report_text (bool sanitized = false) {
            return sanitized ? report : raw_report;
        }

        public void collect (Cancellable cancel) throws Error {
            var b = new StringBuilder (header);
            append_session_manager (b);
            b.append (configuration);
            var paths = Runtime.PrefixPaths.from_root (root);
            add_wine_user_identities (paths);
            append_installed_runners (b);
            append_registry (b, paths, cancel);
            b.append ("\n## DLLs\n");
            inventory (b, paths.system32, cancel);
            inventory (b, paths.syswow64, cancel);
            append_logs (b);
            raw_report = b.str;
            report = sanitize (raw_report);
        }

        public string sanitize (string text) {
            var result = text;
            foreach (var pattern in identity_patterns) {
                try {
                    result = pattern.replace_literal (result, -1, 0, "[user]");
                } catch (RegexError e) {
                    warning ("Sanitizer failed: %s", e.message);
                }
            }
            return result;
        }

        public void export_zip (
            File destination,
            Gee.List<DiagnosticLog> selected,
            bool sanitize_logs,
            Cancellable cancel,
            bool sanitize_report = false
        ) throws Error {
            string temp;
            int fd = FileUtils.open_tmp ("lumoria-diagnostics-XXXXXX", out temp);
            try {
                var zip = new Archive.Write ();
                if (zip.set_format_zip () != Archive.Result.OK || zip.open_fd (fd) != Archive.Result.OK) {
                    throw new IOError.FAILED ("Could not create diagnostics ZIP");
                }
                zip_text (zip, "report.txt", report_text (sanitize_report));
                foreach (var log in selected) {
                    cancel.set_error_if_cancelled ();
                    var folder = log.category == CATEGORY_PREFIX ? "prefix" : "session-manager";
                    zip_log (zip, Path.build_filename ("logs", folder, log.name), log, sanitize_logs, cancel);
                }
                if (zip.close () != Archive.Result.OK) {
                    throw new IOError.FAILED ("Could not finish diagnostics ZIP");
                }
                cancel.set_error_if_cancelled ();
                File.new_for_path (temp).copy (destination, FileCopyFlags.OVERWRITE, cancel);
            } finally {
                Posix.close (fd);
                FileUtils.unlink (temp);
            }
        }

        public static string read_text (string path, Cancellable cancel) throws Error {
            int64 size;
            var input = open_regular_file (path, out size);
            var bytes = new ByteArray ();
            uint8[] chunk = new uint8[16384];
            ssize_t count;
            while ((count = input.read (chunk, cancel)) > 0) {
                if (bytes.len + count > LOG_LIMIT) {
                    bytes.append (chunk[0:LOG_LIMIT - bytes.len]);
                    break;
                }
                bytes.append (chunk[0:count]);
            }
            bytes.append ({ 0 });
            unowned string text = (string) bytes.data;
            if (text.length != bytes.len - 1 || !text.validate ()) {
                throw new IOError.FAILED ("Not a UTF-8 text file: %s", path);
            }
            return text;
        }

        private void append_prefix_summary (StringBuilder b, Models.PrefixEntry entry, Models.ManifestRepository repo) {
            string architecture = entry.wine_arch;
            try {
                architecture = Models.RunnerManifest.resolve_for_entry (repo.all_runners, entry)
                    .effective_variant (entry.variant_id)
                    .effective_arch (entry.wine_arch);
            } catch (Error e) {
                if (architecture == "") architecture = "unknown";
            }
            b.append ("## Application and prefix\n");
            field (b, "Lumoria", Config.APP_VERSION);
            field (b, "Installation", EnvironmentInfo.is_flatpak () ? "Flatpak" : "Native");
            field (b, "Prefix", entry.id);
            field (b, "Path", path_label (root));
            field (b, "Installer", entry.installer_id);
            field (b, "Launcher", entry.launcher_id);
            field (b, "Region", entry.region);
            field (b, "Architecture", architecture);
        }

        private static void append_preferences (StringBuilder b, Preferences prefs) {
            b.append ("\n## Preferences\n");
            var names = new Gee.ArrayList<string> ();
            foreach (var property in prefs.get_class ().list_properties ()) {
                if (property.name != "load-error") names.add (property.name);
            }
            names.sort ();
            foreach (var name in names) {
                field (b, name.replace ("-", " "), preference_text (prefs, name));
            }
            field (b, "Steam userdata", path_label (prefs.resolved_steam_userdata_dir ()));
            append_map (b, "Global environment", prefs.get_runtime_env_vars (), true);
        }

        private static string preference_text (Preferences prefs, string name) {
            string text;
            if (name == "startup-view") {
                text = prefs.startup_view.to_key ();
            } else {
                var value = Value (prefs.get_class ().find_property (name).value_type);
                prefs.get_property (name, ref value);
                text = value.type () == typeof (string) ? (value.get_string () ?? "") : value.strdup_contents ();
            }
            return text == "" ? "default" : text;
        }

        private void append_runner (
            StringBuilder b,
            Models.PrefixEntry entry,
            Preferences prefs,
            Models.ManifestRepository repo
        ) {
            var runner = Preferences.effective_runner_id (entry.runner_id);
            b.append ("\n## Runner\n");
            field (b, "Runner", entry.runner_id != "" ? runner : "%s (global default)".printf (runner));

            var spec = Models.find_by_id<Models.RunnerManifest> (repo.all_runners, runner);
            if (spec != null) {
                runner_adapter = new Runtime.RunnerToolAdapter (spec, entry.variant_id);
                try {
                    var variant = spec.effective_variant (entry.variant_id);
                    field (b, "Variant", variant.id);
                } catch (Error e) {
                    field (b, "Variant", entry.variant_id);
                    field (b, "Runner configuration error", e.message);
                }
            } else {
                field (b, "Variant", entry.variant_id);
                field (b, "Runner configuration error", "no manifest for " + runner);
            }

            field (b, "Version setting", runner_version_setting (runner, entry));
            field (b, "Installed in prefix", installed_runner_version (runner, entry));
            field (b, "Runner updates", prefs.updates_runners ? "enabled (asks before updating)" : "disabled");

            field (b, "Use runner libxkbcommon", entry.use_runner_libxkbcommon.to_string ());
            field (b, "Sync", Preferences.resolve_sync_mode (entry.sync_mode).id ());
            field (b, "Wine debug", wine_debug_text (prefs, entry));
            field (b, "Wayland", inherit_or (entry.wine_wayland));
            field (b, "Prelaunch script configured", (entry.prelaunch_script != "").to_string ());
            field (b, "Large address aware", inherit_or (entry.large_address_aware));
            field (b, "Wayland primary monitor", entry.wayland_primary_monitor);
            field (b, "DXVK FPS display", entry.dxvk_show_fps.to_string ());
            field (b, "DXVK anisotropy", entry.dxvk_sampler_anisotropy);
            field (b, "DXVK max frame rate", entry.dxvk_max_frame_rate);
            field (b, "DXVK sync interval", entry.dxvk_sync_interval);
            field (b, "Custom DXVK config present", (entry.dxvk_config_custom != "").to_string ());
        }

        private static string runner_version_setting (string runner, Models.PrefixEntry entry) {
            var resolved = Preferences.resolve_version (runner, entry.runner_version);
            if (Models.ToolVersionRef.is_inherit (entry.runner_version)) {
                return "inherit global default (%s)".printf (resolved);
            }
            return Models.ToolVersionRef.is_pinned (resolved) ? "pinned to " + resolved : resolved;
        }

        private static string installed_runner_version (string runner, Models.PrefixEntry entry) {
            var state = entry.runner_state;
            if (state == null || state.resolved_version == "") {
                return "no version recorded, prefix not launched";
            }
            if (state.runner_id != runner) {
                return "%s %s (switches to %s on next launch)".printf (
                    state.runner_id, state.resolved_version, runner
                );
            }
            return state.resolved_version;
        }

        private static string wine_debug_text (Preferences prefs, Models.PrefixEntry entry) {
            if (!prefs.keep_runtime_logs) return "-all (logging disabled)";
            var debug = Preferences.resolve_wine_debug (entry.wine_debug);
            return debug == "" ? "default" : debug;
        }

        private static string inherit_or (bool? value) {
            return value == null ? "inherit" : ((bool) value).to_string ();
        }

        private static void append_components (
            StringBuilder b,
            Models.PrefixEntry entry,
            Preferences prefs,
            Models.ManifestRepository repo
        ) {
            b.append ("\n## Components\n");
            foreach (var spec in repo.all_components) {
                var ov = entry.runtime_component_overrides[spec.id];
                var installed = entry.applied_components[spec.id];
                b.append ("- " + spec.id + "\n");
                field (b, "Enabled", component_enabled_text (spec.id, ov, prefs), 2);
                field (b, "Version setting", component_version_setting (spec.id, ov, prefs), 2);
                field (b, "Installed in prefix", installed == null ? "none" : installed.version, 2);
                if (installed != null && installed.installed_files.size > 0) {
                    b.append ("  - Files:\n");
                    foreach (var path in installed.installed_files) b.append ("    - " + code (path) + "\n");
                }
                append_map (b, "Manifest DLL overrides", spec.overrides, false, 2);
                append_map (b, "Component environment defaults", spec.system_env_defaults, true, 2);
                if (ov != null) append_map (b, "Prefix component environment", ov.system_env, true, 2);
            }
        }

        private static string component_enabled_text (
            string id,
            Models.RuntimeComponentOverride? ov,
            Preferences prefs
        ) {
            if (ov != null && ov.enabled != null) {
                return "%s (prefix override)".printf (((bool) ov.enabled).to_string ());
            }
            return "%s (global)".printf (prefs.is_component_enabled (id).to_string ());
        }

        private static string component_version_setting (
            string id,
            Models.RuntimeComponentOverride? ov,
            Preferences prefs
        ) {
            if (ov != null && Models.ToolVersionRef.is_pinned (ov.version)) {
                return "pinned to %s (prefix override)".printf (ov.version);
            }
            var global = prefs.get_tool_version (ToolKind.COMPONENT, id);
            if (Models.ToolVersionRef.is_pinned (global)) return "pinned to %s (global)".printf (global);
            return "%s (global)".printf (global);
        }

        private static void append_overrides (
            StringBuilder b,
            Models.PrefixEntry entry,
            Models.ManifestRepository repo
        ) {
            b.append ("\n## Configured overrides\n");
            append_map (b, "Prefix DLL overrides", entry.runtime_dll_overrides, false);
            append_map (b, "Prefix environment", entry.runtime_env_vars, true);

            var installer = repo.installer (entry.installer_id);
            var launcher = Models.find_by_id<Models.LauncherManifest> (repo.launchers, entry.launcher_id);
            if (installer != null) append_rules (b, "Installer environment rules", installer.env);
            if (launcher != null) append_rules (b, "Launcher environment rules", launcher.env);

            var seen = new Gee.HashSet<string> ();
            if (installer != null) {
                foreach (var ep in installer.entrypoints) append_unique_entrypoint (b, seen, "Installer", ep);
            }
            if (launcher != null) {
                foreach (var ep in launcher.entrypoints) append_unique_entrypoint (b, seen, "Launcher", ep);
            }
            foreach (var ep in entry.custom_entrypoints) append_unique_entrypoint (b, seen, "Custom", ep);
        }

        private static void append_process_environment (StringBuilder b) {
            b.append ("\n## Environment\n");
            var lines = new Gee.ArrayList<string> ();
            foreach (var key in ENV_KEYS) {
                var value = Environment.get_variable (key);
                if (value != null) lines.add (key + "=" + value);
            }
            code_block (b, lines);
        }

        private void append_installed_runners (StringBuilder b) {
            if (runner_adapter == null) return;
            var latest = runner_adapter.latest_installed_tag ();
            b.append ("\n## Installed runners\n");
            field (b, "Latest installed", latest == "" ? "unknown" : latest);
            try {
                var base_dir = runner_adapter.install_base_dir;
                var dir = Dir.open (base_dir);
                var names = new Gee.ArrayList<string> ();
                string? name;
                while ((name = dir.read_name ()) != null) {
                    if (FileUtils.test (Path.build_filename (base_dir, name), FileTest.IS_DIR)) names.add (name);
                }
                names.sort ();
                foreach (var local_name in names) field (b, "Local runner directory", code (local_name));
            } catch (Error e) {
                field (b, "Runner directory unavailable", e.message);
            }
        }

        private static void append_system (StringBuilder b) {
            b.append ("\n## System\n");
            var distro = key_value_file_value (EnvironmentInfo.host_etc_path ("os-release"), "PRETTY_NAME");
            if (distro != null) field (b, "Distribution", distro.replace ("\"", ""));
            var kernel = Posix.utsname ();
            field (b, "Kernel", kernel.sysname + " " + kernel.release);
            field (b, "Architecture", kernel.machine);
            if (!EnvironmentInfo.is_flatpak ()) return;
            try {
                var info = new KeyFile ();
                info.load_from_file ("/.flatpak-info", KeyFileFlags.NONE);
                field (b, "Flatpak runtime", info.get_string ("Application", "runtime"));
            } catch (Error e) {
                field (b, "Flatpak runtime", "unavailable");
            }
        }

        private static void append_registry (
            StringBuilder b,
            Runtime.PrefixPaths paths,
            Cancellable cancel
        ) throws Error {
            b.append ("\n## Wine registry\n");
            foreach (var name in REGISTRY_FILES) {
                cancel.set_error_if_cancelled ();
                b.append ("### " + name + "\n");
                try {
                    var file = File.new_for_path (Path.build_filename (paths.wine_prefix, name));
                    var input = new DataInputStream (file.read (cancel));
                    var lines = new Gee.ArrayList<string> ();
                    bool include = false;
                    string? line;
                    while ((line = input.read_line (null, cancel)) != null) {
                        if (line.has_prefix ("[")) include = registry_section_wanted (line);
                        if (include) lines.add (line.make_valid ());
                    }
                    code_block (b, lines);
                } catch (IOError.CANCELLED e) {
                    throw e;
                } catch (Error e) {
                    field (b, "Unavailable", e.message);
                }
            }
        }

        private static bool registry_section_wanted (string header) {
            var section = header.down ().replace ("\\\\", "\\");
            if (!section.has_prefix ("[software\\wine\\")) return false;
            return section.contains ("\\dlloverrides]")
                || section.contains ("\\fonts\\replacements]")
                || section.has_prefix ("[software\\wine\\drivers]")
                || section.has_prefix ("[software\\wine\\direct3d]");
        }

        private static void inventory (StringBuilder b, string directory, Cancellable cancel) throws Error {
            b.append ("### " + Path.get_basename (directory) + "\n");
            try {
                var dir = File.new_for_path (directory);
                var children = dir.enumerate_children (
                    INVENTORY_ATTRIBUTES,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    cancel
                );
                var rows = new Gee.ArrayList<string> ();
                FileInfo? info;
                while ((info = children.next_file (cancel)) != null) {
                    if (!info.get_name ().down ().has_suffix (".dll")) continue;
                    rows.add (describe_dll (dir.get_child (info.get_name ()), info, cancel));
                }
                rows.sort ();
                b.append ("| File | Size | Mode | Owner | Notes |\n|---|---|---|---|---|\n");
                foreach (var row in rows) b.append (row + "\n");
            } catch (IOError.CANCELLED e) {
                throw e;
            } catch (Error e) {
                field (b, "Unavailable", e.message);
            }
        }

        private static string describe_dll (File file, FileInfo info, Cancellable cancel) {
            var name = info.get_name ();
            string[] notes = {};
            var hard_links = info.get_attribute_uint32 ("unix::nlink");
            if (hard_links > 1) notes += "%u hard links".printf (hard_links);
            if (info.get_is_symlink ()) {
                notes += "symlink to " + code (info.get_symlink_target () ?? "unknown");
                try {
                    var target = file.query_info ("unix::mode", FileQueryInfoFlags.NONE, cancel);
                    notes += "target mode %04o".printf (target.get_attribute_uint32 ("unix::mode") & 07777);
                } catch (Error e) {
                    notes += "target unavailable";
                }
            }
            return "| %s | %s | %04o | %s (%u) | %s |".printf (
                code (name),
                format_size (info.get_size ()),
                info.get_attribute_uint32 ("unix::mode") & 07777,
                info.get_attribute_string ("owner::user") ?? "unknown",
                info.get_attribute_uint32 ("unix::uid"),
                string.joinv ("; ", notes)
            );
        }

        private void append_logs (StringBuilder b) {
            logs.clear ();
            scan_logs (prefix_log_dir (root), CATEGORY_PREFIX, b);
            scan_logs (session_manager_log_dir (), CATEGORY_SESSION_MANAGER, b);
            logs.sort ((a, z) => {
                if (a.modified != z.modified) return a.modified > z.modified ? -1 : 1;
                return strcmp (a.name, z.name);
            });
            var newest_launch = newest_recorded_log ("run");
            var newest_install = newest_recorded_log ("install");
            b.append ("\n## Available Lumoria logs\n");
            foreach (var log in logs) {
                log.selected = log == newest_launch || log == newest_install;
                field (b, log.category, "%s (%s)".printf (code (log.name), format_size (log.size)));
            }
            if (logs.size == 0) b.append ("- (none)\n");
        }

        private void scan_logs (string directory, string category, StringBuilder report) {
            try {
                var dir = File.new_for_path (directory);
                var children = dir.enumerate_children (
                    "standard::name,standard::type,standard::size,time::modified",
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                );
                FileInfo? info;
                while ((info = children.next_file ()) != null) {
                    if (info.get_file_type () != FileType.REGULAR || !info.get_name ().has_suffix (".log")) continue;
                    var log = new DiagnosticLog ();
                    log.path = dir.get_child (info.get_name ()).get_path ();
                    log.name = info.get_name ();
                    log.category = category;
                    log.size = info.get_size ();
                    log.modified = info.get_attribute_uint64 ("time::modified");
                    logs.add (log);
                }
            } catch (IOError.NOT_FOUND e) {
            } catch (Error e) {
                field (report, "Log directory unavailable (" + category + ")", e.message);
            }
        }

        private DiagnosticLog? newest_recorded_log (string kind) {
            DiagnosticLog? latest = null;
            try {
                var pattern = new Regex ("^" + kind + "-[0-9]{8}-[0-9]{6}(?:-[^/]+)?\\.log$");
                foreach (var log in logs) {
                    if (log.category != CATEGORY_PREFIX || !pattern.match (log.name)) continue;
                    if (latest == null || strcmp (log.name, latest.name) > 0) latest = log;
                }
            } catch (RegexError e) {
                warning ("Invalid diagnostic log pattern: %s", e.message);
            }
            return latest;
        }

        private static void append_session_manager (StringBuilder b) {
            string message;
            switch (Cli.session_probe (out message)) {
                case Cli.SessionStatus.READY:
                    field (b, "Session manager", "reachable");
                    break;
                case Cli.SessionStatus.ABSENT:
                    field (b, "Session manager", "not running");
                    break;
                default:
                    field (b, "Session manager", "unavailable (" + message + ")");
                    break;
            }
        }

        private void add_identity (string name) {
            if (name == "" || identities.contains (name)) return;
            try {
                identity_patterns.add (new Regex (
                    "(?<![\\p{L}\\p{N}_-])" + Regex.escape_string (name) + "(?![\\p{L}\\p{N}_-])",
                    RegexCompileFlags.CASELESS
                ));
                identities.add (name);
            } catch (RegexError e) {
                warning ("Cannot build sanitizer for identity: %s", e.message);
            }
        }

        private void add_wine_user_identities (Runtime.PrefixPaths paths) {
            try {
                var users = Dir.open (Path.build_filename (paths.drive_c, "users"));
                string? name;
                while ((name = users.read_name ()) != null) {
                    var lower = name.down ();
                    if (lower != "public" && lower != "default") add_identity (name);
                }
            } catch (FileError e) {
            }
        }

        private static void field (StringBuilder b, string name, string value, int indent = 0) {
            b.append_printf ("%s- %s: %s\n", string.nfill (indent, ' '), name, value);
        }

        private static string code (string value) {
            return value == "" ? "" : "`" + value + "`";
        }

        private static string path_label (string path) {
            var host = portal_host_path (path);
            return host == "" ? code (path) : "%s (host: %s)".printf (code (path), code (host));
        }

        private static void code_block (StringBuilder b, Gee.List<string> lines) {
            b.append ("```\n");
            foreach (var line in lines) b.append (line + "\n");
            b.append ("```\n");
        }

        private static void append_map (
            StringBuilder b,
            string title,
            Gee.Map<string, string> map,
            bool env,
            int indent = 0
        ) {
            var keys = new Gee.ArrayList<string> ();
            keys.add_all (map.keys);
            keys.sort ();
            if (keys.size == 0) {
                field (b, title, "(none)", indent);
                return;
            }
            b.append_printf ("%s- %s:\n", string.nfill (indent, ' '), title);
            foreach (var key in keys) {
                var value = env && looks_secret (key) ? "[omitted]" : map[key];
                b.append_printf ("%s- %s\n", string.nfill (indent + 2, ' '), code (key + "=" + value));
            }
        }

        private static void append_rules (
            StringBuilder b,
            string title,
            Gee.List<Models.EnvRule> rules,
            int indent = 0
        ) {
            foreach (var rule in rules) {
                var kind = rule.when == null ? " (unconditional)" : " (conditional)";
                append_map (b, title + kind, rule.vars, true, indent);
            }
        }

        private static bool looks_secret (string key) {
            var upper = key.up ();
            foreach (var marker in SECRET_MARKERS) {
                if (upper.contains (marker)) return true;
            }
            return false;
        }

        private static void append_unique_entrypoint (
            StringBuilder b,
            Gee.Set<string> seen,
            string source,
            Models.Entrypoint ep
        ) {
            if (ep.env.size == 0
                && ep.runtime_dll_overrides.size == 0
                && ep.runtime_env_overrides.size == 0
                && ep.component_overrides.size == 0) {
                return;
            }
            var section = new StringBuilder ();
            field (section, source + " entrypoint", ep.id);
            append_rules (section, "Environment rules", ep.env, 2);
            append_map (section, "DLL overrides", ep.runtime_dll_overrides, false, 2);
            append_map (section, "Environment overrides", ep.runtime_env_overrides, true, 2);
            if (seen.add (section.str)) b.append (section.str);
        }

        private static UnixInputStream open_regular_file (string path, out int64 size) throws Error {
            int fd = Posix.open (path, Posix.O_RDONLY | Posix.O_NONBLOCK | Posix.O_NOFOLLOW);
            if (fd < 0) throw new IOError.FAILED ("Cannot open %s: %s", path, Posix.strerror (Posix.errno));
            var input = new UnixInputStream (fd, true);
            Posix.Stat st;
            if (Posix.fstat (fd, out st) != 0 || !Posix.S_ISREG (st.st_mode)) {
                throw new IOError.FAILED ("Not a regular file: %s", path);
            }
            size = st.st_size;
            return input;
        }

        private static void begin_zip_member (Archive.Write zip, string name, int64 size) throws Error {
            var entry = new Archive.Entry ();
            entry.set_pathname (name);
            entry.set_filetype (Archive.FileType.IFREG);
            entry.set_perm (0600);
            entry.set_size ((Archive.int64_t) size);
            if (zip.write_header (entry) != Archive.Result.OK) {
                throw new IOError.FAILED ("Could not write diagnostics ZIP: %s", zip.error_string ());
            }
        }

        private static void finish_zip_member (Archive.Write zip) throws Error {
            if (zip.finish_entry () != Archive.Result.OK) {
                throw new IOError.FAILED ("Could not write diagnostics ZIP: %s", zip.error_string ());
            }
        }

        private static void zip_text (Archive.Write zip, string name, string text) throws Error {
            begin_zip_member (zip, name, text.length);
            if (zip.write_data (text.data) != text.length) {
                throw new IOError.FAILED ("Could not write diagnostics ZIP: %s", zip.error_string ());
            }
            finish_zip_member (zip);
        }

        private void zip_log (
            Archive.Write zip,
            string member,
            DiagnosticLog log,
            bool sanitized,
            Cancellable cancel
        ) throws Error {
            int64 size;
            InputStream source = open_regular_file (log.path, out size);
            string? staging = null;
            try {
                if (sanitized) {
                    staging = write_sanitized_copy (source, size, cancel);
                    var copy = File.new_for_path (staging);
                    source = copy.read (cancel);
                    size = copy.query_info ("standard::size", FileQueryInfoFlags.NONE, cancel).get_size ();
                }
                begin_zip_member (zip, member, size);
                uint8[] buffer = new uint8[65536];
                int64 remaining = size;
                while (remaining > 0) {
                    var count = source.read (buffer[0:(int) int64.min (remaining, buffer.length)], cancel);
                    if (count == 0) throw new IOError.FAILED ("Log changed during export: %s", log.name);
                    if (zip.write_data (buffer[0:count]) != count) {
                        throw new IOError.FAILED ("Could not write diagnostics ZIP: %s", zip.error_string ());
                    }
                    remaining -= count;
                }
                finish_zip_member (zip);
            } finally {
                if (staging != null) FileUtils.unlink (staging);
            }
        }

        private string write_sanitized_copy (InputStream input, int64 size, Cancellable cancel) throws Error {
            string staging;
            int fd = FileUtils.open_tmp ("lumoria-log-XXXXXX", out staging);
            var output = new UnixOutputStream (fd, true);
            var lines = new DataInputStream (input);
            string? line = null;
            int64 consumed = 0;
            while (consumed < size && (line = lines.read_line (null, cancel)) != null) {
                int64 remaining = size - consumed;
                if (line.length > remaining) line = line.substring (0, (long) remaining);
                consumed += line.length;
                bool newline = consumed < size;
                if (newline) consumed++;
                var text = sanitize (line.make_valid ()) + (newline ? "\n" : "");
                size_t written;
                output.write_all (text.data, out written, cancel);
            }
            output.close (cancel);
            return staging;
        }
    }
}
