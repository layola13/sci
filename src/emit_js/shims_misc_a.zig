const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_regex_buffer_data")) {
        try writer.writeAll(
            \\function sa_regex_buffer_data(buffer) {
            \\  const b = __sa_regexbufs.get(__sa_num(buffer));
            \\  if (b === undefined) return 0;
            \\  return b.base;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_buffer_free")) {
        try writer.writeAll(
            \\function sa_regex_buffer_free(buffer) {
            \\  const b = __sa_regexbufs.get(__sa_num(buffer));
            \\  if (b !== undefined) { __sa_regexbufs.delete(__sa_num(buffer)); __sa_free(b.base); }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_buffer_len")) {
        try writer.writeAll(
            \\function sa_regex_buffer_len(buffer) {
            \\  const b = __sa_regexbufs.get(__sa_num(buffer));
            \\  if (b === undefined) return 0n;
            \\  return BigInt(b.len);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_compile")) {
        try writer.writeAll(
            \\function sa_regex_compile(pattern, pattern_len, cflags) {
            \\  const bytes = __sa_mem_bytes(pattern, pattern_len);
            \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
            \\  const src = new globalThis.TextDecoder().decode(bytes);
            \\  const f = __sa_num(cflags);
            \\  let flags = "d";
            \\  if ((f & 2) !== 0) flags += "i";
            \\  if ((f & 4) !== 0) flags += "m";
            \\  let re;
            \\  try { re = new RegExp(src, flags); } catch (e) { return 0n; }
            \\  let ngroups = 0;
            \\  try {
            \\    const probe = new RegExp("(?:" + src + ")|()", flags);
            \\    const pm = probe.exec("");
            \\    ngroups = (pm && pm.indices) ? pm.indices.length - 2 : 0;
            \\  } catch (e) { ngroups = 0; }
            \\  const h = __sa_regexnext++;
            \\  __sa_regexes.set(h, { re: re, ngroups: ngroups });
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_free")) {
        try writer.writeAll(
            \\function sa_regex_free(regex) { __sa_regexes.delete(__sa_num(regex)); return 0; }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_group_count")) {
        try writer.writeAll(
            \\function sa_regex_group_count(regex) {
            \\  const rec = __sa_regexes.get(__sa_num(regex));
            \\  if (rec === undefined) return 0n;
            \\  return BigInt(rec.ngroups + 1);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_group_len")) {
        try writer.writeAll(
            \\function sa_regex_group_len(match, group_idx) {
            \\  const g = __sa_regex_group(match, group_idx);
            \\  if (g === null) return 0n;
            \\  return BigInt(g.eo - g.so);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_group_ptr")) {
        try writer.writeAll(
            \\function sa_regex_group_ptr(match, group_idx) {
            \\  const g = __sa_regex_group(match, group_idx);
            \\  if (g === null) return 0;
            \\  return __sa_ptr_add(g.rec.base, g.so);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_group_start")) {
        try writer.writeAll(
            \\function sa_regex_group_start(match, group_idx) {
            \\  const g = __sa_regex_group(match, group_idx);
            \\  if (g === null) return 0n;
            \\  return BigInt(g.so);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_match")) {
        try writer.writeAll(
            \\function sa_regex_match(regex, text, text_len) {
            \\  const rec = __sa_regexes.get(__sa_num(regex));
            \\  if (rec === undefined) return 0n;
            \\  const bytes = __sa_mem_bytes(text, text_len);
            \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
            \\  const s = new globalThis.TextDecoder().decode(bytes);
            \\  rec.re.lastIndex = 0;
            \\  const m = rec.re.exec(s);
            \\  if (m === null || m.indices === undefined) return 0n;
            \\  const p = __sa_alloc(bytes.length);
            \\  __sa_u8.set(bytes, p);
            \\  const groups = m.indices.map((g) => ((g === undefined) ? [-1, -1] : [g[0], g[1]]));
            \\  const h = __sa_regexmatchnext++;
            \\  __sa_regexmatches.set(h, { base: p, len: bytes.length, groups: groups });
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_match_all")) {
        try writer.writeAll(
            \\function sa_regex_match_all(regex, text, text_len) {
            \\  const rec = __sa_regexes.get(__sa_num(regex));
            \\  if (rec === undefined) return 0n;
            \\  const bytes = __sa_mem_bytes(text, text_len);
            \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
            \\  const s = new globalThis.TextDecoder().decode(bytes);
            \\  const matches = __sa_regex_collect(rec, s);
            \\  const p = __sa_alloc(bytes.length);
            \\  __sa_u8.set(bytes, p);
            \\  const h = __sa_regexlistnext++;
            \\  __sa_regexlists.set(h, { base: p, len: bytes.length, matches: matches });
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_match_free")) {
        try writer.writeAll(
            \\function sa_regex_match_free(match) {
            \\  const r = __sa_regexmatches.get(__sa_num(match));
            \\  if (r !== undefined) { __sa_regexmatches.delete(__sa_num(match)); __sa_free(r.base); }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_match_list_at")) {
        try writer.writeAll(
            \\function sa_regex_match_list_at(list, index) {
            \\  const lst = __sa_regexlists.get(__sa_num(list));
            \\  if (lst === undefined) return 0n;
            \\  const i = __sa_tou(index);
            \\  if (!(i >= 0) || i >= lst.matches.length) return 0n;
            \\  const bytes = __sa_mem_bytes(lst.base, lst.len);
            \\  const p = __sa_alloc(bytes.length);
            \\  __sa_u8.set(bytes, p);
            \\  const groups = lst.matches[i].map((g) => [g[0], g[1]]);
            \\  const h = __sa_regexmatchnext++;
            \\  __sa_regexmatches.set(h, { base: p, len: bytes.length, groups: groups });
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_match_list_count")) {
        try writer.writeAll(
            \\function sa_regex_match_list_count(list) {
            \\  const lst = __sa_regexlists.get(__sa_num(list));
            \\  if (lst === undefined) return 0n;
            \\  return BigInt(lst.matches.length);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_match_list_free")) {
        try writer.writeAll(
            \\function sa_regex_match_list_free(list) {
            \\  const lst = __sa_regexlists.get(__sa_num(list));
            \\  if (lst !== undefined) { __sa_regexlists.delete(__sa_num(list)); __sa_free(lst.base); }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_replace")) {
        try writer.writeAll(
            \\function sa_regex_replace(regex, text, text_len, replacement, replacement_len) {
            \\  const rec = __sa_regexes.get(__sa_num(regex));
            \\  if (rec === undefined) return 0n;
            \\  const bytes = __sa_mem_bytes(text, text_len);
            \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
            \\  const s = new globalThis.TextDecoder().decode(bytes);
            \\  const repl = new globalThis.TextDecoder().decode(__sa_mem_bytes(replacement, replacement_len));
            \\  const re = new RegExp(rec.re.source, rec.re.flags);
            \\  const m = re.exec(s);
            \\  let out = s;
            \\  if (m !== null && m.indices !== undefined) {
            \\    const groups = m.indices.map((g) => ((g === undefined) ? [-1, -1] : [g[0], g[1]]));
            \\    out = s.slice(0, groups[0][0]) + __sa_regex_expand(s, groups, repl) + s.slice(groups[0][1]);
            \\  }
            \\  const ob = new globalThis.TextEncoder().encode(out);
            \\  const p = __sa_alloc(ob.length);
            \\  __sa_u8.set(ob, p);
            \\  const h = __sa_regexbufnext++;
            \\  __sa_regexbufs.set(h, { base: p, len: ob.length });
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_replace_all")) {
        try writer.writeAll(
            \\function sa_regex_replace_all(regex, text, text_len, replacement, replacement_len) {
            \\  const rec = __sa_regexes.get(__sa_num(regex));
            \\  if (rec === undefined) return 0n;
            \\  const bytes = __sa_mem_bytes(text, text_len);
            \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
            \\  const s = new globalThis.TextDecoder().decode(bytes);
            \\  const repl = new globalThis.TextDecoder().decode(__sa_mem_bytes(replacement, replacement_len));
            \\  const matches = __sa_regex_collect(rec, s);
            \\  let out = "";
            \\  let last = 0;
            \\  for (const groups of matches) {
            \\    out += s.slice(last, groups[0][0]);
            \\    out += __sa_regex_expand(s, groups, repl);
            \\    last = groups[0][1];
            \\  }
            \\  out += s.slice(last);
            \\  const ob = new globalThis.TextEncoder().encode(out);
            \\  const p = __sa_alloc(ob.length);
            \\  __sa_u8.set(ob, p);
            \\  const h = __sa_regexbufnext++;
            \\  __sa_regexbufs.set(h, { base: p, len: ob.length });
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_split")) {
        try writer.writeAll(
            \\function sa_regex_split(regex, text, text_len, limit) {
            \\  const rec = __sa_regexes.get(__sa_num(regex));
            \\  if (rec === undefined) return 0n;
            \\  const bytes = __sa_mem_bytes(text, text_len);
            \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
            \\  const s = new globalThis.TextDecoder().decode(bytes);
            \\  const pieces = __sa_regex_split_pieces(rec, s, __sa_tou(limit));
            \\  const p = __sa_alloc(bytes.length);
            \\  __sa_u8.set(bytes, p);
            \\  const h = __sa_regexsplitnext++;
            \\  __sa_regexsplits.set(h, { base: p, len: bytes.length, pieces: pieces });
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_split_count")) {
        try writer.writeAll(
            \\function sa_regex_split_count(list) {
            \\  const lst = __sa_regexsplits.get(__sa_num(list));
            \\  if (lst === undefined) return 0n;
            \\  return BigInt(lst.pieces.length);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_split_free")) {
        try writer.writeAll(
            \\function sa_regex_split_free(list) {
            \\  const lst = __sa_regexsplits.get(__sa_num(list));
            \\  if (lst !== undefined) { __sa_regexsplits.delete(__sa_num(list)); __sa_free(lst.base); }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_split_len")) {
        try writer.writeAll(
            \\function sa_regex_split_len(list, index) {
            \\  const lst = __sa_regexsplits.get(__sa_num(list));
            \\  if (lst === undefined) return 0n;
            \\  const i = __sa_tou(index);
            \\  if (!(i >= 0) || i >= lst.pieces.length) return 0n;
            \\  const pc = lst.pieces[i];
            \\  if (pc[0] < 0 || pc[1] < 0) return 0n;
            \\  return BigInt(pc[1] - pc[0]);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_regex_split_ptr")) {
        try writer.writeAll(
            \\function sa_regex_split_ptr(list, index) {
            \\  const lst = __sa_regexsplits.get(__sa_num(list));
            \\  if (lst === undefined) return 0;
            \\  const i = __sa_tou(index);
            \\  if (!(i >= 0) || i >= lst.pieces.length) return 0;
            \\  const pc = lst.pieces[i];
            \\  if (pc[0] < 0) return 0;
            \\  return __sa_ptr_add(lst.base, pc[0]);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_code_point_at")) {
        try writer.writeAll(
            \\function sa_string_code_point_at(ptr, len, idx) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  const i = __sa_num(idx);
            \\  if (i < 0 || i >= b.length) return -1;
            \\  return b[i];
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_concat")) {
        try writer.writeAll(
            \\function sa_string_concat(left, left_len, right, right_len) {
            \\  const l = __sa_mem_bytes(left, left_len), r = __sa_mem_bytes(right, right_len);
            \\  const out = new Uint8Array(l.length + r.length);
            \\  out.set(l, 0); out.set(r, l.length);
            \\  return __sa_buf_open(out);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_ends_with")) {
        try writer.writeAll(
            \\function sa_string_ends_with(hay_ptr, hay_len, ndl_ptr, ndl_len) {
            \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len);
            \\  if (ndl.length > hay.length) return 0;
            \\  const o = hay.length - ndl.length;
            \\  for (let j = 0; j < ndl.length; j++) if (hay[o + j] !== ndl[j]) return 0;
            \\  return 1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_from_char_code")) {
        try writer.writeAll(
            \\function sa_string_from_char_code(code) { return __sa_buf_open(new Uint8Array([__sa_num(code) & 0xff])); }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_from_code_point")) {
        try writer.writeAll(
            \\function sa_string_from_code_point(code) {
            \\  let cp = __sa_num(code);
            \\  if (cp < 0 || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) cp = 0xfffd;
            \\  return __sa_buf_open(new globalThis.TextEncoder().encode(String.fromCodePoint(cp)));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_index_of")) {
        try writer.writeAll(
            \\function sa_string_index_of(hay_ptr, hay_len, ndl_ptr, ndl_len, from) {
            \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len);
            \\  const start = Math.min(__sa_tou(from), hay.length);
            \\  if (ndl.length === 0) return Math.min(start, hay.length);
            \\  if (ndl.length > hay.length) return -1;
            \\  outer: for (let i = start; i + ndl.length <= hay.length; i++) {
            \\    for (let j = 0; j < ndl.length; j++) if (hay[i + j] !== ndl[j]) continue outer;
            \\    return i;
            \\  }
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_last_index_of")) {
        try writer.writeAll(
            \\function sa_string_last_index_of(hay_ptr, hay_len, ndl_ptr, ndl_len, from) {
            \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len);
            \\  const start = Math.min(__sa_tou(from), hay.length);
            \\  if (ndl.length === 0) return Math.min(start, hay.length);
            \\  if (ndl.length > hay.length) return -1;
            \\  outer: for (let i = Math.min(start, hay.length - ndl.length); ; i--) {
            \\    let ok = true;
            \\    for (let j = 0; j < ndl.length; j++) if (hay[i + j] !== ndl[j]) { ok = false; break; }
            \\    if (ok) return i;
            \\    if (i === 0) break;
            \\  }
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_pad_end")) {
        try writer.writeAll(
            \\function sa_string_pad_end(ptr, len, target_len, pad_ptr, pad_len) {
            \\  const b = __sa_mem_bytes(ptr, len), pad = __sa_mem_bytes(pad_ptr, pad_len);
            \\  const t = __sa_num(target_len);
            \\  if (t <= b.length || pad.length === 0) return __sa_buf_open(b);
            \\  const out = new Uint8Array(t);
            \\  out.set(b, 0);
            \\  for (let i = b.length; i < t; i++) out[i] = pad[(i - b.length) % pad.length];
            \\  return __sa_buf_open(out);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_pad_start")) {
        try writer.writeAll(
            \\function sa_string_pad_start(ptr, len, target_len, pad_ptr, pad_len) {
            \\  const b = __sa_mem_bytes(ptr, len), pad = __sa_mem_bytes(pad_ptr, pad_len);
            \\  const t = __sa_num(target_len);
            \\  if (t <= b.length || pad.length === 0) return __sa_buf_open(b);
            \\  const out = new Uint8Array(t);
            \\  const fill = t - b.length;
            \\  for (let i = 0; i < fill; i++) out[i] = pad[i % pad.length];
            \\  out.set(b, fill);
            \\  return __sa_buf_open(out);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_repeat")) {
        try writer.writeAll(
            \\function sa_string_repeat(ptr, len, count) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  if (b.length === 0) return __sa_buf_open(new Uint8Array(0));
            \\  const n = __sa_num(count);
            \\  if (n === 0) return __sa_buf_open(new Uint8Array(0));
            \\  if (!(n > 0) || !Number.isSafeInteger(n) || n > 4294967295 / b.length) return 0n;
            \\  const out = new Uint8Array(b.length * n);
            \\  for (let i = 0; i < n; i++) out.set(b, i * b.length);
            \\  return __sa_buf_open(out);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_replace")) {
        try writer.writeAll(
            \\function sa_string_replace(hay_ptr, hay_len, ndl_ptr, ndl_len, rep_ptr, rep_len, all) {
            \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len), rep = __sa_mem_bytes(rep_ptr, rep_len);
            \\  const want_all = __sa_num(all) !== 0;
            \\  const at = (i) => { for (let j = 0; j < ndl.length; j++) if (hay[i + j] !== ndl[j]) return false; return true; };
            \\  if (ndl.length === 0) {
            \\    if (!want_all) { const o = new Uint8Array(rep.length + hay.length); o.set(rep, 0); o.set(hay, rep.length); return __sa_buf_open(o); }
            \\    const o = new Uint8Array(hay.length + rep.length * (hay.length + 1));
            \\    let w = 0;
            \\    for (let i = 0; i < hay.length; i++) { o.set(rep, w); w += rep.length; o[w++] = hay[i]; }
            \\    o.set(rep, w); w += rep.length;
            \\    return __sa_buf_open(o.slice(0, w));
            \\  }
            \\  if (ndl.length > hay.length) return __sa_buf_open(hay);
            \\  const starts = [];
            \\  if (!want_all) { for (let i = 0; i + ndl.length <= hay.length; i++) if (at(i)) { starts.push(i); break; } }
            \\  else { for (let i = 0; i + ndl.length <= hay.length;) if (at(i)) { starts.push(i); i += ndl.length; } else i++; }
            \\  if (starts.length === 0) return __sa_buf_open(hay);
            \\  let total = hay.length;
            \\  for (const s of starts) total += rep.length - ndl.length;
            \\  const o = new Uint8Array(total);
            \\  let w = 0, s = 0;
            \\  for (const m of starts) {
            \\    o.set(hay.slice(s, m), w); w += m - s;
            \\    o.set(rep, w); w += rep.length;
            \\    s = m + ndl.length;
            \\  }
            \\  o.set(hay.slice(s), w);
            \\  return __sa_buf_open(o);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_starts_with")) {
        try writer.writeAll(
            \\function sa_string_starts_with(hay_ptr, hay_len, ndl_ptr, ndl_len) {
            \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len);
            \\  if (ndl.length > hay.length) return 0;
            \\  for (let j = 0; j < ndl.length; j++) if (hay[j] !== ndl[j]) return 0;
            \\  return 1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_to_lower_ascii")) {
        try writer.writeAll(
            \\function sa_string_to_lower_ascii(ptr, len) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  for (let i = 0; i < b.length; i++) if (b[i] >= 65 && b[i] <= 90) b[i] += 32;
            \\  return __sa_buf_open(b);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_string_to_upper_ascii")) {
        try writer.writeAll(
            \\function sa_string_to_upper_ascii(ptr, len) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  for (let i = 0; i < b.length; i++) if (b[i] >= 97 && b[i] <= 122) b[i] -= 32;
            \\  return __sa_buf_open(b);
            \\}
            \\
        );
        return true;
    }
    return false;
}
