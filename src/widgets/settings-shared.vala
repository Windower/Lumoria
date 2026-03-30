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

    public class SettingsShared : Object {
        public delegate void PrefixRemoveCallback (bool deleted_files);

        public const string PAGE_GENERAL = "general";
        public const string PAGE_RUNTIME = "runtime";
        public const string PAGE_RUNNERS = "runners";
        public const string PAGE_COMPONENTS = "components";
        public const string PAGE_LAUNCH = "launch";
        public const string PAGE_ADVANCED = "advanced";
        public const string PAGE_ABOUT = "about";

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
            var scroll = new Gtk.ScrolledWindow ();
            scroll.child = page_widget;
            scroll.vexpand = true;
            return add_settings_page (stack, scroll, page_id, title);
        }

        public static Adw.PreferencesGroup build_group (
            string title,
            int horizontal_margin = 24,
            int margin_top = 12,
            int margin_bottom = 0
        ) {
            var group = new Adw.PreferencesGroup ();
            group.title = title;
            group.margin_start = horizontal_margin;
            group.margin_end = horizontal_margin;
            group.margin_top = margin_top;
            group.margin_bottom = margin_bottom;
            return group;
        }

        public static Gtk.StringList build_toggle_override_model (string default_label) {
            var model = new Gtk.StringList (null);
            model.append (_("Inherit default (%s)").printf (default_label));
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

        public static Gtk.StringList build_logging_mode_model () {
            var model = new Gtk.StringList (null);
            model.append (_("Don't Keep"));
            model.append (_("Keep (prefix-path/logs)"));
            return model;
        }

        public static bool file_browse_blocked (Adw.ToastOverlay overlay) {
            if (!Utils.EnvironmentInfo.is_gamescope ()) return false;
            overlay.add_toast (new Adw.Toast (_("File browsing is not available in a gamescope session.")));
            return true;
        }

        public static void present_alert (Gtk.Widget parent, string title, string body) {
            var alert = new Adw.AlertDialog (title, body);
            alert.add_response ("ok", _("OK"));
            alert.present (parent);
        }

        public static void present_remove_prefix_dialog (
            Gtk.Widget parent,
            Models.PrefixEntry entry,
            owned PrefixRemoveCallback on_confirm
        ) {
            var dialog = new Adw.AlertDialog (
                _("Remove Prefix?"),
                _("Remove \"%s\" from the prefix list?\n\nPath: %s").printf (
                    entry.display_name (), entry.path
                )
            );
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("remove", _("Remove from List"));
            dialog.add_response ("delete", _("Remove and Delete Files"));
            dialog.set_response_appearance ("remove", Adw.ResponseAppearance.SUGGESTED);
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == "remove") {
                    on_confirm (false);
                    return;
                }
                if (response != "delete") return;

                var removing_dialog = new Adw.Dialog ();
                removing_dialog.title = _("Removing Prefix");
                removing_dialog.content_width = 300;
                removing_dialog.content_height = 150;
                removing_dialog.can_close = false;

                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
                box.halign = Gtk.Align.CENTER;
                box.valign = Gtk.Align.CENTER;
                box.margin_start = 24;
                box.margin_end = 24;

                var spinner = new Gtk.Spinner ();
                spinner.spinning = true;
                spinner.width_request = 32;
                spinner.height_request = 32;
                box.append (spinner);

                var label = new Gtk.Label (_("Removing prefix files\u2026"));
                label.add_css_class ("heading");
                box.append (label);

                removing_dialog.child = box;
                removing_dialog.present (parent);

                var remove_path = entry.resolved_path ();
                new Thread<bool> ("remove-prefix", () => {
                    var ok = Utils.remove_recursive (remove_path);
                    Idle.add (() => {
                        removing_dialog.can_close = true;
                        removing_dialog.close ();
                        on_confirm (ok);
                        return false;
                    });
                    return true;
                });
            });
            dialog.present (parent);
        }
    }
}
