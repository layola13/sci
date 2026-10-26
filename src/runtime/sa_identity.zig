//! sa_std identity-keyed collections (2026-10-26): the sanctioned
//! native substitute for JS WeakMap / WeakSet in converted CXU code.
//!
//! Deliberate difference, stated plainly: these collections are
//! STRONG, not weak. SA/SLA has no garbage collector and sa_std has
//! no finalization hook, so the WeakMap behaviour "the entry vanishes
//! when the key object dies" has no counterpart here and is NOT
//! emulated. Keys are u64 identity tokens chosen by the caller (an
//! object's address, or a stable per-object id such as a runtime
//! handle); entries live until sa_idmap_remove / sa_idset_remove,
//! clear, or free. Callers that key by short-lived objects must
//! remove entries when the object goes away — several CXU call sites
//! already keep that discipline with WeakMap.delete (request attempt
//! stores, pending upgrade tables, history caches).
//!
//! Census behind this surface (2026-10-26): every real WeakMap /
//! WeakSet use in CXU is an identity-keyed side table using only
//! get/set/has/delete — miniModelHistory session history cache,
//! omniRouteFree kernel-identity / forced-shape / injection-context /
//! attempt stores, server runtime request tables — and none of them
//! rely on automatic eviction for correctness, only for memory
//! reclamation of entries whose keys died without a delete.
//!
//! Instances live in a mutex-guarded process-wide registry keyed by
//! handle. Handles are monotonically issued and never reused, so a
//! stale handle reports NOT_FOUND instead of aliasing a newer map.
//! Map values are byte strings (copy-in / copy-out, the sa_globals /
//! sa_ts convention); the _u64 pair stores a u64 in the same map as
//! its 8-byte little-endian encoding. Status codes mirror
//! sa_std.zig (SA_STD_ERR_*): OK=0, INVALID_ARGUMENT=1, NOT_FOUND=3,
//! NO_MEMORY=5, TRUNCATED=9.

const std = @import("std");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_TRUNCATED: i32 = 9;

const IdMap = struct {
    entries: std.AutoHashMapUnmanaged(u64, []u8) = .empty,

    fn deinit(self: *IdMap, alloc: std.mem.Allocator) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        self.entries.deinit(alloc);
    }

    fn clear(self: *IdMap, alloc: std.mem.Allocator) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        self.entries.clearRetainingCapacity();
    }
};

const IdSet = struct {
    keys: std.AutoHashMapUnmanaged(u64, void) = .empty,

    fn deinit(self: *IdSet, alloc: std.mem.Allocator) void {
        self.keys.deinit(alloc);
    }

    fn clear(self: *IdSet) void {
        self.keys.clearRetainingCapacity();
    }
};

var identity_mu = std.Io.Mutex.init;
var idmaps: std.AutoHashMapUnmanaged(u64, *IdMap) = .empty;
var idsets: std.AutoHashMapUnmanaged(u64, *IdSet) = .empty;
var next_handle: u64 = 1;

/// Caller must hold identity_mu.
fn lookupMap(handle: u64) ?*IdMap {
    if (handle == 0) return null;
    return idmaps.get(handle);
}

/// Caller must hold identity_mu.
fn lookupSet(handle: u64) ?*IdSet {
    if (handle == 0) return null;
    return idsets.get(handle);
}

fn handleStatus(handle: u64) i32 {
    return if (handle == 0) ERR_INVALID else ERR_NOT_FOUND;
}

// ---------------- idmap ----------------

pub export fn sa_idmap_new(out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    const alloc = std.heap.page_allocator;
    const map = alloc.create(IdMap) catch return ERR_NOMEM;
    map.* = .{};
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const handle = next_handle;
    idmaps.put(alloc, handle, map) catch {
        map.deinit(alloc);
        alloc.destroy(map);
        return ERR_NOMEM;
    };
    next_handle += 1;
    out_ptr.* = handle;
    return OK;
}

pub export fn sa_idmap_free(handle: u64) i32 {
    if (handle == 0) return ERR_INVALID;
    const alloc = std.heap.page_allocator;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const kv = idmaps.fetchRemove(handle) orelse return ERR_NOT_FOUND;
    kv.value.deinit(alloc);
    alloc.destroy(kv.value);
    return OK;
}

pub export fn sa_idmap_set(handle: u64, key: u64, val_ptr: ?[*]const u8, val_len: u64) i32 {
    if (val_len > 0 and val_ptr == null) return ERR_INVALID;
    const alloc = std.heap.page_allocator;
    const src: []const u8 = if (val_len == 0) &.{} else val_ptr.?[0..@intCast(val_len)];
    const copy = alloc.dupe(u8, src) catch return ERR_NOMEM;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const map = lookupMap(handle) orelse {
        alloc.free(copy);
        return handleStatus(handle);
    };
    const gop = map.entries.getOrPut(alloc, key) catch {
        alloc.free(copy);
        return ERR_NOMEM;
    };
    if (gop.found_existing) alloc.free(gop.value_ptr.*);
    gop.value_ptr.* = copy;
    return OK;
}

pub export fn sa_idmap_get(handle: u64, key: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return ERR_INVALID;
    len_ptr.* = 0;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const map = lookupMap(handle) orelse return handleStatus(handle);
    const value = map.entries.get(key) orelse return ERR_NOT_FOUND;
    len_ptr.* = @intCast(value.len);
    if (value.len > cap) return ERR_TRUNCATED;
    if (value.len > 0) {
        const buf = buf_ptr orelse return ERR_INVALID;
        @memcpy(buf[0..value.len], value);
    }
    return OK;
}

pub export fn sa_idmap_set_u64(handle: u64, key: u64, value: u64) i32 {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    return sa_idmap_set(handle, key, &bytes, bytes.len);
}

pub export fn sa_idmap_get_u64(handle: u64, key: u64, out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const map = lookupMap(handle) orelse return handleStatus(handle);
    const value = map.entries.get(key) orelse return ERR_NOT_FOUND;
    if (value.len != 8) return ERR_INVALID;
    out_ptr.* = std.mem.readInt(u64, value[0..8], .little);
    return OK;
}

pub export fn sa_idmap_has(handle: u64, key: u64, out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const map = lookupMap(handle) orelse return handleStatus(handle);
    out_ptr.* = if (map.entries.contains(key)) 1 else 0;
    return OK;
}

pub export fn sa_idmap_remove(handle: u64, key: u64) i32 {
    const alloc = std.heap.page_allocator;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const map = lookupMap(handle) orelse return handleStatus(handle);
    const kv = map.entries.fetchRemove(key) orelse return ERR_NOT_FOUND;
    alloc.free(kv.value);
    return OK;
}

pub export fn sa_idmap_len(handle: u64, out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const map = lookupMap(handle) orelse return handleStatus(handle);
    out_ptr.* = @intCast(map.entries.count());
    return OK;
}

pub export fn sa_idmap_clear(handle: u64) i32 {
    const alloc = std.heap.page_allocator;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const map = lookupMap(handle) orelse return handleStatus(handle);
    map.clear(alloc);
    return OK;
}

// ---------------- idset ----------------

pub export fn sa_idset_new(out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    const alloc = std.heap.page_allocator;
    const set = alloc.create(IdSet) catch return ERR_NOMEM;
    set.* = .{};
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const handle = next_handle;
    idsets.put(alloc, handle, set) catch {
        set.deinit(alloc);
        alloc.destroy(set);
        return ERR_NOMEM;
    };
    next_handle += 1;
    out_ptr.* = handle;
    return OK;
}

pub export fn sa_idset_free(handle: u64) i32 {
    if (handle == 0) return ERR_INVALID;
    const alloc = std.heap.page_allocator;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const kv = idsets.fetchRemove(handle) orelse return ERR_NOT_FOUND;
    kv.value.deinit(alloc);
    alloc.destroy(kv.value);
    return OK;
}

pub export fn sa_idset_add(handle: u64, key: u64) i32 {
    const alloc = std.heap.page_allocator;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const set = lookupSet(handle) orelse return handleStatus(handle);
    set.keys.put(alloc, key, {}) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_idset_has(handle: u64, key: u64, out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const set = lookupSet(handle) orelse return handleStatus(handle);
    out_ptr.* = if (set.keys.contains(key)) 1 else 0;
    return OK;
}

pub export fn sa_idset_remove(handle: u64, key: u64) i32 {
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const set = lookupSet(handle) orelse return handleStatus(handle);
    if (!set.keys.remove(key)) return ERR_NOT_FOUND;
    return OK;
}

pub export fn sa_idset_len(handle: u64, out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const set = lookupSet(handle) orelse return handleStatus(handle);
    out_ptr.* = @intCast(set.keys.count());
    return OK;
}

pub export fn sa_idset_clear(handle: u64) i32 {
    identity_mu.lockUncancelable(sio.io());
    defer identity_mu.unlock(sio.io());
    const set = lookupSet(handle) orelse return handleStatus(handle);
    set.clear();
    return OK;
}

// ---------------- tests ----------------

test "identity: idmap set/get roundtrip, overwrite, has and len" {
    var h: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_new(&h));
    try std.testing.expect(h != 0);
    defer _ = sa_idmap_free(h);

    var out_len: u64 = 0;
    var buf: [16]u8 = undefined;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_idmap_get(h, 42, &buf, buf.len, &out_len));

    try std.testing.expectEqual(OK, sa_idmap_set(h, 42, "abc".ptr, 3));
    try std.testing.expectEqual(OK, sa_idmap_get(h, 42, &buf, buf.len, &out_len));
    try std.testing.expectEqual(@as(u64, 3), out_len);
    try std.testing.expectEqualStrings("abc", buf[0..3]);

    try std.testing.expectEqual(OK, sa_idmap_set(h, 42, "z".ptr, 1));
    try std.testing.expectEqual(OK, sa_idmap_get(h, 42, &buf, buf.len, &out_len));
    try std.testing.expectEqualStrings("z", buf[0..out_len]);

    var flag: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_has(h, 42, &flag));
    try std.testing.expectEqual(@as(u64, 1), flag);
    try std.testing.expectEqual(OK, sa_idmap_has(h, 7, &flag));
    try std.testing.expectEqual(@as(u64, 0), flag);

    try std.testing.expectEqual(OK, sa_idmap_set(h, 7, "q".ptr, 1));
    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_len(h, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
}

test "identity: idmap copy-in isolation and TRUNCATED reports required length" {
    var h: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_new(&h));
    defer _ = sa_idmap_free(h);

    var src = [_]u8{ 'a', 'b', 'c', 'd' };
    try std.testing.expectEqual(OK, sa_idmap_set(h, 1, &src, src.len));
    src[0] = 'X';

    var small: [2]u8 = undefined;
    var out_len: u64 = 0;
    try std.testing.expectEqual(ERR_TRUNCATED, sa_idmap_get(h, 1, &small, small.len, &out_len));
    try std.testing.expectEqual(@as(u64, 4), out_len);

    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(OK, sa_idmap_get(h, 1, &buf, buf.len, &out_len));
    try std.testing.expectEqualStrings("abcd", &buf);
}

test "identity: idmap u64 values share the byte store" {
    var h: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_new(&h));
    defer _ = sa_idmap_free(h);

    try std.testing.expectEqual(OK, sa_idmap_set_u64(h, 9, 0x0102030405060708));
    var v: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_get_u64(h, 9, &v));
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), v);

    var buf: [8]u8 = undefined;
    var out_len: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_get(h, 9, &buf, buf.len, &out_len));
    try std.testing.expectEqual(@as(u64, 8), out_len);
    try std.testing.expectEqual(@as(u8, 0x08), buf[0]);

    // A byte value of a different length is not a u64 value.
    try std.testing.expectEqual(OK, sa_idmap_set(h, 10, "abc".ptr, 3));
    try std.testing.expectEqual(ERR_INVALID, sa_idmap_get_u64(h, 10, &v));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_idmap_get_u64(h, 11, &v));
}

test "identity: idmap remove, clear, free and stale handles" {
    var h: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_new(&h));
    try std.testing.expectEqual(OK, sa_idmap_set(h, 1, "a".ptr, 1));
    try std.testing.expectEqual(OK, sa_idmap_set(h, 2, "b".ptr, 1));

    try std.testing.expectEqual(OK, sa_idmap_remove(h, 1));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_idmap_remove(h, 1));

    try std.testing.expectEqual(OK, sa_idmap_clear(h));
    var n: u64 = 99;
    try std.testing.expectEqual(OK, sa_idmap_len(h, &n));
    try std.testing.expectEqual(@as(u64, 0), n);

    try std.testing.expectEqual(OK, sa_idmap_free(h));
    var flag: u64 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_idmap_has(h, 2, &flag));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_idmap_free(h));

    // Handles are never reused: a fresh map gets a different handle.
    var h2: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_new(&h2));
    try std.testing.expect(h2 != h);
    defer _ = sa_idmap_free(h2);

    try std.testing.expectEqual(ERR_INVALID, sa_idmap_has(0, 2, &flag));
}

test "identity: idmap instances are independent" {
    var a: u64 = 0;
    var b: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_new(&a));
    try std.testing.expectEqual(OK, sa_idmap_new(&b));
    defer _ = sa_idmap_free(a);
    defer _ = sa_idmap_free(b);

    try std.testing.expectEqual(OK, sa_idmap_set(a, 5, "A".ptr, 1));
    try std.testing.expectEqual(OK, sa_idmap_set(b, 5, "B".ptr, 1));
    var buf: [1]u8 = undefined;
    var out_len: u64 = 0;
    try std.testing.expectEqual(OK, sa_idmap_get(a, 5, &buf, buf.len, &out_len));
    try std.testing.expectEqualStrings("A", &buf);
    try std.testing.expectEqual(OK, sa_idmap_get(b, 5, &buf, buf.len, &out_len));
    try std.testing.expectEqualStrings("B", &buf);
}

test "identity: idset add/has/remove/len/clear" {
    var s: u64 = 0;
    try std.testing.expectEqual(OK, sa_idset_new(&s));
    try std.testing.expect(s != 0);
    defer _ = sa_idset_free(s);

    var flag: u64 = 0;
    try std.testing.expectEqual(OK, sa_idset_has(s, 100, &flag));
    try std.testing.expectEqual(@as(u64, 0), flag);

    try std.testing.expectEqual(OK, sa_idset_add(s, 100));
    try std.testing.expectEqual(OK, sa_idset_add(s, 100));
    try std.testing.expectEqual(OK, sa_idset_add(s, 200));
    try std.testing.expectEqual(OK, sa_idset_has(s, 100, &flag));
    try std.testing.expectEqual(@as(u64, 1), flag);

    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_idset_len(s, &n));
    try std.testing.expectEqual(@as(u64, 2), n);

    try std.testing.expectEqual(OK, sa_idset_remove(s, 100));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_idset_remove(s, 100));

    try std.testing.expectEqual(OK, sa_idset_clear(s));
    try std.testing.expectEqual(OK, sa_idset_len(s, &n));
    try std.testing.expectEqual(@as(u64, 0), n);

    try std.testing.expectEqual(OK, sa_idset_free(s));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_idset_has(s, 200, &flag));
}
