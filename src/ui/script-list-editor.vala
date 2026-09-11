namespace Lumoria.Ui {

    public class ScriptListEditor : Gtk.Box {
        public signal void changed ();

        private Application.Context ctx;
        private Models.PrefixEntry? entry;
        private Gee.ArrayList<Models.PrefixPostInstallManifest> scripts;
        private Widgets.PageSection section;
        private Gtk.Box scripts_box;

        public ScriptListEditor (
            Application.Context ctx,
            Gee.ArrayList<Models.PrefixPostInstallManifest> scripts,
            Models.PrefixEntry? entry = null
        ) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.ctx = ctx;
            this.scripts = scripts;
            this.entry = entry;
            hexpand = true;
            vexpand = true;

            var add = Widgets.PageChrome.icon_button (Widgets.IconRegistry.ADD, _("Add Script"));
            add.clicked.connect (browse_and_add);
            section = new Widgets.PageSection (
                _("Scripts"),
                entry != null
                    ? _("Scripts are add-ons from outside Lumoria. They can install extra files, change settings, or add new launch options to this prefix. Only add scripts you trust: they change things Lumoria cannot undo on its own.")
                    : _("Scripts are optional add-ons that set up extras once the game is installed. Only add scripts you trust: they change things Lumoria cannot undo on its own."),
                add
            );
            section.add (Widgets.PageChrome.placeholder_row (_("No scripts added")));
            append (section);

            scripts_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            append (Widgets.PageChrome.scrolled (scripts_box));

            ctx.installs.session_finished.connect (on_session_finished);
            ctx.actions.changed.connect (on_actions_changed);
            rebuild ();
        }

        private void on_session_finished (Application.InstallSession session, bool success) {
            if (!get_mapped () || entry == null) return;
            if (session.kind != Application.InstallKind.SCRIPT) return;
            if (session.prefix_id != entry.id) return;
            rebuild ();
        }

        private void on_actions_changed () {
            if (get_mapped () && entry != null) rebuild ();
        }

        public void rebuild () {
            Widgets.PageChrome.clear_children (scripts_box);
            section.group.visible = scripts.size == 0;
            if (entry != null && ctx.actions.is_loading (entry.id)) {
                section.group.visible = false;
                scripts_box.append (Widgets.PageChrome.remote_actions_loading_group ());
                return;
            }
            foreach (var spec in scripts) {
                add_script_group (spec);
            }
        }

        private void add_script_group (Models.PrefixPostInstallManifest spec) {
            var manifest = Widgets.ScriptOverview.load (entry, spec);
            var title = spec.name != "" ? spec.name : spec.manifest_id;
            var suffix = script_actions (spec, title, manifest);
            if (entry != null) {
                Widgets.ScriptOverview.append (scripts_box, ctx, entry, spec, suffix, true);
                return;
            }
            if (manifest != null) {
                scripts_box.append (Widgets.ManifestUi.intro (manifest, null, suffix));
                var instructions = Widgets.ManifestUi.prose (manifest, null, Models.ManifestMessages.INSTRUCTIONS);
                if (instructions != null) scripts_box.append (instructions);
            } else {
                scripts_box.append (Widgets.PageChrome.heading_row (title, "", suffix, null, false));
            }
        }

        private Gtk.Widget script_actions (
            Models.PrefixPostInstallManifest spec,
            string title,
            Models.PostInstallManifest? manifest
        ) {
            var can_rerun = entry != null && (manifest == null || manifest.reinstallable);
            var actions = new ScriptActions (spec, title, can_rerun);
            actions.rerun_requested.connect (confirm_rerun);
            actions.remove_requested.connect (confirm_remove);
            return actions;
        }

        private void confirm_rerun (Models.PrefixPostInstallManifest spec, string title) {
            if (entry == null) return;
            Widgets.Dialogs.DialogHelpers.present_confirmation (
                this,
                _("Rerun %s?").printf (title),
                _("Running this script again may have unforeseen consequences."),
                "rerun",
                _("Rerun"),
                Adw.ResponseAppearance.SUGGESTED,
                () => ctx.installs.rerun_script (entry, spec.id)
            );
        }

        private void confirm_remove (Models.PrefixPostInstallManifest spec, string title) {
            var body = entry != null
                ? _("The script will be detached from this prefix. Files it already installed are left in place.")
                : _("This script will not run when the prefix is created.");
            Widgets.Dialogs.DialogHelpers.present_destructive_confirmation (
                this,
                _("Remove %s?").printf (title),
                body,
                "remove",
                _("Remove"),
                () => {
                    if (entry != null) {
                        try {
                            ctx.scripts.detach (entry, spec.id);
                        } catch (Error e) {
                            ctx.show_toast (user_error (e));
                        }
                    } else {
                        scripts.remove (spec);
                    }
                    rebuild ();
                    changed ();
                }
            );
        }

        private class ScriptActions : Gtk.Box {
            public signal void rerun_requested (Models.PrefixPostInstallManifest spec, string title);
            public signal void remove_requested (Models.PrefixPostInstallManifest spec, string title);

            private Models.PrefixPostInstallManifest spec;
            private string title;

            public ScriptActions (Models.PrefixPostInstallManifest spec, string title, bool can_rerun) {
                Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 4);
                this.spec = spec;
                this.title = title;
                valign = Gtk.Align.CENTER;
                if (can_rerun) {
                    var rerun = Widgets.PageChrome.icon_button (Widgets.IconRegistry.REFRESH, _("Rerun"));
                    rerun.clicked.connect (() => rerun_requested (this.spec, this.title));
                    append (rerun);
                }
                var remove = Widgets.PageChrome.icon_button (Widgets.IconRegistry.DELETE, _("Remove"));
                remove.add_css_class ("destructive-action");
                remove.clicked.connect (() => remove_requested (this.spec, this.title));
                append (remove);
            }
        }

        private void browse_and_add () {
            if (Widgets.Dialogs.FileDialogs.file_browse_blocked (ctx)) return;

            var filter = new Gtk.FileFilter ();
            filter.name = _("Scripts");
            filter.add_suffix ("json");
            var dialog = Widgets.Dialogs.FileDialogs.build_file_dialog (_("Choose a Script"), filter);
            var root = get_root () as Gtk.Window;
            Widgets.Dialogs.FileDialogs.open_file_dialog (root, dialog, null, (path) => {
                try {
                    if (entry != null) {
                        ctx.scripts.attach (entry, path, "");
                    } else {
                        var spec = Models.PostInstallManifest.load_from_file (path);
                        foreach (var existing in scripts) {
                            if (existing.manifest_id == spec.id) {
                                ctx.show_toast (_("This script is already attached."));
                                return;
                            }
                        }
                        var meta = new Models.PrefixPostInstallManifest ();
                        meta.ensure_id ();
                        meta.original_path = path;
                        meta.manifest_id = spec.id;
                        meta.name = spec.display_label ();
                        scripts.add (meta);
                    }
                    rebuild ();
                    changed ();
                } catch (Error e) {
                    ctx.show_toast (user_error (e));
                }
            }, (message) => ctx.show_toast (message));
        }
    }
}
