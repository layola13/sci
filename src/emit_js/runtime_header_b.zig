// JS runtime header chunk (moved from src/emit_js.zig writeRuntimeHeader).
// Pure data: the emitted JS source text for the runtime header.
pub const header_runtime_js_b =
        \\function __sa_cvt_bitcast_f64i(v) {
        \\  // int-domain source with a 64-bit target: reinterpret the bits.
        \\  // Used when the emitter statically knows the source is integral
        \\  // (plain bitcast_f64 treats Numbers as f64-domain values).
        \\  const b = (typeof v === "bigint") ? BigInt.asIntN(64, v) : BigInt(Math.trunc(+v));
        \\  __sa_bc_dv.setBigInt64(0, b, true); return __sa_bc_dv.getFloat64(0, true);
        \\}
        \\function __sa_cvt_bitcast_i32f(v) {
        \\  // float-domain f32 source reinterpreted as i32 (emitter-known).
        \\  __sa_bc_dv.setFloat32(0, +v, true); return __sa_bc_dv.getInt32(0, true);
        \\}
        \\function __sa_cvt_bitcast_u32f(v) {
        \\  __sa_bc_dv.setFloat32(0, +v, true); return __sa_bc_dv.getUint32(0, true);
        \\}
        \\function __sa_cvt_bitcast_i64b(v) {
        \\  // float-domain f64 source reinterpreted as i64 (emitter-known).
        \\  __sa_bc_dv.setFloat64(0, +v, true); return __sa_bc_dv.getBigInt64(0, true);
        \\}
        \\function __sa_cvt_bitcast_u64b(v) {
        \\  __sa_bc_dv.setFloat64(0, +v, true); return BigInt.asUintN(64, __sa_bc_dv.getBigInt64(0, true));
        \\}
        \\function __sa_divfloor(a, b) {
        \\  // Floored BigInt division (Zig @divFloor semantics).
        \\  const q = a / b, r = a % b;
        \\  if ((r !== 0n) && ((r < 0n) !== (b < 0n))) return q - 1n;
        \\  return q;
        \\}
        \\function __sa_modfloor(a, b) {
        \\  // Floored BigInt modulo (Zig @mod semantics; b > 0 in our uses).
        \\  const r = a % b;
        \\  return (r < 0n) ? r + (b < 0n ? -b : b) : r;
        \\}
        \\function __sa_civil(ms) {
        \\  // Howard Hinnant civil_from_days over unix millis (mirrors
        \\  // src/runtime/sa_std.zig civilParts). Returns
        \\  // [year, month1, day, hour, min, sec, milli, days] as BigInt.
        \\  const m = (typeof ms === "bigint") ? BigInt.asIntN(64, ms) : BigInt(Math.trunc(+ms));
        \\  const DAY = 86400000n;
        \\  const days = __sa_divfloor(m, DAY);
        \\  const dm = __sa_modfloor(m, DAY);
        \\  const z = days + 719468n;
        \\  const era = (z >= 0n) ? __sa_divfloor(z, 146097n) : __sa_divfloor(z - 146096n, 146097n);
        \\  const doe = z - era * 146097n;
        \\  const yoe = __sa_divfloor(doe - __sa_divfloor(doe, 1460n) + __sa_divfloor(doe, 36524n) - __sa_divfloor(doe, 146096n), 365n);
        \\  const y = yoe + era * 400n;
        \\  const doy = doe - (365n * yoe + __sa_divfloor(yoe, 4n) - __sa_divfloor(yoe, 100n));
        \\  const mp = __sa_divfloor(5n * doy + 2n, 153n);
        \\  const month = (mp < 10n) ? mp + 3n : mp - 9n;
        \\  return [(month <= 2n) ? y + 1n : y, month,
        \\    doy - __sa_divfloor(153n * mp + 2n, 5n) + 1n,
        \\    __sa_divfloor(dm, 3600000n),
        \\    __sa_divfloor(__sa_modfloor(dm, 3600000n), 60000n),
        \\    __sa_divfloor(__sa_modfloor(dm, 60000n), 1000n),
        \\    __sa_modfloor(dm, 1000n), days];
        \\}
        \\const __sa_buffers = new Map();
        \\let __sa_bufnext = 1;
        \\const __sa_regexes = new Map();
        \\let __sa_regexnext = 1;
        \\const __sa_regexmatches = new Map();
        \\let __sa_regexmatchnext = 1;
        \\const __sa_regexlists = new Map();
        \\let __sa_regexlistnext = 1;
        \\const __sa_regexbufs = new Map();
        \\let __sa_regexbufnext = 1;
        \\const __sa_regexsplits = new Map();
        \\let __sa_regexsplitnext = 1;
        \\const __sa_modstate = new Map();
        \\const __sa_jsonnodes = new Map();
        \\let __sa_jsonnext = 1;
        \\const __sa_jsonwriters = new Map();
        \\let __sa_jsonwriternext = 1;
        \\const __sa_jsonbufs = new Map();
        \\let __sa_jsonbufnext = 1;
        \\function __sa_json_quote(bytes, esc_uni) {
        \\  const s = new globalThis.TextDecoder().decode(bytes);
        \\  let o = '"';
        \\  for (const ch of s) {
        \\    const c = ch.codePointAt(0);
        \\    if (c === 34) o += '\\"';
        \\    else if (c === 92) o += '\\\\';
        \\    else if (c === 8) o += '\\b';
        \\    else if (c === 9) o += '\\t';
        \\    else if (c === 10) o += '\\n';
        \\    else if (c === 12) o += '\\f';
        \\    else if (c === 13) o += '\\r';
        \\    else if (c < 0x20) o += '\\u00' + c.toString(16).padStart(2, '0');
        \\    else if (esc_uni && c > 0x7f) {
        \\      if (c > 0xffff) {
        \\        const v = c - 0x10000;
        \\        o += '\\u' + (0xd800 + (v >> 10)).toString(16).padStart(4, '0');
        \\        o += '\\u' + (0xdc00 + (v & 0x3ff)).toString(16).padStart(4, '0');
        \\      } else o += '\\u' + c.toString(16).padStart(4, '0');
        \\    }
        \\    else o += ch;
        \\  }
        \\  return o + '"';
        \\}
        \\function __sa_json_f64_str(x) {
        \\  // Match native (Zig 0.17 std.json decimal shortest): 2.5->"2.5".
        \\  const v = (typeof x === "bigint") ? Number(x) : (+x);
        \\  if (Number.isNaN(v)) return '"nan"';
        \\  if (v === Infinity) return 'inf';
        \\  if (v === -Infinity) return '-inf';
        \\  return String(v).replace("e+", "e");
        \\}
        \\function __sa_jw_begin(w, open) {
        \\  if (w.result !== null) return 2;
        \\  if (w.root_done && w.stack.length === 0) return 1;
        \\  if (w.stack.length !== 0) {
        \\    const top = w.stack[w.stack.length - 1];
        \\    if (top.t === 1) {
        \\      if (!top.first) w.parts.push(',');
        \\      top.first = false;
        \\    }
        \\    // Object parents: the field key (with its comma) was emitted
        \\    // by object_field/field_* just before; push directly.
        \\  }
        \\  w.parts.push(open);
        \\  w.stack.push({ t: open === '{' ? 0 : 1, first: true });
        \\  return 0;
        \\}
        \\function __sa_jw_scalar(w, text) {
        \\  if (w.result !== null) return 2;
        \\  if (w.stack.length !== 0) {
        \\    const top = w.stack[w.stack.length - 1];
        \\    if (top.t !== 1) return 1;
        \\    if (!top.first) w.parts.push(',');
        \\    top.first = false;
        \\  } else {
        \\    if (w.root_done) return 1;
        \\    w.root_done = true;
        \\  }
        \\  w.parts.push(text);
        \\  return 0;
        \\}
        \\function __sa_jw_field(w, key_bytes) {
        \\  if (w.result !== null) return 2;
        \\  if (w.stack.length === 0) return 1;
        \\  const top = w.stack[w.stack.length - 1];
        \\  if (top.t !== 0) return 1;
        \\  if (!top.first) w.parts.push(',');
        \\  top.first = false;
        \\  w.parts.push(__sa_json_quote(key_bytes, w.esc_uni));
        \\  w.parts.push(':');
        \\  return 0;
        \\}
        \\function __sa_jw_end(w, close) {
        \\  if (w.result !== null) return 2;
        \\  if (w.stack.length === 0) return 1;
        \\  const top = w.stack.pop();
        \\  if ((close === '}' && top.t !== 0) || (close === ']' && top.t !== 1)) return 1;
        \\  w.parts.push(close);
        \\  if (w.stack.length === 0) w.root_done = true;
        \\  return 0;
        \\}
        \\function __sa_buf_open(bytes) {
        \\  // Owned byte buffer (mirrors openOwnedBuffer): handle is a u64.
        \\  const h = __sa_bufnext++;
        \\  __sa_buffers.set(h, bytes.slice());
        \\  return BigInt(h);
        \\}
        \\function __sa_buf_get(handle) {
        \\  const b = __sa_buffers.get(__sa_num(handle));
        \\  return (b !== undefined) ? b : null;
        \\}
        \\function __sa_mem_bytes(ptr, len) {
        \\  // Copy of a linear-memory range as Uint8Array.
        \\  const a = __sa_addr(ptr);
        \\  let n = __sa_num(len);
        \\  if (!(n > 0)) return new Uint8Array(0);
        \\  if (a < 0) return new Uint8Array(0);
        \\  return __sa_u8.slice(a, a + n);
        \\}
        \\function __sa_utf8_dec(bytes, idx) {
        \\  // Strict UTF-8 scalar decode (mirrors utf8ScalarAt): returns
        \\  // [scalar, width] or null (overlongs/surrogates rejected).
        \\  if (idx >= bytes.length) return null;
        \\  const b0 = bytes[idx];
        \\  if (b0 < 0x80) return [b0, 1];
        \\  let w = 0;
        \\  if (b0 >= 0xc2 && b0 <= 0xdf) w = 2;
        \\  else if (b0 >= 0xe0 && b0 <= 0xef) w = 3;
        \\  else if (b0 >= 0xf0 && b0 <= 0xf4) w = 4;
        \\  else return null;
        \\  if (idx + w > bytes.length) return null;
        \\  const b1 = bytes[idx + 1];
        \\  if (b1 < 0x80 || b1 > 0xbf) return null;
        \\  if (w === 2) return [((b0 & 0x1f) << 6) | (b1 & 0x3f), 2];
        \\  const b2 = bytes[idx + 2];
        \\  if (b2 < 0x80 || b2 > 0xbf) return null;
        \\  if (w === 3) {
        \\    if (b0 === 0xe0 && b1 < 0xa0) return null;
        \\    if (b0 === 0xed && b1 >= 0xa0) return null;
        \\    return [((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f), 3];
        \\  }
        \\  const b3 = bytes[idx + 3];
        \\  if (b3 < 0x80 || b3 > 0xbf) return null;
        \\  if (b0 === 0xf0 && b1 < 0x90) return null;
        \\  if (b0 === 0xf4 && b1 >= 0x90) return null;
        \\  return [((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f), 4];
        \\}
        \\function __sa_is_ws(b) { return b === 32 || b === 9 || b === 10 || b === 13 || b === 11 || b === 12; }
        \\function __sa_tou(v) {
        \\  // u64 wrapping conversion for index/count params (mirrors Zig
        \\  // u64 param passing: negative Numbers wrap huge, then callers
        \\  // clamp with Math.min against the real length).
        \\  const n = (typeof v === "bigint") ? v : BigInt(Math.trunc(+v));
        \\  return Number(BigInt.asUintN(64, n));
        \\}
        \\function __sa_regex_group(match, group_idx) {
        \\  const r = __sa_regexmatches.get(__sa_num(match));
        \\  if (r === undefined) return null;
        \\  const i = __sa_num(group_idx);
        \\  if (!(i >= 0) || i >= r.groups.length) return null;
        \\  const g = r.groups[i];
        \\  if (g[0] < 0 || g[1] < 0) return null;
        \\  return { rec: r, so: g[0], eo: g[1] };
        \\}
        \\function __sa_regex_collect(rec, s) {
        \\  // JS global-exec loop mirroring regexCollectMatches in sa_std.zig:
        \\  // after an empty match the search advances one position (native: one
        \\  // byte; this JS model works on decoded strings, like sa_regex_match).
        \\  const re = new RegExp(rec.re.source, rec.re.flags + "g");
        \\  const out = [];
        \\  let pos = 0;
        \\  while (pos <= s.length) {
        \\    re.lastIndex = pos;
        \\    const m = re.exec(s);
        \\    if (m === null || m.indices === undefined) break;
        \\    const groups = m.indices.map((g) => ((g === undefined) ? [-1, -1] : [g[0], g[1]]));
        \\    out.push(groups);
        \\    const st = groups[0][0], en = groups[0][1];
        \\    pos = (en === st) ? en + 1 : en;
        \\  }
        \\  return out;
        \\}
        \\function __sa_regex_group_text(text, groups, idx) {
        \\  if (idx >= groups.length) return "";
        \\  const g = groups[idx];
        \\  if (g[0] < 0 || g[1] < 0) return "";
        \\  return text.slice(g[0], g[1]);
        \\}
        \\function __sa_regex_expand(text, groups, repl) {
        \\  // Port of regexAppendExpansion in sa_std.zig (JS template rules):
        \\  // $$ literal $, $& whole match, $` before, $' after, $n/$nn groups
        \\  // (non-participating expands to nothing, out-of-range stays literal,
        \\  // $<name> stays literal).
        \\  const total = groups.length - 1;
        \\  let out = "";
        \\  let i = 0;
        \\  while (i < repl.length) {
        \\    const c = repl[i];
        \\    if (c !== "$" || i + 1 >= repl.length) { out += c; i += 1; continue; }
        \\    const n = repl[i + 1];
        \\    if (n === "$") { out += "$"; i += 2; }
        \\    else if (n === "&") { out += __sa_regex_group_text(text, groups, 0); i += 2; }
        \\    else if (n === "`") { out += text.slice(0, groups[0][0]); i += 2; }
        \\    else if (n === "'") { out += text.slice(groups[0][1]); i += 2; }
        \\    else if (n >= "1" && n <= "9") {
        \\      const d1 = n.charCodeAt(0) - 48;
        \\      let consumed = 0;
        \\      if (i + 2 < repl.length && repl[i + 2] >= "0" && repl[i + 2] <= "9") {
        \\        const nn = d1 * 10 + (repl[i + 2].charCodeAt(0) - 48);
        \\        if (nn >= 1 && nn <= total) { out += __sa_regex_group_text(text, groups, nn); consumed = 3; }
        \\      }
        \\      if (consumed === 0 && d1 <= total) { out += __sa_regex_group_text(text, groups, d1); consumed = 2; }
        \\      if (consumed === 0) { out += "$"; i += 1; } else { i += consumed; }
        \\    }
        \\    else { out += "$"; i += 1; }
        \\  }
        \\  return out;
        \\}
        \\function __sa_regex_split_pieces(rec, s, limit) {
        \\  // Port of regexSplitHandle in sa_std.zig (JS String.split semantics;
        \\  // limit caps the total piece count including inserted groups, and
        \\  // limit == 0 means no limit -- a deliberate divergence from JS).
        \\  const lim = (limit === 0) ? Infinity : limit;
        \\  const pieces = [];
        \\  const re = new RegExp(rec.re.source, rec.re.flags + "g");
        \\  if (s.length === 0) {
        \\    re.lastIndex = 0;
        \\    if (re.exec(s) === null) pieces.push([0, 0]);
        \\    return pieces;
        \\  }
        \\  let p = 0, q = 0, done = false;
        \\  while (!done && q <= s.length) {
        \\    re.lastIndex = q;
        \\    const m = re.exec(s);
        \\    if (m === null || m.indices === undefined) break;
        \\    const groups = m.indices.map((g) => ((g === undefined) ? [-1, -1] : [g[0], g[1]]));
        \\    const ms = groups[0][0], me = groups[0][1];
        \\    if (me === p) { q = me + 1; continue; }
        \\    pieces.push([p, ms]);
        \\    if (pieces.length >= lim) { done = true; break; }
        \\    for (let gi = 1; gi < groups.length; gi++) {
        \\      pieces.push(groups[gi]);
        \\      if (pieces.length >= lim) { done = true; break; }
        \\    }
        \\    if (done) break;
        \\    p = me; q = p;
        \\  }
        \\  if (!done) pieces.push([p, s.length]);
        \\  return pieces;
        \\}
        \\function __sa_json_clone(v) {
        \\  // Deep copy for sa_json_*_set_node / *_push_node (native clones the
        \\  // child into the target document arena; the stored value must not
        \\  // alias the child document tree).
        \\  if (v === null || typeof v !== "object") return v;
        \\  if (Array.isArray(v)) return v.map((x) => __sa_json_clone(x));
        \\  const o = {};
        \\  for (const k of Object.keys(v)) o[k] = __sa_json_clone(v[k]);
        \\  return o;
        \\}
        \\function __sa_json_kind_of(v) {
        \\  if (v === null) return 0;
        \\  if (typeof v === "boolean") return 1;
        \\  if (typeof v === "number") return Number.isInteger(v) ? 2 : 3;
        \\  if (typeof v === "string") return 5;
        \\  if (Array.isArray(v)) return 6;
        \\  if (typeof v === "object") return 7;
        \\  return 4294967295;
        \\}
        \\function __sa_json_i64_of(v) {
        \\  if (typeof v !== "number" || !Number.isInteger(v)) return null;
        \\  if (v > 9223372036854775807 || v < -9223372036854775808) return null;
        \\  return BigInt.asIntN(64, BigInt(v));
        \\}
        \\function __sa_json_f64_of(v) {
        \\  if (typeof v !== "number" || !Number.isFinite(v)) return null;
        \\  return v;
        \\}
        \\function __sa_node_builtin(mod) {
        \\  try {
        \\    const p = globalThis.process;
        \\    if (p && p.getBuiltinModule) return p.getBuiltinModule(mod);
        \\  } catch (e) {}
        \\  return null;
        \\}
        \\function __sa_node_emit(out_ptr, out_len, bytes) {
        \\  const p = __sa_alloc(bytes.length);
        \\  __sa_u8.set(bytes, p);
        \\  __sa_store_i64(out_ptr, p);
        \\  __sa_store_i64(out_len, bytes.length);
        \\  return 0;
        \\}
        \\function __sa_fmt_f64_str(v, prec) {
        \\  // Zig std.fmt.formatFloat decimal mode with precision p (mirrors
        \\  // sa_fmt_f64_into). Returns the text or null on invalid precision.
        \\  const p = __sa_num(prec);
        \\  if (!Number.isInteger(p) || p < 0 || p > 100) return null;
        \\  const x = +v;
        \\  if (Number.isNaN(x)) return "nan";
        \\  if (x === Infinity) return "inf";
        \\  if (x === -Infinity) return "-inf";
        \\  const neg = (x < 0) || (x === 0 && (1 / x) === -Infinity);
        \\  const a = Math.abs(x);
        \\  let s;
        \\  if (a >= 1e21) {
        \\    // Plain decimal notation (Zig never exponentiates); doubles this
        \\    // large are integral so the fraction is all zeros.
        \\    const e = a.toString();
        \\    const m = /^(\\d)(?:\\.(\\d+))?e\\+(\\d+)$/.exec(e);
        \\    if (!m) return (neg ? "-" : "") + e;
        \\    const exp = parseInt(m[3], 10);
        \\    let digits = m[1] + (m[2] || "");
        \\    while (digits.length < exp + 1) digits += "0";
        \\    s = digits.slice(0, exp + 1) + "." + "0".repeat(p);
        \\  } else {
        \\    s = a.toFixed(p);
        \\  }
        \\  return (neg ? "-" : "") + s;
        \\}
        \\// ---- end runtime ----
        \\
;
