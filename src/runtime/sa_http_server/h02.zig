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
const Header = @import("h01.zig").Header;
const HttpRequest = @import("h03.zig").HttpRequest;
const HttpServeHandlerFn = @import("h01.zig").HttpServeHandlerFn;
const NetworkStatus = @import("h01.zig").NetworkStatus;
const PollOutcome = @import("h01.zig").PollOutcome;
const PooledSnapshot = @import("h01.zig").PooledSnapshot;
const ReadyConn = @import("h01.zig").ReadyConn;
const ThreadPool = @import("h01.zig").ThreadPool;
const acceptFlags = @import("h01.zig").acceptFlags;
const conn_read_buffer_len = @import("h01.zig").conn_read_buffer_len;
const histBucketFor = @import("h01.zig").histBucketFor;
const histDumpEnabled = @import("h01.zig").histDumpEnabled;
const hist_buckets = @import("h01.zig").hist_buckets;
const hist_segments = @import("h01.zig").hist_segments;
const ipprotoTcp = @import("h01.zig").ipprotoTcp;
const max_recycled_conns = @import("h01.zig").max_recycled_conns;
const methodStringAlloc = @import("h04.zig").methodStringAlloc;
const nowMicros = @import("h01.zig").nowMicros;
const nowMillis = @import("h01.zig").nowMillis;
const pollStream = @import("h01.zig").pollStream;
const probe_parse_timeout_ms = @import("h01.zig").probe_parse_timeout_ms;
const setBlocking = @import("h01.zig").setBlocking;
const setNonBlockingFd = @import("h01.zig").setNonBlockingFd;
const setReceiveTimeout = @import("h01.zig").setReceiveTimeout;
const spawnPoolWorker = @import("h01.zig").spawnPoolWorker;
const stampSortKey = @import("h01.zig").stampSortKey;
const timeoutMillis = @import("h01.zig").timeoutMillis;
const worker_head_parse_timeout_ms = @import("h01.zig").worker_head_parse_timeout_ms;

const HttpServer_histDump = @import("h02_impl_a.zig").HttpServer_histDump;
const HttpServer_histServed = @import("h02_impl_a.zig").HttpServer_histServed;
const HttpServer_init = @import("h02_impl_a.zig").HttpServer_init;
const HttpServer_initNative = @import("h02_impl_a.zig").HttpServer_initNative;
const HttpServer_start = @import("h02_impl_a.zig").HttpServer_start;
const HttpServer_startWithOptions = @import("h02_impl_a.zig").HttpServer_startWithOptions;
const HttpServer_setMaxBodyLen = @import("h02_impl_a.zig").HttpServer_setMaxBodyLen;
const HttpServer_accept = @import("h02_impl_a.zig").HttpServer_accept;
const HttpServer_acceptWorker = @import("h02_impl_a.zig").HttpServer_acceptWorker;
const HttpServer_serveThreaded = @import("h02_impl_a.zig").HttpServer_serveThreaded;
const HttpServer_stopServing = @import("h02_impl_a.zig").HttpServer_stopServing;
const HttpServer_pollAccept = @import("h02_impl_a.zig").HttpServer_pollAccept;
const HttpServer_posixRead = @import("h02_impl_a.zig").HttpServer_posixRead;
const HttpServer_pollAcceptEx = @import("h02_impl_a.zig").HttpServer_pollAcceptEx;
const HttpServer_acceptWithBodyLimit = @import("h02_impl_a.zig").HttpServer_acceptWithBodyLimit;
const HttpServer_acceptWithBodyLimitAndTimeout = @import("h02_impl_a.zig").HttpServer_acceptWithBodyLimitAndTimeout;
const HttpServer_acceptConfigured = @import("h02_impl_a.zig").HttpServer_acceptConfigured;
const HttpServer_acceptBounded = @import("h02_impl_a.zig").HttpServer_acceptBounded;
const HttpServer_removeFromPool = @import("h02_impl_a.zig").HttpServer_removeFromPool;
const HttpServer_finishClaim = @import("h02_impl_a.zig").HttpServer_finishClaim;
const HttpServer_completeClaim = @import("h02_impl_a.zig").HttpServer_completeClaim;
const HttpServer_tryClaimPooled = @import("h02_impl_a.zig").HttpServer_tryClaimPooled;
const HttpServer_claimRecycled = @import("h02_impl_a.zig").HttpServer_claimRecycled;
const HttpServer_claimRecycledFrom = @import("h02_impl_b.zig").HttpServer_claimRecycledFrom;
const HttpServer_claimFromOutcome = @import("h02_impl_b.zig").HttpServer_claimFromOutcome;
const HttpServer_acceptFresh = @import("h02_impl_b.zig").HttpServer_acceptFresh;
const HttpServer_connCompact = @import("h02_impl_b.zig").HttpServer_connCompact;
const HttpServer_connFill = @import("h02_impl_b.zig").HttpServer_connFill;
const HttpServer_parseHead = @import("h02_impl_b.zig").HttpServer_parseHead;
const HttpServer_newConn = @import("h02_impl_b.zig").HttpServer_newConn;
const HttpServer_destroyConn = @import("h02_impl_b.zig").HttpServer_destroyConn;
const HttpServer_popRecycled = @import("h02_impl_b.zig").HttpServer_popRecycled;
const HttpServer_isPeerClosed = @import("h02_impl_b.zig").HttpServer_isPeerClosed;
const HttpServer_isPeerClosedNative = @import("h02_impl_b.zig").HttpServer_isPeerClosedNative;
const HttpServer_pushRecycled = @import("h02_impl_b.zig").HttpServer_pushRecycled;
const HttpServer_deinit = @import("h02_impl_b.zig").HttpServer_deinit;

pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    server: ?std.Io.net.Server = null,
    /// v1 request body limit. Default 2MB (historic); configurable via
    /// sa_http_server_set_max_body_bytes. v2 always uses 16MB.
    max_body_len: usize = 2 * 1024 * 1024,
    /// Idle keep-alive connections waiting for their next request.
    recycled: std.array_list.Managed(*ConnState),
    /// def-accept F4: a blocking Io.Mutex, not the old yield-spin
    /// atomic mutex. Under multi-acceptor load the spin form convoys:
    /// every accept takes this lock 3-4 times and every response
    /// recycle once, and a yield-reschedule on a saturated box costs
    /// tens of us per handoff, which lands directly in the accept
    /// path. The futex form parks instead of burning scheduler slots.
    recycled_mutex: std.Io.Mutex = .init,
    /// Self-pipe: pushRecycled writes a byte so an accept loop blocked in
    /// poll() wakes up immediately. Recycling is asynchronous (handler
    /// threads recycle after the accept loop snapshotted the pool), so
    /// without this the next request on a reused connection could sleep
    /// until the poll timeout.
    wake_pipe: [2]std.posix.fd_t,
    /// Active plugin-internal thread pool (serve_threaded), if any.
    pool: ?*ThreadPool = null,
    /// Resident instrumentation counters [segment][bucket]
    /// (tail-fix D1; see the segment table near nowMicros).
    hist: [hist_segments][hist_buckets]CounterAtomic = blk: {
        var h: [hist_segments][hist_buckets]CounterAtomic = undefined;
        for (&h) |*seg| {
            for (seg) |*cell| cell.* = CounterAtomic.init(0);
        }
        break :blk h;
    },
    /// Accepts served since boot (drives the env-gated hist dump).
    hist_served: CounterAtomic = CounterAtomic.init(0),

    pub fn histRecord(self: *HttpServer, segment: usize, value: u64) void {
        _ = self.hist[segment][histBucketFor(value)].fetchAdd(1, .monotonic);
    }

    pub fn histDump(self: *HttpServer) void {
        return HttpServer_histDump(self);
    }

    /// Record one served accept (accept segment + periodic dump).
    pub fn histServed(self: *HttpServer, accept_started_us: i64) void {
        return HttpServer_histServed(self, accept_started_us);
    }

    pub fn init(allocator: std.mem.Allocator) !*HttpServer {
        return HttpServer_init(allocator);
    }

    pub fn initNative(allocator: std.mem.Allocator) !*HttpServer {
        return HttpServer_initNative(allocator);
    }

    pub fn start(self: *HttpServer, host: []const u8, port: u16) !void {
        return HttpServer_start(self, host, port);
    }

    pub fn startWithOptions(self: *HttpServer, host: []const u8, port: u16, options: std.Io.net.IpAddress.ListenOptions) !void {
        return HttpServer_startWithOptions(self, host, port, options);
    }

    pub fn setMaxBodyLen(self: *HttpServer, max_bytes: usize) !void {
        return HttpServer_setMaxBodyLen(self, max_bytes);
    }

    pub fn accept(self: *HttpServer) !*HttpRequest {
        return HttpServer_accept(self);
    }

    /// Worker accept for serve_threaded: poll-driven like acceptConfigured
    /// but with a 1s poll slice so stopServing() is noticed promptly, and a
    /// bounded head parse (slowloris guard). Returns error.WouldBlock on
    /// timeout or when stopping so the worker loop can re-check.
    pub fn acceptWorker(self: *HttpServer, stopping: *const std.atomic.Value(bool)) !*HttpRequest {
        return HttpServer_acceptWorker(self, stopping);
    }

    pub fn serveThreaded(
        self: *HttpServer,
        num_threads: u32,
        handler: HttpServeHandlerFn,
        handler_ctx: ?*anyopaque,
        max_requests: u64,
    ) !void {
        return HttpServer_serveThreaded(self, num_threads, handler, handler_ctx, max_requests);
    }

    /// Ask a running serveThreaded loop to stop. Wakes workers blocked in
    /// poll() via listener shutdown; in-flight handlers run to completion.
    /// NOTE: the shutdown also closes the listening socket, so the server
    /// handle cannot accept new connections afterwards — free it with
    /// sa_http_server_free once the loop has returned.
    pub fn stopServing(self: *HttpServer) void {
        return HttpServer_stopServing(self);
    }

    /// Public pollable status (v2 ABI). See pollAcceptEx for the internals.
    pub fn pollAccept(self: *HttpServer, timeout_ms: u32) NetworkStatus {
        return HttpServer_pollAccept(self, timeout_ms);
    }

    /// Like poll(2) over the listener plus all idle keep-alive connections
    /// plus the recycle wake pipe: tells the accept loop which class of fd
    /// is actionable so it can skip sweeping the idle pool when only the
    /// listener has traffic.

    pub fn posixRead(fd: std.posix.fd_t, buf: []u8) !usize {
        return HttpServer_posixRead(fd, buf);
    }

    pub fn pollAcceptEx(self: *HttpServer, timeout_ms: u32) PollOutcome {
        return HttpServer_pollAcceptEx(self, timeout_ms);
    }

    pub fn acceptWithBodyLimit(self: *HttpServer, max_body_len: usize) !*HttpRequest {
        return HttpServer_acceptWithBodyLimit(self, max_body_len);
    }

    pub fn acceptWithBodyLimitAndTimeout(self: *HttpServer, max_body_len: usize, timeout_ms: u32) !*HttpRequest {
        return HttpServer_acceptWithBodyLimitAndTimeout(self, max_body_len, timeout_ms);
    }

    pub fn acceptConfigured(self: *HttpServer, max_body_len: usize, receive_timeout_ms: ?u32) !*HttpRequest {
        return HttpServer_acceptConfigured(self, max_body_len, receive_timeout_ms);
    }

    pub fn acceptBounded(self: *HttpServer, max_body_len: usize, timeout_ms: u32) !*HttpRequest {
        return HttpServer_acceptBounded(self, max_body_len, timeout_ms);
    }

    /// Remove a connection from the idle pool (claim path). The
    /// caller must own the connection's claim.
    pub fn removeFromPool(self: *HttpServer, conn: *ConnState) void {
        return HttpServer_removeFromPool(self, conn);
    }

    /// Finish a successful claim under ONE pool-lock hold
    /// (tail-fix form 1): unlink the served connection and accrue
    /// a missed round to every other readable candidate that is
    /// still pooled and unclaimed. Pointers from the candidate
    /// list are dereferenced only after a presence match under
    /// this lock, so a peer's claim/free cannot race the walk.
    pub fn finishClaim(self: *HttpServer, conn: *ConnState, accounting: []const ReadyConn) void {
        return HttpServer_finishClaim(self, conn, accounting);
    }

    /// Shared tail of a successful claim (tail-fix): the served
    /// connection's delivery wait and missed-round count land in
    /// the histograms, then finishClaim unlinks it and accounts
    /// the missed rounds of the candidates it beat.
    pub fn completeClaim(self: *HttpServer, conn: *ConnState, accounting: []const ReadyConn) void {
        return HttpServer_completeClaim(self, conn, accounting);
    }

    /// Claim a pooled connection iff it is still in the pool.
    /// Claiming under the pool lock is what makes lock-free
    /// snapshots safe: a connection leaves the pool only through
    /// its claim owner (or deinit, when no acceptors run), so a
    /// presence check + CAS under the lock guarantees a peer
    /// cannot free the connection before the claim lands. After a
    /// successful claim the caller owns the connection and may
    /// dereference it without holding the lock.
    pub fn tryClaimPooled(self: *HttpServer, conn: *ConnState) bool {
        return HttpServer_tryClaimPooled(self, conn);
    }

    /// Parallel claim sweep over idle keep-alive connections
    /// (def-accept form 2; replaces the swap-out drain). Snapshots
    /// (pointer, fd, buffered flag) VALUES under a brief lock hold
    /// — pointers are never dereferenced from the snapshot alone —
    /// polls the copied fds once, then claims each ready connection
    /// via tryClaimPooled: the winner parses it outside any lock
    /// while other acceptors claim and parse other connections
    /// concurrently. Dead connections are claimed and reaped the
    /// same way. Returns the first connection that yields a
    /// complete request, or null when every ready connection was
    /// claimed by a peer or none was ready; never blocks.
    pub fn claimRecycled(self: *HttpServer, max_body_len: usize, post_parse_timeout: ?u32) ?*HttpRequest {
        return HttpServer_claimRecycled(self, max_body_len, post_parse_timeout);
    }

    /// Claim from a poll outcome's ready set (tail-fix form 1).
    /// Candidates are served OLDEST-FIRST by their queue stamp
    /// (anti-starvation: a connection that has waited longest is
    /// never passed over for a fresher one), at most one request
    /// per call. The ready set is a us-old hint: the winner is
    /// re-verified (presence + CAS in tryClaimPooled, then a
    /// one-fd poll(0) freshness check) before any parse, so a
    /// connection a peer served and recycled in the meantime is
    /// never parsed on stale readiness.
    pub fn claimRecycledFrom(self: *HttpServer, pr: *const PollOutcome, max_body_len: usize, post_parse_timeout: ?u32) ?*HttpRequest {
        return HttpServer_claimRecycledFrom(self, pr, max_body_len, post_parse_timeout);
    }

    /// Claim dispatcher for the poll-driven accept loops: use
    /// the outcome's ready set when the poll collected one, else
    /// the legacy snapshot sweep (it also reaps dead connections
    /// a wake-only poll could not see).
    pub fn claimFromOutcome(self: *HttpServer, pr: *const PollOutcome, max_body_len: usize, post_parse_timeout: ?u32) ?*HttpRequest {
        return HttpServer_claimFromOutcome(self, pr, max_body_len, post_parse_timeout);
    }

    /// Accept one NEW tcp connection (never a recycled one). With
    /// require_readable, returns null instead of blocking when the listener
    /// has nothing pending. The listener is non-blocking, so accept() can
    /// only return WouldBlock (no pending connection) rather than wedge.
    /// The head parse is always time-bounded: a client that connects but
    /// never sends a head must not wedge the single accept loop.
    pub fn acceptFresh(
        self: *HttpServer,
        max_body_len: usize,
        parse_timeout: ?u32,
        post_parse: ?u32,
        require_readable: bool,
    ) !?*HttpRequest {
        return HttpServer_acceptFresh(self, max_body_len, parse_timeout, post_parse, require_readable);
    }

    pub fn connCompact(conn: *ConnState) void {
        return HttpServer_connCompact(conn);
    }

    pub fn connFill(conn: *ConnState) !void {
        return HttpServer_connFill(conn);
    }

    pub fn parseHead(self: *HttpServer, conn: *ConnState, max_body_len: usize) !*HttpRequest {
        return HttpServer_parseHead(self, conn, max_body_len);
    }

    pub fn newConn(self: *HttpServer, accepted: std.Io.net.Stream) !*ConnState {
        return HttpServer_newConn(self, accepted);
    }

    pub fn destroyConn(self: *HttpServer, conn: *ConnState, close_stream: bool) void {
        return HttpServer_destroyConn(self, conn, close_stream);
    }

    pub fn popRecycled(self: *HttpServer) ?*ConnState {
        return HttpServer_popRecycled(self);
    }

    /// True when the peer already went away (EOF/RST pending). Called at
    /// recycle time so a connection the client already closed never wastes
    /// a pool slot, a wake-pipe byte, and a future O(pool) sweep. A readable
    /// socket is peeked: real bytes (pipelined next request) mean "keep",
    /// EOF means "drop".
    pub fn isPeerClosed(stream: std.Io.net.Stream) bool {
        return HttpServer_isPeerClosed(stream);
    }

    pub fn isPeerClosedNative(stream: std.Io.net.Stream) bool {
        return HttpServer_isPeerClosedNative(stream);
    }

    /// Return a connection to the idle pool (or close it when the pool is
    /// full). Wakes an accept loop blocked in poll() via the self-pipe, so
    /// the next request on this connection is picked up immediately even
    /// though recycling happens on a handler thread.
    pub fn pushRecycled(self: *HttpServer, conn: *ConnState) void {
        return HttpServer_pushRecycled(self, conn);
    }

    pub fn deinit(self: *HttpServer) void {
        return HttpServer_deinit(self);
    }
};
