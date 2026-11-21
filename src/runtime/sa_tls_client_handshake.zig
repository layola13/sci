const std = @import("std");
const sa_std = @import("sa_tls_client.zig");
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_tls_client.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_NO_MEMORY = @import("sa_tls_client.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_OK = @import("sa_tls_client.zig").SA_STD_OK;
const TlsClientConfig = @import("sa_tls_client.zig").TlsClientConfig;
const TlsClientHandle = @import("sa_tls_client.zig").TlsClientHandle;
const addCertsFromMemory = @import("sa_tls_client.zig").addCertsFromMemory;
const ensureBundleLocked = @import("sa_tls_client.zig").ensureBundleLocked;
const mapBundleErr = @import("sa_tls_client.zig").mapBundleErr;
const mapTlsErr = @import("sa_tls_client.zig").mapTlsErr;
const sa_std_tls_client_connect = @import("sa_tls_client.zig").sa_std_tls_client_connect;
const sio = @import("sa_tls_client.zig").sio;

pub fn performHandshake(h: *TlsClientHandle, verify_name: []const u8, cfg: ?*const TlsClientConfig) i32 {
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
    sa_std.bundle_mutex.lockUncancelable(sio.io());
    defer sa_std.bundle_mutex.unlock(sio.io());
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

pub fn connectImpl(stream: std.Io.net.Stream, host_slice: []const u8, port: u32, cfg: ?*TlsClientConfig, slot: *u64) i32 {
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
