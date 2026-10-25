//! sa_std tree-sitter (P0-4): incremental-parsing AST core for code
//! analysis (CXU saVmTreeSitter / code graph). The tree-sitter core is
//! a C library; it and each grammar (one C symbol tree_sitter_<lang>)
//! are loaded with dlopen — nothing is linked statically.
//!
//! Library resolution (explicit, no silent fallback): the core is
//! $SA_TREE_SITTER_DIR/libtree-sitter.so when the env var is set, else
//! the system loader path for "libtree-sitter.so". Grammars live next
//! to the core when a directory was used (libtree-sitter-<name>.so),
//! else the loader path. Missing core -> sa_ts_available() == 0 and
//! parser_new returns SA_STD_ERR_UNSUPPORTED; missing grammar ->
//! ERR_NOT_FOUND; grammar ABI outside the core's supported range ->
//! ERR_UNSUPPORTED. Pinned upstream: core v0.25.10 (ABI 13..15),
//! grammar typescript v0.23.2 (ABI 14). Rebuild script:
//! artifacts/tree_sitter/build_tree_sitter.sh; artifacts in
//! sci/artifacts/tree_sitter/.
//!
//! Handles: parsers, trees and nodes are opaque u64 registrations.
//! A tree owns a copy of its source text, so node text extraction is
//! self-contained. Freeing a tree invalidates its node handles.
//! Status codes mirror sa_std.zig.

const std = @import("std");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_IO: i32 = 6;
const ERR_UNSUPPORTED: i32 = 8;
const ERR_TRUNCATED: i32 = 9;

const ABI_MIN: u32 = 13;
const ABI_MAX: u32 = 15;

const TSNode = extern struct {
    context: [4]u32,
    id: ?*const anyopaque,
    tree: ?*const anyopaque,
};

const FnParserNew = *const fn () callconv(.c) ?*anyopaque;
const FnParserDelete = *const fn (?*anyopaque) callconv(.c) void;
const FnParserSetLanguage = *const fn (?*anyopaque, ?*const anyopaque) callconv(.c) bool;
const FnLanguageVersion = *const fn (?*const anyopaque) callconv(.c) u32;
const FnParseString = *const fn (?*anyopaque, ?*const anyopaque, [*]const u8, u32) callconv(.c) ?*anyopaque;
const FnTreeDelete = *const fn (?*anyopaque) callconv(.c) void;
const FnTreeRootNode = *const fn (?*const anyopaque) callconv(.c) TSNode;
const FnNodeString = *const fn (TSNode) callconv(.c) ?[*:0]u8;
const FnNodeType = *const fn (TSNode) callconv(.c) ?[*:0]const u8;
const FnNodeIsNull = *const fn (TSNode) callconv(.c) bool;
const FnNodeChildCount = *const fn (TSNode) callconv(.c) u32;
const FnNodeChild = *const fn (TSNode, u32) callconv(.c) TSNode;
const FnNodeChildByFieldName = *const fn (TSNode, [*]const u8, u32) callconv(.c) TSNode;
const FnNodeStartByte = *const fn (TSNode) callconv(.c) u32;
const FnNodeEndByte = *const fn (TSNode) callconv(.c) u32;
const FnLanguageFn = *const fn () callconv(.c) ?*const anyopaque;

extern "c" fn free(?*anyopaque) void;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

const Fns = struct {
    parser_new: FnParserNew,
    parser_delete: FnParserDelete,
    parser_set_language: FnParserSetLanguage,
    language_version: FnLanguageVersion,
    parse_string: FnParseString,
    tree_delete: FnTreeDelete,
    tree_root_node: FnTreeRootNode,
    node_string: FnNodeString,
    node_type: FnNodeType,
    node_is_null: FnNodeIsNull,
    node_child_count: FnNodeChildCount,
    node_named_child_count: FnNodeChildCount,
    node_child: FnNodeChild,
    node_named_child: FnNodeChild,
    node_child_by_field_name: FnNodeChildByFieldName,
    node_start_byte: FnNodeStartByte,
    node_end_byte: FnNodeEndByte,
};

var load_mu = std.Io.Mutex.init;
var load_state: enum { unloaded, ready, missing } = .unloaded;
var core_lib: ?std.DynLib = null;
var core_dir: ?[]u8 = null; // owned; set when the core came from a directory
var fns: Fns = undefined;
var grammar_libs: std.AutoHashMapUnmanaged(u64, std.DynLib) = .empty;
var grammar_langs: std.AutoHashMapUnmanaged(u64, *const anyopaque) = .empty;

fn nameHash(name: []const u8) u64 {
    return std.hash.Wyhash.hash(0, name);
}

fn ensureLoaded() bool {
    load_mu.lockUncancelable(sio.io());
    defer load_mu.unlock(sio.io());
    if (load_state != .unloaded) return load_state == .ready;
    load_state = .missing;
    const alloc = std.heap.page_allocator;
    var lib: ?std.DynLib = null;
    if (std.c.getenv("SA_TREE_SITTER_DIR")) |dir_z| {
        const dir = std.mem.span(dir_z);
        if (dir.len > 0) {
            const path = std.fmt.allocPrint(alloc, "{s}/libtree-sitter.so", .{dir}) catch return false;
            defer alloc.free(path);
            const path_z = alloc.allocSentinel(u8, path.len, 0) catch return false;
            defer alloc.free(path_z);
            @memcpy(path_z[0..path.len], path);
            lib = std.DynLib.open(path_z) catch null;
            if (lib != null) {
                core_dir = alloc.dupe(u8, dir) catch null;
            }
        }
    }
    if (lib == null) {
        lib = std.DynLib.open("libtree-sitter.so") catch return false;
    }
    var l = lib.?;
    const table = Fns{
        .parser_new = l.lookup(FnParserNew, "ts_parser_new") orelse return false,
        .parser_delete = l.lookup(FnParserDelete, "ts_parser_delete") orelse return false,
        .parser_set_language = l.lookup(FnParserSetLanguage, "ts_parser_set_language") orelse return false,
        .language_version = l.lookup(FnLanguageVersion, "ts_language_version") orelse return false,
        .parse_string = l.lookup(FnParseString, "ts_parser_parse_string") orelse return false,
        .tree_delete = l.lookup(FnTreeDelete, "ts_tree_delete") orelse return false,
        .tree_root_node = l.lookup(FnTreeRootNode, "ts_tree_root_node") orelse return false,
        .node_string = l.lookup(FnNodeString, "ts_node_string") orelse return false,
        .node_type = l.lookup(FnNodeType, "ts_node_type") orelse return false,
        .node_is_null = l.lookup(FnNodeIsNull, "ts_node_is_null") orelse return false,
        .node_child_count = l.lookup(FnNodeChildCount, "ts_node_child_count") orelse return false,
        .node_named_child_count = l.lookup(FnNodeChildCount, "ts_node_named_child_count") orelse return false,
        .node_child = l.lookup(FnNodeChild, "ts_node_child") orelse return false,
        .node_named_child = l.lookup(FnNodeChild, "ts_node_named_child") orelse return false,
        .node_child_by_field_name = l.lookup(FnNodeChildByFieldName, "ts_node_child_by_field_name") orelse return false,
        .node_start_byte = l.lookup(FnNodeStartByte, "ts_node_start_byte") orelse return false,
        .node_end_byte = l.lookup(FnNodeEndByte, "ts_node_end_byte") orelse return false,
    };
    fns = table;
    core_lib = lib;
    load_state = .ready;
    return true;
}

/// Caller must hold load_mu (grammar state shares the load lock).
fn loadLanguageLocked(name: []const u8) !*const anyopaque {
    const key = nameHash(name);
    if (grammar_langs.get(key)) |lang| return lang;
    const alloc = std.heap.page_allocator;
    var lib: ?std.DynLib = null;
    if (core_dir) |dir| {
        const path = try std.fmt.allocPrint(alloc, "{s}/libtree-sitter-{s}.so", .{ dir, name });
        defer alloc.free(path);
        const path_z = try alloc.allocSentinel(u8, path.len, 0);
        defer alloc.free(path_z);
        @memcpy(path_z[0..path.len], path);
        lib = std.DynLib.open(path_z) catch null;
    }
    if (lib == null) {
        const bare = try std.fmt.allocPrint(alloc, "libtree-sitter-{s}.so", .{name});
        defer alloc.free(bare);
        const bare_z = try alloc.allocSentinel(u8, bare.len, 0);
        defer alloc.free(bare_z);
        @memcpy(bare_z[0..bare.len], bare);
        lib = std.DynLib.open(bare_z) catch return error.NotFound;
    }
    var l = lib.?;
    const sym = try std.fmt.allocPrint(alloc, "tree_sitter_{s}", .{name});
    defer alloc.free(sym);
    const sym_z = try alloc.allocSentinel(u8, sym.len, 0);
    defer alloc.free(sym_z);
    @memcpy(sym_z[0..sym.len], sym);
    const lang_fn = l.lookup(FnLanguageFn, sym_z) orelse return error.NotFound;
    const lang = lang_fn() orelse return error.NotFound;
    try grammar_libs.put(alloc, key, l);
    try grammar_langs.put(alloc, key, lang);
    return lang;
}

// ---------------- registries ----------------

const ParserEntry = struct { raw: *anyopaque };
const TreeEntry = struct { raw: *anyopaque, source: []u8 };
const NodeEntry = struct { node: TSNode, tree_handle: u64 };

var reg_mu = std.Io.Mutex.init;
var parsers: std.AutoHashMapUnmanaged(u64, *ParserEntry) = .empty;
var trees: std.AutoHashMapUnmanaged(u64, *TreeEntry) = .empty;
var nodes: std.AutoHashMapUnmanaged(u64, *NodeEntry) = .empty;
var next_handle: u64 = 1;

fn allocHandle() u64 {
    const h = next_handle;
    next_handle += 1;
    return h;
}

fn registerNode(node: TSNode, tree_handle: u64) !u64 {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    const alloc = std.heap.page_allocator;
    const entry = try alloc.create(NodeEntry);
    entry.* = .{ .node = node, .tree_handle = tree_handle };
    const h = allocHandle();
    errdefer alloc.destroy(entry);
    try nodes.put(alloc, h, entry);
    return h;
}

fn getNode(handle: u64) ?*NodeEntry {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    return nodes.get(handle);
}

fn getTree(handle: u64) ?*TreeEntry {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    return trees.get(handle);
}

fn copyOut(text: []const u8, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const out = out_len orelse return ERR_INVALID;
    out.* = @intCast(text.len);
    if (text.len > cap) return ERR_TRUNCATED;
    if (text.len > 0) {
        const buf = buf_ptr orelse return ERR_INVALID;
        @memcpy(buf[0..text.len], text);
    }
    return OK;
}

// ---------------- externs ----------------

pub export fn sa_ts_available() u32 {
    return if (ensureLoaded()) 1 else 0;
}

pub export fn sa_ts_parser_new(out_handle: ?*u64) i32 {
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    if (!ensureLoaded()) return ERR_UNSUPPORTED;
    const raw = fns.parser_new() orelse return ERR_IO;
    const alloc = std.heap.page_allocator;
    const entry = alloc.create(ParserEntry) catch {
        fns.parser_delete(raw);
        return ERR_NOMEM;
    };
    entry.* = .{ .raw = raw };
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    const h = allocHandle();
    parsers.put(alloc, h, entry) catch {
        alloc.destroy(entry);
        fns.parser_delete(raw);
        return ERR_NOMEM;
    };
    out.* = h;
    return OK;
}

pub export fn sa_ts_parser_free(handle: u64) i32 {
    reg_mu.lockUncancelable(sio.io());
    const kv = parsers.fetchRemove(handle) orelse {
        reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    reg_mu.unlock(sio.io());
    fns.parser_delete(kv.value.raw);
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_parser_set_language(handle: u64, name_ptr: ?[*]const u8, name_len: u64) i32 {
    const np = name_ptr orelse return ERR_INVALID;
    if (name_len == 0 or name_len > 64) return ERR_INVALID;
    const name = np[0..@intCast(name_len)];
    for (name) |ch| {
        const ok = (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_';
        if (!ok) return ERR_INVALID;
    }
    if (!ensureLoaded()) return ERR_UNSUPPORTED;
    reg_mu.lockUncancelable(sio.io());
    const parser = parsers.get(handle) orelse {
        reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    const raw = parser.raw;
    reg_mu.unlock(sio.io());

    load_mu.lockUncancelable(sio.io());
    const lang = loadLanguageLocked(name) catch {
        load_mu.unlock(sio.io());
        return ERR_NOT_FOUND;
    };
    load_mu.unlock(sio.io());
    const version = fns.language_version(lang);
    if (version < ABI_MIN or version > ABI_MAX) return ERR_UNSUPPORTED;
    if (!fns.parser_set_language(raw, lang)) return ERR_UNSUPPORTED;
    return OK;
}

pub export fn sa_ts_parse(handle: u64, src_ptr: ?[*]const u8, src_len: u64, out_tree: ?*u64) i32 {
    const out = out_tree orelse return ERR_INVALID;
    out.* = 0;
    const sp = src_ptr orelse return ERR_INVALID;
    if (src_len > 0xFFFF_FFFF) return ERR_INVALID;
    if (!ensureLoaded()) return ERR_UNSUPPORTED;
    reg_mu.lockUncancelable(sio.io());
    const parser = parsers.get(handle) orelse {
        reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    const raw = parser.raw;
    reg_mu.unlock(sio.io());
    const tree_raw = fns.parse_string(raw, null, sp, @intCast(src_len)) orelse return ERR_INVALID;
    const alloc = std.heap.page_allocator;
    const source = alloc.dupe(u8, sp[0..@intCast(src_len)]) catch {
        fns.tree_delete(tree_raw);
        return ERR_NOMEM;
    };
    const entry = alloc.create(TreeEntry) catch {
        alloc.free(source);
        fns.tree_delete(tree_raw);
        return ERR_NOMEM;
    };
    entry.* = .{ .raw = tree_raw, .source = source };
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    const h = allocHandle();
    trees.put(alloc, h, entry) catch {
        alloc.destroy(entry);
        alloc.free(source);
        fns.tree_delete(tree_raw);
        return ERR_NOMEM;
    };
    out.* = h;
    return OK;
}

pub export fn sa_ts_tree_free(handle: u64) i32 {
    reg_mu.lockUncancelable(sio.io());
    const kv = trees.fetchRemove(handle) orelse {
        reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    // Drop node handles belonging to this tree.
    var it = nodes.iterator();
    var stale: std.array_list.Managed(u64) = .init(std.heap.page_allocator);
    while (it.next()) |kv2| {
        if (kv2.value_ptr.*.tree_handle == handle) stale.append(kv2.key_ptr.*) catch {};
    }
    for (stale.items) |nh| {
        if (nodes.fetchRemove(nh)) |nkv| std.heap.page_allocator.destroy(nkv.value);
    }
    stale.deinit();
    reg_mu.unlock(sio.io());
    fns.tree_delete(kv.value.raw);
    std.heap.page_allocator.free(kv.value.source);
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_tree_root(handle: u64, out_node: ?*u64) i32 {
    const out = out_node orelse return ERR_INVALID;
    out.* = 0;
    const entry = getTree(handle) orelse return ERR_HANDLE;
    const node = fns.tree_root_node(entry.raw);
    out.* = registerNode(node, handle) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_ts_tree_sexp(handle: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const entry = getTree(handle) orelse return ERR_HANDLE;
    const root = fns.tree_root_node(entry.raw);
    const text_z = fns.node_string(root) orelse return ERR_IO;
    const text = std.mem.span(text_z);
    const rc = copyOut(text, buf_ptr, cap, out_len);
    free(@ptrCast(text_z));
    return rc;
}

pub export fn sa_ts_node_free(handle: u64) i32 {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    const kv = nodes.fetchRemove(handle) orelse return ERR_HANDLE;
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_node_type(handle: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const text_z = fns.node_type(entry.node) orelse return ERR_IO;
    return copyOut(std.mem.span(text_z), buf_ptr, cap, out_len);
}

pub export fn sa_ts_node_text(handle: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const tree = getTree(entry.tree_handle) orelse return ERR_HANDLE;
    const start: usize = @intCast(fns.node_start_byte(entry.node));
    const end: usize = @intCast(fns.node_end_byte(entry.node));
    if (end > tree.source.len or start > end) return ERR_IO;
    return copyOut(tree.source[start..end], buf_ptr, cap, out_len);
}

pub export fn sa_ts_node_child_count(handle: u64, out_count: ?*u32) i32 {
    const out = out_count orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = fns.node_child_count(entry.node);
    return OK;
}

pub export fn sa_ts_node_named_child_count(handle: u64, out_count: ?*u32) i32 {
    const out = out_count orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = fns.node_named_child_count(entry.node);
    return OK;
}

pub export fn sa_ts_node_child(handle: u64, index: u32, named: u32, out_node: ?*u64) i32 {
    const out = out_node orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const child = if (named != 0) fns.node_named_child(entry.node, index) else fns.node_child(entry.node, index);
    if (fns.node_is_null(child)) return OK; // out stays 0: no such child
    out.* = registerNode(child, entry.tree_handle) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_ts_node_child_by_field(handle: u64, field_ptr: ?[*]const u8, field_len: u64, out_node: ?*u64) i32 {
    const out = out_node orelse return ERR_INVALID;
    out.* = 0;
    const fp = field_ptr orelse return ERR_INVALID;
    if (field_len == 0 or field_len > 64) return ERR_INVALID;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const child = fns.node_child_by_field_name(entry.node, fp, @intCast(field_len));
    if (fns.node_is_null(child)) return OK; // out stays 0: field absent
    out.* = registerNode(child, entry.tree_handle) catch return ERR_NOMEM;
    return OK;
}

// ---------------- tests ----------------

fn setTsDir() void {
    _ = setenv("SA_TREE_SITTER_DIR", "/content/sa_all/sci/artifacts/tree_sitter", 1);
}

fn readInto(comptime F: anytype, handle: u64, buf: []u8) ![]u8 {
    var len: u64 = 0;
    const rc = F(handle, buf.ptr, buf.len, &len);
    if (rc != OK) return error.ReadFailed;
    return buf[0..@intCast(len)];
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
