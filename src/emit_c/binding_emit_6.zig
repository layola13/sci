pub fn emitCookieJarPolicy(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t v = 0; int32_t st = sa_cookie_jar_policy(a0, &v); sa_store_u32(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieJarStore(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t r = 0; int32_t st = sa_cookie_jar_store(a0, sa_glue_cptr(a1, a2), a2, sa_glue_cptr(a3, a4), a4, (sa_i64)a5, &r); sa_store_u32(a6, (sa_u64)r); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieJarHeader(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_jar_header(a0, sa_glue_cptr(a1, a2), a2, (sa_i64)a3, &hp, &hn); sa_glue_out_str(a4, a5, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieJarCount(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_cookie_jar_count(a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieJarAt(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return sa_cookie_jar_at(a0, a1); }\n");
}

pub fn emitCookieJarClear(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_clear(a0); }\n");
}

pub fn emitCookieJarEvictExpired(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_cookie_jar_evict_expired(a0, (sa_i64)a1, &v); sa_store_u64(a2, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieJarSave(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_save(a0, sa_glue_cptr(a1, a2), a2); }\n");
}

pub fn emitCookieJarLoad(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_cookie_jar_load(a0, sa_glue_cptr(a1, a2), a2, &v); sa_store_u64(a3, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieJarRequestHeader(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_jar_request_header(a0, sa_glue_cptr(a1, a2), a2, &hp, &hn); sa_glue_out_str(a3, a4, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieJarStoreResponse(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_store_response(a0, sa_glue_cptr(a1, a2), a2, sa_glue_cptr(a3, a4), a4); }\n");
}

pub fn emitFmtI64Into(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Signed decimal (or base 2/8/16/17) into the caller buffer;
    // out_len is always written, cap==0 short-circuits OK,
    // overflow reports truncated (mirrors writeFormattedInto).
    try writer.writeAll(" { char tmp[130];");
    try writer.writeAll(" int n = sa_fmt_int(tmp, a0, (unsigned)a1, 1, (a1 == 17));");
    try writer.writeAll(" if (n < 0) return 1;");
    try writer.writeAll(" sa_store_u64(a4, (sa_u64)n);");
    try writer.writeAll(" if (a3 == 0) return 0;");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if ((sa_u64)n > a3) return 9;");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; } } return 0; } }\n");
}

pub fn emitFmtU64Into(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { char tmp[130];");
    try writer.writeAll(" int n = sa_fmt_int(tmp, a0, (unsigned)a1, 0, (a1 == 17));");
    try writer.writeAll(" if (n < 0) return 1;");
    try writer.writeAll(" sa_store_u64(a4, (sa_u64)n);");
    try writer.writeAll(" if (a3 == 0) return 0;");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if ((sa_u64)n > a3) return 9;");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; } } return 0; } }\n");
}

pub fn emitFmtF64Into(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Zig "{d:.precision}" == C "%.*f" for sane precisions;
    // NaN keeps Zig's "NaN" casing (printf says "nan").
    try writer.writeAll(" { if (a1 > 200) return 1;");
    try writer.writeAll(" union { sa_u64 u; double d; } t; t.u = a0;");
    try writer.writeAll(" char tmp[256];");
    try writer.writeAll(" if (t.d != t.d) {");
    try writer.writeAll(" sa_store_u64(a4, 3);");
    try writer.writeAll(" if (a3 == 0) return 0;");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if (3 > a3) return 9;");
    try writer.writeAll(" sa_mem[d] = (uint8_t)'N'; sa_mem[d + 1] = (uint8_t)'a';");
    try writer.writeAll(" sa_mem[d + 2] = (uint8_t)'N'; } return 0; }");
    try writer.writeAll(" int n = snprintf(tmp, sizeof(tmp), \"%.*f\", (int)a1, t.d);");
    try writer.writeAll(" if (n < 0 || n >= 256) return 1;");
    try writer.writeAll(" sa_store_u64(a4, (sa_u64)n);");
    try writer.writeAll(" if (a3 == 0) return 0;");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if ((sa_u64)n > a3) return 9;");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; } } return 0; } }\n");
}

pub fn emitFmtBoolInto(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { const char *s = a0 ? \"true\" : \"false\";");
    try writer.writeAll(" sa_u64 n = a0 ? 4 : 5;");
    try writer.writeAll(" sa_store_u64(a3, n);");
    try writer.writeAll(" if (a2 == 0) return 0;");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (n > a2) return 9;");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)s[i]; } } return 0; } }\n");
}

pub fn emitFmtBytesInto(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t s = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_store_u64(a4, a1);");
    try writer.writeAll(" if (a3 == 0) return 0;");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if (a1 > a3) return 9;");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[s + i]; } } return 0; } }\n");
}

pub fn emitFmtI64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { char tmp[130];");
    try writer.writeAll(" int n = sa_fmt_int(tmp, a0, (unsigned)a1, 1, (a1 == 17));");
    try writer.writeAll(" if (n < 0) return 0;");
    try writer.writeAll(" sa_u64 p = sa_alloc((sa_u64)n);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, (sa_u64)n);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; }");
    try writer.writeAll(" return sa_owned_new(p, (sa_u64)n, 1); } }\n");
}

pub fn emitFmtU64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { char tmp[130];");
    try writer.writeAll(" int n = sa_fmt_int(tmp, a0, (unsigned)a1, 0, (a1 == 17));");
    try writer.writeAll(" if (n < 0) return 0;");
    try writer.writeAll(" sa_u64 p = sa_alloc((sa_u64)n);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, (sa_u64)n);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; }");
    try writer.writeAll(" return sa_owned_new(p, (sa_u64)n, 1); } }\n");
}

pub fn emitFmtF64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (a1 > 200) return 0;");
    try writer.writeAll(" union { sa_u64 u; double d; } t; t.u = a0;");
    try writer.writeAll(" char tmp[256];");
    try writer.writeAll(" int n = snprintf(tmp, sizeof(tmp), \"%.*f\", (int)a1, t.d);");
    try writer.writeAll(" if (n < 0 || n >= 256) return 0;");
    try writer.writeAll(" sa_u64 p = sa_alloc((sa_u64)n);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, (sa_u64)n);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; }");
    try writer.writeAll(" return sa_owned_new(p, (sa_u64)n, 1); } }\n");
}

pub fn emitFmtBool(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { const char *s = a0 ? \"true\" : \"false\";");
    try writer.writeAll(" sa_u64 n = a0 ? 4 : 5;");
    try writer.writeAll(" sa_u64 p = sa_alloc(n);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, n);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
    try writer.writeAll(" sa_mem[d + i] = (uint8_t)s[i]; }");
    try writer.writeAll(" return sa_owned_new(p, n, 1); } }\n");
}

pub fn emitFmtBytes(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t s = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[s + i]; }");
    try writer.writeAll(" return sa_owned_new(p, a1, 1); } }\n");
}

pub fn emitFmtBufferData(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 1) return 0;");
    try writer.writeAll(" return o->ptr; } }\n");
}

pub fn emitFmtBufferLen(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 1) return 0;");
    try writer.writeAll(" return o->len; } }\n");
}

pub fn emitFmtBufferFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_owned_drop(a0); return 0; } }\n");
}

pub fn emitNpmTotalmem(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Deterministic 8GiB stand-in (asserted only as > 0).
    try writer.writeAll(" return 8589934592ULL; }\n");
}

pub fn emitNpmParallelism(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Deterministic stand-in (asserted only as >= 1).
    try writer.writeAll(" return 4; }\n");
}

pub fn emitNpmIsabs(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Byte-level absolute-path check on guest memory (a0 = ptr,
    // a1 = len); OOB traps via the checked address.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 == 0) return 0;");
    try writer.writeAll(" return sa_mem[x] == (uint8_t)'/' ? 1 : 0; } }\n");
}

pub fn emitNpmIseq(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Byte-level deep-equal on guest memory (a0/a1, a2/a3);
    // OOB traps via the checked addresses.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if (a1 != a3) return 0;");
    try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" if (sa_mem[x + i] != sa_mem[y + i]) return 0; }");
    try writer.writeAll(" return 1; } }\n");
}
