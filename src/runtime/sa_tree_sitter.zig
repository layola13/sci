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
//! grammars typescript v0.23.2 and javascript v0.23.1 (ABI 14).
//! Rebuild script:
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
const TSPoint = extern struct { row: u32, column: u32 };
const FnNodeParent = *const fn (TSNode) callconv(.c) TSNode;
const FnNodeFlag = *const fn (TSNode) callconv(.c) bool;
const FnNodePoint = *const fn (TSNode) callconv(.c) TSPoint;
const FnLanguageFn = *const fn () callconv(.c) ?*const anyopaque;

const TSQueryCapture = extern struct {
    node: TSNode,
    index: u32,
};

const TSQueryMatch = extern struct {
    id: u32,
    pattern_index: u16,
    capture_count: u16,
    captures: ?[*]const TSQueryCapture,
};

const TSInputEdit = extern struct {
    start_byte: u32,
    old_end_byte: u32,
    new_end_byte: u32,
    start_point: TSPoint,
    old_end_point: TSPoint,
    new_end_point: TSPoint,
};

const FnQueryNew = *const fn (?*const anyopaque, [*]const u8, u32, *u32, *u32) callconv(.c) ?*anyopaque;
const FnQueryDelete = *const fn (?*anyopaque) callconv(.c) void;
const FnQueryCount = *const fn (?*const anyopaque) callconv(.c) u32;
const FnQueryCaptureName = *const fn (?*const anyopaque, u32, *u32) callconv(.c) ?[*]const u8;
const FnQueryCursorNew = *const fn () callconv(.c) ?*anyopaque;
const FnQueryCursorDelete = *const fn (?*anyopaque) callconv(.c) void;
const FnQueryCursorExec = *const fn (?*anyopaque, ?*const anyopaque, TSNode) callconv(.c) void;
const FnQueryCursorNextMatch = *const fn (?*anyopaque, *TSQueryMatch) callconv(.c) bool;
const FnTreeEdit = *const fn (?*anyopaque, *const TSInputEdit) callconv(.c) void;

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
    node_parent: FnNodeParent,
    node_is_named: FnNodeFlag,
    node_is_missing: FnNodeFlag,
    node_has_error: FnNodeFlag,
    node_start_point: FnNodePoint,
    node_end_point: FnNodePoint,
    query_new: FnQueryNew,
    query_delete: FnQueryDelete,
    query_pattern_count: FnQueryCount,
    query_capture_count: FnQueryCount,
    query_capture_name_for_id: FnQueryCaptureName,
    query_cursor_new: FnQueryCursorNew,
    query_cursor_delete: FnQueryCursorDelete,
    query_cursor_exec: FnQueryCursorExec,
    query_cursor_next_match: FnQueryCursorNextMatch,
    tree_edit: FnTreeEdit,
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
        .node_parent = l.lookup(FnNodeParent, "ts_node_parent") orelse return false,
        .node_is_named = l.lookup(FnNodeFlag, "ts_node_is_named") orelse return false,
        .node_is_missing = l.lookup(FnNodeFlag, "ts_node_is_missing") orelse return false,
        .node_has_error = l.lookup(FnNodeFlag, "ts_node_has_error") orelse return false,
        .node_start_point = l.lookup(FnNodePoint, "ts_node_start_point") orelse return false,
        .node_end_point = l.lookup(FnNodePoint, "ts_node_end_point") orelse return false,
        .query_new = l.lookup(FnQueryNew, "ts_query_new") orelse return false,
        .query_delete = l.lookup(FnQueryDelete, "ts_query_delete") orelse return false,
        .query_pattern_count = l.lookup(FnQueryCount, "ts_query_pattern_count") orelse return false,
        .query_capture_count = l.lookup(FnQueryCount, "ts_query_capture_count") orelse return false,
        .query_capture_name_for_id = l.lookup(FnQueryCaptureName, "ts_query_capture_name_for_id") orelse return false,
        .query_cursor_new = l.lookup(FnQueryCursorNew, "ts_query_cursor_new") orelse return false,
        .query_cursor_delete = l.lookup(FnQueryCursorDelete, "ts_query_cursor_delete") orelse return false,
        .query_cursor_exec = l.lookup(FnQueryCursorExec, "ts_query_cursor_exec") orelse return false,
        .query_cursor_next_match = l.lookup(FnQueryCursorNextMatch, "ts_query_cursor_next_match") orelse return false,
        .tree_edit = l.lookup(FnTreeEdit, "ts_tree_edit") orelse return false,
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
const QueryEntry = struct { raw: *anyopaque };
const CursorEntry = struct {
    raw: *anyopaque,
    tree_handle: u64 = 0,
    has_match: bool = false,
    match: TSQueryMatch = .{ .id = 0, .pattern_index = 0, .capture_count = 0, .captures = null },
};

var reg_mu = std.Io.Mutex.init;
var parsers: std.AutoHashMapUnmanaged(u64, *ParserEntry) = .empty;
var trees: std.AutoHashMapUnmanaged(u64, *TreeEntry) = .empty;
var nodes: std.AutoHashMapUnmanaged(u64, *NodeEntry) = .empty;
var queries: std.AutoHashMapUnmanaged(u64, *QueryEntry) = .empty;
var cursors: std.AutoHashMapUnmanaged(u64, *CursorEntry) = .empty;
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

fn getQuery(handle: u64) ?*QueryEntry {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    return queries.get(handle);
}

fn getCursor(handle: u64) ?*CursorEntry {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    return cursors.get(handle);
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

fn parseImpl(handle: u64, old_tree_handle: u64, src_ptr: ?[*]const u8, src_len: u64, out_tree: ?*u64) i32 {
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
    var old_raw: ?*const anyopaque = null;
    if (old_tree_handle != 0) {
        const old_entry = getTree(old_tree_handle) orelse return ERR_HANDLE;
        old_raw = old_entry.raw;
    }
    const tree_raw = fns.parse_string(raw, old_raw, sp, @intCast(src_len)) orelse return ERR_INVALID;
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

pub export fn sa_ts_parse(handle: u64, src_ptr: ?[*]const u8, src_len: u64, out_tree: ?*u64) i32 {
    return parseImpl(handle, 0, src_ptr, src_len, out_tree);
}

pub export fn sa_ts_parse_incremental(handle: u64, old_tree_handle: u64, src_ptr: ?[*]const u8, src_len: u64, out_tree: ?*u64) i32 {
    if (old_tree_handle == 0) return ERR_INVALID;
    return parseImpl(handle, old_tree_handle, src_ptr, src_len, out_tree);
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

pub export fn sa_ts_node_byte_range(handle: u64, out_start: ?*u32, out_end: ?*u32) i32 {
    const s_out = out_start orelse return ERR_INVALID;
    const e_out = out_end orelse return ERR_INVALID;
    s_out.* = 0;
    e_out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    s_out.* = fns.node_start_byte(entry.node);
    e_out.* = fns.node_end_byte(entry.node);
    return OK;
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

pub export fn sa_ts_node_parent(handle: u64, out_node: ?*u64) i32 {
    const out = out_node orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const parent = fns.node_parent(entry.node);
    if (fns.node_is_null(parent)) return OK; // root node: out stays 0 (no parent)
    out.* = registerNode(parent, entry.tree_handle) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_ts_node_is_named(handle: u64, out_flag: ?*u32) i32 {
    const out = out_flag orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = if (fns.node_is_named(entry.node)) @as(u32, 1) else 0;
    return OK;
}

pub export fn sa_ts_node_is_missing(handle: u64, out_flag: ?*u32) i32 {
    const out = out_flag orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = if (fns.node_is_missing(entry.node)) @as(u32, 1) else 0;
    return OK;
}

pub export fn sa_ts_node_has_error(handle: u64, out_flag: ?*u32) i32 {
    const out = out_flag orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = if (fns.node_has_error(entry.node)) @as(u32, 1) else 0;
    return OK;
}

pub export fn sa_ts_node_start_point(handle: u64, out_row: ?*u32, out_col: ?*u32) i32 {
    const r_out = out_row orelse return ERR_INVALID;
    const c_out = out_col orelse return ERR_INVALID;
    r_out.* = 0;
    c_out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const pt = fns.node_start_point(entry.node);
    r_out.* = pt.row;
    c_out.* = pt.column;
    return OK;
}

pub export fn sa_ts_node_end_point(handle: u64, out_row: ?*u32, out_col: ?*u32) i32 {
    const r_out = out_row orelse return ERR_INVALID;
    const c_out = out_col orelse return ERR_INVALID;
    r_out.* = 0;
    c_out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const pt = fns.node_end_point(entry.node);
    r_out.* = pt.row;
    c_out.* = pt.column;
    return OK;
}

pub export fn sa_ts_query_new(lang_ptr: ?[*]const u8, lang_len: u64, src_ptr: ?[*]const u8, src_len: u64, out_query: ?*u64, out_err_offset: ?*u32, out_err_kind: ?*u32) i32 {
    const out = out_query orelse return ERR_INVALID;
    out.* = 0;
    if (out_err_offset) |p| p.* = 0;
    if (out_err_kind) |p| p.* = 0;
    const lp = lang_ptr orelse return ERR_INVALID;
    if (lang_len == 0 or lang_len > 64) return ERR_INVALID;
    const name = lp[0..@intCast(lang_len)];
    for (name) |ch| {
        const ok = (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_';
        if (!ok) return ERR_INVALID;
    }
    const sp = src_ptr orelse return ERR_INVALID;
    if (src_len > 0xFFFF_FFFF) return ERR_INVALID;
    if (!ensureLoaded()) return ERR_UNSUPPORTED;
    load_mu.lockUncancelable(sio.io());
    const lang = loadLanguageLocked(name) catch {
        load_mu.unlock(sio.io());
        return ERR_NOT_FOUND;
    };
    load_mu.unlock(sio.io());
    const version = fns.language_version(lang);
    if (version < ABI_MIN or version > ABI_MAX) return ERR_UNSUPPORTED;
    var err_offset: u32 = 0;
    var err_kind: u32 = 0;
    const raw = fns.query_new(lang, sp, @intCast(src_len), &err_offset, &err_kind) orelse {
        if (out_err_offset) |p| p.* = err_offset;
        if (out_err_kind) |p| p.* = err_kind;
        return ERR_INVALID;
    };
    const alloc = std.heap.page_allocator;
    const entry = alloc.create(QueryEntry) catch {
        fns.query_delete(raw);
        return ERR_NOMEM;
    };
    entry.* = .{ .raw = raw };
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    const h = allocHandle();
    queries.put(alloc, h, entry) catch {
        alloc.destroy(entry);
        fns.query_delete(raw);
        return ERR_NOMEM;
    };
    out.* = h;
    return OK;
}

pub export fn sa_ts_query_free(handle: u64) i32 {
    reg_mu.lockUncancelable(sio.io());
    const kv = queries.fetchRemove(handle) orelse {
        reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    reg_mu.unlock(sio.io());
    fns.query_delete(kv.value.raw);
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_query_pattern_count(handle: u64, out_count: ?*u32) i32 {
    const out = out_count orelse return ERR_INVALID;
    out.* = 0;
    const entry = getQuery(handle) orelse return ERR_HANDLE;
    out.* = fns.query_pattern_count(entry.raw);
    return OK;
}

pub export fn sa_ts_query_capture_count(handle: u64, out_count: ?*u32) i32 {
    const out = out_count orelse return ERR_INVALID;
    out.* = 0;
    const entry = getQuery(handle) orelse return ERR_HANDLE;
    out.* = fns.query_capture_count(entry.raw);
    return OK;
}

pub export fn sa_ts_query_capture_name(handle: u64, index: u32, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const entry = getQuery(handle) orelse return ERR_HANDLE;
    if (index >= fns.query_capture_count(entry.raw)) return ERR_INVALID;
    var name_len: u32 = 0;
    const name_ptr = fns.query_capture_name_for_id(entry.raw, index, &name_len) orelse return ERR_IO;
    return copyOut(name_ptr[0..@intCast(name_len)], buf_ptr, cap, out_len);
}

pub export fn sa_ts_query_cursor_new(out_cursor: ?*u64) i32 {
    const out = out_cursor orelse return ERR_INVALID;
    out.* = 0;
    if (!ensureLoaded()) return ERR_UNSUPPORTED;
    const raw = fns.query_cursor_new() orelse return ERR_IO;
    const alloc = std.heap.page_allocator;
    const entry = alloc.create(CursorEntry) catch {
        fns.query_cursor_delete(raw);
        return ERR_NOMEM;
    };
    entry.* = .{ .raw = raw };
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    const h = allocHandle();
    cursors.put(alloc, h, entry) catch {
        alloc.destroy(entry);
        fns.query_cursor_delete(raw);
        return ERR_NOMEM;
    };
    out.* = h;
    return OK;
}

pub export fn sa_ts_query_cursor_free(handle: u64) i32 {
    reg_mu.lockUncancelable(sio.io());
    const kv = cursors.fetchRemove(handle) orelse {
        reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    reg_mu.unlock(sio.io());
    fns.query_cursor_delete(kv.value.raw);
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_query_exec(cursor: u64, query: u64, node: u64) i32 {
    const cursor_entry = getCursor(cursor) orelse return ERR_HANDLE;
    const query_entry = getQuery(query) orelse return ERR_HANDLE;
    const node_entry = getNode(node) orelse return ERR_HANDLE;
    fns.query_cursor_exec(cursor_entry.raw, query_entry.raw, node_entry.node);
    cursor_entry.tree_handle = node_entry.tree_handle;
    cursor_entry.has_match = false;
    return OK;
}

pub export fn sa_ts_query_next_match(cursor: u64, out_has: ?*u32, out_pattern: ?*u32, out_captures: ?*u32) i32 {
    const has_out = out_has orelse return ERR_INVALID;
    const pat_out = out_pattern orelse return ERR_INVALID;
    const cap_out = out_captures orelse return ERR_INVALID;
    has_out.* = 0;
    pat_out.* = 0;
    cap_out.* = 0;
    const entry = getCursor(cursor) orelse return ERR_HANDLE;
    var match: TSQueryMatch = undefined;
    if (!fns.query_cursor_next_match(entry.raw, &match)) {
        entry.has_match = false;
        return OK;
    }
    entry.match = match;
    entry.has_match = true;
    has_out.* = 1;
    pat_out.* = match.pattern_index;
    cap_out.* = match.capture_count;
    return OK;
}

pub export fn sa_ts_query_match_capture(cursor: u64, index: u32, out_node: ?*u64, out_capture: ?*u32) i32 {
    const out = out_node orelse return ERR_INVALID;
    const cap_out = out_capture orelse return ERR_INVALID;
    out.* = 0;
    cap_out.* = 0;
    const entry = getCursor(cursor) orelse return ERR_HANDLE;
    if (!entry.has_match) return ERR_INVALID;
    if (index >= entry.match.capture_count) return OK; // out stays 0: no such capture
    const caps = entry.match.captures orelse return ERR_IO;
    const capture = caps[index];
    out.* = registerNode(capture.node, entry.tree_handle) catch return ERR_NOMEM;
    cap_out.* = capture.index;
    return OK;
}

pub export fn sa_ts_tree_edit(handle: u64, start_byte: u32, old_end_byte: u32, new_end_byte: u32, start_row: u32, start_col: u32, old_end_row: u32, old_end_col: u32, new_end_row: u32, new_end_col: u32) i32 {
    const entry = getTree(handle) orelse return ERR_HANDLE;
    const edit = TSInputEdit{
        .start_byte = start_byte,
        .old_end_byte = old_end_byte,
        .new_end_byte = new_end_byte,
        .start_point = .{ .row = start_row, .column = start_col },
        .old_end_point = .{ .row = old_end_row, .column = old_end_col },
        .new_end_point = .{ .row = new_end_row, .column = new_end_col },
    };
    fns.tree_edit(entry.raw, &edit);
    return OK;
}

// ---------------- tests ----------------

fn anyMissingBelow(node: u64) bool {
    var flag: u32 = 0;
    if (sa_ts_node_is_missing(node, &flag) != OK) return false;
    if (flag != 0) return true;
    var count: u32 = 0;
    if (sa_ts_node_child_count(node, &count) != OK) return false;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var ch: u64 = 0;
        if (sa_ts_node_child(node, i, 0, &ch) != OK) return false;
        if (ch == 0) continue;
        defer _ = sa_ts_node_free(ch);
        if (anyMissingBelow(ch)) return true;
    }
    return false;
}

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
