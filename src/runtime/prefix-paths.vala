namespace Lumoria.Runtime {

    public class PrefixPaths : Object {
        public const string WINE_PREFIX_DIR = "pfx";
        public const string DRIVE_C_DIR = "drive_c";

        public string root { get; private set; default = ""; }
        public string wine_prefix { get; private set; default = ""; }
        public string drive_c { get; private set; default = ""; }
        public string windows { get; private set; default = ""; }
        public string system32 { get; private set; default = ""; }
        public string syswow64 { get; private set; default = ""; }
        public string fonts { get; private set; default = ""; }

        public static PrefixPaths from_root (string prefix_root) {
            var paths = new PrefixPaths ();
            paths.root = prefix_root.strip ();
            paths.wine_prefix = prefix_root_has_drive_c (paths.root)
                ? runtime_prefix_path (paths.root)
                : install_prefix_path (paths.root);
            paths.drive_c = drive_c_of (paths.wine_prefix);
            paths.windows = Path.build_filename (paths.drive_c, "windows");
            paths.system32 = Path.build_filename (paths.windows, "system32");
            paths.syswow64 = Path.build_filename (paths.windows, "syswow64");
            paths.fonts = Path.build_filename (paths.windows, "Fonts");
            return paths;
        }

        public static PrefixPaths from_entry (Models.PrefixEntry entry) {
            return from_root (entry.resolved_path ());
        }

        public static string drive_c_of (string wine_prefix) {
            return Path.build_filename (wine_prefix, DRIVE_C_DIR);
        }
    }

    public string runtime_prefix_path (string prefix_path) {
        var trimmed = prefix_path.strip ();
        if (trimmed == "") return "";
        if (Path.get_basename (trimmed) == PrefixPaths.WINE_PREFIX_DIR) return trimmed;
        var pfx = install_prefix_path (trimmed);
        if (FileUtils.test (PrefixPaths.drive_c_of (pfx), FileTest.IS_DIR)) return pfx;
        return trimmed;
    }

    public string install_prefix_path (string prefix_path) {
        var trimmed = prefix_path.strip ();
        if (trimmed == "") return trimmed;
        if (Path.get_basename (trimmed) == PrefixPaths.WINE_PREFIX_DIR) return trimmed;
        return Path.build_filename (trimmed, PrefixPaths.WINE_PREFIX_DIR);
    }

    public bool wine_prefix_drive_c_exists (string wine_prefix) {
        return FileUtils.test (PrefixPaths.drive_c_of (wine_prefix), FileTest.EXISTS);
    }

    public bool prefix_root_has_drive_c (string prefix_root) {
        return wine_prefix_drive_c_exists (prefix_root)
            || wine_prefix_drive_c_exists (install_prefix_path (prefix_root));
    }
}
