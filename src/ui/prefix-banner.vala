namespace Lumoria.Ui {

    public class PrefixBanner : Gtk.Box {
        private Application.Context ctx;
        private Models.PrefixEntry entry;
        private Gtk.EditableLabel name_label;
        private Gtk.Button play_btn;
        private Gtk.Button choose_btn;
        private Gtk.Label path_label;
        private Gtk.Box play_cluster;
        private bool suppress_play = false;
        private Gtk.Button quick_launch_btn;
        private Gtk.Image quick_launch_icon;
        private Gtk.Label quick_launch_label;
        private Gtk.Box header;
        private Gtk.Box name_wrap;
        private Gtk.Box meta_fields;
        private Gtk.Box meta;
        private Gtk.Widget? watched_root;
        private ulong watched_id = 0;
        private Gtk.GestureClick? outside_click;
        private bool stacked = false;

        public PrefixBanner (Application.Context ctx, Models.PrefixEntry entry) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 4);
            this.ctx = ctx;
            this.entry = entry;
            add_css_class ("prefix-banner");
            hexpand = true;

            name_label = new Gtk.EditableLabel (entry.display_name ());
            name_label.add_css_class ("prefix-banner-name");
            name_label.hexpand = true;
            name_label.halign = Gtk.Align.FILL;
            name_label.xalign = 0f;
            name_label.add_css_class ("title-1");
            ellipsize_editable_label (name_label);
            name_label.notify["editing"].connect (on_editing_changed);

            var edit_hint = new Gtk.Image.from_icon_name (Widgets.IconRegistry.EDIT);
            edit_hint.pixel_size = 16;
            edit_hint.valign = Gtk.Align.CENTER;
            edit_hint.add_css_class ("prefix-banner-edit-hint");

            name_wrap = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            name_wrap.add_css_class ("prefix-banner-name-wrap");
            name_wrap.hexpand = true;
            name_wrap.append (edit_hint);
            name_wrap.append (name_label);

            map.connect (watch_root);
            unmap.connect (on_unmap);
            unrealize.connect (unwatch_root);

            path_label = new Gtk.Label ("");
            path_label.add_css_class ("prefix-banner-muted");
            path_label.add_css_class ("caption");
            path_label.xalign = 0f;
            path_label.wrap = true;
            path_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            path_label.selectable = true;
            path_label.can_focus = false;

            quick_launch_icon = Widgets.IconRegistry.bookmark_image (false, 12);
            quick_launch_label = new Gtk.Label (_("Set as Quick Launch"));
            quick_launch_label.add_css_class ("caption");
            var quick_launch_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            quick_launch_box.append (quick_launch_icon);
            quick_launch_box.append (quick_launch_label);
            quick_launch_btn = new Gtk.Button ();
            quick_launch_btn.child = quick_launch_box;
            quick_launch_btn.add_css_class ("flat");
            quick_launch_btn.add_css_class ("prefix-banner-quick-launch");
            quick_launch_btn.hexpand = false;
            quick_launch_btn.halign = Gtk.Align.END;
            quick_launch_btn.valign = Gtk.Align.CENTER;
            quick_launch_btn.clicked.connect (toggle_quick_launch);
            ctx.state.changed.connect (sync_quick_launch);
            sync_quick_launch ();

            play_btn = new Gtk.Button.from_icon_name (Widgets.IconRegistry.PAGE_LAUNCH);
            Widgets.PageChrome.style_play_button (play_btn);
            play_btn.clicked.connect (launch_default);
            var long_press = new Gtk.GestureLongPress ();
            long_press.pressed.connect (on_play_long_press);
            play_btn.add_controller (long_press);

            choose_btn = Widgets.PageChrome.icon_button (Widgets.IconRegistry.DROPDOWN, _("Prefix Default"));
            choose_btn.clicked.connect (open_play_menu);

            play_cluster = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            play_cluster.add_css_class ("prefix-banner-play-cluster");
            play_cluster.hexpand = false;
            play_cluster.halign = Gtk.Align.END;
            play_cluster.valign = Gtk.Align.CENTER;
            play_cluster.append (play_btn);
            play_cluster.append (choose_btn);

            ctx.launches.changed.connect (sync_play);
            ctx.prefixes.changed.connect (on_prefixes_changed);
            ctx.actions.changed.connect (sync_play);
            ctx.exclusive_changed.connect (sync_play);
            var prefs = Utils.Preferences.instance ();
            prefs.notify["runner-id"].connect (sync_meta);
            prefs.notify["runner-version"].connect (sync_meta);
            sync_play ();

            header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            header.add_css_class ("prefix-banner-header");
            header.hexpand = true;
            header.overflow = Gtk.Overflow.HIDDEN;
            header.append (name_wrap);
            header.append (play_cluster);

            meta_fields = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
            meta_fields.hexpand = true;
            meta_fields.halign = Gtk.Align.FILL;
            sync_meta ();

            meta = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
            meta.hexpand = true;
            meta.halign = Gtk.Align.FILL;
            meta.add_css_class ("prefix-banner-meta");
            meta.append (meta_fields);
            meta.append (quick_launch_btn);

            append (header);
            append (path_label);
            append (meta);
        }

        /* Gtk.EditableLabel never ellipsizes its label, so a long name would push the play cluster off the banner. */
        private static void ellipsize_editable_label (Gtk.EditableLabel editable) {
            for (var child = editable.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var stack = child as Gtk.Stack;
                if (stack == null) continue;
                var label = stack.get_child_by_name ("label") as Gtk.Label;
                if (label != null) label.ellipsize = Pango.EllipsizeMode.END;
                return;
            }
        }

        private void on_unmap () {
            if (name_label.editing) commit_name ();
        }

        private void on_prefixes_changed () {
            sync_play ();
            sync_meta ();
        }

        private void on_play_long_press () {
            suppress_play = true;
            open_play_menu ();
        }

        private void watch_root () {
            unwatch_root ();
            watched_root = get_root () as Gtk.Widget;
            if (watched_root == null) return;
            watched_id = watched_root.notify["css-classes"].connect (sync_narrow);
            outside_click = new Gtk.GestureClick ();
            outside_click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            outside_click.pressed.connect (on_root_pressed);
            watched_root.add_controller (outside_click);
            sync_narrow ();
        }

        private void unwatch_root () {
            if (watched_root != null) {
                watched_root.disconnect (watched_id);
                watched_root.remove_controller (outside_click);
            }
            watched_root = null;
            watched_id = 0;
            outside_click = null;
        }

        private void on_root_pressed (int n_press, double x, double y) {
            if (!name_label.editing) return;
            var target = watched_root.pick (x, y, Gtk.PickFlags.DEFAULT);
            if (target != null && (target == name_label || target.is_ancestor (name_label))) return;
            name_label.stop_editing (true);
            ((Gtk.Root) watched_root).set_focus (null);
        }

        private void sync_narrow () {
            apply_stack (watched_root != null && watched_root.has_css_class ("narrow-banner"));
        }

        private void apply_stack (bool should_stack) {
            if (should_stack == stacked) return;
            stacked = should_stack;
            meta.orientation = stacked ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL;
            meta.spacing = stacked ? 8 : 16;
            quick_launch_btn.halign = stacked ? Gtk.Align.START : Gtk.Align.END;
        }

        private void on_editing_changed () {
            if (name_label.editing) {
                name_wrap.add_css_class ("editing");
                return;
            }
            name_wrap.remove_css_class ("editing");
            commit_name ();
        }

        private void launch_default () {
            if (suppress_play) {
                suppress_play = false;
                return;
            }
            if (!ctx.ensure_prefix_access (entry)) return;
            ctx.actions.run_default (entry);
        }

        private void open_play_menu () {
            ctx.show_dialog (new Widgets.Dialogs.BannerPlayTargetDialog (ctx, entry));
        }

        private void toggle_quick_launch () {
            if (ctx.state.quick_launch.matches_prefix (entry.id)) {
                ctx.state.clear_quick_launch ();
                ctx.show_toast (_("Quick Launch cleared"));
                return;
            }
            ctx.state.update_quick_launch (entry.id);
            ctx.show_toast (_("Quick Launch updated"));
        }

        private void sync_quick_launch () {
            var active = ctx.state.quick_launch.matches_prefix (entry.id);
            Widgets.IconRegistry.apply_bookmark (quick_launch_icon, active, 12);
            quick_launch_label.label = active
                ? _("Clear Quick Launch")
                : _("Set as Quick Launch");
            Widgets.PageChrome.set_icon_label (quick_launch_btn, quick_launch_label.label);
            if (active) quick_launch_btn.add_css_class ("shortcut-active");
            else quick_launch_btn.remove_css_class ("shortcut-active");
        }

        private void sync_play () {
            if (entry.needs_grant ()) {
                play_btn.label = _("Grant Access");
                play_btn.remove_css_class ("circular");
                play_btn.sensitive = !ctx.busy && !ctx.launches.is_launching;
                Widgets.PageChrome.set_icon_label (play_btn, _("Grant Access"));
                choose_btn.visible = false;
                path_label.label = _("Permission required to access this prefix");
                path_label.selectable = false;
                return;
            }

            play_btn.icon_name = Widgets.IconRegistry.PAGE_LAUNCH;
            play_btn.add_css_class ("circular");
            choose_btn.visible = true;
            path_label.label = entry.resolved_path ();
            path_label.selectable = true;

            Runtime.LaunchTarget? action = null;
            string? resolve_error = null;
            try {
                action = ctx.actions.default_launch (entry);
            } catch (Error e) {
                resolve_error = user_error (e);
            }
            play_btn.sensitive = action != null && !ctx.busy && !ctx.launches.is_launching;
            if (resolve_error != null) {
                Widgets.PageChrome.set_icon_label (play_btn, resolve_error);
            } else if (action != null) {
                var label = action.kind == Models.PrefixActionKind.LAUNCH
                    ? _("Play %s").printf (action.label)
                    : action.label;
                Widgets.PageChrome.set_icon_label (play_btn, label);
            } else {
                Widgets.PageChrome.set_icon_label (
                    play_btn,
                    _("No default launch entry is available.")
                );
            }
        }

        private void commit_name () {
            var resolved = Utils.sanitize_user_text (name_label.text);
            if (resolved == "") {
                ctx.show_toast (_("Name cannot be empty."));
            } else if (resolved != entry.display_name ()) {
                entry.name = resolved;
                ctx.prefixes.schedule_save ();
            }
            name_label.text = entry.display_name ();
        }

        private void sync_meta () {
            if (meta_fields == null) return;
            Widgets.PageChrome.clear_children (meta_fields);
            var runner = resolve_runner ();
            meta_fields.append (meta_item (
                _("Runner"),
                _("%s - %s").printf (runner_label (runner), version_label (runner))
            ));
            if (entry.region != "") meta_fields.append (meta_item (_("Region"), entry.region.up ()));
            if (entry.launcher_id != "") {
                meta_fields.append (meta_item (
                    _("Launcher"),
                    Widgets.ManifestUi.launcher_display_name (entry, ctx.launcher_manifests)
                ));
            }
        }

        private Gtk.Widget meta_item (string title, string value) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.hexpand = true;
            box.halign = Gtk.Align.FILL;
            var heading = new Gtk.Label (title);
            heading.add_css_class ("caption-heading");
            heading.add_css_class ("prefix-banner-muted");
            heading.xalign = 0f;
            heading.ellipsize = Pango.EllipsizeMode.END;
            var label = new Gtk.Label (value);
            label.xalign = 0f;
            label.selectable = true;
            label.can_focus = false;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.max_width_chars = 24;
            box.append (heading);
            box.append (label);
            return box;
        }

        private Models.RunnerManifest? resolve_runner () {
            try {
                return Models.RunnerManifest.resolve_for_entry (ctx.runner_manifests, entry);
            } catch (Error e) {
                warning ("Failed to resolve runner for %s: %s", entry.id, e.message);
                return null;
            }
        }

        private string runner_label (Models.RunnerManifest? runner) {
            if (runner != null) return runner.display_label ();
            if (entry.runner_id != "") return entry.runner_id;
            var fallback = Utils.Preferences.instance ().runner_id;
            return fallback != "" ? fallback : _("Not set");
        }

        private string version_label (Models.RunnerManifest? runner) {
            var runner_id = runner != null ? runner.id : entry.runner_id;
            var resolved = Utils.Preferences.resolve_version (runner_id, entry.runner_version);
            if (Models.ToolVersionRef.is_latest (resolved)) return _("Latest");
            if (Models.ToolVersionRef.is_inherit (resolved)) return _("Default");
            return resolved;
        }
    }
}
