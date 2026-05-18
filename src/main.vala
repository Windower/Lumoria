int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.bindtextdomain (Config.APP_ID, Config.LOCALE_DIR);
    Intl.bind_textdomain_codeset (Config.APP_ID, "UTF-8");
    Intl.textdomain (Config.APP_ID);

    if (args.length >= 2) {
        var c = args[1];
        if (c == "wrap") {
            return Lumoria.Cli.cmd_wrap (args);
        }
        if (c == "version" || c == "help" || c == "--help" || c == "-h" || c == "list" || c == "launch") {
            Lumoria.Utils.register_resources ();
            return Lumoria.Cli.run (args);
        }
    }

    Lumoria.Utils.register_resources ();

    bool flathub_screenshots = false;
    var filtered = new string[0];
    foreach (var a in args) {
        if (a == "--flathub-screenshots") {
            flathub_screenshots = true;
            continue;
        }
        filtered += a;
    }

    var app = new Lumoria.Widgets.Application ();
    app.flathub_screenshots = flathub_screenshots;
    return app.run (filtered);
}
