// JS runtime chunk (moved from src/emit_js.zig).
// Pure data: the emitted JS source text for one runtime piece.
pub const jshandle_runtime_js =
    \\// ---- SA JS value handles (npm ctor/method/get bindings + callbacks) ----
    \\const SA_JS_STR_TOO_LONG = 1;
    \\const __sa_jsh_slots = [];
    \\const __sa_jsh_free = [];
    \\const __sa_jsh_EMPTY = {};
    \\function __sa_jsh_new(v) {
    \\  if (v === undefined) __sa_trap("js handle: cannot register undefined as a handle");
    \\  let idx;
    \\  if (__sa_jsh_free.length) idx = __sa_jsh_free.pop();
    \\  else { idx = __sa_jsh_slots.length; __sa_jsh_slots.push({ v: __sa_jsh_EMPTY, gen: 1 }); }
    \\  __sa_jsh_slots[idx].v = v;
    \\  return BigInt(__sa_jsh_slots[idx].gen * 4294967296 + (idx + 1));
    \\}
    \\function __sa_jsh_decode(h, what) {
    \\  const n = (typeof h === "bigint") ? Number(h) : __sa_num(h);
    \\  if (!Number.isSafeInteger(n) || n <= 0) __sa_trap("js handle: invalid handle (" + what + ")");
    \\  const idx = (n % 4294967296) - 1;
    \\  const gen = Math.floor(n / 4294967296);
    \\  if (idx < 0 || idx >= __sa_jsh_slots.length) __sa_trap("js handle: handle out of range (" + what + ")");
    \\  const slot = __sa_jsh_slots[idx];
    \\  if (slot.v === __sa_jsh_EMPTY || slot.gen !== gen) __sa_trap("js handle: stale or released handle (" + what + ")");
    \\  return idx;
    \\}
    \\function __sa_jsh_get(h) { return __sa_jsh_slots[__sa_jsh_decode(h, "use")].v; }
    \\function __sa_jsh_release(h) {
    \\  const idx = __sa_jsh_decode(h, "release");
    \\  const slot = __sa_jsh_slots[idx];
    \\  slot.v = __sa_jsh_EMPTY;
    \\  slot.gen += 1;
    \\  __sa_jsh_free.push(idx);
    \\  return 0;
    \\}
    \\function __sa_jsh_str_out(v, out_ptr, out_cap, out_len_ptr) {
    \\  if (typeof v !== "string") __sa_trap("npm extern returned non-string for a string out-param binding");
    \\  const bytes = new globalThis.TextEncoder().encode(v);
    \\  __sa_view.setBigUint64(__sa_addr(out_len_ptr), BigInt(bytes.length), true);
    \\  if (bytes.length > __sa_num(out_cap)) return SA_JS_STR_TOO_LONG;
    \\  __sa_u8.set(bytes, __sa_addr(out_ptr));
    \\  return 0;
    \\}
    \\function __sa_jsh_u8view(ptr, len) {
    \\  const a = __sa_addr(ptr), n = __sa_num(len);
    \\  if (!(n >= 0) || a < 0 || a + n > __sa_u8.length) __sa_trap("js bytes view out of bounds");
    \\  return new Uint8Array(__sa_memory, a, n);
    \\}
    \\function __sa_jsh_f32view(ptr, len) {
    \\  const a = __sa_addr(ptr), n = __sa_num(len);
    \\  if (!(n >= 0) || (n % 4) !== 0 || (a % 4) !== 0 || a + n > __sa_u8.length) __sa_trap("js f32 view out of bounds or unaligned");
    \\  return new Float32Array(__sa_memory, a, n / 4);
    \\}
    \\const __sa_jsh_cb_queue = [];
    \\function __sa_jsh_make_callback(fn) {
    \\  const idx = __sa_fnval(fn);
    \\  if (idx < 0) __sa_trap("sa_js_make_callback: argument is not an SA function pointer");
    \\  const closure = (...args) => {
    \\    const nums = [];
    \\    for (const a of args) {
    \\      if (typeof a === "number") nums.push(a);
    \\      else if (typeof a === "bigint") nums.push(Number(a));
    \\      else if (typeof a === "boolean") nums.push(a ? 1 : 0);
    \\      else __sa_trap("js callback: non-numeric argument from JS");
    \\    }
    \\    __sa_jsh_cb_queue.push({ fn: idx, args: nums });
    \\    return undefined;
    \\  };
    \\  return __sa_jsh_new(closure);
    \\}
    \\function __sa_jsh_cb_poll(fn_out, argc_out, args_out) {
    \\  const ev = __sa_jsh_cb_queue.shift();
    \\  if (!ev) return 0;
    \\  __sa_view.setBigUint64(__sa_addr(fn_out), __sa_fnptr(ev.fn), true);
    \\  __sa_view.setBigUint64(__sa_addr(argc_out), BigInt(ev.args.length), true);
    \\  const base = __sa_addr(args_out);
    \\  for (let i = 0; i < ev.args.length; i++) __sa_view.setFloat64(base + i * 8, ev.args[i], true);
    \\  return 1;
    \\}
    \\try {
    \\  const __sa_jsh_p = globalThis.process;
    \\  if (__sa_jsh_p && typeof __sa_jsh_p.on === "function") __sa_jsh_p.on("exit", () => {
    \\    if (__sa_jsh_cb_queue.length) { try { __sa_jsh_p.stderr.write("[sa-js] exit with " + __sa_jsh_cb_queue.length + " undrained callback event(s)\n"); } catch (e) {} }
    \\  });
    \\} catch (e) {}
    \\
;
