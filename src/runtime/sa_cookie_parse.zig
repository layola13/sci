const std = @import("std");
const Cookie = @import("sa_cookie.zig").Cookie;
const SAMESITE_LAX = @import("sa_cookie.zig").SAMESITE_LAX;
const SAMESITE_NONE = @import("sa_cookie.zig").SAMESITE_NONE;
const SAMESITE_STRICT = @import("sa_cookie.zig").SAMESITE_STRICT;
const alloc = @import("sa_cookie.zig").alloc;
const eqFold = @import("sa_cookie.zig").eqFold;
const formatImfFixdate = @import("sa_cookie.zig").formatImfFixdate;
const isCtl = @import("sa_cookie.zig").isCtl;
const lowerDup = @import("sa_cookie.zig").lowerDup;
const makeCookie = @import("sa_cookie.zig").makeCookie;
const parseCookieDate = @import("sa_cookie.zig").parseCookieDate;
const trimOws = @import("sa_cookie.zig").trimOws;
const validCookieName = @import("sa_cookie.zig").validCookieName;
const validCookieValue = @import("sa_cookie.zig").validCookieValue;

pub const ParseError = error{ InvalidCookie, OutOfMemory };

pub fn parseMaxAge(s: []const u8) ?i64 {
    if (s.len == 0) return null;
    var idx: usize = 0;
    var negative = false;
    if (s[0] == '-') {
        negative = true;
        idx = 1;
    }
    if (idx >= s.len) return null;
    var value: i64 = 0;
    const cap: i64 = 1 << 62;
    while (idx < s.len) : (idx += 1) {
        const c = s[idx];
        if (!std.ascii.isDigit(c)) return null;
        const digit: i64 = c - '0';
        if (value >= (cap - 9) / 10) {
            value = cap;
        } else {
            value = value * 10 + digit;
        }
    }
    return if (negative) -value else value;
}

pub fn validDomainAttr(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        const ok = std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_';
        if (!ok) return false;
    }
    return true;
}

pub fn parseSetCookie(raw: []const u8) ParseError!*Cookie {
    const first_semi = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
    const pair = trimOws(raw[0..first_semi]);
    const eq = std.mem.indexOfScalar(u8, pair, '=') orelse return error.InvalidCookie;
    const name = trimOws(pair[0..eq]);
    if (!validCookieName(name)) return error.InvalidCookie;
    var value = trimOws(pair[eq + 1 ..]);
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        value = value[1 .. value.len - 1];
    }
    if (!validCookieValue(value)) return error.InvalidCookie;

    const cookie = try makeCookie(name, value);
    errdefer {
        cookie.deinit();
        alloc.destroy(cookie);
    }

    if (first_semi < raw.len) {
        var it = std.mem.splitScalar(u8, raw[first_semi + 1 ..], ';');
        while (it.next()) |segment| {
            const attr = trimOws(segment);
            if (attr.len == 0) continue;
            const aeq = std.mem.indexOfScalar(u8, attr, '=');
            const aname = if (aeq) |e| trimOws(attr[0..e]) else attr;
            const avalue: []const u8 = if (aeq) |e| trimOws(attr[e + 1 ..]) else "";
            if (eqFold(aname, "expires")) {
                if (parseCookieDate(avalue)) |ts| cookie.expires_at = ts;
            } else if (eqFold(aname, "max-age")) {
                if (parseMaxAge(avalue)) |ma| cookie.max_age = ma;
            } else if (eqFold(aname, "domain")) {
                var d = avalue;
                if (d.len > 0 and d[0] == '.') d = d[1..];
                if (validDomainAttr(d)) {
                    const nd = try lowerDup(d);
                    if (cookie.domain.len > 0) alloc.free(cookie.domain);
                    cookie.domain = nd;
                    cookie.has_domain = true;
                    cookie.host_only = false;
                }
            } else if (eqFold(aname, "path")) {
                if (avalue.len > 0 and avalue[0] == '/') {
                    var bad = false;
                    for (avalue) |c| {
                        if (isCtl(c)) bad = true;
                    }
                    if (!bad) {
                        const np = try alloc.dupe(u8, avalue);
                        if (cookie.path.len > 0) alloc.free(cookie.path);
                        cookie.path = np;
                        cookie.has_path = true;
                    }
                }
            } else if (eqFold(aname, "secure")) {
                cookie.secure = true;
            } else if (eqFold(aname, "httponly")) {
                cookie.http_only = true;
            } else if (eqFold(aname, "partitioned")) {
                cookie.partitioned = true;
            } else if (eqFold(aname, "samesite")) {
                if (eqFold(avalue, "lax")) {
                    cookie.same_site = SAMESITE_LAX;
                } else if (eqFold(avalue, "strict")) {
                    cookie.same_site = SAMESITE_STRICT;
                } else if (eqFold(avalue, "none")) {
                    cookie.same_site = SAMESITE_NONE;
                }
            }
            // Unknown attributes are ignored (RFC 6265 5.2).
        }
    }
    return cookie;
}

pub fn serializeInto(list: *std.array_list.Managed(u8), c: *const Cookie, pair_only: bool) !void {
    try list.appendSlice(c.name);
    try list.append('=');
    try list.appendSlice(c.value);
    if (pair_only) return;
    if (c.has_domain) {
        try list.appendSlice("; Domain=");
        try list.appendSlice(c.domain);
    }
    if (c.has_path) {
        try list.appendSlice("; Path=");
        try list.appendSlice(c.path);
    }
    if (c.expires_at) |ts| {
        var buf: [40]u8 = undefined;
        try list.appendSlice("; Expires=");
        try list.appendSlice(formatImfFixdate(ts, &buf));
    }
    if (c.max_age) |ma| {
        const s = try std.fmt.allocPrint(alloc, "; Max-Age={d}", .{ma});
        defer alloc.free(s);
        try list.appendSlice(s);
    }
    if (c.secure) try list.appendSlice("; Secure");
    if (c.http_only) try list.appendSlice("; HttpOnly");
    switch (c.same_site) {
        SAMESITE_LAX => try list.appendSlice("; SameSite=Lax"),
        SAMESITE_STRICT => try list.appendSlice("; SameSite=Strict"),
        SAMESITE_NONE => try list.appendSlice("; SameSite=None"),
        else => {},
    }
    if (c.partitioned) try list.appendSlice("; Partitioned");
}

pub fn serializeOwned(c: *const Cookie, pair_only: bool) ![]u8 {
    var list = std.array_list.Managed(u8).init(alloc);
    errdefer list.deinit();
    try serializeInto(&list, c, pair_only);
    return list.toOwnedSlice();
}
