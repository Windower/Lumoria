namespace Lumoria.Models {

    public class RunnerPaths : Object {
        public string bin { get; set; default = ""; }
        public Gee.ArrayList<string> lib { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> lib_32 { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> lib_64 { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wine_dll { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wine_dll_32 { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wine_dll_64 { get; owned set; default = new Gee.ArrayList<string> (); }
        public Gee.ArrayList<string> wine_unix { get; owned set; default = new Gee.ArrayList<string> (); }

        public bool is_empty () {
            return bin == ""
                && lib.size == 0 && lib_32.size == 0 && lib_64.size == 0
                && wine_dll.size == 0 && wine_dll_32.size == 0 && wine_dll_64.size == 0
                && wine_unix.size == 0;
        }

        public static RunnerPaths from_json (Json.Object obj) {
            var p = new RunnerPaths ();
            p.bin = json_string (obj, "bin");
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

    public class RunnerVariant : BaseSpec {
        public bool is_default { get; set; default = false; }
        public string asset_regex { get; set; default = ""; }
        public string checksum_regex { get; set; default = ""; }
        public string wine_bin { get; set; default = ""; }
        public string wineserver { get; set; default = ""; }
        public string wine_arch { get; set; default = ""; }
        public string binary_kind { get; set; default = "wow64"; }
        public bool sandbox_supported { get; set; default = true; }
        public RunnerPaths paths { get; owned set; default = new RunnerPaths (); }

        public static RunnerVariant from_json (Json.Object obj) throws Error {
            var v = new RunnerVariant ();
            v.parse_base (obj);
            v.is_default = json_bool (obj, "default");
            v.asset_regex = json_string (obj, "asset_regex");
            v.checksum_regex = json_string (obj, "checksum_regex");
            v.wine_bin = json_string (obj, "wine_bin");
            v.wineserver = json_string (obj, "wineserver");
            var arch = json_string (obj, "wine_arch").down ().strip ();
            if (arch != "" && arch != "win64" && arch != "win32") {
                throw new IOError.FAILED (
                    "Invalid 'wine_arch' value '%s' in variant '%s' (expected win64 or win32)",
                    arch, v.id
                );
            }
            v.wine_arch = arch;
            v.binary_kind = json_string (obj, "binary_kind");
            if (v.binary_kind == "") v.binary_kind = "wow64";
            if (obj.has_member ("sandbox_supported")) {
                v.sandbox_supported = json_bool (obj, "sandbox_supported");
            }
            if (obj.has_member ("paths")) {
                v.paths = RunnerPaths.from_json (obj.get_object_member ("paths"));
            }
            return v;
        }
    }

    public class RunnerSpec : BaseSpec {
        public Gee.ArrayList<string> host_arches { get; owned set; default = new Gee.ArrayList<string> (); }
        public string github_repo { get; set; default = ""; }
        public string asset_regex { get; set; default = ""; }
        public string checksum_regex { get; set; default = ""; }
        public string wine_bin { get; set; default = ""; }
        public string wineserver { get; set; default = ""; }
        public string wine_arch { get; set; default = ""; }
        public string version_dir { get; set; default = ""; }
        public bool is_default { get; set; default = false; }
        public RunnerPaths paths { get; owned set; default = new RunnerPaths (); }
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
            if (variants.size == 0) {
                var base_variant = new RunnerVariant ();
                base_variant.id = id;
                base_variant.label = name;
                base_variant.is_default = true;
                base_variant.asset_regex = asset_regex;
                base_variant.checksum_regex = checksum_regex;
                base_variant.wine_bin = wine_bin;
                base_variant.wineserver = wineserver;
                base_variant.wine_arch = wine_arch;
                base_variant.binary_kind = "wow64";
                base_variant.sandbox_supported = true;
                base_variant.paths = paths;
                if (!sandboxed || variant_supported_in_sandbox (base_variant)) {
                    result.add (base_variant);
                }
                return result;
            }
            foreach (var v in variants) {
                var merged = merge_variant (v);
                if (!sandboxed || variant_supported_in_sandbox (merged)) {
                    result.add (merged);
                }
            }
            return result;
        }

        public RunnerVariant effective_variant (string variant_id) throws Error {
            var allowed = selectable_variants (Utils.is_sandboxed ());
            if (allowed.size == 0) {
                throw new IOError.FAILED (
                    "Runner '%s' has no variants compatible with this environment",
                    id
                );
            }

            if (variants.size == 0) {
                if (variant_id != "" && variant_id != id) {
                    throw new IOError.FAILED (
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
                    throw new IOError.FAILED (
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
                throw new IOError.FAILED (
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
            m.wine_arch = v.wine_arch != "" ? v.wine_arch : wine_arch;
            m.binary_kind = v.binary_kind;
            m.sandbox_supported = v.sandbox_supported;
            m.paths = v.paths.is_empty () ? paths : v.paths;
            return m;
        }

        private bool variant_supported_in_sandbox (RunnerVariant v) {
            if (!v.sandbox_supported) return false;
            if (v.binary_kind.down ().strip () == "legacy32") return false;
            return Utils.normalize_wine_arch (v.wine_arch) == "win64";
        }

        private static string parse_arch_strict (Json.Object obj, string key) throws Error {
            var a = json_string (obj, key).down ().strip ();
            if (a == "win64" || a == "win32") return a;
            if (a == "") {
                throw new IOError.FAILED ("Missing required '%s' in runner spec", key);
            }
            throw new IOError.FAILED ("Invalid '%s' value '%s' (expected win64 or win32)", key, a);
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

        public static RunnerSpec from_json (Json.Object obj) throws Error {
            var s = new RunnerSpec ();
            s.parse_base (obj);
            s.github_repo = json_string (obj, "github_repo");
            s.asset_regex = json_string (obj, "asset_regex");
            s.checksum_regex = json_string (obj, "checksum_regex");
            s.wine_bin = json_string (obj, "wine_bin");
            s.wineserver = json_string (obj, "wineserver");
            s.wine_arch = parse_arch_strict (obj, "wine_arch");
            s.version_dir = json_string (obj, "version_dir");
            s.is_default = json_bool (obj, "default");
            s.host_arches = json_string_array (obj, "host_arches");
            if (obj.has_member ("paths")) {
                s.paths = RunnerPaths.from_json (obj.get_object_member ("paths"));
            }
            s.variants = parse_json_array<RunnerVariant> (obj, "variants", (o) => RunnerVariant.from_json (o));
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

        public static Gee.ArrayList<RunnerSpec> load_all_from_resource () {
            return load_named_specs_from_resource<RunnerSpec> (
                "runners",
                list_spec_ids_from_resource ("runners"),
                "runner",
                (obj, _) => {
                    return RunnerSpec.from_json (obj);
                }
            );
        }

        public static Gee.ArrayList<RunnerSpec> filter_for_host (Gee.ArrayList<RunnerSpec> specs) {
            var host = current_host_arch ();
            var filtered = new Gee.ArrayList<RunnerSpec> ();
            foreach (var spec in specs) {
                if (spec.supports_host_arch (host)) filtered.add (spec);
            }
            return filtered;
        }

        public static RunnerSpec? find_by_id (Gee.ArrayList<RunnerSpec> specs, string id) {
            foreach (var spec in specs) {
                if (spec.id == id) return spec;
            }
            return null;
        }

        public static RunnerSpec find_or_default (Gee.ArrayList<RunnerSpec> specs, string id) throws Error {
            var spec = find_by_id (specs, id);
            if (spec != null) return spec;
            foreach (var s in specs) {
                if (s.is_default) return s;
            }
            if (specs.size > 0) return specs[0];
            throw new IOError.FAILED ("No runner specs available");
        }
    }
}
