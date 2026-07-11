const std = @import("std");

// Selective test execution ("--affected"): remembers which (source, filter)
// inputs have already passed, so re-running an unchanged test file is skipped.
// Process-scoped (daemon-persistent across requests). Sound: only records a
// pass after an all-pass run; any source edit changes the digest.

var passed_mutex: std.Thread.Mutex = .{};
var passed_map: ?std.StringHashMap(void) = null;

fn passedMap() *std.StringHashMap(void) {
    if (passed_map == null) {
        passed_map = std.StringHashMap(void).init(std.heap.page_allocator);
    }
    return &passed_map.?;
}

// Hex digest of (source content, filter). Stable key for the pass cache.
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
    return passedMap().contains(&digest);
}

pub fn recordPass(digest: [64]u8) void {
    passed_mutex.lock();
    defer passed_mutex.unlock();
    const owned = std.heap.page_allocator.dupe(u8, &digest) catch return;
    passedMap().put(owned, {}) catch {};
}

test "affected pass cache records and detects" {
    const d1 = hashInput("fn main() {}", null);
    try std.testing.expect(!isCachedPass(d1));
    recordPass(d1);
    try std.testing.expect(isCachedPass(d1));
    // different source => different digest => not cached
    const d2 = hashInput("fn main() { return; }", null);
    try std.testing.expect(!isCachedPass(d2));
    // filter is part of the key
    const d3 = hashInput("fn main() {}", "someFilter");
    try std.testing.expect(!isCachedPass(d3));
}
