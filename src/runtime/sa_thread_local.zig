// Thread-local storage runtime for the sci/sa_std platform layer.
//
// Maps Rust `thread_local!` / `LocalKey<T>` shapes (consumer: sarust rsc,
// see `sarust/STD_MAP.md`): each `thread_local!` static becomes a u64 key
// (FNV-1a of its rustc DefPath, computed by the rsc driver so the .sa side
// stays free of string literals); `sa_thread_local_slot(key)` returns the
// calling thread's u64 cell for that key, zero-initialized on first touch
// (mirrors `Cell::new(0)`; the corpus case is `TLS_N: Cell<u32>`).
//
// Isolation is REAL per-thread, not a process-wide Phase-1 shim: entries are
// keyed by (thread id, key) under a mutex, so two OS threads touching the
// same key observe independent cells. Slots are heap boxes that are never
// freed (same never-free policy as the CA-bundle singleton and the pthread
// registry in sa_std.zig); the table itself only grows by (#threads x #keys).
//
// Status codes follow the sci convention: 0 = SA_STD_OK.
const std = @import("std");

const SA_STD_OK: i32 = 0;

const Entry = struct {
    tid: u64,
    key: u64,
    slot: *u64,
};

var registry_mutex = std.Thread.Mutex{};
var entries = std.ArrayList(Entry).init(std.heap.page_allocator);

/// Availability probe (same `*_supported` convention as the http2/tls/dtls/
/// quic modules). Thread-local storage is pure Zig with no native backend,
/// so it is always available: writes 1, returns SA_STD_OK.
pub export fn sa_thread_local_supported(out_supported: ?*u32) i32 {
    const out = out_supported orelse return SA_STD_ERR_INVALID_ARGUMENT;
    out.* = 1;
    return SA_STD_OK;
}

const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;

/// Calling thread's u64 cell for `key`, zero on first touch.
/// Returns null only on allocator OOM (callers treat 0 as fatal, same as a
/// failed `alloc` in SA).
pub export fn sa_thread_local_slot(key: u64) ?*u64 {
    const tid: u64 = @as(u64, @intCast(std.Thread.getCurrentId()));
    registry_mutex.lock();
    defer registry_mutex.unlock();

    for (entries.items) |e| {
        if (e.tid == tid and e.key == key) return e.slot;
    }
    const slot = std.heap.page_allocator.create(u64) catch return null;
    slot.* = 0;
    entries.append(.{ .tid = tid, .key = key, .slot = slot }) catch {
        std.heap.page_allocator.destroy(slot);
        return null;
    };
    return slot;
}

// ---- module-state value facades (satsgo top-level `let`) ----
//
// Same registry, value semantics: no pointers cross into SA, so frontend
// callers hold no registry memory (none of the borrow/release dynamics of
// the raw slot pointer above). Width discipline (i32/u32/f64) lives in the
// frontend (trunc/zext plus scratch-spill bit round-trips); slots store
// opaque u64 bits. Status follows the sci convention: 0 = SA_STD_OK;
// get has no failure channel and yields 0 on OOM, indistinguishable from
// a fresh slot (see sa_std/modstate.sai).
const SA_STD_ERR_NO_MEMORY: i32 = 5;

pub export fn sa_modstate_get_u64(key: u64) u64 {
    const slot = sa_thread_local_slot(key) orelse return 0;
    return slot.*;
}

pub export fn sa_modstate_set_u64(key: u64, value: u64) i32 {
    const slot = sa_thread_local_slot(key) orelse return SA_STD_ERR_NO_MEMORY;
    slot.* = value;
    return SA_STD_OK;
}

// ---- unit tests (honest registry semantics, same-file style as sa_dtls.zig)
const testing = std.testing;

test "sa_thread_local_supported reports always-available pure-Zig backend" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_thread_local_supported(&flag));
    try testing.expectEqual(@as(u32, 1), flag);
}

test "slot is zero-init, stable per key, and round-trips writes" {
    const key: u64 = 0x544C535F54455354; // "TLS_TEST"
    const s1 = sa_thread_local_slot(key) orelse return error.OutOfMemory;
    try testing.expectEqual(@as(u64, 0), s1.*);
    s1.* = 41;
    const s2 = sa_thread_local_slot(key) orelse return error.OutOfMemory;
    try testing.expect(s1 == s2);
    try testing.expectEqual(@as(u64, 41), s2.*);
    s2.* = 0; // leave no residue for other tests using nearby keys
}

test "distinct keys yield distinct slots" {
    const a = sa_thread_local_slot(0xAAAA) orelse return error.OutOfMemory;
    const b = sa_thread_local_slot(0xBBBB) orelse return error.OutOfMemory;
    try testing.expect(a != b);
}

const IsolCtx = struct {
    key: u64,
    child_slot: ?*u64 = null,
    child_saw: u64 = 0,
};

fn isolChild(ctx: *IsolCtx) void {
    const s = sa_thread_local_slot(ctx.key) orelse return;
    ctx.child_saw = s.*;
    ctx.child_slot = s;
    s.* = 7;
}

test "slots are isolated across OS threads" {
    const key: u64 = 0x49534F4C41544544; // "ISOLATED"
    const parent = sa_thread_local_slot(key) orelse return error.OutOfMemory;
    parent.* = 42;
    var ctx = IsolCtx{ .key = key };
    const t = try std.Thread.spawn(.{}, isolChild, .{&ctx});
    t.join();
    // Child saw a fresh zero cell at a different address; parent untouched.
    try testing.expectEqual(@as(u64, 0), ctx.child_saw);
    try testing.expect(ctx.child_slot != parent);
    try testing.expectEqual(@as(u64, 42), parent.*);
    parent.* = 0;
}

test "modstate get/set round-trips bits through the shared registry" {
    const key: u64 = 0x4D4F445354415445; // "MODSTATE"
    try testing.expectEqual(@as(u64, 0), sa_modstate_get_u64(key));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_modstate_set_u64(key, 0xDEADBEEFCAFEBABE));
    try testing.expectEqual(@as(u64, 0xDEADBEEFCAFEBABE), sa_modstate_get_u64(key));
    // Same cell as the raw slot pointer: one registry, two spellings.
    const slot = sa_thread_local_slot(key) orelse return error.OutOfMemory;
    try testing.expectEqual(@as(u64, 0xDEADBEEFCAFEBABE), slot.*);
    slot.* = 0; // leave no residue for other tests using nearby keys
    try testing.expectEqual(@as(u64, 0), sa_modstate_get_u64(key));
}
