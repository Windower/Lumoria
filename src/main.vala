int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.bindtextdomain (Config.APP_ID, Config.LOCALE_DIR);
    Intl.bind_textdomain_codeset (Config.APP_ID, "UTF-8");
    Intl.textdomain (Config.APP_ID);

    if (args.length >= 2 && args[1] == "wrap") {
        return Lumoria.Cli.cmd_wrap (args);
    }
    Lumoria.Utils.register_resources ();

    if (args.length >= 2) {
        var c = args[1];
        if (c == "session-manager") {
            return Lumoria.Cli.cmd_session_manager (args);
        }
        if (c == "version" || c == "help" || c == "--help" || c == "-h"
            || c == "list" || c == "launch" || c == "action" || c == "remove"
            || c == "stop" || c == "update-manifests") {
            return Lumoria.Cli.run (args);
        }
    }

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
