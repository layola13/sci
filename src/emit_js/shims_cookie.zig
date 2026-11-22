const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_cookie_clear_expiry")) {
        try writer.writeAll(
            \\function sa_cookie_clear_expiry(handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  c.expires = null;
            \\  c.maxAge = null;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_domain")) {
        try writer.writeAll(
            \\function sa_cookie_domain(handle, out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  return J.outStr(out_ptr, out_len, c.hasDomain ? c.domain : null);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_domain_match")) {
        try writer.writeAll(
            \\function sa_cookie_domain_match(domain, domain_len, host, host_len, out_flag) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i32(out_flag, 0);
            \\  let d = __sa_mem_bytes(domain, domain_len);
            \\  if (d.length > 0 && d[0] === 46) d = d.subarray(1);
            \\  const h = __sa_mem_bytes(host, host_len);
            \\  __sa_store_i32(out_flag, J.domainMatch(d, h) ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_expires")) {
        try writer.writeAll(
            \\function sa_cookie_expires(handle, out_unix) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_unix, 0n);
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  if (c.expires === null) return 3;
            \\  __sa_store_i64(out_unix, BigInt(c.expires));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_flags")) {
        try writer.writeAll(
            \\function sa_cookie_flags(handle, out_secure, out_http_only, out_partitioned) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  __sa_store_i32(out_secure, c.secure ? 1 : 0);
            \\  __sa_store_i32(out_http_only, c.httpOnly ? 1 : 0);
            \\  __sa_store_i32(out_partitioned, c.partitioned ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_free")) {
        try writer.writeAll(
            \\function sa_cookie_free(handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return J.ckFree(__sa_num(handle)) ? 0 : 2;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_header_pair_at")) {
        try writer.writeAll(
            \\function sa_cookie_header_pair_at(bytes, len, index) {
            \\  const J = globalThis.__sa_jsnet;
            \\  J.ckErrClear();
            \\  const raw = __sa_mem_bytes(bytes, len);
            \\  const c = J.headerPairAt(raw, __sa_num(index));
            \\  if (c === null) return 0n;
            \\  if (c === "bad") { J.ckErrSet("cookie: invalid Cookie header pair"); return 0n; }
            \\  return BigInt(J.ckReg(c));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_header_pair_count")) {
        try writer.writeAll(
            \\function sa_cookie_header_pair_count(bytes, len, out_count) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_count, 0n);
            \\  const raw = __sa_mem_bytes(bytes, len);
            \\  const n = J.headerPairCount(raw);
            \\  if (n < 0) return 1;
            \\  __sa_store_i64(out_count, BigInt(n));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_is_expired")) {
        try writer.writeAll(
            \\function sa_cookie_is_expired(handle, now, out_flag) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i32(out_flag, 0);
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  if (c.expires !== null && c.expires <= __sa_num(now)) __sa_store_i32(out_flag, 1);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_is_host_only")) {
        try writer.writeAll(
            \\function sa_cookie_is_host_only(handle, out_flag) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i32(out_flag, 0);
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  __sa_store_i32(out_flag, c.hostOnly ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_at")) {
        try writer.writeAll(
            \\function sa_cookie_jar_at(jar, index) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 0n;
            \\  const idx = __sa_num(index);
            \\  if (idx >= j.entries.length) return 0n;
            \\  const copy = J.cloneCookie(j.entries[idx]);
            \\  copy.maxAge = null;
            \\  return BigInt(J.ckReg(copy));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_clear")) {
        try writer.writeAll(
            \\function sa_cookie_jar_clear(jar) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  j.entries.length = 0;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_count")) {
        try writer.writeAll(
            \\function sa_cookie_jar_count(jar, out_count) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_count, 0n);
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  __sa_store_i64(out_count, BigInt(j.entries.length));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_evict_expired")) {
        try writer.writeAll(
            \\function sa_cookie_jar_evict_expired(jar, now, out_removed) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_removed, 0n);
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  __sa_store_i64(out_removed, BigInt(J.jarEvict(j, __sa_num(now))));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_free")) {
        try writer.writeAll(
            \\function sa_cookie_jar_free(jar) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return J.jarFree(__sa_num(jar)) ? 0 : 2;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_header")) {
        try writer.writeAll(
            \\function sa_cookie_jar_header(jar, url, url_len, now, out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_ptr(out_ptr, 0);
            \\  __sa_store_i64(out_len, 0n);
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  const u = __sa_mem_bytes(url, url_len);
            \\  const h = J.jarHeader(j, u, __sa_num(now));
            \\  if (h === null) return 3;
            \\  return J.outStr(out_ptr, out_len, h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_load")) {
        try writer.writeAll(
            \\function sa_cookie_jar_load(jar, path, path_len, out_loaded) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_loaded, 0n);
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  const p = __sa_mem_bytes(path, path_len);
            \\  if (p.length === 0) return 1;
            \\  let data;
            \\  try {
            \\    const fs = __sa_node_builtin("node:fs");
            \\    data = new Uint8Array(fs.readFileSync(J.bToStr(p)));
            \\  } catch (e) { return 6; }
            \\  const r = J.jarLoad(j, data);
            \\  if (r.error) { J.ckErrSet(r.error); return 1; }
            \\  __sa_store_i64(out_loaded, BigInt(r.loaded));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_new")) {
        try writer.writeAll(
            \\function sa_cookie_jar_new() {
            \\  const J = globalThis.__sa_jsnet;
            \\  return BigInt(J.jarReg(J.mkJar()));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_policy")) {
        try writer.writeAll(
            \\function sa_cookie_jar_policy(jar, out_policy) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_u32(out_policy, 0);
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  __sa_store_u32(out_policy, j.policy);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_request_header")) {
        try writer.writeAll(
            \\function sa_cookie_jar_request_header(jar, url, url_len, out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_ptr(out_ptr, 0);
            \\  __sa_store_i64(out_len, 0n);
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  const u = __sa_mem_bytes(url, url_len);
            \\  const now = Math.floor(Date.now() / 1000);
            \\  const h = J.jarHeader(j, u, now);
            \\  if (h === null) return 3;
            \\  return J.outStr(out_ptr, out_len, h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_save")) {
        try writer.writeAll(
            \\function sa_cookie_jar_save(jar, path, path_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  const p = __sa_mem_bytes(path, path_len);
            \\  if (p.length === 0) return 1;
            \\  try {
            \\    const fs = __sa_node_builtin("node:fs");
            \\    fs.writeFileSync(J.bToStr(p), Buffer.from(J.jarSaveText(j)));
            \\  } catch (e) { return 6; }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_set_policy")) {
        try writer.writeAll(
            \\function sa_cookie_jar_set_policy(jar, policy) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  if (__sa_num(policy) > 2) return 1;
            \\  j.policy = __sa_num(policy);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_store")) {
        try writer.writeAll(
            \\function sa_cookie_jar_store(jar, url, url_len, set_cookie, set_cookie_len, now, out_result) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  const u = __sa_mem_bytes(url, url_len);
            \\  const sc = __sa_mem_bytes(set_cookie, set_cookie_len);
            \\  const r = J.jarStore(j, u, sc, __sa_num(now));
            \\  if (r < 0) return 1;
            \\  __sa_store_u32(out_result, r);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_jar_store_response")) {
        try writer.writeAll(
            \\function sa_cookie_jar_store_response(jar, url, url_len, set_cookie, set_cookie_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const j = J.jarGet(__sa_num(jar));
            \\  if (!j) return 2;
            \\  const u = __sa_mem_bytes(url, url_len);
            \\  const sc = __sa_mem_bytes(set_cookie, set_cookie_len);
            \\  const now = Math.floor(Date.now() / 1000);
            \\  const r = J.jarStore(j, u, sc, now);
            \\  if (r < 0) return 1;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_last_error")) {
        try writer.writeAll(
            \\function sa_cookie_last_error(out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return J.outStr(out_ptr, out_len, J.ckErrGet());
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_max_age")) {
        try writer.writeAll(
            \\function sa_cookie_max_age(handle, out_secs) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_secs, 0n);
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  if (c.maxAge === null) return 3;
            \\  __sa_store_i64(out_secs, BigInt(c.maxAge));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_name")) {
        try writer.writeAll(
            \\function sa_cookie_name(handle, out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  return J.outStr(out_ptr, out_len, c.name);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_new")) {
        try writer.writeAll(
            \\function sa_cookie_new(name, name_len, value, value_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  J.ckErrClear();
            \\  const n = __sa_mem_bytes(name, name_len);
            \\  const v = __sa_mem_bytes(value, value_len);
            \\  if (!J.validCookieName(n)) { J.ckErrSet("cookie: invalid cookie name"); return 0n; }
            \\  if (!J.validCookieValue(v)) { J.ckErrSet("cookie: invalid cookie value"); return 0n; }
            \\  return BigInt(J.ckReg(J.mkCookie(n.slice(), v.slice())));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_parse_set_cookie")) {
        try writer.writeAll(
            \\function sa_cookie_parse_set_cookie(bytes, len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  J.ckErrClear();
            \\  const raw = __sa_mem_bytes(bytes, len);
            \\  const c = J.parseSetCookie(raw);
            \\  if (!c) { J.ckErrSet("cookie: invalid Set-Cookie value"); return 0n; }
            \\  return BigInt(J.ckReg(c));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_path")) {
        try writer.writeAll(
            \\function sa_cookie_path(handle, out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  return J.outStr(out_ptr, out_len, c.hasPath ? c.path : null);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_path_match")) {
        try writer.writeAll(
            \\function sa_cookie_path_match(cookie_path, cookie_path_len, request_path, request_path_len, out_flag) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i32(out_flag, 0);
            \\  const cp = __sa_mem_bytes(cookie_path, cookie_path_len);
            \\  const rp = __sa_mem_bytes(request_path, request_path_len);
            \\  __sa_store_i32(out_flag, J.pathMatch(cp, rp) ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_same_site")) {
        try writer.writeAll(
            \\function sa_cookie_same_site(handle, out_mode) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_u32(out_mode, 0);
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  __sa_store_u32(out_mode, c.sameSite);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_serialize")) {
        try writer.writeAll(
            \\function sa_cookie_serialize(handle, out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  return J.outStr(out_ptr, out_len, J.serializeCookie(c, false));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_serialize_pair")) {
        try writer.writeAll(
            \\function sa_cookie_serialize_pair(handle, out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  return J.outStr(out_ptr, out_len, J.serializeCookie(c, true));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_set_domain")) {
        try writer.writeAll(
            \\function sa_cookie_set_domain(handle, bytes, len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  let d = __sa_mem_bytes(bytes, len);
            \\  if (d.length > 0 && d[0] === 46) d = d.subarray(1);
            \\  if (!J.validDomainAttr(d)) return 1;
            \\  c.domain = J.bLower(d).slice();
            \\  c.hasDomain = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_set_expires")) {
        try writer.writeAll(
            \\function sa_cookie_set_expires(handle, unix) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  c.expires = __sa_num(unix);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_set_http_only")) {
        try writer.writeAll(
            \\function sa_cookie_set_http_only(handle, on) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  c.httpOnly = __sa_num(on) !== 0;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_set_max_age")) {
        try writer.writeAll(
            \\function sa_cookie_set_max_age(handle, secs) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  c.maxAge = __sa_num(secs);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_set_partitioned")) {
        try writer.writeAll(
            \\function sa_cookie_set_partitioned(handle, on) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  c.partitioned = __sa_num(on) !== 0;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_set_path")) {
        try writer.writeAll(
            \\function sa_cookie_set_path(handle, bytes, len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  const p = __sa_mem_bytes(bytes, len);
            \\  if (p.length === 0 || p[0] !== 47) return 1;
            \\  for (let i = 0; i < p.length; i++) if (p[i] < 32 || p[i] === 127) return 1;
            \\  c.path = p.slice();
            \\  c.hasPath = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_set_same_site")) {
        try writer.writeAll(
            \\function sa_cookie_set_same_site(handle, mode) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  if (__sa_num(mode) > 3) return 1;
            \\  c.sameSite = __sa_num(mode);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_cookie_set_secure")) {
        try writer.writeAll(
            \\function sa_cookie_set_secure(handle, on) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  c.secure = __sa_num(on) !== 0;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    return false;
}
