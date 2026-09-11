namespace Lumoria.Models {

    public class ManifestRepository : Object {
        private static ManifestRepository? shared_instance;
        private string validation_error = "";

        public Gee.ArrayList<InstallerManifest> installers { get; private set; default = new Gee.ArrayList<InstallerManifest> (); }
        public Gee.ArrayList<RunnerManifest> runners { get; private set; default = new Gee.ArrayList<RunnerManifest> (); }
        public Gee.ArrayList<RunnerManifest> all_runners { get; private set; default = new Gee.ArrayList<RunnerManifest> (); }
        /* Catalog runners that can run on this machine's architecture and inside/outside the sandbox. */
        public Gee.ArrayList<RunnerManifest> host_runners { get; private set; default = new Gee.ArrayList<RunnerManifest> (); }
        public Gee.ArrayList<LauncherManifest> launchers { get; private set; default = new Gee.ArrayList<LauncherManifest> (); }
        public Gee.HashMap<string, RedistManifest> all_redists { get; private set; default = new Gee.HashMap<string, RedistManifest> (); }
        public Gee.ArrayList<RedistManifest> redists { get; private set; default = new Gee.ArrayList<RedistManifest> (); }
        public Gee.ArrayList<ComponentManifest> components { get; private set; default = new Gee.ArrayList<ComponentManifest> (); }
        public Gee.ArrayList<ComponentManifest> all_components { get; private set; default = new Gee.ArrayList<ComponentManifest> (); }
        private CatalogManifest catalog = new CatalogManifest ();

        public ManifestRepository () {
            reload ();
        }

        public static ManifestRepository shared () {
            if (shared_instance == null) shared_instance = new ManifestRepository ();
            return shared_instance;
        }

        public void reload () {
            try {
                var next_catalog = CatalogManifest.load ();
                var next_installers = InstallerManifest.load_all_from_resource ();
                var next_all_runners = RunnerManifest.load_all_from_resource ();
                var next_runners = CatalogManifest.select<RunnerManifest> (
                    next_all_runners,
                    next_catalog.runners,
                    (spec) => spec.id
                );
                var next_launchers = InstallerManifest.order_launchers (
                    next_installers,
                    LauncherManifest.load_all_from_resource ()
                );
                var next_all_redists = RedistManifest.load_all_from_resource ();
                var loaded_redists = new Gee.ArrayList<RedistManifest> ();
                foreach (var spec in next_all_redists.values) {
                    loaded_redists.add (spec);
                }
                var next_redists = CatalogManifest.select<RedistManifest> (
                    loaded_redists,
                    next_catalog.redists,
                    (spec) => spec.id
                );
                var next_all_components = ComponentManifest.load_all_from_resource ();
                var next_components = CatalogManifest.select<ComponentManifest> (
                    next_all_components,
                    next_catalog.components,
                    (spec) => spec.id
                );
                validate_catalog (
                    next_catalog,
                    next_installers,
                    next_all_runners,
                    next_all_redists,
                    next_all_components,
                    next_launchers
                );
                catalog = next_catalog;
                installers = next_installers;
                all_runners = next_all_runners;
                runners = next_runners;
                host_runners = RunnerManifest.filter_for_environment (
                    RunnerManifest.filter_for_host (next_runners), Utils.EnvironmentInfo.is_sandboxed ()
                );
                launchers = next_launchers;
                all_redists = next_all_redists;
                redists = next_redists;
                all_components = next_all_components;
                components = next_components;
                validation_error = "";
            } catch (Error e) {
                validation_error = e.message;
                critical ("Invalid manifest repository: %s", e.message);
            }
        }

        public string default_installer_id () {
            return catalog.default_installer;
        }

        public InstallerManifest? installer (string id) {
            return find_by_id<InstallerManifest> (installers, id);
        }

        public InstallerManifest require_installer (string id) throws Error {
            require_valid ();
            var spec = installer (id);
            if (spec == null) {
                throw new LumoriaError.INVALID_MANIFEST (_("Unknown installer manifest: %s").printf (id));
            }
            return spec;
        }

        public void require_valid () throws Error {
            if (validation_error != "") {
                throw new LumoriaError.INVALID_MANIFEST (_("Invalid manifest repository: %s").printf (validation_error));
            }
        }

        private void validate_catalog (
            CatalogManifest catalog,
            Gee.ArrayList<InstallerManifest> next_installers,
            Gee.ArrayList<RunnerManifest> next_all_runners,
            Gee.HashMap<string, RedistManifest> next_all_redists,
            Gee.ArrayList<ComponentManifest> next_all_components,
            Gee.ArrayList<LauncherManifest> next_launchers
        ) throws Error {
            require_catalog_ids (catalog.runners, ids_of (next_all_runners), "runner");
            require_catalog_ids (catalog.components, ids_of (next_all_components), "component");
            require_catalog_ids (catalog.redists, next_all_redists.keys, "redist");

            if (next_installers.size == 0) {
                throw new LumoriaError.INVALID_MANIFEST ("No installer manifests were loaded");
            }

            var installer_ids = new Gee.HashSet<string> ();
            foreach (var installer in next_installers) {
                if (installer.id == "") {
                    throw new LumoriaError.INVALID_MANIFEST ("Installer manifest has no id");
                }
                if (!installer_ids.add (installer.id)) {
                    throw new LumoriaError.INVALID_MANIFEST ("Duplicate installer id: %s", installer.id);
                }

                var region_ids = new Gee.HashSet<string> ();
                foreach (var region in installer.regions) {
                    if (region.id == "" || !region_ids.add (region.id)) {
                        throw new LumoriaError.INVALID_MANIFEST (
                            "Installer '%s' has an empty or duplicate region id", installer.id
                        );
                    }
                }
                if (installer.default_region_id != ""
                    && !region_ids.contains (installer.default_region_id)) {
                    throw new LumoriaError.INVALID_MANIFEST (
                        "Installer '%s' has unknown default region '%s'",
                        installer.id,
                        installer.default_region_id
                    );
                }

                var launcher_ids = new Gee.HashSet<string> ();
                foreach (var launcher_id in installer.launcher_ids) {
                    if (launcher_id == "" || !launcher_ids.add (launcher_id)) {
                        throw new LumoriaError.INVALID_MANIFEST (
                            "Installer '%s' has an empty or duplicate launcher reference", installer.id
                        );
                    }
                    if (find_by_id<LauncherManifest> (next_launchers, launcher_id) == null) {
                        throw new LumoriaError.INVALID_MANIFEST (
                            "Installer '%s' references unknown launcher '%s'", installer.id, launcher_id
                        );
                    }
                }
                if (installer.default_launcher_id != ""
                    && !installer.launcher_ids.contains (installer.default_launcher_id)) {
                    throw new LumoriaError.INVALID_MANIFEST (
                        "Installer '%s' has unsupported default launcher '%s'",
                        installer.id,
                        installer.default_launcher_id
                    );
                }

                var patch_ids = new Gee.HashSet<string> ();
                foreach (var patch in installer.patches) {
                    if (patch.id == "" || !patch_ids.add (patch.id)) {
                        throw new LumoriaError.INVALID_MANIFEST (
                            "Installer '%s' has an empty or duplicate patch id", installer.id
                        );
                    }
                    if (patch.patch_type != "pe_characteristic"
                        || patch.setting != InstallerPatch.SETTING_LARGE_ADDRESS_AWARE
                        || patch.flag != "IMAGE_FILE_LARGE_ADDRESS_AWARE"
                        || patch.target.strip () == "") {
                        throw new LumoriaError.INVALID_MANIFEST (
                            "Installer '%s' has unsupported patch '%s'", installer.id, patch.id
                        );
                    }
                }

                foreach (var redist_id in installer.redists) {
                    if (!next_all_redists.has_key (redist_id)) {
                        throw new LumoriaError.INVALID_MANIFEST (
                            "Installer '%s' references unknown redist '%s'", installer.id, redist_id
                        );
                    }
                }
            }

            if (catalog.default_installer == "" || !installer_ids.contains (catalog.default_installer)) {
                throw new LumoriaError.INVALID_MANIFEST (
                    "Catalog default installer '%s' has no manifest", catalog.default_installer
                );
            }

            var runner_ids = ids_of (next_all_runners);
            var defaults = DefaultsManifest.load ();
            require_known_id (defaults.host.runner_id, runner_ids, "Defaults runner");
            require_known_id (defaults.sandbox.runner_id, runner_ids, "Defaults sandbox runner");

            var component_ids = new Gee.HashSet<string> ();
            foreach (var component in next_all_components) {
                if (component.id == "" || !component_ids.add (component.id)) {
                    throw new LumoriaError.INVALID_MANIFEST ("Component has an empty or duplicate id");
                }
                foreach (var installer_id in component.installer_ids) {
                    if (!installer_ids.contains (installer_id)) {
                        throw new LumoriaError.INVALID_MANIFEST (
                            "Component '%s' references unknown installer '%s'",
                            component.id,
                            installer_id
                        );
                    }
                }
            }
        }

        private static Gee.HashSet<string> ids_of<T> (Gee.Iterable<T> items) {
            var ids = new Gee.HashSet<string> ();
            foreach (var item in items) {
                var record = item as IdentifiedRecord;
                if (record != null && record.id != "") ids.add (record.id);
            }
            return ids;
        }

        private static void require_catalog_ids (
            Gee.List<string> catalog_ids,
            Gee.Collection<string> available,
            string kind
        ) throws Error {
            foreach (var id in catalog_ids) {
                if (id != "" && !available.contains (id)) {
                    throw new LumoriaError.INVALID_MANIFEST ("Catalog %s '%s' has no manifest", kind, id);
                }
            }
        }

        private static void require_known_id (
            string id,
            Gee.Collection<string> available,
            string label
        ) throws Error {
            if (id == "" || !available.contains (id)) {
                throw new LumoriaError.INVALID_MANIFEST ("%s '%s' has no manifest", label, id);
            }
        }
    }
}
