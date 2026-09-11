namespace Lumoria.Runtime {

    public delegate void InstallOpenHandler (string target);

    public class Session : Object {
        public InstallOpenHandler? open_handler;
        public signal void persist_failed (string message);

        private unowned Models.PrefixRegistry? live_registry;
        private Utils.FallibleAction? registry_persist_handler;
        private Models.PrefixEntry? worker_prefix;
        private PersistQueue persist_queue = new PersistQueue ();
        private uint persist_idle = 0;

        public void bind_registry (Models.PrefixRegistry registry, owned Utils.FallibleAction persist) {
            live_registry = registry;
            registry_persist_handler = (owned) persist;
        }

        public void set_worker_prefix (Models.PrefixEntry? entry) {
            worker_prefix = entry;
        }

        public Models.PrefixRegistry require_registry () throws Error {
            if (live_registry == null) {
                throw new LumoriaError.FAILED (_("Prefix registry is not available"));
            }
            return live_registry;
        }

        public void persist_registry () throws Error {
            if (registry_persist_handler == null) {
                throw new LumoriaError.FAILED (_("Prefix registry persist is not available"));
            }
            registry_persist_handler ();
        }

        public Models.PrefixEntry? prefix_for_wine_path (string pfx_path) throws Error {
            if (worker_prefix != null) {
                if (PrefixPaths.from_entry (worker_prefix).wine_prefix == pfx_path) {
                    return worker_prefix;
                }
            }
            foreach (var p in require_registry ().prefixes) {
                if (PrefixPaths.from_root (p.path).wine_prefix == pfx_path
                    || PrefixPaths.from_entry (p).wine_prefix == pfx_path) {
                    return p;
                }
            }
            return null;
        }

        public void persist_prefix (Models.PrefixEntry entry) throws Error {
            require_live_entry (entry);
            persist_queue.mutex.lock ();
            persist_queue.pending[persist_key (entry)] = entry;
            if (persist_queue.queued) {
                persist_queue.mutex.unlock ();
                return;
            }
            persist_queue.queued = true;
            persist_idle = Idle.add (() => {
                flush_persist ();
                return false;
            });
            persist_queue.mutex.unlock ();
        }

        public void flush_persist () {
            persist_queue.mutex.lock ();
            if (persist_idle != 0) {
                Source.remove (persist_idle);
                persist_idle = 0;
            }
            var sources = new Gee.ArrayList<Models.PrefixEntry> ();
            foreach (var source in persist_queue.pending.values) {
                sources.add (source);
            }
            persist_queue.pending.clear ();
            persist_queue.queued = false;
            persist_queue.mutex.unlock ();
            flush_pending (sources);
        }

        public void flush_persist_now () {
            if (MainContext.default ().is_owner ()) {
                flush_persist ();
                return;
            }
            var gate = new OnceGate ();
            Idle.add (() => {
                flush_persist ();
                gate.mutex.lock ();
                gate.done = true;
                gate.cond.broadcast ();
                gate.mutex.unlock ();
                return false;
            });
            gate.mutex.lock ();
            while (!gate.done) {
                gate.cond.wait (gate.mutex);
            }
            gate.mutex.unlock ();
        }

        public void open_target (string target, RuntimeLog logger) {
            if (open_handler == null) {
                logger.typed (LogType.SKIP, "open skipped (no handler): %s".printf (target));
                return;
            }
            Idle.add (() => {
                if (open_handler != null) open_handler (target);
                return false;
            });
        }

        private void flush_pending (Gee.ArrayList<Models.PrefixEntry> sources) {
            var failed = new StringBuilder ();
            foreach (var source in sources) {
                try {
                    apply_prefix_state (source);
                } catch (Error e) {
                    warning ("Failed to apply prefix %s: %s", source.id, e.message);
                    if (failed.len > 0) failed.append ("\n");
                    failed.append (user_error (e));
                }
            }
            if (sources.size > 0) {
                try {
                    persist_registry ();
                } catch (Error e) {
                    warning ("Failed to persist prefix registry: %s", e.message);
                    if (failed.len > 0) failed.append ("\n");
                    failed.append (user_error (e));
                }
            }
            if (failed.len > 0) persist_failed (failed.str);
        }

        private void apply_prefix_state (Models.PrefixEntry source) throws Error {
            var live = require_live_entry (source);
            if (live != source) live.apply_runtime_state (source);
        }

        private Models.PrefixEntry require_live_entry (Models.PrefixEntry hint) throws Error {
            var live = require_registry ().find (hint);
            if (live == null) {
                throw new LumoriaError.NOT_FOUND (_("Prefix not found in registry: %s").printf (persist_key (hint)));
            }
            return live;
        }

        private static string persist_key (Models.PrefixEntry entry) {
            return entry.id != "" ? entry.id : entry.resolved_path ();
        }

        private class PersistQueue : Object {
            public Mutex mutex = Mutex ();
            public bool queued = false;
            public Gee.HashMap<string, Models.PrefixEntry> pending =
                new Gee.HashMap<string, Models.PrefixEntry> ();
        }

        private class OnceGate {
            public Mutex mutex = Mutex ();
            public Cond cond = Cond ();
            public bool done = false;
        }
    }

    private Session? active_session;

    public void attach_session (Session session) {
        active_session = session;
    }

    internal Session? peek_session () {
        return active_session;
    }

    internal Session current_session () throws Error {
        if (active_session == null) {
            throw new LumoriaError.FAILED (_("Runtime session is not available"));
        }
        return active_session;
    }

    internal void persist_prefix (Models.PrefixEntry entry) throws Error {
        current_session ().persist_prefix (entry);
    }

    internal void persist_prefix_now (Models.PrefixEntry entry) throws Error {
        var session = current_session ();
        session.persist_prefix (entry);
        session.flush_persist_now ();
    }
}
