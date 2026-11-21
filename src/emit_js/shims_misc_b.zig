const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_node_plugin_buffer_concat")) {
        try writer.writeAll(
            \\function sa_node_plugin_buffer_concat(argv_ptr, argc, out_ptr, out_len) {
            \\  try {
            \\    const base = __sa_addr(argv_ptr);
            \\    const n = __sa_num(argc);
            \\    let total = 0;
            \\    const parts = [];
            \\    for (let i = 0; i < n; i++) {
            \\      const p = Number(__sa_view.getBigInt64(base + i * 16, true));
            \\      const l = Number(__sa_view.getBigUint64(base + i * 16 + 8, true));
            \\      const b = __sa_mem_bytes(p, l);
            \\      parts.push(b);
            \\      total += b.length;
            \\    }
            \\    const out = new Uint8Array(total);
            \\    let w = 0;
            \\    for (const b of parts) { out.set(b, w); w += b.length; }
            \\    return __sa_node_emit(out_ptr, out_len, out);
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_crypto_hash")) {
        try writer.writeAll(
            \\function sa_node_plugin_crypto_hash(algo_ptr, algo_len, data_ptr, data_len, out_ptr, out_len) {
            \\  const c = __sa_node_builtin("node:crypto");
            \\  if (c === null) return 1;
            \\  try {
            \\    const algo = new globalThis.TextDecoder().decode(__sa_mem_bytes(algo_ptr, algo_len)).toLowerCase();
            \\    if (algo !== "sha256" && algo !== "sha512" && algo !== "sha1" && algo !== "md5") return 2;
            \\    const h = c.createHash(algo);
            \\    h.update(__sa_mem_bytes(data_ptr, data_len));
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(h.digest("hex")));
            \\  } catch (e) { return 2; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_crypto_random_bytes")) {
        try writer.writeAll(
            \\function sa_node_plugin_crypto_random_bytes(size, out_ptr) {
            \\  if (!__sa_policy_unit('random')) return 10;
            \\  const c = __sa_node_builtin("node:crypto");
            \\  if (c === null) return 1;
            \\  try {
            \\    const n = __sa_num(size);
            \\    const b = c.randomBytes(n);
            \\    const p = __sa_alloc(b.length);
            \\    __sa_u8.set(b, p);
            \\    __sa_store_i64(out_ptr, p);
            \\    return 0;
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_free_buffer")) {
        try writer.writeAll(
            \\function sa_node_plugin_free_buffer(ptr, len) { __sa_free(ptr); return 0; }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_path_dirname")) {
        try writer.writeAll(
            \\function sa_node_plugin_path_dirname(path_ptr, path_len, out_ptr, out_len) {
            \\  const pathmod = __sa_node_builtin("node:path");
            \\  if (pathmod === null) return 1;
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pathmod.posix.dirname(s)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_path_extname")) {
        try writer.writeAll(
            \\function sa_node_plugin_path_extname(path_ptr, path_len, out_ptr, out_len) {
            \\  const pathmod = __sa_node_builtin("node:path");
            \\  if (pathmod === null) return 1;
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pathmod.posix.extname(s)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_path_is_absolute")) {
        try writer.writeAll(
            \\function sa_node_plugin_path_is_absolute(path_ptr, path_len, out_bool) {
            \\  const pathmod = __sa_node_builtin("node:path");
            \\  if (pathmod === null) return 1;
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    __sa_store_i32(out_bool, pathmod.posix.isAbsolute(s) ? 1 : 0);
            \\    return 0;
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_path_join")) {
        try writer.writeAll(
            \\function sa_node_plugin_path_join(argv_ptr, argc, out_ptr, out_len) {
            \\  const pathmod = __sa_node_builtin("node:path");
            \\  if (pathmod === null) return 1;
            \\  try {
            \\    const base = __sa_addr(argv_ptr);
            \\    const n = __sa_num(argc);
            \\    const parts = [];
            \\    for (let i = 0; i < n; i++) {
            \\      const p = Number(__sa_view.getBigInt64(base + i * 16, true));
            \\      const l = Number(__sa_view.getBigUint64(base + i * 16 + 8, true));
            \\      parts.push(new globalThis.TextDecoder().decode(__sa_mem_bytes(p, l)));
            \\    }
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pathmod.posix.join(...parts)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_path_normalize")) {
        try writer.writeAll(
            \\function sa_node_plugin_path_normalize(path_ptr, path_len, out_ptr, out_len) {
            \\  const pathmod = __sa_node_builtin("node:path");
            \\  if (pathmod === null) return 1;
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pathmod.posix.normalize(s)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_punycode_decode")) {
        try writer.writeAll(
            \\function sa_node_plugin_punycode_decode(data_ptr, data_len, out_ptr, out_len) {
            \\  const pu = __sa_node_builtin("punycode");
            \\  if (pu === null) return 1;
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pu.decode(s)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_punycode_encode")) {
        try writer.writeAll(
            \\function sa_node_plugin_punycode_encode(data_ptr, data_len, out_ptr, out_len) {
            \\  const pu = __sa_node_builtin("punycode");
            \\  if (pu === null) return 1;
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pu.encode(s)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_querystring_escape")) {
        try writer.writeAll(
            \\function sa_node_plugin_querystring_escape(data_ptr, data_len, out_ptr, out_len) {
            \\  const qs = __sa_node_builtin("node:querystring");
            \\  if (qs === null) return 1;
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(qs.escape(s)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_node_plugin_querystring_unescape")) {
        try writer.writeAll(
            \\function sa_node_plugin_querystring_unescape(data_ptr, data_len, out_ptr, out_len) {
            \\  const qs = __sa_node_builtin("node:querystring");
            \\  if (qs === null) return 1;
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(qs.unescape(s)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_bool")) {
        try writer.writeAll(
            \\function sa_fmt_bool(value) {
            \\  return __sa_buf_open(new globalThis.TextEncoder().encode(__sa_num(value) ? "true" : "false"));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_bool_into")) {
        try writer.writeAll(
            \\function sa_fmt_bool_into(value, out, out_cap, out_len) {
            \\  const text = __sa_num(value) ? "true" : "false";
            \\  __sa_store_i64(out_len, text.length);
            \\  const cap = __sa_num(out_cap);
            \\  if (cap === 0) return 0;
            \\  if (cap < text.length) return 9;
            \\  const a = __sa_addr(out);
            \\  for (let i = 0; i < text.length; i++) __sa_u8[a + i] = text.charCodeAt(i);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_buffer_data")) {
        try writer.writeAll(
            \\function sa_fmt_buffer_data(handle) {
            \\  const b = __sa_buf_get(handle);
            \\  if (b === null) return 0;
            \\  const p = __sa_alloc(b.length);
            \\  __sa_u8.set(b, p);
            \\  return p;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_buffer_free")) {
        try writer.writeAll(
            \\function sa_fmt_buffer_free(handle) { __sa_buffers.delete(__sa_num(handle)); return 0; }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_buffer_len")) {
        try writer.writeAll(
            \\function sa_fmt_buffer_len(handle) {
            \\  const b = __sa_buf_get(handle);
            \\  return b === null ? 0n : BigInt(b.length);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_bytes")) {
        try writer.writeAll(
            \\function sa_fmt_bytes(buf, len) { return __sa_buf_open(__sa_mem_bytes(buf, len)); }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_bytes_into")) {
        try writer.writeAll(
            \\function sa_fmt_bytes_into(buf, len, out, out_cap, out_len) {
            \\  const n = __sa_num(len);
            \\  __sa_store_i64(out_len, n);
            \\  const cap = __sa_num(out_cap);
            \\  if (cap === 0) return 0;
            \\  if (cap < n) return 9;
            \\  const s = __sa_addr(buf), d = __sa_addr(out);
            \\  __sa_u8.copyWithin(d, s, s + n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_f64")) {
        try writer.writeAll(
            \\function sa_fmt_f64(value, precision) {
            \\  const text = __sa_fmt_f64_str(value, precision);
            \\  if (text === null) return 0n;
            \\  return __sa_buf_open(new globalThis.TextEncoder().encode(text));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_f64_into")) {
        try writer.writeAll(
            \\function sa_fmt_f64_into(value, precision, out, out_cap, out_len) {
            \\  const text = __sa_fmt_f64_str(value, precision);
            \\  if (text === null) return 1;
            \\  const n = text.length;
            \\  __sa_store_i64(out_len, n);
            \\  const cap = __sa_num(out_cap);
            \\  if (cap === 0) return 0;
            \\  if (cap < n) return 9;
            \\  const a = __sa_addr(out);
            \\  for (let i = 0; i < n; i++) __sa_u8[a + i] = text.charCodeAt(i);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_i64")) {
        try writer.writeAll(
            \\function sa_fmt_i64(value, base) {
            \\  const b = __sa_num(base);
            \\  const v = BigInt.asIntN(64, BigInt(value));
            \\  let text = null;
            \\  if (b === 2 || b === 8 || b === 10) text = v.toString(b);
            \\  else if (b === 16) text = v.toString(16);
            \\  else if (b === 17) text = v.toString(16).toUpperCase();
            \\  if (text === null) return 0n;
            \\  return __sa_buf_open(new globalThis.TextEncoder().encode(text));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_i64_into")) {
        try writer.writeAll(
            \\function sa_fmt_i64_into(value, base, out, out_cap, out_len) {
            \\  const b = __sa_num(base);
            \\  const v = BigInt.asIntN(64, BigInt(value));
            \\  let text;
            \\  if (b === 2 || b === 8 || b === 10) text = v.toString(b);
            \\  else if (b === 16) text = v.toString(16);
            \\  else if (b === 17) text = v.toString(16).toUpperCase();
            \\  else return 1;
            \\  __sa_store_i64(out_len, text.length);
            \\  const cap = __sa_num(out_cap);
            \\  if (cap === 0) return 0;
            \\  if (cap < text.length) return 9;
            \\  const a = __sa_addr(out);
            \\  for (let i = 0; i < text.length; i++) __sa_u8[a + i] = text.charCodeAt(i);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_u64")) {
        try writer.writeAll(
            \\function sa_fmt_u64(value, base) {
            \\  const b = __sa_num(base);
            \\  const v = BigInt.asUintN(64, BigInt(value));
            \\  let text = null;
            \\  if (b === 2 || b === 8 || b === 10) text = v.toString(b);
            \\  else if (b === 16) text = v.toString(16);
            \\  else if (b === 17) text = v.toString(16).toUpperCase();
            \\  if (text === null) return 0n;
            \\  return __sa_buf_open(new globalThis.TextEncoder().encode(text));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fmt_u64_into")) {
        try writer.writeAll(
            \\function sa_fmt_u64_into(value, base, out, out_cap, out_len) {
            \\  const b = __sa_num(base);
            \\  const v = BigInt.asUintN(64, BigInt(value));
            \\  let text;
            \\  if (b === 2 || b === 8 || b === 10) text = v.toString(b);
            \\  else if (b === 16) text = v.toString(16);
            \\  else if (b === 17) text = v.toString(16).toUpperCase();
            \\  else return 1;
            \\  __sa_store_i64(out_len, text.length);
            \\  const cap = __sa_num(out_cap);
            \\  if (cap === 0) return 0;
            \\  if (cap < text.length) return 9;
            \\  const a = __sa_addr(out);
            \\  for (let i = 0; i < text.length; i++) __sa_u8[a + i] = text.charCodeAt(i);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_date")) {
        try writer.writeAll("function sa_time_get_date(ms) { return __sa_civil(ms)[2]; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_day")) {
        try writer.writeAll("function sa_time_get_day(ms) { const d = __sa_civil(ms)[7]; return __sa_modfloor(d + 4n, 7n); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_day")) {
        try writer.writeAll("function sa_time_get_day(ms) { const d = __sa_civil(ms)[7]; return __sa_modfloor(d + 4n, 7n); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_full_year")) {
        try writer.writeAll("function sa_time_get_full_year(ms) { return __sa_civil(ms)[0]; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_hours")) {
        try writer.writeAll("function sa_time_get_hours(ms) { return __sa_civil(ms)[3]; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_milliseconds")) {
        try writer.writeAll("function sa_time_get_milliseconds(ms) { return __sa_civil(ms)[6]; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_minutes")) {
        try writer.writeAll("function sa_time_get_minutes(ms) { return __sa_civil(ms)[4]; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_month")) {
        try writer.writeAll("function sa_time_get_month(ms) { return __sa_civil(ms)[1] - 1n; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_get_seconds")) {
        try writer.writeAll("function sa_time_get_seconds(ms) { return __sa_civil(ms)[5]; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_instant_ns")) {
        try writer.writeAll(
            \\function sa_time_instant_ns() { if (!__sa_policy_unit('time')) return 0n; return BigInt.asUintN(64, BigInt(globalThis.Date.now()) * 1000000n); }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_parse_iso")) {
        try writer.writeAll(
            \\function sa_time_parse_iso(iso_ptr, iso_len, out_ms) {
            \\  __sa_store_i64(out_ms, 0n);
            \\  const bytes = __sa_mem_bytes(iso_ptr, iso_len);
            \\  let p = 0;
            \\  const digits = (n) => {
            \\    if (p + n > bytes.length) return null;
            \\    let v = 0n;
            \\    for (let i = 0; i < n; i++) {
            \\      const c = bytes[p + i];
            \\      if (c < 48 || c > 57) return null;
            \\      v = v * 10n + BigInt(c - 48);
            \\    }
            \\    p += n;
            \\    return v;
            \\  };
            \\  const year = digits(4); if (year === null) return 1;
            \\  if (p >= bytes.length || bytes[p] !== 45) return 1; p += 1;
            \\  const month = digits(2); if (month === null) return 1;
            \\  if (p >= bytes.length || bytes[p] !== 45) return 1; p += 1;
            \\  const day = digits(2); if (day === null) return 1;
            \\  let hour = 0n, minute = 0n, second = 0n, milli = 0n;
            \\  if (p < bytes.length) {
            \\    const t = bytes[p];
            \\    if (t !== 84 && t !== 116 && t !== 32) return 1; p += 1;
            \\    hour = digits(2); if (hour === null) return 1;
            \\    if (p >= bytes.length || bytes[p] !== 58) return 1; p += 1;
            \\    minute = digits(2); if (minute === null) return 1;
            \\    if (p >= bytes.length || bytes[p] !== 58) return 1; p += 1;
            \\    second = digits(2); if (second === null) return 1;
            \\    if (p < bytes.length && bytes[p] === 46) {
            \\      p += 1;
            \\      const fs = p;
            \\      while (p < bytes.length && bytes[p] >= 48 && bytes[p] <= 57) p += 1;
            \\      const fl = p - fs;
            \\      if (fl === 0 || fl > 3) return 1;
            \\      let f = 0n;
            \\      for (let i = fs; i < p; i++) f = f * 10n + BigInt(bytes[i] - 48);
            \\      milli = fl === 1 ? f * 100n : fl === 2 ? f * 10n : f;
            \\    }
            \\  }
            \\  let off = 0n;
            \\  if (p < bytes.length) {
            \\    const z = bytes[p];
            \\    if (z === 90 || z === 122) { p += 1; }
            \\    else if (z === 43 || z === 45) {
            \\      const neg = z === 45; p += 1;
            \\      const oh = digits(2); if (oh === null) return 1;
            \\      if (p >= bytes.length || bytes[p] !== 58) return 1; p += 1;
            \\      const om = digits(2); if (om === null) return 1;
            \\      if (oh > 23n || om > 59n) return 1;
            \\      off = oh * 60n + om;
            \\      if (neg) off = -off;
            \\    } else return 1;
            \\  }
            \\  if (p !== bytes.length) return 1;
            \\  if (month < 1n || month > 12n) return 1;
            \\  const leap = __sa_modfloor(year, 4n) === 0n && (__sa_modfloor(year, 100n) !== 0n || __sa_modfloor(year, 400n) === 0n);
            \\  const dim = (month === 1n || month === 3n || month === 5n || month === 7n || month === 8n || month === 10n || month === 12n) ? 31n
            \\    : (month === 4n || month === 6n || month === 9n || month === 11n) ? 30n : (leap ? 29n : 28n);
            \\  if (day < 1n || day > dim) return 1;
            \\  if (hour > 23n || minute > 59n || second > 59n) return 1;
            \\  const y = month <= 2n ? year - 1n : year;
            \\  const era = y >= 0n ? __sa_divfloor(y, 400n) : __sa_divfloor(y - 399n, 400n);
            \\  const yoe = y - era * 400n;
            \\  const mp = __sa_modfloor(month - 3n, 12n);
            \\  const doy = __sa_divfloor(153n * mp + 2n, 5n) + day - 1n;
            \\  const doe = yoe * 365n + __sa_divfloor(yoe, 4n) - __sa_divfloor(yoe, 100n) + doy;
            \\  const days = era * 146097n + doe - 719468n;
            \\  __sa_store_i64(out_ms, ((days * 86400n + hour * 3600n + minute * 60n + second) * 1000n + milli) - off * 60000n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_set_field")) {
        try writer.writeAll(
            \\function sa_time_set_field(ms, field, value) {
            \\  const c = __sa_civil(ms);
            \\  let y = c[0], mo = c[1], d = c[2];
            \\  let tod = c[3] * 3600000n + c[4] * 60000n + c[5] * 1000n + c[6];
            \\  const v = BigInt.asIntN(64, BigInt(__sa_num(value)));
            \\  const f = __sa_num(field);
            \\  if (f === 0) y = v;
            \\  else if (f === 1) { const tm = y * 12n + v; y = __sa_divfloor(tm, 12n); mo = __sa_modfloor(tm, 12n) + 1n; }
            \\  else if (f === 2) d = v;
            \\  else if (f === 3) tod = v * 3600000n + __sa_modfloor(tod, 3600000n);
            \\  else if (f === 4) tod = (tod - __sa_modfloor(tod, 3600000n)) + v * 60000n + __sa_modfloor(tod, 60000n);
            \\  else if (f === 5) tod = (tod - __sa_modfloor(tod, 60000n)) + v * 1000n + __sa_modfloor(tod, 1000n);
            \\  else if (f === 6) tod = tod - __sa_modfloor(tod, 1000n) + v;
            \\  else return BigInt.asIntN(64, (typeof ms === "bigint") ? ms : BigInt(Math.trunc(+ms)));
            \\  const tm2 = y * 12n + (mo - 1n);
            \\  const y2 = __sa_divfloor(tm2, 12n);
            \\  const m2 = __sa_modfloor(tm2, 12n) + 1n;
            \\  const yp = m2 <= 2n ? y2 - 1n : y2;
            \\  const era = yp >= 0n ? __sa_divfloor(yp, 400n) : __sa_divfloor(yp - 399n, 400n);
            \\  const yoe = yp - era * 400n;
            \\  const mp = __sa_modfloor(m2 - 3n, 12n);
            \\  const doy = __sa_divfloor(153n * mp + 2n, 5n);
            \\  const doe = yoe * 365n + __sa_divfloor(yoe, 4n) - __sa_divfloor(yoe, 100n) + doy;
            \\  const days = era * 146097n + doe - 719468n + (d - 1n);
            \\  const total = days + __sa_divfloor(tod, 86400000n);
            \\  const norm = tod - __sa_divfloor(tod, 86400000n) * 86400000n;
            \\  return BigInt.asIntN(64, (total * 86400n) * 1000n + norm);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_sleep_ms")) {
        try writer.writeAll("function sa_time_sleep_ms(ms) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_sleep_ns")) {
        try writer.writeAll("function sa_time_sleep_ns(ns) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_unix_ms")) {
        try writer.writeAll(
            \\function sa_time_unix_ms() { if (!__sa_policy_unit('time')) return 0n; return BigInt.asIntN(64, BigInt(globalThis.Date.now())); }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_unix_ns")) {
        try writer.writeAll(
            \\function sa_time_unix_ns() { return BigInt.asIntN(64, BigInt(globalThis.Date.now()) * 1000000n); }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_time_unix_s")) {
        try writer.writeAll(
            \\function sa_time_unix_s() { return BigInt.asIntN(64, BigInt(Math.floor(globalThis.Date.now() / 1000))); }
            \\
        );
        return true;
    }
    return false;
}
