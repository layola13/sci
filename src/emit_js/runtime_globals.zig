// JS runtime chunk (moved from src/emit_js.zig).
// Pure data: the emitted JS source text for one runtime piece.
pub const globals_runtime_js =
    \\// ---- sa global cells runtime (JS port of sa_globals.zig) ----
    \\const __sa_globals = (() => {
    \\  const u64_cells = new Map();
    \\  const bytes_cells = new Map();
    \\  function key(name, name_len) {
    \\    const a = __sa_addr(name), n = __sa_num(name_len);
    \\    if (a === 0 || n === 0 || n > 1024) return null;
    \\    let k = "";
    \\    for (let i = 0; i < n; i++) k += String.fromCharCode(__sa_u8[a + i]);
    \\    return k;
    \\  }
    \\  function u64Set(name, name_len, value) {
    \\    const k = key(name, name_len); if (k === null) return 1;
    \\    u64_cells.set(k, BigInt.asUintN(64, BigInt(value)));
    \\    return 0;
    \\  }
    \\  function u64Get(name, name_len, out) {
    \\    if (__sa_addr(out) === 0) return 1;
    \\    __sa_store_i64(out, 0n);
    \\    const k = key(name, name_len); if (k === null) return 1;
    \\    if (!u64_cells.has(k)) return 3;
    \\    __sa_store_i64(out, u64_cells.get(k));
    \\    return 0;
    \\  }
    \\  function u64SetOnce(name, name_len, value, out_already) {
    \\    if (__sa_addr(out_already) === 0) return 1;
    \\    __sa_store_i64(out_already, 0n);
    \\    const k = key(name, name_len); if (k === null) return 1;
    \\    if (u64_cells.has(k)) { __sa_store_i64(out_already, 1n); return 0; }
    \\    u64_cells.set(k, BigInt.asUintN(64, BigInt(value)));
    \\    return 0;
    \\  }
    \\  function u64Add(name, name_len, delta, out) {
    \\    if (__sa_addr(out) === 0) return 1;
    \\    __sa_store_i64(out, 0n);
    \\    const k = key(name, name_len); if (k === null) return 1;
    \\    const cur = u64_cells.has(k) ? u64_cells.get(k) : 0n;
    \\    const next = BigInt.asUintN(64, cur + BigInt.asIntN(64, BigInt(delta)));
    \\    u64_cells.set(k, next);
    \\    __sa_store_i64(out, next);
    \\    return 0;
    \\  }
    \\  function bytesSet(name, name_len, value, value_len) {
    \\    const k = key(name, name_len); if (k === null) return 1;
    \\    const n = __sa_num(value_len);
    \\    if (n > 0 && __sa_addr(value) === 0) return 1;
    \\    const a = __sa_addr(value);
    \\    bytes_cells.set(k, __sa_u8.slice(a, a + n));
    \\    return 0;
    \\  }
    \\  function bytesGet(name, name_len, buf, cap, out_len) {
    \\    if (__sa_addr(out_len) === 0) return 1;
    \\    __sa_store_i64(out_len, 0n);
    \\    const k = key(name, name_len); if (k === null) return 1;
    \\    if (!bytes_cells.has(k)) return 3;
    \\    const v = bytes_cells.get(k);
    \\    __sa_store_i64(out_len, BigInt(v.length));
    \\    if (v.length > __sa_num(cap)) return 9;
    \\    if (v.length > 0) {
    \\      if (__sa_addr(buf) === 0) return 1;
    \\      __sa_u8.set(v, __sa_addr(buf));
    \\    }
    \\    return 0;
    \\  }
    \\  return { u64Set: u64Set, u64Get: u64Get, u64SetOnce: u64SetOnce, u64Add: u64Add, bytesSet: bytesSet, bytesGet: bytesGet };
    \\})();
;
