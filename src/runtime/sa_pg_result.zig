const std = @import("std");
const Conn = @import("sa_pg.zig").Conn;
const ERR_INVALID = @import("sa_pg.zig").ERR_INVALID;
const ERR_NOT_FOUND = @import("sa_pg.zig").ERR_NOT_FOUND;
const OK = @import("sa_pg.zig").OK;
const copyOut = @import("sa_pg.zig").copyOut;
const lookupConn = @import("sa_pg.zig").lookupConn;
const parseTagCount = @import("sa_pg.zig").parseTagCount;

pub fn resultConn(handle: u64) ?*Conn {
    const conn = lookupConn(handle) orelse return null;
    if (!conn.has_result) return null;
    return conn;
}

pub export fn sa_pg_result_rows(handle: u64, out_rows: ?*u64) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const o = out_rows orelse return ERR_INVALID;
    o.* = @intCast(conn.result.rows.items.len);
    return OK;
}

pub export fn sa_pg_result_cols(handle: u64, out_cols: ?*u64) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const o = out_cols orelse return ERR_INVALID;
    o.* = @intCast(conn.result.fields.items.len);
    return OK;
}

pub export fn sa_pg_col_name(handle: u64, col: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    if (col >= conn.result.fields.items.len) return ERR_INVALID;
    return copyOut(conn.result.fields.items[@intCast(col)].name, out, cap, out_len);
}

pub export fn sa_pg_col_type_oid(handle: u64, col: u64, out_oid: ?*u32) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    if (col >= conn.result.fields.items.len) return ERR_INVALID;
    const o = out_oid orelse return ERR_INVALID;
    o.* = conn.result.fields.items[@intCast(col)].type_oid;
    return OK;
}

pub fn cellAt(conn: *Conn, row: u64, col: u64) ?*const ?[]u8 {
    if (row >= conn.result.rows.items.len) return null;
    const r = &conn.result.rows.items[@intCast(row)];
    if (col >= r.items.len) return null;
    return &r.items[@intCast(col)];
}

pub export fn sa_pg_cell_is_null(handle: u64, row: u64, col: u64, out_is_null: ?*u32) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const cell = cellAt(conn, row, col) orelse return ERR_INVALID;
    const o = out_is_null orelse return ERR_INVALID;
    o.* = if (cell.* == null) 1 else 0;
    return OK;
}

pub export fn sa_pg_cell_len(handle: u64, row: u64, col: u64, out_len: ?*u64) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const cell = cellAt(conn, row, col) orelse return ERR_INVALID;
    const o = out_len orelse return ERR_INVALID;
    o.* = if (cell.*) |bytes| @intCast(bytes.len) else 0;
    return OK;
}

pub export fn sa_pg_cell_copy(handle: u64, row: u64, col: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const cell = cellAt(conn, row, col) orelse return ERR_INVALID;
    const bytes = cell.* orelse return ERR_NOT_FOUND; // NULL cell
    return copyOut(bytes, out, cap, out_len);
}

pub export fn sa_pg_cell_i64(handle: u64, row: u64, col: u64, out_value: ?*i64) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const cell = cellAt(conn, row, col) orelse return ERR_INVALID;
    const bytes = cell.* orelse return ERR_NOT_FOUND;
    const o = out_value orelse return ERR_INVALID;
    const text = std.mem.trim(u8, bytes, " ");
    o.* = std.fmt.parseInt(i64, text, 10) catch return ERR_INVALID;
    return OK;
}

pub export fn sa_pg_cell_f64(handle: u64, row: u64, col: u64, out_value: ?*f64) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const cell = cellAt(conn, row, col) orelse return ERR_INVALID;
    const bytes = cell.* orelse return ERR_NOT_FOUND;
    const o = out_value orelse return ERR_INVALID;
    const text = std.mem.trim(u8, bytes, " ");
    if (std.mem.eql(u8, text, "Infinity")) {
        o.* = std.math.inf(f64);
    } else if (std.mem.eql(u8, text, "-Infinity")) {
        o.* = -std.math.inf(f64);
    } else if (std.mem.eql(u8, text, "NaN")) {
        o.* = std.math.nan(f64);
    } else {
        o.* = std.fmt.parseFloat(f64, text) catch return ERR_INVALID;
    }
    return OK;
}

pub export fn sa_pg_cell_bool(handle: u64, row: u64, col: u64, out_value: ?*u32) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const cell = cellAt(conn, row, col) orelse return ERR_INVALID;
    const bytes = cell.* orelse return ERR_NOT_FOUND;
    const o = out_value orelse return ERR_INVALID;
    if (bytes.len == 1 and bytes[0] == 't') {
        o.* = 1;
    } else if (bytes.len == 1 and bytes[0] == 'f') {
        o.* = 0;
    } else return ERR_INVALID;
    return OK;
}

pub export fn sa_pg_rows_affected(handle: u64, out_count: ?*u64) i32 {
    const conn = resultConn(handle) orelse return ERR_NOT_FOUND;
    const o = out_count orelse return ERR_INVALID;
    const n = parseTagCount(conn.result.tag) orelse return ERR_NOT_FOUND;
    o.* = n;
    return OK;
}
