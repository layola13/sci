pub fn emitEnvGet(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Real host environment via libc (the native binding reads
    // the same process env); the value is copied into an owned
    // buffer of kind 4, the env-buffer registry kind.
    try writer.writeAll(" { if (a1 > 4096) return 0; char kb[4097]; uint32_t s = sa_checked_addr(a0, (size_t)a1); sa_u64 i; for (i = 0; i < a1; i++) kb[i] = (char)sa_mem[s + i]; kb[a1] = 0; const char *v = getenv(kb); if (v == 0) return 0; size_t n = strlen(v); sa_u64 p = sa_alloc(n == 0 ? 1 : (sa_u64)n); uint32_t d = sa_checked_addr(p, n == 0 ? 1 : n); size_t j; for (j = 0; j < n; j++) sa_mem[d + j] = (uint8_t)v[j]; return sa_owned_new(p, (sa_u64)n, 4); } }\n");
}

pub fn emitEnvHas(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Status semantics mirror the native binding: 0 = present,
    // 3 = SA_STD_ERR_NOT_FOUND.
    try writer.writeAll(" { if (a1 > 4096) return 1; char kb[4097]; uint32_t s = sa_checked_addr(a0, (size_t)a1); sa_u64 i; for (i = 0; i < a1; i++) kb[i] = (char)sa_mem[s + i]; kb[a1] = 0; return getenv(kb) != 0 ? 0 : 3; } }\n");
}

pub fn emitEnvSetVar(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { if (a1 > 4096 || a3 > 1048576) return 1; char kb[4097]; char *vb = (char *)malloc(a3 + 1); if (vb == 0) return 6; uint32_t s = sa_checked_addr(a0, (size_t)a1); uint32_t t = sa_checked_addr(a2, (size_t)a3); sa_u64 i; for (i = 0; i < a1; i++) kb[i] = (char)sa_mem[s + i]; kb[a1] = 0; for (i = 0; i < a3; i++) { if (sa_mem[t + i] == 0) { free(vb); return 1; } vb[i] = (char)sa_mem[t + i]; } vb[a3] = 0; int rc = setenv(kb, vb, 1); free(vb); return rc == 0 ? 0 : 6; } }\n");
}

pub fn emitEnvRemoveVar(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { if (a1 > 4096) return 1; char kb[4097]; uint32_t s = sa_checked_addr(a0, (size_t)a1); sa_u64 i; for (i = 0; i < a1; i++) kb[i] = (char)sa_mem[s + i]; kb[a1] = 0; return unsetenv(kb) == 0 ? 0 : 6; } }\n");
}

pub fn emitEnvBufferData(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0); if (o == 0 || o->kind != 4) return 0; return o->ptr; } }\n");
}

pub fn emitEnvBufferLen(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0); if (o == 0 || o->kind != 4) return 0; return o->len; } }\n");
}

pub fn emitEnvBufferFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_owned_drop(a0); return 0; } }\n");
}

pub fn emitDenoBtoaHandle(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Standard-alphabet base64 with padding, matching the
    // native encoder; the result is an fmt buffer (kind 1),
    // consumed via sa_fmt_buffer_data/len/free as natively.
    // (The .deno_btoa tag below is the unrelated out-param
    // shape used by sa_deno_plugin_btoa.)
    try writer.writeAll(" { static const char T[65] = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"; uint32_t s = sa_checked_addr(a0, (size_t)a1); sa_u64 out_len = 4 * ((a1 + 2) / 3); sa_u64 p = sa_alloc(out_len == 0 ? 1 : out_len); uint32_t d = sa_checked_addr(p, out_len == 0 ? 1 : (size_t)out_len); sa_u64 i = 0, j = 0; while (i + 3 <= a1) { uint32_t v = ((uint32_t)sa_mem[s + i] << 16) | ((uint32_t)sa_mem[s + i + 1] << 8) | (uint32_t)sa_mem[s + i + 2]; sa_mem[d + j++] = (uint8_t)T[(v >> 18) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 12) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 6) & 63]; sa_mem[d + j++] = (uint8_t)T[v & 63]; i += 3; } if (a1 - i == 1) { uint32_t v = ((uint32_t)sa_mem[s + i] << 16); sa_mem[d + j++] = (uint8_t)T[(v >> 18) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 12) & 63]; sa_mem[d + j++] = 61; sa_mem[d + j++] = 61; } else if (a1 - i == 2) { uint32_t v = ((uint32_t)sa_mem[s + i] << 16) | ((uint32_t)sa_mem[s + i + 1] << 8); sa_mem[d + j++] = (uint8_t)T[(v >> 18) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 12) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 6) & 63]; sa_mem[d + j++] = 61; } return sa_owned_new(p, out_len, 1); } }\n");
}

pub fn emitDenoBtoa(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 > (~(sa_u64)0 - 2) / 4 * 3) return 1;");
    try writer.writeAll(" sa_u64 n = (a1 + 2) / 3 * 4;");
    try writer.writeAll(" sa_u64 p = sa_alloc(n == 0 ? 1 : n);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, n == 0 ? 1 : n);");
    try writer.writeAll(" size_t i = 0; sa_u64 w = 0;");
    try writer.writeAll(" while (i + 3 <= (size_t)a1) {");
    try writer.writeAll(" uint32_t v = ((uint32_t)sa_mem[x + i] << 16) | ((uint32_t)sa_mem[x + i + 1] << 8) | sa_mem[x + i + 2];");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 18) & 63];");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 12) & 63];");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 6) & 63];");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[v & 63];");
    try writer.writeAll(" i += 3; }");
    try writer.writeAll(" if (i < (size_t)a1) {");
    try writer.writeAll(" uint32_t v = (uint32_t)sa_mem[x + i] << 16;");
    try writer.writeAll(" size_t rem = (size_t)a1 - i;");
    try writer.writeAll(" if (rem == 2) v |= (uint32_t)sa_mem[x + i + 1] << 8;");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 18) & 63];");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 12) & 63];");
    try writer.writeAll(" if (rem == 2) sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 6) & 63]; else sa_mem[d + w++] = (uint8_t)'=';");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)'='; }");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
}

pub fn emitDenoAtob(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 % 4 != 0) return 1;");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 == 0 ? 1 : a1 / 4 * 3);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 == 0 ? 1 : a1 / 4 * 3);");
    try writer.writeAll(" sa_u64 w = 0; size_t i = 0;");
    try writer.writeAll(" while (i < (size_t)a1) {");
    try writer.writeAll(" int v[4]; size_t k; int pad = 0;");
    try writer.writeAll(" for (k = 0; k < 4; k++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + i + k];");
    try writer.writeAll(" if (c >= 'A' && c <= 'Z') v[k] = c - 'A';");
    try writer.writeAll(" else if (c >= 'a' && c <= 'z') v[k] = c - 'a' + 26;");
    try writer.writeAll(" else if (c >= '0' && c <= '9') v[k] = c - '0' + 52;");
    try writer.writeAll(" else if (c == '+') v[k] = 62;");
    try writer.writeAll(" else if (c == '/') v[k] = 63;");
    try writer.writeAll(" else if (c == '=' && k >= 2) { v[k] = 0; pad++; }");
    try writer.writeAll(" else return 1; }");
    try writer.writeAll(" if (pad > 2 || (pad > 0 && i + 4 < (size_t)a1)) return 1;");
    try writer.writeAll(" uint32_t t = ((uint32_t)v[0] << 18) | ((uint32_t)v[1] << 12) | ((uint32_t)v[2] << 6) | (uint32_t)v[3];");
    try writer.writeAll(" sa_mem[d + w++] = (uint8_t)(t >> 16);");
    try writer.writeAll(" if (pad < 2) sa_mem[d + w++] = (uint8_t)(t >> 8);");
    try writer.writeAll(" if (pad < 1) sa_mem[d + w++] = (uint8_t)t; i += 4; }");
    try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
}

pub fn emitDenoReadFile(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Real host read into fresh guest memory (mirrors the deno
    // plugin); 0 ok, 2 on any failure.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 == 0) return 2;");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[d + a1] = 0; }");
    try writer.writeAll(" if (!sa_policy_check(1, (const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], 0, 0)) return 10;");
    try writer.writeAll(" FILE *f = fopen((const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], \"rb\");");
    try writer.writeAll(" if (f == 0) return 2;");
    try writer.writeAll(" if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return 2; }");
    try writer.writeAll(" long sz = ftell(f);");
    try writer.writeAll(" if (sz < 0) { fclose(f); return 2; }");
    try writer.writeAll(" if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return 2; }");
    try writer.writeAll(" sa_u64 q = sa_alloc((sa_u64)sz == 0 ? 1 : (sa_u64)sz);");
    try writer.writeAll(" { uint32_t dd = sa_checked_addr(q, (sa_u64)sz == 0 ? 1 : (sa_u64)sz);");
    try writer.writeAll(" size_t got = fread(&sa_mem[dd], 1, (size_t)sz, f);");
    try writer.writeAll(" fclose(f);");
    try writer.writeAll(" if (got != (size_t)sz) return 2;");
    try writer.writeAll(" sa_store_u64(a2, q); sa_store_u64(a3, (sa_u64)sz); return 0; } } }\n");
}

pub fn emitDenoWriteFile(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
    try writer.writeAll(" if (a1 == 0) return 2;");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[d + a1] = 0; }");
    try writer.writeAll(" if (!sa_policy_check(1, (const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], 1, 0)) return 10;");
    try writer.writeAll(" FILE *f = fopen((const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], \"wb\");");
    try writer.writeAll(" if (f == 0) return 2;");
    try writer.writeAll(" { size_t w = 0; while (w < (size_t)a3) {");
    try writer.writeAll(" size_t n = fwrite(&sa_mem[y + w], 1, (size_t)a3 - w, f);");
    try writer.writeAll(" if (n == 0) { fclose(f); return 2; } w += n; } }");
    try writer.writeAll(" if (fclose(f) != 0) return 2;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitDenoRemove(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Non-recursive remove (files + empty dirs via libc
    // remove); recursive trees are out of scope for now.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 == 0) return 2;");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[d + a1] = 0; }");
    try writer.writeAll(" if (!sa_policy_check(1, (const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], 1, 0)) return 10;");
    try writer.writeAll(" if (remove((const char *)&sa_mem[sa_checked_addr(p, a1 + 1)]) != 0) return 2;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitDenoMkdir(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Recursive prefix walk (mkdir -p shape); EEXIST tolerated.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" if (a1 == 0) return 2;");
    try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
    try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
    try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
    try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
    try writer.writeAll(" sa_mem[d + a1] = 0; }");
    try writer.writeAll(" if (!sa_policy_check(1, (const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], 1, 0)) return 10;");
    try writer.writeAll(" { size_t i = (a2 != 0);");
    try writer.writeAll(" if (i == 0) {");
    try writer.writeAll(" if (sa_mkdir_wrap(&sa_mem[sa_checked_addr(p, a1 + 1)]) != 0) return 2;");
    try writer.writeAll(" } else {");
    try writer.writeAll(" size_t j; for (j = 1; j <= (size_t)a1; j++) {");
    try writer.writeAll(" if (j == (size_t)a1 || sa_mem[sa_checked_addr(p, a1 + 1) + j] == '/') {");
    try writer.writeAll(" uint8_t sv = sa_mem[sa_checked_addr(p, a1 + 1) + j];");
    try writer.writeAll(" sa_mem[sa_checked_addr(p, a1 + 1) + j] = 0;");
    try writer.writeAll(" if (sa_mkdir_wrap(&sa_mem[sa_checked_addr(p, a1 + 1)]) != 0 && errno != EEXIST) return 2;");
    try writer.writeAll(" sa_mem[sa_checked_addr(p, a1 + 1) + j] = sv; } } }");
    try writer.writeAll(" return 0; } } }\n");
}

pub fn emitHcWsRead(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; if (!w->aux2) { sa_store_u64(a2, 0); sa_store_u64(a3, 0); sa_store_u64(a4, 0); return 2; } sa_store_u64(a2, w->aux2 - 1); sa_store_u64(a3, w->aux0); sa_store_u64(a4, w->aux1); w->aux2 = 0; return 0; } }\n");
}

pub fn emitHcWsWrite(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; if (sa_nb_ws_closed_get(a0)) return 2; if (w->aux2) return 1; w->aux0 = a2; w->aux1 = a3; w->aux2 = a1 + 1; return 0; } }\n");
}

pub fn emitHcWsFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_nb_ws_meta_clear(a0); sa_http_drop(sa_http_objs, a0); return 0; } }\n");
}

pub fn emitHc2WsPoll(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 5; sa_store_u64(a3, 2 | (w->aux2 < w->aux1 ? 1 : 0) | (sa_nb_ws_closed_get(a0) ? 4 : 0)); return 0; } }\n");
}

pub fn emitHc2WsRead(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 5; if (w->aux2 >= w->aux1) { if (sa_nb_ws_closed_get(a0)) { sa_store_u64(a3, 0); sa_store_u64(a4, 0); return 2; } return 1; } sa_store_u64(a2, (sa_u64)sa_nb_ws_opcode_get(a0)); sa_store_u64(a3, w->aux0 + w->aux2); sa_store_u64(a4, w->aux1 - w->aux2); w->aux2 = w->aux1; return 0; } }\n");
}

pub fn emitHc2WsWrite(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 5; if (sa_nb_ws_closed_get(a0)) return 2; if (w->aux1 > w->aux2) return 1; w->aux0 = a2; w->aux1 = a3; w->aux2 = 0; sa_nb_ws_meta_set(a0, (int)a1, -1); sa_store_u64(a4, a3); return 0; } }\n");
}

pub fn emitHc2WsClose(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 5; sa_nb_ws_meta_set(a0, -1, 1); return 0; } }\n");
}

pub fn emitTimeUnixMs(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Real wall clock (mirrors the interpreter, not staged).
    try writer.writeAll(" { struct timespec ts;");
    try writer.writeAll(" if (!sa_policy_check(4, 0, 0, 0)) return 0;");
    try writer.writeAll(" if (clock_gettime(CLOCK_REALTIME, &ts) != 0) return 0;");
    try writer.writeAll(" return (sa_u64)((sa_i64)ts.tv_sec * 1000 + ts.tv_nsec / 1000000); } }\n");
}

pub fn emitTimeGetFullYear(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_i64 y, mo, d;");
    try writer.writeAll(" sa_civil_ymd((sa_i64)a0, &y, &mo, &d);");
    try writer.writeAll(" return (sa_u64)y; } }\n");
}

pub fn emitTimeGetMonth(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // 0-based like JS getMonth (mirrors the interpreter).
    try writer.writeAll(" { sa_i64 y, mo, d;");
    try writer.writeAll(" sa_civil_ymd((sa_i64)a0, &y, &mo, &d);");
    try writer.writeAll(" return (sa_u64)(mo - 1); } }\n");
}

pub fn emitTimeGetDate(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_i64 y, mo, d;");
    try writer.writeAll(" sa_civil_ymd((sa_i64)a0, &y, &mo, &d);");
    try writer.writeAll(" return (sa_u64)d; } }\n");
}

pub fn emitTimeParseIso(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Strict ISO YYYY-MM-DD[THH:MM:SS[.sss]][Z|+-HH:MM] to unix
    // millis; 0 ok (writes *out_ms, pre-zeroed), 1 invalid.
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" sa_store_u64(a2, 0);");
    try writer.writeAll(" size_t p = 0;");
    try writer.writeAll(" sa_i64 v = 0; size_t k; size_t q;");
    try writer.writeAll(" if ((size_t)a1 < 10) return 1;");
    try writer.writeAll(" for (k = 0; k < 4; k++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
    try writer.writeAll(" if (c < '0' || c > '9') return 1;");
    try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
    try writer.writeAll(" sa_i64 year = v; p = 4;");
    try writer.writeAll(" if (sa_mem[x + p] != '-') return 1; p++;");
    try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
    try writer.writeAll(" if (c < '0' || c > '9') return 1;");
    try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
    try writer.writeAll(" sa_i64 month = v; p += 2;");
    try writer.writeAll(" if (sa_mem[x + p] != '-') return 1; p++;");
    try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
    try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
    try writer.writeAll(" if (c < '0' || c > '9') return 1;");
    try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
    try writer.writeAll(" sa_i64 day = v; p += 2;");
    try writer.writeAll(" sa_i64 hour = 0; sa_i64 minute = 0;");
    try writer.writeAll(" sa_i64 second = 0; sa_i64 milli = 0;");
    try writer.writeAll(" if (p < (size_t)a1) {");
    try writer.writeAll(" uint8_t t = sa_mem[x + p];");
    try writer.writeAll(" if (t != 'T' && t != 't' && t != ' ') return 1; p++;");
    try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
    try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
    try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
    try writer.writeAll(" if (c < '0' || c > '9') return 1;");
    try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
    try writer.writeAll(" hour = v; p += 2;");
    try writer.writeAll(" if (p >= (size_t)a1 || sa_mem[x + p] != ':') return 1; p++;");
    try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
    try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
    try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
    try writer.writeAll(" if (c < '0' || c > '9') return 1;");
    try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
    try writer.writeAll(" minute = v; p += 2;");
    try writer.writeAll(" if (p >= (size_t)a1 || sa_mem[x + p] != ':') return 1; p++;");
    try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
    try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
    try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
    try writer.writeAll(" if (c < '0' || c > '9') return 1;");
    try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
    try writer.writeAll(" second = v; p += 2;");
    try writer.writeAll(" if (p < (size_t)a1 && sa_mem[x + p] == '.') { p++;");
    try writer.writeAll(" size_t fs = p;");
    try writer.writeAll(" while (p < (size_t)a1 && sa_mem[x + p] >= '0' && sa_mem[x + p] <= '9') p++;");
    try writer.writeAll(" size_t fl = p - fs;");
    try writer.writeAll(" if (fl == 0 || fl > 3) return 1;");
    try writer.writeAll(" v = 0; for (q = fs; q < p; q++)");
    try writer.writeAll(" v = v * 10 + (sa_i64)(sa_mem[x + q] - '0');");
    try writer.writeAll(" milli = fl == 1 ? v * 100 : (fl == 2 ? v * 10 : v); } }");
    try writer.writeAll(" sa_i64 offm = 0;");
    try writer.writeAll(" if (p < (size_t)a1) {");
    try writer.writeAll(" uint8_t z = sa_mem[x + p];");
    try writer.writeAll(" if (z == 'Z' || z == 'z') { p++; }");
    try writer.writeAll(" else if (z == '+' || z == '-') {");
    try writer.writeAll(" int neg = z == '-'; p++;");
    try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
    try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
    try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
    try writer.writeAll(" if (c < '0' || c > '9') return 1;");
    try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
    try writer.writeAll(" sa_i64 oh = v; p += 2;");
    try writer.writeAll(" if (p >= (size_t)a1 || sa_mem[x + p] != ':') return 1; p++;");
    try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
    try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
    try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
    try writer.writeAll(" if (c < '0' || c > '9') return 1;");
    try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
    try writer.writeAll(" sa_i64 om = v; p += 2;");
    try writer.writeAll(" if (oh > 23 || om > 59) return 1;");
    try writer.writeAll(" offm = oh * 60 + om; if (neg) offm = -offm;");
    try writer.writeAll(" } else return 1; }");
    try writer.writeAll(" if (p != (size_t)a1) return 1;");
    try writer.writeAll(" if (month < 1 || month > 12) return 1;");
    try writer.writeAll(" { int leap = (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));");
    try writer.writeAll(" sa_i64 dim = 31;");
    try writer.writeAll(" if (month == 2) dim = leap ? 29 : 28;");
    try writer.writeAll(" else if (month == 4 || month == 6 || month == 9 || month == 11) dim = 30;");
    try writer.writeAll(" if (day < 1 || day > dim) return 1; }");
    try writer.writeAll(" if (hour > 23 || minute > 59 || second > 59) return 1;");
    try writer.writeAll(" { sa_i64 yy = month <= 2 ? year - 1 : year;");
    try writer.writeAll(" sa_i64 era = yy >= 0 ? sa_div_floor(yy, 400) : sa_div_floor(yy - 399, 400);");
    try writer.writeAll(" sa_i64 yoe = yy - era * 400;");
    try writer.writeAll(" sa_i64 mp = sa_mod_floor(month - 3, 12);");
    try writer.writeAll(" sa_i64 doy = sa_div_floor(153 * mp + 2, 5) + day - 1;");
    try writer.writeAll(" sa_i64 doe = yoe * 365 + sa_div_floor(yoe, 4) - sa_div_floor(yoe, 100) + doy;");
    try writer.writeAll(" sa_i64 days = era * 146097 + doe - 719468;");
    try writer.writeAll(" sa_store_u64(a2, (sa_u64)(((days * 86400 + hour * 3600 + minute * 60 + second) * 1000 + milli) - offm * 60000));");
    try writer.writeAll(" return 0; } } }\n");
}

pub fn emitTimeSetField(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_i64 ms = (sa_i64)a0; sa_u64 f = a1; sa_i64 v = (sa_i64)a2;");
    try writer.writeAll(" sa_i64 day_ms = sa_mod_floor(ms, 86400000);");
    try writer.writeAll(" sa_i64 y, mo, d;");
    try writer.writeAll(" sa_civil_ymd(ms, &y, &mo, &d);");
    try writer.writeAll(" sa_i64 tod = day_ms / 3600000 * 3600000 + sa_mod_floor(day_ms, 3600000);");
    try writer.writeAll(" tod = tod / 60000 * 60000 + sa_mod_floor(day_ms, 60000);");
    try writer.writeAll(" tod = tod / 1000 * 1000 + sa_mod_floor(day_ms, 1000);");
    try writer.writeAll(" if (f == 0) y = v;");
    try writer.writeAll(" else if (f == 1) {");
    try writer.writeAll(" sa_i64 tm = y * 12 + v;");
    try writer.writeAll(" y = sa_div_floor(tm, 12); mo = sa_mod_floor(tm, 12) + 1; }");
    try writer.writeAll(" else if (f == 2) d = v;");
    try writer.writeAll(" else if (f == 3) tod = v * 3600000 + sa_mod_floor(tod, 3600000);");
    try writer.writeAll(" else if (f == 4) tod = (tod - sa_mod_floor(tod, 3600000)) + v * 60000 + sa_mod_floor(tod, 60000);");
    try writer.writeAll(" else if (f == 5) tod = (tod - sa_mod_floor(tod, 60000)) + v * 1000 + sa_mod_floor(tod, 1000);");
    try writer.writeAll(" else if (f == 6) tod = tod - sa_mod_floor(tod, 1000) + v;");
    try writer.writeAll(" else return ms;");
    try writer.writeAll(" { sa_i64 tm = y * 12 + (mo - 1);");
    try writer.writeAll(" sa_i64 y2 = sa_div_floor(tm, 12);");
    try writer.writeAll(" sa_i64 m2 = sa_mod_floor(tm, 12) + 1;");
    try writer.writeAll(" sa_i64 yy = m2 <= 2 ? y2 - 1 : y2;");
    try writer.writeAll(" sa_i64 era = yy >= 0 ? sa_div_floor(yy, 400) : sa_div_floor(yy - 399, 400);");
    try writer.writeAll(" sa_i64 yoe = yy - era * 400;");
    try writer.writeAll(" sa_i64 mp = sa_mod_floor(m2 - 3, 12);");
    try writer.writeAll(" sa_i64 doy = sa_div_floor(153 * mp + 2, 5) + d - 1;");
    try writer.writeAll(" sa_i64 doe = yoe * 365 + sa_div_floor(yoe, 4) - sa_div_floor(yoe, 100) + doy;");
    try writer.writeAll(" sa_i64 dys = era * 146097 + doe - 719468;");
    try writer.writeAll(" sa_i64 tdys = dys + sa_div_floor(tod, 86400000);");
    try writer.writeAll(" sa_i64 tnorm = tod - sa_div_floor(tod, 86400000) * 86400000;");
    try writer.writeAll(" return (sa_u64)((tdys * 86400) * 1000 + tnorm); } } }\n");
}
