namespace Lumoria.Application {

    public class ShortcutArtwork : Object {
        public static bool can_use_launch_art (string key) {
            var slot = Models.FfxiIconCatalog.sanitize_slot_key (key);
            var builtin = Models.IconSlots.lookup (slot);
            if (builtin != null) return builtin.has_shortcut_art ();
            return Models.FfxiIconCatalog.instance ().png_path_for_key (slot) != null;
        }

        public static Bytes lumoria_bytes () throws Error {
            return resources_lookup_data (Models.IconSlots.LUMORIA_PNG, ResourceLookupFlags.NONE);
        }

        public static string lumoria_path () throws Error {
            return ensure_png (Config.APP_ID + ".png", lumoria_bytes ());
        }

        public static Bytes bytes_for (Models.PrefixEntry entry, Runtime.LaunchTarget target) throws Error {
            Bytes? bytes;
            string? path;
            resolve (entry, target, out bytes, out path);
            return bytes ?? lumoria_bytes ();
        }

        public static string path_for (Models.PrefixEntry entry, Runtime.LaunchTarget target) throws Error {
            Bytes? bytes;
            string? path;
            resolve (entry, target, out bytes, out path);
            return path ?? lumoria_path ();
        }

        private static void resolve (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target,
            out Bytes? bytes,
            out string? path
        ) throws Error {
            bytes = null;
            path = null;
            if (!entry.uses_launch_icon_for_shortcut (target.id)) return;
            resolve_key (entry.display_icon (target.id, target.icon), out bytes, out path);
        }

        private static void resolve_key (string key, out Bytes? bytes, out string? path) throws Error {
            bytes = null;
            path = null;
            var builtin = Models.IconSlots.lookup (key);
            if (builtin != null) {
                bytes = builtin.shortcut_bytes ();
                if (bytes != null) path = ensure_png (builtin.shortcut_file, bytes);
                return;
            }
            path = Models.FfxiIconCatalog.instance ().png_path_for_key (key);
            if (path == null) return;
            uint8[] data;
            FileUtils.get_data (path, out data);
            bytes = new Bytes (data);
        }

        private static string ensure_png (string name, Bytes bytes) throws Error {
            var icon_path = Path.build_filename (Utils.data_dir (), "icons", name);
            if (FileUtils.test (icon_path, FileTest.EXISTS)) return icon_path;
            Utils.write_bytes_atomic (icon_path, bytes.get_data ());
            return icon_path;
        }
    }
}
