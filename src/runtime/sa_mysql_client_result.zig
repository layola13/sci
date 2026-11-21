const std = @import("std");
const Column = @import("sa_mysql_client.zig").Column;
const Conn = @import("sa_mysql_client.zig").Conn;
const IoError = @import("sa_mysql_client.zig").IoError;
const LenencInt = @import("sa_mysql_client.zig").LenencInt;
const MYSQL_TYPE_DATE = @import("sa_mysql_client.zig").MYSQL_TYPE_DATE;
const MYSQL_TYPE_DATETIME = @import("sa_mysql_client.zig").MYSQL_TYPE_DATETIME;
const MYSQL_TYPE_DOUBLE = @import("sa_mysql_client.zig").MYSQL_TYPE_DOUBLE;
const MYSQL_TYPE_FLOAT = @import("sa_mysql_client.zig").MYSQL_TYPE_FLOAT;
const MYSQL_TYPE_INT24 = @import("sa_mysql_client.zig").MYSQL_TYPE_INT24;
const MYSQL_TYPE_LONG = @import("sa_mysql_client.zig").MYSQL_TYPE_LONG;
const MYSQL_TYPE_LONGLONG = @import("sa_mysql_client.zig").MYSQL_TYPE_LONGLONG;
const MYSQL_TYPE_SHORT = @import("sa_mysql_client.zig").MYSQL_TYPE_SHORT;
const MYSQL_TYPE_TIME = @import("sa_mysql_client.zig").MYSQL_TYPE_TIME;
const MYSQL_TYPE_TIMESTAMP = @import("sa_mysql_client.zig").MYSQL_TYPE_TIMESTAMP;
const MYSQL_TYPE_TINY = @import("sa_mysql_client.zig").MYSQL_TYPE_TINY;
const MYSQL_TYPE_YEAR = @import("sa_mysql_client.zig").MYSQL_TYPE_YEAR;
const QueryError = @import("sa_mysql_client.zig").QueryError;
const Result = @import("sa_mysql_client.zig").Result;
const SERVER_MORE_RESULTS_EXISTS = @import("sa_mysql_client.zig").SERVER_MORE_RESULTS_EXISTS;
const alloc = @import("sa_mysql_client.zig").alloc;
const readLenencInt = @import("sa_mysql_client.zig").readLenencInt;
const readPacket = @import("sa_mysql_client.zig").readPacket;
const u64ToUsize = @import("sa_mysql_client.zig").u64ToUsize;
const writePacket = @import("sa_mysql_client.zig").writePacket;

pub const Cursor = struct {
    bytes: []const u8,
    pos: usize = 0,

    fn remaining(self: *const Cursor) usize {
        return self.bytes.len - self.pos;
    }
    fn byte(self: *Cursor) ?u8 {
        if (self.pos >= self.bytes.len) return null;
        defer self.pos += 1;
        return self.bytes[self.pos];
    }
    fn take(self: *Cursor, n: usize) ?[]const u8 {
        if (self.pos + n > self.bytes.len) return null;
        defer self.pos += n;
        return self.bytes[self.pos .. self.pos + n];
    }
    fn u16le(self: *Cursor) ?u16 {
        const b = self.take(2) orelse return null;
        return std.mem.readInt(u16, b[0..2], .little);
    }
    fn u32le(self: *Cursor) ?u32 {
        const b = self.take(4) orelse return null;
        return std.mem.readInt(u32, b[0..4], .little);
    }
    fn lenencInt(self: *Cursor) ?LenencInt {
        const r = readLenencInt(self.bytes, self.pos) orelse return null;
        self.pos = r.next;
        return r;
    }
    fn lenencBytes(self: *Cursor) ?[]const u8 {
        const li = self.lenencInt() orelse return null;
        if (li.is_null) return null;
        const n = u64ToUsize(li.value) orelse return null;
        return self.take(n);
    }
};

pub fn isEofPacket(p: []const u8) bool {
    return p.len >= 1 and p[0] == 0xFE and p.len < 9;
}

pub const OkInfo = struct { affected: u64 = 0, insert_id: u64 = 0, status: u16 = 0, warnings: u16 = 0 };

pub fn parseOkPacket(p: []const u8) ?OkInfo {
    if (p.len == 0 or p[0] != 0x00) return null;
    var c = Cursor{ .bytes = p, .pos = 1 };
    const affected = c.lenencInt() orelse return null;
    const insert = c.lenencInt() orelse return null;
    var info = OkInfo{ .affected = affected.value, .insert_id = insert.value };
    if (c.remaining() >= 4) {
        info.status = c.u16le() orelse return null;
        info.warnings = c.u16le() orelse return null;
    }
    return info;
}

pub fn parseColumnDef(p: []const u8) QueryError!Column {
    var c = Cursor{ .bytes = p };
    // catalog, schema, table, org_table — skipped; name kept.
    _ = c.lenencBytes() orelse return error.Protocol;
    _ = c.lenencBytes() orelse return error.Protocol;
    _ = c.lenencBytes() orelse return error.Protocol;
    _ = c.lenencBytes() orelse return error.Protocol;
    const name = c.lenencBytes() orelse return error.Protocol;
    _ = c.lenencBytes() orelse return error.Protocol; // org_name
    _ = c.lenencInt() orelse return error.Protocol; // fixed-fields length
    const charset = c.u16le() orelse return error.Protocol;
    const col_len = c.u32le() orelse return error.Protocol;
    const type_code = c.byte() orelse return error.Protocol;
    const flags = c.u16le() orelse return error.Protocol;
    const decimals = c.byte() orelse return error.Protocol;
    return .{
        .name = alloc.dupe(u8, name) catch return error.OutOfMemory,
        .type_code = type_code,
        .flags = flags,
        .charset = charset,
        .column_length = col_len,
        .decimals = decimals,
    };
}

pub fn readOneResult(conn: *Conn, first: []const u8, binary_rows: bool) QueryError!*Result {
    if (first.len == 0) return error.Protocol;
    if (first[0] == 0xFF) {
        conn.recordServerError(first);
        return error.ServerError;
    }
    const result = alloc.create(Result) catch return error.OutOfMemory;
    errdefer alloc.destroy(result);
    result.* = .{ .conn = conn };
    errdefer result.deinit();

    if (first[0] == 0x00) {
        // OK packet: statement produced no result set.
        const ok = parseOkPacket(first) orelse return error.Protocol;
        result.affected_rows = ok.affected;
        result.last_insert_id = ok.insert_id;
        result.warning_count = ok.warnings;
        result.status_flags = ok.status;
        conn.status_flags = ok.status;
        return result;
    }
    if (first[0] == 0xFB) {
        // LOCAL INFILE request: v1 refuses; the protocol offers no
        // clean way to decline mid-stream, so the connection dies.
        conn.markDead();
        return error.Unsupported;
    }

    var fc = Cursor{ .bytes = first };
    const col_count_li = fc.lenencInt() orelse return error.Protocol;
    if (col_count_li.is_null) return error.Protocol;
    const col_count = u64ToUsize(col_count_li.value) orelse return error.Protocol;
    result.has_result_set = true;
    result.columns = alloc.alloc(Column, col_count) catch return error.OutOfMemory;
    for (0..col_count) |i| {
        const pkt = readPacket(conn) catch |e| return mapReadErr(e);
        result.columns[i] = try parseColumnDef(pkt);
        result.columns_filled = i + 1;
    }
    // EOF packet after the column definitions (classic, since
    // CLIENT_DEPRECATE_EOF is never negotiated).
    {
        const pkt = readPacket(conn) catch |e| return mapReadErr(e);
        if (pkt.len > 0 and pkt[0] == 0xFF) {
            conn.recordServerError(pkt);
            return error.ServerError;
        }
        if (!isEofPacket(pkt)) return error.Protocol;
    }
    // Rows until the terminating EOF (or OK) packet.
    while (true) {
        const pkt = readPacket(conn) catch |e| return mapReadErr(e);
        if (pkt.len == 0) return error.Protocol;
        if (pkt[0] == 0xFF) {
            conn.recordServerError(pkt);
            return error.ServerError;
        }
        if (isEofPacket(pkt)) {
            // EOF terminator: 0xFE, warnings(2), status flags(2).
            if (pkt.len >= 5) {
                result.warning_count = std.mem.readInt(u16, pkt[1..3], .little);
                result.status_flags = std.mem.readInt(u16, pkt[3..5], .little);
                conn.status_flags = result.status_flags;
            }
            break;
        }
        // A 0x00-leading packet here is a ROW (binary rows start with
        // a 0x00 header; a text row may start with a 0x00 length for
        // an empty first column). The only terminator is the EOF
        // packet: v1 never negotiates CLIENT_DEPRECATE_EOF, so no
        // OK-packet terminator can legitimately appear.
        const row = if (binary_rows)
            try parseBinaryRow(conn, result.columns, pkt)
        else
            try parseTextRow(result.columns.len, pkt);
        result.rows.append(alloc, row) catch return error.OutOfMemory;
    }
    return result;
}

pub fn mapReadErr(e: IoError) QueryError {
    return switch (e) {
        error.Io => error.Io,
        error.Protocol => error.Protocol,
        error.OutOfMemory => error.OutOfMemory,
    };
}

pub fn parseTextRow(col_count: usize, pkt: []const u8) QueryError![]const ?[]u8 {
    const row = alloc.alloc(?[]u8, col_count) catch return error.OutOfMemory;
    errdefer alloc.free(row);
    var c = Cursor{ .bytes = pkt };
    var filled: usize = 0;
    errdefer {
        for (row[0..filled]) |v| {
            if (v) |b| alloc.free(b);
        }
    }
    for (0..col_count) |i| {
        const li = c.lenencInt() orelse return error.Protocol;
        if (li.is_null) {
            row[i] = null;
        } else {
            const n = u64ToUsize(li.value) orelse return error.Protocol;
            const raw = c.take(n) orelse return error.Protocol;
            row[i] = alloc.dupe(u8, raw) catch return error.OutOfMemory;
        }
        filled += 1;
    }
    return row;
}

pub fn parseBinaryRow(conn: *Conn, columns: []const Column, pkt: []const u8) QueryError![]const ?[]u8 {
    _ = conn;
    if (pkt.len == 0 or pkt[0] != 0x00) return error.Protocol;
    const row = alloc.alloc(?[]u8, columns.len) catch return error.OutOfMemory;
    errdefer alloc.free(row);
    var filled: usize = 0;
    errdefer {
        for (row[0..filled]) |v| {
            if (v) |b| alloc.free(b);
        }
    }
    const bitmap_len = (columns.len + 7 + 2) / 8;
    if (pkt.len < 1 + bitmap_len) return error.Protocol;
    const bitmap = pkt[1 .. 1 + bitmap_len];
    var c = Cursor{ .bytes = pkt, .pos = 1 + bitmap_len };
    for (columns, 0..) |col, i| {
        const bitpos = i + 2;
        const is_null = (bitmap[bitpos / 8] >> @intCast(bitpos % 8)) & 1 == 1;
        if (is_null) {
            row[i] = null;
            filled += 1;
            continue;
        }
        row[i] = try decodeBinaryValue(col, &c);
        filled += 1;
    }
    return row;
}

pub fn fmtAlloc(comptime fmt: []const u8, args: anytype) QueryError![]u8 {
    return std.fmt.allocPrint(alloc, fmt, args) catch return error.OutOfMemory;
}

pub fn decodeBinaryValue(col: Column, c: *Cursor) QueryError!?[]u8 {
    const unsigned = col.isUnsigned();
    switch (col.type_code) {
        MYSQL_TYPE_TINY => {
            const b = c.take(1) orelse return error.Protocol;
            if (unsigned) return try fmtAlloc("{d}", .{b[0]});
            return try fmtAlloc("{d}", .{@as(i8, @bitCast(b[0]))});
        },
        MYSQL_TYPE_SHORT, MYSQL_TYPE_YEAR => {
            const b = c.take(2) orelse return error.Protocol;
            const v = std.mem.readInt(u16, b[0..2], .little);
            if (unsigned or col.type_code == MYSQL_TYPE_YEAR)
                return try fmtAlloc("{d}", .{v});
            return try fmtAlloc("{d}", .{@as(i16, @bitCast(v))});
        },
        MYSQL_TYPE_LONG, MYSQL_TYPE_INT24 => {
            const b = c.take(4) orelse return error.Protocol;
            const v = std.mem.readInt(u32, b[0..4], .little);
            if (unsigned) return try fmtAlloc("{d}", .{v});
            return try fmtAlloc("{d}", .{@as(i32, @bitCast(v))});
        },
        MYSQL_TYPE_LONGLONG => {
            const b = c.take(8) orelse return error.Protocol;
            const v = std.mem.readInt(u64, b[0..8], .little);
            if (unsigned) return try fmtAlloc("{d}", .{v});
            return try fmtAlloc("{d}", .{@as(i64, @bitCast(v))});
        },
        MYSQL_TYPE_FLOAT => {
            const b = c.take(4) orelse return error.Protocol;
            const v: f32 = @bitCast(std.mem.readInt(u32, b[0..4], .little));
            return try fmtAlloc("{d}", .{v});
        },
        MYSQL_TYPE_DOUBLE => {
            const b = c.take(8) orelse return error.Protocol;
            const v: f64 = @bitCast(std.mem.readInt(u64, b[0..8], .little));
            return try fmtAlloc("{d}", .{v});
        },
        MYSQL_TYPE_DATE => {
            const n = c.byte() orelse return error.Protocol;
            const b = c.take(n) orelse return error.Protocol;
            if (n == 0) return try fmtAlloc("0000-00-00", .{});
            if (b.len < 4) return error.Protocol;
            const year = std.mem.readInt(u16, b[0..2], .little);
            return try fmtAlloc("{d:0>4}-{d:0>2}-{d:0>2}", .{ year, b[2], b[3] });
        },
        MYSQL_TYPE_DATETIME, MYSQL_TYPE_TIMESTAMP => {
            const n = c.byte() orelse return error.Protocol;
            const b = c.take(n) orelse return error.Protocol;
            if (n == 0) return try fmtAlloc("0000-00-00 00:00:00", .{});
            if (b.len < 4) return error.Protocol;
            const year = std.mem.readInt(u16, b[0..2], .little);
            if (b.len < 7) {
                return try fmtAlloc("{d:0>4}-{d:0>2}-{d:0>2} 00:00:00", .{ year, b[2], b[3] });
            }
            var base = try fmtAlloc("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ year, b[2], b[3], b[4], b[5], b[6] });
            if (b.len >= 11) {
                const micros = std.mem.readInt(u32, b[7..11], .little);
                if (micros != 0) {
                    const frac = try fmtAlloc(".{d:0>6}", .{micros});
                    defer alloc.free(frac);
                    // MySQL's text rendering trims trailing zeros.
                    var fl = frac.len;
                    while (fl > 1 and frac[fl - 1] == '0') fl -= 1;
                    const joined = std.mem.concat(alloc, u8, &.{ base, frac[0..fl] }) catch return error.OutOfMemory;
                    alloc.free(base);
                    base = joined;
                }
            }
            return base;
        },
        MYSQL_TYPE_TIME => {
            const n = c.byte() orelse return error.Protocol;
            const b = c.take(n) orelse return error.Protocol;
            if (n == 0) return try fmtAlloc("00:00:00", .{});
            if (b.len < 8) return error.Protocol;
            const neg = b[0] != 0;
            const days = std.mem.readInt(u32, b[1..5], .little);
            const hours: u64 = @as(u64, days) * 24 + b[5];
            var base = try fmtAlloc("{s}{d}:{d:0>2}:{d:0>2}", .{ if (neg) "-" else "", hours, b[6], b[7] });
            if (b.len >= 12) {
                const micros = std.mem.readInt(u32, b[8..12], .little);
                if (micros != 0) {
                    const frac = try fmtAlloc(".{d:0>6}", .{micros});
                    defer alloc.free(frac);
                    var fl = frac.len;
                    while (fl > 1 and frac[fl - 1] == '0') fl -= 1;
                    const joined = std.mem.concat(alloc, u8, &.{ base, frac[0..fl] }) catch return error.OutOfMemory;
                    alloc.free(base);
                    base = joined;
                }
            }
            return base;
        },
        else => {
            // Length-encoded byte string family: VARCHAR, VAR_STRING,
            // STRING, all BLOB widths, NEWDECIMAL, DECIMAL, ENUM, SET,
            // JSON, BIT (raw big-endian bytes, documented) and GEOMETRY
            // (raw bytes).
            const raw = c.lenencBytes() orelse return error.Protocol;
            return alloc.dupe(u8, raw) catch return error.OutOfMemory;
        },
    }
}

pub fn runCommand(conn: *Conn, payload: []const u8, binary_rows: bool) QueryError!*Result {
    conn.clearServerError();
    conn.seq = 0;
    writePacket(conn, payload) catch |e| return mapReadErr(e);
    var first = readPacket(conn) catch |e| return mapReadErr(e);
    const result = try readOneResult(conn, first, binary_rows);
    errdefer {
        result.deinit();
        alloc.destroy(result);
    }
    while (result.status_flags & SERVER_MORE_RESULTS_EXISTS != 0) {
        first = readPacket(conn) catch |e| return mapReadErr(e);
        const extra = try readOneResult(conn, first, binary_rows);
        result.status_flags = extra.status_flags;
        extra.deinit();
        alloc.destroy(extra);
    }
    conn.results.append(alloc, result) catch return error.OutOfMemory;
    return result;
}
