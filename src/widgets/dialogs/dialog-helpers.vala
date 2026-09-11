namespace Lumoria.Widgets.Dialogs {

    public class DialogHelpers : Object {
        public delegate void PrefixRemoveCallback (bool deleted_files);
        public delegate void PathSelectedCallback (string path);
        public delegate void FolderSelectedCallback (string path, string uri);
        public delegate void ErrorMessageCallback (string message);
        public delegate void ResponseCallback (string response);
        public delegate void GrantFolderCallback (Models.PrefixEntry entry, File file, string path);

        public class AlertResponse : Object {
            public string id { get; set; }
            public string label { get; set; }
            public Adw.ResponseAppearance appearance { get; set; default = Adw.ResponseAppearance.DEFAULT; }

            public AlertResponse (
                string id,
                string label,
                Adw.ResponseAppearance appearance = Adw.ResponseAppearance.DEFAULT
            ) {
                Object (id: id, label: label, appearance: appearance);
            }
        }

        public static Adw.HeaderBar dialog_header (bool show_close = true) {
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = show_close;
            return header;
        }

        public static Adw.ToolbarView dialog_toolbar (Adw.HeaderBar header, Gtk.Widget content) {
            var toolbar = new Adw.ToolbarView ();
            toolbar.add_top_bar (header);
            toolbar.content = content;
            return toolbar;
        }

        public static Adw.ToolbarView dialog_body (Gtk.Widget content, bool show_close = true) {
            return dialog_toolbar (dialog_header (show_close), content);
        }

        /*
         * Base for every app dialog: gamepad navigation plus a toast layer, so toasts raised while
         * the dialog is on top render above it instead of behind the modal. The navigator is created
         * on first use so it scans the finished widget tree.
         */
        public abstract class GamepadDialog : Adw.Dialog, Services.GamepadNavigable, ToastHost {
            private Services.GamepadListNavigator? navigator_instance;
            private ToastStack? toasts;

            protected Services.GamepadListNavigator navigator {
                get {
                    if (navigator_instance == null) navigator_instance = create_navigator ();
                    return navigator_instance;
                }
            }

            protected void set_body (Gtk.Widget body) {
                child = ToastStack.attach (body, out toasts);
            }

            public void push_toast (string message) {
                if (toasts == null) {
                    var body = child;
                    child = null;
                    set_body (body ?? new Adw.Bin ());
                }
                toasts.push (message);
            }

            protected virtual Services.GamepadListNavigator create_navigator () {
                return new Services.GamepadListNavigator ((Gtk.Widget) this);
            }

            public virtual bool handle_gamepad_action (Services.GamepadAction action) {
                if (action == Services.GamepadAction.BACK) return on_gamepad_back ();
                return navigator.handle_action (action);
            }

            protected virtual bool on_gamepad_back () {
                close ();
                return true;
            }
        }

        public class FormFooter : Gtk.Box {
            public Gtk.Button cancel_button { get; private set; }
            public Gtk.Button save_button { get; private set; }
            public Gtk.Button? delete_button { get; private set; }

            public FormFooter (string save_label, string? delete_label = null, string? cancel_label = null) {
                Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: Lumoria.Ui.Metrics.EDITOR_INSET);
                margin_start = Lumoria.Ui.Metrics.PAGE_MARGIN;
                margin_end = Lumoria.Ui.Metrics.PAGE_MARGIN;
                margin_top = Lumoria.Ui.Metrics.EDITOR_INSET;
                margin_bottom = Lumoria.Ui.Metrics.PAGE_MARGIN;
                homogeneous = true;

                if (delete_label != null) {
                    delete_button = new Gtk.Button.with_label (delete_label);
                    delete_button.add_css_class ("destructive-action");
                    append (delete_button);
                }

                cancel_button = new Gtk.Button.with_label (cancel_label ?? _("Cancel"));
                append (cancel_button);

                save_button = new Gtk.Button.with_label (save_label);
                save_button.add_css_class ("suggested-action");
                append (save_button);
            }
        }

        public static void present_tracked (Gtk.Widget? origin, Adw.Dialog dialog) {
            var root = origin != null ? origin.get_root () : null;
            var host = root as DialogHost;
            if (host != null) host.show_dialog (dialog);
            else dialog.present (root as Gtk.Widget);
        }

        public static void present_confirmation (
            Gtk.Widget parent,
            string title,
            string body,
            string confirm_id,
            string confirm_label,
            Adw.ResponseAppearance confirm_appearance,
            owned Utils.Action on_confirm,
            bool markup = false,
            string cancel_label = ""
        ) {
            var dialog = markup
                ? new Adw.AlertDialog (title, "")
                : new Adw.AlertDialog (title, body);
            if (markup && body.strip () != "") {
                var content = new MarkupContent (body);
                content.margin_start = 4;
                content.margin_end = 4;
                dialog.extra_child = content;
            }
            dialog.add_response ("cancel", cancel_label != "" ? cancel_label : _("Cancel"));
            dialog.add_response (confirm_id, confirm_label);
            dialog.set_response_appearance (confirm_id, confirm_appearance);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == confirm_id) {
                    on_confirm ();
                }
            });
            present_tracked (parent, dialog);
        }

        public static void present_responses (
            Gtk.Widget? parent,
            string title,
            string body,
            string default_id,
            string close_id,
            owned ResponseCallback on_response,
            AlertResponse[] responses,
            Gtk.Widget? extra = null,
            bool prefer_wide = false,
            int content_width = 0
        ) {
            var dialog = new Adw.AlertDialog (title, body);
            dialog.prefer_wide_layout = prefer_wide;
            if (content_width > 0) dialog.content_width = content_width;
            if (extra != null) dialog.extra_child = extra;
            foreach (var spec in responses) {
                dialog.add_response (spec.id, spec.label);
                if (spec.appearance != Adw.ResponseAppearance.DEFAULT) {
                    dialog.set_response_appearance (spec.id, spec.appearance);
                }
            }
            dialog.default_response = default_id;
            dialog.close_response = close_id;
            dialog.response.connect ((response) => on_response (response));
            present_tracked (parent, dialog);
        }

        public static void present_grant (
            Gtk.Widget? parent,
            string title,
            string body,
            owned Utils.Action on_grant,
            string grant_id = "grant",
            string grant_label = ""
        ) {
            present_responses (
                parent,
                title,
                body,
                grant_id,
                "cancel",
                (response) => {
                    if (response == grant_id) on_grant ();
                },
                {
                    new AlertResponse ("cancel", _("Cancel")),
                    new AlertResponse (
                        grant_id,
                        grant_label != "" ? grant_label : _("Grant Access"),
                        Adw.ResponseAppearance.SUGGESTED
                    )
                }
            );
        }

        public static void present_destructive_confirmation (
            Gtk.Widget parent,
            string title,
            string body,
            string confirm_id,
            string confirm_label,
            owned Utils.Action on_confirm
        ) {
            present_confirmation (
                parent, title, body, confirm_id, confirm_label,
                Adw.ResponseAppearance.DESTRUCTIVE, (owned) on_confirm
            );
        }

    }
}
