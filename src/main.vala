int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.bindtextdomain (Config.APP_ID, Config.LOCALE_DIR);
    Intl.bind_textdomain_codeset (Config.APP_ID, "UTF-8");
    Intl.textdomain (Config.APP_ID);

    var resource_path = Lumoria.Utils.resolve_resource_path ();
    if (resource_path != null) {
        try {
            var resource = Resource.load (resource_path);
            GLib.resources_register (resource);
        } catch (Error e) {
            warning ("Failed to load resource bundle: %s", e.message);
        }
    }

    var app = new Lumoria.Widgets.Application ();
    return app.run (args);
}
