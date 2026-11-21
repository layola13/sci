const std = @import("std");
const Cookie = @import("sa_cookie.zig").Cookie;
const ERR_INVALID = @import("sa_cookie.zig").ERR_INVALID;
const ERR_NOMEM = @import("sa_cookie.zig").ERR_NOMEM;
const OK = @import("sa_cookie.zig").OK;
const ParseError = @import("sa_cookie.zig").ParseError;
const alloc = @import("sa_cookie.zig").alloc;
const clearLastError = @import("sa_cookie.zig").clearLastError;
const constSlice = @import("sa_cookie.zig").constSlice;
const makeCookie = @import("sa_cookie.zig").makeCookie;
const registerCookie = @import("sa_cookie.zig").registerCookie;
const setLastError = @import("sa_cookie.zig").setLastError;
const trimOws = @import("sa_cookie.zig").trimOws;
const validCookieName = @import("sa_cookie.zig").validCookieName;
const validCookieValue = @import("sa_cookie.zig").validCookieValue;

pub fn parseHeaderPair(segment: []const u8) ParseError!*Cookie {
    const eq = std.mem.indexOfScalar(u8, segment, '=') orelse return error.InvalidCookie;
    const name = trimOws(segment[0..eq]);
    if (!validCookieName(name)) return error.InvalidCookie;
    var value = trimOws(segment[eq + 1 ..]);
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        value = value[1 .. value.len - 1];
    }
    if (!validCookieValue(value)) return error.InvalidCookie;
    return makeCookie(name, value);
}

pub export fn sa_cookie_header_pair_count(bytes: ?[*]const u8, len: u64, out_count: ?*u64) i32 {
    const slot = out_count orelse return ERR_INVALID;
    slot.* = 0;
    const raw = constSlice(bytes, len) orelse return ERR_INVALID;
    var count: u64 = 0;
    var it = std.mem.splitScalar(u8, raw, ';');
    while (it.next()) |segment| {
        const seg = trimOws(segment);
        if (seg.len == 0) continue;
        const cookie = parseHeaderPair(seg) catch |err| {
            return if (err == error.OutOfMemory) ERR_NOMEM else ERR_INVALID;
        };
        cookie.deinit();
        alloc.destroy(cookie);
        count += 1;
    }
    slot.* = count;
    return OK;
}

pub export fn sa_cookie_header_pair_at(bytes: ?[*]const u8, len: u64, index: u64) u64 {
    clearLastError();
    const raw = constSlice(bytes, len) orelse return 0;
    var idx: u64 = 0;
    var it = std.mem.splitScalar(u8, raw, ';');
    while (it.next()) |segment| {
        const seg = trimOws(segment);
        if (seg.len == 0) continue;
        if (idx == index) {
            const cookie = parseHeaderPair(seg) catch |err| {
                if (err == error.OutOfMemory) {
                    setLastError("cookie: out of memory", .{});
                } else {
                    setLastError("cookie: invalid Cookie header pair", .{});
                }
                return 0;
            };
            return registerCookie(cookie) catch {
                cookie.deinit();
                alloc.destroy(cookie);
                return 0;
            };
        }
        idx += 1;
    }
    return 0;
}
