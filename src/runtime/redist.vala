namespace Lumoria.Runtime {

    /* A REGEDIT4 document built in memory; import it with import_registry in a single wine process. */
    public class RegFile : Object {
        private StringBuilder text = new StringBuilder ("REGEDIT4\r\n");

        public string contents {
            get { return text.str; }
        }

        public RegFile key (string path) {
            text.append ("\r\n[%s]\r\n".printf (path));
            return this;
        }

        public RegFile str (string name, string value) {
            text.append ("\"%s\"=\"%s\"\r\n".printf (escape (name), escape (value)));
            return this;
        }

        public RegFile dword (string name, uint32 value) {
            text.append ("\"%s\"=dword:%08x\r\n".printf (escape (name), value));
            return this;
        }

        private static string escape (string s) {
            return s.replace ("\\", "\\\\").replace ("\"", "\\\"");
        }
    }

    internal void import_registry (
        WinePaths paths,
        WineEnv env,
        RegFile reg,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var tmp_dir = DirUtils.make_tmp ("lumoria-reg-XXXXXX");
        try {
            var reg_path = Path.build_filename (tmp_dir, "import.reg");
            Utils.write_text_atomic (reg_path, reg.contents);
            run_wine_command_with_retry (
                paths,
                { "reg", "import", reg_path },
                env,
                null,
                logger,
                cancellable,
                "wine reg import failed; retrying once after wineserver shutdown"
            );
        } finally {
            Utils.remove_recursive (tmp_dir);
        }
    }

    internal void set_dll_override_in_registry (
        WinePaths paths,
        WineEnv env,
        string dll,
        string mode,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var reg = new RegFile ().key ("HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides").str (dll, mode);
        import_registry (paths, env, reg, logger, cancellable);
    }

    public void install_redist (
        string id,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        switch (id.down ()) {
            case "win7":
            case "win10":
                set_winver (id.down (), paths, env, logger, cancellable);
                break;
            default:
                throw new LumoriaError.INVALID_MANIFEST ("Unknown redist: %s (supported: win7, win10)", id);
        }
    }

    public string builtin_redist_label (string id) {
        switch (id.down ()) {
            case "win7":     return "Setting Windows version to Windows 7...";
            case "win10":    return "Setting Windows version to Windows 10...";
            default:         return "Installing %s...".printf (id);
        }
    }

    private struct WinVer {
        public string build_num;
        public string cur_ver;
        public uint32 major_ver;
        public uint32 minor_ver;
        public string csd;
        public uint32 csd_dword;
    }

    private WinVer? winver_values (string ver) {
        switch (ver) {
            case "winxp": return { "2600", "5.1", 5, 1, "Service Pack 3", 0x300 };
            case "win7": return { "7601", "6.1", 6, 1, "Service Pack 1", 0x100 };
            case "win10": return { "19041", "10.0", 10, 0, "", 0 };
            default: return null;
        }
    }

    /* Mirrors what winecfg writes; wineserver is flushed so the hive is on disk before the next wine start. */
    private void set_winver (
        string ver,
        WinePaths paths,
        WineEnv env,
        RuntimeLog logger,
        Cancellable? cancellable
    ) throws Error {
        var w = winver_values (ver);
        if (w == null) return;
        var reg = new RegFile ()
            .key ("HKEY_CURRENT_USER\\Software\\Wine")
            .str ("Version", ver)
            .key ("HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion")
            .str ("CSDVersion", w.csd)
            .str ("CurrentBuild", w.build_num)
            .str ("CurrentBuildNumber", w.build_num)
            .str ("CurrentVersion", w.cur_ver)
            .dword ("CurrentMajorVersionNumber", w.major_ver)
            .dword ("CurrentMinorVersionNumber", w.minor_ver)
            .key ("HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Windows")
            .dword ("CSDVersion", w.csd_dword);
        import_registry (paths, env, reg, logger, cancellable);
        shutdown_wineserver (paths, env, logger);
    }
}
