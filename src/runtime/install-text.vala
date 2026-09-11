namespace Lumoria.Runtime {

    internal void run_text_upsert_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var vars = ctx.vars;
        var dst = ctx.require_managed_path (step.dst);
        Utils.ensure_dir (Path.get_dirname (dst));

        string existing = "";
        if (FileUtils.test (dst, FileTest.EXISTS)) {
            FileUtils.get_contents (dst, out existing);
        }

        var content = ctx.expand (step.content);
        if (content == "") {
            content = build_text_block_from_args (step.args, vars);
        }
        if (content == "") {
            throw new LumoriaError.INVALID_MANIFEST ("text_upsert requires content or args");
        }

        var normalized_existing = normalize_text_block (existing);
        var normalized_content = normalize_text_block (content);
        if (normalized_existing.contains (normalized_content)) {
            ctx.logger.typed (LogType.SKIP, "text already exists in %s".printf (dst));
            verify_step_paths (ctx);
            return;
        }

        var newline = detect_newline_style (existing);
        string output;
        if (step.mode == "append") {
            output = ensure_trailing_newline (normalize_newlines (existing), newline)
                + ensure_trailing_newline (normalize_newlines (content), newline);
        } else {
            output = ensure_trailing_newline (normalize_newlines (content), newline)
                + ensure_trailing_newline (normalize_newlines (existing), newline);
        }

        Utils.write_text_atomic (dst, output);
        ctx.logger.typed (LogType.COPY, "upserted text in %s".printf (dst));
        verify_step_paths (ctx);
    }

    internal string build_text_block_from_args (
        Gee.ArrayList<string> args,
        Gee.HashMap<string, string> vars
    ) {
        var lines = new Gee.ArrayList<string> ();
        foreach (var arg in args) {
            lines.add (Utils.expand_vars (arg, vars));
        }
        if (lines.size == 0) return "";
        return string.joinv ("\n", Utils.strv (lines));
    }

    internal string normalize_text_block (string value) {
        return normalize_newlines (value).strip ();
    }

    internal string normalize_newlines (string value) {
        return value.replace ("\r\n", "\n").replace ("\r", "\n");
    }

    internal string detect_newline_style (string existing) {
        if (existing.contains ("\r\n")) return "\r\n";
        if (existing.contains ("\n")) return "\n";
        return "\r\n";
    }

    internal string ensure_trailing_newline (string value, string newline) {
        if (value == "") return "";
        var normalized = normalize_newlines (value);
        if (!normalized.has_suffix ("\n")) normalized += "\n";
        return normalized.replace ("\n", newline);
    }

    internal void run_xml_upsert_step (InstallStepContext ctx) throws Error {
        var step = ctx.step;
        var vars = ctx.vars;
        var dst = ctx.require_managed_path (step.dst);
        var root_name = step.root.strip ();
        var element_name = step.element.strip ();
        if (root_name == "" || element_name == "") {
            throw new LumoriaError.INVALID_MANIFEST ("xml_upsert requires root and element");
        }

        Utils.ensure_dir (Path.get_dirname (dst));

        Xml.Doc* doc = null;
        try {
            Xml.Node* root;
            if (FileUtils.test (dst, FileTest.EXISTS)) {
                doc = Xml.Parser.read_file (dst, null, Xml.ParserOption.NOBLANKS);
                if (doc == null) {
                    throw new LumoriaError.FAILED ("Failed to parse XML file: %s", dst);
                }
                root = doc->get_root_element ();
                if (root == null) {
                    throw new LumoriaError.FAILED ("XML file has no root element: %s", dst);
                }
                if (root->name != root_name) {
                    throw new LumoriaError.FAILED ("XML root mismatch in %s: expected %s, got %s", dst, root_name, root->name);
                }
            } else {
                doc = new Xml.Doc ("1.0");
                root = doc->new_node (null, root_name);
                doc->set_root_element (root);
            }

            var target = find_matching_xml_child (root, element_name, step.match, vars);
            if (target == null) {
                if (!step.create_if_missing) {
                    throw new LumoriaError.FAILED ("XML element not found: %s", element_name);
                }
                target = root->new_child (null, element_name, null);
                foreach (var entry in step.match.entries) {
                    target->set_prop (entry.key, Utils.expand_vars (entry.value, vars));
                }
            }

            foreach (var entry in step.children.entries) {
                var value = Utils.expand_vars (entry.value, vars);
                var child = find_xml_element_child (target, entry.key);
                if (child == null) {
                    target->new_text_child (null, entry.key, value);
                } else if (step.overwrite_existing) {
                    child->set_content (value);
                }
            }

            if (step.content != "") {
                merge_xml_fragment (target, Utils.expand_vars (step.content, vars), step.overwrite_existing);
            }

            if (doc->save_format_file (dst, 1) < 0) {
                throw new LumoriaError.FAILED ("Failed to write XML file: %s", dst);
            }
            ctx.logger.typed (LogType.COPY, "updated XML %s".printf (dst));
            verify_step_paths (ctx);
        } finally {
            if (doc != null) delete doc;
        }
    }

    internal Xml.Node* find_matching_xml_child (
        Xml.Node* root,
        string element_name,
        Gee.HashMap<string, string> match,
        Gee.HashMap<string, string> vars
    ) {
        for (Xml.Node* child = root->children; child != null; child = child->next) {
            if (child->type != Xml.ElementType.ELEMENT_NODE || child->name != element_name) continue;
            bool matched = true;
            foreach (var entry in match.entries) {
                var expected = Utils.expand_vars (entry.value, vars);
                var actual = child->get_prop (entry.key);
                if (actual == null || actual != expected) {
                    matched = false;
                    break;
                }
            }
            if (matched) return child;
        }
        return null;
    }

    internal Xml.Node* find_xml_element_child (Xml.Node* parent, string name) {
        for (Xml.Node* child = parent->children; child != null; child = child->next) {
            if (child->type == Xml.ElementType.ELEMENT_NODE && child->name == name) return child;
        }
        return null;
    }

    /*
     * Merges an XML fragment into target. Elements are matched by name and attributes;
     * containers recurse, an element repeated in the fragment is treated as a set (added
     * unless an identical one exists), and a single leaf is updated only with overwrite.
     */
    private void merge_xml_fragment (Xml.Node* target, string fragment, bool overwrite) throws Error {
        var wrapped = "<fragment>%s</fragment>".printf (fragment);
        Xml.Doc* doc = Xml.Parser.read_memory (wrapped, wrapped.length, null, null, Xml.ParserOption.NOBLANKS);
        if (doc == null) {
            throw new LumoriaError.INVALID_MANIFEST ("xml_upsert content is not well-formed XML");
        }
        try {
            merge_xml_children (target, doc->get_root_element (), overwrite);
        } finally {
            delete doc;
        }
    }

    private void merge_xml_children (Xml.Node* target, Xml.Node* source, bool overwrite) {
        for (Xml.Node* item = source->children; item != null; item = item->next) {
            if (item->type != Xml.ElementType.ELEMENT_NODE) continue;
            var repeated = count_xml_siblings (source, item) > 1;
            var existing = find_xml_like_child (target, item, repeated);
            if (existing == null) {
                target->add_child (item->doc_copy (target->doc, 1));
            } else if (has_xml_element_children (item)) {
                merge_xml_children (existing, item, overwrite);
            } else if (!repeated && overwrite) {
                existing->set_content (item->get_content ());
            }
        }
    }

    private int count_xml_siblings (Xml.Node* parent, Xml.Node* proto) {
        var count = 0;
        for (Xml.Node* child = parent->children; child != null; child = child->next) {
            if (xml_shape_matches (child, proto)) count++;
        }
        return count;
    }

    private Xml.Node* find_xml_like_child (Xml.Node* parent, Xml.Node* proto, bool match_text) {
        for (Xml.Node* child = parent->children; child != null; child = child->next) {
            if (!xml_shape_matches (child, proto)) continue;
            if (!match_text || child->get_content () == proto->get_content ()) return child;
        }
        return null;
    }

    private bool xml_shape_matches (Xml.Node* node, Xml.Node* proto) {
        if (node->type != Xml.ElementType.ELEMENT_NODE || node->name != proto->name) return false;
        for (Xml.Attr* attr = proto->properties; attr != null; attr = attr->next) {
            if (node->get_prop (attr->name) != proto->get_prop (attr->name)) return false;
        }
        return true;
    }

    private bool has_xml_element_children (Xml.Node* node) {
        for (Xml.Node* child = node->children; child != null; child = child->next) {
            if (child->type == Xml.ElementType.ELEMENT_NODE) return true;
        }
        return false;
    }

}
