namespace Lumoria.Utils {

    public delegate void GitProgressCallback (int64 received, int64 total);

    public class GitTarget : Object {
        public string branch { get; set; default = ""; }
        public string tag { get; set; default = ""; }
        public string commit { get; set; default = ""; }

        public bool is_empty () {
            return branch == "" && tag == "" && commit == "";
        }
    }

    private static bool _git_initialized = false;

    public void git_init_once () {
        if (_git_initialized) return;
        Ggit.init ();
        _git_initialized = true;
    }

    public void git_clone (
        string url,
        string dest,
        GitTarget target,
        owned GitProgressCallback? progress
    ) throws Error {
        git_init_once ();
        ensure_dir (Path.get_dirname (dest));

        var location = File.new_for_path (dest);
        var dot_git = File.new_for_path (Path.build_filename (dest, ".git"));

        Ggit.Repository repo;
        if (dot_git.query_exists ()) {
            repo = open_existing_repo (location);
            fetch_origin (repo, (owned) progress);
        } else {
            var callbacks = new GitProgressCallbacks ((owned) progress);
            var fetch_opts = new Ggit.FetchOptions ();
            fetch_opts.set_remote_callbacks (callbacks);

            var clone_opts = new Ggit.CloneOptions ();
            clone_opts.set_fetch_options (fetch_opts);
            if (target.branch != "") {
                clone_opts.set_checkout_branch (target.branch);
            }

            try {
                repo = Ggit.Repository.clone (url, location, clone_opts);
            } catch (Error e) {
                throw new IOError.FAILED ("git: clone failed: %s", e.message);
            }
            if (repo == null) {
                throw new IOError.FAILED ("git: clone returned null repository for %s", url);
            }
        }

        apply_target (repo, target);
    }

    public void git_pull (
        string dest,
        GitTarget target,
        owned GitProgressCallback? progress
    ) throws Error {
        git_init_once ();

        var dot_git = File.new_for_path (Path.build_filename (dest, ".git"));
        if (!dot_git.query_exists ()) {
            throw new IOError.FAILED ("git: not a git working tree: %s", dest);
        }

        var repo = open_existing_repo (File.new_for_path (dest));
        fetch_origin (repo, (owned) progress);
        apply_target (repo, target);
    }

    private Ggit.Repository open_existing_repo (File location) throws Error {
        try {
            var repo = Ggit.Repository.open (location);
            if (repo == null) {
                throw new IOError.FAILED ("git: failed to open repository at %s", location.get_path ());
            }
            return repo;
        } catch (Error e) {
            throw new IOError.FAILED ("git: open failed: %s", e.message);
        }
    }

    private void fetch_origin (Ggit.Repository repo, owned GitProgressCallback? progress) throws Error {
        Ggit.Remote? remote = null;
        try {
            remote = repo.lookup_remote ("origin");
        } catch (Error e) {
            throw new IOError.FAILED ("git: lookup_remote(origin) failed: %s", e.message);
        }
        if (remote == null) {
            throw new IOError.FAILED ("git: no 'origin' remote configured");
        }

        var callbacks = new GitProgressCallbacks ((owned) progress);
        var fetch_opts = new Ggit.FetchOptions ();
        fetch_opts.set_remote_callbacks (callbacks);

        try {
            remote.connect (Ggit.Direction.FETCH, callbacks, null, null);
            remote.download (null, fetch_opts);
            remote.update_tips (callbacks, true, Ggit.RemoteDownloadTagsType.AUTO, "fetch");
            remote.disconnect ();
        } catch (Error e) {
            throw new IOError.FAILED ("git: fetch failed: %s", e.message);
        }
    }

    private void apply_target (Ggit.Repository repo, GitTarget target) throws Error {
        var oid = resolve_target_oid (repo, target);
        if (oid == null) {
            throw new IOError.FAILED ("git: could not resolve target");
        }

        Ggit.Commit commit_obj;
        try {
            commit_obj = repo.lookup_commit (oid);
        } catch (Error e) {
            throw new IOError.FAILED ("git: commit %s not reachable: %s", oid.to_string (), e.message);
        }
        if (commit_obj == null) {
            throw new IOError.FAILED ("git: commit %s not found after fetch", oid.to_string ());
        }

        var checkout_opts = new Ggit.CheckoutOptions ();
        checkout_opts.set_strategy (Ggit.CheckoutStrategy.FORCE);
        try {
            repo.reset (commit_obj, Ggit.ResetType.HARD, checkout_opts);
        } catch (Error e) {
            throw new IOError.FAILED ("git: hard reset to %s failed: %s", oid.to_string (), e.message);
        }
    }

    private Ggit.OId? resolve_target_oid (Ggit.Repository repo, GitTarget target) throws Error {
        if (target.commit != "") {
            var oid = new Ggit.OId.from_string (target.commit);
            if (target.tag != "") {
                var tag_oid = lookup_ref_oid (repo, "refs/tags/" + target.tag);
                if (tag_oid == null) {
                    throw new IOError.FAILED ("git: tag %s not found", target.tag);
                }
                if (!tag_oid.equal (oid)) {
                    throw new IOError.FAILED (
                        "git: tag %s points at %s, expected %s",
                        target.tag, tag_oid.to_string (), oid.to_string ()
                    );
                }
            }
            return oid;
        }

        if (target.tag != "") {
            var oid = lookup_ref_oid (repo, "refs/tags/" + target.tag);
            if (oid == null) {
                throw new IOError.FAILED ("git: tag %s not found", target.tag);
            }
            return oid;
        }

        if (target.branch != "") {
            var oid = lookup_ref_oid (repo, "refs/remotes/origin/" + target.branch);
            if (oid == null) {
                throw new IOError.FAILED ("git: branch origin/%s not found", target.branch);
            }
            return oid;
        }

        return lookup_ref_oid (repo, "refs/remotes/origin/HEAD");
    }

    private Ggit.OId? lookup_ref_oid (Ggit.Repository repo, string ref_name) throws Error {
        Ggit.Ref? r = null;
        try {
            r = repo.lookup_reference (ref_name);
        } catch (Error e) {
            return null;
        }
        if (r == null) return null;
        var resolved = r.resolve ();
        if (resolved == null) return null;
        return resolved.get_target ();
    }

    private class GitProgressCallbacks : Ggit.RemoteCallbacks {
        private GitProgressCallback? cb;

        public GitProgressCallbacks (owned GitProgressCallback? cb) {
            this.cb = (owned) cb;
        }

        public override void transfer_progress (Ggit.TransferProgress stats) {
            if (cb == null) return;
            cb ((int64) stats.get_received_objects (), (int64) stats.get_total_objects ());
        }
    }
}
