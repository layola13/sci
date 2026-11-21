const std = @import("std");
const DynLib = @import("sa_crypto.zig").DynLib;
const ERR_INVALID = @import("sa_crypto.zig").ERR_INVALID;
const ERR_IO = @import("sa_crypto.zig").ERR_IO;
const ERR_NOMEM = @import("sa_crypto.zig").ERR_NOMEM;
const ERR_NOT_FOUND = @import("sa_crypto.zig").ERR_NOT_FOUND;
const ERR_TRUNCATED = @import("sa_crypto.zig").ERR_TRUNCATED;
const ERR_UNSUPPORTED = @import("sa_crypto.zig").ERR_UNSUPPORTED;
const OK = @import("sa_crypto.zig").OK;
const dupeZ = @import("sa_crypto.zig").dupeZ;
const sio = @import("sa_crypto.zig").sio;

pub const GError = extern struct {
    domain: u32,
    code: i32,
    message: ?[*:0]const u8,
};

pub const SecretSchemaAttr = extern struct {
    name: ?[*:0]const u8,
    type_: c_int,
};

pub const SecretSchema = extern struct {
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

pub const keyring_schema: SecretSchema = makeSchema();

pub const attr_key: [*:0]const u8 = "key";

pub fn makeSchema() SecretSchema {
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

pub const FnStoreSync = *const fn (*const SecretSchema, [*:0]const u8, [*:0]const u8, [*:0]const u8, ?*anyopaque, *?*GError, ...) callconv(.c) i32;

pub const FnLookupSync = *const fn (*const SecretSchema, ?*anyopaque, *?*GError, ...) callconv(.c) ?[*:0]u8;

pub const FnClearSync = *const fn (*const SecretSchema, ?*anyopaque, *?*GError, ...) callconv(.c) i32;

pub const FnErrorFree = *const fn (?*GError) callconv(.c) void;

pub const FnFree = *const fn (?*anyopaque) callconv(.c) void;

pub var secret_mu = std.Io.Mutex.init;

pub var secret_state: enum { unloaded, ready, missing } = .unloaded;

pub var secret_lib: ?DynLib = null;

pub var store_fn: FnStoreSync = undefined;

pub var lookup_fn: FnLookupSync = undefined;

pub var clear_fn: FnClearSync = undefined;

pub var error_free_fn: FnErrorFree = undefined;

pub var g_free_fn: FnFree = undefined;

pub fn ensureSecret() bool {
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

pub fn collectionZ(alloc: std.mem.Allocator, col_ptr: ?[*]const u8, col_len: u64) ![:0]u8 {
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
