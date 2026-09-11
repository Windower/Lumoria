namespace Lumoria.Models {

    public class EnvRule : Object {
        public Gee.HashMap<string, string> vars { get; owned set; default = new Gee.HashMap<string, string> (); }
        public WhenClause? when { get; set; default = null; }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            obj.set_object_member ("vars", json_string_map_object (vars));
            if (when != null) {
                obj.set_object_member ("when", when.to_json ());
            }
            return obj;
        }

        public static EnvRule from_json (Json.Object obj) throws Error {
            var r = new EnvRule ();
            r.vars = json_string_map (obj, "vars");
            r.when = WhenClause.from_json_member (obj);
            return r;
        }

        public EnvRule copy () {
            var r = new EnvRule ();
            r.vars.set_all (vars);
            r.when = when != null ? when.copy () : null;
            return r;
        }
    }

    public static void parse_variable_definitions (
        Json.Object obj,
        string key,
        out Gee.HashMap<string, string> variables,
        out Gee.ArrayList<EnvRule> variable_rules
    ) throws Error {
        var parsed_variables = new Gee.HashMap<string, string> ();
        var parsed_rules = new Gee.ArrayList<EnvRule> ();
        if (!obj.has_member (key)) {
            variables = parsed_variables;
            variable_rules = parsed_rules;
            return;
        }

        var map = obj.get_object_member (key);
        var members = map.get_members ();
        foreach (unowned string name in members) {
            var node = map.get_member (name);
            switch (node.get_node_type ()) {
                case Json.NodeType.OBJECT:
                    parse_variable_object (name, node.get_object (), parsed_variables, parsed_rules);
                    break;
                case Json.NodeType.ARRAY:
                    parse_variable_array (name, node.get_array (), parsed_variables, parsed_rules);
                    break;
                default:
                    parsed_variables[name] = json_scalar_to_string (node) ?? "";
                    break;
            }
        }
        variables = parsed_variables;
        variable_rules = parsed_rules;
    }

    private static void parse_variable_object (
        string name,
        Json.Object obj,
        Gee.HashMap<string, string> variables,
        Gee.ArrayList<EnvRule> variable_rules
    ) throws Error {
        if (obj.has_member ("default")) {
            variables[name] = obj.get_string_member ("default");
        }
        if (obj.has_member ("value")) {
            append_variable_rule_or_default (name, obj, variables, variable_rules);
        }
        if (obj.has_member ("rules")) {
            parse_variable_array (name, obj.get_array_member ("rules"), variables, variable_rules);
        }
    }

    private static void parse_variable_array (
        string name,
        Json.Array arr,
        Gee.HashMap<string, string> variables,
        Gee.ArrayList<EnvRule> variable_rules
    ) throws Error {
        if (arr.get_length () > 0 && json_array_of_strings (arr)) {
            variables[name] = json_join_lines (arr);
            return;
        }
        for (uint i = 0; i < arr.get_length (); i++) {
            append_variable_rule_or_default (
                name,
                arr.get_object_element (i),
                variables,
                variable_rules
            );
        }
    }

    private static void append_variable_rule_or_default (
        string name,
        Json.Object obj,
        Gee.HashMap<string, string> variables,
        Gee.ArrayList<EnvRule> variable_rules
    ) throws Error {
        if (!obj.has_member ("value")) return;
        if (!obj.has_member ("when")) {
            variables[name] = obj.get_string_member ("value");
            return;
        }

        var rule = new EnvRule ();
        rule.vars[name] = obj.get_string_member ("value");
        rule.when = WhenClause.from_json_member (obj);
        variable_rules.add (rule);
    }

}
