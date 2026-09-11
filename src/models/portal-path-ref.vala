namespace Lumoria.Models {

    public class PortalPathRef : Object {
        public string document_id { get; set; default = ""; }
        public string document_path { get; set; default = ""; }
        public string uri { get; set; default = ""; }

        public bool is_empty () {
            return document_id == "" || document_path == "";
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            if (document_id != "") obj.set_string_member ("document_id", document_id);
            if (document_path != "") obj.set_string_member ("document_path", document_path);
            if (uri != "") obj.set_string_member ("uri", uri);
            return obj;
        }

        public PortalPathRef copy () {
            var r = new PortalPathRef ();
            r.document_id = document_id;
            r.document_path = document_path;
            r.uri = uri;
            return r;
        }

        public static PortalPathRef from_json (Json.Object obj) throws Error {
            var r = new PortalPathRef ();
            r.document_id = json_string (obj, "document_id");
            r.document_path = json_string (obj, "document_path");
            r.uri = json_string (obj, "uri");
            if (r.is_empty () && (r.document_id != "" || r.document_path != "" || r.uri != "")) {
                throw new LumoriaError.INVALID_MANIFEST (
                    _("Portal path requires both document_id and document_path")
                );
            }
            return r;
        }
    }

}
