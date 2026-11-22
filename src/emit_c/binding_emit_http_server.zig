pub fn emitHsReqGetMethod(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 p; if (q == 0) return 1; p = sa_alloc(3); sa_mem[p] = 71; sa_mem[p + 1] = 69; sa_mem[p + 2] = 84; sa_store_u64(a1, p); sa_store_u64(a2, 3); return 0; } }\n");
}

pub fn emitHsRespNew(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a2, h); return 0; } }\n");
}

pub fn emitHsCheck0(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1; return 0; } }\n");
}

pub fn emitHsRespSend(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1; return 0; } }\n");
}

pub fn emitHsFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHsWsUpgrade(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHsServeThreaded(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { (void)a0; return 0; } }\n");
}

pub fn emitHs2New(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a0, h); return 0; } }\n");
}

pub fn emitHs2Accept(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a2, h); return 0; } }\n");
}

pub fn emitHs2WsPoll(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; sa_store_u64(a3, 2 | (w->aux2 < w->aux1 ? 1 : 0) | (sa_nb_ws_closed_get(a0) ? 4 : 0)); return 0; } }\n");
}

pub fn emitHs2WsRead(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; if (w->aux2 >= w->aux1) { if (sa_nb_ws_closed_get(a0)) { sa_store_u64(a3, 0); sa_store_u64(a4, 0); return 2; } return 1; } sa_store_u64(a2, (sa_u64)sa_nb_ws_opcode_get(a0)); sa_store_u64(a3, w->aux0 + w->aux2); sa_store_u64(a4, w->aux1 - w->aux2); w->aux2 = w->aux1; return 0; } }\n");
}

pub fn emitHs2WsWrite(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; if (sa_nb_ws_closed_get(a0)) return 2; if (w->aux1 > w->aux2) return 1; w->aux0 = a2; w->aux1 = a3; w->aux2 = 0; sa_nb_ws_meta_set(a0, (int)a1, -1); sa_store_u64(a4, a3); return 0; } }\n");
}

pub fn emitHs2WsClose(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; sa_nb_ws_meta_set(a0, -1, 1); return 0; } }\n");
}

pub fn emitHttpServerNew(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_u64 h = sa_alloc(8);");
    try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
    try writer.writeAll(" if (s == 0) return 1;");
    try writer.writeAll(" s->h = h; sa_store_u64(a0, h); return 0; } }\n");
}

pub fn emitHttpServerStart(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a1, (size_t)a2); (void)hh; }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitHttpServerAccept(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" sa_u64 h = sa_alloc(8);");
    try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
    try writer.writeAll(" if (s == 0) return 1;");
    try writer.writeAll(" s->h = h; sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHttpServerReqGetPath(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Canned "/stream" served from fresh guest memory (mirrors JS).
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" static const uint8_t lit[] = {47, 115, 116, 114, 101, 97, 109};");
    try writer.writeAll(" sa_u64 p = sa_alloc(7);");
    try writer.writeAll(" { size_t i; for (i = 0; i < 7; i++)");
    try writer.writeAll(" sa_mem[sa_checked_addr(p, 7) + i] = lit[i]; }");
    try writer.writeAll(" sa_store_u64(a1, p); sa_store_u64(a2, 7); return 0; } }\n");
}

pub fn emitHttpServerReqGetHeader(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Canned "text/plain" served from fresh guest memory.
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" { uint32_t k = sa_checked_addr(a1, (size_t)a2); (void)k; }");
    try writer.writeAll(" static const uint8_t lit[] = {116, 101, 120, 116, 47, 112, 108, 97, 105, 110};");
    try writer.writeAll(" sa_u64 p = sa_alloc(10);");
    try writer.writeAll(" { size_t i; for (i = 0; i < 10; i++)");
    try writer.writeAll(" sa_mem[sa_checked_addr(p, 10) + i] = lit[i]; }");
    try writer.writeAll(" sa_store_u64(a3, p); sa_store_u64(a4, 10); return 0; } }\n");
}

pub fn emitHttpServerReqGetBody(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" sa_store_u64(a1, 0); sa_store_u64(a2, 0); return 0; } }\n");
}

pub fn emitHttpServerRespStreamNew(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" sa_u64 h = sa_alloc(8);");
    try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
    try writer.writeAll(" if (s == 0) return 1;");
    try writer.writeAll(" s->h = h; sa_store_u64(a2, h); return 0; } }\n");
}

pub fn emitHttpServerRespStreamWrite(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" { uint32_t b = sa_checked_addr(a1, (size_t)a2); (void)b; }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitHttpServerRespStreamFlush(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitHttpServerRespStreamEnd(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitHttpServerRespStreamFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHttpServerReqFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHttpServerFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitStrIsAscii(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" if (sa_mem[x + i] > 0x7F) return 0;");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitStrEqIgnoreAsciiCase(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if (a1 != a3) return 0;");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a1; i++) {");
    try writer.writeAll(" uint8_t l = sa_mem[x + i]; uint8_t r = sa_mem[y + i];");
    try writer.writeAll(" if (l >= 'A' && l <= 'Z') l += (uint8_t)('a' - 'A');");
    try writer.writeAll(" if (r >= 'A' && r <= 'Z') r += (uint8_t)('a' - 'A');");
    try writer.writeAll(" if (l != r) return 0; } }");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitStrTrimAsciiStartIndex(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" size_t i = 0;");
    try writer.writeAll(" while (i < (size_t)a1) { uint8_t c = sa_mem[x + i];");
    try writer.writeAll(" if (c != ' ' && c != '\\t' && c != '\\n' && c != '\\r' && c != 0x0B && c != 0x0C) break; i++; }");
    try writer.writeAll(" return (sa_u64)i; } }\n");
}

pub fn emitStrTrimAsciiEndLen(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" size_t e = (size_t)a1;");
    try writer.writeAll(" while (e > 0) { uint8_t c = sa_mem[x + e - 1];");
    try writer.writeAll(" if (c != ' ' && c != '\\t' && c != '\\n' && c != '\\r' && c != 0x0B && c != 0x0C) break; e--; }");
    try writer.writeAll(" return (sa_u64)e; } }\n");
}
