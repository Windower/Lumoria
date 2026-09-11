namespace Lumoria.Models {

    public class ManifestSchema : Object {
        private class CompiledSchema : Object {
            public Native.JsonSchema schema;

            public CompiledSchema (owned Native.JsonSchema schema) {
                this.schema = (owned) schema;
            }
        }

        private static Gee.HashMap<string, CompiledSchema>? compiled;
        private static bool registered = false;

        public static void validate_json (string schema_name, string json) throws Error {
            var schema = require_schema (schema_name);
            var payload = Utils.sanitize_ui_text (json);
            string? message = null;
            if (!Native.schema_validate (schema.schema, payload, out message)) {
                throw new LumoriaError.INVALID_MANIFEST (
                    "Manifest schema '%s' rejected the document: %s",
                    schema_name,
                    message ?? "invalid"
                );
            }
        }

        public static void validate_relative (string relative_path, string json) throws Error {
            var kind = ManifestStore.schema_kind_for_path (relative_path);
            if (kind == "") return;
            validate_json (kind, json);
        }

        private static void register_documents () throws Error {
            if (registered) return;
            var dir = Config.RESOURCE_BASE + "/schemas";
            foreach (var name in GLib.resources_enumerate_children (dir, 0)) {
                if (!name.has_suffix (".json")) continue;
                var bytes = GLib.resources_lookup_data (dir + "/" + name, 0);
                string? message = null;
                if (!Native.schema_register (name, (string) bytes.get_data (), out message)) {
                    throw new LumoriaError.INVALID_MANIFEST (
                        "Failed to register schema %s: %s",
                        name,
                        message ?? "unknown error"
                    );
                }
            }
            registered = true;
        }

        private static CompiledSchema require_schema (string schema_name) throws Error {
            register_documents ();
            if (compiled == null) {
                compiled = new Gee.HashMap<string, CompiledSchema> ();
            }
            if (compiled.has_key (schema_name)) {
                return compiled[schema_name];
            }
            var resource = Config.RESOURCE_BASE + "/schemas/" + schema_name + ".json";
            string schema_json;
            try {
                var bytes = GLib.resources_lookup_data (resource, 0);
                schema_json = (string) bytes.get_data ();
            } catch (Error e) {
                throw new LumoriaError.INVALID_MANIFEST ("Missing schema %s: %s", schema_name, e.message);
            }
            string? message = null;
            var schema = Native.schema_compile (schema_json, out message);
            if (schema == null) {
                throw new LumoriaError.INVALID_MANIFEST (
                    "Failed to compile schema %s: %s",
                    schema_name,
                    message ?? "unknown error"
                );
            }
            var compiled_schema = new CompiledSchema ((owned) schema);
            compiled[schema_name] = compiled_schema;
            return compiled_schema;
        }
    }
}
