namespace Lumoria.Runtime {

    public class DownloadResult : Object {
        public string version { get; set; default = ""; }
        public string extracted_to { get; set; default = ""; }
    }

    public delegate void DownloadProgress (int64 downloaded, int64 total);

    public DownloadResult download_and_extract_runner (
        Models.RunnerManifest spec,
        string variant_id,
        string version,
        DownloadProgress? progress,
        RuntimeLog logger,
        bool allow_download = true,
        Cancellable? cancellable = null
    ) throws Error {
        Utils.check_cancelled (cancellable);
        var adapter = new Runtime.RunnerToolAdapter (spec, variant_id);
        var ver = Models.ToolVersionRef.is_pinned (version)
            ? new Models.ToolVersion (version)
            : new Models.ToolVersion.latest ("");

        if (adapter.is_installed (ver)) {
            return runner_result (adapter, ver);
        }

        if (!allow_download) {
            throw new LumoriaError.FAILED (
                _("Runner %s %s is not installed. Open Lumoria to download it before launching from CLI.").printf (
                    spec.id, version
                )
            );
        }

        adapter.install_version (ver, (downloaded, total) => {
            if (progress != null) progress (downloaded, total);
        }, cancellable);
        return runner_result (adapter, ver);
    }

    private DownloadResult runner_result (Runtime.RunnerToolAdapter adapter, Models.ToolVersion ver) throws Error {
        var result = new DownloadResult ();
        result.version = ver.is_latest ? adapter.resolve_latest_tag () : ver.tag;
        result.extracted_to = adapter.installed_path (ver);
        return result;
    }
}
