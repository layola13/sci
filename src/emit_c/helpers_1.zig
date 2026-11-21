const HelperDef = @import("types.zig").HelperDef;

pub const chunk_1: [90]HelperDef = .{
    .{ .name = "sa_install_sigpipe_ignore", .code =
    \\#include <signal.h>
    \\static void sa_install_sigpipe_ignore(void) { static int done = 0; if (done) return; done = 1; signal(SIGPIPE, SIG_IGN); }
    , .deps = &.{} },
    .{ .name = "sa_panic", .code =
    \\static __attribute__((noreturn)) void sa_panic(sa_u64 code) { char b[24]; int n = 0; sa_u64 v = code; char t[24]; int m = 0; if (v == 0) t[m++] = '0'; while (v > 0) { t[m++] = (char)('0' + (v % 10)); v /= 10; } fputs("[sa-panic] code=", stderr); while (m > 0) b[n++] = t[--m]; fwrite(b, 1, (size_t)n, stderr); fputc('\n', stderr); exit(1); }
    , .deps = &.{} },
    .{ .name = "sa_policy_check", .code =
    \\#include <string.h>
    \\#include <time.h>
    \\/* ---- sa policy (16_policy phase 1; C port of sa_policy.zig) ----
    \\   Same policy JSON, same SA_POLICY_* env vars, same audit JSONL shape
    \\   and decision semantics as the native runtime. Lazily initialized on
    \\   first gated call; with no policy configured the backend stays in
    \\   legacy mode (everything allowed), exactly like the native default.
    \\   Categories: 0 net, 1 fs, 2 env, 3 run, 4 time, 5 random.
    \\   Modes: 0 allow, 1 deny, 2 allow-list, 3 audit, 4 ask. */
    \\typedef struct { char **items; size_t len; } sa_pol_list;
    \\typedef struct { int mode; sa_pol_list allow, read, write; } sa_pol_cat;
    \\static sa_pol_cat sa_pol_cats[6];
    \\static int sa_pol_state = 0; /* 0 uninit, 1 legacy, 2 policy */
    \\static char *sa_pol_audit_path = 0;
    \\static const char *sa_pol_cat_names[6] = { "net", "fs", "env", "run", "time", "random" };
    \\static void sa_pol_invalid(void) { fputs("[sa-policy] InvalidPolicy\n", stderr); exit(2); }
    \\static char *sa_pol_strdup_n(const char *s, size_t n) { char *p = (char *)malloc(n + 1); if (!p) exit(2); memcpy(p, s, n); p[n] = 0; return p; }
    \\typedef struct { const char *s; size_t len; size_t pos; } sa_pol_js;
    \\static void sa_pol_ws(sa_pol_js *j) { while (j->pos < j->len) { char c = j->s[j->pos]; if (c == ' ' || c == '\t' || c == '\n' || c == '\r') j->pos++; else break; } }
    \\static void sa_pol_expect(sa_pol_js *j, char c) { sa_pol_ws(j); if (j->pos >= j->len || j->s[j->pos] != c) sa_pol_invalid(); j->pos++; }
    \\static int sa_pol_peek(sa_pol_js *j) { sa_pol_ws(j); return j->pos < j->len ? j->s[j->pos] : -1; }
    \\static unsigned sa_pol_hex4(sa_pol_js *j) { unsigned v = 0; int i; for (i = 0; i < 4; i++) { char c; unsigned d; if (j->pos >= j->len) sa_pol_invalid(); c = j->s[j->pos++]; if (c >= '0' && c <= '9') d = (unsigned)(c - '0'); else if (c >= 'a' && c <= 'f') d = (unsigned)(c - 'a' + 10); else if (c >= 'A' && c <= 'F') d = (unsigned)(c - 'A' + 10); else sa_pol_invalid(); v = v * 16 + d; } return v; }
    \\static char *sa_pol_json_string(sa_pol_js *j) {
    \\  size_t cap = 16, n = 0; char *out;
    \\  sa_pol_expect(j, '"');
    \\  out = (char *)malloc(cap); if (!out) exit(2);
    \\  for (;;) {
    \\    char c; if (j->pos >= j->len) sa_pol_invalid(); c = j->s[j->pos++];
    \\    if (c == '"') break;
    \\    if (c == '\\') {
    \\      char e; if (j->pos >= j->len) sa_pol_invalid(); e = j->s[j->pos++];
    \\      if (e == 'u') { unsigned cp = sa_pol_hex4(j); char tmp[4]; int tn = 0;
    \\        if (cp >= 0xD800 && cp <= 0xDBFF) { /* lone surrogate half: replace */ cp = 0xFFFD; }
    \\        if (cp < 0x80) tmp[tn++] = (char)cp;
    \\        else if (cp < 0x800) { tmp[tn++] = (char)(0xC0 | (cp >> 6)); tmp[tn++] = (char)(0x80 | (cp & 0x3F)); }
    \\        else { tmp[tn++] = (char)(0xE0 | (cp >> 12)); tmp[tn++] = (char)(0x80 | ((cp >> 6) & 0x3F)); tmp[tn++] = (char)(0x80 | (cp & 0x3F)); }
    \\        if (n + (size_t)tn + 1 > cap) { while (n + (size_t)tn + 1 > cap) cap *= 2; out = (char *)realloc(out, cap); if (!out) exit(2); }
    \\        memcpy(out + n, tmp, (size_t)tn); n += (size_t)tn; continue;
    \\      }
    \\      switch (e) { case '"': c = '"'; break; case '\\': c = '\\'; break; case '/': c = '/'; break; case 'b': c = '\b'; break; case 'f': c = '\f'; break; case 'n': c = '\n'; break; case 'r': c = '\r'; break; case 't': c = '\t'; break; default: sa_pol_invalid(); }
    \\    }
    \\    if (n + 2 > cap) { cap *= 2; out = (char *)realloc(out, cap); if (!out) exit(2); }
    \\    out[n++] = c;
    \\  }
    \\  out[n] = 0; return out;
    \\}
    \\static void sa_pol_json_skip(sa_pol_js *j) {
    \\  int c = sa_pol_peek(j);
    \\  if (c == '"') { char *t = sa_pol_json_string(j); free(t); return; }
    \\  if (c == '{') { j->pos++; if (sa_pol_peek(j) == '}') { j->pos++; return; } for (;;) { char *k = sa_pol_json_string(j); free(k); sa_pol_expect(j, ':'); sa_pol_json_skip(j); if (sa_pol_peek(j) == ',') { j->pos++; continue; } sa_pol_expect(j, '}'); return; } }
    \\  if (c == '[') { j->pos++; if (sa_pol_peek(j) == ']') { j->pos++; return; } for (;;) { sa_pol_json_skip(j); if (sa_pol_peek(j) == ',') { j->pos++; continue; } sa_pol_expect(j, ']'); return; } }
    \\  while (j->pos < j->len) { char ch = j->s[j->pos]; if ((ch >= '0' && ch <= '9') || ch == '-' || ch == '+' || ch == '.' || ch == 'e' || ch == 'E' || (ch >= 'a' && ch <= 'z')) j->pos++; else break; }
    \\}
    \\static sa_pol_list sa_pol_json_string_list(sa_pol_js *j) {
    \\  sa_pol_list out; out.items = 0; out.len = 0; size_t cap = 0;
    \\  sa_pol_expect(j, '[');
    \\  if (sa_pol_peek(j) == ']') { j->pos++; return out; }
    \\  for (;;) {
    \\    char *v = sa_pol_json_string(j);
    \\    if (out.len == cap) { cap = cap ? cap * 2 : 4; out.items = (char **)realloc(out.items, cap * sizeof(char *)); if (!out.items) exit(2); }
    \\    out.items[out.len++] = v;
    \\    if (sa_pol_peek(j) == ',') { j->pos++; continue; }
    \\    sa_pol_expect(j, ']'); return out;
    \\  }
    \\}
    \\static int sa_pol_cat_index(const char *name) { int i; for (i = 0; i < 6; i++) if (strcmp(name, sa_pol_cat_names[i]) == 0) return i; return -1; }
    \\static void sa_pol_parse_category(sa_pol_js *j, int cat) {
    \\  sa_pol_cat *cp = &sa_pol_cats[cat]; int has_lists = 0; int has_mode = 0;
    \\  cp->mode = 1;
    \\  sa_pol_expect(j, '{');
    \\  if (sa_pol_peek(j) == '}') { j->pos++; return; }
    \\  for (;;) {
    \\    char *key = sa_pol_json_string(j);
    \\    sa_pol_expect(j, ':');
    \\    if (strcmp(key, "mode") == 0) {
    \\      char *m = sa_pol_json_string(j); has_mode = 1;
    \\      if (strcmp(m, "allow") == 0) cp->mode = 0;
    \\      else if (strcmp(m, "deny") == 0) cp->mode = 1;
    \\      else if (strcmp(m, "allow-list") == 0) cp->mode = 2;
    \\      else if (strcmp(m, "audit") == 0) cp->mode = 3;
    \\      else if (strcmp(m, "ask") == 0) cp->mode = 4;
    \\      else sa_pol_invalid();
    \\      free(m);
    \\    } else if (strcmp(key, "allow") == 0) {
    \\      if (cat == 1 || cat == 4 || cat == 5) sa_pol_invalid();
    \\      cp->allow = sa_pol_json_string_list(j); has_lists = 1;
    \\    } else if (strcmp(key, "read") == 0) {
    \\      if (cat != 1) sa_pol_invalid();
    \\      cp->read = sa_pol_json_string_list(j); has_lists = 1;
    \\    } else if (strcmp(key, "write") == 0) {
    \\      if (cat != 1) sa_pol_invalid();
    \\      cp->write = sa_pol_json_string_list(j); has_lists = 1;
    \\    } else sa_pol_invalid();
    \\    free(key);
    \\    if (sa_pol_peek(j) == ',') { j->pos++; continue; }
    \\    sa_pol_expect(j, '}'); break;
    \\  }
    \\  if (has_lists && !has_mode) cp->mode = 2;
    \\}
    \\static char *sa_pol_sink = 0;
    \\static void sa_pol_parse(const char *text) {
    \\  sa_pol_js j; int i; j.s = text; j.len = strlen(text); j.pos = 0;
    \\  for (i = 0; i < 6; i++) { sa_pol_cats[i].mode = 1; sa_pol_cats[i].allow.items = 0; sa_pol_cats[i].allow.len = 0; sa_pol_cats[i].read.items = 0; sa_pol_cats[i].read.len = 0; sa_pol_cats[i].write.items = 0; sa_pol_cats[i].write.len = 0; }
    \\  sa_pol_expect(&j, '{');
    \\  if (sa_pol_peek(&j) == '}') { j.pos++; }
    \\  else for (;;) {
    \\    char *key = sa_pol_json_string(&j);
    \\    sa_pol_expect(&j, ':');
    \\    if (strcmp(key, "permissions") == 0) {
    \\      sa_pol_expect(&j, '{');
    \\      if (sa_pol_peek(&j) == '}') { j.pos++; }
    \\      else for (;;) {
    \\        char *name = sa_pol_json_string(&j); int cat;
    \\        sa_pol_expect(&j, ':');
    \\        cat = sa_pol_cat_index(name); if (cat < 0) sa_pol_invalid();
    \\        free(name);
    \\        sa_pol_parse_category(&j, cat);
    \\        if (sa_pol_peek(&j) == ',') { j.pos++; continue; }
    \\        sa_pol_expect(&j, '}'); break;
    \\      }
    \\    } else if (strcmp(key, "audit") == 0) {
    \\      sa_pol_expect(&j, '{');
    \\      if (sa_pol_peek(&j) == '}') { j.pos++; }
    \\      else for (;;) {
    \\        char *ak = sa_pol_json_string(&j);
    \\        sa_pol_expect(&j, ':');
    \\        if (strcmp(ak, "sink") == 0) { sa_pol_sink = sa_pol_json_string(&j); }
    \\        else if (strcmp(ak, "events") == 0) { sa_pol_list ev = sa_pol_json_string_list(&j); size_t k; for (k = 0; k < ev.len; k++) free(ev.items[k]); free(ev.items); }
    \\        else sa_pol_invalid();
    \\        free(ak);
    \\        if (sa_pol_peek(&j) == ',') { j.pos++; continue; }
    \\        sa_pol_expect(&j, '}'); break;
    \\      }
    \\    } else sa_pol_invalid();
    \\    free(key);
    \\    if (sa_pol_peek(&j) == ',') { j.pos++; continue; }
    \\    sa_pol_expect(&j, '}'); break;
    \\  }
    \\  sa_pol_ws(&j); if (j.pos != j.len) sa_pol_invalid();
    \\}
    \\static void sa_pol_audit(const char *catname, const char *resource, const char *decision, const char *source) {
    \\  FILE *f; struct timespec ts; unsigned long long ns; const char *p;
    \\  if (!sa_pol_audit_path) return;
    \\  f = fopen(sa_pol_audit_path, "a"); if (!f) return;
    \\  clock_gettime(CLOCK_REALTIME, &ts);
    \\  ns = (unsigned long long)ts.tv_sec * 1000000000ull + (unsigned long long)ts.tv_nsec;
    \\  fputs("{\"ts_ns\":", f); fprintf(f, "%llu", ns);
    \\  fputs(",\"context\":1,\"category\":\"", f); fputs(catname, f);
    \\  fputs("\",\"resource\":\"", f);
    \\  for (p = resource; *p; p++) { unsigned char c = (unsigned char)*p; if (c == '"' || c == '\\') { fputc('\\', f); fputc(c, f); } else if (c == '\n') fputs("\\n", f); else if (c == '\r') fputs("\\r", f); else if (c == '\t') fputs("\\t", f); else if (c < 0x20) fprintf(f, "\\u%04x", c); else fputc(c, f); }
    \\  fputs("\",\"decision\":\"", f); fputs(decision, f);
    \\  fputs("\",\"source\":\"", f); fputs(source, f);
    \\  fputs("\"}\n", f);
    \\  fclose(f);
    \\}
    \\static void sa_pol_init(void) {
    \\  const char *aa; const char *text; const char *file; int i;
    \\  if (sa_pol_state != 0) return;
    \\  sa_pol_state = 1;
    \\  aa = getenv("SA_POLICY_ALLOW_ALL");
    \\  if (aa && strcmp(aa, "1") == 0) {
    \\    const char *af;
    \\    for (i = 0; i < 6; i++) sa_pol_cats[i].mode = 0;
    \\    sa_pol_state = 2;
    \\    af = getenv("SA_AUDIT_FILE"); if (af) sa_pol_audit_path = sa_pol_strdup_n(af, strlen(af));
    \\    fputs("[sa-policy] allow-all policy engaged via SA_POLICY_ALLOW_ALL (audit trace)\n", stderr);
    \\    sa_pol_audit("run", "SA_POLICY_ALLOW_ALL", "allow-all", "env");
    \\    return;
    \\  }
    \\  text = getenv("SA_POLICY_JSON");
    \\  if (!text) {
    \\    file = getenv("SA_POLICY_FILE");
    \\    if (file) {
    \\      FILE *f = fopen(file, "rb"); long sz; char *buf;
    \\      if (!f) { fputs("[sa-policy] SA_POLICY_FILE is set but cannot be opened\n", stderr); exit(2); }
    \\      if (fseek(f, 0, SEEK_END) != 0) { fclose(f); fputs("[sa-policy] SA_POLICY_FILE cannot be read\n", stderr); exit(2); }
    \\      sz = ftell(f); if (sz < 0) { fclose(f); fputs("[sa-policy] SA_POLICY_FILE cannot be read\n", stderr); exit(2); }
    \\      if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); fputs("[sa-policy] SA_POLICY_FILE cannot be read\n", stderr); exit(2); }
    \\      buf = (char *)malloc((size_t)sz + 1); if (!buf) exit(2);
    \\      if (sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) { fclose(f); fputs("[sa-policy] SA_POLICY_FILE cannot be read\n", stderr); exit(2); }
    \\      fclose(f); buf[sz] = 0;
    \\      sa_pol_parse(buf);
    \\      sa_pol_state = 2;
    \\      { const char *af = getenv("SA_AUDIT_FILE"); if (af) sa_pol_audit_path = sa_pol_strdup_n(af, strlen(af)); else if (sa_pol_sink && strncmp(sa_pol_sink, "file://", 7) == 0) sa_pol_audit_path = sa_pol_strdup_n(sa_pol_sink + 7, strlen(sa_pol_sink + 7)); }
    \\      return;
    \\    }
    \\  }
    \\  if (text) {
    \\    sa_pol_parse(text);
    \\    sa_pol_state = 2;
    \\    { const char *af = getenv("SA_AUDIT_FILE"); if (af) sa_pol_audit_path = sa_pol_strdup_n(af, strlen(af)); else if (sa_pol_sink && strncmp(sa_pol_sink, "file://", 7) == 0) sa_pol_audit_path = sa_pol_strdup_n(sa_pol_sink + 7, strlen(sa_pol_sink + 7)); }
    \\    return;
    \\  }
    \\  { const char *req = getenv("SA_POLICY_REQUIRED"); if (req && strcmp(req, "1") == 0) { fputs("[sa-policy] SA_POLICY_REQUIRED is set but no policy was provided (set SA_POLICY_JSON, SA_POLICY_FILE, or SA_POLICY_ALLOW_ALL=1)\n", stderr); exit(1); } }
    \\}
    \\static int sa_pol_list_has(sa_pol_list *l, const char *v) { size_t i; for (i = 0; i < l->len; i++) if (strcmp(l->items[i], v) == 0) return 1; return 0; }
    \\static int sa_pol_fs_allows(sa_pol_list *l, const char *path) {
    \\  size_t i;
    \\  for (i = 0; i < l->len; i++) {
    \\    const char *entry = l->items[i]; size_t plen = strlen(entry);
    \\    while (plen > 0 && entry[plen - 1] == '/') plen--;
    \\    if (strlen(path) == plen && strncmp(path, entry, plen) == 0) return 1;
    \\    if (strlen(path) > plen && strncmp(path, entry, plen) == 0 && path[plen] == '/') return 1;
    \\  }
    \\  return 0;
    \\}
    \\static int sa_pol_ipv4(const char *t, unsigned *out) {
    \\  unsigned v = 0; int count = 0; const char *p = t;
    \\  for (;;) { unsigned oct = 0; int digits = 0; while (*p >= '0' && *p <= '9') { oct = oct * 10 + (unsigned)(*p - '0'); p++; digits++; if (digits > 3) return 0; } if (digits == 0 || oct > 255) return 0; v = v * 256 + oct; count++; if (count == 4) { if (*p != 0) return 0; *out = v; return 1; } if (*p != '.') return 0; p++; }
    \\}
    \\static int sa_pol_net_match(const char *entry, const char *host, unsigned port) {
    \\  const char *colon = strrchr(entry, ':'); const char *slash; size_t hlen; char hbuf[256];
    \\  if (!colon) return 0;
    \\  if (!(colon[1] == '*' && colon[2] == 0)) { unsigned ep = 0; const char *p; for (p = colon + 1; *p; p++) { if (*p < '0' || *p > '9') return 0; ep = ep * 10 + (unsigned)(*p - '0'); } if (ep != port) return 0; }
    \\  hlen = (size_t)(colon - entry); if (hlen >= sizeof(hbuf)) return 0; memcpy(hbuf, entry, hlen); hbuf[hlen] = 0;
    \\  slash = strchr(hbuf, '/');
    \\  if (slash) {
    \\    unsigned prefix_len = 0; const char *p; unsigned network, host_ip; char ipbuf[64]; size_t ilen = (size_t)(slash - hbuf);
    \\    if (ilen >= sizeof(ipbuf)) return 0; memcpy(ipbuf, hbuf, ilen); ipbuf[ilen] = 0;
    \\    for (p = slash + 1; *p; p++) { if (*p < '0' || *p > '9') return 0; prefix_len = prefix_len * 10 + (unsigned)(*p - '0'); }
    \\    if (prefix_len > 32) return 0;
    \\    if (!sa_pol_ipv4(ipbuf, &network)) return 0;
    \\    if (!sa_pol_ipv4(host, &host_ip)) return 0;
    \\    if (prefix_len == 0) return 1;
    \\    { unsigned div = 1u << (32 - prefix_len); return (network / div) == (host_ip / div); }
    \\  }
    \\  { size_t i; if (strlen(host) != hlen) return 0; for (i = 0; i < hlen; i++) { char a = hbuf[i], b = host[i]; if (a >= 'A' && a <= 'Z') a = (char)(a + 32); if (b >= 'A' && b <= 'Z') b = (char)(b + 32); if (a != b) return 0; } return 1; }
    \\}
    \\/* Returns nonzero when the acquisition is allowed. On audit-mode allows
    \\   and on every denial an audit event is written (best-effort). */
    \\static int sa_policy_check(int cat, const char *res, int write, unsigned port) {
    \\  sa_pol_cat *cp; int decision; /* 0 allow, 1 deny, 2 allow_audit, 3 deny_ask */
    \\  char keybuf[1024]; const char *key;
    \\  sa_pol_init();
    \\  if (sa_pol_state == 1) return 1;
    \\  cp = &sa_pol_cats[cat];
    \\  switch (cp->mode) {
    \\    case 0: decision = 0; break;
    \\    case 1: decision = 1; break;
    \\    case 3: decision = 2; break;
    \\    case 4: decision = 3; break;
    \\    default: /* allow-list */
    \\      if (cat == 0) { size_t i; decision = 1; for (i = 0; i < cp->allow.len; i++) if (sa_pol_net_match(cp->allow.items[i], res, port)) { decision = 0; break; } }
    \\      else if (cat == 1) decision = sa_pol_fs_allows(write ? &cp->write : &cp->read, res) ? 0 : 1;
    \\      else if (cat == 2 || cat == 3) decision = sa_pol_list_has(&cp->allow, res) ? 0 : 1;
    \\      else decision = 1;
    \\      break;
    \\  }
    \\  if (cat == 0) { snprintf(keybuf, sizeof(keybuf), "%s:%u", res, port); key = keybuf; }
    \\  else if (cat == 1) { snprintf(keybuf, sizeof(keybuf), "%s:%s", write ? "write" : "read", res); key = keybuf; }
    \\  else if (cat == 2 || cat == 3) key = res;
    \\  else key = sa_pol_cat_names[cat];
    \\  if (decision == 0) return 1;
    \\  if (decision == 2) { sa_pol_audit(sa_pol_cat_names[cat], key, "allow", "policy-audit"); return 1; }
    \\  sa_pol_audit(sa_pol_cat_names[cat], key, "deny", decision == 3 ? "ask-unhandled" : "policy");
    \\  return 0;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_ok_none", .code =
    \\static sa_u64 sa_ok_none(void) { return 0; }
    , .deps = &.{} },
    .{ .name = "sa_ok_val", .code =
    \\static sa_u64 sa_ok_val(sa_u64 v) { (void)v; return v; }
    , .deps = &.{} },
    .{ .name = "sa_truthy", .code =
    \\static int sa_truthy(sa_u64 v) { return v != 0; }
    , .deps = &.{} },
    .{ .name = "sa_align", .code =
    \\static sa_u64 sa_align(sa_u64 n, sa_u64 a) { return (n + (a - 1)) & ~(a - 1); }
    , .deps = &.{} },
    .{ .name = "sa_alloc", .code =
    \\static sa_u64 sa_alloc(sa_u64 size) {
    \\  size = sa_align(size, 8); if (size == 0) size = 8;
    \\  { uint32_t best = 0; uint32_t best_prev = 0; uint32_t best_size = 0xFFFFFFFFu;
    \\    { uint32_t prev = 0; uint32_t cur = sa_free_head;
    \\      while (cur != 0) {
    \\        uint32_t bsize = (uint32_t)sa_load_u32(cur);
    \\        if ((sa_u64)bsize >= size && bsize < best_size) { best = cur; best_prev = prev; best_size = bsize; if ((sa_u64)bsize == size) break; }
    \\        prev = cur; cur = (uint32_t)sa_load_u32((sa_u64)cur + 8);
    \\      } }
    \\    if (best != 0) {
    \\      uint32_t cur = best; uint32_t prev = best_prev; uint32_t bsize = best_size;
    \\      uint32_t next = (uint32_t)sa_load_u32((sa_u64)cur + 8);
    \\      if ((sa_u64)bsize - size >= 32) {
    \\        uint32_t nb = cur + 8 + (uint32_t)size;
    \\        sa_store_u32(nb, (sa_u64)(bsize - (uint32_t)size - 8));
    \\        sa_store_u32((sa_u64)nb + 4, 0xF2EE0B10u);
    \\        sa_store_u32((sa_u64)nb + 8, (sa_u64)next);
    \\        if (prev != 0) sa_store_u32((sa_u64)prev + 8, (sa_u64)nb); else sa_free_head = nb;
    \\        sa_store_u32(cur, size);
    \\      } else {
    \\        if (prev != 0) sa_store_u32((sa_u64)prev + 8, (sa_u64)next); else sa_free_head = next;
    \\      }
    \\      sa_store_u32((sa_u64)cur + 4, 0x5A110C4Bu);
    \\      { uint32_t i; for (i = 0; i < (uint32_t)size; i++) sa_mem[cur + 8 + i] = 0; }
    \\      return (sa_u64)cur + 8;
    \\    } }
    \\  uint32_t base = sa_brk;
    \\  { sa_u64 nb = (sa_u64)base + size + 8; if (nb > (sa_u64)sizeof(sa_mem)) sa_trap("out of memory (bump)"); sa_brk = (uint32_t)nb; } // NOLINT(bugprone-misplaced-widening-cast): nb range-checked above
    \\  { uint32_t i; for (i = 0; i < (uint32_t)(size + 8); i++) sa_mem[base + i] = 0; }
    \\  sa_mem[base] = (uint8_t)(size & 0xFFu); sa_mem[base + 1] = (uint8_t)((size >> 8) & 0xFFu);
    \\  sa_mem[base + 2] = (uint8_t)((size >> 16) & 0xFFu); sa_mem[base + 3] = (uint8_t)((size >> 24) & 0xFFu);
    \\  sa_store_u32((sa_u64)base + 4, 0x5A110C4Bu);
    \\  return (sa_u64)base + 8;
    \\}
    , .deps = &.{ "sa_align", "sa_load_u32", "sa_store_u32" } },
    .{ .name = "sa_salloc", .code =
    \\static sa_u64 sa_salloc(sa_u64 size) { return sa_alloc(size); }
    , .deps = &.{"sa_alloc"} },
    .{ .name = "sa_free", .code =
    \\static sa_u64 sa_free(sa_u64 ptr) {
    \\  if (ptr < 65536 + 8 || ptr >= (sa_u64)sa_brk) return 0;
    \\  { uint32_t base = (uint32_t)ptr - 8;
    \\    if ((uint32_t)sa_load_u32((sa_u64)base + 4) != 0x5A110C4Bu) return 0;
    \\    uint32_t size = (uint32_t)sa_load_u32(base);
    \\    uint32_t end = base + 8 + size;
    \\    uint32_t pred = 0; uint32_t succ = 0; uint32_t succ_prev = 0;
    \\    { uint32_t prev = 0; uint32_t cur = sa_free_head;
    \\      while (cur != 0) {
    \\        uint32_t csize = (uint32_t)sa_load_u32(cur);
    \\        if (cur == end) { succ = cur; succ_prev = prev; }
    \\        if (cur + 8 + csize == base) pred = cur;
    \\        prev = cur; cur = (uint32_t)sa_load_u32((sa_u64)cur + 8);
    \\      } }
    \\    if (succ != 0) {
    \\      uint32_t ssize = (uint32_t)sa_load_u32(succ);
    \\      uint32_t snext = (uint32_t)sa_load_u32((sa_u64)succ + 8);
    \\      if (succ_prev != 0) sa_store_u32((sa_u64)succ_prev + 8, (sa_u64)snext); else sa_free_head = snext;
    \\      size += 8 + ssize;
    \\    }
    \\    sa_store_u32((sa_u64)base + 4, 0xF2EE0B10u);
    \\    if (pred != 0) {
    \\      uint32_t psize = (uint32_t)sa_load_u32(pred);
    \\      sa_store_u32(pred, (sa_u64)(psize + 8 + size));
    \\    } else {
    \\      sa_store_u32(base, (sa_u64)size);
    \\      sa_store_u32((sa_u64)base + 8, (sa_u64)sa_free_head);
    \\      sa_free_head = base;
    \\    } }
    \\  return 0;
    \\}
    , .deps = &.{ "sa_load_u32", "sa_store_u32" } },
    .{ .name = "sa_ptr_add", .code =
    \\static sa_u64 sa_ptr_add(sa_u64 base, sa_u64 off) { return base + off; }
    , .deps = &.{} },
    .{ .name = "sa_addr", .code =
    \\static uint32_t sa_addr(sa_u64 a) { return (uint32_t)(a & 0xFFFFFFFFu); }
    , .deps = &.{} },
    .{ .name = "sa_checked_addr", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, size) signature
    \\static uint32_t sa_checked_addr(sa_u64 a, size_t sz) {
    \\  uint32_t x = sa_addr(a);
    \\  if ((size_t)x + sz > (size_t)sizeof(sa_mem)) sa_trap("oob linear-memory access");
    \\  return x;
    \\}
    , .deps = &.{"sa_addr"} },
    .{ .name = "sa_load_u8", .code =
    \\static sa_u64 sa_load_u8(sa_u64 a) { return (sa_u64)sa_mem[sa_checked_addr(a, 1)]; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_i8", .code =
    \\static sa_u64 sa_load_i8(sa_u64 a) { return (sa_u64)(sa_i64)(int8_t)sa_mem[sa_checked_addr(a, 1)]; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_u16", .code =
    \\static sa_u64 sa_load_u16(sa_u64 a) { uint32_t x = sa_checked_addr(a, 2); return (sa_u64)((uint16_t)((uint16_t)sa_mem[x] | ((uint16_t)sa_mem[x + 1] << 8))); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_i16", .code =
    \\static sa_u64 sa_load_i16(sa_u64 a) { uint32_t x = sa_checked_addr(a, 2); int16_t v = (int16_t)((uint16_t)sa_mem[x] | ((uint16_t)sa_mem[x + 1] << 8)); return (sa_u64)(sa_i64)v; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_u32", .code =
    \\static sa_u64 sa_load_u32(sa_u64 a) { uint32_t x = sa_checked_addr(a, 4); return (sa_u64)((uint32_t)sa_mem[x] | ((uint32_t)sa_mem[x + 1] << 8) | ((uint32_t)sa_mem[x + 2] << 16) | ((uint32_t)sa_mem[x + 3] << 24)); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_i32", .code =
    \\static sa_u64 sa_load_i32(sa_u64 a) { uint32_t x = sa_checked_addr(a, 4); int32_t v = (int32_t)((uint32_t)sa_mem[x] | ((uint32_t)sa_mem[x + 1] << 8) | ((uint32_t)sa_mem[x + 2] << 16) | ((uint32_t)sa_mem[x + 3] << 24)); return (sa_u64)(sa_i64)v; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_u64", .code =
    \\static sa_u64 sa_load_u64(sa_u64 a) { uint32_t x = sa_checked_addr(a, 8); uint64_t v = 0; unsigned k; for (k = 0; k < 8; k++) v |= ((uint64_t)sa_mem[x + k]) << (k * 8); return v; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_f32", .code =
    \\static sa_u64 sa_load_f32(sa_u64 a) { return sa_load_u32(a) & 0xFFFFFFFFULL; }
    , .deps = &.{"sa_load_u32"} },
    .{ .name = "sa_load_f64", .code =
    \\static sa_u64 sa_load_f64(sa_u64 a) { return sa_load_u64(a); }
    , .deps = &.{"sa_load_u64"} },
    .{ .name = "sa_store_u8", .code =
    \\static void sa_store_u8(sa_u64 a, sa_u64 v) { sa_mem[sa_checked_addr(a, 1)] = (uint8_t)(v & 0xFFu); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_store_u16", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
    \\static void sa_store_u16(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 2); sa_mem[x] = (uint8_t)(v & 0xFFu); sa_mem[x + 1] = (uint8_t)((v >> 8) & 0xFFu); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_store_u32", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
    \\static void sa_store_u32(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 4); unsigned k; for (k = 0; k < 4; k++) sa_mem[x + k] = (uint8_t)((v >> (k * 8)) & 0xFFu); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_store_u64", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
    \\static void sa_store_u64(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 8); unsigned k; for (k = 0; k < 8; k++) sa_mem[x + k] = (uint8_t)((v >> (k * 8)) & 0xFFu); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_store_f32", .code =
    \\static void sa_store_f32(sa_u64 a, sa_u64 v) { sa_store_u32(a, v & 0xFFFFFFFFULL); }
    , .deps = &.{"sa_store_u32"} },
    .{ .name = "sa_store_f64", .code =
    \\static void sa_store_f64(sa_u64 a, sa_u64 v) { sa_store_u64(a, v); }
    , .deps = &.{"sa_store_u64"} },
    .{ .name = "sa_add", .code =
    \\static sa_u64 sa_add(sa_u64 a, sa_u64 b) { return a + b; }
    , .deps = &.{} },
    .{ .name = "sa_sub", .code =
    \\static sa_u64 sa_sub(sa_u64 a, sa_u64 b) { return a - b; }
    , .deps = &.{} },
    .{ .name = "sa_mul", .code =
    \\static sa_u64 sa_mul(sa_u64 a, sa_u64 b) { return a * b; }
    , .deps = &.{} },
    .{ .name = "sa_sdiv", .code =
    \\static sa_u64 sa_sdiv(sa_u64 a, sa_u64 b) { if ((sa_i64)b==0) sa_trap("div by zero"); return (sa_u64)((sa_i64)a / (sa_i64)b); }
    , .deps = &.{} },
    .{ .name = "sa_udiv", .code =
    \\static sa_u64 sa_udiv(sa_u64 a, sa_u64 b) { if (b==0) sa_trap("div by zero"); return a / b; }
    , .deps = &.{} },
    .{ .name = "sa_srem", .code =
    \\static sa_u64 sa_srem(sa_u64 a, sa_u64 b) { if ((sa_i64)b==0) sa_trap("rem by zero"); return (sa_u64)((sa_i64)a % (sa_i64)b); }
    , .deps = &.{} },
    .{ .name = "sa_urem", .code =
    \\static sa_u64 sa_urem(sa_u64 a, sa_u64 b) { if (b==0) sa_trap("rem by zero"); return a % b; }
    , .deps = &.{} },
    .{ .name = "sa_band", .code =
    \\static sa_u64 sa_band(sa_u64 a, sa_u64 b) { return a & b; }
    , .deps = &.{} },
    .{ .name = "sa_bor", .code =
    \\static sa_u64 sa_bor(sa_u64 a, sa_u64 b) { return a | b; }
    , .deps = &.{} },
    .{ .name = "sa_bxor", .code =
    \\static sa_u64 sa_bxor(sa_u64 a, sa_u64 b) { return a ^ b; }
    , .deps = &.{} },
    .{ .name = "sa_bnot", .code =
    \\static sa_u64 sa_bnot(sa_u64 a) { return ~a; }
    , .deps = &.{} },
    .{ .name = "sa_neg", .code =
    \\static sa_u64 sa_neg(sa_u64 a) { return (sa_u64)(-(sa_i64)a); }
    , .deps = &.{} },
    .{ .name = "sa_shl", .code =
    \\static sa_u64 sa_shl(sa_u64 a, sa_u64 b) { return a << (b & 63); }
    , .deps = &.{} },
    .{ .name = "sa_lshr", .code =
    \\static sa_u64 sa_lshr(sa_u64 a, sa_u64 b) { return a >> (b & 63); }
    , .deps = &.{} },
    .{ .name = "sa_ashr", .code =
    \\static sa_u64 sa_ashr(sa_u64 a, sa_u64 b) { return (sa_u64)((sa_i64)a >> (b & 63)); }
    , .deps = &.{} },
    .{ .name = "sa_eq", .code =
    \\static sa_u64 sa_eq(sa_u64 a, sa_u64 b) { return a == b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_ne", .code =
    \\static sa_u64 sa_ne(sa_u64 a, sa_u64 b) { return a != b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_slt", .code =
    \\static sa_u64 sa_slt(sa_u64 a, sa_u64 b) { return (sa_i64)a < (sa_i64)b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_sle", .code =
    \\static sa_u64 sa_sle(sa_u64 a, sa_u64 b) { return (sa_i64)a <= (sa_i64)b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_sgt", .code =
    \\static sa_u64 sa_sgt(sa_u64 a, sa_u64 b) { return (sa_i64)a > (sa_i64)b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_sge", .code =
    \\static sa_u64 sa_sge(sa_u64 a, sa_u64 b) { return (sa_i64)a >= (sa_i64)b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_ult", .code =
    \\static sa_u64 sa_ult(sa_u64 a, sa_u64 b) { return a < b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_ule", .code =
    \\static sa_u64 sa_ule(sa_u64 a, sa_u64 b) { return a <= b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_ugt", .code =
    \\static sa_u64 sa_ugt(sa_u64 a, sa_u64 b) { return a > b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_uge", .code =
    \\static sa_u64 sa_uge(sa_u64 a, sa_u64 b) { return a >= b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_bits_f64", .code =
    \\static double sa_bits_f64(sa_u64 v) { union { sa_u64 u; double d; } t; t.u = v; return t.d; }
    , .deps = &.{} },
    .{ .name = "sa_f64_bits", .code =
    \\static sa_u64 sa_f64_bits(double d) { union { sa_u64 u; double d; } t; t.d = d; return t.u; }
    , .deps = &.{} },
    .{ .name = "sa_bits_f32", .code =
    \\static float sa_bits_f32(sa_u64 v) { union { uint32_t u; float f; } t; t.u = (uint32_t)v; return t.f; }
    , .deps = &.{} },
    .{ .name = "sa_f32_bits", .code =
    \\static sa_u64 sa_f32_bits(float f) { union { uint32_t u; float f; } t; t.f = f; return (sa_u64)t.u; }
    , .deps = &.{} },
    .{ .name = "sa_fadd", .code =
    \\static sa_u64 sa_fadd(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)+sa_bits_f64(b)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fsub", .code =
    \\static sa_u64 sa_fsub(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)-sa_bits_f64(b)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fmul", .code =
    \\static sa_u64 sa_fmul(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)*sa_bits_f64(b)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fdiv", .code =
    \\static sa_u64 sa_fdiv(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)/sa_bits_f64(b)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fneg", .code =
    \\static sa_u64 sa_fneg(sa_u64 a) { return sa_f64_bits(-sa_bits_f64(a)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fcmp_eq", .code =
    \\static sa_u64 sa_fcmp_eq(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)==sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_ne", .code =
    \\static sa_u64 sa_fcmp_ne(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)!=sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_lt", .code =
    \\static sa_u64 sa_fcmp_lt(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)<sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_le", .code =
    \\static sa_u64 sa_fcmp_le(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)<=sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_gt", .code =
    \\static sa_u64 sa_fcmp_gt(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)>sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_ge", .code =
    \\static sa_u64 sa_fcmp_ge(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)>=sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_trunc_i1", .code =
    \\static sa_u64 sa_cvt_trunc_i1(sa_u64 v){return v&1;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_i8", .code =
    \\static sa_u64 sa_cvt_trunc_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_i16", .code =
    \\static sa_u64 sa_cvt_trunc_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_i32", .code =
    \\static sa_u64 sa_cvt_trunc_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_i64", .code =
    \\static sa_u64 sa_cvt_trunc_i64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_u8", .code =
    \\static sa_u64 sa_cvt_trunc_u8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_u16", .code =
    \\static sa_u64 sa_cvt_trunc_u16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_u32", .code =
    \\static sa_u64 sa_cvt_trunc_u32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_u64", .code =
    \\static sa_u64 sa_cvt_trunc_u64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_ptr", .code =
    \\static sa_u64 sa_cvt_trunc_ptr(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i1", .code =
    \\static sa_u64 sa_cvt_zext_i1(sa_u64 v){return v&1;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i8", .code =
    \\static sa_u64 sa_cvt_zext_i8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i16", .code =
    \\static sa_u64 sa_cvt_zext_i16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i32", .code =
    \\static sa_u64 sa_cvt_zext_i32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i64", .code =
    \\static sa_u64 sa_cvt_zext_i64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_u8", .code =
    \\static sa_u64 sa_cvt_zext_u8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_u16", .code =
    \\static sa_u64 sa_cvt_zext_u16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_u32", .code =
    \\static sa_u64 sa_cvt_zext_u32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_u64", .code =
    \\static sa_u64 sa_cvt_zext_u64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_ptr", .code =
    \\static sa_u64 sa_cvt_zext_ptr(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i1", .code =
    \\static sa_u64 sa_cvt_sext_i1(sa_u64 v){return (sa_u64)(sa_i64)(v&1? -1:0);}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i8", .code =
    \\static sa_u64 sa_cvt_sext_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
    , .deps = &.{} },
};
