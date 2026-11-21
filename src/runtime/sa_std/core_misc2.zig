const std = @import("std");
const sa_std = @import("../sa_std.zig");
pub const InAddrC = @import("../sa_std.zig").InAddrC;
pub const NetAddress = @import("../sa_std.zig").NetAddress;
const SA_JSON_WHITESPACE_MINIFIED = @import("consts.zig").SA_JSON_WHITESPACE_MINIFIED;
const SA_STD_ERR_INVALID_ARGUMENT = @import("consts.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_ERR_UNSUPPORTED = @import("consts.zig").SA_STD_ERR_UNSUPPORTED;
pub const SA_STD_OK = @import("consts.zig").SA_STD_OK;
pub const Timespec = @import("../sa_std.zig").Timespec;
pub const constBytes = @import("../sa_std.zig").constBytes;
pub const empty_mut_bytes = @import("../sa_std.zig").empty_mut_bytes;
pub const fbsd_sys_nmln = @import("../sa_std.zig").fbsd_sys_nmln;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
pub const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
const sio = @import("../sa_std.zig").sio;

pub const RegexC = if (is_wasm) extern struct {
    re_nsub: usize,
    __opaque: ?*anyopaque,
    __padding: [4]?*anyopaque,
    __nsub2: usize,
    __padding2: u8,
} else extern struct {
    buffer: ?*anyopaque,
    allocated: c_ulong,
    used: c_ulong,
    syntax: c_ulong,
    fastmap: ?[*]u8,
    translate: ?[*]u8,
    re_nsub: usize,
    flags: u32,
};

const IpMreqC = extern struct {
    imr_multiaddr: InAddrC,
    imr_interface: InAddrC,
};

pub const fbsd_utsname = extern struct {
    sysname: [fbsd_sys_nmln]u8,
    nodename: [fbsd_sys_nmln]u8,
    release: [fbsd_sys_nmln]u8,
    version: [fbsd_sys_nmln]u8,
    machine: [fbsd_sys_nmln]u8,
};

pub const SaPluginDescriptor = extern struct {
    abi_version: u32,
    descriptor_size: u32,
    name: [*:0]const u8,
};

// eflags slot value for regexec: restrict the search to the pmatch[0] range
// while reporting absolute offsets. glibc assigns it the same numeric value
// as the SA_REGEX_NEWLINE *cflag*; the two live in different parameters.

pub const SaJsonToken = extern struct {
    kind: u32,
    text_ptr: ?[*]const u8,
    text_len: u64,
};

pub const SaJsonStringifyOptions = extern struct {
    whitespace: u32 = SA_JSON_WHITESPACE_MINIFIED,
    emit_null_optional_fields: u8 = 1,
    emit_strings_as_arrays: u8 = 0,
    escape_unicode: u8 = 0,
    emit_nonportable_numbers_as_strings: u8 = 0,
};

const SaNetAddr = extern struct {
    family: u32,
    port: u32,
    host_ptr: [*]u8,
    host_len: u64,
    scope_id: u64,
};

const TimespecSec = @TypeOf(@as(Timespec, .{ .sec = 0, .nsec = 0 }).sec);

const TimespecNsec = @TypeOf(@as(Timespec, .{ .sec = 0, .nsec = 0 }).nsec);

pub const SaTermWinsize = extern struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
};

var compatibility_mmap_page: [4096]u8 = std.mem.zeroes([4096]u8);

var compatibility_dlsym_cookie: [1]u8 = .{0};

pub fn mutBytes(ptr: ?[*]u8, len: u64) ![]u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return empty_mut_bytes[0..];
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

pub fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

// Parse one "::"-free half ("1:2:3" or trailing embedded IPv4) into out,
// returning the group count. Used only on FreeBSD (see parseIpv6Freebsd).
// Numeric IPv6 parser for FreeBSD: the old Ip6Address.resolve/parse and
// Address.resolveIp all reach if_nametoindex (unimplemented for freebsd in
// zig 0.14). Handles full, "::"-compressed and embedded-IPv4 forms.
// "addr" or "addr%zone" (numeric zone, or interface name via libc
// if_nametoindex which FreeBSD provides). Shared by parseIp6Address and
// parseIpv6Ascii on FreeBSD.

pub fn makeIpv4Membership(multicast_addr: NetAddress, interface_addr: NetAddress) IpMreqC {
    return .{
        .imr_multiaddr = .{ .s_addr = multicast_addr.in4AddrU32() },
        .imr_interface = .{ .s_addr = interface_addr.in4AddrU32() },
    };
}

/// Fixed UTC string forms for Date toString/toDateString/toTimeString/
/// toUTCString (fmt 0..3), byte-exact with Node under UTC. Years use the
/// same 4-digit zero pad as the ISO path (documented bound 0..9999).

pub fn daysFromCivil(y_in: i64, m_in: i64, d: i64) i64 {
    const y: i64 = if (m_in <= 2) y_in - 1 else y_in;
    const era: i64 = if (y >= 0) @divFloor(y, 400) else @divFloor(y - 399, 400);
    const yoe: i64 = y - era * 400;
    const mp: i64 = @mod(m_in - 3, 12);
    const doy: i64 = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

// JS Date setters over i64 unix millis (field 0..6). Components apply
// then normalize with floored divmod, so out-of-range values roll over
// exactly like JS (setMonth(13), setDate(0), setHours(25), negatives).
// Unknown field ids return the input unchanged (frontends only ever
// send 0..6 via fixed table extras).
// Compatibility shims for the rosetta demos that model host APIs directly.

pub fn fd_open(path_ptr: ?[*]const u8) callconv(.c) i32 {
    _ = path_ptr;
    sa_std.last_error = SA_STD_OK;
    return 3;
}

pub fn fd_read(fd: i32) callconv(.c) i32 {
    _ = fd;
    sa_std.last_error = SA_STD_OK;
    return 3;
}

pub fn fd_close(fd: i32) callconv(.c) i32 {
    _ = fd;
    sa_std.last_error = SA_STD_ERR_UNSUPPORTED;
    return SA_STD_ERR_UNSUPPORTED;
}

pub fn mmap(fd: i32, len: i32) callconv(.c) ?[*]u8 {
    _ = fd;
    _ = len;
    sa_std.last_error = SA_STD_OK;
    return compatibility_mmap_page[0..].ptr;
}

pub fn munmap(map: ?[*]u8, len: i32) callconv(.c) i32 {
    _ = map;
    _ = len;
    sa_std.last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn dlsym(handle: ?[*]u8, symbol_ptr: ?[*]const u8) callconv(.c) ?[*]u8 {
    _ = handle;
    _ = symbol_ptr;
    sa_std.last_error = SA_STD_ERR_UNSUPPORTED;
    return compatibility_dlsym_cookie[0..].ptr;
}

/// mkdir -p (2026-10-26): create every missing directory along the
/// path. Existing directories along the way (including the final
/// segment) are success; the TS mkdirSync(recursive) counterpart.

pub fn timespecFromUnixMs(unix_ms: i64) !Timespec {
    const sec = @divFloor(unix_ms, 1000);
    const rem_ms = @mod(unix_ms, 1000);
    const sec_value = std.math.cast(TimespecSec, sec) orelse return error.InvalidArgument;
    const nsec_value = std.math.cast(TimespecNsec, rem_ms * 1_000_000) orelse return error.InvalidArgument;
    return .{ .sec = sec_value, .nsec = nsec_value };
}

// JS `String.prototype.repeat`: `bytes` concatenated `count` times.
// `count == 0` yields an empty handle; size overflow yields 0
// (OOM-equivalent). Fresh buffer handle, concat read-back protocol.
/// Shared pad filler: `pad` bytes tiled/truncated to exactly `fill` bytes.

pub fn tilePad(owned: []u8, pad: []const u8) void {
    var i: usize = 0;
    while (i < owned.len) {
        const n = @min(pad.len, owned.len - i);
        std.mem.copyForwards(u8, owned[i..][0..n], pad[0..n]);
        i += n;
    }
}

// Fill the caller buffer with bytes from the OS CSPRNG (the same source
// behind cryptoRandomU64 and sa_deno_random_uuid). A zero length is a
// no-op success, including with a null pointer.

pub export fn sa_crypto_random_bytes(out_ptr: ?[*]u8, len: u64) i32 {
    if (len == 0) return finish(SA_STD_OK);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const n = lenAsUsize(len) catch |err| return finishErr(err);
    sio.io().random(out[0..n]);
    return finish(SA_STD_OK);
}
