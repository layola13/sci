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
