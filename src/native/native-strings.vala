namespace Lumoria.Native {
    public string? take_string (void* ptr) {
        if (ptr == null) return null;
        unowned string raw = (string) ptr;
        var copy = raw.dup ();
        string_free (ptr);
        return copy;
    }

    public bool schema_register (string id, string schema_json, out string? error) {
        void* err;
        var ok = JsonSchema.register_raw (id, schema_json, out err);
        error = take_string (err);
        return ok;
    }

    public JsonSchema? schema_compile (string schema_json, out string? error) {
        void* err;
        var schema = JsonSchema.compile_raw (schema_json, out err);
        error = take_string (err);
        return schema;
    }

    public bool schema_validate (JsonSchema schema, string json, out string? error) {
        void* err;
        var ok = schema.validate_raw (json, out err);
        error = take_string (err);
        return ok;
    }

    namespace Msi {
        public string? read (string path, out string? error) {
            void* err;
            var ptr = read_raw (path, out err);
            error = take_string (err);
            return take_string (ptr);
        }

        public bool extract_stream (string path, string stream, string out_path, string root, out string? error) {
            void* err;
            var ok = extract_stream_raw (path, stream, out_path, root, out err);
            error = take_string (err);
            return ok;
        }
    }

    namespace SevenZip {
        public string? list (string path, out string? error) {
            void* err;
            var ptr = list_raw (path, out err);
            error = take_string (err);
            return take_string (ptr);
        }

        public bool extract (string path, string plan_json, string root, out string? error) {
            void* err;
            var ok = extract_raw (path, plan_json, root, out err);
            error = take_string (err);
            return ok;
        }
    }
}
