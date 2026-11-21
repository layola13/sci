const std = @import("std");
const Cookie = @import("sa_cookie.zig").Cookie;
const ERR_HANDLE = @import("sa_cookie.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_cookie.zig").ERR_INVALID;
const ERR_IO = @import("sa_cookie.zig").ERR_IO;
const ERR_NOT_FOUND = @import("sa_cookie.zig").ERR_NOT_FOUND;
const OK = @import("sa_cookie.zig").OK;
const POLICY_ACCEPT_ALL = @import("sa_cookie.zig").POLICY_ACCEPT_ALL;
const POLICY_ACCEPT_NONE = @import("sa_cookie.zig").POLICY_ACCEPT_NONE;
const POLICY_HOST_ONLY = @import("sa_cookie.zig").POLICY_HOST_ONLY;
const SAMESITE_LAX = @import("sa_cookie.zig").SAMESITE_LAX;
const SAMESITE_STRICT = @import("sa_cookie.zig").SAMESITE_STRICT;
const STORE_DELETED = @import("sa_cookie.zig").STORE_DELETED;
const STORE_IGNORED_EXPIRED = @import("sa_cookie.zig").STORE_IGNORED_EXPIRED;
const STORE_REJECTED = @import("sa_cookie.zig").STORE_REJECTED;
const STORE_REPLACED = @import("sa_cookie.zig").STORE_REPLACED;
const STORE_STORED = @import("sa_cookie.zig").STORE_STORED;
const alloc = @import("sa_cookie.zig").alloc;
const daysFromCivil = @import("sa_cookie.zig").daysFromCivil;
const defaultPath = @import("sa_cookie.zig").defaultPath;
const domainMatch = @import("sa_cookie.zig").domainMatch;
const formatImfFixdate = @import("sa_cookie.zig").formatImfFixdate;
const parseCookieDate = @import("sa_cookie.zig").parseCookieDate;
const pathMatch = @import("sa_cookie.zig").pathMatch;
const sa_cookie_domain = @import("sa_cookie.zig").sa_cookie_domain;
const sa_cookie_expires = @import("sa_cookie.zig").sa_cookie_expires;
const sa_cookie_flags = @import("sa_cookie.zig").sa_cookie_flags;
const sa_cookie_free = @import("sa_cookie.zig").sa_cookie_free;
const sa_cookie_header_pair_at = @import("sa_cookie.zig").sa_cookie_header_pair_at;
const sa_cookie_header_pair_count = @import("sa_cookie.zig").sa_cookie_header_pair_count;
const sa_cookie_is_expired = @import("sa_cookie.zig").sa_cookie_is_expired;
const sa_cookie_jar_at = @import("sa_cookie.zig").sa_cookie_jar_at;
const sa_cookie_jar_clear = @import("sa_cookie.zig").sa_cookie_jar_clear;
const sa_cookie_jar_count = @import("sa_cookie.zig").sa_cookie_jar_count;
const sa_cookie_jar_evict_expired = @import("sa_cookie.zig").sa_cookie_jar_evict_expired;
const sa_cookie_jar_free = @import("sa_cookie.zig").sa_cookie_jar_free;
const sa_cookie_jar_header = @import("sa_cookie.zig").sa_cookie_jar_header;
const sa_cookie_jar_load = @import("sa_cookie.zig").sa_cookie_jar_load;
const sa_cookie_jar_new = @import("sa_cookie.zig").sa_cookie_jar_new;
const sa_cookie_jar_policy = @import("sa_cookie.zig").sa_cookie_jar_policy;
const sa_cookie_jar_request_header = @import("sa_cookie.zig").sa_cookie_jar_request_header;
const sa_cookie_jar_save = @import("sa_cookie.zig").sa_cookie_jar_save;
const sa_cookie_jar_set_policy = @import("sa_cookie.zig").sa_cookie_jar_set_policy;
const sa_cookie_jar_store = @import("sa_cookie.zig").sa_cookie_jar_store;
const sa_cookie_jar_store_response = @import("sa_cookie.zig").sa_cookie_jar_store_response;
const sa_cookie_last_error = @import("sa_cookie.zig").sa_cookie_last_error;
const sa_cookie_max_age = @import("sa_cookie.zig").sa_cookie_max_age;
const sa_cookie_name = @import("sa_cookie.zig").sa_cookie_name;
const sa_cookie_new = @import("sa_cookie.zig").sa_cookie_new;
const sa_cookie_parse_set_cookie = @import("sa_cookie.zig").sa_cookie_parse_set_cookie;
const sa_cookie_path = @import("sa_cookie.zig").sa_cookie_path;
const sa_cookie_same_site = @import("sa_cookie.zig").sa_cookie_same_site;
const sa_cookie_serialize = @import("sa_cookie.zig").sa_cookie_serialize;
const sa_cookie_serialize_pair = @import("sa_cookie.zig").sa_cookie_serialize_pair;
const sa_cookie_set_domain = @import("sa_cookie.zig").sa_cookie_set_domain;
const sa_cookie_set_path = @import("sa_cookie.zig").sa_cookie_set_path;
const sa_cookie_set_same_site = @import("sa_cookie.zig").sa_cookie_set_same_site;
const sa_cookie_set_secure = @import("sa_cookie.zig").sa_cookie_set_secure;
const sa_cookie_value = @import("sa_cookie.zig").sa_cookie_value;
const sio = @import("sa_cookie.zig").sio;

test "cookie date: RFC formats parse to the same instant" {
    // The RFC 6265 / RFC 7231 example instant in all three
    // historical HTTP date formats.
    try std.testing.expectEqual(@as(?i64, 784111777), parseCookieDate("Sun, 06 Nov 1994 08:49:37 GMT"));
    try std.testing.expectEqual(@as(?i64, 784111777), parseCookieDate("Sunday, 06-Nov-94 08:49:37 GMT"));
    try std.testing.expectEqual(@as(?i64, 784111777), parseCookieDate("Sun Nov  6 08:49:37 1994"));
    // The MDN Set-Cookie example date.
    try std.testing.expectEqual(@as(?i64, 1445412480), parseCookieDate("Wed, 21 Oct 2015 07:28:00 GMT"));
}

test "cookie date: two-digit years pivot at 70" {
    const y69 = parseCookieDate("Wed, 06 Nov 69 08:49:37 GMT") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(daysFromCivil(2069, 11, 6) * 86400 + 8 * 3600 + 49 * 60 + 37, y69);
    const y70 = parseCookieDate("Sat, 06 Nov 70 08:49:37 GMT") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(daysFromCivil(1970, 11, 6) * 86400 + 8 * 3600 + 49 * 60 + 37, y70);
}

test "cookie date: invalid dates are rejected" {
    try std.testing.expectEqual(@as(?i64, null), parseCookieDate("Sun, 32 Nov 1994 08:49:37 GMT"));
    try std.testing.expectEqual(@as(?i64, null), parseCookieDate("Sun, 06 Nov 1994 24:49:37 GMT"));
    try std.testing.expectEqual(@as(?i64, null), parseCookieDate("Sun, 06 Foo 1994 08:49:37 GMT"));
    try std.testing.expectEqual(@as(?i64, null), parseCookieDate("Sun, 06 Nov 1600 08:49:37 GMT"));
    try std.testing.expectEqual(@as(?i64, null), parseCookieDate("not a date"));
    try std.testing.expectEqual(@as(?i64, null), parseCookieDate(""));
}

test "cookie date: IMF-fixdate formatting" {
    var buf: [40]u8 = undefined;
    try std.testing.expectEqualStrings("Sun, 06 Nov 1994 08:49:37 GMT", formatImfFixdate(784111777, &buf));
    try std.testing.expectEqualStrings("Thu, 01 Jan 1970 00:00:00 GMT", formatImfFixdate(0, &buf));
    try std.testing.expectEqualStrings("Wed, 21 Oct 2015 07:28:00 GMT", formatImfFixdate(1445412480, &buf));
}

test "cookie match: domain rules" {
    try std.testing.expect(domainMatch("example.com", "example.com"));
    try std.testing.expect(domainMatch("example.com", "www.example.com"));
    try std.testing.expect(domainMatch("EXAMPLE.com", "WWW.example.COM"));
    try std.testing.expect(!domainMatch("example.com", "badexample.com"));
    try std.testing.expect(!domainMatch("example.com", "example.com.evil.com"));
    try std.testing.expect(!domainMatch("ample.com", "example.com"));
    try std.testing.expect(domainMatch("127.0.0.1", "127.0.0.1"));
    try std.testing.expect(!domainMatch("0.0.1", "127.0.0.1"));
}

test "cookie match: path rules and default path" {
    try std.testing.expect(pathMatch("/foo", "/foo"));
    try std.testing.expect(pathMatch("/foo", "/foo/bar"));
    try std.testing.expect(!pathMatch("/foo", "/foobar"));
    try std.testing.expect(pathMatch("/foo/", "/foo/bar"));
    try std.testing.expect(pathMatch("/", "/anything"));
    try std.testing.expect(!pathMatch("/foo", "/"));
    try std.testing.expectEqualStrings("/foo/bar", defaultPath("/foo/bar/baz"));
    try std.testing.expectEqualStrings("/foo", defaultPath("/foo/"));
    try std.testing.expectEqualStrings("/", defaultPath("/foo"));
    try std.testing.expectEqualStrings("/", defaultPath(""));
    try std.testing.expectEqualStrings("/", defaultPath("relative"));
}

test "cookie value: full Set-Cookie parse and serialize round trip" {
    const raw: []const u8 = "SID=31d4d96e407aad42; Domain=example.com; Path=/; Expires=Sun, 06 Nov 1994 08:49:37 GMT; Max-Age=3600; Secure; HttpOnly; SameSite=Lax; Partitioned";
    const h = sa_cookie_parse_set_cookie(raw.ptr, raw.len);
    try std.testing.expect(h != 0);
    defer _ = sa_cookie_free(h);
    var op: ?[*]const u8 = null;
    var ol: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_name(h, &op, &ol));
    try expectOut("SID", op, ol);
    try std.testing.expectEqual(OK, sa_cookie_value(h, &op, &ol));
    try expectOut("31d4d96e407aad42", op, ol);
    try std.testing.expectEqual(OK, sa_cookie_domain(h, &op, &ol));
    try expectOut("example.com", op, ol);
    try std.testing.expectEqual(OK, sa_cookie_path(h, &op, &ol));
    try expectOut("/", op, ol);
    var ts: i64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_expires(h, &ts));
    try std.testing.expectEqual(@as(i64, 784111777), ts);
    var ma: i64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_max_age(h, &ma));
    try std.testing.expectEqual(@as(i64, 3600), ma);
    var s: i32 = 0;
    var ho: i32 = 0;
    var pa: i32 = 0;
    try std.testing.expectEqual(OK, sa_cookie_flags(h, &s, &ho, &pa));
    try std.testing.expectEqual(@as(i32, 1), s);
    try std.testing.expectEqual(@as(i32, 1), ho);
    try std.testing.expectEqual(@as(i32, 1), pa);
    var mode: u32 = 0;
    try std.testing.expectEqual(OK, sa_cookie_same_site(h, &mode));
    try std.testing.expectEqual(SAMESITE_LAX, mode);

    try std.testing.expectEqual(OK, sa_cookie_serialize(h, &op, &ol));
    try expectOut("SID=31d4d96e407aad42; Domain=example.com; Path=/; Expires=Sun, 06 Nov 1994 08:49:37 GMT; Max-Age=3600; Secure; HttpOnly; SameSite=Lax; Partitioned", op, ol);
    try std.testing.expectEqual(OK, sa_cookie_serialize_pair(h, &op, &ol));
    try expectOut("SID=31d4d96e407aad42", op, ol);

    var expired: i32 = 0;
    try std.testing.expectEqual(OK, sa_cookie_is_expired(h, 784111776, &expired));
    try std.testing.expectEqual(@as(i32, 0), expired);
    try std.testing.expectEqual(OK, sa_cookie_is_expired(h, 784111777, &expired));
    try std.testing.expectEqual(@as(i32, 1), expired);
}

test "cookie value: strict rejection of malformed pairs" {
    const bad = [_][]const u8{
        "",
        "noequalsign",
        "=value",
        "na me=value",
        "a=va lue",
        "a=va,lue",
        "a(b)=1",
        "a=\"unterminated",
    };
    for (bad) |raw| {
        try std.testing.expectEqual(@as(u64, 0), sa_cookie_parse_set_cookie(raw.ptr, raw.len));
    }
    var op: ?[*]const u8 = null;
    var ol: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_last_error(&op, &ol));
    try std.testing.expect(ol > 0);
}

test "cookie value: quoted value unwraps, unknown attributes ignored" {
    const raw = "pref=\"dark-mode\"; Comment=hello; Version=1; X-Custom=yes";
    const h = sa_cookie_parse_set_cookie(raw.ptr, raw.len);
    try std.testing.expect(h != 0);
    defer _ = sa_cookie_free(h);
    var op: ?[*]const u8 = null;
    var ol: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_value(h, &op, &ol));
    try expectOut("dark-mode", op, ol);
    // No Domain attribute anywhere: accessor reports NOT_FOUND.
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_cookie_domain(h, &op, &ol));
    var dummy: i64 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_cookie_expires(h, &dummy));
}

test "cookie value: build with setters and serialize" {
    const h = sa_cookie_new("theme".ptr, 5, "dark".ptr, 4);
    try std.testing.expect(h != 0);
    defer _ = sa_cookie_free(h);
    try std.testing.expectEqual(OK, sa_cookie_set_domain(h, "Example.COM".ptr, 11));
    try std.testing.expectEqual(OK, sa_cookie_set_path(h, "/app".ptr, 4));
    try std.testing.expectEqual(OK, sa_cookie_set_secure(h, 1));
    try std.testing.expectEqual(OK, sa_cookie_set_same_site(h, SAMESITE_STRICT));
    try std.testing.expectEqual(ERR_INVALID, sa_cookie_set_path(h, "app".ptr, 3));
    try std.testing.expectEqual(ERR_INVALID, sa_cookie_set_same_site(h, 9));
    var op: ?[*]const u8 = null;
    var ol: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_domain(h, &op, &ol));
    try expectOut("example.com", op, ol);
    try std.testing.expectEqual(OK, sa_cookie_serialize(h, &op, &ol));
    try expectOut("theme=dark; Domain=example.com; Path=/app; Secure; SameSite=Strict", op, ol);
    try std.testing.expectEqual(ERR_HANDLE, sa_cookie_name(999999, &op, &ol));
    try std.testing.expectEqual(ERR_HANDLE, sa_cookie_free(999999));
}

test "cookie value: request header pairs" {
    const raw = "a=1; b=2; $Version=1; c=";
    var count: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_header_pair_count(raw.ptr, raw.len, &count));
    try std.testing.expectEqual(@as(u64, 4), count);
    const h = sa_cookie_header_pair_at(raw.ptr, raw.len, 1);
    try std.testing.expect(h != 0);
    defer _ = sa_cookie_free(h);
    var op: ?[*]const u8 = null;
    var ol: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_name(h, &op, &ol));
    try expectOut("b", op, ol);
    try std.testing.expectEqual(OK, sa_cookie_value(h, &op, &ol));
    try expectOut("2", op, ol);
    try std.testing.expectEqual(@as(u64, 0), sa_cookie_header_pair_at(raw.ptr, raw.len, 9));
    const bad = "a=1; broken";
    try std.testing.expectEqual(ERR_INVALID, sa_cookie_header_pair_count(bad.ptr, bad.len, &count));
    try std.testing.expectEqual(OK, sa_cookie_header_pair_count("".ptr, 0, &count));
    try std.testing.expectEqual(@as(u64, 0), count);
}

test "cookie jar: domain and host-only rules" {
    const jar = sa_cookie_jar_new();
    try std.testing.expect(jar != 0);
    defer _ = sa_cookie_jar_free(jar);
    try std.testing.expectEqual(STORE_STORED, try jarStore(jar, "http://sub.example.com/", "wide=1; Domain=example.com", 1000));
    try jarHeaderEq(jar, "http://example.com/", 1000, "wide=1");
    try jarHeaderEq(jar, "http://other.example.com/", 1000, "wide=1");
    try std.testing.expectEqual(STORE_STORED, try jarStore(jar, "http://sub.example.com/", "narrow=1", 1000));
    try jarHeaderEq(jar, "http://example.com/", 1000, "wide=1");
    try jarHeaderEq(jar, "http://sub.example.com/", 1000, "wide=1; narrow=1");
    try std.testing.expectEqual(STORE_REJECTED, try jarStore(jar, "http://example.com/", "bad=1; Domain=other.com", 1000));
    try std.testing.expectEqual(STORE_REJECTED, try jarStore(jar, "http://127.0.0.1/", "ip=1; Domain=0.0.1", 1000));
    try std.testing.expectEqual(@as(u64, 2), try jarCount(jar));
    // Enumeration is in creation order.
    const first = sa_cookie_jar_at(jar, 0);
    try std.testing.expect(first != 0);
    defer _ = sa_cookie_free(first);
    var op: ?[*]const u8 = null;
    var ol: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_name(first, &op, &ol));
    try expectOut("wide", op, ol);
    try std.testing.expectEqual(@as(u64, 0), sa_cookie_jar_at(jar, 7));
}

test "cookie jar: secure cookies and trustworthy origins" {
    const jar = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(jar);
    try std.testing.expectEqual(STORE_REJECTED, try jarStore(jar, "http://example.com/", "s=1; Secure", 1000));
    try std.testing.expectEqual(STORE_STORED, try jarStore(jar, "https://example.com/", "s=1; Secure", 1000));
    try jarHeaderEq(jar, "http://example.com/", 1000, null);
    try jarHeaderEq(jar, "https://example.com/", 1000, "s=1");
    try std.testing.expectEqual(STORE_STORED, try jarStore(jar, "http://localhost:8080/", "l=1; Secure", 1000));
    try jarHeaderEq(jar, "http://localhost/", 1000, "l=1");
}

test "cookie jar: path scoping and send ordering" {
    const jar = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(jar);
    _ = try jarStore(jar, "http://example.com/foo/bar", "deep=1", 1000);
    _ = try jarStore(jar, "http://example.com/", "root=1; Path=/", 1000);
    _ = try jarStore(jar, "http://example.com/foo/", "mid=1; Path=/foo", 1000);
    // Longer paths first; ties keep creation order (deep before mid).
    try jarHeaderEq(jar, "http://example.com/foo/bar", 1000, "deep=1; mid=1; root=1");
    try jarHeaderEq(jar, "http://example.com/foo", 1000, "deep=1; mid=1; root=1");
    try jarHeaderEq(jar, "http://example.com/foobar", 1000, "root=1");
    try jarHeaderEq(jar, "http://example.com/", 1000, "root=1");
}

test "cookie jar: expiry, precedence, deletion, replacement" {
    const jar = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(jar);
    _ = try jarStore(jar, "https://example.com/", "temp=1; Max-Age=10", 1000);
    try jarHeaderEq(jar, "https://example.com/", 1009, "temp=1");
    try jarHeaderEq(jar, "https://example.com/", 1010, null);
    _ = try jarStore(jar, "https://example.com/", "gone=1", 1000);
    try std.testing.expectEqual(STORE_DELETED, try jarStore(jar, "https://example.com/", "gone=; Max-Age=0", 1000));
    try jarHeaderEq(jar, "https://example.com/", 1000, null);
    // Expired on arrival: ignored when nothing exists.
    try std.testing.expectEqual(STORE_IGNORED_EXPIRED, try jarStore(jar, "https://example.com/", "ghost=1; Expires=Sun, 06 Nov 1994 08:49:37 GMT", 800_000_000));
    // Max-Age overrides a past Expires.
    try std.testing.expectEqual(STORE_STORED, try jarStore(jar, "https://example.com/", "mix=1; Expires=Sun, 06 Nov 1994 08:49:37 GMT; Max-Age=3600", 800_000_000));
    try jarHeaderEq(jar, "https://example.com/", 800_000_100, "mix=1");
    var mix_removed: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_jar_evict_expired(jar, 800_004_000, &mix_removed));
    try std.testing.expectEqual(@as(u64, 1), mix_removed);
    // Replacement keeps one entry and the original send position.
    _ = try jarStore(jar, "https://example.com/", "a=1; Path=/", 2000);
    _ = try jarStore(jar, "https://example.com/", "b=1; Path=/", 2000);
    try std.testing.expectEqual(STORE_REPLACED, try jarStore(jar, "https://example.com/", "a=2; Path=/", 2000));
    try jarHeaderEq(jar, "https://example.com/", 2000, "a=2; b=1");
    // Explicit eviction reports the count.
    _ = try jarStore(jar, "https://example.com/", "e=1; Max-Age=5", 2000);
    var removed: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_jar_evict_expired(jar, 2006, &removed));
    try std.testing.expectEqual(@as(u64, 1), removed);
    try std.testing.expectEqual(OK, sa_cookie_jar_clear(jar));
    try std.testing.expectEqual(@as(u64, 0), try jarCount(jar));
}

test "cookie jar: acceptance policies" {
    const none_jar = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(none_jar);
    try std.testing.expectEqual(OK, sa_cookie_jar_set_policy(none_jar, POLICY_ACCEPT_NONE));
    try std.testing.expectEqual(STORE_REJECTED, try jarStore(none_jar, "http://example.com/", "x=1", 1000));
    try std.testing.expectEqual(@as(u64, 0), try jarCount(none_jar));

    const host_jar = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(host_jar);
    try std.testing.expectEqual(OK, sa_cookie_jar_set_policy(host_jar, POLICY_HOST_ONLY));
    var pol: u32 = 0;
    try std.testing.expectEqual(OK, sa_cookie_jar_policy(host_jar, &pol));
    try std.testing.expectEqual(POLICY_HOST_ONLY, pol);
    try std.testing.expectEqual(ERR_INVALID, sa_cookie_jar_set_policy(host_jar, 9));
    _ = try jarStore(host_jar, "http://sub.example.com/", "w=1; Domain=example.com", 1000);
    try jarHeaderEq(host_jar, "http://example.com/", 1000, null);
    try jarHeaderEq(host_jar, "http://sub.example.com/", 1000, "w=1");
    try std.testing.expectEqual(ERR_HANDLE, sa_cookie_jar_set_policy(999999, POLICY_ACCEPT_ALL));
}

test "cookie jar: netscape persistence round trip" {
    const path = "sa_cookie_test_netscape.txt";
    const path2 = "sa_cookie_test_netscape2.txt";
    std.Io.Dir.cwd().deleteFile(sio.io(), path) catch {};
    std.Io.Dir.cwd().deleteFile(sio.io(), path2) catch {};
    defer std.Io.Dir.cwd().deleteFile(sio.io(), path) catch {};
    defer std.Io.Dir.cwd().deleteFile(sio.io(), path2) catch {};

    const jar = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(jar);
    _ = try jarStore(jar, "http://example.com/", "sid=abc; Domain=example.com; Path=/; Expires=Sun, 06 Nov 1994 08:49:37 GMT; HttpOnly", 1000);
    _ = try jarStore(jar, "http://sub.example.com/", "host1=v1", 1000);
    _ = try jarStore(jar, "https://example.com/foo/bar", "sec=s3cr3t; Secure; Max-Age=100000", 1000);
    _ = try jarStore(jar, "http://example.com/", "plain=p; Domain=example.com", 1000);
    try std.testing.expectEqual(OK, sa_cookie_jar_save(jar, path.ptr, path.len));

    const expected = "# Netscape HTTP Cookie File\n# Written by sa_std (sa_cookie_jar_save). HttpOnly cookies carry the #HttpOnly_ prefix.\n\n" ++
        "#HttpOnly_.example.com\tTRUE\t/\tFALSE\t784111777\tsid\tabc\n" ++
        "sub.example.com\tFALSE\t/\tFALSE\t0\thost1\tv1\n" ++
        "example.com\tFALSE\t/foo\tTRUE\t101000\tsec\ts3cr3t\n" ++
        ".example.com\tTRUE\t/\tFALSE\t0\tplain\tp\n";
    const saved = try std.Io.Dir.cwd().readFileAlloc(sio.io(), path, alloc, .limited(1 << 20));
    defer alloc.free(saved);
    try std.testing.expectEqualStrings(expected, saved);

    const jar2 = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(jar2);
    var loaded: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_jar_load(jar2, path.ptr, path.len, &loaded));
    try std.testing.expectEqual(@as(u64, 4), loaded);
    try std.testing.expectEqual(@as(u64, 4), try jarCount(jar2));
    try jarHeaderEq(jar2, "https://example.com/foo/x", 2000, "sec=s3cr3t; sid=abc; plain=p");
    try jarHeaderEq(jar2, "http://sub.example.com/", 2000, "sid=abc; host1=v1; plain=p");
    try std.testing.expectEqual(OK, sa_cookie_jar_save(jar2, path2.ptr, path2.len));
    const saved2 = try std.Io.Dir.cwd().readFileAlloc(sio.io(), path2, alloc, .limited(1 << 20));
    defer alloc.free(saved2);
    try std.testing.expectEqualStrings(saved, saved2);

    // A malformed data line fails the whole load atomically.
    const bad_path = "sa_cookie_test_netscape_bad.txt";
    defer std.Io.Dir.cwd().deleteFile(sio.io(), bad_path) catch {};
    {
        var f = try std.Io.Dir.cwd().createFile(sio.io(), bad_path, .{ .truncate = true });
        defer f.close(sio.io());
        var wbuf: [1024]u8 = undefined;
        var w = f.writerStreaming(sio.io(), &wbuf);
        try w.interface.writeAll("example.com\tTRUE\t/\tFALSE\t0\tok\t1\nbroken\tline\n");
        try w.interface.flush();
    }
    const jar3 = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(jar3);
    try std.testing.expectEqual(ERR_INVALID, sa_cookie_jar_load(jar3, bad_path.ptr, bad_path.len, &loaded));
    try std.testing.expectEqual(@as(u64, 0), try jarCount(jar3));
    const missing: []const u8 = "sa_cookie_test_missing.txt";
    try std.testing.expectEqual(ERR_IO, sa_cookie_jar_load(jar3, missing.ptr, missing.len, &loaded));
}

test "cookie hooks: response store and request header use the clock" {
    const jar = sa_cookie_jar_new();
    defer _ = sa_cookie_jar_free(jar);
    const url: []const u8 = "https://example.com/";
    const sc: []const u8 = "live=1; Max-Age=100000";
    try std.testing.expectEqual(OK, sa_cookie_jar_store_response(jar, url.ptr, url.len, sc.ptr, sc.len));
    var op: ?[*]const u8 = null;
    var ol: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_jar_request_header(jar, url.ptr, url.len, &op, &ol));
    try expectOut("live=1", op, ol);
    const other: []const u8 = "https://other.example/";
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_cookie_jar_request_header(jar, other.ptr, other.len, &op, &ol));
}

pub fn expectOut(expected: []const u8, ptr_slot: ?[*]const u8, len: u64) !void {
    try std.testing.expectEqual(expected.len, @as(usize, @intCast(len)));
    if (len > 0) try std.testing.expectEqualStrings(expected, ptr_slot.?[0..@intCast(len)]);
}

pub fn jarStore(jar: u64, url: []const u8, sc: []const u8, now: i64) !u32 {
    var result: u32 = 999;
    try std.testing.expectEqual(OK, sa_cookie_jar_store(jar, url.ptr, url.len, sc.ptr, sc.len, now, &result));
    return result;
}

pub fn jarHeaderEq(jar: u64, url: []const u8, now: i64, expected: ?[]const u8) !void {
    var op: ?[*]const u8 = null;
    var ol: u64 = 0;
    const st = sa_cookie_jar_header(jar, url.ptr, url.len, now, &op, &ol);
    if (expected) |exp| {
        try std.testing.expectEqual(OK, st);
        try expectOut(exp, op, ol);
    } else {
        try std.testing.expectEqual(ERR_NOT_FOUND, st);
        try std.testing.expectEqual(@as(u64, 0), ol);
    }
}

pub fn jarCount(jar: u64) !u64 {
    var count: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_jar_count(jar, &count));
    return count;
}
