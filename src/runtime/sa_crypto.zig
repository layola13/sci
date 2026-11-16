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
const builtin = @import("builtin");
const sio = @import("sio");

/// WASI has no dynamic loading (std.DynLib does not exist there);
/// the stub keeps the libcrypt/libsecret loaders compiling and
/// its open always fails, so both features report themselves
/// missing (ERR_UNSUPPORTED) — loud, never a fake success.
const DynLib = if (builtin.os.tag != .wasi) std.DynLib else struct {
    pub fn open(_: []const u8) error{Unsupported}!@This() {
        return error.Unsupported;
    }

    pub fn lookup(_: *@This(), comptime T: type, _: [:0]const u8) ?T {
        return null;
    }

    pub fn close(_: *@This()) void {}
};

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
var crypt_lib: ?DynLib = null;
var crypt_r_fn: FnCryptR = undefined;
var gensalt_fn: FnGensaltRn = undefined;

fn ensureCrypt() bool {
    crypt_mu.lockUncancelable(sio.io());
    defer crypt_mu.unlock(sio.io());
    if (crypt_state != .unloaded) return crypt_state == .ready;
    crypt_state = .missing;
    var lib = DynLib.open("libcrypt.so.1") catch return false;
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
var secret_lib: ?DynLib = null;
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
    var lib = DynLib.open("libsecret-1.so.0") catch return false;
    store_fn = lib.lookup(FnStoreSync, "secret_password_store_sync") orelse return false;
    lookup_fn = lib.lookup(FnLookupSync, "secret_password_lookup_sync") orelse return false;
    clear_fn = lib.lookup(FnClearSync, "secret_password_clear_sync") orelse return false;
    // g_error_free / g_free live in libglib, a hard dependency of
    // libsecret; dlsym on the libsecret handle searches its dependency
    // tree, and an explicit glib handle is the fallback.
    var glib = DynLib.open("libglib-2.0.so.0") catch null;
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

// ---------------- crypto suite (STD batch 4, 2026-10-28) ----------------
//
// Raw-byte digests / MACs / KDFs, AES-GCM, Ed25519 and ECDSA P-256,
// driven by the sub2api + new-api census: both backends found only
// hex-shaped HMAC in sa_std and no raw digest, AEAD or asymmetric
// data surface at all. All primitives are Zig std.crypto (no new
// system libraries); RSA and the DER key/certificate readers live
// in sa_crypto_asym.zig. Conventions follow the existing crypto
// face: status i32 (0 ok), fixed-size outputs written in full,
// variable outputs via (out, cap, out_len) with out_len always set
// to the needed size first (ERR_TRUNCATED when cap is too small).
// A null pointer is accepted only together with a zero length
// (empty input); a null pointer with a nonzero length is invalid.
// Signature verification never fails on a mere mismatch: it
// returns OK with out_valid = 0; only malformed inputs are errors.

const ERR_ACCESS: i32 = 4;

fn inSlice(ptr: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return &.{};
    const p = ptr orelse return null;
    return p[0..@intCast(len)];
}

fn writeOut(out_ptr: ?[*]u8, cap: u64, out_len: ?*u64, data: []const u8) i32 {
    const ol = out_len orelse return ERR_INVALID;
    ol.* = @intCast(data.len);
    if (data.len > cap) return ERR_TRUNCATED;
    const o = out_ptr orelse return ERR_INVALID;
    @memcpy(o[0..data.len], data);
    return OK;
}

// ---- raw digests (fixed-size outputs) ----

pub export fn sa_md5(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?[*]u8) i32 {
    const data = inSlice(data_ptr, data_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.hash.Md5.hash(data, out[0..16], .{});
    return OK;
}

pub export fn sa_sha1(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?[*]u8) i32 {
    const data = inSlice(data_ptr, data_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.hash.Sha1.hash(data, out[0..20], .{});
    return OK;
}

pub export fn sa_sha256(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?[*]u8) i32 {
    const data = inSlice(data_ptr, data_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.hash.sha2.Sha256.hash(data, out[0..32], .{});
    return OK;
}

pub export fn sa_sha384(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?[*]u8) i32 {
    const data = inSlice(data_ptr, data_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.hash.sha2.Sha384.hash(data, out[0..48], .{});
    return OK;
}

pub export fn sa_sha512(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?[*]u8) i32 {
    const data = inSlice(data_ptr, data_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.hash.sha2.Sha512.hash(data, out[0..64], .{});
    return OK;
}

// ---- HMAC, raw-byte form (the *_hex forms above stay as they are) ----

pub export fn sa_hmac_sha1(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8) i32 {
    const key = inSlice(key_ptr, key_len) orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.auth.hmac.HmacSha1.create(out[0..20], msg, key);
    return OK;
}

pub export fn sa_hmac_sha256(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8) i32 {
    const key = inSlice(key_ptr, key_len) orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.auth.hmac.sha2.HmacSha256.create(out[0..32], msg, key);
    return OK;
}

pub export fn sa_hmac_sha512(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8) i32 {
    const key = inSlice(key_ptr, key_len) orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.auth.hmac.sha2.HmacSha512.create(out[0..64], msg, key);
    return OK;
}

// ---- KDFs ----

pub export fn sa_pbkdf2_hmac_sha256(pw_ptr: ?[*]const u8, pw_len: u64, salt_ptr: ?[*]const u8, salt_len: u64, iterations: u32, out_ptr: ?[*]u8, out_len: u64) i32 {
    const pw = inSlice(pw_ptr, pw_len) orelse return ERR_INVALID;
    const salt = inSlice(salt_ptr, salt_len) orelse return ERR_INVALID;
    if (iterations == 0 or out_len == 0) return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    std.crypto.pwhash.pbkdf2(out[0..@intCast(out_len)], pw, salt, iterations, std.crypto.auth.hmac.sha2.HmacSha256) catch return ERR_INVALID;
    return OK;
}

pub export fn sa_hkdf_sha256(salt_ptr: ?[*]const u8, salt_len: u64, ikm_ptr: ?[*]const u8, ikm_len: u64, info_ptr: ?[*]const u8, info_len: u64, out_ptr: ?[*]u8, out_len: u64) i32 {
    const salt = inSlice(salt_ptr, salt_len) orelse return ERR_INVALID;
    const ikm = inSlice(ikm_ptr, ikm_len) orelse return ERR_INVALID;
    const info = inSlice(info_ptr, info_len) orelse return ERR_INVALID;
    if (out_len == 0 or out_len > 255 * 32) return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const Hkdf = std.crypto.kdf.hkdf.HkdfSha256;
    const prk = Hkdf.extract(salt, ikm);
    Hkdf.expand(out[0..@intCast(out_len)], info, prk);
    return OK;
}

// ---- constant-time equality (webhook / MAC / token compares) ----

pub export fn sa_crypto_timing_safe_equal(a_ptr: ?[*]const u8, a_len: u64, b_ptr: ?[*]const u8, b_len: u64, out_equal: ?*u32) i32 {
    const oe = out_equal orelse return ERR_INVALID;
    oe.* = 0;
    const a = inSlice(a_ptr, a_len) orelse return ERR_INVALID;
    const b = inSlice(b_ptr, b_len) orelse return ERR_INVALID;
    if (a.len != b.len) return OK; // length is not secret; bytes are
    var diff: u8 = 0;
    for (a, b) |x, y| diff |= x ^ y;
    oe.* = if (diff == 0) 1 else 0;
    return OK;
}

// ---- base64url (RFC 4648 section 5, unpadded wire form) ----

const b64url = std.base64.url_safe_no_pad;

pub export fn sa_base64url_encode(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const data = inSlice(data_ptr, data_len) orelse return ERR_INVALID;
    const ol = out_len orelse return ERR_INVALID;
    const need = b64url.Encoder.calcSize(data.len);
    ol.* = @intCast(need);
    if (need > cap) return ERR_TRUNCATED;
    const out = out_ptr orelse return ERR_INVALID;
    _ = b64url.Encoder.encode(out[0..need], data);
    return OK;
}

pub export fn sa_base64url_decode(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    var data = inSlice(data_ptr, data_len) orelse return ERR_INVALID;
    // Tolerate padded input (up to two '='); the wire form is unpadded.
    while (data.len > 0 and data[data.len - 1] == '=') data = data[0 .. data.len - 1];
    const ol = out_len orelse return ERR_INVALID;
    const need = b64url.Decoder.calcSizeForSlice(data) catch return ERR_INVALID;
    ol.* = @intCast(need);
    if (need > cap) return ERR_TRUNCATED;
    const out = out_ptr orelse return ERR_INVALID;
    b64url.Decoder.decode(out[0..need], data) catch return ERR_INVALID;
    return OK;
}

// ---- AES-GCM (AEAD; output is ciphertext || 16-byte tag) ----

pub export fn sa_aes_gcm_encrypt(key_ptr: ?[*]const u8, key_len: u64, nonce_ptr: ?[*]const u8, aad_ptr: ?[*]const u8, aad_len: u64, pt_ptr: ?[*]const u8, pt_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const key = inSlice(key_ptr, key_len) orelse return ERR_INVALID;
    const nonce = inSlice(nonce_ptr, 12) orelse return ERR_INVALID;
    if (nonce_ptr == null) return ERR_INVALID;
    const aad = inSlice(aad_ptr, aad_len) orelse return ERR_INVALID;
    const pt = inSlice(pt_ptr, pt_len) orelse return ERR_INVALID;
    const ol = out_len orelse return ERR_INVALID;
    ol.* = pt_len + 16;
    if (pt_len + 16 > cap) return ERR_TRUNCATED;
    const out = out_ptr orelse return ERR_INVALID;
    var tag: [16]u8 = undefined;
    const npub: [12]u8 = nonce[0..12].*;
    switch (key.len) {
        16 => std.crypto.aead.aes_gcm.Aes128Gcm.encrypt(out[0..@intCast(pt_len)], &tag, pt, aad, npub, key[0..16].*),
        32 => std.crypto.aead.aes_gcm.Aes256Gcm.encrypt(out[0..@intCast(pt_len)], &tag, pt, aad, npub, key[0..32].*),
        else => return ERR_INVALID,
    }
    @memcpy(out[@intCast(pt_len)..][0..16], &tag);
    return OK;
}

pub export fn sa_aes_gcm_decrypt(key_ptr: ?[*]const u8, key_len: u64, nonce_ptr: ?[*]const u8, aad_ptr: ?[*]const u8, aad_len: u64, ct_ptr: ?[*]const u8, ct_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const key = inSlice(key_ptr, key_len) orelse return ERR_INVALID;
    const nonce = inSlice(nonce_ptr, 12) orelse return ERR_INVALID;
    if (nonce_ptr == null) return ERR_INVALID;
    const aad = inSlice(aad_ptr, aad_len) orelse return ERR_INVALID;
    const ct = inSlice(ct_ptr, ct_len) orelse return ERR_INVALID;
    if (ct.len < 16) return ERR_INVALID;
    const pt_len = ct.len - 16;
    const ol = out_len orelse return ERR_INVALID;
    ol.* = @intCast(pt_len);
    if (pt_len > cap) return ERR_TRUNCATED;
    const out = out_ptr orelse return ERR_INVALID;
    const body = ct[0..pt_len];
    const tag: [16]u8 = ct[pt_len..][0..16].*;
    const npub: [12]u8 = nonce[0..12].*;
    const res = switch (key.len) {
        16 => std.crypto.aead.aes_gcm.Aes128Gcm.decrypt(out[0..pt_len], body, tag, aad, npub, key[0..16].*),
        32 => std.crypto.aead.aes_gcm.Aes256Gcm.decrypt(out[0..pt_len], body, tag, aad, npub, key[0..32].*),
        else => return ERR_INVALID,
    };
    // Tag mismatch is an explicit authentication failure (status 4),
    // never a silent success; the out buffer contents are undefined.
    res catch return ERR_ACCESS;
    return OK;
}

// ---- Ed25519 (seed-shaped keys; DER import lives in sa_crypto_asym.zig) ----

const Ed25519 = std.crypto.sign.Ed25519;

pub export fn sa_ed25519_public_key(seed_ptr: ?[*]const u8, out_ptr: ?[*]u8) i32 {
    const seed = seed_ptr orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const kp = Ed25519.KeyPair.generateDeterministic(seed[0..32].*) catch return ERR_INVALID;
    out[0..32].* = kp.public_key.toBytes();
    return OK;
}

pub export fn sa_ed25519_sign(seed_ptr: ?[*]const u8, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8) i32 {
    const seed = seed_ptr orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const kp = Ed25519.KeyPair.generateDeterministic(seed[0..32].*) catch return ERR_INVALID;
    const sig = kp.sign(msg, null) catch return ERR_INVALID;
    out[0..64].* = sig.toBytes();
    return OK;
}

pub export fn sa_ed25519_verify(pk_ptr: ?[*]const u8, msg_ptr: ?[*]const u8, msg_len: u64, sig_ptr: ?[*]const u8, out_valid: ?*u32) i32 {
    const ov = out_valid orelse return ERR_INVALID;
    ov.* = 0;
    const pk_b = pk_ptr orelse return ERR_INVALID;
    const sig_b = sig_ptr orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const pk = Ed25519.PublicKey.fromBytes(pk_b[0..32].*) catch return ERR_INVALID;
    const sig = Ed25519.Signature.fromBytes(sig_b[0..64].*);
    Ed25519.Signature.verify(sig, msg, pk) catch {
        ov.* = 0;
        return OK;
    };
    ov.* = 1;
    return OK;
}

// ---- ECDSA P-256 (raw x||y public keys, raw r||s signatures) ----

const EcdsaP256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

fn p256PublicKey(pk_xy: [*]const u8) ?EcdsaP256.PublicKey {
    var sec1: [65]u8 = undefined;
    sec1[0] = 0x04;
    @memcpy(sec1[1..65], pk_xy[0..64]);
    return EcdsaP256.PublicKey.fromSec1(&sec1) catch null;
}

pub export fn sa_ecdsa_p256_verify(pk_ptr: ?[*]const u8, msg_ptr: ?[*]const u8, msg_len: u64, sig_ptr: ?[*]const u8, out_valid: ?*u32) i32 {
    const ov = out_valid orelse return ERR_INVALID;
    ov.* = 0;
    const pk_b = pk_ptr orelse return ERR_INVALID;
    const sig_b = sig_ptr orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const pk = p256PublicKey(pk_b) orelse return ERR_INVALID;
    const sig = EcdsaP256.Signature.fromBytes(sig_b[0..64].*);
    EcdsaP256.Signature.verify(sig, msg, pk) catch {
        ov.* = 0;
        return OK;
    };
    ov.* = 1;
    return OK;
}

pub export fn sa_ecdsa_p256_verify_prehashed(pk_ptr: ?[*]const u8, digest_ptr: ?[*]const u8, sig_ptr: ?[*]const u8, out_valid: ?*u32) i32 {
    const ov = out_valid orelse return ERR_INVALID;
    ov.* = 0;
    const pk_b = pk_ptr orelse return ERR_INVALID;
    const dg_b = digest_ptr orelse return ERR_INVALID;
    const sig_b = sig_ptr orelse return ERR_INVALID;
    const pk = p256PublicKey(pk_b) orelse return ERR_INVALID;
    const sig = EcdsaP256.Signature.fromBytes(sig_b[0..64].*);
    EcdsaP256.Signature.verifyPrehashed(sig, dg_b[0..32].*, pk) catch {
        ov.* = 0;
        return OK;
    };
    ov.* = 1;
    return OK;
}

pub export fn sa_ecdsa_p256_sign(priv_ptr: ?[*]const u8, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8) i32 {
    const priv = priv_ptr orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const sk = EcdsaP256.SecretKey.fromBytes(priv[0..32].*) catch return ERR_INVALID;
    const kp = EcdsaP256.KeyPair.fromSecretKey(sk) catch return ERR_INVALID;
    const sig = kp.sign(msg, null) catch return ERR_INVALID;
    out[0..64].* = sig.toBytes();
    return OK;
}

// ---------------- crypto suite tests (known-answer vectors) ----------------

fn unhex(comptime s: []const u8) [s.len / 2]u8 {
    var out: [s.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, s) catch unreachable;
    return out;
}

test "digests: FIPS/RFC known answers for abc" {
    var out: [64]u8 = undefined;
    try std.testing.expectEqual(OK, sa_md5("abc".ptr, 3, &out));
    try std.testing.expectEqualSlices(u8, &unhex("900150983cd24fb0d6963f7d28e17f72"), out[0..16]);
    try std.testing.expectEqual(OK, sa_md5(null, 0, &out));
    try std.testing.expectEqualSlices(u8, &unhex("d41d8cd98f00b204e9800998ecf8427e"), out[0..16]);
    try std.testing.expectEqual(OK, sa_sha1("abc".ptr, 3, &out));
    try std.testing.expectEqualSlices(u8, &unhex("a9993e364706816aba3e25717850c26c9cd0d89d"), out[0..20]);
    try std.testing.expectEqual(OK, sa_sha256("abc".ptr, 3, &out));
    try std.testing.expectEqualSlices(u8, &unhex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"), out[0..32]);
    try std.testing.expectEqual(OK, sa_sha384("abc".ptr, 3, &out));
    try std.testing.expectEqualSlices(u8, &unhex("cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"), out[0..48]);
    try std.testing.expectEqual(OK, sa_sha512("abc".ptr, 3, &out));
    try std.testing.expectEqualSlices(u8, &unhex("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"), out[0..64]);
    try std.testing.expectEqual(ERR_INVALID, sa_sha256(null, 3, &out));
}

test "hmac raw: RFC 4231 / RFC 2202 case 1 and 2" {
    var out: [64]u8 = undefined;
    const key: [20]u8 = @splat(0x0b);
    try std.testing.expectEqual(OK, sa_hmac_sha256(&key, 20, "Hi There".ptr, 8, &out));
    try std.testing.expectEqualSlices(u8, &unhex("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"), out[0..32]);
    try std.testing.expectEqual(OK, sa_hmac_sha512(&key, 20, "Hi There".ptr, 8, &out));
    try std.testing.expectEqualSlices(u8, &unhex("87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"), out[0..64]);
    try std.testing.expectEqual(OK, sa_hmac_sha1(&key, 20, "Hi There".ptr, 8, &out));
    try std.testing.expectEqualSlices(u8, &unhex("b617318655057264e28bc0b6fb378c8ef146be00"), out[0..20]);
    try std.testing.expectEqual(OK, sa_hmac_sha256("Jefe".ptr, 4, "what do ya want for nothing?".ptr, 28, &out));
    try std.testing.expectEqualSlices(u8, &unhex("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"), out[0..32]);
}

test "pbkdf2-hmac-sha256: RFC 7914 vectors; hkdf-sha256: RFC 5869 case 1" {
    var out: [64]u8 = undefined;
    try std.testing.expectEqual(OK, sa_pbkdf2_hmac_sha256("password".ptr, 8, "salt".ptr, 4, 1, &out, 32));
    try std.testing.expectEqualSlices(u8, &unhex("120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"), out[0..32]);
    try std.testing.expectEqual(OK, sa_pbkdf2_hmac_sha256("password".ptr, 8, "salt".ptr, 4, 2, &out, 32));
    try std.testing.expectEqualSlices(u8, &unhex("ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"), out[0..32]);
    try std.testing.expectEqual(ERR_INVALID, sa_pbkdf2_hmac_sha256("password".ptr, 8, "salt".ptr, 4, 0, &out, 32));

    const ikm: [22]u8 = @splat(0x0b);
    const salt = unhex("000102030405060708090a0b0c");
    const info = unhex("f0f1f2f3f4f5f6f7f8f9");
    try std.testing.expectEqual(OK, sa_hkdf_sha256(&salt, salt.len, &ikm, ikm.len, &info, info.len, &out, 42));
    try std.testing.expectEqualSlices(u8, &unhex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"), out[0..42]);
}

test "base64url: RFC 4648 alphabet, unpadded wire form" {
    var buf: [64]u8 = undefined;
    var len: u64 = 0;
    try std.testing.expectEqual(OK, sa_base64url_encode("hello".ptr, 5, &buf, buf.len, &len));
    try std.testing.expectEqualSlices(u8, "aGVsbG8", buf[0..@intCast(len)]);
    const raw = [_]u8{ 0xfb, 0xff, 0xfe };
    try std.testing.expectEqual(OK, sa_base64url_encode(&raw, 3, &buf, buf.len, &len));
    try std.testing.expectEqualSlices(u8, "-__-", buf[0..@intCast(len)]);
    try std.testing.expectEqual(OK, sa_base64url_decode("-__-".ptr, 4, &buf, buf.len, &len));
    try std.testing.expectEqualSlices(u8, &raw, buf[0..@intCast(len)]);
    // padded input tolerated
    try std.testing.expectEqual(OK, sa_base64url_decode("aGVsbG8=".ptr, 8, &buf, buf.len, &len));
    try std.testing.expectEqualSlices(u8, "hello", buf[0..@intCast(len)]);
    try std.testing.expectEqual(ERR_INVALID, sa_base64url_decode("aGV*".ptr, 4, &buf, buf.len, &len));
    try std.testing.expectEqual(ERR_TRUNCATED, sa_base64url_encode("hello".ptr, 5, &buf, 4, &len));
    try std.testing.expectEqual(@as(u64, 7), len);
}

test "aes-gcm: NIST zero vectors (128/256), AAD vector, tamper is an explicit error" {
    // Expected values cross-checked byte-for-byte against Node.js
    // crypto (OpenSSL) on the build box, 2026-10-28; the zero-key
    // cases are also McGrew & Viega GCM spec test cases 3 (AES-128)
    // and the corresponding AES-256 case.
    const nonce: [12]u8 = @splat(0);
    const pt: [16]u8 = @splat(0);
    var buf: [64]u8 = undefined;
    var len: u64 = 0;
    // AES-256, zero key/IV/plaintext: full ct||tag asserted
    const key256: [32]u8 = @splat(0);
    try std.testing.expectEqual(OK, sa_aes_gcm_encrypt(&key256, 32, &nonce, null, 0, &pt, 16, &buf, buf.len, &len));
    try std.testing.expectEqual(@as(u64, 32), len);
    try std.testing.expectEqualSlices(u8, &unhex("cea7403d4d606b6e074ec5d3baf39d18" ++ "d0d1c8a799996bf0265b98b5d48ab919"), buf[0..32]);
    var back: [16]u8 = undefined;
    var blen: u64 = 0;
    try std.testing.expectEqual(OK, sa_aes_gcm_decrypt(&key256, 32, &nonce, null, 0, &buf, len, &back, back.len, &blen));
    try std.testing.expectEqualSlices(u8, &pt, &back);
    // tampered tag -> authentication failure status, not silent success
    buf[31] ^= 1;
    try std.testing.expectEqual(ERR_ACCESS, sa_aes_gcm_decrypt(&key256, 32, &nonce, null, 0, &buf, len, &back, back.len, &blen));
    // AES-128, zero key/IV/plaintext
    const key128: [16]u8 = @splat(0);
    try std.testing.expectEqual(OK, sa_aes_gcm_encrypt(&key128, 16, &nonce, null, 0, &pt, 16, &buf, buf.len, &len));
    try std.testing.expectEqualSlices(u8, &unhex("0388dace60b6a392f328c2b971b2fe78" ++ "ab6e47d42cec13bdf53a67b21257bddf"), buf[0..32]);
    // AES-256 with AAD: key 0x07*32, IV 0x03*12, aad "hdr",
    // plaintext "hello gcm world" (Node/OpenSSL cross-check values)
    const key_a: [32]u8 = @splat(0x07);
    const nonce_a: [12]u8 = @splat(0x03);
    var buf_a: [64]u8 = undefined;
    var len_a: u64 = 0;
    try std.testing.expectEqual(OK, sa_aes_gcm_encrypt(&key_a, 32, &nonce_a, "hdr", 3, "hello gcm world", 15, &buf_a, buf_a.len, &len_a));
    try std.testing.expectEqualSlices(u8, &unhex("4d9bcf6f3508392117603433993b9b" ++ "86f8792cccfbfa7a50f17e69c75b5f62"), buf_a[0..31]);
    // wrong AAD fails authentication
    var back_a: [16]u8 = undefined;
    var blen_a: u64 = 0;
    try std.testing.expectEqual(ERR_ACCESS, sa_aes_gcm_decrypt(&key_a, 32, &nonce_a, "HDR", 3, &buf_a, len_a, &back_a, back_a.len, &blen_a));
    // bad key length (AES-192 is not exposed: Zig std has no 192 GCM)
    try std.testing.expectEqual(ERR_INVALID, sa_aes_gcm_encrypt(&key256, 24, &nonce, null, 0, &pt, 16, &buf, buf.len, &len));
}

test "ed25519: RFC 8032 test 1 (empty message)" {
    const seed = unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60");
    const pk_expect = unhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
    const sig_expect = unhex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");
    var pk: [32]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ed25519_public_key(&seed, &pk));
    try std.testing.expectEqualSlices(u8, &pk_expect, &pk);
    var sig: [64]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ed25519_sign(&seed, null, 0, &sig));
    try std.testing.expectEqualSlices(u8, &sig_expect, &sig);
    var valid: u32 = 0;
    try std.testing.expectEqual(OK, sa_ed25519_verify(&pk, null, 0, &sig, &valid));
    try std.testing.expectEqual(@as(u32, 1), valid);
    try std.testing.expectEqual(OK, sa_ed25519_verify(&pk, "x".ptr, 1, &sig, &valid));
    try std.testing.expectEqual(@as(u32, 0), valid);
}

test "ecdsa p-256: RFC 6979 sample vector verifies; sign roundtrips" {
    // RFC 6979 appendix A.2.5: P-256, SHA-256, message "sample".
    const pk_xy = unhex("60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6" ++ "7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299");
    const sig_rs = unhex("efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716" ++ "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8");
    var valid: u32 = 0;
    try std.testing.expectEqual(OK, sa_ecdsa_p256_verify(&pk_xy, "sample".ptr, 6, &sig_rs, &valid));
    try std.testing.expectEqual(@as(u32, 1), valid);
    try std.testing.expectEqual(OK, sa_ecdsa_p256_verify(&pk_xy, "Sample".ptr, 6, &sig_rs, &valid));
    try std.testing.expectEqual(@as(u32, 0), valid);
    // prehashed form: SHA-256("sample") fed directly
    var digest: [32]u8 = undefined;
    try std.testing.expectEqual(OK, sa_sha256("sample".ptr, 6, &digest));
    try std.testing.expectEqual(OK, sa_ecdsa_p256_verify_prehashed(&pk_xy, &digest, &sig_rs, &valid));
    try std.testing.expectEqual(@as(u32, 1), valid);
    // Sign roundtrip with a fixed scalar. Its public key below was
    // derived independently by Zig std and by OpenSSL (python
    // cryptography) with identical results; note it is NOT the
    // public half of the RFC 6979 vector above (that key pair's
    // private half is a different scalar).
    const priv = unhex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622a120f6721");
    const priv_pk = unhex("dfc49dd7b08e0a816871a7ed921e5c97cca536405d0465f7e71da4076278ceec" ++ "02766c3b9e68e98e06d5f62859e6c991ff69054bd94d30df3a4a1b5f31040a02");
    var sig2: [64]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ecdsa_p256_sign(&priv, "sample".ptr, 6, &sig2));
    try std.testing.expectEqual(OK, sa_ecdsa_p256_verify(&priv_pk, "sample".ptr, 6, &sig2, &valid));
    try std.testing.expectEqual(@as(u32, 1), valid);
    // deterministic signer: the same input signs to the same bytes
    var sig3: [64]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ecdsa_p256_sign(&priv, "sample".ptr, 6, &sig3));
    try std.testing.expectEqualSlices(u8, &sig2, &sig3);
}

test "timing_safe_equal: content and length semantics" {
    var eq: u32 = 0;
    try std.testing.expectEqual(OK, sa_crypto_timing_safe_equal("abc".ptr, 3, "abc".ptr, 3, &eq));
    try std.testing.expectEqual(@as(u32, 1), eq);
    try std.testing.expectEqual(OK, sa_crypto_timing_safe_equal("abc".ptr, 3, "abd".ptr, 3, &eq));
    try std.testing.expectEqual(@as(u32, 0), eq);
    try std.testing.expectEqual(OK, sa_crypto_timing_safe_equal("abc".ptr, 3, "abcd".ptr, 4, &eq));
    try std.testing.expectEqual(@as(u32, 0), eq);
}
