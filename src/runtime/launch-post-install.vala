namespace Lumoria.Runtime {

    public Models.LoadedPostInstall? load_post_install (Models.PrefixEntry entry, string instance_id) {
        foreach (var loaded in load_prefix_post_installs (entry)) {
            if (loaded.metadata.id == instance_id) return loaded;
        }
        return null;
    }

    public Gee.ArrayList<Models.LoadedPostInstall> load_prefix_post_installs (Models.PrefixEntry entry) {
        var loaded = new Gee.ArrayList<Models.LoadedPostInstall> ();
        foreach (var metadata in entry.post_install_manifests) {
            var spec = load_post_install_file (entry, metadata, null, false);
            if (spec == null) continue;
            var item = new Models.LoadedPostInstall ();
            item.metadata = metadata;
            item.spec = spec;
            loaded.add (item);
        }
        return loaded;
    }

    public Gee.ArrayList<Models.PostInstallLoadError> collect_post_install_load_errors (
        Models.PrefixEntry entry
    ) {
        var errors = new Gee.ArrayList<Models.PostInstallLoadError> ();
        foreach (var metadata in entry.post_install_manifests) {
            load_post_install_file (entry, metadata, errors, true);
        }
        return errors;
    }

    private Models.PostInstallManifest? load_post_install_file (
        Models.PrefixEntry entry,
        Models.PrefixPostInstallManifest metadata,
        Gee.ArrayList<Models.PostInstallLoadError>? errors,
        bool log
    ) {
        if (metadata.id == "") return null;
        var label = metadata.name != "" ? metadata.name : metadata.id;
        var path = metadata.locate_file (entry.resolved_path ());
        if (path == null) {
            var expected = metadata.stored_path (entry.resolved_path ());
            if (log) warning ("Failed to load post-install manifest %s: file not found", expected);
            record_post_install_load_error (errors, label, _("File not found"));
            return null;
        }
        try {
            return Models.PostInstallManifest.load_from_file (path);
        } catch (Error e) {
            if (log) warning ("Failed to load post-install manifest %s: %s", path, e.message);
            record_post_install_load_error (errors, label, e.message);
            return null;
        }
    }

    private void record_post_install_load_error (
        Gee.ArrayList<Models.PostInstallLoadError>? errors,
        string name,
        string reason
    ) {
        if (errors == null) return;
        var error = new Models.PostInstallLoadError ();
        error.name = name;
        error.reason = reason;
        errors.add (error);
    }
}
