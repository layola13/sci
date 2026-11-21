const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const GNUTLS_ALPN_H3 = @import("q02.zig").GNUTLS_ALPN_H3;
const H3CB_ACKED_STREAM_DATA = @import("q01.zig").H3CB_ACKED_STREAM_DATA;
const H3CB_BEGIN_HEADERS = @import("q01.zig").H3CB_BEGIN_HEADERS;
const H3CB_END_HEADERS = @import("q01.zig").H3CB_END_HEADERS;
const H3CB_END_STREAM = @import("q01.zig").H3CB_END_STREAM;
const H3CB_RECV_DATA = @import("q01.zig").H3CB_RECV_DATA;
const H3CB_RECV_HEADER = @import("q01.zig").H3CB_RECV_HEADER;
const H3CB_RESET_STREAM = @import("q01.zig").H3CB_RESET_STREAM;
const H3CB_STOP_SENDING = @import("q01.zig").H3CB_STOP_SENDING;
const H3CB_STREAM_CLOSE = @import("q01.zig").H3CB_STREAM_CLOSE;
const H3Callbacks = @import("q01.zig").H3Callbacks;
const H3Conn = @import("q01.zig").H3Conn;
const H3Rcbuf = @import("q01.zig").H3Rcbuf;
const H3Settings = @import("q01.zig").H3Settings;
const H3Vec = @import("q01.zig").H3Vec;
const H3_DATA_FLAG_EOF = @import("q01.zig").H3_DATA_FLAG_EOF;
const H3_WRITE_BLOCKED = @import("q02.zig").H3_WRITE_BLOCKED;
const NG_ERR_WRITE_MORE = @import("q01.zig").NG_ERR_WRITE_MORE;
const NG_WRITE_STREAM_FLAG_FIN = @import("q01.zig").NG_WRITE_STREAM_FLAG_FIN;
const NG_WRITE_STREAM_FLAG_MORE = @import("q01.zig").NG_WRITE_STREAM_FLAG_MORE;
const NgCid = @import("q01.zig").NgCid;
const NgConn = @import("q01.zig").NgConn;
const NgPath = @import("q01.zig").NgPath;
const NgPktHd = @import("q01.zig").NgPktHd;
const NgPktInfo = @import("q01.zig").NgPktInfo;
const NgVec = @import("q01.zig").NgVec;
const QuicConn = @import("q01.zig").QuicConn;
const QuicListener = @import("q01.zig").QuicListener;
const SA_STD_ERR_AGAIN = @import("q01.zig").SA_STD_ERR_AGAIN;
const SA_STD_ERR_INVALID_ARGUMENT = @import("q01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("q01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NO_MEMORY = @import("q01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNSUPPORTED = @import("q01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("q01.zig").SA_STD_OK;
const SockStorage = @import("q01.zig").SockStorage;
const buildSettings = @import("q02.zig").buildSettings;
const buildTransportParams = @import("q02.zig").buildTransportParams;
const connFrom = @import("q02.zig").connFrom;
const cryptoGetConn = @import("q01.zig").cryptoGetConn;
const endpointFrom = @import("q02.zig").endpointFrom;
const flushWrites = @import("q02.zig").flushWrites;
const gnuServerSession = @import("q02.zig").gnuServerSession;
const loadGnuApi = @import("q01.zig").loadGnuApi;
const loadH3Api = @import("q01.zig").loadH3Api;
const loadNgApi = @import("q01.zig").loadNgApi;
const lxRecvFrom = @import("q02.zig").lxRecvFrom;
const makeCallbacks = @import("q02.zig").makeCallbacks;
const nowNs = @import("q01.zig").nowNs;
const quicStackAvailable = @import("q01.zig").quicStackAvailable;
const u64ToUsize = @import("q01.zig").u64ToUsize;

// ---- server accept machinery ---------------------------------------------------------
pub fn createServerConn(l: *QuicListener, hd: *const NgPktHd, src: *const SockStorage, src_len: std.posix.socklen_t) ?*QuicConn {
    const ng = loadNgApi() orelse return null;
    const ga = loadGnuApi() orelse return null;
    const qc = std.heap.page_allocator.create(QuicConn) catch return null;
    qc.* = .{ .fd = l.fd, .owns_fd = false, .is_server = true, .listener = l };
    qc.local = l.local;
    qc.local_len = l.local_len;
    qc.peer = src.*;
    qc.peer_len = src_len;
    qc.conn_ref = .{ .get_conn = &cryptoGetConn, .user_data = qc };
    gnuServerSession(ga, ng, qc, l.cred.?, GNUTLS_ALPN_H3) catch {
        std.heap.page_allocator.destroy(qc);
        return null;
    };
    var scid: NgCid = .{ .datalen = 8, .data = @splat(0) };
    sio.io().random(scid.data[0..8]);
    @memcpy(&qc.scid, scid.data[0..8]);
    const cbs = makeCallbacks(ng, qc);
    const settings = buildSettings(ng, nowNs());
    const tp = buildTransportParams(ng, hd.dcid);
    var p = qc.path();
    var conn: ?*NgConn = null;
    if (ng.conn_server_new(&conn, &hd.scid, &scid, &p, hd.version, 1, &cbs, 1, &settings, 1, &tp, null, qc) != 0) {
        if (qc.session) |sess| ga.deinit(sess);
        std.heap.page_allocator.destroy(qc);
        return null;
    }
    qc.conn = conn;
    ng.conn_set_tls_native_handle(conn, qc.session);
    l.conns.append(std.heap.page_allocator, qc) catch return null;
    l.pending.append(std.heap.page_allocator, qc) catch return null;
    const key = std.mem.readInt(u64, &qc.scid, .big);
    l.route.put(std.heap.page_allocator, key, qc) catch return null;
    return qc;
}

pub fn dispatchDatagram(l: *QuicListener, bytes: []const u8, src: *const SockStorage, src_len: std.posix.socklen_t) void {
    const ng = loadNgApi() orelse return;
    if (bytes.len == 0) return;
    var target: ?*QuicConn = null;
    if ((bytes[0] & 0x80) != 0) {
        var hd = NgPktHd{ .dcid = .{ .datalen = 0, .data = @splat(0) }, .scid = .{ .datalen = 0, .data = @splat(0) }, .token = .{ .base = null, .len = 0 }, .version = 0, .type_ = 0 };
        if (ng.accept(&hd, bytes.ptr, bytes.len) != 0) return;
        if (hd.version == 0) return;
        if (hd.dcid.datalen == 8) {
            const key = std.mem.readInt(u64, hd.dcid.data[0..8], .big);
            if (l.route.get(key)) |c| target = c;
        }
        if (target == null) {
            if ((bytes[0] & 0x30) != 0) return; // not an Initial
            target = createServerConn(l, &hd, src, src_len);
        }
    } else {
        if (bytes.len < 9) return;
        const key = std.mem.readInt(u64, bytes[1..9], .big);
        target = l.route.get(key);
    }
    const qc = target orelse return;
    {
        var it = qc.streams.valueIterator();
        while (it.next()) |sp| {
            if (sp.*.fin_in_pending) {
                flushWrites(qc);
                break;
            }
        }
    }
    qc.peer = src.*;
    qc.peer_len = src_len;
    var p = qc.path();
    var pi = NgPktInfo{ .ecn = 0 };
    _ = ng.conn_read_pkt(qc.conn, &p, 1, &pi, bytes.ptr, bytes.len, nowNs());
}

pub fn driveConnTimersAndFlush(qc: *QuicConn) void {
    const ng = loadNgApi() orelse return;
    if (qc.conn) |conn| {
        const now = nowNs();
        if (ng.conn_get_expiry(conn) <= now) {
            _ = ng.conn_handle_expiry(conn, now);
        }
    }
    if (qc.h3) |sess| sess.maybeBind();
    flushWrites(qc);
}

pub export fn sa_std_quic_server_poll(endpoint: u64, timeout_ms: u32) i32 {
    const ep = endpointFrom(endpoint) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const l = ep.listener orelse return SA_STD_ERR_INVALID_ARGUMENT;
    var fds = [_]std.posix.pollfd{.{ .fd = l.fd, .events = std.posix.POLL.IN, .revents = 0 }};
    _ = std.posix.poll(&fds, @intCast(timeout_ms)) catch return SA_STD_ERR_IO;
    var buf: [65536]u8 = undefined;
    var guard_n: usize = 0;
    while (guard_n < 256) : (guard_n += 1) {
        var src: SockStorage = undefined;
        var src_len: std.posix.socklen_t = @sizeOf(SockStorage);
        const rc = lxRecvFrom(l.fd, &buf, buf.len, 0, &src, &src_len);
        if (rc <= 0) break;
        const n: usize = @intCast(rc);
        dispatchDatagram(l, buf[0..n], &src, src_len);
    }
    for (l.conns.items) |qc| driveConnTimersAndFlush(qc);
    return SA_STD_OK;
}

pub export fn sa_std_quic_server_accept(endpoint: u64, out_conn: ?*u64) i32 {
    const slot = out_conn orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const ep = endpointFrom(endpoint) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const l = ep.listener orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (l.pending.items.len == 0) return SA_STD_ERR_AGAIN;
    const qc = l.pending.orderedRemove(0);
    slot.* = @intFromPtr(qc);
    return SA_STD_OK;
}

pub export fn sa_std_quic_conn_poll(handle: u64, timeout_ms: u32) i32 {
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ng = loadNgApi() orelse return SA_STD_ERR_UNSUPPORTED;
    if (qc.is_server) {
        // Incoming data for server conns is drained by server_poll (the
        // listener owns the socket); here we only run timers + flush.
        driveConnTimersAndFlush(qc);
        return SA_STD_OK;
    }
    flushWrites(qc);
    var wait_ms: i32 = @intCast(timeout_ms);
    if (qc.conn) |conn| {
        const now = nowNs();
        const expiry = ng.conn_get_expiry(conn);
        if (expiry > now) {
            const until = @as(i64, @intCast((expiry - now) / 1_000_000));
            if (until < wait_ms) wait_ms = @intCast(@max(until, 0));
        } else {
            wait_ms = 0;
        }
    }
    var fds = [_]std.posix.pollfd{.{ .fd = qc.fd, .events = std.posix.POLL.IN, .revents = 0 }};
    _ = std.posix.poll(&fds, wait_ms) catch return SA_STD_ERR_IO;
    var buf: [65536]u8 = undefined;
    var guard_n: usize = 0;
    while (guard_n < 256) : (guard_n += 1) {
        const rc = lxRecvFrom(qc.fd, &buf, buf.len, 0, null, null);
        if (rc <= 0) break;
        const n: usize = @intCast(rc);
        var p = qc.path();
        var pi = NgPktInfo{ .ecn = 0 };
        _ = ng.conn_read_pkt(qc.conn, &p, 1, &pi, &buf, n, nowNs());
    }
    driveConnTimersAndFlush(qc);
    return SA_STD_OK;
}

// ---- raw stream surface --------------------------------------------------------------
pub export fn sa_std_quic_stream_open(handle: u64, out_stream_id: ?*i64) i32 {
    const slot = out_stream_id orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = -1;
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ng = loadNgApi() orelse return SA_STD_ERR_UNSUPPORTED;
    var sid: i64 = -1;
    if (ng.conn_open_bidi_stream(qc.conn, &sid, null) != 0) return SA_STD_ERR_IO;
    _ = qc.ensureStream(sid) catch return SA_STD_ERR_NO_MEMORY;
    slot.* = sid;
    return SA_STD_OK;
}

pub export fn sa_std_quic_stream_write(handle: u64, stream_id: i64, data_ptr: ?[*]const u8, data_len: u64, fin: u32, out_written: ?*u64) i32 {
    const slot = out_written orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const n = u64ToUsize(data_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const data = if (data_ptr) |p| p[0..n] else return SA_STD_ERR_INVALID_ARGUMENT;
    const s = qc.ensureStream(stream_id) catch return SA_STD_ERR_NO_MEMORY;
    s.send.appendSlice(std.heap.page_allocator, data) catch return SA_STD_ERR_NO_MEMORY;
    if (fin != 0) s.send_fin = true;
    slot.* = data_len;
    return SA_STD_OK;
}

pub export fn sa_std_quic_stream_read(handle: u64, stream_id: i64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_fin: ?*u32) i32 {
    const rslot = out_read orelse return SA_STD_ERR_INVALID_ARGUMENT;
    rslot.* = 0;
    if (out_fin) |f| f.* = 0;
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const s = qc.getStream(stream_id) orelse return SA_STD_ERR_AGAIN;
    const avail = s.recv.items.len - s.recv_off;
    const n = @min(avail, u64ToUsize(cap) orelse return SA_STD_ERR_INVALID_ARGUMENT);
    if (n > 0) {
        const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
        @memcpy(buf[0..n], s.recv.items[s.recv_off..][0..n]);
        s.recv_off += n;
        rslot.* = @intCast(n);
    }
    if (s.recv_off >= s.recv.items.len) {
        s.recv.clearRetainingCapacity();
        s.recv_off = 0;
    }
    if (out_fin) |f| f.* = if (s.recv_fin and s.recv_off >= s.recv.items.len) 1 else 0;
    if (n == 0 and !s.recv_fin) return SA_STD_ERR_AGAIN;
    return SA_STD_OK;
}

// ---- HTTP/3 session --------------------------------------------------------------------
pub const H3Header = struct { name: []u8, value: []u8 };

pub const H3StreamState = struct {
    headers: std.ArrayListUnmanaged(H3Header) = .empty,
    status: u32 = 0,
    body: std.ArrayListUnmanaged(u8) = .empty,
    body_off: usize = 0,
    body_fin: bool = false,
    closed: bool = false,
    send_body: []u8 = &.{},
    send_off: usize = 0,
    pending_in: std.ArrayListUnmanaged(u8) = .empty,
    pending_in_fin: bool = false,

    pub fn header(self: *const H3StreamState, name: []const u8) ?[]const u8 {
        for (self.headers.items) |h| {
            if (std.mem.eql(u8, h.name, name)) return h.value;
        }
        return null;
    }
};

pub const H3Session = struct {
    h3: ?*H3Conn = null,
    qc: ?*QuicConn = null,
    is_server: bool = false,
    bound: bool = false,
    streams: std.AutoHashMapUnmanaged(i64, *H3StreamState) = .empty,
    pending_requests: std.ArrayListUnmanaged(i64) = .empty,
    last_error: i64 = 0,

    pub fn ensureStream(self: *H3Session, id: i64) !*H3StreamState {
        if (self.streams.get(id)) |s| return s;
        const s = try std.heap.page_allocator.create(H3StreamState);
        s.* = .{};
        try self.streams.put(std.heap.page_allocator, id, s);
        return s;
    }
    pub fn getStream(self: *H3Session, id: i64) ?*H3StreamState {
        return self.streams.get(id);
    }

    pub fn maybeBind(self: *H3Session) void {
        if (self.bound) return;
        const qc = self.qc orelse return;
        if (!qc.handshake_done) return;
        const ng = loadNgApi() orelse return;
        const ha = loadH3Api() orelse return;
        const h3 = self.h3 orelse return;
        var ctrl: i64 = -1;
        var enc: i64 = -1;
        var dec: i64 = -1;
        if (ng.conn_open_uni_stream(qc.conn, &ctrl, null) != 0) return;
        if (ng.conn_open_uni_stream(qc.conn, &enc, null) != 0) return;
        if (ng.conn_open_uni_stream(qc.conn, &dec, null) != 0) return;
        if (ha.bind_control_stream(h3, ctrl) != 0) return;
        if (ha.bind_qpack_streams(h3, enc, dec) != 0) return;
        self.bound = true;
    }

    pub fn feedStreamData(self: *H3Session, stream_id: i64, bytes: []const u8, fin: bool) c_int {
        const ha = loadH3Api() orelse return -1;
        const ng = loadNgApi() orelse return -1;
        const qc = self.qc orelse return -1;
        const h3 = self.h3 orelse return -1;
        const st = self.ensureStream(stream_id) catch return -1;
        var input = bytes;
        var input_fin = fin;
        if (st.pending_in.items.len > 0) {
            // Earlier bytes were not fully consumed; they go first.
            st.pending_in.appendSlice(std.heap.page_allocator, bytes) catch return -1;
            if (fin) st.pending_in_fin = true;
            input = st.pending_in.items;
            input_fin = st.pending_in_fin;
        }
        const consumed = ha.read_stream(h3, stream_id, input.ptr, input.len, if (input_fin) 1 else 0);
        if (consumed < 0) {
            self.last_error = consumed;
            return 0;
        }
        const used: usize = @intCast(consumed);
        if (used > 0) {
            ng.conn_extend_max_stream_offset(qc.conn, stream_id, used);
            ng.conn_extend_max_offset(qc.conn, used);
        }
        if (used < input.len) {
            if (st.pending_in.items.len == 0) {
                st.pending_in.appendSlice(std.heap.page_allocator, input[used..]) catch return -1;
                st.pending_in_fin = input_fin;
            } else {
                const rest = st.pending_in.items[used..];
                std.mem.copyForwards(u8, st.pending_in.items, rest);
                st.pending_in.shrinkRetainingCapacity(rest.len);
            }
        } else {
            st.pending_in.clearRetainingCapacity();
            st.pending_in_fin = false;
        }
        return 0;
    }

    pub fn retryPending(self: *H3Session) void {
        var it = self.streams.iterator();
        while (it.next()) |e| {
            const st = e.value_ptr.*;
            if (st.pending_in.items.len > 0) {
                _ = self.feedStreamData(e.key_ptr.*, &.{}, false);
            }
        }
    }

    pub fn ackedStreamData(self: *H3Session, stream_id: i64, datalen: u64) c_int {
        const ha = loadH3Api() orelse return -1;
        const h3 = self.h3 orelse return -1;
        _ = ha.add_ack_offset(h3, stream_id, datalen);
        return 0;
    }

    pub fn streamClosed(self: *H3Session, stream_id: i64, app_error_code: u64) c_int {
        const ha = loadH3Api() orelse return -1;
        if (self.getStream(stream_id)) |st| st.closed = true;
        const h3 = self.h3 orelse return -1;
        _ = ha.close_stream(h3, stream_id, app_error_code);
        return 0;
    }

    pub fn writeStep(self: *H3Session, path: *NgPath, pi: *NgPktInfo, buf: []u8, wdatalen_out: *i64) i64 {
        const ng = loadNgApi() orelse return -1;
        const ha = loadH3Api() orelse return -1;
        const qc = self.qc orelse return -1;
        const h3 = self.h3 orelse return -1;
        self.retryPending();
        var iter: usize = 0;
        while (iter < 64) : (iter += 1) {
            var sid: i64 = -1;
            var fin: c_int = 0;
            var vecs: [4]H3Vec = undefined;
            const nvec = ha.writev_stream(h3, &sid, &fin, &vecs, 4);
            if (nvec < 0) {
                self.last_error = nvec;
                return H3_WRITE_BLOCKED;
            }
            if (nvec == 0) return H3_WRITE_BLOCKED;
            var ngvecs: [4]NgVec = undefined;
            for (0..@intCast(nvec)) |i| {
                ngvecs[i] = .{ .base = vecs[i].base, .len = vecs[i].len };
            }
            var flags: u32 = NG_WRITE_STREAM_FLAG_MORE;
            if (fin == 1) flags |= NG_WRITE_STREAM_FLAG_FIN;
            var wdatalen: i64 = 0;
            const nw = ng.conn_writev_stream(qc.conn, path, 1, pi, buf.ptr, buf.len, &wdatalen, flags, sid, &ngvecs, @intCast(nvec), nowNs());
            if (nw == NG_ERR_WRITE_MORE) {
                if (wdatalen > 0) _ = ha.add_write_offset(h3, sid, @intCast(wdatalen));
                continue;
            }
            if (nw < 0) return nw;
            if (wdatalen > 0) _ = ha.add_write_offset(h3, sid, @intCast(wdatalen));
            if (nw == 0) return H3_WRITE_BLOCKED;
            wdatalen_out.* = wdatalen;
            return nw;
        }
        return H3_WRITE_BLOCKED;
    }

    pub fn destroy(self: *H3Session) void {
        const ha = loadH3Api();
        if (self.h3) |h| {
            if (ha) |a| a.conn_del(h);
        }
        var it = self.streams.valueIterator();
        while (it.next()) |sp| {
            const st = sp.*;
            for (st.headers.items) |hd| {
                std.heap.page_allocator.free(hd.name);
                std.heap.page_allocator.free(hd.value);
            }
            st.headers.deinit(std.heap.page_allocator);
            st.body.deinit(std.heap.page_allocator);
            st.pending_in.deinit(std.heap.page_allocator);
            if (st.send_body.len > 0) std.heap.page_allocator.free(st.send_body);
            std.heap.page_allocator.destroy(st);
        }
        self.streams.deinit(std.heap.page_allocator);
        self.pending_requests.deinit(std.heap.page_allocator);
        std.heap.page_allocator.destroy(self);
    }
};

// nghttp3 callbacks
pub fn h3cbAcked(conn: ?*H3Conn, stream_id: i64, datalen: u64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_id;
    _ = datalen;
    _ = conn_ud;
    _ = stream_ud;
    return 0;
}

pub fn h3cbStreamClose(conn: ?*H3Conn, stream_id: i64, app_error_code: u64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = app_error_code;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    if (sess.getStream(stream_id)) |st| st.closed = true;
    return 0;
}

pub fn h3cbRecvData(conn: ?*H3Conn, stream_id: i64, data: [*]const u8, datalen: usize, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    const st = sess.ensureStream(stream_id) catch return -1;
    st.body.appendSlice(std.heap.page_allocator, data[0..datalen]) catch return -1;
    return 0;
}

pub fn h3cbBeginHeaders(conn: ?*H3Conn, stream_id: i64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    _ = sess.ensureStream(stream_id) catch return -1;
    return 0;
}

pub fn h3cbRecvHeader(conn: ?*H3Conn, stream_id: i64, token: i32, name: ?*H3Rcbuf, value: ?*H3Rcbuf, flags: u8, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = token;
    _ = flags;
    _ = stream_ud;
    const ha = loadH3Api() orelse return -1;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    const st = sess.ensureStream(stream_id) catch return -1;
    const nb = ha.rcbuf_get_buf(name);
    const vb = ha.rcbuf_get_buf(value);
    const nname = std.heap.page_allocator.dupe(u8, (nb.base orelse return -1)[0..nb.len]) catch return -1;
    errdefer std.heap.page_allocator.free(nname);
    const nvalue = std.heap.page_allocator.dupe(u8, (vb.base orelse return -1)[0..vb.len]) catch return -1;
    errdefer std.heap.page_allocator.free(nvalue);
    st.headers.append(std.heap.page_allocator, .{ .name = nname, .value = nvalue }) catch return -1;
    if (std.mem.eql(u8, nname, ":status")) {
        st.status = std.fmt.parseInt(u32, nvalue, 10) catch 0;
    }
    return 0;
}

pub fn h3cbEndHeaders(conn: ?*H3Conn, stream_id: i64, fin: c_int, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = fin;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    _ = sess.ensureStream(stream_id) catch return -1;
    if (sess.is_server) {
        sess.pending_requests.append(std.heap.page_allocator, stream_id) catch return -1;
    }
    return 0;
}

pub fn h3cbEndStream(conn: ?*H3Conn, stream_id: i64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    if (sess.getStream(stream_id)) |st| st.body_fin = true;
    return 0;
}

pub fn h3cbStopSending(conn: ?*H3Conn, stream_id: i64, app_error_code: u64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const ng = loadNgApi() orelse return -1;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    const qc = sess.qc orelse return -1;
    _ = ng.conn_shutdown_stream_read(qc.conn, stream_id, app_error_code);
    return 0;
}

pub fn h3cbResetStream(conn: ?*H3Conn, stream_id: i64, app_error_code: u64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const ng = loadNgApi() orelse return -1;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    const qc = sess.qc orelse return -1;
    _ = ng.conn_shutdown_stream(qc.conn, stream_id, app_error_code);
    return 0;
}

pub fn h3ReadData(conn: ?*H3Conn, stream_id: i64, vecs: [*]H3Vec, veccnt: usize, pflags: *u32, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) i64 {
    _ = conn;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return -1));
    const st = sess.getStream(stream_id) orelse {
        pflags.* = H3_DATA_FLAG_EOF;
        return 0;
    };
    if (veccnt == 0) return 0;
    const remaining = st.send_body.len - st.send_off;
    if (remaining == 0) {
        pflags.* = H3_DATA_FLAG_EOF;
        return 0;
    }
    vecs[0] = .{ .base = st.send_body.ptr + st.send_off, .len = remaining };
    st.send_off += remaining;
    return 1;
}

pub fn makeH3Callbacks() H3Callbacks {
    var cbs = H3Callbacks{ .fields = @splat(null) };
    cbs.fields[H3CB_ACKED_STREAM_DATA] = @ptrCast(&h3cbAcked);
    cbs.fields[H3CB_STREAM_CLOSE] = @ptrCast(&h3cbStreamClose);
    cbs.fields[H3CB_RECV_DATA] = @ptrCast(&h3cbRecvData);
    cbs.fields[H3CB_BEGIN_HEADERS] = @ptrCast(&h3cbBeginHeaders);
    cbs.fields[H3CB_RECV_HEADER] = @ptrCast(&h3cbRecvHeader);
    cbs.fields[H3CB_END_HEADERS] = @ptrCast(&h3cbEndHeaders);
    cbs.fields[H3CB_STOP_SENDING] = @ptrCast(&h3cbStopSending);
    cbs.fields[H3CB_END_STREAM] = @ptrCast(&h3cbEndStream);
    cbs.fields[H3CB_RESET_STREAM] = @ptrCast(&h3cbResetStream);
    return cbs;
}

pub export fn sa_std_http3_session_create(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (!quicStackAvailable()) return SA_STD_ERR_UNSUPPORTED;
    const sess = std.heap.page_allocator.create(H3Session) catch return SA_STD_ERR_NO_MEMORY;
    sess.* = .{};
    slot.* = @intFromPtr(sess);
    return SA_STD_OK;
}

pub fn sessionFrom(handle: u64) ?*H3Session {
    if (handle == 0) return null;
    const p: *H3Session = @ptrFromInt(@as(usize, @intCast(handle)));
    return @alignCast(p);
}

pub export fn sa_std_http3_session_bind(session: u64, quic_conn: u64) i32 {
    const sess = sessionFrom(session) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const qc = connFrom(quic_conn) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ha = loadH3Api() orelse return SA_STD_ERR_UNSUPPORTED;
    if (sess.h3 != null or qc.h3 != null) return SA_STD_ERR_INVALID_ARGUMENT;
    sess.qc = qc;
    sess.is_server = qc.is_server;
    const cbs = makeH3Callbacks();
    const settings = H3Settings{ .max_field_section_size = 0, .qpack_max_dtable_capacity = 4096, .qpack_encoder_max_dtable_capacity = 4096, .qpack_blocked_streams = 100, .enable_connect_protocol = 0 };
    var h3: ?*H3Conn = null;
    const rc = if (qc.is_server)
        ha.conn_server_new(&h3, 1, &cbs, 1, &settings, null, sess)
    else
        ha.conn_client_new(&h3, 1, &cbs, 1, &settings, null, sess);
    if (rc != 0) {
        sess.qc = null;
        return SA_STD_ERR_IO;
    }
    sess.h3 = h3;
    qc.h3 = sess;
    sess.maybeBind();
    return SA_STD_OK;
}

pub export fn sa_std_http3_session_destroy(session: u64) i32 {
    const sess = sessionFrom(session) orelse return SA_STD_OK;
    if (sess.qc) |qc| {
        if (qc.h3 == sess) qc.h3 = null;
    }
    sess.destroy();
    return SA_STD_OK;
}
