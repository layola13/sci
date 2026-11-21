const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_ABI_VERSION = @import("../sa_std.zig").SA_STD_ABI_VERSION;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("consts.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_OK = @import("consts.zig").SA_STD_OK;
const SA_STD_STDERR = @import("consts.zig").SA_STD_STDERR;
const SA_STD_STDIN = @import("consts.zig").SA_STD_STDIN;
const SA_STD_STDOUT = @import("../sa_std.zig").SA_STD_STDOUT;
extern fn u_strFromUTF8_74(dest: [*]u16, dest_cap: c_int, dest_len: ?*c_int, src: [*]const u8, src_len: c_int, err: *c_int) ?[*]u16;
extern fn u_strToUTF8_74(dest: ?[*]u8, dest_cap: c_int, dest_len: ?*c_int, src: [*]const u16, src_len: c_int, err: *c_int) ?[*]u8;
extern fn unorm2_normalize_74(norm2: ?*anyopaque, src: [*]const u16, src_len: c_int, dest: [*]u16, dest_cap: c_int, err: *c_int) c_int;
pub const constBytes = @import("../sa_std.zig").constBytes;
pub const finish = @import("../sa_std.zig").finish;
pub const finishErr = @import("../sa_std.zig").finishErr;
pub const icu_err_overflow = @import("../sa_std.zig").icu_err_overflow;
pub const isAsciiWhitespace = @import("../sa_std.zig").isAsciiWhitespace;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
pub const lxClose = @import("../sa_std.zig").lxClose;
pub const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
pub const saNumCheckedTrap = @import("../sa_std.zig").saNumCheckedTrap;
const sio = @import("../sa_std.zig").sio;
pub const unicodeNormalizerForForm = @import("../sa_std.zig").unicodeNormalizerForForm;

pub export fn sa_std_version() u32 {
    return SA_STD_ABI_VERSION;
}

pub export fn sa_num_add_checked(a: i64, b: i64) i64 {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_add_checked", a, b);
    return result[0];
}

pub export fn sa_num_sub_checked(a: i64, b: i64) i64 {
    const result = @subWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_sub_checked", a, b);
    return result[0];
}

pub export fn sa_num_mul_checked(a: i64, b: i64) i64 {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_mul_checked", a, b);
    return result[0];
}

pub export fn sa_std_last_error() i32 {
    return sa_std.last_error;
}

pub export fn sa_std_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_std_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_std_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_std_print(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    sio.getStdOut().writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_unicode_normalize(text: ?[*]const u8, text_len: u64, form: i32, out: ?[*]u8, out_cap: u64) i64 {
    if (text_len == 0) return 0;
    if (text_len > 0x7fffffff) @panic("sa_unicode_normalize: input too long");
    const input = constBytes(text, text_len) catch @panic("sa_unicode_normalize: null input");
    const norm = unicodeNormalizerForForm(form);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // UTF-8 -> UTF-16. UTF-16 units never exceed UTF-8 bytes (1-byte char
    // -> 1 unit; 4-byte char -> 2 units), so text_len units always suffice.
    const utf16_cap: c_int = @intCast(text_len);
    const utf16 = alloc.alloc(u16, @as(usize, @intCast(text_len))) catch @panic("sa_unicode_normalize: alloc failed");
    var utf16_len: c_int = 0;
    var err: c_int = 0;
    _ = u_strFromUTF8_74(utf16.ptr, utf16_cap, &utf16_len, input.ptr, utf16_cap, &err);
    if (err > 0) @panic("sa_unicode_normalize: invalid UTF-8 input");

    // Normalize in UTF-16. Decomposition can expand, so grow on overflow
    // (unorm2_normalize_74 returns the needed length on overflow).
    var norm_cap: usize = @as(usize, @intCast(utf16_len)) * 2;
    if (norm_cap < 16) norm_cap = 16;
    var norm_buf = alloc.alloc(u16, norm_cap) catch @panic("sa_unicode_normalize: alloc failed");
    err = 0;
    var norm_len = unorm2_normalize_74(norm, utf16.ptr, utf16_len, norm_buf.ptr, @intCast(norm_cap), &err);
    if (err == icu_err_overflow) {
        if (norm_len <= 0) @panic("sa_unicode_normalize: ICU normalize failed");
        norm_cap = @intCast(norm_len);
        norm_buf = alloc.alloc(u16, norm_cap) catch @panic("sa_unicode_normalize: alloc failed");
        err = 0;
        norm_len = unorm2_normalize_74(norm, utf16.ptr, utf16_len, norm_buf.ptr, @intCast(norm_cap), &err);
        if (err != 0) @panic("sa_unicode_normalize: ICU normalize failed");
    } else if (err > 0) {
        @panic("sa_unicode_normalize: ICU normalize failed");
    }

    // Measure the UTF-8 length (destCapacity 0 query), then fill or report.
    var utf8_len: c_int = 0;
    err = 0;
    _ = u_strToUTF8_74(null, 0, &utf8_len, norm_buf.ptr, norm_len, &err);
    if (err > 0 and err != icu_err_overflow) @panic("sa_unicode_normalize: ICU UTF-8 measure failed");
    if (out_cap == 0 or out == null) return utf8_len;
    if (@as(u64, @intCast(utf8_len)) > out_cap) return utf8_len;
    var written: c_int = 0;
    err = 0;
    _ = u_strToUTF8_74(out.?, @intCast(out_cap), &written, norm_buf.ptr, norm_len, &err);
    if (err > 0) @panic("sa_unicode_normalize: ICU UTF-8 convert failed");
    return written;
}

pub export fn sa_host_is_bun() i32 {
    return 0;
}

pub export fn sa_std_fd_from_raw(fd: i32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const handle = registerResourceLocked(.{ .owned_fd = .{ .fd = @as(std.posix.fd_t, @intCast(fd)) } }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_close_raw(fd: i32) i32 {
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    lxClose(@as(std.posix.fd_t, @intCast(fd)));
    return finish(SA_STD_OK);
}

pub export fn sa_thread_current_id() u64 {
    return @as(u64, @intCast(std.Thread.getCurrentId()));
}

pub export fn sa_thread_yield_now() i32 {
    std.Thread.yield() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_parse_float(ptr: ?[*]const u8, len: u64) f64 {
    const bytes = constBytes(ptr, len) catch return std.math.nan(f64);
    var i: usize = 0;
    while (i < bytes.len and isAsciiWhitespace(bytes[i])) : (i += 1) {}
    var negative = false;
    if (i < bytes.len and (bytes[i] == '+' or bytes[i] == '-')) {
        negative = bytes[i] == '-';
        i += 1;
    }
    const rest = bytes[i..];
    if (rest.len >= 8 and std.mem.eql(u8, rest[0..8], "Infinity")) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
    if (rest.len >= 3 and std.mem.eql(u8, rest[0..3], "NaN")) return std.math.nan(f64);
    // Scan the maximal decimal prefix: digits[.digits][(e|E)[+-]digits],
    // requiring at least one digit on either side of the dot.
    var j: usize = 0;
    while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {}
    const int_digits = j;
    if (j < rest.len and rest[j] == '.') {
        j += 1;
        while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {}
    }
    const frac_digits = j - int_digits - @as(usize, if (j > int_digits and rest[int_digits] == '.') 1 else 0);
    if (int_digits == 0 and frac_digits == 0) return std.math.nan(f64);
    var k: usize = j;
    if (k < rest.len and (rest[k] == 'e' or rest[k] == 'E')) {
        var m: usize = k + 1;
        if (m < rest.len and (rest[m] == '+' or rest[m] == '-')) m += 1;
        const exp_start = m;
        while (m < rest.len and rest[m] >= '0' and rest[m] <= '9') : (m += 1) {}
        if (m > exp_start) k = m;
    }
    const num = std.fmt.parseFloat(f64, rest[0..k]) catch |err| {
        if (err == error.Overflow) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
        return std.math.nan(f64);
    };
    // parseFloat scanned an unsigned prefix; apply the leading sign here
    // (a second negation of an explicitly signed prefix cannot occur:
    // the scan above never consumes '+'/'-').
    return if (negative) -num else num;
}

pub export fn sa_mem_free(ptr: ?*anyopaque) void {
    if (comptime is_wasm) return;
    if (ptr) |p| std.c.free(p);
}

pub export fn sa_print_bytes(msg: ?[*]const u8, len: u64) void {
    _ = sa_std_print(msg, len);
}
