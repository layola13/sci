const std = @import("std");
const Conn = @import("sa_mysql_client.zig").Conn;
const MYSQL_TYPE_DOUBLE = @import("sa_mysql_client.zig").MYSQL_TYPE_DOUBLE;
const MYSQL_TYPE_LONGLONG = @import("sa_mysql_client.zig").MYSQL_TYPE_LONGLONG;
const MYSQL_TYPE_NULL = @import("sa_mysql_client.zig").MYSQL_TYPE_NULL;
const MYSQL_TYPE_VAR_STRING = @import("sa_mysql_client.zig").MYSQL_TYPE_VAR_STRING;
const QueryError = @import("sa_mysql_client.zig").QueryError;
const Result = @import("sa_mysql_client.zig").Result;
const alloc = @import("sa_mysql_client.zig").alloc;
const isEofPacket = @import("sa_mysql_client.zig").isEofPacket;
const mapReadErr = @import("sa_mysql_client.zig").mapReadErr;
const readPacket = @import("sa_mysql_client.zig").readPacket;
const runCommand = @import("sa_mysql_client.zig").runCommand;
const writeLenencString = @import("sa_mysql_client.zig").writeLenencString;
const writePacket = @import("sa_mysql_client.zig").writePacket;

pub const Binding = union(enum) {
    null,
    i64: i64,
    u64: u64,
    f64: f64,
    bytes: []u8,
};

pub const Stmt = struct {
    conn: *Conn,
    id: u32,
    param_count: usize,
    bindings: []Binding,

    fn deinit(self: *Stmt) void {
        for (self.bindings) |b| {
            switch (b) {
                .bytes => |bytes| alloc.free(bytes),
                else => {},
            }
        }
        if (self.bindings.len > 0) alloc.free(self.bindings);
    }
};

pub fn prepareStmt(conn: *Conn, sql: []const u8) QueryError!*Stmt {
    conn.clearServerError();
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(alloc);
    payload.append(alloc, 0x16) catch return error.OutOfMemory; // COM_STMT_PREPARE
    payload.appendSlice(alloc, sql) catch return error.OutOfMemory;
    conn.seq = 0;
    writePacket(conn, payload.items) catch |e| return mapReadErr(e);
    const first = readPacket(conn) catch |e| return mapReadErr(e);
    if (first.len == 0) return error.Protocol;
    if (first[0] == 0xFF) {
        conn.recordServerError(first);
        return error.ServerError;
    }
    if (first[0] != 0x00 or first.len < 12) return error.Protocol;
    const stmt_id = std.mem.readInt(u32, first[1..5], .little);
    const num_columns = std.mem.readInt(u16, first[5..7], .little);
    const num_params = std.mem.readInt(u16, first[7..9], .little);
    // Trailing: reserved(1) + warnings(2) — presence checked by len>=12.
    var i: usize = 0;
    while (i < num_params) : (i += 1) {
        const pkt = readPacket(conn) catch |e| return mapReadErr(e);
        if (pkt.len > 0 and pkt[0] == 0xFF) {
            conn.recordServerError(pkt);
            return error.ServerError;
        }
    }
    if (num_params > 0) {
        const pkt = readPacket(conn) catch |e| return mapReadErr(e);
        if (!isEofPacket(pkt)) return error.Protocol;
    }
    i = 0;
    while (i < num_columns) : (i += 1) {
        const pkt = readPacket(conn) catch |e| return mapReadErr(e);
        if (pkt.len > 0 and pkt[0] == 0xFF) {
            conn.recordServerError(pkt);
            return error.ServerError;
        }
    }
    if (num_columns > 0) {
        const pkt = readPacket(conn) catch |e| return mapReadErr(e);
        if (!isEofPacket(pkt)) return error.Protocol;
    }
    const stmt = alloc.create(Stmt) catch return error.OutOfMemory;
    errdefer alloc.destroy(stmt);
    const bindings = alloc.alloc(Binding, num_params) catch return error.OutOfMemory;
    for (bindings) |*b| b.* = .null;
    stmt.* = .{ .conn = conn, .id = stmt_id, .param_count = num_params, .bindings = bindings };
    conn.stmts.append(alloc, stmt) catch return error.OutOfMemory;
    return stmt;
}

pub fn executeStmt(stmt: *Stmt) QueryError!*Result {
    const conn = stmt.conn;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(alloc);
    payload.append(alloc, 0x17) catch return error.OutOfMemory; // COM_STMT_EXECUTE
    var idb: [4]u8 = undefined;
    std.mem.writeInt(u32, &idb, stmt.id, .little);
    payload.appendSlice(alloc, &idb) catch return error.OutOfMemory;
    payload.append(alloc, 0) catch return error.OutOfMemory; // cursor flags: none
    payload.appendSlice(alloc, &.{ 1, 0, 0, 0 }) catch return error.OutOfMemory; // iteration count
    const n = stmt.param_count;
    const bitmap_len = (n + 7) / 8;
    const bitmap_start = payload.items.len;
    payload.appendNTimes(alloc, 0, bitmap_len) catch return error.OutOfMemory;
    for (stmt.bindings, 0..) |b, i| {
        if (b == .null) payload.items[bitmap_start + i / 8] |= @as(u8, 1) << @intCast(i % 8);
    }
    payload.append(alloc, 1) catch return error.OutOfMemory; // new-params-bound-flag
    for (stmt.bindings) |b| {
        const t: u8 = switch (b) {
            .null => MYSQL_TYPE_NULL,
            .i64, .u64 => MYSQL_TYPE_LONGLONG,
            .f64 => MYSQL_TYPE_DOUBLE,
            .bytes => MYSQL_TYPE_VAR_STRING,
        };
        payload.append(alloc, t) catch return error.OutOfMemory;
        payload.append(alloc, if (b == .u64) 0x80 else 0) catch return error.OutOfMemory;
    }
    for (stmt.bindings) |b| {
        switch (b) {
            .null => {},
            .i64 => |v| {
                var buf: [8]u8 = undefined;
                std.mem.writeInt(i64, &buf, v, .little);
                payload.appendSlice(alloc, &buf) catch return error.OutOfMemory;
            },
            .u64 => |v| {
                var buf: [8]u8 = undefined;
                std.mem.writeInt(u64, &buf, v, .little);
                payload.appendSlice(alloc, &buf) catch return error.OutOfMemory;
            },
            .f64 => |v| {
                var buf: [8]u8 = undefined;
                std.mem.writeInt(u64, &buf, @bitCast(v), .little);
                payload.appendSlice(alloc, &buf) catch return error.OutOfMemory;
            },
            .bytes => |bytes| writeLenencString(&payload, alloc, bytes) catch return error.OutOfMemory,
        }
    }
    return runCommand(conn, payload.items, true);
}
