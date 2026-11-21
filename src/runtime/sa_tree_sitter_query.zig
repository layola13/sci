const std = @import("std");
const sa_std = @import("sa_tree_sitter.zig");
const ABI_MAX = @import("sa_tree_sitter.zig").ABI_MAX;
const ABI_MIN = @import("sa_tree_sitter.zig").ABI_MIN;
const CursorEntry = @import("sa_tree_sitter.zig").CursorEntry;
const ERR_HANDLE = @import("sa_tree_sitter.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_tree_sitter.zig").ERR_INVALID;
const ERR_IO = @import("sa_tree_sitter.zig").ERR_IO;
const ERR_NOMEM = @import("sa_tree_sitter.zig").ERR_NOMEM;
const ERR_NOT_FOUND = @import("sa_tree_sitter.zig").ERR_NOT_FOUND;
const ERR_UNSUPPORTED = @import("sa_tree_sitter.zig").ERR_UNSUPPORTED;
const OK = @import("sa_tree_sitter.zig").OK;
const QueryEntry = @import("sa_tree_sitter.zig").QueryEntry;
const TSQueryMatch = @import("sa_tree_sitter.zig").TSQueryMatch;
const allocHandle = @import("sa_tree_sitter.zig").allocHandle;
const copyOut = @import("sa_tree_sitter.zig").copyOut;
const ensureLoaded = @import("sa_tree_sitter.zig").ensureLoaded;
const getCursor = @import("sa_tree_sitter.zig").getCursor;
const getNode = @import("sa_tree_sitter.zig").getNode;
const getQuery = @import("sa_tree_sitter.zig").getQuery;
const loadLanguageLocked = @import("sa_tree_sitter.zig").loadLanguageLocked;
const registerNode = @import("sa_tree_sitter.zig").registerNode;
const sio = @import("sa_tree_sitter.zig").sio;

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
    sa_std.load_mu.lockUncancelable(sio.io());
    const lang = loadLanguageLocked(name) catch {
        sa_std.load_mu.unlock(sio.io());
        return ERR_NOT_FOUND;
    };
    sa_std.load_mu.unlock(sio.io());
    const version = sa_std.fns.language_version(lang);
    if (version < ABI_MIN or version > ABI_MAX) return ERR_UNSUPPORTED;
    var err_offset: u32 = 0;
    var err_kind: u32 = 0;
    const raw = sa_std.fns.query_new(lang, sp, @intCast(src_len), &err_offset, &err_kind) orelse {
        if (out_err_offset) |p| p.* = err_offset;
        if (out_err_kind) |p| p.* = err_kind;
        return ERR_INVALID;
    };
    const alloc = std.heap.page_allocator;
    const entry = alloc.create(QueryEntry) catch {
        sa_std.fns.query_delete(raw);
        return ERR_NOMEM;
    };
    entry.* = .{ .raw = raw };
    sa_std.reg_mu.lockUncancelable(sio.io());
    defer sa_std.reg_mu.unlock(sio.io());
    const h = allocHandle();
    sa_std.queries.put(alloc, h, entry) catch {
        alloc.destroy(entry);
        sa_std.fns.query_delete(raw);
        return ERR_NOMEM;
    };
    out.* = h;
    return OK;
}

pub export fn sa_ts_query_free(handle: u64) i32 {
    sa_std.reg_mu.lockUncancelable(sio.io());
    const kv = sa_std.queries.fetchRemove(handle) orelse {
        sa_std.reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    sa_std.reg_mu.unlock(sio.io());
    sa_std.fns.query_delete(kv.value.raw);
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_query_pattern_count(handle: u64, out_count: ?*u32) i32 {
    const out = out_count orelse return ERR_INVALID;
    out.* = 0;
    const entry = getQuery(handle) orelse return ERR_HANDLE;
    out.* = sa_std.fns.query_pattern_count(entry.raw);
    return OK;
}

pub export fn sa_ts_query_capture_count(handle: u64, out_count: ?*u32) i32 {
    const out = out_count orelse return ERR_INVALID;
    out.* = 0;
    const entry = getQuery(handle) orelse return ERR_HANDLE;
    out.* = sa_std.fns.query_capture_count(entry.raw);
    return OK;
}

pub export fn sa_ts_query_capture_name(handle: u64, index: u32, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const entry = getQuery(handle) orelse return ERR_HANDLE;
    if (index >= sa_std.fns.query_capture_count(entry.raw)) return ERR_INVALID;
    var name_len: u32 = 0;
    const name_ptr = sa_std.fns.query_capture_name_for_id(entry.raw, index, &name_len) orelse return ERR_IO;
    return copyOut(name_ptr[0..@intCast(name_len)], buf_ptr, cap, out_len);
}

pub export fn sa_ts_query_cursor_new(out_cursor: ?*u64) i32 {
    const out = out_cursor orelse return ERR_INVALID;
    out.* = 0;
    if (!ensureLoaded()) return ERR_UNSUPPORTED;
    const raw = sa_std.fns.query_cursor_new() orelse return ERR_IO;
    const alloc = std.heap.page_allocator;
    const entry = alloc.create(CursorEntry) catch {
        sa_std.fns.query_cursor_delete(raw);
        return ERR_NOMEM;
    };
    entry.* = .{ .raw = raw };
    sa_std.reg_mu.lockUncancelable(sio.io());
    defer sa_std.reg_mu.unlock(sio.io());
    const h = allocHandle();
    sa_std.cursors.put(alloc, h, entry) catch {
        alloc.destroy(entry);
        sa_std.fns.query_cursor_delete(raw);
        return ERR_NOMEM;
    };
    out.* = h;
    return OK;
}

pub export fn sa_ts_query_cursor_free(handle: u64) i32 {
    sa_std.reg_mu.lockUncancelable(sio.io());
    const kv = sa_std.cursors.fetchRemove(handle) orelse {
        sa_std.reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    sa_std.reg_mu.unlock(sio.io());
    sa_std.fns.query_cursor_delete(kv.value.raw);
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_query_exec(cursor: u64, query: u64, node: u64) i32 {
    const cursor_entry = getCursor(cursor) orelse return ERR_HANDLE;
    const query_entry = getQuery(query) orelse return ERR_HANDLE;
    const node_entry = getNode(node) orelse return ERR_HANDLE;
    sa_std.fns.query_cursor_exec(cursor_entry.raw, query_entry.raw, node_entry.node);
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
    if (!sa_std.fns.query_cursor_next_match(entry.raw, &match)) {
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
