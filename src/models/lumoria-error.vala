namespace Lumoria {

    public errordomain LumoriaError {
        FAILED,
        NOT_FOUND,
        PERMISSION,
        INVALID_MANIFEST,
        BUSY,
        INTERNAL
    }

    public static string user_error (Error e) {
        if (e is IOError.CANCELLED) {
            return _("The operation was cancelled.");
        }
        if (e is LumoriaError) {
            switch (e.code) {
                case LumoriaError.NOT_FOUND:
                    return e.message != "" ? e.message : _("The requested item was not found.");
                case LumoriaError.PERMISSION:
                    return e.message != "" ? e.message : _("Permission is required to continue.");
                case LumoriaError.INVALID_MANIFEST:
                    return e.message != "" ? e.message : _("A manifest is invalid or missing.");
                case LumoriaError.BUSY:
                    return e.message != "" ? e.message : _("Another operation is already running.");
                case LumoriaError.INTERNAL:
                    return _("Something went wrong. See the log for details.");
                default:
                    break;
            }
        }
        if (e.message != "") return e.message;
        return _("Something went wrong. See the log for details.");
    }
}
