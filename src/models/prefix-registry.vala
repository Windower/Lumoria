namespace Lumoria.Models {

    public class PrefixRegistry : Object {
        public Gee.ArrayList<PrefixEntry> prefixes { get; owned set; default = new Gee.ArrayList<PrefixEntry> (); }
        public string default_prefix_id { get; set; default = ""; }

        public PrefixEntry? default_prefix () {
            if (default_prefix_id != "") {
                var found = by_id (default_prefix_id);
                if (found != null) return found;
            }
            if (prefixes.size > 0) return prefixes[0];
            return null;
        }

        public int default_prefix_index () {
            if (default_prefix_id != "") {
                for (int i = 0; i < prefixes.size; i++) {
                    if (prefixes[i].id == default_prefix_id) return i;
                }
            }
            return prefixes.size > 0 ? 0 : -1;
        }

        public bool is_default (PrefixEntry entry) {
            if (default_prefix_id != "") return entry.id == default_prefix_id;
            return prefixes.size > 0 && prefixes[0] == entry;
        }

        public void add_prefix (PrefixEntry entry) {
            if (entry.runner_version == "") entry.runner_version = "default";
            prefixes.add (entry);
        }

        public PrefixEntry? by_id (string id) {
            foreach (var p in prefixes) {
                if (p.id == id) return p;
            }
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

        public void update_entry (PrefixEntry updated) {
            for (int i = 0; i < prefixes.size; i++) {
                if (prefixes[i].id == updated.id) {
                    prefixes[i] = updated;
                    return;
                }
            }
        }

        public void update_runner (int index, string runner_id, string runner_version) {
            if (index < 0 || index >= prefixes.size) return;
            prefixes[index].runner_id = runner_id;
            prefixes[index].runner_version = runner_version != "" ? runner_version : "default";
        }

        public void update_launcher (int index, string launcher_id) {
            if (index < 0 || index >= prefixes.size) return;
            prefixes[index].launcher_id = launcher_id;
        }

        public void remove_at (int index) {
            if (index < 0 || index >= prefixes.size) return;
            if (prefixes[index].id == default_prefix_id) {
                default_prefix_id = "";
            }
            prefixes.remove_at (index);
        }

        public static PrefixRegistry load (string path) {
            var reg = new PrefixRegistry ();
            if (!FileUtils.test (path, FileTest.EXISTS)) return reg;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path);
                var root = parser.get_root ().get_object ();
                reg.prefixes = parse_json_array<PrefixEntry> (root, "prefixes", (o) => PrefixEntry.from_json (o));
                reg.default_prefix_id = json_string (root, "default_prefix_id");
                var changed = reg.backfill_runner_state ();
                changed = reg.migrate_duplicate_custom_entry_ids () || changed;
                if (changed) {
                    reg.save (path);
                }
            } catch (Error e) {
                warning ("Failed to load prefix registry: %s", e.message);
            }
            return reg;
        }

        private bool backfill_runner_state () {
            var changed = false;
            foreach (var prefix in prefixes) {
                if (prefix.runner_state != null) continue;

                var state = new PrefixRunnerState ();
                state.runner_id = prefix.runner_id;
                state.variant_id = prefix.variant_id;
                if (!is_deferred_runner_version (prefix.runner_version)) {
                    state.resolved_version = prefix.runner_version;
                }
                prefix.runner_state = state;
                changed = true;
            }
            return changed;
        }

        private bool migrate_duplicate_custom_entry_ids () {
            var changed = false;
            foreach (var prefix in prefixes) {
                if (migrate_duplicate_custom_entry_ids_for_prefix (prefix)) changed = true;
            }
            return changed;
        }

        private bool migrate_duplicate_custom_entry_ids_for_prefix (PrefixEntry prefix) {
            if (prefix.custom_entrypoints.size < 2) return false;

            var changed = false;
            var seen_ids = new Gee.HashSet<string> ();
            var used_ids = new Gee.HashSet<string> ();
            foreach (var ep in prefix.custom_entrypoints) {
                if (ep.id != "") used_ids.add (ep.id);
            }

            foreach (var ep in prefix.custom_entrypoints) {
                if (!PrefixEntry.is_legacy_custom_entry_id (ep.id)) continue;

                var old_id = ep.id;
                if (!seen_ids.contains (old_id)) {
                    seen_ids.add (old_id);
                    continue;
                }

                var new_id = generate_unique_custom_entry_id (used_ids);
                ep.id = new_id;
                used_ids.add (new_id);

                if (!custom_entry_id_exists (prefix, old_id)) {
                    remap_entrypoint_id (prefix, old_id, new_id);
                }
                changed = true;
            }

            return changed;
        }

        private static string generate_unique_custom_entry_id (Gee.HashSet<string> used_ids) {
            while (true) {
                var id = PrefixEntry.generate_custom_entry_id ();
                if (!used_ids.contains (id)) return id;
            }
        }

        private static bool custom_entry_id_exists (PrefixEntry prefix, string id) {
            if (id == "") return false;
            foreach (var ep in prefix.custom_entrypoints) {
                if (ep.id == id) return true;
            }
            return false;
        }

        private static void remap_entrypoint_id (PrefixEntry prefix, string old_id, string new_id) {
            if (prefix.launch_entrypoint_id == old_id) {
                prefix.launch_entrypoint_id = new_id;
            }
            if (prefix.dynamic_launcher_desktop_ids.has_key (old_id)) {
                var desktop_id = prefix.dynamic_launcher_desktop_ids[old_id];
                prefix.dynamic_launcher_desktop_ids.unset (old_id);
                prefix.dynamic_launcher_desktop_ids[new_id] = desktop_id;
            }
        }

        private static bool is_deferred_runner_version (string version) {
            var v = version.strip ().down ();
            return v == "" || v == "latest" || v == "default";
        }

        public bool save (string path) {
            var root = new Json.Object ();
            var arr = new Json.Array ();
            foreach (var p in prefixes) {
                arr.add_object_element (p.to_json ());
            }
            root.set_array_member ("prefixes", arr);
            if (default_prefix_id != "") {
                root.set_string_member ("default_prefix_id", default_prefix_id);
            }

            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (root);
            var gen = new Json.Generator ();
            gen.set_root (node);
            gen.pretty = true;
            gen.indent = 2;

            try {
                var dir = Path.get_dirname (path);
                DirUtils.create_with_parents (dir, 0755);
                gen.to_file (path);
                return true;
            } catch (Error e) {
                warning ("Failed to save prefix registry: %s", e.message);
                return false;
            }
        }
    }
}
