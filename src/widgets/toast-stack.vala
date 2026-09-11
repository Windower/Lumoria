namespace Lumoria.Widgets {

    public interface ToastHost : Object {
        public abstract void push_toast (string message);
    }

    /* A root that tracks presented dialogs so gamepad navigation and toasts know what is on top. */
    public interface DialogHost : Object {
        public abstract void show_dialog (Adw.Dialog dialog);
    }

    public class ToastStack : Gtk.Box {
        private const int MAX_VISIBLE = 4;
        private const int HIDE_MS = 320;
        private Gee.LinkedList<Adw.Toast> live = new Gee.LinkedList<Adw.Toast> ();
        private Gee.HashMap<Adw.Toast, Adw.ToastOverlay> slots = new Gee.HashMap<Adw.Toast, Adw.ToastOverlay> ();
        private Gee.ArrayList<uint> hide_timeouts = new Gee.ArrayList<uint> ();
        private bool disposed = false;

        public ToastStack () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            hexpand = false;
            vexpand = false;
            halign = Gtk.Align.CENTER;
            valign = Gtk.Align.END;
            destroy.connect (on_destroy);
        }

        public static Gtk.Overlay attach (Gtk.Widget child, out ToastStack stack) {
            var overlay = new Gtk.Overlay () {
                child = child,
                hexpand = true,
                vexpand = true
            };
            stack = new ToastStack ();
            overlay.add_overlay (stack);
            overlay.set_measure_overlay (stack, true);
            return overlay;
        }

        public void push (string message) {
            if (live.size >= MAX_VISIBLE) live.peek_head ().dismiss ();
            var toast = new Adw.Toast (message);
            var slot = new Adw.ToastOverlay ();
            slot.child = new Adw.Bin ();
            live.add (toast);
            slots[toast] = slot;
            toast.dismissed.connect (on_toast_dismissed);
            append (slot);
            slot.add_toast (toast);
        }

        private void on_toast_dismissed (Adw.Toast toast) {
            live.remove (toast);
            Adw.ToastOverlay slot;
            if (!slots.unset (toast, out slot)) return;
            uint id = 0;
            id = Timeout.add (HIDE_MS, () => {
                hide_timeouts.remove (id);
                if (!disposed && slot.parent == this) remove (slot);
                return false;
            });
            hide_timeouts.add (id);
        }

        private void on_destroy () {
            disposed = true;
            foreach (var id in hide_timeouts) Source.remove (id);
            hide_timeouts.clear ();
        }
    }
}
