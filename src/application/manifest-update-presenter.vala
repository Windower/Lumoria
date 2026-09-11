namespace Lumoria.Application {

    public class ManifestUpdatePresenter : Object {
        private Context ctx;
        private UiHost host;
        private Widgets.Dialogs.ManifestUpdateProgressDialog? progress;

        public ManifestUpdatePresenter (Context ctx, UiHost host) {
            this.ctx = ctx;
            this.host = host;
            var updates = ctx.manifest_updates;
            updates.checking.connect (on_checking);
            updates.consent_needed.connect (on_consent);
            updates.apply_started.connect (on_apply_started);
            updates.status_changed.connect (on_status);
            updates.progress.connect (on_progress);
            updates.apply_finished.connect (on_apply_finished);
        }

        private void on_checking (bool manual) {
            if (!manual) return;
            dismiss ();
            progress = new Widgets.Dialogs.ManifestUpdateProgressDialog ();
            progress.show_checking ();
            host.show_dialog (progress);
        }

        private void on_consent (ManifestUpdateCheck result, owned ManifestCheckReport? report) {
            var dialog = new Widgets.Dialogs.ManifestUpdateConsentDialog ();
            dialog.decided.connect ((update, dont_ask) => {
                var remote = result.remote;
                if (remote != null) {
                    Utils.Preferences.instance ().remember_manifest_consent (
                        update, dont_ask, remote.revision
                    );
                }
                if (!update) {
                    if (report != null) report (result.message, false);
                    return;
                }
                ctx.manifest_updates.apply_async (result, (owned) report);
            });
            host.show_dialog (dialog);
        }

        private void on_apply_started () {
            if (progress == null) {
                progress = new Widgets.Dialogs.ManifestUpdateProgressDialog ();
                host.show_dialog (progress);
            }
            progress.show_applying ();
        }

        private void on_status (string status) {
            if (progress != null) progress.set_status (status);
        }

        private void on_progress (int64 got, int64 total) {
            if (progress != null) progress.set_progress (got, total);
        }

        private void on_apply_finished (Error? error) {
            if (progress == null) return;
            if (error != null) {
                progress.fail (user_error (error));
                progress = null;
                return;
            }
            dismiss ();
        }

        private void dismiss () {
            if (progress == null) return;
            progress.force_close ();
            progress = null;
        }
    }
}
