namespace Lumoria.Application {

    public class ScriptService : Object {
        private Context ctx;

        public ScriptService (Context ctx) {
            this.ctx = ctx;
        }

        public Models.PrefixPostInstallManifest attach (
            Models.PrefixEntry entry,
            string path,
            string uri
        ) throws Error {
            var spec = Models.PostInstallManifest.load_from_file (path);
            if (entry.has_post_install_manifest_id (spec.id)) {
                throw new LumoriaError.FAILED (_("This script is already attached to the prefix."));
            }

            var meta = new Models.PrefixPostInstallManifest ();
            meta.ensure_id ();
            meta.original_path = path;
            meta.original_uri = uri;
            meta.manifest_id = spec.id;
            meta.name = spec.display_label ();
            Runtime.store_post_install_manifest (entry.resolved_path (), path, meta.id);
            entry.post_install_manifests.add (meta);
            ctx.prefixes.save ();
            ctx.actions.invalidate_and_prune (entry);
            return meta;
        }

        public void detach (Models.PrefixEntry entry, string instance_id) throws Error {
            for (int i = 0; i < entry.post_install_manifests.size; i++) {
                if (entry.post_install_manifests[i].id != instance_id) continue;
                var stored = entry.post_install_manifests[i].stored_path (entry.resolved_path ());
                entry.post_install_manifests.remove_at (i);
                if (FileUtils.test (stored, FileTest.EXISTS)) {
                    try {
                        Utils.remove_file_or_symlink (stored);
                    } catch (Error e) {
                        warning ("Failed to remove stored script %s: %s", stored, e.message);
                    }
                }
                ctx.prefixes.save ();
                ctx.actions.invalidate_and_prune (entry);
                return;
            }
            throw new LumoriaError.NOT_FOUND (_("This script is not attached to the prefix."));
        }
    }
}
