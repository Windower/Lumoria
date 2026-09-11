namespace Lumoria.Runtime {

    internal void install_fonts_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var fonts_dir = ctx.require_managed_path (step.dst);
        Utils.ensure_dir (fonts_dir);

        var tmp_dir = DirUtils.make_tmp ("fonts-XXXXXX");
        int packages_processed = 0;
        int fonts_copied_total = 0;

        try {
          foreach (var raw_path in step.args) {
            packages_processed++;
            var exe_path = ctx.expand (raw_path);
            var exe_lower = exe_path.down ();

            if (exe_lower.has_suffix (".ttf") || exe_lower.has_suffix (".ttc")) {
                copy_font_file (exe_path, fonts_dir, ctx.logger);
                fonts_copied_total++;
                continue;
            }

            var basename = Path.get_basename (exe_path).replace (".exe", "");
            var extract_dir = Path.build_filename (tmp_dir, basename);
            Utils.ensure_dir (extract_dir);

            ctx.logger.typed (LogType.FONTS, "extracting %s".printf (Path.get_basename (exe_path)));
            Utils.extract_archive (exe_path, extract_dir, {}, ctx.cancellable);

            var found = collect_font_files (extract_dir);
            if (found.size == 0) {
                throw new LumoriaError.FAILED ("No font files found in extracted package: %s", exe_path);
            }
            foreach (var src in found) {
                copy_font_file (src, fonts_dir, ctx.logger);
                fonts_copied_total++;
            }
          }
          register_fonts_into_prefix (fonts_dir, ctx);
        } finally {
            ctx.remove_tree (tmp_dir);
        }
        ctx.logger.typed (LogType.FONTS, "summary: packages=%d, fonts_copied=%d".printf (packages_processed, fonts_copied_total));
        ctx.logger.typed (LogType.FONTS, "installed to %s".printf (fonts_dir));
    }

    internal void register_fonts_into_prefix (string fonts_dir, InstallStepContext ctx) throws Error {
        var step = ctx.step;
        int declared = step.font_registrations.size;
        if (declared == 0) return;

        var faces = new Gee.HashMap<string, string> ();
        foreach (var raw in step.font_registrations) {
            string file;
            string face;
            parse_font_pair (raw, "registration", out file, out face);
            if (!FileUtils.test (Path.build_filename (fonts_dir, file), FileTest.EXISTS)) {
                throw new LumoriaError.INVALID_MANIFEST ("Declared font registration missing: %s", file);
            }
            var lower = file.down ();
            var suffix = (lower.has_suffix (".ttf") || lower.has_suffix (".ttc")) ? " (TrueType)" : "";
            faces[face + suffix] = file;
        }

        import_registry (ctx.paths, ctx.env, registry_for_keys ({
            "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts",
            "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Fonts"
        }, faces), ctx.logger, ctx.cancellable);

        ctx.logger.typed (LogType.FONTS, "registered %d/%d font(s)".printf (faces.size, declared));
    }

    /* The same string values written under every key in keys. */
    private RegFile registry_for_keys (string[] keys, Gee.Map<string, string> values) {
        var reg = new RegFile ();
        foreach (var key in keys) {
            reg.key (key);
            foreach (var entry in values.entries) reg.str (entry.key, entry.value);
        }
        return reg;
    }

    internal Gee.ArrayList<string> collect_font_files (string dir_path) throws Error {
        var results = new Gee.ArrayList<string> ();
        try {
            var dir = Dir.open (dir_path);
            string? name;
            while ((name = dir.read_name ()) != null) {
                var path = Path.build_filename (dir_path, name);
                var lower = name.down ();
                if (lower.has_suffix (".ttf") || lower.has_suffix (".ttc")) {
                    results.add (path);
                } else if (FileUtils.test (path, FileTest.IS_DIR)) {
                    results.add_all (collect_font_files (path));
                }
            }
        } catch (Error e) {
            throw new LumoriaError.FAILED ("Failed to scan font directory %s: %s", dir_path, e.message);
        }
        return results;
    }

    internal void install_font_replacements (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        if (step.font_registrations.size == 0) return;

        var replacements = new Gee.HashMap<string, string> ();
        foreach (var raw in step.font_registrations) {
            string alias;
            string target;
            parse_font_pair (raw, "replacement", out alias, out target);
            replacements[alias] = target;
        }

        import_registry (ctx.paths, ctx.env, registry_for_keys ({
            "HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements",
            "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes"
        }, replacements), ctx.logger, ctx.cancellable);
        ctx.logger.typed (LogType.FONTS, "registered %d font replacement(s)".printf (replacements.size));
    }

    private void parse_font_pair (string raw, string kind, out string left, out string right) throws Error {
        var parts = raw.split ("|", 2);
        if (parts.length != 2) {
            throw new LumoriaError.INVALID_MANIFEST ("Invalid font %s '%s'", kind, raw);
        }
        left = parts[0].strip ();
        right = parts[1].strip ();
        if (left == "" || right == "") {
            throw new LumoriaError.INVALID_MANIFEST ("Invalid font %s '%s'", kind, raw);
        }
    }

    private void copy_font_file (string src, string fonts_dir, RuntimeLog logger) throws Error {
        var dst = Path.build_filename (fonts_dir, Path.get_basename (src).down ());
        Utils.copy_path (src, dst);
        logger.typed (LogType.FONTS, "copied %s".printf (dst));
    }
}
