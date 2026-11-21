const std = @import("std");
const ALLOC = @import("sa_pg.zig").ALLOC;
const ERR_HANDLE = @import("sa_pg.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_pg.zig").ERR_INVALID;
const ERR_NOMEM = @import("sa_pg.zig").ERR_NOMEM;
const OK = @import("sa_pg.zig").OK;
const PgErr = @import("sa_pg.zig").PgErr;
const Stmt = @import("sa_pg.zig").Stmt;
const lookupStmt = @import("sa_pg.zig").lookupStmt;
const sliceOf = @import("sa_pg.zig").sliceOf;

pub fn bindSlot(stmt: *Stmt, index: u32) PgErr!*?[]u8 {
    if (index == 0 or index > stmt.binds.items.len) return error.InvalidArgument;
    return &stmt.binds.items[index - 1];
}

pub fn setBind(stmt: *Stmt, index: u32, value: ?[]const u8) i32 {
    const slot = bindSlot(stmt, index) catch return ERR_INVALID;
    if (slot.*) |old| ALLOC.free(old);
    slot.* = if (value) |v| (ALLOC.dupe(u8, v) catch return ERR_NOMEM) else null;
    return OK;
}

pub export fn sa_pg_bind_null(stmt_handle: u64, index: u32) i32 {
    const stmt = lookupStmt(stmt_handle) orelse return ERR_HANDLE;
    return setBind(stmt, index, null);
}

pub export fn sa_pg_bind_text(stmt_handle: u64, index: u32, value_ptr: ?[*]const u8, value_len: u64) i32 {
    const stmt = lookupStmt(stmt_handle) orelse return ERR_HANDLE;
    const value = sliceOf(value_ptr, value_len) orelse return ERR_INVALID;
    return setBind(stmt, index, value);
}

pub export fn sa_pg_bind_i64(stmt_handle: u64, index: u32, value: i64) i32 {
    const stmt = lookupStmt(stmt_handle) orelse return ERR_HANDLE;
    var buf: [24]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return ERR_INVALID;
    return setBind(stmt, index, text);
}

pub export fn sa_pg_bind_f64(stmt_handle: u64, index: u32, value: f64) i32 {
    const stmt = lookupStmt(stmt_handle) orelse return ERR_HANDLE;
    var buf: [40]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return ERR_INVALID;
    return setBind(stmt, index, text);
}

pub export fn sa_pg_bind_bool(stmt_handle: u64, index: u32, value: u32) i32 {
    const stmt = lookupStmt(stmt_handle) orelse return ERR_HANDLE;
    return setBind(stmt, index, if (value != 0) "t" else "f");
}
