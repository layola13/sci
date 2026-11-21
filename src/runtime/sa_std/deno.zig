const std = @import("std");
const Fallible = @import("../sa_std.zig").Fallible;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const TimeDate = @import("../sa_std.zig").TimeDate;
const appendIsoUtc = @import("../sa_std.zig").appendIsoUtc;
const builtin = @import("../sa_std.zig").builtin;
const constBytes = @import("../sa_std.zig").constBytes;
const denoChatJsonToResponses = @import("../sa_std.zig").denoChatJsonToResponses;
const denoChatSseToResponses = @import("../sa_std.zig").denoChatSseToResponses;
const denoResponsesChatFallbackRequest = @import("../sa_std.zig").denoResponsesChatFallbackRequest;
const denoResponsesJsonNormalize = @import("../sa_std.zig").denoResponsesJsonNormalize;
const denoResponsesRequestNormalize = @import("../sa_std.zig").denoResponsesRequestNormalize;
const denoResponsesSseNormalize = @import("../sa_std.zig").denoResponsesSseNormalize;
const envKeyBytes = @import("../sa_std.zig").envKeyBytes;
const fail = @import("../sa_std.zig").fail;
const fbsd_utsname = @import("../sa_std.zig").fbsd_utsname;
const fillUtcNow = @import("../sa_std.zig").fillUtcNow;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const jsonRpcParamsStringLiteralAlloc = @import("../sa_std.zig").jsonRpcParamsStringLiteralAlloc;
const libc = @import("../sa_std.zig").libc;
const mapError = @import("../sa_std.zig").mapError;
const ok = @import("../sa_std.zig").ok;
const openOwnedBuffer = @import("../sa_std.zig").openOwnedBuffer;
const openOwnedByteBuffer = @import("../sa_std.zig").openOwnedByteBuffer;
const pathBytes = @import("../sa_std.zig").pathBytes;
const sio = @import("../sa_std.zig").sio;
const struct_ifaddrs = @import("../sa_std.zig").struct_ifaddrs;
const tempPathAlloc = @import("../sa_std.zig").tempPathAlloc;
extern fn freeifaddrs(ifa: ?*struct_ifaddrs) void;
extern fn getgid() c_uint;
extern fn getifaddrs(ifap: *?*struct_ifaddrs) c_int;
extern fn getpagesize() c_int;
extern fn getpid() c_int;
extern fn getppid() c_int;
extern fn getuid() c_uint;
extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn uname(buf: *fbsd_utsname) c_int;
extern fn unsetenv(name: [*:0]const u8) c_int;
extern fn inet_ntop(af: c_int, src: ?*const anyopaque, dst: [*]u8, size: c_uint) ?[*:0]const u8;

pub export fn sa_deno_cwd() u64 {
    const cwd = sio.getCwdAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(cwd) catch return 0;
}

pub export fn sa_deno_chdir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.changeCurDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_env_set(key_ptr: ?[*]const u8, key_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const value = constBytes(value_ptr, value_len) catch |err| return finishErr(err);
    if (std.mem.indexOfScalar(u8, value, 0) != null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const key_z = std.heap.page_allocator.dupeSentinel(u8, key, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(key_z);
    const value_z = std.heap.page_allocator.dupeSentinel(u8, value, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(value_z);
    if (setenv(key_z.ptr, value_z.ptr, 1) != 0) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_env_delete(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const key_z = std.heap.page_allocator.dupeSentinel(u8, key, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(key_z);
    if (unsetenv(key_z.ptr) != 0) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_random_uuid() u64 {
    var bytes: [16]u8 = undefined;
    sio.io().random(&bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    var text: [36]u8 = undefined;
    _ = std.fmt.bufPrint(
        &text,
        "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        },
    ) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, &text) catch return 0;
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_deno_make_temp_dir(prefix_ptr: ?[*]const u8, prefix_len: u64) Fallible(u64) {
    const prefix = constBytes(prefix_ptr, prefix_len) catch |err| return fail(u64, mapError(err));
    if (std.mem.indexOfScalar(u8, prefix, 0) != null) return fail(u64, SA_STD_ERR_INVALID_ARGUMENT);
    const allocator = std.heap.page_allocator;
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = tempPathAlloc(allocator, prefix, "") catch |err| return fail(u64, mapError(err));
        sio.cwd().makeDir(path) catch |err| {
            allocator.free(path);
            if (err == error.PathAlreadyExists) continue;
            return fail(u64, mapError(err));
        };
        const handle = openOwnedByteBuffer(path) catch |err| return fail(u64, mapError(err));
        return ok(u64, handle);
    }
    return fail(u64, SA_STD_ERR_IO);
}

pub export fn sa_deno_make_temp_file(
    prefix_ptr: ?[*]const u8,
    prefix_len: u64,
    suffix_ptr: ?[*]const u8,
    suffix_len: u64,
) Fallible(u64) {
    const prefix = constBytes(prefix_ptr, prefix_len) catch |err| return fail(u64, mapError(err));
    const suffix = constBytes(suffix_ptr, suffix_len) catch |err| return fail(u64, mapError(err));
    if (std.mem.indexOfScalar(u8, prefix, 0) != null) return fail(u64, SA_STD_ERR_INVALID_ARGUMENT);
    if (std.mem.indexOfScalar(u8, suffix, 0) != null) return fail(u64, SA_STD_ERR_INVALID_ARGUMENT);
    const allocator = std.heap.page_allocator;
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = tempPathAlloc(allocator, prefix, suffix) catch |err| return fail(u64, mapError(err));
        const file = sio.cwd().createFile(path, .{ .read = true, .exclusive = true }) catch |err| {
            allocator.free(path);
            if (err == error.PathAlreadyExists) continue;
            return fail(u64, mapError(err));
        };
        file.close();
        const handle = openOwnedByteBuffer(path) catch |err| return fail(u64, mapError(err));
        return ok(u64, handle);
    }
    return fail(u64, SA_STD_ERR_IO);
}

pub export fn sa_deno_args_json() u64 {
    var args = sio.argsAlloc(std.heap.page_allocator) catch return 0;
    defer sio.argsFree(std.heap.page_allocator, args);

    const deno_args = if (args.len > 0) args[1..] else args[0..0];
    const json = std.json.Stringify.valueAlloc(std.heap.page_allocator, deno_args, .{}) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_btoa(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch return 0;
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return openOwnedBuffer(encoded) catch return 0;
}

pub export fn sa_deno_atob(data_ptr: ?[*]const u8, len: u64) u64 {
    const encoded = constBytes(data_ptr, len) catch return 0;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return 0;
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch return 0;
    errdefer std.heap.page_allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded) catch return 0;
    return openOwnedBuffer(decoded) catch return 0;
}

pub export fn sa_deno_text_encode(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_text_decode(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_chat_sse_to_responses(
    chat_body_ptr: ?[*]const u8,
    chat_body_len: u64,
    req_body_ptr: ?[*]const u8,
    req_body_len: u64,
) u64 {
    const chat_body = constBytes(chat_body_ptr, chat_body_len) catch return 0;
    const req_body = constBytes(req_body_ptr, req_body_len) catch return 0;
    const converted = denoChatSseToResponses(chat_body, req_body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_chat_json_to_responses(
    chat_body_ptr: ?[*]const u8,
    chat_body_len: u64,
    req_body_ptr: ?[*]const u8,
    req_body_len: u64,
) u64 {
    const chat_body = constBytes(chat_body_ptr, chat_body_len) catch return 0;
    const req_body = constBytes(req_body_ptr, req_body_len) catch return 0;
    const converted = denoChatJsonToResponses(chat_body, req_body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_responses_sse_normalize(
    sse_body_ptr: ?[*]const u8,
    sse_body_len: u64,
) u64 {
    const sse_body = constBytes(sse_body_ptr, sse_body_len) catch return 0;
    const converted = denoResponsesSseNormalize(sse_body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_responses_json_normalize(
    body_ptr: ?[*]const u8,
    body_len: u64,
) u64 {
    const body = constBytes(body_ptr, body_len) catch return 0;
    const converted = denoResponsesJsonNormalize(body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_responses_request_normalize(
    body_ptr: ?[*]const u8,
    body_len: u64,
) u64 {
    const body = constBytes(body_ptr, body_len) catch return 0;
    const converted = denoResponsesRequestNormalize(body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_responses_chat_fallback_request(
    body_ptr: ?[*]const u8,
    body_len: u64,
    default_model_ptr: ?[*]const u8,
    default_model_len: u64,
    plan_mode_like: u8,
) u64 {
    const body = constBytes(body_ptr, body_len) catch return 0;
    const default_model = constBytes(default_model_ptr, default_model_len) catch return 0;
    const converted = denoResponsesChatFallbackRequest(body, default_model, plan_mode_like != 0) catch return 0;
    const actual = converted orelse return 0;
    return openOwnedByteBuffer(actual) catch return 0;
}

pub export fn sa_deno_jsonrpc_params_string_literal(
    body_ptr: ?[*]const u8,
    body_len: u64,
    key_ptr: ?[*]const u8,
    key_len: u64,
    fallback_ptr: ?[*]const u8,
    fallback_len: u64,
    emit_null_if_missing: u8,
) u64 {
    const body = constBytes(body_ptr, body_len) catch return 0;
    const key = constBytes(key_ptr, key_len) catch return 0;
    const fallback = constBytes(fallback_ptr, fallback_len) catch return 0;
    const literal = jsonRpcParamsStringLiteralAlloc(body, key, fallback, emit_null_if_missing != 0) catch return 0;
    return openOwnedByteBuffer(literal) catch return 0;
}

pub export fn sa_deno_version_json() u64 {
    const json = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"deno\":\"sa-std\",\"v8\":\"\",\"typescript\":\"\",\"sci\":\"{s}\"}}",
        .{builtin.zig_version_string},
    ) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_version_deno() u64 {
    const owned = std.heap.page_allocator.dupe(u8, "sa-std") catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_build_json() u64 {
    const os = @tagName(builtin.os.tag);
    const arch = @tagName(builtin.cpu.arch);
    const vendor = @tagName(builtin.abi);
    const json = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"os\":\"{s}\",\"arch\":\"{s}\",\"target\":\"{s}-{s}\"}}",
        .{ os, arch, arch, vendor },
    ) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_build_os() u64 {
    const os = @tagName(builtin.os.tag);
    const owned = std.heap.page_allocator.dupe(u8, os) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_build_platform_family() u64 {
    const family = if (builtin.os.tag == .windows) "windows" else "unix";
    const owned = std.heap.page_allocator.dupe(u8, family) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_date_now_iso() u64 {
    var date: TimeDate = undefined;
    fillUtcNow(&date) catch return 0;
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    appendIsoUtc(&out, date.year, date.month, date.day, date.hour, date.minute, date.second, date.millisecond) catch return 0;
    return openOwnedByteBuffer(out.toOwnedSlice() catch return 0) catch return 0;
}

pub export fn sa_deno_hostname() u64 {
    // FreeBSD: std.posix.uname is void in zig 0.14; call libc directly.
    if (comptime builtin.os.tag == .freebsd) {
        var uts: fbsd_utsname = undefined;
        if (uname(&uts) != 0) return 0;
        const nodename = std.mem.sliceTo(uts.nodename[0..], 0);
        const owned = std.heap.page_allocator.dupe(u8, nodename) catch return 0;
        return openOwnedByteBuffer(owned) catch return 0;
    }
    const uname_val = std.posix.uname();
    const nodename = std.mem.sliceTo(&uname_val.nodename, 0);
    const owned = std.heap.page_allocator.dupe(u8, nodename) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_os_release() u64 {
    if (comptime builtin.os.tag == .freebsd) {
        var uts: fbsd_utsname = undefined;
        if (uname(&uts) != 0) return 0;
        const release = std.mem.sliceTo(uts.release[0..], 0);
        const owned = std.heap.page_allocator.dupe(u8, release) catch return 0;
        return openOwnedByteBuffer(owned) catch return 0;
    }
    const uname_val = std.posix.uname();
    const release = std.mem.sliceTo(&uname_val.release, 0);
    const owned = std.heap.page_allocator.dupe(u8, release) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_os_uptime() f64 {
    var file = sio.openFileAbsolute("/proc/uptime", .{}) catch return -1.0;
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.read(&buf) catch return -1.0;
    const content = buf[0..n];
    const space_idx = std.mem.indexOfScalar(u8, content, ' ') orelse content.len;
    const uptime_str = std.mem.trim(u8, content[0..space_idx], " \t\r\n");
    return std.fmt.parseFloat(f64, uptime_str) catch -1.0;
}

pub export fn sa_deno_loadavg(out_ptr: ?*f64) i32 {
    const ptr = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var file = sio.openFileAbsolute("/proc/loadavg", .{}) catch return finish(SA_STD_ERR_IO);
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.read(&buf) catch return finish(SA_STD_ERR_IO);
    const content = buf[0..n];
    var it = std.mem.tokenizeScalar(u8, content, ' ');
    const l1_str = it.next() orelse return finish(SA_STD_ERR_IO);
    const l2_str = it.next() orelse return finish(SA_STD_ERR_IO);
    const l3_str = it.next() orelse return finish(SA_STD_ERR_IO);
    const l1 = std.fmt.parseFloat(f64, l1_str) catch return finish(SA_STD_ERR_IO);
    const l2 = std.fmt.parseFloat(f64, l2_str) catch return finish(SA_STD_ERR_IO);
    const l3 = std.fmt.parseFloat(f64, l3_str) catch return finish(SA_STD_ERR_IO);
    const dest: [*]f64 = @ptrCast(ptr);
    dest[0] = l1;
    dest[1] = l2;
    dest[2] = l3;
    return finish(SA_STD_OK);
}

pub export fn sa_deno_system_memory_info() u64 {
    var file = sio.openFileAbsolute("/proc/meminfo", .{}) catch return 0;
    defer file.close();
    var buf: [2048]u8 = undefined;
    const n = file.read(&buf) catch return 0;
    const content = buf[0..n];

    var total: u64 = 0;
    var free: u64 = 0;
    var available: u64 = 0;
    var buffers: u64 = 0;
    var cached: u64 = 0;
    var swapTotal: u64 = 0;
    var swapFree: u64 = 0;

    var it = std.mem.tokenizeScalar(u8, content, '\n');
    while (it.next()) |line| {
        var line_it = std.mem.tokenizeAny(u8, line, " \t:");
        const key = line_it.next() orelse continue;
        const val_str = line_it.next() orelse continue;
        const val = std.fmt.parseInt(u64, val_str, 10) catch continue;
        const bytes = val * 1024;
        if (std.mem.eql(u8, key, "MemTotal")) {
            total = bytes;
        } else if (std.mem.eql(u8, key, "MemFree")) {
            free = bytes;
        } else if (std.mem.eql(u8, key, "MemAvailable")) {
            available = bytes;
        } else if (std.mem.eql(u8, key, "Buffers")) {
            buffers = bytes;
        } else if (std.mem.eql(u8, key, "Cached")) {
            cached = bytes;
        } else if (std.mem.eql(u8, key, "SwapTotal")) {
            swapTotal = bytes;
        } else if (std.mem.eql(u8, key, "SwapFree")) {
            swapFree = bytes;
        }
    }

    var out_buf: [512]u8 = undefined;
    const json = std.fmt.bufPrint(&out_buf, "{{\"total\":{d},\"free\":{d},\"available\":{d},\"buffers\":{d},\"cached\":{d},\"swapTotal\":{d},\"swapFree\":{d}}}", .{ total, free, available, buffers, cached, swapTotal, swapFree }) catch return 0;

    const owned = std.heap.page_allocator.dupe(u8, json) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_network_interfaces() u64 {
    var ifap: ?*struct_ifaddrs = null;
    if (getifaddrs(&ifap) != 0) return 0;
    defer {
        if (ifap) |ptr| freeifaddrs(ptr);
    }

    var list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer list.deinit();
    list.append('[') catch return 0;

    var first = true;
    var current = ifap;
    while (current) |ifa| : (current = ifa.ifa_next) {
        const addr_ptr = ifa.ifa_addr orelse continue;
        const family = addr_ptr.sa_family;
        if (family != 2 and family != 10) continue;

        const name = std.mem.sliceTo(ifa.ifa_name, 0);

        var ip_buf: [46]u8 = undefined;
        const family_str = if (family == 2) "IPv4" else "IPv6";
        const af: c_int = if (family == 2) 2 else 10;

        const ip_src = if (family == 2)
            @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                sa_family: u16,
                sin_port: u16,
                sin_addr: [4]u8,
            }, @ptrCast(addr_ptr)).sin_addr))
        else
            @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                sa_family: u16,
                sin6_port: u16,
                sin6_flowinfo: u32,
                sin6_addr: [16]u8,
                sin6_scope_id: u32,
            }, @ptrCast(addr_ptr)).sin6_addr));

        const ip_z = inet_ntop(af, ip_src, &ip_buf, ip_buf.len) orelse continue;
        const ip_str = std.mem.sliceTo(ip_z, 0);

        var mask_buf: [46]u8 = undefined;
        var cidr: u32 = 0;
        var mask_str: []const u8 = "000.000.000.000";
        if (ifa.ifa_netmask) |mask_ptr| {
            const mask_src = if (family == 2)
                @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                    sa_family: u16,
                    sin_port: u16,
                    sin_addr: [4]u8,
                }, @ptrCast(mask_ptr)).sin_addr))
            else
                @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                    sa_family: u16,
                    sin6_port: u16,
                    sin6_flowinfo: u32,
                    sin6_addr: [16]u8,
                    sin6_scope_id: u32,
                }, @ptrCast(mask_ptr)).sin6_addr));
            if (inet_ntop(af, mask_src, &mask_buf, mask_buf.len)) |mask_z| {
                mask_str = std.mem.sliceTo(mask_z, 0);
            }

            if (family == 2) {
                const sin_addr = @as(*align(1) const extern struct {
                    sa_family: u16,
                    sin_port: u16,
                    sin_addr: [4]u8,
                }, @ptrCast(mask_ptr)).sin_addr;
                const mask_val = @as(u32, @bitCast(sin_addr));
                cidr = @popCount(mask_val);
            } else {
                const sin6_addr = @as(*align(1) const extern struct {
                    sa_family: u16,
                    sin6_port: u16,
                    sin6_flowinfo: u32,
                    sin6_addr: [16]u8,
                    sin6_scope_id: u32,
                }, @ptrCast(mask_ptr)).sin6_addr;
                for (sin6_addr) |b| {
                    cidr += @popCount(b);
                }
            }
        }

        var mac_buf: [32]u8 = undefined;
        var mac_path_buf: [128]u8 = undefined;
        const mac_path = std.fmt.bufPrint(&mac_path_buf, "/sys/class/net/{s}/address", .{name}) catch "";
        var mac_str: []const u8 = "00:00:00:00:00:00";
        if (mac_path.len != 0) {
            if (sio.openFileAbsolute(mac_path, .{})) |mac_file| {
                defer mac_file.close();
                if (mac_file.read(&mac_buf)) |mac_len| {
                    mac_str = std.mem.trim(u8, mac_buf[0..mac_len], " \t\r\n");
                } else |_| {}
            } else |_| {}
        }

        if (!first) {
            list.append(',') catch return 0;
        }
        first = false;

        var json_buf: [512]u8 = undefined;
        const entry = std.fmt.bufPrint(&json_buf, "{{\"name\":\"{s}\",\"family\":\"{s}\",\"address\":\"{s}\",\"netmask\":\"{s}\",\"scopeid\":null,\"cidr\":\"{s}/{d}\",\"mac\":\"{s}\"}}", .{ name, family_str, ip_str, mask_str, ip_str, cidr, mac_str }) catch return 0;

        list.appendSlice(entry) catch return 0;
    }

    list.append(']') catch return 0;
    const owned = list.toOwnedSlice() catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_pid() u32 {
    return @intCast(getpid());
}

pub export fn sa_deno_ppid() u32 {
    return @intCast(getppid());
}

pub export fn sa_deno_uid() u32 {
    return @intCast(getuid());
}

pub export fn sa_deno_gid() u32 {
    return @intCast(getgid());
}

pub export fn sa_deno_exec_path() u64 {
    const path = sio.selfExePathAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_deno_memory_usage() u64 {
    var file = sio.openFileAbsolute("/proc/self/statm", .{}) catch return 0;
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.read(&buf) catch return 0;
    const content = buf[0..n];
    var it = std.mem.tokenizeScalar(u8, content, ' ');
    _ = it.next() orelse return 0;
    const rss_pages_str = it.next() orelse return 0;
    const rss_pages = std.fmt.parseInt(u64, rss_pages_str, 10) catch return 0;

    const page_size: u64 = @intCast(getpagesize());
    const rss = rss_pages * page_size;

    var out_buf: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&out_buf, "{{\"rss\":{d},\"heapTotal\":{d},\"heapUsed\":{d},\"external\":0}}", .{ rss, rss, rss }) catch return 0;

    const owned = std.heap.page_allocator.dupe(u8, json) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}
