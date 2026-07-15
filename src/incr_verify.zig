const std = @import("std");
const verification_input = @import("verification_input.zig");

pub const ConsumerCapability = enum {
    verdict_only,
    needs_annotations,
};

pub const VerdictLookup = enum {
    hit,
    miss,
    unsupported_consumer,
};

const max_verdict_entries: usize = 4096;

var mutex: std.Thread.Mutex = .{};
var passed_map: ?std.AutoHashMap(verification_input.Digest, void) = null;

pub var hits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
pub var misses: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

fn verdictMap() *std.AutoHashMap(verification_input.Digest, void) {
    if (passed_map == null) {
        passed_map = std.AutoHashMap(verification_input.Digest, void).init(std.heap.page_allocator);
    }
    return &passed_map.?;
}

/// A boolean verdict cache is intentionally unavailable to any consumer that
/// needs annotations, deltas, gas, symbols, signatures, or source maps.
pub fn lookupVerdict(digest: verification_input.Digest, consumer: ConsumerCapability) VerdictLookup {
    if (consumer != .verdict_only) return .unsupported_consumer;

    mutex.lock();
    defer mutex.unlock();
    if (verdictMap().contains(digest)) {
        _ = hits.fetchAdd(1, .monotonic);
        return .hit;
    }
    _ = misses.fetchAdd(1, .monotonic);
    return .miss;
}

/// Called only by the Referee verdict-only wrapper after a real successful
/// verification. Trap results and arbitrary instruction streams never enter
/// this namespace.
pub fn recordVerifiedAfterRefereeSuccess(digest: verification_input.Digest) void {
    mutex.lock();
    defer mutex.unlock();
    const map = verdictMap();
    if (!map.contains(digest) and map.count() >= max_verdict_entries) {
        // Keep the process-local cache byte-bounded without introducing an
        // unreviewed persistence or eviction policy. A later daemon LRU can
        // replace this coarse generation rollover.
        map.clearRetainingCapacity();
    }
    map.put(digest, {}) catch {};
}

pub fn clear() void {
    mutex.lock();
    defer mutex.unlock();
    if (passed_map) |*map| map.clearRetainingCapacity();
    hits.store(0, .monotonic);
    misses.store(0, .monotonic);
}

pub fn stats() struct { hits: u64, misses: u64 } {
    return .{
        .hits = hits.load(.monotonic),
        .misses = misses.load(.monotonic),
    };
}

test "verdict cache requires an explicit verdict-only consumer" {
    clear();
    const digest = verification_input.Digest{ .bytes = [_]u8{1} ** 32 };
    try std.testing.expectEqual(VerdictLookup.miss, lookupVerdict(digest, .verdict_only));
    recordVerifiedAfterRefereeSuccess(digest);
    try std.testing.expectEqual(VerdictLookup.hit, lookupVerdict(digest, .verdict_only));
    try std.testing.expectEqual(VerdictLookup.unsupported_consumer, lookupVerdict(digest, .needs_annotations));
    try std.testing.expectEqual(@as(u64, 1), stats().hits);
    try std.testing.expectEqual(@as(u64, 1), stats().misses);
}

test "verdict cache does not share a raw digest namespace" {
    clear();
    const first = verification_input.Digest{ .bytes = [_]u8{2} ** 32 };
    const second = verification_input.Digest{ .bytes = [_]u8{3} ** 32 };
    recordVerifiedAfterRefereeSuccess(first);
    try std.testing.expectEqual(VerdictLookup.hit, lookupVerdict(first, .verdict_only));
    try std.testing.expectEqual(VerdictLookup.miss, lookupVerdict(second, .verdict_only));
}
