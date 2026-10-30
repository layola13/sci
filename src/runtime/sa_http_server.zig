// Built-in HTTP/1.1 + WebSocket server core for sa_std.
// Moved into sci from sa_plugin_http_server (2026-10-24 architecture decision:
// HTTP/WS/TCP/UDP cores are built into sa_std; plugins only provide frameworks).
// Formerly vite_api.zig in the plugin (the file contained no Vite-specific code).
const std = @import("std");
const builtin = @import("builtin");
const sa_std_net = @import("sa_ws_stream");

const sio = @import("sio");

var sigpipe_installed = false;
var sigpipe_mu: std.atomic.Mutex = .unlocked;

fn installSigpipeHandler() void {
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

fn timeoutMillis(timeout_ms: u32) i32 {
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

fn setNonBlocking(stream: std.Io.net.Stream) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        return setNonBlockingNative(stream);
    }
}

fn setNonBlockingNative(stream: std.Io.net.Stream) !void {
    const fd = stream.socket.handle;
    const rc_get = std.c.fcntl(fd, std.os.linux.F.GETFL, @as(c_int, 0));
    if (rc_get < 0) return error.Unexpected;
    const flags: c_int = @intCast(rc_get);
    const nb_bit: c_int = @as(c_int, 1) << @intCast(@bitOffsetOf(std.posix.O, "NONBLOCK"));
    const rc_set = std.c.fcntl(fd, std.os.linux.F.SETFL, flags | nb_bit);
    if (rc_set < 0) return error.Unexpected;
}

/// Restore fully blocking I/O and clear any receive timeout.
fn acceptFlags() c_uint {
    if (comptime builtin.cpu.arch.isWasm()) {
        return 0;
    } else {
        return @intCast(std.posix.SOCK.CLOEXEC);
    }
}

fn setBlocking(stream: std.Io.net.Stream) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        return setBlockingNative(stream);
    }
}

fn setBlockingNative(stream: std.Io.net.Stream) !void {
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

fn ipprotoTcp() c_int {
    if (comptime builtin.cpu.arch.isWasm()) {
        return 6;
    } else {
        return std.posix.IPPROTO.TCP;
    }
}

fn setReceiveTimeout(stream: std.Io.net.Stream, timeout_ms: u32) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        return setReceiveTimeoutNative(stream, timeout_ms);
    }
}

fn setReceiveTimeoutNative(stream: std.Io.net.Stream, timeout_ms: u32) !void {
    if (timeout_ms == 0) return setNonBlocking(stream);
    const timeout = std.posix.timeval{
        .sec = @intCast(timeout_ms / 1000),
        .usec = @intCast((timeout_ms % 1000) * 1000),
    };
    try std.posix.setsockopt(stream.socket.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));
}

fn setNonBlockingFd(fd: std.posix.fd_t) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        return setNonBlockingFdNative(fd);
    }
}

fn setNonBlockingFdNative(fd: std.posix.fd_t) !void {
    const rc_get = std.c.fcntl(fd, std.os.linux.F.GETFL, @as(c_int, 0));
    if (rc_get < 0) return error.Unexpected;
    const flags: c_int = @intCast(rc_get);
    const nb_bit: c_int = @as(c_int, 1) << @intCast(@bitOffsetOf(std.posix.O, "NONBLOCK"));
    const rc_set = std.c.fcntl(fd, std.os.linux.F.SETFL, flags | nb_bit);
    if (rc_set < 0) return error.Unexpected;
}

fn validHeaderName(name: []const u8) bool {
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

fn validHeaderValue(value: []const u8) bool {
    for (value) |ch| {
        if ((ch < 0x20 and ch != '\t') or ch == 0x7f) return false;
    }
    return true;
}

const ResponseHeaderBag = struct {
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

const WebSocketOpcode = enum(u8) {
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
const ConnState = struct {
    stream: std.Io.net.Stream,
    read_buffer: []u8,
    /// Bytes in read_buffer[request_start..read_len] are buffered pipelined data.
    read_len: usize = 0,
    request_start: usize = 0,
};

/// Cap on idle keep-alive connections held in the pool (each pins an 8KB
/// read buffer plus a socket). Overflow connections are closed on recycle.
/// Kept small on purpose: every accept scans the pool, so the cap bounds
/// the per-accept cost under connection-churn workloads.
const max_recycled_conns: usize = 64;
const conn_read_buffer_len: usize = 8192;
/// Buffered stream output is pushed to the socket once it reaches this size,
/// or on flush()/endChunked().
const stream_flush_threshold: usize = 8192;
/// Bound on one non-blocking keep-alive probe parse (covers normal TCP
/// segment gaps without stalling the accept loop).
const probe_parse_timeout_ms: u32 = 50;

/// Result of the internal poll over listener + idle pool + wake pipe.
const PollOutcome = struct {
    status: NetworkStatus,
    /// A recycled connection may have a request (or died): sweep the pool.
    recycled_ready: bool,
    /// The listener has a pending connection.
    listener_ready: bool,
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
    served: std.atomic.Value(u64),
    stopping: std.atomic.Value(bool),
    done: std.atomic.Value(usize),
};


fn spawnPoolWorker(pool: *ThreadPool) !std.Thread {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.UnsupportedPlatform;
    } else {
        return std.Thread.spawn(.{}, workerMain, .{pool});
    }
}

fn workerMain(pool: *ThreadPool) void {
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
const worker_head_parse_timeout_ms: u32 = 5000;

pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    server: ?std.Io.net.Server = null,
    /// v1 request body limit. Default 2MB (historic); configurable via
    /// sa_http_server_set_max_body_bytes. v2 always uses 16MB.
    max_body_len: usize = 2 * 1024 * 1024,
    /// Idle keep-alive connections waiting for their next request.
    recycled: std.array_list.Managed(*ConnState),
    recycled_mutex: std.atomic.Mutex = .unlocked,
    /// Self-pipe: pushRecycled writes a byte so an accept loop blocked in
    /// poll() wakes up immediately. Recycling is asynchronous (handler
    /// threads recycle after the accept loop snapshotted the pool), so
    /// without this the next request on a reused connection could sleep
    /// until the poll timeout.
    wake_pipe: [2]std.posix.fd_t,
    /// Active plugin-internal thread pool (serve_threaded), if any.
    pool: ?*ThreadPool = null,

    pub fn init(allocator: std.mem.Allocator) !*HttpServer {
        if (comptime builtin.cpu.arch.isWasm()) {
            return error.UnsupportedPlatform;
        } else {
            return initNative(allocator);
        }
    }

    pub fn initNative(allocator: std.mem.Allocator) !*HttpServer {
        const self = try allocator.create(HttpServer);
        errdefer allocator.destroy(self);
        var pipe: [2]std.posix.fd_t = undefined;
        if (std.c.pipe(&pipe) != 0) return error.Unexpected;
        errdefer {
            _ = std.c.close(pipe[0]);
            _ = std.c.close(pipe[1]);
        }
        for (pipe) |fd| {
            const rc_get = std.c.fcntl(fd, std.os.linux.F.GETFL, @as(c_int, 0));
            if (rc_get < 0) return error.Unexpected;
            const flags: c_int = @intCast(rc_get);
            const nb_bit: c_int = @as(c_int, 1) << @intCast(@bitOffsetOf(std.posix.O, "NONBLOCK"));
            if (std.c.fcntl(fd, std.os.linux.F.SETFL, flags | nb_bit) < 0) return error.Unexpected;
        }
        self.* = .{
            .allocator = allocator,
            .server = null,
            .recycled = std.array_list.Managed(*ConnState).init(allocator),
            .wake_pipe = pipe,
        };
        return self;
    }

    pub fn start(self: *HttpServer, host: []const u8, port: u16) !void {
        try self.startWithOptions(host, port, .{ .reuse_address = true });
    }

    pub fn startWithOptions(self: *HttpServer, host: []const u8, port: u16, options: std.Io.net.IpAddress.ListenOptions) !void {
        if (self.server != null) return;
        const address = try std.Io.net.IpAddress.parse(host, port);
        self.server = try address.listen(sio.io(), options);
        // The accept loop must never block inside accept(): a poll-reported
        // readable listener can still yield an empty accept queue if the
        // pending connection reset between poll and accept. Non-blocking
        // accept returns WouldBlock instead of wedging the whole server.
        setNonBlockingFd(self.server.?.socket.handle) catch |err| {
            self.server.?.deinit(sio.io());
            self.server = null;
            return err;
        };
    }

    pub fn setMaxBodyLen(self: *HttpServer, max_bytes: usize) !void {
        if (max_bytes == 0 or max_bytes > (1 << 30)) return error.InvalidArgument;
        self.max_body_len = max_bytes;
    }

    pub fn accept(self: *HttpServer) !*HttpRequest {
        return self.acceptConfigured(self.max_body_len, null);
    }

    /// Worker accept for serve_threaded: poll-driven like acceptConfigured
    /// but with a 1s poll slice so stopServing() is noticed promptly, and a
    /// bounded head parse (slowloris guard). Returns error.WouldBlock on
    /// timeout or when stopping so the worker loop can re-check.
    fn acceptWorker(self: *HttpServer, stopping: *const std.atomic.Value(bool)) !*HttpRequest {
        while (true) {
            if (stopping.load(.acquire)) return error.WouldBlock;
            const pr = self.pollAcceptEx(1000);
            switch (pr.status) {
                .ok => {
                    if (pr.recycled_ready) {
                        if (self.drainRecycled(self.max_body_len, null)) |req| return req;
                    }
                    if (pr.listener_ready) {
                        if (try self.acceptFresh(self.max_body_len, worker_head_parse_timeout_ms, null, true)) |req| return req;
                    }
                },
                .timeout => return error.WouldBlock,
                else => return error.ConnectionAborted,
            }
        }
    }

    pub fn serveThreaded(
        self: *HttpServer,
        num_threads: u32,
        handler: HttpServeHandlerFn,
        handler_ctx: ?*anyopaque,
        max_requests: u64,
    ) !void {
        if (self.server == null) return error.NotStarted;
        if (self.pool != null) return error.AlreadyServing;
        var n: usize = num_threads;
        if (n == 0) n = std.Thread.getCpuCount() catch 4;
        n = @min(@max(n, 1), 256);

        const pool = try self.allocator.create(ThreadPool);
        errdefer self.allocator.destroy(pool);
        const threads = try self.allocator.alloc(std.Thread, n);
        errdefer self.allocator.free(threads);
        pool.* = .{
            .server = self,
            .threads = threads,
            .handler = handler,
            .handler_ctx = handler_ctx,
            .max_requests = max_requests,
            .served = std.atomic.Value(u64).init(0),
            .stopping = std.atomic.Value(bool).init(false),
            .done = std.atomic.Value(usize).init(0),
        };
        self.pool = pool;

        var started: usize = 0;
        while (started < n) : (started += 1) {
            threads[started] = spawnPoolWorker(pool) catch |err| {
                pool.stopping.store(true, .release);
                for (threads[0..started]) |t| t.join();
                self.pool = null;
                self.allocator.free(threads);
                self.allocator.destroy(pool);
                return err;
            };
        }
        // The SA host executable exports its own `pthread_join(int32_t, u8*)`,
        // which interposes libc's pthread_join for dynamically linked plugins.
        // Calling std.Thread.join here therefore does not wait for the worker
        // and would free the pool underneath a live thread. Detach instead and
        // wait on an explicit completion counter that uses only atomics.
        for (threads) |t| t.detach();
        while (!pool.stopping.load(.acquire)) std.Io.sleep(sio.io(), .fromMilliseconds(1), .awake) catch {};
        while (pool.done.load(.acquire) < n) std.Io.sleep(sio.io(), .fromMilliseconds(1), .awake) catch {};
        self.pool = null;
        self.allocator.free(threads);
        self.allocator.destroy(pool);
    }

    /// Ask a running serveThreaded loop to stop. Wakes workers blocked in
    /// poll() via listener shutdown; in-flight handlers run to completion.
    /// NOTE: the shutdown also closes the listening socket, so the server
    /// handle cannot accept new connections afterwards — free it with
    /// sa_http_server_free once the loop has returned.
    pub fn stopServing(self: *HttpServer) void {
        if (self.pool) |pool| pool.stopping.store(true, .release);
        if (self.server) |*s| _ = std.c.shutdown(s.socket.handle, 2);
    }

    /// Public pollable status (v2 ABI). See pollAcceptEx for the internals.
    pub fn pollAccept(self: *HttpServer, timeout_ms: u32) NetworkStatus {
        return self.pollAcceptEx(timeout_ms).status;
    }

    /// Like poll(2) over the listener plus all idle keep-alive connections
    /// plus the recycle wake pipe: tells the accept loop which class of fd
    /// is actionable so it can skip sweeping the idle pool when only the
    /// listener has traffic.

fn posixRead(fd: std.posix.fd_t, buf: []u8) !usize {
    if (comptime builtin.cpu.arch.isWasm()) {
        var iov = [_]std.os.wasi.iovec_t{.{ .base = buf.ptr, .len = buf.len }};
        var n: usize = 0;
        const err = std.os.wasi.fd_read(fd, &iov, iov.len, &n);
        if (err != .SUCCESS) return error.Io;
        return n;
    } else {
        return std.posix.read(fd, buf);
    }
}

    fn pollAcceptEx(self: *HttpServer, timeout_ms: u32) PollOutcome {
        const bad = PollOutcome{ .status = .invalid, .recycled_ready = false, .listener_ready = false };
        var fds: [max_recycled_conns + 2]std.posix.pollfd = undefined;        var nfds: usize = 0;
        var nrec: usize = 0;
        {
            while (!self.recycled_mutex.tryLock()) std.Thread.yield() catch {};
            defer self.recycled_mutex.unlock();
            for (self.recycled.items) |conn| {
                // Pipelined bytes already buffered: no need to poll.
                if (conn.read_len > conn.request_start) {
                    return .{ .status = .ok, .recycled_ready = true, .listener_ready = false };
                }
                fds[nfds] = .{
                    .fd = conn.stream.socket.handle,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                };
                nfds += 1;
            }
            nrec = nfds;
            fds[nfds] = .{ .fd = self.wake_pipe[0], .events = std.posix.POLL.IN, .revents = 0 };
            nfds += 1;
            if (self.server) |*s| {
                fds[nfds] = .{
                    .fd = s.socket.handle,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                };
                nfds += 1;
            } else {
                return bad;
            }
        }
        const ready = std.posix.poll(fds[0..nfds], timeoutMillis(timeout_ms)) catch
            return .{ .status = .io_error, .recycled_ready = false, .listener_ready = false };
        if (ready == 0) return .{
            .status = if (timeout_ms == 0) .would_block else .timeout,
            .recycled_ready = false,
            .listener_ready = false,
        };
        // Drain the wake pipe (a recycle happened); it counts as pool activity.
        // A dead pooled fd (POLLERR/POLLNVAL, e.g. a keep-alive connection
        // whose TCP state fully died while pooled) must NEVER poison the
        // poll: mark the pool for sweeping and let drainRecycled reap the
        // dead connection. Returning .io_error here used to wedge the accept
        // loop permanently (host spins on the failed accept). Only the
        // listener's health is fatal.
        var recycled_ready = false;
        if (fds[nrec].revents & std.posix.POLL.IN != 0) {
            recycled_ready = true;
            var tmp: [64]u8 = undefined;
            while (posixRead(self.wake_pipe[0], &tmp)) |n| {
                if (n == 0) break;
            } else |_| {}
        }
        for (fds[0..nrec]) |pfd| {
            if (pfd.revents != 0) recycled_ready = true;
        }
        const levents = fds[nfds - 1].revents;
        if (levents & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0)
            return .{ .status = .io_error, .recycled_ready = false, .listener_ready = false };
        return .{
            .status = .ok,
            .recycled_ready = recycled_ready,
            .listener_ready = levents & std.posix.POLL.IN != 0,
        };
    }

    pub fn acceptWithBodyLimit(self: *HttpServer, max_body_len: usize) !*HttpRequest {
        return self.acceptConfigured(max_body_len, null);
    }

    pub fn acceptWithBodyLimitAndTimeout(self: *HttpServer, max_body_len: usize, timeout_ms: u32) !*HttpRequest {
        return self.acceptConfigured(max_body_len, timeout_ms);
    }

    fn acceptConfigured(self: *HttpServer, max_body_len: usize, receive_timeout_ms: ?u32) !*HttpRequest {
        if (self.server == null) return error.NotFound;
        if (receive_timeout_ms) |timeout_ms| {
            return self.acceptBounded(max_body_len, timeout_ms);
        }
        // v1: block until the next request arrives on any connection.
        // Poll-driven so one idle keep-alive connection can never wedge the
        // accept loop while other connections have traffic. The idle pool is
        // only swept when poll saw pool activity (wake pipe or recycled fd),
        // keeping the per-accept cost O(1) in the common listener-traffic case.
        while (true) {
            const pr = self.pollAcceptEx(60_000);
            switch (pr.status) {
                .ok => {
                    if (pr.recycled_ready) {
                        if (self.drainRecycled(max_body_len, null)) |req| return req;
                    }
                    if (pr.listener_ready) {
                        if (try self.acceptFresh(max_body_len, null, null, true)) |req| return req;
                    }
                    // Spurious wakeup (e.g. a recycled fd died and was
                    // reaped): re-poll.
                },
                .timeout => continue,
                else => return error.ConnectionAborted,
            }
        }
    }

    fn acceptBounded(self: *HttpServer, max_body_len: usize, timeout_ms: u32) !*HttpRequest {
        if (self.server == null) return error.NotFound;
        const start_ms = nowMillis();
        while (true) {
            const elapsed_ms: u64 = blk: {
                const e = nowMillis() - start_ms;
                break :blk if (e <= 0) 0 else @intCast(e);
            };
            if (elapsed_ms >= timeout_ms) return if (timeout_ms == 0) error.WouldBlock else error.HttpHeadersUnreadable;
            const remaining: u32 = @intCast(@min(timeout_ms - elapsed_ms, std.math.maxInt(u32)));
            const pr = self.pollAcceptEx(remaining);
            switch (pr.status) {
                .ok => {
                    if (pr.recycled_ready) {
                        if (self.drainRecycled(max_body_len, timeout_ms)) |req| return req;
                    }
                    if (pr.listener_ready) {
                        if (try self.acceptFresh(max_body_len, remaining, timeout_ms, true)) |req| return req;
                    }
                },
                .timeout => return error.HttpHeadersUnreadable,
                .would_block => return error.WouldBlock,
                else => return error.ConnectionAborted,
            }
        }
    }

    /// Non-blocking sweep over idle keep-alive connections. Returns the first
    /// connection that yields a complete request; unready connections are
    /// pushed back, dead ones closed. Never blocks. Takes the pool lock only
    /// twice (swap-out, push-back) and uses a single poll(2) over the whole
    /// batch, so the cost stays flat no matter how many idle connections sit
    /// in the pool.
    fn drainRecycled(self: *HttpServer, max_body_len: usize, post_parse_timeout: ?u32) ?*HttpRequest {
        var conns = std.array_list.Managed(*ConnState).init(self.allocator);
        {
            while (!self.recycled_mutex.tryLock()) std.Thread.yield() catch {};
            defer self.recycled_mutex.unlock();
            std.mem.swap(std.array_list.Managed(*ConnState), &self.recycled, &conns);
        }
        var keep = std.array_list.Managed(*ConnState).init(self.allocator);
        defer keep.deinit();
        var result: ?*HttpRequest = null;

        // One poll over the whole batch instead of one syscall per conn.
        var pfds: [max_recycled_conns]std.posix.pollfd = undefined;
        for (conns.items, 0..) |conn, i| {
            pfds[i] = .{
                .fd = conn.stream.socket.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            };
        }
        const npoll = conns.items.len;
        if (npoll > 0) {
            _ = std.posix.poll(pfds[0..npoll], 0) catch {};
        }

        for (conns.items, 0..) |conn, i| {
            if (result != null) {
                keep.append(conn) catch self.destroyConn(conn, true);
                continue;
            }
            const stream = conn.stream;
            const has_buffered = conn.read_len > conn.request_start;
            const rev: i16 = if (npoll > 0) pfds[i].revents else 0;
            const dead = rev & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0;
            // HUP without IN (or with nothing readable) also means the peer
            // is gone; IN means either data or EOF, decided by the parse.
            const readable = !dead and (has_buffered or (rev & std.posix.POLL.IN) != 0);
            if (!readable) {
                if (dead or (rev & std.posix.POLL.HUP) != 0) {
                    self.destroyConn(conn, true);
                } else {
                    keep.append(conn) catch self.destroyConn(conn, true);
                }
                continue;
            }
            if (!has_buffered) {
                // Readable: give the head parse a short bounded wait so a
                // head+body split across TCP segments still completes.
                setBlocking(stream) catch {
                    self.destroyConn(conn, true);
                    continue;
                };
                setReceiveTimeout(stream, probe_parse_timeout_ms) catch {
                    self.destroyConn(conn, true);
                    continue;
                };
            }
            const req = self.parseHead(conn, max_body_len) catch {
                // A reused connection that stalls mid-head (or speaks garbage)
                // is dropped outright: retrying a partial head is unsafe
                // because std.http keeps a stale next_request_start across
                // attempts, which would discard already-read bytes and
                // mis-parse the remainder. The client simply reconnects.
                self.destroyConn(conn, true);
                continue;
            };
            // Normalize the socket mode for the handler.
            if (post_parse_timeout) |ms| {
                setReceiveTimeout(stream, ms) catch {
                    req.deinit();
                    continue;
                };
            } else {
                setBlocking(stream) catch {
                    req.deinit();
                    continue;
                };
            }
            result = req;
        }
        conns.deinit();

        // Push the survivors back under a single lock hold. No wake-pipe
        // byte: these were already in the pool before this sweep.
        while (!self.recycled_mutex.tryLock()) std.Thread.yield() catch {};
        defer self.recycled_mutex.unlock();
        for (keep.items) |conn| {
            if (self.recycled.items.len >= max_recycled_conns) {
                self.destroyConn(conn, true);
            } else {
                self.recycled.append(conn) catch self.destroyConn(conn, true);
            }
        }
        return result;
    }

    /// Accept one NEW tcp connection (never a recycled one). With
    /// require_readable, returns null instead of blocking when the listener
    /// has nothing pending. The listener is non-blocking, so accept() can
    /// only return WouldBlock (no pending connection) rather than wedge.
    /// The head parse is always time-bounded: a client that connects but
    /// never sends a head must not wedge the single accept loop.
    fn acceptFresh(
        self: *HttpServer,
        max_body_len: usize,
        parse_timeout: ?u32,
        post_parse: ?u32,
        require_readable: bool,
    ) !?*HttpRequest {
        const listener = &(self.server orelse return error.NotFound);
        if (require_readable and pollStream(listener.socket.handle, std.posix.POLL.IN, 0, null) != .ok) return null;
        // NOTE(Zig 0.17): the Threaded backend's netAccept treats EAGAIN on
        // a non-blocking listener as a programmer bug (errnoBug panic), not
        // WouldBlock. The listener is deliberately non-blocking here, and a
        // poll-reported readable listener can still yield an empty accept
        // queue (TOCTOU), so accept via raw accept4 and map EAGAIN to null.
        var addr: std.posix.sockaddr = undefined;
        var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);
        const rc = std.c.accept4(listener.socket.handle, &addr, &addr_len, acceptFlags());
        if (rc < 0) {
            const e = std.c.errno(rc);
            if (e == .AGAIN) return null;
            if (e == .CONNABORTED) return error.ConnectionAborted;
            return error.ConnectionAborted;
        }
        const one: c_int = 1;
        std.posix.setsockopt(rc, ipprotoTcp(), 1, std.mem.asBytes(&one)) catch {};
        const accepted: std.Io.net.Stream = .{
            .socket = .{ .handle = @intCast(rc), .address = listener.socket.address },
        };
        // fd ownership transfers into conn below; the block-scoped errdefer
        // only closes if newConn itself fails (double-close would SIGABRT).
        const conn: *ConnState = blk: {
            errdefer accepted.close(sio.io());
            break :blk try self.newConn(accepted);
        };
        errdefer self.destroyConn(conn, true);
        const stream = conn.stream;
        // Bound the head parse: v1 (parse_timeout == null) gets a generous
        // 30s rather than blocking forever on a silent client.
        const head_timeout_ms = parse_timeout orelse 30_000;
        try setReceiveTimeout(stream, head_timeout_ms);
        const req = try self.parseHead(conn, max_body_len);
        errdefer req.deinit();
        if (post_parse) |ms| {
            try setReceiveTimeout(stream, ms);
        } else {
            try setBlocking(stream);
        }
        return req;
    }

    fn connCompact(conn: *ConnState) void {
        if (conn.request_start == 0) return;
        if (conn.request_start < conn.read_len) {
            const remain = conn.read_len - conn.request_start;
            std.mem.copyForwards(u8, conn.read_buffer[0..remain], conn.read_buffer[conn.request_start..conn.read_len]);
            conn.read_len = remain;
        } else {
            conn.read_len = 0;
        }
        conn.request_start = 0;
    }

    fn connFill(conn: *ConnState) !void {
        connCompact(conn);
        if (conn.read_len >= conn.read_buffer.len) return error.HttpHeadersOversize;
        const fd = conn.stream.socket.handle;
        const rc = std.c.read(fd, conn.read_buffer.ptr + conn.read_len, conn.read_buffer.len - conn.read_len);
        if (rc == 0) return error.EndOfStream;
        if (rc < 0) {
            const e = std.c.errno(rc);
            if (e == .AGAIN) return error.HttpHeadersUnreadable;
            return error.ConnectionResetByPeer;
        }
        conn.read_len += @intCast(rc);
    }

    fn parseHead(self: *HttpServer, conn: *ConnState, max_body_len: usize) !*HttpRequest {

        while (true) {
            const avail = conn.read_buffer[conn.request_start..conn.read_len];
            if (std.mem.indexOf(u8, avail, "\r\n\r\n")) |_| break;
            if (avail.len >= 64 * 1024) return error.HttpHeadersOversize;
            try connFill(conn);
        }
        const avail = conn.read_buffer[conn.request_start..conn.read_len];
        const head_end = std.mem.indexOf(u8, avail, "\r\n\r\n") orelse return error.HttpHeadersUnreadable;
        const head_bytes = avail[0 .. head_end + 4];
        const parsed = try std.http.Server.Request.Head.parse(head_bytes);
        const content_length: usize = @intCast(parsed.content_length orelse 0);
        // We only consume Content-Length bodies. Chunked request bodies are
        // left unread, which forces the connection closed after the response.
        const supports_reuse = parsed.transfer_encoding == .none;
        const keep_alive = parsed.keep_alive and supports_reuse;
        const body_start = conn.request_start + head_end + 4;

        const request = try self.allocator.create(HttpRequest);
        errdefer self.allocator.destroy(request);

        const method = try methodStringAlloc(self.allocator, parsed.method);
        errdefer self.allocator.free(method);

        const target = try self.allocator.dupe(u8, parsed.target);
        errdefer self.allocator.free(target);

        var headers = std.array_list.Managed(Header).init(self.allocator);
        errdefer headers.deinit();
        var it = std.http.HeaderIterator.init(head_bytes);
        while (it.next()) |header| {
            try headers.append(.{
                .name = try self.allocator.dupe(u8, header.name),
                .value = try self.allocator.dupe(u8, header.value),
            });
        }

        var body = std.array_list.Managed(u8).init(self.allocator);
        errdefer body.deinit();
        if (content_length > 0) {
            if (content_length > max_body_len) return error.BodyTooLarge;
            const reader_need = body_start + content_length;
            if (reader_need > conn.read_buffer.len + max_body_len) return error.BodyTooLarge;
            while (conn.read_len < reader_need) {
                if (conn.read_len >= conn.read_buffer.len) {
                    const extra = try self.allocator.alloc(u8, reader_need - conn.read_len);
                    defer self.allocator.free(extra);
                    var off: usize = 0;
                    while (off < extra.len) {
                        const rc = std.c.read(conn.stream.socket.handle, extra.ptr + off, extra.len - off);
                        if (rc == 0) return error.EndOfStream;
                        if (rc < 0) {
                            const e = std.c.errno(rc);
                            if (e == .AGAIN) return error.HttpHeadersUnreadable;
                            return error.ConnectionResetByPeer;
                        }
                        off += @intCast(rc);
                    }
                    try body.appendSlice(conn.read_buffer[body_start..conn.read_len]);
                    try body.appendSlice(extra);
                    conn.read_len = 0;
                    conn.request_start = 0;
                    // request struct filled below; skip default tail copy
                    request.* = .{
                        .allocator = self.allocator,
                        .conn = conn,
                        .server = self,
                        .keep_alive = keep_alive,
                        .response_done = false,
                        .method = method,
                        .target = target,
                        .headers = try headers.toOwnedSlice(),
                        .body = try body.toOwnedSlice(),
                    };
                    return request;
                }
                const rc = std.c.read(conn.stream.socket.handle, conn.read_buffer.ptr + conn.read_len, @min(conn.read_buffer.len - conn.read_len, reader_need - conn.read_len));
                if (rc == 0) return error.EndOfStream;
                if (rc < 0) {
                    const e = std.c.errno(rc);
                    if (e == .AGAIN) return error.HttpHeadersUnreadable;
                    return error.ConnectionResetByPeer;
                }
                conn.read_len += @intCast(rc);
            }
            try body.appendSlice(conn.read_buffer[body_start..reader_need]);
            conn.request_start = reader_need;
        } else if (supports_reuse) {
            // No body: advance past the parsed head so the next accept on
            // this recycled connection parses the NEXT request, not this one.
            conn.request_start = body_start;
        }

        request.* = .{
            .allocator = self.allocator,
            .conn = conn,
            .server = self,
            .keep_alive = keep_alive,
            .response_done = false,
            .method = method,
            .target = target,
            .headers = try headers.toOwnedSlice(),
            .body = try body.toOwnedSlice(),
        };
        return request;
    }

    fn newConn(self: *HttpServer, accepted: std.Io.net.Stream) !*ConnState {
        const read_buffer = try self.allocator.alloc(u8, conn_read_buffer_len);
        errdefer self.allocator.free(read_buffer);
        const conn = try self.allocator.create(ConnState);
        errdefer self.allocator.destroy(conn);
        conn.* = .{
            .stream = accepted,
            .read_buffer = read_buffer,
            .read_len = 0,
            .request_start = 0,
        };
        return conn;
    }

    fn destroyConn(self: *HttpServer, conn: *ConnState, close_stream: bool) void {
        if (close_stream) conn.stream.close(sio.io());
        self.allocator.free(conn.read_buffer);
        self.allocator.destroy(conn);
    }

    fn popRecycled(self: *HttpServer) ?*ConnState {
        while (!self.recycled_mutex.tryLock()) std.Thread.yield() catch {};
        defer self.recycled_mutex.unlock();
        if (self.recycled.items.len == 0) return null;
        return self.recycled.pop();
    }

    /// True when the peer already went away (EOF/RST pending). Called at
    /// recycle time so a connection the client already closed never wastes
    /// a pool slot, a wake-pipe byte, and a future O(pool) sweep. A readable
    /// socket is peeked: real bytes (pipelined next request) mean "keep",
    /// EOF means "drop".
    pub fn isPeerClosed(stream: std.Io.net.Stream) bool {
        if (comptime builtin.cpu.arch.isWasm()) {
            return true;
        } else {
            return isPeerClosedNative(stream);
        }
    }

    pub fn isPeerClosedNative(stream: std.Io.net.Stream) bool {
        var pfd = [1]std.posix.pollfd{.{
            .fd = stream.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&pfd, 0) catch return true;
        if (ready == 0) return false; // idle: genuine keep-alive candidate
        const rev = pfd[0].revents;
        if (rev & (std.posix.POLL.ERR | std.posix.POLL.NVAL | std.posix.POLL.HUP) != 0) return true;
        if (rev & std.posix.POLL.IN == 0) return false;
        var b: [1]u8 = undefined;
        const flags: c_int = @intCast(std.os.linux.MSG.PEEK | std.os.linux.MSG.DONTWAIT);
        const n = std.c.recv(stream.socket.handle, &b, 1, flags);
        if (n < 0) return true;
        return n == 0;
    }

    /// Return a connection to the idle pool (or close it when the pool is
    /// full). Wakes an accept loop blocked in poll() via the self-pipe, so
    /// the next request on this connection is picked up immediately even
    /// though recycling happens on a handler thread.
    pub fn pushRecycled(self: *HttpServer, conn: *ConnState) void {
        {
            while (!self.recycled_mutex.tryLock()) std.Thread.yield() catch {};
            defer self.recycled_mutex.unlock();
            if (self.recycled.items.len >= max_recycled_conns) {
                self.destroyConn(conn, true);
                return;
            }
            self.recycled.append(conn) catch {
                self.destroyConn(conn, true);
                return;
            };
        }
        var b: [1]u8 = .{0};
        _ = std.c.write(self.wake_pipe[1], &b, 1);
    }

    pub fn deinit(self: *HttpServer) void {
        if (self.server) |*server| server.deinit(sio.io());
        while (self.popRecycled()) |conn| self.destroyConn(conn, true);
        self.recycled.deinit();
        _ = std.c.close(self.wake_pipe[0]);
        _ = std.c.close(self.wake_pipe[1]);
        self.allocator.destroy(self);
    }
};

pub const HttpRequest = struct {
    allocator: std.mem.Allocator,
    conn: *ConnState,
    server: *HttpServer,
    /// Negotiated at accept: HTTP/1.1 default (unless `Connection: close`),
    /// HTTP/1.0 only with `Connection: keep-alive`. Chunked request bodies
    /// force false (we don't consume them).
    keep_alive: bool,
    /// Set once a fully-framed response hit the wire (content-length body or
    /// terminated chunked stream). req_free recycles the connection only when
    /// this is true; otherwise the connection is closed.
    response_done: bool = false,
    method: []u8,
    target: []u8,
    headers: []Header,
    body: []u8,

    pub fn stream(self: *HttpRequest) std.Io.net.Stream {
        return self.conn.stream;
    }

    pub fn freeResources(self: *HttpRequest) void {
        for (self.headers) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.allocator.free(self.headers);
        self.allocator.free(self.method);
        self.allocator.free(self.target);
        if (self.body.len != 0) self.allocator.free(self.body);
    }

    /// Release parser state without closing the stream; ownership of the
    /// returned stream transfers to the caller (WebSocket upgrade).
    pub fn releaseStream(self: *HttpRequest) std.Io.net.Stream {
        const s = self.conn.stream;
        self.server.destroyConn(self.conn, false);
        return s;
    }

    pub fn deinit(self: *HttpRequest) void {
        self.server.destroyConn(self.conn, true);
        self.freeResources();
        self.allocator.destroy(self);
    }
};

pub const HttpResponse = struct {
    allocator: std.mem.Allocator,
    request: *HttpRequest,
    status: u16,
    headers: ResponseHeaderBag,
    sent: bool = false,

    pub fn init(request: *HttpRequest, status: u16) !*HttpResponse {
        const self = try request.allocator.create(HttpResponse);
        self.* = .{
            .allocator = request.allocator,
            .request = request,
            .status = status,
            .headers = ResponseHeaderBag.init(request.allocator, "text/plain"),
        };
        return self;
    }

    pub fn setContentType(self: *HttpResponse, content_type: []const u8) !void {
        if (self.sent) return error.ResponseAlreadySent;
        try self.headers.setContentType(content_type);
    }

    pub fn setHeader(self: *HttpResponse, name: []const u8, value: []const u8) !void {
        if (self.sent) return error.ResponseAlreadySent;
        try self.headers.add(name, value);
    }

    pub fn send(self: *HttpResponse, body: []const u8) !void {
        if (self.sent) return error.ResponseAlreadySent;
        var head: std.Io.Writer.Allocating = .init(self.allocator);
        defer head.deinit();
        const writer = &head.writer;
        try writer.print("HTTP/1.1 {d} {s}\r\ncontent-length: {d}\r\n", .{ self.status, statusText(self.status), body.len });
        try self.headers.write(writer);
        // Framing is explicit (content-length), so the connection may be
        // reused when the client negotiated keep-alive.
        if (self.request.keep_alive) {
            try writer.writeAll("connection: keep-alive\r\n\r\n");
        } else {
            try writer.writeAll("connection: close\r\n\r\n");
        }
        try writer.writeAll(body);
        try streamWriteAll(self.request.stream(), head.written());
        self.sent = true;
        self.request.response_done = true;
    }

    /// Header-only response (HEAD semantics): the caller declares
    /// the content-length the equivalent GET would have produced and
    /// no body bytes are written. `send` cannot express this: it
    /// always frames content-length from the body it is handed, and
    /// the header bag rejects a caller-set content-length. Framing
    /// stays explicit, so keep-alive reuse works exactly as send().
    pub fn sendHeadOnly(self: *HttpResponse, content_length: u64) !void {
        if (self.sent) return error.ResponseAlreadySent;
        var head: std.Io.Writer.Allocating = .init(self.allocator);
        defer head.deinit();
        const writer = &head.writer;
        try writer.print("HTTP/1.1 {d} {s}\r\ncontent-length: {d}\r\n", .{ self.status, statusText(self.status), content_length });
        try self.headers.write(writer);
        if (self.request.keep_alive) {
            try writer.writeAll("connection: keep-alive\r\n\r\n");
        } else {
            try writer.writeAll("connection: close\r\n\r\n");
        }
        try streamWriteAll(self.request.stream(), head.written());
        self.sent = true;
        self.request.response_done = true;
    }

    /// File-body response (static serving): the head is framed
    /// with content-length = count, then the file bytes move
    /// kernel-side via sendfile(2) -- no userspace copy, no
    /// whole-file buffer. Returns the number of file bytes
    /// actually sent: it equals count on success; a short count
    /// means the file ended early (it shrank after the caller
    /// measured it), which the caller must treat as a failed
    /// response, never as a completed one. response_done is set
    /// only when the full count is on the wire, so a short or
    /// failed send closes the connection instead of recycling a
    /// stream whose framing is broken. Linux only: other
    /// platforms return error.Unsupported BEFORE any byte is
    /// written, so the caller can still send an explicit error
    /// response. There is deliberately no buffered fallback here.
    pub fn sendFile(self: *HttpResponse, in_fd: std.posix.fd_t, offset: u64, count: u64) !u64 {
        if (self.sent) return error.ResponseAlreadySent;
        if (comptime builtin.cpu.arch.isWasm() or builtin.os.tag != .linux) return error.Unsupported;
        var head: std.Io.Writer.Allocating = .init(self.allocator);
        defer head.deinit();
        const writer = &head.writer;
        try writer.print("HTTP/1.1 {d} {s}\r\ncontent-length: {d}\r\n", .{ self.status, statusText(self.status), count });
        try self.headers.write(writer);
        if (self.request.keep_alive) {
            try writer.writeAll("connection: keep-alive\r\n\r\n");
        } else {
            try writer.writeAll("connection: close\r\n\r\n");
        }
        try streamWriteAll(self.request.stream(), head.written());
        self.sent = true;
        const out_fd = self.request.stream().socket.handle;
        var next_offset: u64 = offset;
        var sent_total: u64 = 0;
        while (sent_total < count) {
            const remaining = count - sent_total;
            const chunk: usize = @intCast(@min(remaining, @as(u64, 0x7ffff000)));
            var off: i64 = @intCast(next_offset);
            const rc = std.os.linux.sendfile(out_fd, in_fd, &off, chunk);
            const e = std.os.linux.errno(rc);
            if (e != .SUCCESS) {
                return switch (e) {
                    .AGAIN => error.WouldBlock,
                    .PIPE => error.BrokenPipe,
                    .INVAL, .BADF, .NOTSOCK => error.InvalidArgument,
                    else => error.SendFileFailed,
                };
            }
            if (rc == 0) break; // EOF: short send, reported via the return value.
            sent_total += rc;
            next_offset = @intCast(off);
        }
        if (sent_total == count) {
            self.request.response_done = true;
        }
        return sent_total;
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
        self.allocator.destroy(self);
    }
};

pub const HttpStreamResponse = struct {
    allocator: std.mem.Allocator,
    request: *HttpRequest,
    status: u16,
    headers: ResponseHeaderBag,
    sent_head: bool = false,
    ended: bool = false,
    /// Explicit write buffer. writeChunk frames chunk bytes into it instead
    /// of hitting the socket directly. flush() — or the 8KB auto-flush, or
    /// endChunked() — pushes it to the socket. This is what makes flush() a
    /// real operation: without it, bytes may sit in this buffer.
    /// Semantics: writeChunk alone does NOT guarantee delivery; call flush()
    /// (or end the stream) to push.
    out_buffer: std.array_list.Managed(u8),

    pub fn init(request: *HttpRequest, status: u16) !*HttpStreamResponse {
        const self = try initDeferred(request, status);
        errdefer self.deinit();
        try self.sendHead(status);
        return self;
    }

    pub fn initDeferred(request: *HttpRequest, status: u16) !*HttpStreamResponse {
        const self = try request.allocator.create(HttpStreamResponse);
        errdefer request.allocator.destroy(self);
        self.* = .{
            .allocator = request.allocator,
            .request = request,
            .status = status,
            .headers = ResponseHeaderBag.init(request.allocator, "text/event-stream"),
            .sent_head = false,
            .ended = false,
            .out_buffer = std.array_list.Managed(u8).init(request.allocator),
        };
        return self;
    }

    pub fn setHeader(self: *HttpStreamResponse, name: []const u8, value: []const u8) !void {
        if (self.sent_head) return error.ResponseAlreadySent;
        try self.headers.add(name, value);
    }

    pub fn sendHead(self: *HttpStreamResponse, status: u16) !void {
        if (self.sent_head) return;
        var head: std.Io.Writer.Allocating = .init(self.allocator);
        defer head.deinit();
        const writer = &head.writer;
        try writer.print("HTTP/1.1 {d} {s}\r\n", .{ status, statusText(status) });
        try self.headers.write(writer);
        try writer.writeAll("transfer-encoding: chunked\r\n");
        // Chunked framing is self-delimiting, so the connection may be
        // reused once the terminal chunk is sent.
        if (self.request.keep_alive) {
            try writer.writeAll("connection: keep-alive\r\n\r\n");
        } else {
            try writer.writeAll("connection: close\r\n\r\n");
        }
        try streamWriteAll(self.request.stream(), head.written());
        self.sent_head = true;
    }

    pub fn writeChunk(self: *HttpStreamResponse, bytes: []const u8) !void {
        if (!self.sent_head) try self.sendHead(self.status);
        var size_buf: [32]u8 = undefined;
        const size = try std.fmt.bufPrint(&size_buf, "{x}\r\n", .{bytes.len});
        try self.out_buffer.appendSlice(size);
        try self.out_buffer.appendSlice(bytes);
        try self.out_buffer.appendSlice("\r\n");
        if (self.out_buffer.items.len >= stream_flush_threshold) try self.flush();
    }

    /// Push everything buffered (sending the head first if needed) to the
    /// socket. This is a real flush: after it returns, all previously
    /// written chunks have been handed to the OS.
    pub fn flush(self: *HttpStreamResponse) !void {
        if (!self.sent_head) try self.sendHead(self.status);
        if (self.out_buffer.items.len != 0) {
            try streamWriteAll(self.request.stream(), self.out_buffer.items);
            self.out_buffer.clearRetainingCapacity();
        }
    }

    pub fn endChunked(self: *HttpStreamResponse) !void {
        if (self.ended) return;
        if (!self.sent_head) try self.sendHead(self.status);
        try self.flush();
        try streamWriteAll(self.request.stream(), "0\r\n\r\n");
        self.ended = true;
        self.request.response_done = true;
    }

    pub fn deinit(self: *HttpStreamResponse) void {
        self.out_buffer.deinit();
        self.headers.deinit();
        self.allocator.destroy(self);
    }
};

pub const WebSocketHandle = struct {
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,
    last_message: ?[]u8 = null,
    incoming: std.array_list.Managed(u8),
    fragmented: std.array_list.Managed(u8),
    fragmented_opcode: ?u8 = null,
    pending_write: ?[]u8 = null,
    pending_offset: usize = 0,
    v2_mode: bool = false,
    close_sent: bool = false,
    close_received: bool = false,
    peer_closed: bool = false,

    pub fn initFromRequest(request: *HttpRequest) !*WebSocketHandle {
        const self = try request.allocator.create(WebSocketHandle);
        self.* = .{
            .allocator = request.allocator,
            // Takes over the TCP stream; the HTTP connection is consumed and
            // never recycled for keep-alive.
            .stream = request.releaseStream(),
            .incoming = std.array_list.Managed(u8).init(request.allocator),
            .fragmented = std.array_list.Managed(u8).init(request.allocator),
        };
        return self;
    }

    pub fn enableV2(self: *WebSocketHandle) !void {
        if (self.v2_mode) return;
        try setNonBlocking(self.stream);
        self.v2_mode = true;
    }

    pub fn deinit(self: *WebSocketHandle) void {
        if (self.last_message) |message| self.allocator.free(message);
        if (self.pending_write) |pending| self.allocator.free(pending);
        self.incoming.deinit();
        self.fragmented.deinit();
        self.stream.close(sio.io());
        self.allocator.destroy(self);
    }
};

fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        500 => "Internal Server Error",
        else => "OK",
    };
}

pub fn findHeader(request: *HttpRequest, name: []const u8) ?[]const u8 {
    for (request.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) return header.value;
    }
    return null;
}

pub fn headerContainsToken(value: []const u8, token: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, value, " \t,");
    while (it.next()) |part| {
        if (std.ascii.eqlIgnoreCase(part, token)) return true;
    }
    return false;
}

pub fn streamWriteAll(stream: std.Io.net.Stream, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = std.c.write(stream.socket.handle, bytes.ptr + off, bytes.len - off);
        if (rc == 0) return error.BrokenPipe;
        if (rc < 0) {
            const e = std.c.errno(rc);
            if (e == .AGAIN) return error.WouldBlock;
            return error.ConnectionResetByPeer;
        }
        off += @intCast(rc);
    }
}

pub fn streamWriteSome(stream: std.Io.net.Stream, bytes: []const u8) !usize {
    const rc = std.c.write(stream.socket.handle, bytes.ptr, bytes.len);
    if (rc == 0) return error.BrokenPipe;
    if (rc < 0) {
        const e = std.c.errno(rc);
        if (e == .AGAIN) return error.WouldBlock;
        return error.ConnectionResetByPeer;
    }
    return @intCast(rc);
}

pub fn streamReadSome(stream: std.Io.net.Stream, buf: []u8) !usize {
    const rc = std.c.read(stream.socket.handle, buf.ptr, buf.len);
    if (rc == 0) return 0;
    if (rc < 0) {
        const e = std.c.errno(rc);
        if (e == .AGAIN) return error.WouldBlock;
        return error.ConnectionResetByPeer;
    }
    return @intCast(rc);
}

fn writeExact(stream: std.Io.net.Stream, bytes: []const u8) bool {
    streamWriteAll(stream, bytes) catch return false;
    return true;
}

pub fn writeFrame(stream: std.Io.net.Stream, opcode: u8, payload: []const u8) bool {
    const frame_cap = std.math.add(usize, payload.len, 14) catch return false;
    const frame = std.heap.c_allocator.alloc(u8, frame_cap) catch return false;
    defer std.heap.c_allocator.free(frame);
    const frame_len = sa_std_net.buildWebSocketFrame(frame, opcode, payload, null) catch return false;
    return writeExact(stream, frame[0..frame_len]);
}

pub fn readFrame(handle: *WebSocketHandle, max_len: u64, out_opcode: ?*u8, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const opcode_slot = out_opcode orelse return 2;
    const ptr_slot = out_ptr orelse return 2;
    const len_slot = out_len orelse return 2;

    while (true) {
        const frame = sa_std_net.readWebSocketFrameAlloc(handle.allocator, handle.stream, max_len, true) catch return 2;
        const opcode = frame.opcode;
        const payload = frame.payload;
        if (payload.len > 0) {
            if (handle.last_message) |message| handle.allocator.free(message);
            handle.last_message = null;
        }

        switch (opcode) {
            @intFromEnum(WebSocketOpcode.ping) => {
                if (!writeFrame(handle.stream, @intFromEnum(WebSocketOpcode.pong), payload)) {
                    if (payload.len > 0) handle.allocator.free(payload);
                    return 2;
                }
                if (payload.len > 0) handle.allocator.free(payload);
                continue;
            },
            @intFromEnum(WebSocketOpcode.pong) => {
                if (payload.len > 0) handle.allocator.free(payload);
                continue;
            },
            @intFromEnum(WebSocketOpcode.connection_close), @intFromEnum(WebSocketOpcode.text), @intFromEnum(WebSocketOpcode.binary) => {
                opcode_slot.* = opcode;
                if (payload.len == 0) {
                    if (handle.last_message) |message| handle.allocator.free(message);
                    handle.last_message = null;
                    ptr_slot.* = null;
                    len_slot.* = 0;
                } else {
                    if (handle.last_message) |message| handle.allocator.free(message);
                    handle.last_message = payload;
                    ptr_slot.* = payload.ptr;
                    len_slot.* = payload.len;
                }
                return 0;
            },
            else => {
                if (payload.len > 0) handle.allocator.free(payload);
                return 2;
            },
        }
    }
}

const ParsedV2Frame = struct {
    fin: bool,
    opcode: u8,
    payload: []u8,
};

fn decodeV2Frame(handle: *WebSocketHandle, max_len: usize) !?ParsedV2Frame {
    const bytes = handle.incoming.items;
    if (bytes.len < 2) return null;
    if ((bytes[0] & 0x70) != 0) return error.InvalidWebSocketFrame;

    const fin = bytes[0] & 0x80 != 0;
    const opcode = bytes[0] & 0x0f;
    const masked = bytes[1] & 0x80 != 0;
    if (!masked) return error.InvalidWebSocketFrame;

    var payload_len: u64 = bytes[1] & 0x7f;
    var offset: usize = 2;
    if (payload_len == 126) {
        if (bytes.len < 4) return null;
        payload_len = std.mem.readInt(u16, bytes[2..4], .big);
        if (payload_len < 126) return error.InvalidWebSocketFrame;
        offset = 4;
    } else if (payload_len == 127) {
        if (bytes.len < 10) return null;
        payload_len = std.mem.readInt(u64, bytes[2..10], .big);
        if (payload_len < 65536 or payload_len & (@as(u64, 1) << 63) != 0) return error.InvalidWebSocketFrame;
        offset = 10;
    }
    if (payload_len > max_len or payload_len > max_v2_message_bytes) return error.StreamTooLong;
    if (opcode >= 8 and (!fin or payload_len > 125)) return error.InvalidWebSocketFrame;
    if (opcode != 0 and opcode != 1 and opcode != 2 and opcode != 8 and opcode != 9 and opcode != 10) return error.InvalidWebSocketFrame;

    const payload_len_usize: usize = @intCast(payload_len);
    const frame_len = std.math.add(usize, offset + 4, payload_len_usize) catch return error.StreamTooLong;
    if (bytes.len < frame_len) return null;
    const mask = bytes[offset..][0..4].*;
    offset += 4;

    var payload: []u8 = &.{};
    if (payload_len_usize != 0) {
        payload = try handle.allocator.alloc(u8, payload_len_usize);
        @memcpy(payload, bytes[offset .. offset + payload_len_usize]);
        for (payload, 0..) |*byte, idx| byte.* ^= mask[idx & 3];
    }

    const remaining = bytes.len - frame_len;
    std.mem.copyForwards(u8, handle.incoming.items[0..remaining], handle.incoming.items[frame_len..]);
    handle.incoming.items.len = remaining;
    return .{ .fin = fin, .opcode = opcode, .payload = payload };
}

fn replaceLastMessage(handle: *WebSocketHandle, payload: []u8, out_ptr: *?[*]const u8, out_len: *u64) void {
    if (handle.last_message) |message| handle.allocator.free(message);
    if (payload.len == 0) {
        handle.last_message = null;
        out_ptr.* = null;
        out_len.* = 0;
    } else {
        handle.last_message = payload;
        out_ptr.* = payload.ptr;
        out_len.* = payload.len;
    }
}

fn flushPendingWrite(handle: *WebSocketHandle) NetworkStatus {
    const pending = handle.pending_write orelse return .ok;
    while (handle.pending_offset < pending.len) {
        const written = streamWriteSome(handle.stream, pending[handle.pending_offset..]) catch |err| return statusFromError(err);
        if (written == 0) {
            handle.peer_closed = true;
            return .closed;
        }
        handle.pending_offset += written;
    }
    handle.allocator.free(pending);
    handle.pending_write = null;
    handle.pending_offset = 0;
    return .ok;
}

fn websocketFrameSize(payload_len: usize) !usize {
    const header_len: usize = if (payload_len < 126) 2 else if (payload_len <= std.math.maxInt(u16)) 4 else 10;
    return std.math.add(usize, payload_len, header_len) catch error.StreamTooLong;
}

pub fn writeFrameV2(handle: *WebSocketHandle, opcode: u8, payload: []const u8) NetworkStatus {
    if (handle.peer_closed or handle.close_sent or handle.close_received) return .closed;
    if (payload.len > max_v2_message_bytes) return .too_large;
    if (opcode != 1 and opcode != 2 and opcode != 9 and opcode != 10) return .invalid;
    if ((opcode == @intFromEnum(WebSocketOpcode.ping) or opcode == @intFromEnum(WebSocketOpcode.pong)) and payload.len > 125) return .too_large;
    if (opcode == @intFromEnum(WebSocketOpcode.text) and !std.unicode.utf8ValidateSlice(payload)) return .invalid;
    handle.enableV2() catch return .io_error;

    const pending_status = flushPendingWrite(handle);
    if (pending_status != .ok) return pending_status;

    const frame_cap = websocketFrameSize(payload.len) catch return .too_large;
    const frame = handle.allocator.alloc(u8, frame_cap) catch return .io_error;
    const frame_len = sa_std_net.buildWebSocketFrame(frame, opcode, payload, null) catch {
        handle.allocator.free(frame);
        return .invalid;
    };
    handle.pending_write = frame[0..frame_len];
    handle.pending_offset = 0;
    const status = flushPendingWrite(handle);
    return switch (status) {
        .would_block => .ok,
        else => status,
    };
}

pub fn pollWebSocketV2(handle: *WebSocketHandle, interests: u32, timeout_ms: u32, out_events: *u32) NetworkStatus {
    out_events.* = 0;
    if (handle.peer_closed or handle.close_received) {
        out_events.* = PollEvent.closed;
        return .closed;
    }
    if (interests == 0 or interests & ~(PollEvent.readable | PollEvent.writable) != 0) return .invalid;
    handle.enableV2() catch return .io_error;

    if (interests & PollEvent.writable != 0 and handle.pending_write != null) {
        const flush_status = flushPendingWrite(handle);
        if (flush_status == .closed or flush_status == .io_error) return flush_status;
    }

    var posix_events: i16 = 0;
    if (interests & PollEvent.readable != 0) posix_events |= std.posix.POLL.IN;
    if (interests & PollEvent.writable != 0) posix_events |= std.posix.POLL.OUT;
    const poll_status = pollStream(handle.stream.socket.handle, posix_events, timeout_ms, out_events);
    if (poll_status != .ok) return poll_status;
    if (out_events.* & PollEvent.writable != 0 and handle.pending_write != null) {
        const flush_status = flushPendingWrite(handle);
        if (flush_status != .ok) {
            out_events.* &= ~PollEvent.writable;
            if (out_events.* & PollEvent.readable != 0) return .ok;
            return flush_status;
        }
    }
    return .ok;
}

pub fn readFrameV2(handle: *WebSocketHandle, max_len_u64: u64, out_opcode: *u8, out_ptr: *?[*]const u8, out_len: *u64) NetworkStatus {
    out_opcode.* = 0;
    out_ptr.* = null;
    out_len.* = 0;
    if (handle.peer_closed or handle.close_received) return .closed;
    handle.enableV2() catch return .io_error;
    const max_len: usize = @intCast(@min(max_len_u64, @as(u64, max_v2_message_bytes)));

    while (true) {
        const decoded = decodeV2Frame(handle, max_len) catch |err| {
            const status = statusFromError(err);
            if (status == .too_large or status == .invalid) handle.peer_closed = true;
            return status;
        };
        if (decoded) |frame| {
            switch (frame.opcode) {
                @intFromEnum(WebSocketOpcode.ping) => {
                    const pong_status = writeFrameV2(handle, @intFromEnum(WebSocketOpcode.pong), frame.payload);
                    if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                    if (pong_status != .ok) return pong_status;
                    continue;
                },
                @intFromEnum(WebSocketOpcode.pong) => {
                    if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                    continue;
                },
                @intFromEnum(WebSocketOpcode.connection_close) => {
                    if (frame.payload.len == 1) {
                        handle.allocator.free(frame.payload);
                        handle.peer_closed = true;
                        return .invalid;
                    }
                    if (frame.payload.len >= 2) {
                        const code = std.mem.readInt(u16, frame.payload[0..2], .big);
                        if (!validCloseCode(code) or !std.unicode.utf8ValidateSlice(frame.payload[2..])) {
                            handle.allocator.free(frame.payload);
                            handle.peer_closed = true;
                            return .invalid;
                        }
                    }
                    handle.close_received = true;
                    out_opcode.* = frame.opcode;
                    replaceLastMessage(handle, frame.payload, out_ptr, out_len);
                    return .ok;
                },
                @intFromEnum(WebSocketOpcode.text), @intFromEnum(WebSocketOpcode.binary) => {
                    if (handle.fragmented_opcode != null) {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        handle.peer_closed = true;
                        return .invalid;
                    }
                    if (frame.fin) {
                        if (frame.opcode == @intFromEnum(WebSocketOpcode.text) and !std.unicode.utf8ValidateSlice(frame.payload)) {
                            if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                            handle.peer_closed = true;
                            return .invalid;
                        }
                        out_opcode.* = frame.opcode;
                        replaceLastMessage(handle, frame.payload, out_ptr, out_len);
                        return .ok;
                    }
                    handle.fragmented_opcode = frame.opcode;
                    handle.fragmented.appendSlice(frame.payload) catch {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        return .io_error;
                    };
                    if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                },
                @intFromEnum(WebSocketOpcode.continuation) => {
                    const opcode = handle.fragmented_opcode orelse {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        handle.peer_closed = true;
                        return .invalid;
                    };
                    if (handle.fragmented.items.len + frame.payload.len > max_len or
                        handle.fragmented.items.len + frame.payload.len > max_v2_message_bytes)
                    {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        handle.peer_closed = true;
                        return .too_large;
                    }
                    handle.fragmented.appendSlice(frame.payload) catch {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        return .io_error;
                    };
                    if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                    if (frame.fin) {
                        const message = handle.fragmented.toOwnedSlice() catch return .io_error;
                        handle.fragmented = std.array_list.Managed(u8).init(handle.allocator);
                        handle.fragmented_opcode = null;
                        if (opcode == @intFromEnum(WebSocketOpcode.text) and !std.unicode.utf8ValidateSlice(message)) {
                            if (message.len != 0) handle.allocator.free(message);
                            handle.peer_closed = true;
                            return .invalid;
                        }
                        out_opcode.* = opcode;
                        replaceLastMessage(handle, message, out_ptr, out_len);
                        return .ok;
                    }
                },
                else => unreachable,
            }
            continue;
        }

        if (handle.incoming.items.len >= max_v2_message_bytes + 14) {
            handle.peer_closed = true;
            return .too_large;
        }
        var buffer: [4096]u8 = undefined;
        const capacity = max_v2_message_bytes + 14 - handle.incoming.items.len;
        const read_len = @min(buffer.len, capacity);
        const count = streamReadSome(handle.stream, buffer[0..read_len]) catch |err| return statusFromError(err);
        if (count == 0) {
            handle.peer_closed = true;
            return .closed;
        }
        handle.incoming.appendSlice(buffer[0..count]) catch return .io_error;
    }
}

fn validCloseCode(code: u16) bool {
    if (code < 1000 or code >= 5000) return false;
    return switch (code) {
        1004, 1005, 1006, 1015 => false,
        else => true,
    };
}

pub fn closeWebSocketV2(handle: *WebSocketHandle, code: u16, reason: []const u8) NetworkStatus {
    if (handle.peer_closed or handle.close_sent) return .closed;
    if (!validCloseCode(code) or reason.len > 123 or !std.unicode.utf8ValidateSlice(reason)) return .invalid;
    var payload: [125]u8 = undefined;
    std.mem.writeInt(u16, payload[0..2], code, .big);
    @memcpy(payload[2 .. 2 + reason.len], reason);

    handle.enableV2() catch return .io_error;
    const pending_status = flushPendingWrite(handle);
    if (pending_status != .ok) return pending_status;
    const frame_cap = websocketFrameSize(2 + reason.len) catch return .too_large;
    const frame = handle.allocator.alloc(u8, frame_cap) catch return .io_error;
    const frame_len = sa_std_net.buildWebSocketFrame(frame, @intFromEnum(WebSocketOpcode.connection_close), payload[0 .. 2 + reason.len], null) catch {
        handle.allocator.free(frame);
        return .invalid;
    };
    handle.pending_write = frame[0..frame_len];
    handle.pending_offset = 0;
    handle.close_sent = true;
    const status = flushPendingWrite(handle);
    return switch (status) {
        .would_block => .ok,
        else => status,
    };
}

fn methodStringAlloc(allocator: std.mem.Allocator, method: std.http.Method) ![]u8 {
    return allocator.dupe(u8, @tagName(method));
}

// ---------------------------------------------------------------------------
// SA-facing C ABI (sa_http_server_*). Moved from the plugin's
// http_saasm_api.zig; symbol names and status values are unchanged so
// existing .sai declarations and generated code link unmodified.
// AbiStatus mirrors the plugin ABI enum (ok=0, failed=2).
// ---------------------------------------------------------------------------
const AbiStatus = enum(u32) { ok = 0, failed = 2 };
const ws_net = @import("sa_ws_stream");
pub const SaHttpServerHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpRequestHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpResponseHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpStreamResponseHandle = extern struct {
    impl: ?*anyopaque,
};

/// The HTTP server used to be initialized with `std.heap.page_allocator`, which
/// issues one `mmap` per small allocation and one `munmap` per free. Under the
/// SA host that used to be invisible because the host's `munmap` stub was a
/// no-op, so the process leaked ~55 KB per request. With the stub hidden (see
/// `sci/src/runtime/sa_std.zig`) those syscalls became real and per-request
/// throughput collapsed. Use libc malloc so small request objects are pooled.
fn serverAllocator() std.mem.Allocator {
    return std.heap.c_allocator;
}

pub export fn sa_http_server_new(out_server: ?*?*anyopaque) u32 {
    ensureProcessSignalSafety();
    const slot = out_server orelse return @intFromEnum(AbiStatus.failed);
    const server = HttpServer.init(serverAllocator()) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(server);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_start(server: ?*anyopaque, host_ptr: ?[*]const u8, host_len: u64, port: u16) u32 {
    const server_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const host = host_ptr orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    srv.start(host[0..@intCast(host_len)], port) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_accept(server: ?*anyopaque, out_req: ?*?*anyopaque) u32 {
    const server_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_req orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    const request = srv.accept() catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(request);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_req_get_method(req: ?*anyopaque, out_method_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const method_slot = out_method_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_len orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    method_slot.* = request.method.ptr;
    len_slot.* = request.method.len;
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_req_get_path(req: ?*anyopaque, out_path_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const path_slot = out_path_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_len orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const target = request.target;
    const path = if (std.mem.indexOfScalar(u8, target, '?')) |idx| target[0..idx] else target;
    path_slot.* = path.ptr;
    len_slot.* = path.len;
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_req_get_header(req: ?*anyopaque, key_ptr: ?[*]const u8, key_len: u64, out_val_ptr: ?*?[*]const u8, out_val_len: ?*u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const key = key_ptr orelse return @intFromEnum(AbiStatus.failed);
    const path_slot = out_val_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_val_len orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const wanted = key[0..@intCast(key_len)];
    for (request.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, wanted)) {
            path_slot.* = header.value.ptr;
            len_slot.* = header.value.len;
            return @intFromEnum(AbiStatus.ok);
        }
    }
    return @intFromEnum(AbiStatus.failed);
}

pub export fn sa_http_server_req_get_body(req: ?*anyopaque, out_body_ptr: ?*?[*]const u8, out_body_len: ?*u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const body_slot = out_body_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_body_len orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    body_slot.* = request.body.ptr;
    len_slot.* = request.body.len;
    return @intFromEnum(AbiStatus.ok);
}

/// Frees a request. When the client negotiated keep-alive AND a fully-framed
/// response was sent, the TCP connection is recycled into the server's pool
/// for the next request instead of being closed.
fn recycleOrCloseRequest(request: *HttpRequest) void {
    if (request.response_done and request.keep_alive) {
        const srv = request.server;
        const conn = request.conn;
        // The client usually closes a connection-per-request socket right
        // after reading the response; recycling it would only fill the idle
        // pool with dead connections and slow every later accept to O(pool).
        if (HttpServer.isPeerClosed(conn.stream)) {
            request.deinit();
        } else {
            request.freeResources();
            request.allocator.destroy(request);
            srv.pushRecycled(conn);
        }
    } else {
        request.deinit();
    }
}

pub export fn sa_http_server_req_free(req: ?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    recycleOrCloseRequest(request);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_new(req: ?*anyopaque, status: u16, out_resp: ?*?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_resp orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = HttpResponse.init(request, status) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(response);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_send(resp: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const body = if (body_ptr) |body| body[0..@intCast(body_len)] else blk: {
        if (body_len != 0) return @intFromEnum(AbiStatus.failed);
        break :blk "";
    };
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.send(body) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_set_content_type(resp: ?*anyopaque, content_type_ptr: ?[*]const u8, content_type_len: u64) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const content_type = content_type_ptr orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.setContentType(content_type[0..@intCast(content_type_len)]) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_free(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.deinit();
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_new(req: ?*anyopaque, status: u16, out_resp: ?*?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_resp orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = HttpStreamResponse.init(request, status) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(response);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_write(resp: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const body = if (body_ptr) |body| body[0..@intCast(body_len)] else blk: {
        if (body_len != 0) return @intFromEnum(AbiStatus.failed);
        break :blk "";
    };
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return @intFromEnum(AbiStatus.failed);
    response.writeChunk(body) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_flush(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return @intFromEnum(AbiStatus.failed);
    response.flush() catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_end(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return @intFromEnum(AbiStatus.failed);
    response.endChunked() catch return @intFromEnum(AbiStatus.failed);
    response.ended = true;
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_free(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    response.deinit();
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_free(server: ?*anyopaque) u32 {
    const server_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    srv.deinit();
    return @intFromEnum(AbiStatus.ok);
}

/// Sets the v1 request body limit (default 2MB). Rejects 0 or >1GB.
/// v2's 16MB limit is unchanged.
pub export fn sa_http_server_set_max_body_bytes(server: ?*anyopaque, max_bytes: u64) u32 {
    const srv_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(srv_ptr)));
    srv.setMaxBodyLen(@intCast(max_bytes)) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

/// Runs a fixed-size plugin-internal accept loop: `num_threads` worker
/// threads invoke `handler(req, handler_ctx)` per accepted request (the
/// handler owns the request and must resp/upgrade + req_free it). Blocks
/// until sa_http_server_stop_serving is called or max_requests requests were
/// accepted (0 = unlimited). num_threads=0 uses the CPU count (1..256 clamp).
pub export fn sa_http_server_serve_threaded(
    server: ?*anyopaque,
    num_threads: u32,
    handler: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    handler_ctx: ?*anyopaque,
    max_requests: u64,
) u32 {
    const srv_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const h = handler orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(srv_ptr)));
    srv.serveThreaded(num_threads, h, handler_ctx, max_requests) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

/// Signals a running sa_http_server_serve_threaded loop to stop. Wakes
/// workers blocked in poll() via listener shutdown; in-flight handlers run
/// to completion. The listening socket is shut down, so the server handle
/// cannot accept afterwards — free it once serve_threaded has returned.
pub export fn sa_http_server_stop_serving(server: ?*anyopaque) u32 {
    const srv_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(srv_ptr)));
    srv.stopServing();
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_websocket_upgrade(req: ?*anyopaque, out_ws: ?*?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_ws orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));

    const upgrade = findHeader(request, "upgrade") orelse return @intFromEnum(AbiStatus.failed);
    if (!std.ascii.eqlIgnoreCase(upgrade, "websocket")) return @intFromEnum(AbiStatus.failed);
    const connection = findHeader(request, "connection") orelse return @intFromEnum(AbiStatus.failed);
    if (!headerContainsToken(connection, "upgrade")) return @intFromEnum(AbiStatus.failed);
    const key = findHeader(request, "sec-websocket-key") orelse return @intFromEnum(AbiStatus.failed);

    var accept_buf: [28]u8 = undefined;
    const accept = ws_net.websocketAccept(key, &accept_buf) catch return @intFromEnum(AbiStatus.failed);

    var header_buf: [256]u8 = undefined;
    const response = std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: {s}\r\n\r\n",
        .{accept},
    ) catch return @intFromEnum(AbiStatus.failed);
    streamWriteAll(request.stream(), response) catch return @intFromEnum(AbiStatus.failed);

    const handle = WebSocketHandle.initFromRequest(request) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(handle);
    request.freeResources();
    request.allocator.destroy(request);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_websocket_read(ws: ?*anyopaque, max_len: u64, out_opcode: ?*u8, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const ws_ptr = ws orelse return @intFromEnum(AbiStatus.failed);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    return readFrame(handle, max_len, out_opcode, out_ptr, out_len);
}

pub export fn sa_http_server_websocket_write(ws: ?*anyopaque, opcode: u8, data_ptr: ?[*]const u8, data_len: u64) u32 {
    const ws_ptr = ws orelse return @intFromEnum(AbiStatus.failed);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    const payload = if (data_ptr) |ptr| ptr[0..@intCast(data_len)] else &[_]u8{};
    if (!writeFrame(handle.stream, opcode, payload)) return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_websocket_free(ws: ?*anyopaque) u32 {
    const ws_ptr = ws orelse return @intFromEnum(AbiStatus.failed);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    handle.deinit();
    return @intFromEnum(AbiStatus.ok);
}

fn networkStatus(status: NetworkStatus) u32 {
    return @intFromEnum(status);
}

fn validWebSocketKey(key: []const u8) bool {
    if (key.len != 24) return false;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(key) catch return false;
    if (decoded_len != 16) return false;
    var decoded: [16]u8 = undefined;
    std.base64.standard.Decoder.decode(&decoded, key) catch return false;
    return true;
}

pub export fn sa_http_server_new_v2(out_server: ?*?*anyopaque) u32 {
    ensureProcessSignalSafety();
    const slot = out_server orelse return networkStatus(.invalid);
    slot.* = null;
    const server = HttpServer.init(serverAllocator()) catch return networkStatus(.io_error);
    slot.* = @ptrCast(server);
    return networkStatus(.ok);
}

pub export fn sa_http_server_start_v2(server: ?*anyopaque, host_ptr: ?[*]const u8, host_len: u64, port: u16) u32 {
    const server_ptr = server orelse return networkStatus(.invalid);
    if (host_len == 0 or host_len > std.math.maxInt(usize)) return networkStatus(.invalid);
    const host = host_ptr orelse return networkStatus(.invalid);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    srv.start(host[0..@intCast(host_len)], port) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_accept_v2(server: ?*anyopaque, timeout_ms: u32, out_req: ?*?*anyopaque) u32 {
    const slot = out_req orelse return networkStatus(.invalid);
    slot.* = null;
    const server_ptr = server orelse return networkStatus(.invalid);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    const started_ms = nowMillis();
    const poll_status = srv.pollAccept(timeout_ms);
    if (poll_status != .ok) return networkStatus(poll_status);
    const receive_timeout_ms: u32 = if (timeout_ms == 0) 0 else blk: {
        const elapsed_signed = nowMillis() - started_ms;
        const elapsed_ms: u64 = if (elapsed_signed <= 0) 0 else @intCast(elapsed_signed);
        if (elapsed_ms >= timeout_ms) return networkStatus(.timeout);
        break :blk @intCast(@as(u64, timeout_ms) - elapsed_ms);
    };
    const request = srv.acceptWithBodyLimitAndTimeout(max_v2_message_bytes, receive_timeout_ms) catch |err| {
        if (err == error.WouldBlock or err == error.HttpHeadersUnreadable) return networkStatus(if (timeout_ms == 0) .would_block else .timeout);
        return networkStatus(statusFromError(err));
    };
    slot.* = @ptrCast(request);
    return networkStatus(.ok);
}

pub export fn sa_http_server_req_free_v2(req: ?*anyopaque) u32 {
    const req_ptr = req orelse return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    recycleOrCloseRequest(request);
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_new_v2(req: ?*anyopaque, status: u16, out_resp: ?*?*anyopaque) u32 {
    const slot = out_resp orelse return networkStatus(.invalid);
    slot.* = null;
    const req_ptr = req orelse return networkStatus(.invalid);
    if (status < 100 or status > 599) return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = HttpResponse.init(request, status) catch return networkStatus(.io_error);
    slot.* = @ptrCast(response);
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_add_header_v2(resp: ?*anyopaque, name_ptr: ?[*]const u8, name_len: u64, value_ptr: ?[*]const u8, value_len: u64) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (name_len == 0 or name_len > std.math.maxInt(usize) or value_len > std.math.maxInt(usize)) return networkStatus(.invalid);
    const name = name_ptr orelse return networkStatus(.invalid);
    const value = if (value_ptr) |ptr| ptr[0..@intCast(value_len)] else blk: {
        if (value_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.setHeader(name[0..@intCast(name_len)], value) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_send_v2(resp: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64, timeout_ms: u32) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (body_len > max_v2_message_bytes) return networkStatus(.too_large);
    const body = if (body_ptr) |ptr| ptr[0..@intCast(body_len)] else blk: {
        if (body_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    response.send(body) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

// Header-only send (HEAD): same response object and header bag as
// resp_send_v2, but the wire carries the caller-declared
// content-length and zero body bytes. resp_send_v2 is unchanged.
pub export fn sa_http_server_resp_send_head_v2(resp: ?*anyopaque, content_length: u64, timeout_ms: u32) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    response.sendHeadOnly(content_length) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

// Raw request target of a v2 request, exactly as it arrived on
// the request line (path + "?" + query, absolute-form untouched).
// req_get_path strips the query; this getter exists so proxies
// and loggers can see the whole target. The returned slice is
// borrowed from the request and stays valid until req_free.
pub export fn sa_http_server_req_get_target_v2(req: ?*anyopaque, out_target_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const target_slot = out_target_ptr orelse return networkStatus(.invalid);
    const len_slot = out_len orelse return networkStatus(.invalid);
    const req_ptr = req orelse return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    target_slot.* = request.target.ptr;
    len_slot.* = request.target.len;
    return networkStatus(.ok);
}

// Query component of a v2 request's target: the bytes after the
// first "?", without the "?" itself. A target with no "?" returns
// ok with a zero length (no query is a normal case, not an
// error); the out pointer then addresses the end of the target.
pub export fn sa_http_server_req_get_query_v2(req: ?*anyopaque, out_query_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const query_slot = out_query_ptr orelse return networkStatus(.invalid);
    const len_slot = out_len orelse return networkStatus(.invalid);
    const req_ptr = req orelse return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const target = request.target;
    if (std.mem.indexOfScalar(u8, target, '?')) |idx| {
        const query = target[idx + 1 ..];
        query_slot.* = query.ptr;
        len_slot.* = query.len;
    } else {
        query_slot.* = target.ptr + target.len;
        len_slot.* = 0;
    }
    return networkStatus(.ok);
}

// File-body send (G3'): frames the response head with
// content-length = count and streams the file body with
// sendfile(2) -- the static-serving shape resp_send_v2 cannot
// express (it would need the whole file in memory). file_fd is a
// borrowed OS descriptor for an already-open readable file (see
// sa_std_fs_file_fd); it is NOT closed here. out_sent always
// receives the number of file bytes written, including on
// failure. Status values are the v2 network statuses, plus one
// extension: 8 = unsupported (the platform has no sendfile;
// NOTHING was sent, so the caller may still answer with an
// explicit error response). There is no buffered fallback: a
// short send (the file shrank after being measured) is reported
// as io_error with out_sent < count, never as success.
pub export fn sa_http_server_resp_send_file_v2(resp: ?*anyopaque, file_fd: i64, offset: u64, count: u64, timeout_ms: u32, out_sent: ?*u64) u32 {
    const sent_slot = out_sent orelse return networkStatus(.invalid);
    sent_slot.* = 0;
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (file_fd < 0 or file_fd > std.math.maxInt(std.posix.fd_t)) return networkStatus(.invalid);
    if (comptime builtin.cpu.arch.isWasm() or builtin.os.tag != .linux) return 8;
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    const sent = response.sendFile(@intCast(file_fd), offset, count) catch |err| return networkStatus(statusFromError(err));
    sent_slot.* = sent;
    if (sent != count) return networkStatus(.io_error);
    return networkStatus(.ok);
}

// Peer (remote) address of a v2 request, as text + port: the access
// log's remote field and per-request ACLs both need exactly this.
// The address text goes to out[0..out_len): dotted quad for IPv4;
// IPv6 in full (uncompressed) groups. If out_cap is too small the
// call returns too_large and out_len reports the needed size (the
// port is still written). Linux resolves via getpeername(2); other
// native platforms use the libc call; WASM has no sockets and
// returns invalid.
pub export fn sa_http_server_req_peer_addr_v2(req: ?*anyopaque, out: ?[*]u8, out_cap: u64, out_len: ?*u64, out_port: ?*u32) u32 {
    const len_slot = out_len orelse return networkStatus(.invalid);
    const port_slot = out_port orelse return networkStatus(.invalid);
    len_slot.* = 0;
    port_slot.* = 0;
    const req_ptr = req orelse return networkStatus(.invalid);
    if (out_cap > 0 and out == null) return networkStatus(.invalid);
    if (out_cap > std.math.maxInt(usize)) return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const fd = request.stream().socket.handle;
    var storage: [128]u8 align(4) = std.mem.zeroes([128]u8);
    var addr_len: u32 = storage.len;
    if (comptime builtin.cpu.arch.isWasm()) {
        return networkStatus(.invalid);
    } else if (comptime builtin.os.tag == .linux) {
        const rc = std.os.linux.getpeername(fd, @ptrCast(&storage), &addr_len);
        if (std.os.linux.errno(rc) != .SUCCESS) return networkStatus(.io_error);
    } else {
        const getpeername_c = struct {
            extern "c" fn getpeername(fd: std.posix.fd_t, addr: *anyopaque, len: *u32) c_int;
        }.getpeername;
        if (getpeername_c(fd, @ptrCast(&storage), &addr_len) != 0) return networkStatus(.io_error);
    }
    const family: u16 = std.mem.readInt(u16, storage[0..2], .little);
    const port_be: u16 = std.mem.readInt(u16, storage[2..4], .big);
    port_slot.* = port_be;
    var text_buf: [64]u8 = undefined;
    const text: []const u8 = switch (family) {
        2 => std.fmt.bufPrint(&text_buf, "{d}.{d}.{d}.{d}", .{ storage[4], storage[5], storage[6], storage[7] }) catch return networkStatus(.io_error),
        10 => blk: {
            var groups: [8]u16 = undefined;
            for (&groups, 0..) |*group, i| {
                group.* = std.mem.readInt(u16, storage[8 + i * 2 ..][0..2], .big);
            }
            break :blk std.fmt.bufPrint(&text_buf, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}", .{ groups[0], groups[1], groups[2], groups[3], groups[4], groups[5], groups[6], groups[7] }) catch return networkStatus(.io_error);
        },
        else => return networkStatus(.invalid),
    };
    len_slot.* = text.len;
    if (out_cap < text.len) return networkStatus(.too_large);
    if (out) |dst| @memcpy(dst[0..text.len], text);
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_free_v2(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.deinit();
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_new_v2(req: ?*anyopaque, status: u16, out_resp: ?*?*anyopaque) u32 {
    const slot = out_resp orelse return networkStatus(.invalid);
    slot.* = null;
    const req_ptr = req orelse return networkStatus(.invalid);
    if (status < 100 or status > 599) return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = HttpStreamResponse.initDeferred(request, status) catch return networkStatus(.io_error);
    slot.* = @ptrCast(response);
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_add_header_v2(resp: ?*anyopaque, name_ptr: ?[*]const u8, name_len: u64, value_ptr: ?[*]const u8, value_len: u64) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (name_len == 0 or name_len > std.math.maxInt(usize) or value_len > std.math.maxInt(usize)) return networkStatus(.invalid);
    const name = name_ptr orelse return networkStatus(.invalid);
    const value = if (value_ptr) |ptr| ptr[0..@intCast(value_len)] else blk: {
        if (value_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    response.setHeader(name[0..@intCast(name_len)], value) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_write_v2(resp: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64, timeout_ms: u32) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (body_len > max_v2_message_bytes) return networkStatus(.too_large);
    const body = if (body_ptr) |ptr| ptr[0..@intCast(body_len)] else blk: {
        if (body_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return networkStatus(.closed);
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    response.writeChunk(body) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_flush_v2(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return networkStatus(.closed);
    response.flush() catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_end_v2(resp: ?*anyopaque, timeout_ms: u32) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return networkStatus(.closed);
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    response.endChunked() catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_free_v2(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    response.deinit();
    return networkStatus(.ok);
}

pub export fn sa_http_server_free_v2(server: ?*anyopaque) u32 {
    const server_ptr = server orelse return networkStatus(.invalid);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    srv.deinit();
    return networkStatus(.ok);
}

pub export fn sa_http_server_websocket_upgrade_v2(req: ?*anyopaque, out_ws: ?*?*anyopaque) u32 {
    const slot = out_ws orelse return networkStatus(.invalid);
    slot.* = null;
    const req_ptr = req orelse return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const version = findHeader(request, "sec-websocket-version") orelse return networkStatus(.invalid);
    const key = findHeader(request, "sec-websocket-key") orelse return networkStatus(.invalid);
    if (!std.mem.eql(u8, version, "13") or !validWebSocketKey(key)) return networkStatus(.invalid);

    var raw_ws: ?*anyopaque = null;
    if (sa_http_server_websocket_upgrade(req, &raw_ws) != @intFromEnum(AbiStatus.ok)) return networkStatus(.invalid);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(raw_ws orelse return networkStatus(.io_error))));
    handle.enableV2() catch {
        handle.deinit();
        return networkStatus(.io_error);
    };
    slot.* = raw_ws;
    return networkStatus(.ok);
}

pub export fn sa_http_server_websocket_poll_v2(ws: ?*anyopaque, interests: u32, timeout_ms: u32, out_events: ?*u32) u32 {
    const events_slot = out_events orelse return networkStatus(.invalid);
    events_slot.* = 0;
    const ws_ptr = ws orelse return networkStatus(.invalid);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    return networkStatus(pollWebSocketV2(handle, interests, timeout_ms, events_slot));
}

pub export fn sa_http_server_websocket_read_v2(ws: ?*anyopaque, max_len: u64, out_opcode: ?*u8, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const opcode_slot = out_opcode orelse return networkStatus(.invalid);
    const ptr_slot = out_ptr orelse return networkStatus(.invalid);
    const len_slot = out_len orelse return networkStatus(.invalid);
    opcode_slot.* = 0;
    ptr_slot.* = null;
    len_slot.* = 0;
    const ws_ptr = ws orelse return networkStatus(.invalid);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    return networkStatus(readFrameV2(handle, max_len, opcode_slot, ptr_slot, len_slot));
}

pub export fn sa_http_server_websocket_write_v2(ws: ?*anyopaque, opcode: u8, data_ptr: ?[*]const u8, data_len: u64, out_written: ?*u64) u32 {
    const written_slot = out_written orelse return networkStatus(.invalid);
    written_slot.* = 0;
    const ws_ptr = ws orelse return networkStatus(.invalid);
    if (data_len > max_v2_message_bytes) return networkStatus(.too_large);
    const payload = if (data_ptr) |ptr| ptr[0..@intCast(data_len)] else blk: {
        if (data_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    const status = writeFrameV2(handle, opcode, payload);
    if (status == .ok) written_slot.* = data_len;
    return networkStatus(status);
}

pub export fn sa_http_server_websocket_close_v2(ws: ?*anyopaque, code: u16, reason_ptr: ?[*]const u8, reason_len: u64) u32 {
    const ws_ptr = ws orelse return networkStatus(.invalid);
    if (reason_len > 123) return networkStatus(.too_large);
    const reason = if (reason_ptr) |ptr| ptr[0..@intCast(reason_len)] else blk: {
        if (reason_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    return networkStatus(closeWebSocketV2(handle, code, reason));
}

pub export fn sa_http_server_websocket_free_v2(ws: ?*anyopaque) u32 {
    const ws_ptr = ws orelse return networkStatus(.invalid);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    handle.deinit();
    return networkStatus(.ok);
}

test "v2 send_head carries declared content-length without body; peer addr is the loopback client" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var server_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_new_v2(&server_slot));
    const server = server_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_free_v2(server);
    const host = "127.0.0.1";
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_start_v2(server, host.ptr, host.len, 18231));

    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 18231);
    var client = try address.connect(sio.io(), .{ .mode = .stream });
    defer client.close(sio.io());
    try streamWriteAll(client, "HEAD /thing HTTP/1.1\r\nhost: x\r\n\r\n");

    var req_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_accept_v2(server, 5000, &req_slot));
    const request = req_slot orelse return error.TestUnexpectedResult;

    // G2: peer address is the loopback client, port = client's own
    // local port (cross-checked through getsockname on the client).
    var ip_buf: [64]u8 = undefined;
    var ip_len: u64 = 0;
    var peer_port: u32 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_peer_addr_v2(request, &ip_buf, ip_buf.len, &ip_len, &peer_port));
    try std.testing.expectEqualStrings("127.0.0.1", ip_buf[0..@intCast(ip_len)]);
    var client_storage: [128]u8 align(4) = std.mem.zeroes([128]u8);
    var client_len: u32 = client_storage.len;
    const grc = std.os.linux.getsockname(client.socket.handle, @ptrCast(&client_storage), &client_len);
    try std.testing.expect(std.os.linux.errno(grc) == .SUCCESS);
    const client_port: u32 = std.mem.readInt(u16, client_storage[2..4], .big);
    try std.testing.expectEqual(client_port, peer_port);
    // Too-small buffer: too_large + needed length reported.
    var tiny: [4]u8 = undefined;
    var tiny_len: u64 = 0;
    var tiny_port: u32 = 0;
    try std.testing.expectEqual(@as(u32, 4), sa_http_server_req_peer_addr_v2(request, &tiny, tiny.len, &tiny_len, &tiny_port));
    try std.testing.expectEqual(@as(u64, 9), tiny_len);

    // G1: header-only send with a declared content-length of 1234.
    var resp_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_new_v2(request, 200, &resp_slot));
    const resp = resp_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_resp_free_v2(resp);
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_send_head_v2(resp, 1234, 5000));

    // The client receives exactly the head: status line, the
    // declared content-length, and no body bytes after the blank
    // line (the connection stays open under keep-alive, so any
    // extra byte within 300 ms would be a body leak).
    var rbuf: [512]u8 = undefined;
    var total: usize = 0;
    while (std.mem.indexOf(u8, rbuf[0..total], "\r\n\r\n") == null) {
        const rc = std.c.read(client.socket.handle, @ptrCast(rbuf[total..].ptr), rbuf.len - total);
        if (rc <= 0) return error.TestUnexpectedResult;
        total += @intCast(rc);
    }
    const head_text = rbuf[0..total];
    try std.testing.expect(std.mem.indexOf(u8, head_text, "HTTP/1.1 200") != null);
    try std.testing.expect(std.mem.indexOf(u8, head_text, "content-length: 1234") != null);
    var poll_fds = [1]std.posix.pollfd{.{ .fd = client.socket.handle, .events = std.posix.POLL.IN, .revents = 0 }};
    const ready = std.posix.poll(&poll_fds, 300) catch return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i32, 0), ready);

    _ = sa_http_server_req_free_v2(request);
}

test "v2 req_get_target/req_get_query expose the raw target and query (G4)" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var server_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_new_v2(&server_slot));
    const server = server_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_free_v2(server);
    const host = "127.0.0.1";
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_start_v2(server, host.ptr, host.len, 18234));
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 18234);

    // Request WITH a query string: target is verbatim, query is
    // the bytes after the first '?', path stays query-free.
    var client = try address.connect(sio.io(), .{ .mode = .stream });
    try streamWriteAll(client, "GET /api/echo?x=1&y=%32 HTTP/1.1\r\nhost: x\r\n\r\n");
    var req_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_accept_v2(server, 5000, &req_slot));
    const request = req_slot orelse return error.TestUnexpectedResult;
    var t_ptr: ?[*]const u8 = null;
    var t_len: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_target_v2(request, &t_ptr, &t_len));
    try std.testing.expectEqualStrings("/api/echo?x=1&y=%32", t_ptr.?[0..t_len]);
    var q_ptr: ?[*]const u8 = null;
    var q_len: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_query_v2(request, &q_ptr, &q_len));
    try std.testing.expectEqualStrings("x=1&y=%32", q_ptr.?[0..q_len]);
    var p_ptr: ?[*]const u8 = null;
    var p_len: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_path(request, &p_ptr, &p_len));
    try std.testing.expectEqualStrings("/api/echo", p_ptr.?[0..p_len]);
    var resp_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_new_v2(request, 200, &resp_slot));
    const resp = resp_slot orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_send_head_v2(resp, 0, 5000));
    _ = sa_http_server_resp_free_v2(resp);
    _ = sa_http_server_req_free_v2(request);
    client.close(sio.io());

    // Request WITHOUT a query string: ok status, zero length.
    var client2 = try address.connect(sio.io(), .{ .mode = .stream });
    defer client2.close(sio.io());
    try streamWriteAll(client2, "GET /plain HTTP/1.1\r\nhost: x\r\n\r\n");
    var req2_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_accept_v2(server, 5000, &req2_slot));
    const request2 = req2_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_req_free_v2(request2);
    var q2_ptr: ?[*]const u8 = null;
    var q2_len: u64 = 99;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_query_v2(request2, &q2_ptr, &q2_len));
    try std.testing.expectEqual(@as(u64, 0), q2_len);
    var t2_ptr: ?[*]const u8 = null;
    var t2_len: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_target_v2(request2, &t2_ptr, &t2_len));
    try std.testing.expectEqualStrings("/plain", t2_ptr.?[0..t2_len]);
    var resp2_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_new_v2(request2, 200, &resp2_slot));
    const resp2 = resp2_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_resp_free_v2(resp2);
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_send_head_v2(resp2, 0, 5000));
}

test "v2 resp_send_file streams the file body kernel-side (G3')" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const content = "sendfile-body-0123456789";
    const fd = std.c.open("/tmp/sa_sendfile_test_body.txt", .{ .ACCMODE = .RDWR, .CREAT = true, .TRUNC = true }, @as(std.c.mode_t, 0o644));
    if (fd < 0) return error.TestUnexpectedResult;
    defer _ = std.c.close(fd);
    if (std.c.write(fd, content.ptr, content.len) != @as(isize, @intCast(content.len))) return error.TestUnexpectedResult;

    var server_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_new_v2(&server_slot));
    const server = server_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_free_v2(server);
    const host = "127.0.0.1";
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_start_v2(server, host.ptr, host.len, 18235));
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 18235);
    var client = try address.connect(sio.io(), .{ .mode = .stream });
    defer client.close(sio.io());
    try streamWriteAll(client, "GET /body.txt HTTP/1.1\r\nhost: x\r\n\r\n");

    var req_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_accept_v2(server, 5000, &req_slot));
    const request = req_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_req_free_v2(request);
    var resp_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_new_v2(request, 200, &resp_slot));
    const resp = resp_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_resp_free_v2(resp);
    var sent: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_send_file_v2(resp, @intCast(fd), 0, content.len, 5000, &sent));
    try std.testing.expectEqual(@as(u64, content.len), sent);

    // The client receives the framed head (content-length =
    // count) followed by exactly the file bytes.
    var rbuf: [1024]u8 = undefined;
    var total: usize = 0;
    while (total < rbuf.len) {
        const rc = std.c.read(client.socket.handle, @ptrCast(rbuf[total..].ptr), rbuf.len - total);
        if (rc <= 0) break;
        total += @intCast(rc);
        if (std.mem.indexOf(u8, rbuf[0..total], "\r\n\r\n")) |hend| {
            if (total >= hend + 4 + content.len) break;
        }
    }
    const got = rbuf[0..total];
    const hend = std.mem.indexOf(u8, got, "\r\n\r\n") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, got[0..hend], "content-length: 24") != null);
    try std.testing.expectEqualStrings(content, got[hend + 4 ..][0..content.len]);
}
