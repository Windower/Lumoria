// Credit to Lutris for the original implementation in Python: https://github.com/lutris/lutris/
namespace Lumoria.Utils.SteamVdf {

    public errordomain ParseError {
        INVALID_DATA
    }

    public enum ValueKind {
        OBJECT,
        STRING,
        INT32,
        FLOAT32,
        POINTER,
        COLOR,
        UINT64,
        INT64
    }

    public class Value : Object {
        public ValueKind kind { get; private set; }
        public Gee.HashMap<string, Value> object_value { get; private set; default = new Gee.HashMap<string, Value> (); }
        public string string_value { get; private set; default = ""; }
        public int32 int_value { get; private set; default = 0; }
        public uint32 float_bits { get; private set; default = 0; }
        public uint64 uint64_value { get; private set; default = 0; }
        public int64 int64_value { get; private set; default = 0; }

        private Value (ValueKind kind) {
            this.kind = kind;
        }

        public static Value object () {
            return new Value (ValueKind.OBJECT);
        }

        public static Value string (string value) {
            var v = new Value (ValueKind.STRING);
            v.string_value = value;
            return v;
        }

        public static Value int32 (int32 value) {
            var v = new Value (ValueKind.INT32);
            v.int_value = value;
            return v;
        }

        public static Value pointer (int32 value) {
            var v = new Value (ValueKind.POINTER);
            v.int_value = value;
            return v;
        }

        public static Value color (int32 value) {
            var v = new Value (ValueKind.COLOR);
            v.int_value = value;
            return v;
        }

        public static Value float32_bits (uint32 value) {
            var v = new Value (ValueKind.FLOAT32);
            v.float_bits = value;
            return v;
        }

        public static Value uint64 (uint64 value) {
            var v = new Value (ValueKind.UINT64);
            v.uint64_value = value;
            return v;
        }

        public static Value int64 (int64 value) {
            var v = new Value (ValueKind.INT64);
            v.int64_value = value;
            return v;
        }

        public Value? lookup (string key) {
            if (kind != ValueKind.OBJECT) return null;
            return object_value.has_key (key) ? object_value[key] : null;
        }

        public string string_member (string key, string fallback = "") {
            var child = lookup (key);
            if (child == null || child.kind != ValueKind.STRING) return fallback;
            return child.string_value;
        }

        public int32 int32_member (string key, int32 fallback = 0) {
            var child = lookup (key);
            if (child == null || child.kind != ValueKind.INT32) return fallback;
            return child.int_value;
        }
    }

    private class Reader : Object {
        private uint8[] data;
        private int offset = 0;

        public Reader (uint8[] data) {
            this.data = data;
        }

        public bool eof {
            get { return offset >= data.length; }
        }

        public uint8 byte () throws Error {
            if (offset >= data.length) {
                throw new ParseError.INVALID_DATA ("Unexpected end of VDF data");
            }
            return data[offset++];
        }

        public int32 int32 () throws Error {
            return (int32) uint32 ();
        }

        public uint32 uint32 () throws Error {
            require_bytes (4, "uint32");
            var b0 = (uint32) data[offset++];
            var b1 = (uint32) data[offset++] << 8;
            var b2 = (uint32) data[offset++] << 16;
            var b3 = (uint32) data[offset++] << 24;
            return b0 | b1 | b2 | b3;
        }

        public uint64 uint64 () throws Error {
            require_bytes (8, "uint64");
            uint64 value = 0;
            for (int i = 0; i < 8; i++) {
                value |= ((uint64) data[offset++]) << (i * 8);
            }
            return value;
        }

        public int64 int64 () throws Error {
            return (int64) uint64 ();
        }

        public string cstring () throws Error {
            var start = offset;
            while (offset < data.length && data[offset] != 0) offset++;
            if (offset >= data.length) {
                throw new ParseError.INVALID_DATA ("Unterminated VDF string");
            }
            var len = offset - start;
            offset++;
            return ((string) data[start:start + len]).dup ();
        }

        public string wide_string () throws Error {
            var start = offset;
            while (offset + 1 < data.length && !(data[offset] == 0 && data[offset + 1] == 0)) {
                offset += 2;
            }
            if (offset + 1 >= data.length) {
                throw new ParseError.INVALID_DATA ("Unterminated VDF wide string");
            }

            var builder = new StringBuilder ();
            for (int i = start; i < offset; i += 2) {
                var code = ((uint16) data[i]) | (((uint16) data[i + 1]) << 8);
                if (code == 0) break;
                builder.append_unichar ((unichar) code);
            }
            offset += 2;
            return builder.str;
        }

        private void require_bytes (int count, string label) throws Error {
            if (offset + count > data.length) {
                throw new ParseError.INVALID_DATA ("Unexpected end of VDF %s".printf (label));
            }
        }
    }

    public static Value parse (uint8[] data) throws Error {
        var reader = new Reader (data);
        var root = Value.object ();
        parse_object_body (reader, root, false);
        if (!reader.eof) {
            throw new ParseError.INVALID_DATA ("Trailing data after VDF root object");
        }
        return root;
    }

    private static void parse_object_body (Reader reader, Value object_value, bool expect_end) throws Error {
        while (!reader.eof) {
            var type = reader.byte ();
            if (type == 0x08) {
                return;
            }

            var key = reader.cstring ();
            switch (type) {
                case 0x00:
                    var child = Value.object ();
                    parse_object_body (reader, child, true);
                    object_value.object_value[key] = child;
                    break;
                case 0x01:
                    object_value.object_value[key] = Value.string (reader.cstring ());
                    break;
                case 0x02:
                    object_value.object_value[key] = Value.int32 (reader.int32 ());
                    break;
                case 0x03:
                    object_value.object_value[key] = Value.float32_bits (reader.uint32 ());
                    break;
                case 0x04:
                    object_value.object_value[key] = Value.pointer (reader.int32 ());
                    break;
                case 0x05:
                    object_value.object_value[key] = Value.string (reader.wide_string ());
                    break;
                case 0x06:
                    object_value.object_value[key] = Value.color (reader.int32 ());
                    break;
                case 0x07:
                    object_value.object_value[key] = Value.uint64 (reader.uint64 ());
                    break;
                case 0x0a:
                    object_value.object_value[key] = Value.int64 (reader.int64 ());
                    break;
                default:
                    throw new ParseError.INVALID_DATA ("Unsupported VDF value type 0x%02x for key '%s'".printf (type, key));
            }
        }

        if (expect_end) {
            throw new ParseError.INVALID_DATA ("Unterminated VDF object");
        }
    }

    public static uint8[] serialize (Value root) throws Error {
        if (root.kind != ValueKind.OBJECT) {
            throw new ParseError.INVALID_DATA ("VDF root must be an object");
        }
        var buffer = new ByteArray ();
        write_object_body (buffer, root, true);
        return buffer.data;
    }

    private static void write_object_body (ByteArray buffer, Value object_value, bool write_end) throws Error {
        foreach (var entry in object_value.object_value.entries) {
            switch (entry.value.kind) {
                case ValueKind.OBJECT:
                    append_byte (buffer, 0x00);
                    append_cstring (buffer, entry.key);
                    write_object_body (buffer, entry.value, true);
                    break;
                case ValueKind.STRING:
                    append_byte (buffer, 0x01);
                    append_cstring (buffer, entry.key);
                    append_cstring (buffer, entry.value.string_value);
                    break;
                case ValueKind.INT32:
                    append_byte (buffer, 0x02);
                    append_cstring (buffer, entry.key);
                    append_int32 (buffer, entry.value.int_value);
                    break;
                case ValueKind.FLOAT32:
                    append_byte (buffer, 0x03);
                    append_cstring (buffer, entry.key);
                    append_uint32 (buffer, entry.value.float_bits);
                    break;
                case ValueKind.POINTER:
                    append_byte (buffer, 0x04);
                    append_cstring (buffer, entry.key);
                    append_int32 (buffer, entry.value.int_value);
                    break;
                case ValueKind.COLOR:
                    append_byte (buffer, 0x06);
                    append_cstring (buffer, entry.key);
                    append_int32 (buffer, entry.value.int_value);
                    break;
                case ValueKind.UINT64:
                    append_byte (buffer, 0x07);
                    append_cstring (buffer, entry.key);
                    append_uint64 (buffer, entry.value.uint64_value);
                    break;
                case ValueKind.INT64:
                    append_byte (buffer, 0x0a);
                    append_cstring (buffer, entry.key);
                    append_int64 (buffer, entry.value.int64_value);
                    break;
            }
        }
        if (write_end) append_byte (buffer, 0x08);
    }

    private static void append_byte (ByteArray buffer, uint8 byte) {
        uint8[] bytes = { byte };
        buffer.append (bytes);
    }

    private static void append_cstring (ByteArray buffer, string value) {
        buffer.append (value.data);
        append_byte (buffer, 0);
    }

    private static void append_int32 (ByteArray buffer, int32 value) {
        append_uint32 (buffer, (uint32) value);
    }

    private static void append_uint32 (ByteArray buffer, uint32 value) {
        uint8[] bytes = {
            (uint8) (value & 0xff),
            (uint8) ((value >> 8) & 0xff),
            (uint8) ((value >> 16) & 0xff),
            (uint8) ((value >> 24) & 0xff)
        };
        buffer.append (bytes);
    }

    private static void append_uint64 (ByteArray buffer, uint64 value) {
        uint8[] bytes = new uint8[8];
        for (int i = 0; i < 8; i++) {
            bytes[i] = (uint8) ((value >> (i * 8)) & 0xff);
        }
        buffer.append (bytes);
    }

    private static void append_int64 (ByteArray buffer, int64 value) {
        append_uint64 (buffer, (uint64) value);
    }

    public static Value empty_shortcuts_file () {
        var root = Value.object ();
        root.object_value["shortcuts"] = Value.object ();
        return root;
    }

    public static Value shortcuts_object (Value root) throws Error {
        if (root.kind != ValueKind.OBJECT) {
            throw new ParseError.INVALID_DATA ("VDF root must be an object");
        }

        var shortcuts = root.lookup ("shortcuts");
        if (shortcuts == null) {
            shortcuts = Value.object ();
            root.object_value["shortcuts"] = shortcuts;
        }
        if (shortcuts.kind != ValueKind.OBJECT) {
            throw new ParseError.INVALID_DATA ("VDF shortcuts member must be an object");
        }
        return shortcuts;
    }

    public static Value build_shortcut (
        int32 appid,
        string app_name,
        string exe,
        string start_dir,
        string icon,
        string launch_options
    ) {
        var shortcut = Value.object ();
        shortcut.object_value["appid"] = Value.int32 (appid);
        shortcut.object_value["AppName"] = Value.string (app_name);
        shortcut.object_value["Exe"] = Value.string (exe);
        shortcut.object_value["StartDir"] = Value.string (start_dir);
        shortcut.object_value["icon"] = Value.string (icon);
        shortcut.object_value["ShortcutPath"] = Value.string ("");
        shortcut.object_value["LaunchOptions"] = Value.string (launch_options);
        shortcut.object_value["IsHidden"] = Value.int32 (0);
        shortcut.object_value["AllowDesktopConfig"] = Value.int32 (1);
        shortcut.object_value["AllowOverlay"] = Value.int32 (1);
        shortcut.object_value["OpenVR"] = Value.int32 (0);
        shortcut.object_value["Devkit"] = Value.int32 (0);
        shortcut.object_value["DevkitGameID"] = Value.string ("");
        shortcut.object_value["DevkitOverrideAppID"] = Value.int32 (0);
        shortcut.object_value["LastPlayTime"] = Value.int32 (0);
        shortcut.object_value["FlatpakAppID"] = Value.string ("");
        shortcut.object_value["tags"] = Value.object ();
        return shortcut;
    }
}
