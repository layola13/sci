const HelperDef = @import("types.zig").HelperDef;

pub const chunk_3: [47]HelperDef = .{
    .{ .name = "sa_mp_builder_finish", .code =
    \\static int sa_mp_builder_finish(sa_u64 h, sa_u64 out_slot) {
    \\  sa_mp_t *mp = sa_mp_find(h); sa_u64 bh;
    \\  if (!mp || mp->kind != 2) return 3;
    \\  sa_mp_accs(mp, "\r\n--"); sa_mp_accb(mp); sa_mp_accs(mp, "--\r\n");
    \\  bh = sa_nb_buf_new(mp->acc_a, mp->acc_n);
    \\  if (bh == 0) return 5;
    \\  mp->h = 0;
    \\  sa_store_u64(out_slot, bh);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_acc", "sa_nb_buf_find", "sa_nb_buf_new", "sa_store_u64" } },
    .{ .name = "sa_mp_bnd_out", .code =
    \\static int sa_mp_bnd_out(sa_u64 h, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_mp_t *mp = sa_mp_find(h);
    \\  if (!mp) return 3;
    \\  return sa_mp_writeout_host(mp->bnd, mp->bnd_n, ov, ol, cap);
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_writeout" } },
    .{ .name = "sa_mp_ctype_out", .code =
    \\static int sa_mp_ctype_out(sa_u64 h, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_mp_t *mp = sa_mp_find(h); const char *pfx = "multipart/form-data; boundary="; sa_u64 pn = 0, total, i; uint32_t t;
    \\  if (!mp) return 3;
    \\  while (pfx[pn]) pn++;
    \\  total = pn + mp->bnd_n;
    \\  sa_store_u64(ol, total);
    \\  if (cap < total) return 9;
    \\  t = (uint32_t)ov;
    \\  for (i = 0; i < pn; i++) sa_mem[t + i] = (uint8_t)pfx[i];
    \\  for (i = 0; i < mp->bnd_n; i++) sa_mem[t + pn + i] = mp->bnd[i];
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_store_u64" } },
    .{ .name = "sa_nb_ws_opcode_get", .code =
    \\typedef struct { sa_u64 h; int opcode; int closed; } sa_nb_ws_t;
    \\static sa_nb_ws_t sa_nb_ws_tab[32];
    \\static sa_nb_ws_t *sa_nb_ws_rec(sa_u64 h) { unsigned i; for (i = 0; i < 32; i++) if (sa_nb_ws_tab[i].h == h) return &sa_nb_ws_tab[i]; return 0; }
    \\static int sa_nb_ws_opcode_get(sa_u64 h) { sa_nb_ws_t *r = sa_nb_ws_rec(h); return r ? r->opcode : 2; }
    , .deps = &.{} },
    .{ .name = "sa_nb_ws_closed_get", .code =
    \\static int sa_nb_ws_closed_get(sa_u64 h) { sa_nb_ws_t *r = sa_nb_ws_rec(h); return r ? r->closed : 0; }
    , .deps = &.{"sa_nb_ws_opcode_get"} },
    .{ .name = "sa_nb_ws_meta_set", .code =
    \\static void sa_nb_ws_meta_set(sa_u64 h, int opcode, int closed) {
    \\  sa_nb_ws_t *r = sa_nb_ws_rec(h); unsigned i;
    \\  if (!r) { for (i = 0; i < 32; i++) if (sa_nb_ws_tab[i].h == 0) { r = &sa_nb_ws_tab[i]; r->h = h; r->opcode = 2; r->closed = 0; break; } }
    \\  if (!r) return;
    \\  if (opcode >= 0) r->opcode = opcode;
    \\  if (closed >= 0) r->closed = closed;
    \\}
    , .deps = &.{"sa_nb_ws_opcode_get"} },
    .{ .name = "sa_nb_ws_meta_clear", .code =
    \\static void sa_nb_ws_meta_clear(sa_u64 h) { sa_nb_ws_t *r = sa_nb_ws_rec(h); if (r) r->h = 0; }
    , .deps = &.{"sa_nb_ws_opcode_get"} },
    .{ .name = "sa_fmt_int", .code =
    \\static int sa_fmt_int(char *d, sa_u64 v, unsigned base, int sgn, int up) {
    \\  unsigned b; sa_u64 mag; int neg = 0; char t[64]; int m = 0; int o; int i;
    \\  if (base != 2 && base != 8 && base != 10 && base != 16 && base != 17) return -1;
    \\  b = (base == 17) ? 16 : base;
    \\  if (sgn && ((sa_i64)v) < 0) { neg = 1; mag = (~v) + 1u; } else { mag = v; }
    \\  if (mag == 0) t[m++] = '0';
    \\  while (mag > 0) { unsigned dg = (unsigned)(mag % b); t[m++] = (char)(dg < 10 ? '0' + dg : (up ? 'A' + dg - 10 : 'a' + dg - 10)); mag /= b; }
    \\  o = neg ? 1 : 0; if (neg) d[0] = '-';
    \\  for (i = 0; i < m; i++) d[o + i] = t[m - 1 - i];
    \\  return o + m;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_owned_new", .code =
    \\static sa_u64 sa_owned_new(sa_u64 ptr, sa_u64 len, unsigned kind) { unsigned i; for (i = 0; i < SA_OWNED_MAX_OBJS; i++) if (sa_owned_bufs[i].h == 0) { sa_u64 h = sa_owned_next++; sa_owned_bufs[i].h = h; sa_owned_bufs[i].ptr = ptr; sa_owned_bufs[i].len = len; sa_owned_bufs[i].kind = kind; return h; } return 0; }
    , .deps = &.{} },
    .{ .name = "sa_owned_find", .code =
    \\static sa_owned_buf_t *sa_owned_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_OWNED_MAX_OBJS; i++) if (sa_owned_bufs[i].h == h) return &sa_owned_bufs[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_mkdir_wrap", .code =
    \\static int sa_mkdir_wrap(const uint8_t *p) { return mkdir((const char *)p, 0777); }
    , .deps = &.{} },
    .{ .name = "SA_ROTR32", .code =
    \\#define SA_ROTR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
    , .deps = &.{} },
    .{ .name = "SA_ROTL32", .code =
    \\#define SA_ROTL32(x, n) (((x) << (n)) | ((x) >> (32 - (n))))
    , .deps = &.{} },
    .{ .name = "SA_ROTR64", .code =
    \\#define SA_ROTR64(x, n) (((x) >> (n)) | ((x) << (64 - (n))))
    , .deps = &.{} },
    .{ .name = "sa_access_wrap", .code =
    \\static int sa_access_wrap(const uint8_t *p) { return access((const char *)p, F_OK); }
    , .deps = &.{} },
    .{ .name = "sa_sha256_block", .code =
    \\static void sa_sha256_block(uint32_t st[8], const uint8_t *p) {
    \\  static const uint32_t sa_sha256_k[64] = {
    \\  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    \\  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    \\  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    \\  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    \\  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    \\  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    \\  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    \\  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
    \\  uint32_t w[64]; int i;
    \\  for (i = 0; i < 16; i++) w[i] = ((uint32_t)p[i*4] << 24) | ((uint32_t)p[i*4+1] << 16) | ((uint32_t)p[i*4+2] << 8) | p[i*4+3];
    \\  for (i = 16; i < 64; i++) { uint32_t s0 = SA_ROTR32(w[i-15], 7) ^ SA_ROTR32(w[i-15], 18) ^ (w[i-15] >> 3); uint32_t s1 = SA_ROTR32(w[i-2], 17) ^ SA_ROTR32(w[i-2], 19) ^ (w[i-2] >> 10); w[i] = w[i-16] + s0 + w[i-7] + s1; }
    \\  uint32_t a=st[0],b=st[1],c=st[2],d=st[3],e=st[4],f=st[5],g=st[6],h=st[7];
    \\  for (i = 0; i < 64; i++) { uint32_t S1 = SA_ROTR32(e,6)^SA_ROTR32(e,11)^SA_ROTR32(e,25); uint32_t ch = (e&f)^(~e&g); uint32_t t1 = h+S1+ch+sa_sha256_k[i]+w[i]; uint32_t S0 = SA_ROTR32(a,2)^SA_ROTR32(a,13)^SA_ROTR32(a,22); uint32_t mj = (a&b)^(a&c)^(b&c); uint32_t t2 = S0+mj; h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2; }
    \\  st[0]+=a; st[1]+=b; st[2]+=c; st[3]+=d; st[4]+=e; st[5]+=f; st[6]+=g; st[7]+=h;
    \\}
    , .deps = &.{"SA_ROTR32"} },
    .{ .name = "sa_sha256", .code =
    \\static void sa_sha256(const uint8_t *msg, size_t len, uint8_t out[32]) {
    \\  uint32_t st[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    \\  uint8_t blk[64]; size_t i, off = 0;
    \\  uint64_t bitlen = (uint64_t)len * 8;
    \\  while (len - off >= 64) { sa_sha256_block(st, msg + off); off += 64; }
    \\  size_t rem = len - off;
    \\  for (i = 0; i < rem; i++) blk[i] = msg[off + i];
    \\  blk[rem] = 0x80;
    \\  if (rem + 1 + 8 > 64) { for (i = rem + 1; i < 64; i++) blk[i] = 0; sa_sha256_block(st, blk); for (i = 0; i < 56; i++) blk[i] = 0; }
    \\  else { for (i = rem + 1; i < 56; i++) blk[i] = 0; }
    \\  for (i = 0; i < 8; i++) blk[56 + i] = (uint8_t)(bitlen >> (56 - i * 8));
    \\  sa_sha256_block(st, blk);
    \\  for (i = 0; i < 8; i++) { out[i*4] = (uint8_t)(st[i] >> 24); out[i*4+1] = (uint8_t)(st[i] >> 16); out[i*4+2] = (uint8_t)(st[i] >> 8); out[i*4+3] = (uint8_t)st[i]; }
    \\}
    , .deps = &.{"sa_sha256_block"} },
    .{ .name = "sa_sha512_block", .code =
    \\static void sa_sha512_block(uint64_t st[8], const uint8_t *p) {
    \\  static const uint64_t sa_sha512_k[80] = {
    \\  0x428a2f98d728ae22ULL,0x7137449123ef65cdULL,0xb5c0fbcfec4d3b2fULL,0xe9b5dba58189dbbcULL,0x3956c25bf348b538ULL,0x59f111f1b605d019ULL,0x923f82a4af194f9bULL,0xab1c5ed5da6d8118ULL,
    \\  0xd807aa98a3030242ULL,0x12835b0145706fbeULL,0x243185be4ee4b28cULL,0x550c7dc3d5ffb4e2ULL,0x72be5d74f27b896fULL,0x80deb1fe3b1696b1ULL,0x9bdc06a725c71235ULL,0xc19bf174cf692694ULL,
    \\  0xe49b69c19ef14ad2ULL,0xefbe4786384f25e3ULL,0x0fc19dc68b8cd5b5ULL,0x240ca1cc77ac9c65ULL,0x2de92c6f592b0275ULL,0x4a7484aa6ea6e483ULL,0x5cb0a9dcbd41fbd4ULL,0x76f988da831153b5ULL,
    \\  0x983e5152ee66dfabULL,0xa831c66d2db43210ULL,0xb00327c898fb213fULL,0xbf597fc7beef0ee4ULL,0xc6e00bf33da88fc2ULL,0xd5a79147930aa725ULL,0x06ca6351e003826fULL,0x142929670a0e6e70ULL,
    \\  0x27b70a8546d22ffcULL,0x2e1b21385c26c926ULL,0x4d2c6dfc5ac42aedULL,0x53380d139d95b3dfULL,0x650a73548baf63deULL,0x766a0abb3c77b2a8ULL,0x81c2c92e47edaee6ULL,0x92722c851482353bULL,
    \\  0xa2bfe8a14cf10364ULL,0xa81a664bbc423001ULL,0xc24b8b70d0f89791ULL,0xc76c51a30654be30ULL,0xd192e819d6ef5218ULL,0xd69906245565a910ULL,0xf40e35855771202aULL,0x106aa07032bbd1b8ULL,
    \\  0x19a4c116b8d2d0c8ULL,0x1e376c085141ab53ULL,0x2748774cdf8eeb99ULL,0x34b0bcb5e19b48a8ULL,0x391c0cb3c5c95a63ULL,0x4ed8aa4ae3418acbULL,0x5b9cca4f7763e373ULL,0x682e6ff3d6b2b8a3ULL,
    \\  0x748f82ee5defb2fcULL,0x78a5636f43172f60ULL,0x84c87814a1f0ab72ULL,0x8cc702081a6439ecULL,0x90befffa23631e28ULL,0xa4506cebde82bde9ULL,0xbef9a3f7b2c67915ULL,0xc67178f2e372532bULL,
    \\  0xca273eceea26619cULL,0xd186b8c721c0c207ULL,0xeada7dd6cde0eb1eULL,0xf57d4f7fee6ed178ULL,0x06f067aa72176fbaULL,0x0a637dc5a2c898a6ULL,0x113f9804bef90daeULL,0x1b710b35131c471bULL,
    \\  0x28db77f523047d84ULL,0x32caab7b40c72493ULL,0x3c9ebe0a15c9bebcULL,0x431d67c49c100d4cULL,0x4cc5d4becb3e42b6ULL,0x597f299cfc657e2aULL,0x5fcb6fab3ad6faecULL,0x6c44198c4a475817ULL};
    \\  uint64_t w[80]; int i; int j;
    \\  for (i = 0; i < 16; i++) { w[i] = 0; for (j = 0; j < 8; j++) w[i] |= (uint64_t)p[i*8+j] << (56 - j * 8); }
    \\  for (i = 16; i < 80; i++) { uint64_t s0 = SA_ROTR64(w[i-15],1)^SA_ROTR64(w[i-15],8)^(w[i-15]>>7); uint64_t s1 = SA_ROTR64(w[i-2],19)^SA_ROTR64(w[i-2],61)^(w[i-2]>>6); w[i] = w[i-16]+s0+w[i-7]+s1; }
    \\  uint64_t a=st[0],b=st[1],c=st[2],d=st[3],e=st[4],f=st[5],g=st[6],h=st[7];
    \\  for (i = 0; i < 80; i++) { uint64_t S1 = SA_ROTR64(e,14)^SA_ROTR64(e,18)^SA_ROTR64(e,41); uint64_t ch = (e&f)^(~e&g); uint64_t t1 = h+S1+ch+sa_sha512_k[i]+w[i]; uint64_t S0 = SA_ROTR64(a,28)^SA_ROTR64(a,34)^SA_ROTR64(a,39); uint64_t mj = (a&b)^(a&c)^(b&c); uint64_t t2 = S0+mj; h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2; }
    \\  st[0]+=a; st[1]+=b; st[2]+=c; st[3]+=d; st[4]+=e; st[5]+=f; st[6]+=g; st[7]+=h;
    \\}
    , .deps = &.{"SA_ROTR64"} },
    .{ .name = "sa_sha512", .code =
    \\static void sa_sha512(const uint8_t *msg, size_t len, uint8_t out[64]) {
    \\  uint64_t st[8] = {0x6a09e667f3bcc908ULL,0xbb67ae8584caa73bULL,0x3c6ef372fe94f82bULL,0xa54ff53a5f1d36f1ULL,0x510e527fade682d1ULL,0x9b05688c2b3e6c1fULL,0x1f83d9abfb41bd6bULL,0x5be0cd19137e2179ULL};
    \\  uint8_t blk[128]; size_t i, off = 0;
    \\  uint64_t bitlen = (uint64_t)len * 8;
    \\  while (len - off >= 128) { sa_sha512_block(st, msg + off); off += 128; }
    \\  size_t rem = len - off;
    \\  for (i = 0; i < rem; i++) blk[i] = msg[off + i];
    \\  blk[rem] = 0x80;
    \\  if (rem + 1 + 16 > 128) { for (i = rem + 1; i < 128; i++) blk[i] = 0; sa_sha512_block(st, blk); for (i = 0; i < 112; i++) blk[i] = 0; }
    \\  else { for (i = rem + 1; i < 112; i++) blk[i] = 0; }
    \\  for (i = 0; i < 8; i++) blk[112 + i] = 0;
    \\  for (i = 0; i < 8; i++) blk[120 + i] = (uint8_t)(bitlen >> (56 - i * 8));
    \\  sa_sha512_block(st, blk);
    \\  for (i = 0; i < 8; i++) { int j; for (j = 0; j < 8; j++) out[i*8+j] = (uint8_t)(st[i] >> (56 - j * 8)); }
    \\}
    , .deps = &.{"sa_sha512_block"} },
    .{ .name = "sa_sha1_block", .code =
    \\static void sa_sha1_block(uint32_t st[5], const uint8_t *p) {
    \\  uint32_t w[80]; int i;
    \\  for (i = 0; i < 16; i++) w[i] = ((uint32_t)p[i*4] << 24) | ((uint32_t)p[i*4+1] << 16) | ((uint32_t)p[i*4+2] << 8) | p[i*4+3];
    \\  for (i = 16; i < 80; i++) w[i] = SA_ROTL32(w[i-3]^w[i-8]^w[i-14]^w[i-16], 1);
    \\  uint32_t a=st[0],b=st[1],c=st[2],d=st[3],e=st[4];
    \\  for (i = 0; i < 80; i++) { uint32_t f, k; if (i < 20) { f = (b&c)|(~b&d); k = 0x5a827999; } else if (i < 40) { f = b^c^d; k = 0x6ed9eba1; } else if (i < 60) { f = (b&c)|(b&d)|(c&d); k = 0x8f1bbcdc; } else { f = b^c^d; k = 0xca62c1d6; } uint32_t t = SA_ROTL32(a,5)+f+e+k+w[i]; e=d; d=c; c=SA_ROTL32(b,30); b=a; a=t; }
    \\  st[0]+=a; st[1]+=b; st[2]+=c; st[3]+=d; st[4]+=e;
    \\}
    , .deps = &.{"SA_ROTL32"} },
    .{ .name = "sa_sha1", .code =
    \\static void sa_sha1(const uint8_t *msg, size_t len, uint8_t out[20]) {
    \\  uint32_t st[5] = {0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0};
    \\  uint8_t blk[64]; size_t i, off = 0;
    \\  uint64_t bitlen = (uint64_t)len * 8;
    \\  while (len - off >= 64) { sa_sha1_block(st, msg + off); off += 64; }
    \\  size_t rem = len - off;
    \\  for (i = 0; i < rem; i++) blk[i] = msg[off + i];
    \\  blk[rem] = 0x80;
    \\  if (rem + 1 + 8 > 64) { for (i = rem + 1; i < 64; i++) blk[i] = 0; sa_sha1_block(st, blk); for (i = 0; i < 56; i++) blk[i] = 0; }
    \\  else { for (i = rem + 1; i < 56; i++) blk[i] = 0; }
    \\  for (i = 0; i < 8; i++) blk[56 + i] = (uint8_t)(bitlen >> (56 - i * 8));
    \\  sa_sha1_block(st, blk);
    \\  for (i = 0; i < 5; i++) { out[i*4] = (uint8_t)(st[i] >> 24); out[i*4+1] = (uint8_t)(st[i] >> 16); out[i*4+2] = (uint8_t)(st[i] >> 8); out[i*4+3] = (uint8_t)st[i]; }
    \\}
    , .deps = &.{"sa_sha1_block"} },
    .{ .name = "sa_md5_block", .code =
    \\static void sa_md5_block(uint32_t st[4], const uint8_t *p) {
    \\  static const uint32_t s[64] = {7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21};
    \\  static const uint32_t K[64] = {0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391};
    \\  uint32_t M[16]; int i;
    \\  for (i = 0; i < 16; i++) M[i] = (uint32_t)p[i*4] | ((uint32_t)p[i*4+1] << 8) | ((uint32_t)p[i*4+2] << 16) | ((uint32_t)p[i*4+3] << 24);
    \\  uint32_t a=st[0],b=st[1],c=st[2],d=st[3];
    \\  for (i = 0; i < 64; i++) { uint32_t f; int g; if (i < 16) { f = (b&c)|(~b&d); g = i; } else if (i < 32) { f = (d&b)|(~d&c); g = (5*i+1)%16; } else if (i < 48) { f = b^c^d; g = (3*i+5)%16; } else { f = c^(b|~d); g = (7*i)%16; } f = f + a + K[i] + M[g]; a = d; d = c; c = b; b = b + SA_ROTL32(f, s[i]); }
    \\  st[0]+=a; st[1]+=b; st[2]+=c; st[3]+=d;
    \\}
    , .deps = &.{"SA_ROTL32"} },
    .{ .name = "sa_md5", .code =
    \\static void sa_md5(const uint8_t *msg, size_t len, uint8_t out[16]) {
    \\  uint32_t st[4] = {0x67452301,0xefcdab89,0x98badcfe,0x10325476};
    \\  uint8_t blk[64]; size_t i, off = 0;
    \\  uint64_t bitlen = (uint64_t)len * 8;
    \\  while (len - off >= 64) { sa_md5_block(st, msg + off); off += 64; }
    \\  size_t rem = len - off;
    \\  for (i = 0; i < rem; i++) blk[i] = msg[off + i];
    \\  blk[rem] = 0x80;
    \\  if (rem + 1 + 8 > 64) { for (i = rem + 1; i < 64; i++) blk[i] = 0; sa_md5_block(st, blk); for (i = 0; i < 56; i++) blk[i] = 0; }
    \\  else { for (i = rem + 1; i < 56; i++) blk[i] = 0; }
    \\  for (i = 0; i < 8; i++) blk[56 + i] = (uint8_t)(bitlen >> (i * 8));
    \\  sa_md5_block(st, blk);
    \\  for (i = 0; i < 4; i++) { out[i*4] = (uint8_t)st[i]; out[i*4+1] = (uint8_t)(st[i] >> 8); out[i*4+2] = (uint8_t)(st[i] >> 16); out[i*4+3] = (uint8_t)(st[i] >> 24); }
    \\}
    , .deps = &.{"sa_md5_block"} },
    .{ .name = "sa_owned_drop", .code =
    \\static void sa_owned_drop(sa_u64 h) { sa_owned_buf_t *o = sa_owned_find(h); if (o != 0) o->h = 0; }
    , .deps = &.{"sa_owned_find"} },
    .{ .name = "sa_regex_find", .code =
    \\static sa_regex_t *sa_regex_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_REGEX_MAX_OBJS; i++) if (sa_regexes[i].h == h) return &sa_regexes[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_json_find", .code =
    \\static sa_json_node_t *sa_json_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_JSON_MAX_NODES; i++) if (sa_json_nodes[i].h == h) return &sa_json_nodes[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_json_writer_find", .code =
    \\static sa_json_writer_t *sa_json_writer_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_JSON_MAX_WRITERS; i++) if (sa_json_writers[i].h == h) return &sa_json_writers[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_json_new", .code =
    \\static sa_json_node_t *sa_json_new(void) { unsigned i; for (i = 0; i < SA_JSON_MAX_NODES; i++) if (sa_json_nodes[i].h == 0) { sa_u64 h = sa_alloc(8); sa_json_nodes[i].h = h; sa_json_nodes[i].kind = 0; sa_json_nodes[i].first = 0; sa_json_nodes[i].next = 0; sa_json_nodes[i].kptr = 0; sa_json_nodes[i].klen = 0; sa_json_nodes[i].vptr = 0; sa_json_nodes[i].vlen = 0; sa_json_nodes[i].ival = 0; sa_json_nodes[i].fbits = 0; sa_json_nodes[i].bval = 0; return &sa_json_nodes[i]; } return 0; }
    , .deps = &.{} },
    .{ .name = "sa_jw_grow", .code =
    \\static int sa_jw_grow(sa_json_writer_t *w, size_t extra) {
    \\  if (w->len + extra < w->len) return 1;
    \\  if (w->len + extra <= w->cap) return 0;
    \\  { size_t ncap = w->cap == 0 ? 256 : w->cap * 2;
    \\    while (ncap < w->len + extra) { if (ncap > ~(size_t)0 / 2) return 1; ncap *= 2; }
    \\    sa_u64 p = sa_alloc((sa_u64)ncap);
    \\    uint32_t d = sa_checked_addr(p, (sa_u64)ncap);
    \\    uint32_t s = sa_checked_addr(w->buf, w->len);
    \\    size_t i; for (i = 0; i < w->len; i++) sa_mem[d + i] = sa_mem[s + i];
    \\    w->buf = p; w->cap = ncap; }
    \\  return 0;
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr" } },
    .{ .name = "sa_jw_putc", .code =
    \\static int sa_jw_putc(sa_json_writer_t *w, uint8_t c) {
    \\  if (sa_jw_grow(w, 1)) return 1;
    \\  { uint32_t d = sa_checked_addr(w->buf, w->len + 1); sa_mem[d + w->len] = c; }
    \\  w->len++;
    \\  return 0;
    \\}
    , .deps = &.{"sa_jw_grow"} },
    .{ .name = "sa_jw_write", .code =
    \\static int sa_jw_write(sa_json_writer_t *w, const uint8_t *s, size_t n) {
    \\  size_t i; uint32_t d;
    \\  if (sa_jw_grow(w, n)) return 1;
    \\  d = sa_checked_addr(w->buf, w->len + n);
    \\  for (i = 0; i < n; i++) sa_mem[d + w->len + i] = s[i];
    \\  w->len += n;
    \\  return 0;
    \\}
    , .deps = &.{"sa_jw_grow"} },
    .{ .name = "sa_jw_comma", .code =
    \\static int sa_jw_comma(sa_json_writer_t *w) {
    \\  if (w->depth == 0 || w->first[w->depth - 1]) return 0;
    \\  return sa_jw_putc(w, ',');
    \\}
    , .deps = &.{"sa_jw_putc"} },
    .{ .name = "sa_jw_value_begin", .code =
    \\static int sa_jw_value_begin(sa_json_writer_t *w) {
    \\  if (w->done) return 1;
    \\  if (w->pending) { w->pending = 0; w->started = 1; return 0; }
    \\  if (w->depth == 0) {
    \\    if (w->complete) return 1;
    \\    w->started = 1; w->complete = 1; return 0;
    \\  }
    \\  if (w->kinds[w->depth - 1] != '{' && w->kinds[w->depth - 1] != '[') return 1;
    \\  if (sa_jw_comma(w)) return 1;
    \\  w->first[w->depth - 1] = 0; w->started = 1;
    \\  return 0;
    \\}
    , .deps = &.{"sa_jw_comma"} },
    .{ .name = "sa_jw_string", .code =
    \\static int sa_jw_string(sa_json_writer_t *w, const uint8_t *s, size_t n) {
    \\  size_t i;
    \\  if (sa_jw_putc(w, '"')) return 1;
    \\  for (i = 0; i < n; i++) {
    \\    uint8_t c = s[i];
    \\    if (c == '"' || c == '\\') { if (sa_jw_putc(w, '\\')) return 1; if (sa_jw_putc(w, c)) return 1; }
    \\    else if (c == '\b') { if (sa_jw_write(w, (const uint8_t *)"\\b", 2)) return 1; }
    \\    else if (c == '\f') { if (sa_jw_write(w, (const uint8_t *)"\\f", 2)) return 1; }
    \\    else if (c == '\n') { if (sa_jw_write(w, (const uint8_t *)"\\n", 2)) return 1; }
    \\    else if (c == '\r') { if (sa_jw_write(w, (const uint8_t *)"\\r", 2)) return 1; }
    \\    else if (c == '\t') { if (sa_jw_write(w, (const uint8_t *)"\\t", 2)) return 1; }
    \\    else if (c < 0x20) {
    \\      char eb[6]; eb[0] = '\\'; eb[1] = 'u'; eb[2] = '0'; eb[3] = '0';
    \\      eb[4] = (char)"0123456789abcdef"[(c >> 4) & 15]; eb[5] = (char)"0123456789abcdef"[c & 15];
    \\      if (sa_jw_write(w, (const uint8_t *)eb, 6)) return 1;
    \\    } else if (sa_jw_putc(w, c)) return 1;
    \\  }
    \\  if (sa_jw_putc(w, '"')) return 1;
    \\  return 0;
    \\}
    , .deps = &.{ "sa_jw_putc", "sa_jw_write" } },
    .{ .name = "sa_utf8_next", .code =
    \\static uint32_t sa_utf8_next(const uint8_t *s, size_t n, size_t *i) {
    \\  size_t k = *i; uint8_t b0;
    \\  if (k >= n) return ~(uint32_t)0;
    \\  b0 = s[k];
    \\  if (b0 < 0x80) { *i = k + 1; return b0; }
    \\  if (b0 >= 0xC2 && b0 <= 0xDF && k + 1 < n && (s[k + 1] & 0xC0) == 0x80) {
    \\    *i = k + 2; return ((uint32_t)(b0 & 0x1F) << 6) | (s[k + 1] & 0x3F); }
    \\  if (b0 >= 0xE0 && b0 <= 0xEF && k + 2 < n && (s[k + 1] & 0xC0) == 0x80 && (s[k + 2] & 0xC0) == 0x80) {
    \\    uint32_t cp = ((uint32_t)(b0 & 0x0F) << 12) | ((uint32_t)(s[k + 1] & 0x3F) << 6) | (s[k + 2] & 0x3F);
    \\    if (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF)) return ~(uint32_t)0;
    \\    *i = k + 3; return cp; }
    \\  if (b0 >= 0xF0 && b0 <= 0xF4 && k + 3 < n && (s[k + 1] & 0xC0) == 0x80 && (s[k + 2] & 0xC0) == 0x80 && (s[k + 3] & 0xC0) == 0x80) {
    \\    uint32_t cp = ((uint32_t)(b0 & 0x07) << 18) | ((uint32_t)(s[k + 1] & 0x3F) << 12) | ((uint32_t)(s[k + 2] & 0x3F) << 6) | (s[k + 3] & 0x3F);
    \\    if (cp < 0x10000 || cp > 0x10FFFF) return ~(uint32_t)0;
    \\    *i = k + 4; return cp; }
    \\  return ~(uint32_t)0;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_utf8_enc", .code =
    \\static unsigned sa_utf8_enc(uint32_t cp, uint8_t *o) {
    \\  if (cp < 0x80) { o[0] = (uint8_t)cp; return 1; }
    \\  if (cp < 0x800) { o[0] = (uint8_t)(0xC0 | (cp >> 6)); o[1] = (uint8_t)(0x80 | (cp & 0x3F)); return 2; }
    \\  if (cp < 0x10000) { o[0] = (uint8_t)(0xE0 | (cp >> 12)); o[1] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F)); o[2] = (uint8_t)(0x80 | (cp & 0x3F)); return 3; }
    \\  o[0] = (uint8_t)(0xF0 | (cp >> 18)); o[1] = (uint8_t)(0x80 | ((cp >> 12) & 0x3F)); o[2] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F)); o[3] = (uint8_t)(0x80 | (cp & 0x3F)); return 4;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_json_string", .code =
    \\static int sa_json_string(const uint8_t *s, size_t n, size_t *pos, sa_u64 *out_ptr, sa_u64 *out_len) {
    \\  size_t i = *pos; size_t w; sa_u64 p; uint32_t d;
    \\  if (i >= n || s[i] != '"') return 0;
    \\  i++;
    \\  p = sa_alloc(n - i + 1);
    \\  d = sa_checked_addr(p, n - i + 1);
    \\  w = 0;
    \\  while (i < n && s[i] != '"') {
    \\    uint8_t c = s[i];
    \\    if (c == '\\') {
    \\      uint8_t e;
    \\      i++; if (i >= n) return 0; e = s[i];
    \\      if (e == '"' || e == '\\' || e == '/') sa_mem[d + w++] = e;
    \\      else if (e == 'b') sa_mem[d + w++] = 8;
    \\      else if (e == 'f') sa_mem[d + w++] = 12;
    \\      else if (e == 'n') sa_mem[d + w++] = 10;
    \\      else if (e == 'r') sa_mem[d + w++] = 13;
    \\      else if (e == 't') sa_mem[d + w++] = 9;
    \\      else if (e == 'u') {
    \\        uint32_t cp = 0; int k;
    \\        for (k = 0; k < 4; k++) {
    \\          i++; if (i >= n) return 0;
    \\          uint8_t h = s[i]; uint32_t v;
    \\          if (h >= '0' && h <= '9') v = (uint32_t)(h - '0');
    \\          else if (h >= 'a' && h <= 'f') v = (uint32_t)(h - 'a' + 10);
    \\          else if (h >= 'A' && h <= 'F') v = (uint32_t)(h - 'A' + 10);
    \\          else return 0;
    \\          cp = cp * 16 + v;
    \\        }
    \\        if (cp >= 0xD800 && cp <= 0xDBFF) {
    \\          uint32_t lo;
    \\          if (i + 2 >= n || s[i + 1] != '\\' || s[i + 2] != 'u') return 0;
    \\          lo = 0; i += 2;
    \\          for (k = 0; k < 4; k++) {
    \\            i++; if (i >= n) return 0;
    \\            uint8_t h = s[i]; uint32_t v;
    \\            if (h >= '0' && h <= '9') v = (uint32_t)(h - '0');
    \\            else if (h >= 'a' && h <= 'f') v = (uint32_t)(h - 'a' + 10);
    \\            else if (h >= 'A' && h <= 'F') v = (uint32_t)(h - 'A' + 10);
    \\            else return 0;
    \\            lo = lo * 16 + v;
    \\          }
    \\          if (lo < 0xDC00 || lo > 0xDFFF) return 0;
    \\          cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
    \\        } else if (cp >= 0xDC00 && cp <= 0xDFFF) return 0;
    \\        w += sa_utf8_enc(cp, &sa_mem[d + w]);
    \\      } else return 0;
    \\      i++;
    \\    } else if ((uint8_t)c < 0x20) return 0;
    \\    else { sa_mem[d + w++] = c; i++; }
    \\  }
    \\  if (i >= n) return 0;
    \\  *pos = i + 1;
    \\  *out_ptr = p;
    \\  *out_len = w;
    \\  return 1;
    \\}
    , .deps = &.{"sa_utf8_enc"} },
    .{ .name = "sa_json_guest_dup", .code =
    \\static sa_u64 sa_json_guest_dup(sa_u64 src, sa_u64 len) {
    \\  sa_u64 p = sa_alloc(len);
    \\  uint32_t d = sa_checked_addr(p, len);
    \\  uint32_t s = sa_checked_addr(src, len);
    \\  size_t i;
    \\  for (i = 0; i < (size_t)len; i++) sa_mem[d + i] = sa_mem[s + i];
    \\  return p;
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr" } },
    .{ .name = "sa_json_append_child", .code =
    \\static void sa_json_append_child(sa_json_node_t *parent, sa_json_node_t *child) {
    \\  child->next = 0;
    \\  if (parent->first == 0) {
    \\    parent->first = (sa_u64)(child - sa_json_nodes) + 1;
    \\    return;
    \\  }
    \\  { sa_json_node_t *m = &sa_json_nodes[parent->first - 1];
    \\    while (m->next != 0) m = &sa_json_nodes[m->next - 1];
    \\    m->next = (sa_u64)(child - sa_json_nodes) + 1; }
    \\}
    , .deps = &.{} },
    .{ .name = "sa_json_child_named", .code =
    \\static sa_json_node_t *sa_json_child_named(sa_json_node_t *obj, uint32_t k, sa_u64 klen) {
    \\  sa_u64 ci = obj->first;
    \\  while (ci != 0) {
    \\    sa_json_node_t *m = &sa_json_nodes[ci - 1];
    \\    if (m->klen == klen) {
    \\      uint32_t mk = sa_checked_addr(m->kptr, m->klen);
    \\      size_t i; int eq = 1;
    \\      for (i = 0; i < (size_t)klen; i++) {
    \\        if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }
    \\      }
    \\      if (eq) return m;
    \\    }
    \\    ci = m->next;
    \\  }
    \\  return 0;
    \\}
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_json_unlink_child", .code =
    \\static void sa_json_unlink_child(sa_json_node_t *parent, sa_json_node_t *child) {
    \\  sa_u64 want = (sa_u64)(child - sa_json_nodes) + 1;
    \\  if (parent->first == want) {
    \\    parent->first = child->next;
    \\    child->next = 0;
    \\    return;
    \\  }
    \\  { sa_u64 ci = parent->first;
    \\    while (ci != 0) {
    \\      sa_json_node_t *m = &sa_json_nodes[ci - 1];
    \\      if (m->next == want) {
    \\        m->next = child->next;
    \\        child->next = 0;
    \\        return;
    \\      }
    \\      ci = m->next;
    \\    } }
    \\}
    , .deps = &.{} },
    .{ .name = "sa_json_retire_subtree", .code =
    \\static void sa_json_retire_subtree(sa_json_node_t *nd) {
    \\  sa_u64 ci = nd->first;
    \\  while (ci != 0) {
    \\    sa_json_node_t *m = &sa_json_nodes[ci - 1];
    \\    sa_u64 nx = m->next;
    \\    sa_json_retire_subtree(m);
    \\    ci = nx;
    \\  }
    \\  nd->h = 0;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_json_clone_node", .code =
    \\static sa_json_node_t *sa_json_clone_node(sa_json_node_t *src) {
    \\  sa_json_node_t *nd = sa_json_new();
    \\  if (nd == 0) return 0;
    \\  nd->kind = src->kind;
    \\  nd->ival = src->ival;
    \\  nd->fbits = src->fbits;
    \\  nd->bval = src->bval;
    \\  nd->vlen = src->vlen;
    \\  if (src->vlen > 0) nd->vptr = sa_json_guest_dup(src->vptr, src->vlen);
    \\  { sa_u64 ci = src->first;
    \\    sa_json_node_t *last = 0;
    \\    while (ci != 0) {
    \\      sa_json_node_t *cm = &sa_json_nodes[ci - 1];
    \\      sa_u64 nx = cm->next;
    \\      sa_json_node_t *cc = sa_json_clone_node(cm);
    \\      if (cc == 0) return 0;
    \\      cc->klen = cm->klen;
    \\      if (cm->klen > 0) cc->kptr = sa_json_guest_dup(cm->kptr, cm->klen);
    \\      cc->next = 0;
    \\      if (last == 0) nd->first = (sa_u64)(cc - sa_json_nodes) + 1;
    \\      else last->next = (sa_u64)(cc - sa_json_nodes) + 1;
    \\      last = cc;
    \\      ci = nx;
    \\    } }
    \\  return nd;
    \\}
    , .deps = &.{ "sa_json_new", "sa_json_guest_dup" } },
    .{ .name = "sa_regex_exec_range", .code =
    \\static int sa_regex_exec_range(sa_regex_t *r, sa_u64 tp, sa_u64 tl, sa_u64 pos, regmatch_t *pm, sa_u64 n) {
    \\  uint32_t td = sa_checked_addr(tp, tl + 1);
    \\  pm[0].rm_so = (regoff_t)pos;
    \\  pm[0].rm_eo = (regoff_t)tl;
    \\  return regexec(&r->rx, (const char *)&sa_mem[td], (size_t)n, pm, REG_STARTEND);
    \\}
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_rb_put", .code =
    \\static void sa_rb_put(sa_u64 *base, sa_u64 *len, sa_u64 *cap, const uint8_t *sp, sa_u64 n) {
    \\  if (n == 0) return;
    \\  if (*len + n > *cap) {
    \\    sa_u64 ncap = *cap == 0 ? 64 : *cap;
    \\    while (ncap < *len + n) ncap *= 2;
    \\    { sa_u64 nb = sa_alloc(ncap);
    \\      uint32_t d = sa_checked_addr(nb, ncap);
    \\      if (*len > 0) {
    \\        uint32_t s = sa_checked_addr(*base, *len);
    \\        size_t i;
    \\        for (i = 0; i < (size_t)*len; i++) sa_mem[d + i] = sa_mem[s + i];
    \\      }
    \\      *base = nb;
    \\      *cap = ncap; }
    \\  }
    \\  { uint32_t d = sa_checked_addr(*base, *len + n);
    \\    size_t i;
    \\    for (i = 0; i < (size_t)n; i++) sa_mem[d + *len + i] = sp[i]; }
    \\  *len += n;
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr" } },
    .{ .name = "sa_regex_put_group", .code =
    \\static void sa_regex_put_group(sa_u64 *base, sa_u64 *len, sa_u64 *cap, uint32_t td, regmatch_t *pm, sa_u64 idx) {
    \\  if (pm[idx].rm_so < 0 || pm[idx].rm_eo < pm[idx].rm_so) return;
    \\  sa_rb_put(base, len, cap, &sa_mem[td + (sa_u64)pm[idx].rm_so],
    \\    (sa_u64)(pm[idx].rm_eo - pm[idx].rm_so));
    \\}
    , .deps = &.{"sa_rb_put"} },
    .{ .name = "sa_regex_expand_into", .code =
    \\/* Template expansion mirroring sa_std regexExpandInto. Byte codes:
    \\   36='$' 38='&' 96=backtick 39=quote 48..57 digits. */
    \\static void sa_regex_expand_into(sa_u64 *base, sa_u64 *len, sa_u64 *cap,
    \\    sa_u64 tp, sa_u64 tl, regmatch_t *pm, sa_u64 n, sa_u64 rp, sa_u64 rl) {
    \\  uint32_t td = sa_checked_addr(tp, tl);
    \\  uint32_t rd = sa_checked_addr(rp, rl);
    \\  sa_u64 total = n - 1;
    \\  sa_u64 i = 0;
    \\  while (i < rl) {
    \\    uint8_t c = sa_mem[rd + i];
    \\    if (c != 36 || i + 1 >= rl) {
    \\      sa_rb_put(base, len, cap, &sa_mem[rd + i], 1);
    \\      i += 1;
    \\      continue;
    \\    }
    \\    { uint8_t nx = sa_mem[rd + i + 1];
    \\      if (nx == 36) {
    \\        sa_rb_put(base, len, cap, &sa_mem[rd + i], 1);
    \\        i += 2;
    \\      } else if (nx == 38) {
    \\        sa_regex_put_group(base, len, cap, td, pm, 0);
    \\        i += 2;
    \\      } else if (nx == 96) {
    \\        if (pm[0].rm_so > 0)
    \\          sa_rb_put(base, len, cap, &sa_mem[td], (sa_u64)pm[0].rm_so);
    \\        i += 2;
    \\      } else if (nx == 39) {
    \\        if (pm[0].rm_eo >= 0 && (sa_u64)pm[0].rm_eo < tl)
    \\          sa_rb_put(base, len, cap, &sa_mem[td + (sa_u64)pm[0].rm_eo],
    \\            tl - (sa_u64)pm[0].rm_eo);
    \\        i += 2;
    \\      } else if (nx >= 49 && nx <= 57) {
    \\        sa_u64 d1 = (sa_u64)(nx - 49) + 1;
    \\        sa_u64 consumed = 0;
    \\        if (i + 2 < rl && sa_mem[rd + i + 2] >= 48 && sa_mem[rd + i + 2] <= 57) {
    \\          sa_u64 nn = d1 * 10 + (sa_u64)(sa_mem[rd + i + 2] - 48);
    \\          if (nn >= 1 && nn <= total) {
    \\            sa_regex_put_group(base, len, cap, td, pm, nn);
    \\            consumed = 3;
    \\          }
    \\        }
    \\        if (consumed == 0 && d1 <= total) {
    \\          sa_regex_put_group(base, len, cap, td, pm, d1);
    \\          consumed = 2;
    \\        }
    \\        if (consumed == 0) {
    \\          sa_rb_put(base, len, cap, &sa_mem[rd + i], 1);
    \\          i += 1;
    \\        } else {
    \\          i += consumed;
    \\        }
    \\      } else {
    \\        sa_rb_put(base, len, cap, &sa_mem[rd + i], 1);
    \\        i += 1;
    \\      } }
    \\  }
    \\}
    , .deps = &.{ "sa_checked_addr", "sa_rb_put", "sa_regex_put_group" } },
};
