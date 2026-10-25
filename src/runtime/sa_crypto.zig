//! sa_std auth small items (P0-6 remainder): bcrypt password hashing
//! and OS keyring access for CXU's auth surface.
//!
//! bcrypt: provided by the system libxcrypt (dlopen libcrypt.so.1,
//! the compress/brotli and tree-sitter pattern — capability lives in
//! sa_std, the heavy primitive is a system library). Hashes are the
//! standard $2b$ form (60 chars). crypt_r returns a pointer into its
//! scratch struct, so results are copied out before any next call.
//! Missing libcrypt -> ERR_UNSUPPORTED, never a fake hash.
//!
//! keyring: provided by libsecret (dlopen libsecret-1.so.0) over the
//! session Secret Service (gnome-keyring etc.). One attribute "key"
//! under a DONT_MATCH_NAME schema. The collection is chosen per call:
//! an empty collection name means the OS default collection (the
//! unlocked login keyring on a desktop; headless setups without one
//! get ERR_IO, and CI uses the always-present "session" collection).
//! sa_keyring_available() reports the LIBRARY only; a missing secret
//! service surfaces as ERR_IO on operations, an absent entry as
//! ERR_NOT_FOUND. Variadic secret_password_*_sync entry points are
//! used so attributes pass without a GHashTable.
//! Status codes mirror sa_std.zig.

const std = @import("std");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_IO: i32 = 6;
const ERR_UNSUPPORTED: i32 = 8;
const ERR_TRUNCATED: i32 = 9;

// ---------------- bcrypt (libcrypt) ----------------

const FnCryptR = *const fn ([*:0]const u8, [*:0]const u8, *anyopaque) callconv(.c) ?[*:0]u8;
const FnGensaltRn = *const fn ([*:0]const u8, c_ulong, ?[*]const u8, c_int, [*]u8, c_int) callconv(.c) ?[*:0]u8;

var crypt_mu = std.Io.Mutex.init;
var crypt_state: enum { unloaded, ready, missing } = .unloaded;
var crypt_lib: ?std.DynLib = null;
var crypt_r_fn: FnCryptR = undefined;
var gensalt_fn: FnGensaltRn = undefined;

fn ensureCrypt() bool {
    crypt_mu.lockUncancelable(sio.io());
    defer crypt_mu.unlock(sio.io());
    if (crypt_state != .unloaded) return crypt_state == .ready;
    crypt_state = .missing;
    var lib = std.DynLib.open("libcrypt.so.1") catch return false;
    crypt_r_fn = lib.lookup(FnCryptR, "crypt_r") orelse return false;
    gensalt_fn = lib.lookup(FnGensaltRn, "crypt_gensalt_rn") orelse return false;
    crypt_lib = lib;
    crypt_state = .ready;
    return true;
}

fn dupeZ(alloc: std.mem.Allocator, slice: []const u8) ![:0]u8 {
    const buf = try alloc.allocSentinel(u8, slice.len, 0);
    @memcpy(buf[0..slice.len], slice);
    return buf;
}

/// Runs crypt_r with a fresh zeroed scratch struct (libxcrypt's
/// struct crypt_data is ~128 KiB; 256 KiB zeroed is safely above it)
/// and copies the result into a caller-owned slice.
fn cryptRun(key_z: [*:0]const u8, setting_z: [*:0]const u8) ![]u8 {
    const alloc = std.heap.page_allocator;
    const scratch = try alloc.alloc(u8, 256 * 1024);
    defer alloc.free(scratch);
    @memset(scratch, 0);
    const out = crypt_r_fn(key_z, setting_z, @ptrCast(scratch.ptr)) orelse return error.CryptFailed;
    const text = std.mem.span(out);
    if (text.len == 0 or text[0] == '*') return error.CryptFailed;
    return alloc.dupe(u8, text);
}

pub export fn sa_bcrypt_hash(pw_ptr: ?[*]const u8, pw_len: u64, cost: u32, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const out_l = out_len orelse return ERR_INVALID;
    out_l.* = 0;
    const pp = pw_ptr orelse return ERR_INVALID;
    if (cost < 4 or cost > 31) return ERR_INVALID;
    if (!ensureCrypt()) return ERR_UNSUPPORTED;
    const alloc = std.heap.page_allocator;
    const pw_z = dupeZ(alloc, pp[0..@intCast(pw_len)]) catch return ERR_NOMEM;
    defer alloc.free(pw_z);
    var salt_buf: [192]u8 = undefined;
    const salt = gensalt_fn("$2b$", @intCast(cost), null, 0, &salt_buf, salt_buf.len) orelse return ERR_IO;
    const hash = cryptRun(pw_z, salt) catch return ERR_IO;
    defer alloc.free(hash);
    out_l.* = @intCast(hash.len);
    if (hash.len > cap) return ERR_TRUNCATED;
    const out = out_ptr orelse return ERR_INVALID;
    @memcpy(out[0..hash.len], hash);
    return OK;
}

pub export fn sa_bcrypt_verify(pw_ptr: ?[*]const u8, pw_len: u64, hash_ptr: ?[*]const u8, hash_len: u64, out_match: ?*u32) i32 {
    const out_m = out_match orelse return ERR_INVALID;
    out_m.* = 0;
    const pp = pw_ptr orelse return ERR_INVALID;
    const hp = hash_ptr orelse return ERR_INVALID;
    const hash = hp[0..@intCast(hash_len)];
    if (hash.len != 60 or !std.mem.startsWith(u8, hash, "$2")) return ERR_INVALID;
    if (!ensureCrypt()) return ERR_UNSUPPORTED;
    const alloc = std.heap.page_allocator;
    const pw_z = dupeZ(alloc, pp[0..@intCast(pw_len)]) catch return ERR_NOMEM;
    defer alloc.free(pw_z);
    const hash_z = dupeZ(alloc, hash) catch return ERR_NOMEM;
    defer alloc.free(hash_z);
    const candidate = cryptRun(pw_z, hash_z.ptr) catch {
        out_m.* = 0;
        return OK; // a hash libcrypt cannot process matches nothing
    };
    defer alloc.free(candidate);
    if (candidate.len != hash.len) {
        out_m.* = 0;
        return OK;
    }
    var diff: u8 = 0;
    for (candidate, hash) |a, b| diff |= a ^ b;
    out_m.* = if (diff == 0) 1 else 0;
    return OK;
}

// ---------------- keyring (libsecret) ----------------

const GError = extern struct {
    domain: u32,
    code: i32,
    message: ?[*:0]const u8,
};

const SecretSchemaAttr = extern struct {
    name: ?[*:0]const u8,
    type_: c_int,
};

const SecretSchema = extern struct {
    name: [*:0]const u8,
    flags: c_int,
    attributes: [32]SecretSchemaAttr,
    reserved: c_int,
    r1: ?*anyopaque = null,
    r2: ?*anyopaque = null,
    r3: ?*anyopaque = null,
    r4: ?*anyopaque = null,
    r5: ?*anyopaque = null,
    r6: ?*anyopaque = null,
    r7: ?*anyopaque = null,
};

const keyring_schema: SecretSchema = makeSchema();
const attr_key: [*:0]const u8 = "key";

fn makeSchema() SecretSchema {
    var attrs: [32]SecretSchemaAttr = undefined;
    for (&attrs) |*a| a.* = .{ .name = null, .type_ = 0 };
    attrs[0] = .{ .name = "key", .type_ = 0 };
    return .{
        .name = "org.sa.std.Keyring",
        .flags = 2, // SECRET_SCHEMA_DONT_MATCH_NAME
        .attributes = attrs,
        .reserved = 0,
    };
}

const FnStoreSync = *const fn (*const SecretSchema, [*:0]const u8, [*:0]const u8, [*:0]const u8, ?*anyopaque, *?*GError, ...) callconv(.c) i32;
const FnLookupSync = *const fn (*const SecretSchema, ?*anyopaque, *?*GError, ...) callconv(.c) ?[*:0]u8;
const FnClearSync = *const fn (*const SecretSchema, ?*anyopaque, *?*GError, ...) callconv(.c) i32;
const FnErrorFree = *const fn (?*GError) callconv(.c) void;
const FnFree = *const fn (?*anyopaque) callconv(.c) void;

var secret_mu = std.Io.Mutex.init;
var secret_state: enum { unloaded, ready, missing } = .unloaded;
var secret_lib: ?std.DynLib = null;
var store_fn: FnStoreSync = undefined;
var lookup_fn: FnLookupSync = undefined;
var clear_fn: FnClearSync = undefined;
var error_free_fn: FnErrorFree = undefined;
var g_free_fn: FnFree = undefined;

fn ensureSecret() bool {
    secret_mu.lockUncancelable(sio.io());
    defer secret_mu.unlock(sio.io());
    if (secret_state != .unloaded) return secret_state == .ready;
    secret_state = .missing;
    var lib = std.DynLib.open("libsecret-1.so.0") catch return false;
    store_fn = lib.lookup(FnStoreSync, "secret_password_store_sync") orelse return false;
    lookup_fn = lib.lookup(FnLookupSync, "secret_password_lookup_sync") orelse return false;
    clear_fn = lib.lookup(FnClearSync, "secret_password_clear_sync") orelse return false;
    // g_error_free / g_free live in libglib, a hard dependency of
    // libsecret; dlsym on the libsecret handle searches its dependency
    // tree, and an explicit glib handle is the fallback.
    var glib = std.DynLib.open("libglib-2.0.so.0") catch null;
    error_free_fn = lib.lookup(FnErrorFree, "g_error_free") orelse blk: {
        if (glib) |*g| break :blk g.lookup(FnErrorFree, "g_error_free") orelse return false;
        return false;
    };
    g_free_fn = lib.lookup(FnFree, "g_free") orelse blk: {
        if (glib) |*g| break :blk g.lookup(FnFree, "g_free") orelse return false;
        return false;
    };
    secret_lib = lib;
    secret_state = .ready;
    return true;
}

pub export fn sa_keyring_available() u32 {
    return if (ensureSecret()) 1 else 0;
}

/// Collection name for a call: empty -> "default".
fn collectionZ(alloc: std.mem.Allocator, col_ptr: ?[*]const u8, col_len: u64) ![:0]u8 {
    if (col_len == 0) return dupeZ(alloc, "default");
    const cp = col_ptr orelse return error.InvalidArgument;
    return dupeZ(alloc, cp[0..@intCast(col_len)]);
}

pub export fn sa_keyring_set(col_ptr: ?[*]const u8, col_len: u64, key_ptr: ?[*]const u8, key_len: u64, secret_ptr: ?[*]const u8, secret_len: u64) i32 {
    const kp = key_ptr orelse return ERR_INVALID;
    const sp = secret_ptr orelse return ERR_INVALID;
    if (key_len == 0) return ERR_INVALID;
    if (!ensureSecret()) return ERR_UNSUPPORTED;
    const alloc = std.heap.page_allocator;
    const col_z = collectionZ(alloc, col_ptr, col_len) catch return ERR_NOMEM;
    defer alloc.free(col_z);
    const key_z = dupeZ(alloc, kp[0..@intCast(key_len)]) catch return ERR_NOMEM;
    defer alloc.free(key_z);
    const secret_z = dupeZ(alloc, sp[0..@intCast(secret_len)]) catch return ERR_NOMEM;
    defer alloc.free(secret_z);
    var err: ?*GError = null;
    const ok = store_fn(&keyring_schema, col_z.ptr, key_z, secret_z, null, &err, attr_key, key_z.ptr, @as(?*anyopaque, null));
    if (err) |e| {
        error_free_fn(e);
        return ERR_IO;
    }
    return if (ok != 0) OK else ERR_IO;
}

pub export fn sa_keyring_get(key_ptr: ?[*]const u8, key_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const out_l = out_len orelse return ERR_INVALID;
    out_l.* = 0;
    const kp = key_ptr orelse return ERR_INVALID;
    if (key_len == 0) return ERR_INVALID;
    if (!ensureSecret()) return ERR_UNSUPPORTED;
    const alloc = std.heap.page_allocator;
    const key_z = dupeZ(alloc, kp[0..@intCast(key_len)]) catch return ERR_NOMEM;
    defer alloc.free(key_z);
    var err: ?*GError = null;
    const found = lookup_fn(&keyring_schema, null, &err, attr_key, key_z.ptr, @as(?*anyopaque, null));
    if (err) |e| {
        error_free_fn(e);
        return ERR_IO;
    }
    const text_z = found orelse return ERR_NOT_FOUND;
    const text = std.mem.span(text_z);
    defer g_free_fn(@ptrCast(text_z));
    out_l.* = @intCast(text.len);
    if (text.len > cap) return ERR_TRUNCATED;
    const out = out_ptr orelse return ERR_INVALID;
    @memcpy(out[0..text.len], text);
    return OK;
}

pub export fn sa_keyring_remove(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const kp = key_ptr orelse return ERR_INVALID;
    if (key_len == 0) return ERR_INVALID;
    if (!ensureSecret()) return ERR_UNSUPPORTED;
    const alloc = std.heap.page_allocator;
    const key_z = dupeZ(alloc, kp[0..@intCast(key_len)]) catch return ERR_NOMEM;
    defer alloc.free(key_z);
    var err: ?*GError = null;
    const ok = clear_fn(&keyring_schema, null, &err, attr_key, key_z.ptr, @as(?*anyopaque, null));
    if (err) |e| {
        error_free_fn(e);
        return ERR_IO;
    }
    return if (ok != 0) OK else ERR_NOT_FOUND;
}

// ---------------- tests ----------------

test "bcrypt: known-answer verify and hash roundtrip" {
    // $2b$12$ hash of "hello-cxu" produced by libxcrypt (verified with
    // an independent C probe using crypt_r/crypt_gensalt_rn).
    const known = "$2b$12$l0qFXIqXQKrXFMWfD8IOVu2.nCr6QMIzWrhPXFuLt5LnCN1e6/QWe";
    var match: u32 = 0;
    try std.testing.expectEqual(OK, sa_bcrypt_verify("hello-cxu".ptr, 9, known.ptr, known.len, &match));
    try std.testing.expectEqual(@as(u32, 1), match);
    try std.testing.expectEqual(OK, sa_bcrypt_verify("wrong".ptr, 5, known.ptr, known.len, &match));
    try std.testing.expectEqual(@as(u32, 0), match);

    var buf: [128]u8 = undefined;
    var len: u64 = 0;
    try std.testing.expectEqual(OK, sa_bcrypt_hash("s3cret".ptr, 6, 4, &buf, buf.len, &len));
    try std.testing.expectEqual(@as(u64, 60), len);
    try std.testing.expectEqualStrings("$2b$04$", buf[0..7]);
    try std.testing.expectEqual(OK, sa_bcrypt_verify("s3cret".ptr, 6, &buf, len, &match));
    try std.testing.expectEqual(@as(u32, 1), match);
    try std.testing.expectEqual(ERR_INVALID, sa_bcrypt_hash("x".ptr, 1, 3, &buf, buf.len, &len));
}

test "keyring: library availability is reported honestly" {
    // libsecret-1 is installed on the build box; the secret SERVICE
    // roundtrip is asserted by demo D8 under dbus-run-session.
    try std.testing.expectEqual(@as(u32, 1), sa_keyring_available());
}
