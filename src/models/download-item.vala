namespace Lumoria.Models {

    public class DownloadItem : Object {
        public string id { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public string dest { get; set; default = ""; }
        public string sha256 { get; set; default = ""; }
        public string checksum_algorithm { get; set; default = ""; }
        public WhenClause? when { get; set; default = null; }
        public string for_each { get; set; default = ""; }

        public static DownloadItem from_json (Json.Object obj) throws Error {
            var d = new DownloadItem ();
            d.id = json_string (obj, "id");
            d.url = json_string (obj, "url");
            d.dest = json_string (obj, "dest");
            d.sha256 = json_string (obj, "sha256");
            d.checksum_algorithm = json_string (obj, "checksum_algorithm");
            d.when = WhenClause.from_json_member (obj);
            d.for_each = json_string_or_array (obj, "for_each");
            if (d.id == "" || d.url == "" || d.dest == "") {
                throw new LumoriaError.INVALID_MANIFEST (_("Download items require id, url, and dest"));
            }
            return d;
        }
    }

}
