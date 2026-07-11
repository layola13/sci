const std = @import("std");

// Incremental-verification verdict cache (Phase B, sound minimal form).
//
// This module caches ONLY a boolean verdict: "an instruction stream with this
// exact content hash previously verified OK". It deliberately does NOT cache
// the VerifyOk result, because VerifyOk holds caller-owned heap data
// (annotated instructions, function_sigs, symbols) whose reuse would cause
// double-free, and TrapReport holds ?[]const u8 slices that may dangle.
//
// A verdict cache is sound because it stores no pointers -- only a 32-byte
// hash keyed to a plain bool. Verify remains the source of truth; a cache hit
// lets a verdict-only path (check/audit) skip re-verification of byte-identical
// input. The codegen path, which needs VerifyOk, must still run verify.
//
// Process-scoped (daemon-persistent), mutex-protected.

var mutex: std.Thread.Mutex = .{};
var passed_map: ?std.AutoHashMap([32]u8, void) = null;

fn map() *std.AutoHashMap([32]u8, void) {
    if (passed_map == null) {
        passed_map = std.AutoHashMap([32]u8, void).init(std.heap.page_allocator);
    }
    return &passed_map.?;
}

// Hash the salient, verification-relevant bytes of an instruction stream.
// Callers pass the raw serialized instruction bytes (e.g. the .sab payload or
// the source-derived encoding); any change to the stream changes the hash.
pub fn hashStream(bytes: []const u8) [32]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(bytes);
    var out: [32]u8 = undefined;
    h.final(&out);
    return out;
}

pub fn isVerified(digest: [32]u8) bool {
    mutex.lock();
    defer mutex.unlock();
    return map().contains(digest);
}

pub fn recordVerified(digest: [32]u8) void {
    mutex.lock();
    defer mutex.unlock();
    map().put(digest, {}) catch {};
}

pub fn clear() void {
    mutex.lock();
    defer mutex.unlock();
    if (passed_map) |*m| m.clearRetainingCapacity();
}

test "verdict cache records and detects by content hash" {
    clear();
    const a = hashStream("instr-stream-A");
    const b = hashStream("instr-stream-B");
    try std.testing.expect(!isVerified(a));
    recordVerified(a);
    try std.testing.expect(isVerified(a));
    // different content -> different hash -> not a false hit
    try std.testing.expect(!isVerified(b));
    // identical content -> same hash -> hit
    try std.testing.expect(isVerified(hashStream("instr-stream-A")));
}

test "hashStream is deterministic and change-sensitive" {
    const h1 = hashStream("x");
    const h2 = hashStream("x");
    const h3 = hashStream("y");
    try std.testing.expect(std.mem.eql(u8, &h1, &h2));
    try std.testing.expect(!std.mem.eql(u8, &h1, &h3));
}
