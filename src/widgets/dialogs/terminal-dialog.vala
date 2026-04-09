namespace Lumoria.Widgets.Dialogs {

    public class TerminalDialog : Adw.Dialog {
        private Vte.Terminal terminal;
        private Gtk.Button copy_btn;
        private Gtk.Button paste_btn;

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
            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = true;

            copy_btn = new Gtk.Button.from_icon_name (IconRegistry.COPY);
            copy_btn.tooltip_text = _("Copy Terminal Output");
            copy_btn.clicked.connect (copy_terminal_buffer);

            paste_btn = new Gtk.Button.from_icon_name (IconRegistry.PASTE);
            paste_btn.tooltip_text = _("Paste");
            paste_btn.clicked.connect (paste_terminal_clipboard);

            var clipboard_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            clipboard_actions.add_css_class ("linked");
            clipboard_actions.append (copy_btn);
            clipboard_actions.append (paste_btn);
            header.pack_end (clipboard_actions);

            toolbar.add_top_bar (header);

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
            toolbar.content = scroll;

            map.connect (() => {
                terminal.grab_focus ();
            });

            this.child = toolbar;
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

            var envv = new string[merged.size];
            int i = 0;
            foreach (var entry in merged.entries) {
                envv[i++] = "%s=%s".printf (entry.key, entry.value);
            }

            string[] argv = { "bash", "-l" };
            string? work_dir = working_directory != "" ? working_directory : null;

            terminal.spawn_async (
                Vte.PtyFlags.DEFAULT,
                work_dir,
                argv,
                envv,
                SpawnFlags.SEARCH_PATH,
                null,
                -1,
                null,
                (terminal, pid, error) => {
                    if (error != null) {
                        warning ("Terminal spawn failed: %s", error.message);
                    }
                }
            );
        }

        private void install_shortcuts () {
            var shortcuts = new Gtk.ShortcutController ();
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<Primary><Shift>c"),
                new Gtk.CallbackAction ((widget, args) => {
                    copy_terminal_selection ();
                    return true;
                })
            ));
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<Primary><Shift>v"),
                new Gtk.CallbackAction ((widget, args) => {
                    paste_terminal_clipboard ();
                    return true;
                })
            ));
            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("Shift+Insert"),
                new Gtk.CallbackAction ((widget, args) => {
                    paste_terminal_clipboard ();
                    return true;
                })
            ));
            terminal.add_controller (shortcuts);
        }

        private void copy_terminal_selection () {
            if (!terminal.get_has_selection ()) return;

            terminal.copy_clipboard_format (Vte.Format.TEXT);
            pulse_copy_button (_("Copied selection!"));
        }

        private void copy_terminal_buffer () {
            var text = terminal.get_text_format (Vte.Format.TEXT);
            if (text == null) return;

            var trimmed = trim_trailing_blank_lines (text);
            if (trimmed.strip () == "") return;

            var clipboard = get_clipboard ();
            clipboard.set_text (trimmed);
            pulse_copy_button (_("Copied terminal output!"));
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
            Timeout.add (2000, () => {
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
