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

test "sa_cookie_tests" { std.testing.refAllDecls(@import("sa_cookie_test.zig")); }

const std = @import("std");
pub const sio = @import("sio");

pub const OK: i32 = 0;
pub const ERR_INVALID: i32 = 1;
pub const ERR_HANDLE: i32 = 2;
pub const ERR_NOT_FOUND: i32 = 3;
pub const ERR_NOMEM: i32 = 5;
pub const ERR_IO: i32 = 6;

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

pub const alloc = std.heap.page_allocator;

// ---------------- value model ----------------

pub const Cookie = struct {
    name: []u8,
    value: []u8,
    domain: []u8 = "",
    has_domain: bool = false,
    // RFC 6265 5.3: a cookie with no Domain attribute is host-only.
    // A Cookie is born domain-less, so it is born host-only; every
    // path that gains a domain (parse, set_domain) must clear this.
    // Invariant: host_only == !has_domain (W1-DEF-COOKIE-HOSTONLY).
    host_only: bool = true,
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

    pub fn deinit(self: *Cookie) void {
        alloc.free(self.name);
        alloc.free(self.value);
        if (self.domain.len > 0) alloc.free(self.domain);
        if (self.path.len > 0) alloc.free(self.path);
        if (self.serial_buf.len > 0) alloc.free(self.serial_buf);
        if (self.pair_buf.len > 0) alloc.free(self.pair_buf);
    }

    pub fn clone(self: *const Cookie) !*Cookie {
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
pub fn makeCookie(name: []const u8, value: []const u8) ParseError!*Cookie {
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

pub fn constSlice(p: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return "";
    const ptr = p orelse return null;
    const n: usize = @intCast(len);
    return ptr[0..n];
}

pub fn isCtl(c: u8) bool {
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

pub fn validCookieName(name: []const u8) bool {
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

pub fn validCookieValue(value: []const u8) bool {
    for (value) |c| {
        if (!isCookieOctet(c)) return false;
    }
    return true;
}

pub fn trimOws(s: []const u8) []const u8 {
    var out = s;
    while (out.len > 0 and (out[0] == ' ' or out[0] == '\t')) out = out[1..];
    while (out.len > 0 and (out[out.len - 1] == ' ' or out[out.len - 1] == '\t')) out = out[0 .. out.len - 1];
    return out;
}

pub fn lowerDup(s: []const u8) ![]u8 {
    const out = try alloc.dupe(u8, s);
    for (out) |*c| c.* = std.ascii.toLower(c.*);
    return out;
}

pub fn eqFold(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    }
    return true;
}

pub fn endsWithFold(s: []const u8, suffix: []const u8) bool {
    if (suffix.len > s.len) return false;
    return eqFold(s[s.len - suffix.len ..], suffix);
}

// ---------------- dates (RFC 6265 5.1.1 + IMF-fixdate) ----------------

pub const daysFromCivil = @import("sa_cookie_date.zig").daysFromCivil;

pub const Civil = @import("sa_cookie_date.zig").Civil;

pub const civilFromDays = @import("sa_cookie_date.zig").civilFromDays;

pub const isDateDelimiter = @import("sa_cookie_date.zig").isDateDelimiter;

pub const month_names = @import("sa_cookie_date.zig").month_names;

pub const parseLeadingUint = @import("sa_cookie_date.zig").parseLeadingUint;

pub const TimeOfDay = @import("sa_cookie_date.zig").TimeOfDay;

pub const tokenTime = @import("sa_cookie_date.zig").tokenTime;

/// RFC 6265 section 5.1.1 cookie-date parser. Accepts IMF-fixdate,
/// RFC 850 and asctime shapes (and the loose variants the RFC
/// algorithm accepts). Returns null when the string is not a
/// cookie date -- callers treat that as "attribute absent".
pub const parseCookieDate = @import("sa_cookie_date.zig").parseCookieDate;

pub const weekday_names = @import("sa_cookie_date.zig").weekday_names;
pub const month_names_full = @import("sa_cookie_date.zig").month_names_full;

/// IMF-fixdate, the only date form serialization emits.
pub const formatImfFixdate = @import("sa_cookie_date.zig").formatImfFixdate;

// ---------------- matching (RFC 6265 5.1.3 / 5.1.4) ----------------

pub const hostIsIp = @import("sa_cookie_url.zig").hostIsIp;

/// RFC 6265 5.1.3 string matching: identical, or host ends with
/// "." ++ domain. When the host is an IP literal only the identical
/// form counts (a cookie domain must never suffix-match an IP).
pub const domainMatch = @import("sa_cookie_url.zig").domainMatch;

/// RFC 6265 5.1.4 path-match.
pub const pathMatch = @import("sa_cookie_url.zig").pathMatch;

/// RFC 6265 5.1.4 default-path of a request URI path.
pub const defaultPath = @import("sa_cookie_url.zig").defaultPath;

// ---------------- URL splitting (jar operations) ----------------

pub const UrlParts = @import("sa_cookie_url.zig").UrlParts;

pub const splitUrl = @import("sa_cookie_url.zig").splitUrl;

/// RFC 6265bis "potentially trustworthy origin": a secure scheme,
/// or a loopback / localhost host.
pub const originTrustworthy = @import("sa_cookie_url.zig").originTrustworthy;

pub const nowUnix = @import("sa_cookie_url.zig").nowUnix;

// ---------------- parse / serialize core ----------------

pub const ParseError = @import("sa_cookie_parse.zig").ParseError;

pub const parseMaxAge = @import("sa_cookie_parse.zig").parseMaxAge;

pub const validDomainAttr = @import("sa_cookie_parse.zig").validDomainAttr;

/// Parse one Set-Cookie header value into an owned Cookie.
/// Caller owns the returned object (alloc.destroy after deinit).
pub const parseSetCookie = @import("sa_cookie_parse.zig").parseSetCookie;

pub const serializeInto = @import("sa_cookie_parse.zig").serializeInto;

pub const serializeOwned = @import("sa_cookie_parse.zig").serializeOwned;

// ---------------- registries + last error ----------------

var cookies_mu = std.Io.Mutex.init;
var cookies_map: std.AutoHashMapUnmanaged(u64, *Cookie) = .empty;
var cookies_next: u64 = 1;

var jars_mu = std.Io.Mutex.init;
var jars_map: std.AutoHashMapUnmanaged(u64, *Jar) = .empty;
var jars_next: u64 = 1;

pub fn registerCookie(c: *Cookie) !u64 {
    cookies_mu.lockUncancelable(sio.io());
    defer cookies_mu.unlock(sio.io());
    const h = cookies_next;
    cookies_next += 1;
    try cookies_map.put(alloc, h, c);
    return h;
}

pub fn getCookie(handle: u64) ?*Cookie {
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

pub fn registerJar(j: *Jar) !u64 {
    jars_mu.lockUncancelable(sio.io());
    defer jars_mu.unlock(sio.io());
    const h = jars_next;
    jars_next += 1;
    try jars_map.put(alloc, h, j);
    return h;
}

pub fn getJar(handle: u64) ?*Jar {
    jars_mu.lockUncancelable(sio.io());
    defer jars_mu.unlock(sio.io());
    return jars_map.get(handle);
}

pub fn removeJar(handle: u64) ?*Jar {
    jars_mu.lockUncancelable(sio.io());
    defer jars_mu.unlock(sio.io());
    const kv = jars_map.fetchRemove(handle) orelse return null;
    return kv.value;
}

var last_error_buf: [512]u8 = undefined;
var last_error_len: usize = 0;

pub fn setLastError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&last_error_buf, fmt, args) catch blk: {
        last_error_len = 0;
        break :blk "";
    };
    last_error_len = msg.len;
}

pub fn clearLastError() void {
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

pub const sa_cookie_set_domain = @import("sa_cookie_set.zig").sa_cookie_set_domain;

pub const sa_cookie_set_path = @import("sa_cookie_set.zig").sa_cookie_set_path;

pub const sa_cookie_set_expires = @import("sa_cookie_set.zig").sa_cookie_set_expires;

pub const sa_cookie_set_max_age = @import("sa_cookie_set.zig").sa_cookie_set_max_age;

pub export fn sa_cookie_clear_expiry(handle: u64) i32 {
    const c = getCookie(handle) orelse return ERR_HANDLE;
    c.expires_at = null;
    c.max_age = null;
    return OK;
}

pub const sa_cookie_set_secure = @import("sa_cookie_set.zig").sa_cookie_set_secure;

pub const sa_cookie_set_http_only = @import("sa_cookie_set.zig").sa_cookie_set_http_only;

pub const sa_cookie_set_partitioned = @import("sa_cookie_set.zig").sa_cookie_set_partitioned;

pub const sa_cookie_set_same_site = @import("sa_cookie_set.zig").sa_cookie_set_same_site;

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
pub const parseHeaderPair = @import("sa_cookie_header.zig").parseHeaderPair;

pub const sa_cookie_header_pair_count = @import("sa_cookie_header.zig").sa_cookie_header_pair_count;

pub const sa_cookie_header_pair_at = @import("sa_cookie_header.zig").sa_cookie_header_pair_at;

// ---------------- jar layer ----------------

pub const Jar = @import("sa_cookie_jar.zig").Jar;

/// Insert a fully-formed entry (domain/path already resolved).
/// Replaces an existing (name, domain, path) entry in place,
/// preserving its creation sequence. Takes ownership of `entry`'s
/// strings in all outcomes.
pub const jarInsert = @import("sa_cookie_jar.zig").jarInsert;

pub const sa_cookie_jar_new = @import("sa_cookie_jar.zig").sa_cookie_jar_new;

pub const sa_cookie_jar_free = @import("sa_cookie_jar.zig").sa_cookie_jar_free;

pub const sa_cookie_jar_set_policy = @import("sa_cookie_jar.zig").sa_cookie_jar_set_policy;

pub const sa_cookie_jar_policy = @import("sa_cookie_jar.zig").sa_cookie_jar_policy;

pub const sa_cookie_jar_store = @import("sa_cookie_jar.zig").sa_cookie_jar_store;

pub const headerLessThan = @import("sa_cookie_jar.zig").headerLessThan;

pub const sa_cookie_jar_header = @import("sa_cookie_jar.zig").sa_cookie_jar_header;

pub const sa_cookie_jar_count = @import("sa_cookie_jar.zig").sa_cookie_jar_count;

pub const sa_cookie_jar_at = @import("sa_cookie_jar.zig").sa_cookie_jar_at;

pub const sa_cookie_jar_clear = @import("sa_cookie_jar.zig").sa_cookie_jar_clear;

pub const sa_cookie_jar_evict_expired = @import("sa_cookie_jar.zig").sa_cookie_jar_evict_expired;

// ---------------- Netscape cookie file persistence ----------------

pub const boolWord = @import("sa_cookie_jar.zig").boolWord;

pub const sa_cookie_jar_save = @import("sa_cookie_jar.zig").sa_cookie_jar_save;

pub const parseBoolWord = @import("sa_cookie_jar.zig").parseBoolWord;

pub const sa_cookie_jar_load = @import("sa_cookie_jar.zig").sa_cookie_jar_load;

// ---------------- http_client hooks (explicit, std-level) ----------------

pub const sa_cookie_jar_request_header = @import("sa_cookie_jar.zig").sa_cookie_jar_request_header;

pub const sa_cookie_jar_store_response = @import("sa_cookie_jar.zig").sa_cookie_jar_store_response;

// ---------------- tests ----------------

pub const expectOut = @import("sa_cookie_test.zig").expectOut;

pub const jarStore = @import("sa_cookie_test.zig").jarStore;

pub const jarHeaderEq = @import("sa_cookie_test.zig").jarHeaderEq;

pub const jarCount = @import("sa_cookie_test.zig").jarCount;
