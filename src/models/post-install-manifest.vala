namespace Lumoria.Models {

    public class PostInstallManifest : InstallableManifest {

        public static PostInstallManifest load_from_file (string path) throws Error {
            string json;
            FileUtils.get_contents (path, out json);
            ManifestSchema.validate_json ("post-install", json);
            return from_json (parse_data_object (json));
        }

        public static PostInstallManifest from_json (Json.Object obj) throws Error {
            var s = new PostInstallManifest ();
            s.parse_installable (obj);
            return s;
        }
    }
}
