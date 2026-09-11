namespace Lumoria.Application {

    public class ResourceStore : Object {
        public signal void changed ();

        public bool busy { get; private set; default = false; }
        public string last_error { get; private set; default = ""; }

        private class DoneWaiter {
            public Utils.BackgroundDone cb;

            public DoneWaiter (owned Utils.BackgroundDone cb) {
                this.cb = (owned) cb;
            }
        }

        private static ResourceStore? _instance;
        private Mutex work_lock = Mutex ();
        private Cond work_cond = Cond ();
        private Gee.ArrayList<DoneWaiter> waiters = new Gee.ArrayList<DoneWaiter> ();

        public static ResourceStore instance () {
            if (_instance == null) _instance = new ResourceStore ();
            return _instance;
        }

        public bool is_current (Models.ResourceEntry entry) {
            var mark = Path.build_filename (Utils.resource_dir (entry.id), "sha256");
            if (!FileUtils.test (mark, FileTest.IS_REGULAR)) return false;
            try {
                string contents;
                FileUtils.get_contents (mark, out contents);
                return contents.strip ().down () == entry.sha256.down ();
            } catch (Error e) {
                warning ("Failed to read resource checksum %s: %s", mark, e.message);
                return false;
            }
        }

        /* Required resources still to fetch; with resource updates off, only missing ones count. */
        public Gee.ArrayList<Models.ResourceEntry> pending_auto_required () {
            try {
                return pending_where (true, !Utils.Preferences.instance ().updates_resources);
            } catch (Error e) {
                warning ("Failed to load resources manifest: %s", e.message);
                last_error = user_error (e);
                return new Gee.ArrayList<Models.ResourceEntry> ();
            }
        }

        public void ensure_all (Cancellable? cancellable = null) throws Error {
            acquire_work (cancellable);
            try {
                ensure_entries (pending_where (false), cancellable, null);
            } catch (Error e) {
                end_work (e);
                throw e;
            }
            end_work (null);
        }

        public void ensure_async (
            bool required_only = false,
            owned Utils.BackgroundDone? done = null,
            Utils.ProgressCallback? progress = null,
            bool missing_only = false
        ) {
            if (!try_begin_work ((owned) done)) return;
            var name = required_only ? "ensure-required-resources" : "ensure-resources";
            Utils.run_background (name, () => {
                ensure_entries (
                    pending_where (required_only, missing_only),
                    Utils.BackgroundJobs.instance ().cancellable,
                    progress
                );
            }, end_work);
        }

        /* Either claims the store or queues the callback for whichever run currently holds it. */
        private bool try_begin_work (owned Utils.BackgroundDone? waiter) {
            work_lock.lock ();
            var started = !busy;
            if (started) {
                busy = true;
                last_error = "";
            } else if (waiter != null) {
                waiters.add (new DoneWaiter ((owned) waiter));
            }
            work_lock.unlock ();
            if (started) notify_ui ();
            return started;
        }

        private void acquire_work (Cancellable? cancellable) throws Error {
            work_lock.lock ();
            try {
                while (busy) {
                    Utils.check_cancelled (cancellable);
                    work_cond.wait_until (work_lock, get_monotonic_time () + 100 * TimeSpan.MILLISECOND);
                }
                busy = true;
                last_error = "";
            } finally {
                work_lock.unlock ();
            }
            notify_ui ();
        }

        private void end_work (Error? error) {
            work_lock.lock ();
            busy = false;
            var queued = waiters;
            waiters = new Gee.ArrayList<DoneWaiter> ();
            work_cond.broadcast ();
            work_lock.unlock ();
            on_main (() => {
                Models.FfxiIconCatalog.instance ().reload ();
                changed ();
                foreach (var waiter in queued) waiter.cb (error);
                return false;
            });
        }

        private void notify_ui () {
            on_main (() => {
                changed ();
                return false;
            });
        }

        private static void on_main (owned SourceFunc action) {
            if (MainContext.default ().is_owner ()) action ();
            else Idle.add ((owned) action);
        }

        private Gee.ArrayList<Models.ResourceEntry> pending_where (
            bool required_only,
            bool missing_only = false
        ) throws Error {
            var list = new Gee.ArrayList<Models.ResourceEntry> ();
            foreach (var entry in Models.ResourceManifest.load ().resources) {
                if (required_only && !entry.required) continue;
                if (is_current (entry)) continue;
                if (missing_only && entry.id == Models.FfxiIconCatalog.RESOURCE_ID
                    && Models.FfxiIconCatalog.installed_root () != null) {
                    continue;
                }
                list.add (entry);
            }
            return list;
        }

        private void ensure_entries (
            Gee.ArrayList<Models.ResourceEntry> waiting,
            Cancellable? cancellable,
            Utils.ProgressCallback? progress
        ) throws Error {
            if (waiting.size == 0) {
                last_error = "";
                return;
            }
            try {
                foreach (var entry in waiting) {
                    ensure_entry (entry, cancellable, progress);
                }
                last_error = "";
            } catch (Error e) {
                warning ("Resource download failed: %s", e.message);
                last_error = user_error (e);
                throw e;
            }
        }

        private void ensure_entry (
            Models.ResourceEntry entry,
            Cancellable? cancellable,
            Utils.ProgressCallback? progress
        ) throws Error {
            if (is_current (entry)) return;
            Utils.check_cancelled (cancellable);
            var cache = Path.build_filename (Utils.cache_dir (), "resources", Path.get_basename (entry.url));
            Utils.ensure_downloaded_file (
                entry.url,
                cache,
                entry.size,
                entry.sha256,
                entry.id,
                progress,
                null,
                cancellable,
                true
            );
            Utils.check_cancelled (cancellable);

            var parent = Utils.resources_dir ();
            var dest = Utils.resource_dir (entry.id);
            var staging = Path.build_filename (parent, ".tmp-%s".printf (entry.id));
            if (FileUtils.test (staging, FileTest.EXISTS)) Utils.remove_recursive (staging);
            Utils.ensure_dir (staging);
            try {
                Utils.extract_archive (cache, staging, {}, cancellable);
                var payload = Models.FfxiIconCatalog.payload_root (staging);
                if (payload == null) {
                    throw new LumoriaError.FAILED (
                        _("Resource archive is missing %s").printf (Models.FfxiIconCatalog.REGISTRY_FILE)
                    );
                }
                Utils.replace_dir_atomic (payload, dest, _("Failed to install resource %s").printf (entry.id));
                Utils.write_text_atomic (Path.build_filename (dest, "sha256"), entry.sha256 + "\n");
            } finally {
                if (FileUtils.test (staging, FileTest.EXISTS) && staging != dest) {
                    Utils.remove_recursive (staging);
                }
            }
        }
    }
}
