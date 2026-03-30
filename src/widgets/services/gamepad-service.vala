namespace Lumoria.Widgets.Services {

    public enum GamepadAction {
        NAVIGATE_UP,
        NAVIGATE_DOWN,
        NAVIGATE_LEFT,
        NAVIGATE_RIGHT,
        TAB_PREV,
        TAB_NEXT,
        ACTIVATE,
        BACK,
        GLOBAL_PLAY,
        OPEN_PREFERENCES
    }

    public class GamepadService : Object {
        private static GamepadService? _instance = null;

        public signal void action_pressed (GamepadAction action);

        private Manette.Monitor monitor;
        private Gee.ArrayList<Manette.Device> devices;

        private const double STICK_DEADZONE = 0.7;
        private const uint STICK_REPEAT_INITIAL_MS = 500;
        private const uint STICK_REPEAT_MS = 200;

        private GamepadAction? stick_held_action = null;
        private uint stick_repeat_source = 0;
        private double stick_x = 0.0;
        private double stick_y = 0.0;

        private GamepadService () {
            devices = new Gee.ArrayList<Manette.Device> ();
            monitor = new Manette.Monitor ();

            var iter = monitor.iterate ();
            Manette.Device? dev;
            while (iter.next (out dev)) {
                if (dev != null) bind_device (dev);
            }

            monitor.device_connected.connect (bind_device);
            monitor.device_disconnected.connect (unbind_device);
        }

        public static GamepadService instance () {
            if (_instance == null) {
                _instance = new GamepadService ();
            }
            return _instance;
        }

        private void bind_device (Manette.Device device) {
            if (devices.contains (device)) return;
            devices.add (device);
            device.button_press_event.connect (on_button_press);
            device.hat_axis_event.connect (on_hat_axis);
            device.absolute_axis_event.connect (on_absolute_axis);
        }

        private void unbind_device (Manette.Device device) {
            device.button_press_event.disconnect (on_button_press);
            device.hat_axis_event.disconnect (on_hat_axis);
            device.absolute_axis_event.disconnect (on_absolute_axis);
            devices.remove (device);
        }

        private void on_button_press (Manette.Event event) {
            uint16 button;
            if (!event.get_button (out button)) return;

            var action = map_button (button);
            if (action != null) {
                action_pressed ((GamepadAction) action);
            }
        }

        private void on_hat_axis (Manette.Event event) {
            uint16 axis;
            int8 value;
            if (!event.get_hat (out axis, out value)) return;
            if (value == 0) return;

            if (axis == 0 || axis == 16) {
                action_pressed (value < 0 ? GamepadAction.NAVIGATE_LEFT : GamepadAction.NAVIGATE_RIGHT);
            } else if (axis == 1 || axis == 17) {
                action_pressed (value < 0 ? GamepadAction.NAVIGATE_UP : GamepadAction.NAVIGATE_DOWN);
            }
        }

        private GamepadAction? dominant_stick_action () {
            double ax = Math.fabs (stick_x);
            double ay = Math.fabs (stick_y);

            if (ay >= ax) {
                if (stick_y < -STICK_DEADZONE) return GamepadAction.NAVIGATE_UP;
                if (stick_y > STICK_DEADZONE) return GamepadAction.NAVIGATE_DOWN;
            } else {
                if (stick_x < -STICK_DEADZONE) return GamepadAction.NAVIGATE_LEFT;
                if (stick_x > STICK_DEADZONE) return GamepadAction.NAVIGATE_RIGHT;
            }
            return null;
        }

        private void on_absolute_axis (Manette.Event event) {
            uint16 axis;
            double value;
            if (!event.get_absolute (out axis, out value)) return;

            if (axis == 0 || axis == 6) stick_x = value;
            else if (axis == 1 || axis == 7) stick_y = value;
            else return;

            var action = dominant_stick_action ();

            if (action == stick_held_action) return;

            cancel_stick_repeat ();

            if (action == null) {
                stick_held_action = null;
                return;
            }

            stick_held_action = action;
            action_pressed ((GamepadAction) action);

            stick_repeat_source = Timeout.add (STICK_REPEAT_INITIAL_MS, () => {
                stick_repeat_source = Timeout.add (STICK_REPEAT_MS, () => {
                    if (stick_held_action != null) {
                        action_pressed ((GamepadAction) stick_held_action);
                    }
                    return stick_held_action != null;
                });
                return false;
            });
        }

        private void cancel_stick_repeat () {
            if (stick_repeat_source != 0) {
                Source.remove (stick_repeat_source);
                stick_repeat_source = 0;
            }
        }

        private GamepadAction? map_button (uint16 button) {
            switch (button) {
                case 0: case 304: return GamepadAction.ACTIVATE;
                case 1: case 305: return GamepadAction.BACK;
                case 6: case 314: return GamepadAction.OPEN_PREFERENCES;
                case 11: case 544: return GamepadAction.NAVIGATE_UP;
                case 12: case 545: return GamepadAction.NAVIGATE_DOWN;
                case 13: case 546: return GamepadAction.NAVIGATE_LEFT;
                case 14: case 547: return GamepadAction.NAVIGATE_RIGHT;
                case 4: case 310: return GamepadAction.TAB_PREV;
                case 5: case 311: return GamepadAction.TAB_NEXT;
                case 7: case 315: return GamepadAction.GLOBAL_PLAY;
                default: return null;
            }
        }
    }
}
