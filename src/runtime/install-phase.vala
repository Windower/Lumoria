namespace Lumoria.Runtime {

    private bool step_applies (
        Models.InstallStep step,
        Gee.HashMap<string, string> vars,
        bool ignore_when
    ) {
        return ignore_when || step.when == null || step.when.evaluate (vars);
    }

    /* One vars map per non-empty line of a for_each list, with ITEM bound; just the input when there is no list. */
    private Gee.List<Gee.HashMap<string, string>> item_vars_for (string for_each, Gee.HashMap<string, string> vars) {
        var result = new Gee.ArrayList<Gee.HashMap<string, string>> ();
        if (for_each == "") {
            result.add (vars);
            return result;
        }
        foreach (var line in Utils.expand_vars (for_each, vars).split ("\n")) {
            var item = line.strip ();
            if (item == "") continue;
            var item_vars = new Gee.HashMap<string, string> ();
            item_vars.set_all (vars);
            item_vars["ITEM"] = item;
            result.add (item_vars);
        }
        return result;
    }

    class StepReporter : Object {
        public int total { get; set; }
        public InstallProgress progress { get; private set; }
        public RuntimeLog logger { get; private set; }
        public Cancellable? cancellable { get; private set; }
        public int idx { get; private set; }

        public StepReporter (
            int total,
            InstallProgress progress,
            RuntimeLog logger,
            Cancellable? cancellable
        ) {
            this.total = total;
            this.progress = progress;
            this.logger = logger;
            this.cancellable = cancellable;
            this.idx = 0;
        }

        public void label (string text) throws IOError {
            advance ();
            emit_progress (text);
        }

        public void run_step (
            Models.InstallStep step,
            Gee.HashMap<string, string> vars,
            WinePaths paths,
            WineEnv env,
            bool ignore_when = false
        ) throws Error {
            if (!step_applies (step, vars, ignore_when)) {
                logger.typed (
                    LogType.SKIP,
                    "when clause not met, skipping: %s".printf (Utils.expand_vars (step.description, vars))
                );
                return;
            }
            advance ();
            var desc = Utils.expand_vars (step.description, vars);
            emit_progress (desc);
            logger.step (idx, total, desc, step.step_type.id ());
            var step_env = step.env.size > 0 ? env.copy () : env;
            if (step.env.size > 0) apply_env_rules (step_env, step.env, vars);
            var ctx = new InstallStepContext ();
            ctx.step = step;
            ctx.vars = vars;
            ctx.paths = paths;
            ctx.env = step_env;
            ctx.logger = logger;
            ctx.cancellable = cancellable;
            run_install_step (ctx);
        }

        public void run_download (Models.DownloadItem dl, Gee.HashMap<string, string> vars) throws Error {
            advance ();
            var id = Utils.expand_vars (dl.id, vars);
            var url = Utils.expand_vars (dl.url, vars);
            var dest = Utils.expand_vars (dl.dest, vars);
            var sha256 = Utils.expand_vars (dl.sha256, vars);
            var algorithm = Utils.expand_vars (dl.checksum_algorithm, vars);
            emit_progress ("Downloading %s...".printf (id));

            if (sha256 == "") {
                logger.typed (LogType.WARN, "%s has no checksum; using size-only cache validation".printf (id));
            }
            if (Utils.validate_downloaded_file (dest, 0, sha256, id, algorithm != "" ? algorithm : null, sha256 != "")) {
                logger.typed (LogType.CACHED, dest);
                return;
            }
            logger.typed (LogType.DOWNLOAD, "%s -> %s".printf (url, dest));
            Utils.download_file_verified (
                url, dest, 0, sha256, id, download_progress_cb (),
                algorithm != "" ? algorithm : null, cancellable, sha256 != ""
            );
            logger.typed (LogType.DONE, id);
        }

        public DownloadProgress download_progress_cb () {
            var sig = progress;
            int slot = idx;
            return (downloaded, total_bytes) => {
                if (total_bytes <= 0) return;
                var denom = total > 0 ? total : 1;
                var base_p = (double) (slot - 1) / denom;
                var range = 1.0 / denom;
                sig.progress_changed (base_p + (double) downloaded / (double) total_bytes * range);
            };
        }

        private void advance () throws IOError {
            Utils.check_cancelled (cancellable);
            idx++;
        }

        private void emit_progress (string text) {
            if (idx > total) total = idx;
            var denom = total > 0 ? total : 1;
            progress.step_changed ("(%d/%d) %s".printf (idx, denom, text));
            progress.progress_changed ((double) (idx - 1) / denom);
        }
    }

    class ResolvedRedistSet : Object {
        public Gee.ArrayList<Models.RedistManifest> specs { get; private set; }
        public Gee.ArrayList<Models.InstallStep> code_steps { get; private set; }
        public Gee.ArrayList<Models.DownloadItem> downloads { get; private set; }

        public ResolvedRedistSet () {
            specs = new Gee.ArrayList<Models.RedistManifest> ();
            code_steps = new Gee.ArrayList<Models.InstallStep> ();
            downloads = new Gee.ArrayList<Models.DownloadItem> ();
        }

        public static ResolvedRedistSet resolve (
            Gee.Iterable<string> redist_ids,
            Gee.Map<string, Models.RedistManifest> all
        ) {
            var set = new ResolvedRedistSet ();
            var deferred = new Gee.ArrayList<Models.RedistManifest> ();
            var seen = new Gee.HashSet<string> ();
            resolve_into (set, deferred, redist_ids, all, seen);
            foreach (var spec in deferred) {
                set.specs.add (spec);
                set.downloads.add_all (spec.downloads);
            }
            return set;
        }

        private static void resolve_into (
            ResolvedRedistSet set,
            Gee.ArrayList<Models.RedistManifest> deferred,
            Gee.Iterable<string> redist_ids,
            Gee.Map<string, Models.RedistManifest> all,
            Gee.HashSet<string> seen
        ) {
            foreach (var rid in redist_ids) {
                if (!seen.add (rid)) continue;
                if (all.has_key (rid)) {
                    var spec = all[rid];
                    if (spec.redists.size > 0)
                        resolve_into (set, deferred, spec.redists, all, seen);
                    if (spec.defer) {
                        deferred.add (spec);
                    } else {
                        set.specs.add (spec);
                        set.downloads.add_all (spec.downloads);
                    }
                } else {
                    var step = new Models.InstallStep ();
                    step.step_type = Models.InstallStepKind.REDIST;
                    step.command = rid;
                    step.description = builtin_redist_label (rid);
                    set.code_steps.add (step);
                }
            }
        }
    }

    class InstallPhase : Object {
        public Gee.ArrayList<Models.DownloadItem> downloads { get; private set; }
        public Gee.ArrayList<Models.InstallStep> steps { get; private set; }
        public ResolvedRedistSet redists { get; private set; }
        public Gee.HashMap<string, string> vars { get; private set; }
        public Models.PrefixEntry? prefix_entry { get; private set; }
        public bool reinstall_mode { get; private set; }

        public InstallPhase (
            Gee.ArrayList<Models.DownloadItem> downloads,
            Gee.ArrayList<Models.InstallStep> steps,
            ResolvedRedistSet redists,
            Gee.HashMap<string, string> vars,
            Models.PrefixEntry? prefix_entry = null,
            bool reinstall_mode = false
        ) {
            this.downloads = downloads;
            this.steps = steps;
            this.redists = redists;
            this.vars = vars;
            this.prefix_entry = prefix_entry;
            this.reinstall_mode = reinstall_mode;
        }

        public int download_count {
            get {
                int count = 0;
                foreach (var dl in redists.downloads) {
                    if (dl.when == null || dl.when.evaluate (vars)) count++;
                }
                foreach (var dl in downloads) {
                    foreach (var dl_vars in item_vars_for (dl.for_each, vars)) {
                        if (dl.when == null || dl.when.evaluate (dl_vars)) count++;
                    }
                }
                return count;
            }
        }

        public int exec_count {
            get {
                int count = redists.code_steps.size;
                foreach (var spec in redists.specs) {
                    var spec_vars = redist_vars (spec);
                    bool spec_force = reinstall_mode && spec.reinstallable;
                    foreach (var step in spec.steps) {
                        foreach (var step_vars in item_vars_for (step.for_each, spec_vars)) {
                            if (step_applies (step, step_vars, spec_force && step.idempotent)) count++;
                        }
                    }
                }
                foreach (var step in steps) {
                    foreach (var step_vars in item_vars_for (step.for_each, vars)) {
                        if (step_applies (step, step_vars, false)) count++;
                    }
                }
                return count;
            }
        }

        public int step_count {
            get { return download_count + exec_count; }
        }

        public void run_downloads (StepReporter rep, string phase_banner) throws Error {
            rep.logger.phase (phase_banner);
            foreach (var dl in redists.downloads) {
                if (dl.when != null && !dl.when.evaluate (vars)) continue;
                rep.run_download (dl, vars);
            }
            foreach (var dl in downloads) {
                foreach (var dl_vars in item_vars_for (dl.for_each, vars)) {
                    if (dl.when != null && !dl.when.evaluate (dl_vars)) continue;
                    rep.run_download (dl, dl_vars);
                }
            }
        }

        public void run_steps (
            StepReporter rep,
            WinePaths paths,
            WineEnv env,
            string? phase_banner
        ) throws Error {
            if (phase_banner != null) rep.logger.phase (phase_banner);
            foreach (var spec in redists.specs) {
                if (spec.defer) continue;
                run_redist_manifest (rep, spec, paths, env);
            }
            foreach (var step in redists.code_steps) {
                rep.run_step (step, vars, paths, env);
                mark_redist_installed (prefix_entry, step.command);
            }
            foreach (var step in steps) {
                foreach (var step_vars in item_vars_for (step.for_each, vars)) {
                    rep.run_step (step, step_vars, paths, env);
                }
            }
            // Deferred specs run AFTER installer steps but still while wineserver
            // is alive: dropping native DLLs after wineserver -k lets the next
            // wine bootstrap reinitialize the prefix and clobber them.
            foreach (var spec in redists.specs) {
                if (!spec.defer) continue;
                run_redist_manifest (rep, spec, paths, env);
            }
        }

        private void run_redist_manifest (
            StepReporter rep,
            Models.RedistManifest spec,
            WinePaths paths,
            WineEnv env
        ) throws Error {
            rep.logger.banner (spec.display_label ());
            var spec_vars = redist_vars (spec, paths, env);
            var redist_env = spec.env.size > 0 ? env.copy () : env;
            if (spec.env.size > 0) apply_env_rules (redist_env, spec.env, spec_vars);
            bool spec_force = reinstall_mode && spec.reinstallable;
            foreach (var step in spec.steps) {
                foreach (var step_vars in item_vars_for (step.for_each, spec_vars)) {
                    rep.run_step (step, step_vars, paths, redist_env, spec_force && step.idempotent);
                }
            }
            mark_redist_installed (prefix_entry, spec.id);
        }

        private Gee.HashMap<string, string> redist_vars (
            Models.RedistManifest spec,
            WinePaths? paths = null,
            WineEnv? env = null
        ) {
            if (spec.variables.size == 0 && spec.variable_rules.size == 0) return vars;
            var merged = new Gee.HashMap<string, string> ();
            merged.set_all (vars);
            merged.set_all (spec.variables);
            apply_variable_rules (merged, spec.variable_rules);
            finalize_manifest_vars (merged, paths, env);
            return merged;
        }
    }

    private void mark_redist_installed (Models.PrefixEntry? entry, string redist_id) {
        if (entry == null || redist_id == "") return;
        if (entry.installed_redists.contains (redist_id)) return;
        entry.installed_redists.add (redist_id);
    }
}
