//! sa_std HTTP cookies (RFC 6265): Set-Cookie / Cookie value layer,
//! an RFC 6265 storage-model jar, and Netscape cookie-file
//! persistence.
//!
//! Three layers, mirroring the shape the cross-language census
//! (sala tools/{java,go,python}_net_census) found missing as one
//! block:
//!   1. Value layer: parse / build / inspect a single cookie
//!      (sa_cookie_parse_set_cookie, sa_cookie_new, accessors,
//!      sa_cookie_serialize). Cookie request headers are covered by
//!      sa_cookie_header_pair_count / _at.
//!   2. Jar layer: an opaque handle holding cookies under the
//!      RFC 6265 storage model -- domain and path matching,
//!      host-only cookies, expiry with Max-Age precedence, the
//!      secure-origin rule, replacement that preserves the original
//!      creation order, and send ordering (longer path first,
//!      earlier creation first).
//!   3. Persistence: sa_cookie_jar_save / _load in the Netscape
//!      cookie file format (the Mozilla format Python's
//!      http.cookiejar and curl both read/write).
//!
//! The two http_client hooks (sa_cookie_jar_request_header,
//! sa_cookie_jar_store_response) are deliberately the ONLY client
//! integration: they are explicit calls a client makes around a
//! request. Nothing here changes the managed http_client runtime's
//! default behavior -- whether the client grows a handler model
//! that calls them automatically is a separate architecture call.
//!
//! Strictness contract (explicit rejection, no silent swallowing):
//!   - A Set-Cookie string whose name-value pair has no '=', an
//!     empty name, a name outside the RFC 7230 token set, or a
//!     value outside the RFC 6265 cookie-octet set fails the whole
//!     parse (handle 0 / SA_STD_ERR_INVALID_ARGUMENT). RFC 6265
//!     tells user agents to "ignore" such strings; at an API
//!     boundary the ignore is surfaced as an error instead.
//!   - Individual ATTRIBUTES that fail to parse (bad date,
//!     non-numeric Max-Age, unknown SameSite token, Path not
//!     starting with '/', Domain with illegal bytes) are ignored
//!     per RFC 6265 section 5.2 -- that leniency is the interop
//!     behavior every browser implements, and it is per-attribute,
//!     never whole-cookie.
//!   - Unknown attributes (including the obsolete RFC 2965
//!     Comment / Version / Port / Discard) are ignored, per RFC.
//!   - The jar REJECTS (store result SA_COOKIE_STORE_REJECTED) a
//!     cookie whose Domain attribute does not domain-match the
//!     request host, and a Secure cookie set from an origin that
//!     is not potentially trustworthy (RFC 6265bis: https/wss
//!     scheme, or a loopback / localhost host).
//!   - No public-suffix list ships in sa_std, so the jar does not
//!     reject cookies for public suffixes (same behavior as Go's
//!     net/http/cookiejar with a nil PublicSuffixList). Callers
//!     that need PSL checks must layer them on top.
//!
//! Handles are opaque u64s (0 = invalid), mirroring the JSON/TOML
//! document surfaces. Status codes are the shared SA_STD_* set
//! (0 ok, 1 invalid argument, 2 invalid handle, 3 not found,
//! 5 no memory, 6 io). Time is unix seconds; jar operations take
//! an explicit `now` so behavior is deterministic and testable --
//! the two http hooks are the only functions that read the clock.
//! Strings handed out through &out_ptr/&out_len are owned by the
//! handle they came from and are invalidated by the next mutation
//! or serialization of that same handle (the TOML stringify rule).

const std = @import("std");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_IO: i32 = 6;

pub const SAMESITE_UNSPECIFIED: u32 = 0;
pub const SAMESITE_LAX: u32 = 1;
pub const SAMESITE_STRICT: u32 = 2;
pub const SAMESITE_NONE: u32 = 3;

pub const POLICY_ACCEPT_ALL: u32 = 0;
pub const POLICY_ACCEPT_NONE: u32 = 1;
pub const POLICY_HOST_ONLY: u32 = 2;

pub const STORE_STORED: u32 = 0;
pub const STORE_REPLACED: u32 = 1;
pub const STORE_DELETED: u32 = 2;
pub const STORE_IGNORED_EXPIRED: u32 = 3;
pub const STORE_REJECTED: u32 = 4;

const alloc = std.heap.page_allocator;

// ---------------- value model ----------------

const Cookie = struct {
    name: []u8,
    value: []u8,
    domain: []u8 = "",
    has_domain: bool = false,
    host_only: bool = false,
    path: []u8 = "",
    has_path: bool = false,
    expires_at: ?i64 = null,
    max_age: ?i64 = null,
    secure: bool = false,
    http_only: bool = false,
    partitioned: bool = false,
    same_site: u32 = SAMESITE_UNSPECIFIED,
    seq: u64 = 0,
    serial_buf: []u8 = "",
    pair_buf: []u8 = "",

    fn deinit(self: *Cookie) void {
        alloc.free(self.name);
        alloc.free(self.value);
        if (self.domain.len > 0) alloc.free(self.domain);
        if (self.path.len > 0) alloc.free(self.path);
        if (self.serial_buf.len > 0) alloc.free(self.serial_buf);
        if (self.pair_buf.len > 0) alloc.free(self.pair_buf);
    }

    fn clone(self: *const Cookie) !*Cookie {
        const out = try makeCookie(self.name, self.value);
        errdefer {
            out.deinit();
            alloc.destroy(out);
        }
        if (self.domain.len > 0) out.domain = try alloc.dupe(u8, self.domain);
        out.has_domain = self.has_domain;
        out.host_only = self.host_only;
        if (self.path.len > 0) out.path = try alloc.dupe(u8, self.path);
        out.has_path = self.has_path;
        out.expires_at = self.expires_at;
        out.max_age = self.max_age;
        out.secure = self.secure;
        out.http_only = self.http_only;
        out.partitioned = self.partitioned;
        out.same_site = self.same_site;
        out.seq = self.seq;
        return out;
    }
};

/// Heap-allocate a Cookie with owned name/value. Error paths free
/// exactly what was allocated (no errdefer overlap).
fn makeCookie(name: []const u8, value: []const u8) ParseError!*Cookie {
    const n = try alloc.dupe(u8, name);
    errdefer alloc.free(n);
    const v = try alloc.dupe(u8, value);
    const c = alloc.create(Cookie) catch |e| {
        alloc.free(v);
        return e;
    };
    c.* = .{ .name = n, .value = v };
    return c;
}

// ---------------- small helpers ----------------

fn constSlice(p: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return "";
    const ptr = p orelse return null;
    const n: usize = @intCast(len);
    return ptr[0..n];
}

fn isCtl(c: u8) bool {
    return c < 0x20 or c == 0x7f;
}

fn isTokenChar(c: u8) bool {
    // RFC 7230 tchar.
    return switch (c) {
        '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => true,
        '0'...'9', 'A'...'Z', 'a'...'z' => true,
        else => false,
    };
}

fn validCookieName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!isTokenChar(c)) return false;
    }
    return true;
}

fn isCookieOctet(c: u8) bool {
    // RFC 6265 cookie-octet: %x21 / %x23-2B / %x2D-3A / %x3C-5B / %x5D-7E
    return c == 0x21 or (c >= 0x23 and c <= 0x2b) or (c >= 0x2d and c <= 0x3a) or
        (c >= 0x3c and c <= 0x5b) or (c >= 0x5d and c <= 0x7e);
}

fn validCookieValue(value: []const u8) bool {
    for (value) |c| {
        if (!isCookieOctet(c)) return false;
    }
    return true;
}

fn trimOws(s: []const u8) []const u8 {
    var out = s;
    while (out.len > 0 and (out[0] == ' ' or out[0] == '\t')) out = out[1..];
    while (out.len > 0 and (out[out.len - 1] == ' ' or out[out.len - 1] == '\t')) out = out[0 .. out.len - 1];
    return out;
}

fn lowerDup(s: []const u8) ![]u8 {
    const out = try alloc.dupe(u8, s);
    for (out) |*c| c.* = std.ascii.toLower(c.*);
    return out;
}

fn eqFold(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    }
    return true;
}

fn endsWithFold(s: []const u8, suffix: []const u8) bool {
    if (suffix.len > s.len) return false;
    return eqFold(s[s.len - suffix.len ..], suffix);
}

// ---------------- dates (RFC 6265 5.1.1 + IMF-fixdate) ----------------

fn daysFromCivil(y0: i64, m: u32, d: u32) i64 {
    var y = y0;
    if (m <= 2) y -= 1;
    const era: i64 = @divFloor(y, 400);
    const yoe: u64 = @intCast(y - era * 400);
    const mp: u64 = if (m > 2) m - 3 else m + 9;
    const doy: u64 = (153 * mp + 2) / 5 + @as(u64, d) - 1;
    const doe: u64 = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + @as(i64, @intCast(doe)) - 719468;
}

const Civil = struct { year: i64, month: u32, day: u32 };

fn civilFromDays(z0: i64) Civil {
    const z = z0 + 719468;
    const era: i64 = @divFloor(z, 146097);
    const doe: u64 = @intCast(z - era * 146097);
    const yoe: u64 = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const y: i64 = @as(i64, @intCast(yoe)) + era * 400;
    const doy: u64 = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp: u64 = (5 * doy + 2) / 153;
    const d: u32 = @intCast(doy - (153 * mp + 2) / 5 + 1);
    const m: u32 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    return .{ .year = if (m <= 2) y + 1 else y, .month = m, .day = d };
}

fn isDateDelimiter(c: u8) bool {
    // RFC 6265 5.1.1 delimiter set.
    return c == 0x09 or (c >= 0x20 and c <= 0x2f) or (c >= 0x3b and c <= 0x40) or
        (c >= 0x5b and c <= 0x60) or (c >= 0x7b and c <= 0x7e);
}

const month_names = [_][]const u8{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };

fn parseLeadingUint(token: []const u8, max_digits: usize) ?struct { value: u32, digits: usize } {
    var value: u32 = 0;
    var n: usize = 0;
    while (n < token.len and n < max_digits and std.ascii.isDigit(token[n])) : (n += 1) {
        value = value * 10 + @as(u32, token[n] - '0');
    }
    if (n == 0) return null;
    return .{ .value = value, .digits = n };
}

const TimeOfDay = struct { h: u32, m: u32, s: u32 };

fn tokenTime(token: []const u8) ?TimeOfDay {
    // hms-time: 1*2DIGIT ":" 1*2DIGIT ":" 1*2DIGIT, trailing junk ignored.
    const h = parseLeadingUint(token, 2) orelse return null;
    var rest = token[h.digits..];
    if (rest.len == 0 or rest[0] != ':') return null;
    rest = rest[1..];
    const m = parseLeadingUint(rest, 2) orelse return null;
    rest = rest[m.digits..];
    if (rest.len == 0 or rest[0] != ':') return null;
    rest = rest[1..];
    const s = parseLeadingUint(rest, 2) orelse return null;
    return .{ .h = h.value, .m = m.value, .s = s.value };
}

/// RFC 6265 section 5.1.1 cookie-date parser. Accepts IMF-fixdate,
/// RFC 850 and asctime shapes (and the loose variants the RFC
/// algorithm accepts). Returns null when the string is not a
/// cookie date -- callers treat that as "attribute absent".
fn parseCookieDate(s: []const u8) ?i64 {
    var time: ?TimeOfDay = null;
    var day: ?u32 = null;
    var month: ?u32 = null;
    var year: ?i64 = null;

    var i: usize = 0;
    while (i < s.len) {
        while (i < s.len and isDateDelimiter(s[i])) i += 1;
        if (i >= s.len) break;
        const start = i;
        while (i < s.len and !isDateDelimiter(s[i])) i += 1;
        const token = s[start..i];

        if (time == null) {
            if (tokenTime(token)) |t| {
                time = t;
                continue;
            }
        }
        if (day == null) {
            if (parseLeadingUint(token, 2)) |d| {
                // A day token is 1-2 digits not followed by another digit.
                if (d.digits == token.len or !std.ascii.isDigit(token[d.digits])) {
                    day = d.value;
                    continue;
                }
            }
        }
        if (month == null and token.len >= 3) {
            var matched: ?u32 = null;
            for (month_names, 0..) |name, idx| {
                if (eqFold(token[0..3], name)) {
                    matched = @intCast(idx + 1);
                    break;
                }
            }
            if (matched) |mo| {
                month = mo;
                continue;
            }
        }
        if (year == null) {
            if (parseLeadingUint(token, 4)) |y| {
                if (y.digits >= 2 and (y.digits == token.len or !std.ascii.isDigit(token[y.digits]))) {
                    var v: i64 = @intCast(y.value);
                    if (y.digits == 2) {
                        if (v >= 70) {
                            v += 1900;
                        } else {
                            v += 2000;
                        }
                    }
                    year = v;
                    continue;
                }
            }
        }
    }

    const t = time orelse return null;
    const d = day orelse return null;
    const mo = month orelse return null;
    const y = year orelse return null;
    if (d < 1 or d > 31) return null;
    if (y < 1601) return null;
    if (t.h > 23 or t.m > 59 or t.s > 59) return null;
    const days = daysFromCivil(y, mo, d);
    return days * 86400 + @as(i64, t.h) * 3600 + @as(i64, t.m) * 60 + @as(i64, t.s);
}

const weekday_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
const month_names_full = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

/// IMF-fixdate, the only date form serialization emits.
fn formatImfFixdate(unix: i64, buf: *[40]u8) []const u8 {
    const days = @divFloor(unix, 86400);
    var rem = unix - days * 86400;
    const c = civilFromDays(days);
    const wd: usize = @intCast(@mod(days + 4, 7));
    const hh: u32 = @intCast(@divFloor(rem, 3600));
    rem -= @as(i64, hh) * 3600;
    const mm: u32 = @intCast(@divFloor(rem, 60));
    const ss: u32 = @intCast(rem - @as(i64, mm) * 60);
    // The year goes through an unsigned format on the common path:
    // Zig pads signed integers with an explicit '+' ("+1994"),
    // which is not IMF-fixdate. Out-of-range years (reachable only
    // through sa_cookie_set_expires with an extreme value) fall
    // back to an unpadded rendering.
    if (c.year >= 0 and c.year <= 9999) {
        return std.fmt.bufPrint(buf, "{s}, {d:0>2} {s} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
            weekday_names[wd], c.day, month_names_full[c.month - 1], @as(u64, @intCast(c.year)), hh, mm, ss,
        }) catch buf[0..0];
    }
    return std.fmt.bufPrint(buf, "{s}, {d:0>2} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
        weekday_names[wd], c.day, month_names_full[c.month - 1], c.year, hh, mm, ss,
    }) catch buf[0..0];
}

// ---------------- matching (RFC 6265 5.1.3 / 5.1.4) ----------------

fn hostIsIp(host: []const u8) bool {
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

/// RFC 6265 5.1.3 string matching: identical, or host ends with
/// "." ++ domain. When the host is an IP literal only the identical
/// form counts (a cookie domain must never suffix-match an IP).
fn domainMatch(domain: []const u8, host: []const u8) bool {
    if (domain.len == 0 or host.len == 0) return false;
    if (eqFold(domain, host)) return true;
    if (hostIsIp(host)) return false;
    if (host.len <= domain.len) return false;
    if (host[host.len - domain.len - 1] != '.') return false;
    return endsWithFold(host, domain);
}

/// RFC 6265 5.1.4 path-match.
fn pathMatch(cookie_path: []const u8, request_path: []const u8) bool {
    if (cookie_path.len == 0) return false;
    const rp = if (request_path.len == 0) "/" else request_path;
    if (std.mem.eql(u8, cookie_path, rp)) return true;
    if (rp.len > cookie_path.len and std.mem.startsWith(u8, rp, cookie_path)) {
        if (cookie_path[cookie_path.len - 1] == '/') return true;
        if (rp[cookie_path.len] == '/') return true;
    }
    return false;
}

/// RFC 6265 5.1.4 default-path of a request URI path.
fn defaultPath(uri_path: []const u8) []const u8 {
    if (uri_path.len == 0 or uri_path[0] != '/') return "/";
    const last_slash = std.mem.lastIndexOfScalar(u8, uri_path, '/') orelse return "/";
    if (last_slash == 0) return "/";
    return uri_path[0..last_slash];
}

// ---------------- URL splitting (jar operations) ----------------

const UrlParts = struct {
    scheme: []const u8,
    host: []const u8,
    path: []const u8,
};

fn splitUrl(url: []const u8) ?UrlParts {
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

/// RFC 6265bis "potentially trustworthy origin": a secure scheme,
/// or a loopback / localhost host.
fn originTrustworthy(scheme: []const u8, host: []const u8) bool {
    if (eqFold(scheme, "https") or eqFold(scheme, "wss")) return true;
    if (eqFold(host, "localhost") or endsWithFold(host, ".localhost")) return true;
    if (std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "::1")) return true;
    return false;
}

fn nowUnix() i64 {
    const ts = std.Io.Clock.real.now(sio.io());
    return @divFloor(ts.toMilliseconds(), 1000);
}

// ---------------- parse / serialize core ----------------

const ParseError = error{ InvalidCookie, OutOfMemory };

fn parseMaxAge(s: []const u8) ?i64 {
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

fn validDomainAttr(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        const ok = std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_';
        if (!ok) return false;
    }
    return true;
}

/// Parse one Set-Cookie header value into an owned Cookie.
/// Caller owns the returned object (alloc.destroy after deinit).
fn parseSetCookie(raw: []const u8) ParseError!*Cookie {
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

fn serializeInto(list: *std.array_list.Managed(u8), c: *const Cookie, pair_only: bool) !void {
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

fn serializeOwned(c: *const Cookie, pair_only: bool) ![]u8 {
    var list = std.array_list.Managed(u8).init(alloc);
    errdefer list.deinit();
    try serializeInto(&list, c, pair_only);
    return list.toOwnedSlice();
}

// ---------------- registries + last error ----------------

var cookies_mu = std.Io.Mutex.init;
var cookies_map: std.AutoHashMapUnmanaged(u64, *Cookie) = .empty;
var cookies_next: u64 = 1;

var jars_mu = std.Io.Mutex.init;
var jars_map: std.AutoHashMapUnmanaged(u64, *Jar) = .empty;
var jars_next: u64 = 1;

fn registerCookie(c: *Cookie) !u64 {
    cookies_mu.lockUncancelable(sio.io());
    defer cookies_mu.unlock(sio.io());
    const h = cookies_next;
    cookies_next += 1;
    try cookies_map.put(alloc, h, c);
    return h;
}

fn getCookie(handle: u64) ?*Cookie {
    cookies_mu.lockUncancelable(sio.io());
    defer cookies_mu.unlock(sio.io());
    return cookies_map.get(handle);
}

fn removeCookie(handle: u64) ?*Cookie {
    cookies_mu.lockUncancelable(sio.io());
    defer cookies_mu.unlock(sio.io());
    const kv = cookies_map.fetchRemove(handle) orelse return null;
    return kv.value;
}

fn registerJar(j: *Jar) !u64 {
    jars_mu.lockUncancelable(sio.io());
    defer jars_mu.unlock(sio.io());
    const h = jars_next;
    jars_next += 1;
    try jars_map.put(alloc, h, j);
    return h;
}

fn getJar(handle: u64) ?*Jar {
    jars_mu.lockUncancelable(sio.io());
    defer jars_mu.unlock(sio.io());
    return jars_map.get(handle);
}

fn removeJar(handle: u64) ?*Jar {
    jars_mu.lockUncancelable(sio.io());
    defer jars_mu.unlock(sio.io());
    const kv = jars_map.fetchRemove(handle) orelse return null;
    return kv.value;
}

var last_error_buf: [512]u8 = undefined;
var last_error_len: usize = 0;

fn setLastError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&last_error_buf, fmt, args) catch blk: {
        last_error_len = 0;
        break :blk "";
    };
    last_error_len = msg.len;
}

fn clearLastError() void {
    last_error_len = 0;
}

// ---------------- value layer externs ----------------

fn outString(out_ptr: ?*?[*]const u8, out_len: ?*u64, s: ?[]const u8) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const v = s orelse return ERR_NOT_FOUND;
    if (v.len > 0) ptr_slot.* = v.ptr;
    len_slot.* = @intCast(v.len);
    return OK;
}

pub export fn sa_cookie_last_error(out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    if (last_error_len == 0) {
        ptr_slot.* = null;
        len_slot.* = 0;
        return ERR_NOT_FOUND;
    }
    ptr_slot.* = last_error_buf[0..last_error_len].ptr;
    len_slot.* = @intCast(last_error_len);
    return OK;
}

pub export fn sa_cookie_parse_set_cookie(bytes: ?[*]const u8, len: u64) u64 {
    clearLastError();
    const raw = constSlice(bytes, len) orelse {
        setLastError("cookie: null bytes with nonzero length", .{});
        return 0;
    };
    const cookie = parseSetCookie(raw) catch |err| {
        if (err == error.OutOfMemory) {
            setLastError("cookie: out of memory", .{});
        } else {
            setLastError("cookie: invalid Set-Cookie value", .{});
        }
        return 0;
    };
    return registerCookie(cookie) catch {
        cookie.deinit();
        alloc.destroy(cookie);
        setLastError("cookie: out of memory", .{});
        return 0;
    };
}

pub export fn sa_cookie_new(name_ptr: ?[*]const u8, name_len: u64, value_ptr: ?[*]const u8, value_len: u64) u64 {
    clearLastError();
    const name = constSlice(name_ptr, name_len) orelse return 0;
    const value = constSlice(value_ptr, value_len) orelse return 0;
    if (!validCookieName(name)) {
        setLastError("cookie: invalid cookie name", .{});
        return 0;
    }
    if (!validCookieValue(value)) {
        setLastError("cookie: invalid cookie value", .{});
        return 0;
    }
    const cookie = alloc.create(Cookie) catch return 0;
    cookie.* = .{
        .name = alloc.dupe(u8, name) catch {
            alloc.destroy(cookie);
            return 0;
        },
        .value = alloc.dupe(u8, value) catch {
            alloc.free(cookie.name);
            alloc.destroy(cookie);
            return 0;
        },
    };
    return registerCookie(cookie) catch {
        cookie.deinit();
        alloc.destroy(cookie);
        return 0;
    };
}

pub export fn sa_cookie_free(handle: u64) i32 {
    const cookie = removeCookie(handle) orelse return ERR_HANDLE;
    cookie.deinit();
    alloc.destroy(cookie);
    return OK;
}

pub export fn sa_cookie_name(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    return outString(out_ptr, out_len, c.name);
}

pub export fn sa_cookie_value(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    return outString(out_ptr, out_len, c.value);
}

pub export fn sa_cookie_domain(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    return outString(out_ptr, out_len, if (c.has_domain) c.domain else null);
}

pub export fn sa_cookie_path(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    return outString(out_ptr, out_len, if (c.has_path) c.path else null);
}

pub export fn sa_cookie_expires(handle: u64, out_unix: ?*i64) i32 {
    const slot = out_unix orelse return ERR_INVALID;
    slot.* = 0;
    const c = getCookie(handle) orelse return ERR_HANDLE;
    const v = c.expires_at orelse return ERR_NOT_FOUND;
    slot.* = v;
    return OK;
}

pub export fn sa_cookie_max_age(handle: u64, out_secs: ?*i64) i32 {
    const slot = out_secs orelse return ERR_INVALID;
    slot.* = 0;
    const c = getCookie(handle) orelse return ERR_HANDLE;
    const v = c.max_age orelse return ERR_NOT_FOUND;
    slot.* = v;
    return OK;
}

pub export fn sa_cookie_flags(handle: u64, out_secure: ?*i32, out_http_only: ?*i32, out_partitioned: ?*i32) i32 {
    const s = out_secure orelse return ERR_INVALID;
    const h = out_http_only orelse return ERR_INVALID;
    const p = out_partitioned orelse return ERR_INVALID;
    const c = getCookie(handle) orelse return ERR_HANDLE;
    s.* = if (c.secure) 1 else 0;
    h.* = if (c.http_only) 1 else 0;
    p.* = if (c.partitioned) 1 else 0;
    return OK;
}

pub export fn sa_cookie_same_site(handle: u64, out_mode: ?*u32) i32 {
    const slot = out_mode orelse return ERR_INVALID;
    slot.* = 0;
    const c = getCookie(handle) orelse return ERR_HANDLE;
    slot.* = c.same_site;
    return OK;
}

pub export fn sa_cookie_is_host_only(handle: u64, out_flag: ?*i32) i32 {
    const slot = out_flag orelse return ERR_INVALID;
    slot.* = 0;
    const c = getCookie(handle) orelse return ERR_HANDLE;
    slot.* = if (c.host_only) 1 else 0;
    return OK;
}

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

pub export fn sa_cookie_clear_expiry(handle: u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    c.expires_at = null;
    c.max_age = null;
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

pub export fn sa_cookie_serialize(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    const s = serializeOwned(c, false) catch return ERR_NOMEM;
    if (c.serial_buf.len > 0) alloc.free(c.serial_buf);
    c.serial_buf = s;
    return outString(out_ptr, out_len, c.serial_buf);
}

pub export fn sa_cookie_serialize_pair(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    const s = serializeOwned(c, true) catch return ERR_NOMEM;
    if (c.pair_buf.len > 0) alloc.free(c.pair_buf);
    c.pair_buf = s;
    return outString(out_ptr, out_len, c.pair_buf);
}

pub export fn sa_cookie_is_expired(handle: u64, now: i64, out_flag: ?*i32) i32 {
    const slot = out_flag orelse return ERR_INVALID;
    slot.* = 0;
    const c = getCookie(handle) orelse return ERR_HANDLE;
    // Only the absolute Expires form can be judged on a bare value:
    // Max-Age is relative to receipt, which only the jar knows.
    if (c.expires_at) |ts| {
        slot.* = if (ts <= now) 1 else 0;
    }
    return OK;
}

pub export fn sa_cookie_domain_match(domain_ptr: ?[*]const u8, domain_len: u64, host_ptr: ?[*]const u8, host_len: u64, out_flag: ?*i32) i32 {
    const slot = out_flag orelse return ERR_INVALID;
    slot.* = 0;
    const domain = constSlice(domain_ptr, domain_len) orelse return ERR_INVALID;
    const host = constSlice(host_ptr, host_len) orelse return ERR_INVALID;
    var d = domain;
    if (d.len > 0 and d[0] == '.') d = d[1..];
    slot.* = if (domainMatch(d, host)) 1 else 0;
    return OK;
}

pub export fn sa_cookie_path_match(cookie_path_ptr: ?[*]const u8, cookie_path_len: u64, request_path_ptr: ?[*]const u8, request_path_len: u64, out_flag: ?*i32) i32 {
    const slot = out_flag orelse return ERR_INVALID;
    slot.* = 0;
    const cp = constSlice(cookie_path_ptr, cookie_path_len) orelse return ERR_INVALID;
    const rp = constSlice(request_path_ptr, request_path_len) orelse return ERR_INVALID;
    slot.* = if (pathMatch(cp, rp)) 1 else 0;
    return OK;
}

// Cookie request header: "name=value; name2=value2". Segments
// without '=' are malformed (explicit error, never skipped
// silently); empty segments from stray ';' are skipped.
fn parseHeaderPair(segment: []const u8) ParseError!*Cookie {
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

// ---------------- jar layer ----------------

const Jar = struct {
    entries: std.array_list.Managed(Cookie) = std.array_list.Managed(Cookie).init(alloc),
    policy: u32 = POLICY_ACCEPT_ALL,
    next_seq: u64 = 1,
    header_buf: []u8 = "",

    fn deinit(self: *Jar) void {
        for (self.entries.items) |*e| e.deinit();
        self.entries.deinit();
        if (self.header_buf.len > 0) alloc.free(self.header_buf);
    }

    fn findEntry(self: *Jar, name: []const u8, domain: []const u8, path: []const u8) ?usize {
        for (self.entries.items, 0..) |*e, i| {
            if (std.mem.eql(u8, e.name, name) and std.mem.eql(u8, e.domain, domain) and std.mem.eql(u8, e.path, path)) {
                return i;
            }
        }
        return null;
    }

    fn evictExpired(self: *Jar, now: i64) usize {
        var removed: usize = 0;
        var i = self.entries.items.len;
        while (i > 0) {
            i -= 1;
            const e = &self.entries.items[i];
            if (e.expires_at) |ts| {
                if (ts <= now) {
                    var dead = self.entries.orderedRemove(i);
                    dead.deinit();
                    removed += 1;
                }
            }
        }
        return removed;
    }
};

/// Insert a fully-formed entry (domain/path already resolved).
/// Replaces an existing (name, domain, path) entry in place,
/// preserving its creation sequence. Takes ownership of `entry`'s
/// strings in all outcomes.
fn jarInsert(jar: *Jar, entry: Cookie) !enum { stored, replaced } {
    if (jar.findEntry(entry.name, entry.domain, entry.path)) |idx| {
        var old = &jar.entries.items[idx];
        const seq = old.seq;
        old.deinit();
        jar.entries.items[idx] = entry;
        jar.entries.items[idx].seq = seq;
        return .replaced;
    }
    var fresh = entry;
    fresh.seq = jar.next_seq;
    jar.next_seq += 1;
    try jar.entries.append(fresh);
    return .stored;
}

pub export fn sa_cookie_jar_new() u64 {
    const jar = alloc.create(Jar) catch return 0;
    jar.* = .{};
    return registerJar(jar) catch {
        jar.deinit();
        alloc.destroy(jar);
        return 0;
    };
}

pub export fn sa_cookie_jar_free(handle: u64) i32 {
    const jar = removeJar(handle) orelse return ERR_HANDLE;
    jar.deinit();
    alloc.destroy(jar);
    return OK;
}

pub export fn sa_cookie_jar_set_policy(handle: u64, policy: u32) i32 {
    const jar = getJar(handle) orelse return ERR_HANDLE;
    if (policy > POLICY_HOST_ONLY) return ERR_INVALID;
    jar.policy = policy;
    return OK;
}

pub export fn sa_cookie_jar_policy(handle: u64, out_policy: ?*u32) i32 {
    const slot = out_policy orelse return ERR_INVALID;
    slot.* = 0;
    const jar = getJar(handle) orelse return ERR_HANDLE;
    slot.* = jar.policy;
    return OK;
}

pub export fn sa_cookie_jar_store(handle: u64, url_ptr: ?[*]const u8, url_len: u64, set_cookie_ptr: ?[*]const u8, set_cookie_len: u64, now: i64, out_result: ?*u32) i32 {
    const result_slot = out_result orelse return ERR_INVALID;
    const jar = getJar(handle) orelse return ERR_HANDLE;
    const url_raw = constSlice(url_ptr, url_len) orelse return ERR_INVALID;
    const sc_raw = constSlice(set_cookie_ptr, set_cookie_len) orelse return ERR_INVALID;
    const url = splitUrl(url_raw) orelse return ERR_INVALID;

    const parsed = parseSetCookie(sc_raw) catch |err| {
        return if (err == error.OutOfMemory) ERR_NOMEM else ERR_INVALID;
    };
    // `parsed` is a heap-owned scratch cookie: its fields are
    // copied (never moved) into the jar entry, so it is freed on
    // every path out of this function.
    defer {
        parsed.deinit();
        alloc.destroy(parsed);
    }

    if (jar.policy == POLICY_ACCEPT_NONE) {
        result_slot.* = STORE_REJECTED;
        return OK;
    }

    const host_lower = lowerDup(url.host) catch return ERR_NOMEM;
    defer alloc.free(host_lower);

    // Resolve the storage domain (RFC 6265 5.3 step 5/6). Every
    // allocation below is guarded by a live flag: exactly one
    // owner frees each string on every path.
    var domain: []u8 = "";
    var domain_live = false;
    defer {
        if (domain_live) alloc.free(domain);
    }
    var host_only = true;
    if (parsed.has_domain and jar.policy != POLICY_HOST_ONLY) {
        if (!domainMatch(parsed.domain, host_lower)) {
            result_slot.* = STORE_REJECTED;
            return OK;
        }
        domain = alloc.dupe(u8, parsed.domain) catch return ERR_NOMEM;
        domain_live = true;
        host_only = false;
    } else {
        domain = alloc.dupe(u8, host_lower) catch return ERR_NOMEM;
        domain_live = true;
        host_only = true;
    }

    // Secure cookies only from potentially trustworthy origins.
    if (parsed.secure and !originTrustworthy(url.scheme, host_lower)) {
        result_slot.* = STORE_REJECTED;
        return OK;
    }

    // Resolve the storage path (RFC 6265 5.3 step 5 / 5.1.4).
    var path: []u8 = "";
    var path_live = false;
    defer {
        if (path_live) alloc.free(path);
    }
    if (parsed.has_path) {
        path = alloc.dupe(u8, parsed.path) catch return ERR_NOMEM;
    } else {
        path = alloc.dupe(u8, defaultPath(url.path)) catch return ERR_NOMEM;
    }
    path_live = true;

    // Effective expiry: Max-Age beats Expires (RFC 6265 5.3).
    var expires_at: ?i64 = parsed.expires_at;
    if (parsed.max_age) |ma| {
        expires_at = if (ma <= 0) now else now +| ma;
    }

    var entry = Cookie{ .name = "", .value = "" };
    var entry_live = true;
    defer {
        if (entry_live) entry.deinit();
    }
    entry.name = alloc.dupe(u8, parsed.name) catch return ERR_NOMEM;
    entry.value = alloc.dupe(u8, parsed.value) catch return ERR_NOMEM;
    entry.domain = domain;
    domain_live = false;
    entry.has_domain = true;
    entry.host_only = host_only;
    entry.path = path;
    path_live = false;
    entry.has_path = true;
    entry.expires_at = expires_at;
    entry.secure = parsed.secure;
    entry.http_only = parsed.http_only;
    entry.partitioned = parsed.partitioned;
    entry.same_site = parsed.same_site;

    if (expires_at) |ts| {
        if (ts <= now) {
            // Already expired: delete any existing cookie with
            // this key, store nothing (RFC 6265 5.3 step 11/12).
            if (jar.findEntry(entry.name, entry.domain, entry.path)) |idx| {
                var dead = jar.entries.orderedRemove(idx);
                dead.deinit();
                result_slot.* = STORE_DELETED;
            } else {
                result_slot.* = STORE_IGNORED_EXPIRED;
            }
            return OK;
        }
    }

    // On error jarInsert has NOT consumed the entry; the deferred
    // cleanup above remains the owner.
    const how = jarInsert(jar, entry) catch return ERR_NOMEM;
    entry_live = false;
    result_slot.* = if (how == .replaced) STORE_REPLACED else STORE_STORED;
    return OK;
}

fn headerLessThan(_: void, a: *Cookie, b: *Cookie) bool {
    if (a.path.len != b.path.len) return a.path.len > b.path.len;
    return a.seq < b.seq;
}

pub export fn sa_cookie_jar_header(handle: u64, url_ptr: ?[*]const u8, url_len: u64, now: i64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const jar = getJar(handle) orelse return ERR_HANDLE;
    const url_raw = constSlice(url_ptr, url_len) orelse return ERR_INVALID;
    const url = splitUrl(url_raw) orelse return ERR_INVALID;

    _ = jar.evictExpired(now);

    var matches = std.array_list.Managed(*Cookie).init(alloc);
    defer matches.deinit();
    for (jar.entries.items) |*e| {
        if (e.host_only) {
            if (!eqFold(e.domain, url.host)) continue;
        } else {
            if (!domainMatch(e.domain, url.host)) continue;
        }
        if (!pathMatch(e.path, url.path)) continue;
        if (e.secure and !originTrustworthy(url.scheme, url.host)) continue;
        matches.append(e) catch return ERR_NOMEM;
    }
    if (matches.items.len == 0) return ERR_NOT_FOUND;

    std.mem.sort(*Cookie, matches.items, {}, headerLessThan);

    var list = std.array_list.Managed(u8).init(alloc);
    defer list.deinit();
    for (matches.items, 0..) |e, i| {
        if (i > 0) list.appendSlice("; ") catch return ERR_NOMEM;
        serializeInto(&list, e, true) catch return ERR_NOMEM;
    }
    const owned_slice = list.toOwnedSlice() catch return ERR_NOMEM;
    if (jar.header_buf.len > 0) alloc.free(jar.header_buf);
    jar.header_buf = owned_slice;
    ptr_slot.* = jar.header_buf.ptr;
    len_slot.* = @intCast(jar.header_buf.len);
    return OK;
}

pub export fn sa_cookie_jar_count(handle: u64, out_count: ?*u64) i32 {
    const slot = out_count orelse return ERR_INVALID;
    slot.* = 0;
    const jar = getJar(handle) orelse return ERR_HANDLE;
    slot.* = @intCast(jar.entries.items.len);
    return OK;
}

pub export fn sa_cookie_jar_at(handle: u64, index: u64) u64 {
    const jar = getJar(handle) orelse return 0;
    if (index >= jar.entries.items.len) return 0;
    const src = &jar.entries.items[@intCast(index)];
    const copy = src.clone() catch return 0;
    copy.max_age = null; // the copy carries the absolute expiry only
    return registerCookie(copy) catch {
        copy.deinit();
        alloc.destroy(copy);
        return 0;
    };
}

pub export fn sa_cookie_jar_clear(handle: u64) i32 {
    const jar = getJar(handle) orelse return ERR_HANDLE;
    for (jar.entries.items) |*e| e.deinit();
    jar.entries.clearRetainingCapacity();
    return OK;
}

pub export fn sa_cookie_jar_evict_expired(handle: u64, now: i64, out_removed: ?*u64) i32 {
    const slot = out_removed orelse return ERR_INVALID;
    slot.* = 0;
    const jar = getJar(handle) orelse return ERR_HANDLE;
    slot.* = @intCast(jar.evictExpired(now));
    return OK;
}

// ---------------- Netscape cookie file persistence ----------------

fn boolWord(b: bool) []const u8 {
    return if (b) "TRUE" else "FALSE";
}

pub export fn sa_cookie_jar_save(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const jar = getJar(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    if (path.len == 0) return ERR_INVALID;

    var list = std.array_list.Managed(u8).init(alloc);
    defer list.deinit();
    list.appendSlice("# Netscape HTTP Cookie File\n# Written by sa_std (sa_cookie_jar_save). HttpOnly cookies carry the #HttpOnly_ prefix.\n\n") catch return ERR_NOMEM;
    for (jar.entries.items) |*e| {
        if (e.http_only) list.appendSlice("#HttpOnly_") catch return ERR_NOMEM;
        if (e.host_only) {
            list.appendSlice(e.domain) catch return ERR_NOMEM;
        } else {
            list.append('.') catch return ERR_NOMEM;
            list.appendSlice(e.domain) catch return ERR_NOMEM;
        }
        list.append('\t') catch return ERR_NOMEM;
        list.appendSlice(boolWord(!e.host_only)) catch return ERR_NOMEM;
        list.append('\t') catch return ERR_NOMEM;
        list.appendSlice(e.path) catch return ERR_NOMEM;
        list.append('\t') catch return ERR_NOMEM;
        list.appendSlice(boolWord(e.secure)) catch return ERR_NOMEM;
        list.append('\t') catch return ERR_NOMEM;
        const exp = e.expires_at orelse 0;
        const exp_s = std.fmt.allocPrint(alloc, "{d}", .{exp}) catch return ERR_NOMEM;
        list.appendSlice(exp_s) catch {
            alloc.free(exp_s);
            return ERR_NOMEM;
        };
        alloc.free(exp_s);
        list.append('\t') catch return ERR_NOMEM;
        list.appendSlice(e.name) catch return ERR_NOMEM;
        list.append('\t') catch return ERR_NOMEM;
        list.appendSlice(e.value) catch return ERR_NOMEM;
        list.append('\n') catch return ERR_NOMEM;
    }

    var file = std.Io.Dir.cwd().createFile(sio.io(), path, .{ .truncate = true }) catch return ERR_IO;
    defer file.close(sio.io());
    var wbuf: [8192]u8 = undefined;
    var w = file.writerStreaming(sio.io(), &wbuf);
    w.interface.writeAll(list.items) catch return ERR_IO;
    w.interface.flush() catch return ERR_IO;
    return OK;
}

fn parseBoolWord(s: []const u8) ?bool {
    if (std.mem.eql(u8, s, "TRUE")) return true;
    if (std.mem.eql(u8, s, "FALSE")) return false;
    return null;
}

pub export fn sa_cookie_jar_load(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_loaded: ?*u64) i32 {
    const slot = out_loaded orelse return ERR_INVALID;
    slot.* = 0;
    const jar = getJar(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    if (path.len == 0) return ERR_INVALID;

    var file = std.Io.Dir.cwd().openFile(sio.io(), path, .{}) catch return ERR_IO;
    defer file.close(sio.io());
    var rbuf: [8192]u8 = undefined;
    var r = file.readerStreaming(sio.io(), &rbuf);
    const data = r.interface.allocRemaining(alloc, .limited(16 * 1024 * 1024)) catch return ERR_IO;
    defer alloc.free(data);

    // Parse everything first: a malformed data line fails the
    // whole load and leaves the jar untouched.
    var pending = std.array_list.Managed(Cookie).init(alloc);
    defer {
        for (pending.items) |*e| e.deinit();
        pending.deinit();
    }
    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        line_no += 1;
        var line = raw_line;
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        if (line.len == 0) continue;
        var http_only = false;
        if (std.mem.startsWith(u8, line, "#HttpOnly_")) {
            http_only = true;
            line = line["#HttpOnly_".len..];
        } else if (line[0] == '#') {
            continue;
        }
        var fields: [7][]const u8 = undefined;
        var nf: usize = 0;
        var fit = std.mem.splitScalar(u8, line, '\t');
        while (fit.next()) |f| {
            if (nf >= 7) {
                setLastError("cookie: netscape line {d} has too many fields", .{line_no});
                return ERR_INVALID;
            }
            fields[nf] = f;
            nf += 1;
        }
        if (nf != 7) {
            setLastError("cookie: netscape line {d} has {d} fields, want 7", .{ line_no, nf });
            return ERR_INVALID;
        }
        const flag_all = parseBoolWord(fields[1]) orelse {
            setLastError("cookie: netscape line {d} has a bad domain flag", .{line_no});
            return ERR_INVALID;
        };
        const secure = parseBoolWord(fields[3]) orelse {
            setLastError("cookie: netscape line {d} has a bad secure flag", .{line_no});
            return ERR_INVALID;
        };
        const expires_raw = std.fmt.parseInt(i64, fields[4], 10) catch {
            setLastError("cookie: netscape line {d} has a bad expiry", .{line_no});
            return ERR_INVALID;
        };
        var domain = fields[0];
        if (domain.len > 0 and domain[0] == '.') domain = domain[1..];
        if (!validDomainAttr(domain)) {
            setLastError("cookie: netscape line {d} has a bad domain", .{line_no});
            return ERR_INVALID;
        }
        if (!validCookieName(fields[5])) {
            setLastError("cookie: netscape line {d} has a bad name", .{line_no});
            return ERR_INVALID;
        }
        if (!validCookieValue(fields[6])) {
            setLastError("cookie: netscape line {d} has a bad value", .{line_no});
            return ERR_INVALID;
        }
        if (fields[2].len == 0 or fields[2][0] != '/') {
            setLastError("cookie: netscape line {d} has a bad path", .{line_no});
            return ERR_INVALID;
        }
        var entry = Cookie{
            .name = alloc.dupe(u8, fields[5]) catch return ERR_NOMEM,
            .value = "",
        };
        entry.value = alloc.dupe(u8, fields[6]) catch {
            entry.deinit();
            return ERR_NOMEM;
        };
        entry.domain = lowerDup(domain) catch {
            entry.deinit();
            return ERR_NOMEM;
        };
        entry.has_domain = true;
        entry.host_only = !flag_all;
        entry.path = alloc.dupe(u8, fields[2]) catch {
            entry.deinit();
            return ERR_NOMEM;
        };
        entry.has_path = true;
        entry.expires_at = if (expires_raw == 0) null else expires_raw;
        entry.secure = secure;
        entry.http_only = http_only;
        pending.append(entry) catch {
            entry.deinit();
            return ERR_NOMEM;
        };
    }

    var loaded: u64 = 0;
    for (pending.items) |*e| {
        // Move out of `pending` so its deferred cleanup skips it.
        var entry = e.*;
        e.name = "";
        e.value = "";
        e.domain = "";
        e.path = "";
        _ = jarInsert(jar, entry) catch {
            entry.deinit();
            return ERR_NOMEM;
        };
        loaded += 1;
    }
    slot.* = loaded;
    return OK;
}

// ---------------- http_client hooks (explicit, std-level) ----------------

pub export fn sa_cookie_jar_request_header(handle: u64, url_ptr: ?[*]const u8, url_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    return sa_cookie_jar_header(handle, url_ptr, url_len, nowUnix(), out_ptr, out_len);
}

pub export fn sa_cookie_jar_store_response(handle: u64, url_ptr: ?[*]const u8, url_len: u64, set_cookie_ptr: ?[*]const u8, set_cookie_len: u64) i32 {
    var result: u32 = 0;
    return sa_cookie_jar_store(handle, url_ptr, url_len, set_cookie_ptr, set_cookie_len, nowUnix(), &result);
}

// ---------------- tests ----------------

fn expectOut(expected: []const u8, ptr_slot: ?[*]const u8, len: u64) !void {
    try std.testing.expectEqual(expected.len, @as(usize, @intCast(len)));
    if (len > 0) try std.testing.expectEqualStrings(expected, ptr_slot.?[0..@intCast(len)]);
}

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

fn jarStore(jar: u64, url: []const u8, sc: []const u8, now: i64) !u32 {
    var result: u32 = 999;
    try std.testing.expectEqual(OK, sa_cookie_jar_store(jar, url.ptr, url.len, sc.ptr, sc.len, now, &result));
    return result;
}

fn jarHeaderEq(jar: u64, url: []const u8, now: i64, expected: ?[]const u8) !void {
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

fn jarCount(jar: u64) !u64 {
    var count: u64 = 0;
    try std.testing.expectEqual(OK, sa_cookie_jar_count(jar, &count));
    return count;
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
