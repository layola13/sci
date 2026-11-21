const std = @import("std");
const builtin = @import("builtin");
const sa_std_net = @import("sa_ws_stream");
const sio = @import("sio");
const ws_net = @import("sa_ws_stream");
const ConnState = @import("h01.zig").ConnState;
const Header = @import("h01.zig").Header;
const HttpRequest = @import("h03.zig").HttpRequest;
const HttpServer = @import("h02.zig").HttpServer;
const PollOutcome = @import("h01.zig").PollOutcome;
const ReadyConn = @import("h01.zig").ReadyConn;
const acceptFlags = @import("h01.zig").acceptFlags;
const conn_read_buffer_len = @import("h01.zig").conn_read_buffer_len;
const ipprotoTcp = @import("h01.zig").ipprotoTcp;
const max_recycled_conns = @import("h01.zig").max_recycled_conns;
const methodStringAlloc = @import("h04.zig").methodStringAlloc;
const nowMicros = @import("h01.zig").nowMicros;
const pollStream = @import("h01.zig").pollStream;
const probe_parse_timeout_ms = @import("h01.zig").probe_parse_timeout_ms;
const setBlocking = @import("h01.zig").setBlocking;
const setReceiveTimeout = @import("h01.zig").setReceiveTimeout;
const stampSortKey = @import("h01.zig").stampSortKey;

pub fn HttpServer_claimRecycledFrom(self: *HttpServer, pr: *const PollOutcome, max_body_len: usize, post_parse_timeout: ?u32) ?*HttpRequest {
        const n = pr.n_ready;
        // Accounting set: the readable candidates, in claim order.
        var accounting: [max_recycled_conns]ReadyConn = undefined;
        var nacc: usize = 0;
        // Claim order: insertion sort of candidate indices by
        // queue stamp, oldest first; unstamped (0) sorts last.
        var order: [max_recycled_conns]usize = undefined;
        for (0..n) |i| order[i] = i;
        var a: usize = 1;
        while (a < n) : (a += 1) {
            var b = a;
            while (b > 0) : (b -= 1) {
                const sb = stampSortKey(pr.ready[order[b]].stamp_us);
                const sp = stampSortKey(pr.ready[order[b - 1]].stamp_us);
                if (sb >= sp) break;
                const tmp = order[b];
                order[b] = order[b - 1];
                order[b - 1] = tmp;
            }
        }
        for (order[0..n]) |ci| {
            const entry = pr.ready[ci];
            const rev: i16 = entry.revents;
            const dead = rev & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0;
            const readable = !dead and (entry.has_buffered or (rev & std.posix.POLL.IN) != 0);
            if (!readable) {
                if (dead or (rev & std.posix.POLL.HUP) != 0) {
                    if (self.tryClaimPooled(entry.conn)) {
                        self.removeFromPool(entry.conn);
                        self.destroyConn(entry.conn, true);
                    }
                }
                continue;
            }
            accounting[nacc] = entry;
            nacc += 1;
            if (!self.tryClaimPooled(entry.conn)) continue;
            const conn = entry.conn;
            const stream = conn.stream;
            if (!(conn.read_len > conn.request_start)) {
                // Freshness re-check: exactly one poll(0) on the
                // winner (the legacy sweep polled the whole pool
                // at this point).
                var one = [_]std.posix.pollfd{.{
                    .fd = conn.stream.socket.handle,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                }};
                _ = std.posix.poll(&one, 0) catch 0;
                const orev: i16 = one[0].revents;
                if (orev & std.posix.POLL.IN == 0) {
                    if (orev & (std.posix.POLL.ERR | std.posix.POLL.NVAL | std.posix.POLL.HUP) != 0) {
                        self.removeFromPool(conn);
                        self.destroyConn(conn, true);
                    } else {
                        // Served and recycled by a peer after the
                        // accept poll: still pooled, just not
                        // ready. Release the claim and move on.
                        conn.claimed.store(false, .release);
                    }
                    continue;
                }
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
                self.removeFromPool(conn);
                self.destroyConn(conn, true);
                continue;
            };
            if (post_parse_timeout) |ms| {
                setReceiveTimeout(stream, ms) catch {
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

pub fn HttpServer_claimFromOutcome(self: *HttpServer, pr: *const PollOutcome, max_body_len: usize, post_parse_timeout: ?u32) ?*HttpRequest {
        if (pr.n_ready > 0) {
            if (self.claimRecycledFrom(pr, max_body_len, post_parse_timeout)) |req| return req;
        }
        return self.claimRecycled(max_body_len, post_parse_timeout);
    }

pub fn HttpServer_acceptFresh(
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

pub fn HttpServer_connCompact(conn: *ConnState) void {
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

pub fn HttpServer_connFill(conn: *ConnState) !void {
        HttpServer_connCompact(conn);
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

pub fn HttpServer_parseHead(self: *HttpServer, conn: *ConnState, max_body_len: usize) !*HttpRequest {

        while (true) {
            const avail = conn.read_buffer[conn.request_start..conn.read_len];
            if (std.mem.indexOf(u8, avail, "\r\n\r\n")) |_| break;
            if (avail.len >= 64 * 1024) return error.HttpHeadersOversize;
            try HttpServer_connFill(conn);
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

pub fn HttpServer_newConn(self: *HttpServer, accepted: std.Io.net.Stream) !*ConnState {
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

pub fn HttpServer_destroyConn(self: *HttpServer, conn: *ConnState, close_stream: bool) void {
        if (close_stream) conn.stream.close(sio.io());
        self.allocator.free(conn.read_buffer);
        self.allocator.destroy(conn);
    }

pub fn HttpServer_popRecycled(self: *HttpServer) ?*ConnState {
        self.recycled_mutex.lockUncancelable(sio.io());
        defer self.recycled_mutex.unlock(sio.io());
        if (self.recycled.items.len == 0) return null;
        return self.recycled.pop();
    }

pub fn HttpServer_isPeerClosed(stream: std.Io.net.Stream) bool {
        if (comptime builtin.cpu.arch.isWasm()) {
            return true;
        } else {
            return HttpServer_isPeerClosedNative(stream);
        }
    }

pub fn HttpServer_isPeerClosedNative(stream: std.Io.net.Stream) bool {
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

pub fn HttpServer_pushRecycled(self: *HttpServer, conn: *ConnState) void {
        {
            self.recycled_mutex.lockUncancelable(sio.io());
            defer self.recycled_mutex.unlock(sio.io());
            if (self.recycled.items.len >= max_recycled_conns) {
                self.destroyConn(conn, true);
                return;
            }
            // The pushing thread exclusively owns the connection
            // here; clear any claim before it becomes visible in
            // the pool.
            conn.claimed.store(false, .release);
            // A request pipelined into the buffer is already
            // queued at recycle time: stamp it for the delivery
            // histogram.
            if (conn.read_len > conn.request_start and conn.queued_since_us == 0) {
                conn.queued_since_us = nowMicros();
            }
            self.recycled.append(conn) catch {
                self.destroyConn(conn, true);
                return;
            };
        }
        var b: [1]u8 = .{0};
        _ = std.c.write(self.wake_pipe[1], &b, 1);
    }

pub fn HttpServer_deinit(self: *HttpServer) void {
        if (self.server) |*server| server.deinit(sio.io());
        while (self.popRecycled()) |conn| self.destroyConn(conn, true);
        self.recycled.deinit();
        _ = std.c.close(self.wake_pipe[0]);
        _ = std.c.close(self.wake_pipe[1]);
        self.allocator.destroy(self);
    }

