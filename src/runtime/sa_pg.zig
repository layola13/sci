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

test "sa_pg_tests" { std.testing.refAllDecls(@import("sa_pg_test.zig")); }

const std = @import("std");
pub const builtin = @import("builtin");
pub const sio = @import("sio");

pub const OK: i32 = 0;
pub const ERR_INVALID: i32 = 1;
pub const ERR_HANDLE: i32 = 2;
pub const ERR_NOT_FOUND: i32 = 3;
pub const ERR_NOMEM: i32 = 5;
pub const ERR_IO: i32 = 6;
pub const ERR_NET: i32 = 7;
pub const ERR_UNSUPPORTED: i32 = 8;
pub const ERR_TRUNCATED: i32 = 9;
pub const ERR_PG_SERVER: i32 = 12;

pub const ALLOC = std.heap.page_allocator;

/// Free a possibly-literal empty slice (several owned-string fields
/// start life as the "" literal; only real allocations may be freed).
pub fn freeSlice(s: []u8) void {
    if (s.len > 0) ALLOC.free(s);
}

pub const PgErr = error{
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

pub fn lookupConn(handle: u64) ?*Conn {
    registryLock();
    defer registryUnlock();
    return registry_conns.get(handle);
}

pub fn lookupStmt(handle: u64) ?*Stmt {
    registryLock();
    defer registryUnlock();
    return registry_stmts.get(handle);
}

// ---------------------------------------------------------------------
// Data model

pub const Field = struct {
    name: []u8,
    type_oid: u32,
};

const Result = struct {
    fields: std.array_list.Managed(Field) = .init(ALLOC),
    rows: std.array_list.Managed(std.array_list.Managed(?[]u8)) = .init(ALLOC),
    tag: []u8 = "",

    pub fn clear(self: *Result) void {
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

    pub fn deinit(self: *Result) void {
        self.clear();
        self.fields.deinit();
        self.rows.deinit();
    }
};

pub const Conn = struct {
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

    pub fn deinit(self: *Conn) void {
        self.result.deinit();
        freeSlice(self.server_version);
        freeSlice(self.err_severity);
        freeSlice(self.err_message);
        freeSlice(self.err_detail);
    }

    pub fn clearError(self: *Conn) void {
        self.has_error = false;
        self.err_sqlstate = .{ '0', '0', '0', '0', '0' };
        freeSlice(self.err_severity);
        self.err_severity = "";
        freeSlice(self.err_message);
        self.err_message = "";
        freeSlice(self.err_detail);
        self.err_detail = "";
    }

    pub fn setError(self: *Conn, fields: ErrorFields) void {
        self.clearError();
        self.has_error = true;
        if (fields.code.len == 5) @memcpy(&self.err_sqlstate, fields.code[0..5]);
        self.err_severity = ALLOC.dupe(u8, fields.severity) catch "";
        self.err_message = ALLOC.dupe(u8, fields.message) catch "";
        self.err_detail = ALLOC.dupe(u8, fields.detail) catch "";
    }

    pub fn setLocalError(self: *Conn, sqlstate: *const [5]u8, message: []const u8) void {
        self.clearError();
        self.has_error = true;
        self.err_sqlstate = sqlstate.*;
        self.err_message = ALLOC.dupe(u8, message) catch "";
    }
};

pub const Stmt = struct {
    conn_handle: u64,
    name: []u8,
    param_oids: []u32 = &.{},
    binds: std.array_list.Managed(?[]u8) = .init(ALLOC),

    pub fn deinit(self: *Stmt) void {
        ALLOC.free(self.name);
        ALLOC.free(self.param_oids);
        for (self.binds.items) |b| if (b) |bytes| ALLOC.free(bytes);
        self.binds.deinit();
    }
};

// ---------------------------------------------------------------------
// Wire primitives

pub const writeAll = @import("sa_pg_wire.zig").writeAll;

pub const flushWrites = @import("sa_pg_wire.zig").flushWrites;

pub const readExact = @import("sa_pg_wire.zig").readExact;

pub const Message = @import("sa_pg_wire.zig").Message;

pub const readMessage = @import("sa_pg_wire.zig").readMessage;

pub const MsgBuilder = @import("sa_pg_wire.zig").MsgBuilder;

// ---------------------------------------------------------------------
// Message body parsers (pure functions over the body bytes; unit
// tested without a server).

pub const BodyReader = @import("sa_pg_wire.zig").BodyReader;

pub const ErrorFields = @import("sa_pg_wire.zig").ErrorFields;

pub const parseErrorBody = @import("sa_pg_wire.zig").parseErrorBody;

pub const parseRowDescription = @import("sa_pg_wire.zig").parseRowDescription;

pub const parseDataRow = @import("sa_pg_wire.zig").parseDataRow;

/// Trailing count of a CommandComplete tag ("INSERT 0 3" -> 3,
/// "SELECT 5" -> 5, "CREATE TABLE" -> null).
/// CommandComplete bodies carry the tag as a NUL-terminated string;
/// strip the terminator (exactly one, when present) before storing.
pub const cleanTag = @import("sa_pg_wire.zig").cleanTag;

pub const parseTagCount = @import("sa_pg_wire.zig").parseTagCount;

// ---------------------------------------------------------------------
// Reply draining

/// Read messages until ReadyForQuery, filling conn.result from row
/// descriptions / data rows / the command tag. Returns error.Server
/// when an ErrorResponse was seen (details in conn's error slots).
/// Any other surprise poisons the connection and yields error.Protocol.
/// When `collect` is false (Describe of a statement) row descriptions
/// are returned via `desc_fields` instead of the connection result.
pub const drainUntilReady = @import("sa_pg_wire.zig").drainUntilReady;

// ---------------------------------------------------------------------
// Authentication helpers

pub const hexLower = @import("sa_pg_auth.zig").hexLower;

/// PostgreSQL md5 auth: "md5" + hex(md5(hex(md5(password+user)) + salt)).
pub const md5AuthResponse = @import("sa_pg_auth.zig").md5AuthResponse;

pub const HmacSha256 = @import("sa_pg_auth.zig").HmacSha256;

pub const ScramState = @import("sa_pg_auth.zig").ScramState;

pub const saslEscape = @import("sa_pg_auth.zig").saslEscape;

pub const scramClientFirst = @import("sa_pg_auth.zig").scramClientFirst;

/// Consume the server-first message, produce the client-final message,
/// and remember the expected server signature for SASLFinal checking.
pub const scramClientFinal = @import("sa_pg_auth.zig").scramClientFinal;

pub const scramVerifyServerFinal = @import("sa_pg_auth.zig").scramVerifyServerFinal;

pub const timingSafeEql32 = @import("sa_pg_auth.zig").timingSafeEql32;

pub const sendPassword = @import("sa_pg_auth.zig").sendPassword;

/// Run the post-startup authentication exchange until AuthenticationOk.
/// `scram` state is threaded through SASL rounds.
pub const authenticate = @import("sa_pg_auth.zig").authenticate;

// ---------------------------------------------------------------------
// ABI helpers

pub const sliceOf = @import("sa_pg_connect.zig").sliceOf;

pub const statusOf = @import("sa_pg_connect.zig").statusOf;

/// Caller-buffer copy-out: 0 on success, 9 when cap is too small
/// (out_len then holds the full length and nothing is copied).
pub const copyOut = @import("sa_pg_connect.zig").copyOut;

pub const setSockTimeouts = @import("sa_pg_connect.zig").setSockTimeouts;

// ---------------------------------------------------------------------
// ABI: connections

/// Startup message + authentication + startup tail, on an already
/// dialed connection. On error the caller tears the connection down;
/// ErrorResponse details are recorded on the (doomed) connection and
/// surface only as the mapped status, since no handle exists yet.
pub const finishConnect = @import("sa_pg_connect.zig").finishConnect;

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

pub const dial = @import("sa_pg_connect.zig").dial;

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

pub const bindSlot = @import("sa_pg_bind.zig").bindSlot;

pub const setBind = @import("sa_pg_bind.zig").setBind;

pub const sa_pg_bind_null = @import("sa_pg_bind.zig").sa_pg_bind_null;

pub const sa_pg_bind_text = @import("sa_pg_bind.zig").sa_pg_bind_text;

pub const sa_pg_bind_i64 = @import("sa_pg_bind.zig").sa_pg_bind_i64;

pub const sa_pg_bind_f64 = @import("sa_pg_bind.zig").sa_pg_bind_f64;

pub const sa_pg_bind_bool = @import("sa_pg_bind.zig").sa_pg_bind_bool;

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

pub const resultConn = @import("sa_pg_result.zig").resultConn;

pub const sa_pg_result_rows = @import("sa_pg_result.zig").sa_pg_result_rows;

pub const sa_pg_result_cols = @import("sa_pg_result.zig").sa_pg_result_cols;

pub const sa_pg_col_name = @import("sa_pg_result.zig").sa_pg_col_name;

pub const sa_pg_col_type_oid = @import("sa_pg_result.zig").sa_pg_col_type_oid;

pub const cellAt = @import("sa_pg_result.zig").cellAt;

pub const sa_pg_cell_is_null = @import("sa_pg_result.zig").sa_pg_cell_is_null;

pub const sa_pg_cell_len = @import("sa_pg_result.zig").sa_pg_cell_len;

pub const sa_pg_cell_copy = @import("sa_pg_result.zig").sa_pg_cell_copy;

pub const sa_pg_cell_i64 = @import("sa_pg_result.zig").sa_pg_cell_i64;

pub const sa_pg_cell_f64 = @import("sa_pg_result.zig").sa_pg_cell_f64;

pub const sa_pg_cell_bool = @import("sa_pg_result.zig").sa_pg_cell_bool;

pub const sa_pg_rows_affected = @import("sa_pg_result.zig").sa_pg_rows_affected;

// ---------------------------------------------------------------------
// Unit tests (run under `zig build sa-std-unit`). The SCRAM and md5
// vectors were produced independently with Python hashlib/hmac and
// are asserted byte-for-byte.





