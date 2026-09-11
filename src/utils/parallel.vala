namespace Lumoria.Utils {

    private const int WORKER_NICE = 10;

    public static bool move_item<T> (Gee.ArrayList<T> list, int idx, int dest) {
        if (idx < 0 || idx >= list.size) return false;
        int n = list.size;
        if (dest < 0) dest = 0;
        if (dest > n) dest = n;
        if (dest == idx || dest == idx + 1) return false;
        var item = list[idx];
        list.remove_at (idx);
        if (dest > idx) dest--;
        list.insert (dest, item);
        return true;
    }

    public static int parallel_workers () {
        var override = Environment.get_variable ("LUMORIA_JOBS");
        if (override != null) {
            int jobs;
            if (int.try_parse (override, out jobs) && jobs > 0) return jobs;
        }
        return int.max (1, (int) get_num_processors () - 1);
    }

    public delegate void Action ();
    public delegate void FallibleAction () throws Error;

    /*
     * Coalesces bursts of schedule () calls into one main-loop callback; 0 ms means next idle.
     * The action keeps a strong reference to whatever it captures, so an owner that stores its
     * Debouncer must call release () when it goes away to break the cycle.
     */
    public class Debouncer : Object {
        private Action? action;
        private uint delay_ms;
        private uint source = 0;

        public Debouncer (uint delay_ms, owned Action action) {
            this.delay_ms = delay_ms;
            this.action = (owned) action;
        }

        public bool pending { get { return source != 0; } }

        public void schedule () {
            schedule_in (delay_ms);
        }

        public void schedule_in (uint ms) {
            cancel ();
            source = ms == 0 ? Idle.add (fire) : Timeout.add (ms, fire);
        }

        public void flush () {
            cancel ();
            if (action != null) action ();
        }

        public void cancel () {
            if (source == 0) return;
            Source.remove (source);
            source = 0;
        }

        public void release () {
            cancel ();
            action = null;
        }

        private bool fire () {
            source = 0;
            if (action != null) action ();
            return false;
        }
    }

    public abstract class Worker<J> : Object {
        public abstract void run (J job) throws Error;
    }

    public delegate Worker<J> WorkerFactory<J> ();
    public delegate void BackgroundDone (Error? error);

    public class BackgroundJobs : Object {
        private static BackgroundJobs? _instance;
        public static BackgroundJobs instance () {
            if (_instance == null) _instance = new BackgroundJobs ();
            return _instance;
        }

        public Cancellable cancellable { get; default = new Cancellable (); }
        private Mutex mutex = Mutex ();
        private int inflight = 0;

        public bool shutting_down {
            get { return cancellable.is_cancelled (); }
        }

        public void begin () {
            mutex.lock ();
            inflight++;
            mutex.unlock ();
        }

        public void end () {
            mutex.lock ();
            inflight--;
            mutex.unlock ();
        }

        public void shutdown (int timeout_ms = 5000) {
            cancellable.cancel ();
            var deadline = GLib.get_monotonic_time () + (int64) timeout_ms * 1000;
            while (true) {
                mutex.lock ();
                var n = inflight;
                mutex.unlock ();
                if (n <= 0) return;
                if (GLib.get_monotonic_time () >= deadline) {
                    warning ("Background jobs still running after shutdown timeout (%d)", n);
                    return;
                }
                Thread.usleep (10000);
            }
        }
    }

    public static void run_background (
        string name,
        owned FallibleAction work,
        owned BackgroundDone? on_done = null
    ) {
        var jobs = BackgroundJobs.instance ();
        if (jobs.shutting_down) {
            Idle.add (() => {
                if (on_done != null) on_done (new IOError.CANCELLED ("Application is shutting down"));
                return false;
            });
            return;
        }
        jobs.begin ();
        new Thread<bool> (name, () => {
            Error? error = null;
            try {
                jobs.cancellable.set_error_if_cancelled ();
                work ();
            } catch (Error e) {
                error = e;
            }
            jobs.end ();
            var captured = error;
            Idle.add (() => {
                if (on_done != null) on_done (captured);
                return false;
            });
            return true;
        });
    }

    private class ParallelState : Object {
        private Mutex mutex = Mutex ();
        private Error? error = null;
        private Cancellable? cancellable;

        public ParallelState (Cancellable? cancellable) {
            this.cancellable = cancellable;
        }

        public bool should_stop () {
            if (cancellable != null && cancellable.is_cancelled ()) return true;
            mutex.lock ();
            var failed = error != null;
            mutex.unlock ();
            return failed;
        }

        public void fail (Error e) {
            mutex.lock ();
            if (error == null) error = e;
            mutex.unlock ();
        }

        public void rethrow () throws Error {
            if (error != null) throw error;
            if (cancellable != null) cancellable.set_error_if_cancelled ();
        }
    }

    public static void run_parallel<J> (
        Gee.Collection<J> jobs,
        owned WorkerFactory<J> factory,
        Cancellable? cancellable = null
    ) throws Error {
        if (jobs.size == 0) return;

        var queue = new AsyncQueue<J> ();
        foreach (var job in jobs) queue.push (job);

        var state = new ParallelState (cancellable);
        var count = int.min (jobs.size, parallel_workers ());
        var threads = new Thread<void*>[count];
        for (int i = 0; i < count; i++) {
            threads[i] = new Thread<void*> ("lumoria-worker", () => {
                Posix.setpriority (Posix.PRIO_PROCESS, 0, WORKER_NICE);
                try {
                    var worker = factory ();
                    while (!state.should_stop ()) {
                        J? job = queue.try_pop ();
                        if (job == null) break;
                        worker.run (job);
                    }
                } catch (Error e) {
                    state.fail (e);
                }
                return null;
            });
        }
        foreach (var thread in threads) thread.join ();
        state.rethrow ();
    }
}
