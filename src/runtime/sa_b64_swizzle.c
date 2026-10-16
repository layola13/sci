/* sa_b64dec_avx2: AVX2 base64 decoding kernel + runtime dispatch.
 *
 * Vector translation and packing adapted from simdutf,
 *   src/haswell/avx2_base64.cpp
 *   (to_base64_mask strict-standard tables + base64_decode pack),
 * which is Copyright (c) the simdutf authors, licensed under Apache-2.0
 * (https://github.com/simdutf/simdutf/blob/master/LICENSE-APACHE).
 * Translation-table approach credit: Wojciech Mula; packing with
 * multiply-add credit: aqrit. This file keeps that attribution as
 * required by the license; the surrounding stop-at-first-invalid
 * contract, scalar tail, and SA dispatch glue are original work.
 *
 * Contract mirrors sa_b64dec_simd in sa_std.zig: clean A-Za-z0-9+/
 * input with n % 4 == 0 yields n/4*3 bytes; stops at the first
 * non-alphabet char (including '='), returning bytes written.
 * Processes 64-byte blocks while both 32-byte halves validate;
 * scalar tail covers the rest (whole trailing quanta).
 *
 * Portability: x86-64 only code is inside #if guards with per-function
 * target("avx2") attributes, so no TU-wide -mavx2 flag is needed and
 * other architectures compile to stubs (Zig falls back to the
 * portable Mula path). Never execute the kernel without checking
 * sa_cpu_has_avx2() first.
 */
#include <stdint.h>

#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#if defined(__GNUC__) || defined(__clang__)
#include <cpuid.h>
/* _xgetbv needs the xsave feature; explicit -mcpu=baseline release
   builds (cross targets) lack it TU-wide, so enable it for the
   dispatch probe only. Other architectures never see this TU region. */
#define SA_XSAVE_ATTR __attribute__((target("xsave")))
#else
#define SA_XSAVE_ATTR
#endif

static const uint8_t kDeltaAsso[32] = {
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x0F, 0x00, 0x0F, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x0F};
static const uint8_t kDeltaVals[32] = {
    0x00, 0x00, 0x00, 0x13, 0x04, 0xBF, 0xBF, 0xB9, 0xB9, 0x00, 0x10, 0xC3,
    0xBF, 0xBF, 0xB9, 0xB9, 0x00, 0x00, 0x00, 0x13, 0x04, 0xBF, 0xBF, 0xB9,
    0xB9, 0x00, 0x10, 0xC3, 0xBF, 0xBF, 0xB9, 0xB9};
static const uint8_t kCheckAsso[32] = {
    0x0D, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x03, 0x07,
    0x0B, 0x0B, 0x0B, 0x0F, 0x0D, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x03, 0x07, 0x0B, 0x0B, 0x0B, 0x0F};
static const uint8_t kCheckVals[32] = {
    0x80, 0x80, 0x80, 0x80, 0xCF, 0xBF, 0xD5, 0xA6, 0xB5, 0x86, 0xD1, 0x80,
    0xB1, 0x80, 0x91, 0x80, 0x80, 0x80, 0x80, 0x80, 0xCF, 0xBF, 0xD5, 0xA6,
    0xB5, 0x86, 0xD1, 0x80, 0xB1, 0x80, 0x91, 0x80};
static const int8_t kPackShuf[32] = {2,  1,  0,  6,   5,   4,   10, 9,
                                     8,  14, 13, 12,  -1,  -1,  -1, -1,
                                     2,  1,  0,  6,   5,   4,   10, 9,
                                     8,  14, 13, 12,  -1,  -1,  -1, -1};

/* Translate 32 chars -> 32 sextets; returns movemask (0 = all valid). */
__attribute__((target("avx2,bmi,bmi2"), always_inline)) static inline int
b64_trans32(const uint8_t *src, uint8_t *sext) {
  __m256i v = _mm256_loadu_si256((const __m256i *)src);
  __m256i da = _mm256_loadu_si256((const __m256i *)kDeltaAsso);
  __m256i dv = _mm256_loadu_si256((const __m256i *)kDeltaVals);
  __m256i ca = _mm256_loadu_si256((const __m256i *)kCheckAsso);
  __m256i cv = _mm256_loadu_si256((const __m256i *)kCheckVals);
  __m256i shifted = _mm256_srli_epi32(v, 3);
  __m256i delta_hash =
      _mm256_avg_epu8(_mm256_shuffle_epi8(da, v), shifted);
  __m256i check_hash =
      _mm256_avg_epu8(_mm256_shuffle_epi8(ca, v), shifted);
  __m256i out = _mm256_adds_epi8(_mm256_shuffle_epi8(dv, delta_hash), v);
  __m256i chk = _mm256_adds_epi8(_mm256_shuffle_epi8(cv, check_hash), v);
  _mm256_storeu_si256((__m256i *)sext, out);
  return _mm256_movemask_epi8(chk);
}

/* Pack 32 sextets -> exactly 24 bytes (4 exact stores, no overhang). */
__attribute__((target("avx2,bmi,bmi2"), always_inline)) static inline void
b64_pack24(const uint8_t *sext, uint8_t *out) {
  __m256i str = _mm256_loadu_si256((const __m256i *)sext);
  __m256i sh = _mm256_loadu_si256((const __m256i *)kPackShuf);
  __m256i t0 = _mm256_maddubs_epi16(str, _mm256_set1_epi32(0x01400140));
  __m256i t1 = _mm256_madd_epi16(t0, _mm256_set1_epi32(0x00011000));
  __m256i t2 = _mm256_shuffle_epi8(t1, sh);
  __m128i lo = _mm256_castsi256_si128(t2);
  __m128i hi = _mm256_extracti128_si256(t2, 1);
  _mm_storel_epi64((__m128i *)out, lo);
  {
    uint32_t b8_11 = (uint32_t)_mm_extract_epi32(lo, 2);
    __builtin_memcpy(out + 8, &b8_11, 4);
  }
  _mm_storel_epi64((__m128i *)(out + 12), hi);
  {
    uint32_t b20_23 = (uint32_t)_mm_extract_epi32(hi, 2);
    __builtin_memcpy(out + 20, &b20_23, 4);
  }
}

static inline int b64_sextet_val(uint8_t c) {
  if (c >= (uint8_t)'A' && c <= (uint8_t)'Z')
    return (int)c - 65;
  if (c >= (uint8_t)'a' && c <= (uint8_t)'z')
    return (int)c - 71;
  if (c >= (uint8_t)'0' && c <= (uint8_t)'9')
    return (int)c + 4;
  if (c == (uint8_t)'+')
    return 62;
  if (c == (uint8_t)'/')
    return 63;
  return -1;
}

SA_XSAVE_ATTR
int sa_cpu_has_avx2(void) {
  static int cached = -1;
  int v = __atomic_load_n(&cached, __ATOMIC_RELAXED);
  if (v < 0) {
#if (defined(__x86_64__) || defined(_M_X64)) &&                          \
    (defined(__GNUC__) || defined(__clang__))
    /* Raw cpuid+xgetbv: no libgcc dependency (__builtin_cpu_supports
       needs __cpu_model). AVX2 needs OSXSAVE + AVX2 bit + OS XMM/YMM. */
    unsigned a = 0, b = 0, c = 0, d = 0;
    if (!__get_cpuid(1, &a, &b, &c, &d)) {
      v = 0;
    } else if ((c & (1u << 27)) == 0) {
      v = 0;
    } else if (!__get_cpuid_count(7, 0, &a, &b, &c, &d)) {
      v = 0;
    } else if ((b & (1u << 5)) == 0) {
      v = 0;
    } else {
      uint64_t xcr = _xgetbv(0);
      v = ((xcr & 0x6u) == 0x6u) ? 1 : 0;
    }
#else
    v = 0;
#endif
    __atomic_store_n(&cached, v, __ATOMIC_RELAXED);
  }
  return v;
}

__attribute__((target("avx2,bmi,bmi2"))) uint64_t
sa_b64dec_avx2(const uint8_t *in, uint64_t len, uint8_t *out) {
  uint64_t i = 0, w = 0;
  if (in == 0 || out == 0 || len == 0)
    return 0;
  while (i + 64 <= len) {
    uint8_t s0[32], s1[32];
    int m0 = b64_trans32(in + i, s0);
    int m1 = b64_trans32(in + i + 32, s1);
    if ((m0 | m1) != 0)
      break;
    b64_pack24(s0, out + w);
    b64_pack24(s1, out + w + 24);
    i += 64;
    w += 48;
  }
  while (i + 4 <= len) {
    int a = b64_sextet_val(in[i]);
    int b = b64_sextet_val(in[i + 1]);
    int c = b64_sextet_val(in[i + 2]);
    int d = b64_sextet_val(in[i + 3]);
    if ((a | b | c | d) < 0)
      break;
    /* NOTE: (a|b|c|d)<0 is the invalid test only because valid sextets
       are non-negative; a|b|c|d is non-negative iff all four are. */
    out[w] = (uint8_t)(((uint32_t)a << 2) | ((uint32_t)b >> 4));
    out[w + 1] =
        (uint8_t)((((uint32_t)b & 15) << 4) | ((uint32_t)c >> 2));
    out[w + 2] = (uint8_t)((((uint32_t)c & 3) << 6) | (uint32_t)d);
    i += 4;
    w += 3;
  }
  return w;
}

#else /* non-x86_64: stubs, Zig uses the portable path */

int sa_cpu_has_avx2(void) { return 0; }

uint64_t sa_b64dec_avx2(const uint8_t *in, uint64_t len, uint8_t *out) {
  (void)in;
  (void)len;
  (void)out;
  return 0;
}

#endif
