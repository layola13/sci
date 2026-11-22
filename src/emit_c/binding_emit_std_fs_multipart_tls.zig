const std = @import("std");

pub fn emitStdFsExists(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Status-code shape (mirror native): 0 exists, NOT_FOUND 3
    // missing, INVALID_ARGUMENT 1 on bad input, ACCESS 4 on
    // permission errors, IO 6 otherwise.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 == 0) return 1;");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[d + a1] = 0; }");
    try writer.writeAll(" if (sa_access_wrap(&sa_mem[sa_checked_addr(p, a1 + 1)]) == 0) return 0;");
    try writer.writeAll(" if (errno == ENOENT || errno == ENOTDIR) return 3;");
    try writer.writeAll(" if (errno == EACCES) return 4;");
    try writer.writeAll(" return 6; } }\n");
}

pub fn emitNbCompressSupported(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u64(a0, 1); return 0; } }\n");
}

pub fn emitNbCompressEncode(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_nb_deflate((int)a0, (uint32_t)a1, a2, a3); } }\n");
}

pub fn emitNbCompressDecode(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_nb_undeflate((int)a0, (uint32_t)a1, a2, a3); } }\n");
}

pub fn emitNbBufData(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_nb_buf_t *b = sa_nb_buf_find(a0); return b ? (sa_u64)b->addr : 0; } }\n");
}

pub fn emitNbBufLen(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_nb_buf_t *b = sa_nb_buf_find(a0); return b ? b->len : 0; } }\n");
}

pub fn emitNbBufFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_nb_buf_drop(a0) ? 0 : 2; } }\n");
}

pub fn emitMpParse(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_parse(a0, a1, a2, a3, a4); } }\n");
}

pub fn emitMpFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_mp_t *mp = sa_mp_find(a0); if (!mp) return 3; mp->h = 0; return 0; } }\n");
}

pub fn emitMpCount(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_mp_t *mp = sa_mp_find(a0); sa_u64 c = 0, so, sn; if (!mp) return 0; while (sa_mp_seek(mp, c, &so, &sn)) c++; return c; } }\n");
}

pub fn emitMpPartName(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_field(a0, a1, 0, a2, a4, a3); } }\n");
}

pub fn emitMpPartFilename(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_field(a0, a1, 1, a2, a4, a3); } }\n");
}

pub fn emitMpPartContentType(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_field(a0, a1, 2, a2, a4, a3); } }\n");
}

pub fn emitMpPartHeader(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_header(a0, a1, a2, a3, a4, a6, a5); } }\n");
}

pub fn emitMpPartBody(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_part_body(a0, a1, a2, a3); } }\n");
}

pub fn emitMpBuilderNew(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_builder_new(0, 0, a0); } }\n");
}

pub fn emitMpBuilderFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_mp_t *mp = sa_mp_find(a0); if (!mp) return 3; mp->h = 0; return 0; } }\n");
}

pub fn emitMpBuilderAddField(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_add_field(a0, a1, a2, a3, a4, 0, 0, 0, 0, 0, 0, 0); } }\n");
}

pub fn emitMpBuilderAddFile(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_add_field(a0, a1, a2, 0, 0, 1, a3, a4, a5, a6, a7, a8); } }\n");
}

pub fn emitMpBuilderBoundary(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_bnd_out(a0, a1, a3, a2); } }\n");
}

pub fn emitMpBuilderContentType(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_ctype_out(a0, a1, a3, a2); } }\n");
}

pub fn emitMpBuilderFinish(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return sa_mp_builder_finish(a0, a1); } }\n");
}

pub fn emitSshSupported(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u64(a0, 0); return 0; } }\n");
}

pub fn emitSshBufData(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return 0; } }\n");
}

pub fn emitSshBufLen(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return 0; } }\n");
}

pub fn emitSshBufFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return 0; } }\n");
}

pub fn emitTlscfgNew(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Direct link: the real config registry in libsa_std.a;
    // the handle value passes through, only the out slot is
    // translated into guest memory.
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_tls_client_config_new(&v); sa_store_u64(a0, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTlscfgFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_free(a0); }\n");
}

pub fn emitTlscfgSetServerName(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_set_server_name(a0, sa_glue_cptr(a1, a2), a2); }\n");
}

pub fn emitTlscfgAddCaFile(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_add_ca_file(a0, sa_glue_cptr(a1, a2), a2); }\n");
}

pub fn emitTlscfgAddCaMemory(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // The PEM validation is OpenSSL's, inside libsa_std.a:
    // malformed PEM fails with -22 exactly as natively.
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_add_ca_memory(a0, sa_glue_cptr(a1, a2), a2); }\n");
}

pub fn emitTlscfgSetInsecure(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_set_insecure_no_verification(a0, (uint32_t)a1); }\n");
}
