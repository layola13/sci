const std = @import("std");
const ALLOC = @import("sa_pg.zig").ALLOC;
const BodyReader = @import("sa_pg.zig").BodyReader;
const Conn = @import("sa_pg.zig").Conn;
const ERR_INVALID = @import("sa_pg.zig").ERR_INVALID;
const ERR_IO = @import("sa_pg.zig").ERR_IO;
const ERR_NET = @import("sa_pg.zig").ERR_NET;
const ERR_NOMEM = @import("sa_pg.zig").ERR_NOMEM;
const ERR_PG_SERVER = @import("sa_pg.zig").ERR_PG_SERVER;
const ERR_TRUNCATED = @import("sa_pg.zig").ERR_TRUNCATED;
const ERR_UNSUPPORTED = @import("sa_pg.zig").ERR_UNSUPPORTED;
const MsgBuilder = @import("sa_pg.zig").MsgBuilder;
const OK = @import("sa_pg.zig").OK;
const PgErr = @import("sa_pg.zig").PgErr;
const authenticate = @import("sa_pg.zig").authenticate;
const builtin = @import("sa_pg.zig").builtin;
const freeSlice = @import("sa_pg.zig").freeSlice;
const parseErrorBody = @import("sa_pg.zig").parseErrorBody;
const readMessage = @import("sa_pg.zig").readMessage;
const sio = @import("sa_pg.zig").sio;

pub fn sliceOf(ptr_: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return "";
    const p = ptr_ orelse return null;
    return p[0..@intCast(len)];
}

pub fn statusOf(err: PgErr) i32 {
    return switch (err) {
        error.InvalidArgument => ERR_INVALID,
        error.OutOfMemory => ERR_NOMEM,
        error.Io => ERR_IO,
        error.Protocol => ERR_NET,
        error.Unsupported => ERR_UNSUPPORTED,
        error.ServerError => ERR_PG_SERVER,
    };
}

pub fn copyOut(text: []const u8, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    if (out_len) |p| p.* = @intCast(text.len);
    if (text.len > cap) return ERR_TRUNCATED;
    if (text.len == 0) return OK;
    const dst = out orelse return ERR_INVALID;
    @memcpy(dst[0..text.len], text);
    return OK;
}

pub fn setSockTimeouts(fd: std.posix.fd_t, timeout_ms: u32) void {
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

pub fn finishConnect(conn: *Conn, user: []const u8, password: []const u8, database: []const u8) PgErr!void {
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

pub fn dial(host: []const u8, port: u16) !std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream });
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    return hn.connect(sio.io(), port, .{ .mode = .stream });
}
