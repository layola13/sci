const std = @import("std");
const Column = @import("sa_mysql_client.zig").Column;
const Conn = @import("sa_mysql_client.zig").Conn;
const Handshake = @import("sa_mysql_client.zig").Handshake;
const MYSQL_TYPE_DATETIME = @import("sa_mysql_client.zig").MYSQL_TYPE_DATETIME;
const MYSQL_TYPE_DOUBLE = @import("sa_mysql_client.zig").MYSQL_TYPE_DOUBLE;
const MYSQL_TYPE_LONG = @import("sa_mysql_client.zig").MYSQL_TYPE_LONG;
const MYSQL_TYPE_LONGLONG = @import("sa_mysql_client.zig").MYSQL_TYPE_LONGLONG;
const MYSQL_TYPE_TIME = @import("sa_mysql_client.zig").MYSQL_TYPE_TIME;
const MYSQL_TYPE_TINY = @import("sa_mysql_client.zig").MYSQL_TYPE_TINY;
const MYSQL_TYPE_VAR_STRING = @import("sa_mysql_client.zig").MYSQL_TYPE_VAR_STRING;
const SA_MYSQL_ERR_SERVER = @import("sa_mysql_client.zig").SA_MYSQL_ERR_SERVER;
const SA_STD_OK = @import("sa_mysql_client.zig").SA_STD_OK;
const UNSIGNED_FLAG = @import("sa_mysql_client.zig").UNSIGNED_FLAG;
const alloc = @import("sa_mysql_client.zig").alloc;
const cachingSha2Token = @import("sa_mysql_client.zig").cachingSha2Token;
const nativePasswordToken = @import("sa_mysql_client.zig").nativePasswordToken;
const parseBinaryRow = @import("sa_mysql_client.zig").parseBinaryRow;
const readLenencInt = @import("sa_mysql_client.zig").readLenencInt;
const sa_mysql_close = @import("sa_mysql_client.zig").sa_mysql_close;
const sa_mysql_connect = @import("sa_mysql_client.zig").sa_mysql_connect;
const sa_mysql_connection_id = @import("sa_mysql_client.zig").sa_mysql_connection_id;
const sa_mysql_errno = @import("sa_mysql_client.zig").sa_mysql_errno;
const sa_mysql_error_message = @import("sa_mysql_client.zig").sa_mysql_error_message;
const sa_mysql_ping = @import("sa_mysql_client.zig").sa_mysql_ping;
const sa_mysql_prepare = @import("sa_mysql_client.zig").sa_mysql_prepare;
const sa_mysql_query = @import("sa_mysql_client.zig").sa_mysql_query;
const sa_mysql_result_column_count = @import("sa_mysql_client.zig").sa_mysql_result_column_count;
const sa_mysql_result_column_name = @import("sa_mysql_client.zig").sa_mysql_result_column_name;
const sa_mysql_result_column_type = @import("sa_mysql_client.zig").sa_mysql_result_column_type;
const sa_mysql_result_free = @import("sa_mysql_client.zig").sa_mysql_result_free;
const sa_mysql_result_has_result_set = @import("sa_mysql_client.zig").sa_mysql_result_has_result_set;
const sa_mysql_result_next = @import("sa_mysql_client.zig").sa_mysql_result_next;
const sa_mysql_result_row_count = @import("sa_mysql_client.zig").sa_mysql_result_row_count;
const sa_mysql_result_value = @import("sa_mysql_client.zig").sa_mysql_result_value;
const sa_mysql_server_version = @import("sa_mysql_client.zig").sa_mysql_server_version;
const sa_mysql_sqlstate = @import("sa_mysql_client.zig").sa_mysql_sqlstate;
const sa_mysql_stmt_bind_bytes = @import("sa_mysql_client.zig").sa_mysql_stmt_bind_bytes;
const sa_mysql_stmt_bind_i64 = @import("sa_mysql_client.zig").sa_mysql_stmt_bind_i64;
const sa_mysql_stmt_close = @import("sa_mysql_client.zig").sa_mysql_stmt_close;
const sa_mysql_stmt_execute = @import("sa_mysql_client.zig").sa_mysql_stmt_execute;
const sa_mysql_stmt_param_count = @import("sa_mysql_client.zig").sa_mysql_stmt_param_count;
const sio = @import("sa_mysql_client.zig").sio;
const testing = @import("sa_mysql_client.zig").testing;
const u64ToUsize = @import("sa_mysql_client.zig").u64ToUsize;
const writeLenencInt = @import("sa_mysql_client.zig").writeLenencInt;
const writeLenencString = @import("sa_mysql_client.zig").writeLenencString;

test "mysql lenenc int roundtrip and boundaries" {
    const cases = [_]u64{ 0, 1, 250, 251, 65535, 65536, 16777215, 16777216, 4294967295, 18446744073709551615 };
    for (cases) |v| {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(testing.allocator);
        try writeLenencInt(&buf, testing.allocator, v);
        const r = readLenencInt(buf.items, 0) orelse return error.TestUnexpectedResult;
        try testing.expectEqual(v, r.value);
        try testing.expect(!r.is_null);
        try testing.expectEqual(buf.items.len, r.next);
    }
    const null_r = readLenencInt(&.{0xFB}, 0) orelse return error.TestUnexpectedResult;
    try testing.expect(null_r.is_null);
    // Truncation is a parse failure, never a panic.
    try testing.expect(readLenencInt(&.{ 0xFC, 0x01 }, 0) == null);
    try testing.expect(readLenencInt(&.{ 0xFE, 0x01, 0x02 }, 0) == null);
}

test "mysql native password scramble known vector" {
    // Vector computed independently (Python hashlib):
    // pw "s3cret!", salt "1234567890abcdefghij".
    var expected: [20]u8 = undefined;
    hexToBytes("2016259fa51e35448bff4fbeb2c9262025edfac9", &expected);
    var out: [20]u8 = undefined;
    const n = nativePasswordToken("s3cret!", "1234567890abcdefghij", &out);
    try testing.expectEqual(@as(usize, 20), n);
    try testing.expectEqualSlices(u8, &expected, &out);
    // Empty password -> empty token.
    try testing.expectEqual(@as(usize, 0), nativePasswordToken("", "1234567890abcdefghij", &out));
}

test "mysql caching_sha2 scramble known vector" {
    var expected: [32]u8 = undefined;
    hexToBytes("bbc1105a220a1cd70d21753e02b7c0fc818089eba2ce0627f9d0e80d150a54ce", &expected);
    var out: [32]u8 = undefined;
    const n = cachingSha2Token("s3cret!", "1234567890abcdefghij", &out);
    try testing.expectEqual(@as(usize, 32), n);
    try testing.expectEqualSlices(u8, &expected, &out);
    try testing.expectEqual(@as(usize, 0), cachingSha2Token("", "1234567890abcdefghij", &out));
}

test "mysql server error packet is recorded verbatim" {
    var conn = Conn{};
    defer conn.deinit();
    // errno 1064 (0x0428), sqlstate "42000", message.
    var pkt: std.ArrayList(u8) = .empty;
    defer pkt.deinit(testing.allocator);
    try pkt.appendSlice(testing.allocator, &.{ 0xFF, 0x28, 0x04, '#' });
    try pkt.appendSlice(testing.allocator, "42000");
    try pkt.appendSlice(testing.allocator, "You have an error in your SQL syntax");
    conn.recordServerError(pkt.items);
    try testing.expectEqual(@as(u32, 1064), conn.err_no);
    try testing.expectEqualStrings("42000", &conn.sql_state);
    try testing.expectEqualStrings("You have an error in your SQL syntax", conn.err_msg);
}

test "mysql binary row decoding renders text values" {
    var dummy = Conn{};
    const columns = [_]Column{
        .{ .name = @constCast("dt"), .type_code = MYSQL_TYPE_DATETIME, .flags = 0, .charset = 63, .column_length = 19, .decimals = 0 },
        .{ .name = @constCast("tm"), .type_code = MYSQL_TYPE_TIME, .flags = 0, .charset = 63, .column_length = 10, .decimals = 0 },
        .{ .name = @constCast("d"), .type_code = MYSQL_TYPE_DOUBLE, .flags = 0, .charset = 63, .column_length = 22, .decimals = 31 },
        .{ .name = @constCast("t"), .type_code = MYSQL_TYPE_TINY, .flags = 0, .charset = 63, .column_length = 4, .decimals = 0 },
        .{ .name = @constCast("u"), .type_code = MYSQL_TYPE_LONGLONG, .flags = UNSIGNED_FLAG, .charset = 63, .column_length = 20, .decimals = 0 },
    };
    var pkt: std.ArrayList(u8) = .empty;
    defer pkt.deinit(testing.allocator);
    try pkt.append(testing.allocator, 0x00); // binary row header
    try pkt.append(testing.allocator, 0x00); // null bitmap: nothing null
    // DATETIME 2026-10-28 20:36:51 (7-byte form)
    try pkt.append(testing.allocator, 7);
    var yb: [2]u8 = undefined;
    std.mem.writeInt(u16, &yb, 2026, .little);
    try pkt.appendSlice(testing.allocator, &yb);
    try pkt.appendSlice(testing.allocator, &.{ 10, 28, 20, 36, 51 });
    // TIME 26:03:04 (8-byte form: neg, days=1, 02:03:04)
    try pkt.append(testing.allocator, 8);
    try pkt.append(testing.allocator, 0);
    var db: [4]u8 = undefined;
    std.mem.writeInt(u32, &db, 1, .little);
    try pkt.appendSlice(testing.allocator, &db);
    try pkt.appendSlice(testing.allocator, &.{ 2, 3, 4 });
    // DOUBLE 3.5
    var fb: [8]u8 = undefined;
    std.mem.writeInt(u64, &fb, @bitCast(@as(f64, 3.5)), .little);
    try pkt.appendSlice(testing.allocator, &fb);
    // TINY -5
    try pkt.append(testing.allocator, 0xFB);
    // LONGLONG unsigned max
    std.mem.writeInt(u64, &fb, 18446744073709551615, .little);
    try pkt.appendSlice(testing.allocator, &fb);

    const row = try parseBinaryRow(&dummy, &columns, pkt.items);
    defer {
        for (row) |v| {
            if (v) |b| alloc.free(b);
        }
        alloc.free(row);
    }
    try testing.expectEqualStrings("2026-10-28 20:36:51", row[0].?);
    try testing.expectEqualStrings("26:03:04", row[1].?);
    try testing.expectEqualStrings("3.5", row[2].?);
    try testing.expectEqualStrings("-5", row[3].?);
    try testing.expectEqualStrings("18446744073709551615", row[4].?);
}

test "mysql client end-to-end against scripted fake server" {
    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const port: u16 = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    var fake = FakeServer{ .listener = &listener };
    const thread = try std.Thread.spawn(.{}, FakeServer.run, .{&fake});

    var conn: u64 = 0;
    const host = "127.0.0.1";
    const user = "tester";
    const pass = "s3cret!";
    var rc = sa_mysql_connect(host.ptr, host.len, port, user.ptr, user.len, pass.ptr, pass.len, null, 0, &conn);
    try testing.expectEqual(SA_STD_OK, rc);
    try testing.expect(conn != 0);
    var closed = false;
    defer if (!closed) {
        _ = sa_mysql_close(conn);
    };
    try testing.expectEqual(@as(u32, 42), sa_mysql_connection_id(conn));
    {
        var vp: ?[*]const u8 = null;
        var vl: u64 = 0;
        try testing.expectEqual(SA_STD_OK, sa_mysql_server_version(conn, &vp, &vl));
        try testing.expectEqualStrings("8.0.0-fake", vp.?[0..@intCast(vl)]);
    }

    // Text query.
    var res: u64 = 0;
    const q1 = "select id, name from t";
    rc = sa_mysql_query(conn, q1.ptr, q1.len, &res);
    try testing.expectEqual(SA_STD_OK, rc);
    try testing.expectEqual(@as(u32, 1), sa_mysql_result_has_result_set(res));
    try testing.expectEqual(@as(u64, 2), sa_mysql_result_column_count(res));
    try testing.expectEqual(@as(u64, 2), sa_mysql_result_row_count(res));
    {
        var np: ?[*]const u8 = null;
        var nl: u64 = 0;
        try testing.expectEqual(SA_STD_OK, sa_mysql_result_column_name(res, 0, &np, &nl));
        try testing.expectEqualStrings("id", np.?[0..@intCast(nl)]);
        try testing.expectEqual(SA_STD_OK, sa_mysql_result_column_name(res, 1, &np, &nl));
        try testing.expectEqualStrings("name", np.?[0..@intCast(nl)]);
    }
    try testing.expectEqual(@as(u32, MYSQL_TYPE_LONG), sa_mysql_result_column_type(res, 0));
    const expectVal = struct {
        fn call(r: u64, row: u64, col: u64, want: []const u8) !void {
            var vp: ?[*]const u8 = null;
            var vl: u64 = 0;
            var isn: u32 = 1;
            try testing.expectEqual(SA_STD_OK, sa_mysql_result_value(r, row, col, &vp, &vl, &isn));
            try testing.expectEqual(@as(u32, 0), isn);
            try testing.expectEqualStrings(want, vp.?[0..@intCast(vl)]);
        }
    };
    try expectVal.call(res, 0, 0, "42");
    try expectVal.call(res, 0, 1, "hello");
    try expectVal.call(res, 1, 0, "-7");
    {
        var vp: ?[*]const u8 = null;
        var vl: u64 = 1;
        var isn: u32 = 0;
        try testing.expectEqual(SA_STD_OK, sa_mysql_result_value(res, 1, 1, &vp, &vl, &isn));
        try testing.expectEqual(@as(u32, 1), isn);
        try testing.expectEqual(@as(u64, 0), vl);
    }
    // Sequential cursor.
    var row_idx: u64 = 99;
    try testing.expectEqual(@as(i32, 1), sa_mysql_result_next(res, &row_idx));
    try testing.expectEqual(@as(u64, 0), row_idx);
    try testing.expectEqual(@as(i32, 1), sa_mysql_result_next(res, &row_idx));
    try testing.expectEqual(@as(u64, 1), row_idx);
    try testing.expectEqual(@as(i32, 0), sa_mysql_result_next(res, &row_idx));
    try testing.expectEqual(SA_STD_OK, sa_mysql_result_free(res));

    // Prepared statement round trip.
    var stmt: u64 = 0;
    const prep_sql = "insert into t values (?, ?)";
    rc = sa_mysql_prepare(conn, prep_sql.ptr, prep_sql.len, &stmt);
    try testing.expectEqual(SA_STD_OK, rc);
    try testing.expectEqual(@as(u64, 2), sa_mysql_stmt_param_count(stmt));
    try testing.expectEqual(SA_STD_OK, sa_mysql_stmt_bind_i64(stmt, 0, -99));
    const word = "xyz";
    try testing.expectEqual(SA_STD_OK, sa_mysql_stmt_bind_bytes(stmt, 1, word.ptr, word.len));
    var res2: u64 = 0;
    rc = sa_mysql_stmt_execute(stmt, &res2);
    try testing.expectEqual(SA_STD_OK, rc);
    try testing.expectEqual(@as(u64, 1), sa_mysql_result_row_count(res2));
    try expectVal.call(res2, 0, 0, "-99");
    {
        var vp: ?[*]const u8 = null;
        var vl: u64 = 1;
        var isn: u32 = 0;
        try testing.expectEqual(SA_STD_OK, sa_mysql_result_value(res2, 0, 1, &vp, &vl, &isn));
        try testing.expectEqual(@as(u32, 1), isn);
    }
    try testing.expectEqual(SA_STD_OK, sa_mysql_result_free(res2));
    try testing.expectEqual(SA_STD_OK, sa_mysql_stmt_close(stmt));

    // Server ERR packet surfaces verbatim.
    const bad = "select bad";
    var res3: u64 = 0;
    rc = sa_mysql_query(conn, bad.ptr, bad.len, &res3);
    try testing.expectEqual(SA_MYSQL_ERR_SERVER, rc);
    try testing.expectEqual(@as(u64, 0), res3);
    try testing.expectEqual(@as(u32, 1146), sa_mysql_errno(conn));
    {
        var sp: ?[*]const u8 = null;
        var sl: u64 = 0;
        try testing.expectEqual(SA_STD_OK, sa_mysql_sqlstate(conn, &sp, &sl));
        try testing.expectEqualStrings("42S02", sp.?[0..@intCast(sl)]);
        var mp: ?[*]const u8 = null;
        var ml: u64 = 0;
        try testing.expectEqual(SA_STD_OK, sa_mysql_error_message(conn, &mp, &ml));
        try testing.expectEqualStrings("Table 'x.y' doesn't exist", mp.?[0..@intCast(ml)]);
    }

    try testing.expectEqual(SA_STD_OK, sa_mysql_ping(conn));
    try testing.expectEqual(SA_STD_OK, sa_mysql_close(conn));
    closed = true;
    thread.join();
    try testing.expect(!fake.failed);
    try testing.expect(fake.token_ok);
    try testing.expect(fake.user_ok);
    try testing.expect(fake.saw_query);
    try testing.expect(fake.saw_prepare);
    try testing.expectEqual(@as(i64, -99), fake.exec_i64);
    try testing.expectEqualStrings("xyz", fake.exec_text_buf[0..fake.exec_text_len]);
    try testing.expect(fake.saw_close);
    try testing.expect(fake.saw_bad_query);
    try testing.expect(fake.saw_ping);
    try testing.expect(fake.saw_quit);
}

pub fn hexToBytes(comptime hex: []const u8, out: []u8) void {
    std.debug.assert(hex.len == out.len * 2);
    for (out, 0..) |*b, i| {
        b.* = std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16) catch unreachable;
    }
}

const FakeServer = struct {
    listener: *std.Io.net.Server,
    token_ok: bool = false,
    user_ok: bool = false,
    saw_query: bool = false,
    saw_prepare: bool = false,
    exec_i64: i64 = 0,
    exec_text_buf: [64]u8 = undefined,
    exec_text_len: usize = 0,
    saw_close: bool = false,
    saw_bad_query: bool = false,
    saw_ping: bool = false,
    saw_quit: bool = false,
    failed: bool = false,

    fn send(w: *std.Io.net.Stream.Writer, seq: u8, payload: []const u8) bool {
        var hdr: [4]u8 = .{ @intCast(payload.len & 0xFF), @intCast((payload.len >> 8) & 0xFF), @intCast((payload.len >> 16) & 0xFF), seq };
        w.interface.writeAll(&hdr) catch return false;
        w.interface.writeAll(payload) catch return false;
        w.interface.flush() catch return false;
        return true;
    }

    fn readExact(fd: std.posix.fd_t, buf: []u8) bool {
        var off: usize = 0;
        while (off < buf.len) {
            const n = std.posix.read(fd, buf[off..]) catch return false;
            if (n == 0) return false;
            off += n;
        }
        return true;
    }

    fn srvReadPacket(fd: std.posix.fd_t, a: std.mem.Allocator, out: *std.ArrayList(u8)) bool {
        var hdr: [4]u8 = undefined;
        if (!readExact(fd, &hdr)) return false;
        const len: usize = @as(usize, hdr[0]) | (@as(usize, hdr[1]) << 8) | (@as(usize, hdr[2]) << 16);
        out.clearRetainingCapacity();
        out.resize(a, len) catch return false;
        return readExact(fd, out.items);
    }

    fn colDef(a: std.mem.Allocator, name: []const u8, type_code: u8, flags: u16) ?[]u8 {
        var d: std.ArrayList(u8) = .empty;
        errdefer d.deinit(a);
        writeLenencString(&d, a, "def") catch return null;
        writeLenencString(&d, a, "") catch return null;
        writeLenencString(&d, a, "") catch return null;
        writeLenencString(&d, a, "") catch return null;
        writeLenencString(&d, a, name) catch return null;
        writeLenencString(&d, a, "") catch return null;
        d.append(a, 0x0C) catch return null;
        var b2: [2]u8 = undefined;
        std.mem.writeInt(u16, &b2, 63, .little);
        d.appendSlice(a, &b2) catch return null;
        var b4: [4]u8 = undefined;
        std.mem.writeInt(u32, &b4, 20, .little);
        d.appendSlice(a, &b4) catch return null;
        d.append(a, type_code) catch return null;
        std.mem.writeInt(u16, &b2, flags, .little);
        d.appendSlice(a, &b2) catch return null;
        d.append(a, 0) catch return null; // decimals
        d.appendSlice(a, &.{ 0, 0 }) catch return null; // filler
        return d.toOwnedSlice(a) catch null;
    }

    fn run(self: *FakeServer) void {
        const a = testing.allocator;
        const stream = self.listener.accept(sio.io()) catch {
            self.failed = true;
            return;
        };
        defer stream.close(sio.io());
        const fd = stream.socket.handle;
        var wbuf: [4096]u8 = undefined;
        var wr = stream.writer(sio.io(), &wbuf);
        const tv = std.posix.timeval{ .sec = 15, .usec = 0 };
        std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&tv)) catch {};

        var pkt: std.ArrayList(u8) = .empty;
        defer pkt.deinit(a);

        // 1. Handshake (seq 0). Salt parts join to "1234567890abcdefghij".
        var hs: std.ArrayList(u8) = .empty;
        defer hs.deinit(a);
        const caps: u32 = 0x8A20D;
        hs.appendSlice(a, &.{10}) catch return;
        hs.appendSlice(a, "8.0.0-fake") catch return;
        hs.append(a, 0) catch return;
        var b4: [4]u8 = undefined;
        std.mem.writeInt(u32, &b4, 42, .little);
        hs.appendSlice(a, &b4) catch return;
        hs.appendSlice(a, "12345678") catch return;
        hs.append(a, 0) catch return;
        var b2: [2]u8 = undefined;
        std.mem.writeInt(u16, &b2, @intCast(caps & 0xFFFF), .little);
        hs.appendSlice(a, &b2) catch return;
        hs.append(a, 45) catch return;
        std.mem.writeInt(u16, &b2, 2, .little);
        hs.appendSlice(a, &b2) catch return;
        std.mem.writeInt(u16, &b2, @intCast(caps >> 16), .little);
        hs.appendSlice(a, &b2) catch return;
        hs.append(a, 21) catch return;
        hs.appendNTimes(a, 0, 10) catch return;
        hs.appendSlice(a, "90abcdefghij\x00") catch return;
        hs.appendSlice(a, "mysql_native_password") catch return;
        hs.append(a, 0) catch return;
        if (!send(&wr, 0, hs.items)) return;

        // 2. Handshake response: check user + token against the vector.
        if (!srvReadPacket(fd, a, &pkt)) return;
        if (pkt.items.len < 33) return;
        var pos: usize = 32;
        const user_end = std.mem.indexOfScalarPos(u8, pkt.items, pos, 0) orelse return;
        self.user_ok = std.mem.eql(u8, pkt.items[pos..user_end], "tester");
        pos = user_end + 1;
        if (pos >= pkt.items.len) return;
        const tlen: usize = pkt.items[pos];
        pos += 1;
        if (pos + tlen > pkt.items.len) return;
        var expected: [20]u8 = undefined;
        hexToBytes("2016259fa51e35448bff4fbeb2c9262025edfac9", &expected);
        self.token_ok = std.mem.eql(u8, pkt.items[pos .. pos + tlen], &expected);
        if (!send(&wr, 2, &.{ 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00 })) return;

        // 3. COM_QUERY -> two-column text result set.
        if (!srvReadPacket(fd, a, &pkt)) return;
        if (pkt.items.len == 0 or pkt.items[0] != 0x03) {
            self.failed = true;
            return;
        }
        self.saw_query = true;
        if (!send(&wr, 1, &.{0x02})) return;
        const def_id = colDef(a, "id", MYSQL_TYPE_LONG, 0) orelse return;
        defer a.free(def_id);
        const def_name = colDef(a, "name", MYSQL_TYPE_VAR_STRING, 0) orelse return;
        defer a.free(def_name);
        if (!send(&wr, 2, def_id)) return;
        if (!send(&wr, 3, def_name)) return;
        if (!send(&wr, 4, &.{ 0xFE, 0, 0, 0x02, 0 })) return;
        if (!send(&wr, 5, &.{ 0x02, '4', '2', 0x05, 'h', 'e', 'l', 'l', 'o' })) return;
        if (!send(&wr, 6, &.{ 0x02, '-', '7', 0xFB })) return;
        if (!send(&wr, 7, &.{ 0xFE, 0, 0, 0x02, 0 })) return;

        // 4. COM_STMT_PREPARE -> prepare OK + param defs + column defs.
        if (!srvReadPacket(fd, a, &pkt)) return;
        if (pkt.items.len == 0 or pkt.items[0] != 0x16) {
            self.failed = true;
            return;
        }
        self.saw_prepare = true;
        var pok: [12]u8 = .{ 0x00, 7, 0, 0, 0, 2, 0, 2, 0, 0, 0, 0 };
        _ = &pok;
        if (!send(&wr, 1, &pok)) return;
        const def_p = colDef(a, "?", MYSQL_TYPE_VAR_STRING, 0) orelse return;
        defer a.free(def_p);
        if (!send(&wr, 2, def_p)) return;
        if (!send(&wr, 3, def_p)) return;
        if (!send(&wr, 4, &.{ 0xFE, 0, 0, 0x02, 0 })) return;
        const def_v = colDef(a, "v", MYSQL_TYPE_LONGLONG, 0) orelse return;
        defer a.free(def_v);
        const def_w = colDef(a, "w", MYSQL_TYPE_VAR_STRING, 0) orelse return;
        defer a.free(def_w);
        if (!send(&wr, 5, def_v)) return;
        if (!send(&wr, 6, def_w)) return;
        if (!send(&wr, 7, &.{ 0xFE, 0, 0, 0x02, 0 })) return;

        // 5. COM_STMT_EXECUTE -> record bindings, answer a binary row.
        if (!srvReadPacket(fd, a, &pkt)) return;
        if (pkt.items.len < 24 or pkt.items[0] != 0x17) {
            self.failed = true;
            return;
        }
        self.exec_i64 = std.mem.readInt(i64, pkt.items[16..24], .little);
        var vpos: usize = 24;
        if (vpos < pkt.items.len) {
            const li = readLenencInt(pkt.items, vpos) orelse return;
            vpos = li.next;
            const n = u64ToUsize(li.value) orelse return;
            if (vpos + n <= pkt.items.len and n <= self.exec_text_buf.len) {
                @memcpy(self.exec_text_buf[0..n], pkt.items[vpos .. vpos + n]);
                self.exec_text_len = n;
            }
        }
        if (!send(&wr, 1, &.{0x02})) return;
        if (!send(&wr, 2, def_v)) return;
        if (!send(&wr, 3, def_w)) return;
        if (!send(&wr, 4, &.{ 0xFE, 0, 0, 0x02, 0 })) return;
        var brow: [10]u8 = undefined;
        brow[0] = 0x00;
        brow[1] = 0x08; // null bitmap: column 1 ("w") is NULL
        std.mem.writeInt(i64, brow[2..10], self.exec_i64, .little);
        if (!send(&wr, 5, &brow)) return;
        if (!send(&wr, 6, &.{ 0xFE, 0, 0, 0x02, 0 })) return;

        // 6. COM_STMT_CLOSE (no response).
        if (!srvReadPacket(fd, a, &pkt)) return;
        if (pkt.items.len == 0 or pkt.items[0] != 0x19) {
            self.failed = true;
            return;
        }
        self.saw_close = true;

        // 7. COM_QUERY (bad) -> ERR packet 1146 / 42S02.
        if (!srvReadPacket(fd, a, &pkt)) return;
        if (pkt.items.len == 0 or pkt.items[0] != 0x03) {
            self.failed = true;
            return;
        }
        self.saw_bad_query = true;
        var err: std.ArrayList(u8) = .empty;
        defer err.deinit(a);
        err.appendSlice(a, &.{ 0xFF, 0x7A, 0x04, '#' }) catch return;
        err.appendSlice(a, "42S02") catch return;
        err.appendSlice(a, "Table 'x.y' doesn't exist") catch return;
        if (!send(&wr, 1, err.items)) return;

        // 8. COM_PING -> OK. 9. COM_QUIT -> hang up.
        if (!srvReadPacket(fd, a, &pkt)) return;
        if (pkt.items.len == 0 or pkt.items[0] != 0x0E) {
            self.failed = true;
            return;
        }
        self.saw_ping = true;
        if (!send(&wr, 1, &.{ 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00 })) return;
        if (!srvReadPacket(fd, a, &pkt)) return;
        if (pkt.items.len > 0 and pkt.items[0] == 0x01) self.saw_quit = true;
    }
};
