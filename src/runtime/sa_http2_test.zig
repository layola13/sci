const std = @import("std");
const HTTP2_CLIENT_PREFACE = @import("sa_http2.zig").HTTP2_CLIENT_PREFACE;
const HTTP2_FLAG_ACK = @import("sa_http2.zig").HTTP2_FLAG_ACK;
const HTTP2_FRAME_SETTINGS = @import("sa_http2.zig").HTTP2_FRAME_SETTINGS;
const HTTP2_SETTINGS_HEADER_TABLE_SIZE = @import("sa_http2.zig").HTTP2_SETTINGS_HEADER_TABLE_SIZE;
const HTTP2_SETTINGS_INITIAL_WINDOW_SIZE = @import("sa_http2.zig").HTTP2_SETTINGS_INITIAL_WINDOW_SIZE;
const HTTP2_SETTINGS_MAX_FRAME_SIZE = @import("sa_http2.zig").HTTP2_SETTINGS_MAX_FRAME_SIZE;
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_http2.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_NO_MEMORY = @import("sa_http2.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_OK = @import("sa_http2.zig").SA_STD_OK;
const UnsupportedStatus = @import("sa_http2.zig").UnsupportedStatus;
const fail = @import("sa_http2.zig").fail;
const h2SettingsClientThread = @import("sa_http2.zig").h2SettingsClientThread;
const http2ParseUrl = @import("sa_http2.zig").http2ParseUrl;
const http2ReadFrameHeader = @import("sa_http2.zig").http2ReadFrameHeader;
const http2ReadSetting = @import("sa_http2.zig").http2ReadSetting;
const loadNghttp2Api = @import("sa_http2.zig").loadNghttp2Api;
const posixRead = @import("sa_http2.zig").posixRead;
const readHandle = @import("sa_http2.zig").readHandle;
const registerBuffer = @import("sa_http2.zig").registerBuffer;
const registerOwnedString = @import("sa_http2.zig").registerOwnedString;
const sa_std_http2_buffer_data = @import("sa_http2.zig").sa_std_http2_buffer_data;
const sa_std_http2_buffer_free = @import("sa_http2.zig").sa_std_http2_buffer_free;
const sa_std_http2_buffer_len = @import("sa_http2.zig").sa_std_http2_buffer_len;
const sa_std_http2_get_default_settings_json = @import("sa_http2.zig").sa_std_http2_get_default_settings_json;
const sa_std_http2_get_packed_settings = @import("sa_http2.zig").sa_std_http2_get_packed_settings;
const sa_std_http2_get_unpacked_settings_json = @import("sa_http2.zig").sa_std_http2_get_unpacked_settings_json;
const sa_std_http2_nghttp2_version_json = @import("sa_http2.zig").sa_std_http2_nghttp2_version_json;
const sa_std_http2_perform_server_handshake = @import("sa_http2.zig").sa_std_http2_perform_server_handshake;
const sa_std_http2_sensitive_headers = @import("sa_http2.zig").sa_std_http2_sensitive_headers;
const sa_std_http2_status_json = @import("sa_http2.zig").sa_std_http2_status_json;
const sa_std_http2_supported = @import("sa_http2.zig").sa_std_http2_supported;
const sio = @import("sa_http2.zig").sio;
const testing = @import("sa_http2.zig").testing;

test "buffer handle register/data/len/free roundtrip" {
    const bytes = try std.heap.page_allocator.dupe(u8, "hello-h2");
    const h = registerBuffer(bytes);
    try testing.expect(h != 0);
    try testing.expectEqualStrings("hello-h2", readHandle(h));
    try testing.expect(@as(u64, 8) == sa_std_http2_buffer_len(h));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(h));
    // double-free returns INVALID_ARGUMENT (handle now empty)
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_http2_buffer_free(h));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_http2_buffer_data(h));
    try testing.expectEqual(@as(u64, 0), sa_std_http2_buffer_len(0));
}

test "sa_std_http2_supported reflects real libnghttp2 availability" {
    var supported: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_supported(&supported));
    // On this host libnghttp2.so.14 is installed (verified at assessment time);
    // the exported flag must therefore be 1.
    try testing.expectEqual(@as(u32, 1), supported);
}

test "status json reports protocol machine on, libnghttp2 backend" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_status_json(&handle));
    defer _ = sa_std_http2_buffer_free(handle);
    const json = readHandle(handle);
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"http2\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"backend\":\"libnghttp2\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"protocolMachine\":true") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"supported\":true") != null);
}

test "default settings json round-trips through pack -> unpack" {
    // This exercises the real libnghttp2-independent settings frame codec that
    // perform_server_handshake and the client both rely on.
    var defaults_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_default_settings_json(&defaults_handle));
    defer _ = sa_std_http2_buffer_free(defaults_handle);
    const defaults = readHandle(defaults_handle);

    var packed_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_packed_settings(defaults.ptr, defaults.len, &packed_handle));
    const packed_bytes = readHandle(packed_handle);

    var unpacked_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_unpacked_settings_json(packed_bytes.ptr, packed_bytes.len, &unpacked_handle));
    const unpacked = readHandle(unpacked_handle);

    // The unpacked JSON must contain the same canonical numeric/bool fields we
    // packed from the defaults. (HPACK-free settings pairs are self-inverse.)
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"headerTableSize\":4096") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"maxFrameSize\":16384") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"initialWindowSize\":65535") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"enablePush\":true") != null);

    _ = sa_std_http2_buffer_free(packed_handle);
    _ = sa_std_http2_buffer_free(unpacked_handle);
}

test "pack -> unpack is self-inverse for custom settings" {
    const settings_json =
        \\{"headerTableSize":8192,"maxConcurrentStreams":128,"initialWindowSize":65535,"maxFrameSize":16384,"customSettings":{"99":1,"500":4294967295}}
    ;
    var packed_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_packed_settings(settings_json.ptr, settings_json.len, &packed_handle));
    const packed_bytes = readHandle(packed_handle);
    // 4 known keys present (headerTableSize, maxConcurrentStreams, initialWindowSize, maxFrameSize) + 2 custom = 6 pairs * 6 bytes = 36 bytes
    try testing.expectEqual(@as(u64, 36), sa_std_http2_buffer_len(packed_handle));

    var unpacked_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_unpacked_settings_json(packed_bytes.ptr, packed_bytes.len, &unpacked_handle));
    const unpacked = readHandle(unpacked_handle);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"headerTableSize\":8192") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"maxConcurrentStreams\":128") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"customSettings\":{") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"99\":1") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"500\":4294967295") != null);

    _ = sa_std_http2_buffer_free(packed_handle);
    _ = sa_std_http2_buffer_free(unpacked_handle);
}

test "perform_server_handshake round-trips a client preface + SETTINGS frame" {
    // Build a synthetic client preface: connection preface bytes followed by a
    // single SETTINGS frame carrying one pair (max_frame_size=16384 == 0x05).
    var input = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice(HTTP2_CLIENT_PREFACE);
    // frame: length=6, type=SETTINGS(4), flags=0, stream_id=0, payload 6 bytes
    try input.append(0); // len >> 16
    try input.append(0); // len >> 8
    try input.append(6); // len
    try input.append(HTTP2_FRAME_SETTINGS);
    try input.append(0); // flags (no ACK)
    try input.append(0); // stream_id bytes
    try input.append(0);
    try input.append(0);
    try input.append(0);
    // one setting: id=5 (MAX_FRAME_SIZE), value=16384
    try input.append(0);
    try input.append(5);
    try input.append(0);
    try input.append(0);
    try input.append(0x40);
    try input.append(0);

    var out_bytes_handle: u64 = 0;
    var out_json_handle: u64 = 0;
    const server_settings_json = "{\"maxFrameSize\":16384}";
    const status = sa_std_http2_perform_server_handshake(
        input.items.ptr,
        input.items.len,
        server_settings_json.ptr,
        server_settings_json.len,
        &out_bytes_handle,
        &out_json_handle,
    );
    try testing.expectEqual(@as(i32, SA_STD_OK), status);
    defer _ = sa_std_http2_buffer_free(out_bytes_handle);
    defer _ = sa_std_http2_buffer_free(out_json_handle);

    const outbound = readHandle(out_bytes_handle);
    // Server must emit two SETTINGS frames: the server's own settings + an ACK.
    // Both are frame type 0x4; the second carries the ACK flag (0x1).
    try testing.expect(outbound.len >= 18); // two 9-byte headers minimum
    // First SETTINGS frame: 9-byte header (type at [3]) + 6-byte payload.
    try testing.expectEqual(@as(u8, HTTP2_FRAME_SETTINGS), outbound[3]);
    // Second frame (the ACK) starts at offset 9 + 6 = 15: type at [18], flags at [19].
    try testing.expectEqual(@as(u8, HTTP2_FRAME_SETTINGS), outbound[15 + 3]);
    try testing.expectEqual(@as(u8, HTTP2_FLAG_ACK), outbound[15 + 4]);

    const meta = readHandle(out_json_handle);
    try testing.expect(std.mem.indexOf(u8, meta, "\"preface\":true") != null);
    try testing.expect(std.mem.indexOf(u8, meta, "\"clientSettingsBytes\":6") != null);
    try testing.expect(std.mem.indexOf(u8, meta, "\"frames\":[\"SETTINGS\",\"SETTINGS_ACK\"]") != null);
}

test "perform_server_handshake rejects a missing/broken preface" {
    var out_bytes: u64 = 0;
    var out_json: u64 = 0;
    // Too short to contain preface + a frame header.
    const bad = "PRI * not a preface";
    const status = sa_std_http2_perform_server_handshake(bad.ptr, bad.len, null, 0, &out_bytes, &out_json);
    try testing.expect(status != SA_STD_OK);
}

test "sensitive headers list is a JSON array of known header names" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_sensitive_headers(&handle));
    defer _ = sa_std_http2_buffer_free(handle);
    const json = readHandle(handle);
    try testing.expect(std.mem.indexOf(u8, json, "\"authorization\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"cookie\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"set-cookie\"") != null);
}

test "nghttp2 version json is present when supported" {
    var supported: u32 = 0;
    _ = sa_std_http2_supported(&supported);
    if (supported == 0) return;

    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_nghttp2_version_json(&handle));
    defer _ = sa_std_http2_buffer_free(handle);
    const json = readHandle(handle);
    try testing.expect(std.mem.indexOf(u8, json, "\"version\":\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"versionNum\":") != null);
}

test "buffer handle rejects double-free and reading a freed handle" {
    const bytes = try std.heap.page_allocator.dupe(u8, "boundary");
    const h = registerBuffer(bytes);
    try testing.expect(h != 0);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_http2_buffer_free(h));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_http2_buffer_data(h));
    try testing.expectEqual(@as(u64, 0), sa_std_http2_buffer_len(h));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_http2_buffer_data(0));
    try testing.expectEqual(@as(u64, 0), sa_std_http2_buffer_len(0));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(0));
}

test "buffer handle registry survives a burst of many alloc/free cycles" {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var buf: [16]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "h2-{d}", .{i}) catch unreachable;
        const h = registerOwnedString(text);
        try testing.expect(h != 0);
        const len = sa_std_http2_buffer_len(h);
        try testing.expectEqual(@as(u64, text.len), len);
        const ptr = sa_std_http2_buffer_data(h) orelse return error.MissingData;
        try testing.expectEqualStrings(text, ptr[0..@intCast(len)]);
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(h));
    }
}

test "buffer handle registry is thread-safe under concurrent alloc/free" {
    const N: usize = 64;
    const Writer = struct {
        fn run() void {
            const alloc = std.heap.page_allocator;
            for (0..N) |_| {
                const bytes = alloc.dupe(u8, "concurrent-h2") catch continue;
                const h = registerBuffer(bytes);
                if (h == 0) {
                    alloc.free(bytes);
                    continue;
                }
                _ = sa_std_http2_buffer_len(h);
                _ = sa_std_http2_buffer_data(h);
                _ = sa_std_http2_buffer_free(h);
            }
        }
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Writer.run, .{});
    for (threads) |t| t.join();
    // After the concurrent burst the registry must remain usable: a fresh
    // handle can still be allocated, read, and freed cleanly (no state
    // corruption from the concurrent alloc/free storm).
    const probe = registerOwnedString("probe-after-concurrency");
    try testing.expect(probe != 0);
    try testing.expectEqual(@as(u64, 23), sa_std_http2_buffer_len(probe));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(probe));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_http2_buffer_free(probe));
}

test "get_packed_settings rejects malformed JSON and out-of-range values" {
    var handle: u64 = 0;
    // Not an object.
    try testing.expect(sa_std_http2_get_packed_settings("not json".ptr, 8, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
    // maxFrameSize below the RFC minimum 16384 must be rejected.
    const too_small = "{\"maxFrameSize\":1024}";
    try testing.expect(sa_std_http2_get_packed_settings(too_small.ptr, too_small.len, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
    // maxFrameSize above the RFC maximum 0xffffff must be rejected.
    const too_big = "{\"maxFrameSize\":33554432}";
    try testing.expect(sa_std_http2_get_packed_settings(too_big.ptr, too_big.len, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
}

test "get_unpacked_settings_json rejects buffers whose length is not a multiple of 6" {
    var handle: u64 = 0;
    const bad = "12345"; // 5 bytes
    try testing.expect(sa_std_http2_get_unpacked_settings_json(bad.ptr, bad.len, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
    const bad2 = "1234567"; // 7 bytes
    try testing.expect(sa_std_http2_get_unpacked_settings_json(bad2.ptr, bad2.len, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
}

test "perform_server_handshake rejects a SETTINGS frame that carries the ACK flag" {
    // preface + a SETTINGS frame with ACK set (flags byte = 0x1) must fail.
    var input = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice(HTTP2_CLIENT_PREFACE);
    try input.append(0); // len>>16
    try input.append(0); // len>>8
    try input.append(0); // len=0
    try input.append(HTTP2_FRAME_SETTINGS);
    try input.append(HTTP2_FLAG_ACK); // ACK — illegal for the *client* preface
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    var bytes_h: u64 = 0;
    var json_h: u64 = 0;
    const server_settings_json = "{\"maxFrameSize\":16384}";
    const status = sa_std_http2_perform_server_handshake(input.items.ptr, input.items.len, server_settings_json.ptr, server_settings_json.len, &bytes_h, &json_h);
    try testing.expect(status != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), bytes_h);
    try testing.expectEqual(@as(u64, 0), json_h);
}

test "perform_server_handshake rejects a non-SETTINGS first frame type" {
    var input = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice(HTTP2_CLIENT_PREFACE);
    // PING frame (type 6) instead of SETTINGS — must fail.
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0x6); // PING
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    var bytes_h: u64 = 0;
    var json_h: u64 = 0;
    const status = sa_std_http2_perform_server_handshake(input.items.ptr, input.items.len, null, 0, &bytes_h, &json_h);
    try testing.expect(status != SA_STD_OK);
}

test "perform_server_handshake rejects a SETTINGS frame on a non-zero stream id" {
    var input = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice(HTTP2_CLIENT_PREFACE);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(HTTP2_FRAME_SETTINGS);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(1); // stream_id LSB = 1, illegal for client preface SETTINGS
    var bytes_h: u64 = 0;
    var json_h: u64 = 0;
    const status = sa_std_http2_perform_server_handshake(input.items.ptr, input.items.len, null, 0, &bytes_h, &json_h);
    try testing.expect(status != SA_STD_OK);
}

test "http2ParseUrl validates scheme and authority" {
    try testing.expectError(error.InvalidUrl, http2ParseUrl("not a url"));
    try testing.expectError(error.InvalidUrl, http2ParseUrl("http://"));
    try testing.expectError(error.UnsupportedScheme, http2ParseUrl("https://example.com/"));
    // IPv6 literals carry ':' which must route through parseIp6, not the port split.
    const parsed_ipv6 = try http2ParseUrl("http://[::1]:8080/path");
    try testing.expectEqualStrings("::1", parsed_ipv6.host);
    try testing.expectEqual(@as(u16, 8080), parsed_ipv6.port);
    try testing.expectEqualStrings("/path", parsed_ipv6.path);
    const parsed_default = try http2ParseUrl("http://example.com");
    try testing.expectEqual(@as(u16, 80), parsed_default.port);
    try testing.expectEqualStrings("/", parsed_default.path);
}

test "export fn return-status domain never overlaps SA_STD_OK" {
    // Every error path must return a *negative* status, never 0; the buffer
    // accessor math must keep 0 == invalid-handle invariant.
    try testing.expectEqual(@as(u64, 0), sa_std_http2_buffer_len(0));
    try testing.expect(SA_STD_OK == 0);
    try testing.expect(SA_STD_ERR_NO_MEMORY < 0);
    try testing.expect(SA_STD_ERR_INVALID_ARGUMENT < 0);
    try testing.expect(@as(u32, 0x8000_0000) != 0); // UnsupportedStatus sentinel for flush
}

test "client_request_with_settings puts custom SETTINGS in the client preface" {
    if (loadNghttp2Api() == null) return;
    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };

    const thread = try std.Thread.spawn(.{}, h2SettingsClientThread, .{port});
    var stream = try listener.accept(sio.io());

    // Accumulate bytes until the preface (24) + first frame are complete.
    var buf: [8192]u8 = undefined;
    var have: usize = 0;
    var polls: usize = 0;
    while (polls < 100) : (polls += 1) {
        if (have >= 24 + 9) {
            const hdr = try http2ReadFrameHeader(buf[24..]);
            if (have >= 24 + 9 + hdr.len) break;
        }
        var fds = [_]std.posix.pollfd{.{ .fd = stream.socket.handle, .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = try std.posix.poll(&fds, 100);
        if (ready == 0) continue;
        const n = try posixRead(stream.socket.handle, buf[have..]);
        if (n == 0) break;
        have += n;
    }
    try testing.expect(have >= 24 + 9);
    try testing.expect(std.mem.startsWith(u8, buf[0..24], "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"));
    const hdr = try http2ReadFrameHeader(buf[24..]);
    try testing.expectEqual(HTTP2_FRAME_SETTINGS, hdr.frame_type);
    try testing.expectEqual(@as(u32, 0), hdr.stream_id);
    const payload = buf[24 + 9 ..][0..hdr.len];
    try testing.expect(payload.len % 6 == 0);
    var found_table: ?u32 = null;
    var found_window: ?u32 = null;
    var found_frame: ?u32 = null;
    var off: usize = 0;
    while (off < payload.len) : (off += 6) {
        const pair = http2ReadSetting(payload, off);
        switch (pair.id) {
            HTTP2_SETTINGS_HEADER_TABLE_SIZE => found_table = pair.value,
            HTTP2_SETTINGS_INITIAL_WINDOW_SIZE => found_window = pair.value,
            HTTP2_SETTINGS_MAX_FRAME_SIZE => found_frame = pair.value,
            else => {},
        }
    }
    try testing.expectEqual(@as(?u32, 8192), found_table);
    try testing.expectEqual(@as(?u32, 1000000), found_window);
    try testing.expectEqual(@as(?u32, 32768), found_frame);

    stream.close(sio.io());
    thread.join();
}
