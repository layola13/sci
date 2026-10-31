//! sa_std PostgreSQL wire-protocol (v3) client, built into libsa_std.
//!
//! Synchronous, one result set per connection at a time (a new query
//! replaces the previous result), caller-serialized per connection --
//! the same discipline as the SQLite facade. Handles are opaque u64s
//! from a process-global registry.
//!
//! Status codes mirror sa_std.h (0 ok, 1 invalid argument, 2 invalid
//! handle, 3 not found, 5 no memory, 6 io, 7 net, 8 unsupported,
//! 9 truncated) plus one domain code defined here and in sa_std.h:
//! 12 (SA_STD_ERR_PG_SERVER) when the server answered with an
//! ErrorResponse; the SQLSTATE and message are then available through
//! sa_pg_last_sqlstate / sa_pg_last_error / sa_pg_last_error_detail.
//! Nothing is silently swallowed: unexpected protocol messages, a
//! dropped connection mid-reply, and auth mechanisms outside the
//! supported set all fail loudly and poison the connection (later
//! calls return 7 until it is closed).
//!
//! v1 scope: startup + trust / cleartext / md5 / SCRAM-SHA-256 auth,
//! simple query, extended query (Parse/Bind/Describe/Execute/Sync)
//! with text-format parameters and results. TLS is NOT implemented:
//! ssl_mode != 0 fails with 8 (unsupported) instead of silently
//! falling back to plaintext. Type coverage is by text round-trip:
//! int2/int4/int8, float4/float8, text/varchar, bool, date,
//! timestamp/timestamptz (and anything else PostgreSQL renders as
//! text is readable through the generic cell accessors).

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_IO: i32 = 6;
const ERR_NET: i32 = 7;
const ERR_UNSUPPORTED: i32 = 8;
const ERR_TRUNCATED: i32 = 9;
const ERR_PG_SERVER: i32 = 12;

const ALLOC = std.heap.page_allocator;

/// Free a possibly-literal empty slice (several owned-string fields
/// start life as the "" literal; only real allocations may be freed).
fn freeSlice(s: []u8) void {
    if (s.len > 0) ALLOC.free(s);
}

const PgErr = error{
    InvalidArgument,
    OutOfMemory,
    Io,
    Protocol,
    Unsupported,
    ServerError,
};

// ---------------------------------------------------------------------
// Handle registry (connections and prepared statements share the id
// space so a statement handle can never alias a connection handle).

var registry_spin: std.atomic.Mutex = .unlocked;
var registry_conns: std.AutoHashMapUnmanaged(u64, *Conn) = .{};
var registry_stmts: std.AutoHashMapUnmanaged(u64, *Stmt) = .{};
var registry_next: u64 = 1;

fn registryLock() void {
    while (!registry_spin.tryLock()) std.atomic.spinLoopHint();
}
fn registryUnlock() void {
    registry_spin.unlock();
}

fn lookupConn(handle: u64) ?*Conn {
    registryLock();
    defer registryUnlock();
    return registry_conns.get(handle);
}

fn lookupStmt(handle: u64) ?*Stmt {
    registryLock();
    defer registryUnlock();
    return registry_stmts.get(handle);
}

// ---------------------------------------------------------------------
// Data model

const Field = struct {
    name: []u8,
    type_oid: u32,
};

const Result = struct {
    fields: std.array_list.Managed(Field) = .init(ALLOC),
    rows: std.array_list.Managed(std.array_list.Managed(?[]u8)) = .init(ALLOC),
    tag: []u8 = "",

    fn clear(self: *Result) void {
        for (self.fields.items) |f| ALLOC.free(f.name);
        self.fields.clearRetainingCapacity();
        for (self.rows.items) |*row| {
            for (row.items) |cell| if (cell) |bytes| ALLOC.free(bytes);
            row.deinit();
        }
        self.rows.clearRetainingCapacity();
        freeSlice(self.tag);
        self.tag = "";
    }

    fn deinit(self: *Result) void {
        self.clear();
        self.fields.deinit();
        self.rows.deinit();
    }
};

const Conn = struct {
    stream: std.Io.net.Stream,
    fd: std.posix.fd_t,
    read_buf: [16384]u8 = undefined,
    write_buf: [8192]u8 = undefined,
    net_reader: std.Io.net.Stream.Reader = undefined,
    net_writer: std.Io.net.Stream.Writer = undefined,
    dead: bool = false,
    txn_status: u8 = 'I',
    server_version: []u8 = "",
    result: Result = .{},
    has_result: bool = false,
    err_sqlstate: [5]u8 = .{ '0', '0', '0', '0', '0' },
    err_severity: []u8 = "",
    err_message: []u8 = "",
    err_detail: []u8 = "",
    has_error: bool = false,
    stmt_counter: u64 = 0,

    fn deinit(self: *Conn) void {
        self.result.deinit();
        freeSlice(self.server_version);
        freeSlice(self.err_severity);
        freeSlice(self.err_message);
        freeSlice(self.err_detail);
    }

    fn clearError(self: *Conn) void {
        self.has_error = false;
        self.err_sqlstate = .{ '0', '0', '0', '0', '0' };
        freeSlice(self.err_severity);
        self.err_severity = "";
        freeSlice(self.err_message);
        self.err_message = "";
        freeSlice(self.err_detail);
        self.err_detail = "";
    }

    fn setError(self: *Conn, fields: ErrorFields) void {
        self.clearError();
        self.has_error = true;
        if (fields.code.len == 5) @memcpy(&self.err_sqlstate, fields.code[0..5]);
        self.err_severity = ALLOC.dupe(u8, fields.severity) catch "";
        self.err_message = ALLOC.dupe(u8, fields.message) catch "";
        self.err_detail = ALLOC.dupe(u8, fields.detail) catch "";
    }

    fn setLocalError(self: *Conn, sqlstate: *const [5]u8, message: []const u8) void {
        self.clearError();
        self.has_error = true;
        self.err_sqlstate = sqlstate.*;
        self.err_message = ALLOC.dupe(u8, message) catch "";
    }
};

const Stmt = struct {
    conn_handle: u64,
    name: []u8,
    param_oids: []u32 = &.{},
    binds: std.array_list.Managed(?[]u8) = .init(ALLOC),

    fn deinit(self: *Stmt) void {
        ALLOC.free(self.name);
        ALLOC.free(self.param_oids);
        for (self.binds.items) |b| if (b) |bytes| ALLOC.free(bytes);
        self.binds.deinit();
    }
};

// ---------------------------------------------------------------------
// Wire primitives

fn writeAll(conn: *Conn, bytes: []const u8) PgErr!void {
    conn.net_writer.interface.writeAll(bytes) catch return error.Io;
}

fn flushWrites(conn: *Conn) PgErr!void {
    conn.net_writer.interface.flush() catch return error.Io;
}

fn readExact(conn: *Conn, out: []u8) PgErr!void {
    var off: usize = 0;
    while (off < out.len) {
        const n = conn.net_reader.interface.readSliceShort(out[off..]) catch return error.Io;
        if (n == 0) return error.Io; // orderly shutdown mid-conversation
        off += n;
    }
}

const Message = struct {
    kind: u8,
    body: []u8, // owned by caller

    fn deinit(self: *const Message) void {
        ALLOC.free(self.body);
    }
};

fn readMessage(conn: *Conn) PgErr!Message {
    var head: [5]u8 = undefined;
    try readExact(conn, &head);
    const len = std.mem.readInt(u32, head[1..5], .big);
    // Length counts itself but not the type byte; 4 is an empty body.
    // Cap at 1 GiB: anything beyond that is a corrupt stream.
    if (len < 4 or len > (1 << 30)) {
        conn.dead = true;
        return error.Protocol;
    }
    const body = ALLOC.alloc(u8, len - 4) catch return error.OutOfMemory;
    errdefer ALLOC.free(body);
    try readExact(conn, body);
    return .{ .kind = head[0], .body = body };
}

const MsgBuilder = struct {
    buf: std.array_list.Managed(u8) = .init(ALLOC),

    fn deinit(self: *MsgBuilder) void {
        self.buf.deinit();
    }
    fn u8v(self: *MsgBuilder, v: u8) PgErr!void {
        self.buf.append(v) catch return error.OutOfMemory;
    }
    fn u16v(self: *MsgBuilder, v: u16) PgErr!void {
        var b: [2]u8 = undefined;
        std.mem.writeInt(u16, &b, v, .big);
        self.buf.appendSlice(&b) catch return error.OutOfMemory;
    }
    fn u32v(self: *MsgBuilder, v: u32) PgErr!void {
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, v, .big);
        self.buf.appendSlice(&b) catch return error.OutOfMemory;
    }
    fn bytes(self: *MsgBuilder, v: []const u8) PgErr!void {
        self.buf.appendSlice(v) catch return error.OutOfMemory;
    }
    fn cstr(self: *MsgBuilder, v: []const u8) PgErr!void {
        try self.bytes(v);
        try self.u8v(0);
    }
    /// Frame the accumulated body with a type byte + length and send.
    fn send(self: *MsgBuilder, conn: *Conn, kind: u8) PgErr!void {
        var head: [5]u8 = undefined;
        head[0] = kind;
        std.mem.writeInt(u32, head[1..5], @intCast(self.buf.items.len + 4), .big);
        try writeAll(conn, &head);
        try writeAll(conn, self.buf.items);
        try flushWrites(conn);
    }
    /// Startup-family messages carry no type byte.
    fn sendUntyped(self: *MsgBuilder, conn: *Conn) PgErr!void {
        var head: [4]u8 = undefined;
        std.mem.writeInt(u32, &head, @intCast(self.buf.items.len + 4), .big);
        try writeAll(conn, &head);
        try writeAll(conn, self.buf.items);
        try flushWrites(conn);
    }
};

// ---------------------------------------------------------------------
// Message body parsers (pure functions over the body bytes; unit
// tested without a server).

const BodyReader = struct {
    body: []const u8,
    pos: usize = 0,

    fn u8v(self: *BodyReader) PgErr!u8 {
        if (self.pos + 1 > self.body.len) return error.Protocol;
        defer self.pos += 1;
        return self.body[self.pos];
    }
    fn u16v(self: *BodyReader) PgErr!u16 {
        if (self.pos + 2 > self.body.len) return error.Protocol;
        defer self.pos += 2;
        return std.mem.readInt(u16, self.body[self.pos..][0..2], .big);
    }
    fn u32v(self: *BodyReader) PgErr!u32 {
        if (self.pos + 4 > self.body.len) return error.Protocol;
        defer self.pos += 4;
        return std.mem.readInt(u32, self.body[self.pos..][0..4], .big);
    }
    fn i32v(self: *BodyReader) PgErr!i32 {
        return @bitCast(try self.u32v());
    }
    fn bytes(self: *BodyReader, n: usize) PgErr![]const u8 {
        if (self.pos + n > self.body.len) return error.Protocol;
        defer self.pos += n;
        return self.body[self.pos..][0..n];
    }
    fn cstr(self: *BodyReader) PgErr![]const u8 {
        const start = self.pos;
        while (self.pos < self.body.len) : (self.pos += 1) {
            if (self.body[self.pos] == 0) {
                defer self.pos += 1;
                return self.body[start..self.pos];
            }
        }
        return error.Protocol;
    }
};

const ErrorFields = struct {
    severity: []const u8 = "",
    code: []const u8 = "",
    message: []const u8 = "",
    detail: []const u8 = "",
};

fn parseErrorBody(body: []const u8) ErrorFields {
    var out = ErrorFields{};
    var r = BodyReader{ .body = body };
    while (true) {
        const kind = r.u8v() catch return out;
        if (kind == 0) return out;
        const value = r.cstr() catch return out;
        switch (kind) {
            // 'S' is the localized severity, 'V' the invariant one;
            // V wins regardless of field order.
            'S' => {
                if (out.severity.len == 0) out.severity = value;
            },
            'V' => out.severity = value,
            'C' => out.code = value,
            'M' => out.message = value,
            'D' => out.detail = value,
            else => {},
        }
    }
}

fn parseRowDescription(body: []const u8, fields: *std.array_list.Managed(Field)) PgErr!void {
    var r = BodyReader{ .body = body };
    const count = try r.u16v();
    var i: u16 = 0;
    while (i < count) : (i += 1) {
        const name = try r.cstr();
        _ = try r.u32v(); // table oid
        _ = try r.u16v(); // column attribute number
        const type_oid = try r.u32v();
        _ = try r.u16v(); // type length
        _ = try r.i32v(); // type modifier
        _ = try r.u16v(); // format code (text in v1)
        fields.append(.{ .name = ALLOC.dupe(u8, name) catch return error.OutOfMemory, .type_oid = type_oid }) catch return error.OutOfMemory;
    }
}

fn parseDataRow(body: []const u8, row: *std.array_list.Managed(?[]u8)) PgErr!void {
    var r = BodyReader{ .body = body };
    const count = try r.u16v();
    var i: u16 = 0;
    while (i < count) : (i += 1) {
        const len = try r.i32v();
        if (len == -1) {
            row.append(null) catch return error.OutOfMemory;
        } else if (len < 0) {
            return error.Protocol;
        } else {
            const raw = try r.bytes(@intCast(len));
            row.append(ALLOC.dupe(u8, raw) catch return error.OutOfMemory) catch return error.OutOfMemory;
        }
    }
}

/// Trailing count of a CommandComplete tag ("INSERT 0 3" -> 3,
/// "SELECT 5" -> 5, "CREATE TABLE" -> null).
/// CommandComplete bodies carry the tag as a NUL-terminated string;
/// strip the terminator (exactly one, when present) before storing.
fn cleanTag(body: []const u8) []const u8 {
    if (body.len > 0 and body[body.len - 1] == 0) return body[0 .. body.len - 1];
    return body;
}

fn parseTagCount(tag: []const u8) ?u64 {
    var end = tag.len;
    while (end > 0 and tag[end - 1] == ' ') end -= 1;
    if (end == 0) return null;
    var start = end;
    while (start > 0 and std.ascii.isDigit(tag[start - 1])) start -= 1;
    if (start == end) return null;
    if (start > 0 and tag[start - 1] != ' ') return null;
    return std.fmt.parseInt(u64, tag[start..end], 10) catch null;
}

// ---------------------------------------------------------------------
// Reply draining

/// Read messages until ReadyForQuery, filling conn.result from row
/// descriptions / data rows / the command tag. Returns error.Server
/// when an ErrorResponse was seen (details in conn's error slots).
/// Any other surprise poisons the connection and yields error.Protocol.
/// When `collect` is false (Describe of a statement) row descriptions
/// are returned via `desc_fields` instead of the connection result.
fn drainUntilReady(conn: *Conn, collect: bool, desc_fields: ?*std.array_list.Managed(Field)) PgErr!void {
    var saw_error = false;
    while (true) {
        const msg = try readMessage(conn);
        defer msg.deinit();
        switch (msg.kind) {
            'Z' => {
                if (msg.body.len == 1) conn.txn_status = msg.body[0];
                if (saw_error) return error.ServerError;
                return;
            },
            'T' => {
                if (collect) {
                    conn.result.clear();
                    try parseRowDescription(msg.body, &conn.result.fields);
                    conn.has_result = true;
                } else if (desc_fields) |df| {
                    try parseRowDescription(msg.body, df);
                }
            },
            'D' => {
                if (collect) {
                    var row: std.array_list.Managed(?[]u8) = .init(ALLOC);
                    errdefer {
                        for (row.items) |c| if (c) |b| ALLOC.free(b);
                        row.deinit();
                    }
                    try parseDataRow(msg.body, &row);
                    conn.result.rows.append(row) catch return error.OutOfMemory;
                }
            },
            'C' => {
                if (collect) {
                    freeSlice(conn.result.tag);
                    conn.result.tag = ALLOC.dupe(u8, cleanTag(msg.body)) catch return error.OutOfMemory;
                    conn.has_result = true;
                }
            },
            'E' => {
                conn.setError(parseErrorBody(msg.body));
                saw_error = true;
            },
            'I' => { // EmptyQueryResponse
                if (collect) {
                    conn.result.clear();
                    conn.has_result = true;
                }
            },
            'n', 't', '1', '2', 's' => {
                // NoData / ParameterDescription / ParseComplete /
                // BindComplete / PortalSuspended: statement machinery
                // messages the caller accounts for. PortalSuspended
                // cannot occur: Execute always asks for all rows.
            },
            'S' => { // ParameterStatus can arrive at any time
                var r = BodyReader{ .body = msg.body };
                const name = r.cstr() catch continue;
                const value = r.cstr() catch continue;
                if (std.mem.eql(u8, name, "server_version")) {
                    freeSlice(conn.server_version);
                    conn.server_version = ALLOC.dupe(u8, value) catch return error.OutOfMemory;
                }
            },
            'N', 'A', 'K' => {}, // notices, notifications, key data
            else => {
                conn.dead = true;
                return error.Protocol;
            },
        }
    }
}

// ---------------------------------------------------------------------
// Authentication helpers

fn hexLower(bytes: []const u8, out: []u8) void {
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 0x0f];
    }
}

/// PostgreSQL md5 auth: "md5" + hex(md5(hex(md5(password+user)) + salt)).
fn md5AuthResponse(user: []const u8, password: []const u8, salt: *const [4]u8, out: *[35]u8) void {
    var inner: [16]u8 = undefined;
    {
        var h = std.crypto.hash.Md5.init(.{});
        h.update(password);
        h.update(user);
        h.final(&inner);
    }
    var inner_hex: [32]u8 = undefined;
    hexLower(&inner, &inner_hex);
    var outer: [16]u8 = undefined;
    {
        var h = std.crypto.hash.Md5.init(.{});
        h.update(&inner_hex);
        h.update(salt);
        h.final(&outer);
    }
    @memcpy(out[0..3], "md5");
    hexLower(&outer, out[3..35]);
}

const HmacSha256 = std.crypto.auth.hmac.Hmac(std.crypto.hash.sha2.Sha256);

const ScramState = struct {
    client_nonce: []u8,
    client_first_bare: []u8,
    salted_password: [32]u8 = undefined,

    fn deinit(self: *ScramState) void {
        freeSlice(self.client_nonce);
        freeSlice(self.client_first_bare);
    }
};

fn saslEscape(name: []const u8, out: *std.array_list.Managed(u8)) PgErr!void {
    for (name) |c| {
        switch (c) {
            '=' => out.appendSlice("=3D") catch return error.OutOfMemory,
            ',' => out.appendSlice("=2C") catch return error.OutOfMemory,
            else => out.append(c) catch return error.OutOfMemory,
        }
    }
}

fn scramClientFirst(user: []const u8, state: *ScramState) PgErr![]u8 {
    var nonce_raw: [18]u8 = undefined;
    sio.io().randomSecure(&nonce_raw) catch return error.Io;
    var nonce_buf: [24]u8 = undefined;
    const nonce = std.base64.standard.Encoder.encode(&nonce_buf, &nonce_raw);
    state.client_nonce = ALLOC.dupe(u8, nonce) catch return error.OutOfMemory;

    var bare: std.array_list.Managed(u8) = .init(ALLOC);
    errdefer bare.deinit();
    bare.appendSlice("n=") catch return error.OutOfMemory;
    try saslEscape(user, &bare);
    bare.appendSlice(",r=") catch return error.OutOfMemory;
    bare.appendSlice(nonce) catch return error.OutOfMemory;
    state.client_first_bare = bare.toOwnedSlice() catch return error.OutOfMemory;

    var first: std.array_list.Managed(u8) = .init(ALLOC);
    errdefer first.deinit();
    first.appendSlice("n,,") catch return error.OutOfMemory;
    first.appendSlice(state.client_first_bare) catch return error.OutOfMemory;
    return first.toOwnedSlice() catch error.OutOfMemory;
}

/// Consume the server-first message, produce the client-final message,
/// and remember the expected server signature for SASLFinal checking.
fn scramClientFinal(state: *ScramState, password: []const u8, server_first: []const u8, expected_server_sig: *[32]u8) PgErr![]u8 {
    var server_nonce: []const u8 = "";
    var salt_b64: []const u8 = "";
    var iterations: u32 = 0;
    var it = std.mem.splitScalar(u8, server_first, ',');
    while (it.next()) |part| {
        if (part.len < 2 or part[1] != '=') return error.Protocol;
        switch (part[0]) {
            'r' => server_nonce = part[2..],
            's' => salt_b64 = part[2..],
            'i' => iterations = std.fmt.parseInt(u32, part[2..], 10) catch return error.Protocol,
            'e' => {
                return error.ServerError; // server sent a SASL error extension
            },
            else => return error.Protocol,
        }
    }
    if (server_nonce.len == 0 or salt_b64.len == 0 or iterations == 0) return error.Protocol;
    if (!std.mem.startsWith(u8, server_nonce, state.client_nonce)) return error.Protocol;
    if (iterations > 1_000_000) return error.Protocol; // sanity bound vs hostile servers

    var salt: [64]u8 = undefined;
    const salt_len = std.base64.standard.Decoder.calcSizeForSlice(salt_b64) catch return error.Protocol;
    if (salt_len > salt.len) return error.Protocol;
    std.base64.standard.Decoder.decode(salt[0..salt_len], salt_b64) catch return error.Protocol;

    std.crypto.pwhash.pbkdf2(&state.salted_password, password, salt[0..salt_len], iterations, HmacSha256) catch return error.Protocol;

    var client_key: [32]u8 = undefined;
    HmacSha256.create(&client_key, "Client Key", &state.salted_password);
    var stored_key: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&client_key, &stored_key, .{});

    // client-final-without-proof = "c=biws,r=<server nonce>"
    var without_proof: std.array_list.Managed(u8) = .init(ALLOC);
    defer without_proof.deinit();
    without_proof.appendSlice("c=biws,r=") catch return error.OutOfMemory;
    without_proof.appendSlice(server_nonce) catch return error.OutOfMemory;

    var auth_message: std.array_list.Managed(u8) = .init(ALLOC);
    defer auth_message.deinit();
    auth_message.appendSlice(state.client_first_bare) catch return error.OutOfMemory;
    auth_message.append(',') catch return error.OutOfMemory;
    auth_message.appendSlice(server_first) catch return error.OutOfMemory;
    auth_message.append(',') catch return error.OutOfMemory;
    auth_message.appendSlice(without_proof.items) catch return error.OutOfMemory;

    var client_signature: [32]u8 = undefined;
    HmacSha256.create(&client_signature, auth_message.items, &stored_key);
    var proof: [32]u8 = undefined;
    for (0..32) |i| proof[i] = client_key[i] ^ client_signature[i];

    var server_key: [32]u8 = undefined;
    HmacSha256.create(&server_key, "Server Key", &state.salted_password);
    HmacSha256.create(expected_server_sig, auth_message.items, &server_key);

    var proof_b64: [44]u8 = undefined;
    const proof_enc = std.base64.standard.Encoder.encode(&proof_b64, &proof);
    var final_msg: std.array_list.Managed(u8) = .init(ALLOC);
    errdefer final_msg.deinit();
    final_msg.appendSlice(without_proof.items) catch return error.OutOfMemory;
    final_msg.appendSlice(",p=") catch return error.OutOfMemory;
    final_msg.appendSlice(proof_enc) catch return error.OutOfMemory;
    return final_msg.toOwnedSlice() catch error.OutOfMemory;
}

fn scramVerifyServerFinal(expected: *const [32]u8, server_final: []const u8) PgErr!void {
    var it = std.mem.splitScalar(u8, server_final, ',');
    while (it.next()) |part| {
        if (part.len < 2 or part[1] != '=') return error.Protocol;
        switch (part[0]) {
            'v' => {
                var got: [32]u8 = undefined;
                const n = std.base64.standard.Decoder.calcSizeForSlice(part[2..]) catch return error.Protocol;
                if (n != 32) return error.Protocol;
                std.base64.standard.Decoder.decode(&got, part[2..]) catch return error.Protocol;
                if (!timingSafeEql32(&got, expected)) return error.Protocol;
                return;
            },
            'e' => return error.ServerError,
            else => return error.Protocol,
        }
    }
    return error.Protocol;
}

fn timingSafeEql32(a: *const [32]u8, b: *const [32]u8) bool {
    var diff: u8 = 0;
    for (a.*, b.*) |x, y| diff |= x ^ y;
    return diff == 0;
}

fn sendPassword(conn: *Conn, password: []const u8) PgErr!void {
    var b = MsgBuilder{};
    defer b.deinit();
    try b.cstr(password);
    try b.send(conn, 'p');
}

/// Run the post-startup authentication exchange until AuthenticationOk.
/// `scram` state is threaded through SASL rounds.
fn authenticate(conn: *Conn, user: []const u8, password: []const u8) PgErr!void {
    var scram: ?ScramState = null;
    defer {
        if (scram) |*s| s.deinit();
    }
    var expected_sig: [32]u8 = undefined;
    var have_expected_sig = false;

    while (true) {
        const msg = try readMessage(conn);
        defer msg.deinit();
        switch (msg.kind) {
            'R' => {
                var r = BodyReader{ .body = msg.body };
                const code = try r.u32v();
                switch (code) {
                    0 => return, // AuthenticationOk; startup continues in caller
                    3 => try sendPassword(conn, password),
                    5 => {
                        const salt = try r.bytes(4);
                        var salt4: [4]u8 = undefined;
                        @memcpy(&salt4, salt[0..4]);
                        var resp: [35]u8 = undefined;
                        md5AuthResponse(user, password, &salt4, &resp);
                        try sendPassword(conn, &resp);
                    },
                    10 => { // SASL: mechanism name list, empty string ends it
                        var offered_scram = false;
                        while (true) {
                            const name = try r.cstr();
                            if (name.len == 0) break;
                            if (std.mem.eql(u8, name, "SCRAM-SHA-256")) offered_scram = true;
                        }
                        if (!offered_scram) return error.Unsupported;
                        scram = .{ .client_nonce = "", .client_first_bare = "" };
                        const first = try scramClientFirst(user, &scram.?);
                        defer ALLOC.free(first);
                        var b = MsgBuilder{};
                        defer b.deinit();
                        try b.cstr("SCRAM-SHA-256");
                        try b.u32v(@intCast(first.len));
                        try b.bytes(first);
                        try b.send(conn, 'p');
                    },
                    11 => { // SASLContinue: server-first (body after the auth type code)
                        if (scram == null) return error.Protocol;
                        const final_msg = try scramClientFinal(&scram.?, password, msg.body[r.pos..], &expected_sig);
                        defer ALLOC.free(final_msg);
                        have_expected_sig = true;
                        var b = MsgBuilder{};
                        defer b.deinit();
                        try b.bytes(final_msg);
                        try b.send(conn, 'p');
                    },
                    12 => { // SASLFinal: verify server signature, then 'R' 0 follows
                        if (!have_expected_sig) return error.Protocol;
                        try scramVerifyServerFinal(&expected_sig, msg.body[r.pos..]);
                    },
                    else => return error.Unsupported, // e.g. GSSAPI / SSPI / SCM credentials
                }
            },
            'E' => {
                conn.setError(parseErrorBody(msg.body));
                return error.ServerError;
            },
            'N' => {},
            else => return error.Protocol,
        }
    }
}

// ---------------------------------------------------------------------
// ABI helpers

fn sliceOf(ptr_: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return "";
    const p = ptr_ orelse return null;
    return p[0..@intCast(len)];
}

fn statusOf(err: PgErr) i32 {
    return switch (err) {
        error.InvalidArgument => ERR_INVALID,
        error.OutOfMemory => ERR_NOMEM,
        error.Io => ERR_IO,
        error.Protocol => ERR_NET,
        error.Unsupported => ERR_UNSUPPORTED,
        error.ServerError => ERR_PG_SERVER,
    };
}

/// Caller-buffer copy-out: 0 on success, 9 when cap is too small
/// (out_len then holds the full length and nothing is copied).
fn copyOut(text: []const u8, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    if (out_len) |p| p.* = @intCast(text.len);
    if (text.len > cap) return ERR_TRUNCATED;
    if (text.len == 0) return OK;
    const dst = out orelse return ERR_INVALID;
    @memcpy(dst[0..text.len], text);
    return OK;
}

fn setSockTimeouts(fd: std.posix.fd_t, timeout_ms: u32) void {
    // WASI has no socket layer in std.posix (SOL is a void
    // placeholder there); the helper is best-effort everywhere
    // (its callers ignore failures), and a WASI build cannot open
    // sockets in the first place, so skipping is the whole
    // behaviour there.
    if (comptime builtin.os.tag != .wasi) {
        const tv = std.posix.timeval{
            .sec = @intCast(timeout_ms / 1000),
            .usec = @intCast((timeout_ms % 1000) * 1000),
        };
        std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&tv)) catch {};
        std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&tv)) catch {};
    }
}

// ---------------------------------------------------------------------
// ABI: connections

/// Startup message + authentication + startup tail, on an already
/// dialed connection. On error the caller tears the connection down;
/// ErrorResponse details are recorded on the (doomed) connection and
/// surface only as the mapped status, since no handle exists yet.
fn finishConnect(conn: *Conn, user: []const u8, password: []const u8, database: []const u8) PgErr!void {
    {
        var b = MsgBuilder{};
        defer b.deinit();
        try b.u32v(196608); // protocol 3.0
        try b.cstr("user");
        try b.cstr(user);
        try b.cstr("database");
        try b.cstr(database);
        try b.cstr("client_encoding");
        try b.cstr("UTF8");
        try b.cstr("application_name");
        try b.cstr("sa_std_pg");
        try b.u8v(0);
        try b.sendUntyped(conn);
    }

    try authenticate(conn, user, password);

    // Startup tail: ParameterStatus / BackendKeyData until ReadyForQuery.
    while (true) {
        const msg = try readMessage(conn);
        defer msg.deinit();
        switch (msg.kind) {
            'Z' => {
                if (msg.body.len == 1) conn.txn_status = msg.body[0];
                return;
            },
            'S' => {
                var r = BodyReader{ .body = msg.body };
                const name = try r.cstr();
                const value = try r.cstr();
                if (std.mem.eql(u8, name, "server_version")) {
                    freeSlice(conn.server_version);
                    conn.server_version = ALLOC.dupe(u8, value) catch return error.OutOfMemory;
                }
            },
            'E' => {
                conn.setError(parseErrorBody(msg.body));
                return error.ServerError;
            },
            'N', 'K' => {},
            else => return error.Protocol,
        }
    }
}

/// Connect and authenticate. timeout_ms bounds socket reads/writes
/// after connect (0 selects the default 10000). ssl_mode: 0 =
/// plaintext; any other value returns 8 in v1 (TLS not implemented;
/// never a silent plaintext fallback when TLS was requested).
pub export fn sa_pg_connect(
    host_ptr: ?[*]const u8,
    host_len: u64,
    port: u32,
    user_ptr: ?[*]const u8,
    user_len: u64,
    password_ptr: ?[*]const u8,
    password_len: u64,
    database_ptr: ?[*]const u8,
    database_len: u64,
    timeout_ms: u32,
    ssl_mode: u32,
    out_handle: ?*u64,
) i32 {
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    if (ssl_mode != 0) return ERR_UNSUPPORTED;
    const host = sliceOf(host_ptr, host_len) orelse return ERR_INVALID;
    const user = sliceOf(user_ptr, user_len) orelse return ERR_INVALID;
    const password = sliceOf(password_ptr, password_len) orelse return ERR_INVALID;
    const database = sliceOf(database_ptr, database_len) orelse return ERR_INVALID;
    if (host.len == 0 or user.len == 0 or database.len == 0) return ERR_INVALID;
    const effective_port: u16 = if (port == 0) 5432 else @intCast(port);

    const stream = dial(host, effective_port) catch return ERR_NET;
    const conn = ALLOC.create(Conn) catch {
        stream.close(sio.io());
        return ERR_NOMEM;
    };
    conn.* = .{ .stream = stream, .fd = stream.socket.handle };
    conn.net_reader = stream.reader(sio.io(), &conn.read_buf);
    conn.net_writer = stream.writer(sio.io(), &conn.write_buf);
    setSockTimeouts(conn.fd, if (timeout_ms == 0) 10000 else timeout_ms);
    finishConnect(conn, user, password, database) catch |err| {
        conn.deinit();
        ALLOC.destroy(conn);
        stream.close(sio.io());
        return statusOf(err);
    };

    registryLock();
    const handle = registry_next;
    registry_next += 1;
    registry_conns.put(ALLOC, handle, conn) catch {
        registryUnlock();
        return ERR_NOMEM;
    };
    registryUnlock();
    out.* = handle;
    return OK;
}

fn dial(host: []const u8, port: u16) !std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream });
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    return hn.connect(sio.io(), port, .{ .mode = .stream });
}

pub export fn sa_pg_close(handle: u64) i32 {
    registryLock();
    const conn = registry_conns.fetchRemove(handle) orelse {
        registryUnlock();
        return ERR_HANDLE;
    };
    // Drop statements still bound to this connection.
    var doomed: std.array_list.Managed(u64) = .init(ALLOC);
    var it = registry_stmts.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.*.conn_handle == handle) doomed.append(entry.key_ptr.*) catch {};
    }
    for (doomed.items) |sid| {
        if (registry_stmts.fetchRemove(sid)) |kv| {
            kv.value.deinit();
            ALLOC.destroy(kv.value);
        }
    }
    doomed.deinit();
    registryUnlock();

    const c = conn.value;
    if (!c.dead) {
        var b = MsgBuilder{};
        defer b.deinit();
        b.send(c, 'X') catch {}; // Terminate; close regardless
    }
    c.stream.close(sio.io());
    c.deinit();
    ALLOC.destroy(c);
    return OK;
}

pub export fn sa_pg_server_version(handle: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const conn = lookupConn(handle) orelse return ERR_HANDLE;
    return copyOut(conn.server_version, out, cap, out_len);
}

pub export fn sa_pg_txn_status(handle: u64, out_status: ?*u32) i32 {
    const conn = lookupConn(handle) orelse return ERR_HANDLE;
    const o = out_status orelse return ERR_INVALID;
    o.* = switch (conn.txn_status) {
        'I' => 0,
        'T' => 1,
        'E' => 2,
        else => 3,
    };
    return OK;
}

// ---------------------------------------------------------------------
// ABI: error accessors

pub export fn sa_pg_last_sqlstate(handle: u64, out: ?[*]u8) i32 {
    const conn = lookupConn(handle) orelse return ERR_HANDLE;
    if (!conn.has_error) return ERR_NOT_FOUND;
    const dst = out orelse return ERR_INVALID;
    @memcpy(dst[0..5], &conn.err_sqlstate);
    return OK;
}

pub export fn sa_pg_last_error(handle: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const conn = lookupConn(handle) orelse return ERR_HANDLE;
    if (!conn.has_error) return ERR_NOT_FOUND;
    return copyOut(conn.err_message, out, cap, out_len);
}

pub export fn sa_pg_last_error_detail(handle: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const conn = lookupConn(handle) orelse return ERR_HANDLE;
    if (!conn.has_error) return ERR_NOT_FOUND;
    return copyOut(conn.err_detail, out, cap, out_len);
}

// ---------------------------------------------------------------------
// ABI: simple query

pub export fn sa_pg_exec(handle: u64, sql_ptr: ?[*]const u8, sql_len: u64) i32 {
    const conn = lookupConn(handle) orelse return ERR_HANDLE;
    if (conn.dead) return ERR_NET;
    const sql = sliceOf(sql_ptr, sql_len) orelse return ERR_INVALID;
    if (sql.len == 0) return ERR_INVALID;
    conn.clearError();
    conn.result.clear();
    conn.has_result = false;

    var b = MsgBuilder{};
    defer b.deinit();
    b.cstr(sql) catch return ERR_NOMEM;
    b.send(conn, 'Q') catch return ERR_IO;
    drainUntilReady(conn, true, null) catch |err| {
        if (err == error.Io or err == error.Protocol) conn.dead = true;
        return statusOf(err);
    };
    return OK;
}

// ---------------------------------------------------------------------
// ABI: extended query (prepared statements)

fn prepareInner(conn: *Conn, conn_handle: u64, sql: []const u8) PgErr!u64 {
    conn.stmt_counter += 1;
    const name = std.fmt.allocPrint(ALLOC, "sa_pg_{d}", .{conn.stmt_counter}) catch return error.OutOfMemory;
    errdefer ALLOC.free(name);

    // Parse + Describe(statement) + Sync.
    {
        var b = MsgBuilder{};
        defer b.deinit();
        try b.cstr(name);
        try b.cstr(sql);
        try b.u16v(0); // no explicit param types
        try b.send(conn, 'P');
    }
    {
        var b = MsgBuilder{};
        defer b.deinit();
        try b.u8v('S');
        try b.cstr(name);
        try b.send(conn, 'D');
    }
    {
        var b = MsgBuilder{};
        defer b.deinit();
        try b.send(conn, 'S');
    }

    // Read until ReadyForQuery, harvesting 't' (parameter types).
    var param_oids: std.array_list.Managed(u32) = .init(ALLOC);
    errdefer param_oids.deinit();
    var saw_error = false;
    while (true) {
        const msg = readMessage(conn) catch |err| {
            conn.dead = true;
            return err;
        };
        defer msg.deinit();
        switch (msg.kind) {
            'Z' => {
                if (msg.body.len == 1) conn.txn_status = msg.body[0];
                break;
            },
            't' => {
                var r = BodyReader{ .body = msg.body };
                const count = try r.u16v();
                var i: u16 = 0;
                while (i < count) : (i += 1) {
                    const oid = try r.u32v();
                    param_oids.append(oid) catch return error.OutOfMemory;
                }
            },
            'E' => {
                conn.setError(parseErrorBody(msg.body));
                saw_error = true;
            },
            'T', 'n', '1', 'S', 'N', 'A', 'K' => {},
            else => {
                conn.dead = true;
                return error.Protocol;
            },
        }
    }
    if (saw_error) return error.ServerError;

    const stmt = ALLOC.create(Stmt) catch return error.OutOfMemory;
    errdefer ALLOC.destroy(stmt);
    stmt.* = .{ .conn_handle = conn_handle, .name = name };
    stmt.param_oids = param_oids.toOwnedSlice() catch return error.OutOfMemory;
    stmt.binds.appendNTimes(null, stmt.param_oids.len) catch return error.OutOfMemory;

    registryLock();
    const sid = registry_next;
    registry_next += 1;
    registry_stmts.put(ALLOC, sid, stmt) catch {
        registryUnlock();
        stmt.deinit();
        return error.OutOfMemory;
    };
    registryUnlock();
    return sid;
}

pub export fn sa_pg_prepare(handle: u64, sql_ptr: ?[*]const u8, sql_len: u64, out_stmt: ?*u64) i32 {
    const out = out_stmt orelse return ERR_INVALID;
    out.* = 0;
    const conn = lookupConn(handle) orelse return ERR_HANDLE;
    if (conn.dead) return ERR_NET;
    const sql = sliceOf(sql_ptr, sql_len) orelse return ERR_INVALID;
    if (sql.len == 0) return ERR_INVALID;
    conn.clearError();
    out.* = prepareInner(conn, handle, sql) catch |err| return statusOf(err);
    return OK;
}

pub export fn sa_pg_stmt_param_count(stmt_handle: u64, out_count: ?*u64) i32 {
    const stmt = lookupStmt(stmt_handle) orelse return ERR_HANDLE;
    const o = out_count orelse return ERR_INVALID;
    o.* = @intCast(stmt.param_oids.len);
    return OK;
}

pub export fn sa_pg_stmt_free(stmt_handle: u64) i32 {
    registryLock();
    const kv = registry_stmts.fetchRemove(stmt_handle) orelse {
        registryUnlock();
        return ERR_HANDLE;
    };
    registryUnlock();
    const stmt = kv.value;
    // Best-effort Close on a live connection; the registry entry is
    // gone either way.
    if (lookupConn(stmt.conn_handle)) |conn| {
        if (!conn.dead) {
            var b = MsgBuilder{};
            defer b.deinit();
            b.u8v('S') catch {};
            b.cstr(stmt.name) catch {};
            b.send(conn, 'C') catch {};
            var sync = MsgBuilder{};
            defer sync.deinit();
            sync.send(conn, 'S') catch {};
            drainUntilReady(conn, false, null) catch {};
        }
    }
    stmt.deinit();
    ALLOC.destroy(stmt);
    return OK;
}

fn bindSlot(stmt: *Stmt, index: u32) PgErr!*?[]u8 {
    if (index == 0 or index > stmt.binds.items.len) return error.InvalidArgument;
    return &stmt.binds.items[index - 1];
}

fn setBind(stmt: *Stmt, index: u32, value: ?[]const u8) i32 {
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

pub export fn sa_pg_execute(handle: u64, stmt_handle: u64) i32 {
    const conn = lookupConn(handle) orelse return ERR_HANDLE;
    const stmt = lookupStmt(stmt_handle) orelse return ERR_HANDLE;
    if (stmt.conn_handle != handle) return ERR_INVALID;
    if (conn.dead) return ERR_NET;
    conn.clearError();
    conn.result.clear();
    conn.has_result = false;

    // Bind (unnamed portal) + Describe(portal) + Execute + Sync.
    {
        var b = MsgBuilder{};
        defer b.deinit();
        b.cstr("") catch return ERR_NOMEM; // portal
        b.cstr(stmt.name) catch return ERR_NOMEM;
        b.u16v(0) catch return ERR_NOMEM; // params default to text
        b.u16v(@intCast(stmt.binds.items.len)) catch return ERR_NOMEM;
        for (stmt.binds.items) |bind| {
            if (bind) |v| {
                b.u32v(@intCast(v.len)) catch return ERR_NOMEM;
                b.bytes(v) catch return ERR_NOMEM;
            } else {
                b.u32v(@bitCast(@as(i32, -1))) catch return ERR_NOMEM;
            }
        }
        b.u16v(0) catch return ERR_NOMEM; // results default to text
        b.send(conn, 'B') catch return ERR_IO;
    }
    {
        var b = MsgBuilder{};
        defer b.deinit();
        b.u8v('P') catch return ERR_NOMEM;
        b.cstr("") catch return ERR_NOMEM;
        b.send(conn, 'D') catch return ERR_IO;
    }
    {
        var b = MsgBuilder{};
        defer b.deinit();
        b.cstr("") catch return ERR_NOMEM;
        b.u32v(0) catch return ERR_NOMEM; // all rows
        b.send(conn, 'E') catch return ERR_IO;
    }
    {
        var b = MsgBuilder{};
        defer b.deinit();
        b.send(conn, 'S') catch return ERR_IO;
    }
    drainUntilReady(conn, true, null) catch |err| {
        if (err == error.Io or err == error.Protocol) conn.dead = true;
        return statusOf(err);
    };
    return OK;
}

// ---------------------------------------------------------------------
// ABI: result accessors

fn resultConn(handle: u64) ?*Conn {
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

fn cellAt(conn: *Conn, row: u64, col: u64) ?*const ?[]u8 {
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

// ---------------------------------------------------------------------
// Unit tests (run under `zig build sa-std-unit`). The SCRAM and md5
// vectors were produced independently with Python hashlib/hmac and
// are asserted byte-for-byte.

test "pg md5 auth response matches reference vector" {
    var out: [35]u8 = undefined;
    md5AuthResponse("bob", "secret", &.{ 1, 2, 3, 4 }, &out);
    try std.testing.expectEqualStrings("md5f21dfe33ff3a9e03dbc3e008251fe5cc", &out);
}

test "pg scram-sha-256 client final and server verify" {
    var state = ScramState{
        .client_nonce = try ALLOC.dupe(u8, "ClientNonce123"),
        .client_first_bare = try ALLOC.dupe(u8, "n=alice,r=ClientNonce123"),
    };
    defer state.deinit();
    var expected_sig: [32]u8 = undefined;
    const server_first = "r=ClientNonce123ServerNonce,s=AAECAwQFBgcICQoLDA0ODw==,i=4096";
    const final_msg = try scramClientFinal(&state, "wonderland", server_first, &expected_sig);
    defer ALLOC.free(final_msg);
    try std.testing.expectEqualStrings(
        "c=biws,r=ClientNonce123ServerNonce,p=csb5CfCFSUvpkjN2wstfk95EFZMTN7Uv1LwkLTcNwh0=",
        final_msg,
    );
    try scramVerifyServerFinal(&expected_sig, "v=P4/PjPVdJBzd6HipXn8WldnX0faYBNTBHQLSg47Hsqw=");
    try std.testing.expectError(error.Protocol, scramVerifyServerFinal(&expected_sig, "v=AAAA/PjPVdJBzd6HipXn8WldnX0faYBNTBHQLSg47Hsqw="));
    // A server nonce that does not extend ours is a protocol error.
    var state2 = ScramState{
        .client_nonce = try ALLOC.dupe(u8, "ClientNonce123"),
        .client_first_bare = try ALLOC.dupe(u8, "n=alice,r=ClientNonce123"),
    };
    defer state2.deinit();
    var sig2: [32]u8 = undefined;
    try std.testing.expectError(error.Protocol, scramClientFinal(&state2, "wonderland", "r=OtherNonce,s=AAECAwQFBgcICQoLDA0ODw==,i=4096", &sig2));
}

test "pg row description and data row parsing" {
    // RowDescription body: 2 fields ("id" int4/23, "name" text/25).
    var body: std.array_list.Managed(u8) = .init(ALLOC);
    defer body.deinit();
    try body.appendSlice(&.{ 0, 2 });
    try body.appendSlice("id\x00");
    try body.appendSlice(&.{ 0, 0, 0, 0, 0, 0 }); // table oid + attnum
    try body.appendSlice(&.{ 0, 0, 0, 23, 0, 4, 0xff, 0xff, 0xff, 0xff, 0, 0 });
    try body.appendSlice("name\x00");
    try body.appendSlice(&.{ 0, 0, 0, 0, 0, 0 });
    try body.appendSlice(&.{ 0, 0, 0, 25, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0, 0 });

    var fields: std.array_list.Managed(Field) = .init(ALLOC);
    defer {
        for (fields.items) |f| ALLOC.free(f.name);
        fields.deinit();
    }
    try parseRowDescription(body.items, &fields);
    try std.testing.expectEqual(@as(usize, 2), fields.items.len);
    try std.testing.expectEqualStrings("id", fields.items[0].name);
    try std.testing.expectEqual(@as(u32, 23), fields.items[0].type_oid);
    try std.testing.expectEqualStrings("name", fields.items[1].name);
    try std.testing.expectEqual(@as(u32, 25), fields.items[1].type_oid);

    // DataRow body: "42", NULL, "hi".
    var dbody: std.array_list.Managed(u8) = .init(ALLOC);
    defer dbody.deinit();
    try dbody.appendSlice(&.{ 0, 3 });
    try dbody.appendSlice(&.{ 0, 0, 0, 2 });
    try dbody.appendSlice("42");
    try dbody.appendSlice(&.{ 0xff, 0xff, 0xff, 0xff });
    try dbody.appendSlice(&.{ 0, 0, 0, 2 });
    try dbody.appendSlice("hi");

    var row: std.array_list.Managed(?[]u8) = .init(ALLOC);
    defer {
        for (row.items) |c| if (c) |b| ALLOC.free(b);
        row.deinit();
    }
    try parseDataRow(dbody.items, &row);
    try std.testing.expectEqual(@as(usize, 3), row.items.len);
    try std.testing.expectEqualStrings("42", row.items[0].?);
    try std.testing.expect(row.items[1] == null);
    try std.testing.expectEqualStrings("hi", row.items[2].?);
}

test "pg error body and tag count parsing" {
    const fields = parseErrorBody("SERROR\x00VERROR\x00C42601\x00Msyntax error\x00Dnear \"x\"\x00\x00");
    try std.testing.expectEqualStrings("ERROR", fields.severity);
    try std.testing.expectEqualStrings("42601", fields.code);
    try std.testing.expectEqualStrings("syntax error", fields.message);
    try std.testing.expectEqualStrings("near \"x\"", fields.detail);

    try std.testing.expectEqual(@as(?u64, 3), parseTagCount("INSERT 0 3"));
    try std.testing.expectEqual(@as(?u64, 5), parseTagCount("SELECT 5"));
    // CommandComplete bodies are NUL-terminated on the wire.
    try std.testing.expectEqual(@as(?u64, 2), parseTagCount(cleanTag("INSERT 0 2\x00")));
    try std.testing.expectEqual(@as(?u64, null), parseTagCount(cleanTag("CREATE TABLE\x00")));
    try std.testing.expectEqual(@as(?u64, 0), parseTagCount("UPDATE 0"));
    try std.testing.expectEqual(@as(?u64, null), parseTagCount("CREATE TABLE"));
}

test "pg abi rejects invalid arguments and handles" {
    var handle: u64 = 77;
    try std.testing.expectEqual(ERR_INVALID, sa_pg_connect("", 0, 0, "u".ptr, 1, null, 0, "d".ptr, 1, 0, 0, &handle));
    try std.testing.expectEqual(ERR_UNSUPPORTED, sa_pg_connect("h".ptr, 1, 0, "u".ptr, 1, null, 0, "d".ptr, 1, 0, 2, &handle));
    try std.testing.expectEqual(ERR_HANDLE, sa_pg_close(987654321));
    var five: [5]u8 = undefined;
    try std.testing.expectEqual(ERR_HANDLE, sa_pg_last_sqlstate(987654321, &five));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_pg_result_rows(987654321, &handle));
}
