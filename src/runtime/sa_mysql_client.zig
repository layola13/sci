// MySQL / MariaDB client runtime for the sci/sa_std platform layer.
//
// Pure-Zig implementation of the MySQL client/server protocol (protocol
// version 10) over a plain TCP stream. No external library, no plugin:
// this is a sa_std builtin core in the same sense as sa_http_client and
// sa_ws_client. TLS transport is deliberately NOT part of v1 (see the
// full-auth note under caching_sha2_password below); connections are
// plaintext and callers that need wire encryption must not use this
// surface yet.
//
// Scope of v1 (see sa_std/mysql_client.sai for the SA-facing contract):
//   * Handshake + authentication for the two password plugins a stock
//     server negotiates by default:
//       - mysql_native_password (SHA-1 scramble),
//       - caching_sha2_password (SHA-256 scramble, fast auth path only).
//     caching_sha2 full authentication requires either a TLS channel
//     (clear password) or RSA public-key encryption of the password.
//     Neither exists in sa_std yet (RSA lands with the crypto batch), so
//     when a server demands full auth this client refuses loudly with
//     SA_MYSQL_ERR_FULL_AUTH (-103) instead of failing silently or
//     sending anything on the wire. Once the server-side credential
//     cache is warm (any prior successful full auth by any client), the
//     fast path succeeds.
//   * COM_QUERY text protocol with full result-set materialization:
//     column definitions, text rows, OK/ERR/EOF packets. NULL, integer,
//     floating-point, text and temporal values round-trip as text bytes
//     (the server already renders temporal values as text in the text
//     protocol).
//   * COM_STMT_PREPARE / COM_STMT_EXECUTE binary protocol, minimal
//     binding set: NULL, i64, u64, f64 and byte-string parameters.
//     Binary row values are decoded to the same text-byte shape as the
//     text protocol (integers rendered decimal, floats rendered with
//     the shortest round-trip decimal, temporal values rendered ISO),
//     so callers see one value model. BIT arrives as raw big-endian
//     bytes; GEOMETRY as raw bytes.
//   * Server ERR packets are never swallowed: errno, SQLSTATE and the
//     message are recorded on the connection and returned via
//     sa_mysql_errno / sa_mysql_sqlstate / sa_mysql_error_message, and
//     the call itself returns SA_MYSQL_ERR_SERVER (-101).
//   * Explicit refusals, never silent degradation: LOAD DATA LOCAL
//     INFILE requests (-1, connection closed: the protocol leaves no
//     safe way to continue), multi-statements (never negotiated),
//     unknown auth plugins (-104), auth switch to an unimplemented
//     plugin (-104).
//
// Handles are heap-allocated structs packed into a u64; 0 == invalid.
// close() consumes the handle (double-close is a caller bug, same as
// the other protocol sinks). A Result handle is owned by its connection
// and is released automatically when the connection closes; freeing it
// earlier with sa_mysql_result_free is the normal path. Blocking I/O
// throughout, same as sa_tls_client / sa_ws_client.
//
// Status codes: 0 = SA_STD_OK; negative = error. Local errors reuse the
// sci conventions (-1 unsupported, -5 I/O, -12 out of memory, -22
// invalid argument). MySQL-specific codes:
//   -101 SA_MYSQL_ERR_SERVER    server sent an ERR packet (see accessors)
//   -102 SA_MYSQL_ERR_PROTOCOL  malformed/unexpected packet; conn is dead
//   -103 SA_MYSQL_ERR_FULL_AUTH caching_sha2 full auth needs TLS or RSA
//   -104 SA_MYSQL_ERR_AUTH_PLUGIN server demands an auth plugin v1 lacks

const std = @import("std");
const sio = @import("sio");

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_UNSUPPORTED: i32 = -1;
pub const SA_STD_ERR_IO: i32 = -5;
pub const SA_STD_ERR_NO_MEMORY: i32 = -12;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
pub const SA_MYSQL_ERR_SERVER: i32 = -101;
pub const SA_MYSQL_ERR_PROTOCOL: i32 = -102;
pub const SA_MYSQL_ERR_FULL_AUTH: i32 = -103;
pub const SA_MYSQL_ERR_AUTH_PLUGIN: i32 = -104;

// Client capability flags (protocol reference values).
const CLIENT_LONG_PASSWORD: u32 = 0x0000_0001;
const CLIENT_LONG_FLAG: u32 = 0x0000_0004;
const CLIENT_CONNECT_WITH_DB: u32 = 0x0000_0008;
const CLIENT_PROTOCOL_41: u32 = 0x0000_0200;
const CLIENT_TRANSACTIONS: u32 = 0x0000_2000;
const CLIENT_SECURE_CONNECTION: u32 = 0x0000_8000;
const CLIENT_PLUGIN_AUTH: u32 = 0x0008_0000;

const CLIENT_BASE_FLAGS: u32 = CLIENT_LONG_PASSWORD | CLIENT_LONG_FLAG |
    CLIENT_PROTOCOL_41 | CLIENT_TRANSACTIONS | CLIENT_SECURE_CONNECTION |
    CLIENT_PLUGIN_AUTH;

// utf8mb4_general_ci: present on every MySQL 5.6+/MariaDB 10.x server,
// unlike utf8mb4_0900_ai_ci (id 255, MySQL 8 only).
const MYSQL_CHARSET_UTF8MB4: u8 = 45;

const SERVER_MORE_RESULTS_EXISTS: u16 = 0x0008;
const SERVER_STATUS_AUTOCOMMIT: u16 = 0x0002;

const MAX_PACKET_SIZE: usize = 0x00FF_FFFF;

// Column type codes (enum_field_types), published for SLA in
// sa_std/mysql_client.sla.
pub const MYSQL_TYPE_DECIMAL: u8 = 0;
pub const MYSQL_TYPE_TINY: u8 = 1;
pub const MYSQL_TYPE_SHORT: u8 = 2;
pub const MYSQL_TYPE_LONG: u8 = 3;
pub const MYSQL_TYPE_FLOAT: u8 = 4;
pub const MYSQL_TYPE_DOUBLE: u8 = 5;
pub const MYSQL_TYPE_NULL: u8 = 6;
pub const MYSQL_TYPE_TIMESTAMP: u8 = 7;
pub const MYSQL_TYPE_LONGLONG: u8 = 8;
pub const MYSQL_TYPE_INT24: u8 = 9;
pub const MYSQL_TYPE_DATE: u8 = 10;
pub const MYSQL_TYPE_TIME: u8 = 11;
pub const MYSQL_TYPE_DATETIME: u8 = 12;
pub const MYSQL_TYPE_YEAR: u8 = 13;
pub const MYSQL_TYPE_VARCHAR: u8 = 15;
pub const MYSQL_TYPE_BIT: u8 = 16;
pub const MYSQL_TYPE_JSON: u8 = 245;
pub const MYSQL_TYPE_NEWDECIMAL: u8 = 246;
pub const MYSQL_TYPE_ENUM: u8 = 247;
pub const MYSQL_TYPE_SET: u8 = 248;
pub const MYSQL_TYPE_TINY_BLOB: u8 = 249;
pub const MYSQL_TYPE_MEDIUM_BLOB: u8 = 250;
pub const MYSQL_TYPE_LONG_BLOB: u8 = 251;
pub const MYSQL_TYPE_BLOB: u8 = 252;
pub const MYSQL_TYPE_VAR_STRING: u8 = 253;
pub const MYSQL_TYPE_STRING: u8 = 254;
pub const MYSQL_TYPE_GEOMETRY: u8 = 255;

const UNSIGNED_FLAG: u32 = 0x20;

const alloc = std.heap.page_allocator;

fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

fn sliceArg(ptr: ?[*]const u8, len: u64) ?[]const u8 {
    const n = u64ToUsize(len) orelse return null;
    if (ptr) |p| return p[0..n];
    if (n == 0) return "";
    return null;
}

// ---------------------------------------------------------------------------
// Length-encoded integers / strings
// ---------------------------------------------------------------------------

/// Decode a length-encoded integer at `pos`. Returns null on truncation.
/// `is_null` is set when the marker is 0xFB (NULL in string contexts);
/// callers decoding pure integers treat 0xFB per the packet grammar.
const LenencInt = struct { value: u64, is_null: bool, next: usize };

fn readLenencInt(bytes: []const u8, pos: usize) ?LenencInt {
    if (pos >= bytes.len) return null;
    const b = bytes[pos];
    switch (b) {
        0x00...0xFA => return .{ .value = b, .is_null = false, .next = pos + 1 },
        0xFB => return .{ .value = 0, .is_null = true, .next = pos + 1 },
        0xFC => {
            if (pos + 3 > bytes.len) return null;
            return .{ .value = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little), .is_null = false, .next = pos + 3 };
        },
        0xFD => {
            if (pos + 4 > bytes.len) return null;
            const v3: u64 = @as(u64, bytes[pos + 1]) | (@as(u64, bytes[pos + 2]) << 8) | (@as(u64, bytes[pos + 3]) << 16);
            return .{ .value = v3, .is_null = false, .next = pos + 4 };
        },
        0xFE => {
            if (pos + 9 > bytes.len) return null;
            return .{ .value = std.mem.readInt(u64, bytes[pos + 1 ..][0..8], .little), .is_null = false, .next = pos + 9 };
        },
        0xFF => return null,
    }
}

fn writeLenencInt(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u64) !void {
    if (value < 251) {
        try out.append(a, @intCast(value));
    } else if (value < 65536) {
        try out.append(a, 0xFC);
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, @intCast(value), .little);
        try out.appendSlice(a, &buf);
    } else if (value < 16777216) {
        try out.append(a, 0xFD);
        try out.append(a, @intCast(value & 0xFF));
        try out.append(a, @intCast((value >> 8) & 0xFF));
        try out.append(a, @intCast((value >> 16) & 0xFF));
    } else {
        try out.append(a, 0xFE);
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, value, .little);
        try out.appendSlice(a, &buf);
    }
}

fn writeLenencString(out: *std.ArrayList(u8), a: std.mem.Allocator, s: []const u8) !void {
    try writeLenencInt(out, a, s.len);
    try out.appendSlice(a, s);
}

// ---------------------------------------------------------------------------
// Authentication scrambles
// ---------------------------------------------------------------------------

/// mysql_native_password token: SHA1(pw) XOR SHA1(salt + SHA1(SHA1(pw))).
/// Empty password -> empty token.
fn nativePasswordToken(password: []const u8, salt: []const u8, out: *[20]u8) usize {
    if (password.len == 0) return 0;
    var stage1: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(password, &stage1, .{});
    var stage2: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(&stage1, &stage2, .{});
    var h = std.crypto.hash.Sha1.init(.{});
    h.update(salt);
    h.update(&stage2);
    var mask: [20]u8 = undefined;
    h.final(&mask);
    for (0..20) |i| out[i] = stage1[i] ^ mask[i];
    return 20;
}

/// caching_sha2_password scramble:
/// SHA256(pw) XOR SHA256(SHA256(SHA256(pw)) + salt).
/// Empty password -> empty token.
fn cachingSha2Token(password: []const u8, salt: []const u8, out: *[32]u8) usize {
    if (password.len == 0) return 0;
    const Sha256 = std.crypto.hash.sha2.Sha256;
    var stage1: [32]u8 = undefined;
    Sha256.hash(password, &stage1, .{});
    var stage2: [32]u8 = undefined;
    Sha256.hash(&stage1, &stage2, .{});
    var h = Sha256.init(.{});
    h.update(&stage2);
    h.update(salt);
    var mask: [32]u8 = undefined;
    h.final(&mask);
    for (0..32) |i| out[i] = stage1[i] ^ mask[i];
    return 32;
}

const AuthPlugin = enum { native_password, caching_sha2, unsupported };

fn authPluginFromName(name: []const u8) AuthPlugin {
    if (std.mem.eql(u8, name, "mysql_native_password")) return .native_password;
    if (std.mem.eql(u8, name, "caching_sha2_password")) return .caching_sha2;
    return .unsupported;
}

/// Compute the auth response for `plugin`; returns the token length
/// written to `out` (max 32 bytes), or null for an unsupported plugin.
fn authToken(plugin: AuthPlugin, password: []const u8, salt: []const u8, out: *[32]u8) ?usize {
    switch (plugin) {
        .native_password => {
            var t: [20]u8 = undefined;
            const n = nativePasswordToken(password, salt, &t);
            @memcpy(out[0..n], t[0..n]);
            return n;
        },
        .caching_sha2 => return cachingSha2Token(password, salt, out),
        .unsupported => return null,
    }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

pub const Column = struct {
    name: []u8,
    type_code: u8,
    flags: u16,
    charset: u16,
    column_length: u32,
    decimals: u8,

    pub fn isUnsigned(self: Column) bool {
        return (self.flags & UNSIGNED_FLAG) != 0;
    }
};

pub const Result = struct {
    conn: *Conn,
    columns: []Column = &.{},
    /// How many entries of `columns` own a heap `name` (parsing fills
    /// the array progressively; deinit must only free those).
    columns_filled: usize = 0,
    /// Materialized rows; each value is owned bytes, null = SQL NULL.
    /// Text-protocol rows hold the server's text rendering as-is;
    /// binary-protocol rows are decoded to the same text shape.
    rows: std.ArrayList([]const ?[]u8) = .empty,
    cursor: usize = 0,
    has_result_set: bool = false,
    affected_rows: u64 = 0,
    last_insert_id: u64 = 0,
    warning_count: u16 = 0,
    status_flags: u16 = 0,

    fn deinit(self: *Result) void {
        for (self.columns[0..self.columns_filled]) |c| alloc.free(c.name);
        if (self.columns.len > 0) alloc.free(self.columns);
        for (self.rows.items) |row| {
            for (row) |v| {
                if (v) |bytes| alloc.free(bytes);
            }
            if (row.len > 0) alloc.free(row);
        }
        self.rows.deinit(alloc);
    }
};

const Conn = struct {
    stream: ?std.Io.net.Stream = null,
    reader: ?std.Io.net.Stream.Reader = null,
    writer: ?std.Io.net.Stream.Writer = null,
    read_buf: [8192]u8 = undefined,
    write_buf: [8192]u8 = undefined,
    seq: u8 = 0,
    dead: bool = true,
    /// Scratch payload of the most recent packet read; consumed (and
    /// copied out of) before the next read.
    packet_scratch: std.ArrayList(u8) = .empty,
    /// Results currently alive on this connection (freed at close).
    results: std.ArrayList(*Result) = .empty,
    stmts: std.ArrayList(*Stmt) = .empty,
    // Session info from the handshake.
    server_version: []u8 = &.{},
    connection_id: u32 = 0,
    server_capabilities: u32 = 0,
    status_flags: u16 = 0,
    // Last server ERR packet recorded on this connection.
    err_no: u32 = 0,
    sql_state: [5]u8 = .{ '0', '0', '0', '0', '0' },
    err_msg: []u8 = &.{},

    fn recordServerError(self: *Conn, payload: []const u8) void {
        // ERR packet: 0xFF, errno(2 LE), ['#' sqlstate(5)], message.
        if (payload.len < 3) return;
        self.err_no = std.mem.readInt(u16, payload[1..3], .little);
        var msg_start: usize = 3;
        if (payload.len >= 9 and payload[3] == '#') {
            @memcpy(&self.sql_state, payload[4..9]);
            msg_start = 9;
        } else {
            self.sql_state = .{ 'H', 'Y', '0', '0', '0' };
        }
        const msg = payload[msg_start..];
        const owned = alloc.dupe(u8, msg) catch return;
        if (self.err_msg.len > 0) alloc.free(self.err_msg);
        self.err_msg = owned;
    }

    fn clearServerError(self: *Conn) void {
        self.err_no = 0;
        self.sql_state = .{ '0', '0', '0', '0', '0' };
        if (self.err_msg.len > 0) alloc.free(self.err_msg);
        self.err_msg = &.{};
    }

    fn markDead(self: *Conn) void {
        self.dead = true;
        if (self.stream) |s| {
            s.close(sio.io());
            self.stream = null;
            self.reader = null;
            self.writer = null;
        }
    }

    fn deinit(self: *Conn) void {
        // Free live results/statements first (they borrow the conn).
        while (self.stmts.items.len > 0) {
            const st = self.stmts.items[self.stmts.items.len - 1];
            _ = self.stmts.pop();
            st.deinit();
            alloc.destroy(st);
        }
        self.stmts.deinit(alloc);
        while (self.results.items.len > 0) {
            const r = self.results.items[self.results.items.len - 1];
            _ = self.results.pop();
            r.deinit();
            alloc.destroy(r);
        }
        self.results.deinit(alloc);
        self.markDead();
        self.packet_scratch.deinit(alloc);
        if (self.server_version.len > 0) alloc.free(self.server_version);
        if (self.err_msg.len > 0) alloc.free(self.err_msg);
    }
};

const IoError = error{ Io, Protocol, OutOfMemory };

/// Send one logical packet, splitting payloads at the 16MB-1 framing
/// limit as the protocol requires.
fn writePacket(conn: *Conn, payload: []const u8) IoError!void {
    const w = &conn.writer.?.interface;
    var rest = payload;
    while (true) {
        const chunk = @min(rest.len, MAX_PACKET_SIZE);
        var hdr: [4]u8 = undefined;
        hdr[0] = @intCast(chunk & 0xFF);
        hdr[1] = @intCast((chunk >> 8) & 0xFF);
        hdr[2] = @intCast((chunk >> 16) & 0xFF);
        hdr[3] = conn.seq;
        conn.seq +%= 1;
        w.writeAll(&hdr) catch return error.Io;
        w.writeAll(rest[0..chunk]) catch return error.Io;
        rest = rest[chunk..];
        if (chunk < MAX_PACKET_SIZE) break;
        if (rest.len == 0) {
            // Payload exactly on the boundary still needs the empty
            // terminator packet.
            var eh: [4]u8 = .{ 0, 0, 0, conn.seq };
            conn.seq +%= 1;
            w.writeAll(&eh) catch return error.Io;
            break;
        }
    }
    w.flush() catch return error.Io;
}

/// Read one logical packet into conn.packet_scratch and return it.
/// Validates the sequence id; on a mismatch the connection is dead.
fn readPacket(conn: *Conn) IoError![]const u8 {
    conn.packet_scratch.clearRetainingCapacity();
    const r = &conn.reader.?.interface;
    while (true) {
        var hdr: [4]u8 = undefined;
        r.readSliceAll(&hdr) catch return error.Io;
        const len: usize = @as(usize, hdr[0]) | (@as(usize, hdr[1]) << 8) | (@as(usize, hdr[2]) << 16);
        if (hdr[3] != conn.seq) {
            conn.markDead();
            return error.Protocol;
        }
        conn.seq +%= 1;
        const start = conn.packet_scratch.items.len;
        conn.packet_scratch.resize(alloc, start + len) catch return error.OutOfMemory;
        r.readSliceAll(conn.packet_scratch.items[start..]) catch return error.Io;
        if (len < MAX_PACKET_SIZE) break;
    }
    return conn.packet_scratch.items;
}

/// Dial like the other sa_std protocol clients: literal IPs connect
/// directly, names go through HostName (Happy Eyeballs).
fn dialHost(host: []const u8, port: u16) !std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream });
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    return hn.connect(sio.io(), port, .{ .mode = .stream });
}

const Handshake = struct {
    server_version: []const u8,
    connection_id: u32,
    salt: [20]u8,
    salt_len: usize,
    capabilities: u32,
    plugin_name: []const u8,
};

fn parseHandshake(payload: []const u8) ?Handshake {
    // HandshakeV10.
    if (payload.len < 1 or payload[0] == 0xFF) return null;
    var pos: usize = 1; // protocol version
    const ver_end = std.mem.indexOfScalarPos(u8, payload, pos, 0) orelse return null;
    const version = payload[pos..ver_end];
    pos = ver_end + 1;
    // conn_id(4) salt1(8) filler(1) cap_lo(2) charset(1) status(2)
    // cap_hi(2) auth_len(1) reserved(10) = 31 fixed bytes must follow.
    if (pos + 31 > payload.len) return null;
    const conn_id = std.mem.readInt(u32, payload[pos..][0..4], .little);
    pos += 4;
    var salt: [20]u8 = @splat(0);
    @memcpy(salt[0..8], payload[pos..][0..8]);
    var salt_len: usize = 8;
    pos += 8;
    pos += 1; // filler
    const cap_lo = std.mem.readInt(u16, payload[pos..][0..2], .little);
    pos += 2;
    var caps: u32 = cap_lo;
    pos += 1; // charset
    pos += 2; // status flags
    const cap_hi = std.mem.readInt(u16, payload[pos..][0..2], .little);
    pos += 2;
    caps |= @as(u32, cap_hi) << 16;
    const auth_data_len: usize = payload[pos];
    pos += 1;
    pos += 10; // reserved
    const part2_len: usize = if (caps & CLIENT_SECURE_CONNECTION != 0)
        @max(13, if (auth_data_len > 8) auth_data_len - 8 else 0)
    else
        0;
    if (pos + part2_len > payload.len) return null;
    const copy2 = @min(part2_len, 20 - salt_len);
    // The salt's second part is NUL-terminated inside its field; the
    // terminator is not part of the scramble input.
    var eff2 = copy2;
    if (eff2 > 0 and payload[pos + eff2 - 1] == 0) eff2 -= 1;
    @memcpy(salt[salt_len..][0..eff2], payload[pos..][0..eff2]);
    salt_len += eff2;
    pos += part2_len;
    var plugin_name: []const u8 = "mysql_native_password";
    if (caps & CLIENT_PLUGIN_AUTH != 0 and pos < payload.len) {
        const end = std.mem.indexOfScalarPos(u8, payload, pos, 0) orelse payload.len;
        plugin_name = payload[pos..end];
    }
    return .{
        .server_version = version,
        .connection_id = conn_id,
        .salt = salt,
        .salt_len = salt_len,
        .capabilities = caps,
        .plugin_name = plugin_name,
    };
}

/// Send the handshake response and run the auth conversation.
/// Returns SA_STD_OK or a negative status; on failure the connection
/// keeps the recorded server error (if any) for the accessors.
fn runAuth(conn: *Conn, hs: Handshake, user: []const u8, password: []const u8, database: []const u8) i32 {
    var plugin = authPluginFromName(hs.plugin_name);
    if (plugin == .unsupported) return SA_MYSQL_ERR_AUTH_PLUGIN;
    var salt_buf: [20]u8 = hs.salt;
    var salt: []const u8 = salt_buf[0..hs.salt_len];

    var caps = CLIENT_BASE_FLAGS & hs.capabilities;
    caps |= CLIENT_PROTOCOL_41 | CLIENT_SECURE_CONNECTION | CLIENT_PLUGIN_AUTH;
    if (database.len > 0) caps |= CLIENT_CONNECT_WITH_DB;

    var token_buf: [32]u8 = undefined;
    const token_len = authToken(plugin, password, salt, &token_buf) orelse
        return SA_MYSQL_ERR_AUTH_PLUGIN;

    var pkt: std.ArrayList(u8) = .empty;
    defer pkt.deinit(alloc);
    {
        var fixed: [4 + 4 + 1 + 23]u8 = undefined;
        std.mem.writeInt(u32, fixed[0..4], caps, .little);
        std.mem.writeInt(u32, fixed[4..8], 0, .little); // max packet size: server default
        fixed[8] = MYSQL_CHARSET_UTF8MB4;
        @memset(fixed[9..32], 0);
        pkt.appendSlice(alloc, &fixed) catch return SA_STD_ERR_NO_MEMORY;
        pkt.appendSlice(alloc, user) catch return SA_STD_ERR_NO_MEMORY;
        pkt.append(alloc, 0) catch return SA_STD_ERR_NO_MEMORY;
        // Auth response: 1-byte length (CLIENT_PLUGIN_AUTH_LENENC_CLIENT_DATA
        // is not negotiated).
        pkt.append(alloc, @intCast(token_len)) catch return SA_STD_ERR_NO_MEMORY;
        pkt.appendSlice(alloc, token_buf[0..token_len]) catch return SA_STD_ERR_NO_MEMORY;
        if (database.len > 0) {
            pkt.appendSlice(alloc, database) catch return SA_STD_ERR_NO_MEMORY;
            pkt.append(alloc, 0) catch return SA_STD_ERR_NO_MEMORY;
        }
    }
    // Plugin name (NUL-terminated).
    const plugin_name_str: []const u8 = switch (plugin) {
        .native_password => "mysql_native_password",
        .caching_sha2 => "caching_sha2_password",
        .unsupported => unreachable,
    };
    pkt.appendSlice(alloc, plugin_name_str) catch return SA_STD_ERR_NO_MEMORY;
    pkt.append(alloc, 0) catch return SA_STD_ERR_NO_MEMORY;

    writePacket(conn, pkt.items) catch |e| return mapIoErr(e);

    // Auth conversation.
    while (true) {
        const resp = readPacket(conn) catch |e| return mapIoErr(e);
        if (resp.len == 0) {
            conn.markDead();
            return SA_MYSQL_ERR_PROTOCOL;
        }
        switch (resp[0]) {
            0x00 => return SA_STD_OK, // OK packet: authenticated
            0xFF => {
                conn.recordServerError(resp);
                return SA_MYSQL_ERR_SERVER;
            },
            0xFE => {
                // Auth switch request: plugin name (NUL-terminated),
                // then the new salt (trailing NUL not included).
                const name_end = std.mem.indexOfScalarPos(u8, resp, 1, 0) orelse {
                    conn.markDead();
                    return SA_MYSQL_ERR_PROTOCOL;
                };
                plugin = authPluginFromName(resp[1..name_end]);
                if (plugin == .unsupported) return SA_MYSQL_ERR_AUTH_PLUGIN;
                var new_salt = resp[name_end + 1 ..];
                if (new_salt.len > 0 and new_salt[new_salt.len - 1] == 0)
                    new_salt = new_salt[0 .. new_salt.len - 1];
                if (new_salt.len > salt_buf.len) {
                    conn.markDead();
                    return SA_MYSQL_ERR_PROTOCOL;
                }
                @memcpy(salt_buf[0..new_salt.len], new_salt);
                salt = salt_buf[0..new_salt.len];
                const tl = authToken(plugin, password, salt, &token_buf) orelse
                    return SA_MYSQL_ERR_AUTH_PLUGIN;
                writePacket(conn, token_buf[0..tl]) catch |e| return mapIoErr(e);
            },
            0x01 => {
                // AuthMoreData (caching_sha2_password conversation).
                if (plugin != .caching_sha2 or resp.len < 2) {
                    conn.markDead();
                    return SA_MYSQL_ERR_PROTOCOL;
                }
                switch (resp[1]) {
                    0x03 => {
                        // Fast auth succeeded; the OK packet follows.
                        continue;
                    },
                    0x04 => {
                        // Full auth: requires TLS (clear password) or
                        // RSA encryption. Neither is available in v1;
                        // refuse explicitly and hang up.
                        conn.markDead();
                        return SA_MYSQL_ERR_FULL_AUTH;
                    },
                    else => {
                        conn.markDead();
                        return SA_MYSQL_ERR_PROTOCOL;
                    },
                }
            },
            else => {
                conn.markDead();
                return SA_MYSQL_ERR_PROTOCOL;
            },
        }
    }
}

fn mapIoErr(e: IoError) i32 {
    return switch (e) {
        error.Io => SA_STD_ERR_IO,
        error.Protocol => SA_MYSQL_ERR_PROTOCOL,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
    };
}

// ---------------------------------------------------------------------------
// Result-set reading
// ---------------------------------------------------------------------------

const QueryError = error{ Io, Protocol, OutOfMemory, ServerError, Unsupported };

fn mapQueryErr(conn: *Conn, e: QueryError) i32 {
    return switch (e) {
        error.Io => SA_STD_ERR_IO,
        error.Protocol => blk: {
            conn.markDead();
            break :blk SA_MYSQL_ERR_PROTOCOL;
        },
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.ServerError => SA_MYSQL_ERR_SERVER,
        error.Unsupported => SA_STD_ERR_UNSUPPORTED,
    };
}

const Cursor = struct {
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

fn isEofPacket(p: []const u8) bool {
    return p.len >= 1 and p[0] == 0xFE and p.len < 9;
}

const OkInfo = struct { affected: u64 = 0, insert_id: u64 = 0, status: u16 = 0, warnings: u16 = 0 };

fn parseOkPacket(p: []const u8) ?OkInfo {
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

fn parseColumnDef(p: []const u8) QueryError!Column {
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

/// Read the packets of one result set whose first response packet was
/// already consumed and is passed as `first` (it is the column-count
/// packet, an OK packet, or an ERR packet).
/// `binary_rows` selects the binary row decoder (prepared statements).
fn readOneResult(conn: *Conn, first: []const u8, binary_rows: bool) QueryError!*Result {
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

fn mapReadErr(e: IoError) QueryError {
    return switch (e) {
        error.Io => error.Io,
        error.Protocol => error.Protocol,
        error.OutOfMemory => error.OutOfMemory,
    };
}

fn parseTextRow(col_count: usize, pkt: []const u8) QueryError![]const ?[]u8 {
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

/// Decode one binary-protocol row into owned text-shaped values.
fn parseBinaryRow(conn: *Conn, columns: []const Column, pkt: []const u8) QueryError![]const ?[]u8 {
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

fn fmtAlloc(comptime fmt: []const u8, args: anytype) QueryError![]u8 {
    return std.fmt.allocPrint(alloc, fmt, args) catch return error.OutOfMemory;
}

fn decodeBinaryValue(col: Column, c: *Cursor) QueryError!?[]u8 {
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

/// Run one command whose response is a (possibly multi-) result set,
/// after writing `payload` as a single command packet at sequence 0.
/// Returns the first result; further result sets (only producible by
/// stored procedures, which v1 never calls) are drained and discarded
/// so the connection stays in sync, as documented in the .sai header.
fn runCommand(conn: *Conn, payload: []const u8, binary_rows: bool) QueryError!*Result {
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

// ---------------------------------------------------------------------------
// Prepared statements
// ---------------------------------------------------------------------------

const Binding = union(enum) {
    null,
    i64: i64,
    u64: u64,
    f64: f64,
    bytes: []u8,
};

const Stmt = struct {
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

fn prepareStmt(conn: *Conn, sql: []const u8) QueryError!*Stmt {
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

fn executeStmt(stmt: *Stmt) QueryError!*Result {
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

// ---------------------------------------------------------------------------
// Exported surface
// ---------------------------------------------------------------------------

fn connFrom(handle: u64) ?*Conn {
    if (handle == 0) return null;
    return @ptrFromInt(handle);
}

fn resultFrom(handle: u64) ?*Result {
    if (handle == 0) return null;
    return @ptrFromInt(handle);
}

fn stmtFrom(handle: u64) ?*Stmt {
    if (handle == 0) return null;
    return @ptrFromInt(handle);
}

pub export fn sa_mysql_supported(out_supported: ?*u32) i32 {
    const slot = out_supported orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 1;
    return SA_STD_OK;
}

pub export fn sa_mysql_connect(
    host_ptr: ?[*]const u8,
    host_len: u64,
    port: u32,
    user_ptr: ?[*]const u8,
    user_len: u64,
    pass_ptr: ?[*]const u8,
    pass_len: u64,
    db_ptr: ?[*]const u8,
    db_len: u64,
    out_conn: ?*u64,
) i32 {
    const slot = out_conn orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const host = sliceArg(host_ptr, host_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const user = sliceArg(user_ptr, user_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pass = sliceArg(pass_ptr, pass_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const database = sliceArg(db_ptr, db_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (host.len == 0 or user.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if (port == 0 or port > 65535) return SA_STD_ERR_INVALID_ARGUMENT;

    const conn = alloc.create(Conn) catch return SA_STD_ERR_NO_MEMORY;
    conn.* = .{};
    // From here on, failures still hand the caller the handle: it keeps
    // the recorded server error for the accessors and close() frees it.
    slot.* = @intFromPtr(conn);

    const stream = dialHost(host, @intCast(port)) catch return SA_STD_ERR_IO;
    conn.stream = stream;
    conn.reader = stream.reader(sio.io(), &conn.read_buf);
    conn.writer = stream.writer(sio.io(), &conn.write_buf);
    conn.dead = false;
    conn.seq = 0;

    const hs_pkt = readPacket(conn) catch |e| {
        conn.markDead();
        return mapIoErr(e);
    };
    if (hs_pkt.len > 0 and hs_pkt[0] == 0xFF) {
        conn.recordServerError(hs_pkt);
        conn.markDead();
        return SA_MYSQL_ERR_SERVER;
    }
    const hs = parseHandshake(hs_pkt) orelse {
        conn.markDead();
        return SA_MYSQL_ERR_PROTOCOL;
    };
    conn.connection_id = hs.connection_id;
    conn.server_capabilities = hs.capabilities;
    conn.server_version = alloc.dupe(u8, hs.server_version) catch return SA_STD_ERR_NO_MEMORY;

    const rc = runAuth(conn, hs, user, pass, database);
    if (rc != SA_STD_OK) {
        if (rc != SA_MYSQL_ERR_SERVER) conn.markDead();
        return rc;
    }
    return SA_STD_OK;
}

pub export fn sa_mysql_close(handle: u64) i32 {
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (!conn.dead and conn.stream != null) {
        // COM_QUIT: best effort — the socket closes either way.
        conn.seq = 0;
        writePacket(conn, &.{0x01}) catch {};
    }
    conn.deinit();
    alloc.destroy(conn);
    return SA_STD_OK;
}

pub export fn sa_mysql_ping(handle: u64) i32 {
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (conn.dead) return SA_MYSQL_ERR_PROTOCOL;
    conn.clearServerError();
    conn.seq = 0;
    writePacket(conn, &.{0x0E}) catch |e| {
        conn.markDead();
        return mapIoErr(e);
    };
    const pkt = readPacket(conn) catch |e| {
        conn.markDead();
        return mapIoErr(e);
    };
    if (pkt.len > 0 and pkt[0] == 0xFF) {
        conn.recordServerError(pkt);
        return SA_MYSQL_ERR_SERVER;
    }
    if (pkt.len == 0 or pkt[0] != 0x00) {
        conn.markDead();
        return SA_MYSQL_ERR_PROTOCOL;
    }
    return SA_STD_OK;
}

pub export fn sa_mysql_query(handle: u64, sql_ptr: ?[*]const u8, sql_len: u64, out_result: ?*u64) i32 {
    const slot = out_result orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (conn.dead) return SA_MYSQL_ERR_PROTOCOL;
    const sql = sliceArg(sql_ptr, sql_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (sql.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(alloc);
    payload.append(alloc, 0x03) catch return SA_STD_ERR_NO_MEMORY; // COM_QUERY
    payload.appendSlice(alloc, sql) catch return SA_STD_ERR_NO_MEMORY;
    const result = runCommand(conn, payload.items, false) catch |e|
        return mapQueryErr(conn, e);
    slot.* = @intFromPtr(result);
    return SA_STD_OK;
}

pub export fn sa_mysql_prepare(handle: u64, sql_ptr: ?[*]const u8, sql_len: u64, out_stmt: ?*u64) i32 {
    const slot = out_stmt orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (conn.dead) return SA_MYSQL_ERR_PROTOCOL;
    const sql = sliceArg(sql_ptr, sql_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (sql.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const stmt = prepareStmt(conn, sql) catch |e| return mapQueryErr(conn, e);
    slot.* = @intFromPtr(stmt);
    return SA_STD_OK;
}

fn bindSet(stmt_handle: u64, idx: u64, binding: Binding) i32 {
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

// -- error / session accessors ----------------------------------------------

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

pub export fn sa_mysql_error_message(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    pp.* = conn.err_msg.ptr;
    ll.* = conn.err_msg.len;
    return SA_STD_OK;
}

pub export fn sa_mysql_server_version(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    pp.* = conn.server_version.ptr;
    ll.* = conn.server_version.len;
    return SA_STD_OK;
}

pub export fn sa_mysql_connection_id(handle: u64) u32 {
    const conn = connFrom(handle) orelse return 0;
    return conn.connection_id;
}

// -- result accessors ---------------------------------------------------------

pub export fn sa_mysql_result_free(handle: u64) i32 {
    const result = resultFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const conn = result.conn;
    for (conn.results.items, 0..) |r, i| {
        if (r == result) {
            _ = conn.results.orderedRemove(i);
            break;
        }
    }
    result.deinit();
    alloc.destroy(result);
    return SA_STD_OK;
}

pub export fn sa_mysql_result_has_result_set(handle: u64) u32 {
    const result = resultFrom(handle) orelse return 0;
    return if (result.has_result_set) 1 else 0;
}

pub export fn sa_mysql_result_column_count(handle: u64) u64 {
    const result = resultFrom(handle) orelse return 0;
    return @intCast(result.columns.len);
}

pub export fn sa_mysql_result_column_name(handle: u64, idx: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const result = resultFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const i = u64ToUsize(idx) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (i >= result.columns.len) return SA_STD_ERR_INVALID_ARGUMENT;
    pp.* = result.columns[i].name.ptr;
    ll.* = result.columns[i].name.len;
    return SA_STD_OK;
}

pub export fn sa_mysql_result_column_type(handle: u64, idx: u64) u32 {
    const result = resultFrom(handle) orelse return 0xFFFF_FFFF;
    const i = u64ToUsize(idx) orelse return 0xFFFF_FFFF;
    if (i >= result.columns.len) return 0xFFFF_FFFF;
    return result.columns[i].type_code;
}

pub export fn sa_mysql_result_row_count(handle: u64) u64 {
    const result = resultFrom(handle) orelse return 0;
    return @intCast(result.rows.items.len);
}

/// Fetch the next row's index sequentially; returns 1 and sets
/// out_row when a row is available, 0 when the result is exhausted.
pub export fn sa_mysql_result_next(handle: u64, out_row: ?*u64) i32 {
    const result = resultFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const slot = out_row orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (result.cursor >= result.rows.items.len) return 0;
    slot.* = @intCast(result.cursor);
    result.cursor += 1;
    return 1;
}

/// Read one value. On success out_ptr/out_len address result-owned
/// bytes (valid until the result is freed) and out_is_null is 1 for
/// SQL NULL (out_len is then 0).
pub export fn sa_mysql_result_value(
    handle: u64,
    row_idx: u64,
    col_idx: u64,
    out_ptr: ?*?[*]const u8,
    out_len: ?*u64,
    out_is_null: ?*u32,
) i32 {
    const result = resultFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const nn = out_is_null orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const r = u64ToUsize(row_idx) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const c = u64ToUsize(col_idx) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (r >= result.rows.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const row = result.rows.items[r];
    if (c >= row.len) return SA_STD_ERR_INVALID_ARGUMENT;
    if (row[c]) |bytes| {
        pp.* = bytes.ptr;
        ll.* = bytes.len;
        nn.* = 0;
    } else {
        pp.* = "".ptr;
        ll.* = 0;
        nn.* = 1;
    }
    return SA_STD_OK;
}

pub export fn sa_mysql_affected_rows(handle: u64) u64 {
    const result = resultFrom(handle) orelse return 0;
    return result.affected_rows;
}

pub export fn sa_mysql_last_insert_id(handle: u64) u64 {
    const result = resultFrom(handle) orelse return 0;
    return result.last_insert_id;
}

pub export fn sa_mysql_result_warnings(handle: u64) u32 {
    const result = resultFrom(handle) orelse return 0;
    return result.warning_count;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn hexToBytes(comptime hex: []const u8, out: []u8) void {
    std.debug.assert(hex.len == out.len * 2);
    for (out, 0..) |*b, i| {
        b.* = std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16) catch unreachable;
    }
}

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

// -- Scripted fake server: end-to-end protocol test ---------------------------
// The fake server speaks just enough of the wire protocol, from literal
// byte layouts, to verify the client independently: it checks the auth
// token against the hashlib-computed vector, serves one text result
// set, one prepare/execute round trip with a binary row (incl. a NULL
// column via the null bitmap), one ERR packet, PING and QUIT.

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
