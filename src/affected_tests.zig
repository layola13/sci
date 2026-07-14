const std = @import("std");

// Selective test execution helpers.
//
// Level 1 (legacy/simple): whole-source pass cache keyed by (source, filter).
// Level 2 (call-graph): remember last-good per-function body hashes and compute
// the set of tests that transitively cover changed functions.

var passed_mutex: std.Thread.Mutex = .{};
var passed_map: ?std.StringHashMap(void) = null;

var fn_mutex: std.Thread.Mutex = .{};
var fn_hash_map: ?std.StringHashMap([32]u8) = null;

pub var hits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
pub var misses: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

fn passedMap() *std.StringHashMap(void) {
    if (passed_map == null) {
        passed_map = std.StringHashMap(void).init(std.heap.page_allocator);
    }
    return &passed_map.?;
}

fn fnHashMap() *std.StringHashMap([32]u8) {
    if (fn_hash_map == null) {
        fn_hash_map = std.StringHashMap([32]u8).init(std.heap.page_allocator);
    }
    return &fn_hash_map.?;
}

pub fn hashInput(source: []const u8, filter: ?[]const u8) [64]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(source);
    h.update("\x00");
    if (filter) |f| h.update(f);
    var raw: [32]u8 = undefined;
    h.final(&raw);
    var hex: [64]u8 = undefined;
    const digits = "0123456789abcdef";
    for (raw, 0..) |b, i| {
        hex[i * 2] = digits[b >> 4];
        hex[i * 2 + 1] = digits[b & 0xf];
    }
    return hex;
}

pub fn isCachedPass(digest: [64]u8) bool {
    passed_mutex.lock();
    defer passed_mutex.unlock();
    const hit = passedMap().contains(&digest);
    if (hit) {
        _ = hits.fetchAdd(1, .monotonic);
    } else {
        _ = misses.fetchAdd(1, .monotonic);
    }
    return hit;
}

pub fn recordPass(digest: [64]u8) void {
    passed_mutex.lock();
    defer passed_mutex.unlock();
    const owned = std.heap.page_allocator.dupe(u8, &digest) catch return;
    passedMap().put(owned, {}) catch {
        std.heap.page_allocator.free(owned);
    };
}

pub fn hashFunctionBody(name: []const u8, body_raw_texts: []const []const u8) [32]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update("sa-fn-body-v1");
    h.update(name);
    h.update("\x00");
    for (body_raw_texts) |line| {
        h.update(line);
        h.update("\n");
    }
    var out: [32]u8 = undefined;
    h.final(&out);
    return out;
}

/// Returns true if this function body changed vs the last recorded baseline.
/// Missing baseline counts as changed (first run establishes baseline later).
pub fn functionChanged(name: []const u8, digest: [32]u8) bool {
    fn_mutex.lock();
    defer fn_mutex.unlock();
    if (fnHashMap().get(name)) |prev| {
        return !std.mem.eql(u8, &prev, &digest);
    }
    return true;
}

pub fn recordFunctionHash(name: []const u8, digest: [32]u8) void {
    fn_mutex.lock();
    defer fn_mutex.unlock();
    const map = fnHashMap();
    if (map.getPtr(name)) |slot| {
        slot.* = digest;
        return;
    }
    const owned = std.heap.page_allocator.dupe(u8, name) catch return;
    map.put(owned, digest) catch {
        std.heap.page_allocator.free(owned);
    };
}

pub fn hasFunctionBaseline() bool {
    fn_mutex.lock();
    defer fn_mutex.unlock();
    return if (fn_hash_map) |*m| m.count() > 0 else false;
}

pub fn clear() void {
    passed_mutex.lock();
    defer passed_mutex.unlock();
    if (passed_map) |*m| {
        var it = m.keyIterator();
        while (it.next()) |k| std.heap.page_allocator.free(k.*);
        m.clearRetainingCapacity();
    }
    fn_mutex.lock();
    defer fn_mutex.unlock();
    if (fn_hash_map) |*m| {
        var it = m.keyIterator();
        while (it.next()) |k| std.heap.page_allocator.free(k.*);
        m.clearRetainingCapacity();
    }
    hits.store(0, .monotonic);
    misses.store(0, .monotonic);
}

pub fn stats() struct { hits: u64, misses: u64 } {
    return .{ .hits = hits.load(.monotonic), .misses = misses.load(.monotonic) };
}

/// Compute reverse adjacency: callee -> list of callers, from edges of form (caller, callee).
/// `edges` is pairs of names. Returns owned map callee -> callers; caller frees keys/values.
pub fn buildReverseCallMap(
    allocator: std.mem.Allocator,
    callers: []const []const u8,
    callees: []const []const u8,
) !std.StringHashMap(std.ArrayList([]const u8)) {
    std.debug.assert(callers.len == callees.len);
    var rev = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    errdefer {
        var it = rev.iterator();
        while (it.next()) |e| e.value_ptr.deinit();
        rev.deinit();
    }
    for (callers, callees) |caller, callee| {
        const gop = try rev.getOrPut(callee);
        if (!gop.found_existing) {
            gop.key_ptr.* = callee;
            gop.value_ptr.* = std.ArrayList([]const u8).init(allocator);
        }
        try gop.value_ptr.append(caller);
    }
    return rev;
}

/// Given changed function names and reverse call edges, return the closed set of
/// functions (including tests) that transitively call any changed function.
pub fn impactedFunctions(
    allocator: std.mem.Allocator,
    changed: []const []const u8,
    rev: *const std.StringHashMap(std.ArrayList([]const u8)),
) !std.StringHashMap(void) {
    var out = std.StringHashMap(void).init(allocator);
    errdefer out.deinit();
    var queue = std.ArrayList([]const u8).init(allocator);
    defer queue.deinit();
    for (changed) |name| {
        try out.put(name, {});
        try queue.append(name);
    }
    var qi: usize = 0;
    while (qi < queue.items.len) : (qi += 1) {
        const cur = queue.items[qi];
        if (rev.get(cur)) |callers| {
            for (callers.items) |caller| {
                const gop = try out.getOrPut(caller);
                if (!gop.found_existing) try queue.append(caller);
            }
        }
    }
    return out;
}

test "affected pass cache records and detects" {
    clear();
    const d1 = hashInput("fn main() {}", null);
    try std.testing.expect(!isCachedPass(d1));
    recordPass(d1);
    try std.testing.expect(isCachedPass(d1));
    const d2 = hashInput("fn main() { return; }", null);
    try std.testing.expect(!isCachedPass(d2));
    const d3 = hashInput("fn main() {}", "someFilter");
    try std.testing.expect(!isCachedPass(d3));
}

test "function body hash change detection" {
    clear();
    const h1 = hashFunctionBody("foo", &.{"x = add 1, 2"});
    const h2 = hashFunctionBody("foo", &.{"x = add 1, 2"});
    const h3 = hashFunctionBody("foo", &.{"x = add 1, 3"});
    try std.testing.expect(std.mem.eql(u8, &h1, &h2));
    try std.testing.expect(!std.mem.eql(u8, &h1, &h3));
    try std.testing.expect(functionChanged("foo", h1));
    recordFunctionHash("foo", h1);
    try std.testing.expect(!functionChanged("foo", h2));
    try std.testing.expect(functionChanged("foo", h3));
}

test "impactedFunctions closes over callers" {
    const allocator = std.testing.allocator;
    // test_a calls foo; test_b calls bar; foo unchanged path
    var rev = try buildReverseCallMap(allocator, &.{ "test_a", "test_b", "foo" }, &.{ "foo", "bar", "helper" });
    defer {
        var it = rev.iterator();
        while (it.next()) |e| e.value_ptr.deinit();
        rev.deinit();
    }
    var impacted = try impactedFunctions(allocator, &.{"helper"}, &rev);
    defer impacted.deinit();
    try std.testing.expect(impacted.contains("helper"));
    try std.testing.expect(impacted.contains("foo"));
    try std.testing.expect(impacted.contains("test_a"));
    try std.testing.expect(!impacted.contains("test_b"));
}
