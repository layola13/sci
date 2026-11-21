pub fn emitHttpClientNew(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8);");
    try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
    try writer.writeAll(" if (s == 0) return 1;");
    try writer.writeAll(" s->h = h; s->aux0 = a0;");
    try writer.writeAll(" sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHttpClientReqNew(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
    try writer.writeAll(" { uint32_t u = sa_checked_addr(a2, (size_t)a3); (void)u; }");
    try writer.writeAll(" sa_u64 h = sa_alloc(8);");
    try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
    try writer.writeAll(" if (s == 0) return 1;");
    try writer.writeAll(" s->h = h; s->aux0 = 0; s->aux1 = 0;");
    try writer.writeAll(" sa_store_u64(a4, h); return 0; } }\n");
}

pub fn emitHttpClientReqAddHeader(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
    try writer.writeAll(" if (r == 0) return 1;");
    try writer.writeAll(" { uint32_t k = sa_checked_addr(a1, (size_t)a2); (void)k; }");
    try writer.writeAll(" { uint32_t v = sa_checked_addr(a3, (size_t)a4); (void)v; }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitHttpClientReqSetBody(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
    try writer.writeAll(" if (r == 0) return 1;");
    try writer.writeAll(" { uint32_t b = sa_checked_addr(a1, (size_t)a2); (void)b; }");
    try writer.writeAll(" r->aux0 = a1; r->aux1 = a2; return 0; } }\n");
}

pub fn emitHttpClientReqSend(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Echo the recorded body with status 200 (mirrors JS).
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
    try writer.writeAll(" if (r == 0) return 1;");
    try writer.writeAll(" sa_u64 h = sa_alloc(8);");
    try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
    try writer.writeAll(" if (s == 0) return 1;");
    try writer.writeAll(" s->h = h; s->aux0 = r->aux0; s->aux1 = r->aux1;");
    try writer.writeAll(" sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHttpClientRespStatus(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 0;");
    try writer.writeAll(" return 200; } }\n");
}

pub fn emitHttpClientRespBodyReader(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
    try writer.writeAll(" if (r == 0) return 1;");
    try writer.writeAll(" sa_u64 h = sa_alloc(8);");
    try writer.writeAll(" sa_http_obj_t *d = sa_http_slot(sa_http_objs);");
    try writer.writeAll(" if (d == 0) return 1;");
    try writer.writeAll(" d->h = h; d->aux0 = r->aux0; d->aux1 = r->aux1; d->aux2 = 0;");
    try writer.writeAll(" sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHttpClientRespReadChunk(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
    try writer.writeAll(" if (r == 0) return 1;");
    try writer.writeAll(" sa_u64 rem = r->aux1 - r->aux2;");
    try writer.writeAll(" sa_u64 n = a2 < rem ? a2 : rem;");
    try writer.writeAll(" { uint32_t b = sa_checked_addr(a1, (size_t)n);");
    try writer.writeAll(" uint32_t s = sa_checked_addr(r->aux0, (size_t)r->aux1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[b + i] = sa_mem[s + r->aux2 + i]; }");
    try writer.writeAll(" r->aux2 += n; sa_store_u64(a3, n); return 0; } }\n");
}

pub fn emitHttpClientRespFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHttpClientBodyReaderFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHttpClientReqFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHttpClientFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHcReqNewJoined(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); sa_u64 n = a3 + a5; sa_u64 buf; sa_u64 i; if (s == 0) return 1; buf = sa_alloc(n); for (i = 0; i < a3; i++) sa_mem[buf + i] = sa_mem[a2 + i]; for (i = 0; i < a5; i++) sa_mem[buf + a3 + i] = sa_mem[a4 + i]; s->h = h; s->aux0 = buf; s->aux1 = n; s->aux2 = 0; sa_store_u64(a7, h); return 0; } }\n");
}

pub fn emitHcReqOpenaiAuth(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1; return 0; } }\n");
}

pub fn emitHcSendAsync(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = q->aux0; s->aux1 = q->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHcOpPoll(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); if (o == 0) return 1; sa_store_u64(a1, o->aux2 ? 0 : 1); return 0; } }\n");
}

pub fn emitHcOpTake(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (o == 0) return 1; if (o->aux2) return 1; o->aux2 = 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = o->aux0; s->aux1 = o->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHcOpFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHcRespGetHeader(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0); if (r == 0) return 1; sa_store_u64(a4, 0); return 2; } }\n");
}

pub fn emitHcRespBodySlice(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0); if (r == 0) return 1; sa_store_u64(a1, r->aux0); sa_store_u64(a2, r->aux1); return 0; } }\n");
}

pub fn emitHcRespBodyPtr(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0); return r ? r->aux0 : 0; } }\n");
}

pub fn emitHcRespBodyLen(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0); return r ? r->aux1 : 0; } }\n");
}

pub fn emitHcWsConnect(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a3, h); return 0; } }\n");
}

pub fn emitHc2ClientNew(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a3, h); return 0; } }\n");
}

pub fn emitHc2ReqNew(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = a2; s->aux1 = a3; s->aux2 = 0; sa_store_u64(a4, h); return 0; } }\n");
}

pub fn emitHc2AddHeader(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 5; return 0; } }\n");
}

pub fn emitHc2SetBody(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); if (q == 0) return 5; q->aux0 = a1; q->aux1 = a2; return 0; } }\n");
}

pub fn emitHc2SetTimeout(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 5; return 0; } }\n");
}

pub fn emitHc2SetMax(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); if (q == 0) return 5; q->aux2 = a1; return 0; } }\n");
}

pub fn emitHc2Send(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 5; if (q->aux2 && q->aux1 > q->aux2) return 4; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = q->aux0; s->aux1 = q->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHc2SendAsync(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 5; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = q->aux0; s->aux1 = q->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
}

pub fn emitHc2Poll(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); if (o == 0) return 5; sa_store_u64(a2, o->aux2 ? 0 : 1); return 0; } }\n");
}
