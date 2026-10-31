//! sa_std compression primitives: gzip / zlib-deflate / raw deflate via
//! Zig std flate, brotli via dlopen (libbrotlienc/libbrotlidec).
//!
//! One-shot buffer API following the sci buffer-handle convention:
//! encode/decode return a u64 handle; read it with
//! sa_std_compress_buffer_data / _len and release with _free.
//! Formats: 1 = gzip, 2 = zlib (HTTP "deflate"), 3 = raw deflate,
//! 4 = brotli. Status codes mirror sa_std.zig (0 ok, 1 invalid
//! argument, 5 no memory, 6 io, 8 unsupported, 9 truncated).

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

/// WASI has no dynamic loading (std.DynLib does not exist there);
/// the stub keeps the brotli loader compiling and its open always
/// fails, so brotli reports itself missing (loadBrotli -> null ->
/// error.Unsupported) — loud, never a fake success.
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
const ERR_NOMEM: i32 = 5;
const ERR_IO: i32 = 6;
const ERR_UNSUPPORTED: i32 = 8;

const FORMAT_GZIP: u32 = 1;
const FORMAT_ZLIB: u32 = 2;
const FORMAT_RAW: u32 = 3;
const FORMAT_BROTLI: u32 = 4;

const MAX_INPUT: usize = 512 * 1024 * 1024;

// ---------- buffer handles ----------
var buffers_mu = std.Io.Mutex.init;
var buffers: std.AutoHashMapUnmanaged(u64, []u8) = .empty;
var next_handle: u64 = 1;

fn registerBuffer(data: []u8) !u64 {
    buffers_mu.lockUncancelable(sio.io());
    defer buffers_mu.unlock(sio.io());
    const h = next_handle;
    next_handle += 1;
    try buffers.put(std.heap.page_allocator, h, data);
    return h;
}

fn takeBuffer(handle: u64) ?[]u8 {
    buffers_mu.lockUncancelable(sio.io());
    defer buffers_mu.unlock(sio.io());
    const kv = buffers.fetchRemove(handle) orelse return null;
    return kv.value;
}

fn peekBuffer(handle: u64) ?[]u8 {
    buffers_mu.lockUncancelable(sio.io());
    defer buffers_mu.unlock(sio.io());
    return buffers.get(handle);
}

pub export fn sa_std_compress_buffer_data(handle: u64) ?[*]const u8 {
    const b = peekBuffer(handle) orelse return null;
    return b.ptr;
}

pub export fn sa_std_compress_buffer_len(handle: u64) u64 {
    const b = peekBuffer(handle) orelse return 0;
    return b.len;
}

pub export fn sa_std_compress_buffer_free(handle: u64) i32 {
    const b = takeBuffer(handle) orelse return 2; // invalid handle
    std.heap.page_allocator.free(b);
    return OK;
}

// ---------- brotli (dlopen) ----------
const BrotliApi = struct {
    enc_max_size: *const fn (usize) callconv(.c) usize,
    enc_compress: *const fn (c_int, c_int, c_int, usize, [*]const u8, *usize, [*]u8) callconv(.c) c_int,
    dec_create: *const fn (?*const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque,
    dec_destroy: *const fn (?*anyopaque) callconv(.c) void,
    dec_stream: *const fn (?*anyopaque, *usize, *?[*]const u8, *usize, *?[*]u8) callconv(.c) c_int,
    dec_is_finished: *const fn (?*anyopaque) callconv(.c) c_int,
};

var brotli_api: ?BrotliApi = null;
var brotli_tried: bool = false;
var brotli_mu = std.Io.Mutex.init;

fn loadBrotli() ?BrotliApi {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return loadBrotliNative();
    }
}

fn loadBrotliNative() ?BrotliApi {
    brotli_mu.lockUncancelable(sio.io());
    defer brotli_mu.unlock(sio.io());
    if (brotli_api) |a| return a;
    if (brotli_tried) return null;
    brotli_tried = true;
    var enc_lib = DynLib.open("libbrotlienc.so.1") catch return null;
    var dec_lib = DynLib.open("libbrotlidec.so.1") catch return null;
    const api = BrotliApi{
        .enc_max_size = enc_lib.lookup(*const fn (usize) callconv(.c) usize, "BrotliEncoderMaxCompressedSize") orelse return null,
        .enc_compress = enc_lib.lookup(*const fn (c_int, c_int, c_int, usize, [*]const u8, *usize, [*]u8) callconv(.c) c_int, "BrotliEncoderCompress") orelse return null,
        .dec_create = dec_lib.lookup(*const fn (?*const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque, "BrotliDecoderCreateInstance") orelse return null,
        .dec_destroy = dec_lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "BrotliDecoderDestroyInstance") orelse return null,
        .dec_stream = dec_lib.lookup(*const fn (?*anyopaque, *usize, *?[*]const u8, *usize, *?[*]u8) callconv(.c) c_int, "BrotliDecoderDecompressStream") orelse return null,
        .dec_is_finished = dec_lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "BrotliDecoderIsFinished") orelse return null,
    };
    brotli_api = api;
    return api;
}

fn brotliEncode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const api = loadBrotli() orelse return error.Unsupported;
    const cap = api.enc_max_size(data.len);
    const out = try allocator.alloc(u8, cap);
    errdefer allocator.free(out);
    var out_len: usize = cap;
    // mode 0 = generic, quality 5, lgwin 22
    if (api.enc_compress(0, 5, 22, data.len, data.ptr, &out_len, out.ptr) != 1) return error.Io;
    return allocator.realloc(out, out_len) catch out[0..out_len];
}

fn brotliDecode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const api = loadBrotli() orelse return error.Unsupported;
    const state = api.dec_create(null, null, null) orelse return error.Io;
    defer api.dec_destroy(state);
    var list = std.array_list.Managed(u8).init(allocator);
    errdefer list.deinit();
    var in_ptr: ?[*]const u8 = data.ptr;
    var in_len: usize = data.len;
    var chunk: [16384]u8 = undefined;
    while (true) {
        var out_ptr: ?[*]u8 = &chunk;
        var out_len: usize = chunk.len;
        const rc = api.dec_stream(state, &in_len, &in_ptr, &out_len, &out_ptr);
        const produced = chunk.len - out_len;
        if (produced > 0) try list.appendSlice(chunk[0..produced]);
        if (api.dec_is_finished(state) == 1) break;
        if (rc == 0) return error.Io; // BROTLI_DECODER_RESULT_ERROR
        if (in_len == 0 and produced == 0) return error.Io;
    }
    return list.toOwnedSlice();
}

// ---------- flate (std) ----------
fn flateContainer(format: u32) ?std.compress.flate.Container {
    return switch (format) {
        FORMAT_GZIP => .gzip,
        FORMAT_ZLIB => .zlib,
        FORMAT_RAW => .raw,
        else => null,
    };
}

fn flateEncode(allocator: std.mem.Allocator, data: []const u8, container: std.compress.flate.Container) ![]u8 {
    // flate.Compress asserts the output writer has a buffered capacity
    // > 8, so encode into a pre-sized fixed buffer (worst case is the
    // stored-block overhead); grow and retry if it ever falls short.
    var capacity: usize = data.len + data.len / 100 + 4096;
    var attempt: usize = 0;
    while (attempt < 4) : (attempt += 1) {
        const out_buf = try allocator.alloc(u8, capacity);
        defer allocator.free(out_buf);
        var writer = std.Io.Writer.fixed(out_buf);
        var buf: [std.compress.flate.max_window_len]u8 = undefined;
        var comp = std.compress.flate.Compress.init(&writer, &buf, container, .default) catch {
            capacity *= 2;
            continue;
        };
        comp.writer.writeAll(data) catch {
            capacity *= 2;
            continue;
        };
        comp.finish() catch {
            capacity *= 2;
            continue;
        };
        return allocator.dupe(u8, writer.buffered());
    }
    return error.Io;
}

fn flateDecode(allocator: std.mem.Allocator, data: []const u8, container: std.compress.flate.Container) ![]u8 {
    var input = std.Io.Reader.fixed(data);
    var buf: [std.compress.flate.max_window_len]u8 = undefined;
    var dec = std.compress.flate.Decompress.init(&input, container, &buf);
    var list = std.array_list.Managed(u8).init(allocator);
    errdefer list.deinit();
    var chunk: [16384]u8 = undefined;
    while (true) {
        const n = dec.reader.readSliceShort(&chunk) catch return error.Io;
        if (n == 0) break;
        try list.appendSlice(chunk[0..n]);
        if (list.items.len > MAX_INPUT) return error.Io;
    }
    return list.toOwnedSlice();
}

// ---------- exported surface ----------

/// out_flags: bit0 = flate formats available (always), bit1 = brotli.
pub export fn sa_std_compress_supported(out_flags: ?*u32) i32 {
    const slot = out_flags orelse return ERR_INVALID;
    var flags: u32 = 1;
    if (loadBrotli() != null) flags |= 2;
    slot.* = flags;
    return OK;
}

pub export fn sa_std_compress_encode(format: u32, data: ?[*]const u8, data_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return ERR_INVALID;
    slot.* = 0;
    const in = sliceOf(data, data_len) orelse return ERR_INVALID;
    const allocator = std.heap.page_allocator;
    const out = if (flateContainer(format)) |c|
        flateEncode(allocator, in, c) catch return ERR_IO
    else if (format == FORMAT_BROTLI)
        brotliEncode(allocator, in) catch |e| return if (e == error.Unsupported) ERR_UNSUPPORTED else ERR_IO
    else
        return ERR_INVALID;
    slot.* = registerBuffer(out) catch {
        allocator.free(out);
        return ERR_NOMEM;
    };
    return OK;
}

pub export fn sa_std_compress_decode(format: u32, data: ?[*]const u8, data_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return ERR_INVALID;
    slot.* = 0;
    const in = sliceOf(data, data_len) orelse return ERR_INVALID;
    const allocator = std.heap.page_allocator;
    const out = if (flateContainer(format)) |c|
        flateDecode(allocator, in, c) catch return ERR_IO
    else if (format == FORMAT_BROTLI)
        brotliDecode(allocator, in) catch |e| return if (e == error.Unsupported) ERR_UNSUPPORTED else ERR_IO
    else
        return ERR_INVALID;
    slot.* = registerBuffer(out) catch {
        allocator.free(out);
        return ERR_NOMEM;
    };
    return OK;
}

fn sliceOf(ptr: ?[*]const u8, len: u64) ?[]const u8 {
    if (len > MAX_INPUT) return null;
    if (len == 0) return "";
    const p = ptr orelse return null;
    return p[0..@intCast(len)];
}

// ---------- tests ----------
const testing = std.testing;

test "compress: gzip/zlib/raw round trips" {
    const phrase = "hello sa_std compression - the quick brown fox jumps over the lazy dog. ";
    var msg_buf: [phrase.len * 30]u8 = undefined;
    for (0..30) |i| @memcpy(msg_buf[i * phrase.len ..][0..phrase.len], phrase);
    const msg = &msg_buf;
    for ([_]u32{ FORMAT_GZIP, FORMAT_ZLIB, FORMAT_RAW }) |format| {
        var enc: u64 = 0;
        try testing.expectEqual(OK, sa_std_compress_encode(format, msg.ptr, msg.len, &enc));
        defer _ = sa_std_compress_buffer_free(enc);
        const enc_ptr = sa_std_compress_buffer_data(enc).?;
        const enc_len = sa_std_compress_buffer_len(enc);
        try testing.expect(enc_len < msg.len);
        var dec: u64 = 0;
        try testing.expectEqual(OK, sa_std_compress_decode(format, enc_ptr, enc_len, &dec));
        defer _ = sa_std_compress_buffer_free(dec);
        const dec_ptr = sa_std_compress_buffer_data(dec).?;
        try testing.expectEqualStrings(msg, dec_ptr[0..@intCast(sa_std_compress_buffer_len(dec))]);
    }
}

test "compress: gzip output has gzip magic and brotli round trip when present" {
    const msg = "brotli and gzip walk into a buffer";
    var enc: u64 = 0;
    try testing.expectEqual(OK, sa_std_compress_encode(FORMAT_GZIP, msg.ptr, msg.len, &enc));
    defer _ = sa_std_compress_buffer_free(enc);
    const p = sa_std_compress_buffer_data(enc).?;
    try testing.expectEqual(@as(u8, 0x1f), p[0]);
    try testing.expectEqual(@as(u8, 0x8b), p[1]);

    var flags: u32 = 0;
    try testing.expectEqual(OK, sa_std_compress_supported(&flags));
    if (flags & 2 == 0) return; // brotli libs absent on this host
    var benc: u64 = 0;
    try testing.expectEqual(OK, sa_std_compress_encode(FORMAT_BROTLI, msg.ptr, msg.len, &benc));
    defer _ = sa_std_compress_buffer_free(benc);
    var bdec: u64 = 0;
    try testing.expectEqual(OK, sa_std_compress_decode(FORMAT_BROTLI, sa_std_compress_buffer_data(benc).?, sa_std_compress_buffer_len(benc), &bdec));
    defer _ = sa_std_compress_buffer_free(bdec);
    try testing.expectEqualStrings(msg, sa_std_compress_buffer_data(bdec).?[0..@intCast(sa_std_compress_buffer_len(bdec))]);
}
