const std = @import("std");
const builtin = @import("builtin");
const sa_std_net = @import("sa_ws_stream");
const sio = @import("sio");
const ws_net = @import("sa_ws_stream");
const ConnState = @import("h01.zig").ConnState;
const CounterAtomic = @import("h01.zig").CounterAtomic;
const HIST_SEG_ACCEPT = @import("h01.zig").HIST_SEG_ACCEPT;
const HIST_SEG_DELIVERY = @import("h01.zig").HIST_SEG_DELIVERY;
const HIST_SEG_MISSED = @import("h01.zig").HIST_SEG_MISSED;
const HttpRequest = @import("h03.zig").HttpRequest;
const HttpServeHandlerFn = @import("h01.zig").HttpServeHandlerFn;
const HttpServer = @import("h02.zig").HttpServer;
const NetworkStatus = @import("h01.zig").NetworkStatus;
const PollOutcome = @import("h01.zig").PollOutcome;
const PooledSnapshot = @import("h01.zig").PooledSnapshot;
const ReadyConn = @import("h01.zig").ReadyConn;
const ThreadPool = @import("h01.zig").ThreadPool;
const histDumpEnabled = @import("h01.zig").histDumpEnabled;
const hist_buckets = @import("h01.zig").hist_buckets;
const hist_segments = @import("h01.zig").hist_segments;
const max_recycled_conns = @import("h01.zig").max_recycled_conns;
const nowMicros = @import("h01.zig").nowMicros;
const nowMillis = @import("h01.zig").nowMillis;
const probe_parse_timeout_ms = @import("h01.zig").probe_parse_timeout_ms;
const setBlocking = @import("h01.zig").setBlocking;
const setNonBlockingFd = @import("h01.zig").setNonBlockingFd;
const setReceiveTimeout = @import("h01.zig").setReceiveTimeout;
const spawnPoolWorker = @import("h01.zig").spawnPoolWorker;
const timeoutMillis = @import("h01.zig").timeoutMillis;
const worker_head_parse_timeout_ms = @import("h01.zig").worker_head_parse_timeout_ms;

pub fn HttpServer_histDump(self: *HttpServer) void {
        for (0..hist_segments) |seg| {
            var total: u64 = 0;
            for (0..hist_buckets) |b| total += self.hist[seg][b].load(.monotonic);
            std.debug.print("SA_HTTP_HIST seg={d} total={d} buckets=", .{ seg, total });
            for (0..hist_buckets) |b| std.debug.print("{d},", .{self.hist[seg][b].load(.monotonic)});
            std.debug.print("\n", .{});
        }
    }

pub fn HttpServer_histServed(self: *HttpServer, accept_started_us: i64) void {
        const elapsed = nowMicros() - accept_started_us;
        if (elapsed > 0) self.histRecord(HIST_SEG_ACCEPT, @intCast(elapsed));
        const n = self.hist_served.fetchAdd(1, .monotonic) + 1;
        if (n % 16384 == 0 and histDumpEnabled()) self.histDump();
    }

pub fn HttpServer_init(allocator: std.mem.Allocator) !*HttpServer {
        if (comptime builtin.cpu.arch.isWasm()) {
            return error.UnsupportedPlatform;
        } else {
            return HttpServer_initNative(allocator);
        }
    }

pub fn HttpServer_initNative(allocator: std.mem.Allocator) !*HttpServer {
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

pub fn HttpServer_start(self: *HttpServer, host: []const u8, port: u16) !void {
        try self.startWithOptions(host, port, .{ .reuse_address = true });
    }

pub fn HttpServer_startWithOptions(self: *HttpServer, host: []const u8, port: u16, options: std.Io.net.IpAddress.ListenOptions) !void {
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

pub fn HttpServer_setMaxBodyLen(self: *HttpServer, max_bytes: usize) !void {
        if (max_bytes == 0 or max_bytes > (1 << 30)) return error.InvalidArgument;
        self.max_body_len = max_bytes;
    }

pub fn HttpServer_accept(self: *HttpServer) !*HttpRequest {
        return self.acceptConfigured(self.max_body_len, null);
    }

pub fn HttpServer_acceptWorker(self: *HttpServer, stopping: *const std.atomic.Value(bool)) !*HttpRequest {
        while (true) {
            if (stopping.load(.acquire)) return error.WouldBlock;
            const pr = self.pollAcceptEx(1000);
            switch (pr.status) {
                .ok => {
                    if (pr.recycled_ready) {
                        if (self.claimRecycled(self.max_body_len, null)) |req| return req;
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

pub fn HttpServer_serveThreaded(
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
            .served = CounterAtomic.init(0),
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

pub fn HttpServer_stopServing(self: *HttpServer) void {
        if (self.pool) |pool| pool.stopping.store(true, .release);
        if (self.server) |*s| _ = std.c.shutdown(s.socket.handle, 2);
    }

pub fn HttpServer_pollAccept(self: *HttpServer, timeout_ms: u32) NetworkStatus {
        return self.pollAcceptEx(timeout_ms).status;
    }

pub fn HttpServer_posixRead(fd: std.posix.fd_t, buf: []u8) !usize {
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

pub fn HttpServer_pollAcceptEx(self: *HttpServer, timeout_ms: u32) PollOutcome {
        const bad = PollOutcome{ .status = .invalid, .recycled_ready = false, .listener_ready = false };
        var fds: [max_recycled_conns + 2]std.posix.pollfd = undefined;        var nfds: usize = 0;
        var nrec: usize = 0;
        {
            self.recycled_mutex.lockUncancelable(sio.io());
            defer self.recycled_mutex.unlock(sio.io());
            for (self.recycled.items) |conn| {
                // Claimed connections are being parsed by another
                // acceptor: invisible to this poll.
                if (conn.claimed.load(.acquire)) continue;
                // Pipelined bytes already buffered: no need to poll.
                if (conn.read_len > conn.request_start) {
                    if (conn.queued_since_us == 0) conn.queued_since_us = nowMicros();
                    var out = PollOutcome{ .status = .ok, .recycled_ready = true, .listener_ready = false };
                    out.ready[0] = .{ .conn = conn, .revents = 0, .has_buffered = true, .stamp_us = conn.queued_since_us };
                    out.n_ready = 1;
                    return out;
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
        // poll: mark the pool for sweeping and let claimRecycled reap the
        // dead connection. Returning .io_error here used to wedge the accept
        // loop permanently (host spins on the failed accept). Only the
        // listener's health is fatal.
        var recycled_ready = false;
        if (fds[nrec].revents & std.posix.POLL.IN != 0) {
            recycled_ready = true;
            var tmp: [64]u8 = undefined;
            while (HttpServer_posixRead(self.wake_pipe[0], &tmp)) |n| {
                if (n == 0) break;
            } else |_| {}
        }
        for (fds[0..nrec]) |pfd| {
            if (pfd.revents != 0) recycled_ready = true;
        }
        var out = PollOutcome{ .status = .ok, .recycled_ready = recycled_ready, .listener_ready = false };
        if (recycled_ready) {
            // Delivery-histogram stamps + ready-set collection:
            // record when each ready pooled connection was first
            // observed, and carry the ready set into the claim.
            // Re-walk the pool under the lock and match poll slots
            // in build order (unclaimed connections only) so no
            // pointer from the unlocked poll set is dereferenced;
            // a pool change mid-poll can shift a stamp to a
            // neighbour, which only blurs this instrumentation,
            // never the service path (claims re-verify presence).
            const stamp_us = nowMicros();
            self.recycled_mutex.lockUncancelable(sio.io());
            defer self.recycled_mutex.unlock(sio.io());
            var fi: usize = 0;
            for (self.recycled.items) |conn| {
                if (conn.claimed.load(.acquire)) continue;
                if (fi >= nrec) break;
                const rev = fds[fi].revents;
                fi += 1;
                if (rev != 0) {
                    if (conn.queued_since_us == 0) conn.queued_since_us = stamp_us;
                    out.ready[out.n_ready] = .{ .conn = conn, .revents = rev, .has_buffered = false, .stamp_us = conn.queued_since_us };
                    out.n_ready += 1;
                }
            }
        }
        const levents = fds[nfds - 1].revents;
        if (levents & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0)
            return .{ .status = .io_error, .recycled_ready = false, .listener_ready = false };
        out.listener_ready = levents & std.posix.POLL.IN != 0;
        return out;
    }

pub fn HttpServer_acceptWithBodyLimit(self: *HttpServer, max_body_len: usize) !*HttpRequest {
        return self.acceptConfigured(max_body_len, null);
    }

pub fn HttpServer_acceptWithBodyLimitAndTimeout(self: *HttpServer, max_body_len: usize, timeout_ms: u32) !*HttpRequest {
        return self.acceptConfigured(max_body_len, timeout_ms);
    }

pub fn HttpServer_acceptConfigured(self: *HttpServer, max_body_len: usize, receive_timeout_ms: ?u32) !*HttpRequest {
        if (self.server == null) return error.NotFound;
        if (receive_timeout_ms) |timeout_ms| {
            return self.acceptBounded(max_body_len, timeout_ms);
        }
        // v1: block until the next request arrives on any connection.
        // Poll-driven so one idle keep-alive connection can never wedge the
        // accept loop while other connections have traffic. The idle pool is
        // only swept when poll saw pool activity (wake pipe or recycled fd),
        // keeping the per-accept cost O(1) in the common listener-traffic case.
        const accept_t0 = nowMicros();
        while (true) {
            const pr = self.pollAcceptEx(60_000);
            switch (pr.status) {
                .ok => {
                    if (pr.recycled_ready) {
                        if (self.claimFromOutcome(&pr, max_body_len, null)) |req| {
                            self.histServed(accept_t0);
                            return req;
                        }
                    }
                    if (pr.listener_ready) {
                        if (try self.acceptFresh(max_body_len, null, null, true)) |req| {
                            self.histServed(accept_t0);
                            return req;
                        }
                    }
                    // Spurious wakeup (e.g. a recycled fd died and was
                    // reaped): re-poll.
                },
                .timeout => continue,
                else => return error.ConnectionAborted,
            }
        }
    }

pub fn HttpServer_acceptBounded(self: *HttpServer, max_body_len: usize, timeout_ms: u32) !*HttpRequest {
        if (self.server == null) return error.NotFound;
        const start_ms = nowMillis();
        const accept_t0 = nowMicros();
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
                        if (self.claimFromOutcome(&pr, max_body_len, timeout_ms)) |req| {
                            self.histServed(accept_t0);
                            return req;
                        }
                    }
                    if (pr.listener_ready) {
                        if (try self.acceptFresh(max_body_len, remaining, timeout_ms, true)) |req| {
                            self.histServed(accept_t0);
                            return req;
                        }
                    }
                },
                .timeout => return error.HttpHeadersUnreadable,
                .would_block => return error.WouldBlock,
                else => return error.ConnectionAborted,
            }
        }
    }

pub fn HttpServer_removeFromPool(self: *HttpServer, conn: *ConnState) void {
        self.recycled_mutex.lockUncancelable(sio.io());
        defer self.recycled_mutex.unlock(sio.io());
        for (self.recycled.items, 0..) |item, idx| {
            if (item == conn) {
                _ = self.recycled.swapRemove(idx);
                return;
            }
        }
    }

pub fn HttpServer_finishClaim(self: *HttpServer, conn: *ConnState, accounting: []const ReadyConn) void {
        self.recycled_mutex.lockUncancelable(sio.io());
        defer self.recycled_mutex.unlock(sio.io());
        for (self.recycled.items, 0..) |item, idx| {
            if (item == conn) {
                _ = self.recycled.swapRemove(idx);
                break;
            }
        }
        for (accounting) |entry| {
            if (entry.conn == conn) continue;
            for (self.recycled.items) |item| {
                if (item == entry.conn) {
                    if (!item.claimed.load(.acquire)) {
                        _ = item.missed_rounds.fetchAdd(1, .monotonic);
                    }
                    break;
                }
            }
        }
    }

pub fn HttpServer_completeClaim(self: *HttpServer, conn: *ConnState, accounting: []const ReadyConn) void {
        if (conn.queued_since_us != 0) {
            const waited_us = nowMicros() - conn.queued_since_us;
            if (waited_us > 0) self.histRecord(HIST_SEG_DELIVERY, @intCast(waited_us));
            conn.queued_since_us = 0;
        }
        self.histRecord(HIST_SEG_MISSED, conn.missed_rounds.swap(0, .monotonic));
        self.finishClaim(conn, accounting);
    }

pub fn HttpServer_tryClaimPooled(self: *HttpServer, conn: *ConnState) bool {
        self.recycled_mutex.lockUncancelable(sio.io());
        defer self.recycled_mutex.unlock(sio.io());
        var present = false;
        for (self.recycled.items) |item| {
            if (item == conn) {
                present = true;
                break;
            }
        }
        if (!present) return false;
        return conn.claimed.cmpxchgStrong(false, true, .acquire, .monotonic) == null;
    }

pub fn HttpServer_claimRecycled(self: *HttpServer, max_body_len: usize, post_parse_timeout: ?u32) ?*HttpRequest {
        const Snapshot = PooledSnapshot;
        var snap: [max_recycled_conns]Snapshot = undefined;
        var nsnap: usize = 0;
        {
            self.recycled_mutex.lockUncancelable(sio.io());
            defer self.recycled_mutex.unlock(sio.io());
            for (self.recycled.items) |conn| {
                snap[nsnap] = .{
                    .conn = conn,
                    .fd = conn.stream.socket.handle,
                    .has_buffered = conn.read_len > conn.request_start,
                };
                nsnap += 1;
            }
        }

        // One poll over the whole snapshot instead of one syscall
        // per connection.
        var pfds: [max_recycled_conns]std.posix.pollfd = undefined;
        for (snap[0..nsnap], 0..) |entry, i| {
            pfds[i] = .{
                .fd = entry.fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            };
        }
        if (nsnap > 0) {
            _ = std.posix.poll(pfds[0..nsnap], 0) catch {};
        }

        // Readable candidates of this sweep (the claim accounting
        // set): if one of them wins, completeClaim charges the
        // others a missed round.
        var accounting: [max_recycled_conns]ReadyConn = undefined;
        var nacc: usize = 0;
        for (snap[0..nsnap], 0..) |entry, i| {
            const rev: i16 = pfds[i].revents;
            const dead = rev & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0;
            if (!dead and (entry.has_buffered or (rev & std.posix.POLL.IN) != 0)) {
                accounting[nacc] = .{ .conn = entry.conn, .revents = rev, .has_buffered = entry.has_buffered, .stamp_us = 0 };
                nacc += 1;
            }
        }

        for (snap[0..nsnap], 0..) |entry, i| {
            const rev: i16 = pfds[i].revents;
            const dead = rev & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0;
            // HUP without IN (or with nothing readable) also means the peer
            // is gone; IN means either data or EOF, decided by the parse.
            const readable = !dead and (entry.has_buffered or (rev & std.posix.POLL.IN) != 0);
            if (!readable) {
                if (dead or (rev & std.posix.POLL.HUP) != 0) {
                    // Reap a dead pooled connection; the claim keeps
                    // a peer sweep from double-freeing it.
                    if (self.tryClaimPooled(entry.conn)) {
                        self.removeFromPool(entry.conn);
                        self.destroyConn(entry.conn, true);
                    }
                }
                continue;
            }
            if (!self.tryClaimPooled(entry.conn)) {
                // A peer acceptor owns this one (or it left the
                // pool); try the next.
                continue;
            }
            // This acceptor owns the connection until it leaves the
            // pool (parsed into a request, or dropped below).
            const conn = entry.conn;
            const stream = conn.stream;
            if (!entry.has_buffered) {
                // Readable: give the head parse a short bounded wait so a
                // head+body split across TCP segments still completes.
                setBlocking(stream) catch {
                    self.removeFromPool(conn);
                    self.destroyConn(conn, true);
                    continue;
                };
                setReceiveTimeout(stream, probe_parse_timeout_ms) catch {
                    self.removeFromPool(conn);
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
                self.removeFromPool(conn);
                self.destroyConn(conn, true);
                continue;
            };
            // Normalize the socket mode for the handler.
            if (post_parse_timeout) |ms| {
                setReceiveTimeout(stream, ms) catch {
                    // req.deinit() destroys the conn; just unlink it
                    // from the pool first (pointer stays valid here).
                    self.removeFromPool(conn);
                    req.deinit();
                    continue;
                };
            } else {
                setBlocking(stream) catch {
                    self.removeFromPool(conn);
                    req.deinit();
                    continue;
                };
            }
            self.completeClaim(conn, accounting[0..nacc]);
            return req;
        }
        return null;
    }

