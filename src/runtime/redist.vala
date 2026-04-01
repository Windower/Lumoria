namespace Lumoria.Runtime {
    private delegate string RegFileRewriter (string data);

    public class RedistOptions : Object {
        public string cache_dir { get; set; default = ""; }
        public string prefix_path { get; set; default = ""; }
        public string wine_arch { get; set; default = "win64"; }
        public string wine_bin { get; set; default = ""; }
        public WineEnv wine_env { get; set; }
        public WinePaths paths { get; set; }
        public Cancellable? cancellable { get; set; default = null; }
    }

    public RedistOptions build_redist_options (
        string prefix_path,
        WinePaths paths,
        WineEnv env,
        Cancellable? cancellable = null
    ) {
        var opts = new RedistOptions ();
        opts.cache_dir = Utils.cache_dir ();
        opts.prefix_path = prefix_path;
        opts.wine_arch = env.get_var ("WINEARCH") ?? "win64";
        opts.wine_bin = paths.wine;
        opts.wine_env = env;
        opts.paths = paths;
        opts.cancellable = cancellable;
        return opts;
    }

    public void install_redist (string id, RedistOptions opts, RuntimeLog logger) throws Error {
        switch (id.down ()) {
            case "dotnet48":
                install_dotnet48 (opts, logger);
                break;
            default:
                throw new IOError.FAILED ("Unknown redist: %s (supported: dotnet48)", id);
        }
    }

    private void install_dotnet48 (RedistOptions opts, RuntimeLog logger) throws Error {
        if (opts.wine_bin == "")
            throw new IOError.FAILED ("dotnet48 requires wine binary");

        if (dotnet_already_installed (opts, logger)) {
            logger.emit_line (".NET Framework 4.8 already installed, skipping\n");
            return;
        }

        var cache = Path.build_filename (opts.cache_dir, "redist", "dotnet48");
        Utils.ensure_dir (cache);

        logger.emit_line ("Installing .NET Framework 4.0 (dependency)...\n");
        install_dotnet40 (opts, cache, logger);

        logger.emit_line ("Setting Windows version to win7...\n");
        set_winver (opts, "win7", logger);

        logger.emit_line ("Cleaning stale .NET 4.8 Release value...\n");
        strip_reg_value (opts, "\"Release\"=dword:", logger);

        var installer48 = Path.build_filename (cache, "ndp48-x86-x64-allos-enu.exe");
        require_cached_redist_installer (installer48, ".NET Framework 4.8", logger);

        logger.emit_line ("Running .NET Framework 4.8 installer (this may take several minutes)...\n");
        run_wine_installer (opts, installer48, { "/sfxlang:1027", "/q", "/norestart" }, logger);

        logger.emit_line ("Restoring Windows version to win10...\n");
        flush_wineserver (opts, logger);
        remove_netfxrepair (opts);
        set_winver_direct (opts, "win10", logger);

        logger.emit_line ("Setting mscoree DLL override to native...\n");
        set_dll_override (opts, "mscoree", DLL_NATIVE, logger);

        logger.emit_line ("Processing queued .NET native images...\n");
        run_ngen_executequeueditems (opts, logger);

        var mscorlib = Path.build_filename (
            opts.prefix_path, "drive_c", "windows", "Microsoft.NET",
            "Framework", "v4.0.30319", "mscorlib.dll"
        );
        int64 sz = 0;
        try {
            sz = File.new_for_path (mscorlib).query_info (
                FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE
            ).get_size ();
        } catch (Error e) {
            logger.typed (LogType.WARN, "Could not query mscorlib.dll size: %s".printf (e.message));
        }
        if (sz < 4 * 1024 * 1024) {
            throw new IOError.FAILED ("dotnet48 install appeared to succeed but mscorlib.dll is missing or too small (%s)", mscorlib);
        }

        logger.emit_line (".NET Framework 4.8 installation complete\n");
    }

    private void install_dotnet40 (RedistOptions opts, string cache, RuntimeLog logger) throws Error {
        var installer40 = Path.build_filename (cache, "dotNetFx40_Full_x86_x64.exe");
        require_cached_redist_installer (installer40, ".NET Framework 4.0", logger);

        set_winver (opts, "winxp", logger);

        run_wine_installer (opts, installer40, { "/q", "/c:install.exe /q" }, logger);

        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full",
            "/v", "Install", "/t", "REG_DWORD", "/d", "0001", "/f" }, logger);
        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full",
            "/v", "Version", "/t", "REG_SZ", "/d", "4.0.30319", "/f" }, logger);
        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\.NETFramework",
            "/v", "OnlyUseLatestCLR", "/t", "REG_DWORD", "/d", "0001", "/f" }, logger);

        if (Utils.normalize_wine_arch (opts.wine_arch) == "win64") {
            wine_reg (opts, { "add", "HKLM\\Software\\Wow6432Node\\.NETFramework",
                "/v", "OnlyUseLatestCLR", "/t", "REG_DWORD", "/d", "0001", "/f" }, logger);
        }

        set_dll_override (opts, "mscoree", DLL_NATIVE, logger);
    }

    private void run_ngen_executequeueditems (RedistOptions opts, RuntimeLog logger) {
        var ngen = Path.build_filename (
            opts.prefix_path, "drive_c", "windows", "Microsoft.NET",
            "Framework", "v4.0.30319", "ngen.exe"
        );
        if (FileUtils.test (ngen, FileTest.EXISTS)) {
            try {
                run_wine_command (opts.wine_bin, { ngen, "executequeueditems" },
                    opts.wine_env, null, logger, opts.cancellable);
            } catch (Error e) {
                logger.typed (LogType.DEBUG, "ngen executequeueditems failed (non-fatal): %s".printf (e.message));
            }
        }
    }

    private bool dotnet_already_installed (RedistOptions opts, RuntimeLog logger) {
        var fw = Path.build_filename (
            opts.prefix_path, "drive_c", "windows", "Microsoft.NET",
            "Framework", "v4.0.30319"
        );
        if (!FileUtils.test (Path.build_filename (fw, "clrjit.dll"), FileTest.EXISTS))
            return false;

        int64 mscorlib_sz = 0;
        try {
            mscorlib_sz = File.new_for_path (Path.build_filename (fw, "mscorlib.dll"))
                .query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE).get_size ();
        } catch (Error e) {
            logger.typed (LogType.WARN, "dotnet check: failed to query mscorlib.dll: %s".printf (e.message));
            return false;
        }
        if (mscorlib_sz < 4 * 1024 * 1024) return false;

        int64 mscoree_sz = 0;
        try {
            mscoree_sz = File.new_for_path (
                Path.build_filename (opts.prefix_path, "drive_c", "windows", "system32", "mscoree.dll")
            ).query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE).get_size ();
        } catch (Error e) {
            logger.typed (LogType.WARN, "dotnet check: failed to query mscoree.dll: %s".printf (e.message));
            return false;
        }

        return mscoree_sz >= 1024 * 1024;
    }

    private void run_wine_installer (RedistOptions opts, string exe_path, string[] args, RuntimeLog logger) throws Error {
        var env = opts.wine_env.copy ();
        env.add_dll_override ("fusion", DLL_BUILTIN);

        var wine_args = new string[args.length + 1];
        wine_args[0] = exe_path;
        for (int i = 0; i < args.length; i++) wine_args[i + 1] = args[i];

        try {
            run_wine_command (opts.wine_bin, wine_args, env, Path.get_dirname (exe_path), logger, opts.cancellable);
        } catch (IOError.FAILED e) {
            if (e.message.contains ("exit code 105") ||
                e.message.contains ("exit code 194") ||
                e.message.contains ("exit code 236")) {
                logger.emit_line ("Installer returned non-fatal exit code, continuing\n");
                return;
            }
            throw e;
        }
    }

    private void wine_reg (RedistOptions opts, string[] args, RuntimeLog logger) {
        var wine_args = new string[args.length + 1];
        wine_args[0] = "reg";
        for (int i = 0; i < args.length; i++) wine_args[i + 1] = args[i];
        try {
            run_wine_command (opts.wine_bin, wine_args, opts.wine_env, null, logger, opts.cancellable);
        } catch (Error e) {
            logger.typed (LogType.WARN, "wine reg command failed: %s".printf (e.message));
        }
    }

    private void set_dll_override (RedistOptions opts, string dll, string mode, RuntimeLog logger) throws Error {
        wine_reg (opts, { "add",
            "HKCU\\Software\\Wine\\DllOverrides",
            "/v", dll, "/t", "REG_SZ", "/d", mode, "/f" }, logger);
    }

    private void flush_wineserver (RedistOptions opts, RuntimeLog logger) {
        shutdown_wineserver (opts.paths, opts.wine_env, logger);
    }

    private struct WinVer {
        public string build_num;
        public string cur_ver;
        public string major_ver;
        public string minor_ver;
        public string csd;
        public string csd_dword;
    }

    private WinVer get_winver_values (string ver) {
        WinVer w = {};
        switch (ver) {
            case "winxp":
                w.build_num = "2600";
                w.cur_ver = "5.1";
                w.major_ver = "00000005";
                w.minor_ver = "00000001";
                w.csd = "Service Pack 3";
                w.csd_dword = "00000300";
                break;
            case "win7":
                w.build_num = "7601";
                w.cur_ver = "6.1";
                w.major_ver = "00000006";
                w.minor_ver = "00000001";
                w.csd = "Service Pack 1";
                w.csd_dword = "00000100";
                break;
            case "win10":
                w.build_num = "19041";
                w.cur_ver = "10.0";
                w.major_ver = "0000000a";
                w.minor_ver = "00000000";
                w.csd = "";
                w.csd_dword = "00000000";
                break;
            default:
                w.build_num = "";
                w.cur_ver = "";
                w.major_ver = "";
                w.minor_ver = "";
                w.csd = "";
                w.csd_dword = "";
                break;
        }
        return w;
    }

    private void set_winver (RedistOptions opts, string ver, RuntimeLog logger) {
        var w = get_winver_values (ver);
        if (w.build_num == "")
            return;

        wine_reg (opts, { "add", "HKCU\\Software\\Wine",
            "/v", "Version", "/t", "REG_SZ", "/d", ver, "/f" }, logger);

        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion",
            "/v", "CSDVersion", "/t", "REG_SZ", "/d", w.csd, "/f" }, logger);
        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion",
            "/v", "CurrentBuildNumber", "/t", "REG_SZ", "/d", w.build_num, "/f" }, logger);
        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion",
            "/v", "CurrentVersion", "/t", "REG_SZ", "/d", w.cur_ver, "/f" }, logger);
        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion",
            "/v", "CurrentBuild", "/t", "REG_SZ", "/d", w.build_num, "/f" }, logger);
        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion",
            "/v", "CurrentMajorVersionNumber", "/t", "REG_DWORD", "/d", w.major_ver, "/f" }, logger);
        wine_reg (opts, { "add", "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion",
            "/v", "CurrentMinorVersionNumber", "/t", "REG_DWORD", "/d", w.minor_ver, "/f" }, logger);

        wine_reg (opts, { "add", "HKLM\\System\\CurrentControlSet\\Control\\Windows",
            "/v", "CSDVersion", "/t", "REG_DWORD", "/d", w.csd_dword, "/f" }, logger);

        flush_wineserver (opts, logger);
        patch_reg_values (
            opts.prefix_path,
            build_winver_reg_map (w.build_num, w.cur_ver, w.major_ver, w.minor_ver),
            logger
        );
    }

    private void set_winver_direct (RedistOptions opts, string ver, RuntimeLog logger) {
        var w = get_winver_values (ver);
        if (w.build_num == "")
            return;

        patch_reg_values (
            opts.prefix_path,
            build_winver_reg_map (w.build_num, w.cur_ver, w.major_ver, w.minor_ver),
            logger
        );

        var user_reg = Path.build_filename (opts.prefix_path, "user.reg");
        rewrite_reg_file (user_reg, "winver restore", logger, (data) => {
            var lines = data.split ("\n");
            var output = new StringBuilder ();
            bool in_wine_section = false;
            foreach (var line in lines) {
                if (line.has_prefix ("[")) {
                    in_wine_section = line.contains ("Software\\\\Wine]");
                }
                if (in_wine_section && line.strip ().has_prefix ("\"Version\"=")) {
                    continue;
                }
                output.append (line);
                output.append_c ('\n');
            }
            return output.str;
        });
    }

    private void remove_netfxrepair (RedistOptions opts) {
        string[] paths = {
            Path.build_filename (opts.prefix_path, "drive_c", "windows", "Microsoft.NET", "NETFXRepair.exe"),
            Path.build_filename (opts.prefix_path, "drive_c", "windows", "Microsoft.NET", "Framework", "v4.0.30319", "NETFXRepair.exe"),
            Path.build_filename (opts.prefix_path, "drive_c", "windows", "Microsoft.NET", "Framework64", "v4.0.30319", "NETFXRepair.exe")
        };
        foreach (var p in paths) {
            FileUtils.remove (p);
        }
    }

    private void strip_reg_value (RedistOptions opts, string substr, RuntimeLog logger) {
        flush_wineserver (opts, logger);
        var reg_file = Path.build_filename (opts.prefix_path, "system.reg");
        rewrite_reg_file (reg_file, "strip_reg_value", logger, (data) => {
            var lines = data.split ("\n");
            var output = new StringBuilder ();
            foreach (var line in lines) {
                if (!line.contains (substr)) {
                    output.append (line);
                    output.append_c ('\n');
                }
            }
            return output.str;
        });
    }

    private Gee.HashMap<string, string> build_winver_reg_map (
        string build_num, string cur_ver, string major_ver, string minor_ver
    ) {
        var m = new Gee.HashMap<string, string> ();
        m["\"CurrentBuild\"="] = "\"CurrentBuild\"=\"" + build_num + "\"";
        m["\"CurrentBuildNumber\"="] = "\"CurrentBuildNumber\"=\"" + build_num + "\"";
        m["\"CurrentVersion\"="] = "\"CurrentVersion\"=\"" + cur_ver + "\"";
        m["\"CurrentMajorVersionNumber\"="] = "\"CurrentMajorVersionNumber\"=dword:" + major_ver;
        m["\"CurrentMinorVersionNumber\"="] = "\"CurrentMinorVersionNumber\"=dword:" + minor_ver;
        return m;
    }

    private void patch_reg_values (string prefix_path, Gee.HashMap<string, string> vals, RuntimeLog logger) {
        var reg_file = Path.build_filename (prefix_path, "system.reg");
        rewrite_reg_file (reg_file, "patch_reg_values", logger, (data) => {
            var lines = data.split ("\n");
            var output = new StringBuilder ();
            foreach (var line in lines) {
                var trimmed = line.strip ();
                bool replaced = false;
                foreach (var entry in vals.entries) {
                    if (trimmed.has_prefix (entry.key)) {
                        output.append (entry.value);
                        output.append_c ('\n');
                        replaced = true;
                        break;
                    }
                }
                if (!replaced) {
                    output.append (line);
                    output.append_c ('\n');
                }
            }
            return output.str;
        });
    }

    private void rewrite_reg_file (
        string reg_file,
        string action,
        RuntimeLog logger,
        owned RegFileRewriter rewrite
    ) {
        string data;
        try {
            FileUtils.get_contents (reg_file, out data);
        } catch (Error e) {
            logger.typed (LogType.WARN, "Could not read %s for %s: %s".printf (reg_file, action, e.message));
            return;
        }

        try {
            FileUtils.set_contents (reg_file, rewrite (data));
        } catch (Error e) {
            logger.typed (LogType.WARN, "Could not write %s for %s: %s".printf (reg_file, action, e.message));
        }
    }

    private void require_cached_redist_installer (string path, string name, RuntimeLog logger) throws Error {
        if (!FileUtils.test (path, FileTest.EXISTS) || Utils.file_size_or_zero (path) <= 0) {
            throw new IOError.FAILED (
                "%s installer is missing from cache: %s (download phase must complete first)",
                name, path
            );
        }
        logger.emit_line ("Using cached %s installer: %s\n".printf (name, path));
    }
}
