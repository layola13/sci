const std = @import("std");
const affected_tests = @import("../affected_tests.zig");
const builtin = @import("builtin");
const incr_verify = @import("../incr_verify.zig");
const sio = @import("sio");
const commandFromName = @import("help.zig").commandFromName;
const daemon_cancel = @import("../daemon_cancel.zig");
const daemon_client = @import("../daemon_client.zig");
const executeWithWritersAndOptions = @import("../cli.zig").executeWithWritersAndOptions;
const elapsedNs = @import("compile.zig").elapsedNs;

var daemon_cwd_lock: std.Io.RwLock = .init;
var daemon_shutdown_flag = std.atomic.Value(bool).init(false);
var daemon_in_flight_global = std.atomic.Value(usize).init(0);

pub fn daemonWrite(stream: std.Io.net.Stream, bytes: []const u8) void {
    var wbuf: [8192]u8 = undefined;
    var w = stream.writer(sio.io(), &wbuf);
    w.interface.writeAll(bytes) catch {};
    w.interface.flush() catch {};
}

pub fn daemonWorker(allocator: std.mem.Allocator, stream: std.Io.net.Stream, in_flight: *std.atomic.Value(usize)) void {
    defer _ = in_flight.fetchSub(1, .monotonic);
    handleDaemonConnection(allocator, stream);
}

pub fn handleDaemonConnection(allocator: std.mem.Allocator, stream: std.Io.net.Stream) void {
    defer stream.close(sio.io());
    var request_buf = std.array_list.Managed(u8).init(allocator);
    defer request_buf.deinit();
    var read_buf: [4096]u8 = undefined;
    var request_line: []const u8 = &.{};
    var sock_rbuf: [4096]u8 = undefined;
    var sock_reader = stream.reader(sio.io(), &sock_rbuf);
    while (true) {
        const n = sock_reader.interface.readSliceShort(read_buf[0..]) catch return;
        if (n == 0) return;
        if (request_buf.items.len > daemon_client.MAX_REQUEST_BYTES - n) {
            daemonWrite(stream, "{\"status\":\"error\",\"message\":\"request too large\"}\n");
            return;
        }
        request_buf.appendSlice(read_buf[0..n]) catch return;
        if (std.mem.indexOfScalar(u8, request_buf.items, '\n')) |newline| {
            request_line = std.mem.trimEnd(u8, request_buf.items[0..newline], "\r ");
            break;
        }
    }
    if (request_line.len == 0) return;

    // Control ops that don't need argv execution.
    if (std.mem.indexOf(u8, request_line, "\"op\":\"ping\"") != null or std.mem.indexOf(u8, request_line, "\"op\": \"ping\"") != null) {
        const st = daemon_cancel.stats();
        const vs = incr_verify.stats();
        const as = affected_tests.stats();
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();
        aw.writer.print(
            "{{\"status\":\"ok\",\"code\":0,\"metrics\":{{\"in_flight\":{d},\"accepted\":{d},\"canceled\":{d},\"busy_rejects\":{d},\"verdict_hits\":{d},\"verdict_misses\":{d},\"affected_hits\":{d},\"affected_misses\":{d}}}}}\n",
            .{
                daemon_in_flight_global.load(.monotonic),
                st.accepted,
                st.canceled,
                st.busy_rejects,
                vs.hits,
                vs.misses,
                as.hits,
                as.misses,
            },
        ) catch return;
        daemonWrite(stream, aw.written());
        return;
    }
    if (std.mem.indexOf(u8, request_line, "\"op\":\"shutdown\"") != null or std.mem.indexOf(u8, request_line, "\"op\": \"shutdown\"") != null) {
        daemon_shutdown_flag.store(true, .monotonic);
        daemonWrite(stream, "{\"status\":\"ok\",\"code\":0,\"message\":\"shutting down\"}\n");
        return;
    }
    if (std.mem.indexOf(u8, request_line, "\"op\":\"cancel\"") != null or std.mem.indexOf(u8, request_line, "\"op\": \"cancel\"") != null) {
        const agent_id = daemon_cancel.parseJsonStrField(request_line, "\"agent_id\"") orelse "";
        const gen = daemon_cancel.cancelAgent(agent_id);
        daemon_cancel.noteCanceled();
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();
        aw.writer.print("{{\"status\":\"ok\",\"code\":0,\"canceled_generation\":{d}}}\n", .{gen}) catch return;
        daemonWrite(stream, aw.written());
        return;
    }

    // Cooperative cancellation: skip work if a newer generation superseded this.
    const agent_id = daemon_cancel.parseJsonStrField(request_line, "\"agent_id\"") orelse "";
    const generation = daemon_cancel.parseJsonU64Field(request_line, "\"generation\"") orelse 0;
    if (agent_id.len != 0) {
        _ = daemon_cancel.registerGeneration(agent_id, generation);
        if (!daemon_cancel.generationIsCurrent(agent_id, generation)) {
            daemon_cancel.noteCanceled();
            daemonWrite(stream, "{\"status\":\"canceled\"}\n");
            return;
        }
    }

    // Per-agent quota: reject if this agent already has too many in-flight
    // requests. Prevents one agent from starving others. Empty id = unlimited.
    if (agent_id.len != 0 and !daemon_cancel.acquireSlot(agent_id)) {
        daemonWrite(stream, "{\"status\":\"busy\",\"message\":\"per-agent quota exceeded\"}\n");
        return;
    }
    defer if (agent_id.len != 0) daemon_cancel.releaseSlot(agent_id);

    const parsed = parseDaemonArgv(allocator, request_line) catch {
        daemonWrite(stream, "{\"status\":\"error\",\"message\":\"invalid request\"}\n");
        return;
    };
    defer freeDaemonArgv(allocator, parsed);

    const requested_cwd = daemon_cancel.parseJsonStrField(request_line, "\"cwd\"");
    if (requested_cwd != null) {
        daemon_cwd_lock.lock(sio.io()) catch {};
    } else {
        daemon_cwd_lock.lockShared(sio.io()) catch {};
    }
    defer if (requested_cwd != null) daemon_cwd_lock.unlock(sio.io()) else daemon_cwd_lock.unlockShared(sio.io());

    var old_cwd_buf: [sio.max_path_bytes]u8 = undefined;
    const old_cwd = if (requested_cwd != null) sio.cwd().realpath(".", &old_cwd_buf) catch null else null;
    if (requested_cwd) |cwd| {
        sio.changeCurDir(cwd) catch {
            daemonWrite(stream, "{\"status\":\"error\",\"message\":\"invalid cwd\"}\n");
            return;
        };
    }
    defer if (old_cwd) |c| sio.changeCurDir(c) catch {};

    const wall_start = std.Io.Clock.awake.now(sio.io());
    var resp: std.Io.Writer.Allocating = .init(allocator);
    defer resp.deinit();
    const code: u8 = executeWithWritersAndOptions(allocator, parsed, &resp.writer, &resp.writer, .{}) catch |err| blk: {
        resp.clearRetainingCapacity();
        resp.writer.print("execution error: {s}", .{@errorName(err)}) catch {};
        break :blk @as(u8, 1);
    };
    const wall_ms: u64 = elapsedNs(wall_start) / 1_000_000;
    const vs = incr_verify.stats();
    const as = affected_tests.stats();

    // Re-check cancellation after work (cooperative end boundary).
    if (agent_id.len != 0 and !daemon_cancel.generationIsCurrent(agent_id, generation)) {
        daemon_cancel.noteCanceled();
        daemonWrite(stream, "{\"status\":\"canceled\"}\n");
        return;
    }

    var haw: std.Io.Writer.Allocating = .init(allocator);
    defer haw.deinit();
    haw.writer.print(
        "{{\"status\":\"ok\",\"code\":{d},\"len\":{d},\"metrics\":{{\"wall_ms\":{d},\"verdict_hits\":{d},\"verdict_misses\":{d},\"affected_hits\":{d},\"affected_misses\":{d}}}}}\n",
        .{ code, resp.written().len, wall_ms, vs.hits, vs.misses, as.hits, as.misses },
    ) catch return;
    daemonWrite(stream, haw.written());
    daemonWrite(stream, resp.written());
}

pub fn parseDaemonArgv(allocator: std.mem.Allocator, request: []const u8) ![]const []const u8 {
    // Prefer explicit argv array. Also accept op/file/args document style.
    if (std.mem.indexOf(u8, request, "\"argv\"")) |_| {
        const lb = std.mem.indexOfScalar(u8, request, '[') orelse return error.InvalidRequest;
        const rb = std.mem.lastIndexOfScalar(u8, request, ']') orelse return error.InvalidRequest;
        if (rb <= lb) return error.InvalidRequest;
        const inner = request[lb + 1 .. rb];
        var list = std.array_list.Managed([]const u8).init(allocator);
        errdefer {
            for (list.items) |it| allocator.free(it);
            list.deinit();
        }
        var i: usize = 0;
        while (i < inner.len) {
            if (inner[i] != '"') {
                i += 1;
                continue;
            }
            i += 1;
            var item = std.array_list.Managed(u8).init(allocator);
            errdefer item.deinit();
            while (i < inner.len and inner[i] != '"') {
                if (inner[i] == '\\' and i + 1 < inner.len) {
                    i += 1;
                }
                try item.append(inner[i]);
                i += 1;
            }
            i += 1; // closing quote
            try list.append(try item.toOwnedSlice());
        }
        // Normalize argv[0] to "sa". Clients may send the real binary path
        // (e.g. zig-out/bin/sa) or omit argv[0] entirely and start at the command.
        if (list.items.len == 0) {
            try list.insert(0, try allocator.dupe(u8, "sa"));
        } else if (std.mem.eql(u8, list.items[0], "sa") or std.mem.endsWith(u8, list.items[0], "/sa")) {
            if (!std.mem.eql(u8, list.items[0], "sa")) {
                allocator.free(list.items[0]);
                list.items[0] = try allocator.dupe(u8, "sa");
            }
        } else if (commandFromName(list.items[0]) != null or std.mem.eql(u8, list.items[0], "help") or std.mem.eql(u8, list.items[0], "version")) {
            try list.insert(0, try allocator.dupe(u8, "sa"));
        } else {
            // Unknown first token: still force sa so dispatch can error cleanly.
            try list.insert(0, try allocator.dupe(u8, "sa"));
        }
        return try list.toOwnedSlice();
    }

    // Document-style: {"op":"build","file":"x.sa","args":["--json"]}
    const op = daemon_cancel.parseJsonStrField(request, "\"op\"") orelse return error.InvalidRequest;
    var list = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (list.items) |it| allocator.free(it);
        list.deinit();
    }
    try list.append(try allocator.dupe(u8, "sa"));
    try list.append(try allocator.dupe(u8, op));
    if (daemon_cancel.parseJsonStrField(request, "\"file\"")) |file| {
        try list.append(try allocator.dupe(u8, file));
    }
    // Best-effort: pull string items after "args"
    if (std.mem.indexOf(u8, request, "\"args\"")) |ap| {
        const sub = request[ap..];
        const lb = std.mem.indexOfScalar(u8, sub, '[') orelse 0;
        const rb = std.mem.indexOfScalar(u8, sub, ']') orelse 0;
        if (rb > lb) {
            const inner = sub[lb + 1 .. rb];
            var i: usize = 0;
            while (i < inner.len) {
                if (inner[i] != '"') {
                    i += 1;
                    continue;
                }
                i += 1;
                var item = std.array_list.Managed(u8).init(allocator);
                errdefer item.deinit();
                while (i < inner.len and inner[i] != '"') {
                    if (inner[i] == '\\' and i + 1 < inner.len) i += 1;
                    try item.append(inner[i]);
                    i += 1;
                }
                i += 1;
                try list.append(try item.toOwnedSlice());
            }
        }
    }
    return try list.toOwnedSlice();
}

pub fn daemonCommandUnix(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var socket_path: []const u8 = "/tmp/sa-daemon.sock";
    var max_workers: usize = 8;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--socket") and i + 1 < args.len) {
            socket_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--max-workers") and i + 1 < args.len) {
            max_workers = std.fmt.parseInt(usize, args[i + 1], 10) catch 8;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--per-agent-limit") and i + 1 < args.len) {
            daemon_cancel.setPerAgentLimit(std.fmt.parseInt(u32, args[i + 1], 10) catch 4);
            i += 1;
        }
    }
    sio.cwd().deleteFile(socket_path) catch {};
    const ua = try std.Io.net.UnixAddress.init(socket_path);
    var server = ua.listen(sio.io(), .{}) catch |err| {
        try stderr.print("daemon: failed to listen on {s}: {s}\n", .{ socket_path, @errorName(err) });
        return 1;
    };
    defer server.deinit(sio.io());
    if (!restrictDaemonSocket(socket_path)) {
        try stderr.print("daemon: failed to restrict socket permissions for {s}\n", .{socket_path});
        return 1;
    }
    try stdout.print("sa daemon listening on {s} (max_workers={d})\n", .{ socket_path, max_workers });

    var in_flight = std.atomic.Value(usize).init(0);
    daemon_shutdown_flag.store(false, .monotonic);
    while (!daemon_shutdown_flag.load(.monotonic)) {
        const stream = server.accept(sio.io()) catch |err| {
            if (daemon_shutdown_flag.load(.monotonic)) break;
            try stderr.print("daemon: accept failed: {s}\n", .{@errorName(err)});
            continue;
        };
        // Backpressure: at capacity, handle inline (blocks accept) instead of
        // spawning unbounded threads. Bounds memory under many agents.
        daemon_in_flight_global.store(in_flight.load(.monotonic), .monotonic);
        if (in_flight.load(.monotonic) >= max_workers) {
            handleDaemonConnection(allocator, stream);
            continue;
        }
        _ = in_flight.fetchAdd(1, .monotonic);
        daemon_in_flight_global.store(in_flight.load(.monotonic), .monotonic);
        const thread = std.Thread.spawn(.{}, daemonWorker, .{ allocator, stream, &in_flight }) catch {
            _ = in_flight.fetchSub(1, .monotonic);
            handleDaemonConnection(allocator, stream);
            continue;
        };
        thread.detach();
    }
    // Wait briefly for in-flight workers to drain.
    var spins: usize = 0;
    while (in_flight.load(.monotonic) > 0 and spins < 1000) : (spins += 1) {
        sio.io().sleep(.fromNanoseconds(1 * std.time.ns_per_ms), .awake) catch {};
    }
    sio.cwd().deleteFile(socket_path) catch {};
    return 0;
}

pub fn restrictDaemonSocket(socket_path: []const u8) bool {
    if (comptime builtin.os.tag != .linux) return true;
    var path_buf: [sio.max_path_bytes + 1]u8 = undefined;
    const path_slice = std.fmt.bufPrint(path_buf[0..sio.max_path_bytes], "{s}", .{socket_path}) catch return false;
    path_buf[path_slice.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(&path_buf);
    const rc = std.os.linux.chmod(path_z, 0o600);
    return std.os.linux.errno(rc) == .SUCCESS;
}

pub fn freeDaemonArgv(allocator: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| allocator.free(a);
    allocator.free(argv);
}
