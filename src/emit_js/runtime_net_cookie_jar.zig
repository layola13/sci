// JS runtime chunk (moved from src/emit_js.zig).
// Pure data: the emitted JS source text for one runtime piece.
// Part of jsnet_runtime_js; concatenated with the other part in emit_js.zig.
pub const jsnet_runtime_js_cookie_jar =
    \\// ---- sa2js net runtime chunk (BP wave: cookie / tls-config / net-slice / netinfo) ----
    \\// Emitted ONCE per generated program that declares any BP net shim (see the
    \\// gate after writeRuntimeHeader in emit_js.zig). Pure functions operate on
    \\// Uint8Array byte strings (latin1-exact); shims adapt linear memory <-> bytes.
    \\// Cookie semantics mirror src/runtime/sa_cookie.zig exactly (RFC 6265);
    \\// TLS verification modes mirror src/runtime/sa_tls_client.zig.
    \\globalThis.__sa_jsnet = globalThis.__sa_jsnet || (function () {
    \\  "use strict";
    \\  // ---------- byte helpers ----------
    \\  function bLen(b) { return b.length; }
    \\  function bEq(a, b) {
    \\    if (a.length !== b.length) return false;
    \\    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    \\    return true;
    \\  }
    \\  function bLower(b) {
    \\    const o = new Uint8Array(b.length);
    \\    for (let i = 0; i < b.length; i++) { const c = b[i]; o[i] = (c >= 65 && c <= 90) ? c + 32 : c; }
    \\    return o;
    \\  }
    \\  function bEqFold(a, b) { return bEq(bLower(a), bLower(b)); }
    \\  function bEndsWithFold(s, suf) {
    \\    if (suf.length > s.length) return false;
    \\    return bEqFold(s.subarray(s.length - suf.length), suf);
    \\  }
    \\  function bTrimOws(b) {
    \\    let a = 0, z = b.length;
    \\    while (a < z && (b[a] === 32 || b[a] === 9)) a++;
    \\    while (z > a && (b[z - 1] === 32 || b[z - 1] === 9)) z--;
    \\    return b.subarray(a, z);
    \\  }
    \\  function bIndexOf(b, byte, from) {
    \\    for (let i = (from || 0); i < b.length; i++) if (b[i] === byte) return i;
    \\    return -1;
    \\  }
    \\  function bFromStr(s) {
    \\    const o = new Uint8Array(s.length);
    \\    for (let i = 0; i < s.length; i++) o[i] = s.charCodeAt(i) & 255;
    \\    return o;
    \\  }
    \\  function bToStr(b) {
    \\    let s = "";
    \\    for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
    \\    return s;
    \\  }
    \\  function bConcat(parts) {
    \\    let n = 0;
    \\    for (const p of parts) n += p.length;
    \\    const o = new Uint8Array(n);
    \\    let off = 0;
    \\    for (const p of parts) { o.set(p, off); off += p.length; }
    \\    return o;
    \\  }
    \\  function isDigit(c) { return c >= 48 && c <= 57; }
    \\  function isCtl(c) { return c < 32 || c === 127; }
    \\  function isTokenChar(c) {
    \\    if (c >= 48 && c <= 57) return true;
    \\    if (c >= 65 && c <= 90) return true;
    \\    if (c >= 97 && c <= 122) return true;
    \\    return c === 33 || c === 35 || c === 36 || c === 37 || c === 38 || c === 39 ||
    \\      c === 42 || c === 43 || c === 45 || c === 46 || c === 94 || c === 95 ||
    \\      c === 96 || c === 124 || c === 126;
    \\  }
    \\  function isCookieOctet(c) {
    \\    return c === 33 || (c >= 35 && c <= 43) || (c >= 45 && c <= 58) ||
    \\      (c >= 60 && c <= 91) || (c >= 93 && c <= 126);
    \\  }
    \\  function validCookieName(b) {
    \\    if (b.length === 0) return false;
    \\    for (let i = 0; i < b.length; i++) if (!isTokenChar(b[i])) return false;
    \\    return true;
    \\  }
    \\  function validCookieValue(b) {
    \\    for (let i = 0; i < b.length; i++) if (!isCookieOctet(b[i])) return false;
    \\    return true;
    \\  }
    \\  function validDomainAttr(b) {
    \\    if (b.length === 0) return false;
    \\    for (let i = 0; i < b.length; i++) {
    \\      const c = b[i];
    \\      const ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
    \\        c === 45 || c === 46 || c === 95;
    \\      if (!ok) return false;
    \\    }
    \\    return true;
    \\  }
    \\  // ---------- dates (RFC 6265 5.1.1 + IMF-fixdate) ----------
    \\  function daysFromCivil(y0, m, d) {
    \\    let y = y0;
    \\    if (m <= 2) y -= 1;
    \\    const era = Math.floor(y / 400);
    \\    const yoe = y - era * 400;
    \\    const mp = (m > 2) ? m - 3 : m + 9;
    \\    const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
    \\    const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    \\    return era * 146097 + doe - 719468;
    \\  }
    \\  function civilFromDays(z0) {
    \\    const z = z0 + 719468;
    \\    const era = Math.floor(z / 146097);
    \\    const doe = z - era * 146097;
    \\    const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
    \\    const y = yoe + era * 400;
    \\    const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
    \\    const mp = Math.floor((5 * doy + 2) / 153);
    \\    const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
    \\    const m = (mp < 10) ? mp + 3 : mp - 9;
    \\    return { year: (m <= 2) ? y + 1 : y, month: m, day: d };
    \\  }
    \\  function isDateDelimiter(c) {
    \\    return c === 9 || (c >= 32 && c <= 47) || (c >= 59 && c <= 64) ||
    \\      (c >= 91 && c <= 96) || (c >= 123 && c <= 126);
    \\  }
    \\  const MONTH3 = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
    \\  function parseLeadingUint(tok, maxDigits) {
    \\    let v = 0, n = 0;
    \\    while (n < tok.length && n < maxDigits && isDigit(tok[n])) { v = v * 10 + (tok[n] - 48); n++; }
    \\    if (n === 0) return null;
    \\    return { value: v, digits: n };
    \\  }
    \\  function tokenTime(tok) {
    \\    const h = parseLeadingUint(tok, 2);
    \\    if (!h) return null;
    \\    let rest = tok.subarray(h.digits);
    \\    if (rest.length === 0 || rest[0] !== 58) return null;
    \\    rest = rest.subarray(1);
    \\    const m = parseLeadingUint(rest, 2);
    \\    if (!m) return null;
    \\    rest = rest.subarray(m.digits);
    \\    if (rest.length === 0 || rest[0] !== 58) return null;
    \\    rest = rest.subarray(1);
    \\    const s = parseLeadingUint(rest, 2);
    \\    if (!s) return null;
    \\    return { h: h.value, m: m.value, s: s.value };
    \\  }
    \\  function parseCookieDate(b) {
    \\    let time = null, day = null, month = null, year = null;
    \\    let i = 0;
    \\    while (i < b.length) {
    \\      while (i < b.length && isDateDelimiter(b[i])) i++;
    \\      if (i >= b.length) break;
    \\      const start = i;
    \\      while (i < b.length && !isDateDelimiter(b[i])) i++;
    \\      const tok = b.subarray(start, i);
    \\      if (time === null) {
    \\        const t = tokenTime(tok);
    \\        if (t) { time = t; continue; }
    \\      }
    \\      if (day === null) {
    \\        const d = parseLeadingUint(tok, 2);
    \\        if (d && (d.digits === tok.length || !isDigit(tok[d.digits]))) { day = d.value; continue; }
    \\      }
    \\      if (month === null && tok.length >= 3) {
    \\        const first3 = bLower(tok.subarray(0, 3));
    \\        let mo = null;
    \\        for (let k = 0; k < 12; k++) {
    \\          if (bEq(first3, bFromStr(MONTH3[k]))) { mo = k + 1; break; }
    \\        }
    \\        if (mo !== null) { month = mo; continue; }
    \\      }
    \\      if (year === null) {
    \\        const y = parseLeadingUint(tok, 4);
    \\        if (y && y.digits >= 2 && (y.digits === tok.length || !isDigit(tok[y.digits]))) {
    \\          let v = y.value;
    \\          if (y.digits === 2) v += (v >= 70) ? 1900 : 2000;
    \\          year = v;
    \\          continue;
    \\        }
    \\      }
    \\    }
    \\    if (time === null || day === null || month === null || year === null) return null;
    \\    if (day < 1 || day > 31) return null;
    \\    if (year < 1601) return null;
    \\    if (time.h > 23 || time.m > 59 || time.s > 59) return null;
    \\    return daysFromCivil(year, month, day) * 86400 + time.h * 3600 + time.m * 60 + time.s;
    \\  }
    \\  const WEEKDAY = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    \\  const MONTHFULL = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    \\  function pad2(n) { return (n < 10 ? "0" : "") + n; }
    \\  function pad4(n) { let s = String(n); while (s.length < 4) s = "0" + s; return s; }
    \\  function formatImfFixdate(unix) {
    \\    const days = Math.floor(unix / 86400);
    \\    let rem = unix - days * 86400;
    \\    const c = civilFromDays(days);
    \\    const wd = ((days + 4) % 7 + 7) % 7;
    \\    const hh = Math.floor(rem / 3600); rem -= hh * 3600;
    \\    const mm = Math.floor(rem / 60); const ss = rem - mm * 60;
    \\    const ystr = (c.year >= 0 && c.year <= 9999) ? pad4(c.year) : String(c.year);
    \\    return bFromStr(WEEKDAY[wd] + ", " + pad2(c.day) + " " + MONTHFULL[c.month - 1] + " " +
    \\      ystr + " " + pad2(hh) + ":" + pad2(mm) + ":" + pad2(ss) + " GMT");
    \\  }
    \\
    \\  // ---------- cookie value layer ----------
    \\  function mkCookie(name, value) {
    \\    return { name: name, value: value, domain: new Uint8Array(0), hasDomain: false,
    \\      hostOnly: false, path: new Uint8Array(0), hasPath: false, expires: null,
    \\      maxAge: null, secure: false, httpOnly: false, partitioned: false, sameSite: 0, seq: 0 };
    \\  }
    \\  function cloneCookie(c) {
    \\    const o = mkCookie(c.name.slice(), c.value.slice());
    \\    o.domain = c.domain.slice(); o.hasDomain = c.hasDomain; o.hostOnly = c.hostOnly;
    \\    o.path = c.path.slice(); o.hasPath = c.hasPath; o.expires = c.expires;
    \\    o.maxAge = c.maxAge; o.secure = c.secure; o.httpOnly = c.httpOnly;
    \\    o.partitioned = c.partitioned; o.sameSite = c.sameSite; o.seq = c.seq;
    \\    return o;
    \\  }
    \\  function parseMaxAge(b) {
    \\    if (b.length === 0) return null;
    \\    let idx = 0, neg = false;
    \\    if (b[0] === 45) { neg = true; idx = 1; }
    \\    if (idx >= b.length) return null;
    \\    let v = 0;
    \\    const cap = 1 << 62;
    \\    while (idx < b.length) {
    \\      const c = b[idx];
    \\      if (!isDigit(c)) return null;
    \\      const d = c - 48;
    \\      v = (v >= Math.floor((cap - 9) / 10)) ? cap : v * 10 + d;
    \\      idx++;
    \\    }
    \\    return neg ? -v : v;
    \\  }
    \\  function parseSetCookie(raw) {
    \\    const firstSemi = bIndexOf(raw, 59, 0);
    \\    const pairEnd = (firstSemi < 0) ? raw.length : firstSemi;
    \\    const pair = bTrimOws(raw.subarray(0, pairEnd));
    \\    const eq = bIndexOf(pair, 61, 0);
    \\    if (eq < 0) return null;
    \\    const name = bTrimOws(pair.subarray(0, eq));
    \\    if (!validCookieName(name)) return null;
    \\    let value = bTrimOws(pair.subarray(eq + 1));
    \\    if (value.length >= 2 && value[0] === 34 && value[value.length - 1] === 34) {
    \\      value = value.subarray(1, value.length - 1);
    \\    }
    \\    if (!validCookieValue(value)) return null;
    \\    const cookie = mkCookie(name.slice(), value.slice());
    \\    if (firstSemi >= 0) {
    \\      let pos = firstSemi + 1;
    \\      while (pos <= raw.length) {
    \\        const next = bIndexOf(raw, 59, pos);
    \\        const segEnd = (next < 0) ? raw.length : next;
    \\        const attr = bTrimOws(raw.subarray(pos, segEnd));
    \\        if (attr.length > 0) {
    \\          const aeq = bIndexOf(attr, 61, 0);
    \\          const aname = (aeq < 0) ? attr : bTrimOws(attr.subarray(0, aeq));
    \\          const avalue = (aeq < 0) ? new Uint8Array(0) : bTrimOws(attr.subarray(aeq + 1));
    \\          if (bEqFold(aname, bFromStr("expires"))) {
    \\            const ts = parseCookieDate(avalue);
    \\            if (ts !== null) cookie.expires = ts;
    \\          } else if (bEqFold(aname, bFromStr("max-age"))) {
    \\            const ma = parseMaxAge(avalue);
    \\            if (ma !== null) cookie.maxAge = ma;
    \\          } else if (bEqFold(aname, bFromStr("domain"))) {
    \\            let d = avalue;
    \\            if (d.length > 0 && d[0] === 46) d = d.subarray(1);
    \\            if (validDomainAttr(d)) { cookie.domain = bLower(d).slice(); cookie.hasDomain = true; }
    \\          } else if (bEqFold(aname, bFromStr("path"))) {
    \\            if (avalue.length > 0 && avalue[0] === 47) {
    \\              let bad = false;
    \\              for (let i = 0; i < avalue.length; i++) if (isCtl(avalue[i])) bad = true;
    \\              if (!bad) { cookie.path = avalue.slice(); cookie.hasPath = true; }
    \\            }
    \\          } else if (bEqFold(aname, bFromStr("secure"))) {
    \\            cookie.secure = true;
    \\          } else if (bEqFold(aname, bFromStr("httponly"))) {
    \\            cookie.httpOnly = true;
    \\          } else if (bEqFold(aname, bFromStr("partitioned"))) {
    \\            cookie.partitioned = true;
    \\          } else if (bEqFold(aname, bFromStr("samesite"))) {
    \\            if (bEqFold(avalue, bFromStr("lax"))) cookie.sameSite = 1;
    \\            else if (bEqFold(avalue, bFromStr("strict"))) cookie.sameSite = 2;
    \\            else if (bEqFold(avalue, bFromStr("none"))) cookie.sameSite = 3;
    \\          }
    \\        }
    \\        if (next < 0) break;
    \\        pos = next + 1;
    \\      }
    \\    }
    \\    return cookie;
    \\  }
    \\  function serializeCookie(c, pairOnly) {
    \\    const parts = [c.name, bFromStr("="), c.value];
    \\    if (pairOnly) return bConcat(parts);
    \\    if (c.hasDomain) parts.push(bFromStr("; Domain="), c.domain);
    \\    if (c.hasPath) parts.push(bFromStr("; Path="), c.path);
    \\    if (c.expires !== null) parts.push(bFromStr("; Expires="), formatImfFixdate(c.expires));
    \\    if (c.maxAge !== null) parts.push(bFromStr("; Max-Age=" + String(c.maxAge)));
    \\    if (c.secure) parts.push(bFromStr("; Secure"));
    \\    if (c.httpOnly) parts.push(bFromStr("; HttpOnly"));
    \\    if (c.sameSite === 1) parts.push(bFromStr("; SameSite=Lax"));
    \\    else if (c.sameSite === 2) parts.push(bFromStr("; SameSite=Strict"));
    \\    else if (c.sameSite === 3) parts.push(bFromStr("; SameSite=None"));
    \\    if (c.partitioned) parts.push(bFromStr("; Partitioned"));
    \\    return bConcat(parts);
    \\  }
    \\  function hostIsIp(host) {
    \\    if (host.length === 0) return false;
    \\    if (bIndexOf(host, 58, 0) >= 0) return true;
    \\    let parts = 0, pos = 0;
    \\    while (pos <= host.length) {
    \\      const dot = bIndexOf(host, 46, pos);
    \\      const end = (dot < 0) ? host.length : dot;
    \\      const part = host.subarray(pos, end);
    \\      if (part.length === 0 || part.length > 3) return false;
    \\      for (let i = 0; i < part.length; i++) if (!isDigit(part[i])) return false;
    \\      parts++;
    \\      if (dot < 0) break;
    \\      pos = dot + 1;
    \\    }
    \\    return parts === 4;
    \\  }
    \\  function domainMatch(domain, host) {
    \\    if (domain.length === 0 || host.length === 0) return false;
    \\    if (bEqFold(domain, host)) return true;
    \\    if (hostIsIp(host)) return false;
    \\    if (host.length <= domain.length) return false;
    \\    if (host[host.length - domain.length - 1] !== 46) return false;
    \\    return bEndsWithFold(host, domain);
    \\  }
    \\  function pathMatch(cookiePath, requestPath) {
    \\    if (cookiePath.length === 0) return false;
    \\    const rp = (requestPath.length === 0) ? bFromStr("/") : requestPath;
    \\    if (bEq(cookiePath, rp)) return true;
    \\    if (rp.length > cookiePath.length) {
    \\      let pre = true;
    \\      for (let i = 0; i < cookiePath.length; i++) if (rp[i] !== cookiePath[i]) { pre = false; break; }
    \\      if (pre) {
    \\        if (cookiePath[cookiePath.length - 1] === 47) return true;
    \\        if (rp[cookiePath.length] === 47) return true;
    \\      }
    \\    }
    \\    return false;
    \\  }
    \\  function defaultPath(uriPath) {
    \\    if (uriPath.length === 0 || uriPath[0] !== 47) return bFromStr("/");
    \\    let last = -1;
    \\    for (let i = 0; i < uriPath.length; i++) if (uriPath[i] === 47) last = i;
    \\    if (last <= 0) return bFromStr("/");
    \\    return uriPath.subarray(0, last);
    \\  }
    \\  function splitUrl(url) {
    \\    const schemeEnd = bToStr(url).indexOf("://");
    \\    if (schemeEnd < 0) return null;
    \\    const scheme = url.subarray(0, schemeEnd);
    \\    if (scheme.length === 0) return null;
    \\    for (let i = 0; i < scheme.length; i++) {
    \\      const c = scheme[i];
    \\      if (isCtl(c) || c === 32 || c === 47) return null;
    \\    }
    \\    let rest = url.subarray(schemeEnd + 3);
    \\    let authEnd = rest.length;
    \\    for (let i = 0; i < rest.length; i++) {
    \\      const c = rest[i];
    \\      if (c === 47 || c === 63 || c === 35) { authEnd = i; break; }
    \\    }
    \\    let authority = rest.subarray(0, authEnd);
    \\    rest = rest.subarray(authEnd);
    \\    let at = -1;
    \\    for (let i = 0; i < authority.length; i++) if (authority[i] === 64) at = i;
    \\    if (at >= 0) authority = authority.subarray(at + 1);
    \\    let host;
    \\    if (authority.length > 0 && authority[0] === 91) {
    \\      const close = bIndexOf(authority, 93, 0);
    \\      if (close < 0) return null;
    \\      host = authority.subarray(1, close);
    \\    } else {
    \\      const colon = bIndexOf(authority, 58, 0);
    \\      host = (colon < 0) ? authority : authority.subarray(0, colon);
    \\    }
    \\    if (host.length === 0) return null;
    \\    let path = new Uint8Array(0);
    \\    if (rest.length > 0 && rest[0] === 47) {
    \\      let pathEnd = rest.length;
    \\      for (let i = 0; i < rest.length; i++) {
    \\        const c = rest[i];
    \\        if (c === 63 || c === 35) { pathEnd = i; break; }
    \\      }
    \\      path = rest.subarray(0, pathEnd);
    \\    }
    \\    return { scheme: scheme, host: host, path: path };
    \\  }
    \\  function originTrustworthy(scheme, host) {
    \\    if (bEqFold(scheme, bFromStr("https")) || bEqFold(scheme, bFromStr("wss"))) return true;
    \\    if (bEqFold(host, bFromStr("localhost")) || bEndsWithFold(host, bFromStr(".localhost"))) return true;
    \\    if (bEq(host, bFromStr("127.0.0.1")) || bEq(host, bFromStr("::1"))) return true;
    \\    return false;
    \\  }
    \\  // ---------- cookie registries + last error ----------
    \\  const CK = { cookies: new Map(), jars: new Map(), next: 1, err: null };
    \\  function ckErrSet(msg) { CK.err = bFromStr(msg); }
    \\  function ckErrClear() { CK.err = null; }
    \\  function ckErrGet() { return CK.err; }
    \\  function ckReg(c) { const h = CK.next++; CK.cookies.set(h, c); return h; }
    \\  function ckGet(h) { return CK.cookies.get(h) || null; }
    \\  function ckFree(h) { return CK.cookies.delete(h); }
    \\  function jarReg(j) { const h = CK.next++; CK.jars.set(h, j); return h; }
    \\  function jarGet(h) { return CK.jars.get(h) || null; }
    \\  function jarFree(h) { return CK.jars.delete(h); }
    \\  function mkJar() { return { entries: [], policy: 0, nextSeq: 1 }; }
    \\  function jarFind(jar, name, domain, path) {
    \\    for (let i = 0; i < jar.entries.length; i++) {
    \\      const e = jar.entries[i];
    \\      if (bEq(e.name, name) && bEq(e.domain, domain) && bEq(e.path, path)) return i;
    \\    }
    \\    return -1;
    \\  }
    \\  function jarInsert(jar, entry) {
    \\    const idx = jarFind(jar, entry.name, entry.domain, entry.path);
    \\    if (idx >= 0) { const seq = jar.entries[idx].seq; entry.seq = seq; jar.entries[idx] = entry; return 1; }
    \\    entry.seq = jar.nextSeq++;
    \\    jar.entries.push(entry);
    \\    return 0;
    \\  }
    \\  function jarEvict(jar, now) {
    \\    let removed = 0;
    \\    for (let i = jar.entries.length - 1; i >= 0; i--) {
    \\      const e = jar.entries[i];
    \\      if (e.expires !== null && e.expires <= now) { jar.entries.splice(i, 1); removed++; }
    \\    }
    \\    return removed;
    \\  }
    \\  // returns STORE code 0..4, or -1 for call-level invalid (bad url / bad cookie)
    \\  function jarStore(jar, urlB, scB, now) {
    \\    const url = splitUrl(urlB);
    \\    if (!url) return -1;
    \\    const parsed = parseSetCookie(scB);
    \\    if (!parsed) return -1;
    \\    if (jar.policy === 1) return 4;
    \\    const hostLower = bLower(url.host);
    \\    let domain, hostOnly;
    \\    if (parsed.hasDomain && jar.policy !== 2) {
    \\      if (!domainMatch(parsed.domain, hostLower)) return 4;
    \\      domain = parsed.domain.slice(); hostOnly = false;
    \\    } else {
    \\      domain = hostLower.slice(); hostOnly = true;
    \\    }
    \\    if (parsed.secure && !originTrustworthy(url.scheme, hostLower)) return 4;
    \\    const path = parsed.hasPath ? parsed.path.slice() : defaultPath(url.path).slice();
    \\    let expires = parsed.expires;
    \\    if (parsed.maxAge !== null) expires = (parsed.maxAge <= 0) ? now : now + parsed.maxAge;
    \\    const entry = mkCookie(parsed.name.slice(), parsed.value.slice());
    \\    entry.domain = domain; entry.hasDomain = true; entry.hostOnly = hostOnly;
    \\    entry.path = path; entry.hasPath = true; entry.expires = expires;
    \\    entry.secure = parsed.secure; entry.httpOnly = parsed.httpOnly;
    \\    entry.partitioned = parsed.partitioned; entry.sameSite = parsed.sameSite;
    \\    if (expires !== null && expires <= now) {
    \\      const idx = jarFind(jar, entry.name, entry.domain, entry.path);
    \\      if (idx >= 0) { jar.entries.splice(idx, 1); return 2; }
    \\      return 3;
    \\    }
    \\    return jarInsert(jar, entry);
    \\  }
    \\  function jarHeader(jar, urlB, now) {
    \\    const url = splitUrl(urlB);
    \\    if (!url) return null;
    \\    jarEvict(jar, now);
    \\    const matches = [];
    \\    for (const e of jar.entries) {
    \\      if (e.hostOnly) { if (!bEqFold(e.domain, url.host)) continue; }
    \\      else { if (!domainMatch(e.domain, url.host)) continue; }
    \\      if (!pathMatch(e.path, url.path)) continue;
    \\      if (e.secure && !originTrustworthy(url.scheme, url.host)) continue;
    \\      matches.push(e);
    \\    }
    \\    if (matches.length === 0) return null;
    \\    matches.sort((a, b) => {
    \\      if (a.path.length !== b.path.length) return b.path.length - a.path.length;
    \\      return a.seq - b.seq;
    \\    });
    \\    const parts = [];
    \\    for (let i = 0; i < matches.length; i++) {
    \\      if (i > 0) parts.push(bFromStr("; "));
    \\      parts.push(serializeCookie(matches[i], true));
    \\    }
    \\    return bConcat(parts);
    \\  }
    \\  function jarSaveText(jar) {
    \\    const parts = [bFromStr("# Netscape HTTP Cookie File\n# Written by sa_std (sa_cookie_jar_save). HttpOnly cookies carry the #HttpOnly_ prefix.\n\n")];
    \\    for (const e of jar.entries) {
    \\      if (e.httpOnly) parts.push(bFromStr("#HttpOnly_"));
    \\      if (e.hostOnly) parts.push(e.domain);
    \\      else parts.push(bFromStr("."), e.domain);
    \\      parts.push(bFromStr("\t"), bFromStr(e.hostOnly ? "FALSE" : "TRUE"));
    \\      parts.push(bFromStr("\t"), e.path);
    \\      parts.push(bFromStr("\t"), bFromStr(e.secure ? "TRUE" : "FALSE"));
    \\      parts.push(bFromStr("\t"), bFromStr(String(e.expires === null ? 0 : e.expires)));
    \\      parts.push(bFromStr("\t"), e.name, bFromStr("\t"), e.value, bFromStr("\n"));
    \\    }
    \\    return bConcat(parts);
    \\  }
    \\  // returns { loaded } or { error } ; on error the jar is untouched
    \\  function jarLoad(jar, data) {
    \\    const pending = [];
    \\    let lineNo = 0, pos = 0;
    \\    while (pos <= data.length) {
    \\      const nl = bIndexOf(data, 10, pos);
    \\      const rawEnd = (nl < 0) ? data.length : nl;
    \\      let line = data.subarray(pos, rawEnd);
    \\      lineNo++;
    \\      if (line.length > 0 && line[line.length - 1] === 13) line = line.subarray(0, line.length - 1);
    \\      if (line.length > 0) {
    \\        let httpOnly = false;
    \\        if (line.length >= 10 && bEq(line.subarray(0, 10), bFromStr("#HttpOnly_"))) {
    \\          httpOnly = true; line = line.subarray(10);
    \\        } else if (line[0] === 35) {
    \\          line = null;
    \\        }
    \\        if (line !== null) {
    \\          const fields = [];
    \\          let fpos = 0;
    \\          while (fpos <= line.length) {
    \\            const tab = bIndexOf(line, 9, fpos);
    \\            const fend = (tab < 0) ? line.length : tab;
    \\            fields.push(line.subarray(fpos, fend));
    \\            if (tab < 0) break;
    \\            fpos = tab + 1;
    \\          }
    \\          if (fields.length > 7) return { error: "cookie: netscape line " + lineNo + " has too many fields" };
    \\          if (fields.length !== 7) return { error: "cookie: netscape line " + lineNo + " has " + fields.length + " fields, want 7" };
    \\          const flagAll = bToStr(fields[1]);
    \\          const secureWord = bToStr(fields[3]);
    \\          if (flagAll !== "TRUE" && flagAll !== "FALSE") return { error: "cookie: netscape line " + lineNo + " has a bad domain flag" };
    \\          if (secureWord !== "TRUE" && secureWord !== "FALSE") return { error: "cookie: netscape line " + lineNo + " has a bad secure flag" };
    \\          const expStr = bToStr(fields[4]);
    \\          if (!/^[+-]?\d+$/.test(expStr)) return { error: "cookie: netscape line " + lineNo + " has a bad expiry" };
    \\          let exp = null;
    \\          try {
    \\            const bv = BigInt(expStr);
    \\            if (bv > 9223372036854775807n || bv < -9223372036854775808n) return { error: "cookie: netscape line " + lineNo + " has a bad expiry" };
    \\            exp = (bv === 0n) ? null : Number(bv);
    \\          } catch (e) { return { error: "cookie: netscape line " + lineNo + " has a bad expiry" }; }
    \\          let domain = fields[0];
    \\          if (domain.length > 0 && domain[0] === 46) domain = domain.subarray(1);
    \\          if (!validDomainAttr(domain)) return { error: "cookie: netscape line " + lineNo + " has a bad domain" };
    \\          if (!validCookieName(fields[5])) return { error: "cookie: netscape line " + lineNo + " has a bad name" };
    \\          if (!validCookieValue(fields[6])) return { error: "cookie: netscape line " + lineNo + " has a bad value" };
    \\          if (fields[2].length === 0 || fields[2][0] !== 47) return { error: "cookie: netscape line " + lineNo + " has a bad path" };
    \\          const entry = mkCookie(fields[5].slice(), fields[6].slice());
    \\          entry.domain = bLower(domain).slice(); entry.hasDomain = true;
    \\          entry.hostOnly = (flagAll === "FALSE");
    \\          entry.path = fields[2].slice(); entry.hasPath = true;
    \\          entry.expires = exp; entry.secure = (secureWord === "TRUE"); entry.httpOnly = httpOnly;
    \\          pending.push(entry);
    \\        }
    \\      }
    \\      if (nl < 0) break;
    \\      pos = nl + 1;
    \\    }
    \\    let loaded = 0;
    \\    for (const e of pending) { jarInsert(jar, e); loaded++; }
    \\    return { loaded: loaded };
    \\  }
    \\  function parseHeaderPair(seg) {
    \\    const eq = bIndexOf(seg, 61, 0);
    \\    if (eq < 0) return null;
    \\    const name = bTrimOws(seg.subarray(0, eq));
    \\    if (!validCookieName(name)) return null;
    \\    let value = bTrimOws(seg.subarray(eq + 1));
    \\    if (value.length >= 2 && value[0] === 34 && value[value.length - 1] === 34) {
    \\      value = value.subarray(1, value.length - 1);
    \\    }
    \\    if (!validCookieValue(value)) return null;
    \\    return mkCookie(name.slice(), value.slice());
    \\  }
    \\  // returns count, or -1 on any bad pair
    \\  function headerPairCount(raw) {
    \\    let count = 0, pos = 0;
    \\    while (pos <= raw.length) {
    \\      const semi = bIndexOf(raw, 59, pos);
    \\      const end = (semi < 0) ? raw.length : semi;
    \\      const seg = bTrimOws(raw.subarray(pos, end));
    \\      if (seg.length > 0) {
    \\        if (!parseHeaderPair(seg)) return -1;
    \\        count++;
    \\      }
    \\      if (semi < 0) break;
    \\      pos = semi + 1;
    \\    }
    \\    return count;
    \\  }
;
