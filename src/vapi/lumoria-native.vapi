[CCode (cheader_filename = "lumoria-native.h")]
namespace Lumoria.Native {
    [Compact]
    [CCode (cname = "LumoriaJsonSchema", free_function = "lumoria_json_schema_free", has_copy_function = false)]
    public class JsonSchema {
        [CCode (cname = "lumoria_json_schema_register")]
        public static bool register_raw (string id, string schema_json, out void* error);

        [CCode (cname = "lumoria_json_schema_new")]
        public static JsonSchema? compile_raw (string schema_json, out void* error);

        [CCode (cname = "lumoria_json_schema_validate")]
        public bool validate_raw (string json, out void* error);
    }

    namespace Msi {
        [CCode (cname = "lumoria_msi_read")]
        public void* read_raw (string path, out void* error);

        [CCode (cname = "lumoria_msi_extract_stream")]
        public bool extract_stream_raw (string path, string stream, string out_path, string root, out void* error);
    }

    namespace SevenZip {
        [CCode (cname = "lumoria_7z_list")]
        public void* list_raw (string path, out void* error);

        [CCode (cname = "lumoria_7z_extract")]
        public bool extract_raw (string path, string plan_json, string root, out void* error);
    }

    [CCode (cname = "lumoria_native_string_free")]
    public void string_free (void* value);
}
