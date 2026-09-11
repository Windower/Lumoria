namespace Lumoria.Utils {
    [DBus (name = "org.freedesktop.portal.Documents")]
    private interface DocumentPortal : Object {
        public abstract uint8[] GetMountPoint () throws Error;
    }

    public static Models.PortalPathRef? portal_path_ref_from_path_uri (
        string raw_path,
        string raw_uri = ""
    ) {
        string document_id;
        string document_path;
        if (!parse_document_portal_path (raw_path, out document_id, out document_path)) {
            var uri_path = file_uri_path (raw_uri);
            if (!parse_document_portal_path (uri_path, out document_id, out document_path)) return null;
        }

        var portal = new Models.PortalPathRef ();
        portal.document_id = document_id;
        portal.document_path = document_path;
        portal.uri = raw_uri;
        return portal;
    }

    public static string resolve_user_path (
        string raw_path,
        Models.PortalPathRef? portal_ref = null,
        string raw_uri = ""
    ) {
        if (raw_path != "" && FileUtils.test (raw_path, FileTest.EXISTS)) return raw_path;

        var uri_path = file_uri_path (raw_uri);
        if (uri_path != "" && FileUtils.test (uri_path, FileTest.EXISTS)) return uri_path;

        var portal_path = resolve_portal_path (portal_ref);
        if (portal_path != "") return portal_path;

        return raw_path != "" ? raw_path : uri_path;
    }

    public static string resolve_portal_path (Models.PortalPathRef? portal_ref) {
        if (portal_ref == null || portal_ref.is_empty ()) return "";

        var mount = document_portal_mount_point ();
        if (mount == "") return "";

        var path = Path.build_filename (
            mount,
            portal_ref.document_id,
            portal_ref.document_path
        );
        if (FileUtils.test (path, FileTest.EXISTS)) return path;

        var by_app = Path.build_filename (
            mount,
            "by-app",
            Config.APP_ID,
            portal_ref.document_id,
            portal_ref.document_path
        );
        if (FileUtils.test (by_app, FileTest.EXISTS)) return by_app;

        return "";
    }

    private static string file_uri_path (string raw_uri) {
        if (raw_uri == "") return "";
        try {
            var uri = Uri.parse (raw_uri, UriFlags.NONE);
            if (uri.get_scheme () != "file") return "";
            var path = uri.get_path ();
            return path != null ? path : "";
        } catch (UriError e) {
            return "";
        }
    }

    private static bool parse_document_portal_path (
        string raw_path,
        out string document_id,
        out string document_path
    ) {
        document_id = "";
        document_path = "";

        var normalized = raw_path.replace ("\\", "/");
        var marker = "/doc/";
        var idx = normalized.index_of (marker);
        if (idx < 0) return false;

        var rest = normalized.substring (idx + marker.length);
        if (rest.has_prefix ("by-app/")) {
            var by_app_parts = rest.split ("/", 4);
            if (by_app_parts.length < 4) return false;
            document_id = by_app_parts[2];
            document_path = by_app_parts[3];
            return document_id != "" && document_path != "";
        }

        var parts = rest.split ("/", 2);
        if (parts.length < 2) return false;
        document_id = parts[0];
        document_path = parts[1];
        return document_id != "" && document_path != "";
    }

    private static string document_portal_mount_point () {
        try {
            var portal = Bus.get_proxy_sync<DocumentPortal> (
                BusType.SESSION,
                "org.freedesktop.portal.Documents",
                "/org/freedesktop/portal/documents"
            );
            return uint8_array_to_string (portal.GetMountPoint ());
        } catch (Error e) {
            warning ("Failed to resolve document portal mount point: %s", e.message);
            return "";
        }
    }

    private static string uint8_array_to_string (uint8[] bytes) {
        var builder = new StringBuilder ();
        foreach (var b in bytes) {
            if (b == 0) break;
            builder.append_c ((char) b);
        }
        return builder.str;
    }
}
