namespace Lumoria.Widgets.Dialogs {

    public class InstallProgressDialog : DialogHelpers.GamepadDialog {
        private Lumoria.Application.Context ctx;
        private Lumoria.Application.InstallSession session;

        public InstallProgressDialog (
            Lumoria.Application.Context ctx,
            Lumoria.Application.InstallSession session
        ) {
            Object (
                title: "",
                content_width: Lumoria.Ui.Metrics.DIALOG_WIDTH_WIDE,
                follows_content_size: true,
                can_close: false
            );
            this.ctx = ctx;
            this.session = session;

            var view = new Ui.InstallProgressView (session);
            view.close_requested.connect (() => close ());
            set_body (view);

            close_attempt.connect (on_close_attempt);
            session.changed.connect (sync_can_close);
            session.finished.connect ((success) => sync_can_close ());
            sync_can_close ();
        }

        protected override bool on_gamepad_back () {
            if (can_close) close ();
            return true;
        }

        private bool needs_prompt () {
            return session.created_prefix
                && session.kind == Lumoria.Application.InstallKind.FULL
                && !session.is_active;
        }

        private void sync_can_close () {
            can_close = !session.is_active && !needs_prompt ();
        }

        private void on_close_attempt () {
            if (session.is_active) return;
            if (!needs_prompt ()) {
                force_close ();
                return;
            }
            if (session.status == Lumoria.Application.InstallStatus.SUCCEEDED) {
                present_cache_prompt ();
            } else {
                present_incomplete_prompt ();
            }
        }

        private void present_cache_prompt () {
            DialogHelpers.present_responses (
                this,
                _("Clear Install Cache?"),
                _("Cached downloads will save time if you need to reinstall."),
                "keep",
                "keep",
                (response) => {
                    if (response == "remove") {
                        Utils.StorageCache.instance ().clear_all_cache_async ((error) => {
                            if (error != null) ctx.show_toast (user_error (error));
                        });
                    }
                    force_close ();
                },
                {
                    new DialogHelpers.AlertResponse ("remove", _("Remove Files"), Adw.ResponseAppearance.DESTRUCTIVE),
                    new DialogHelpers.AlertResponse ("keep", _("Keep Files"), Adw.ResponseAppearance.SUGGESTED)
                }
            );
        }

        private void present_incomplete_prompt () {
            var entry = ctx.registry.by_id (session.prefix_id);
            var path = entry != null ? entry.resolved_path () : "";
            var cancelled = session.status == Lumoria.Application.InstallStatus.CANCELLED;
            var title = cancelled ? _("Installation Cancelled") : _("Installation Failed");
            var body = path != ""
                ? _("The prefix at %s may be incomplete. Would you like to delete it?").printf (path)
                : _("The prefix may be incomplete. Would you like to delete it?");
            var responses = new Gee.ArrayList<DialogHelpers.AlertResponse> ();
            if (session.log_path != "") {
                responses.add (new DialogHelpers.AlertResponse ("logs", _("Open Logs")));
            }
            responses.add (new DialogHelpers.AlertResponse ("close", _("Keep Prefix")));
            responses.add (new DialogHelpers.AlertResponse (
                "delete", _("Delete Prefix"), Adw.ResponseAppearance.DESTRUCTIVE
            ));
            DialogHelpers.present_responses (
                this,
                title,
                body,
                "close",
                "close",
                (response) => {
                    if (response == "logs") {
                        var dir = Path.get_dirname (session.log_path);
                        FileDialogs.open_directory (get_root () as Gtk.Window, dir, null);
                        return;
                    }
                    if (response == "delete" && entry != null) {
                        ctx.remove_prefix (entry, true);
                    }
                    force_close ();
                },
                responses.to_array ()
            );
        }
    }
}
