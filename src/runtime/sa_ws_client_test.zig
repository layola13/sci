const std = @import("std");
const SA_STD_ERR_IO = @import("sa_ws_client.zig").SA_STD_ERR_IO;
const SA_STD_ERR_TLS_VERIFY = @import("sa_ws_client.zig").SA_STD_ERR_TLS_VERIFY;
const SA_STD_OK = @import("sa_ws_client.zig").SA_STD_OK;
const WS_OPCODE_BINARY = @import("sa_ws_client.zig").WS_OPCODE_BINARY;
const WS_OPCODE_TEXT = @import("sa_ws_client.zig").WS_OPCODE_TEXT;
const boundPort = @import("sa_ws_client.zig").boundPort;
const primitives = @import("sa_ws_client.zig").primitives;
const sa_std_ws_client_add_ca_file = @import("sa_ws_client.zig").sa_std_ws_client_add_ca_file;
const sa_std_ws_client_buffer_data = @import("sa_ws_client.zig").sa_std_ws_client_buffer_data;
const sa_std_ws_client_buffer_free = @import("sa_ws_client.zig").sa_std_ws_client_buffer_free;
const sa_std_ws_client_buffer_len = @import("sa_ws_client.zig").sa_std_ws_client_buffer_len;
const sa_std_ws_client_close = @import("sa_ws_client.zig").sa_std_ws_client_close;
const sa_std_ws_client_connect = @import("sa_ws_client.zig").sa_std_ws_client_connect;
const sa_std_ws_client_recv = @import("sa_ws_client.zig").sa_std_ws_client_recv;
const sa_std_ws_client_send_binary = @import("sa_ws_client.zig").sa_std_ws_client_send_binary;
const sa_std_ws_client_send_text = @import("sa_ws_client.zig").sa_std_ws_client_send_text;
const sio = @import("sa_ws_client.zig").sio;
const tcpRead = @import("sa_ws_client.zig").tcpRead;
const tcpWriteAll = @import("sa_ws_client.zig").tcpWriteAll;
const testing = @import("sa_ws_client.zig").testing;
const tls_client = @import("sa_ws_client.zig").tls_client;

const SrvScript = struct {
    listener: std.Io.net.Server,
    err: *?anyerror,
};

fn srvReadFrame(stream: std.Io.net.Stream, fbuf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !struct { opcode: u8, payload: []u8 } {
    var tmp: [8192]u8 = undefined;
    while (true) {
        const fr = primitives.parseWsFrame(fbuf.items) catch |e| {
            if (e == error.Incomplete) {
                const n = try tcpRead(stream, tmp[0..]);
                if (n == 0) return error.Eof;
                try fbuf.appendSlice(alloc, tmp[0..n]);
                continue;
            }
            return e;
        };
        const payload = try alloc.dupe(u8, fbuf.items[fr.payload_start .. fr.payload_start + fr.payload_len]);
        errdefer alloc.free(payload);
        if (fr.masked) primitives.unmaskFrame(payload, fr.mask);
        const rest_len = fbuf.items.len - fr.frame_len;
        std.mem.copyForwards(u8, fbuf.items[0..rest_len], fbuf.items[fr.frame_len..]);
        fbuf.shrinkRetainingCapacity(rest_len);
        return .{ .opcode = fr.opcode, .payload = payload };
    }
}

fn srvSendFrame(stream: std.Io.net.Stream, opcode: u8, payload: []const u8, alloc: std.mem.Allocator) !void {
    // Servers MUST NOT mask.
    const out = try alloc.alloc(u8, 14 + payload.len);
    defer alloc.free(out);
    const n = try primitives.buildWsFrame(opcode, true, payload, null, out);
    try tcpWriteAll(stream, out[0..n]);
}

fn wsScriptedServer(listener: *std.Io.net.Server) !void {
    defer listener.deinit(sio.io());
    const alloc = testing.allocator;
    var stream = try listener.accept(sio.io());
    defer stream.close(sio.io());

    // --- HTTP Upgrade ---
    var req = std.ArrayListUnmanaged(u8).empty;
    defer req.deinit(alloc);
    var tmp: [4096]u8 = undefined;
    while (std.mem.indexOf(u8, req.items, "\r\n\r\n") == null) {
        if (req.items.len > 32768) return error.ReqTooLarge;
        const n = try tcpRead(stream, tmp[0..]);
        if (n == 0) return error.Eof;
        try req.appendSlice(alloc, tmp[0..n]);
    }
    var key: ?[]const u8 = null;
    var lines = std.mem.splitSequence(u8, req.items, "\r\n");
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), "sec-websocket-key")) {
            key = std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
    }
    const accept = try primitives.websocketAccept(key orelse return error.NoKey);
    var resp: [256]u8 = undefined;
    const resp_s = try std.fmt.bufPrint(&resp, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept});
    try tcpWriteAll(stream, resp_s);

    // --- scripted frame exchange ---
    var fbuf = std.ArrayListUnmanaged(u8).empty;
    defer fbuf.deinit(alloc);

    // 1. echo a text message
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0x1), fr.opcode);
        try testing.expectEqualStrings("hello-ws", fr.payload);
        try srvSendFrame(stream, 0x1, fr.payload, alloc);
    }
    // 2. echo a binary message
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0x2), fr.opcode);
        try testing.expectEqualStrings("bin-payload", fr.payload);
        try srvSendFrame(stream, 0x2, fr.payload, alloc);
    }
    // 3. server -> client ping; client must auto-pong with identical payload.
    // The client does NOT send anything before its next recv(), so the pong
    // is guaranteed to be the next client frame — no race.
    try srvSendFrame(stream, 0x9, "srv-ping", alloc);
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0xA), fr.opcode);
        try testing.expectEqualStrings("srv-ping", fr.payload);
    }
    // 4. liveness probe after the pong: the client's recv() must have
    // answered the ping internally and kept going.
    try srvSendFrame(stream, 0x1, "ping-done", alloc);
    // 5. echo another text message
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0x1), fr.opcode);
        try testing.expectEqualStrings("after-ping", fr.payload);
        try srvSendFrame(stream, 0x1, fr.payload, alloc);
    }
    // 6. expect the client's close, reply close
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0x8), fr.opcode);
        try testing.expect(fr.payload.len >= 2);
        try testing.expectEqual(@as(u16, 1000), std.mem.readInt(u16, fr.payload[0..2], .big));
        try testing.expectEqualStrings("done", fr.payload[2..]);
        try srvSendFrame(stream, 0x8, fr.payload, alloc);
    }
}

fn wsServerMain(ctx: SrvScript) void {
    var listener = ctx.listener;
    wsScriptedServer(&listener) catch |e| {
        ctx.err.* = e;
    };
}

fn recvText(h: u64, want_opcode: u32, want: []const u8) !void {
    var opcode: u32 = 0;
    var msg_h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_recv(h, &opcode, &msg_h));
    try testing.expectEqual(want_opcode, opcode);
    try testing.expect(msg_h != 0);
    const ptr = sa_std_ws_client_buffer_data(msg_h) orelse return error.MissingData;
    const got = ptr[0..@as(usize, @intCast(sa_std_ws_client_buffer_len(msg_h)))];
    try testing.expectEqualStrings(want, got);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_buffer_free(msg_h));
}

fn runClientScript(url: []const u8) !void {
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_connect(url.ptr, url.len, &h));
    try testing.expect(h != 0);
    errdefer _ = sa_std_ws_client_close(h, 1000, "", 0);

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_send_text(h, "hello-ws".ptr, 8));
    try recvText(h, WS_OPCODE_TEXT, "hello-ws");

    const bin = "bin-payload";
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_send_binary(h, bin.ptr, bin.len));
    try recvText(h, WS_OPCODE_BINARY, "bin-payload");

    // The server pings us after the binary echo; this recv() must answer
    // the ping internally and return the following "ping-done" message.
    try recvText(h, WS_OPCODE_TEXT, "ping-done");

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_send_text(h, "after-ping".ptr, 10));
    try recvText(h, WS_OPCODE_TEXT, "after-ping");

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_close(h, 1000, "done".ptr, 4));
}

const ViolationServer = struct {
    listener: *std.Io.net.Server,
    frame: []const u8,
    fn run(self: *ViolationServer) void {
        self.runImpl() catch {};
    }
    fn runImpl(self: *ViolationServer) !void {
        var stream = try self.listener.accept(sio.io());
        defer stream.close(sio.io());
        var buf: [8192]u8 = undefined;
        var total: usize = 0;
        while (total < buf.len) {
            const n = tcpRead(stream, buf[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
        }
        var key: []const u8 = "";
        var lines = std.mem.splitSequence(u8, buf[0..total], "\r\n");
        while (lines.next()) |line| {
            if (line.len > 18 and std.ascii.eqlIgnoreCase(line[0..18], "sec-websocket-key:")) {
                key = std.mem.trim(u8, line[18..], " \t");
            }
        }
        const accept = primitives.websocketAccept(key) catch return;
        var resp: [256]u8 = undefined;
        const resp_str = std.fmt.bufPrint(&resp,
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n",
            .{accept}) catch return;
        tcpWriteAll(stream, resp_str) catch return;
        tcpWriteAll(stream, self.frame) catch {};
        // Hold the connection briefly so the client reads the bad frame.
        std.Io.sleep(sio.io(), .fromMilliseconds(500), .awake) catch {};
    }
};

fn expectViolation(frame: []const u8) !void {
    const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(sio.io(), .{});
    defer listener.deinit(sio.io());
    const port = boundPort(&listener);
    var srv = ViolationServer{ .listener = &listener, .frame = frame };
    const t = try std.Thread.spawn(.{}, ViolationServer.run, .{&srv});
    defer t.join();

    const url = try std.fmt.allocPrint(testing.allocator, "ws://127.0.0.1:{d}/", .{port});
    defer testing.allocator.free(url);
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_connect(url.ptr, url.len, &h));
    errdefer _ = sa_std_ws_client_close(h, 1000, "", 0);
    var opcode: u32 = 0;
    var bh: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_ws_client_recv(h, &opcode, &bh));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_close(h, 1000, "", 0));
}

const wss_server_py =
    \\import socket, ssl, hashlib, base64, sys
    \\
    \\cert_path, key_path, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
    \\
    \\ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    \\ctx.load_cert_chain(cert_path, key_path)
    \\
    \\srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    \\srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    \\srv.bind(("127.0.0.1", port))
    \\srv.listen(4)
    \\print("READY", flush=True)
    \\
    \\GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    \\
    \\def read_frame(tls):
    \\    buf = b""
    \\    while True:
    \\        if len(buf) >= 2:
    \\            b0, b1 = buf[0], buf[1]
    \\            op = b0 & 0x0F
    \\            masked = (b1 & 0x80) != 0
    \\            ln = b1 & 0x7F
    \\            i = 2
    \\            ok = True
    \\            if ln == 126:
    \\                if len(buf) < 4:
    \\                    ok = False
    \\                else:
    \\                    ln = int.from_bytes(buf[2:4], "big")
    \\                    i = 4
    \\            elif ln == 127:
    \\                if len(buf) < 10:
    \\                    ok = False
    \\                else:
    \\                    ln = int.from_bytes(buf[2:10], "big")
    \\                    i = 10
    \\            if ok:
    \\                hlen = i + (4 if masked else 0)
    \\                if len(buf) >= hlen + ln:
    \\                    if masked:
    \\                        m = buf[i:i+4]
    \\                        pl = bytes(c ^ m[j % 4] for j, c in enumerate(buf[i+4:i+4+ln]))
    \\                    else:
    \\                        pl = buf[hlen:hlen+ln]
    \\                    return op, pl
    \\        chunk = tls.recv(65536)
    \\        if not chunk:
    \\            return None, None
    \\        buf += chunk
    \\
    \\def send_frame(tls, op, payload):
    \\    hdr = bytes([0x80 | op])
    \\    ln = len(payload)
    \\    if ln < 126:
    \\        hdr += bytes([ln])
    \\    elif ln < 65536:
    \\        hdr += bytes([126]) + ln.to_bytes(2, "big")
    \\    else:
    \\        hdr += bytes([127]) + ln.to_bytes(8, "big")
    \\    tls.sendall(hdr + payload)
    \\
    \\for _ in range(2):
    \\    try:
    \\        conn, _ = srv.accept()
    \\    except Exception:
    \\        break
    \\    try:
    \\        tls = ctx.wrap_socket(conn, server_side=True)
    \\    except Exception:
    \\        continue
    \\    try:
    \\        data = b""
    \\        while b"\r\n\r\n" not in data:
    \\            chunk = tls.recv(4096)
    \\            if not chunk:
    \\                raise Exception("eof")
    \\            data += chunk
    \\        key = None
    \\        for line in data.decode("latin1").split("\r\n"):
    \\            if line.lower().startswith("sec-websocket-key:"):
    \\                key = line.split(":", 1)[1].strip()
    \\        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    \\        tls.sendall(("HTTP/1.1 101 Switching Protocols\r\n"
    \\                     "Upgrade: websocket\r\n"
    \\                     "Connection: Upgrade\r\n"
    \\                     "Sec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())
    \\        op, pl = read_frame(tls)
    \\        if op == 1:
    \\            send_frame(tls, 1, pl)
    \\        try:
    \\            tls.settimeout(5)
    \\            read_frame(tls)
    \\        except Exception:
    \\            pass
    \\    except Exception:
    \\        pass
    \\    try:
    \\        tls.close()
    \\    except Exception:
    \\        pass
    \\
;


test "loopback wss:// via python ssl server, pinned CA and -100 without pin" {
    const alloc = testing.allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(alloc, ".");
    defer alloc.free(dirpath);

    const cert_path = try std.fs.path.join(alloc, &.{ dirpath, "cert.pem" });
    defer alloc.free(cert_path);
    const key_path = try std.fs.path.join(alloc, &.{ dirpath, "key.pem" });
    defer alloc.free(key_path);
    try makeSelfSigned(alloc, cert_path, key_path);

    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    const port = boundPort(&listener);
    listener.deinit(sio.io());
    const port_str = try std.fmt.allocPrint(alloc, "{d}", .{port});
    defer alloc.free(port_str);

    const py_path = try std.fs.path.join(alloc, &.{ dirpath, "wss_srv.py" });
    defer alloc.free(py_path);
    try tdir.writeFile(.{ .sub_path = "wss_srv.py", .data = wss_server_py });

    var child = sio.Child.init(&.{ "python3", py_path, cert_path, key_path, port_str }, alloc);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    errdefer _ = child.kill() catch {};

    // Wait for READY on the server's stdout.
    var ready: [16]u8 = undefined;
    var ready_len: usize = 0;
    while (ready_len < ready.len) {
        const n = try child.stdout.?.read(ready[ready_len..]);
        if (n == 0) return error.ServerDied;
        ready_len += n;
        if (std.mem.indexOf(u8, ready[0..ready_len], "\n") != null) break;
    }
    try testing.expect(std.mem.startsWith(u8, ready[0..ready_len], "READY"));

    const url = try std.fmt.allocPrint(alloc, "wss://localhost:{d}/secure", .{port});
    defer alloc.free(url);

    // Without the pinned CA the self-signed chain must fail verification.
    {
        var h: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_ERR_TLS_VERIFY), sa_std_ws_client_connect(url.ptr, url.len, &h));
        try testing.expectEqual(@as(u64, 0), h);
    }

    // Pin the CA, then the full wss round-trip works.
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_add_ca_file(cert_path.ptr, cert_path.len));
    {
        var h: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_connect(url.ptr, url.len, &h));
        errdefer _ = sa_std_ws_client_close(h, 1000, "", 0);
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_send_text(h, "hello-wss".ptr, 9));
        try recvText(h, WS_OPCODE_TEXT, "hello-wss");
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_close(h, 1000, "", 0));
    }

    const term = try child.wait();
    switch (term) {
        .exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.ServerAbnormalExit,
    }
}

fn makeSelfSigned(alloc: std.mem.Allocator, cert_path: []const u8, key_path: []const u8) !void {
    // NOTE: the OU keeps this test's subject distinct from the tls_client
    // tests' "/CN=localhost": std's Bundle keeps only the FIRST cert per
    // subject name and silently drops later ones, so two pinned self-signed
    // certs with identical subjects would collide in the shared bundle.
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days",  "1",   "-nodes", "-subj", "/CN=localhost/OU=sa-ws-client-test",
    };
    var child = sio.Child.init(&args, alloc);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = try child.spawnAndWait();
    switch (term) {
        .exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.OpensslFailed,
    }
}

test "loopback ws:// echo + server ping/pong + close handshake" {
    const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(sio.io(), .{ .reuse_address = true });
    const port = boundPort(&listener);

    var server_err: ?anyerror = null;
    const thread = try std.Thread.spawn(.{}, wsServerMain, .{SrvScript{ .listener = listener, .err = &server_err }});

    const url = try std.fmt.allocPrint(testing.allocator, "ws://127.0.0.1:{d}/chat", .{port});
    defer testing.allocator.free(url);
    try runClientScript(url);

    thread.join();
    try testing.expectEqual(@as(?anyerror, null), server_err);
}

test "loopback ws:// over IPv6 [::1]" {
    const addr = try std.Io.net.IpAddress.parseIp6("::1", 0);
    var listener = try addr.listen(sio.io(), .{ .reuse_address = true });
    const port = boundPort(&listener);

    var server_err: ?anyerror = null;
    const thread = try std.Thread.spawn(.{}, wsServerMain, .{SrvScript{ .listener = listener, .err = &server_err }});

    // Bracketed literal exercises parseUrlParts' IPv6 path and the Host
    // header bracketing; tcpConnectToHost resolves the bare "::1".
    const url = try std.fmt.allocPrint(testing.allocator, "ws://[::1]:{d}/v6", .{port});
    defer testing.allocator.free(url);
    try runClientScript(url);

    thread.join();
    try testing.expectEqual(@as(?anyerror, null), server_err);
}

test "connect to a closed port fails cleanly" {
    // Grab a port, close it, then connect: expect IO error, handle stays 0.
    const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(sio.io(), .{});
    const port = boundPort(&listener);
    listener.deinit(sio.io());

    const url = try std.fmt.allocPrint(testing.allocator, "ws://127.0.0.1:{d}/", .{port});
    defer testing.allocator.free(url);
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_ws_client_connect(url.ptr, url.len, &h));
    try testing.expectEqual(@as(u64, 0), h);
}

test "server protocol violations fail recv with -5" {
    // Masked frame from server (RFC 6455 5.1: server MUST NOT mask).
    try expectViolation(&.{ 0x81, 0x82, 0x01, 0x02, 0x03, 0x04, 'h' ^ 0x01, 'i' ^ 0x02 });
    // RSV1 set with no extensions negotiated (5.2).
    try expectViolation(&.{ 0xC1, 0x02, 'h', 'i' });
    // Text frame with invalid UTF-8 payload (5.6).
    try expectViolation(&.{ 0x81, 0x02, 0xFF, 0xFE });
    // Close frame with a 1-byte body: never a valid close code (7.1.5).
    try expectViolation(&.{ 0x88, 0x01, 0x03 });
}
