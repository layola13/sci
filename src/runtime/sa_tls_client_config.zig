const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_tls_client.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_NO_MEMORY = @import("sa_tls_client.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_OK = @import("sa_tls_client.zig").SA_STD_OK;
const sio = @import("sa_tls_client.zig").sio;
const u64ToUsize = @import("sa_tls_client.zig").u64ToUsize;

pub const TlsClientConfig = struct {
    server_name: ?[]u8 = null,
    ca_files: std.ArrayListUnmanaged([]u8) = .empty,
    ca_pem: std.ArrayListUnmanaged(u8) = .empty,
    insecure_no_verification: bool = false,
    verify_self_signed: bool = false,
};

pub fn configFromU64(handle: u64) ?*TlsClientConfig {
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

pub fn addCertsFromMemory(bundle: *std.crypto.Certificate.Bundle, pem: []const u8, now_sec: i64) !void {
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

pub export fn sa_std_tls_client_config_set_insecure_no_verification(config: u64, enabled: u32) i32 {
    const cfg = configFromU64(config) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    cfg.insecure_no_verification = enabled != 0;
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_config_set_verify_self_signed(config: u64, enabled: u32) i32 {
    const cfg = configFromU64(config) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    cfg.verify_self_signed = enabled != 0;
    return SA_STD_OK;
}
