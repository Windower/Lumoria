namespace Lumoria.Widgets {

    public class FavoriteButton : Gtk.Button {
        private Lumoria.Application.Context ctx;
        private string prefix_id;
        private string action_id;

        public FavoriteButton (Lumoria.Application.Context ctx, Models.PrefixEntry entry, string action_id) {
            this.ctx = ctx;
            prefix_id = entry.id;
            this.action_id = action_id;
            valign = Gtk.Align.CENTER;
            PageChrome.style_icon_button (this);
            sync ();
            clicked.connect (toggle);
            ctx.state.changed.connect (sync);
        }

        private bool favorited () {
            return ctx.state.favorite (prefix_id, action_id) != null;
        }

        private void toggle () {
            ctx.state.toggle_favorite (prefix_id, action_id);
            ctx.show_toast (favorited () ? _("Added to Favorites") : _("Removed from Favorites"));
        }

        private void sync () {
            var active = favorited ();
            icon_name = IconRegistry.bookmark_icon_name (active);
            PageChrome.set_icon_label (this, active ? _("Remove from Favorites") : _("Add to Favorites"));
            if (active) add_css_class ("shortcut-active");
            else remove_css_class ("shortcut-active");
        }
    }

    public class ShortcutToggles : Gtk.Box {
        public Gtk.Button menu { get; private set; }
        public Gtk.Button steam { get; private set; }

        private Lumoria.Application.Context? ctx;
        private Models.PrefixEntry? entry;
        private Runtime.LaunchTarget? target;

        public ShortcutToggles () {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 4);
            menu = new Gtk.Button.from_icon_name (IconRegistry.APP_GRID);
            style_toggle (menu);
            steam = new Gtk.Button ();
            steam.child = new Gtk.Image.from_resource (Config.RESOURCE_BASE + "/images/steam.svg");
            style_toggle (steam);
            sync (false, false);
            append (menu);
            append (steam);
        }

        public ShortcutToggles.for_target (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget target
        ) {
            this ();
            this.ctx = ctx;
            this.entry = entry;
            this.target = target;
            sync_target ();
            menu.clicked.connect (toggle_menu);
            steam.clicked.connect (toggle_steam);
        }

        public void sync (bool menu_active, bool steam_active) {
            if (menu_active) menu.add_css_class ("shortcut-active");
            else menu.remove_css_class ("shortcut-active");
            PageChrome.set_icon_label (menu, menu_active
                ? _("Remove from App Launcher")
                : _("Add to App Launcher"));
            if (steam_active) steam.add_css_class ("shortcut-active");
            else steam.remove_css_class ("shortcut-active");
            PageChrome.set_icon_label (steam, steam_active
                ? _("Remove from Steam")
                : _("Add to Steam"));
        }

        private static void style_toggle (Gtk.Button button) {
            button.valign = Gtk.Align.CENTER;
            button.add_css_class ("flat");
            button.add_css_class ("shortcut-toggle");
        }

        private void sync_target () {
            sync (entry.has_menu_shortcut (target.id), entry.has_steam_shortcut (target.id));
        }

        private void toggle_menu () {
            ctx.shortcuts.toggle_menu (entry, target, sync_target);
        }

        private void toggle_steam () {
            ctx.shortcuts.toggle_steam (entry, target, sync_target);
        }
    }

    public class LaunchDisplayRow : Adw.ActionRow {
        private Lumoria.Application.Context ctx;
        private Models.PrefixEntry entry;
        private Runtime.LaunchTarget action;
        private Gee.HashMap<string, string>? vars;
        private IconKeySlot? icon;
        private FadeLabel heading;
        private FadeLabel plain;
        private FadeMarkup markup;

        public LaunchDisplayRow (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action,
            Gee.HashMap<string, string>? vars
        ) {
            this.ctx = ctx;
            this.entry = entry;
            this.action = action;
            this.vars = vars;
            add_css_class ("launch-display-row");

            var text = ActionRows.launch_text (entry, action, vars);
            icon = new IconKeySlot (entry.display_icon (action.id, action.icon), 16);
            heading = new FadeLabel.row_title (text.title);
            plain = new FadeLabel.row_subtitle (text.plain ());
            markup = new FadeMarkup (text.markup ());
            var column = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            column.add_css_class ("launch-display-text");
            column.hexpand = true;
            column.valign = Gtk.Align.CENTER;
            column.append (heading);
            column.append (plain);
            column.append (markup);
            var lead = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            lead.hexpand = true;
            lead.valign = Gtk.Align.CENTER;
            lead.append (icon);
            lead.append (column);
            add_prefix (lead);
            var prefixes = lead.get_parent ();
            if (prefixes != null) prefixes.hexpand = true;
            set_accessible (text.title, text.subtitle);
            watch_catalog (icon);
            ctx.prefixes.changed.connect (sync);
        }

        /* Fixed title and subtitle; only the icon follows edits. */
        public LaunchDisplayRow.static_text (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action,
            Gee.HashMap<string, string> vars
        ) {
            this.ctx = ctx;
            this.entry = entry;
            this.action = action;
            this.vars = vars;
            var text = ActionRows.launch_text (entry, action, vars);
            title = text.title;
            if (text.plain () != "") subtitle = text.plain ();

            var key = entry.display_icon (action.id, action.icon);
            if (!shows_icon (key)) return;
            icon = new IconKeySlot (key, 16);
            add_prefix (icon);
            watch_catalog (icon);
            ctx.prefixes.changed.connect (sync_icon);
        }

        private bool shows_icon (string key) {
            if (key == "") return false;
            if (action.kind == Models.PrefixActionKind.LAUNCH) return true;
            return action.has_button && action.button_label.strip () != "";
        }

        private static void watch_catalog (IconKeySlot slot) {
            Models.FfxiIconCatalog.instance ().changed.connect (slot.reload);
        }

        private void sync_icon () {
            icon.set_key (entry.display_icon (action.id, action.icon));
        }

        private void sync () {
            var text = ActionRows.launch_text (entry, action, vars);
            sync_icon ();
            heading.set_key (text.title);
            plain.set_key (text.plain ());
            markup.set_key (text.markup ());
            set_accessible (text.title, text.subtitle);
        }

        private void set_accessible (string title_text, string detail) {
            update_property (Gtk.AccessibleProperty.LABEL, Utils.sanitize_ui_text (title_text));
            update_property (Gtk.AccessibleProperty.DESCRIPTION, Utils.sanitize_ui_text (detail));
        }
    }

    /* An activatable row that remembers what it stands for, so handlers read the sender instead of capturing a value. */
    public class ChoiceRow : Adw.ActionRow {
        public string value { get; construct; }

        public ChoiceRow (string value, string title, string subtitle = "") {
            Object (value: value, title: title, subtitle: subtitle, activatable: true);
        }

        public void mark_current (bool current) {
            if (current) add_suffix (new Gtk.Image.from_icon_name (IconRegistry.CHECKMARK) { valign = Gtk.Align.CENTER });
        }
    }

    public class ActionRows : Object {
        public static Adw.PreferencesRow prefix_action_row (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action
        ) {
            var vars = Runtime.message_vars_for_prefix (entry, ctx.launcher_manifests);
            var run = prefix_action_button (action, vars);
            run.valign = Gtk.Align.CENTER;
            run.clicked.connect (() => {
                ctx.actions.run (entry, action.id);
            });
            var suffix = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            if (action.pinnable) {
                suffix.append (edit_button (ctx, entry, action));
                suffix.append (new FavoriteButton (ctx, entry, action.id));
            }
            suffix.append (run);

            var row = action.pinnable
                ? new LaunchDisplayRow (ctx, entry, action, vars)
                : new LaunchDisplayRow.static_text (ctx, entry, action, vars);
            row.add_suffix (suffix);
            row.activatable_widget = run;
            return row;
        }

        private static Gtk.Button prefix_action_button (
            Runtime.LaunchTarget action,
            Gee.HashMap<string, string> vars
        ) {
            if (action.has_button) return manifest_action_button (action, vars);
            if (action.kind == Models.PrefixActionKind.LAUNCH) {
                var play = new Gtk.Button.from_icon_name (IconRegistry.PAGE_LAUNCH);
                PageChrome.set_icon_label (play, _("Play %s").printf (action.label));
                PageChrome.style_play_button (play, true);
                return play;
            }
            var icon_name = action.icon != ""
                ? IconRegistry.resolve_action_icon (action.icon)
                : IconRegistry.TOOLS;
            var button = new Gtk.Button.from_icon_name (icon_name);
            if (action.label != "") PageChrome.set_icon_label (button, action.label);
            PageChrome.style_action_icon_button (button);
            return button;
        }

        private static Gtk.Button manifest_action_button (
            Runtime.LaunchTarget action,
            Gee.HashMap<string, string> vars
        ) {
            var label = Utils.expand_vars (action.button_label, vars).strip ();
            var icon = action.button_icon.strip ();
            Gtk.Button button;
            if (label != "") {
                if (icon != "") {
                    button = new Gtk.Button ();
                    var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                    var image = new Gtk.Image.from_icon_name (IconRegistry.resolve_action_icon (icon));
                    image.valign = Gtk.Align.CENTER;
                    box.append (image);
                    box.append (new Gtk.Label (label));
                    button.child = box;
                } else {
                    button = new Gtk.Button.with_label (label);
                }
                button.tooltip_text = label;
                PageChrome.apply_button_style (button, action.button_style);
            } else {
                var icon_name = icon != ""
                    ? IconRegistry.resolve_action_icon (icon)
                    : IconRegistry.TOOLS;
                button = new Gtk.Button.from_icon_name (icon_name);
                if (action.label != "") PageChrome.set_icon_label (button, action.label);
                PageChrome.style_action_icon_button (button, action.button_style);
            }
            return button;
        }

        public static Adw.ActionRow prelaunch_row (
            string path,
            out Gtk.Button browse,
            out Gtk.Button clear
        ) {
            var row = new Adw.ActionRow ();
            row.title = _("Prelaunch Script");
            set_prelaunch_path (row, path);
            browse = PageChrome.browse_button ();
            browse.sensitive = !Utils.EnvironmentInfo.is_gamescope ();
            row.add_suffix (browse);
            clear = PageChrome.icon_button (IconRegistry.CLOSE, _("Clear"));
            clear.add_css_class ("flat");
            row.add_suffix (clear);
            return row;
        }

        public static void set_prelaunch_path (Adw.ActionRow row, string path) {
            row.subtitle = path != "" ? path : _("None");
        }

        public static Gtk.Widget prelaunch_gamescope_note () {
            return Messages.warning (
                _("Prelaunch scripts are skipped in gamescope sessions. They still run when launching from desktop mode."),
                Ui.Metrics.EDITOR_INSET,
                Ui.Metrics.EDITOR_INSET,
                Ui.Metrics.PAGE_MARGIN,
                Ui.Metrics.PAGE_MARGIN
            );
        }

        public static string dll_overrides_hint () {
            return _("Wine loads the first available mode for each DLL.");
        }

        public struct LaunchText {
            public string title;
            public string subtitle;
            public bool markdown;

            /* Subtitle text meant for a plain label; empty when the subtitle is markdown. */
            public string plain () {
                return markdown ? "" : subtitle;
            }

            public string markup () {
                return markdown ? subtitle : "";
            }
        }

        public static LaunchText launch_text (
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action,
            Gee.HashMap<string, string>? vars
        ) {
            var text = LaunchText () { title = action.label, subtitle = "", markdown = false };
            if (Models.PrefixEntry.is_custom_entry_id (action.id)) {
                var ep = entry.custom_entrypoint (action.id);
                if (ep != null) text.title = ep.title ();
                return text;
            }
            var nickname = entry.display_nickname (action.id);
            if (nickname != "") {
                text.title = nickname;
                text.subtitle = action.label;
                return text;
            }
            if (vars != null && action.description != "") {
                text.subtitle = Utils.expand_vars (action.description, vars);
                text.markdown = true;
            }
            return text;
        }

        public static void edit_launch (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action
        ) {
            ctx.show_dialog (new Dialogs.LaunchEditDialog (ctx, entry, action));
        }

        public static Gtk.Button edit_button (
            Lumoria.Application.Context ctx,
            Models.PrefixEntry entry,
            Runtime.LaunchTarget action
        ) {
            var pencil = PageChrome.icon_button (IconRegistry.EDIT, _("Edit"));
            pencil.clicked.connect (() => edit_launch (ctx, entry, action));
            return pencil;
        }
    }
}
