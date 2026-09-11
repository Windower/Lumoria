namespace Lumoria.Runtime {

    internal void run_manifest_extract_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var vars = ctx.vars;
        var logger = ctx.logger;
        var cancellable = ctx.cancellable;
        if (step.manifest_schema == null) {
            throw new LumoriaError.INVALID_MANIFEST ("manifest_extract step missing manifest_schema");
        }

        var manifest_url = ctx.expand (step.manifest_url);
        if (manifest_url == "") {
            throw new LumoriaError.INVALID_MANIFEST ("manifest_extract step has empty manifest_url");
        }

        var dst = ctx.expand (step.dst);
        var remote = new Utils.RemoteManifestCache (manifest_url);

        var files = Utils.fetch_remote_manifest_sync (
            manifest_url, step.manifest_schema, remote.cache_path, vars, cancellable
        );

        foreach (var file in files) {
            Utils.check_cancelled (cancellable);
            var dl_dest = ensure_remote_manifest_file (file, remote, logger, cancellable);
            logger.typed (LogType.EXTRACT, "%s -> %s".printf (file.filename, dst));
            Utils.extract_archive (dl_dest, dst, {}, cancellable);
        }
    }

    internal void run_manifest_cache_clear_step (InstallStepContext ctx) throws Error {
        var url = ctx.expand (ctx.step.manifest_url);
        if (url == "") throw new LumoriaError.INVALID_MANIFEST ("manifest_cache_clear: empty manifest_url");
        var remote = new Utils.RemoteManifestCache (url);
        if (FileUtils.test (remote.cache_path, FileTest.EXISTS)) {
            if (FileUtils.remove (remote.cache_path) == 0) {
                ctx.logger.typed (LogType.COPY, "cleared manifest envelope: %s".printf (remote.url_hash));
            } else {
                ctx.logger.typed (LogType.WARN, "could not clear manifest envelope %s: %s".printf (
                    remote.url_hash, Posix.strerror (Posix.errno)
                ));
            }
        } else {
            ctx.logger.typed (LogType.SKIP, "manifest envelope not cached: %s".printf (remote.url_hash));
        }
    }

    internal void run_manifest_downloads_clear_step (InstallStepContext ctx) throws Error {
        var url = ctx.expand (ctx.step.manifest_url);
        if (url == "") throw new LumoriaError.INVALID_MANIFEST ("manifest_downloads_clear: empty manifest_url");
        var remote = new Utils.RemoteManifestCache (url);
        if (FileUtils.test (remote.download_dir, FileTest.IS_DIR)) {
            ctx.remove_tree (remote.download_dir);
            ctx.logger.typed (LogType.COPY, "cleared manifest downloads: %s".printf (remote.url_hash));
        } else {
            ctx.logger.typed (LogType.SKIP, "manifest downloads not cached: %s".printf (remote.url_hash));
        }
    }

    internal string ensure_remote_manifest_file (
        Utils.RemoteManifestFile file,
        Utils.RemoteManifestCache remote,
        RuntimeLog? logger,
        Cancellable? cancellable
    ) throws Error {
        var dl_dest = remote.download_path (file.filename);
        var algorithm = file.checksum_algorithm != "" ? file.checksum_algorithm : null;
        if (Utils.validate_downloaded_file (dl_dest, 0, file.checksum, file.filename, algorithm)) {
            if (logger != null) logger.typed (LogType.CACHED, dl_dest);
            return dl_dest;
        }
        if (logger != null) logger.typed (LogType.DOWNLOAD, "%s -> %s".printf (file.download_url, dl_dest));
        Utils.download_file_verified (
            file.download_url, dl_dest, 0, file.checksum, file.filename, null, algorithm, cancellable
        );
        return dl_dest;
    }
}
