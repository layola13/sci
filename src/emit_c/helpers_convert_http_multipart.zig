const HelperDef = @import("types.zig").HelperDef;

pub const chunk_convert_http_multipart: [76]HelperDef = .{
    .{ .name = "sa_cvt_sext_i16", .code =
    \\static sa_u64 sa_cvt_sext_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i32", .code =
    \\static sa_u64 sa_cvt_sext_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i64", .code =
    \\static sa_u64 sa_cvt_sext_i64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_u8", .code =
    \\static sa_u64 sa_cvt_sext_u8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_u16", .code =
    \\static sa_u64 sa_cvt_sext_u16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_u32", .code =
    \\static sa_u64 sa_cvt_sext_u32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_u64", .code =
    \\static sa_u64 sa_cvt_sext_u64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_ptr", .code =
    \\static sa_u64 sa_cvt_sext_ptr(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sitofp_f32", .code =
    \\static sa_u64 sa_cvt_sitofp_f32(sa_u64 v){return sa_f32_bits((float)(sa_i64)v);}
    , .deps = &.{"sa_f32_bits"} },
    .{ .name = "sa_cvt_sitofp_f64", .code =
    \\static sa_u64 sa_cvt_sitofp_f64(sa_u64 v){return sa_f64_bits((double)(sa_i64)v);}
    , .deps = &.{"sa_f64_bits"} },
    .{ .name = "sa_cvt_uitofp_f32", .code =
    \\static sa_u64 sa_cvt_uitofp_f32(sa_u64 v){return sa_f32_bits((float)v);}
    , .deps = &.{"sa_f32_bits"} },
    .{ .name = "sa_cvt_uitofp_f64", .code =
    \\static sa_u64 sa_cvt_uitofp_f64(sa_u64 v){return sa_f64_bits((double)v);}
    , .deps = &.{"sa_f64_bits"} },
    .{ .name = "sa_cvt_fptosi_i1", .code =
    \\static sa_u64 sa_cvt_fptosi_i1(sa_u64 v){return ((sa_i64)sa_bits_f64(v))&1;}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_i8", .code =
    \\static sa_u64 sa_cvt_fptosi_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_i16", .code =
    \\static sa_u64 sa_cvt_fptosi_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_i32", .code =
    \\static sa_u64 sa_cvt_fptosi_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_i64", .code =
    \\static sa_u64 sa_cvt_fptosi_i64(sa_u64 v){return (sa_u64)(sa_i64)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_u8", .code =
    \\static sa_u64 sa_cvt_fptosi_u8(sa_u64 v){return (sa_u64)(uint8_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_u16", .code =
    \\static sa_u64 sa_cvt_fptosi_u16(sa_u64 v){return (sa_u64)(uint16_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_u32", .code =
    \\static sa_u64 sa_cvt_fptosi_u32(sa_u64 v){return (sa_u64)(uint32_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_u64", .code =
    \\static sa_u64 sa_cvt_fptosi_u64(sa_u64 v){return (sa_u64)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_ptr", .code =
    \\static sa_u64 sa_cvt_fptosi_ptr(sa_u64 v){return (sa_u64)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptrunc_f32", .code =
    \\static sa_u64 sa_cvt_fptrunc_f32(sa_u64 v){return sa_f32_bits((float)sa_bits_f64(v));}
    , .deps = &.{ "sa_bits_f64", "sa_f32_bits" } },
    .{ .name = "sa_cvt_fpext_f64", .code =
    \\static sa_u64 sa_cvt_fpext_f64(sa_u64 v){float f=sa_bits_f32(v); return sa_f64_bits((double)f);}
    , .deps = &.{ "sa_bits_f32", "sa_f64_bits" } },
    .{ .name = "sa_cvt_bitcast_i1", .code =
    \\static sa_u64 sa_cvt_bitcast_i1(sa_u64 v){return v&1;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_i8", .code =
    \\static sa_u64 sa_cvt_bitcast_i8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_u8", .code =
    \\static sa_u64 sa_cvt_bitcast_u8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_i16", .code =
    \\static sa_u64 sa_cvt_bitcast_i16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_u16", .code =
    \\static sa_u64 sa_cvt_bitcast_u16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_i32", .code =
    \\static sa_u64 sa_cvt_bitcast_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)(uint32_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_u32", .code =
    \\static sa_u64 sa_cvt_bitcast_u32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_i64", .code =
    \\static sa_u64 sa_cvt_bitcast_i64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_u64", .code =
    \\static sa_u64 sa_cvt_bitcast_u64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_f32", .code =
    \\static sa_u64 sa_cvt_bitcast_f32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_f64", .code =
    \\static sa_u64 sa_cvt_bitcast_f64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_ptr", .code =
    \\static sa_u64 sa_cvt_bitcast_ptr(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_print_bytes", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, len) signature
    \\static sa_u64 sa_print_bytes(sa_u64 addr, sa_u64 len) { uint32_t a=sa_addr(addr); if ((size_t)a+(size_t)len>sizeof(sa_mem)) sa_trap("print oob"); fwrite(&sa_mem[a],1,(size_t)len,stdout); return 0; }
    , .deps = &.{"sa_addr"} },
    .{ .name = "sa_f32_to_f64", .code =
    \\static sa_u64 sa_f32_to_f64(sa_u64 v) { return sa_f64_bits((double)sa_bits_f32(v)); }
    , .deps = &.{ "sa_bits_f32", "sa_f64_bits" } },
    .{ .name = "sa_f64_to_f32", .code =
    \\static sa_u64 sa_f64_to_f32(sa_u64 v) { return sa_f32_bits((float)sa_bits_f64(v)); }
    , .deps = &.{ "sa_bits_f64", "sa_f32_bits" } },
    .{ .name = "sa_fadd32", .code =
    \\static sa_u64 sa_fadd32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)+sa_bits_f32(b)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fsub32", .code =
    \\static sa_u64 sa_fsub32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)-sa_bits_f32(b)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fmul32", .code =
    \\static sa_u64 sa_fmul32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)*sa_bits_f32(b)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fdiv32", .code =
    \\static sa_u64 sa_fdiv32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)/sa_bits_f32(b)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fneg32", .code =
    \\static sa_u64 sa_fneg32(sa_u64 a) { return sa_f32_bits(-sa_bits_f32(a)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fcmp_eq32", .code =
    \\static sa_u64 sa_fcmp_eq32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)==sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_ne32", .code =
    \\static sa_u64 sa_fcmp_ne32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)!=sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_lt32", .code =
    \\static sa_u64 sa_fcmp_lt32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)<sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_le32", .code =
    \\static sa_u64 sa_fcmp_le32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)<=sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_gt32", .code =
    \\static sa_u64 sa_fcmp_gt32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)>sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_ge32", .code =
    \\static sa_u64 sa_fcmp_ge32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)>=sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_srcmask", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (value, width, sign) signature
    \\static sa_u64 sa_srcmask(sa_u64 v, unsigned w, int sgn) {
    \\  if (w >= 64) return v;
    \\  if (w == 32) return sgn ? (sa_u64)(sa_i64)(int32_t)(uint32_t)v : (sa_u64)(uint32_t)v;
    \\  if (w == 1) return v & 1u;
    \\  { sa_u64 m = (w == 64) ? ~(sa_u64)0 : ((((sa_u64)1) << w) - 1); sa_u64 r = v & m;
    \\    if (sgn && (r >> (w - 1)) & 1u) { r |= ~m; } return r; }
    \\}
    , .deps = &.{} },
    .{ .name = "sa_fnaddr", .code =
    \\static sa_u64 sa_fnaddr(int i) { return (sa_u64)(uint64_t)(1000000 + i); }
    , .deps = &.{} },
    .{ .name = "sa_http_find", .code =
    \\static sa_http_obj_t *sa_http_find(sa_http_obj_t *t, sa_u64 h) { unsigned i; for (i = 0; i < SA_HTTP_MAX_OBJS; i++) if (t[i].h == h) return &t[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_http_slot", .code =
    \\static sa_http_obj_t *sa_http_slot(sa_http_obj_t *t) { unsigned i; for (i = 0; i < SA_HTTP_MAX_OBJS; i++) if (t[i].h == 0) return &t[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_http_drop", .code =
    \\static void sa_http_drop(sa_http_obj_t *t, sa_u64 h) { sa_http_obj_t *o = sa_http_find(t, h); if (o != 0) o->h = 0; }
    , .deps = &.{"sa_http_find"} },
    .{ .name = "sa_nb_buf_find", .code =
    \\typedef struct { sa_u64 h; uint32_t addr; sa_u64 len; } sa_nb_buf_t;
    \\static sa_nb_buf_t sa_nb_bufs[64];
    \\static sa_u64 sa_nb_next = 1;
    \\static sa_nb_buf_t *sa_nb_buf_find(sa_u64 h) { unsigned i; if (h == 0) return 0; for (i = 0; i < 64; i++) if (sa_nb_bufs[i].h == h) return &sa_nb_bufs[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_nb_buf_new", .code =
    \\static sa_u64 sa_nb_buf_new(uint32_t addr, sa_u64 len) { unsigned i; for (i = 0; i < 64; i++) if (sa_nb_bufs[i].h == 0) { sa_u64 h = sa_nb_next++; sa_nb_bufs[i].h = h; sa_nb_bufs[i].addr = addr; sa_nb_bufs[i].len = len; return h; } return 0; }
    , .deps = &.{"sa_nb_buf_find"} },
    .{ .name = "sa_nb_buf_drop", .code =
    \\static int sa_nb_buf_drop(sa_u64 h) { sa_nb_buf_t *b = sa_nb_buf_find(h); if (!b) return 0; b->h = 0; return 1; }
    , .deps = &.{"sa_nb_buf_find"} },
    .{ .name = "sa_nb_crc32", .code =
    \\static uint32_t sa_nb_crc_tab[256];
    \\static int sa_nb_crc_ready = 0;
    \\static uint32_t sa_nb_crc32(uint32_t addr, sa_u64 len) {
    \\  uint32_t c; sa_u64 i; unsigned k;
    \\  if (!sa_nb_crc_ready) { for (k = 0; k < 256; k++) { uint32_t x = k; int j; for (j = 0; j < 8; j++) x = (x & 1) ? (0xEDB88320u ^ (x >> 1)) : (x >> 1); sa_nb_crc_tab[k] = x; } sa_nb_crc_ready = 1; }
    \\  c = 0xFFFFFFFFu;
    \\  for (i = 0; i < len; i++) c = sa_nb_crc_tab[(c ^ sa_mem[addr + i]) & 0xFF] ^ (c >> 8);
    \\  return c ^ 0xFFFFFFFFu;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_nb_adler32", .code =
    \\static uint32_t sa_nb_adler32(uint32_t addr, sa_u64 len) {
    \\  uint32_t a = 1, b = 0; sa_u64 i;
    \\  for (i = 0; i < len; i++) { a += sa_mem[addr + i]; if (a >= 65521) a -= 65521; b += a; if (b >= 65521) b -= 65521; }
    \\  return (b << 16) | a;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_nb_deflate", .code =
    \\static int sa_nb_deflate(int fmt, uint32_t ia, sa_u64 ilen, sa_u64 out_slot) {
    \\  uint32_t oa; sa_u64 cap, pos = 0, off = 0;
    \\  if (fmt < 1 || fmt > 4) return 1;
    \\  if (fmt == 4) return 8;
    \\  cap = ilen + (ilen / 65535 + 1) * 5 + 32;
    \\  oa = (uint32_t)sa_alloc(cap);
    \\  if (fmt == 1) { int k; for (k = 0; k < 10; k++) sa_mem[oa + pos++] = (uint8_t)((k == 0) ? 0x1F : (k == 1) ? 0x8B : (k == 2) ? 8 : 0); }
    \\  else if (fmt == 2) { sa_mem[oa + pos++] = 0x78; sa_mem[oa + pos++] = 0x9C; }
    \\  while (1) {
    \\    sa_u64 chunk = ilen - off; sa_u64 j; int fin; uint16_t nc;
    \\    if (chunk > 65535) chunk = 65535;
    \\    fin = (off + chunk >= ilen);
    \\    sa_mem[oa + pos++] = (uint8_t)(fin ? 1 : 0);
    \\    sa_mem[oa + pos++] = (uint8_t)(chunk & 0xFF); sa_mem[oa + pos++] = (uint8_t)((chunk >> 8) & 0xFF);
    \\    nc = (uint16_t)~(uint16_t)chunk;
    \\    sa_mem[oa + pos++] = (uint8_t)(nc & 0xFF); sa_mem[oa + pos++] = (uint8_t)((nc >> 8) & 0xFF);
    \\    for (j = 0; j < chunk; j++) sa_mem[oa + pos + j] = sa_mem[ia + off + j];
    \\    pos += chunk; off += chunk;
    \\    if (fin) break;
    \\  }
    \\  if (fmt == 1) { uint32_t crc = sa_nb_crc32(ia, ilen); int k; for (k = 0; k < 4; k++) sa_mem[oa + pos++] = (uint8_t)(crc >> (8 * k)); for (k = 0; k < 4; k++) sa_mem[oa + pos++] = (uint8_t)((uint32_t)ilen >> (8 * k)); }
    \\  else if (fmt == 2) { uint32_t ad = sa_nb_adler32(ia, ilen); int k; for (k = 3; k >= 0; k--) sa_mem[oa + pos++] = (uint8_t)(ad >> (8 * k)); }
    \\  { sa_u64 h = sa_nb_buf_new(oa, pos); if (h == 0) return 5; sa_store_u64(out_slot, h); }
    \\  return 0;
    \\}
    , .deps = &.{ "sa_nb_buf_find", "sa_nb_buf_new", "sa_nb_crc32", "sa_nb_adler32", "sa_alloc", "sa_store_u64" } },
    .{ .name = "sa_nb_inflate_stream", .code =
    \\typedef struct { uint32_t addr; sa_u64 len; sa_u64 pos; uint32_t bitbuf; int bitcnt; } sa_nb_bits_t;
    \\static int sa_nb_getbit(sa_nb_bits_t *b) { if (b->bitcnt == 0) { if (b->pos >= b->len) return -1; b->bitbuf = sa_mem[b->addr + b->pos]; b->pos++; b->bitcnt = 8; } { int v = (int)(b->bitbuf & 1u); b->bitbuf >>= 1; b->bitcnt--; return v; } }
    \\static int sa_nb_getbits(sa_nb_bits_t *b, int n) { int v = 0, i; for (i = 0; i < n; i++) { int bit = sa_nb_getbit(b); if (bit < 0) return -1; v |= bit << i; } return v; }
    \\typedef struct { uint16_t counts[16]; uint16_t symbols[288]; } sa_nb_huff_t;
    \\static int sa_nb_huff_build(sa_nb_huff_t *h, const uint8_t *lengths, int n) {
    \\  int len, sym, left; uint16_t offs[16];
    \\  for (len = 0; len < 16; len++) h->counts[len] = 0;
    \\  for (sym = 0; sym < n; sym++) h->counts[lengths[sym]]++;
    \\  if (h->counts[0] == n) return 0;
    \\  left = 1;
    \\  for (len = 1; len < 16; len++) { left <<= 1; left -= h->counts[len]; if (left < 0) return -1; }
    \\  offs[1] = 0;
    \\  for (len = 1; len < 15; len++) offs[len + 1] = offs[len] + h->counts[len];
    \\  for (sym = 0; sym < n; sym++) if (lengths[sym] != 0) h->symbols[offs[lengths[sym]]++] = (uint16_t)sym;
    \\  return 0;
    \\}
    \\static int sa_nb_huff_decode(sa_nb_bits_t *b, const sa_nb_huff_t *h) {
    \\  int len, code = 0, first = 0, index = 0;
    \\  for (len = 1; len <= 15; len++) {
    \\    int bit = sa_nb_getbit(b); int count;
    \\    if (bit < 0) return -1;
    \\    code |= bit;
    \\    count = h->counts[len];
    \\    if (code - count < first) return h->symbols[index + (code - first)];
    \\    index += count; first += count; first <<= 1; code <<= 1;
    \\  }
    \\  return -1;
    \\}
    \\typedef struct { uint32_t addr; sa_u64 cap; sa_u64 len; } sa_nb_out_t;
    \\static int sa_nb_out_put(sa_nb_out_t *o, uint8_t v) {
    \\  if (o->len >= o->cap) { uint32_t na; sa_u64 nc = o->cap ? o->cap * 2 : 4096, j; na = (uint32_t)sa_alloc(nc); for (j = 0; j < o->len; j++) sa_mem[na + j] = sa_mem[o->addr + j]; o->addr = na; o->cap = nc; }
    \\  sa_mem[o->addr + o->len] = v; o->len++; return 0;
    \\}
    \\static int sa_nb_inflate_stream(uint32_t ia, sa_u64 ilen, uint32_t *out_a, sa_u64 *out_n) {
    \\  static const uint16_t lbase[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
    \\  static const uint8_t lext[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
    \\  static const uint16_t dbase[30] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
    \\  static const uint8_t dext[30] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};
    \\  sa_nb_bits_t b; sa_nb_out_t o; int fin = 0;
    \\  b.addr = ia; b.len = ilen; b.pos = 0; b.bitbuf = 0; b.bitcnt = 0;
    \\  o.addr = 0; o.cap = 0; o.len = 0;
    \\  while (!fin) {
    \\    int btype = sa_nb_getbits(&b, 3);
    \\    if (btype < 0) return -1;
    \\    fin = btype & 1; btype >>= 1;
    \\    if (btype == 0) {
    \\      uint32_t ln, nn; sa_u64 j;
    \\      b.bitcnt = 0;
    \\      if (b.pos + 4 > b.len) return -1;
    \\      ln = (uint32_t)(sa_mem[b.addr + b.pos] | (sa_mem[b.addr + b.pos + 1] << 8));
    \\      nn = (uint32_t)(sa_mem[b.addr + b.pos + 2] | (sa_mem[b.addr + b.pos + 3] << 8));
    \\      if (ln != (nn ^ 0xFFFFu)) return -1;
    \\      b.pos += 4;
    \\      if (b.pos + ln > b.len) return -1;
    \\      for (j = 0; j < ln; j++) if (sa_nb_out_put(&o, sa_mem[b.addr + b.pos + j])) return -1;
    \\      b.pos += ln;
    \\    } else {
    \\      sa_nb_huff_t lit, dist; uint8_t lengths[320]; int i;
    \\      if (btype == 2) {
    \\        int hlit, hdist, hclen; sa_nb_huff_t cl; uint8_t clens[19];
    \\        static const uint8_t order[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
    \\        hlit = sa_nb_getbits(&b, 5); hdist = sa_nb_getbits(&b, 5); hclen = sa_nb_getbits(&b, 4);
    \\        if (hlit < 0 || hdist < 0 || hclen < 0) return -1;
    \\        hlit += 257; hdist += 1; hclen += 4;
    \\        for (i = 0; i < 19; i++) clens[i] = 0;
    \\        for (i = 0; i < hclen; i++) { int v = sa_nb_getbits(&b, 3); if (v < 0) return -1; clens[order[i]] = (uint8_t)v; }
    \\        if (sa_nb_huff_build(&cl, clens, 19)) return -1;
    \\        i = 0;
    \\        while (i < hlit + hdist) {
    \\          int sym = sa_nb_huff_decode(&b, &cl); if (sym < 0) return -1;
    \\          if (sym < 16) lengths[i++] = (uint8_t)sym;
    \\          else if (sym == 16) { int rep, v; if (i == 0) return -1; v = sa_nb_getbits(&b, 2); if (v < 0) return -1; rep = v + 3; while (rep-- > 0) { if (i >= hlit + hdist) return -1; lengths[i] = lengths[i - 1]; i++; } }
    \\          else if (sym == 17) { int v = sa_nb_getbits(&b, 3); if (v < 0) return -1; v += 3; while (v-- > 0) { if (i >= hlit + hdist) return -1; lengths[i++] = 0; } }
    \\          else { int v = sa_nb_getbits(&b, 7); if (v < 0) return -1; v += 11; while (v-- > 0) { if (i >= hlit + hdist) return -1; lengths[i++] = 0; } }
    \\        }
    \\        if (sa_nb_huff_build(&lit, lengths, hlit)) return -1;
    \\        if (sa_nb_huff_build(&dist, lengths + hlit, hdist)) return -1;
    \\      } else if (btype == 1) {
    \\        for (i = 0; i < 288; i++) lengths[i] = (uint8_t)((i < 144) ? 8 : (i < 256) ? 9 : (i < 280) ? 7 : 8);
    \\        if (sa_nb_huff_build(&lit, lengths, 288)) return -1;
    \\        for (i = 0; i < 30; i++) lengths[i] = 5;
    \\        if (sa_nb_huff_build(&dist, lengths, 30)) return -1;
    \\      } else return -1;
    \\      while (1) {
    \\        int sym = sa_nb_huff_decode(&b, &lit); if (sym < 0) return -1;
    \\        if (sym < 256) { if (sa_nb_out_put(&o, (uint8_t)sym)) return -1; }
    \\        else if (sym == 256) break;
    \\        else {
    \\          int len, dsym, distv, e, v; sa_u64 k, from;
    \\          if (sym > 285) return -1;
    \\          len = lbase[sym - 257]; e = lext[sym - 257];
    \\          if (e) { v = sa_nb_getbits(&b, e); if (v < 0) return -1; len += v; }
    \\          dsym = sa_nb_huff_decode(&b, &dist); if (dsym < 0 || dsym > 29) return -1;
    \\          distv = dbase[dsym]; e = dext[dsym];
    \\          if (e) { v = sa_nb_getbits(&b, e); if (v < 0) return -1; distv += v; }
    \\          if ((sa_u64)distv > o.len) return -1;
    \\          from = o.len - (sa_u64)distv;
    \\          for (k = 0; k < (sa_u64)len; k++) if (sa_nb_out_put(&o, sa_mem[o.addr + from + k])) return -1;
    \\        }
    \\      }
    \\    }
    \\  }
    \\  *out_a = o.addr; *out_n = o.len;
    \\  return 0;
    \\}
    , .deps = &.{"sa_alloc"} },
    .{ .name = "sa_nb_undeflate", .code =
    \\static int sa_nb_undeflate(int fmt, uint32_t ia, sa_u64 ilen, sa_u64 out_slot) {
    \\  uint32_t start = ia; sa_u64 avail = ilen; uint32_t crc_want = 0, ad_want = 0, oa = 0; sa_u64 on = 0, h; int have_crc = 0, have_ad = 0;
    \\  if (fmt < 1 || fmt > 4) return 1;
    \\  if (fmt == 4) return 8;
    \\  if (fmt == 1) {
    \\    uint8_t flg; uint32_t p = ia; sa_u64 rem = ilen; uint32_t isize;
    \\    if (rem < 18) return 6;
    \\    if (sa_mem[p] != 0x1F || sa_mem[p + 1] != 0x8B || sa_mem[p + 2] != 8) return 6;
    \\    flg = sa_mem[p + 3]; p += 10; rem -= 10;
    \\    if (flg & 4) { uint32_t xl; if (rem < 2) return 6; xl = (uint32_t)(sa_mem[p] | (sa_mem[p + 1] << 8)); p += 2; rem -= 2; if (rem < xl) return 6; p += xl; rem -= xl; }
    \\    if (flg & 8) { while (1) { if (rem == 0) return 6; if (sa_mem[p] == 0) { p++; rem--; break; } p++; rem--; } }
    \\    if (flg & 16) { while (1) { if (rem == 0) return 6; if (sa_mem[p] == 0) { p++; rem--; break; } p++; rem--; } }
    \\    if (flg & 2) { if (rem < 2) return 6; p += 2; rem -= 2; }
    \\    if (rem < 8) return 6;
    \\    { uint32_t ep = p + (uint32_t)(rem - 8);
    \\      crc_want = (uint32_t)(sa_mem[ep] | (sa_mem[ep + 1] << 8) | ((uint32_t)sa_mem[ep + 2] << 16) | ((uint32_t)sa_mem[ep + 3] << 24));
    \\      isize = (uint32_t)(sa_mem[ep + 4] | (sa_mem[ep + 5] << 8) | ((uint32_t)sa_mem[ep + 6] << 16) | ((uint32_t)sa_mem[ep + 7] << 24));
    \\      have_crc = 1;
    \\      if (sa_nb_inflate_stream(p, rem - 8, &oa, &on)) return 6;
    \\      if ((uint32_t)on != isize) return 6;
    \\    }
    \\    if (sa_nb_crc32(oa, on) != crc_want) return 6;
    \\    (void)have_ad;
    \\    h = sa_nb_buf_new(oa, on); if (h == 0) return 5;
    \\    sa_store_u64(out_slot, h);
    \\    return 0;
    \\  }
    \\  if (fmt == 2) {
    \\    uint32_t cmf, flg;
    \\    if (ilen < 6) return 6;
    \\    cmf = sa_mem[ia]; flg = sa_mem[ia + 1];
    \\    if (((cmf << 8) + flg) % 31 != 0 || (cmf & 0x0F) != 8) return 6;
    \\    if (flg & 0x20) return 6;
    \\    ad_want = ((uint32_t)sa_mem[ia + ilen - 4] << 24) | ((uint32_t)sa_mem[ia + ilen - 3] << 16) | ((uint32_t)sa_mem[ia + ilen - 2] << 8) | (uint32_t)sa_mem[ia + ilen - 1];
    \\    if (sa_nb_inflate_stream(ia + 2, ilen - 6, &oa, &on)) return 6;
    \\    if (sa_nb_adler32(oa, on) != ad_want) return 6;
    \\    h = sa_nb_buf_new(oa, on); if (h == 0) return 5;
    \\    sa_store_u64(out_slot, h);
    \\    return 0;
    \\  }
    \\  start = ia; avail = ilen;
    \\  if (sa_nb_inflate_stream(start, avail, &oa, &on)) return 6;
    \\  h = sa_nb_buf_new(oa, on); if (h == 0) return 5;
    \\  sa_store_u64(out_slot, h);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_nb_buf_find", "sa_nb_buf_new", "sa_nb_inflate_stream", "sa_nb_crc32", "sa_nb_adler32", "sa_store_u64" } },
    .{ .name = "sa_mp_find", .code =
    \\typedef struct { sa_u64 h; int kind; uint32_t body_a; sa_u64 body_n; uint8_t bnd[96]; sa_u64 bnd_n; uint32_t acc_a; sa_u64 acc_n; sa_u64 acc_cap; } sa_mp_t;
    \\static sa_mp_t sa_mp_tab[32];
    \\static sa_u64 sa_mp_next = 1;
    \\static sa_mp_t *sa_mp_find(sa_u64 h) { unsigned i; if (h == 0) return 0; for (i = 0; i < 32; i++) if (sa_mp_tab[i].h == h) return &sa_mp_tab[i]; return 0; }
    \\static sa_mp_t *sa_mp_slot(void) { unsigned i; for (i = 0; i < 32; i++) if (sa_mp_tab[i].h == 0) { sa_mp_t *mp = &sa_mp_tab[i]; mp->h = sa_mp_next++; mp->kind = 0; mp->body_a = 0; mp->body_n = 0; mp->bnd_n = 0; mp->acc_a = 0; mp->acc_n = 0; mp->acc_cap = 0; return mp; } return 0; }
    \\static int sa_mp_bnd_eq(sa_mp_t *mp, uint32_t a) { sa_u64 i; for (i = 0; i < mp->bnd_n; i++) if (sa_mem[a + i] != mp->bnd[i]) return 0; return 1; }
    \\static int sa_mp_is_delim(sa_mp_t *mp, sa_u64 off) { if (off + 2 + mp->bnd_n > mp->body_n) return 0; if (sa_mem[mp->body_a + off] != '-' || sa_mem[mp->body_a + off + 1] != '-') return 0; return sa_mp_bnd_eq(mp, mp->body_a + (uint32_t)off + 2); }
    \\static int sa_mp_ci_at(uint32_t a, sa_u64 n, const char *s) { sa_u64 i, m = 0; while (s[m]) m++; if (n < m) return 0; for (i = 0; i < m; i++) { uint8_t x = sa_mem[a + i]; if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32); if (x != (uint8_t)s[i]) return 0; } return 1; }
    , .deps = &.{} },
    .{ .name = "sa_mp_seek", .code =
    \\static int sa_mp_seek(sa_mp_t *mp, sa_u64 idx, sa_u64 *so, sa_u64 *sn) {
    \\  sa_u64 off = 0, cur = 0;
    \\  if (!sa_mp_is_delim(mp, 0)) return 0;
    \\  while (1) {
    \\    sa_u64 p = off + 2 + mp->bnd_n;
    \\    if (p + 2 <= mp->body_n && sa_mem[mp->body_a + p] == '-' && sa_mem[mp->body_a + p + 1] == '-') return 0;
    \\    if (p + 2 > mp->body_n || sa_mem[mp->body_a + p] != '\r' || sa_mem[mp->body_a + p + 1] != '\n') return 0;
    \\    { sa_u64 seg_start = p + 2, q = seg_start; int found = 0;
    \\      while (q + 4 + mp->bnd_n <= mp->body_n) {
    \\        if (sa_mem[mp->body_a + q] == '\r' && sa_mem[mp->body_a + q + 1] == '\n' && sa_mem[mp->body_a + q + 2] == '-' && sa_mem[mp->body_a + q + 3] == '-' && sa_mp_bnd_eq(mp, mp->body_a + (uint32_t)q + 4)) { found = 1; break; }
    \\        q++;
    \\      }
    \\      if (!found) return 0;
    \\      if (cur == idx) { *so = seg_start; *sn = q - seg_start; return 1; }
    \\      cur++; off = q + 2;
    \\    }
    \\  }
    \\}
    , .deps = &.{"sa_mp_find"} },
    .{ .name = "sa_mp_split", .code =
    \\static int sa_mp_split(sa_mp_t *mp, sa_u64 so, sa_u64 sn, sa_u64 *bo, sa_u64 *bn) {
    \\  sa_u64 i;
    \\  if (sn >= 4) for (i = 0; i + 4 <= sn; i++) { uint32_t a = mp->body_a + (uint32_t)(so + i); if (sa_mem[a] == '\r' && sa_mem[a + 1] == '\n' && sa_mem[a + 2] == '\r' && sa_mem[a + 3] == '\n') { *bo = so + i + 4; *bn = sn - (i + 4); return 1; } }
    \\  return 0;
    \\}
    , .deps = &.{"sa_mp_find"} },
    .{ .name = "sa_mp_hdr", .code =
    \\static int sa_mp_hdr(sa_mp_t *mp, sa_u64 so, sa_u64 hn, const char *name, sa_u64 *va, sa_u64 *vn) {
    \\  sa_u64 ls = so, end = so + hn, m = 0;
    \\  while (name[m]) m++;
    \\  while (ls < end) {
    \\    sa_u64 le = ls, i, colon = 0; int has = 0;
    \\    while (le < end && !(sa_mem[mp->body_a + le] == '\r' && le + 1 < end && sa_mem[mp->body_a + le + 1] == '\n')) le++;
    \\    for (i = ls; i < le; i++) if (sa_mem[mp->body_a + i] == ':') { colon = i; has = 1; break; }
    \\    if (has && colon - ls == m) {
    \\      int eq = 1;
    \\      for (i = 0; i < m; i++) { uint8_t x = sa_mem[mp->body_a + ls + i]; if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32); if (x != (uint8_t)name[i]) { eq = 0; break; } }
    \\      if (eq) { sa_u64 vs = colon + 1; while (vs < le && (sa_mem[mp->body_a + vs] == ' ' || sa_mem[mp->body_a + vs] == '\t')) vs++; *va = mp->body_a + vs; *vn = le - vs; return 1; }
    \\    }
    \\    ls = le + 2;
    \\  }
    \\  return 0;
    \\}
    \\static int sa_mp_hdr_guest(sa_mp_t *mp, sa_u64 so, sa_u64 hn, uint32_t na, sa_u64 nn, sa_u64 *va, sa_u64 *vn) {
    \\  sa_u64 ls = so, end = so + hn;
    \\  while (ls < end) {
    \\    sa_u64 le = ls, i, colon = 0; int has = 0;
    \\    while (le < end && !(sa_mem[mp->body_a + le] == '\r' && le + 1 < end && sa_mem[mp->body_a + le + 1] == '\n')) le++;
    \\    for (i = ls; i < le; i++) if (sa_mem[mp->body_a + i] == ':') { colon = i; has = 1; break; }
    \\    if (has && colon - ls == nn) {
    \\      int eq = 1;
    \\      for (i = 0; i < nn; i++) { uint8_t x = sa_mem[mp->body_a + ls + i]; uint8_t y = sa_mem[na + i]; if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32); if (y >= 'A' && y <= 'Z') y = (uint8_t)(y + 32); if (x != y) { eq = 0; break; } }
    \\      if (eq) { sa_u64 vs = colon + 1; while (vs < le && (sa_mem[mp->body_a + vs] == ' ' || sa_mem[mp->body_a + vs] == '\t')) vs++; *va = mp->body_a + vs; *vn = le - vs; return 1; }
    \\    }
    \\    ls = le + 2;
    \\  }
    \\  return 0;
    \\}
    , .deps = &.{"sa_mp_find"} },
    .{ .name = "sa_mp_param", .code =
    \\static int sa_mp_param(sa_u64 va, sa_u64 vn, const char *key, sa_u64 *pa, sa_u64 *pn) {
    \\  sa_u64 pos = 0, kl = 0; int first = 1;
    \\  while (key[kl]) kl++;
    \\  while (pos <= vn) {
    \\    sa_u64 te = pos, ts, tn;
    \\    while (te < vn && sa_mem[va + te] != ';') te++;
    \\    ts = pos; tn = te - pos;
    \\    while (tn > 0 && (sa_mem[va + ts] == ' ' || sa_mem[va + ts] == '\t')) { ts++; tn--; }
    \\    while (tn > 0 && (sa_mem[va + ts + tn - 1] == ' ' || sa_mem[va + ts + tn - 1] == '\t')) tn--;
    \\    if (!first && tn > kl && sa_mp_ci_at((uint32_t)(va + ts), kl, key) && sa_mem[va + ts + kl] == '=') {
    \\      sa_u64 vs = ts + kl + 1, vl = tn - kl - 1;
    \\      while (vl > 0 && sa_mem[va + vs] == ' ') { vs++; vl--; }
    \\      if (vl >= 2 && sa_mem[va + vs] == '"' && sa_mem[va + vs + vl - 1] == '"') { vs++; vl -= 2; }
    \\      *pa = va + vs; *pn = vl; return 1;
    \\    }
    \\    first = 0;
    \\    if (te >= vn) break;
    \\    pos = te + 1;
    \\  }
    \\  return 0;
    \\}
    , .deps = &.{"sa_mp_find"} },
    .{ .name = "sa_mp_writeout", .code =
    \\static int sa_mp_writeout(uint32_t va, sa_u64 vn, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_u64 i; sa_store_u64(ol, vn); if (cap < vn) return 9;
    \\  for (i = 0; i < vn; i++) sa_mem[(uint32_t)ov + i] = sa_mem[va + i];
    \\  return 0;
    \\}
    \\static int sa_mp_writeout_host(const uint8_t *v, sa_u64 vn, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_u64 i; sa_store_u64(ol, vn); if (cap < vn) return 9;
    \\  for (i = 0; i < vn; i++) sa_mem[(uint32_t)ov + i] = v[i];
    \\  return 0;
    \\}
    , .deps = &.{"sa_store_u64"} },
    .{ .name = "sa_mp_parse", .code =
    \\static int sa_mp_parse(sa_u64 body_a, sa_u64 body_n, sa_u64 ct_a, sa_u64 ct_n, sa_u64 out_slot) {
    \\  sa_u64 i, vs = 0, vn = 0; int found = 0;
    \\  for (i = 0; i + 9 <= ct_n; i++) if (sa_mp_ci_at((uint32_t)(ct_a + i), 9, "boundary=")) { vs = ct_a + i + 9; found = 1; break; }
    \\  if (!found) return 1;
    \\  { sa_u64 e = vs; sa_mp_t *mp;
    \\    while (e < ct_a + ct_n && sa_mem[e] != ';') e++;
    \\    vn = e - vs;
    \\    while (vn > 0 && (sa_mem[vs] == ' ' || sa_mem[vs] == '"')) { vs++; vn--; }
    \\    while (vn > 0 && (sa_mem[vs + vn - 1] == ' ' || sa_mem[vs + vn - 1] == '"')) vn--;
    \\    if (vn == 0 || vn > 95) return 1;
    \\    mp = sa_mp_slot(); if (!mp) return 5;
    \\    mp->kind = 1; mp->body_a = (uint32_t)body_a; mp->body_n = body_n;
    \\    for (i = 0; i < vn; i++) mp->bnd[i] = sa_mem[vs + i];
    \\    mp->bnd_n = vn;
    \\    if (!sa_mp_is_delim(mp, 0)) { mp->h = 0; return 1; }
    \\    sa_store_u64(out_slot, mp->h);
    \\    return 0;
    \\  }
    \\}
    , .deps = &.{ "sa_mp_find", "sa_store_u64" } },
    .{ .name = "sa_mp_field", .code =
    \\static int sa_mp_field(sa_u64 h, sa_u64 idx, int kind, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_mp_t *mp = sa_mp_find(h); sa_u64 so, sn, bo, bn, va, vn;
    \\  if (!mp) return 3;
    \\  if (!sa_mp_seek(mp, idx, &so, &sn)) return 3;
    \\  if (!sa_mp_split(mp, so, sn, &bo, &bn)) return 3;
    \\  if (kind == 2) { if (!sa_mp_hdr(mp, so, bo - so, "content-type", &va, &vn)) return 100; return sa_mp_writeout((uint32_t)va, vn, ov, ol, cap); }
    \\  { sa_u64 pa, pn;
    \\    if (!sa_mp_hdr(mp, so, bo - so, "content-disposition", &va, &vn)) return 100;
    \\    if (!sa_mp_param(va, vn, kind == 0 ? "name" : "filename", &pa, &pn)) return 100;
    \\    return sa_mp_writeout((uint32_t)pa, pn, ov, ol, cap); }
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_seek", "sa_mp_split", "sa_mp_hdr", "sa_mp_param", "sa_mp_writeout" } },
    .{ .name = "sa_mp_header", .code =
    \\static int sa_mp_header(sa_u64 h, sa_u64 idx, sa_u64 na, sa_u64 nn, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_mp_t *mp = sa_mp_find(h); sa_u64 so, sn, bo, bn, va, vn;
    \\  if (!mp) return 3;
    \\  if (!sa_mp_seek(mp, idx, &so, &sn)) return 3;
    \\  if (!sa_mp_split(mp, so, sn, &bo, &bn)) return 3;
    \\  if (!sa_mp_hdr_guest(mp, so, bo - so, (uint32_t)na, nn, &va, &vn)) return 100;
    \\  return sa_mp_writeout((uint32_t)va, vn, ov, ol, cap);
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_seek", "sa_mp_split", "sa_mp_hdr", "sa_mp_writeout" } },
    .{ .name = "sa_mp_part_body", .code =
    \\static int sa_mp_part_body(sa_u64 h, sa_u64 idx, sa_u64 op, sa_u64 ol) {
    \\  sa_mp_t *mp = sa_mp_find(h); sa_u64 so, sn, bo, bn;
    \\  if (!mp) return 3;
    \\  if (!sa_mp_seek(mp, idx, &so, &sn)) return 3;
    \\  if (!sa_mp_split(mp, so, sn, &bo, &bn)) return 3;
    \\  sa_store_u64(op, mp->body_a + bo); sa_store_u64(ol, bn);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_seek", "sa_mp_split", "sa_store_u64" } },
    .{ .name = "sa_mp_acc", .code =
    \\static int sa_mp_reserve(sa_mp_t *mp, sa_u64 extra) {
    \\  if (mp->acc_n + extra > mp->acc_cap) { uint32_t na; sa_u64 nc = mp->acc_cap ? mp->acc_cap : 1024, i; while (nc < mp->acc_n + extra) nc *= 2; na = (uint32_t)sa_alloc(nc); for (i = 0; i < mp->acc_n; i++) sa_mem[na + i] = sa_mem[mp->acc_a + i]; mp->acc_a = na; mp->acc_cap = nc; }
    \\  return 0;
    \\}
    \\static int sa_mp_acc(sa_mp_t *mp, uint32_t a, sa_u64 n) { sa_u64 i; sa_mp_reserve(mp, n); for (i = 0; i < n; i++) sa_mem[mp->acc_a + mp->acc_n + i] = sa_mem[a + i]; mp->acc_n += n; return 0; }
    \\static int sa_mp_accs(sa_mp_t *mp, const char *s) { sa_u64 i, n = 0; while (s[n]) n++; sa_mp_reserve(mp, n); for (i = 0; i < n; i++) sa_mem[mp->acc_a + mp->acc_n + i] = (uint8_t)s[i]; mp->acc_n += n; return 0; }
    \\static int sa_mp_accb(sa_mp_t *mp) { sa_u64 i; sa_mp_reserve(mp, mp->bnd_n); for (i = 0; i < mp->bnd_n; i++) sa_mem[mp->acc_a + mp->acc_n + i] = mp->bnd[i]; mp->acc_n += mp->bnd_n; return 0; }
    , .deps = &.{ "sa_mp_find", "sa_alloc" } },
    .{ .name = "sa_mp_builder_new", .code =
    \\static int sa_mp_builder_new(sa_u64 bnd_a, sa_u64 bnd_n, sa_u64 out_slot) {
    \\  sa_mp_t *mp = sa_mp_slot(); sa_u64 i;
    \\  if (!mp) return 5;
    \\  mp->kind = 2;
    \\  if (bnd_n == 0) {
    \\    const char *pfx = "----sa-std-multipart-c-"; sa_u64 hv = mp->h; char tmp[24]; int nd = 0;
    \\    mp->bnd_n = 0;
    \\    while (*pfx) mp->bnd[mp->bnd_n++] = (uint8_t)*pfx++;
    \\    if (hv == 0) tmp[nd++] = '0';
    \\    while (hv) { tmp[nd++] = (char)('0' + (hv % 10)); hv /= 10; }
    \\    while (nd > 0) mp->bnd[mp->bnd_n++] = (uint8_t)tmp[--nd];
    \\  } else {
    \\    if (bnd_n > 95) { mp->h = 0; return 1; }
    \\    for (i = 0; i < bnd_n; i++) mp->bnd[i] = sa_mem[bnd_a + i];
    \\    mp->bnd_n = bnd_n;
    \\  }
    \\  sa_store_u64(out_slot, mp->h);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_acc", "sa_store_u64" } },
    .{ .name = "sa_mp_add_field", .code =
    \\static int sa_mp_add_field(sa_u64 h, sa_u64 na, sa_u64 nn, sa_u64 va, sa_u64 vn, int is_file, sa_u64 fa, sa_u64 fnn, sa_u64 ca, sa_u64 cn, sa_u64 da, sa_u64 dn) {
    \\  sa_mp_t *mp = sa_mp_find(h);
    \\  if (!mp || mp->kind != 2) return 3;
    \\  if (mp->acc_n > 0) sa_mp_accs(mp, "\r\n"); sa_mp_accs(mp, "--"); sa_mp_accb(mp); sa_mp_accs(mp, "\r\nContent-Disposition: form-data; name=\"");
    \\  sa_mp_acc(mp, (uint32_t)na, nn);
    \\  sa_mp_accs(mp, "\"");
    \\  if (is_file) { sa_mp_accs(mp, "; filename=\""); sa_mp_acc(mp, (uint32_t)fa, fnn); sa_mp_accs(mp, "\""); }
    \\  sa_mp_accs(mp, "\r\n");
    \\  if (is_file) { sa_mp_accs(mp, "Content-Type: "); sa_mp_acc(mp, (uint32_t)ca, cn); sa_mp_accs(mp, "\r\n"); }
    \\  sa_mp_accs(mp, "\r\n");
    \\  sa_mp_acc(mp, is_file ? (uint32_t)da : (uint32_t)va, is_file ? dn : vn);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_acc" } },
};
