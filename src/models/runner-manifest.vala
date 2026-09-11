namespace Lumoria.Models {

    private void seed_path_list (Gee.ArrayList<string> list, string fallback) {
        if (list.size == 0 && fallback != "") list.add (fallback);
    }

    public class RunnerPaths : Object {
        public string bin { get; set; default = ""; }
        public Gee.ArrayList<string> bin_paths { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> lib { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> lib_32 { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> lib_64 { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wine_dll { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wine_dll_32 { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wine_dll_64 { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wine_unix { get; owned set; default = new Gee.ArrayList<string> (); }

        public bool is_empty () {
            return bin == ""
                && bin_paths.size == 0
                && lib.size == 0 && lib_32.size == 0 && lib_64.size == 0
                && wine_dll.size == 0 && wine_dll_32.size == 0 && wine_dll_64.size == 0
                && wine_unix.size == 0;
        }

        /* Variant paths fill in only the fields they name; everything else comes from the runner. */
        public static RunnerPaths overlay (RunnerPaths runner, RunnerPaths variant) {
            var p = new RunnerPaths ();
            p.bin = variant.bin != "" ? variant.bin : runner.bin;
            p.bin_paths = variant.bin_paths.size > 0 ? variant.bin_paths : runner.bin_paths;
            p.lib = variant.lib.size > 0 ? variant.lib : runner.lib;
            p.lib_32 = variant.lib_32.size > 0 ? variant.lib_32 : runner.lib_32;
            p.lib_64 = variant.lib_64.size > 0 ? variant.lib_64 : runner.lib_64;
            p.wine_dll = variant.wine_dll.size > 0 ? variant.wine_dll : runner.wine_dll;
            p.wine_dll_32 = variant.wine_dll_32.size > 0 ? variant.wine_dll_32 : runner.wine_dll_32;
            p.wine_dll_64 = variant.wine_dll_64.size > 0 ? variant.wine_dll_64 : runner.wine_dll_64;
            p.wine_unix = variant.wine_unix.size > 0 ? variant.wine_unix : runner.wine_unix;
            return p;
        }

        public static RunnerPaths from_json (Json.Object obj) throws Error {
            var p = new RunnerPaths ();
            p.bin = json_string (obj, "bin");
            p.bin_paths = json_string_array (obj, "bin_paths");
            seed_path_list (p.bin_paths, p.bin);
            p.lib = json_string_array (obj, "lib");
            p.lib_32 = json_string_array (obj, "lib_32");
            p.lib_64 = json_string_array (obj, "lib_64");
            p.wine_dll = json_string_array (obj, "wine_dll");
            p.wine_dll_32 = json_string_array (obj, "wine_dll_32");
            p.wine_dll_64 = json_string_array (obj, "wine_dll_64");
            p.wine_unix = json_string_array (obj, "wine_unix");
            return p;
        }
    }

    public class RunnerSupportFile : Object {
        public string id { get; set; default = ""; }
        public Gee.ArrayList<string> src {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public Gee.ArrayList<string> src_dirs {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public Gee.ArrayList<string> files {
            get; owned set; default = new Gee.ArrayList<string> ();
        }
        public string mode { get; set; default = ""; }
        public string dst { get; set; default = ""; }
        public string dst_dir { get; set; default = ""; }
        public WhenClause? when { get; set; default = null; }

        public static RunnerSupportFile from_json (Json.Object obj) throws Error {
            var f = new RunnerSupportFile ();
            f.id = json_string (obj, "id");
            f.src = json_string_array (obj, "src");
            f.src_dirs = json_string_array (obj, "src_dirs");
            f.files = json_string_array (obj, "files");
            f.mode = json_string (obj, "mode");
            f.dst = json_string (obj, "dst");
            f.dst_dir = json_string (obj, "dst_dir");
            f.when = WhenClause.from_json_member (obj);
            return f;
        }
    }

    /* Wine binary layout shared by a runner and its variants; a variant falls back to the runner's values. */
    public abstract class RunnerBinaries : BaseManifest {
        public bool is_default { get; set; default = false; }
        public string asset_regex { get; set; default = ""; }
        public string checksum_regex { get; set; default = ""; }
        public string wine_bin { get; set; default = ""; }
        public string wineserver { get; set; default = ""; }
        public Gee.ArrayList<string> wine_bins { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wineservers { get; owned set; default = new Gee.ArrayList<string> (); }
        public string wine_arch { get; set; default = ""; }
        public bool sandbox_supported { get; set; default = true; }
        public RunnerPaths paths { get; owned set; default = new RunnerPaths (); }

        /* The requested arch when it names one, else this runner's; win64 when neither does. */
        public string effective_arch (string requested) {
            var arch = Utils.normalize_wine_arch (requested);
            if (arch == "") arch = Utils.normalize_wine_arch (wine_arch);
            return arch == "win32" ? "win32" : "win64";
        }

        protected void parse_binaries (Json.Object obj, bool arch_required) throws Error {
            parse_base (obj);
            is_default = json_bool (obj, "default");
            asset_regex = json_string (obj, "asset_regex");
            checksum_regex = json_string (obj, "checksum_regex");
            wine_bin = json_string (obj, "wine_bin");
            wineserver = json_string (obj, "wineserver");
            wine_bins = json_string_array (obj, "wine_bins");
            wineservers = json_string_array (obj, "wineservers");
            seed_path_list (wine_bins, wine_bin);
            seed_path_list (wineservers, wineserver);
            wine_arch = RunnerManifest.parse_arch (obj, "wine_arch", arch_required);
            sandbox_supported = json_bool (obj, "sandbox_supported", true);
            paths = json_parse_member<RunnerPaths> (obj, "paths", RunnerPaths.from_json) ?? new RunnerPaths ();
        }
    }

    public class RunnerVariant : RunnerBinaries {
        public string binary_kind { get; set; default = "wow64"; }

        public static RunnerVariant from_json (Json.Object obj) throws Error {
            var v = new RunnerVariant ();
            v.parse_binaries (obj, false);
            v.binary_kind = json_string (obj, "binary_kind", "wow64");
            return v;
        }
    }

    public class RunnerManifest : RunnerBinaries {
        public Gee.ArrayList<string> host_arches { get; owned set; default = new Gee.ArrayList<string> (); }
        public string github_repo { get; set; default = ""; }
        public string version_dir { get; set; default = ""; }
        public Gee.ArrayList<RunnerSupportFile> support_files {
            get; owned set; default = new Gee.ArrayList<RunnerSupportFile> ();
        }
        public Gee.ArrayList<RunnerVariant> variants { get; owned set; default = new Gee.ArrayList<RunnerVariant> (); }

        public bool supports_host_arch (string host_arch) {
            if (host_arches.size == 0) return true;
            foreach (var arch in host_arches) {
                if (arch.strip () == host_arch) return true;
            }
            return false;
        }

        public Gee.ArrayList<RunnerVariant> selectable_variants (bool sandboxed) {
            var result = new Gee.ArrayList<RunnerVariant> ();
            var source = variants;
            if (source.size == 0) {
                var implicit = new RunnerVariant ();
                implicit.id = id;
                implicit.label = name;
                implicit.is_default = true;
                source = new Gee.ArrayList<RunnerVariant> ();
                source.add (implicit);
            }
            foreach (var v in source) {
                var merged = merge_variant (v);
                if (!sandboxed || variant_supported_in_sandbox (merged)) result.add (merged);
            }
            return result;
        }

        public bool supported_in_environment (bool sandboxed) {
            return !sandboxed || selectable_variants (true).size > 0;
        }

        public RunnerVariant effective_variant (string variant_id) throws Error {
            var allowed = selectable_variants (Utils.EnvironmentInfo.is_sandboxed ());
            if (allowed.size == 0) {
                throw new LumoriaError.INVALID_MANIFEST (
                    "Runner '%s' has no variants compatible with this environment",
                    id
                );
            }

            if (variants.size == 0) {
                if (variant_id != "" && variant_id != id) {
                    throw new LumoriaError.INVALID_MANIFEST (
                        "Runner '%s' does not support variant '%s'",
                        id, variant_id
                    );
                }
                return allowed[0];
            }

            RunnerVariant? selected = null;
            if (variant_id != "") {
                foreach (var v in allowed) {
                    if (v.id == variant_id) { selected = v; break; }
                }
                if (selected == null) {
                    throw new LumoriaError.INVALID_MANIFEST (
                        "Runner '%s': unknown or unsupported variant '%s'",
                        id, variant_id
                    );
                }
            }
            if (selected == null) {
                foreach (var v in allowed) {
                    if (v.is_default) { selected = v; break; }
                }
            }
            if (selected == null) {
                throw new LumoriaError.INVALID_MANIFEST (
                    "Runner '%s' has no default variant configured",
                    id
                );
            }

            return selected;
        }

        private RunnerVariant merge_variant (RunnerVariant v) {
            var m = new RunnerVariant ();
            m.id = v.id;
            m.name = v.name;
            m.label = v.label;
            m.is_default = v.is_default;
            m.asset_regex = v.asset_regex != "" ? v.asset_regex : asset_regex;
            m.checksum_regex = v.checksum_regex != "" ? v.checksum_regex : checksum_regex;
            m.wine_bin = v.wine_bin != "" ? v.wine_bin : wine_bin;
            m.wineserver = v.wineserver != "" ? v.wineserver : wineserver;
            m.wine_bins.add_all (v.wine_bins.size > 0 ? v.wine_bins : wine_bins);
            m.wineservers.add_all (v.wineservers.size > 0 ? v.wineservers : wineservers);
            seed_path_list (m.wine_bins, m.wine_bin);
            seed_path_list (m.wineservers, m.wineserver);
            m.wine_arch = v.wine_arch != "" ? v.wine_arch : wine_arch;
            m.binary_kind = v.binary_kind;
            m.sandbox_supported = sandbox_supported && v.sandbox_supported;
            m.paths = RunnerPaths.overlay (paths, v.paths);
            m.support = v.support != SupportStatus.SUPPORTED ? v.support : support;
            m.messages = v.messages.empty ? messages : v.messages;
            m.links = v.links.empty ? links : v.links;
            m.recommended = recommended || v.recommended;
            copy_unique_strings (skip_versions, m.skip_versions);
            copy_unique_strings (v.skip_versions, m.skip_versions);
            copy_unique_strings (features, m.features);
            copy_unique_strings (v.features, m.features);
            return m;
        }

        private static void copy_unique_strings (Gee.ArrayList<string> source, Gee.ArrayList<string> target) {
            foreach (var value in source) {
                var normalized = value.strip ();
                if (normalized == "") continue;
                bool exists = false;
                foreach (var current in target) {
                    if (current.strip () == normalized) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) target.add (normalized);
            }
        }

        private bool variant_supported_in_sandbox (RunnerVariant v) {
            if (!v.sandbox_supported) return false;
            if (v.binary_kind.down ().strip () == "legacy32") return false;
            return Utils.normalize_wine_arch (v.wine_arch) == "win64";
        }

        internal static string parse_arch (Json.Object obj, string key, bool required) throws Error {
            var a = json_string (obj, key).down ().strip ();
            if (a == "win64" || a == "win32" || (a == "" && !required)) return a;
            if (a == "") {
                throw new LumoriaError.INVALID_MANIFEST (_("Missing required '%s' in runner manifest").printf (key));
            }
            throw new LumoriaError.INVALID_MANIFEST (
                _("Invalid '%s' value '%s' (expected win64 or win32)").printf (key, a)
            );
        }

        public string resolve_version_dir (string tag) {
            var pattern = version_dir.strip ();
            if (pattern == "") return tag;
            if (!("(" in pattern)) return pattern;
            try {
                var re = new Regex (pattern);
                MatchInfo match;
                if (re.match (tag, 0, out match) && match.get_match_count () >= 2) {
                    var sub = match.fetch (1);
                    if (sub != null && sub != "") return sub;
                }
            } catch (RegexError e) {
                warning ("Failed to apply version_dir regex: %s", e.message);
            }
            return tag;
        }

        public static RunnerManifest from_json (Json.Object obj) throws Error {
            var s = new RunnerManifest ();
            s.parse_binaries (obj, true);
            s.github_repo = json_string (obj, "github_repo");
            s.version_dir = json_string (obj, "version_dir");
            s.host_arches = json_string_array (obj, "host_arches");
            s.support_files = parse_json_array<RunnerSupportFile> (obj, "support_files", RunnerSupportFile.from_json);
            s.variants = parse_json_array<RunnerVariant> (obj, "variants", RunnerVariant.from_json);
            return s;
        }

        public static string current_host_arch () {
#if ARCH_X86
            return "x86";
#elif ARCH_ARM64
            return "arm64";
#else
            return "x86_64";
#endif
        }

        public static Gee.ArrayList<RunnerManifest> load_all_from_resource () throws Error {
            return load_named_manifests_from_resource<RunnerManifest> (
                "runners",
                ManifestStore.list_ids ("runners"),
                "runner",
                (obj, _) => {
                    return RunnerManifest.from_json (obj);
                }
            );
        }

        public static Gee.ArrayList<RunnerManifest> filter_for_host (Gee.ArrayList<RunnerManifest> specs) {
            var host = current_host_arch ();
            var filtered = new Gee.ArrayList<RunnerManifest> ();
            foreach (var spec in specs) {
                if (spec.supports_host_arch (host)) filtered.add (spec);
            }
            return filtered;
        }

        public static Gee.ArrayList<RunnerManifest> filter_for_environment (Gee.ArrayList<RunnerManifest> specs, bool sandboxed) {
            var filtered = new Gee.ArrayList<RunnerManifest> ();
            foreach (var spec in specs) {
                if (spec.supported_in_environment (sandboxed)) filtered.add (spec);
            }
            return filtered;
        }

        /* Falls back to the default (then first) host runner when the entry's runner is unknown. */
        public static RunnerManifest resolve_for_entry (Gee.ArrayList<RunnerManifest> specs, PrefixEntry entry) throws Error {
            var id = Utils.Preferences.effective_runner_id (entry.runner_id);
            var spec = Models.find_by_id<RunnerManifest> (specs, id)
                ?? Models.find_by_id<RunnerManifest> (ManifestRepository.shared ().all_runners, id);
            if (spec != null) return spec;
            foreach (var s in specs) {
                if (s.is_default) return s;
            }
            if (specs.size > 0) return specs[0];
            throw new LumoriaError.INVALID_MANIFEST (_("No runner manifests available"));
        }
    }
}
