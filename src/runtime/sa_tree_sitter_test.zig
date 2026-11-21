const std = @import("std");
const builtin = @import("builtin");
const ERR_INVALID = @import("sa_tree_sitter.zig").ERR_INVALID;
const ERR_NOT_FOUND = @import("sa_tree_sitter.zig").ERR_NOT_FOUND;
const OK = @import("sa_tree_sitter.zig").OK;
const anyMissingBelow = @import("sa_tree_sitter.zig").anyMissingBelow;
const readInto = @import("sa_tree_sitter.zig").readInto;
const sa_ts_available = @import("sa_tree_sitter.zig").sa_ts_available;
const sa_ts_node_child = @import("sa_tree_sitter.zig").sa_ts_node_child;
const sa_ts_node_child_by_field = @import("sa_tree_sitter.zig").sa_ts_node_child_by_field;
const sa_ts_node_end_point = @import("sa_tree_sitter.zig").sa_ts_node_end_point;
const sa_ts_node_free = @import("sa_tree_sitter.zig").sa_ts_node_free;
const sa_ts_node_has_error = @import("sa_tree_sitter.zig").sa_ts_node_has_error;
const sa_ts_node_is_missing = @import("sa_tree_sitter.zig").sa_ts_node_is_missing;
const sa_ts_node_is_named = @import("sa_tree_sitter.zig").sa_ts_node_is_named;
const sa_ts_node_named_child_count = @import("sa_tree_sitter.zig").sa_ts_node_named_child_count;
const sa_ts_node_parent = @import("sa_tree_sitter.zig").sa_ts_node_parent;
const sa_ts_node_start_point = @import("sa_tree_sitter.zig").sa_ts_node_start_point;
const sa_ts_node_text = @import("sa_tree_sitter.zig").sa_ts_node_text;
const sa_ts_node_type = @import("sa_tree_sitter.zig").sa_ts_node_type;
const sa_ts_parse = @import("sa_tree_sitter.zig").sa_ts_parse;
const sa_ts_parse_incremental = @import("sa_tree_sitter.zig").sa_ts_parse_incremental;
const sa_ts_parser_free = @import("sa_tree_sitter.zig").sa_ts_parser_free;
const sa_ts_parser_new = @import("sa_tree_sitter.zig").sa_ts_parser_new;
const sa_ts_parser_set_language = @import("sa_tree_sitter.zig").sa_ts_parser_set_language;
const sa_ts_query_capture_count = @import("sa_tree_sitter.zig").sa_ts_query_capture_count;
const sa_ts_query_capture_name = @import("sa_tree_sitter.zig").sa_ts_query_capture_name;
const sa_ts_query_cursor_free = @import("sa_tree_sitter.zig").sa_ts_query_cursor_free;
const sa_ts_query_cursor_new = @import("sa_tree_sitter.zig").sa_ts_query_cursor_new;
const sa_ts_query_exec = @import("sa_tree_sitter.zig").sa_ts_query_exec;
const sa_ts_query_free = @import("sa_tree_sitter.zig").sa_ts_query_free;
const sa_ts_query_match_capture = @import("sa_tree_sitter.zig").sa_ts_query_match_capture;
const sa_ts_query_new = @import("sa_tree_sitter.zig").sa_ts_query_new;
const sa_ts_query_next_match = @import("sa_tree_sitter.zig").sa_ts_query_next_match;
const sa_ts_query_pattern_count = @import("sa_tree_sitter.zig").sa_ts_query_pattern_count;
const sa_ts_tree_edit = @import("sa_tree_sitter.zig").sa_ts_tree_edit;
const sa_ts_tree_free = @import("sa_tree_sitter.zig").sa_ts_tree_free;
const sa_ts_tree_root = @import("sa_tree_sitter.zig").sa_ts_tree_root;
const sa_ts_tree_sexp = @import("sa_tree_sitter.zig").sa_ts_tree_sexp;
const setTsDir = @import("sa_tree_sitter.zig").setTsDir;

test "tree-sitter: parent, points, and node flags" {
    setTsDir();
    var parser: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parser_new(&parser));
    defer _ = sa_ts_parser_free(parser);
    try std.testing.expectEqual(OK, sa_ts_parser_set_language(parser, "typescript".ptr, 10));

    const src = "function add(a: number): number {\n  return a;\n}\n";
    var tree: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parse(parser, src.ptr, src.len, &tree));
    defer _ = sa_ts_tree_free(tree);
    var root: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_tree_root(tree, &root));
    defer _ = sa_ts_node_free(root);

    var flag: u32 = 0;
    var parent: u64 = 999;
    try std.testing.expectEqual(OK, sa_ts_node_parent(root, &parent));
    try std.testing.expectEqual(@as(u64, 0), parent); // root has no parent
    try std.testing.expectEqual(OK, sa_ts_node_is_named(root, &flag));
    try std.testing.expectEqual(@as(u32, 1), flag);
    try std.testing.expectEqual(OK, sa_ts_node_is_missing(root, &flag));
    try std.testing.expectEqual(@as(u32, 0), flag);
    try std.testing.expectEqual(OK, sa_ts_node_has_error(root, &flag));
    try std.testing.expectEqual(@as(u32, 0), flag);

    var fn_node: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child(root, 0, 1, &fn_node));
    try std.testing.expect(fn_node != 0);
    defer _ = sa_ts_node_free(fn_node);

    try std.testing.expectEqual(OK, sa_ts_node_parent(fn_node, &parent));
    try std.testing.expect(parent != 0);
    var buf: [64]u8 = undefined;
    const ptype = try readInto(sa_ts_node_type, parent, &buf);
    try std.testing.expectEqualStrings("program", ptype);
    _ = sa_ts_node_free(parent);

    var row: u32 = 99;
    var col: u32 = 99;
    try std.testing.expectEqual(OK, sa_ts_node_start_point(fn_node, &row, &col));
    try std.testing.expectEqual(@as(u32, 0), row);
    try std.testing.expectEqual(@as(u32, 0), col);
    var name_node: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child_by_field(fn_node, "name".ptr, 4, &name_node));
    try std.testing.expect(name_node != 0);
    defer _ = sa_ts_node_free(name_node);
    try std.testing.expectEqual(OK, sa_ts_node_start_point(name_node, &row, &col));
    try std.testing.expectEqual(@as(u32, 0), row);
    try std.testing.expectEqual(@as(u32, 9), col);
    try std.testing.expectEqual(OK, sa_ts_node_end_point(name_node, &row, &col));
    try std.testing.expectEqual(@as(u32, 0), row);
    try std.testing.expectEqual(@as(u32, 12), col);
    try std.testing.expectEqual(OK, sa_ts_node_end_point(fn_node, &row, &col));
    try std.testing.expectEqual(@as(u32, 2), row);

    // The "function" keyword child is unnamed; named children report 1.
    var kw: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child(fn_node, 0, 0, &kw));
    try std.testing.expect(kw != 0);
    defer _ = sa_ts_node_free(kw);
    try std.testing.expectEqual(OK, sa_ts_node_is_named(kw, &flag));
    try std.testing.expectEqual(@as(u32, 0), flag);

    // Truncated source (unclosed body brace): the tree reports an error
    // and error recovery inserts a MISSING node (pinned grammar, probed).
    const bad = "function add(a: number): number {\n  return a;\n";
    var btree: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parse(parser, bad.ptr, bad.len, &btree));
    defer _ = sa_ts_tree_free(btree);
    var broot: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_tree_root(btree, &broot));
    defer _ = sa_ts_node_free(broot);
    try std.testing.expectEqual(OK, sa_ts_node_has_error(broot, &flag));
    try std.testing.expectEqual(@as(u32, 1), flag);
    try std.testing.expect(anyMissingBelow(broot));
}

test "tree-sitter: query captures function definitions in typescript" {
    setTsDir();
    var parser: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parser_new(&parser));
    defer _ = sa_ts_parser_free(parser);
    try std.testing.expectEqual(OK, sa_ts_parser_set_language(parser, "typescript".ptr, 10));

    const src = "function add(a: number): number { return a; }\nfunction sub(a: number): number { return a; }\n";
    var tree: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parse(parser, src.ptr, src.len, &tree));
    defer _ = sa_ts_tree_free(tree);
    var root: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_tree_root(tree, &root));
    defer _ = sa_ts_node_free(root);

    const query_src = "(function_declaration name: (identifier) @func_name)";
    var query: u64 = 0;
    var err_off: u32 = 7;
    var err_kind: u32 = 7;
    try std.testing.expectEqual(OK, sa_ts_query_new("typescript".ptr, 10, query_src.ptr, query_src.len, &query, &err_off, &err_kind));
    try std.testing.expect(query != 0);
    try std.testing.expectEqual(@as(u32, 0), err_off);
    try std.testing.expectEqual(@as(u32, 0), err_kind);
    defer _ = sa_ts_query_free(query);

    var count: u32 = 0;
    try std.testing.expectEqual(OK, sa_ts_query_pattern_count(query, &count));
    try std.testing.expectEqual(@as(u32, 1), count);
    try std.testing.expectEqual(OK, sa_ts_query_capture_count(query, &count));
    try std.testing.expectEqual(@as(u32, 1), count);
    var buf: [8192]u8 = undefined;
    var name_len: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_query_capture_name(query, 0, &buf, buf.len, &name_len));
    try std.testing.expectEqualStrings("func_name", buf[0..@intCast(name_len)]);

    var cursor: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_query_cursor_new(&cursor));
    defer _ = sa_ts_query_cursor_free(cursor);
    try std.testing.expectEqual(OK, sa_ts_query_exec(cursor, query, root));

    const expected = [_][]const u8{ "add", "sub" };
    var seen: u32 = 0;
    while (true) {
        var has: u32 = 0;
        var pattern: u32 = 0;
        var captures: u32 = 0;
        try std.testing.expectEqual(OK, sa_ts_query_next_match(cursor, &has, &pattern, &captures));
        if (has == 0) break;
        try std.testing.expectEqual(@as(u32, 0), pattern);
        try std.testing.expectEqual(@as(u32, 1), captures);
        var cap_node: u64 = 0;
        var cap_index: u32 = 99;
        try std.testing.expectEqual(OK, sa_ts_query_match_capture(cursor, 0, &cap_node, &cap_index));
        try std.testing.expect(cap_node != 0);
        try std.testing.expectEqual(@as(u32, 0), cap_index);
        const text = try readInto(sa_ts_node_text, cap_node, &buf);
        try std.testing.expectEqualStrings(expected[seen], text);
        _ = sa_ts_node_free(cap_node);
        seen += 1;
    }
    try std.testing.expectEqual(@as(u32, 2), seen);
}

test "tree-sitter: query errors are explicit" {
    setTsDir();
    var query: u64 = 0;
    var err_off: u32 = 0;
    var err_kind: u32 = 0;
    // Unknown node type -> ERR_INVALID, kind 2 (TSQueryErrorNodeType).
    const bad_type = "(missing_node_type) @x";
    try std.testing.expectEqual(ERR_INVALID, sa_ts_query_new("typescript".ptr, 10, bad_type.ptr, bad_type.len, &query, &err_off, &err_kind));
    try std.testing.expectEqual(@as(u64, 0), query);
    try std.testing.expectEqual(@as(u32, 2), err_kind);
    try std.testing.expect(err_off < bad_type.len);
    // Unbalanced pattern -> ERR_INVALID, kind 1 (TSQueryErrorSyntax).
    const bad_syntax = "(((";
    err_kind = 0;
    try std.testing.expectEqual(ERR_INVALID, sa_ts_query_new("typescript".ptr, 10, bad_syntax.ptr, bad_syntax.len, &query, &err_off, &err_kind));
    try std.testing.expectEqual(@as(u32, 1), err_kind);
    // Unknown grammar -> ERR_NOT_FOUND.
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_ts_query_new("cobol".ptr, 5, bad_syntax.ptr, bad_syntax.len, &query, &err_off, &err_kind));
}

test "tree-sitter: incremental edit and reparse" {
    setTsDir();
    var parser: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parser_new(&parser));
    defer _ = sa_ts_parser_free(parser);
    try std.testing.expectEqual(OK, sa_ts_parser_set_language(parser, "typescript".ptr, 10));

    const v1 = "function f(): number { return 1; }\n";
    var tree1: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parse(parser, v1.ptr, v1.len, &tree1));
    defer _ = sa_ts_tree_free(tree1);

    // Replace the literal 1 with 42: bytes [pos, pos+1) become [pos, pos+2).
    // The source is a single line, so point columns equal byte offsets.
    const pos: u32 = @intCast(std.mem.indexOf(u8, v1, "1;").?);
    try std.testing.expectEqual(OK, sa_ts_tree_edit(tree1, pos, pos + 1, pos + 2, 0, pos, 0, pos + 1, 0, pos + 2));

    const v2 = "function f(): number { return 42; }\n";
    var tree2: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parse_incremental(parser, tree1, v2.ptr, v2.len, &tree2));
    defer _ = sa_ts_tree_free(tree2);

    var root2: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_tree_root(tree2, &root2));
    defer _ = sa_ts_node_free(root2);
    var flag: u32 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_has_error(root2, &flag));
    try std.testing.expectEqual(@as(u32, 0), flag);

    var buf: [8192]u8 = undefined;
    var fn_node: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child(root2, 0, 1, &fn_node));
    try std.testing.expect(fn_node != 0);
    defer _ = sa_ts_node_free(fn_node);
    var body: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child_by_field(fn_node, "body".ptr, 4, &body));
    try std.testing.expect(body != 0);
    defer _ = sa_ts_node_free(body);
    var ret: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child(body, 0, 1, &ret));
    try std.testing.expect(ret != 0);
    defer _ = sa_ts_node_free(ret);
    var num: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child(ret, 0, 1, &num));
    try std.testing.expect(num != 0);
    defer _ = sa_ts_node_free(num);
    const num_type = try readInto(sa_ts_node_type, num, &buf);
    try std.testing.expectEqualStrings("number", num_type);
    const num_text = try readInto(sa_ts_node_text, num, &buf);
    try std.testing.expectEqualStrings("42", num_text);

    // The incremental result matches a fresh full parse of the new text.
    var tree3: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parse(parser, v2.ptr, v2.len, &tree3));
    defer _ = sa_ts_tree_free(tree3);
    const sexp_inc = try readInto(sa_ts_tree_sexp, tree2, &buf);
    var buf2: [8192]u8 = undefined;
    const sexp_full = try readInto(sa_ts_tree_sexp, tree3, &buf2);
    try std.testing.expectEqualStrings(sexp_full, sexp_inc);
}

test "tree-sitter: parse javascript, query its function definitions" {
    setTsDir();
    var parser: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parser_new(&parser));
    defer _ = sa_ts_parser_free(parser);
    try std.testing.expectEqual(OK, sa_ts_parser_set_language(parser, "javascript".ptr, 10));

    const src = "function greet(name) { return 'hi ' + name; }\nconst y = greet('x');\n";
    var tree: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parse(parser, src.ptr, src.len, &tree));
    defer _ = sa_ts_tree_free(tree);
    var root: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_tree_root(tree, &root));
    defer _ = sa_ts_node_free(root);
    var buf: [8192]u8 = undefined;
    const root_type = try readInto(sa_ts_node_type, root, &buf);
    try std.testing.expectEqualStrings("program", root_type);
    var flag: u32 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_has_error(root, &flag));
    try std.testing.expectEqual(@as(u32, 0), flag);
    var named: u32 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_named_child_count(root, &named));
    try std.testing.expectEqual(@as(u32, 2), named);

    var fn_node: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child(root, 0, 1, &fn_node));
    try std.testing.expect(fn_node != 0);
    defer _ = sa_ts_node_free(fn_node);
    var name_node: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child_by_field(fn_node, "name".ptr, 4, &name_node));
    try std.testing.expect(name_node != 0);
    defer _ = sa_ts_node_free(name_node);
    const name_text = try readInto(sa_ts_node_text, name_node, &buf);
    try std.testing.expectEqualStrings("greet", name_text);

    const query_src = "(function_declaration name: (identifier) @func_name)";
    var query: u64 = 0;
    var err_off: u32 = 0;
    var err_kind: u32 = 0;
    try std.testing.expectEqual(OK, sa_ts_query_new("javascript".ptr, 10, query_src.ptr, query_src.len, &query, &err_off, &err_kind));
    defer _ = sa_ts_query_free(query);
    var cursor: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_query_cursor_new(&cursor));
    defer _ = sa_ts_query_cursor_free(cursor);
    try std.testing.expectEqual(OK, sa_ts_query_exec(cursor, query, root));
    var has: u32 = 0;
    var pattern: u32 = 0;
    var captures: u32 = 0;
    try std.testing.expectEqual(OK, sa_ts_query_next_match(cursor, &has, &pattern, &captures));
    try std.testing.expectEqual(@as(u32, 1), has);
    try std.testing.expectEqual(@as(u32, 1), captures);
    var cap_node: u64 = 0;
    var cap_index: u32 = 99;
    try std.testing.expectEqual(OK, sa_ts_query_match_capture(cursor, 0, &cap_node, &cap_index));
    try std.testing.expect(cap_node != 0);
    const cap_text = try readInto(sa_ts_node_text, cap_node, &buf);
    try std.testing.expectEqualStrings("greet", cap_text);
    _ = sa_ts_node_free(cap_node);
    try std.testing.expectEqual(OK, sa_ts_query_next_match(cursor, &has, &pattern, &captures));
    try std.testing.expectEqual(@as(u32, 0), has);
}

test "tree-sitter: parse typescript and extract the function name" {
    setTsDir();
    try std.testing.expectEqual(@as(u32, 1), sa_ts_available());
    var parser: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parser_new(&parser));
    defer _ = sa_ts_parser_free(parser);
    try std.testing.expectEqual(OK, sa_ts_parser_set_language(parser, "typescript".ptr, 10));

    const src = "function add(a: number, b: number): number { return a + b; }\nconst x = add(1, 2);\n";
    var tree: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parse(parser, src.ptr, src.len, &tree));
    defer _ = sa_ts_tree_free(tree);

    var buf: [8192]u8 = undefined;
    const sexp = try readInto(sa_ts_tree_sexp, tree, &buf);
    try std.testing.expect(std.mem.indexOf(u8, sexp, "function_declaration") != null);

    var root: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_tree_root(tree, &root));
    defer _ = sa_ts_node_free(root);
    const root_type = try readInto(sa_ts_node_type, root, &buf);
    try std.testing.expectEqualStrings("program", root_type);
    var named: u32 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_named_child_count(root, &named));
    try std.testing.expectEqual(@as(u32, 2), named);

    var fn_node: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child(root, 0, 1, &fn_node));
    try std.testing.expect(fn_node != 0);
    defer _ = sa_ts_node_free(fn_node);
    const fn_type = try readInto(sa_ts_node_type, fn_node, &buf);
    try std.testing.expectEqualStrings("function_declaration", fn_type);

    var name_node: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_node_child_by_field(fn_node, "name".ptr, 4, &name_node));
    try std.testing.expect(name_node != 0);
    defer _ = sa_ts_node_free(name_node);
    const name_text = try readInto(sa_ts_node_text, name_node, &buf);
    try std.testing.expectEqualStrings("add", name_text);
}

test "tree-sitter: unknown grammar and bad names are explicit errors" {
    setTsDir();
    var parser: u64 = 0;
    try std.testing.expectEqual(OK, sa_ts_parser_new(&parser));
    defer _ = sa_ts_parser_free(parser);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_ts_parser_set_language(parser, "cobol".ptr, 5));
    try std.testing.expectEqual(ERR_INVALID, sa_ts_parser_set_language(parser, "bad-name!".ptr, 9));
    // Parse without a language: the core returns NULL -> ERR_INVALID.
    var tree: u64 = 0;
    try std.testing.expectEqual(ERR_INVALID, sa_ts_parse(parser, "x".ptr, 1, &tree));
}
