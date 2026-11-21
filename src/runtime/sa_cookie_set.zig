const std = @import("std");
const ERR_HANDLE = @import("sa_cookie.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_cookie.zig").ERR_INVALID;
const ERR_NOMEM = @import("sa_cookie.zig").ERR_NOMEM;
const OK = @import("sa_cookie.zig").OK;
const SAMESITE_NONE = @import("sa_cookie.zig").SAMESITE_NONE;
const alloc = @import("sa_cookie.zig").alloc;
const constSlice = @import("sa_cookie.zig").constSlice;
const getCookie = @import("sa_cookie.zig").getCookie;
const isCtl = @import("sa_cookie.zig").isCtl;
const lowerDup = @import("sa_cookie.zig").lowerDup;
const validDomainAttr = @import("sa_cookie.zig").validDomainAttr;

pub export fn sa_cookie_set_domain(handle: u64, bytes: ?[*]const u8, len: u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    const raw = constSlice(bytes, len) orelse return ERR_INVALID;
    var d = raw;
    if (d.len > 0 and d[0] == '.') d = d[1..];
    if (!validDomainAttr(d)) return ERR_INVALID;
    const lowered = lowerDup(d) catch return ERR_NOMEM;
    if (c.domain.len > 0) alloc.free(c.domain);
    c.domain = lowered;
    c.has_domain = true;
    c.host_only = false;
    return OK;
}

pub export fn sa_cookie_set_path(handle: u64, bytes: ?[*]const u8, len: u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    const raw = constSlice(bytes, len) orelse return ERR_INVALID;
    if (raw.len == 0 or raw[0] != '/') return ERR_INVALID;
    for (raw) |ch| {
        if (isCtl(ch)) return ERR_INVALID;
    }
    const duped = alloc.dupe(u8, raw) catch return ERR_NOMEM;
    if (c.path.len > 0) alloc.free(c.path);
    c.path = duped;
    c.has_path = true;
    return OK;
}

pub export fn sa_cookie_set_expires(handle: u64, unix: i64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    c.expires_at = unix;
    return OK;
}

pub export fn sa_cookie_set_max_age(handle: u64, secs: i64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    c.max_age = secs;
    return OK;
}

pub export fn sa_cookie_set_secure(handle: u64, on: i32) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    c.secure = on != 0;
    return OK;
}

pub export fn sa_cookie_set_http_only(handle: u64, on: i32) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    c.http_only = on != 0;
    return OK;
}

pub export fn sa_cookie_set_partitioned(handle: u64, on: i32) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    c.partitioned = on != 0;
    return OK;
}

pub export fn sa_cookie_set_same_site(handle: u64, mode: u32) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    if (mode > SAMESITE_NONE) return ERR_INVALID;
    c.same_site = mode;
    return OK;
}
