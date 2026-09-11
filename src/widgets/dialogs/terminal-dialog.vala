namespace Lumoria.Widgets.Dialogs {

    public class TerminalDialog : DialogHelpers.GamepadDialog {
        public signal void failed (string message);

        private Vte.Terminal terminal;
        private Gtk.Button copy_btn;
        private Gtk.Button paste_btn;
        private uint copy_pulse_id = 0;

        public TerminalDialog (
            string working_directory,
            Gee.HashMap<string, string> env_vars
        ) {
            Object (
                title: _("Prefix Shell"),
                content_width: 720,
                content_height: 480
            );
            build_ui ();
            spawn_shell (working_directory, env_vars);
        }

        private void build_ui () {
            var header = DialogHelpers.dialog_header ();

            copy_btn = new Gtk.Button.from_icon_name (IconRegistry.COPY);
            PageChrome.set_icon_label (copy_btn, _("Copy Terminal Output"));
            copy_btn.clicked.connect (copy_terminal_buffer);

            paste_btn = new Gtk.Button.from_icon_name (IconRegistry.PASTE);
            PageChrome.set_icon_label (paste_btn, _("Paste"));
            paste_btn.clicked.connect (paste_terminal_clipboard);

            var clipboard_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            clipboard_actions.add_css_class ("linked");
            clipboard_actions.append (copy_btn);
            clipboard_actions.append (paste_btn);
            header.pack_end (clipboard_actions);

            terminal = new Vte.Terminal ();
            terminal.hexpand = true;
            terminal.vexpand = true;
            terminal.set_scroll_on_output (true);
            terminal.set_scrollback_lines (4096);

            var font = Pango.FontDescription.from_string ("Monospace 11");
            terminal.set_font (font);

            apply_colors ();
            install_shortcuts ();

            terminal.child_exited.connect (() => {
                close ();
            });

            var scroll = new Gtk.ScrolledWindow ();
            scroll.child = terminal;
            scroll.hexpand = true;
            scroll.vexpand = true;
            map.connect (() => {
                terminal.grab_focus ();
            });

            set_body (DialogHelpers.dialog_toolbar (header, scroll));
            closed.connect (() => {
                if (copy_pulse_id != 0) Source.remove (copy_pulse_id);
                copy_pulse_id = 0;
            });
        }

        private void apply_colors () {
            var fg = Gdk.RGBA ();
            fg.parse ("#d0d0d0");
            var bg = Gdk.RGBA ();
            bg.parse ("#1e1e1e");
            terminal.set_color_foreground (fg);
            terminal.set_color_background (bg);
        }

        private void spawn_shell (
            string working_directory,
            Gee.HashMap<string, string> env_vars
        ) {
            var merged = new Gee.HashMap<string, string> ();
            foreach (var key in Environment.list_variables ()) {
                var val = Environment.get_variable (key);
                if (val != null) merged[key] = val;
            }
            foreach (var entry in env_vars.entries) {
                merged[entry.key] = entry.value;
            }
            merged["TERM"] = "xterm-256color";

            var envv = new Gee.ArrayList<string> ();
            foreach (var entry in merged.entries) envv.add ("%s=%s".printf (entry.key, entry.value));

            string[] argv = { "bash", "-l" };
            string? work_dir = working_directory != "" ? working_directory : null;

            terminal.spawn_async (
                Vte.PtyFlags.DEFAULT,
                work_dir,
                argv,
                Utils.strv (envv),
                SpawnFlags.SEARCH_PATH,
                null,
                -1,
                null,
                (terminal, pid, error) => {
                    if (error == null) return;
                    warning ("Terminal spawn failed: %s", error.message);
                    failed (_("Could not start the shell: %s").printf (user_error (error)));
                    close ();
                }
            );
        }

        private void install_shortcuts () {
            var keys = new Gtk.EventControllerKey ();
            keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            keys.key_pressed.connect (on_key_pressed);
            terminal.add_controller (keys);
        }

        private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
            var mods = state & Gtk.accelerator_get_default_mod_mask ();
            var primary_shift = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK;
            switch (Gdk.keyval_to_lower (keyval)) {
            case Gdk.Key.c:
                if (mods != primary_shift) return false;
                copy_terminal_selection ();
                return true;
            case Gdk.Key.v:
                if (mods != primary_shift) return false;
                paste_terminal_clipboard ();
                return true;
            case Gdk.Key.Insert:
                if (mods != Gdk.ModifierType.SHIFT_MASK) return false;
                paste_terminal_clipboard ();
                return true;
            default:
                return false;
            }
        }

        private void copy_terminal_selection () {
            if (!terminal.get_has_selection ()) return;

            terminal.copy_clipboard_format (Vte.Format.TEXT);
            pulse_copy_button (_("Copied selection!"));
        }

        private void copy_terminal_buffer () {
            var text = read_terminal_buffer ();
            if (text == null) return;

            var trimmed = trim_trailing_blank_lines (text);
            if (trimmed.strip () == "") return;

            var clipboard = get_clipboard ();
            clipboard.set_text (trimmed);
            pulse_copy_button (_("Copied terminal output!"));
        }

        private string? read_terminal_buffer () {
            var stream = new MemoryOutputStream.resizable ();
            try {
                terminal.write_contents_sync (stream, Vte.WriteFlags.DEFAULT);
                stream.close ();
            } catch (Error e) {
                warning ("Terminal copy failed: %s", e.message);
                failed (_("Could not copy the terminal output: %s").printf (user_error (e)));
                return null;
            }

            var size = stream.get_data_size ();
            if (size == 0) return "";

            void* data = stream.get_data ();
            return ((string) data).substring (0, (long) size);
        }

        private string trim_trailing_blank_lines (string text) {
            try {
                var regex = new Regex ("(?:\\r?\\n[ \\t]*)+$");
                return regex.replace (text, text.length, 0, "");
            } catch (RegexError e) {
                warning ("Terminal copy trim failed: %s", e.message);
                return text;
            }
        }

        private void pulse_copy_button (string tooltip_text) {
            copy_btn.icon_name = IconRegistry.CHECKMARK;
            copy_btn.tooltip_text = tooltip_text;
            if (copy_pulse_id != 0) Source.remove (copy_pulse_id);
            copy_pulse_id = Timeout.add (2000, () => {
                copy_pulse_id = 0;
                copy_btn.icon_name = IconRegistry.COPY;
                copy_btn.tooltip_text = _("Copy Terminal Output");
                return false;
            });
        }

        private void paste_terminal_clipboard () {
            terminal.paste_clipboard ();
            terminal.grab_focus ();
        }
    }
}
