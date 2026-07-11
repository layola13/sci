const std = @import("std");

// Cooperative request cancellation for the daemon: each request may carry an
// agent_id + generation. When a newer generation from the same agent arrives,
// older in-flight/queued requests are recognized as superseded and skipped.
// This is entry-level cooperative cancellation, not mid-compile interruption.

var agent_gen_mutex: std.Thread.Mutex = .{};
var agent_gen_map: ?std.StringHashMap(u64) = null;

fn agentGenMap() *std.StringHashMap(u64) {
    if (agent_gen_map == null) {
        agent_gen_map = std.StringHashMap(u64).init(std.heap.page_allocator);
    }
    return &agent_gen_map.?;
}

// Register (agent_id, generation) as the latest seen. Returns true if this
// generation should proceed, false if a newer one was already registered.
pub fn registerGeneration(agent_id: []const u8, generation: u64) bool {
    if (agent_id.len == 0) return true;
    agent_gen_mutex.lock();
    defer agent_gen_mutex.unlock();
    const map = agentGenMap();
    const gop = map.getOrPut(agent_id) catch return true;
    if (gop.found_existing) {
        if (generation < gop.value_ptr.*) return false;
        gop.value_ptr.* = generation;
        return true;
    }
    const owned = std.heap.page_allocator.dupe(u8, agent_id) catch return true;
    gop.key_ptr.* = owned;
    gop.value_ptr.* = generation;
    return true;
}

// Check whether this request's generation is still current.
pub fn generationIsCurrent(agent_id: []const u8, generation: u64) bool {
    if (agent_id.len == 0) return true;
    agent_gen_mutex.lock();
    defer agent_gen_mutex.unlock();
    const map = agentGenMap();
    if (map.get(agent_id)) |latest| {
        return generation >= latest;
    }
    return true;
}

pub fn parseJsonU64Field(request: []const u8, field: []const u8) ?u64 {
    const key_pos = std.mem.indexOf(u8, request, field) orelse return null;
    var i = key_pos + field.len;
    while (i < request.len and (request[i] == ' ' or request[i] == ':' or request[i] == '"')) i += 1;
    var val: u64 = 0;
    var found = false;
    while (i < request.len and request[i] >= '0' and request[i] <= '9') {
        val = val * 10 + (request[i] - '0');
        i += 1;
        found = true;
    }
    return if (found) val else null;
}

pub fn parseJsonStrField(request: []const u8, field: []const u8) ?[]const u8 {
    const key_pos = std.mem.indexOf(u8, request, field) orelse return null;
    var i = key_pos + field.len;
    while (i < request.len and (request[i] == ' ' or request[i] == ':')) i += 1;
    if (i >= request.len or request[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < request.len and request[i] != '"') i += 1;
    if (i >= request.len) return null;
    return request[start..i];
}

test "generation cancellation semantics" {
    try std.testing.expect(registerGeneration("agentX", 1));
    try std.testing.expect(registerGeneration("agentX", 2));
    // older generation after newer is superseded
    try std.testing.expect(!generationIsCurrent("agentX", 1));
    try std.testing.expect(generationIsCurrent("agentX", 2));
    // unknown agent always current
    try std.testing.expect(generationIsCurrent("", 0));
}

test "json field parsing" {
    const req = "{\"argv\":[\"test\"],\"agent_id\":\"A7\",\"generation\":42}";
    try std.testing.expectEqualStrings("A7", parseJsonStrField(req, "\"agent_id\"").?);
    try std.testing.expectEqual(@as(u64, 42), parseJsonU64Field(req, "\"generation\"").?);
    try std.testing.expect(parseJsonStrField(req, "\"missing\"") == null);
}

// Per-agent in-flight quota: bounds how many concurrent requests a single agent
// may hold, so one agent cannot monopolize the daemon's worker pool. Pure,
// mutex-protected counters keyed by agent_id.
var agent_inflight_mutex: std.Thread.Mutex = .{};
var agent_inflight_map: ?std.StringHashMap(u32) = null;

fn agentInflightMap() *std.StringHashMap(u32) {
    if (agent_inflight_map == null) {
        agent_inflight_map = std.StringHashMap(u32).init(std.heap.page_allocator);
    }
    return &agent_inflight_map.?;
}

// Try to acquire an in-flight slot for agent_id. Returns true and increments if
// the agent is below max_per_agent; returns false (no increment) if at/over the
// limit. An empty agent_id or max_per_agent==0 means unlimited (always true).
pub fn tryAcquireSlot(agent_id: []const u8, max_per_agent: u32) bool {
    if (agent_id.len == 0 or max_per_agent == 0) return true;
    agent_inflight_mutex.lock();
    defer agent_inflight_mutex.unlock();
    const map = agentInflightMap();
    const gop = map.getOrPut(agent_id) catch return true;
    if (!gop.found_existing) {
        const owned = std.heap.page_allocator.dupe(u8, agent_id) catch return true;
        gop.key_ptr.* = owned;
        gop.value_ptr.* = 0;
    }
    if (gop.value_ptr.* >= max_per_agent) return false;
    gop.value_ptr.* += 1;
    return true;
}

// Release a previously acquired in-flight slot for agent_id.
pub fn releaseSlot(agent_id: []const u8) void {
    if (agent_id.len == 0) return;
    agent_inflight_mutex.lock();
    defer agent_inflight_mutex.unlock();
    const map = agentInflightMap();
    if (map.getPtr(agent_id)) |count| {
        if (count.* > 0) count.* -= 1;
    }
}

test "per-agent quota acquire and release" {
    // Under limit: two acquires with max=2 succeed, third fails.
    try std.testing.expect(tryAcquireSlot("qA", 2));
    try std.testing.expect(tryAcquireSlot("qA", 2));
    try std.testing.expect(!tryAcquireSlot("qA", 2));
    // Release one, then another acquire succeeds.
    releaseSlot("qA");
    try std.testing.expect(tryAcquireSlot("qA", 2));
    // Empty agent id and max=0 are unlimited.
    try std.testing.expect(tryAcquireSlot("", 1));
    try std.testing.expect(tryAcquireSlot("qB", 0));
}

// Per-agent in-flight quota: prevents a single agent from occupying all daemon
// workers and starving others. agent_id == "" is unlimited.
var agent_inflight_mutex: std.Thread.Mutex = .{};
var agent_inflight_map: ?std.StringHashMap(u32) = null;
var per_agent_limit: u32 = 4;

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
    if (gop.value_ptr.* >= per_agent_limit) return false;
    gop.value_ptr.* += 1;
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
}
