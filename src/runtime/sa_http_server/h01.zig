const std = @import("std");
const builtin = @import("builtin");
const sa_std_net = @import("sa_ws_stream");
const sio = @import("sio");
const ws_net = @import("sa_ws_stream");
const HttpServer = @import("h02.zig").HttpServer;

/// Monotonic event counters (histogram cells, served tallies).
/// Zig sema rejects 64-bit atomic operands on targets whose widest
/// atomic is 32 bits (wasm32), so those targets use u32 cells and
/// widen on read; 64-bit targets keep exact u64 counters. The HTTP
/// server proper is UnsupportedPlatform on wasm, so the narrower
/// cells there only gate compilation, never live counts.
pub const CounterAtomic = if (@sizeOf(usize) >= 8) std.atomic.Value(u64) else std.atomic.Value(u32);

pub var sigpipe_installed = false;

pub var sigpipe_mu: std.atomic.Mutex = .unlocked;

pub fn installSigpipeHandler() void {
    // DEF-R7: the process-wide policy is SIG_IGN, installed at host
    // startup by sa_std's bootstrap constructor (see sa_std.zig). This
    // lazy re-install keeps the same disposition — SIG_IGN, not a
    // do-nothing handler — for contexts where this module is reached
    // without that constructor having run. (The pre-DEF-R7 version of
    // this install was dead code: its @hasDecl(std.posix.SIG, "PIPE")
    // gate is false for enum members on this Zig version, so the
    // sigaction was never executed.)
    if (comptime builtin.cpu.arch.isWasm() or builtin.os.tag != .linux) {
        return;
    } else {
        const act: std.posix.Sigaction = .{
            .handler = .{ .handler = std.posix.SIG.IGN },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.PIPE, &act, null);
    }}

pub fn ensureProcessSignalSafety() void {
    while (!sigpipe_mu.tryLock()) std.Thread.yield() catch {};
    defer sigpipe_mu.unlock();
    if (!sigpipe_installed) {
        installSigpipeHandler();
        sigpipe_installed = true;
    }
}

pub const Header = struct {
    name: []u8,
    value: []u8,
};

pub const max_v2_message_bytes: usize = 16 * 1024 * 1024;

pub const NetworkStatus = enum(u32) {
    ok = 0,
    would_block = 1,
    closed = 2,
    timeout = 3,
    too_large = 4,
    invalid = 5,
    io_error = 6,
};

pub const PollEvent = struct {
    pub const readable: u32 = 1;
    pub const writable: u32 = 2;
    pub const closed: u32 = 4;
};

pub fn timeoutMillis(timeout_ms: u32) i32 {
    return @intCast(@min(timeout_ms, @as(u32, @intCast(std.math.maxInt(i32)))));
}

pub fn statusFromError(err: anyerror) NetworkStatus {
    return switch (err) {
        error.WouldBlock => .would_block,
        error.EndOfStream,
        error.BrokenPipe,
        error.ConnectionAborted,
        error.ConnectionResetByPeer,
        error.NotOpenForReading,
        error.NotOpenForWriting,
        error.HttpConnectionClosing,
        error.HttpRequestTruncated,
        => .closed,
        error.BodyTooLarge, error.StreamTooLong => .too_large,
        error.InvalidCharacter,
        error.InvalidContentLength,
        error.InvalidWebSocketFrame,
        error.HttpHeadersInvalid,
        error.HttpHeadersOversize,
        error.InvalidArgument,
        => .invalid,
        else => .io_error,
    };
}

pub fn nowMillis() i64 {
    return std.Io.Timestamp.now(sio.io(), .awake).toMilliseconds();
}

pub fn nowMicros() i64 {
    return std.Io.Timestamp.now(sio.io(), .awake).toMicroseconds();
}

// ---------------------------------------------------------------------
// Resident accept-wait instrumentation (tail-fix D1). Always compiled
// in; per-request cost is a stamp write under the pool lock or one
// atomic increment, so the face's service discipline is observable
// without application-level probes. Segments:
//   0 delivery: us a pooled keep-alive request waited from first
//      being observed ready (queued_since stamp) to being claimed
//      and parsed by an acceptor.
//   1 exit:     time inside the v2 response send exports (poll for
//      writability + the write/sendfile itself).
//   2 missed:   number of claim sweeps in which a connection was
//      readable but another connection was served instead
//      (bucketed with the same thresholds, read as counts).
//   3 accept:   wall time inside one bounded/configured accept
//      call that returned a request (poll -> claim/fresh -> return).
// Bucket thresholds are microseconds for segments 0/1/3.
// Read via sa_http_server_hist_v2; SA_HTTP_HIST_DUMP=1 additionally
// dumps all segments to stderr every 16384 served accepts.
// ---------------------------------------------------------------------
pub const hist_segments: usize = 4;

pub const hist_buckets: usize = 20;

pub const HIST_SEG_DELIVERY: usize = 0;

pub const HIST_SEG_EXIT: usize = 1;

pub const HIST_SEG_MISSED: usize = 2;

pub const HIST_SEG_ACCEPT: usize = 3;

pub const hist_thresholds_us: [hist_buckets - 1]u64 = .{
    5, 10, 25, 50, 100, 250, 500, 1_000, 2_000, 5_000,
    10_000, 25_000, 50_000, 100_000, 250_000, 500_000,
    1_000_000, 2_500_000, 5_000_000,
};

/// Oldest-first sort key for claim candidates: an unstamped
/// candidate (stamp 0) sorts last, as if newest.
pub fn stampSortKey(stamp_us: i64) i64 {
    return if (stamp_us == 0) std.math.maxInt(i64) else stamp_us;
}

pub fn histBucketFor(value: u64) usize {
    for (hist_thresholds_us, 0..) |t, i| {
        if (value < t) return i;
    }
    return hist_buckets - 1;
}

pub var hist_dump_flag: std.atomic.Value(i32) = std.atomic.Value(i32).init(-1);

pub fn histDumpEnabled() bool {
    const cur = hist_dump_flag.load(.monotonic);
    if (cur >= 0) return cur != 0;
    const on = if (std.c.getenv("SA_HTTP_HIST_DUMP")) |v| v[0] != 0 and v[0] != '0' else false;
    hist_dump_flag.store(if (on) 1 else 0, .monotonic);
    return on;
}

pub fn pollStream(fd: std.posix.fd_t, events: i16, timeout_ms: u32, out_events: ?*u32) NetworkStatus {
    var poll_fds = [1]std.posix.pollfd{.{
        .fd = fd,
        .events = events,
        .revents = 0,
    }};
    const ready = std.posix.poll(&poll_fds, timeoutMillis(timeout_ms)) catch return .io_error;
    if (ready == 0) return if (timeout_ms == 0) .would_block else .timeout;

    const revents = poll_fds[0].revents;
    if (revents & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0) return .io_error;

    var result: u32 = 0;
    if (revents & std.posix.POLL.IN != 0) result |= PollEvent.readable;
    if (revents & std.posix.POLL.OUT != 0) result |= PollEvent.writable;
    if (revents & std.posix.POLL.HUP != 0) result |= PollEvent.closed;
    if (out_events) |slot| slot.* = result;
    if (result & (PollEvent.readable | PollEvent.writable) != 0) return .ok;
    if (result & PollEvent.closed != 0) return .closed;
    return .would_block;
}

pub fn setNonBlocking(stream: std.Io.net.Stream) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        return setNonBlockingNative(stream);
    }
}

pub fn setNonBlockingNative(stream: std.Io.net.Stream) !void {
    const fd = stream.socket.handle;
    const rc_get = std.c.fcntl(fd, std.os.linux.F.GETFL, @as(c_int, 0));
    if (rc_get < 0) return error.Unexpected;
    const flags: c_int = @intCast(rc_get);
    const nb_bit: c_int = @as(c_int, 1) << @intCast(@bitOffsetOf(std.posix.O, "NONBLOCK"));
    const rc_set = std.c.fcntl(fd, std.os.linux.F.SETFL, flags | nb_bit);
    if (rc_set < 0) return error.Unexpected;
}

/// Restore fully blocking I/O and clear any receive timeout.
pub fn acceptFlags() c_uint {
    if (comptime builtin.cpu.arch.isWasm()) {
        return 0;
    } else {
        return @intCast(std.posix.SOCK.CLOEXEC);
    }
}

pub fn setBlocking(stream: std.Io.net.Stream) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        return setBlockingNative(stream);
    }
}

pub fn setBlockingNative(stream: std.Io.net.Stream) !void {
    const fd = stream.socket.handle;
    const rc_get = std.c.fcntl(fd, std.os.linux.F.GETFL, @as(c_int, 0));
    if (rc_get < 0) return error.Unexpected;
    const flags: c_int = @intCast(rc_get);
    const nb_bit: c_int = @as(c_int, 1) << @intCast(@bitOffsetOf(std.posix.O, "NONBLOCK"));
    const rc_set = std.c.fcntl(fd, std.os.linux.F.SETFL, flags & ~nb_bit);
    if (rc_set < 0) return error.Unexpected;
    const zero = std.posix.timeval{ .sec = 0, .usec = 0 };
    std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&zero)) catch {};
}

pub fn ipprotoTcp() c_int {
    if (comptime builtin.cpu.arch.isWasm()) {
        return 6;
    } else {
        return std.posix.IPPROTO.TCP;
    }
}

pub fn setReceiveTimeout(stream: std.Io.net.Stream, timeout_ms: u32) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        return setReceiveTimeoutNative(stream, timeout_ms);
    }
}

pub fn setReceiveTimeoutNative(stream: std.Io.net.Stream, timeout_ms: u32) !void {
    if (timeout_ms == 0) return setNonBlocking(stream);
    const timeout = std.posix.timeval{
        .sec = @intCast(timeout_ms / 1000),
        .usec = @intCast((timeout_ms % 1000) * 1000),
    };
    try std.posix.setsockopt(stream.socket.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));
}

pub fn setNonBlockingFd(fd: std.posix.fd_t) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        return setNonBlockingFdNative(fd);
    }
}

pub fn setNonBlockingFdNative(fd: std.posix.fd_t) !void {
    const rc_get = std.c.fcntl(fd, std.os.linux.F.GETFL, @as(c_int, 0));
    if (rc_get < 0) return error.Unexpected;
    const flags: c_int = @intCast(rc_get);
    const nb_bit: c_int = @as(c_int, 1) << @intCast(@bitOffsetOf(std.posix.O, "NONBLOCK"));
    const rc_set = std.c.fcntl(fd, std.os.linux.F.SETFL, flags | nb_bit);
    if (rc_set < 0) return error.Unexpected;
}

pub fn validHeaderName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        const valid = std.ascii.isAlphanumeric(ch) or switch (ch) {
            '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => true,
            else => false,
        };
        if (!valid) return false;
    }
    return true;
}

pub fn validHeaderValue(value: []const u8) bool {
    for (value) |ch| {
        if ((ch < 0x20 and ch != '\t') or ch == 0x7f) return false;
    }
    return true;
}

pub const ResponseHeaderBag = struct {
    allocator: std.mem.Allocator,
    content_type: []const u8,
    owns_content_type: bool = false,
    extra: std.array_list.Managed(Header),
    byte_len: usize = 0,

    fn init(allocator: std.mem.Allocator, content_type: []const u8) ResponseHeaderBag {
        return .{
            .allocator = allocator,
            .content_type = content_type,
            .extra = std.array_list.Managed(Header).init(allocator),
        };
    }

    fn deinit(self: *ResponseHeaderBag) void {
        if (self.owns_content_type) self.allocator.free(self.content_type);
        for (self.extra.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.extra.deinit();
    }

    fn setContentType(self: *ResponseHeaderBag, value: []const u8) !void {
        if (!validHeaderValue(value)) return error.InvalidArgument;
        const total = std.math.add(usize, value.len, self.byte_len) catch return error.StreamTooLong;
        if (total > max_v2_message_bytes) return error.StreamTooLong;
        const owned = try self.allocator.dupe(u8, value);
        if (self.owns_content_type) self.allocator.free(self.content_type);
        self.content_type = owned;
        self.owns_content_type = true;
    }

    fn add(self: *ResponseHeaderBag, name: []const u8, value: []const u8) !void {
        if (!validHeaderName(name) or !validHeaderValue(value)) return error.InvalidArgument;
        if (std.ascii.eqlIgnoreCase(name, "content-type")) return self.setContentType(value);
        if (std.ascii.eqlIgnoreCase(name, "content-length") or
            std.ascii.eqlIgnoreCase(name, "connection") or
            std.ascii.eqlIgnoreCase(name, "transfer-encoding")) return error.InvalidArgument;

        const new_size = std.math.add(usize, name.len, value.len) catch return error.StreamTooLong;
        const with_content_type = std.math.add(usize, self.content_type.len, self.byte_len) catch return error.StreamTooLong;
        const total = std.math.add(usize, with_content_type, new_size) catch return error.StreamTooLong;
        if (total > max_v2_message_bytes) return error.StreamTooLong;
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);
        try self.extra.append(.{ .name = owned_name, .value = owned_value });
        self.byte_len += new_size;
    }

    fn write(self: *const ResponseHeaderBag, writer: anytype) !void {
        try writer.print("content-type: {s}\r\n", .{self.content_type});
        for (self.extra.items) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
        }
    }
};

pub const WebSocketOpcode = enum(u8) {
    continuation = 0,
    text = 1,
    binary = 2,
    connection_close = 8,
    ping = 9,
    pong = 10,
};

/// Per-connection state for HTTP keep-alive. Owns the TCP stream plus any
/// pipelined bytes already read but not yet consumed.
/// Always heap-allocated and never moved while pooled.
pub const ConnState = struct {
    stream: std.Io.net.Stream,
    read_buffer: []u8,
    /// Bytes in read_buffer[request_start..read_len] are buffered pipelined data.
    read_len: usize = 0,
    request_start: usize = 0,
    /// def-accept form 2: per-connection claim flag. A pooled
    /// connection is parsed by exactly one acceptor at a time — the
    /// one that wins the CAS — while every other acceptor works on
    /// other connections in parallel. Set under claim, cleared when
    /// the connection is pushed back into the pool.
    claimed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Tail-fix instrumentation: wall time (us) when an acceptor
    /// first observed this pooled connection with a queued request
    /// (poll readiness or bytes already buffered at recycle time).
    /// 0 = not queued. Written under the pool lock (poll stamp,
    /// pushRecycled) or by the claim owner; read by the claim owner.
    queued_since_us: i64 = 0,
    /// Tail-fix instrumentation: claim sweeps that saw this
    /// connection readable but served another connection instead.
    /// Recorded into the missed-rounds histogram when claimed.
    missed_rounds: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
};

/// Cap on idle keep-alive connections held in the pool (each pins an 8KB
/// read buffer plus a socket). Overflow connections are closed on recycle.
/// Kept small on purpose: every accept scans the pool, so the cap bounds
/// the per-accept cost under connection-churn workloads.
pub const max_recycled_conns: usize = 64;

pub const conn_read_buffer_len: usize = 8192;

/// Buffered stream output is pushed to the socket once it reaches this size,
/// or on flush()/endChunked().
pub const stream_flush_threshold: usize = 8192;

/// Bound on one non-blocking keep-alive probe parse (covers normal TCP
/// segment gaps without stalling the accept loop).
pub const probe_parse_timeout_ms: u32 = 50;

/// One pooled connection as snapshotted by a claim sweep: values
/// only (pointer, fd, buffered flag); the pointer is dereferenced
/// solely after a claim or a locked presence re-check.
pub const PooledSnapshot = struct {
    conn: *ConnState,
    fd: std.posix.fd_t,
    has_buffered: bool,
};

/// Result of the internal poll over listener + idle pool + wake pipe.
/// One pooled connection a poll found actionable (tail-fix
/// form 1): the pointer is a pool item at collection time and
/// must be re-verified by tryClaimPooled before dereferencing.
pub const ReadyConn = struct {
    conn: *ConnState,
    revents: i16,
    has_buffered: bool,
    /// Queue stamp copied at collection time (under the pool
    /// lock): the claim sorts on this value and never has to
    /// dereference the pointer before tryClaimPooled.
    stamp_us: i64,
};

pub const PollOutcome = struct {
    status: NetworkStatus,
    /// A recycled connection may have a request (or died): sweep the pool.
    recycled_ready: bool,
    /// The listener has a pending connection.
    listener_ready: bool,
    /// Tail-fix form 1: the ready set of this poll, threaded into
    /// the claim so one accept cycle polls once instead of three
    /// times (export pre-poll, accept poll, claim re-poll).
    ready: [max_recycled_conns]ReadyConn = undefined,
    n_ready: usize = 0,
};

/// Request handler for sa_http_server_serve_threaded:
/// `fn (req: ?*anyopaque, ctx: ?*anyopaque) callconv(.c) void`.
/// Runs on plugin pool threads. The handler owns the request: it must send a
/// response (or upgrade) and then call sa_http_server_req_free, which
/// recycles keep-alive connections back into the pool.
pub const HttpServeHandlerFn = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void;

pub const ThreadPool = struct {
    server: *HttpServer,
    threads: []std.Thread,
    handler: HttpServeHandlerFn,
    handler_ctx: ?*anyopaque,
    max_requests: u64,
    served: CounterAtomic,
    stopping: std.atomic.Value(bool),
    done: std.atomic.Value(usize),
};

pub fn spawnPoolWorker(pool: *ThreadPool) !std.Thread {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.UnsupportedPlatform;
    } else {
        return std.Thread.spawn(.{}, workerMain, .{pool});
    }
}

pub fn workerMain(pool: *ThreadPool) void {
    const srv = pool.server;
    while (!pool.stopping.load(.acquire)) {
        if (pool.max_requests != 0 and pool.served.load(.acquire) >= pool.max_requests) {
            pool.stopping.store(true, .release);
            break;
        }
        const req = srv.acceptWorker(&pool.stopping) catch continue;
        _ = pool.served.fetchAdd(1, .acq_rel);
        pool.handler(@ptrCast(req), pool.handler_ctx);
    }
    _ = pool.done.fetchAdd(1, .acq_rel);
}

/// Bound on the request-head parse for connections accepted by the plugin
/// thread pool (slowloris guard for serve_threaded).
pub const worker_head_parse_timeout_ms: u32 = 5000;
