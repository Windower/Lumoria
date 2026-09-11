namespace Lumoria.Application {

    public interface UiHost : Object {
        public abstract Gtk.Window window { get; }
        public abstract void present_updates (
            Gee.ArrayList<Runtime.PendingUpdate> updates,
            owned Runtime.UpdateDecisionHandler respond
        );
        public abstract void show_dialog (Adw.Dialog dialog);
        public abstract void show_toast (string message);
        public abstract void present_prefix_removal (Models.PrefixEntry entry, bool delete_files);
        public abstract void finish_remove_ui ();
        public abstract void close_after_successful_launch ();

        public abstract void confirm (
            string title,
            string body,
            string confirm_label,
            bool destructive,
            owned Utils.Action on_confirm,
            string cancel_label
        );
        public abstract void present_busy (string status);
        public abstract void set_busy_status (string status);
        public abstract void dismiss_busy ();
        public abstract void present_wine_tools (Models.PrefixEntry entry);
        public abstract void pick_executable (
            string dir,
            owned Widgets.Dialogs.DialogHelpers.PathSelectedCallback on_path,
            owned Widgets.Dialogs.DialogHelpers.ErrorMessageCallback on_error
        );
        public abstract void pick_folder (
            string title,
            string? initial_folder,
            owned Widgets.Dialogs.DialogHelpers.FolderSelectedCallback on_path,
            owned Widgets.Dialogs.DialogHelpers.ErrorMessageCallback on_error
        );
        public abstract void grant_prefix_access (
            Models.PrefixEntry entry,
            owned Widgets.Dialogs.DialogHelpers.GrantFolderCallback on_granted,
            owned Widgets.Dialogs.DialogHelpers.ErrorMessageCallback on_error
        );
        public abstract void open_directory (
            string path,
            owned Widgets.Dialogs.DialogHelpers.ErrorMessageCallback? on_error
        );
        public abstract void open_http_uri (string url);
        public abstract void present_terminal (
            string working_directory,
            Gee.HashMap<string, string> env_vars
        );
        public abstract async void install_dynamic_launcher (
            string label,
            string desktop_id,
            string desktop_entry,
            Bytes icon
        ) throws Error;
    }

    public enum ExclusiveKind {
        NONE,
        INSTALL,
        LAUNCH,
        MANIFEST,
        REMOVE
    }

    public class Context : Object {
        public AppState state { get; private set; }
        public Models.PrefixRegistry registry { get; private set; }
        public Gee.ArrayList<Models.RunnerManifest> runner_manifests { get; private set; }
        public Gee.ArrayList<Models.LauncherManifest> launcher_manifests { get; private set; }

        public PrefixService prefixes { get; private set; }
        public InstallService installs { get; private set; }
        public LaunchService launches { get; private set; }
        public ActionService actions { get; private set; }
        public ScriptService scripts { get; private set; }
        public DynamicLauncherService dynamic_launcher { get; private set; }
        public SteamShortcutService steam { get; private set; }
        public ShortcutService shortcuts { get; private set; }
        public ManifestUpdateService manifest_updates { get; private set; }
        public Runtime.Session runtime { get; private set; }
        public UiHost? ui { get; set; }
        public ExclusiveKind exclusive { get; private set; default = ExclusiveKind.NONE; }
        public signal void exclusive_changed ();
        private bool reload_manifests_pending = false;

        public bool busy {
            get { return exclusive != ExclusiveKind.NONE; }
        }

        public bool try_begin (ExclusiveKind kind) {
            if (kind == ExclusiveKind.NONE) return false;
            if (exclusive != ExclusiveKind.NONE) return false;
            exclusive = kind;
            exclusive_changed ();
            return true;
        }

        public void end_session (ExclusiveKind kind) {
            if (exclusive != kind) return;
            exclusive = ExclusiveKind.NONE;
            exclusive_changed ();
            if (!reload_manifests_pending) return;
            Idle.add (() => {
                reload_manifests ();
                return false;
            });
        }

        public string exclusive_busy_message () {
            switch (exclusive) {
                case ExclusiveKind.INSTALL:
                    return _("An install is already running.");
                case ExclusiveKind.MANIFEST:
                    return _("A manifest update is already running.");
                case ExclusiveKind.REMOVE:
                    return _("A prefix is already being removed.");
                default:
                    return _("A launch is already running.");
            }
        }

        public void present_updates (
            Gee.ArrayList<Runtime.PendingUpdate> updates,
            owned Runtime.UpdateDecisionHandler respond
        ) {
            if (ui != null) {
                ui.present_updates (updates, (owned) respond);
            } else {
                respond (Runtime.UpdateDecision.CANCEL);
            }
        }

        public void show_dialog (Adw.Dialog dialog) {
            if (ui != null) {
                ui.show_dialog (dialog);
            } else {
                dialog.present (null);
            }
        }

        public void show_toast (string message) {
            if (ui != null) ui.show_toast (message);
            else warning ("%s", message);
        }

        public void present_busy (string status) {
            if (ui != null) ui.present_busy (status);
        }

        public void set_busy_status (string status) {
            if (ui != null) ui.set_busy_status (status);
        }

        public void dismiss_busy () {
            if (ui != null) ui.dismiss_busy ();
        }

        public bool ensure_prefix_access (Models.PrefixEntry entry) {
            try {
                return prefixes.request_access (entry);
            } catch (Error e) {
                show_toast (user_error (e));
                return false;
            }
        }

        public void remove_prefix (Models.PrefixEntry entry, bool delete_files) {
            if (ui != null) {
                ui.present_prefix_removal (entry, delete_files);
            } else {
                prefixes.remove (entry, delete_files);
            }
        }

        public Context () throws Error {
            Object ();
            MigrationService.ensure_current ();
            Utils.ensure_prefix_indexer_ignores ();
            bool registry_dirty;
            registry = Models.PrefixRegistry.load (Utils.prefix_registry_path (), out registry_dirty);
            reload_manifests ();
            bool state_touched_registry;
            state = AppState.load (registry, out state_touched_registry);
            registry_dirty |= state_touched_registry;
            state.persist_failed.connect ((message) => show_toast (message));
            Utils.Preferences.instance ().persist_failed.connect ((message) => show_toast (message));
            prefixes = new PrefixService (this);
            prefixes.persist_failed.connect ((message) => show_toast (message));
            if (registry_dirty) prefixes.schedule_save ();
            installs = new InstallService (this);
            actions = new ActionService (this);
            scripts = new ScriptService (this);
            launches = new LaunchService (this);
            dynamic_launcher = new DynamicLauncherService (this);
            steam = new SteamShortcutService (prefixes);
            shortcuts = new ShortcutService (this);
            manifest_updates = new ManifestUpdateService (this);
            runtime = new Runtime.Session ();
            runtime.persist_failed.connect ((message) => show_toast (message));
            runtime.open_handler = open_install_target;
            runtime.bind_registry (registry, () => prefixes.save (false));
            Runtime.attach_session (runtime);
        }

        private void open_install_target (string target) {
            if (ui == null) {
                warning ("No UI available to open %s", target);
                return;
            }
            if (Widgets.Markup.is_http_url (target)) {
                ui.open_http_uri (target);
                return;
            }
            ui.open_directory (target, (message) => {
                warning ("Failed to open %s: %s", target, message);
                show_toast (_("Could not open folder: %s").printf (message));
            });
        }

        public void shutdown () {
            if (installs.active != null) installs.active.cancel ();
            manifest_updates.cancel ();
            runtime.flush_persist ();
            state.flush_persist ();
            Utils.Preferences.instance ().flush_persist ();
            prefixes.flush_persist ();
            Utils.BackgroundJobs.instance ().shutdown ();
        }

        public void reload_manifests () {
            if (busy) {
                reload_manifests_pending = true;
                warning ("Deferring manifest reload until the current operation finishes");
                return;
            }
            reload_manifests_pending = false;
            Models.ManifestRepository.shared ().reload ();
            runner_manifests = Models.ManifestRepository.shared ().host_runners;
            launcher_manifests = Models.ManifestRepository.shared ().launchers;
            Utils.Preferences.instance ().reload_defaults ();
            if (actions != null) actions.invalidate ();
        }

    }
}
