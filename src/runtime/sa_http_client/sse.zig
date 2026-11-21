const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const SseCall = @import("sse_events.zig").SseCall;
const backoffSecs = @import("exec.zig").backoffSecs;
const isRetryableStatus = @import("exec.zig").isRetryableStatus;
const linux = @import("tests_server.zig").linux;
const sseCaptureUsage = @import("sse_events.zig").sseCaptureUsage;
const sseFinalizeActive = @import("sse_events.zig").sseFinalizeActive;
const sseFindEventEnd = @import("sse_events.zig").sseFindEventEnd;
const sseHandleEvent = @import("sse_events.zig").sseHandleEvent;
const sseJsonEscape = @import("sse_events.zig").sseJsonEscape;
const sseParseEventData = @import("sse_events.zig").sseParseEventData;
const sseReadNew = @import("sse_events.zig").sseReadNew;

// ============ SSE streaming POST ============
// Spawns curl in the background writing the response body to a temp file
// as it arrives (-N/--no-buffer). The caller polls and reads incrementally.

var sse_stream_counter = std.atomic.Value(u32).init(0);
// Handle-kind tag for SseStream allocations. The sse_* exports
// receive opaque handles; a client handle (HttpClient) passed
// where a stream handle belongs must fail soft (error status),
// never be reinterpreted as a stream -- the blind cast used to
// read a client allocation's bytes as stream state and crash
// inside sse_read. The value's high byte keeps it outside every
// pointer/small-int range a foreign allocation's first word can
// plausibly hold.
const SSE_STREAM_MAGIC: u64 = 0xA5A5_5353_4554_0001;
pub const SseStream = struct {
    magic: u64,
    allocator: std.mem.Allocator,
    child: sio.Child,
    body_path: []u8,
    header_path: []u8,
    req_body_path: []u8,
    read_offset: u64,
    http_status: u16,
    finished: bool,
    failed: bool,
};
fn sseTempPath(allocator: std.mem.Allocator, suffix: []const u8) ![]u8 {
    const n = sse_stream_counter.fetchAdd(1, .monotonic);
    const pid: i32 = if (comptime builtin.cpu.arch.isWasm()) 0 else std.os.linux.getpid();
    return std.fmt.allocPrint(allocator, "/tmp/scodex_sse_{d}_{d}.{s}", .{ pid, n, suffix });
}
fn sseParseStatus(header_path: []const u8) u16 {
    const f = sio.cwd().openFile(header_path, .{}) catch return 0;
    defer f.close();
    var buf: [256]u8 = undefined;
    const n = f.read(&buf) catch return 0;
    // First line: "HTTP/1.1 200 OK"
    const line_end = std.mem.indexOfScalar(u8, buf[0..n], '\n') orelse n;
    const line = buf[0..line_end];
    // Find first space, then parse the number after it.
    const sp = std.mem.indexOfScalar(u8, line, ' ') orelse return 0;
    const rest = std.mem.trimStart(u8, line[sp + 1 ..], " ");
    const sp2 = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
    return std.fmt.parseInt(u16, rest[0..sp2], 10) catch 0;
}
/// Parse Retry-After from SSE header file. Returns 0 if absent/invalid. Capped at 300s.
fn sseParseRetryAfter(header_path: []const u8) u64 {
    const f = sio.cwd().openFile(header_path, .{}) catch return 0;
    defer f.close();
    var buf: [4096]u8 = undefined;
    const n = f.read(&buf) catch return 0;
    var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len > 12 and std.ascii.eqlIgnoreCase(trimmed[0..12], "retry-after:")) {
            const v = std.mem.trim(u8, trimmed[12..], " \t");
            if (std.fmt.parseInt(u64, v, 10)) |secs| {
                return @min(secs, 300);
            } else |_| {}
        }
    }
    return 0;
}
// Blocking reap of an SSE curl child by its own pid. Do NOT use
// std.process.Child.wait() here: sseCheckFinished polls with a
// raw waitpid(pid, WNOHANG) and may already have reaped the
// child, after which Child.wait() blocks in the Io reaper's
// waitpid(-1) until some unrelated child of the process exits
// (deadlock when a long-lived child, e.g. an MCP server, is
// alive). One mechanism, one pid: this wait.
fn sseWaitSioChild(child: *sio.Child) void {
    if (builtin.os.tag != .linux) {
        _ = child.wait() catch {};
        return;
    }
    const inner = &(child.inner orelse return);
    const pid = inner.id orelse return;
    var status: i32 = 0;
    _ = std.os.linux.waitpid(pid, &status, 0);
}
fn sseCheckFinished(s: *SseStream) void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        sseCheckFinishedNative(s);
    }
}
fn sseCheckFinishedNative(s: *SseStream) void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        sseCheckFinishedNativeNative(s);
    }
}
fn sseCheckFinishedNativeNative(s: *SseStream) void {
    if (s.finished) return;
    // NOTE(Zig 0.17): `std.posix.waitpid` was removed; poll via raw Linux
    // wait4 with WNOHANG (curl SSE path is Linux-only in practice).
    if (builtin.os.tag != .linux) return;
    const inner = &(s.child.inner orelse return);
    const pid = inner.id orelse return;
    var status: i32 = 0;
    const rc = std.os.linux.waitpid(pid, &status, std.os.linux.W.NOHANG);
    if (rc == 0) return; // still running
    s.finished = true;
    if (@as(isize, @bitCast(rc)) < 0) {
        s.failed = true; // wait error (e.g. no child)
    } else {
        const st: u32 = @bitCast(status);
        if (std.os.linux.W.IFEXITED(st)) {
            s.failed = std.os.linux.W.EXITSTATUS(st) != 0;
        } else {
            s.failed = true; // signaled or stopped
        }
    }
    s.http_status = sseParseStatus(s.header_path);
}
pub export fn sa_http_client_sse_post(
    url_ptr: ?[*]const u8, url_len: u64,
    body_ptr: ?[*]const u8, body_len: u64,
    key_ptr: ?[*]const u8, key_len: u64,
    out_handle: ?*?*anyopaque,
) u32 {
    const allocator = std.heap.page_allocator;
    const slot = out_handle orelse return 1;
    const url = if (url_ptr) |p| p[0..@intCast(url_len)] else return 1;

    const body_path = sseTempPath(allocator, "body") catch return 1;
    errdefer allocator.free(body_path);
    const header_path = sseTempPath(allocator, "headers") catch return 1;
    errdefer allocator.free(header_path);
    const req_body_path = sseTempPath(allocator, "req") catch return 1;
    errdefer allocator.free(req_body_path);

    // Write request body to temp file.
    {
        const f = sio.cwd().createFile(req_body_path, .{}) catch return 1;
        defer f.close();
        if (body_ptr) |p| {
            f.writeAll(p[0..@intCast(body_len)]) catch return 1;
        }
    }

    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();
    args.append("curl") catch return 1;
    args.append("-s") catch return 1;
    args.append("-S") catch return 1;
    args.append("-N") catch return 1; // no buffering: stream as it arrives
    args.append("--max-time") catch return 1;
    args.append("300") catch return 1;
    args.append("-X") catch return 1;
    args.append("POST") catch return 1;
    args.append(url) catch return 1;
    // Auth header. The string must outlive this block: a block-scoped
    // defer here freed it before Child.spawn consumed argv
    // (use-after-free, caught by the std loopback tests).
    var auth_buf: ?[]u8 = null;
    defer if (auth_buf) |a| allocator.free(a);
    if (key_ptr) |kp| {
        auth_buf = std.fmt.allocPrint(allocator, "Authorization: Bearer {s}", .{kp[0..@intCast(key_len)]}) catch return 1;
        args.append("-H") catch return 1;
        args.append(auth_buf.?) catch return 1;
    }
    args.append("-H") catch return 1;
    args.append("Content-Type: application/json") catch return 1;
    args.append("-H") catch return 1;
    args.append("Accept: text/event-stream") catch return 1;
    const data_arg = std.fmt.allocPrint(allocator, "@{s}", .{req_body_path}) catch return 1;
    defer allocator.free(data_arg);
    args.append("--data-binary") catch return 1;
    args.append(data_arg) catch return 1;
    args.append("-D") catch return 1;
    args.append(header_path) catch return 1;
    args.append("-o") catch return 1;
    args.append(body_path) catch return 1;

    var child = sio.Child.init(args.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.spawn() catch return 1;

    const s = allocator.create(SseStream) catch {
        child.kill() catch {};
        sseWaitSioChild(&child);
        return 1;
    };
    s.* = .{
        .magic = SSE_STREAM_MAGIC,
        .allocator = allocator,
        .child = child,
        .body_path = body_path,
        .header_path = header_path,
        .req_body_path = req_body_path,
        .read_offset = 0,
        .http_status = 0,
        .finished = false,
        .failed = false,
    };
    slot.* = @ptrCast(s);
    return 0;
}
// Resolve an opaque handle to its stream, or null when the
// handle is null or is not an SseStream allocation (see
// SSE_STREAM_MAGIC). Every public sse_* export goes through
// here before touching any stream field.
fn sseStreamFromHandle(handle: ?*anyopaque) ?*SseStream {
    const raw = handle orelse return null;
    const s = @as(*SseStream, @ptrCast(@alignCast(raw)));
    if (s.magic != SSE_STREAM_MAGIC) return null;
    return s;
}
pub export fn sa_http_client_sse_read(
    handle: ?*anyopaque,
    buf_ptr: ?[*]u8, buf_cap: u64,
    out_len: ?*u64,
) u32 {
    const s = sseStreamFromHandle(handle) orelse return 1;
    const out = out_len orelse return 1;
    const buf = buf_ptr orelse return 1;
    out.* = 0;
    if (buf_cap == 0) return 0;

    const f = sio.cwd().openFile(s.body_path, .{}) catch return 0;
    defer f.close();
    const st = f.stat() catch return 0;
    if (st.size <= s.read_offset) return 0;
    f.seekTo(s.read_offset) catch return 0;
    const want: usize = @intCast(@min(buf_cap, st.size - s.read_offset));
    const n = f.read(buf[0..want]) catch return 0;
    s.read_offset += n;
    out.* = n;
    return 0;
}
// out_done: 0 = running, 1 = finished ok, 2 = finished with error
pub export fn sa_http_client_sse_poll(handle: ?*anyopaque, out_done: ?*u8) u32 {
    const s = sseStreamFromHandle(handle) orelse return 1;
    const out = out_done orelse return 1;
    sseCheckFinished(s);
    // Also try to parse status from headers if not yet known.
    if (s.http_status == 0) {
        s.http_status = sseParseStatus(s.header_path);
    }
    out.* = if (!s.finished) 0 else if (s.failed) 2 else 1;
    return 0;
}
pub export fn sa_http_client_sse_status(handle: ?*anyopaque) u16 {
    const s = sseStreamFromHandle(handle) orelse return 0;
    if (s.http_status == 0) {
        s.http_status = sseParseStatus(s.header_path);
    }
    return s.http_status;
}
pub export fn sa_http_client_sse_free(handle: ?*anyopaque) u32 {
    const s = sseStreamFromHandle(handle) orelse return 1;
    if (!s.finished) {
        _ = s.child.kill() catch {};
        sseWaitSioChild(&s.child);
    }
    sio.cwd().deleteFile(s.body_path) catch {};
    sio.cwd().deleteFile(s.header_path) catch {};
    sio.cwd().deleteFile(s.req_body_path) catch {};
    s.allocator.free(s.body_path);
    s.allocator.free(s.header_path);
    s.allocator.free(s.req_body_path);
    s.allocator.destroy(s);
    return 0;
}
// High-level SSE turn: POST, stream, parse events, print deltas live,
// accumulate text and tool calls. Bypasses SLA compiler limitations.
// Returns: 0=ok (text), 1=ok (tool calls), 2=error.
// Out params: text (ptr/len), calls_json (ptr/len, JSON array of {call_id,name,args}).
// Caller must free returned buffers via sa_http_client_sse_turn_free.
pub export fn sa_http_client_sse_turn(
    url_ptr: ?[*]const u8, url_len: u64,
    body_ptr: ?[*]const u8, body_len: u64,
    key_ptr: ?[*]const u8, key_len: u64,
    api_mode: u64,
    out_text_ptr: ?*?[*]u8, out_text_len: ?*u64,
    out_calls_ptr: ?*?[*]u8, out_calls_len: ?*u64,
) u32 {
    return sseTurnImpl(url_ptr, url_len, body_ptr, body_len, key_ptr, key_len, api_mode, out_text_ptr, out_text_len, out_calls_ptr, out_calls_len, null, null, null, null);
}
// sse_turn plus the channel-reported usage object: out_usage
// receives the raw JSON span of the last top-level "usage" value
// in the stream (for example
// {"prompt_tokens":N,"completion_tokens":N,"total_tokens":N}).
// It stays empty when the channel reports no usage; callers must
// treat absence as "not reported", never as zero. Free with
// sa_http_client_sse_turn_free like the other outs.
pub export fn sa_http_client_sse_turn_ex(
    url_ptr: ?[*]const u8, url_len: u64,
    body_ptr: ?[*]const u8, body_len: u64,
    key_ptr: ?[*]const u8, key_len: u64,
    api_mode: u64,
    out_text_ptr: ?*?[*]u8, out_text_len: ?*u64,
    out_calls_ptr: ?*?[*]u8, out_calls_len: ?*u64,
    out_usage_ptr: ?*?[*]u8, out_usage_len: ?*u64,
    out_reasoning_ptr: ?*?[*]u8, out_reasoning_len: ?*u64,
) u32 {
    return sseTurnImpl(url_ptr, url_len, body_ptr, body_len, key_ptr, key_len, api_mode, out_text_ptr, out_text_len, out_calls_ptr, out_calls_len, out_usage_ptr, out_usage_len, out_reasoning_ptr, out_reasoning_len);
}
fn sseTurnImpl(
    url_ptr: ?[*]const u8, url_len: u64,
    body_ptr: ?[*]const u8, body_len: u64,
    key_ptr: ?[*]const u8, key_len: u64,
    api_mode: u64,
    out_text_ptr: ?*?[*]u8, out_text_len: ?*u64,
    out_calls_ptr: ?*?[*]u8, out_calls_len: ?*u64,
    out_usage_ptr: ?*?[*]u8, out_usage_len: ?*u64,
    out_reasoning_ptr: ?*?[*]u8, out_reasoning_len: ?*u64,
) u32 {
    const otp = out_text_ptr orelse return 2;
    const otl = out_text_len orelse return 2;
    const ocp = out_calls_ptr orelse return 2;
    const ocl = out_calls_len orelse return 2;
    otp.* = null;
    otl.* = 0;
    ocp.* = null;
    ocl.* = 0;
    if (out_usage_ptr) |oup| {
        if (out_usage_len) |oul| {
            oup.* = null;
            oul.* = 0;
        }
    }
    if (out_reasoning_ptr) |orp| {
        if (out_reasoning_len) |orl| {
            orp.* = null;
            orl.* = 0;
        }
    }

    // Retry wrapper: up to 5 retries (6 attempts) on 429/5xx/transient network errors.
    // Exponential backoff 1/2/4/8/16s, respecting Retry-After (capped at 5min).
    // Once streaming starts (200 OK), no retry - mid-stream failures return error.
    var attempt: u32 = 0;
    while (true) {
        var handle: ?*anyopaque = null;
        if (sa_http_client_sse_post(url_ptr, url_len, body_ptr, body_len, key_ptr, key_len, &handle) != 0 or handle == null) {
            if (handle) |h| _ = sa_http_client_sse_free(h);
            if (attempt < 5) {
                sio.io().sleep(.fromNanoseconds(backoffSecs(attempt) * std.time.ns_per_s), .awake) catch {};
                attempt += 1;
                continue;
            }
            return 2;
        }
        // Wait for HTTP status. The poll cap must tolerate slow
        // time-to-first-byte upstreams: a grok tool-call request was
        // measured at 20s to first byte, over the old 200*50ms = 10s
        // cap, which surfaced as a spurious upstream error. 3600*50ms
        // = 180s; a dead transfer still ends the wait via poll done.
        var status: u16 = 0;
        var waits: u32 = 0;
        while (waits < 3600) : (waits += 1) {
            const st = sa_http_client_sse_status(handle);
            if (st != 0) {
                status = st;
                break;
            }
            var done: u8 = 0;
            _ = sa_http_client_sse_poll(handle, &done);
            if (done != 0) break;
            sio.io().sleep(.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};
        }
        if (status == 200) {
            // Success: stream to completion. sseTurnStream does not free handle;
            // we free it here via defer.
            defer _ = sa_http_client_sse_free(handle);
            return sseTurnStream(handle, api_mode, otp, otl, ocp, ocl, out_usage_ptr, out_usage_len, out_reasoning_ptr, out_reasoning_len);
        }
        // Non-200: check if retryable.
        const s = @as(*SseStream, @ptrCast(@alignCast(handle.?)));
        const retry_after = sseParseRetryAfter(s.header_path);
        _ = sa_http_client_sse_free(handle);
        if (status != 0 and isRetryableStatus(status) and attempt < 5) {
            const wait_secs = @max(backoffSecs(attempt), retry_after);
            sio.io().sleep(.fromNanoseconds(wait_secs * std.time.ns_per_s), .awake) catch {};
            attempt += 1;
            continue;
        }
        return 2;
    }
}
/// Streaming part: assumes handle has 200 OK status. Reads SSE stream to completion.
fn sseTurnStream(
    handle: ?*anyopaque,
    api_mode: u64,
    otp: *?[*]u8, otl: *u64,
    ocp: *?[*]u8, ocl: *u64,
    oup_opt: ?*?[*]u8, oul_opt: ?*u64,
    orp_opt: ?*?[*]u8, orl_opt: ?*u64,
) u32 {
    const allocator = std.heap.page_allocator;
    const s = @as(*SseStream, @ptrCast(@alignCast(handle.?)));

    var text = std.array_list.Managed(u8).init(allocator);
    defer text.deinit();
    var calls = std.array_list.Managed(SseCall).init(allocator);
    defer {
        for (calls.items) |*c| {
            if (c.call_id.len > 0) allocator.free(c.call_id);
            if (c.name.len > 0) allocator.free(c.name);
            if (c.args.len > 0) allocator.free(c.args);
            if (c.key.len > 0) allocator.free(c.key);
        }
        calls.deinit();
    }
    var active = std.array_list.Managed(SseCall).init(allocator);
    defer {
        // Free any remaining active calls.
        for (active.items) |*ac| {
            if (ac.call_id.len > 0) allocator.free(ac.call_id);
            if (ac.name.len > 0) allocator.free(ac.name);
            if (ac.args.len > 0) allocator.free(ac.args);
            if (ac.key.len > 0) allocator.free(ac.key);
        }
        active.deinit();
    }
    var stream_done = false;
    var usage = std.array_list.Managed(u8).init(allocator);
    defer usage.deinit();
    var reasoning = std.array_list.Managed(u8).init(allocator);
    defer reasoning.deinit();

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();
    var processed_offset: usize = 0;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_stream = std.Io.File.stdout().writerStreaming(sio.io(), &stdout_buf);
    const stdout = &stdout_stream.interface;
    defer stdout_stream.interface.flush() catch {};

    // Main read loop.
    while (!stream_done) {
        // Read new bytes from body file.
        const new_data = sseReadNew(s, &processed_offset) catch {
            return 2;
        };
        if (new_data.len > 0) {
            buf.appendSlice(new_data) catch return 2;
            allocator.free(new_data);
            // Extract complete events.
            while (true) {
                const delim = sseFindEventEnd(buf.items) orelse break;
                const ev = buf.items[0..delim.pos];
                // Parse event data.
                if (sseParseEventData(allocator, ev)) |data| {
                    defer if (data.owned) allocator.free(data.payload);
                    if (data.is_done) {
                        stream_done = true;
                    } else if (data.payload.len > 0) {
                        sseCaptureUsage(data.payload, &usage);
                        sseHandleEvent(allocator, data.payload, api_mode, &text, &reasoning, &calls, &active, &stream_done, stdout) catch {};
                    }
                }
                // Remove processed event (+ delimiter length).
                const remove_len = delim.pos + delim.len;
                if (remove_len < buf.items.len) {
                    std.mem.copyForwards(u8, buf.items[0..], buf.items[remove_len..]);
                }
                buf.shrinkRetainingCapacity(buf.items.len - remove_len);
                if (stream_done) break;
            }
        }
        if (stream_done) break;
        var done: u8 = 0;
        _ = sa_http_client_sse_poll(handle, &done);
        if (done == 1) {
            // Process trailing.
            if (buf.items.len > 0) {
                if (sseParseEventData(allocator, buf.items)) |data| {
                    defer if (data.owned) allocator.free(data.payload);
                    if (!data.is_done and data.payload.len > 0) {
                        sseCaptureUsage(data.payload, &usage);
                        sseHandleEvent(allocator, data.payload, api_mode, &text, &reasoning, &calls, &active, &stream_done, stdout) catch {};
                    }
                }
            }
            break;
        } else if (done == 2) {
            return 2;
        }
        if (new_data.len == 0) {
            sio.io().sleep(.fromNanoseconds(20 * std.time.ns_per_ms), .awake) catch {};
        }
    }

    // Finalize all active calls.
    sseFinalizeActive(allocator, &active, &calls) catch return 2;

    // Print newline after stream.
    stdout.writeAll("\n") catch {};

    // Build calls JSON first (so text isn't leaked on failure).
    var calls_json = std.array_list.Managed(u8).init(allocator);
    defer calls_json.deinit();
    calls_json.appendSlice("[") catch return 2;
    for (calls.items, 0..) |c, i| {
        if (i > 0) calls_json.appendSlice(",") catch return 2;
        calls_json.appendSlice("{\"call_id\":\"") catch return 2;
        sseJsonEscape(&calls_json, c.call_id) catch return 2;
        calls_json.appendSlice("\",\"name\":\"") catch return 2;
        sseJsonEscape(&calls_json, c.name) catch return 2;
        calls_json.appendSlice("\",\"args\":\"") catch return 2;
        sseJsonEscape(&calls_json, c.args) catch return 2;
        calls_json.appendSlice("\"}") catch return 2;
    }
    calls_json.appendSlice("]") catch return 2;
    const cj_slice = calls_json.toOwnedSlice() catch return 2;
    errdefer allocator.free(cj_slice);

    // Return text.
    const text_slice = text.toOwnedSlice() catch {
        allocator.free(cj_slice);
        return 2;
    };

    const usage_slice = usage.toOwnedSlice() catch {
        allocator.free(cj_slice);
        allocator.free(text_slice);
        return 2;
    };
    errdefer allocator.free(usage_slice);

    // All succeeded; assign outputs.
    otp.* = text_slice.ptr;
    otl.* = text_slice.len;
    ocp.* = cj_slice.ptr;
    ocl.* = cj_slice.len;
    if (oup_opt) |oup| {
        if (oul_opt) |oul| {
            oup.* = usage_slice.ptr;
            oul.* = usage_slice.len;
        } else {
            allocator.free(usage_slice);
        }
    } else {
        allocator.free(usage_slice);
    }
    const reasoning_slice = reasoning.toOwnedSlice() catch {
        allocator.free(cj_slice);
        allocator.free(text_slice);
        return 2;
    };
    if (orp_opt) |orp| {
        if (orl_opt) |orl| {
            orp.* = reasoning_slice.ptr;
            orl.* = reasoning_slice.len;
        } else {
            allocator.free(reasoning_slice);
        }
    } else {
        allocator.free(reasoning_slice);
    }

    return if (calls.items.len > 0) 1 else 0;
}
