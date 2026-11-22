// JS runtime header chunk (moved from src/emit_js.zig writeRuntimeHeader).
// Pure data: the emitted JS source text for the runtime header.
pub const header_runtime_js_memory =
        \\// ---- SA JS runtime (MVP, JEV: ArrayBuffer linear memory) ----
        \\const __SA_MEM_BYTES = __SA_MEM_BYTES_DECL__;
        \\const __sa_memory = new ArrayBuffer(__SA_MEM_BYTES);
        \\const __sa_view = new DataView(__sa_memory);
        \\const __sa_u8 = new Uint8Array(__sa_memory);
        \\const __sa_ti8 = new Int8Array(__sa_memory);
        \\const __sa_ti16 = new Int16Array(__sa_memory);
        \\const __sa_tu16 = new Uint16Array(__sa_memory);
        \\const __sa_ti32 = new Int32Array(__sa_memory);
        \\const __sa_tu32 = new Uint32Array(__sa_memory);
        \\const __sa_tf32 = new Float32Array(__sa_memory);
        \\const __sa_tf64 = new Float64Array(__sa_memory);
        \\const __sa_tb64 = new BigInt64Array(__sa_memory);
        \\const __sa_buf = (typeof globalThis.Buffer !== "undefined" && globalThis.Buffer.from) ? globalThis.Buffer.from(__sa_memory) : null; // zero-copy host Buffer: C++ memset/memmove fast path for bulk shims (both node and bun provide it)
        \\const __sa_use_dv64 = (typeof globalThis.Bun !== "undefined"); // JSC BigInt typed arrays are slow; DataView is ~3x faster there
        \\let __sa_brk = 65536; // bump allocator starts after reserved zero page region
        \\const __sa_live = new Set(); // live BIG heap bases (>32B, user pointers handed out by __sa_alloc)
        \\const __sa_fl = Object.create(null); // free-list buckets: aligned size -> stack of user pointers (big blocks only)
        \\const __sa_SMALL_MAX = 32; // headerless slab classes: 8/16/24/32
        \\const __sa_SLAB = 4096; // bytes per slab chunk carved from linear memory
        \\const __sa_slab_by_page = new Map(); // (chunkBase >>> 12) -> slab record
        \\const __sa_slab_by_class = { 8: [], 16: [], 24: [], 32: [] }; // per-class slab chunks
        \\const __sa_slab_hint = { 8: null, 16: null, 24: null, 32: null }; // slab known to have a free slot
        \\function __sa_slab_new(sc) {
        \\  if (!__sa_slab_by_class[sc]) __sa_slab_by_class[sc] = [];
        \\  if (!(sc > 0)) __sa_trap("bad slab class");
        \\  __sa_brk = (__sa_brk + (__sa_SLAB - 1)) & ~(__sa_SLAB - 1);
        \\  const base = __sa_brk;
        \\  __sa_brk += __sa_SLAB;
        \\  if (__sa_brk >= __sa_memory.byteLength) __sa_trap("out of memory (slab)");
        \\  __sa_u8.fill(0, base, base + __sa_SLAB);
        \\  const count = (__sa_SLAB / sc) | 0;
        \\  const slab = { base, sc, count, next: 0, free: new Int32Array(count), top: 0, live: new Uint8Array(count) };
        \\  __sa_slab_by_page.set(base >>> 12, slab);
        \\  __sa_slab_by_class[sc].push(slab);
        \\  __sa_slab_hint[sc] = slab;
        \\  return slab;
        \\}
        \\function __sa_slab_take(slab) {
        \\  let idx;
        \\  if (slab.top > 0) idx = slab.free[--slab.top];
        \\  else idx = slab.next++;
        \\  slab.live[idx] = 1;
        \\  if (slab.top === 0 && slab.next >= slab.count && __sa_slab_hint[slab.sc] === slab) __sa_slab_hint[slab.sc] = null;
        \\  const ptr = slab.base + idx * slab.sc;
        \\  __sa_u8.fill(0, ptr, ptr + slab.sc);
        \\  return ptr | 0;
        \\}
        \\function __sa_slab_alloc(sc) {
        \\  sc = __sa_align((__sa_num(sc) | 0), 8);
        \\  if (sc <= 0) sc = 8;
        \\  if (sc > __sa_SMALL_MAX) __sa_trap("bad slab class " + sc);
        \\  if (!__sa_slab_by_class[sc]) { __sa_slab_by_class[sc] = []; __sa_slab_hint[sc] = null; }
        \\  let slab = __sa_slab_hint[sc];
        \\  if (!slab || (slab.top === 0 && slab.next >= slab.count)) {
        \\    const list = __sa_slab_by_class[sc];
        \\    slab = null;
        \\    for (let i = list.length - 1; i >= 0; i--) { const c = list[i]; if (c.top > 0 || c.next < c.count) { slab = c; break; } }
        \\    if (!slab) slab = __sa_slab_new(sc);
        \\    __sa_slab_hint[sc] = slab;
        \\  }
        \\  return __sa_slab_take(slab);
        \\}
        \\function __sa_slab_release(ptr) {
        \\  // Recycle one live slab slot; foreign, misaligned, const or
        \\  // already-free pointers report false (all stay silent no-ops).
        \\  const p = __sa_addr(ptr);
        \\  const slab = __sa_slab_by_page.get(p >>> 12);
        \\  if (!slab) return false;
        \\  const off = p - slab.base;
        \\  const idx = (off / slab.sc) | 0;
        \\  if (idx < 0 || idx >= slab.count || slab.base + idx * slab.sc !== p) return false;
        \\  if (!slab.live[idx]) return false;
        \\  slab.live[idx] = 0;
        \\  slab.free[slab.top++] = idx;
        \\  __sa_slab_hint[slab.sc] = slab;
        \\  return true;
        \\}
        \\function __sa_mem_used() { return (__sa_brk - 65536) | 0; } // linear bytes consumed (slab metadata excluded)
        \\function __sa_trap(msg) { throw new Error("[sa-trap] " + msg); }
        \\function __sa_panic(code) { throw new Error("[sa-panic] code=" + code); }
        \\function __sa_truthy(v) { return !!v; }
        \\const __SA_FN_BASE = 0x5341000000000000n;
        \\function __sa_fnptr(i) { return __SA_FN_BASE + BigInt(i); }
        \\function __sa_fnval(v) { const d = BigInt(v) - __SA_FN_BASE; return (d >= 0n && d < BigInt(__sa_ftable.length)) ? Number(d) : -1; }
        \\function __sa_call_indirect(f, ...args) { const i = __sa_fnval(f); if (i < 0) __sa_trap("bad indirect callee"); return __sa_ftable[i](...args); }
        \\function __sa_fok(t) { return ((t && typeof t === "object" && ("s" in t)) ? ((t.s | 0) === 0) : true); }
        \\function __sa_fv(t) { return ((t && typeof t === "object" && ("v" in t)) ? t.v : t); }
        \\function __sa_num(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_addr(a) { return (typeof a === "bigint") ? Number(BigInt.asUintN(32, a)) : (a | 0); }
        \\function __sa_align(n, a) { return (n + (a - 1)) & ~(a - 1); }
        \\function __sa_alloc(size) {
        \\  size = __sa_align((__sa_num(size) | 0), 8);
        \\  if (!(size > 0)) size = 8; // malloc(0)-style: never hand out class 0 (was: slab list undefined -> TypeError length)
        \\  if (size <= __sa_SMALL_MAX) return __sa_slab_alloc(size); // headerless, no live Set
        \\  const bucket = __sa_fl[size];
        \\  if (bucket && bucket.length) { const ptr = bucket.pop(); __sa_u8.fill(0, ptr, ptr + size); __sa_live.add(ptr | 0); return ptr | 0; }
        \\  const total = (size + 8); // 8-byte header holds the aligned user size
        \\  const base = __sa_brk;
        \\  __sa_brk += total;
        \\  if (__sa_brk >= __sa_memory.byteLength) __sa_trap("out of memory (bump)");
        \\  __sa_u8.fill(0, base, base + total);
        \\  __sa_view.setUint32(base, size, true);
        \\  const ptr = (base + 8);
        \\  __sa_live.add(ptr | 0);
        \\  return ptr | 0;
        \\}
        \\function __sa_free(ptr) {
        \\  // Mirrors the interpreter: only exact live heap bases are recycled.
        \\  // Slab members (<=32B) recycle via bitset; big bases via the live
        \\  // Set + header. BigInt pointers are normalized to 32-bit addresses
        \\  // first so 64-bit-typed bases stay freeable; interior pointers,
        \\  // consts and unknown addresses remain no-ops.
        \\  if (__sa_slab_release(ptr)) return 0;
        \\  const p = __sa_addr(ptr);
        \\  if (!__sa_live.has(p)) return 0;
        \\  __sa_live.delete(p);
        \\  const size = __sa_view.getUint32((p - 8), true);
        \\  (__sa_fl[size] || (__sa_fl[size] = [])).push(p);
        \\  return 0;
        \\}
        \\const __sa_fstack = []; // call-stack of frames; each frame lists its stack slots
        \\function __sa_salloc(size) {
        \\  // Function-scoped allocation: freed when the owning frame returns
        \\  // via __sa_sfree (mirrors stack-slot lifetime; the interpreter
        \\  // never frees these mid-frame either). Small sizes ride the
        \\  // headerless slab (no __sa_live); big sizes share the free-list
        \\  // pool with __sa_alloc (every big block keeps its 8-byte header).
        \\  // Either way the live Set is untouched, so frame temporaries skip
        \\  // both Set add/delete on the hot path. Returned blocks are
        \\  // recycled on frame pop.
        \\  size = __sa_align((__sa_num(size) | 0), 8);
        \\  if (!(size > 0)) size = 8;
        \\  if (!__sa_fstack.length) return __sa_alloc(size);
        \\  let ptr;
        \\  if (size <= __sa_SMALL_MAX) { ptr = __sa_slab_alloc(size); }
        \\  else {
        \\  const bucket = __sa_fl[size];
        \\  if (bucket && bucket.length) { ptr = bucket.pop(); __sa_u8.fill(0, ptr, ptr + size); }
        \\  else {
        \\    const base = __sa_brk;
        \\    __sa_brk += (size + 8);
        \\    if (__sa_brk >= __sa_memory.byteLength) __sa_trap("out of memory (bump)");
        \\    __sa_u8.fill(0, base, base + size + 8);
        \\    __sa_view.setUint32(base, size, true);
        \\    ptr = (base + 8);
        \\  }
        \\  }
        \\  __sa_fstack[__sa_fstack.length - 1].push(ptr | 0);
        \\  return ptr | 0;
        \\}
        \\function __sa_sfree(ptr) {
        \\  // Frame-pop recycle for __sa_salloc blocks: slab members via
        \\  // bitset, big blocks via header size. No __sa_live membership
        \\  // test needed (salloc never registers).
        \\  if (__sa_slab_release(ptr)) return 0;
        \\  const p = __sa_addr(ptr);
        \\  const size = __sa_view.getUint32((p - 8), true);
        \\  (__sa_fl[size] || (__sa_fl[size] = [])).push(p);
        \\  return 0;
        \\}
        \\function __sa_load_i8(addr) { return __sa_ti8[__sa_addr(addr)]; }
        \\function __sa_load_u8(addr) { return __sa_u8[__sa_addr(addr)]; }
        \\function __sa_load_i16(addr) { const a = __sa_addr(addr); return ((a & 1) === 0) ? __sa_ti16[a >> 1] : __sa_view.getInt16(a, true); }
        \\function __sa_load_u16(addr) { const a = __sa_addr(addr); return ((a & 1) === 0) ? __sa_tu16[a >> 1] : __sa_view.getUint16(a, true); }
        \\function __sa_load_i32(addr) { const a = __sa_addr(addr); return ((a & 3) === 0) ? __sa_ti32[a >> 2] : __sa_view.getInt32(a, true); }
        \\function __sa_load_u32(addr) { const a = __sa_addr(addr); return ((a & 3) === 0) ? __sa_tu32[a >> 2] : __sa_view.getUint32(a, true); }
        \\function __sa_load_f32(addr) { const a = __sa_addr(addr); return ((a & 3) === 0) ? __sa_tf32[a >> 2] : __sa_view.getFloat32(a, true); }
        \\function __sa_load_f64(addr) { const a = __sa_addr(addr); return ((a & 7) === 0) ? __sa_tf64[a >> 3] : __sa_view.getFloat64(a, true); }
        \\function __sa_store_i8(addr, v) { __sa_ti8[__sa_addr(addr)] = __sa_narrow(v, 8, true); }
        \\function __sa_store_u8(addr, v) { __sa_u8[__sa_addr(addr)] = __sa_narrow(v, 8, false); }
        \\function __sa_store_i16(addr, v) { const a = __sa_addr(addr); const n = __sa_narrow(v, 16, true); if ((a & 1) === 0) __sa_ti16[a >> 1] = n; else __sa_view.setInt16(a, n, true); }
        \\function __sa_store_u16(addr, v) { const a = __sa_addr(addr); const n = __sa_narrow(v, 16, false); if ((a & 1) === 0) __sa_tu16[a >> 1] = n; else __sa_view.setUint16(a, n, true); }
        \\function __sa_store_i32(addr, v) { const a = __sa_addr(addr); const n = __sa_narrow(v, 32, true); if ((a & 3) === 0) __sa_ti32[a >> 2] = n; else __sa_view.setInt32(a, n, true); }
        \\function __sa_store_u32(addr, v) { const a = __sa_addr(addr); const n = __sa_narrow(v, 32, false); if ((a & 3) === 0) __sa_tu32[a >> 2] = n; else __sa_view.setUint32(a, n, true); }
        \\function __sa_store_f32(addr, v) { const a = __sa_addr(addr); const n = +v; if ((a & 3) === 0) __sa_tf32[a >> 2] = n; else __sa_view.setFloat32(a, n, true); }
        \\function __sa_store_f64(addr, v) { const a = __sa_addr(addr); const n = +v; if ((a & 7) === 0) __sa_tf64[a >> 3] = n; else __sa_view.setFloat64(a, n, true); }
        \\function __sa_load_i64(addr) { const a = __sa_addr(addr); if (__sa_use_dv64) return __sa_view.getBigInt64(a, true); return ((a & 7) === 0) ? __sa_tb64[a >> 3] : __sa_view.getBigInt64(a, true); }
        \\function __sa_store_i64(addr, v) { const a = __sa_addr(addr); const n = BigInt.asIntN(64, BigInt(v)); if (__sa_use_dv64) { __sa_view.setBigInt64(a, n, true); return; } if ((a & 7) === 0) __sa_tb64[a >> 3] = n; else __sa_view.setBigInt64(a, n, true); }
        \\function __sa_load_ptr(addr) { return __sa_load_i64(addr); }
        \\function __sa_store_ptr(addr, v) { __sa_store_i64(addr, v); }
        \\function __sa_ptr_add(ptr, off) {
        \\  if (typeof ptr === "bigint" || typeof off === "bigint") return BigInt.asIntN(64, BigInt(ptr) + BigInt(off));
        \\  return (ptr + off) | 0;
        \\}
        \\function __sa_i32(v) { return v | 0; }
        \\function __sa_i64(v) { return BigInt.asIntN(64, BigInt(v)); }
        \\function __sa_f64(v) { return +v; }
        \\function __sa_BI(v) { return BigInt.asIntN(64, BigInt(v)); }
        \\function __sa_BU(v) { return BigInt.asUintN(64, BigInt(v)); }
        \\function __sa_isBI(a, b) { return typeof a === "bigint" || typeof b === "bigint"; }
        \\function __sa_add(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) + BigInt(b)) : ((+a) + (+b)); }
        \\function __sa_sub(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) - BigInt(b)) : ((+a) - (+b)); }
        \\function __sa_mul(a, b) { if (__sa_isBI(a, b)) return __sa_BI(BigInt(a) * BigInt(b)); const p = (+a) * (+b); return (p >= -2147483648 && p <= 2147483647) ? (p | 0) : (Number.isSafeInteger(p) ? p : __sa_BI(BigInt(a) * BigInt(b))); }
        \\function __sa_sdiv(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) { const nb = BigInt.asIntN(64, BigInt(b)); if (nb === 0n) __sa_trap("div by zero"); return __sa_BI(BigInt.asIntN(64, BigInt(a)) / nb); } const nb32 = (b | 0); if (nb32 === 0) __sa_trap("div by zero"); return (Math.trunc((a | 0) / nb32) | 0); }
        \\function __sa_udiv(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) { const x = __sa_BU(a), y = __sa_BU(b); if (y === 0n) __sa_trap("div by zero"); return x / y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("div by zero"); return Math.trunc((a >>> 0) / y32); }
        \\function __sa_srem(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) { const nb = BigInt.asIntN(64, BigInt(b)); if (nb === 0n) __sa_trap("rem by zero"); return __sa_BI(BigInt.asIntN(64, BigInt(a)) % nb); } const nb32 = (b | 0); if (nb32 === 0) __sa_trap("rem by zero"); return (((a | 0) % nb32) | 0); }
        \\function __sa_urem(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) { const x = __sa_BU(a), y = __sa_BU(b); if (y === 0n) __sa_trap("rem by zero"); return x % y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("rem by zero"); return ((a >>> 0) % y32); }
        \\function __sa_neg(a) { return (typeof a === "bigint") ? __sa_BI(-a) : (-(+a)); }
        \\function __sa_band(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return __sa_BI(BigInt(a) & BigInt(b)); return ((a & b) | 0); }
        \\function __sa_bor(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return __sa_BI(BigInt(a) | BigInt(b)); return ((a | b) | 0); }
        \\function __sa_bxor(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return __sa_BI(BigInt(a) ^ BigInt(b)); return ((a ^ b) | 0); }
        \\function __sa_shl(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || (typeof b !== "bigint" && b > 31)) return __sa_BI(BigInt(a) << (BigInt(b) & 63n)); return ((a << (b & 31)) | 0); }
        \\function __sa_lshr(a, b) { if (typeof a === "bigint" || a < 0 || a > 4294967295 || (typeof b !== "bigint" && b > 31)) return __sa_BU(a) >> (BigInt(b) & 63n); if (typeof b === "bigint") { const k = Number(BigInt(b) & 63n); return k >= 32 ? 0 : (a >>> k); } return (a >>> (b & 31)); }
        \\function __sa_ashr(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || (typeof b !== "bigint" && b > 31)) return __sa_BI(BigInt.asIntN(64, BigInt(a)) >> (BigInt(b) & 63n)); return ((a >> (b & 31)) | 0); }
        \\function __sa_bnot(a) { if (typeof a === "bigint" || a > 2147483647 || a < -2147483648) return __sa_BI(~BigInt(a)); return ((~a) | 0); }
        \\function __sa_eq(a, b) { return ((a == b) ? 1 : 0); }
        \\function __sa_ne(a, b) { return ((a != b) ? 1 : 0); }
        \\function __sa_slt(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return ((BigInt.asIntN(64, BigInt(a)) < BigInt.asIntN(64, BigInt(b))) ? 1 : 0); return (((a | 0) < (b | 0)) ? 1 : 0); }
        \\function __sa_sle(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return ((BigInt.asIntN(64, BigInt(a)) <= BigInt.asIntN(64, BigInt(b))) ? 1 : 0); return (((a | 0) <= (b | 0)) ? 1 : 0); }
        \\function __sa_sgt(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return ((BigInt.asIntN(64, BigInt(a)) > BigInt.asIntN(64, BigInt(b))) ? 1 : 0); return (((a | 0) > (b | 0)) ? 1 : 0); }
        \\function __sa_sge(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return ((BigInt.asIntN(64, BigInt(a)) >= BigInt.asIntN(64, BigInt(b))) ? 1 : 0); return (((a | 0) >= (b | 0)) ? 1 : 0); }
        \\function __sa_ult(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) < __sa_BU(b)) ? 1 : 0); return (((a >>> 0) < (b >>> 0)) ? 1 : 0); }
        \\function __sa_ule(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) <= __sa_BU(b)) ? 1 : 0); return (((a >>> 0) <= (b >>> 0)) ? 1 : 0); }
        \\function __sa_ugt(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) > __sa_BU(b)) ? 1 : 0); return (((a >>> 0) > (b >>> 0)) ? 1 : 0); }
        \\function __sa_uge(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) >= __sa_BU(b)) ? 1 : 0); return (((a >>> 0) >= (b >>> 0)) ? 1 : 0); }
        \\function __sa_ult32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) < __sa_BU(b)) ? 1 : 0); return (((a >>> 0) < (b >>> 0)) ? 1 : 0); }
        \\function __sa_ule32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) <= __sa_BU(b)) ? 1 : 0); return (((a >>> 0) <= (b >>> 0)) ? 1 : 0); }
        \\function __sa_ugt32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) > __sa_BU(b)) ? 1 : 0); return (((a >>> 0) > (b >>> 0)) ? 1 : 0); }
        \\function __sa_uge32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) >= __sa_BU(b)) ? 1 : 0); return (((a >>> 0) >= (b >>> 0)) ? 1 : 0); }
        \\function __sa_udiv32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) { const x = __sa_BU(a), y = __sa_BU(b); if (y === 0n) __sa_trap("div by zero"); return x / y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("div by zero"); return Math.trunc((a >>> 0) / y32); }
        \\function __sa_urem32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) { const x = __sa_BU(a), y = __sa_BU(b); if (y === 0n) __sa_trap("rem by zero"); return x % y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("rem by zero"); return ((a >>> 0) % y32); }
        \\function __sa_lshr32(a, b) { if (typeof a === "bigint" || a > 4294967295 || (typeof b !== "bigint" && b > 31)) return __sa_BU(a) >> (BigInt(b) & 63n); if (typeof b === "bigint") { const k = Number(BigInt(b) & 63n); return k >= 32 ? 0 : (a >>> k); } return (a >>> (b & 31)); }
        \\function __sa_fnum(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_fadd(a, b) { return (__sa_fnum(a) + __sa_fnum(b)); }
        \\function __sa_fsub(a, b) { return (__sa_fnum(a) - __sa_fnum(b)); }
        \\function __sa_fmul(a, b) { return (__sa_fnum(a) * __sa_fnum(b)); }
        \\function __sa_fdiv(a, b) { return (__sa_fnum(a) / __sa_fnum(b)); }
        \\function __sa_fneg(a) { return (-__sa_fnum(a)); }
        \\function __sa_feq(a, b) { return ((__sa_fnum(a) === __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_fne(a, b) { return ((__sa_fnum(a) !== __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_flt(a, b) { return ((__sa_fnum(a) < __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_fle(a, b) { return ((__sa_fnum(a) <= __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_fgt(a, b) { return ((__sa_fnum(a) > __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_fge(a, b) { return ((__sa_fnum(a) >= __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_narrow(v, bits, signed) {
        \\  // Narrow any int-domain value to a target width, returned as Number.
        \\  // BigInt inputs are 64-bit sources; Number inputs are 32-bit (or
        \\  // smaller) sources. Matches interpreter wrap-around for
        \\  // trunc/zext/sext/bitcast to widths <= 32.
        \\  if (typeof v === "bigint") return signed ? Number(BigInt.asIntN(bits, v)) : Number(BigInt.asUintN(bits, v));
        \\  if (bits === 32) return signed ? (v | 0) : (v >>> 0);
        \\  if (bits === 1) return (v & 1);
        \\  const m = Math.pow(2, bits);
        \\  let r = Math.trunc(+v) % m;
        \\  if (r < 0) r += m;
        \\  if (signed && r >= m / 2) r -= m;
        \\  return r;
        \\}
        \\function __sa_wide(v, signed) {
        \\  // Widen any int-domain value to 64 bits, returned as BigInt.
        \\  // BigInt inputs are 64-bit sources (modular); Number inputs are
        \\  // 32-bit sources read with signed/unsigned 32-bit semantics.
        \\  if (typeof v === "bigint") return signed ? BigInt.asIntN(64, v) : BigInt.asUintN(64, v);
        \\  if (!Number.isFinite(+v)) return 0n;
        \\  return signed ? BigInt((+v) | 0) : BigInt((+v) >>> 0);
        \\}
        \\function __sa_cvt_trunc_i8(v) { return __sa_narrow(v, 8, true); }
        \\function __sa_cvt_trunc_i16(v) { return __sa_narrow(v, 16, true); }
        \\function __sa_cvt_trunc_i1(v) { return __sa_narrow(v, 1, false); }
        \\function __sa_cvt_trunc_i32(v) { return __sa_narrow(v, 32, true); }
        \\function __sa_cvt_trunc_u8(v) { return __sa_narrow(v, 8, false); }
        \\function __sa_cvt_trunc_u16(v) { return __sa_narrow(v, 16, false); }
        \\function __sa_cvt_trunc_u32(v) { return __sa_narrow(v, 32, false); }
        \\function __sa_cvt_trunc_i64(v) { return __sa_wide(v, true); }
        \\function __sa_cvt_trunc_u64(v) { return __sa_wide(v, false); }
        \\function __sa_cvt_trunc_ptr(v) { return __sa_cvt_ptr64(v); }
        \\function __sa_cvt_zext_i8(v) { return __sa_narrow(v, 8, false); }
        \\function __sa_cvt_zext_i16(v) { return __sa_narrow(v, 16, false); }
        \\function __sa_cvt_zext_i1(v) { return __sa_narrow(v, 1, false); }
        \\function __sa_cvt_zext_i32(v) { return __sa_narrow(v, 32, false); }
        \\function __sa_cvt_zext_u8(v) { return __sa_narrow(v, 8, false); }
        \\function __sa_cvt_zext_u16(v) { return __sa_narrow(v, 16, false); }
        \\function __sa_cvt_zext_u32(v) { return __sa_narrow(v, 32, false); }
        \\function __sa_cvt_zext_i64(v) { return (typeof v === "bigint") ? BigInt.asIntN(64, v) : BigInt((+v) >>> 0); }
        \\function __sa_cvt_zext_u64(v) { return (typeof v === "bigint") ? BigInt.asUintN(64, v) : BigInt((+v) >>> 0); }
        \\function __sa_cvt_zext_ptr(v) { return __sa_cvt_ptr64(v); }
        \\function __sa_cvt_sext_i8(v) { return __sa_narrow(v, 8, true); }
        \\function __sa_cvt_sext_i16(v) { return __sa_narrow(v, 16, true); }
        \\function __sa_cvt_sext_i1(v) { return __sa_narrow(v, 1, false); }
        \\function __sa_cvt_sext_i32(v) { return __sa_narrow(v, 32, true); }
        \\function __sa_cvt_sext_u8(v) { return __sa_narrow(v, 8, true); }
        \\function __sa_cvt_sext_u16(v) { return __sa_narrow(v, 16, true); }
        \\function __sa_cvt_sext_u32(v) { return __sa_narrow(v, 32, true); }
        \\function __sa_cvt_sext_i64(v) { return (typeof v === "bigint") ? BigInt.asIntN(64, v) : BigInt.asIntN(64, BigInt(Math.trunc(+v))); }
        \\function __sa_cvt_sext_u64(v) { return (typeof v === "bigint") ? BigInt.asUintN(64, v) : BigInt.asUintN(64, BigInt(Math.trunc(+v))); }
        \\function __sa_cvt_sext_ptr(v) { return __sa_cvt_ptr64(v); }
        \\function __sa_cvt_sitofp_f64(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_cvt_sitofp_f32(v) { return Math.fround((typeof v === "bigint") ? Number(v) : (+v)); }
        \\function __sa_cvt_uitofp_f64(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_cvt_uitofp_f32(v) { return Math.fround((typeof v === "bigint") ? Number(v) : (+v)); }
        \\function __sa_cvt_fptosi_i64(v) {
        \\  // Truncate toward zero like LLVM fptosi; out-of-range/NaN/Inf
        \\  // maps to INT64_MIN (x86 cvttsd2si behavior) instead of throwing.
        \\  const t = Math.trunc(+v);
        \\  if (!Number.isFinite(t) || t >= 9223372036854775808 || t < -9223372036854775808) return -9223372036854775808n;
        \\  return BigInt(t);
        \\}
        \\function __sa_cvt_fptosi_u64(v) { return BigInt.asUintN(64, __sa_cvt_fptosi_i64(v)); }
        \\function __sa_cvt_fptosi_i32(v) { return Number(BigInt.asIntN(32, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_u32(v) { return Number(BigInt.asUintN(32, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_i16(v) { return Number(BigInt.asIntN(16, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_u16(v) { return Number(BigInt.asUintN(16, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_i8(v) { return Number(BigInt.asIntN(8, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_u8(v) { return Number(BigInt.asUintN(8, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_i1(v) { return Number(BigInt.asUintN(1, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_ptr(v) { return __sa_addr(__sa_cvt_fptosi_i64(v)); }
        \\function __sa_cvt_fptrunc_f32(v) { return Math.fround(+v); }
        \\function __sa_cvt_fpext_f64(v) { return (+v); }
        \\const __sa_bc_dv = new DataView(new ArrayBuffer(8));
        \\function __sa_cvt_bitcast_i8(v) { return (typeof v === "bigint") ? Number(BigInt.asIntN(8, v)) : ((v << 24) >> 24); }
        \\function __sa_cvt_bitcast_u8(v) { return (typeof v === "bigint") ? Number(BigInt.asUintN(8, v)) : (v & 0xFF); }
        \\function __sa_cvt_bitcast_i16(v) { return (typeof v === "bigint") ? Number(BigInt.asIntN(16, v)) : ((v << 16) >> 16); }
        \\function __sa_cvt_bitcast_u16(v) { return (typeof v === "bigint") ? Number(BigInt.asUintN(16, v)) : (v & 0xFFFF); }
        \\function __sa_cvt_bitcast_i1(v) { return (typeof v === "bigint") ? Number(BigInt.asUintN(1, v)) : (v & 1); }
        \\function __sa_cvt_bitcast_i32(v) {
        \\  // Non-integer Numbers are f32-domain values (f64 sources are
        \\  // rejected by the verifier for 32-bit bitcasts); reinterpret them.
        \\  if (typeof v === "bigint") return Number(BigInt.asIntN(32, v));
        \\  if (!Number.isInteger(v)) { __sa_bc_dv.setFloat32(0, v, true); return __sa_bc_dv.getInt32(0, true); }
        \\  return (v | 0);
        \\}
        \\function __sa_cvt_bitcast_u32(v) {
        \\  if (typeof v === "bigint") return Number(BigInt.asUintN(32, v));
        \\  if (!Number.isInteger(v)) { __sa_bc_dv.setFloat32(0, v, true); return __sa_bc_dv.getUint32(0, true); }
        \\  return (v >>> 0);
        \\}
        \\function __sa_cvt_bitcast_i64(v) {
        \\  // Non-integer Numbers are f64-domain values; reinterpret them.
        \\  // Integer Numbers are immediates (f64-integral bitcasts are a
        \\  // known edge; use sitofp-produced values only via fptosi).
        \\  if (typeof v === "bigint") return BigInt.asIntN(64, v);
        \\  if (!Number.isInteger(v)) { __sa_bc_dv.setFloat64(0, v, true); return __sa_bc_dv.getBigInt64(0, true); }
        \\  return BigInt(v);
        \\}
        \\function __sa_cvt_bitcast_u64(v) {
        \\  if (typeof v === "bigint") return BigInt.asUintN(64, v);
        \\  if (!Number.isInteger(v)) { __sa_bc_dv.setFloat64(0, v, true); return BigInt.asUintN(64, __sa_bc_dv.getBigInt64(0, true)); }
        \\  return BigInt(v);
        \\}
        \\function __sa_cvt_bitcast_ptr(v) {
        \\  // Pointers carry full 64-bit patterns in every backend (only
        \\  // real heap bases are 32-bit); narrowing here would break
        \\  // bitcast roundtrips of high-bit patterns.
        \\  if (typeof v === "bigint") return BigInt.asUintN(64, v);
        \\  return v;
        \\}
        \\function __sa_cvt_ptr64(v) {
        \\  // 64-bit-preserving pointer conversion (trunc/zext/sext to ptr):
        \\  // same as bitcast_ptr, factored for the int-conversion family.
        \\  if (typeof v === "bigint") return BigInt.asUintN(64, v);
        \\  return v;
        \\}
        \\function __sa_cvt_bitcast_f32(v) {
        \\  // BigInt/integer inputs are int-domain bits; fractional inputs are
        \\  // already f32-domain values (f32-to-f32 is identity).
        \\  if (typeof v === "bigint") { __sa_bc_dv.setUint32(0, Number(BigInt.asUintN(32, v)), true); return __sa_bc_dv.getFloat32(0, true); }
        \\  if (!Number.isInteger(v)) return (+v);
        \\  __sa_bc_dv.setInt32(0, v | 0, true); return __sa_bc_dv.getFloat32(0, true);
        \\}
        \\function __sa_cvt_bitcast_f64(v) {
        \\  // Number inputs are always f64-domain here (equal-bits rule keeps
        \\  // int-domain f64 bitcasts on the BigInt path).
        \\  if (typeof v === "bigint") { __sa_bc_dv.setBigInt64(0, BigInt.asIntN(64, v), true); return __sa_bc_dv.getFloat64(0, true); }
        \\  return (+v);
        \\}
        \\function __sa_srcmask(v, w, signed) {
        \\  // Restrict a value to a known source width (statically tracked by
        \\  // the emitter for load-defined slots) before zext/sext, so
        \\  // sub-32-bit sources (e.g. i8 0xFF) extend from the right bits
        \\  // instead of the 32-bit value-inference default.
        \\  if (typeof v === "bigint") return signed ? BigInt.asIntN(w, v) : BigInt.asUintN(w, v);
        \\  if (w >= 64) return v;
        \\  if (w === 32) return signed ? (v | 0) : (v >>> 0);
        \\  if (w === 1) return (v & 1);
        \\  const s = 32 - w;
        \\  return signed ? ((v << s) >> s) : (((v << s) >>> s));
        \\}
;
