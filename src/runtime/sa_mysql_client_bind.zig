const std = @import("std");
const Binding = @import("sa_mysql_client.zig").Binding;
const SA_MYSQL_ERR_PROTOCOL = @import("sa_mysql_client.zig").SA_MYSQL_ERR_PROTOCOL;
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_mysql_client.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_NO_MEMORY = @import("sa_mysql_client.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_OK = @import("sa_mysql_client.zig").SA_STD_OK;
const alloc = @import("sa_mysql_client.zig").alloc;
const connFrom = @import("sa_mysql_client.zig").connFrom;
const executeStmt = @import("sa_mysql_client.zig").executeStmt;
const mapQueryErr = @import("sa_mysql_client.zig").mapQueryErr;
const sliceArg = @import("sa_mysql_client.zig").sliceArg;
const stmtFrom = @import("sa_mysql_client.zig").stmtFrom;
const u64ToUsize = @import("sa_mysql_client.zig").u64ToUsize;
const writePacket = @import("sa_mysql_client.zig").writePacket;

pub fn bindSet(stmt_handle: u64, idx: u64, binding: Binding) i32 {
    const stmt = stmtFrom(stmt_handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const i = u64ToUsize(idx) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (i >= stmt.param_count) return SA_STD_ERR_INVALID_ARGUMENT;
    switch (stmt.bindings[i]) {
        .bytes => |old| alloc.free(old),
        else => {},
    }
    stmt.bindings[i] = binding;
    return SA_STD_OK;
}

pub export fn sa_mysql_stmt_bind_null(stmt: u64, idx: u64) i32 {
    return bindSet(stmt, idx, .null);
}

pub export fn sa_mysql_stmt_bind_i64(stmt: u64, idx: u64, value: i64) i32 {
    return bindSet(stmt, idx, .{ .i64 = value });
}

pub export fn sa_mysql_stmt_bind_u64(stmt: u64, idx: u64, value: u64) i32 {
    return bindSet(stmt, idx, .{ .u64 = value });
}

pub export fn sa_mysql_stmt_bind_f64(stmt: u64, idx: u64, value: f64) i32 {
    return bindSet(stmt, idx, .{ .f64 = value });
}

pub export fn sa_mysql_stmt_bind_bytes(stmt: u64, idx: u64, data_ptr: ?[*]const u8, data_len: u64) i32 {
    const data = sliceArg(data_ptr, data_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const owned = alloc.dupe(u8, data) catch return SA_STD_ERR_NO_MEMORY;
    const rc = bindSet(stmt, idx, .{ .bytes = owned });
    if (rc != SA_STD_OK) alloc.free(owned);
    return rc;
}

pub export fn sa_mysql_stmt_param_count(stmt: u64) u64 {
    const s = stmtFrom(stmt) orelse return 0;
    return @intCast(s.param_count);
}

pub export fn sa_mysql_stmt_execute(stmt_handle: u64, out_result: ?*u64) i32 {
    const slot = out_result orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const stmt = stmtFrom(stmt_handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (stmt.conn.dead) return SA_MYSQL_ERR_PROTOCOL;
    const result = executeStmt(stmt) catch |e| return mapQueryErr(stmt.conn, e);
    slot.* = @intFromPtr(result);
    return SA_STD_OK;
}

pub export fn sa_mysql_stmt_close(stmt_handle: u64) i32 {
    const stmt = stmtFrom(stmt_handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const conn = stmt.conn;
    if (!conn.dead) {
        // COM_STMT_CLOSE: no response packet.
        var payload: [5]u8 = .{ 0x19, 0, 0, 0, 0 };
        std.mem.writeInt(u32, payload[1..5], stmt.id, .little);
        conn.seq = 0;
        writePacket(conn, &payload) catch {};
    }
    for (conn.stmts.items, 0..) |s, i| {
        if (s == stmt) {
            _ = conn.stmts.orderedRemove(i);
            break;
        }
    }
    stmt.deinit();
    alloc.destroy(stmt);
    return SA_STD_OK;
}

pub export fn sa_mysql_errno(handle: u64) u32 {
    const conn = connFrom(handle) orelse return 0;
    return conn.err_no;
}

pub export fn sa_mysql_sqlstate(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    pp.* = &conn.sql_state;
    ll.* = 5;
    return SA_STD_OK;
}
