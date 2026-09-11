namespace Lumoria.Ui {

    public class RunnerOverrideRows : Gtk.Box {
        public signal void changed ();

        private Application.Context ctx;
        private bool lock_identity;
        private Gee.ArrayList<Models.RunnerVariant> visible_variants;
        private Widgets.OptionListRow? runner_combo;
        private Widgets.OptionListRow? variant_combo;
        private Adw.ActionRow? runner_label;
        private Adw.ActionRow? variant_label;
        private Adw.ActionRow version_row;
        private Gtk.Box runner_about;
        private Gtk.Widget latest_warning;
        private string runner_version = Models.ToolVersionRef.INHERIT.id ();
        private string bound_runner_id = "";
        private string bound_variant_id = "";
        private bool applying = false;

        public RunnerOverrideRows (Application.Context ctx, bool lock_identity = false) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.lock_identity = lock_identity;
            visible_variants = new Gee.ArrayList<Models.RunnerVariant> ();
            build_ui ();
        }

        public void bind (string runner_id, string version, string variant_id) {
            applying = true;
            bound_runner_id = runner_id;
            bound_variant_id = variant_id;
            runner_version = version != "" ? version : Models.ToolVersionRef.INHERIT.id ();
            if (lock_identity) {
                update_identity_labels ();
            } else {
                runner_combo.selected = Widgets.RunnerSettings.select_runner_override_index (
                    ctx.runner_manifests, runner_id
                );
                rebuild_variant (variant_id);
            }
            update_version_row ();
            update_runner_about ();
            applying = false;
        }

        public string runner_id () {
            if (lock_identity) return bound_runner_id;
            return Widgets.RunnerSettings.runner_id_for_override_index (
                ctx.runner_manifests, runner_combo.selected
            );
        }

        public string version () {
            return runner_version != "" ? runner_version : Models.ToolVersionRef.INHERIT.id ();
        }

        public string variant_id () {
            if (lock_identity) return bound_variant_id;
            if (runner_id () == "" || variant_combo == null || !variant_combo.visible) return "";
            var idx = (int) variant_combo.selected;
            if (idx < 0 || idx >= visible_variants.size) return "";
            return visible_variants[idx].id;
        }

        private void build_ui () {
            var group = new Widgets.PageSection (_("Runner"));
            if (lock_identity) {
                runner_label = new Adw.ActionRow ();
                runner_label.title = _("Runner");
                runner_label.activatable = false;
                group.add (runner_label);
                variant_label = new Adw.ActionRow ();
                variant_label.title = _("Variant");
                variant_label.activatable = false;
                group.add (variant_label);
            } else {
                runner_combo = new Widgets.OptionListRow ();
                runner_combo.title = _("Runner");
                runner_combo.set_items (
                    Widgets.RunnerSettings.build_runner_override_items (ctx.runner_manifests)
                );
                runner_combo.notify["selected"].connect (() => {
                    if (applying) return;
                    runner_version = Models.ToolVersionRef.INHERIT.id ();
                    rebuild_variant ("");
                    update_version_row ();
                    update_runner_about ();
                    changed ();
                });
                group.add (runner_combo);

                variant_combo = new Widgets.OptionListRow ();
                variant_combo.title = _("Variant");
                variant_combo.notify["selected"].connect (() => {
                    if (applying) return;
                    runner_version = Models.ToolVersionRef.INHERIT.id ();
                    update_version_row ();
                    update_runner_about ();
                    changed ();
                });
                group.add (variant_combo);
            }

            version_row = Widgets.PageChrome.navigation_row (_("Version"));
            version_row.activated.connect (open_version_picker);
            group.add (version_row);
            append (group);

            runner_about = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            append (runner_about);

            latest_warning = Widgets.Messages.warning (
                _("Latest keeps this prefix on the newest runner automatically. Updates may change compatibility or behavior without notice.")
            );
            latest_warning.visible = false;
            append (latest_warning);
        }

        private void update_identity_labels () {
            var runner = resolve_bound_runner ();
            if (runner != null) {
                runner_label.subtitle = runner.display_label ();
                try {
                    var variant = runner.effective_variant (bound_variant_id);
                    variant_label.subtitle = variant.display_label ();
                    variant_label.visible = true;
                } catch (Error e) {
                    variant_label.visible = false;
                }
                return;
            }
            runner_label.subtitle = bound_runner_id != "" ? bound_runner_id : _("Using the Runtime default");
            variant_label.visible = bound_variant_id != "";
            variant_label.subtitle = bound_variant_id;
        }

        private void rebuild_variant (string preselect) {
            Widgets.RunnerSettings.fill_variant_combo (
                variant_combo,
                Models.find_by_id<Models.RunnerManifest> (ctx.runner_manifests, runner_id ()),
                visible_variants,
                preselect
            );
        }

        private void update_version_row () {
            var runner = resolve_bound_runner ();
            var inheriting_version = Models.ToolVersionRef.is_inherit (runner_version);
            version_row.sensitive = effective_runner_id () != "";
            version_row.subtitle = inheriting_version
                ? _("Using the Runtime default")
                : Widgets.RunnerSettings.version_label_for_value (runner, runner_version);
            latest_warning.visible = !inheriting_version
                && Widgets.RunnerSettings.is_effective_latest (runner, runner_version);
        }

        private Models.RunnerManifest? resolve_bound_runner () {
            var entry = new Models.PrefixEntry ();
            entry.runner_id = runner_id ();
            entry.runner_version = runner_version;
            entry.variant_id = variant_id ();
            try {
                return Models.RunnerManifest.resolve_for_entry (ctx.runner_manifests, entry);
            } catch (Error e) {
                return null;
            }
        }

        private string effective_runner_id () {
            return Utils.Preferences.effective_runner_id (runner_id ());
        }

        private void update_runner_about () {
            if (runner_about == null) return;
            Widgets.ManifestUi.populate_about (
                runner_about,
                Models.find_by_id<Models.RunnerManifest> (ctx.runner_manifests, effective_runner_id ())
            );
        }

        private void open_version_picker () {
            var id = effective_runner_id ();
            if (id == "") return;
            var runner = Models.find_by_id<Models.RunnerManifest> (ctx.runner_manifests, id);
            if (runner == null) return;
            Models.RunnerVariant? variant = null;
            if (lock_identity) {
                try {
                    variant = runner.effective_variant (bound_variant_id);
                } catch (Error e) {
                    ctx.show_toast (user_error (e));
                    return;
                }
            } else {
                var idx = (int) variant_combo.selected;
                if (variant_combo.visible && idx >= 0 && idx < visible_variants.size) {
                    variant = visible_variants[idx];
                }
            }
            var variant_id = variant != null ? variant.id : "";
            var picker = new Widgets.Dialogs.VersionBrowserDialog.pick (
                new Runtime.RunnerToolAdapter (runner, variant_id),
                runner_version,
                Widgets.RunnerSettings.version_label_for_value (runner, Models.ToolVersionRef.INHERIT.id ()),
                Models.ToolVersionRef.INHERIT.id ()
            );
            picker.version_selected.connect ((value) => {
                runner_version = value;
                update_version_row ();
                changed ();
            });
            ctx.show_dialog (picker);
        }
    }
}
