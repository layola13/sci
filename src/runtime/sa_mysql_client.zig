// MySQL / MariaDB client runtime for the sci/sa_std platform layer.
test "sa_mysql_client_tests" { std.testing.refAllDecls(@import("sa_mysql_client_test.zig")); }
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
pub const sio = @import("sio");

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
pub const CLIENT_CONNECT_WITH_DB: u32 = 0x0000_0008;
pub const CLIENT_PROTOCOL_41: u32 = 0x0000_0200;
const CLIENT_TRANSACTIONS: u32 = 0x0000_2000;
pub const CLIENT_SECURE_CONNECTION: u32 = 0x0000_8000;
pub const CLIENT_PLUGIN_AUTH: u32 = 0x0008_0000;

pub const CLIENT_BASE_FLAGS: u32 = CLIENT_LONG_PASSWORD | CLIENT_LONG_FLAG |
    CLIENT_PROTOCOL_41 | CLIENT_TRANSACTIONS | CLIENT_SECURE_CONNECTION |
    CLIENT_PLUGIN_AUTH;

// utf8mb4_general_ci: present on every MySQL 5.6+/MariaDB 10.x server,
// unlike utf8mb4_0900_ai_ci (id 255, MySQL 8 only).
pub const MYSQL_CHARSET_UTF8MB4: u8 = 45;

pub const SERVER_MORE_RESULTS_EXISTS: u16 = 0x0008;
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

pub const UNSIGNED_FLAG: u32 = 0x20;

pub const alloc = std.heap.page_allocator;

pub fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

pub fn sliceArg(ptr: ?[*]const u8, len: u64) ?[]const u8 {
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
pub const LenencInt = @import("sa_mysql_client_lenenc.zig").LenencInt;

pub const readLenencInt = @import("sa_mysql_client_lenenc.zig").readLenencInt;

pub const writeLenencInt = @import("sa_mysql_client_lenenc.zig").writeLenencInt;

pub const writeLenencString = @import("sa_mysql_client_lenenc.zig").writeLenencString;

// ---------------------------------------------------------------------------
// Authentication scrambles
// ---------------------------------------------------------------------------

/// mysql_native_password token: SHA1(pw) XOR SHA1(salt + SHA1(SHA1(pw))).
/// Empty password -> empty token.
pub const nativePasswordToken = @import("sa_mysql_client_auth.zig").nativePasswordToken;

/// caching_sha2_password scramble:
/// SHA256(pw) XOR SHA256(SHA256(SHA256(pw)) + salt).
/// Empty password -> empty token.
pub const cachingSha2Token = @import("sa_mysql_client_auth.zig").cachingSha2Token;

pub const AuthPlugin = @import("sa_mysql_client_auth.zig").AuthPlugin;

pub const authPluginFromName = @import("sa_mysql_client_auth.zig").authPluginFromName;

/// Compute the auth response for `plugin`; returns the token length
/// written to `out` (max 32 bytes), or null for an unsupported plugin.
pub const authToken = @import("sa_mysql_client_auth.zig").authToken;

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

    pub fn deinit(self: *Result) void {
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

pub const Conn = struct {
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

    pub fn recordServerError(self: *Conn, payload: []const u8) void {
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

    pub fn clearServerError(self: *Conn) void {
        self.err_no = 0;
        self.sql_state = .{ '0', '0', '0', '0', '0' };
        if (self.err_msg.len > 0) alloc.free(self.err_msg);
        self.err_msg = &.{};
    }

    pub fn markDead(self: *Conn) void {
        self.dead = true;
        if (self.stream) |s| {
            s.close(sio.io());
            self.stream = null;
            self.reader = null;
            self.writer = null;
        }
    }

    pub fn deinit(self: *Conn) void {
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

pub const IoError = error{ Io, Protocol, OutOfMemory };

/// Send one logical packet, splitting payloads at the 16MB-1 framing
/// limit as the protocol requires.
pub fn writePacket(conn: *Conn, payload: []const u8) IoError!void {
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
pub fn readPacket(conn: *Conn) IoError![]const u8 {
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

pub const Handshake = @import("sa_mysql_client_auth.zig").Handshake;

pub const parseHandshake = @import("sa_mysql_client_auth.zig").parseHandshake;

/// Send the handshake response and run the auth conversation.
/// Returns SA_STD_OK or a negative status; on failure the connection
/// keeps the recorded server error (if any) for the accessors.
pub const runAuth = @import("sa_mysql_client_auth.zig").runAuth;

pub fn mapIoErr(e: IoError) i32 {
    return switch (e) {
        error.Io => SA_STD_ERR_IO,
        error.Protocol => SA_MYSQL_ERR_PROTOCOL,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
    };
}

// ---------------------------------------------------------------------------
// Result-set reading
// ---------------------------------------------------------------------------

pub const QueryError = error{ Io, Protocol, OutOfMemory, ServerError, Unsupported };

pub fn mapQueryErr(conn: *Conn, e: QueryError) i32 {
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

pub const Cursor = @import("sa_mysql_client_result.zig").Cursor;

pub const isEofPacket = @import("sa_mysql_client_result.zig").isEofPacket;

pub const OkInfo = @import("sa_mysql_client_result.zig").OkInfo;

pub const parseOkPacket = @import("sa_mysql_client_result.zig").parseOkPacket;

pub const parseColumnDef = @import("sa_mysql_client_result.zig").parseColumnDef;

/// Read the packets of one result set whose first response packet was
/// already consumed and is passed as `first` (it is the column-count
/// packet, an OK packet, or an ERR packet).
/// `binary_rows` selects the binary row decoder (prepared statements).
pub const readOneResult = @import("sa_mysql_client_result.zig").readOneResult;

pub const mapReadErr = @import("sa_mysql_client_result.zig").mapReadErr;

pub const parseTextRow = @import("sa_mysql_client_result.zig").parseTextRow;

/// Decode one binary-protocol row into owned text-shaped values.
pub const parseBinaryRow = @import("sa_mysql_client_result.zig").parseBinaryRow;

pub const fmtAlloc = @import("sa_mysql_client_result.zig").fmtAlloc;

pub const decodeBinaryValue = @import("sa_mysql_client_result.zig").decodeBinaryValue;

/// Run one command whose response is a (possibly multi-) result set,
/// after writing `payload` as a single command packet at sequence 0.
/// Returns the first result; further result sets (only producible by
/// stored procedures, which v1 never calls) are drained and discarded
/// so the connection stays in sync, as documented in the .sai header.
pub const runCommand = @import("sa_mysql_client_result.zig").runCommand;

// ---------------------------------------------------------------------------
// Prepared statements
// ---------------------------------------------------------------------------

pub const Binding = @import("sa_mysql_client_stmt.zig").Binding;

pub const Stmt = @import("sa_mysql_client_stmt.zig").Stmt;

pub const prepareStmt = @import("sa_mysql_client_stmt.zig").prepareStmt;

pub const executeStmt = @import("sa_mysql_client_stmt.zig").executeStmt;

// ---------------------------------------------------------------------------
// Exported surface
// ---------------------------------------------------------------------------

pub fn connFrom(handle: u64) ?*Conn {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

pub fn resultFrom(handle: u64) ?*Result {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

pub fn stmtFrom(handle: u64) ?*Stmt {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
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

pub const bindSet = @import("sa_mysql_client_bind.zig").bindSet;

pub const sa_mysql_stmt_bind_null = @import("sa_mysql_client_bind.zig").sa_mysql_stmt_bind_null;

pub const sa_mysql_stmt_bind_i64 = @import("sa_mysql_client_bind.zig").sa_mysql_stmt_bind_i64;

pub const sa_mysql_stmt_bind_u64 = @import("sa_mysql_client_bind.zig").sa_mysql_stmt_bind_u64;

pub const sa_mysql_stmt_bind_f64 = @import("sa_mysql_client_bind.zig").sa_mysql_stmt_bind_f64;

pub const sa_mysql_stmt_bind_bytes = @import("sa_mysql_client_bind.zig").sa_mysql_stmt_bind_bytes;

pub const sa_mysql_stmt_param_count = @import("sa_mysql_client_bind.zig").sa_mysql_stmt_param_count;

pub const sa_mysql_stmt_execute = @import("sa_mysql_client_bind.zig").sa_mysql_stmt_execute;

pub const sa_mysql_stmt_close = @import("sa_mysql_client_bind.zig").sa_mysql_stmt_close;

// -- error / session accessors ----------------------------------------------

pub const sa_mysql_errno = @import("sa_mysql_client_bind.zig").sa_mysql_errno;

pub const sa_mysql_sqlstate = @import("sa_mysql_client_bind.zig").sa_mysql_sqlstate;

pub const sa_mysql_error_message = @import("sa_mysql_client_result_api.zig").sa_mysql_error_message;

pub const sa_mysql_server_version = @import("sa_mysql_client_result_api.zig").sa_mysql_server_version;

pub const sa_mysql_connection_id = @import("sa_mysql_client_result_api.zig").sa_mysql_connection_id;

// -- result accessors ---------------------------------------------------------

pub const sa_mysql_result_free = @import("sa_mysql_client_result_api.zig").sa_mysql_result_free;

pub const sa_mysql_result_has_result_set = @import("sa_mysql_client_result_api.zig").sa_mysql_result_has_result_set;

pub const sa_mysql_result_column_count = @import("sa_mysql_client_result_api.zig").sa_mysql_result_column_count;

pub const sa_mysql_result_column_name = @import("sa_mysql_client_result_api.zig").sa_mysql_result_column_name;

pub const sa_mysql_result_column_type = @import("sa_mysql_client_result_api.zig").sa_mysql_result_column_type;

pub const sa_mysql_result_row_count = @import("sa_mysql_client_result_api.zig").sa_mysql_result_row_count;

/// Fetch the next row's index sequentially; returns 1 and sets
/// out_row when a row is available, 0 when the result is exhausted.
pub const sa_mysql_result_next = @import("sa_mysql_client_result_api.zig").sa_mysql_result_next;

/// Read one value. On success out_ptr/out_len address result-owned
/// bytes (valid until the result is freed) and out_is_null is 1 for
/// SQL NULL (out_len is then 0).
pub const sa_mysql_result_value = @import("sa_mysql_client_result_api.zig").sa_mysql_result_value;

pub const sa_mysql_affected_rows = @import("sa_mysql_client_result_api.zig").sa_mysql_affected_rows;

pub const sa_mysql_last_insert_id = @import("sa_mysql_client_result_api.zig").sa_mysql_last_insert_id;

pub const sa_mysql_result_warnings = @import("sa_mysql_client_result_api.zig").sa_mysql_result_warnings;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

pub const testing = std.testing;

pub const hexToBytes = @import("sa_mysql_client_test.zig").hexToBytes;

// -- Scripted fake server: end-to-end protocol test ---------------------------
// The fake server speaks just enough of the wire protocol, from literal
// byte layouts, to verify the client independently: it checks the auth
// token against the hashlib-computed vector, serves one text result
// set, one prepare/execute round trip with a binary row (incl. a NULL
// column via the null bitmap), one ERR packet, PING and QUIT.

pub const FakeServer = @import("sa_mysql_client_test.zig").FakeServer;
