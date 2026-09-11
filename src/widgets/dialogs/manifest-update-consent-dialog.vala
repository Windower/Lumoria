namespace Lumoria.Widgets.Dialogs {

    public class ManifestUpdateConsentDialog : DialogHelpers.GamepadDialog {
        public signal void decided (bool update, bool dont_ask);

        private Gtk.CheckButton dont_ask;
        private bool resolved = false;

        public ManifestUpdateConsentDialog () {
            Object (
                title: _("A manifest update is available."),
                content_width: 480
            );
            build_ui ();
            closed.connect (() => {
                if (resolved) return;
                decided (false, false);
            });
        }

        private void build_ui () {
            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, Lumoria.Ui.Metrics.GROUP_SPACING);
            PageChrome.margins (
                body, Lumoria.Ui.Metrics.PAGE_MARGIN, Lumoria.Ui.Metrics.GROUP_SPACING, Lumoria.Ui.Metrics.EDITOR_INSET
            );

            body.append (IconRegistry.mascot_image (80));

            var explanation = new Gtk.Label (
                _("These files tell Lumoria how to install and launch Final Fantasy XI. The install steps, launcher, Wine runner, components, and redistributables. Updating replaces those definitions and may also download required resources.")
            );
            explanation.wrap = true;
            explanation.justify = Gtk.Justification.CENTER;
            explanation.add_css_class ("body");
            body.append (explanation);

            dont_ask = new Gtk.CheckButton.with_label (_("Don't ask again"));
            dont_ask.halign = Gtk.Align.CENTER;
            body.append (dont_ask);

            var actions = new DialogHelpers.FormFooter (_("Yes"), null, _("No"));
            actions.margin_top = 0;
            actions.cancel_button.clicked.connect (() => finish (false));
            actions.save_button.clicked.connect (() => finish (true));

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.append (body);
            content.append (actions);
            set_body (DialogHelpers.dialog_body (content, true));
        }

        protected override bool on_gamepad_back () {
            finish (false);
            return true;
        }

        private void finish (bool update) {
            if (resolved) return;
            resolved = true;
            decided (update, dont_ask.active);
            can_close = true;
            close ();
        }
    }
}
