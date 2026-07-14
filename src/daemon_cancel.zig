const std = @import("std");

// Cooperative request cancellation for the daemon: each request may carry an
// agent_id + generation. When a newer generation from the same agent arrives,
// older in-flight/queued requests are recognized as superseded and skipped.
// This is entry-level cooperative cancellation, not mid-compile interruption.

var gen_mutex: std.Thread.Mutex = .{};
var gen_map: ?std.StringHashMap(u64) = null;

fn genMap() *std.StringHashMap(u64) {
    if (gen_map == null) {
        gen_map = std.StringHashMap(u64).init(std.heap.page_allocator);
    }
    return &gen_map.?;
}

// Register (agent_id, generation) as the latest seen. Returns true if this
// generation should proceed, false if a newer one was already registered.
pub fn registerGeneration(agent_id: []const u8, generation: u64) bool {
    if (agent_id.len == 0) return true;
    gen_mutex.lock();
    defer gen_mutex.unlock();
    const map = genMap();
    const gop = map.getOrPut(agent_id) catch return true;
    if (!gop.found_existing) {
        const owned = std.heap.page_allocator.dupe(u8, agent_id) catch return true;
        gop.key_ptr.* = owned;
        gop.value_ptr.* = generation;
        return true;
    }
    if (generation < gop.value_ptr.*) return false;
    gop.value_ptr.* = generation;
    return true;
}

// Check whether this request's generation is still current.
pub fn generationIsCurrent(agent_id: []const u8, generation: u64) bool {
    if (agent_id.len == 0) return true;
    gen_mutex.lock();
    defer gen_mutex.unlock();
    if (genMap().get(agent_id)) |latest| {
        return generation >= latest;
    }
    return true;
}

/// Force-cancel all in-flight work for an agent by bumping generation past any
/// known value. Returns the new generation.
pub fn cancelAgent(agent_id: []const u8) u64 {
    if (agent_id.len == 0) return 0;
    gen_mutex.lock();
    defer gen_mutex.unlock();
    const map = genMap();
    const gop = map.getOrPut(agent_id) catch return 0;
    if (!gop.found_existing) {
        const owned = std.heap.page_allocator.dupe(u8, agent_id) catch return 0;
        gop.key_ptr.* = owned;
        gop.value_ptr.* = 1;
        return 1;
    }
    gop.value_ptr.* += 1;
    return gop.value_ptr.*;
}

pub fn parseJsonStrField(json: []const u8, key: []const u8) ?[]const u8 {
    const kp = std.mem.indexOf(u8, json, key) orelse return null;
    var i = kp + key.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) i += 1;
    if (i >= json.len or json[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < json.len and json[i] != '"') {
        if (json[i] == '\\' and i + 1 < json.len) i += 1;
        i += 1;
    }
    if (i > json.len) return null;
    return json[start..i];
}

pub fn parseJsonU64Field(json: []const u8, key: []const u8) ?u64 {
    const kp = std.mem.indexOf(u8, json, key) orelse return null;
    var i = kp + key.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) i += 1;
    var val: u64 = 0;
    var found = false;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') {
        val = val * 10 + (json[i] - '0');
        i += 1;
        found = true;
    }
    return if (found) val else null;
}

test "generation cancellation semantics" {
    try std.testing.expect(registerGeneration("agentX", 1));
    try std.testing.expect(registerGeneration("agentX", 2));
    // older generation after newer is superseded
    try std.testing.expect(!generationIsCurrent("agentX", 1));
    try std.testing.expect(generationIsCurrent("agentX", 2));
    // unknown agent always current
    try std.testing.expect(generationIsCurrent("", 0));
    const g = cancelAgent("agentX");
    try std.testing.expect(g >= 3);
    try std.testing.expect(!generationIsCurrent("agentX", 2));
}

test "json field parsing" {
    const req = "{\"argv\":[\"test\"],\"agent_id\":\"A7\",\"generation\":42}";
    try std.testing.expectEqualStrings("A7", parseJsonStrField(req, "\"agent_id\"").?);
    try std.testing.expectEqual(@as(u64, 42), parseJsonU64Field(req, "\"generation\"").?);
    try std.testing.expect(parseJsonStrField(req, "\"missing\"") == null);
}

// Per-agent in-flight quota: prevents a single agent from occupying all daemon
// workers and starving others. agent_id == "" is unlimited.
var agent_inflight_mutex: std.Thread.Mutex = .{};
var agent_inflight_map: ?std.StringHashMap(u32) = null;
var per_agent_limit: u32 = 4;

pub var accepted: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
pub var canceled: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
pub var busy_rejects: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

fn agentInflightMap() *std.StringHashMap(u32) {
    if (agent_inflight_map == null) {
        agent_inflight_map = std.StringHashMap(u32).init(std.heap.page_allocator);
    }
    return &agent_inflight_map.?;
}

pub fn setPerAgentLimit(limit: u32) void {
    agent_inflight_mutex.lock();
    defer agent_inflight_mutex.unlock();
    per_agent_limit = limit;
}

pub fn acquireSlot(agent_id: []const u8) bool {
    if (agent_id.len == 0) return true;
    agent_inflight_mutex.lock();
    defer agent_inflight_mutex.unlock();
    const map = agentInflightMap();
    const gop = map.getOrPut(agent_id) catch return true;
    if (!gop.found_existing) {
        const owned = std.heap.page_allocator.dupe(u8, agent_id) catch return true;
        gop.key_ptr.* = owned;
        gop.value_ptr.* = 0;
    }
    if (gop.value_ptr.* >= per_agent_limit) {
        _ = busy_rejects.fetchAdd(1, .monotonic);
        return false;
    }
    gop.value_ptr.* += 1;
    _ = accepted.fetchAdd(1, .monotonic);
    return true;
}

pub fn releaseSlot(agent_id: []const u8) void {
    if (agent_id.len == 0) return;
    agent_inflight_mutex.lock();
    defer agent_inflight_mutex.unlock();
    const map = agentInflightMap();
    if (map.getPtr(agent_id)) |v| {
        if (v.* > 0) v.* -= 1;
    }
}

pub fn noteCanceled() void {
    _ = canceled.fetchAdd(1, .monotonic);
}

pub fn stats() struct { accepted: u64, canceled: u64, busy_rejects: u64 } {
    return .{
        .accepted = accepted.load(.monotonic),
        .canceled = canceled.load(.monotonic),
        .busy_rejects = busy_rejects.load(.monotonic),
    };
}

test "per-agent quota limits in-flight slots" {
    setPerAgentLimit(2);
    try std.testing.expect(acquireSlot("agentQ"));
    try std.testing.expect(acquireSlot("agentQ"));
    try std.testing.expect(!acquireSlot("agentQ"));
    releaseSlot("agentQ");
    try std.testing.expect(acquireSlot("agentQ"));
    try std.testing.expect(acquireSlot(""));
    try std.testing.expect(acquireSlot(""));
    setPerAgentLimit(4);
    // cleanup slots
    releaseSlot("agentQ");
    releaseSlot("agentQ");
}
