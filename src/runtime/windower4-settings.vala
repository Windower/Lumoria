namespace Lumoria.Runtime {

    public const string WINDOWER_PROFILE_ID_PREFIX = "windower4-profile:";

    public string windower_settings_xml_path (Models.PrefixEntry entry) {
        return Path.build_filename (
            install_prefix_path (entry.path),
            "drive_c", "Windower4", "settings.xml"
        );
    }

    public string windower_profile_entry_id (string profile_name) {
        if (profile_name.strip () == "") {
            return WINDOWER_PROFILE_ID_PREFIX + "default";
        }
        return WINDOWER_PROFILE_ID_PREFIX + Uri.escape_string (profile_name, null, true);
    }

    public string windower_profile_display_label (string profile_name) {
        return profile_name.strip () == "" ? _("Default") : profile_name;
    }

    public string? windower_profile_name_from_entry_id (string entrypoint_id) {
        if (!entrypoint_id.has_prefix (WINDOWER_PROFILE_ID_PREFIX)) return null;
        var suffix = entrypoint_id.substring (WINDOWER_PROFILE_ID_PREFIX.length);
        if (suffix == "" || suffix == "default") return "";
        return Uri.unescape_string (suffix);
    }

    public Gee.ArrayList<Models.Entrypoint> list_windower_profile_entrypoints (
        Models.PrefixEntry entry
    ) {
        var list = new Gee.ArrayList<Models.Entrypoint> ();
        if (entry.launcher_id != "windower4") return list;

        string xml_text;
        try {
            FileUtils.get_contents (windower_settings_xml_path (entry), out xml_text);
        } catch (FileError e) {
            list.add (build_windower_profile_entry (""));
            return list;
        }

        var names = parse_windower_profile_names_from_xml (xml_text);
        foreach (var name in names) {
            list.add (build_windower_profile_entry (name));
        }
        return list;
    }

    private Models.Entrypoint build_windower_profile_entry (string profile_name) {
        var ep = new Models.Entrypoint ();
        ep.id = windower_profile_entry_id (profile_name);
        ep.name = profile_name;
        ep.label = windower_profile_display_label (profile_name);
        ep.exe = "";
        return ep;
    }

    private Gee.ArrayList<string> parse_windower_profile_names_from_xml (string xml_text) {
        var names = new Gee.ArrayList<string> ();
        var seen = new Gee.HashSet<string> ();
        try {
            var r = new Regex ("<profile\\b[^>]*\\bname\\s*=\\s*\"([^\"]*)\"", RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL);
            MatchInfo mi;
            if (r.match (xml_text, 0, out mi)) {
                do {
                    var n = mi.fetch (1);
                    if (!seen.contains (n)) {
                        seen.add (n);
                        names.add (n);
                    }
                } while (mi.next ());
            }
            var r2 = new Regex ("<profile\\b[^>]*\\bname\\s*=\\s*'([^']*)'", RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL);
            MatchInfo mi2;
            if (r2.match (xml_text, 0, out mi2)) {
                do {
                    var n = mi2.fetch (1);
                    if (!seen.contains (n)) {
                        seen.add (n);
                        names.add (n);
                    }
                } while (mi2.next ());
            }
        } catch (Error e) {
            warning ("Windower profile parse: %s", e.message);
        }
        return names;
    }
}
