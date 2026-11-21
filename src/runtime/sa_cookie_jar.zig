const std = @import("std");
const Cookie = @import("sa_cookie.zig").Cookie;
const ERR_HANDLE = @import("sa_cookie.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_cookie.zig").ERR_INVALID;
const ERR_IO = @import("sa_cookie.zig").ERR_IO;
const ERR_NOMEM = @import("sa_cookie.zig").ERR_NOMEM;
const ERR_NOT_FOUND = @import("sa_cookie.zig").ERR_NOT_FOUND;
const OK = @import("sa_cookie.zig").OK;
const POLICY_ACCEPT_ALL = @import("sa_cookie.zig").POLICY_ACCEPT_ALL;
const POLICY_ACCEPT_NONE = @import("sa_cookie.zig").POLICY_ACCEPT_NONE;
const POLICY_HOST_ONLY = @import("sa_cookie.zig").POLICY_HOST_ONLY;
const STORE_DELETED = @import("sa_cookie.zig").STORE_DELETED;
const STORE_IGNORED_EXPIRED = @import("sa_cookie.zig").STORE_IGNORED_EXPIRED;
const STORE_REJECTED = @import("sa_cookie.zig").STORE_REJECTED;
const STORE_REPLACED = @import("sa_cookie.zig").STORE_REPLACED;
const STORE_STORED = @import("sa_cookie.zig").STORE_STORED;
const alloc = @import("sa_cookie.zig").alloc;
const constSlice = @import("sa_cookie.zig").constSlice;
const defaultPath = @import("sa_cookie.zig").defaultPath;
const domainMatch = @import("sa_cookie.zig").domainMatch;
const eqFold = @import("sa_cookie.zig").eqFold;
const getJar = @import("sa_cookie.zig").getJar;
const lowerDup = @import("sa_cookie.zig").lowerDup;
const nowUnix = @import("sa_cookie.zig").nowUnix;
const originTrustworthy = @import("sa_cookie.zig").originTrustworthy;
const parseSetCookie = @import("sa_cookie.zig").parseSetCookie;
const pathMatch = @import("sa_cookie.zig").pathMatch;
const registerCookie = @import("sa_cookie.zig").registerCookie;
const registerJar = @import("sa_cookie.zig").registerJar;
const removeJar = @import("sa_cookie.zig").removeJar;
const serializeInto = @import("sa_cookie.zig").serializeInto;
const setLastError = @import("sa_cookie.zig").setLastError;
const sio = @import("sa_cookie.zig").sio;
const splitUrl = @import("sa_cookie.zig").splitUrl;
const validCookieName = @import("sa_cookie.zig").validCookieName;
const validCookieValue = @import("sa_cookie.zig").validCookieValue;
const validDomainAttr = @import("sa_cookie.zig").validDomainAttr;

pub const Jar = struct {
    entries: std.array_list.Managed(Cookie) = std.array_list.Managed(Cookie).init(alloc),
    policy: u32 = POLICY_ACCEPT_ALL,
    next_seq: u64 = 1,
    header_buf: []u8 = "",

    pub fn deinit(self: *Jar) void {
        for (self.entries.items) |*e| e.deinit();
        self.entries.deinit();
        if (self.header_buf.len > 0) alloc.free(self.header_buf);
    }

    pub fn findEntry(self: *Jar, name: []const u8, domain: []const u8, path: []const u8) ?usize {
        for (self.entries.items, 0..) |*e, i| {
            if (std.mem.eql(u8, e.name, name) and std.mem.eql(u8, e.domain, domain) and std.mem.eql(u8, e.path, path)) {
                return i;
            }
        }
        return null;
    }

    pub fn evictExpired(self: *Jar, now: i64) usize {
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

pub fn jarInsert(jar: *Jar, entry: Cookie) !enum { stored, replaced } {
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

pub fn headerLessThan(_: void, a: *Cookie, b: *Cookie) bool {
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

pub fn boolWord(b: bool) []const u8 {
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

pub fn parseBoolWord(s: []const u8) ?bool {
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

pub export fn sa_cookie_jar_request_header(handle: u64, url_ptr: ?[*]const u8, url_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    return sa_cookie_jar_header(handle, url_ptr, url_len, nowUnix(), out_ptr, out_len);
}

pub export fn sa_cookie_jar_store_response(handle: u64, url_ptr: ?[*]const u8, url_len: u64, set_cookie_ptr: ?[*]const u8, set_cookie_len: u64) i32 {
    var result: u32 = 0;
    return sa_cookie_jar_store(handle, url_ptr, url_len, set_cookie_ptr, set_cookie_len, nowUnix(), &result);
}
