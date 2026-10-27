// TLS-client runtime binding for the sci/sa_std platform layer.
//
// Real TLS client handshake backed by Zig 0.14's std.crypto.tls.Client (pure
// Zig, no OpenSSL). std.crypto ships a TLS *client* only, which makes this the
// natural complement of sa_tls_server.zig (OpenSSL-backed TLS server).
//
// Trust model: the process-wide CA bundle singleton is populated from the OS
// trust store on first use (std.crypto.Certificate.Bundle.rescan, which covers
// Linux/macOS/Windows) and can be extended via sa_std_tls_client_add_ca_file
// (e.g. a private CA for loopback tests). There is deliberately NO
// verification-disabled path on this surface: `ca` is always `.bundle` and
// `host` is always `.explicit` (SNI + hostname check against the peer cert).
// The std ssl_key_log_file hook exists but is not exposed.
//
// Threading: the bundle singleton is guarded by a mutex. connect() dials TCP
// outside the lock (DNS can block), then holds the lock for the bundle
// snapshot + the full TLS handshake, because a copied Bundle shares the
// singleton's byte storage and add_ca_file could otherwise reallocate it out
// from under a live handshake.
//
// Configuration: sa_std_tls_client_connect is the fixed default profile
// (system bundle, SNI + hostname check against the dial host). The config
// object surface further down (sa_std_tls_client_config_*) adds the
// per-connection knobs std.crypto.tls.Client can actually honor: a
// server-name override (SNI + verification name, Python's server_hostname
// semantics), extra CA anchors from files or memory PEM, an expected
// self-signed peer mode, and an explicitly named no-verification switch.
// std's Client has a fixed ClientHello -- no ALPN, no cipher-suite or
// version selection, no session resumption -- so those knobs live on the
// OpenSSL shaped client (sa_tls_shaped.zig), not here; nothing on this
// surface silently accepts-and-ignores a setting. The peer certificate is
// likewise not exposed here: std's Client discards it after the handshake
// (see sa_std_tls_client_peer_cert_json).
//
// Status codes follow the sci convention: 0 = SA_STD_OK, negative = error.
// Certificate verification failures get SA_STD_ERR_TLS_VERIFY (-100).
//
// Handles are heap-allocated TlsClientHandle structs packed into a u64;
// 0 == invalid. close() consumes the handle (double-close is a caller bug,
// same as the other protocol sinks).
//
// Note: allow_truncation_attacks is set on every connection. Without it, a
// peer that closes TCP without a close_notify alert turns the final read into
// an error instead of a clean 0-byte EOF; HTTP-style users rely on the
// application layer (Content-Length / connection-close framing) for
// truncation safety anyway.

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_NO_MEMORY: i32 = -12;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_TLS_VERIFY: i32 = -100;

// wasm32-wasi: usize is 32-bit, C ABI passes u64 lengths. Checked conversion.
fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

const TlsClientHandle = struct {
    stream: std.Io.net.Stream,
    stream_reader: std.Io.net.Stream.Reader,
    stream_writer: std.Io.net.Stream.Writer,
    client: std.crypto.tls.Client,
    bundle: std.crypto.Certificate.Bundle,
    owns_bundle: bool = false,
    bundle_lock: std.Io.RwLock,
    sock_read_buf: [tls_buf_len]u8,
    sock_write_buf: [tls_buf_len]u8,
    tls_read_buf: [tls_buf_len]u8,
    tls_write_buf: [tls_buf_len]u8,
    host: []u8,
    port: u32,
};

// NOTE(Zig 0.17): one max-size TLS record per buffer; the stream reader
// buffer must hold at least `min_buffer_len`.
const tls_buf_len = std.crypto.tls.max_ciphertext_record_len;

// ---- process-wide CA bundle singleton --------------------------------------
// Populated once from the OS trust store (rescan), extended on demand by
// add_ca_file, never freed. Mirrors the SslApi singleton in sa_tls_server.zig.

var bundle_mutex = std.Io.Mutex.init;
var ca_bundle: ?std.crypto.Certificate.Bundle = null;

/// Caller must hold bundle_mutex. Returns a pointer to the live singleton so
/// adders mutate the shared store; readers take a value copy while the lock is
/// held and must finish using it before the lock is released by the owner.
fn ensureBundleLocked() anyerror!*std.crypto.Certificate.Bundle {
    if (ca_bundle == null) {
        var b: std.crypto.Certificate.Bundle = .empty;
        errdefer b.deinit(std.heap.page_allocator);
        try b.rescan(std.heap.page_allocator, sio.io(), std.Io.Clock.real.now(sio.io()));
        ca_bundle = b;
    }
    return &ca_bundle.?;
}

fn mapBundleErr(err: anyerror) i32 {
    return switch (err) {
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        else => SA_STD_ERR_IO,
    };
}

/// Certificate-shaped failures -> SA_STD_ERR_TLS_VERIFY (-100); everything
/// else that can surface from a TLS operation -> IO (or NO_MEMORY).
fn mapTlsErr(err: anyerror) i32 {
    return switch (err) {
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.CertificateHostMismatch,
        error.CertificateExpired,
        error.CertificateNotYetValid,
        error.CertificateTimeInvalid,
        error.CertificateIssuerMismatch,
        error.CertificateSignatureInvalid,
        error.CertificateSignatureInvalidLength,
        error.CertificateSignatureAlgorithmMismatch,
        error.CertificateSignatureAlgorithmUnsupported,
        error.CertificatePublicKeyInvalid,
        error.CertificateFieldHasInvalidLength,
        error.CertificateFieldHasWrongDataType,
        error.CertificateHasUnrecognizedObjectId,
        error.CertificateHasInvalidBitString,
        error.CertificateIssuerNotFound,
        error.TlsCertificateNotVerified,
        error.SignatureVerificationFailed,
        error.InvalidSignature,
        error.WeakPublicKey,
        => SA_STD_ERR_TLS_VERIFY,
        else => SA_STD_ERR_IO,
    };
}

fn mapDialErr(err: anyerror) i32 {
    return switch (err) {
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        else => SA_STD_ERR_IO,
    };
}

// NOTE(Zig 0.17): `IpAddress.resolve` only parses literals (no DNS), while
// the old `tcpConnectToHost` tried every resolved address. Literals connect
// directly; anything else goes through `HostName.connect`, which fans out to
// all addresses (Happy Eyeballs), so `localhost` works regardless of whether
// the peer bound ::1 or 127.0.0.1.
fn dialHost(host: []const u8, port: u16) !std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream });
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    return hn.connect(sio.io(), port, .{ .mode = .stream });
}

// ---- exported surface ------------------------------------------------------
// Handles are u64-packed heap pointers; 0 == invalid, matching the TCP and
// tls_server sinks.

pub export fn sa_std_tls_client_supported(out_supported: ?*u32) i32 {
    const slot = out_supported orelse return SA_STD_ERR_INVALID_ARGUMENT;
    // Pure-Zig backend (std.crypto.tls): no dlopen, no external library, so
    // the client is always available wherever sa_std itself builds.
    slot.* = 1;
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const host_n = u64ToUsize(host_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const host_slice = if (host_ptr) |p| p[0..host_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (host_slice.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if (port == 0 or port > 65535) return SA_STD_ERR_INVALID_ARGUMENT;

    // 1. TCP dial first, outside the bundle mutex (DNS resolution can block).
    // NOTE: this function returns i32, so errdefer is dead code here -- every
    // failure path below frees/closes explicitly.
    const stream = dialHost(host_slice, @intCast(port)) catch |err| {
        return mapDialErr(err);
    };

    // 2. Owned copy of the hostname: Client.init only borrows it during the
    // call, but we keep it on the handle for status/debug.
    const host_owned = std.heap.page_allocator.dupe(u8, host_slice) catch {
        stream.close(sio.io());
        return SA_STD_ERR_NO_MEMORY;
    };

    const h = std.heap.page_allocator.create(TlsClientHandle) catch {
        std.heap.page_allocator.free(host_owned);
        stream.close(sio.io());
        return SA_STD_ERR_NO_MEMORY;
    };
    h.* = .{
        .stream = stream,
        .stream_reader = undefined,
        .stream_writer = undefined,
        .client = undefined,
        .bundle = undefined,
        .bundle_lock = .init,
        .sock_read_buf = undefined,
        .sock_write_buf = undefined,
        .tls_read_buf = undefined,
        .tls_write_buf = undefined,
        .host = host_owned,
        .port = port,
    };
    h.stream_reader = stream.reader(sio.io(), &h.sock_read_buf);
    h.stream_writer = stream.writer(sio.io(), &h.sock_write_buf);

    // 3. Snapshot the bundle and run the blocking TLS handshake under the
    // mutex: the copied Bundle shares the singleton's byte storage, and this
    // keeps add_ca_file from reallocating it mid-handshake.
    // NOTE(Zig 0.17): the client borrows `&h.bundle`/`&h.bundle_lock` for the
    // life of the connection, so the copy lives on the handle, not the stack.
    var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
    sio.io().random(&entropy);
    bundle_mutex.lockUncancelable(sio.io());
    defer bundle_mutex.unlock(sio.io());
    h.bundle = (ensureBundleLocked() catch |err| {
        std.heap.page_allocator.free(host_owned);
        stream.close(sio.io());
        std.heap.page_allocator.destroy(h);
        return mapBundleErr(err);
    }).*;
    h.client = std.crypto.tls.Client.init(&h.stream_reader.interface, &h.stream_writer.interface, .{
        .host = .{ .explicit = host_owned },
        .ca = .{ .bundle = .{
            .gpa = std.heap.page_allocator,
            .io = sio.io(),
            .lock = &h.bundle_lock,
            .bundle = &h.bundle,
        } },
        .read_buffer = &h.tls_read_buf,
        .write_buffer = &h.tls_write_buf,
        .entropy = &entropy,
        .realtime_now = std.Io.Clock.real.now(sio.io()),
        .allow_truncation_attacks = true,
    }) catch |err| {
        std.heap.page_allocator.free(host_owned);
        stream.close(sio.io());
        std.heap.page_allocator.destroy(h);
        return mapTlsErr(err);
    };

    slot.* = @intFromPtr(h);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_add_ca_file(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path_n = u64ToUsize(path_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const path = if (path_ptr) |p| p[0..path_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (path.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    // addCertsFromFilePathAbsolute asserts an absolute path; reject early with
    // a contract error instead of tripping the assert.
    if (!std.fs.path.isAbsolute(path)) return SA_STD_ERR_INVALID_ARGUMENT;
    bundle_mutex.lockUncancelable(sio.io());
    defer bundle_mutex.unlock(sio.io());
    const b = ensureBundleLocked() catch |err| return mapBundleErr(err);
    const now = std.Io.Clock.real.now(sio.io());
    b.addCertsFromFilePathAbsolute(std.heap.page_allocator, sio.io(), now, path) catch |err| {
        return switch (err) {
            error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            else => SA_STD_ERR_IO,
        };
    };
    return SA_STD_OK;
}

fn handleFromU64(handle: u64) *TlsClientHandle {
    // Heap pointers from page_allocator are 16-byte aligned; alignCast keeps
    // this sound on targets (aarch64) where @ptrFromInt is stricter.
    // wasm32-wasi: usize is 32-bit, handle is u64 ABI (zero-extended pointer).
    const p: *TlsClientHandle = @ptrFromInt(@as(usize, @intCast(handle)));
    return @alignCast(p);
}

pub export fn sa_std_tls_client_read(handle: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const slot = out_read orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const h = handleFromU64(handle);
    const cap_len: usize = @min(cap, @as(u64, @intCast(std.math.maxInt(c_int))));
    if (cap_len == 0) return SA_STD_OK;
    // NOTE(Zig 0.17): single-shot read (not fill-or-EOF) to preserve the old
    // short-read contract framing callers rely on. The TLS record layer
    // buffers a full decrypted record and reports 0, and `readVec` calls
    // back into it to fill the rest of the vector (blocking for more records
    // even when bytes are already buffered), so: drain whatever is buffered
    // first with an exact-size vector (no vtable call), else pull one record
    // and loop around to drain it.
    while (true) {
        const avail = h.client.reader.bufferedLen();
        if (avail > 0) {
            const take = @min(cap_len, avail);
            var vec = [_][]u8{buf[0..take]};
            const n = h.client.reader.readVec(&vec) catch |err| {
                if (h.client.read_err) |rerr| return mapTlsErr(rerr);
                return mapTlsErr(err);
            };
            slot.* = @intCast(n);
            return SA_STD_OK;
        }
        var vec = [_][]u8{buf[0..cap_len]};
        _ = h.client.reader.readVec(&vec) catch |err| {
            if (h.client.read_err) |rerr| return mapTlsErr(rerr);
            if (err == error.EndOfStream) return SA_STD_OK;
            return mapTlsErr(err);
        };
    }
}

pub export fn sa_std_tls_client_write(handle: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const slot = out_written orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const src = buf orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const h = handleFromU64(handle);
    const chunk = src[0..@min(len, @as(u64, @intCast(std.math.maxInt(c_int))))];
    // NOTE(Zig 0.17): encrypted bytes land in the stream writer's buffer, so
    // both layers must flush (writer flush, then socket flush).
    h.client.writer.writeAll(chunk) catch |err| {
        return mapTlsErr(err);
    };
    h.client.writer.flush() catch |err| {
        return mapTlsErr(err);
    };
    h.stream_writer.interface.flush() catch |err| {
        return mapTlsErr(err);
    };
    slot.* = @intCast(chunk.len);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_close(handle: u64) i32 {
    if (handle == 0) return SA_STD_OK;
    const h = handleFromU64(handle);
    // Best-effort close_notify so the peer sees a clean shutdown; the peer
    // may already be gone, hence catch {}.
    h.client.end() catch {};
    h.client.writer.flush() catch {};
    h.stream_writer.interface.flush() catch {};
    h.stream.close(sio.io());
    if (h.owns_bundle) h.bundle.deinit(std.heap.page_allocator);
    std.heap.page_allocator.free(h.host);
    std.heap.page_allocator.destroy(h);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_status_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    var buffer: [192]u8 = undefined;
    const json = std.fmt.bufPrint(&buffer, "{{\"module\":\"tls_client\",\"backend\":\"std.crypto.tls\",\"supported\":true,\"protocolMachine\":true}}", .{}) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}


// ---- per-connection configuration (config object) --------------------------
//
// An opaque u64 handle to a heap TlsClientConfig; cfg == 0 passed to
// connect_config / start_tls selects the default configuration and behaves
// exactly like sa_std_tls_client_connect. Ownership: config_new hands the
// caller a handle released with config_free; connect_config / start_tls
// only borrow the config for the duration of the call.
//
// Security semantics (no silent demotions anywhere):
//  * Verification is ON by default against the OS trust store extended by
//    the process-wide add_ca_file anchors and any per-config CA anchors.
//  * The ONLY way to turn verification off is the explicitly named
//    sa_std_tls_client_config_set_insecure_no_verification switch. It is
//    never a default, and combining it with a server-name override or the
//    self-signed mode is a loud INVALID_ARGUMENT (std's no_verification
//    sends no SNI, so the combination cannot be honored honestly).
//  * set_verify_self_signed is NOT a skip: the peer must present a
//    well-formed, in-date, correctly self-signed certificate (std's
//    `.self_signed` mode); chain building is skipped, cryptography is not.

const TlsClientConfig = struct {
    server_name: ?[]u8 = null,
    ca_files: std.ArrayListUnmanaged([]u8) = .empty,
    ca_pem: std.ArrayListUnmanaged(u8) = .empty,
    insecure_no_verification: bool = false,
    verify_self_signed: bool = false,
};

fn configFromU64(handle: u64) ?*TlsClientConfig {
    if (handle == 0) return null;
    const p: *TlsClientConfig = @ptrFromInt(@as(usize, @intCast(handle)));
    return @alignCast(p);
}

pub export fn sa_std_tls_client_config_new(out_config: ?*u64) i32 {
    const slot = out_config orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const cfg = std.heap.page_allocator.create(TlsClientConfig) catch return SA_STD_ERR_NO_MEMORY;
    cfg.* = .{};
    slot.* = @intFromPtr(cfg);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_config_free(config: u64) i32 {
    const cfg = configFromU64(config) orelse return SA_STD_OK;
    if (cfg.server_name) |n| std.heap.page_allocator.free(n);
    for (cfg.ca_files.items) |p| std.heap.page_allocator.free(p);
    cfg.ca_files.deinit(std.heap.page_allocator);
    cfg.ca_pem.deinit(std.heap.page_allocator);
    std.heap.page_allocator.destroy(cfg);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_config_set_server_name(config: u64, name_ptr: ?[*]const u8, name_len: u64) i32 {
    const cfg = configFromU64(config) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const n = u64ToUsize(name_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (n == 0) {
        if (cfg.server_name) |old| std.heap.page_allocator.free(old);
        cfg.server_name = null;
        return SA_STD_OK;
    }
    const name = if (name_ptr) |p| p[0..n] else return SA_STD_ERR_INVALID_ARGUMENT;
    const owned = std.heap.page_allocator.dupe(u8, name) catch return SA_STD_ERR_NO_MEMORY;
    if (cfg.server_name) |old| std.heap.page_allocator.free(old);
    cfg.server_name = owned;
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_config_add_ca_file(config: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const cfg = configFromU64(config) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const n = u64ToUsize(path_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const path = if (path_ptr) |p| p[0..n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (path.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    // Same early contract check as the process-wide add_ca_file: the
    // underlying bundle API asserts on relative paths.
    if (!std.fs.path.isAbsolute(path)) return SA_STD_ERR_INVALID_ARGUMENT;
    const owned = std.heap.page_allocator.dupe(u8, path) catch return SA_STD_ERR_NO_MEMORY;
    cfg.ca_files.append(std.heap.page_allocator, owned) catch {
        std.heap.page_allocator.free(owned);
        return SA_STD_ERR_NO_MEMORY;
    };
    return SA_STD_OK;
}

/// Decode PEM certificates into a bundle, following the exact algorithm of
/// std's own Bundle.addCertsFromFile (marker scan, base64 decode, parseCert
/// per certificate) but sourced from memory. Certificates std would skip
/// (unrecognized OID, expired) are skipped the same way; a decode failure
/// aborts with an error.
fn addCertsFromMemory(bundle: *std.crypto.Certificate.Bundle, pem: []const u8, now_sec: i64) !void {
    const gpa = std.heap.page_allocator;
    const decoder = std.base64.standard.decoderWithIgnore(" \t\r\n");
    const begin_marker = "-----BEGIN CERTIFICATE-----";
    const end_marker = "-----END CERTIFICATE-----";
    var start_index: usize = 0;
    while (std.mem.findPos(u8, pem, start_index, begin_marker)) |begin_start| {
        const cert_start = begin_start + begin_marker.len;
        const cert_end = std.mem.findPos(u8, pem, cert_start, end_marker) orelse return error.MissingEndCertificateMarker;
        start_index = cert_end + end_marker.len;
        const encoded = std.mem.trim(u8, pem[cert_start..cert_end], " \t\r\n");
        // The decoded form is never longer than the encoded form.
        const buf = try gpa.alloc(u8, encoded.len);
        defer gpa.free(buf);
        const decoded_len = decoder.decode(buf, encoded) catch return error.InvalidCertificatePem;
        const decoded_start: u32 = @intCast(bundle.bytes.items.len);
        try bundle.bytes.appendSlice(gpa, buf[0..decoded_len]);
        bundle.parseCert(gpa, decoded_start, now_sec) catch |err| {
            bundle.bytes.items.len = decoded_start;
            return err;
        };
    }
}

pub export fn sa_std_tls_client_config_add_ca_memory(config: u64, pem_ptr: ?[*]const u8, pem_len: u64) i32 {
    const cfg = configFromU64(config) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const n = u64ToUsize(pem_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pem = if (pem_ptr) |p| p[0..n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (pem.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    // Validate eagerly into a scratch bundle so malformed PEM fails HERE,
    // loudly, instead of being silently dropped at connect time.
    var scratch: std.crypto.Certificate.Bundle = .empty;
    defer scratch.deinit(std.heap.page_allocator);
    addCertsFromMemory(&scratch, pem, std.Io.Clock.real.now(sio.io()).toSeconds()) catch |err| {
        return switch (err) {
            error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            else => SA_STD_ERR_INVALID_ARGUMENT,
        };
    };
    if (scratch.bytes.items.len == 0) return SA_STD_ERR_INVALID_ARGUMENT; // no usable certificate in the PEM
    cfg.ca_pem.appendSlice(std.heap.page_allocator, pem) catch return SA_STD_ERR_NO_MEMORY;
    return SA_STD_OK;
}

/// THE explicitly named verification kill switch. enabled != 0 means the
/// resulting connections perform NO certificate verification and NO hostname
/// check (std `.no_verification` for both): anyone able to intercept the
/// connection can impersonate the peer. It exists for controlled test rigs;
/// it is never implied by any other setting.
pub export fn sa_std_tls_client_config_set_insecure_no_verification(config: u64, enabled: u32) i32 {
    const cfg = configFromU64(config) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    cfg.insecure_no_verification = enabled != 0;
    return SA_STD_OK;
}

/// Expect a self-signed peer certificate: the certificate must still be
/// well-formed, in date, and correctly self-signed; only CA chain building
/// is skipped. Mutually exclusive with the insecure switch and with
/// per-config CA anchors (both are rejected at connect time, not ignored).
pub export fn sa_std_tls_client_config_set_verify_self_signed(config: u64, enabled: u32) i32 {
    const cfg = configFromU64(config) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    cfg.verify_self_signed = enabled != 0;
    return SA_STD_OK;
}

/// Runs the TLS handshake for an already-connected stream and fills `h`.
/// On error the caller performs handle cleanup; a partially built bundle is
/// released here (owns_bundle is reset so the caller never double-frees).
fn performHandshake(h: *TlsClientHandle, verify_name: []const u8, cfg: ?*const TlsClientConfig) i32 {
    const gpa = std.heap.page_allocator;
    var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
    sio.io().random(&entropy);

    if (cfg) |c| {
        if (c.insecure_no_verification) {
            if (c.verify_self_signed or c.server_name != null) return SA_STD_ERR_INVALID_ARGUMENT;
            h.client = std.crypto.tls.Client.init(&h.stream_reader.interface, &h.stream_writer.interface, .{
                .host = .no_verification,
                .ca = .no_verification,
                .read_buffer = &h.tls_read_buf,
                .write_buffer = &h.tls_write_buf,
                .entropy = &entropy,
                .realtime_now = std.Io.Clock.real.now(sio.io()),
                .allow_truncation_attacks = true,
            }) catch |err| return mapTlsErr(err);
            return SA_STD_OK;
        }
        if (c.verify_self_signed) {
            if (c.ca_files.items.len != 0 or c.ca_pem.items.len != 0) return SA_STD_ERR_INVALID_ARGUMENT;
            h.client = std.crypto.tls.Client.init(&h.stream_reader.interface, &h.stream_writer.interface, .{
                .host = .{ .explicit = verify_name },
                .ca = .self_signed,
                .read_buffer = &h.tls_read_buf,
                .write_buffer = &h.tls_write_buf,
                .entropy = &entropy,
                .realtime_now = std.Io.Clock.real.now(sio.io()),
                .allow_truncation_attacks = true,
            }) catch |err| return mapTlsErr(err);
            return SA_STD_OK;
        }
        if (c.ca_files.items.len != 0 or c.ca_pem.items.len != 0) {
            // Per-connection bundle: OS trust store + this config's anchors.
            // Built outside the singleton mutex; the handle owns it and
            // close() releases it (owns_bundle).
            var b: std.crypto.Certificate.Bundle = .empty;
            b.rescan(gpa, sio.io(), std.Io.Clock.real.now(sio.io())) catch |err| {
                b.deinit(gpa);
                return mapBundleErr(err);
            };
            const now = std.Io.Clock.real.now(sio.io());
            for (c.ca_files.items) |path| {
                b.addCertsFromFilePathAbsolute(gpa, sio.io(), now, path) catch |err| {
                    b.deinit(gpa);
                    return mapBundleErr(err);
                };
            }
            if (c.ca_pem.items.len != 0) {
                addCertsFromMemory(&b, c.ca_pem.items, std.Io.Clock.real.now(sio.io()).toSeconds()) catch |err| {
                    b.deinit(gpa);
                    return switch (err) {
                        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
                        else => SA_STD_ERR_INVALID_ARGUMENT,
                    };
                };
            }
            h.bundle = b;
            h.owns_bundle = true;
            h.client = std.crypto.tls.Client.init(&h.stream_reader.interface, &h.stream_writer.interface, .{
                .host = .{ .explicit = verify_name },
                .ca = .{ .bundle = .{
                    .gpa = gpa,
                    .io = sio.io(),
                    .lock = &h.bundle_lock,
                    .bundle = &h.bundle,
                } },
                .read_buffer = &h.tls_read_buf,
                .write_buffer = &h.tls_write_buf,
                .entropy = &entropy,
                .realtime_now = std.Io.Clock.real.now(sio.io()),
                .allow_truncation_attacks = true,
            }) catch |err| {
                h.bundle.deinit(gpa);
                h.owns_bundle = false;
                return mapTlsErr(err);
            };
            return SA_STD_OK;
        }
    }

    // Default path: singleton bundle snapshot, handshake under the mutex
    // (identical discipline to sa_std_tls_client_connect).
    bundle_mutex.lockUncancelable(sio.io());
    defer bundle_mutex.unlock(sio.io());
    h.bundle = (ensureBundleLocked() catch |err| return mapBundleErr(err)).*;
    h.client = std.crypto.tls.Client.init(&h.stream_reader.interface, &h.stream_writer.interface, .{
        .host = .{ .explicit = verify_name },
        .ca = .{ .bundle = .{
            .gpa = gpa,
            .io = sio.io(),
            .lock = &h.bundle_lock,
            .bundle = &h.bundle,
        } },
        .read_buffer = &h.tls_read_buf,
        .write_buffer = &h.tls_write_buf,
        .entropy = &entropy,
        .realtime_now = std.Io.Clock.real.now(sio.io()),
        .allow_truncation_attacks = true,
    }) catch |err| return mapTlsErr(err);
    return SA_STD_OK;
}

/// Shared body of connect_config / start_tls: takes ownership of `stream`
/// (closes it on every failure path) and produces a connected handle.
fn connectImpl(stream: std.Io.net.Stream, host_slice: []const u8, port: u32, cfg: ?*TlsClientConfig, slot: *u64) i32 {
    const host_owned = std.heap.page_allocator.dupe(u8, host_slice) catch {
        stream.close(sio.io());
        return SA_STD_ERR_NO_MEMORY;
    };
    const h = std.heap.page_allocator.create(TlsClientHandle) catch {
        std.heap.page_allocator.free(host_owned);
        stream.close(sio.io());
        return SA_STD_ERR_NO_MEMORY;
    };
    h.* = .{
        .stream = stream,
        .stream_reader = undefined,
        .stream_writer = undefined,
        .client = undefined,
        .bundle = undefined,
        .bundle_lock = .init,
        .sock_read_buf = undefined,
        .sock_write_buf = undefined,
        .tls_read_buf = undefined,
        .tls_write_buf = undefined,
        .host = host_owned,
        .port = port,
    };
    h.stream_reader = stream.reader(sio.io(), &h.sock_read_buf);
    h.stream_writer = stream.writer(sio.io(), &h.sock_write_buf);
    const verify_name: []const u8 = if (cfg) |c| (c.server_name orelse host_owned) else host_owned;
    const rc = performHandshake(h, verify_name, cfg);
    if (rc != SA_STD_OK) {
        if (h.owns_bundle) h.bundle.deinit(std.heap.page_allocator);
        std.heap.page_allocator.free(host_owned);
        stream.close(sio.io());
        std.heap.page_allocator.destroy(h);
        return rc;
    }
    slot.* = @intFromPtr(h);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_connect_config(host_ptr: ?[*]const u8, host_len: u64, port: u32, config: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const host_n = u64ToUsize(host_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const host_slice = if (host_ptr) |p| p[0..host_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (host_slice.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if (port == 0 or port > 65535) return SA_STD_ERR_INVALID_ARGUMENT;
    const cfg = if (config == 0) null else configFromU64(config);
    if (config != 0 and cfg == null) return SA_STD_ERR_INVALID_ARGUMENT;
    const stream = dialHost(host_slice, @intCast(port)) catch |err| return mapDialErr(err);
    return connectImpl(stream, host_slice, port, cfg, slot);
}

/// STARTTLS upgrade: wraps an already-connected plaintext TCP stream (given
/// by raw fd) in TLS and returns a normal tls_client handle. The fd's
/// ownership transfers to this call: it is closed on failure and owned by
/// the returned handle on success. `host` is NOT dialed -- it is the
/// verification name (and SNI), typically paired with a config server-name
/// override. POSIX only; on Windows the WSA handle model does not fit the
/// i32 fd convention and this returns SA_STD_ERR_UNSUPPORTED.
pub export fn sa_std_tls_client_start_tls(fd: i32, host_ptr: ?[*]const u8, host_len: u64, config: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (comptime builtin.os.tag == .windows) return SA_STD_ERR_UNSUPPORTED;
    if (fd < 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const host_n = u64ToUsize(host_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const host_slice = if (host_ptr) |p| p[0..host_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (host_slice.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const cfg = if (config == 0) null else configFromU64(config);
    if (config != 0 and cfg == null) return SA_STD_ERR_INVALID_ARGUMENT;
    const addr = std.Io.net.IpAddress.parseIp4("0.0.0.0", 0) catch return SA_STD_ERR_IO;
    const stream = std.Io.net.Stream{ .socket = .{ .handle = @intCast(fd), .address = addr } };
    return connectImpl(stream, host_slice, 0, cfg, slot);
}

/// The peer certificate is NOT available on this backend: std.crypto.tls
/// .Client verifies the chain during the handshake and then discards the
/// certificate, so there is nothing truthful to report after the fact.
/// This entry point exists so consumers can feature-probe one uniform
/// name; it always returns SA_STD_ERR_UNSUPPORTED. Use the OpenSSL shaped
/// client's sa_std_tls_shaped_peer_cert_chain_json for the decoded chain.
pub export fn sa_std_tls_client_peer_cert_json(handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    return SA_STD_ERR_UNSUPPORTED;
}

// ---- buffer handle registry (same shape as sa_tls_server.zig) --------------

var string_registry_mutex = std.Io.Mutex.init;
var string_registry = std.ArrayListUnmanaged(?[]u8).empty;

fn registerString(bytes: []u8, slot: *u64) i32 {
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
    var i: usize = 0;
    while (i < string_registry.items.len) : (i += 1) {
        if (string_registry.items[i] == null) {
            string_registry.items[i] = bytes;
            slot.* = @intCast(i + 1);
            return SA_STD_OK;
        }
    }
    string_registry.append(std.heap.page_allocator, bytes) catch {
        std.heap.page_allocator.free(bytes);
        return SA_STD_ERR_NO_MEMORY;
    };
    slot.* = @intCast(string_registry.items.len);
    return SA_STD_OK;
}

fn takeString(handle: u64) ?[]u8 {
    if (handle == 0) return null;
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return null;
    return string_registry.items[idx];
}

pub export fn sa_std_tls_client_buffer_data(handle: u64) ?[*]const u8 {
    const s = takeString(handle) orelse return null;
    return s.ptr;
}

pub export fn sa_std_tls_client_buffer_len(handle: u64) u64 {
    const s = takeString(handle) orelse return 0;
    return @intCast(s.len);
}

pub export fn sa_std_tls_client_buffer_free(handle: u64) i32 {
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
    if (handle == 0) return SA_STD_OK;
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const entry = string_registry.items[idx] orelse return SA_STD_ERR_INVALID_ARGUMENT;
    string_registry.items[idx] = null;
    std.heap.page_allocator.free(entry);
    return SA_STD_OK;
}

// ============================================================================
// Unit tests.
// ============================================================================

const testing = std.testing;

test "supported is always 1: pure-Zig backend, no dlopen" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_supported(&flag));
    try testing.expectEqual(@as(u32, 1), flag);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_supported(null));
}

test "connect rejects bad arguments without touching the network" {
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect(null, 0, 443, &h));
    try testing.expectEqual(@as(u64, 0), h);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect("example.com".ptr, 0, 443, &h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect("example.com".ptr, 11, 0, &h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect("example.com".ptr, 11, 65536, &h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect("example.com".ptr, 11, 443, null));
    try testing.expectEqual(@as(u64, 0), h);
}

test "read/write/close contract on the invalid (0) handle" {
    var buf: [4]u8 = undefined;
    var n: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_read(0, &buf, buf.len, &n));
    try testing.expectEqual(@as(u64, 0), n);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_write(0, "x".ptr, 1, &n));
    try testing.expectEqual(@as(u64, 0), n);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_read(0, null, 4, &n));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_read(0, &buf, 4, null));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_close(0));
}

test "add_ca_file rejects bad paths" {
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_add_ca_file(null, 0));
    const empty = "";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_add_ca_file(empty.ptr, 0));
    const rel = "relative/ca.pem";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_add_ca_file(rel.ptr, rel.len));
    const missing = "/nonexistent-dir-xyz/ca.pem";
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_tls_client_add_ca_file(missing.ptr, missing.len));
}

test "status json + buffer trio round-trips" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_status_json(&handle));
    try testing.expect(handle != 0);
    const ptr = sa_std_tls_client_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_tls_client_buffer_len(handle);
    try testing.expect(len != 0);
    const json = ptr[0..@as(usize, @intCast(len))];
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"tls_client\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"backend\":\"std.crypto.tls\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"supported\":true") != null);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_buffer_free(handle));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_buffer_free(handle));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_tls_client_buffer_data(0));
    try testing.expectEqual(@as(u64, 0), sa_std_tls_client_buffer_len(0));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_buffer_free(0));
}

test "export invariants: err codes negative, OK is 0" {
    try testing.expectEqual(@as(i32, 0), SA_STD_OK);
    try testing.expect(SA_STD_ERR_NO_MEMORY < 0);
    try testing.expect(SA_STD_ERR_INVALID_ARGUMENT < 0);
    try testing.expect(SA_STD_ERR_UNSUPPORTED < 0);
    try testing.expect(SA_STD_ERR_IO < 0);
    try testing.expectEqual(@as(i32, -100), SA_STD_ERR_TLS_VERIFY);
}

fn makeSelfSignedCert(allocator: std.mem.Allocator, dirpath: []const u8) !struct { cert: []u8, key: []u8 } {
    const cert_path = try std.fs.path.join(allocator, &.{ dirpath, "cert.pem" });
    errdefer allocator.free(cert_path);
    const key_path = try std.fs.path.join(allocator, &.{ dirpath, "key.pem" });
    errdefer allocator.free(key_path);
    // openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 1
    //             -nodes -subj "/CN=localhost"
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path,
        "-out",    cert_path,
        "-days",   "1",   "-nodes", "-subj", "/CN=localhost",
    };
    var child = sio.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return error.OpensslSpawnFailed;
    switch (term) {
        .exited => |code| if (code != 0) return error.OpensslCertFailed,
        else => return error.OpensslCertAbnormal,
    }
    return .{ .cert = cert_path, .key = key_path };
}

test "loopback: real handshake vs openssl s_server with CA-pinned verification" {
    // The repo's OpenSSL-backed tls_server FFI cannot dlopen versioned-only
    // libssl symbols on this host, so the loopback peer is the openssl CLI
    // server instead. The client side still goes through the real exported
    // FFI with REAL certificate verification: the self-signed cert is pinned
    // via add_ca_file and the hostname is verified against CN=localhost.
    // No .no_verification anywhere on this path.
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);

    // Pin the self-signed CA into the singleton bundle (real verification).
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_add_ca_file(paths.cert.ptr, paths.cert.len));

    // Grab a free loopback port, then hand it to s_server.
    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    const port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    listener.deinit(sio.io());

    const accept_arg = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
    defer allocator.free(accept_arg);
    const server_args = [_][]const u8{
        "openssl", "s_server",
        "-accept", accept_arg,
        "-cert",   paths.cert,
        "-key",    paths.key,
        "-naccept", "1",
        "-quiet",
    };
    var server = sio.Child.init(&server_args, allocator);
    server.stdin_behavior = .Pipe;
    server.stdout_behavior = .Pipe;
    server.stderr_behavior = .Ignore;
    try server.spawn();
    errdefer _ = server.kill() catch {};

    // Connect with retries: s_server needs a moment to bind.
    const host = "localhost";
    var handle: u64 = 0;
    var connected = false;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        const rc = sa_std_tls_client_connect(host.ptr, host.len, port, &handle);
        if (rc == SA_STD_OK) {
            connected = true;
            break;
        }
        // Only retry dial-level failures; a -100 here would be a real
        // verification bug and must fail the test, not loop.
        try testing.expectEqual(@as(i32, SA_STD_ERR_IO), rc);
        std.Io.sleep(sio.io(), .fromMilliseconds(50), .awake) catch {};
    }
    try testing.expect(connected);
    try testing.expect(handle != 0);
    errdefer _ = sa_std_tls_client_close(handle);

    // Server -> client: feed s_server's stdin, read it back over TLS.
    const server_msg = "server-hello\n";
    try server.stdin.?.writeAll(server_msg);
    var got_buf: [64]u8 = undefined;
    var got_total: usize = 0;
    while (got_total < server_msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_read(handle, got_buf[got_total..].ptr, got_buf.len - got_total, &n));
        if (n == 0) break; // clean EOF
        got_total += @as(usize, @intCast(n));
    }
    try testing.expectEqualStrings(server_msg, got_buf[0..got_total]);

    // Client -> server: write over TLS, expect it on s_server's stdout.
    const client_msg = "client-ping";
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_write(handle, client_msg.ptr, client_msg.len, &written));
    try testing.expectEqual(@as(u64, client_msg.len), written);

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_close(handle));

    // -naccept 1: s_server exits once our connection closes; its stdout must
    // carry the plaintext we sent. Read before wait(): wait() closes the
    // stdio pipes (cleanupStreams).
    const echoed = try server.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(echoed);
    const term = try server.wait();
    switch (term) {
        .exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.ServerAbnormalExit,
    }
    try testing.expect(std.mem.indexOf(u8, echoed, client_msg) != null);
}

test "public internet: handshake with example.com:443 against the OS trust store" {
    // Graceful skip when there is no usable network path; a verification
    // failure (-100) is a real bug and fails the test. The HTTP GET after the
    // handshake is best-effort: the handshake itself is the assertion.
    const host = "example.com";
    var handle: u64 = 0;
    const rc = sa_std_tls_client_connect(host.ptr, host.len, 443, &handle);
    if (rc == SA_STD_ERR_IO) return; // no network: skip, don't fail
    try testing.expectEqual(@as(i32, SA_STD_OK), rc);
    defer _ = sa_std_tls_client_close(handle);
    try testing.expect(handle != 0);

    const req = "GET / HTTP/1.0\r\nHost: example.com\r\nConnection: close\r\n\r\n";
    var written: u64 = 0;
    if (sa_std_tls_client_write(handle, req.ptr, req.len, &written) != SA_STD_OK) return;
    if (written != req.len) return;

    var head: [512]u8 = undefined;
    var head_len: usize = 0;
    var total: u64 = 0;
    var buf: [4096]u8 = undefined;
    while (true) {
        var n: u64 = 0;
        if (sa_std_tls_client_read(handle, &buf, buf.len, &n) != SA_STD_OK) return;
        if (n == 0) break; // clean EOF
        const room = head.len - head_len;
        const take: usize = @min(@as(usize, @intCast(n)), room);
        @memcpy(head[head_len..][0..take], buf[0..take]);
        head_len += take;
        total += n;
        if (total > 256 * 1024) break;
    }
    try testing.expect(total > 0);
    try testing.expect(std.mem.indexOf(u8, head[0..head_len], "HTTP/") != null);
}

// ---- configuration object surface (loopback only) -----------------------------

fn spawnPlainServer(allocator: std.mem.Allocator, cert: []const u8, key: []const u8, port: u16) !sio.Child {
    const accept_arg = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
    defer allocator.free(accept_arg);
    const args = [_][]const u8{
        "openssl", "s_server",
        "-accept", accept_arg,
        "-cert",   cert,
        "-key",    key,
        "-naccept", "1",
        "-quiet",
    };
    var server = sio.Child.init(&args, allocator);
    server.stdin_behavior = .Pipe;
    server.stdout_behavior = .Pipe;
    server.stderr_behavior = .Ignore;
    try server.spawn();
    return server;
}

fn freePort() !u16 {
    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    const port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    listener.deinit(sio.io());
    return port;
}

fn connectConfigRetry(host: []const u8, port: u16, cfg: u64) i32 {
    var handle: u64 = 0;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        const rc = sa_std_tls_client_connect_config(host.ptr, host.len, port, cfg, &handle);
        if (rc == SA_STD_OK) {
            _ = sa_std_tls_client_close(handle);
            return SA_STD_OK;
        }
        if (rc != SA_STD_ERR_IO) return rc;
        std.Io.sleep(sio.io(), .fromMilliseconds(50), .awake) catch {};
    }
    return SA_STD_ERR_IO;
}

test "config object: lifecycle and argument validation without network" {
    var cfg: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg));
    try testing.expect(cfg != 0);
    defer _ = sa_std_tls_client_config_free(cfg);

    // Handle 0 is invalid for every setter.
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_config_set_server_name(0, "x", 1));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_config_add_ca_memory(0, "x", 1));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_config_set_insecure_no_verification(0, 1));
    // free(0) is a no-op success, matching close() conventions.
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_free(0));

    // server_name set + clear.
    const name = "example.internal";
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_server_name(cfg, name.ptr, name.len));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_server_name(cfg, null, 0));

    // Relative CA paths are rejected at set time (bundle API contract).
    const rel = "certs/ca.pem";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_config_add_ca_file(cfg, rel.ptr, rel.len));

    // Malformed memory CA fails at set time, not silently at connect time.
    const junk = "this is not a pem file";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_config_add_ca_memory(cfg, junk.ptr, junk.len));

    // peer_cert_json: the std backend cannot produce it -- explicit
    // UNSUPPORTED probe result, INVALID for the null handle.
    var out: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_peer_cert_json(0, &out));
    try testing.expectEqual(@as(i32, SA_STD_ERR_UNSUPPORTED), sa_std_tls_client_peer_cert_json(1, &out));
}

test "config object: memory CA + server_name override connects by IP; unpinned fails" {
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, paths.cert, 1 << 20);
    defer allocator.free(pem);

    // (1) Per-config memory CA is accepted eagerly.
    var cfg: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg));
    defer _ = sa_std_tls_client_config_free(cfg);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_add_ca_memory(cfg, pem.ptr, pem.len));
    const sni = "localhost";
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_server_name(cfg, sni.ptr, sni.len));

    var port = try freePort();
    var server = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server.kill() catch {};
    // Dial by IP; the certificate names "localhost" only, so this succeeds
    // solely because the config's server_name drives SNI + verification.
    try testing.expectEqual(@as(i32, SA_STD_OK), connectConfigRetry("127.0.0.1", port, cfg));
    _ = server.wait() catch {};

    // (2) The CA-file variant of the same config also connects.
    var cfg2: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg2));
    defer _ = sa_std_tls_client_config_free(cfg2);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_add_ca_file(cfg2, paths.cert.ptr, paths.cert.len));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_server_name(cfg2, sni.ptr, sni.len));
    port = try freePort();
    var server2 = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server2.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_OK), connectConfigRetry("127.0.0.1", port, cfg2));
    _ = server2.wait() catch {};

    // (3) No pin at all: the self-signed peer must fail verification (-100),
    // never silently connect.
    port = try freePort();
    var server3 = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server3.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_ERR_TLS_VERIFY), connectConfigRetry("localhost", port, 0));
    _ = server3.wait() catch {};
}

test "config object: insecure switch and self-signed mode are separate, conflicts are loud" {
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);

    // Insecure switch alone: connects to the unpinned self-signed server.
    var cfg: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg));
    defer _ = sa_std_tls_client_config_free(cfg);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_insecure_no_verification(cfg, 1));
    var port = try freePort();
    var server = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_OK), connectConfigRetry("127.0.0.1", port, cfg));
    _ = server.wait() catch {};

    // Self-signed mode (NOT a bypass): also connects, by name.
    var cfg2: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg2));
    defer _ = sa_std_tls_client_config_free(cfg2);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_verify_self_signed(cfg2, 1));
    port = try freePort();
    var server2 = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server2.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_OK), connectConfigRetry("localhost", port, cfg2));
    _ = server2.wait() catch {};

    // Insecure + server_name is a contradiction (no_verification sends no
    // SNI): loud INVALID_ARGUMENT, not a silent ignore.
    var cfg3: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg3));
    defer _ = sa_std_tls_client_config_free(cfg3);
    _ = sa_std_tls_client_config_set_insecure_no_verification(cfg3, 1);
    const nm = "localhost";
    _ = sa_std_tls_client_config_set_server_name(cfg3, nm.ptr, nm.len);
    port = try freePort();
    var server3 = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server3.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), connectConfigRetry("127.0.0.1", port, cfg3));
    _ = server3.wait() catch {};
}

test "start_tls upgrades a plaintext connection after a STARTTLS preamble" {
    if (comptime builtin.os.tag == .windows) return;
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, paths.cert, 1 << 20);
    defer allocator.free(pem);

    // Server side: our own OpenSSL tls_server ctx on a listener thread.
    const srv = @import("sa_tls_server.zig");
    var sup: u32 = 0;
    _ = srv.sa_std_tls_server_supported(&sup);
    if (sup == 0) return; // host cannot resolve OpenSSL symbols; nothing to prove against
    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), srv.sa_std_tls_server_ctx_create(paths.cert.ptr, paths.cert.len, paths.key.ptr, paths.key.len, &ctx));
    defer _ = srv.sa_std_tls_server_ctx_free(ctx);

    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };

    const Arg = struct { ctx: u64, lst: *std.Io.net.Server, accept_rc: i32 = -999 };
    var arg: Arg = .{ .ctx = ctx, .lst = &listener };
    const Runner = struct {
        fn run(a: *Arg) void {
            const tsrv = @import("sa_tls_server.zig");
            var stream = a.lst.accept(sio.io()) catch return;
            defer stream.close(sio.io());
            // Plaintext preamble: read one line BYTE BY BYTE off the raw
            // fd. A buffered reader could swallow ClientHello bytes that
            // already arrived, starving the TLS handshake that follows.
            var line_buf: [16]u8 = undefined;
            var line_len: usize = 0;
            while (line_len < line_buf.len) {
                var b: [1]u8 = undefined;
                const n = std.posix.read(stream.socket.handle, &b) catch return;
                if (n == 0) return;
                line_buf[line_len] = b[0];
                line_len += 1;
                if (b[0] == '\n') break;
            }
            if (!std.mem.eql(u8, line_buf[0..line_len], "STARTTLS\n")) return;
            var ssl: u64 = 0;
            a.accept_rc = tsrv.sa_std_tls_server_accept(a.ctx, stream.socket.handle, &ssl);
            if (a.accept_rc != 0) return;
            var buf: [64]u8 = undefined;
            var n: u64 = 0;
            if (tsrv.sa_std_tls_server_read(ssl, &buf, buf.len, &n) == 0) {
                _ = tsrv.sa_std_tls_server_write(ssl, &buf, n, &n);
            }
            _ = tsrv.sa_std_tls_server_close(ssl);
        }
    };
    var thread = try std.Thread.spawn(.{}, Runner.run, .{&arg});

    // Client side: plain TCP, preamble, then upgrade in place.
    const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", port);
    var plain = try addr.connect(sio.io(), .{ .mode = .stream });
    var wb: [64]u8 = undefined;
    var wr = plain.writer(sio.io(), &wb);
    try wr.interface.writeAll("STARTTLS\n");
    try wr.interface.flush();

    var cfg: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg));
    defer _ = sa_std_tls_client_config_free(cfg);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_add_ca_memory(cfg, pem.ptr, pem.len));

    const host = "localhost";
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_start_tls(plain.socket.handle, host.ptr, host.len, cfg, &handle));
    try testing.expect(handle != 0);

    const msg = "post-upgrade-ping";
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_write(handle, msg.ptr, msg.len, &written));
    try testing.expectEqual(@as(u64, msg.len), written);
    var echo: [64]u8 = undefined;
    var got: usize = 0;
    while (got < msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_read(handle, echo[got..].ptr, echo.len - got, &n));
        if (n == 0) break;
        got += @intCast(n);
    }
    try testing.expectEqualStrings(msg, echo[0..got]);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_close(handle));
    thread.join();
    try testing.expectEqual(@as(i32, 0), arg.accept_rc);
}
