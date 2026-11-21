// TLS-client runtime binding for the sci/sa_std platform layer.
test "sa_tls_client_tests" { std.testing.refAllDecls(@import("sa_tls_client_test.zig")); }
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
pub const builtin = @import("builtin");
pub const sio = @import("sio");

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_NO_MEMORY: i32 = -12;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
pub const SA_STD_ERR_IO: i32 = -5;
pub const SA_STD_ERR_TLS_VERIFY: i32 = -100;

// wasm32-wasi: usize is 32-bit, C ABI passes u64 lengths. Checked conversion.
pub fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

pub const TlsClientHandle = struct {
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

pub var bundle_mutex = std.Io.Mutex.init;
var ca_bundle: ?std.crypto.Certificate.Bundle = null;

/// Caller must hold bundle_mutex. Returns a pointer to the live singleton so
/// adders mutate the shared store; readers take a value copy while the lock is
/// held and must finish using it before the lock is released by the owner.
pub fn ensureBundleLocked() anyerror!*std.crypto.Certificate.Bundle {
    if (ca_bundle == null) {
        var b: std.crypto.Certificate.Bundle = .empty;
        errdefer b.deinit(std.heap.page_allocator);
        try b.rescan(std.heap.page_allocator, sio.io(), std.Io.Clock.real.now(sio.io()));
        ca_bundle = b;
    }
    return &ca_bundle.?;
}

pub fn mapBundleErr(err: anyerror) i32 {
    return switch (err) {
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        else => SA_STD_ERR_IO,
    };
}

/// Certificate-shaped failures -> SA_STD_ERR_TLS_VERIFY (-100); everything
/// else that can surface from a TLS operation -> IO (or NO_MEMORY).
pub fn mapTlsErr(err: anyerror) i32 {
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

pub const TlsClientConfig = @import("sa_tls_client_config.zig").TlsClientConfig;

pub const configFromU64 = @import("sa_tls_client_config.zig").configFromU64;

pub const sa_std_tls_client_config_new = @import("sa_tls_client_config.zig").sa_std_tls_client_config_new;

pub const sa_std_tls_client_config_free = @import("sa_tls_client_config.zig").sa_std_tls_client_config_free;

pub const sa_std_tls_client_config_set_server_name = @import("sa_tls_client_config.zig").sa_std_tls_client_config_set_server_name;

pub const sa_std_tls_client_config_add_ca_file = @import("sa_tls_client_config.zig").sa_std_tls_client_config_add_ca_file;

/// Decode PEM certificates into a bundle, following the exact algorithm of
/// std's own Bundle.addCertsFromFile (marker scan, base64 decode, parseCert
/// per certificate) but sourced from memory. Certificates std would skip
/// (unrecognized OID, expired) are skipped the same way; a decode failure
/// aborts with an error.
pub const addCertsFromMemory = @import("sa_tls_client_config.zig").addCertsFromMemory;

pub const sa_std_tls_client_config_add_ca_memory = @import("sa_tls_client_config.zig").sa_std_tls_client_config_add_ca_memory;

/// THE explicitly named verification kill switch. enabled != 0 means the
/// resulting connections perform NO certificate verification and NO hostname
/// check (std `.no_verification` for both): anyone able to intercept the
/// connection can impersonate the peer. It exists for controlled test rigs;
/// it is never implied by any other setting.
pub const sa_std_tls_client_config_set_insecure_no_verification = @import("sa_tls_client_config.zig").sa_std_tls_client_config_set_insecure_no_verification;

/// Expect a self-signed peer certificate: the certificate must still be
/// well-formed, in date, and correctly self-signed; only CA chain building
/// is skipped. Mutually exclusive with the insecure switch and with
/// per-config CA anchors (both are rejected at connect time, not ignored).
pub const sa_std_tls_client_config_set_verify_self_signed = @import("sa_tls_client_config.zig").sa_std_tls_client_config_set_verify_self_signed;

/// Runs the TLS handshake for an already-connected stream and fills `h`.
/// On error the caller performs handle cleanup; a partially built bundle is
/// released here (owns_bundle is reset so the caller never double-frees).
pub const performHandshake = @import("sa_tls_client_handshake.zig").performHandshake;

/// Shared body of connect_config / start_tls: takes ownership of `stream`
/// (closes it on every failure path) and produces a connected handle.
pub const connectImpl = @import("sa_tls_client_handshake.zig").connectImpl;

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
    // DEF-SCI-TLS-STARTTLS-NONSOCKET-ABORT: the fd must be an
    // already-connected socket. A non-socket fd (e.g. stdin) makes the
    // handshake's socket syscalls fail with ENOTSOCK, which the std.Io
    // runtime treats as a programmer bug and aborts on (SIGABRT) instead
    // of returning an error. Reject it up front with an error code.
    // getpeername succeeds only on a connected socket: ENOTSOCK for a
    // non-socket fd, ENOTCONN for an unconnected socket (both violate the
    // "already-connected TCP stream" contract in tls_client.sai).
    var peer: std.posix.sockaddr = undefined;
    var peer_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);
    std.posix.getpeername(fd, &peer, &peer_len) catch |err| return switch (err) {
        error.FileDescriptorNotASocket, error.SocketUnconnected => SA_STD_ERR_INVALID_ARGUMENT,
        else => SA_STD_ERR_IO,
    };
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

pub const testing = std.testing;

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

pub const makeSelfSignedCert = @import("sa_tls_client_test.zig").makeSelfSignedCert;



// ---- configuration object surface (loopback only) -----------------------------

pub const spawnPlainServer = @import("sa_tls_client_test.zig").spawnPlainServer;

pub const freePort = @import("sa_tls_client_test.zig").freePort;

pub const connectConfigRetry = @import("sa_tls_client_test.zig").connectConfigRetry;

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




