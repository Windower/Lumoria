namespace Lumoria.Application {

    class ManifestDownloadProgress : Object {
        private Mutex mutex = Mutex ();
        private ManifestUpdateService service;
        private int64 total;
        private int file_count;
        private int completed = 0;

        public int64 downloaded { get; private set; default = 0; }

        public ManifestDownloadProgress (ManifestUpdateService service, int64 total, int file_count) {
            this.service = service;
            this.total = total;
            this.file_count = file_count;
        }

        public void add_bytes (int64 delta) {
            if (delta == 0) return;
            mutex.lock ();
            downloaded += delta;
            var got = downloaded;
            mutex.unlock ();
            service.report_progress (got, total);
        }

        public void file_done () {
            mutex.lock ();
            completed++;
            var n = completed;
            mutex.unlock ();
            service.report_status (_("Downloading manifests (%d / %d)").printf (n, file_count));
        }
    }

    class ManifestDownloadWorker : Utils.Worker<ManifestFileEntry> {
        private ManifestUpdateService service;
        private ManifestDownloadProgress tracker;
        private Cancellable? cancellable;

        public ManifestDownloadWorker (
            ManifestUpdateService service,
            ManifestDownloadProgress tracker,
            Cancellable? cancellable
        ) {
            this.service = service;
            this.tracker = tracker;
            this.cancellable = cancellable;
        }

        public override void run (ManifestFileEntry file) throws Error {
            Utils.check_cancelled (cancellable);
            var dest = Models.ManifestStore.staging_file (file.path);
            int64 last = 0;
            Utils.ensure_downloaded_file (
                service.file_url (file.path, file.sha256),
                dest,
                file.size,
                file.sha256,
                file.path,
                (got, _total) => {
                    tracker.add_bytes (got - last);
                    last = got;
                },
                null,
                cancellable,
                true
            );
            var final_size = file.size > 0 ? file.size : Utils.file_size_or_zero (dest);
            tracker.add_bytes (final_size - last);
            tracker.file_done ();
        }
    }

    class ReleaseIndexBatch : Object {
        public Gee.ArrayList<string> failures {
            get; default = new Gee.ArrayList<string> ();
        }
        private Mutex mutex = Mutex ();

        public void fail (string tool_id) {
            mutex.lock ();
            failures.add (tool_id);
            mutex.unlock ();
        }
    }

    class ReleaseIndexWorker : Utils.Worker<Runtime.ToolAdapter> {
        private ReleaseIndexBatch batch;
        private bool force;

        public ReleaseIndexWorker (ReleaseIndexBatch batch, bool force) {
            this.batch = batch;
            this.force = force;
        }

        public override void run (Runtime.ToolAdapter tool) {
            try {
                if (force) tool.invalidate_cache ();
                tool.resolve_latest_tag ();
            } catch (Error e) {
                warning ("Failed to refresh %s releases: %s", tool.tool_id, e.message);
                batch.fail (tool.tool_id);
            }
        }
    }
}
