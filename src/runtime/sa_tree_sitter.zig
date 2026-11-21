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
const builtin = @import("builtin");
pub const sio = @import("sio");

/// WASI has no dynamic loading (std.DynLib does not exist there),
/// which otherwise breaks the whole sa_std archive build for
/// wasm32-wasi. The stub type keeps every use site compiling; its
/// open always fails, so the module reports the library missing
/// through its existing surface (sa_ts_available() == 0, parser_new
/// -> SA_STD_ERR_UNSUPPORTED) — loud, never a fake success.
const dynlib_supported = builtin.os.tag != .wasi;
const DynLib = if (dynlib_supported) std.DynLib else struct {
    pub fn open(_: []const u8) error{Unsupported}!@This() {
        return error.Unsupported;
    }

    pub fn lookup(_: *@This(), comptime T: type, _: [:0]const u8) ?T {
        return null;
    }

    pub fn close(_: *@This()) void {}
};

pub const OK: i32 = 0;
pub const ERR_INVALID: i32 = 1;
pub const ERR_HANDLE: i32 = 2;
pub const ERR_NOT_FOUND: i32 = 3;
pub const ERR_NOMEM: i32 = 5;
pub const ERR_IO: i32 = 6;
pub const ERR_UNSUPPORTED: i32 = 8;
const ERR_TRUNCATED: i32 = 9;

pub const ABI_MIN: u32 = 13;
pub const ABI_MAX: u32 = 15;

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

pub const TSQueryMatch = extern struct {
    id: u32,
    pattern_index: u16,
    capture_count: u16,
    captures: ?[*]const TSQueryCapture,
};

pub const TSInputEdit = extern struct {
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

pub var load_mu = std.Io.Mutex.init;
var load_state: enum { unloaded, ready, missing } = .unloaded;
var core_lib: ?DynLib = null;
var core_dir: ?[]u8 = null; // owned; set when the core came from a directory
pub var fns: Fns = undefined;
var grammar_libs: std.AutoHashMapUnmanaged(u64, DynLib) = .empty;
var grammar_langs: std.AutoHashMapUnmanaged(u64, *const anyopaque) = .empty;

fn nameHash(name: []const u8) u64 {
    return std.hash.Wyhash.hash(0, name);
}

pub fn ensureLoaded() bool {
    load_mu.lockUncancelable(sio.io());
    defer load_mu.unlock(sio.io());
    if (load_state != .unloaded) return load_state == .ready;
    load_state = .missing;
    const alloc = std.heap.page_allocator;
    var lib: ?DynLib = null;
    if (std.c.getenv("SA_TREE_SITTER_DIR")) |dir_z| {
        const dir = std.mem.span(dir_z);
        if (dir.len > 0) {
            const path = std.fmt.allocPrint(alloc, "{s}/libtree-sitter.so", .{dir}) catch return false;
            defer alloc.free(path);
            const path_z = alloc.allocSentinel(u8, path.len, 0) catch return false;
            defer alloc.free(path_z);
            @memcpy(path_z[0..path.len], path);
            lib = DynLib.open(path_z) catch null;
            if (lib != null) {
                core_dir = alloc.dupe(u8, dir) catch null;
            }
        }
    }
    if (lib == null) {
        lib = DynLib.open("libtree-sitter.so") catch return false;
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
pub fn loadLanguageLocked(name: []const u8) !*const anyopaque {
    const key = nameHash(name);
    if (grammar_langs.get(key)) |lang| return lang;
    const alloc = std.heap.page_allocator;
    var lib: ?DynLib = null;
    if (core_dir) |dir| {
        const path = try std.fmt.allocPrint(alloc, "{s}/libtree-sitter-{s}.so", .{ dir, name });
        defer alloc.free(path);
        const path_z = try alloc.allocSentinel(u8, path.len, 0);
        defer alloc.free(path_z);
        @memcpy(path_z[0..path.len], path);
        lib = DynLib.open(path_z) catch null;
    }
    if (lib == null) {
        const bare = try std.fmt.allocPrint(alloc, "libtree-sitter-{s}.so", .{name});
        defer alloc.free(bare);
        const bare_z = try alloc.allocSentinel(u8, bare.len, 0);
        defer alloc.free(bare_z);
        @memcpy(bare_z[0..bare.len], bare);
        lib = DynLib.open(bare_z) catch return error.NotFound;
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
pub const QueryEntry = struct { raw: *anyopaque };
pub const CursorEntry = struct {
    raw: *anyopaque,
    tree_handle: u64 = 0,
    has_match: bool = false,
    match: TSQueryMatch = .{ .id = 0, .pattern_index = 0, .capture_count = 0, .captures = null },
};

pub var reg_mu = std.Io.Mutex.init;
var parsers: std.AutoHashMapUnmanaged(u64, *ParserEntry) = .empty;
pub var trees: std.AutoHashMapUnmanaged(u64, *TreeEntry) = .empty;
pub var nodes: std.AutoHashMapUnmanaged(u64, *NodeEntry) = .empty;
pub var queries: std.AutoHashMapUnmanaged(u64, *QueryEntry) = .empty;
pub var cursors: std.AutoHashMapUnmanaged(u64, *CursorEntry) = .empty;
var next_handle: u64 = 1;

pub fn allocHandle() u64 {
    const h = next_handle;
    next_handle += 1;
    return h;
}

pub fn registerNode(node: TSNode, tree_handle: u64) !u64 {
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

pub fn getNode(handle: u64) ?*NodeEntry {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    return nodes.get(handle);
}

pub fn getTree(handle: u64) ?*TreeEntry {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    return trees.get(handle);
}

pub fn getQuery(handle: u64) ?*QueryEntry {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    return queries.get(handle);
}

pub fn getCursor(handle: u64) ?*CursorEntry {
    reg_mu.lockUncancelable(sio.io());
    defer reg_mu.unlock(sio.io());
    return cursors.get(handle);
}

pub fn copyOut(text: []const u8, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
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

pub const sa_ts_tree_free = @import("sa_tree_sitter_node.zig").sa_ts_tree_free;

pub const sa_ts_tree_root = @import("sa_tree_sitter_node.zig").sa_ts_tree_root;

pub const sa_ts_tree_sexp = @import("sa_tree_sitter_node.zig").sa_ts_tree_sexp;

pub const sa_ts_node_free = @import("sa_tree_sitter_node.zig").sa_ts_node_free;

pub const sa_ts_node_type = @import("sa_tree_sitter_node.zig").sa_ts_node_type;

pub const sa_ts_node_byte_range = @import("sa_tree_sitter_node.zig").sa_ts_node_byte_range;

pub const sa_ts_node_text = @import("sa_tree_sitter_node.zig").sa_ts_node_text;

pub const sa_ts_node_child_count = @import("sa_tree_sitter_node.zig").sa_ts_node_child_count;

pub const sa_ts_node_named_child_count = @import("sa_tree_sitter_node.zig").sa_ts_node_named_child_count;

pub const sa_ts_node_child = @import("sa_tree_sitter_node.zig").sa_ts_node_child;

pub const sa_ts_node_child_by_field = @import("sa_tree_sitter_node.zig").sa_ts_node_child_by_field;

pub const sa_ts_node_parent = @import("sa_tree_sitter_node.zig").sa_ts_node_parent;

pub const sa_ts_node_is_named = @import("sa_tree_sitter_node.zig").sa_ts_node_is_named;

pub const sa_ts_node_is_missing = @import("sa_tree_sitter_node.zig").sa_ts_node_is_missing;

pub const sa_ts_node_has_error = @import("sa_tree_sitter_node.zig").sa_ts_node_has_error;

pub const sa_ts_node_start_point = @import("sa_tree_sitter_node.zig").sa_ts_node_start_point;

pub const sa_ts_node_end_point = @import("sa_tree_sitter_node.zig").sa_ts_node_end_point;

pub const sa_ts_query_new = @import("sa_tree_sitter_query.zig").sa_ts_query_new;

pub const sa_ts_query_free = @import("sa_tree_sitter_query.zig").sa_ts_query_free;

pub const sa_ts_query_pattern_count = @import("sa_tree_sitter_query.zig").sa_ts_query_pattern_count;

pub const sa_ts_query_capture_count = @import("sa_tree_sitter_query.zig").sa_ts_query_capture_count;

pub const sa_ts_query_capture_name = @import("sa_tree_sitter_query.zig").sa_ts_query_capture_name;

pub const sa_ts_query_cursor_new = @import("sa_tree_sitter_query.zig").sa_ts_query_cursor_new;

pub const sa_ts_query_cursor_free = @import("sa_tree_sitter_query.zig").sa_ts_query_cursor_free;

pub const sa_ts_query_exec = @import("sa_tree_sitter_query.zig").sa_ts_query_exec;

pub const sa_ts_query_next_match = @import("sa_tree_sitter_query.zig").sa_ts_query_next_match;

pub const sa_ts_query_match_capture = @import("sa_tree_sitter_query.zig").sa_ts_query_match_capture;

pub const sa_ts_tree_edit = @import("sa_tree_sitter_node.zig").sa_ts_tree_edit;

// ---------------- tests ----------------

pub fn anyMissingBelow(node: u64) bool {
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






pub fn setTsDir() void {
    // DEF-TS-HARDCODE-PATH: the tests must load the tree-sitter artifacts
    // that ship with this repository (artifacts/tree_sitter), never a
    // venue-specific absolute path. Derive the directory from the
    // build-time repo root baked into build_options (the same source
    // cli.zig uses to locate sa_std), so the tests find the in-tree
    // artifacts on any machine.
    const build_options = @import("build_options");
    const suffix = std.fs.path.sep_str ++ "artifacts" ++ std.fs.path.sep_str ++ "tree_sitter";
    const root = build_options.repo_root;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    if (root.len + suffix.len >= buf.len) return;
    @memcpy(buf[0..root.len], root);
    @memcpy(buf[root.len..][0..suffix.len], suffix);
    buf[root.len + suffix.len] = 0;
    const dir: [*:0]const u8 = @ptrCast(&buf);
    _ = setenv("SA_TREE_SITTER_DIR", dir, 1);
}

pub fn readInto(comptime F: anytype, handle: u64, buf: []u8) ![]u8 {
    var len: u64 = 0;
    const rc = F(handle, buf.ptr, buf.len, &len);
    if (rc != OK) return error.ReadFailed;
    return buf[0..@intCast(len)];
}


