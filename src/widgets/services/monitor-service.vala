namespace Lumoria.Widgets.Services {
    public class MonitorInfo : Object {
        public string connector { get; set; default = ""; }
        public string label { get; set; default = ""; }
    }

    public Gee.ArrayList<MonitorInfo> list_monitors () {
        var result = new Gee.ArrayList<MonitorInfo> ();
        var display = Gdk.Display.get_default ();
        if (display == null) return result;

        var monitors = display.get_monitors ();
        for (uint i = 0; i < monitors.get_n_items (); i++) {
            var monitor = monitors.get_item (i) as Gdk.Monitor;
            if (monitor == null || !monitor.is_valid ()) continue;

            var connector = monitor.get_connector ();
            if (connector == null || connector == "") continue;

            var info = new MonitorInfo ();
            info.connector = connector;
            info.label = connector;
            result.add (info);
        }

        return result;
    }
}
