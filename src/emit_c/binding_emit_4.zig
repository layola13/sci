pub fn emitHc2Take(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (o == 0) return 5; if (o->aux2) return 5; o->aux2 = 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = o->aux0; s->aux1 = o->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHc2Cancel(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); if (o == 0) return 5; o->aux2 = 1; return 0; } }\n");
}

pub fn emitHc2FreeObj(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHc2WsConnect4(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a4, h); return 0; } }\n");
}

pub fn emitHc2WsConnect6(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a6, h); return 0; } }\n");
}

pub fn emitHc2WsConnect2(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a2, h); return 0; } }\n");
}

pub fn emitHcSsePost(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = a2; s->aux1 = a3; s->aux2 = 0; sa_store_u64(a6, h); return 0; } }\n");
}

pub fn emitHcSseRead(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *s = sa_http_find(sa_http_objs, a0); sa_u64 rem, n, i; if (s == 0) return 1; rem = s->aux1 - s->aux2; n = rem < a2 ? rem : a2; for (i = 0; i < n; i++) sa_mem[a1 + i] = sa_mem[s->aux0 + s->aux2 + i]; s->aux2 += n; sa_store_u64(a3, n); return n == 0 ? 2 : 0; } }\n");
}

pub fn emitHcSsePoll(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *s = sa_http_find(sa_http_objs, a0); if (s == 0) return 1; sa_store_u64(a1, s->aux2 >= s->aux1 ? 1 : 0); return 0; } }\n");
}

pub fn emitHcSseStatus(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *s = sa_http_find(sa_http_objs, a0); return s ? 200 : 0; } }\n");
}

pub fn emitHcSseTurn(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_store_u64(a7, a2); sa_store_u64(a8, a3); sa_store_u64(a9, 0); sa_store_u64(a10, 0); return 0; } }\n");
}

pub fn emitHcSseTurnFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { (void)a0; (void)a1; } }\n");
}

pub fn emitStringConcat(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" sa_u64 n = a1 + a3;");
    try writer.writeAll(" sa_u64 p = sa_alloc(n);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, n);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
    try writer.writeAll(" for (i = 0; i < (size_t)a3; i++)");
    try writer.writeAll(" sa_mem[d + (size_t)a1 + i] = sa_mem[y + i]; }");
    try writer.writeAll(" return sa_owned_new(p, n, 1); } }\n");
}

pub fn emitStringIndexOf(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" sa_u64 st = a4 < a1 ? a4 : a1;");
    try writer.writeAll(" if (a3 == 0) return st;");
    try writer.writeAll(" if (a3 > a1) return ~(sa_u64)0;");
    try writer.writeAll(" { sa_u64 i, j; for (i = st; i + a3 <= a1; i++) {");
    try writer.writeAll(" int eq = 1;");
    try writer.writeAll(" for (j = 0; j < a3; j++)");
    try writer.writeAll(" if (sa_mem[x + i + j] != sa_mem[y + j]) { eq = 0; break; }");
    try writer.writeAll(" if (eq) return i; } } return ~(sa_u64)0; } }\n");
}

pub fn emitStringLastIndexOf(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" sa_u64 st = a4 < a1 ? a4 : a1;");
    try writer.writeAll(" if (a3 == 0) return st;");
    try writer.writeAll(" if (a3 > a1) return ~(sa_u64)0;");
    try writer.writeAll(" { sa_u64 i = st < a1 - a3 ? st : a1 - a3; sa_u64 j;");
    try writer.writeAll(" for (;;) { int eq = 1;");
    try writer.writeAll(" for (j = 0; j < a3; j++)");
    try writer.writeAll(" if (sa_mem[x + i + j] != sa_mem[y + j]) { eq = 0; break; }");
    try writer.writeAll(" if (eq) return i; if (i == 0) break; i--; } }");
    try writer.writeAll(" return ~(sa_u64)0; } }\n");
}

pub fn emitStringStartsWith(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if (a3 > a1) return 0;");
    try writer.writeAll(" { sa_u64 j; for (j = 0; j < a3; j++)");
    try writer.writeAll(" if (sa_mem[x + j] != sa_mem[y + j]) return 0; }");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitStringEndsWith(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if (a3 > a1) return 0;");
    try writer.writeAll(" { sa_u64 j; for (j = 0; j < a3; j++)");
    try writer.writeAll(" if (sa_mem[x + a1 - a3 + j] != sa_mem[y + j]) return 0; }");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitStringToLowerAscii(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c); } }");
    try writer.writeAll(" return sa_owned_new(p, a1, 1); } }\n");
}

pub fn emitStringToUpperAscii(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)(c >= 'a' && c <= 'z' ? c - ('a' - 'A') : c); } }");
    try writer.writeAll(" return sa_owned_new(p, a1, 1); } }\n");
}

pub fn emitStringRepeat(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a2 == 0 || a1 == 0) {");
    try writer.writeAll(" sa_u64 p0 = sa_alloc(0);");
    try writer.writeAll(" return sa_owned_new(p0, 0, 1); }");
    try writer.writeAll(" if (a1 > ~(sa_u64)0 / a2) return 0;");
    try writer.writeAll(" { sa_u64 n = a1 * a2; sa_u64 p = sa_alloc(n);");
    try writer.writeAll(" uint32_t d = sa_checked_addr(p, n);");
    try writer.writeAll(" sa_u64 i, j; for (i = 0; i < a2; i++)");
    try writer.writeAll(" for (j = 0; j < a1; j++)");
    try writer.writeAll(" sa_mem[d + i * a1 + j] = sa_mem[x + j];");
    try writer.writeAll(" return sa_owned_new(p, n, 1); } } }\n");
}

pub fn emitStringPadStart(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t v = sa_checked_addr(a3, (size_t)a4);");
    try writer.writeAll(" if (a2 <= a1 || a4 == 0) {");
    try writer.writeAll(" sa_u64 p0 = sa_alloc(a1);");
    try writer.writeAll(" { uint32_t d0 = sa_checked_addr(p0, a1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d0 + i] = sa_mem[x + i]; }");
    try writer.writeAll(" return sa_owned_new(p0, a1, 1); }");
    try writer.writeAll(" { sa_u64 fill = a2 - a1; sa_u64 p = sa_alloc(a2);");
    try writer.writeAll(" uint32_t d = sa_checked_addr(p, a2);");
    try writer.writeAll(" sa_u64 i, j; for (i = 0; i < fill; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[v + i % a4];");
    try writer.writeAll(" for (j = 0; j < a1; j++)");
    try writer.writeAll(" sa_mem[d + fill + j] = sa_mem[x + j];");
    try writer.writeAll(" return sa_owned_new(p, a2, 1); } } }\n");
}

pub fn emitStringPadEnd(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t v = sa_checked_addr(a3, (size_t)a4);");
    try writer.writeAll(" if (a2 <= a1 || a4 == 0) {");
    try writer.writeAll(" sa_u64 p0 = sa_alloc(a1);");
    try writer.writeAll(" { uint32_t d0 = sa_checked_addr(p0, a1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d0 + i] = sa_mem[x + i]; }");
    try writer.writeAll(" return sa_owned_new(p0, a1, 1); }");
    try writer.writeAll(" { sa_u64 p = sa_alloc(a2);");
    try writer.writeAll(" uint32_t d = sa_checked_addr(p, a2);");
    try writer.writeAll(" sa_u64 j; for (j = 0; j < a1; j++)");
    try writer.writeAll(" sa_mem[d + j] = sa_mem[x + j];");
    try writer.writeAll(" for (; j < a2; j++)");
    try writer.writeAll(" sa_mem[d + j] = sa_mem[v + (j - a1) % a4];");
    try writer.writeAll(" return sa_owned_new(p, a2, 1); } } }\n");
}

pub fn emitStringFromCharCode(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 p = sa_alloc(1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, 1);");
    try writer.writeAll(" sa_mem[d] = (uint8_t)(a0 & 0xFFu); }");
    try writer.writeAll(" return sa_owned_new(p, 1, 1); } }\n");
}

pub fn emitStringFromCodePoint(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // UTF-8 encode with U+FFFD fallback for negative, >0x10FFFF
    // and surrogate halves (mirrors the interpreter exactly).
    try writer.writeAll(" { sa_i64 c = (sa_i64)(int32_t)(uint32_t)a0;");
    try writer.writeAll(" uint32_t cp = c < 0 ? 0xFFFDu : (uint32_t)c;");
    try writer.writeAll(" if (cp > 0x10FFFFu || (cp >= 0xD800u && cp <= 0xDFFFu)) cp = 0xFFFDu;");
    try writer.writeAll(" uint8_t t[4]; sa_u64 n;");
    try writer.writeAll(" if (cp < 0x80) { t[0] = (uint8_t)cp; n = 1; }");
    try writer.writeAll(" else if (cp < 0x800) {");
    try writer.writeAll(" t[0] = (uint8_t)(0xC0 | (cp >> 6));");
    try writer.writeAll(" t[1] = (uint8_t)(0x80 | (cp & 0x3F)); n = 2; }");
    try writer.writeAll(" else if (cp < 0x10000) {");
    try writer.writeAll(" t[0] = (uint8_t)(0xE0 | (cp >> 12));");
    try writer.writeAll(" t[1] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));");
    try writer.writeAll(" t[2] = (uint8_t)(0x80 | (cp & 0x3F)); n = 3; }");
    try writer.writeAll(" else {");
    try writer.writeAll(" t[0] = (uint8_t)(0xF0 | (cp >> 18));");
    try writer.writeAll(" t[1] = (uint8_t)(0x80 | ((cp >> 12) & 0x3F));");
    try writer.writeAll(" t[2] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));");
    try writer.writeAll(" t[3] = (uint8_t)(0x80 | (cp & 0x3F)); n = 4; }");
    try writer.writeAll(" { sa_u64 p = sa_alloc(n);");
    try writer.writeAll(" uint32_t d = sa_checked_addr(p, n);");
    try writer.writeAll(" sa_u64 i; for (i = 0; i < n; i++) sa_mem[d + i] = t[i];");
    try writer.writeAll(" return sa_owned_new(p, n, 1); } } }\n");
}

pub fn emitStringCodePointAt(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Byte at idx despite the name (mirrors the interpreter).
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a2 >= a1) return ~(sa_u64)0;");
    try writer.writeAll(" return (sa_u64)sa_mem[x + a2]; } }\n");
}

pub fn emitStringReplace(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // First or all non-overlapping matches swapped; empty needle
    // prepends (once) or interleaves (all); misses copy input.
    // Overflow bails to 0 (mirrors checked arithmetic). Flat
    // structure: each path returns inside its own block.
    try writer.writeAll(" uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" uint32_t z = sa_checked_addr(a4, (size_t)a5);");
    try writer.writeAll(" if (a3 == 0) {");
    try writer.writeAll(" if (!a6) {");
    try writer.writeAll(" sa_u64 n0 = a5 + a1; if (n0 < a5) return 0;");
    try writer.writeAll(" sa_u64 p0 = sa_alloc(n0);");
    try writer.writeAll(" { uint32_t d0 = sa_checked_addr(p0, n0);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a5; i++)");
    try writer.writeAll(" sa_mem[d0 + i] = sa_mem[z + i];");
    try writer.writeAll(" for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d0 + (size_t)a5 + i] = sa_mem[x + i]; }");
    try writer.writeAll(" return sa_owned_new(p0, n0, 1); }");
    try writer.writeAll(" if (a5 != 0 && a1 + 1 > ~(sa_u64)0 / a5) return 0;");
    try writer.writeAll(" { sa_u64 n1 = a1 + a5 * (a1 + 1);");
    try writer.writeAll(" if (n1 < a1) return 0;");
    try writer.writeAll(" sa_u64 p1 = sa_alloc(n1);");
    try writer.writeAll(" uint32_t d1 = sa_checked_addr(p1, n1);");
    try writer.writeAll(" sa_u64 o = 0; sa_u64 i;");
    try writer.writeAll(" for (i = 0; i < a1; i++) {");
    try writer.writeAll(" sa_u64 j; for (j = 0; j < a5; j++)");
    try writer.writeAll(" sa_mem[d1 + o + j] = sa_mem[z + j];");
    try writer.writeAll(" o += a5; sa_mem[d1 + o] = sa_mem[x + i]; o += 1; }");
    try writer.writeAll(" { sa_u64 j; for (j = 0; j < a5; j++)");
    try writer.writeAll(" sa_mem[d1 + o + j] = sa_mem[z + j]; }");
    try writer.writeAll(" return sa_owned_new(p1, n1, 1); } }");
    try writer.writeAll(" { sa_u64 cnt = 0; sa_u64 i = 0; sa_u64 first = 0;");
    try writer.writeAll(" while (i + a3 <= a1) { sa_u64 j; int eq = 1;");
    try writer.writeAll(" for (j = 0; j < a3; j++)");
    try writer.writeAll(" if (sa_mem[x + i + j] != sa_mem[y + j]) { eq = 0; break; }");
    try writer.writeAll(" if (eq) { if (cnt == 0) first = i; cnt++;");
    try writer.writeAll(" if (!a6) break; i += a3; continue; } i++; }");
    try writer.writeAll(" if (cnt == 0) {");
    try writer.writeAll(" sa_u64 p2 = sa_alloc(a1);");
    try writer.writeAll(" { uint32_t d2 = sa_checked_addr(p2, a1);");
    try writer.writeAll(" size_t k; for (k = 0; k < (size_t)a1; k++)");
    try writer.writeAll(" sa_mem[d2 + k] = sa_mem[x + k]; }");
    try writer.writeAll(" return sa_owned_new(p2, a1, 1); }");
    try writer.writeAll(" if (!a6) {");
    try writer.writeAll(" if (a1 - a3 > ~(sa_u64)0 - a5) return 0;");
    try writer.writeAll(" sa_u64 n3 = a1 - a3 + a5;");
    try writer.writeAll(" sa_u64 p3 = sa_alloc(n3);");
    try writer.writeAll(" uint32_t d3 = sa_checked_addr(p3, n3);");
    try writer.writeAll(" { size_t k; for (k = 0; k < (size_t)first; k++)");
    try writer.writeAll(" sa_mem[d3 + k] = sa_mem[x + k]; }");
    try writer.writeAll(" { size_t k; for (k = 0; k < (size_t)a5; k++)");
    try writer.writeAll(" sa_mem[d3 + (size_t)first + k] = sa_mem[z + k]; }");
    try writer.writeAll(" { size_t k; for (k = 0; k + first + a3 < a1 + 1; k++)");
    try writer.writeAll(" sa_mem[d3 + (size_t)first + (size_t)a5 + k] = sa_mem[x + first + a3 + k]; }");
    try writer.writeAll(" return sa_owned_new(p3, n3, 1); }");
    try writer.writeAll(" { sa_u64 total = a1; sa_u64 ii = 0;");
    try writer.writeAll(" while (ii + a3 <= a1) { sa_u64 jj; int eq2 = 1;");
    try writer.writeAll(" for (jj = 0; jj < a3; jj++)");
    try writer.writeAll(" if (sa_mem[x + ii + jj] != sa_mem[y + jj]) { eq2 = 0; break; }");
    try writer.writeAll(" if (eq2) {");
    try writer.writeAll(" if (total < a3 || total - a3 > ~(sa_u64)0 - a5) return 0;");
    try writer.writeAll(" total = total - a3 + a5; ii += a3; } else ii++; }");
    try writer.writeAll(" sa_u64 p4 = sa_alloc(total);");
    try writer.writeAll(" uint32_t d4 = sa_checked_addr(p4, total);");
    try writer.writeAll(" sa_u64 o4 = 0; ii = 0;");
    try writer.writeAll(" while (ii + a3 <= a1) { sa_u64 jj; int eq3 = 1;");
    try writer.writeAll(" for (jj = 0; jj < a3; jj++)");
    try writer.writeAll(" if (sa_mem[x + ii + jj] != sa_mem[y + jj]) { eq3 = 0; break; }");
    try writer.writeAll(" if (eq3) { sa_u64 jj;");
    try writer.writeAll(" for (jj = 0; jj < a5; jj++)");
    try writer.writeAll(" sa_mem[d4 + o4 + jj] = sa_mem[z + jj];");
    try writer.writeAll(" o4 += a5; ii += a3; } else {");
    try writer.writeAll(" sa_mem[d4 + o4] = sa_mem[x + ii]; o4 += 1; ii++; } }");
    try writer.writeAll(" while (o4 < total) {");
    try writer.writeAll(" sa_mem[d4 + o4] = sa_mem[x + ii]; o4 += 1; ii++; }");
    try writer.writeAll(" return sa_owned_new(p4, total, 1); } } }\n");
}

pub fn emitFdOpen(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Fake fd counter from 3 (mirrors JS next-fd); the path is
    // staged and unread, like the interpreter.
    try writer.writeAll(" { static sa_u64 next_fd = 3; return next_fd++; } }\n");
}

pub fn emitFdClose(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitFdRead(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 3; }\n");
}
