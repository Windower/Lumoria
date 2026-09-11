namespace Lumoria.Models {

    public enum WhenClauseKind {
        MATCH,
        MANIFEST_FIELD_MATCH,
        FILE_EXISTS,
        ALL,
        ANY,
        NOT
    }

    public enum WhenMatchOp {
        EQ,
        NEQ,
        CONTAINS,
        STARTSWITH,
        ENDSWITH,
        GT,
        GTE,
        LT,
        LTE;

        public static WhenMatchOp parse (string op) throws Error {
            switch (op) {
                case "eq": return EQ;
                case "neq": return NEQ;
                case "contains": return CONTAINS;
                case "startswith": return STARTSWITH;
                case "endswith": return ENDSWITH;
                case "gt": return GT;
                case "gte": return GTE;
                case "lt": return LT;
                case "lte": return LTE;
                default:
                    throw new LumoriaError.INVALID_MANIFEST ("Invalid when match operator: %s", op);
            }
        }

        public unowned string id () {
            switch (this) {
                case NEQ: return "neq";
                case CONTAINS: return "contains";
                case STARTSWITH: return "startswith";
                case ENDSWITH: return "endswith";
                case GT: return "gt";
                case GTE: return "gte";
                case LT: return "lt";
                case LTE: return "lte";
                default: return "eq";
            }
        }
    }

    public class WhenClause : Object {
        public WhenClauseKind kind { get; set; }
        public string key { get; set; default = ""; }
        public string value { get; set; default = ""; }
        public WhenMatchOp op { get; set; default = WhenMatchOp.EQ; }
        public Gee.ArrayList<WhenClause> children { get; owned set; default = new Gee.ArrayList<WhenClause> (); }

        public WhenClause (WhenClauseKind kind) {
            this.kind = kind;
        }

        public WhenClause copy () {
            var clause = new WhenClause (kind);
            clause.key = key;
            clause.value = value;
            clause.op = op;
            foreach (var child in children) clause.children.add (child.copy ());
            return clause;
        }

        public bool evaluate (Gee.HashMap<string, string> vars, Gee.HashMap<string, string>? item_fields = null) {
            switch (kind) {
                case WhenClauseKind.MATCH:
                    return vars.has_key (key) && apply_op (vars[key]);
                case WhenClauseKind.MANIFEST_FIELD_MATCH:
                    return item_fields != null && item_fields.has_key (key) && apply_op (item_fields[key]);
                case WhenClauseKind.FILE_EXISTS:
                    return FileUtils.test (Utils.expand_vars (value, vars), FileTest.EXISTS);
                case WhenClauseKind.ALL:
                    foreach (var child in children) {
                        if (!child.evaluate (vars, item_fields)) return false;
                    }
                    return true;
                case WhenClauseKind.ANY:
                    foreach (var child in children) {
                        if (child.evaluate (vars, item_fields)) return true;
                    }
                    return false;
                case WhenClauseKind.NOT:
                    return children.size > 0 && !children[0].evaluate (vars, item_fields);
                default:
                    return false;
            }
        }

        private bool apply_op (string actual) {
            switch (op) {
                case WhenMatchOp.EQ:         return actual == value;
                case WhenMatchOp.NEQ:        return actual != value;
                case WhenMatchOp.CONTAINS:   return actual.contains (value);
                case WhenMatchOp.STARTSWITH: return actual.has_prefix (value);
                case WhenMatchOp.ENDSWITH:   return actual.has_suffix (value);
                case WhenMatchOp.GT:
                case WhenMatchOp.GTE:
                case WhenMatchOp.LT:
                case WhenMatchOp.LTE: {
                    double a = 0, b = 0;
                    if (!double.try_parse (actual, out a) || !double.try_parse (value, out b)) return false;
                    switch (op) {
                        case WhenMatchOp.GT:  return a > b;
                        case WhenMatchOp.GTE: return a >= b;
                        case WhenMatchOp.LT:  return a < b;
                        default:              return a <= b;
                    }
                }
                default: return actual == value;
            }
        }

        public static WhenClause? from_json_member (Json.Object obj) throws Error {
            return json_parse_member<WhenClause> (obj, "when", parse_node);
        }

        public static WhenClause parse_node (Json.Object obj) throws Error {
            var members = obj.get_members ();
            if (members.length () != 1) {
                throw new LumoriaError.INVALID_MANIFEST ("Invalid when clause: expected exactly one operator");
            }

            var op = members.nth_data (0);
            switch (op) {
                case "all":
                    var all_clause = new WhenClause (WhenClauseKind.ALL);
                    parse_array_children (obj.get_array_member ("all"), all_clause);
                    return all_clause;
                case "any":
                    var any_clause = new WhenClause (WhenClauseKind.ANY);
                    parse_array_children (obj.get_array_member ("any"), any_clause);
                    return any_clause;
                case "not":
                    var not_clause = new WhenClause (WhenClauseKind.NOT);
                    var inner = obj.get_member ("not").get_object ();
                    not_clause.children.add (parse_node (inner));
                    return not_clause;
                case "file_exists":
                    var file_clause = new WhenClause (WhenClauseKind.FILE_EXISTS);
                    file_clause.value = obj.get_string_member ("file_exists");
                    return file_clause;
                case "var":
                    return parse_var_match (obj.get_object_member ("var"));
                case "manifestField":
                    return parse_manifest_field_match (obj.get_object_member ("manifestField"));
                default:
                    throw new LumoriaError.INVALID_MANIFEST ("Invalid when clause operator: %s", op);
            }
        }

        private static WhenClause parse_var_match (Json.Object obj) throws Error {
            return parse_match_map (
                obj,
                WhenClauseKind.MATCH,
                "Invalid when var clause: expected at least one variable match"
            );
        }

        private static WhenClause parse_manifest_field_match (Json.Object obj) throws Error {
            return parse_match_map (
                obj,
                WhenClauseKind.MANIFEST_FIELD_MATCH,
                "Invalid manifestField clause: expected at least one field match"
            );
        }

        private static WhenClause parse_match_map (
            Json.Object obj,
            WhenClauseKind kind,
            string empty_error
        ) throws Error {
            var members = obj.get_members ();
            if (members.length () == 0) {
                throw new LumoriaError.INVALID_MANIFEST ("%s", empty_error);
            }
            var clause = new WhenClause (WhenClauseKind.ALL);
            foreach (unowned string k in members) {
                var child = new WhenClause (kind);
                child.key = k;
                parse_match_value (obj.get_member (k), child);
                clause.children.add (child);
            }
            if (clause.children.size == 1) return clause.children[0];
            return clause;
        }

        private static void parse_array_children (Json.Array arr, WhenClause parent) throws Error {
            for (uint i = 0; i < arr.get_length (); i++) {
                parent.children.add (parse_node (arr.get_object_element (i)));
            }
        }

        private static void parse_match_value (Json.Node node, WhenClause clause) throws Error {
            if (node.get_node_type () == Json.NodeType.OBJECT) {
                var op_obj = node.get_object ();
                var ops = op_obj.get_members ();
                if (ops.length () == 1) {
                    var key = ops.nth_data (0);
                    clause.op = WhenMatchOp.parse (key);
                    clause.value = json_scalar_to_string (op_obj.get_member (key)) ?? "";
                    return;
                }
            }
            clause.op = WhenMatchOp.EQ;
            clause.value = json_scalar_to_string (node) ?? "";
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            switch (kind) {
                case WhenClauseKind.ALL:
                    if (uniform_match_children (WhenClauseKind.MATCH)) {
                        obj.set_object_member ("var", match_map ());
                    } else if (uniform_match_children (WhenClauseKind.MANIFEST_FIELD_MATCH)) {
                        obj.set_object_member ("manifestField", match_map ());
                    } else {
                        obj.set_array_member ("all", children_array ());
                    }
                    break;
                case WhenClauseKind.ANY:
                    obj.set_array_member ("any", children_array ());
                    break;
                case WhenClauseKind.NOT:
                    if (children.size > 0) {
                        obj.set_object_member ("not", children[0].to_json ());
                    }
                    break;
                case WhenClauseKind.FILE_EXISTS:
                    obj.set_string_member ("file_exists", value);
                    break;
                case WhenClauseKind.MATCH:
                    obj.set_object_member ("var", single_match_map ());
                    break;
                case WhenClauseKind.MANIFEST_FIELD_MATCH:
                    obj.set_object_member ("manifestField", single_match_map ());
                    break;
            }
            return obj;
        }

        private bool uniform_match_children (WhenClauseKind expected) {
            if (children.size == 0) return false;
            foreach (var child in children) {
                if (child.kind != expected) return false;
            }
            return true;
        }

        private Json.Object match_map () {
            var map = new Json.Object ();
            foreach (var child in children) {
                map.set_member (child.key, child.match_value_node ());
            }
            return map;
        }

        private Json.Object single_match_map () {
            var map = new Json.Object ();
            map.set_member (key, match_value_node ());
            return map;
        }

        private Json.Array children_array () {
            var arr = new Json.Array ();
            foreach (var child in children) arr.add_object_element (child.to_json ());
            return arr;
        }

        private Json.Node match_value_node () {
            if (op == WhenMatchOp.EQ) {
                var node = new Json.Node (Json.NodeType.VALUE);
                node.set_string (value);
                return node;
            }
            var op_obj = new Json.Object ();
            op_obj.set_string_member (op.id (), value);
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.take_object (op_obj);
            return node;
        }
    }

}
