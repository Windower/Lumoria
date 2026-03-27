namespace Lumoria.Widgets.Dialogs {

    public class TerminalDialog : Adw.Dialog {
        private Vte.Terminal terminal;

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
            toolbar.add_top_bar (header);

            terminal = new Vte.Terminal ();
            terminal.hexpand = true;
            terminal.vexpand = true;
            terminal.set_scroll_on_output (true);
            terminal.set_scrollback_lines (4096);

            var font = Pango.FontDescription.from_string ("Monospace 11");
            terminal.set_font (font);

            apply_colors ();

            terminal.child_exited.connect (() => {
                close ();
            });

            var scroll = new Gtk.ScrolledWindow ();
            scroll.child = terminal;
            scroll.hexpand = true;
            scroll.vexpand = true;
            toolbar.content = scroll;

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
    }
}
