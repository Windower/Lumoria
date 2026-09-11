namespace Lumoria.Runtime {

    public class MsiInstaller : Object {
        private const string SYSTEM32 = "C:\\windows\\system32\\";
        private const string SYSWOW64 = "C:\\windows\\syswow64\\";
        private const string MULTI_SZ_SEPARATOR = "[~]";

        private class Location {
            public string host;
            public string win;
            public int64 size;
            /* Uncompressed files only. */
            public string? source;

            public Location (string host, string win, int64 size = 0, string? source = null) {
                this.host = host;
                this.win = win;
                this.size = size;
                this.source = source;
            }
        }

        private string msi_path;
        private string prefix;
        private bool win64;
        private WinePaths paths;
        private WineEnv env;
        private RuntimeLog logger;
        private Cancellable? cancellable;

        private Json.Object package;
        private Gee.HashMap<string, Location> directories = new Gee.HashMap<string, Location> ();
        private Gee.HashMap<string, string> source_dirs = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, Location> files = new Gee.HashMap<string, Location> ();

        public MsiInstaller (
            string msi_path,
            string prefix,
            string arch,
            WinePaths paths,
            WineEnv env,
            RuntimeLog logger,
            Cancellable? cancellable
        ) {
            this.msi_path = msi_path;
            this.prefix = prefix;
            this.win64 = arch == "win64";
            this.paths = paths;
            this.env = env;
            this.logger = logger;
            this.cancellable = cancellable;
        }

        public void run () throws Error {
            load ();
            map_files ();
            create_folders ();
            extract ();
            install_assemblies ();
            import_registry ();
            register_servers ();
        }

        private void load () throws Error {
            string? error;
            var json = Native.Msi.read (msi_path, out error);
            if (json == null) {
                throw new LumoriaError.INTERNAL ("msi: cannot read %s: %s", msi_path, error ?? "unknown error");
            }
            package = Models.parse_data_object (json);
            log_skipped_actions ();

            var product = property ("ProductName");
            logger.typed (LogType.MSI, "%s %s (%s)".printf (product, property ("ProductVersion"), Path.get_basename (msi_path)));
        }

        private void log_skipped_actions () {
            if (!package.has_member ("skipped_actions")) return;
            var skipped = package.get_member ("skipped_actions");
            if (skipped.get_node_type () != Json.NodeType.ARRAY) return;
            foreach (var node in skipped.get_array ().get_elements ()) {
                if (node.get_node_type () != Json.NodeType.OBJECT) continue;
                var action = node.get_object ();
                logger.typed (LogType.MSI, "ignored conditioned %s (%s)".printf (
                    action.get_string_member ("action"),
                    action.get_string_member ("condition")
                ));
            }
        }

        private static bool directory_may_skip (Json.Object? dir) {
            return dir != null && dir.has_member ("system_root") && dir.get_boolean_member ("system_root");
        }

        private string property (string name) {
            var props = package.get_object_member ("properties");
            return props.has_member (name) ? props.get_string_member (name) : "";
        }

        private Location? system_folder (string root) {
            var program_files = win64 ? "Program Files (x86)" : "Program Files";
            var system = win64 ? "syswow64" : "system32";
            switch (root) {
                case "TARGETDIR":
                    return drive_c ("");
                case "WindowsFolder":
                    return drive_c ("windows");
                case "SystemFolder":
                    return drive_c ("windows\\" + system);
                case "System64Folder":
                    return win64 ? drive_c ("windows\\system32") : null;
                case "FontsFolder":
                    return drive_c ("windows\\Fonts");
                case "ProgramFilesFolder":
                    return drive_c (program_files);
                case "CommonFilesFolder":
                    return drive_c (program_files + "\\Common Files");
                case "ProgramFiles64Folder":
                    return win64 ? drive_c ("Program Files") : null;
                case "CommonFiles64Folder":
                    return win64 ? drive_c ("Program Files\\Common Files") : null;
                case "CommonAppDataFolder":
                    return drive_c ("ProgramData");
                default:
                    return null;
            }
        }

        private Location drive_c (string rel) {
            var host = Path.build_filename (PrefixPaths.drive_c_of (prefix), rel.replace ("\\", "/"));
            return new Location (host, rel == "" ? "C:\\" : "C:\\" + rel + "\\");
        }

        private void map_files () throws Error {
            var dirs = package.get_object_member ("directories");
            foreach (var id in dirs.get_members ()) {
                var node = dirs.get_member (id);
                if (node.get_node_type () != Json.NodeType.OBJECT) continue;
                var dir = node.get_object ();
                source_dirs[id] = dir.get_string_member ("source").replace ("\\", "/");
                var root_id = dir.get_string_member ("root");
                var root = system_folder (root_id);
                if (root == null) {
                    if (directory_may_skip (dir)) continue;
                    throw new LumoriaError.INTERNAL ("msi: payload directory root '%s' is not mapped", root_id);
                }
                var rel = dir.get_string_member ("path");
                if (rel == "") {
                    directories[id] = root;
                    continue;
                }
                directories[id] = new Location (
                    Utils.join_inside (root.host, rel.replace ("\\", "/")),
                    root.win + rel + "\\"
                );
            }

            int skipped = 0;
            foreach (var node in package.get_array_member ("files").get_elements ()) {
                var file = node.get_object ();
                var dir_id = file.get_string_member ("directory");
                var dir = directories[dir_id];
                if (dir == null) {
                    Json.Object? dir_obj = null;
                    if (dirs.has_member (dir_id) && dirs.get_member (dir_id).get_node_type () == Json.NodeType.OBJECT) {
                        dir_obj = dirs.get_object_member (dir_id);
                    }
                    if (directory_may_skip (dir_obj)) {
                        skipped++;
                        continue;
                    }
                    var root_id = dir_obj != null && dir_obj.has_member ("root")
                        ? dir_obj.get_string_member ("root") : "";
                    throw new LumoriaError.INTERNAL (
                        "msi: file '%s' uses unmapped directory '%s' (root %s)",
                        file.get_string_member ("name"),
                        dir_id,
                        root_id != "" ? root_id : "unknown"
                    );
                }
                var key = file.get_string_member ("key");
                var name = Utils.confined_filename (file.get_string_member ("name"));
                string? source = null;
                if (!file.get_boolean_member ("compressed")) {
                    source = Path.build_filename (source_dirs[file.get_string_member ("directory")], name);
                }
                files[key] = new Location (
                    Path.build_filename (dir.host, name),
                    dir.win + name,
                    file.get_int_member ("size"),
                    source
                );
            }
            logger.typed (LogType.MSI, "%d file(s) mapped, %d outside supported folders".printf (files.size, skipped));
        }

        private void create_folders () throws Error {
            foreach (var node in package.get_array_member ("create_folders").get_elements ()) {
                var dir = directories[node.get_string ()];
                if (dir != null) Utils.ensure_dir (dir.host);
            }
        }

        private void extract () throws Error {
            var msi_dir = Path.get_dirname (msi_path);
            var cabs = new Gee.ArrayList<string> ();
            var embedded = new Gee.ArrayList<string> ();
            try {
                foreach (var node in package.get_array_member ("media").get_elements ()) {
                    var cabinet = node.get_object ().get_string_member ("cabinet");
                    if (cabinet == "") continue;

                    if (cabinet.has_prefix ("#")) {
                        var cab_path = Path.build_filename (msi_dir, cabinet.substring (1));
                        string? error;
                        if (!Native.Msi.extract_stream (msi_path, cabinet, cab_path, msi_dir, out error)) {
                            throw new LumoriaError.INTERNAL ("msi: cannot extract stream %s: %s", cabinet, error ?? "unknown error");
                        }
                        embedded.add (cab_path);
                        cabs.add (cab_path);
                        continue;
                    }

                    var external = find_cabinet (msi_dir, cabinet);
                    if (external == null) {
                        throw new LumoriaError.INTERNAL ("msi: cabinet missing: %s", Path.build_filename (msi_dir, cabinet));
                    }
                    cabs.add (external);
                }

                logger.typed (LogType.MSI, "extracting %d cabinet(s)".printf (cabs.size));
                int unreferenced = 0;
                Utils.extract_cab_entries (Utils.strv (cabs), (name, size) => {
                    var file = files[name];
                    if (file == null) AtomicInt.inc (ref unreferenced);
                    return file?.host;
                }, cancellable);
                /* Shared cabinets (e.g. netfx_Core.mzz) carry both architectures; a single package only references one. */
                if (unreferenced > 0) {
                    logger.typed (LogType.MSI, "%d cabinet entr%s not referenced by this package".printf (
                        unreferenced, unreferenced == 1 ? "y" : "ies"));
                }
            } finally {
                foreach (var path in embedded) FileUtils.remove (path);
            }
            copy_uncompressed ();
            verify_sizes ();
        }

        /* Media.Cabinet names are case-insensitive on Windows; match the file that is actually on disk. */
        private static string? find_cabinet (string dir, string name) throws Error {
            var exact = Path.build_filename (dir, name);
            if (FileUtils.test (exact, FileTest.EXISTS)) return exact;

            var folded = name.casefold ();
            var listing = Dir.open (dir);
            string? entry;
            while ((entry = listing.read_name ()) != null) {
                if (entry.casefold () == folded) return Path.build_filename (dir, entry);
            }
            return null;
        }

        private void copy_uncompressed () throws Error {
            var msi_dir = Path.get_dirname (msi_path);
            int copied = 0, absent = 0;
            foreach (var file in files.values) {
                if (file.source == null) continue;
                var source = Path.build_filename (msi_dir, file.source);
                if (!FileUtils.test (source, FileTest.EXISTS)) {
                    absent++;
                    continue;
                }
                Utils.check_cancelled (cancellable);
                Utils.copy_path (source, file.host, null, cancellable);
                copied++;
            }
            if (copied + absent > 0) {
                logger.typed (LogType.MSI, "%d uncompressed file(s) copied, %d not shipped with the package".printf (copied, absent));
            }
        }

        private void verify_sizes () throws Error {
            int missing = 0, verified = 0;
            foreach (var file in files.values) {
                if (!FileUtils.test (file.host, FileTest.EXISTS)) {
                    if (file.source == null) missing++;
                    continue;
                }
                var actual = Utils.file_size_or_zero (file.host);
                /* Some packages ship rows with FileSize 0; Windows Installer does not validate those either. */
                if (file.size > 0 && actual != file.size) {
                    throw new LumoriaError.INTERNAL (
                        "msi: size mismatch for %s (got %lld, expected %lld)", file.host, actual, file.size
                    );
                }
                verified++;
            }
            if (missing > 0) {
                throw new LumoriaError.INTERNAL ("msi: %d file(s) listed in %s were not extracted", missing, Path.get_basename (msi_path));
            }
            logger.typed (LogType.MSI, "%d file(s) verified".printf (verified));
        }

        private void install_assemblies () throws Error {
            if (!package.has_member ("assemblies")) return;
            var node = package.get_member ("assemblies");
            if (node.get_node_type () != Json.NodeType.ARRAY) return;

            int gac = 0, priv = 0, sxs = 0;
            foreach (var item in node.get_array ().get_elements ()) {
                if (item.get_node_type () != Json.NodeType.OBJECT) continue;
                Utils.check_cancelled (cancellable);
                var row = item.get_object ();
                if (Models.json_bool (row, "win32")) {
                    install_win32_assembly (row);
                    sxs++;
                } else if (Models.json_string (row, "application") != "") {
                    install_private_assembly (row);
                    priv++;
                } else {
                    install_gac_assembly (row);
                    gac++;
                }
            }
            if (gac + priv + sxs > 0) {
                logger.typed (LogType.MSI, "%d .NET GAC, %d private, %d Win32 SxS".printf (gac, priv, sxs));
            }
        }

        private void install_gac_assembly (Json.Object row) throws Error {
            var file = require_assembly_file (Models.json_string (row, "file"), Models.json_string (row, "name"));
            copy_host_file (file.host, gac_dest (row, Path.get_basename (file.host)));
        }

        private void install_private_assembly (Json.Object row) throws Error {
            var payload = files[Models.json_string (row, "file")];
            var application = files[Models.json_string (row, "application")];
            if (payload == null || application == null) return;
            var dest_dir = Path.get_dirname (application.host);
            copy_if_elsewhere (payload, dest_dir);
            var manifest = files[Models.json_string (row, "manifest")];
            if (manifest != null) copy_if_elsewhere (manifest, dest_dir);
        }

        private void install_win32_assembly (Json.Object row) throws Error {
            var name = Models.json_string (row, "name");
            var version = Models.json_string (row, "version");
            var token = Models.json_string (row, "publicKeyToken");
            var arch = sxs_arch (Models.json_string (row, "processorArchitecture"));
            var lang = sxs_lang (Models.json_string (row, "culture"));
            var manifest = files[Models.json_string (row, "manifest")];
            if (name == "" && manifest != null && FileUtils.test (manifest.host, FileTest.EXISTS)) {
                read_sxs_identity (manifest.host, out name, out version, out token, out arch, out lang);
            }
            if (name == "") {
                throw new LumoriaError.INTERNAL (
                    "msi: Win32 assembly '%s' has no identity", Models.json_string (row, "component")
                );
            }

            var folder = "%s_%s_%s_%s_%s_00000000".printf (arch, name, token, version, lang);
            var dest_dir = Path.build_filename (prefix, "drive_c/windows/winsxs", folder);
            Utils.ensure_dir (dest_dir);
            foreach (var key in assembly_file_keys (row)) {
                var file = files[key];
                if (file == null || !FileUtils.test (file.host, FileTest.EXISTS)) continue;
                copy_host_file (file.host, Path.build_filename (dest_dir, Path.get_basename (file.host)));
            }
            if (manifest != null && FileUtils.test (manifest.host, FileTest.EXISTS)) {
                copy_host_file (
                    manifest.host,
                    Path.build_filename (prefix, "drive_c/windows/winsxs/manifests", folder + ".manifest")
                );
            }
        }

        private Location require_assembly_file (string key, string name) throws Error {
            var file = files[key];
            if (file == null || !FileUtils.test (file.host, FileTest.EXISTS)) {
                throw new LumoriaError.INTERNAL (
                    "msi: assembly '%s' missing file '%s'", name != "" ? name : key, key
                );
            }
            return file;
        }

        private void copy_if_elsewhere (Location file, string dest_dir) throws Error {
            if (!FileUtils.test (file.host, FileTest.EXISTS)) return;
            if (Path.get_dirname (file.host) == dest_dir) return;
            copy_host_file (file.host, Path.build_filename (dest_dir, Path.get_basename (file.host)));
        }

        private void copy_host_file (string src, string dst) throws Error {
            if (src == dst) return;
            Utils.copy_path (src, dst, null, cancellable);
        }

        private string gac_dest (Json.Object row, string filename) {
            var name = Models.json_string (row, "name");
            var version = Models.json_string (row, "version");
            var culture = gac_culture (Models.json_string (row, "culture"));
            var token = Models.json_string (row, "publicKeyToken");
            var leaf = gac_leaf (Models.json_string (row, "processorArchitecture"));
            var v4 = version.has_prefix ("4.") || property ("ProductVersion").has_prefix ("4.");
            if (v4) {
                return Path.build_filename (
                    prefix, "drive_c/windows/Microsoft.NET/assembly", leaf, name,
                    "v4.0_%s_%s_%s".printf (version, culture, token), filename
                );
            }
            return Path.build_filename (
                prefix, "drive_c/windows/assembly", leaf, name,
                "%s_%s_%s".printf (version, culture, token), filename
            );
        }

        private static string gac_leaf (string arch) {
            switch (arch.down ()) {
                case "x86": return "GAC_32";
                case "amd64":
                case "x64": return "GAC_64";
                default: return "GAC_MSIL";
            }
        }

        private static string gac_culture (string culture) {
            var folded = culture.down ().strip ();
            return (folded == "" || folded == "neutral") ? "" : culture;
        }

        private static string sxs_arch (string arch) {
            switch (arch.down ()) {
                case "amd64":
                case "x64": return "amd64";
                case "msil": return "msil";
                case "": return "x86";
                default: return arch.down ();
            }
        }

        private static string sxs_lang (string culture) {
            var folded = culture.down ().strip ();
            return (folded == "" || folded == "neutral") ? "none" : culture;
        }

        private static Gee.ArrayList<string> assembly_file_keys (Json.Object row) {
            var keys = new Gee.ArrayList<string> ();
            if (row.has_member ("files") && row.get_member ("files").get_node_type () == Json.NodeType.ARRAY) {
                foreach (var node in row.get_array_member ("files").get_elements ()) {
                    if (node.get_node_type () == Json.NodeType.VALUE) keys.add (node.get_string ());
                }
            }
            foreach (var field in new string[] { "file", "manifest" }) {
                var key = Models.json_string (row, field);
                if (key != "" && !keys.contains (key)) keys.add (key);
            }
            return keys;
        }

        private static void read_sxs_identity (
            string manifest,
            out string name,
            out string version,
            out string token,
            out string arch,
            out string lang
        ) {
            name = "";
            version = "";
            token = "";
            arch = "x86";
            lang = "none";
            var doc = Xml.Parser.parse_file (manifest);
            if (doc == null) return;
            var root = doc->get_root_element ();
            if (root != null) {
                var identity = find_xml_named (root, "assemblyIdentity");
                if (identity != null) {
                    name = identity->get_prop ("name") ?? "";
                    version = identity->get_prop ("version") ?? "";
                    token = identity->get_prop ("publicKeyToken") ?? "";
                    var raw_arch = identity->get_prop ("processorArchitecture") ?? "";
                    if (raw_arch != "") arch = sxs_arch (raw_arch);
                    var raw_lang = identity->get_prop ("language") ?? identity->get_prop ("culture") ?? "";
                    if (raw_lang != "") lang = sxs_lang (raw_lang);
                }
            }
            delete doc;
        }

        private static Xml.Node* find_xml_named (Xml.Node* node, string name) {
            if (node->type == Xml.ElementType.ELEMENT_NODE && node->name == name) return node;
            for (Xml.Node* child = node->children; child != null; child = child->next) {
                var found = find_xml_named (child, name);
                if (found != null) return found;
            }
            return null;
        }

        private void import_registry () throws Error {
            var views = new StringBuilder[] {
                new StringBuilder ("Windows Registry Editor Version 5.00\r\n"),
                new StringBuilder ("Windows Registry Editor Version 5.00\r\n")
            };
            var counts = new int[2];
            foreach (var node in package.get_array_member ("registry").get_elements ()) {
                var row = node.get_object ();
                var name = row.get_string_member ("name");
                if (name == "-") continue;

                var view = win64 && row.get_boolean_member ("win64") ? 1 : 0;
                unowned var reg = views[view];
                var hive = registry_hive ((int) row.get_int_member ("root"));
                reg.append ("\r\n[%s\\%s]\r\n".printf (hive, expand (row.get_string_member ("key"))));
                counts[view]++;

                if (name == "+" || name == "*") continue;

                var label = name == "" ? "@" : quoted (expand (name));
                reg.append ("%s=%s\r\n".printf (label, registry_value (row.get_string_member ("value"))));
            }

            /* The 64-bit regedit lives in the Windows folder itself, as on Windows; only the WOW64 copy is in syswow64. */
            string[] regedits = { system_exe ("regedit.exe"), "C:\\windows\\regedit.exe" };
            for (int view = 0; view < 2; view++) {
                if (counts[view] == 0) continue;
                var reg_path = Path.build_filename (
                    Path.get_dirname (msi_path), "%s.%s.reg".printf (Path.get_basename (msi_path), view == 0 ? "32" : "64")
                );
                write_utf16 (reg_path, views[view].str);
                logger.typed (LogType.MSI, "importing %d %s-bit registry key(s)".printf (counts[view], view == 0 ? "32" : "64"));
                try {
                    run_wine ({ regedits[view], "/S", to_wine_path (prefix, reg_path) });
                } finally {
                    FileUtils.remove (reg_path);
                }
            }
        }

        private string registry_hive (int root) {
            switch (root) {
                case 0: return "HKEY_CLASSES_ROOT";
                case 1: return "HKEY_CURRENT_USER";
                case 2: return "HKEY_LOCAL_MACHINE";
                case 3: return "HKEY_USERS";
                default: return property ("ALLUSERS") != "" ? "HKEY_LOCAL_MACHINE" : "HKEY_CURRENT_USER";
            }
        }

        private string registry_value (string raw) throws Error {
            if (raw.has_prefix ("#x")) return "hex:" + hex_bytes (raw.substring (2));
            if (raw.has_prefix ("#%")) return "hex(2):" + utf16_hex (expand (raw.substring (2)));
            if (raw.has_prefix ("##")) return quoted (expand (raw.substring (1)));
            if (raw.has_prefix ("#")) {
                int64 number = int64.parse (raw.substring (1));
                return "dword:%08x".printf ((uint32) number);
            }
            if (raw.contains (MULTI_SZ_SEPARATOR)) return "hex(7):" + multi_sz_hex (raw);
            return quoted (expand (raw));
        }

        /* REG_MULTI_SZ rows separate strings with [~]; a leading or trailing one is an append/prepend hint. */
        private string multi_sz_hex (string raw) throws Error {
            var parts = new StringBuilder ();
            foreach (var item in raw.split (MULTI_SZ_SEPARATOR)) {
                if (item == "") continue;
                parts.append (utf16_hex (expand (item))).append (",");
            }
            return parts.str + "00,00";
        }

        private static string hex_bytes (string hex) {
            var parts = new string[hex.length / 2];
            for (int i = 0; i + 1 < hex.length; i += 2) parts[i / 2] = hex.substring (i, 2);
            return string.joinv (",", parts);
        }

        private static string utf16_hex (string text) throws Error {
            long units;
            var utf16 = text.to_utf16 (-1, null, out units);
            uint16* code_units = (uint16*) utf16;
            var parts = new StringBuilder ();
            for (long i = 0; i < units; i++) {
                parts.append ("%02x,%02x,".printf (code_units[i] & 0xff, code_units[i] >> 8));
            }
            return parts.str + "00,00";
        }

        private static string quoted (string text) {
            return "\"%s\"".printf (text.replace ("\\", "\\\\").replace ("\"", "\\\""));
        }

        private string expand (string text) {
            var result = new StringBuilder ();
            int pos = 0;
            while (pos < text.length) {
                var open = text.index_of ("[", pos);
                var close = open < 0 ? -1 : text.index_of ("]", open);
                if (open < 0 || close < 0) {
                    result.append (text.substring (pos));
                    break;
                }
                result.append (text.substring (pos, open - pos));
                var token = text.substring (open + 1, close - open - 1);
                if (token.has_prefix ("#") || token.has_prefix ("!")) {
                    var file = files[token.substring (1)];
                    if (file != null) result.append (file.win);
                } else if (directories.has_key (token)) {
                    result.append (directories[token].win);
                } else {
                    result.append (property (token));
                }
                pos = close + 1;
            }
            return result.str;
        }

        private void register_servers () throws Error {
            foreach (var node in package.get_array_member ("com_servers").get_elements ()) {
                var server = node.get_object ();
                var file = files[server.get_string_member ("file")];
                if (file == null) continue;
                Utils.check_cancelled (cancellable);
                logger.typed (LogType.MSI, "regsvr32 %s".printf (Path.get_basename (file.host)));
                var regsvr = win64 && server.get_boolean_member ("win64") ? SYSTEM32 + "regsvr32.exe" : system_exe ("regsvr32.exe");
                run_wine ({ regsvr, "/s", file.win });
            }
        }

        private string system_exe (string name) {
            return win64 ? SYSWOW64 + name : name;
        }

        private void run_wine (string[] argv) throws Error {
            run_wine_command (paths, argv, env, null, logger, cancellable);
        }

        private static void write_utf16 (string path, string text) throws Error {
            long units;
            var utf16 = text.to_utf16 (-1, null, out units);
            var bytes = new uint8[2 + units * 2];
            bytes[0] = 0xFF;
            bytes[1] = 0xFE;
            Memory.copy (&bytes[2], (uint8*) utf16, units * 2);
            FileUtils.set_data (path, bytes);
        }

    }
}
