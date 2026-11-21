pub fn emitRegexCompile(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // POSIX regcomp over a NUL-terminated guest copy; the
    // compiled form lives in a C-side table (host pointers).
    // Bad patterns yield 0, mirroring the interpreter.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
    try writer.writeAll(" uint32_t d = sa_checked_addr(p, a1 + 1);");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i]; }");
    try writer.writeAll(" sa_mem[d + a1] = 0;");
    try writer.writeAll(" { unsigned k; sa_regex_t *o = 0;");
    try writer.writeAll(" for (k = 0; k < SA_REGEX_MAX_OBJS; k++)");
    try writer.writeAll(" if (sa_regexes[k].h == 0) { o = &sa_regexes[k]; break; }");
    try writer.writeAll(" if (o == 0) return 0;");
    try writer.writeAll(" if (regcomp(&o->rx, (const char *)&sa_mem[d], (int)a2) != 0) return 0;");
    try writer.writeAll(" sa_u64 h = sa_alloc(8); o->h = h; return h; } } }\n");
}

pub fn emitRegexMatch(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Match header lives in guest memory: [text_base][magic|n]
    // then n (start,end) pairs. Embedded NUL or no-match yields
    // 0, mirroring the interpreter.
    try writer.writeAll(" { sa_regex_t *r = sa_regex_find(a0);");
    try writer.writeAll(" if (r == 0) return 0;");
    try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
    try writer.writeAll(" sa_u64 n = (sa_u64)r->rx.re_nsub + 1;");
    try writer.writeAll(" if (n > SA_REGEX_MAX_GROUPS) n = SA_REGEX_MAX_GROUPS;");
    try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
    try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[td + a2] = 0; }");
    try writer.writeAll(" regmatch_t pm[SA_REGEX_MAX_GROUPS];");
    try writer.writeAll(" if (regexec(&r->rx, (const char *)&sa_mem[sa_checked_addr(tp, a2 + 1)], (size_t)n, pm, 0) != 0) return 0;");
    try writer.writeAll(" { sa_u64 h = sa_alloc(16 + n * 16);");
    try writer.writeAll(" sa_store_u64(h, tp);");
    try writer.writeAll(" sa_store_u64(h + 8, (sa_u64)0x53414D5800000000ULL | n);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++) {");
    try writer.writeAll(" sa_store_u64(h + 16 + i * 16, (sa_u64)(sa_i64)pm[i].rm_so);");
    try writer.writeAll(" sa_store_u64(h + 16 + i * 16 + 8, (sa_u64)(sa_i64)pm[i].rm_eo); }");
    try writer.writeAll(" return h; } } }\n");
}

pub fn emitRegexGroupPtr(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
    try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414D58u) return 0;");
    try writer.writeAll(" sa_u64 n = hdr1 & (sa_u64)0xFFFFFFFFu;");
    try writer.writeAll(" if (a1 >= n) return 0;");
    try writer.writeAll(" sa_u64 so = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
    try writer.writeAll(" sa_u64 eo = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16 + 8);");
    try writer.writeAll(" if ((sa_i64)so < 0 || (sa_i64)eo < 0) return 0;");
    try writer.writeAll(" return sa_load_u64(a0) + so; } }\n");
}

pub fn emitRegexGroupLen(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
    try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414D58u) return 0;");
    try writer.writeAll(" sa_u64 n = hdr1 & (sa_u64)0xFFFFFFFFu;");
    try writer.writeAll(" if (a1 >= n) return 0;");
    try writer.writeAll(" sa_u64 so = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
    try writer.writeAll(" sa_u64 eo = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16 + 8);");
    try writer.writeAll(" if ((sa_i64)so < 0 || (sa_i64)eo < 0) return 0;");
    try writer.writeAll(" return eo - so; } }\n");
}

pub fn emitRegexGroupStart(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
    try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414D58u) return 0;");
    try writer.writeAll(" sa_u64 n = hdr1 & (sa_u64)0xFFFFFFFFu;");
    try writer.writeAll(" if (a1 >= n) return 0;");
    try writer.writeAll(" sa_u64 so = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
    try writer.writeAll(" sa_u64 eo = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16 + 8);");
    try writer.writeAll(" if ((sa_i64)so < 0 || (sa_i64)eo < 0) return 0;");
    try writer.writeAll(" return so; } }\n");
}

pub fn emitRegexGroupCount(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_regex_t *r = sa_regex_find(a0);");
    try writer.writeAll(" if (r == 0) return 0;");
    try writer.writeAll(" return (sa_u64)r->rx.re_nsub + 1; } }\n");
}

pub fn emitRegexFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_regex_t *r = sa_regex_find(a0);");
    try writer.writeAll(" if (r == 0) return 0;");
    try writer.writeAll(" regfree(&r->rx); r->h = 0; return 0; } }\n");
}

pub fn emitRegexMatchFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Guest-side match regions live in the bump arena (no free);
    // dropping is a no-op that still validates nothing and
    // returns OK, matching observable behavior.
    try writer.writeAll(" return 0; }\n");
}

pub fn emitRegexMatchAll(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" {");
    try writer.writeAll(" sa_regex_t *r = sa_regex_find(a0);");
    try writer.writeAll(" if (r == 0) return 0;");
    try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
    try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
    try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[td + a2] = 0; }");
    try writer.writeAll(" return sa_regex_collect_block(r, tp, a2); } }\n");
}

pub fn emitRegexMatchListCount(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 24);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
    try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414C58u) return 0;");
    try writer.writeAll(" return hdr1 & (sa_u64)0xFFFFFFFFu; } }\n");
}

pub fn emitRegexMatchListAt(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 24);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
    try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414C58u) return 0;");
    try writer.writeAll(" sa_u64 cnt = hdr1 & (sa_u64)0xFFFFFFFFu;");
    try writer.writeAll(" if (a1 >= cnt) return 0;");
    try writer.writeAll(" sa_u64 n = sa_load_u64(a0 + 16);");
    try writer.writeAll(" sa_u64 h = sa_alloc(16 + n * 16);");
    try writer.writeAll(" sa_store_u64(h, sa_load_u64(a0));");
    try writer.writeAll(" sa_store_u64(h + 8, (sa_u64)0x53414D5800000000ULL | n);");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++) {");
    try writer.writeAll(" sa_store_u64(h + 16 + i * 16,");
    try writer.writeAll(" sa_load_u64(a0 + 24 + (a1 * n + i) * 16));");
    try writer.writeAll(" sa_store_u64(h + 16 + i * 16 + 8,");
    try writer.writeAll(" sa_load_u64(a0 + 24 + (a1 * n + i) * 16 + 8)); } }");
    try writer.writeAll(" return h; } }\n");
}

pub fn emitRegexMatchListFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitRegexReplace(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" {");
    try writer.writeAll(" sa_regex_t *r = sa_regex_find(a0);");
    try writer.writeAll(" if (r == 0) return 0;");
    try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
    try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
    try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[td + a2] = 0; }");
    try writer.writeAll(" return sa_regex_build_replace(r, tp, a2, a3, a4, 0); } }\n");
}

pub fn emitRegexReplaceAll(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" {");
    try writer.writeAll(" sa_regex_t *r = sa_regex_find(a0);");
    try writer.writeAll(" if (r == 0) return 0;");
    try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
    try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
    try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[td + a2] = 0; }");
    try writer.writeAll(" return sa_regex_build_replace(r, tp, a2, a3, a4, 1); } }\n");
}

pub fn emitRegexBufferData(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr = sa_load_u64(a0);");
    try writer.writeAll(" if ((hdr >> 32) != (sa_u64)0x53414258u) return 0;");
    try writer.writeAll(" return a0 + 16; } }\n");
}

pub fn emitRegexBufferLen(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr = sa_load_u64(a0);");
    try writer.writeAll(" if ((hdr >> 32) != (sa_u64)0x53414258u) return 0;");
    try writer.writeAll(" return sa_load_u64(a0 + 8); } }\n");
}

pub fn emitRegexBufferFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitRegexSplit(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" {");
    try writer.writeAll(" sa_regex_t *r = sa_regex_find(a0);");
    try writer.writeAll(" if (r == 0) return 0;");
    try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
    try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
    try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[td + a2] = 0; }");
    try writer.writeAll(" return sa_regex_split_block(r, tp, a2, a3); } }\n");
}

pub fn emitRegexSplitCount(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
    try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53415058u) return 0;");
    try writer.writeAll(" return hdr1 & (sa_u64)0xFFFFFFFFu; } }\n");
}

pub fn emitRegexSplitPtr(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
    try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53415058u) return 0;");
    try writer.writeAll(" sa_u64 cnt = hdr1 & (sa_u64)0xFFFFFFFFu;");
    try writer.writeAll(" if (a1 >= cnt) return 0;");
    try writer.writeAll(" sa_i64 so = (sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
    try writer.writeAll(" if (so < 0) return 0;");
    try writer.writeAll(" return sa_load_u64(a0) + (sa_u64)so; } }\n");
}

pub fn emitRegexSplitLen(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
    try writer.writeAll(" (void)hh;");
    try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
    try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53415058u) return 0;");
    try writer.writeAll(" sa_u64 cnt = hdr1 & (sa_u64)0xFFFFFFFFu;");
    try writer.writeAll(" if (a1 >= cnt) return 0;");
    try writer.writeAll(" sa_i64 so = (sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
    try writer.writeAll(" sa_i64 eo = (sa_i64)sa_load_u64(a0 + 16 + a1 * 16 + 8);");
    try writer.writeAll(" if (so < 0 || eo < so) return 0;");
    try writer.writeAll(" return (sa_u64)(eo - so); } }\n");
}

pub fn emitRegexSplitFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitTaskOut0(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint64_t v = 0; int32_t st = ");
    try writer.writeAll(name);
    try writer.writeAll("(&v); sa_store_u64(a0, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTaskHandleRet(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)");
    try writer.writeAll(name);
    try writer.writeAll("(a0); }\n");
}

pub fn emitTaskNoargsRet(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)");
    try writer.writeAll(name);
    try writer.writeAll("(); }\n");
}

pub fn emitTaskHandleOut1(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint64_t v = 0; int32_t st = ");
    try writer.writeAll(name);
    try writer.writeAll("(a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTaskSpawn(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_glue_task_ctx *c = (sa_glue_task_ctx *)malloc(sizeof(sa_glue_task_ctx)); uint64_t v = 0; int32_t st; c->entry = a0; c->arg = a1; st = sa_task_spawn(sa_glue_task_entry, c, &v); if (st != 0) { free(c); } sa_store_u64(a2, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTaskSpawnSupervised(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_glue_task_ctx *c = (sa_glue_task_ctx *)malloc(sizeof(sa_glue_task_ctx)); uint64_t v = 0; int32_t st; c->entry = a0; c->arg = a1; c->sink = a2; c->sink_ctx = a3; st = sa_task_spawn_supervised(sa_glue_task_entry_keep, c, sa_glue_trap_sink, c, &v); if (st != 0) { free(c); } sa_store_u64(a4, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTaskTrapInfo(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { int32_t code = 0; const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_task_trap_info(a0, &code, &hp, &hn); sa_store_u32(a1, (sa_u64)(uint32_t)code); sa_glue_out_str(a2, a3, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTaskNetWait(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t r = 0; int32_t st = sa_task_net_wait(a0, (uint32_t)a1, (sa_i64)a2, &r); sa_store_u32(a3, (sa_u64)r); return (sa_u64)(sa_i64)st; } }\n");
}
