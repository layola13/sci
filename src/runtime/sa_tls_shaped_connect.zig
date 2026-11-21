const std = @import("std");
const ConnectError = @import("sa_tls_shaped.zig").ConnectError;
const Effective = @import("sa_tls_shaped.zig").Effective;
const SSL_CTRL_SET_GROUPS_LIST = @import("sa_tls_shaped.zig").SSL_CTRL_SET_GROUPS_LIST;
const SSL_CTRL_SET_MAX_PROTO_VERSION = @import("sa_tls_shaped.zig").SSL_CTRL_SET_MAX_PROTO_VERSION;
const SSL_CTRL_SET_MIN_PROTO_VERSION = @import("sa_tls_shaped.zig").SSL_CTRL_SET_MIN_PROTO_VERSION;
const SSL_CTRL_SET_MSG_CALLBACK_ARG = @import("sa_tls_shaped.zig").SSL_CTRL_SET_MSG_CALLBACK_ARG;
const SSL_CTRL_SET_SIGALGS_LIST = @import("sa_tls_shaped.zig").SSL_CTRL_SET_SIGALGS_LIST;
const SSL_CTRL_SET_TLSEXT_HOSTNAME = @import("sa_tls_shaped.zig").SSL_CTRL_SET_TLSEXT_HOSTNAME;
const SSL_FILETYPE_PEM = @import("sa_tls_shaped.zig").SSL_FILETYPE_PEM;
const SSL_VERIFY_PEER = @import("sa_tls_shaped.zig").SSL_VERIFY_PEER;
const ShapedHandle = @import("sa_tls_shaped.zig").ShapedHandle;
const SslApi = @import("sa_tls_shaped.zig").SslApi;
const SslCtx = @import("sa_tls_shaped.zig").SslCtx;
const dialHost = @import("sa_tls_shaped.zig").dialHost;
const effectiveFromProfile = @import("sa_tls_shaped.zig").effectiveFromProfile;
const hello_cap = @import("sa_tls_shaped.zig").hello_cap;
const loadSslApi = @import("sa_tls_shaped.zig").loadSslApi;
const msgCallback = @import("sa_tls_shaped.zig").msgCallback;
const sio = @import("sa_tls_shaped.zig").sio;
const toZ = @import("sa_tls_shaped.zig").toZ;
const versionConst = @import("sa_tls_shaped.zig").versionConst;

pub fn loadCaPemIntoStore(api: *SslApi, ctx: *SslCtx, pem: []const u8) bool {
    const store = api.ctx_get_cert_store(ctx) orelse return false;
    const bio = api.bio_new_mem_buf(pem.ptr, @intCast(@min(pem.len, @as(usize, @intCast(std.math.maxInt(c_int)))))) orelse return false;
    defer _ = api.bio_free(bio);
    var count: usize = 0;
    while (true) {
        const x = api.pem_read_bio_x509(bio, null, null, null) orelse break;
        defer api.x509_free(x);
        if (api.x509_store_add_cert(store, x) != 1) return false;
        count += 1;
    }
    return count > 0;
}

pub fn doConnect(api: *SslApi, host_slice: []const u8, port: u16, eff: *const Effective) ConnectError!*ShapedHandle {
    const stream = dialHost(host_slice, port) catch return ConnectError.Io;
    return doConnectOnStream(api, stream, host_slice, eff);
}

pub fn doConnectOnStream(api: *SslApi, stream: std.Io.net.Stream, host_slice: []const u8, eff: *const Effective) ConnectError!*ShapedHandle {
    const alloc = std.heap.page_allocator;
    errdefer stream.close(sio.io());

    const method = api.method_new() orelse return ConnectError.Unsupported;
    const ctx = api.ctx_new(method) orelse return ConnectError.Io;
    errdefer api.ctx_free(ctx);

    // Fingerprint shaping on the context.
    if (eff.ciphersuites) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_set_ciphersuites(ctx, z.ptr) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.ciphers) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_set_cipher_list(ctx, z.ptr) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.groups) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_GROUPS_LIST, 0, @ptrCast(z.ptr)) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.sigalgs) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_SIGALGS_LIST, 0, @ptrCast(z.ptr)) != 1) return ConnectError.InvalidArgument;
    }
    // Client certificate presentation (mutual TLS): both files or neither
    // (validated in effectiveFromProfile).
    if (eff.cert_file) |cf| {
        const cz = toZ(alloc, cf) orelse return ConnectError.OutOfMemory;
        defer alloc.free(cz);
        if (api.ctx_use_cert_chain_file(ctx, cz.ptr) != 1) return ConnectError.Io;
        const kz = toZ(alloc, eff.key_file.?) orelse return ConnectError.OutOfMemory;
        defer alloc.free(kz);
        if (api.ctx_use_key_file(ctx, kz.ptr, SSL_FILETYPE_PEM) != 1) return ConnectError.Io;
        if (api.ctx_check_private_key(ctx) != 1) return ConnectError.Io;
    }
    if (eff.min_version) |v| {
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_MIN_PROTO_VERSION, versionConst(v).?, null) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.max_version) |v| {
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_MAX_PROTO_VERSION, versionConst(v).?, null) != 1) return ConnectError.InvalidArgument;
    }

    // Verification modes. Default: on, system store. ca_file / ca_pem
    // REPLACE the store with explicit private anchors (loopback tests,
    // private PKI). insecure_skip_verify -- and only that explicitly named
    // flag -- turns verification off entirely.
    if (eff.insecure_skip_verify) {
        api.ctx_set_verify(ctx, 0, null);
    } else if (eff.ca_pem) |v| {
        if (!loadCaPemIntoStore(api, ctx, v)) return ConnectError.InvalidArgument;
        api.ctx_set_verify(ctx, SSL_VERIFY_PEER, null);
    } else if (eff.ca_file) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_load_verify_locations(ctx, z.ptr, null) != 1) return ConnectError.Io;
        api.ctx_set_verify(ctx, SSL_VERIFY_PEER, null);
    } else {
        if (api.ctx_set_default_verify_paths(ctx) != 1) return ConnectError.Io;
        api.ctx_set_verify(ctx, SSL_VERIFY_PEER, null);
    }

    const ssl = api.new(ctx) orelse return ConnectError.Io;
    errdefer api.free(ssl);

    // SNI and the verification name split from the dial host when the
    // profile asks (CDN / IP-direct connects): verify_host wins for the
    // certificate check, then sni, then the dial host; SNI uses sni, then
    // the dial host. In insecure mode there is no name check at all.
    const verify_name: []const u8 = eff.verify_host orelse eff.sni orelse host_slice;
    const sni_name: []const u8 = eff.sni orelse host_slice;
    if (!eff.insecure_skip_verify) {
        const vz = toZ(alloc, verify_name) orelse return ConnectError.OutOfMemory;
        defer alloc.free(vz);
        if (api.set1_host(ssl, vz.ptr) != 1) return ConnectError.InvalidArgument;
    }
    {
        const sz = toZ(alloc, sni_name) orelse return ConnectError.OutOfMemory;
        defer alloc.free(sz);
        _ = api.ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, 0, @ptrCast(@constCast(sz.ptr)));
    }

    if (eff.alpn.len > 0) {
        var wire: [512]u8 = undefined;
        var off: usize = 0;
        for (eff.alpn) |proto| {
            if (proto.len == 0 or proto.len > 255) return ConnectError.InvalidArgument;
            if (off + 1 + proto.len > wire.len) return ConnectError.InvalidArgument;
            wire[off] = @intCast(proto.len);
            off += 1;
            @memcpy(wire[off..][0..proto.len], proto);
            off += proto.len;
        }
        if (api.set_alpn_protos(ssl, &wire, @intCast(off)) != 0) return ConnectError.InvalidArgument;
    }

    if (api.set_fd(ssl, stream.socket.handle) != 1) return ConnectError.Io;

    // Opportunistic session resumption: a malformed blob is a loud
    // argument error; a server that declines to resume simply produces a
    // full handshake (that is TLS semantics, not a verification change).
    if (eff.session_der) |der| {
        var p: ?[*]const u8 = der.ptr;
        const sess = api.d2i_session(null, &p, @intCast(der.len)) orelse return ConnectError.InvalidArgument;
        defer api.session_free(sess);
        if (api.set_session(ssl, sess) != 1) return ConnectError.InvalidArgument;
    }

    const host_owned = alloc.dupe(u8, host_slice) catch return ConnectError.OutOfMemory;
    errdefer alloc.free(host_owned);
    const hello_buf = alloc.alloc(u8, hello_cap) catch return ConnectError.OutOfMemory;
    errdefer alloc.free(hello_buf);
    const h = alloc.create(ShapedHandle) catch return ConnectError.OutOfMemory;
    errdefer alloc.destroy(h);
    h.* = .{
        .ssl = ssl,
        .ctx = ctx,
        .stream = stream,
        .host = host_owned,
        .hello_buf = hello_buf,
    };
    api.set_msg_callback(ssl, &msgCallback);
    _ = api.ctrl(ssl, SSL_CTRL_SET_MSG_CALLBACK_ARG, 0, h);

    if (api.connect(ssl) != 1) {
        if (eff.insecure_skip_verify) return ConnectError.Io;
        const vrc = api.get_verify_result(ssl);
        return if (vrc != 0) ConnectError.TlsVerify else ConnectError.Io;
    }
    if (!eff.insecure_skip_verify and api.get_verify_result(ssl) != 0) return ConnectError.TlsVerify;
    return h;
}

pub fn freeHandle(h: *ShapedHandle) void {
    const api = loadSslApi() orelse return;
    _ = api.shutdown(h.ssl);
    api.free(h.ssl);
    api.ctx_free(h.ctx);
    h.stream.close(sio.io());
    std.heap.page_allocator.free(h.host);
    std.heap.page_allocator.free(h.hello_buf);
    std.heap.page_allocator.destroy(h);
}

pub fn handleFromU64(handle: u64) ?*ShapedHandle {
    if (handle == 0) return null;
    const p: *ShapedHandle = @ptrFromInt(@as(usize, @intCast(handle)));
    return @alignCast(p);
}
