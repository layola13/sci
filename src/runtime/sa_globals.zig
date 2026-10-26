//! sa_std global cells (2026-10-26): process-wide named cells for
//! module-level state in SA/SLA programs. The language ruling is
//! Rust-style: SLA gets NO top-level mutable globals and has no
//! `unsafe` marker; mutable module state lives behind these std
//! functions instead — a mutex-guarded registry keyed by name, with
//! set-once and locked read-modify-write add for u64 cells, and
//! copy-in / copy-out byte cells. u64 and bytes cells are independent
//! namespaces: the same name may hold one of each.
//!
//! Status codes mirror sa_std.zig (SA_STD_ERR_*): OK=0,
//! INVALID_ARGUMENT=1, NOT_FOUND=3, NO_MEMORY=5, TRUNCATED=9.
//! bytes_get follows the sa_ts copyOut convention: when the caller's
//! buffer is too small, out_len still reports the required length and
//! the status is TRUNCATED.

const std = @import("std");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_TRUNCATED: i32 = 9;

const MAX_NAME_LEN: u64 = 1024;

var globals_mu = std.Io.Mutex.init;
var u64_cells: std.StringHashMapUnmanaged(u64) = .empty;
var bytes_cells: std.StringHashMapUnmanaged([]u8) = .empty;

fn cellName(name_ptr: ?[*]const u8, name_len: u64) ?[]const u8 {
    const np = name_ptr orelse return null;
    if (name_len == 0 or name_len > MAX_NAME_LEN) return null;
    return np[0..@intCast(name_len)];
}

/// Inserts a duped key for a fresh entry obtained from getOrPut.
/// On failure the half-inserted entry is removed again.
fn ownKey(map: anytype, alloc: std.mem.Allocator, name: []const u8, gop: anytype) bool {
    const owned = alloc.dupe(u8, name) catch {
        _ = map.remove(name);
        return false;
    };
    gop.key_ptr.* = owned;
    return true;
}

pub export fn sa_global_u64_set(name_ptr: ?[*]const u8, name_len: u64, value: u64) i32 {
    const name = cellName(name_ptr, name_len) orelse return ERR_INVALID;
    const alloc = std.heap.page_allocator;
    globals_mu.lockUncancelable(sio.io());
    defer globals_mu.unlock(sio.io());
    const gop = u64_cells.getOrPut(alloc, name) catch return ERR_NOMEM;
    if (!gop.found_existing and !ownKey(&u64_cells, alloc, name, gop)) return ERR_NOMEM;
    gop.value_ptr.* = value;
    return OK;
}

pub export fn sa_global_u64_get(name_ptr: ?[*]const u8, name_len: u64, out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    const name = cellName(name_ptr, name_len) orelse return ERR_INVALID;
    globals_mu.lockUncancelable(sio.io());
    defer globals_mu.unlock(sio.io());
    const value = u64_cells.get(name) orelse return ERR_NOT_FOUND;
    out_ptr.* = value;
    return OK;
}

pub export fn sa_global_u64_set_once(name_ptr: ?[*]const u8, name_len: u64, value: u64, out_already: ?*u64) i32 {
    const already_ptr = out_already orelse return ERR_INVALID;
    already_ptr.* = 0;
    const name = cellName(name_ptr, name_len) orelse return ERR_INVALID;
    const alloc = std.heap.page_allocator;
    globals_mu.lockUncancelable(sio.io());
    defer globals_mu.unlock(sio.io());
    if (u64_cells.contains(name)) {
        already_ptr.* = 1;
        return OK;
    }
    const gop = u64_cells.getOrPut(alloc, name) catch return ERR_NOMEM;
    if (!ownKey(&u64_cells, alloc, name, gop)) return ERR_NOMEM;
    gop.value_ptr.* = value;
    return OK;
}

pub export fn sa_global_u64_add(name_ptr: ?[*]const u8, name_len: u64, delta: i64, out: ?*u64) i32 {
    const out_ptr = out orelse return ERR_INVALID;
    out_ptr.* = 0;
    const name = cellName(name_ptr, name_len) orelse return ERR_INVALID;
    const alloc = std.heap.page_allocator;
    globals_mu.lockUncancelable(sio.io());
    defer globals_mu.unlock(sio.io());
    const gop = u64_cells.getOrPut(alloc, name) catch return ERR_NOMEM;
    if (!gop.found_existing) {
        if (!ownKey(&u64_cells, alloc, name, gop)) return ERR_NOMEM;
        gop.value_ptr.* = 0;
    }
    // Locked read-modify-write; wraps on overflow (two's complement),
    // matching counter semantics.
    const next = gop.value_ptr.* +% @as(u64, @bitCast(delta));
    gop.value_ptr.* = next;
    out_ptr.* = next;
    return OK;
}

pub export fn sa_global_bytes_set(name_ptr: ?[*]const u8, name_len: u64, val_ptr: ?[*]const u8, val_len: u64) i32 {
    const name = cellName(name_ptr, name_len) orelse return ERR_INVALID;
    if (val_len > 0 and val_ptr == null) return ERR_INVALID;
    const alloc = std.heap.page_allocator;
    const src: []const u8 = if (val_len == 0) &.{} else val_ptr.?[0..@intCast(val_len)];
    const copy = alloc.dupe(u8, src) catch return ERR_NOMEM;
    globals_mu.lockUncancelable(sio.io());
    defer globals_mu.unlock(sio.io());
    const gop = bytes_cells.getOrPut(alloc, name) catch {
        alloc.free(copy);
        return ERR_NOMEM;
    };
    if (gop.found_existing) {
        alloc.free(gop.value_ptr.*);
    } else if (!ownKey(&bytes_cells, alloc, name, gop)) {
        alloc.free(copy);
        return ERR_NOMEM;
    }
    gop.value_ptr.* = copy;
    return OK;
}

pub export fn sa_global_bytes_get(name_ptr: ?[*]const u8, name_len: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return ERR_INVALID;
    len_ptr.* = 0;
    const name = cellName(name_ptr, name_len) orelse return ERR_INVALID;
    globals_mu.lockUncancelable(sio.io());
    defer globals_mu.unlock(sio.io());
    const value = bytes_cells.get(name) orelse return ERR_NOT_FOUND;
    len_ptr.* = @intCast(value.len);
    if (value.len > cap) return ERR_TRUNCATED;
    if (value.len > 0) {
        const buf = buf_ptr orelse return ERR_INVALID;
        @memcpy(buf[0..value.len], value);
    }
    return OK;
}

// ---------------- tests ----------------

test "globals: u64 get on unset name reports NOT_FOUND, set/get roundtrip" {
    var out: u64 = 99;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_global_u64_get("t1.missing".ptr, 10, &out));
    try std.testing.expectEqual(@as(u64, 0), out);
    try std.testing.expectEqual(OK, sa_global_u64_set("t1.counter".ptr, 10, 41));
    try std.testing.expectEqual(OK, sa_global_u64_get("t1.counter".ptr, 10, &out));
    try std.testing.expectEqual(@as(u64, 41), out);
    // Overwrite is a plain set.
    try std.testing.expectEqual(OK, sa_global_u64_set("t1.counter".ptr, 10, 42));
    try std.testing.expectEqual(OK, sa_global_u64_get("t1.counter".ptr, 10, &out));
    try std.testing.expectEqual(@as(u64, 42), out);
}

test "globals: u64 set_once does not overwrite" {
    var already: u64 = 99;
    try std.testing.expectEqual(OK, sa_global_u64_set_once("t2.once".ptr, 7, 7, &already));
    try std.testing.expectEqual(@as(u64, 0), already);
    try std.testing.expectEqual(OK, sa_global_u64_set_once("t2.once".ptr, 7, 9, &already));
    try std.testing.expectEqual(@as(u64, 1), already);
    var out: u64 = 0;
    try std.testing.expectEqual(OK, sa_global_u64_get("t2.once".ptr, 7, &out));
    try std.testing.expectEqual(@as(u64, 7), out);
}

test "globals: u64 add accumulates from unset and supports negative deltas" {
    var out: u64 = 0;
    try std.testing.expectEqual(OK, sa_global_u64_add("t3.acc".ptr, 6, 5, &out));
    try std.testing.expectEqual(@as(u64, 5), out);
    try std.testing.expectEqual(OK, sa_global_u64_add("t3.acc".ptr, 6, 3, &out));
    try std.testing.expectEqual(@as(u64, 8), out);
    try std.testing.expectEqual(OK, sa_global_u64_add("t3.acc".ptr, 6, -2, &out));
    try std.testing.expectEqual(@as(u64, 6), out);
    try std.testing.expectEqual(OK, sa_global_u64_get("t3.acc".ptr, 6, &out));
    try std.testing.expectEqual(@as(u64, 6), out);
}

test "globals: bytes set/get roundtrip, copy-in isolation, missing NOT_FOUND" {
    var len: u64 = 0;
    var buf: [16]u8 = undefined;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_global_bytes_get("t4.blob".ptr, 7, &buf, buf.len, &len));
    var src = [_]u8{ 'h', 'e', 'l', 'l', 'o' };
    try std.testing.expectEqual(OK, sa_global_bytes_set("t4.blob".ptr, 7, &src, 5));
    // Mutating the source after set must not affect the stored copy.
    src[0] = 'H';
    try std.testing.expectEqual(OK, sa_global_bytes_get("t4.blob".ptr, 7, &buf, buf.len, &len));
    try std.testing.expectEqual(@as(u64, 5), len);
    try std.testing.expectEqualStrings("hello", buf[0..5]);
    // Replacement frees the old value and stores the new one.
    try std.testing.expectEqual(OK, sa_global_bytes_set("t4.blob".ptr, 7, "bye".ptr, 3));
    try std.testing.expectEqual(OK, sa_global_bytes_get("t4.blob".ptr, 7, &buf, buf.len, &len));
    try std.testing.expectEqual(@as(u64, 3), len);
    try std.testing.expectEqualStrings("bye", buf[0..3]);
}

test "globals: bytes get with small buffer is TRUNCATED and reports required length" {
    try std.testing.expectEqual(OK, sa_global_bytes_set("t5.blob".ptr, 7, "0123456789".ptr, 10));
    var len: u64 = 0;
    var small: [4]u8 = undefined;
    try std.testing.expectEqual(ERR_TRUNCATED, sa_global_bytes_get("t5.blob".ptr, 7, &small, small.len, &len));
    try std.testing.expectEqual(@as(u64, 10), len);
    var big: [16]u8 = undefined;
    try std.testing.expectEqual(OK, sa_global_bytes_get("t5.blob".ptr, 7, &big, big.len, &len));
    try std.testing.expectEqualStrings("0123456789", big[0..10]);
}
