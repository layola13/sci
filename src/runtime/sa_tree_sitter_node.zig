const std = @import("std");
const sa_std = @import("sa_tree_sitter.zig");
const ERR_HANDLE = @import("sa_tree_sitter.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_tree_sitter.zig").ERR_INVALID;
const ERR_IO = @import("sa_tree_sitter.zig").ERR_IO;
const ERR_NOMEM = @import("sa_tree_sitter.zig").ERR_NOMEM;
const OK = @import("sa_tree_sitter.zig").OK;
const TSInputEdit = @import("sa_tree_sitter.zig").TSInputEdit;
const copyOut = @import("sa_tree_sitter.zig").copyOut;
const getNode = @import("sa_tree_sitter.zig").getNode;
const getTree = @import("sa_tree_sitter.zig").getTree;
const registerNode = @import("sa_tree_sitter.zig").registerNode;
const sio = @import("sa_tree_sitter.zig").sio;
extern "c" fn free(?*anyopaque) void;

pub export fn sa_ts_tree_free(handle: u64) i32 {
    sa_std.reg_mu.lockUncancelable(sio.io());
    const kv = sa_std.trees.fetchRemove(handle) orelse {
        sa_std.reg_mu.unlock(sio.io());
        return ERR_HANDLE;
    };
    // Drop node handles belonging to this tree.
    var it = sa_std.nodes.iterator();
    var stale: std.array_list.Managed(u64) = .init(std.heap.page_allocator);
    while (it.next()) |kv2| {
        if (kv2.value_ptr.*.tree_handle == handle) stale.append(kv2.key_ptr.*) catch {};
    }
    for (stale.items) |nh| {
        if (sa_std.nodes.fetchRemove(nh)) |nkv| std.heap.page_allocator.destroy(nkv.value);
    }
    stale.deinit();
    sa_std.reg_mu.unlock(sio.io());
    sa_std.fns.tree_delete(kv.value.raw);
    std.heap.page_allocator.free(kv.value.source);
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_tree_root(handle: u64, out_node: ?*u64) i32 {
    const out = out_node orelse return ERR_INVALID;
    out.* = 0;
    const entry = getTree(handle) orelse return ERR_HANDLE;
    const node = sa_std.fns.tree_root_node(entry.raw);
    out.* = registerNode(node, handle) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_ts_tree_sexp(handle: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const entry = getTree(handle) orelse return ERR_HANDLE;
    const root = sa_std.fns.tree_root_node(entry.raw);
    const text_z = sa_std.fns.node_string(root) orelse return ERR_IO;
    const text = std.mem.span(text_z);
    const rc = copyOut(text, buf_ptr, cap, out_len);
    free(@ptrCast(text_z));
    return rc;
}

pub export fn sa_ts_node_free(handle: u64) i32 {
    sa_std.reg_mu.lockUncancelable(sio.io());
    defer sa_std.reg_mu.unlock(sio.io());
    const kv = sa_std.nodes.fetchRemove(handle) orelse return ERR_HANDLE;
    std.heap.page_allocator.destroy(kv.value);
    return OK;
}

pub export fn sa_ts_node_type(handle: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const text_z = sa_std.fns.node_type(entry.node) orelse return ERR_IO;
    return copyOut(std.mem.span(text_z), buf_ptr, cap, out_len);
}

pub export fn sa_ts_node_byte_range(handle: u64, out_start: ?*u32, out_end: ?*u32) i32 {
    const s_out = out_start orelse return ERR_INVALID;
    const e_out = out_end orelse return ERR_INVALID;
    s_out.* = 0;
    e_out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    s_out.* = sa_std.fns.node_start_byte(entry.node);
    e_out.* = sa_std.fns.node_end_byte(entry.node);
    return OK;
}

pub export fn sa_ts_node_text(handle: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const tree = getTree(entry.tree_handle) orelse return ERR_HANDLE;
    const start: usize = @intCast(sa_std.fns.node_start_byte(entry.node));
    const end: usize = @intCast(sa_std.fns.node_end_byte(entry.node));
    if (end > tree.source.len or start > end) return ERR_IO;
    return copyOut(tree.source[start..end], buf_ptr, cap, out_len);
}

pub export fn sa_ts_node_child_count(handle: u64, out_count: ?*u32) i32 {
    const out = out_count orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = sa_std.fns.node_child_count(entry.node);
    return OK;
}

pub export fn sa_ts_node_named_child_count(handle: u64, out_count: ?*u32) i32 {
    const out = out_count orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = sa_std.fns.node_named_child_count(entry.node);
    return OK;
}

pub export fn sa_ts_node_child(handle: u64, index: u32, named: u32, out_node: ?*u64) i32 {
    const out = out_node orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const child = if (named != 0) sa_std.fns.node_named_child(entry.node, index) else sa_std.fns.node_child(entry.node, index);
    if (sa_std.fns.node_is_null(child)) return OK; // out stays 0: no such child
    out.* = registerNode(child, entry.tree_handle) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_ts_node_child_by_field(handle: u64, field_ptr: ?[*]const u8, field_len: u64, out_node: ?*u64) i32 {
    const out = out_node orelse return ERR_INVALID;
    out.* = 0;
    const fp = field_ptr orelse return ERR_INVALID;
    if (field_len == 0 or field_len > 64) return ERR_INVALID;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const child = sa_std.fns.node_child_by_field_name(entry.node, fp, @intCast(field_len));
    if (sa_std.fns.node_is_null(child)) return OK; // out stays 0: field absent
    out.* = registerNode(child, entry.tree_handle) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_ts_node_parent(handle: u64, out_node: ?*u64) i32 {
    const out = out_node orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const parent = sa_std.fns.node_parent(entry.node);
    if (sa_std.fns.node_is_null(parent)) return OK; // root node: out stays 0 (no parent)
    out.* = registerNode(parent, entry.tree_handle) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_ts_node_is_named(handle: u64, out_flag: ?*u32) i32 {
    const out = out_flag orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = if (sa_std.fns.node_is_named(entry.node)) @as(u32, 1) else 0;
    return OK;
}

pub export fn sa_ts_node_is_missing(handle: u64, out_flag: ?*u32) i32 {
    const out = out_flag orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = if (sa_std.fns.node_is_missing(entry.node)) @as(u32, 1) else 0;
    return OK;
}

pub export fn sa_ts_node_has_error(handle: u64, out_flag: ?*u32) i32 {
    const out = out_flag orelse return ERR_INVALID;
    out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    out.* = if (sa_std.fns.node_has_error(entry.node)) @as(u32, 1) else 0;
    return OK;
}

pub export fn sa_ts_node_start_point(handle: u64, out_row: ?*u32, out_col: ?*u32) i32 {
    const r_out = out_row orelse return ERR_INVALID;
    const c_out = out_col orelse return ERR_INVALID;
    r_out.* = 0;
    c_out.* = 0;
    const entry = getNode(handle) orelse return ERR_HANDLE;
    const pt = sa_std.fns.node_start_point(entry.node);
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
    const pt = sa_std.fns.node_end_point(entry.node);
    r_out.* = pt.row;
    c_out.* = pt.column;
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
    sa_std.fns.tree_edit(entry.raw, &edit);
    return OK;
}
