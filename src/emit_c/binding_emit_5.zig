const std = @import("std");

pub fn emitCookieParse(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Direct link: the real RFC 6265 parser in libsa_std.a;
    // the guest byte span is handed over as a host pointer
    // into linear memory, the returned handle passes through.
    try writer.writeAll(" return sa_cookie_parse_set_cookie(sa_glue_cptr(a0, a1), a1); }\n");
}

pub fn emitCookieLastError(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_last_error(&hp, &hn); sa_glue_out_str(a0, a1, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_free(a0); }\n");
}

pub fn emitCookieNew(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return sa_cookie_new(sa_glue_cptr(a0, a1), a1, sa_glue_cptr(a2, a3), a3); }\n");
}

pub fn emitCookieName(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_name(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieValue(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_value(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieDomain(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_domain(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookiePath(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_path(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieExpires(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { int64_t v = 0; int32_t st = sa_cookie_expires(a0, &v); sa_store_u64(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieMaxAge(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { int64_t v = 0; int32_t st = sa_cookie_max_age(a0, &v); sa_store_u64(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieFlags(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { int32_t x = 0, y = 0, z = 0; int32_t st = sa_cookie_flags(a0, &x, &y, &z); sa_store_u32(a1, (sa_u64)(uint32_t)x); sa_store_u32(a2, (sa_u64)(uint32_t)y); sa_store_u32(a3, (sa_u64)(uint32_t)z); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieSameSite(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t v = 0; int32_t st = sa_cookie_same_site(a0, &v); sa_store_u32(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieIsHostOnly(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { int32_t v = 0; int32_t st = sa_cookie_is_host_only(a0, &v); sa_store_u32(a1, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieSetDomain(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_domain(a0, sa_glue_cptr(a1, a2), a2); }\n");
}

pub fn emitCookieSetPath(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_path(a0, sa_glue_cptr(a1, a2), a2); }\n");
}

pub fn emitCookieSetExpires(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_expires(a0, (sa_i64)a1); }\n");
}

pub fn emitCookieSetMaxAge(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_max_age(a0, (sa_i64)a1); }\n");
}

pub fn emitCookieClearExpiry(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_clear_expiry(a0); }\n");
}

pub fn emitCookieSetSecure(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_secure(a0, (int32_t)a1); }\n");
}

pub fn emitCookieSetHttpOnly(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_http_only(a0, (int32_t)a1); }\n");
}

pub fn emitCookieSetPartitioned(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_partitioned(a0, (int32_t)a1); }\n");
}

pub fn emitCookieSetSameSite(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_same_site(a0, (uint32_t)a1); }\n");
}

pub fn emitCookieSerialize(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_serialize(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieSerializePair(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_serialize_pair(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieIsExpired(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { int32_t v = 0; int32_t st = sa_cookie_is_expired(a0, (sa_i64)a1, &v); sa_store_u32(a2, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieDomainMatch(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { int32_t v = 0; int32_t st = sa_cookie_domain_match(sa_glue_cptr(a0, a1), a1, sa_glue_cptr(a2, a3), a3, &v); sa_store_u32(a4, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookiePathMatch(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { int32_t v = 0; int32_t st = sa_cookie_path_match(sa_glue_cptr(a0, a1), a1, sa_glue_cptr(a2, a3), a3, &v); sa_store_u32(a4, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieHeaderPairCount(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_cookie_header_pair_count(sa_glue_cptr(a0, a1), a1, &v); sa_store_u64(a2, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitCookieHeaderPairAt(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return sa_cookie_header_pair_at(sa_glue_cptr(a0, a1), a1, a2); }\n");
}

pub fn emitCookieJarNew(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return sa_cookie_jar_new(); }\n");
}

pub fn emitCookieJarFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_free(a0); }\n");
}

pub fn emitCookieJarSetPolicy(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_set_policy(a0, (uint32_t)a1); }\n");
}
