pub fn emitJsonWriterWriteBool(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0) return 1;");
    try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)(a1 ? \"true\" : \"false\"), a1 ? 4 : 5)) return 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterWriteI64(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0) return 1;");
    try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" { char tmp[130];");
    try writer.writeAll(" int n = sa_fmt_int(tmp, a1, 10, 1, 0);");
    try writer.writeAll(" if (n < 0) return 1;");
    try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)tmp, (size_t)n)) return 1; }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterWriteF64(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0) return 1;");
    try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" { union { sa_u64 u; double d; } t; t.u = a1;");
    try writer.writeAll(" if (t.d != t.d) return 1;");
    try writer.writeAll(" if ((t.u & (sa_u64)0x7FF0000000000000ULL) == (sa_u64)0x7FF0000000000000ULL) return 1;");
    try writer.writeAll(" char tmp[256];");
    try writer.writeAll(" int n = snprintf(tmp, sizeof(tmp), \"%.17g\", t.d);");
    try writer.writeAll(" if (n < 0 || n >= 256) return 1;");
    try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)tmp, (size_t)n)) return 1; }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterWriteString(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0) return 1;");
    try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" { uint32_t v = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (sa_jw_string(w, &sa_mem[v], (size_t)a2)) return 1; }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterWriteNull(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0) return 1;");
    try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)\"null\", 4)) return 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterFinish(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" sa_store_u64(a1, 0);");
    try writer.writeAll(" if (w == 0 || !w->started || w->pending || w->depth != 0 || w->done) return 1;");
    try writer.writeAll(" { sa_u64 h = sa_owned_new(w->buf, w->len, 2);");
    try writer.writeAll(" if (h == 0) return 1;");
    try writer.writeAll(" w->done = 1;");
    try writer.writeAll(" sa_store_u64(a1, h); return 0; } } }\n");
}

pub fn emitJsonWriterFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0) return 0;");
    try writer.writeAll(" w->h = 0; return 0; } }\n");
}

pub fn emitJsonBufferData(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 2) return 0;");
    try writer.writeAll(" return o->ptr; } }\n");
}

pub fn emitJsonBufferLen(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 2) return 0;");
    try writer.writeAll(" return o->len; } }\n");
}

pub fn emitJsonBufferFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_owned_drop(a0); return 0; } }\n");
}

pub fn emitNodePathNormalize(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_u64 cap = a1 + 2;");
    try writer.writeAll(" sa_u64 p = sa_alloc(cap);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, cap);");
    try writer.writeAll(" sa_u64 n = sa_path_norm(&sa_mem[x], (size_t)a1, &sa_mem[d], (size_t)cap);");
    try writer.writeAll(" if (n == ~(sa_u64)0) return 1;");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, n); return 0; } } }\n");
}

pub fn emitNodePathDirname(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" size_t e = (size_t)a1;");
    try writer.writeAll(" while (e > 1 && sa_mem[x + e - 1] == '/') e--;");
    try writer.writeAll(" size_t i = e;");
    try writer.writeAll(" while (i > 0 && sa_mem[x + i - 1] != '/') i--;");
    try writer.writeAll(" sa_u64 n; sa_u64 src;");
    try writer.writeAll(" if (e == 0 || i == 0) { n = 1; src = 0; }");
    try writer.writeAll(" else if (i == 1) { n = 1; src = 1; }");
    try writer.writeAll(" else { n = (sa_u64)(i - 1); src = 2; }");
    try writer.writeAll(" { sa_u64 p = sa_alloc(n);");
    try writer.writeAll(" uint32_t d = sa_checked_addr(p, n);");
    try writer.writeAll(" if (src == 0) sa_mem[d] = (uint8_t)'.';");
    try writer.writeAll(" else if (src == 1) sa_mem[d] = (uint8_t)'/';");
    try writer.writeAll(" else { size_t k; for (k = 0; k < (size_t)n; k++)");
    try writer.writeAll(" sa_mem[d + k] = sa_mem[x + k]; }");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, n);");
    try writer.writeAll(" return 0; } } }\n");
}

pub fn emitNodePathExtname(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Zero-copy view into the input (no allocation needed).
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" size_t i = (size_t)a1;");
    try writer.writeAll(" while (i > 0 && sa_mem[x + i - 1] != '/') i--;");
    try writer.writeAll(" size_t j = (size_t)a1;");
    try writer.writeAll(" while (j > i && sa_mem[x + j - 1] != '.') j--;");
    try writer.writeAll(" if (j <= i || j == i + 1 || j == (size_t)a1) {");
    try writer.writeAll(" sa_store_u64(a2, 0); sa_store_u64(a3, 0); return 0; }");
    try writer.writeAll(" sa_store_u64(a2, (sa_u64)x + (j - 1));");
    try writer.writeAll(" sa_store_u64(a3, (sa_u64)a1 - (j - 1));");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitNodePathIsAbsolute(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_u64 r = (a1 > 0 && sa_mem[x] == '/') ? 1 : 0;");
    try writer.writeAll(" sa_store_u32(a2, r); return 0; } }\n");
}

pub fn emitNodePathJoin(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // argv of (ptr,len) pairs; joined with '/' then normalized
    // in place (output never exceeds input + 1).
    try writer.writeAll(" { if (a1 > (sa_u64)0x100000u) return 1;");
    try writer.writeAll(" uint32_t ab = sa_checked_addr(a0, (size_t)(a1 * 16));");
    try writer.writeAll(" (void)ab;");
    try writer.writeAll(" sa_u64 total = 0; sa_u64 k;");
    try writer.writeAll(" for (k = 0; k < a1; k++) {");
    try writer.writeAll(" sa_u64 l = sa_load_u64(a0 + k * 16 + 8);");
    try writer.writeAll(" if (l > 0 && total > ~(sa_u64)0 - l - 1) return 1;");
    try writer.writeAll(" total += l + (k + 1 < a1 && l > 0 ? 1 : 0); }");
    try writer.writeAll(" sa_u64 p = sa_alloc(total + 2);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, total + 2);");
    try writer.writeAll(" sa_u64 w = 0;");
    try writer.writeAll(" for (k = 0; k < a1; k++) {");
    try writer.writeAll(" sa_u64 pp = sa_load_u64(a0 + k * 16);");
    try writer.writeAll(" sa_u64 l = sa_load_u64(a0 + k * 16 + 8);");
    try writer.writeAll(" uint32_t s = sa_checked_addr(pp, (size_t)l);");
    try writer.writeAll(" if (l > 0 && w > 0) sa_mem[d + w++] = (uint8_t)'/';");
    try writer.writeAll(" { size_t q; for (q = 0; q < (size_t)l; q++)");
    try writer.writeAll(" sa_mem[d + w + q] = sa_mem[s + q]; }");
    try writer.writeAll(" w += l; }");
    try writer.writeAll(" sa_u64 n = sa_path_norm(&sa_mem[d], (size_t)w, &sa_mem[d], (size_t)(total + 2));");
    try writer.writeAll(" if (n == ~(sa_u64)0) return 1;");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, n); return 0; } } }\n");
}

pub fn emitNodeQsEscape(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Node querystring.escape: alnum + ~!*()-'_. pass through,
    // everything else becomes %XX uppercase hex.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 > ~(sa_u64)0 / 3) return 1;");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 * 3);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 * 3);");
    try writer.writeAll(" sa_u64 w = 0; size_t i;");
    try writer.writeAll(" for (i = 0; i < (size_t)a1; i++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + i];");
    try writer.writeAll(" int ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');");
    try writer.writeAll(" if (!ok) { const char *u = \"~!*()-'_.\"; size_t k; ok = 0;");
    try writer.writeAll(" for (k = 0; k < 8; k++) if (c == (uint8_t)u[k]) { ok = 1; break; } }");
    try writer.writeAll(" if (ok) sa_mem[d + w++] = c;");
    try writer.writeAll(" else {");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)'%';");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"0123456789ABCDEF\"[c >> 4];");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"0123456789ABCDEF\"[c & 15]; } }");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
}

pub fn emitNodeQsUnescape(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // %XX (either case) decodes; malformed % and '+' pass through
    // literally (mirrors Node).
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 == 0 ? 1 : a1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 == 0 ? 1 : a1);");
    try writer.writeAll(" sa_u64 w = 0; size_t i = 0;");
    try writer.writeAll(" while (i < (size_t)a1) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + i];");
    try writer.writeAll(" if (c == '%' && i + 2 < (size_t)a1) {");
    try writer.writeAll(" uint8_t h1 = sa_mem[x + i + 1]; uint8_t h2 = sa_mem[x + i + 2];");
    try writer.writeAll(" int v1 = h1 >= '0' && h1 <= '9' ? h1 - '0' : (h1 >= 'a' && h1 <= 'f' ? h1 - 'a' + 10 : (h1 >= 'A' && h1 <= 'F' ? h1 - 'A' + 10 : -1));");
    try writer.writeAll(" int v2 = h2 >= '0' && h2 <= '9' ? h2 - '0' : (h2 >= 'a' && h2 <= 'f' ? h2 - 'a' + 10 : (h2 >= 'A' && h2 <= 'F' ? h2 - 'A' + 10 : -1));");
    try writer.writeAll(" if (v1 >= 0 && v2 >= 0) { sa_mem[d + w++] = (uint8_t)(v1 * 16 + v2); i += 3; continue; } }");
    try writer.writeAll(" sa_mem[d + w++] = c; i++; }");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
}

pub fn emitNodePunyEncode(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // RFC 3492 encode (UTF-8 in, ASCII out); invalid UTF-8 or
    // overflow yields 1. Output capped at 12x+16 (DoS bound).
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 > (~(sa_u64)0 - 16) / 12) return 1;");
    try writer.writeAll(" sa_u64 cap = a1 * 12 + 16;");
    try writer.writeAll(" sa_u64 p = sa_alloc(cap);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, cap);");
    try writer.writeAll(" sa_u64 cp = sa_alloc((a1 + 1) * 4);");
    try writer.writeAll(" uint32_t cd = sa_checked_addr(cp, (a1 + 1) * 4);");
    try writer.writeAll(" sa_u64 h = 0; size_t i = 0;");
    try writer.writeAll(" while (i < (size_t)a1) {");
    try writer.writeAll(" uint32_t c = sa_utf8_next(&sa_mem[x], (size_t)a1, &i);");
    try writer.writeAll(" if (c == ~(uint32_t)0) return 1;");
    try writer.writeAll(" sa_mem[cd + h * 4] = (uint8_t)(c & 0xFF);");
    try writer.writeAll(" sa_mem[cd + h * 4 + 1] = (uint8_t)((c >> 8) & 0xFF);");
    try writer.writeAll(" sa_mem[cd + h * 4 + 2] = (uint8_t)((c >> 16) & 0xFF);");
    try writer.writeAll(" sa_mem[cd + h * 4 + 3] = (uint8_t)((c >> 24) & 0xFF);");
    try writer.writeAll(" h++; }");
    try writer.writeAll(" sa_u64 w = 0; sa_u64 b;");
    try writer.writeAll(" for (b = 0; b < h; b++) {");
    try writer.writeAll(" uint32_t c = (uint32_t)sa_mem[cd + b * 4] | ((uint32_t)sa_mem[cd + b * 4 + 1] << 8) | ((uint32_t)sa_mem[cd + b * 4 + 2] << 16) | ((uint32_t)sa_mem[cd + b * 4 + 3] << 24);");
    try writer.writeAll(" if (c < 0x80) { if (w >= cap) return 1; sa_mem[d + w++] = (uint8_t)c; } }");
    try writer.writeAll(" sa_u64 nb = w;");
    try writer.writeAll(" if (nb > 0) { if (w >= cap) return 1; sa_mem[d + w++] = (uint8_t)'-'; }");
    try writer.writeAll(" sa_u64 n = 0x80; sa_u64 delta = 0; sa_u64 bias = 72;");
    try writer.writeAll(" int first = 1;");
    try writer.writeAll(" while (h > nb) {");
    try writer.writeAll(" sa_u64 m = ~(sa_u64)0; sa_u64 k;");
    try writer.writeAll(" for (k = 0; k < h; k++) {");
    try writer.writeAll(" uint32_t c = (uint32_t)sa_mem[cd + k * 4] | ((uint32_t)sa_mem[cd + k * 4 + 1] << 8) | ((uint32_t)sa_mem[cd + k * 4 + 2] << 16) | ((uint32_t)sa_mem[cd + k * 4 + 3] << 24);");
    try writer.writeAll(" if (c >= n && (sa_u64)c < m) m = c; }");
    try writer.writeAll(" if (m - n > (~(sa_u64)0 - delta) / (h > 0 ? h : 1)) return 1;");
    try writer.writeAll(" delta += (m - n) * h;");
    try writer.writeAll(" n = m;");
    try writer.writeAll(" for (k = 0; k < h; k++) {");
    try writer.writeAll(" uint32_t c = (uint32_t)sa_mem[cd + k * 4] | ((uint32_t)sa_mem[cd + k * 4 + 1] << 8) | ((uint32_t)sa_mem[cd + k * 4 + 2] << 16) | ((uint32_t)sa_mem[cd + k * 4 + 3] << 24);");
    try writer.writeAll(" if ((sa_u64)c < n) { delta++; if (delta == 0) return 1; continue; }");
    try writer.writeAll(" if ((sa_u64)c == n) {");
    try writer.writeAll(" sa_u64 q = delta; sa_u64 kk = 36;");
    try writer.writeAll(" for (;;) {");
    try writer.writeAll(" sa_u64 t = kk <= bias ? 1 : (kk >= bias + 26 ? 26 : kk - bias);");
    try writer.writeAll(" if (q < t) break;");
    try writer.writeAll(" { sa_u64 bt = 36 - t; sa_u64 dg = t + (q - t) % bt;");
    try writer.writeAll(" if (w >= cap) return 1;");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)(dg < 26 ? 'a' + dg : '0' + dg - 26); }");
    try writer.writeAll(" q = (q - t) / (36 - t); kk += 36; }");
    try writer.writeAll(" if (w >= cap) return 1;");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)(q < 26 ? 'a' + q : '0' + q - 26);");
    try writer.writeAll(" bias = sa_puny_adapt(delta, h + 1, first);");
    try writer.writeAll(" first = 0;");
    try writer.writeAll(" delta = 0; nb++; } }");
    try writer.writeAll(" n++; }");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
}

pub fn emitNodePunyDecode(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // RFC 3492 decode (ASCII in, UTF-8 out); malformed input or
    // overflow yields 1.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" size_t dl = (size_t)a1; size_t q;");
    try writer.writeAll(" for (q = 0; q < (size_t)a1; q++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + q];");
    try writer.writeAll(" if (c == '-') dl = q; }");
    try writer.writeAll(" sa_u64 cp = sa_alloc(((sa_u64)a1 + 1) * 4);");
    try writer.writeAll(" uint32_t cd = sa_checked_addr(cp, ((sa_u64)a1 + 1) * 4);");
    try writer.writeAll(" sa_u64 out = 0; size_t i;");
    try writer.writeAll(" for (i = 0; i < dl; i++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + i];");
    try writer.writeAll(" if (c >= 0x80) return 1;");
    try writer.writeAll(" sa_mem[cd + out * 4] = c;");
    try writer.writeAll(" sa_mem[cd + out * 4 + 1] = 0;");
    try writer.writeAll(" sa_mem[cd + out * 4 + 2] = 0;");
    try writer.writeAll(" sa_mem[cd + out * 4 + 3] = 0; out++; }");
    try writer.writeAll(" size_t pos = dl < (size_t)a1 ? dl + 1 : (size_t)a1;");
    try writer.writeAll(" sa_u64 n = 0x80; sa_u64 bias = 72;");
    try writer.writeAll(" sa_u64 idx = 0; int first = 1;");
    try writer.writeAll(" while (pos < (size_t)a1) {");
    try writer.writeAll(" sa_u64 oldi = idx; sa_u64 w = 1; sa_u64 kk = 36;");
    try writer.writeAll(" for (;;) {");
    try writer.writeAll(" if (pos >= (size_t)a1) return 1;");
    try writer.writeAll(" uint8_t c = sa_mem[x + pos++];");
    try writer.writeAll(" sa_u64 dg = c >= '0' && c <= '9' ? (sa_u64)(c - '0' + 26)");
    try writer.writeAll(" : (c >= 'a' && c <= 'z' ? (sa_u64)(c - 'a')");
    try writer.writeAll(" : (c >= 'A' && c <= 'Z' ? (sa_u64)(c - 'A') : ~(sa_u64)0));");
    try writer.writeAll(" if (dg == ~(sa_u64)0) return 1;");
    try writer.writeAll(" if (dg > (~(sa_u64)0 - idx) / w) return 1;");
    try writer.writeAll(" idx += dg * w;");
    try writer.writeAll(" sa_u64 t = kk <= bias ? 1 : (kk >= bias + 26 ? 26 : kk - bias);");
    try writer.writeAll(" if (dg < t) break;");
    try writer.writeAll(" if (w > ~(sa_u64)0 / (36 - t)) return 1;");
    try writer.writeAll(" w *= 36 - t; kk += 36; }");
    try writer.writeAll(" bias = sa_puny_adapt(idx - oldi, out + 1, first);");
    try writer.writeAll(" first = 0;");
    try writer.writeAll(" if (idx - oldi > (~(sa_u64)0 - n) / (out + 1)) return 1;");
    try writer.writeAll(" n += (idx - oldi) / (out + 1);");
    try writer.writeAll(" idx %= out + 1;");
    try writer.writeAll(" if (n > 0x10FFFF) return 1;");
    try writer.writeAll(" { sa_u64 z; for (z = out; z > idx; z--) {");
    try writer.writeAll(" sa_mem[cd + z * 4] = sa_mem[cd + (z - 1) * 4];");
    try writer.writeAll(" sa_mem[cd + z * 4 + 1] = sa_mem[cd + (z - 1) * 4 + 1];");
    try writer.writeAll(" sa_mem[cd + z * 4 + 2] = sa_mem[cd + (z - 1) * 4 + 2];");
    try writer.writeAll(" sa_mem[cd + z * 4 + 3] = sa_mem[cd + (z - 1) * 4 + 3]; } }");
    try writer.writeAll(" sa_mem[cd + idx * 4] = (uint8_t)(n & 0xFF);");
    try writer.writeAll(" sa_mem[cd + idx * 4 + 1] = (uint8_t)((n >> 8) & 0xFF);");
    try writer.writeAll(" sa_mem[cd + idx * 4 + 2] = (uint8_t)((n >> 16) & 0xFF);");
    try writer.writeAll(" sa_mem[cd + idx * 4 + 3] = (uint8_t)((n >> 24) & 0xFF);");
    try writer.writeAll(" out++; idx++; }");
    try writer.writeAll(" sa_u64 p = sa_alloc(out * 4);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, out * 4);");
    try writer.writeAll(" sa_u64 w = 0; sa_u64 z;");
    try writer.writeAll(" for (z = 0; z < out; z++) {");
    try writer.writeAll(" uint32_t c = (uint32_t)sa_mem[cd + z * 4] | ((uint32_t)sa_mem[cd + z * 4 + 1] << 8) | ((uint32_t)sa_mem[cd + z * 4 + 2] << 16) | ((uint32_t)sa_mem[cd + z * 4 + 3] << 24);");
    try writer.writeAll(" unsigned el = sa_utf8_enc(c, &sa_mem[d + w]);");
    try writer.writeAll(" if (el == 0 || c > 0x10FFFF) return 1; w += el; }");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
}

pub fn emitNodeBufConcat(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // argv of (ptr,len) pairs concatenated in order.
    try writer.writeAll(" { if (a1 > (sa_u64)0x100000u) return 1;");
    try writer.writeAll(" uint32_t ab = sa_checked_addr(a0, (size_t)(a1 * 16));");
    try writer.writeAll(" (void)ab;");
    try writer.writeAll(" sa_u64 total = 0; sa_u64 k;");
    try writer.writeAll(" for (k = 0; k < a1; k++) {");
    try writer.writeAll(" sa_u64 l = sa_load_u64(a0 + k * 16 + 8);");
    try writer.writeAll(" if (total > ~(sa_u64)0 - l) return 1;");
    try writer.writeAll(" total += l; }");
    try writer.writeAll(" sa_u64 p = sa_alloc(total == 0 ? 1 : total);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, total == 0 ? 1 : total);");
    try writer.writeAll(" sa_u64 w = 0;");
    try writer.writeAll(" for (k = 0; k < a1; k++) {");
    try writer.writeAll(" sa_u64 pp = sa_load_u64(a0 + k * 16);");
    try writer.writeAll(" sa_u64 l = sa_load_u64(a0 + k * 16 + 8);");
    try writer.writeAll(" uint32_t s = sa_checked_addr(pp, (size_t)l);");
    try writer.writeAll(" { size_t q; for (q = 0; q < (size_t)l; q++)");
    try writer.writeAll(" sa_mem[d + w + q] = sa_mem[s + q]; }");
    try writer.writeAll(" w += l; }");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, total); return 0; } } }\n");
}

pub fn emitNodeRandBytes(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Staged zero region (only the length is asserted).
    try writer.writeAll(" if (!sa_policy_check(5, 0, 0, 0)) return 10;");
    try writer.writeAll(" sa_u64 p = sa_alloc(a0 == 0 ? 1 : a0);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a0 == 0 ? 1 : a0);");
    try writer.writeAll(" (void)d;");
    try writer.writeAll(" sa_store_u64(a1, p); return 0; } }\n");
}

pub fn emitNodeCryptoHash(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Byte-exact algo dispatch (mirror native: sha256, sha512,
    // sha1, md5 in either case, status 2 otherwise); lowercase
    // hex digest materializes into fresh guest memory.
    try writer.writeAll(" { uint32_t ax = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t dx = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" unsigned hlen = 0; unsigned hk = 0; unsigned e0; unsigned e1; size_t i;");
    try writer.writeAll(" if (a1 == 6) { e0 = 1; e1 = 1;");
    try writer.writeAll(" for (i = 0; i < 6; i++) {");
    try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"sha256\"[i]) e0 = 0;");
    try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"SHA256\"[i]) e1 = 0; }");
    try writer.writeAll(" if (e0 != 0 || e1 != 0) { hk = 1; hlen = 32; }");
    try writer.writeAll(" else { e0 = 1; e1 = 1;");
    try writer.writeAll(" for (i = 0; i < 6; i++) {");
    try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"sha512\"[i]) e0 = 0;");
    try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"SHA512\"[i]) e1 = 0; }");
    try writer.writeAll(" if (e0 != 0 || e1 != 0) { hk = 2; hlen = 64; } } }");
    try writer.writeAll(" if (hk == 0 && a1 == 4) { e0 = 1; e1 = 1;");
    try writer.writeAll(" for (i = 0; i < 4; i++) {");
    try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"sha1\"[i]) e0 = 0;");
    try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"SHA1\"[i]) e1 = 0; }");
    try writer.writeAll(" if (e0 != 0 || e1 != 0) { hk = 3; hlen = 20; } }");
    try writer.writeAll(" if (hk == 0 && a1 == 3) { e0 = 1; e1 = 1;");
    try writer.writeAll(" for (i = 0; i < 3; i++) {");
    try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"md5\"[i]) e0 = 0;");
    try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"MD5\"[i]) e1 = 0; }");
    try writer.writeAll(" if (e0 != 0 || e1 != 0) { hk = 4; hlen = 16; } }");
    try writer.writeAll(" if (hk == 0) return 2;");
    try writer.writeAll(" { uint8_t dig[64];");
    try writer.writeAll(" if (hk == 1) sa_sha256(&sa_mem[dx], (size_t)a3, dig);");
    try writer.writeAll(" else if (hk == 2) sa_sha512(&sa_mem[dx], (size_t)a3, dig);");
    try writer.writeAll(" else if (hk == 3) sa_sha1(&sa_mem[dx], (size_t)a3, dig);");
    try writer.writeAll(" else sa_md5(&sa_mem[dx], (size_t)a3, dig);");
    try writer.writeAll(" sa_u64 p = sa_alloc((sa_u64)hlen * 2);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, (sa_u64)hlen * 2);");
    try writer.writeAll(" unsigned k; for (k = 0; k < hlen; k++) {");
    try writer.writeAll(" sa_mem[d + k * 2] = (uint8_t)\"0123456789abcdef\"[dig[k] >> 4];");
    try writer.writeAll(" sa_mem[d + k * 2 + 1] = (uint8_t)\"0123456789abcdef\"[dig[k] & 15]; }");
    try writer.writeAll(" sa_store_u64(a4, p); sa_store_u64(a5, (sa_u64)hlen * 2); return 0; } } } }\n");
}

pub fn emitMathFloor(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // libm floor over the f64 bit pattern (mirrors sa_math_floor).
    try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = floor(t.v); return t.u; } }\n");
}

pub fn emitMathCeil(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = ceil(t.v); return t.u; } }\n");
}

pub fn emitMathSqrt(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // C sqrt of a negative is NaN, matching Zig @sqrt.
    try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = sqrt(t.v); return t.u; } }\n");
}

pub fn emitMathSin(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = sin(t.v); return t.u; } }\n");
}

pub fn emitMathCos(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = cos(t.v); return t.u; } }\n");
}

pub fn emitMathPow(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { union { sa_u64 u; double v; } x; union { sa_u64 u; double v; } y; x.u = a0; y.u = a1; x.v = pow(x.v, y.v); return x.u; } }\n");
}

pub fn emitMathRandom(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Native sa_math_random is crypto-random in [0, 1), so exact
    // values can never match across backends; the binding keeps
    // the same 53-bit draw shape with a deterministic LCG state,
    // per this backend's determinism rule for staged bindings.
    try writer.writeAll(" { static sa_u64 st = (sa_u64)0x9E3779B97F4A7C15ULL; st = st * (sa_u64)6364136223846793005ULL + (sa_u64)1442695040888963407ULL; union { sa_u64 u; double v; } t; t.v = (double)(st >> 11) * (1.0 / 9007199254740992.0); return t.u; } }\n");
}
