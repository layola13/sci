const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const SseStream = @import("sse.zig").SseStream;
const testing = @import("tests_server.zig").testing;

pub const SseCall = struct {
    call_id: []u8,
    name: []u8,
    args: []u8,
    // For lookup during streaming: responses uses call_id, chat uses index.
    // We store the raw key string for matching.
    key: []u8,
};
const SseEventData = struct {
    payload: []const u8,
    is_done: bool,
    owned: bool, // if true, caller must free payload
};
pub fn sseReadNew(s: *SseStream, offset: *usize) ![]u8 {
    const f = sio.cwd().openFile(s.body_path, .{}) catch |err| {
        // File not yet created by curl; treat as no new data.
        if (err == error.FileNotFound) {
            return try s.allocator.alloc(u8, 0);
        }
        return err;
    };
    defer f.close();
    const stat = try f.stat();
    const size = stat.size;
    if (size <= offset.*) return try s.allocator.alloc(u8, 0);
    const len = size - offset.*;
    var data = try s.allocator.alloc(u8, @intCast(len));
    errdefer s.allocator.free(data);
    try f.seekTo(offset.*);
    var n: usize = 0;
    while (n < data.len) {
        const m = try f.read(data[n..]);
        if (m == 0) break;
        n += m;
    }
    offset.* += n;
    // Shrink to actual bytes read so free() gets the right size.
    if (n < len) {
        data = try s.allocator.realloc(data, n);
    }
    return data;
}
const SseDelim = struct { pos: usize, len: usize };
pub fn sseFindEventEnd(data: []const u8) ?SseDelim {
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 1) {
        if (data[i] == '\n' and data[i + 1] == '\n') return .{ .pos = i, .len = 2 };
        // CRLF: \r\n\r\n is 4 bytes.
        if (i + 3 < data.len and data[i] == '\r' and data[i + 1] == '\n' and data[i + 2] == '\r' and data[i + 3] == '\n') return .{ .pos = i, .len = 4 };
    }
    return null;
}
pub fn sseParseEventData(allocator: std.mem.Allocator, ev: []const u8) ?SseEventData {
    // SSE spec: multiple "data:" lines are joined with "\n".
    var parts = std.array_list.Managed([]const u8).init(allocator);
    defer parts.deinit();
    var is_done = false;
    var lines = std.mem.splitScalar(u8, ev, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (std.mem.startsWith(u8, trimmed, "data:")) {
            const d = std.mem.trim(u8, trimmed[5..], " ");
            if (std.mem.eql(u8, d, "[DONE]")) {
                is_done = true;
            } else {
                parts.append(d) catch return null;
            }
        }
    }
    if (is_done) return .{ .payload = "", .is_done = true, .owned = false };
    if (parts.items.len == 0) return null;
    if (parts.items.len == 1) {
        return .{ .payload = parts.items[0], .is_done = false, .owned = false };
    }
    // Join with \n.
    const joined = std.mem.join(allocator, "\n", parts.items) catch return null;
    return .{ .payload = joined, .is_done = false, .owned = true };
}
/// Captures the raw JSON span of the last top-level "usage"
/// object in one SSE event payload. Escaped quotes inside string
/// values cannot form a false match because the search requires
/// a literal opening quote directly before the key.
pub fn sseCaptureUsage(payload: []const u8, usage: *std.array_list.Managed(u8)) void {
    const key = "\"usage\"";
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, payload, i, key)) |pos| {
        var j = pos + key.len;
        while (j < payload.len and (payload[j] == ' ' or payload[j] == '\t')) : (j += 1) {}
        if (j < payload.len and payload[j] == ':') {
            j += 1;
            while (j < payload.len and (payload[j] == ' ' or payload[j] == '\t')) : (j += 1) {}
            if (j < payload.len and payload[j] == '{') {
                var depth: usize = 0;
                var in_str = false;
                var esc = false;
                var k = j;
                while (k < payload.len) : (k += 1) {
                    const c = payload[k];
                    if (in_str) {
                        if (esc) {
                            esc = false;
                        } else if (c == '\\') {
                            esc = true;
                        } else if (c == '"') {
                            in_str = false;
                        }
                    } else if (c == '"') {
                        in_str = true;
                    } else if (c == '{') {
                        depth += 1;
                    } else if (c == '}') {
                        depth -= 1;
                        if (depth == 0) {
                            usage.clearRetainingCapacity();
                            usage.appendSlice(payload[j .. k + 1]) catch return;
                            return;
                        }
                    }
                }
                return;
            }
        }
        i = pos + key.len;
    }
}
test "sse usage capture extracts the last usage object" {
    const alloc = std.testing.allocator;
    var usage = std.array_list.Managed(u8).init(alloc);
    defer usage.deinit();
    sseCaptureUsage("{\"choices\":[],\"usage\":{\"prompt_tokens\":47,\"completion_tokens\":31,\"total_tokens\":78,\"prompt_tokens_details\":{\"cached_tokens\":0}}}", &usage);
    try std.testing.expectEqualStrings("{\"prompt_tokens\":47,\"completion_tokens\":31,\"total_tokens\":78,\"prompt_tokens_details\":{\"cached_tokens\":0}}", usage.items);
    // A later, smaller usage replaces the earlier one.
    sseCaptureUsage("{\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}", &usage);
    try std.testing.expectEqualStrings("{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}", usage.items);
    // null usage and content text do not capture.
    var usage2 = std.array_list.Managed(u8).init(alloc);
    defer usage2.deinit();
    sseCaptureUsage("{\"usage\":null}", &usage2);
    try std.testing.expectEqual(@as(usize, 0), usage2.items.len);
    sseCaptureUsage("{\"choices\":[{\"delta\":{\"content\":\"say \\\"usage\\\" please\"}}]}", &usage2);
    try std.testing.expectEqual(@as(usize, 0), usage2.items.len);
}
test "sse chat events accumulate reasoning separately from text" {
    const alloc = std.testing.allocator;
    var text = std.array_list.Managed(u8).init(alloc);
    defer text.deinit();
    var reasoning = std.array_list.Managed(u8).init(alloc);
    defer reasoning.deinit();
    var calls = std.array_list.Managed(SseCall).init(alloc);
    defer calls.deinit();
    var active = std.array_list.Managed(SseCall).init(alloc);
    defer active.deinit();
    var done = false;
    const DiscardWriter = struct {
        pub fn writeAll(_: *@This(), _: []const u8) !void {}
    };
    var dw = DiscardWriter{};
    const w = &dw;
    try sseHandleEvent(alloc, "{\"choices\":[{\"delta\":{\"reasoning\":\"The user\"}}]}", 1, &text, &reasoning, &calls, &active, &done, w);
    try sseHandleEvent(alloc, "{\"choices\":[{\"delta\":{\"reasoning\":\" asks.\",\"content\":\"ok\"}}]}", 1, &text, &reasoning, &calls, &active, &done, w);
    try std.testing.expectEqualStrings("The user asks.", reasoning.items);
    try std.testing.expectEqualStrings("ok", text.items);
}
pub fn sseHandleEvent(
    allocator: std.mem.Allocator,
    data: []const u8,
    api_mode: u64,
    text: *std.array_list.Managed(u8),
    reasoning: *std.array_list.Managed(u8),
    calls: *std.array_list.Managed(SseCall),
    active: *std.array_list.Managed(SseCall),
    stream_done: *bool,
    stdout: anytype,
) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return;
    defer parsed.deinit();
    const root = parsed.value;
    if (api_mode == 0) {
        try sseHandleResponsesEvent(allocator, root, text, reasoning, calls, active, stream_done, stdout);
    } else {
        try sseHandleChatEvent(allocator, root, text, reasoning, calls, active, stream_done, stdout);
    }
}
// Find an active call by key (call_id for responses, index string for chat).
fn sseFindActive(active: *std.array_list.Managed(SseCall), key: []const u8) ?*SseCall {
    for (active.items) |*ac| {
        if (std.mem.eql(u8, ac.key, key)) return ac;
    }
    return null;
}
// Move all active calls to the completed list (finalize).
pub fn sseFinalizeActive(allocator: std.mem.Allocator, active: *std.array_list.Managed(SseCall), calls: *std.array_list.Managed(SseCall)) !void {
    for (active.items) |*ac| {
        if (ac.name.len > 0) {
            try calls.append(ac.*);
        } else {
            if (ac.call_id.len > 0) allocator.free(ac.call_id);
            if (ac.name.len > 0) allocator.free(ac.name);
            if (ac.args.len > 0) allocator.free(ac.args);
            if (ac.key.len > 0) allocator.free(ac.key);
        }
    }
    active.clearRetainingCapacity();
}
fn sseJsonStr(val: std.json.Value) ?[]const u8 {
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}
fn sseHandleResponsesEvent(
    allocator: std.mem.Allocator,
    root: std.json.Value,
    text: *std.array_list.Managed(u8),
    reasoning: *std.array_list.Managed(u8),
    calls: *std.array_list.Managed(SseCall),
    active: *std.array_list.Managed(SseCall),
    stream_done: *bool,
    stdout: anytype,
) !void {
    const obj = switch (root) { .object => |o| o, else => return };
    const tval = obj.get("type") orelse return;
    const tstr = sseJsonStr(tval) orelse return;

    if (std.mem.eql(u8, tstr, "response.output_text.delta")) {
        if (obj.get("delta")) |dval| {
            if (sseJsonStr(dval)) |ds| {
                try stdout.writeAll(ds);
                try text.appendSlice(ds);
            }
        }
    } else if (std.mem.eql(u8, tstr, "response.reasoning_summary_text.delta") or std.mem.eql(u8, tstr, "response.reasoning_text.delta")) {
        if (obj.get("delta")) |dval| {
            if (sseJsonStr(dval)) |ds| {
                try reasoning.appendSlice(ds);
            }
        }
    } else if (std.mem.eql(u8, tstr, "response.output_item.added")) {
        if (obj.get("item")) |ival| {
            const item = switch (ival) { .object => |o| o, else => return };
            if (item.get("type")) |tyval| {
                if (sseJsonStr(tyval)) |tys| {
                    if (std.mem.eql(u8, tys, "function_call")) {
                        var cid: []u8 = &.{};
                        var nm: []u8 = &.{};
                        if (item.get("call_id")) |cv| {
                            if (sseJsonStr(cv)) |cs| cid = try allocator.dupe(u8, cs);
                        }
                        if (item.get("name")) |nv| {
                            if (sseJsonStr(nv)) |ns| nm = try allocator.dupe(u8, ns);
                        }
                        // Key by call_id for delta routing.
                        const key = try allocator.dupe(u8, cid);
                        errdefer allocator.free(key);
                        // If a call with same key exists, finalize it first.
                        if (sseFindActive(active, key)) |existing| {
                            if (existing.name.len > 0) {
                                try calls.append(existing.*);
                            } else {
                                if (existing.call_id.len > 0) allocator.free(existing.call_id);
                                if (existing.name.len > 0) allocator.free(existing.name);
                                if (existing.args.len > 0) allocator.free(existing.args);
                                if (existing.key.len > 0) allocator.free(existing.key);
                            }
                            // Remove from active.
                            for (active.items, 0..) |*ac, idx| {
                                if (ac == existing) {
                                    _ = active.orderedRemove(idx);
                                    break;
                                }
                            }
                        }
                        try active.append(.{
                            .call_id = cid,
                            .name = nm,
                            .args = &.{},
                            .key = key,
                        });
                    }
                }
            }
        }
    } else if (std.mem.eql(u8, tstr, "response.function_call_arguments.delta")) {
        // Route by item_id if present, else use most recent active.
        var target: ?*SseCall = null;
        if (obj.get("item_id")) |idval| {
            if (sseJsonStr(idval)) |ids| {
                target = sseFindActive(active, ids);
            }
        }
        if (target == null and active.items.len > 0) {
            target = &active.items[active.items.len - 1];
        }
        if (target) |cc| {
            if (obj.get("delta")) |dval| {
                if (sseJsonStr(dval)) |ds| {
                    const old_args = cc.args;
                    const new_args = try std.mem.concat(allocator, u8, &.{ old_args, ds });
                    if (old_args.len > 0) allocator.free(old_args);
                    cc.args = new_args;
                }
            }
        }
    } else if (std.mem.eql(u8, tstr, "response.completed")) {
        stream_done.* = true;
    }
}
fn sseHandleChatEvent(
    allocator: std.mem.Allocator,
    root: std.json.Value,
    text: *std.array_list.Managed(u8),
    reasoning: *std.array_list.Managed(u8),
    calls: *std.array_list.Managed(SseCall),
    active: *std.array_list.Managed(SseCall),
    stream_done: *bool,
    stdout: anytype,
) !void {
    _ = stream_done;
    const obj = switch (root) { .object => |o| o, else => return };
    const cval = obj.get("choices") orelse return;
    const carr = switch (cval) { .array => |a| a, else => return };
    if (carr.items.len == 0) return;
    const choice = switch (carr.items[0]) { .object => |o| o, else => return };
    const dval = choice.get("delta") orelse return;
    const delta = switch (dval) { .object => |o| o, else => return };

    if (delta.get("content")) |cv| {
        if (sseJsonStr(cv)) |cs| {
            try stdout.writeAll(cs);
            try text.appendSlice(cs);
        }
    }

    // Reasoning text (chat shapes: delta.reasoning on some
    // gateways, delta.reasoning_content on DeepSeek-style APIs).
    // Accumulated separately; never printed, never mixed into
    // the answer text.
    if (delta.get("reasoning")) |rv| {
        if (sseJsonStr(rv)) |rs| {
            try reasoning.appendSlice(rs);
        }
    }
    if (delta.get("reasoning_content")) |rv| {
        if (sseJsonStr(rv)) |rs| {
            try reasoning.appendSlice(rs);
        }
    }

    if (delta.get("tool_calls")) |tcval| {
        const tcarr = switch (tcval) { .array => |a| a, else => return };
        for (tcarr.items) |tcitem| {
            const tc = switch (tcitem) { .object => |o| o, else => continue };
            // Get index for routing (default "0").
            var idx_buf: [16]u8 = undefined;
            var idx_str: []const u8 = "0";
            if (tc.get("index")) |ixval| {
                switch (ixval) {
                    .integer => |ix| {
                        idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{ix}) catch "0";
                    },
                    else => {},
                }
            }
            if (tc.get("id")) |idval| {
                if (sseJsonStr(idval)) |ids| {
                    // New call with this index: finalize previous with same index.
                    if (sseFindActive(active, idx_str)) |existing| {
                        if (existing.name.len > 0) {
                            try calls.append(existing.*);
                        } else {
                            if (existing.call_id.len > 0) allocator.free(existing.call_id);
                            if (existing.name.len > 0) allocator.free(existing.name);
                            if (existing.args.len > 0) allocator.free(existing.args);
                            if (existing.key.len > 0) allocator.free(existing.key);
                        }
                        for (active.items, 0..) |*ac, i| {
                            if (ac == existing) {
                                _ = active.orderedRemove(i);
                                break;
                            }
                        }
                    }
                    var nm: []u8 = &.{};
                    var ag: []u8 = &.{};
                    if (tc.get("function")) |fval| {
                        const func = switch (fval) { .object => |o| o, else => null };
                        if (func) |fo| {
                            if (fo.get("name")) |nv| {
                                if (sseJsonStr(nv)) |ns| nm = try allocator.dupe(u8, ns);
                            }
                            if (fo.get("arguments")) |av| {
                                if (sseJsonStr(av)) |as| ag = try allocator.dupe(u8, as);
                            }
                        }
                    }
                    const key = try allocator.dupe(u8, idx_str);
                    errdefer allocator.free(key);
                    try active.append(.{
                        .call_id = try allocator.dupe(u8, ids),
                        .name = nm,
                        .args = ag,
                        .key = key,
                    });
                }
            } else if (tc.get("function")) |fval| {
                // Arguments delta: route by index.
                if (sseFindActive(active, idx_str)) |cc| {
                    const func = switch (fval) { .object => |o| o, else => continue };
                    if (func.get("arguments")) |av| {
                        if (sseJsonStr(av)) |as| {
                            const old_args = cc.args;
                            const new_args = try std.mem.concat(allocator, u8, &.{ old_args, as });
                            if (old_args.len > 0) allocator.free(old_args);
                            cc.args = new_args;
                        }
                    }
                }
            }
        }
    }
}
pub fn sseJsonEscape(out: *std.array_list.Managed(u8), s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            else => try out.append(ch),
        }
    }
}
/// Frees all four out buffers of an sse turn at once
/// (sa_http_client_sse_turn / _ex). Exists alongside the
/// per-buffer sa_http_client_sse_turn_free: that one returns
/// void, and SLA codegen cannot pass plain ptrs to
/// void-returning ptr externs (CapabilityMismatch), while
/// value-returning externs accept them. Zero-length outs are
/// skipped (their slices may be sentinels, not allocations).
pub export fn sa_http_client_sse_turn_free_all(
    text_ptr: ?[*]u8, text_len: u64,
    calls_ptr: ?[*]u8, calls_len: u64,
    usage_ptr: ?[*]u8, usage_len: u64,
    reasoning_ptr: ?[*]u8, reasoning_len: u64,
) u32 {
    if (text_len > 0) sa_http_client_sse_turn_free(text_ptr, text_len);
    if (calls_len > 0) sa_http_client_sse_turn_free(calls_ptr, calls_len);
    if (usage_len > 0) sa_http_client_sse_turn_free(usage_ptr, usage_len);
    if (reasoning_len > 0) sa_http_client_sse_turn_free(reasoning_ptr, reasoning_len);
    return 0;
}
pub export fn sa_http_client_sse_turn_free(ptr: ?[*]u8, len: u64) void {
    if (ptr) |p| {
        const slice = p[0..@intCast(len)];
        std.heap.page_allocator.free(slice);
    }
}
