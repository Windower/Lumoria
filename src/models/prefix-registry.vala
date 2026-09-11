namespace Lumoria.Models {

    public class PrefixRegistry : Object {
        public Gee.ArrayList<PrefixEntry> prefixes { get; owned set; default = new Gee.ArrayList<PrefixEntry> (); }
        public string default_prefix_id { get; set; default = ""; }
        public string load_error { get; private set; default = ""; }

        public PrefixEntry? default_prefix () {
            if (default_prefix_id != "") {
                var found = by_id (default_prefix_id);
                if (found != null) return found;
            }
            if (prefixes.size > 0) return prefixes[0];
            return null;
        }

        public void add_prefix (PrefixEntry entry) {
            if (entry.runner_version == "") entry.runner_version = ToolVersionRef.WIRE_INHERIT;
            prefixes.add (entry);
        }

        public PrefixEntry? by_id (string id) {
            foreach (var p in prefixes) {
                if (p.id == id) return p;
            }
            return null;
        }

        public PrefixEntry? find (PrefixEntry hint) {
            if (hint.id != "") {
                var found = by_id (hint.id);
                if (found != null) return found;
            }
            var resolved = hint.resolved_path ();
            if (resolved != "") return by_path (resolved);
            return null;
        }

        public PrefixEntry? by_path (string path) {
            var want = Utils.normalize_dir_path (path);
            foreach (var p in prefixes) {
                if (Utils.normalize_dir_path (p.path) == want) return p;
                if (Utils.normalize_dir_path (p.resolved_path ()) == want) return p;
            }
            return null;
        }

        public void remove_at (int index) {
            if (index < 0 || index >= prefixes.size) return;
            if (prefixes[index].id == default_prefix_id) {
                default_prefix_id = "";
            }
            prefixes.remove_at (index);
        }

        /* dirty is set when unreadable entries were dropped and the pruned registry should be re-saved. */
        public static PrefixRegistry load (string path, out bool dirty) {
            var reg = new PrefixRegistry ();
            dirty = false;
            string json;
            Json.Object root;
            try {
                if (!Utils.read_user_text (path, out json)) return reg;
                root = parse_data_object (json);
            } catch (Error e) {
                warning ("Failed to load prefixes: %s", e.message);
                Utils.quarantine_broken_file (path);
                reg.load_error = _("Could not load prefixes; starting with none.");
                return reg;
            }

            reg.default_prefix_id = json_string (root, "default_prefix_id");
            try {
                ManifestSchema.validate_json ("prefix-registry", json);
                reg.prefixes = parse_json_array<PrefixEntry> (root, "prefixes", (o) => PrefixEntry.from_json (o));
                return reg;
            } catch (Error e) {
                warning ("Prefix registry failed as a whole, salvaging entries: %s", e.message);
            }

            var dropped = 0;
            if (root.has_member ("prefixes") && root.get_member ("prefixes").get_node_type () == Json.NodeType.ARRAY) {
                var arr = root.get_array_member ("prefixes");
                for (uint i = 0; i < arr.get_length (); i++) {
                    var entry = salvage_entry (arr.get_element (i));
                    if (entry != null) reg.prefixes.add (entry); else dropped++;
                }
            }
            Utils.preserve_broken_copy (path);
            dirty = true;
            reg.load_error = ngettext (
                "Skipped %d unreadable prefix entry; a copy of the old registry was kept.",
                "Skipped %d unreadable prefix entries; a copy of the old registry was kept.",
                dropped
            ).printf (dropped);
            return reg;
        }

        private static PrefixEntry? salvage_entry (Json.Node node) {
            if (node.get_node_type () != Json.NodeType.OBJECT) return null;
            var wrapper = new Json.Object ();
            wrapper.set_int_member ("format_version", Config.CONFIG_FORMAT_VERSION);
            var arr = new Json.Array ();
            arr.add_element (node.copy ());
            wrapper.set_array_member ("prefixes", arr);
            try {
                ManifestSchema.validate_json ("prefix-registry", json_object_to_string (wrapper, false));
                return PrefixEntry.from_json (node.get_object ());
            } catch (Error e) {
                warning ("Dropping prefix entry %s: %s", json_string (node.get_object (), "id", "?"), e.message);
                return null;
            }
        }

        public Json.Object to_json () {
            var root = new Json.Object ();
            root.set_int_member ("format_version", Config.CONFIG_FORMAT_VERSION);
            var arr = new Json.Array ();
            foreach (var p in prefixes) {
                arr.add_object_element (p.to_json ());
            }
            root.set_array_member ("prefixes", arr);
            if (default_prefix_id != "") {
                root.set_string_member ("default_prefix_id", default_prefix_id);
            }
            return root;
        }

        public void save (string path) throws Error {
            Utils.write_validated_json (path, "prefix-registry", to_json ());
        }
    }
}
