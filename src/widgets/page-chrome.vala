namespace Lumoria.Widgets {

    public enum ToggleOverrideState {
        INHERIT,
        ENABLED,
        DISABLED;

        public static ToggleOverrideState from_nullable_bool (bool? value) {
            if (value == null) return INHERIT;
            return (bool) value ? ENABLED : DISABLED;
        }

        public bool? to_nullable_bool () {
            switch (this) {
                case ENABLED:
                    return true;
                case DISABLED:
                    return false;
                default:
                    return null;
            }
        }
    }

    public class PageChrome : Object {
        public const string PAGE_GENERAL = "general";
        public const string PAGE_RUNTIME = "runtime";
        public const string PAGE_SHORTCUTS = "shortcuts";
        public const string PAGE_PACKAGES = "packages";
        public const string PAGE_ADVANCED = "advanced";
        public const string PAGE_SCRIPTS = "scripts";

        public static Adw.WindowTitle page_title (string title) {
            return new Adw.WindowTitle (title, "");
        }

        public static void pack_header (Adw.HeaderBar header) {
            header.show_back_button = false;

            var sidebar_btn = new Gtk.ToggleButton ();
            sidebar_btn.icon_name = IconRegistry.SIDEBAR;
            sidebar_btn.action_name = "win.show-sidebar";
            sidebar_btn.add_css_class ("circular");
            set_icon_label (sidebar_btn, _("Hide Sidebar"));
            sidebar_btn.notify["active"].connect ((btn, p) => {
                var toggle = (Gtk.ToggleButton) btn;
                set_icon_label (toggle, toggle.active ? _("Hide Sidebar") : _("Show Sidebar"));
            });
            header.pack_start (sidebar_btn);

            var home_btn = new Gtk.ToggleButton ();
            home_btn.icon_name = IconRegistry.HOME;
            home_btn.action_name = "win.show-home";
            home_btn.add_css_class ("circular");
            set_icon_label (home_btn, _("Home"));
            header.pack_start (home_btn);

            var close_btn = icon_button (IconRegistry.CLOSE, _("Quit"));
            close_btn.action_name = "win.quit";
            header.pack_end (close_btn);

            var session_btn = icon_button (IconRegistry.SESSIONS, _("Session Manager"));
            session_btn.action_name = "win.session-manager";
            Utils.Preferences.instance ().bind_property (
                "session-manager", session_btn, "visible", BindingFlags.SYNC_CREATE
            );
            header.pack_end (session_btn);
        }

        public static Adw.ToolbarView page (string title, Gtk.Widget child) {
            return page_with_heading (page_title (title != "" ? title : Config.APP_NAME), child);
        }

        public static Adw.ToolbarView page_with_heading (Adw.WindowTitle heading, Gtk.Widget child) {
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = false;
            header.title_widget = heading;
            pack_header (header);
            var toolbar = new Adw.ToolbarView ();
            toolbar.add_top_bar (header);
            toolbar.content = child;
            return toolbar;
        }

        public static Adw.ToolbarView page_with_stack (
            Adw.ViewStack stack,
            Adw.WindowTitle heading,
            Gtk.Widget? above = null,
            Gtk.Widget? below = null
        ) {
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = false;
            header.title_widget = heading;
            pack_header (header);
            var toolbar = new Adw.ToolbarView ();
            toolbar.add_top_bar (header);
            if (above != null) toolbar.add_top_bar (above);
            toolbar.add_top_bar (page_switcher (stack));
            toolbar.content = stack;
            if (below != null) toolbar.add_bottom_bar (below);
            return toolbar;
        }

        public static Adw.ViewStack settings_stack () {
            var stack = new Adw.ViewStack ();
            stack.vexpand = true;
            stack.enable_transitions = true;
            stack.transition_duration = 250;
            return stack;
        }

        public static Adw.ViewStackPage add_settings_page (
            Adw.ViewStack stack,
            Gtk.Widget child,
            string page_id,
            string title
        ) {
            return stack.add_titled_with_icon (
                child,
                page_id,
                title,
                IconRegistry.settings_page_icon (page_id)
            );
        }

        public static Adw.ViewStackPage add_scrolled_settings_page (
            Adw.ViewStack stack,
            Gtk.Widget page_widget,
            string page_id,
            string title
        ) {
            page_widget.margin_bottom = Ui.Metrics.PAGE_BOTTOM;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.child = page_widget;
            scroll.vexpand = true;
            return add_settings_page (stack, scroll, page_id, title);
        }

        public static Gtk.Widget page_switcher (Adw.ViewStack stack) {
            var switcher = new Adw.ViewSwitcher ();
            switcher.stack = stack;
            switcher.policy = Adw.ViewSwitcherPolicy.NARROW;
            switcher.hexpand = true;
            switcher.valign = Gtk.Align.CENTER;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.add_css_class ("page-switcher-scroll");
            scroll.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroll.vscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.overlay_scrolling = true;
            scroll.propagate_natural_height = true;
            scroll.propagate_natural_width = false;
            scroll.min_content_width = 0;
            scroll.min_content_height = 0;
            scroll.hexpand = true;
            scroll.child = switcher;
            return scroll;
        }

        public static Gtk.Widget scrolled (Gtk.Widget child) {
            child.margin_bottom = Ui.Metrics.PAGE_BOTTOM;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.child = child;
            scroll.vexpand = true;
            return scroll;
        }

        public static void clear_children (Gtk.Widget host) {
            Gtk.Widget? child;
            while ((child = host.get_first_child ()) != null) {
                child.unparent ();
            }
        }

        public static void margins (Gtk.Widget widget, int horizontal, int top, int bottom = -1) {
            widget.margin_start = horizontal;
            widget.margin_end = horizontal;
            widget.margin_top = top;
            widget.margin_bottom = bottom >= 0 ? bottom : top;
        }

        /* Manifest button styles: "suggested", "destructive", "flat"; unknown values fall back to suggested. */
        public static void apply_button_style (Gtk.Button button, string style, string fallback = "suggested") {
            var resolved = style.strip ();
            switch (resolved == "" ? fallback : resolved) {
                case "destructive":
                    button.add_css_class ("destructive-action");
                    break;
                case "flat":
                    button.add_css_class ("flat");
                    break;
                case "":
                    break;
                default:
                    button.add_css_class ("suggested-action");
                    break;
            }
        }

        public static void style_play_button (Gtk.Button button, bool compact = false) {
            button.add_css_class ("suggested-action");
            button.add_css_class ("circular");
            button.add_css_class (compact ? "launch-entry-play-btn" : "play-btn");
        }

        public static void style_icon_button (Gtk.Button button) {
            button.add_css_class ("flat");
            button.add_css_class ("circular");
        }

        public static void style_action_icon_button (Gtk.Button button, string style = "") {
            var resolved = style.strip ();
            if (resolved == "flat") {
                style_icon_button (button);
                return;
            }
            apply_button_style (button, resolved);
            button.add_css_class ("circular");
            button.add_css_class ("launch-entry-play-btn");
        }

        public static void set_icon_label (Gtk.Widget widget, string label) {
            widget.tooltip_text = label;
            widget.update_property (Gtk.AccessibleProperty.LABEL, label);
        }

        public static Gtk.Button icon_button (string icon, string tooltip = "") {
            var button = new Gtk.Button.from_icon_name (icon);
            button.valign = Gtk.Align.CENTER;
            if (tooltip != "") set_icon_label (button, tooltip);
            style_icon_button (button);
            return button;
        }

        public static Gtk.Button browse_button () {
            var button = new Gtk.Button.with_label (_("Browse..."));
            button.valign = Gtk.Align.CENTER;
            return button;
        }

        public static Adw.PreferencesGroup build_group (
            string title,
            int horizontal_margin = Ui.Metrics.PAGE_MARGIN,
            int margin_top = Ui.Metrics.GROUP_SPACING,
            int margin_bottom = 0
        ) {
            var group = new Adw.PreferencesGroup ();
            group.title = title;
            margins (group, horizontal_margin, margin_top, margin_bottom);
            return group;
        }

        public static Adw.InlineViewSwitcher inline_tab_switcher (Adw.ViewStack stack) {
            var switcher = new Adw.InlineViewSwitcher ();
            switcher.stack = stack;
            switcher.display_mode = Adw.InlineViewSwitcherDisplayMode.LABELS;
            switcher.homogeneous = true;
            switcher.halign = Gtk.Align.CENTER;
            switcher.hexpand = true;
            switcher.margin_top = Ui.Metrics.GROUP_SPACING;
            switcher.margin_start = Ui.Metrics.PAGE_MARGIN;
            switcher.margin_end = Ui.Metrics.PAGE_MARGIN;
            return switcher;
        }

        public static bool cycle_stack (Adw.ViewStack stack, int delta) {
            var pages = stack.get_pages ();
            int n = (int) pages.get_n_items ();
            if (n <= 1) return false;
            int idx = 0;
            for (int i = 0; i < n; i++) {
                var page = pages.get_item (i) as Adw.ViewStackPage;
                if (page != null && page.name == stack.visible_child_name) idx = i;
            }
            var page = pages.get_item ((idx + delta + n) % n) as Adw.ViewStackPage;
            if (page != null) stack.visible_child_name = page.name;
            return true;
        }

        public static Adw.PreferencesGroup untitled_group () {
            var group = build_group ("");
            group.margin_top = 0;
            return group;
        }

        public static Adw.ActionRow placeholder_row (string title) {
            var row = new Adw.ActionRow ();
            row.title = title;
            row.activatable = false;
            return row;
        }

        public static Adw.ActionRow loading_row (string title) {
            var row = placeholder_row (title);
            var spinner = new Gtk.Spinner ();
            spinner.spinning = true;
            spinner.valign = Gtk.Align.CENTER;
            row.add_suffix (spinner);
            return row;
        }

        public static Adw.PreferencesGroup remote_actions_loading_group () {
            var group = untitled_group ();
            group.add (loading_row (_("Checking remote actions…")));
            return group;
        }

        /* Callers connect to activated, so the row never owns a closure that references its page. */
        public static Adw.ActionRow navigation_row (string title, string subtitle = "") {
            var row = new Adw.ActionRow ();
            row.title = title;
            if (subtitle != "") row.subtitle = subtitle;
            row.activatable = true;
            row.add_suffix (new Gtk.Image.from_icon_name (IconRegistry.NEXT));
            return row;
        }

        public static ButtonRow action_row (
            string title,
            string button_label,
            string subtitle = "",
            string style = ""
        ) {
            return new ButtonRow (title, button_label, subtitle, style);
        }

        public static Adw.ActionRow error_row (string title, Error e) {
            var row = new Adw.ActionRow ();
            row.title = title;
            row.subtitle = user_error (e);
            row.activatable = false;
            row.add_css_class ("error");
            return row;
        }

        public static Gtk.Label validation_label () {
            var label = new Gtk.Label ("");
            label.xalign = 0f;
            label.wrap = true;
            label.add_css_class ("error");
            label.visible = false;
            return label;
        }

        public static bool show_validation (Gtk.Label label, bool ok, string error) {
            if (!ok) {
                label.label = error;
                label.visible = true;
                return false;
            }
            label.visible = false;
            return true;
        }

        public static Gtk.Widget heading_row (
            string name,
            string icon = "",
            Gtk.Widget? suffix = null,
            Gtk.Widget? after_title = null,
            bool first = false
        ) {
            var heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            heading.margin_start = Ui.Metrics.PAGE_MARGIN;
            heading.margin_end = Ui.Metrics.PAGE_MARGIN;
            heading.margin_top = first ? 0 : Ui.Metrics.GROUP_SPACING;
            heading.margin_bottom = Ui.Metrics.HEADING_GAP;
            if (icon != "") {
                var mark = IconRegistry.icon_key_image (icon, 22);
                mark.valign = Gtk.Align.CENTER;
                heading.append (mark);
            }
            var ident = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            ident.valign = Gtk.Align.CENTER;
            var label = new Gtk.Label (name);
            label.add_css_class ("heading");
            label.xalign = 0f;
            label.valign = Gtk.Align.CENTER;
            ident.append (label);
            if (after_title != null) {
                after_title.valign = Gtk.Align.CENTER;
                ident.append (after_title);
            }
            heading.append (ident);
            var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            heading.append (spacer);
            if (suffix != null) {
                suffix.valign = Gtk.Align.CENTER;
                heading.append (suffix);
            }
            return heading;
        }

        public static Gtk.Widget section_caption (string title) {
            var sub = new Gtk.Label (title);
            sub.add_css_class ("caption-heading");
            sub.add_css_class ("dim-label");
            sub.xalign = 0f;
            margins (sub, Ui.Metrics.PAGE_MARGIN, Ui.Metrics.GROUP_SPACING, Ui.Metrics.HEADING_GAP);
            return sub;
        }

        public static Gtk.Widget section_prose (string text) {
            var label = new Gtk.Label (text);
            label.add_css_class ("dim-label");
            label.wrap = true;
            label.xalign = 0f;
            label.margin_start = Ui.Metrics.PAGE_MARGIN;
            label.margin_end = Ui.Metrics.PAGE_MARGIN;
            label.margin_bottom = Ui.Metrics.HEADING_GAP;
            return label;
        }

        public static void inset_editor (Gtk.Widget widget) {
            widget.margin_top = Ui.Metrics.EDITOR_INSET;
            widget.margin_bottom = Ui.Metrics.EDITOR_INSET;
            widget.margin_start = Ui.Metrics.EDITOR_INSET;
            widget.margin_end = Ui.Metrics.EDITOR_INSET;
        }

        public static Gtk.Widget status_pill (string text, string kind) {
            var label = new Gtk.Label (text);
            label.add_css_class ("caption");
            label.add_css_class ("status-pill");
            label.add_css_class ("status-pill-" + kind);
            label.valign = Gtk.Align.CENTER;
            label.ellipsize = Pango.EllipsizeMode.NONE;
            return label;
        }

        public static Gtk.Widget? support_pill (Models.SupportStatus support) {
            switch (support) {
                case Models.SupportStatus.EXPERIMENTAL:
                    return status_pill (_("Experimental"), "warning");
                case Models.SupportStatus.UNSUPPORTED:
                    return status_pill (_("Unsupported"), "danger");
                default:
                    return null;
            }
        }

        public static void append_status_pills (Gtk.Box box, Models.SupportStatus support) {
            var pill = support_pill (support);
            if (pill != null) box.append (pill);
        }

        public static void append_item_pills (
            Gtk.Box box,
            bool recommended,
            Models.SupportStatus support
        ) {
            if (recommended) box.append (status_pill (_("Recommended"), "accent"));
            append_status_pills (box, support);
        }

        public static string inherit_default_label (string default_label) {
            return _("Use default (%s)").printf (default_label);
        }

        public static Gtk.StringList build_toggle_override_model (string default_label) {
            var model = new Gtk.StringList (null);
            model.append (inherit_default_label (default_label));
            model.append (_("Enabled"));
            model.append (_("Disabled"));
            return model;
        }

        public static OptionListRow build_toggle_override_combo (
            string title,
            bool? current_value,
            string default_label,
            string subtitle = ""
        ) {
            var row = new OptionListRow ();
            row.title = title;
            if (subtitle != "") row.subtitle = subtitle;
            row.model = build_toggle_override_model (default_label);
            row.selected = (uint) ToggleOverrideState.from_nullable_bool (current_value);
            return row;
        }

        public static Models.InstallerPatch? installer_patch_for_setting (
            Models.InstallerManifest? installer,
            string setting
        ) {
            if (installer == null) return null;
            foreach (var patch in installer.patches) {
                if (patch.setting == setting) return patch;
            }
            return null;
        }
    }

    public class PageSection : Gtk.Box {
        public Adw.PreferencesGroup group { get; private set; }

        private Gtk.Box suffix_host;

        public PageSection (string title, string prose = "", Gtk.Widget? suffix = null, string icon = "") {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            suffix_host = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            suffix_host.valign = Gtk.Align.CENTER;
            append (PageChrome.heading_row (title, icon, suffix_host));
            if (suffix != null) set_suffix (suffix);
            if (prose.strip () != "") append (PageChrome.section_prose (prose));
            group = PageChrome.untitled_group ();
            append (group);
        }

        public void set_suffix (Gtk.Widget? widget) {
            PageChrome.clear_children (suffix_host);
            if (widget != null) suffix_host.append (widget);
        }

        public void add (Gtk.Widget child) {
            group.add (child);
        }

        public void remove_row (Gtk.Widget child) {
            group.remove (child);
        }
    }

    public class ButtonRow : Adw.ActionRow {
        public Gtk.Button button { get; private set; }

        public ButtonRow (string title, string button_label, string subtitle = "", string style = "") {
            this.title = title;
            if (subtitle != "") this.subtitle = subtitle;
            button = new Gtk.Button.with_label (button_label);
            button.valign = Gtk.Align.CENTER;
            PageChrome.apply_button_style (button, style, "");
            add_suffix (button);
            activatable_widget = button;
        }
    }
}
