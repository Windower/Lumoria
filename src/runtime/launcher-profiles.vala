namespace Lumoria.Runtime {

    public const string FEATURE_PROFILES = "profiles";
    public const string LAUNCHER_PROFILE_ID_PREFIX = "windower4-profile:";

    public string launcher_profile_entry_id (string profile_name) {
        if (profile_name.strip () == "") {
            return LAUNCHER_PROFILE_ID_PREFIX + "default";
        }
        return LAUNCHER_PROFILE_ID_PREFIX + Uri.escape_string (profile_name, null, true);
    }

    public string launcher_profile_display_label (string profile_name) {
        return profile_name.strip () == "" ? _("Default") : profile_name;
    }

    public string? launcher_profile_name_from_entry_id (string entrypoint_id) {
        if (!entrypoint_id.has_prefix (LAUNCHER_PROFILE_ID_PREFIX)) return null;
        var suffix = entrypoint_id.substring (LAUNCHER_PROFILE_ID_PREFIX.length);
        if (suffix == "" || suffix == "default") return "";
        return Uri.unescape_string (suffix);
    }

    public Gee.ArrayList<Models.Entrypoint> list_launcher_profile_entrypoints (ManifestContext ctx) {
        var list = new Gee.ArrayList<Models.Entrypoint> ();
        if (ctx.launcher == null || !ctx.launcher.supports_feature (FEATURE_PROFILES)) return list;

        var dir = launcher_dir_from_context (ctx);
        if (dir == "") return list;
        var settings = Path.build_filename (dir, "settings.xml");

        string xml_text;
        try {
            FileUtils.get_contents (settings, out xml_text);
        } catch (FileError e) {
            list.add (build_launcher_profile_entry (""));
            return list;
        }

        foreach (var name in parse_profile_names_from_xml (xml_text)) {
            list.add (build_launcher_profile_entry (name));
        }
        return list;
    }

    private Models.Entrypoint build_launcher_profile_entry (string profile_name) {
        var ep = new Models.Entrypoint ();
        ep.id = launcher_profile_entry_id (profile_name);
        ep.name = profile_name;
        ep.label = launcher_profile_display_label (profile_name);
        ep.exe = "";
        return ep;
    }

    private Gee.ArrayList<string> parse_profile_names_from_xml (string xml_text) {
        var names = new Gee.ArrayList<string> ();
        var seen = new Gee.HashSet<string> ();
        try {
            var r = new Regex (
                "<profile\\b[^>]*\\bname\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')",
                RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL
            );
            MatchInfo mi;
            if (r.match (xml_text, 0, out mi)) {
                do {
                    var n = mi.fetch (1) ?? "";
                    if (n == "") n = mi.fetch (2) ?? "";
                    if (seen.add (n)) names.add (n);
                } while (mi.next ());
            }
        } catch (Error e) {
            warning ("Launcher profile parse: %s", e.message);
        }
        return names;
    }
}
