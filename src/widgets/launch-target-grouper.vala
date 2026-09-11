namespace Lumoria.Widgets {

    public class LaunchTargetGrouper : Object {
        public static void split_launcher (
            Gee.Iterable<Runtime.LaunchTarget> targets,
            Gee.ArrayList<Runtime.LaunchTarget> main,
            Gee.ArrayList<Runtime.LaunchTarget> profiles
        ) {
            foreach (var target in targets) {
                if (target.section == Runtime.LaunchTargetSection.LAUNCHER_PROFILES) {
                    profiles.add (target);
                } else {
                    main.add (target);
                }
            }
        }

        public static bool is_launcher_section (Runtime.LaunchTarget target) {
            return target.section == Runtime.LaunchTargetSection.LAUNCHER
                || target.section == Runtime.LaunchTargetSection.LAUNCHER_PROFILES;
        }
    }
}
