const std = @import("std");
const endsWithFold = @import("sa_cookie.zig").endsWithFold;
const eqFold = @import("sa_cookie.zig").eqFold;
const isCtl = @import("sa_cookie.zig").isCtl;
const sio = @import("sa_cookie.zig").sio;

pub fn hostIsIp(host: []const u8) bool {
    if (host.len == 0) return false;
    if (std.mem.indexOfScalar(u8, host, ':') != null) return true; // IPv6 literal (brackets already stripped)
    var parts: usize = 0;
    var it = std.mem.splitScalar(u8, host, '.');
    while (it.next()) |part| {
        if (part.len == 0 or part.len > 3) return false;
        for (part) |c| {
            if (!std.ascii.isDigit(c)) return false;
        }
        parts += 1;
    }
    return parts == 4;
}

pub fn domainMatch(domain: []const u8, host: []const u8) bool {
    if (domain.len == 0 or host.len == 0) return false;
    if (eqFold(domain, host)) return true;
    if (hostIsIp(host)) return false;
    if (host.len <= domain.len) return false;
    if (host[host.len - domain.len - 1] != '.') return false;
    return endsWithFold(host, domain);
}

pub fn pathMatch(cookie_path: []const u8, request_path: []const u8) bool {
    if (cookie_path.len == 0) return false;
    const rp = if (request_path.len == 0) "/" else request_path;
    if (std.mem.eql(u8, cookie_path, rp)) return true;
    if (rp.len > cookie_path.len and std.mem.startsWith(u8, rp, cookie_path)) {
        if (cookie_path[cookie_path.len - 1] == '/') return true;
        if (rp[cookie_path.len] == '/') return true;
    }
    return false;
}

pub fn defaultPath(uri_path: []const u8) []const u8 {
    if (uri_path.len == 0 or uri_path[0] != '/') return "/";
    const last_slash = std.mem.lastIndexOfScalar(u8, uri_path, '/') orelse return "/";
    if (last_slash == 0) return "/";
    return uri_path[0..last_slash];
}

pub const UrlParts = struct {
    scheme: []const u8,
    host: []const u8,
    path: []const u8,
};

pub fn splitUrl(url: []const u8) ?UrlParts {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return null;
    const scheme = url[0..scheme_end];
    if (scheme.len == 0) return null;
    for (scheme) |c| {
        if (isCtl(c) or c == ' ' or c == '/') return null;
    }
    var rest = url[scheme_end + 3 ..];
    var auth_end = rest.len;
    for (rest, 0..) |c, idx| {
        if (c == '/' or c == '?' or c == '#') {
            auth_end = idx;
            break;
        }
    }
    var authority = rest[0..auth_end];
    rest = rest[auth_end..];
    if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at| {
        authority = authority[at + 1 ..];
    }
    var host: []const u8 = "";
    if (authority.len > 0 and authority[0] == '[') {
        const close = std.mem.indexOfScalar(u8, authority, ']') orelse return null;
        host = authority[1..close];
    } else if (std.mem.indexOfScalar(u8, authority, ':')) |colon| {
        host = authority[0..colon];
    } else {
        host = authority;
    }
    if (host.len == 0) return null;
    var path: []const u8 = "";
    if (rest.len > 0 and rest[0] == '/') {
        var path_end = rest.len;
        for (rest, 0..) |c, idx| {
            if (c == '?' or c == '#') {
                path_end = idx;
                break;
            }
        }
        path = rest[0..path_end];
    }
    return .{ .scheme = scheme, .host = host, .path = path };
}

pub fn originTrustworthy(scheme: []const u8, host: []const u8) bool {
    if (eqFold(scheme, "https") or eqFold(scheme, "wss")) return true;
    if (eqFold(host, "localhost") or endsWithFold(host, ".localhost")) return true;
    if (std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "::1")) return true;
    return false;
}

pub fn nowUnix() i64 {
    const ts = std.Io.Clock.real.now(sio.io());
    return @divFloor(ts.toMilliseconds(), 1000);
}
