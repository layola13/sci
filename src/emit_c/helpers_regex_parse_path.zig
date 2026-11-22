const HelperDef = @import("types.zig").HelperDef;

pub const chunk_regex_parse_path: [10]HelperDef = .{
    .{ .name = "sa_regex_collect_block", .code =
    \\/* Match list block (guest): [0]=text base [8]=0x53414C58<<32 | count
    \\   [16]=group count, then per match n (start,end) pairs. */
    \\static sa_u64 sa_regex_collect_block(sa_regex_t *r, sa_u64 tp, sa_u64 tl) {
    \\  sa_u64 n = (sa_u64)r->rx.re_nsub + 1;
    \\  if (n > SA_REGEX_MAX_GROUPS) n = SA_REGEX_MAX_GROUPS;
    \\  { sa_u64 cap = 16;
    \\    sa_u64 cnt = 0;
    \\    sa_u64 blk = sa_alloc(24 + cap * n * 16);
    \\    regmatch_t pm[SA_REGEX_MAX_GROUPS];
    \\    sa_u64 pos = 0;
    \\    while (pos <= tl) {
    \\      if (sa_regex_exec_range(r, tp, tl, pos, pm, n) != 0) break;
    \\      if (cnt == cap) {
    \\        sa_u64 nblk = sa_alloc(24 + cap * 2 * n * 16);
    \\        uint32_t d = sa_checked_addr(nblk, 24 + cap * n * 16);
    \\        uint32_t s = sa_checked_addr(blk, 24 + cap * n * 16);
    \\        size_t i;
    \\        for (i = 0; i < (size_t)(24 + cap * n * 16); i++)
    \\          sa_mem[d + i] = sa_mem[s + i];
    \\        blk = nblk;
    \\        cap *= 2;
    \\      }
    \\      { sa_u64 g;
    \\        for (g = 0; g < n; g++) {
    \\          sa_store_u64(blk + 24 + (cnt * n + g) * 16,
    \\            (sa_u64)(sa_i64)pm[g].rm_so);
    \\          sa_store_u64(blk + 24 + (cnt * n + g) * 16 + 8,
    \\            (sa_u64)(sa_i64)pm[g].rm_eo);
    \\        } }
    \\      cnt++;
    \\      { sa_u64 ms = (sa_u64)(sa_i64)pm[0].rm_so;
    \\        sa_u64 me = (sa_u64)(sa_i64)pm[0].rm_eo;
    \\        pos = (me == ms) ? me + 1 : me; }
    \\    }
    \\    sa_store_u64(blk, tp);
    \\    sa_store_u64(blk + 8, (sa_u64)0x53414C5800000000ULL | cnt);
    \\    sa_store_u64(blk + 16, n);
    \\    return blk; }
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr", "sa_store_u64", "sa_regex_exec_range" } },
    .{ .name = "sa_regex_build_replace", .code =
    \\/* Replace result buffer block (guest): [0]=0x53414258<<32 [8]=len,
    \\   bytes at +16. Mirrors sa_std regexBuildReplace. */
    \\static sa_u64 sa_regex_build_replace(sa_regex_t *r, sa_u64 tp, sa_u64 tl,
    \\    sa_u64 rp, sa_u64 rl, int global) {
    \\  sa_u64 n = (sa_u64)r->rx.re_nsub + 1;
    \\  if (n > SA_REGEX_MAX_GROUPS) n = SA_REGEX_MAX_GROUPS;
    \\  { sa_u64 base = 0;
    \\    sa_u64 len = 0;
    \\    sa_u64 cap = 0;
    \\    regmatch_t pm[SA_REGEX_MAX_GROUPS];
    \\    uint32_t td = sa_checked_addr(tp, tl);
    \\    if (!global) {
    \\      if (sa_regex_exec_range(r, tp, tl, 0, pm, n) != 0) {
    \\        sa_rb_put(&base, &len, &cap, &sa_mem[td], tl);
    \\      } else {
    \\        sa_u64 ms = (sa_u64)(sa_i64)pm[0].rm_so;
    \\        sa_u64 me = (sa_u64)(sa_i64)pm[0].rm_eo;
    \\        if (ms > 0) sa_rb_put(&base, &len, &cap, &sa_mem[td], ms);
    \\        sa_regex_expand_into(&base, &len, &cap, tp, tl, pm, n, rp, rl);
    \\        if (me < tl)
    \\          sa_rb_put(&base, &len, &cap, &sa_mem[td + me], tl - me);
    \\      }
    \\    } else {
    \\      sa_u64 last = 0;
    \\      sa_u64 pos = 0;
    \\      while (pos <= tl) {
    \\        if (sa_regex_exec_range(r, tp, tl, pos, pm, n) != 0) break;
    \\        { sa_u64 ms = (sa_u64)(sa_i64)pm[0].rm_so;
    \\          sa_u64 me = (sa_u64)(sa_i64)pm[0].rm_eo;
    \\          if (ms > last)
    \\            sa_rb_put(&base, &len, &cap, &sa_mem[td + last], ms - last);
    \\          sa_regex_expand_into(&base, &len, &cap, tp, tl, pm, n, rp, rl);
    \\          last = me;
    \\          pos = (me == ms) ? me + 1 : me; }
    \\      }
    \\      if (last < tl)
    \\        sa_rb_put(&base, &len, &cap, &sa_mem[td + last], tl - last);
    \\    }
    \\    { sa_u64 blk = sa_alloc(16 + len);
    \\      sa_store_u64(blk, (sa_u64)0x5341425800000000ULL);
    \\      sa_store_u64(blk + 8, len);
    \\      if (len > 0) {
    \\        uint32_t d = sa_checked_addr(blk + 16, len);
    \\        uint32_t s = sa_checked_addr(base, len);
    \\        size_t i;
    \\        for (i = 0; i < (size_t)len; i++) sa_mem[d + i] = sa_mem[s + i];
    \\      }
    \\      return blk; } }
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr", "sa_store_u64", "sa_rb_put", "sa_regex_exec_range", "sa_regex_expand_into" } },
    .{ .name = "sa_regex_piece_put", .code =
    \\static void sa_regex_piece_put(sa_u64 *blk, sa_u64 *cap, sa_u64 *cnt,
    \\    sa_i64 so, sa_i64 eo) {
    \\  if (*cnt == *cap) {
    \\    sa_u64 nblk = sa_alloc(16 + *cap * 2 * 16);
    \\    uint32_t d = sa_checked_addr(nblk, 16 + *cap * 16);
    \\    uint32_t s = sa_checked_addr(*blk, 16 + *cap * 16);
    \\    size_t i;
    \\    for (i = 0; i < (size_t)(16 + *cap * 16); i++)
    \\      sa_mem[d + i] = sa_mem[s + i];
    \\    *blk = nblk;
    \\    *cap *= 2;
    \\  }
    \\  sa_store_u64(*blk + 16 + *cnt * 16, (sa_u64)so);
    \\  sa_store_u64(*blk + 16 + *cnt * 16 + 8, (sa_u64)eo);
    \\  *cnt += 1;
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr", "sa_store_u64" } },
    .{ .name = "sa_regex_split_block", .code =
    \\/* Split list block (guest): [0]=text base [8]=0x53415058<<32 | count,
    \\   then count (start,end) pairs; start -1 marks non-participating
    \\   groups. Ports sa_std regexSplitList (JS String.split semantics). */
    \\static sa_u64 sa_regex_split_block(sa_regex_t *r, sa_u64 tp, sa_u64 tl,
    \\    sa_u64 limit) {
    \\  sa_u64 n = (sa_u64)r->rx.re_nsub + 1;
    \\  if (n > SA_REGEX_MAX_GROUPS) n = SA_REGEX_MAX_GROUPS;
    \\  { sa_u64 lim = limit == 0 ? ~(sa_u64)0 : limit;
    \\    sa_u64 cap = 16;
    \\    sa_u64 cnt = 0;
    \\    sa_u64 blk = sa_alloc(16 + cap * 16);
    \\    regmatch_t pm[SA_REGEX_MAX_GROUPS];
    \\    if (tl == 0) {
    \\      if (sa_regex_exec_range(r, tp, tl, 0, pm, n) != 0)
    \\        sa_regex_piece_put(&blk, &cap, &cnt, 0, 0);
    \\    } else {
    \\      sa_u64 p = 0;
    \\      sa_u64 q = 0;
    \\      int done = 0;
    \\      while (!done && q < tl) {
    \\        if (cnt >= lim) break;
    \\        if (sa_regex_exec_range(r, tp, tl, q, pm, n) != 0) break;
    \\        { sa_u64 ms = (sa_u64)(sa_i64)pm[0].rm_so;
    \\          sa_u64 me = (sa_u64)(sa_i64)pm[0].rm_eo;
    \\          if (me == p) { q = me + 1; continue; }
    \\          sa_regex_piece_put(&blk, &cap, &cnt, (sa_i64)p, (sa_i64)ms);
    \\          { sa_u64 g;
    \\            for (g = 1; g < n; g++) {
    \\              if (cnt >= lim) break;
    \\              sa_regex_piece_put(&blk, &cap, &cnt,
    \\                (sa_i64)pm[g].rm_so, (sa_i64)pm[g].rm_eo);
    \\            } }
    \\          if (cnt >= lim) done = 1;
    \\          else { p = me; q = me; } }
    \\      }
    \\      if (!done && cnt < lim)
    \\        sa_regex_piece_put(&blk, &cap, &cnt, (sa_i64)p, (sa_i64)tl);
    \\    }
    \\    sa_store_u64(blk, tp);
    \\    sa_store_u64(blk + 8, (sa_u64)0x5341505800000000ULL | cnt);
    \\    return blk; }
    \\}
    , .deps = &.{ "sa_alloc", "sa_store_u64", "sa_regex_exec_range", "sa_regex_piece_put" } },
    .{ .name = "sa_json_parse_value", .code =
    \\static sa_json_node_t *sa_json_parse_value(const uint8_t *s, size_t n, size_t *pos, int depth) {
    \\  sa_json_node_t *nd; uint8_t c;
    \\  if (depth > SA_JSON_MAX_DEPTH) return 0;
    \\  while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\  if (*pos >= n) return 0;
    \\  c = s[*pos];
    \\  if (c == '{') {
    \\    sa_json_node_t *last = 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0; nd->kind = 7;
    \\    (*pos)++;
    \\    while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\    if (*pos < n && s[*pos] == '}') { (*pos)++; return nd; }
    \\    for (;;) {
    \\      sa_u64 kp = 0, kl = 0; sa_json_node_t *v;
    \\      while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\      if (!sa_json_string(s, n, pos, &kp, &kl)) return 0;
    \\      while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\      if (*pos >= n || s[*pos] != ':') return 0;
    \\      (*pos)++;
    \\      v = sa_json_parse_value(s, n, pos, depth + 1);
    \\      if (v == 0) return 0;
    \\      v->kptr = kp; v->klen = kl;
    \\      if (last == 0) nd->first = (sa_u64)(v - sa_json_nodes) + 1; else last->next = (sa_u64)(v - sa_json_nodes) + 1;
    \\      last = v;
    \\      while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\      if (*pos < n && s[*pos] == ',') { (*pos)++; continue; }
    \\      if (*pos < n && s[*pos] == '}') { (*pos)++; return nd; }
    \\      return 0;
    \\    }
    \\  }
    \\  if (c == '[') {
    \\    sa_json_node_t *last = 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0; nd->kind = 6;
    \\    (*pos)++;
    \\    while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\    if (*pos < n && s[*pos] == ']') { (*pos)++; return nd; }
    \\    for (;;) {
    \\      sa_json_node_t *v = sa_json_parse_value(s, n, pos, depth + 1);
    \\      if (v == 0) return 0;
    \\      if (last == 0) nd->first = (sa_u64)(v - sa_json_nodes) + 1; else last->next = (sa_u64)(v - sa_json_nodes) + 1;
    \\      last = v;
    \\      while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\      if (*pos < n && s[*pos] == ',') { (*pos)++; continue; }
    \\      if (*pos < n && s[*pos] == ']') { (*pos)++; return nd; }
    \\      return 0;
    \\    }
    \\  }
    \\  if (c == '"') {
    \\    sa_u64 p = 0, l = 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    if (!sa_json_string(s, n, pos, &p, &l)) return 0;
    \\    nd->kind = 5; nd->vptr = p; nd->vlen = l;
    \\    return nd;
    \\  }
    \\  if (c == 't') {
    \\    if (*pos + 4 > n || s[*pos+1] != 'r' || s[*pos+2] != 'u' || s[*pos+3] != 'e') return 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    *pos += 4; nd->kind = 1; nd->bval = 1;
    \\    return nd;
    \\  }
    \\  if (c == 'f') {
    \\    if (*pos + 5 > n || s[*pos+1] != 'a' || s[*pos+2] != 'l' || s[*pos+3] != 's' || s[*pos+4] != 'e') return 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    *pos += 5; nd->kind = 1; nd->bval = 0;
    \\    return nd;
    \\  }
    \\  if (c == 'n') {
    \\    if (*pos + 4 > n || s[*pos+1] != 'u' || s[*pos+2] != 'l' || s[*pos+3] != 'l') return 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    *pos += 4; nd->kind = 0;
    \\    return nd;
    \\  }
    \\  if (c == '-' || (c >= '0' && c <= '9')) {
    \\    size_t st = *pos; size_t j = *pos; int is_float = 0;
    \\    if (s[j] == '-') j++;
    \\    if (j >= n) return 0;
    \\    if (s[j] == '0') j++;
    \\    else if (s[j] >= '1' && s[j] <= '9') { while (j < n && s[j] >= '0' && s[j] <= '9') j++; }
    \\    else return 0;
    \\    if (j < n && s[j] == '.') {
    \\      is_float = 1; j++;
    \\      if (j >= n || s[j] < '0' || s[j] > '9') return 0;
    \\      while (j < n && s[j] >= '0' && s[j] <= '9') j++;
    \\    }
    \\    if (j < n && (s[j] == 'e' || s[j] == 'E')) {
    \\      size_t m;
    \\      is_float = 1; j++;
    \\      if (j < n && (s[j] == '+' || s[j] == '-')) j++;
    \\      m = j;
    \\      while (j < n && s[j] >= '0' && s[j] <= '9') j++;
    \\      if (m == j) return 0;
    \\    }
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    if (!is_float) {
    \\      sa_u64 mag = 0; size_t k = st; int neg = 0;
    \\      if (s[k] == '-') { neg = 1; k++; }
    \\      for (; k < j; k++) {
    \\        unsigned dg = (unsigned)(s[k] - '0');
    \\        if (mag > (~(sa_u64)0 - dg) / 10) break;
    \\        mag = mag * 10 + dg;
    \\      }
    \\      if (k == j && !neg && mag <= (sa_u64)9223372036854775807ULL) { nd->kind = 2; nd->ival = (sa_i64)mag; }
    \\      else if (k == j && neg && mag <= (sa_u64)9223372036854775808ULL) { nd->kind = 2; nd->ival = (sa_i64)(~(sa_u64)0 - mag + 1); }
    \\      else is_float = 1;
    \\    }
    \\    if (is_float) {
    \\      sa_u64 span = j - st;
    \\      sa_u64 tp = sa_alloc(span + 1);
    \\      uint32_t td = sa_checked_addr(tp, span + 1);
    \\      size_t q; for (q = 0; q < (size_t)span; q++) sa_mem[td + q] = s[st + q];
    \\      sa_mem[td + span] = 0; errno = 0;
    \\      union { sa_u64 u; double v; } t; t.v = strtod((const char *)&sa_mem[td], 0);
    \\      nd->kind = 3; nd->fbits = t.u;
    \\    }
    \\    *pos = j;
    \\    return nd;
    \\  }
    \\  return 0;
    \\}
    , .deps = &.{ "sa_json_new", "sa_json_string", "sa_utf8_enc" } },
    .{ .name = "sa_path_norm", .code =
    \\static sa_u64 sa_path_norm(const uint8_t *s, size_t n, uint8_t *o, size_t cap) {
    \\  size_t w = 0; size_t i = 0; int abs = (n > 0 && s[0] == '/');
    \\  int trail = (n > 1 && s[n - 1] == '/');
    \\  size_t base = abs ? 1 : 0;
    \\  if (abs) { if (w >= cap) return ~(sa_u64)0; o[w++] = '/'; }
    \\  while (i < n) {
    \\    while (i < n && s[i] == '/') i++;
    \\    if (i >= n) break;
    \\    size_t j = i; while (j < n && s[j] != '/') j++;
    \\    size_t sl = j - i;
    \\    if (sl == 1 && s[i] == '.') { }
    \\    else if (sl == 2 && s[i] == '.' && s[i + 1] == '.') {
    \\      size_t e = w;
    \\      if (w > base && o[w - 1] == '/') e--;
    \\      size_t ss = e;
    \\      while (ss > base && o[ss - 1] != '/') ss--;
    \\      if (w > base && !(e - ss == 2 && o[ss] == '.' && o[ss + 1] == '.')) { w = ss; if (w > base && o[w - 1] == '/') w--; }
    \\      else if (w == base && !abs) {
    \\        if (w + 2 > cap) return ~(sa_u64)0;
    \\        o[w++] = '.'; o[w++] = '.';
    \\      }
    \\      else if (w > base) {
    \\        if (w + 3 > cap) return ~(sa_u64)0;
    \\        o[w++] = '/'; o[w++] = '.'; o[w++] = '.';
    \\      }
    \\    } else {
    \\      if (w > base) { if (w + 1 > cap) return ~(sa_u64)0; o[w++] = '/'; }
    \\      if (w + sl > cap) return ~(sa_u64)0;
    \\      { size_t k; for (k = 0; k < sl; k++) o[w + k] = s[i + k]; }
    \\      w += sl;
    \\    }
    \\    i = j;
    \\  }
    \\  if (w == 0) { if (w + 1 > cap) return ~(sa_u64)0; o[w++] = abs ? '/' : '.'; }
    \\  else if (trail && o[w - 1] != '/') { if (w + 1 > cap) return ~(sa_u64)0; o[w++] = '/'; }
    \\  return (sa_u64)w;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_div_floor", .code =
    \\static sa_i64 sa_div_floor(sa_i64 a, sa_i64 b) { sa_i64 q = a / b; sa_i64 r = a % b; if (r != 0 && ((r < 0) != (b < 0))) q -= 1; return q; }
    , .deps = &.{} },
    .{ .name = "sa_mod_floor", .code =
    \\static sa_i64 sa_mod_floor(sa_i64 a, sa_i64 b) { sa_i64 r = a % b; if ((r != 0) && ((r < 0) != (b < 0))) r += b; return r; }
    , .deps = &.{} },
    .{ .name = "sa_civil_ymd", .code =
    \\static void sa_civil_ymd(sa_i64 ms, sa_i64 *y, sa_i64 *mo, sa_i64 *d) {
    \\  sa_i64 days = sa_div_floor(ms, 86400000);
    \\  sa_i64 z = days + 719468;
    \\  sa_i64 era = (z >= 0) ? sa_div_floor(z, 146097) : sa_div_floor(z - 146096, 146097);
    \\  sa_i64 doe = z - era * 146097;
    \\  sa_i64 yoe = sa_div_floor(doe - sa_div_floor(doe, 1460) + sa_div_floor(doe, 36524) - sa_div_floor(doe, 146096), 365);
    \\  sa_i64 yy = yoe + era * 400;
    \\  sa_i64 doy = doe - (365 * yoe + sa_div_floor(yoe, 4) - sa_div_floor(yoe, 100));
    \\  sa_i64 mp = sa_div_floor(5 * doy + 2, 153);
    \\  sa_i64 month = (mp < 10) ? mp + 3 : mp - 9;
    \\  *y = (month <= 2) ? yy + 1 : yy;
    \\  *mo = month;
    \\  *d = doy - sa_div_floor(153 * mp + 2, 5) + 1;
    \\}
    , .deps = &.{"sa_div_floor"} },
    .{ .name = "sa_puny_adapt", .code =
    \\static sa_u64 sa_puny_adapt(sa_u64 delta, sa_u64 numpoints, int first) {
    \\  sa_u64 k = 0;
    \\  delta = first ? delta / 700 : delta >> 1;
    \\  delta += delta / numpoints;
    \\  while (delta > ((36 - 1) * 26) / 2) { delta /= 36 - 1; k += 36; }
    \\  return k + (36 - 1 + 1) * delta / (delta + 38);
    \\}
    , .deps = &.{} },
};
