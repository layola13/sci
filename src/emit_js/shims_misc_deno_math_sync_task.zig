const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_str_eq_ignore_ascii_case")) {
        try writer.writeAll(
            \\function sa_str_eq_ignore_ascii_case(left_ptr, left_len, right_ptr, right_len) {
            \\  const l = __sa_mem_bytes(left_ptr, left_len), r = __sa_mem_bytes(right_ptr, right_len);
            \\  if (l.length !== r.length) return 0;
            \\  const f = (c) => (c >= 65 && c <= 90) ? c + 32 : c;
            \\  for (let i = 0; i < l.length; i++) if (f(l[i]) !== f(r[i])) return 0;
            \\  return 1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_is_ascii")) {
        try writer.writeAll(
            \\function sa_str_is_ascii(ptr, len) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  for (let i = 0; i < b.length; i++) if (b[i] > 0x7f) return 0;
            \\  return 1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_trim_ascii_end_len")) {
        try writer.writeAll(
            \\function sa_str_trim_ascii_end_len(ptr, len) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  let e = b.length;
            \\  while (e > 0 && __sa_is_ws(b[e - 1])) e--;
            \\  return BigInt(e);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_trim_ascii_start_index")) {
        try writer.writeAll(
            \\function sa_str_trim_ascii_start_index(ptr, len) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  let i = 0;
            \\  while (i < b.length && __sa_is_ws(b[i])) i++;
            \\  return BigInt(i);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_utf8_char_at")) {
        try writer.writeAll(
            \\function sa_str_utf8_char_at(ptr, len, char_index, out_codepoint) {
            \\  __sa_store_i64(out_codepoint, 0n);
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  let bi = 0, cur = 0n;
            \\  const want = BigInt.asUintN(64, BigInt(__sa_num(char_index)));
            \\  while (bi < b.length) {
            \\    const d = __sa_utf8_dec(b, bi);
            \\    if (d === null) return 1;
            \\    if (cur === want) { __sa_store_i64(out_codepoint, d[0]); return 0; }
            \\    bi += d[1]; cur++;
            \\  }
            \\  return 3;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_utf8_char_at_byte")) {
        try writer.writeAll(
            \\function sa_str_utf8_char_at_byte(ptr, len, byte_index, out_codepoint, out_len) {
            \\  __sa_store_i64(out_codepoint, 0n);
            \\  __sa_store_i64(out_len, 0n);
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  const idx = __sa_num(byte_index);
            \\  if (idx < 0 || idx >= b.length) return 3;
            \\  const d = __sa_utf8_dec(b, idx);
            \\  if (d === null) return 1;
            \\  __sa_store_i64(out_codepoint, d[0]);
            \\  __sa_store_i64(out_len, d[1]);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_utf8_char_count")) {
        try writer.writeAll(
            \\function sa_str_utf8_char_count(ptr, len) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  let i = 0, n = 0n;
            \\  while (i < b.length) {
            \\    const d = __sa_utf8_dec(b, i);
            \\    if (d === null) return 0n;
            \\    i += d[1]; n++;
            \\  }
            \\  return n;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_utf8_char_range_at")) {
        try writer.writeAll(
            \\function sa_str_utf8_char_range_at(ptr, len, char_index, out_start, out_len) {
            \\  __sa_store_i64(out_start, 0n);
            \\  __sa_store_i64(out_len, 0n);
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  let bi = 0, cur = 0n;
            \\  const want = BigInt.asUintN(64, BigInt(__sa_num(char_index)));
            \\  while (bi < b.length) {
            \\    const d = __sa_utf8_dec(b, bi);
            \\    if (d === null) return 1;
            \\    if (cur === want) { __sa_store_i64(out_start, bi); __sa_store_i64(out_len, d[1]); return 0; }
            \\    bi += d[1]; cur++;
            \\  }
            \\  return 3;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_utf8_lossy_next")) {
        try writer.writeAll(
            \\function sa_str_utf8_lossy_next(ptr, len, byte_index, out_codepoint, out_len) {
            \\  __sa_store_i64(out_codepoint, 0n);
            \\  __sa_store_i64(out_len, 0n);
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  const idx = __sa_num(byte_index);
            \\  if (idx < 0 || idx >= b.length) return 1;
            \\  const d = __sa_utf8_dec(b, idx);
            \\  if (d === null) {
            \\    let w = 1;
            \\    const b0 = b[idx];
            \\    const exp = (b0 >= 0xc2 && b0 <= 0xdf) ? 2 : (b0 >= 0xe0 && b0 <= 0xef) ? 3 : (b0 >= 0xf0 && b0 <= 0xf4) ? 4 : 1;
            \\    while (w < exp && idx + w < b.length) { const c = b[idx + w]; if (c < 0x80 || c > 0xbf) break; w++; }
            \\    __sa_store_i64(out_codepoint, 65533);
            \\    __sa_store_i64(out_len, w);
            \\    return 0;
            \\  }
            \\  __sa_store_i64(out_codepoint, d[0]);
            \\  __sa_store_i64(out_len, d[1]);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_str_utf8_validate")) {
        try writer.writeAll(
            \\function sa_str_utf8_validate(ptr, len) {
            \\  const b = __sa_mem_bytes(ptr, len);
            \\  let i = 0;
            \\  while (i < b.length) {
            \\    const d = __sa_utf8_dec(b, i);
            \\    if (d === null) return 1;
            \\    i += d[1];
            \\  }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_deno_plugin_atob")) {
        try writer.writeAll(
            \\function sa_deno_plugin_atob(data_ptr, data_len, out_ptr, out_len) {
            \\  try {
            \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
            \\    const bin = globalThis.atob(s);
            \\    const out = new Uint8Array(bin.length);
            \\    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) & 0xff;
            \\    return __sa_node_emit(out_ptr, out_len, out);
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_deno_plugin_btoa")) {
        try writer.writeAll(
            \\function sa_deno_plugin_btoa(data_ptr, data_len, out_ptr, out_len) {
            \\  try {
            \\    const b = __sa_mem_bytes(data_ptr, data_len);
            \\    let s = "";
            \\    for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(globalThis.btoa(s)));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_deno_plugin_free_buffer")) {
        try writer.writeAll(
            \\function sa_deno_plugin_free_buffer(ptr, len) { __sa_free(ptr); return 0; }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_deno_plugin_mkdir")) {
        try writer.writeAll(
            \\function sa_deno_plugin_mkdir(path_ptr, path_len, recursive) {
            \\  const fs = __sa_node_builtin("node:fs");
            \\  if (fs === null) return 1;
            \\  try {
            \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    if (!__sa_policy_fs(p, true)) return 10;
            \\    fs.mkdirSync(p, { recursive: __sa_num(recursive) !== 0 });
            \\    return 0;
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_deno_plugin_read_text_file")) {
        try writer.writeAll(
            \\function sa_deno_plugin_read_text_file(path_ptr, path_len, out_ptr, out_len) {
            \\  const fs = __sa_node_builtin("node:fs");
            \\  if (fs === null) return 1;
            \\  try {
            \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    if (!__sa_policy_fs(p, false)) return 10;
            \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(fs.readFileSync(p, "utf8")));
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_deno_plugin_remove")) {
        try writer.writeAll(
            \\function sa_deno_plugin_remove(path_ptr, path_len, recursive) {
            \\  const fs = __sa_node_builtin("node:fs");
            \\  if (fs === null) return 1;
            \\  try {
            \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    if (!__sa_policy_fs(p, true)) return 10;
            \\    if (__sa_num(recursive) !== 0) { fs.rmSync(p, { recursive: true }); return 0; }
            \\    try { fs.unlinkSync(p); return 0; } catch (e) {}
            \\    fs.rmdirSync(p);
            \\    return 0;
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_deno_plugin_write_text_file")) {
        try writer.writeAll(
            \\function sa_deno_plugin_write_text_file(path_ptr, path_len, data_ptr, data_len) {
            \\  const fs = __sa_node_builtin("node:fs");
            \\  if (fs === null) return 1;
            \\  try {
            \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    if (!__sa_policy_fs(p, true)) return 10;
            \\    fs.writeFileSync(p, __sa_mem_bytes(data_ptr, data_len));
            \\    return 0;
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_net_addr_family")) {
        try writer.writeAll(
            \\function sa_net_addr_family(addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!a || a.kind !== "addr") return 0;
            \\  return a.family;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_net_addr_free")) {
        try writer.writeAll(
            \\function sa_net_addr_free(addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return J.netDel(__sa_num(addr)) ? 0 : 2;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_net_addr_host")) {
        try writer.writeAll(
            \\function sa_net_addr_host(addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!a || a.kind !== "addr") return 0;
            \\  const b = J.bFromStr(a.host);
            \\  const p = __sa_alloc(b.length);
            \\  __sa_u8.set(b, p);
            \\  return p;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_net_addr_host_len")) {
        try writer.writeAll(
            \\function sa_net_addr_host_len(addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!a || a.kind !== "addr") return 0n;
            \\  return BigInt(J.bFromStr(a.host).length);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_net_addr_port")) {
        try writer.writeAll(
            \\function sa_net_addr_port(addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!a || a.kind !== "addr") return 0;
            \\  return a.port;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_net_addr_scope_id")) {
        try writer.writeAll(
            \\function sa_net_addr_scope_id(addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!a || a.kind !== "addr") return 0n;
            \\  return BigInt(a.scopeId);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_destroy")) {
        try writer.writeAll("function sa_sync_destroy(handle) { return __sa_task.syncDestroy(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_mutex_lock")) {
        try writer.writeAll("function sa_sync_mutex_lock(handle) { return __sa_task.mutexLock(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_mutex_new")) {
        try writer.writeAll("function sa_sync_mutex_new(out_handle) { return __sa_task.mutexNew(out_handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_mutex_try_lock")) {
        try writer.writeAll("function sa_sync_mutex_try_lock(handle, out_acquired) { return __sa_task.mutexTryLock(handle, out_acquired); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_mutex_unlock")) {
        try writer.writeAll("function sa_sync_mutex_unlock(handle) { return __sa_task.mutexUnlock(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_once_do")) {
        try writer.writeAll("function sa_sync_once_do(handle, entry, arg) { return __sa_task.onceDo(handle, entry, arg); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_once_new")) {
        try writer.writeAll("function sa_sync_once_new(out_handle) { return __sa_task.onceNew(out_handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_rwlock_lock")) {
        try writer.writeAll("function sa_sync_rwlock_lock(handle) { return __sa_task.rwlockLock(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_rwlock_new")) {
        try writer.writeAll("function sa_sync_rwlock_new(out_handle) { return __sa_task.rwlockNew(out_handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_rwlock_rlock")) {
        try writer.writeAll("function sa_sync_rwlock_rlock(handle) { return __sa_task.rwlockRlock(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_rwlock_runlock")) {
        try writer.writeAll("function sa_sync_rwlock_runlock(handle) { return __sa_task.rwlockRunlock(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_rwlock_unlock")) {
        try writer.writeAll("function sa_sync_rwlock_unlock(handle) { return __sa_task.rwlockUnlock(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_waitgroup_add")) {
        try writer.writeAll("function sa_sync_waitgroup_add(handle, delta) { return __sa_task.wgAdd(handle, delta); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_waitgroup_done")) {
        try writer.writeAll("function sa_sync_waitgroup_done(handle) { return __sa_task.wgDone(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_waitgroup_new")) {
        try writer.writeAll("function sa_sync_waitgroup_new(out_handle) { return __sa_task.waitgroupNew(out_handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_sync_waitgroup_wait")) {
        try writer.writeAll("function sa_sync_waitgroup_wait(handle) { return __sa_task.wgWait(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_current")) {
        try writer.writeAll("function sa_task_current(out_handle) { return __sa_task.current_(out_handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_deadlock_guard_arm")) {
        try writer.writeAll("function sa_task_deadlock_guard_arm() { return __sa_task.deadlockGuardArm(); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_detach")) {
        try writer.writeAll("function sa_task_detach(handle) { return __sa_task.detach(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_join")) {
        try writer.writeAll("function sa_task_join(handle) { return __sa_task.join(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_live_count")) {
        try writer.writeAll("function sa_task_live_count(out_count) { return __sa_task.liveCount(out_count); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_monitor")) {
        try writer.writeAll("function sa_task_monitor(handle, out_chan) { return __sa_task.monitor(handle, out_chan); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_net_wait")) {
        try writer.writeAll("function sa_task_net_wait(handle, interest, timeout_ns, out_ready) { return __sa_task.netWait(handle, interest, timeout_ns, out_ready); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_sleep_ms")) {
        try writer.writeAll("function sa_task_sleep_ms(ms) { return __sa_task.sleepMs(ms); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_sleep_ns")) {
        try writer.writeAll("function sa_task_sleep_ns(ns) { return __sa_task.sleepNs(ns); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_spawn")) {
        try writer.writeAll("function sa_task_spawn(entry, arg, out_handle) { return __sa_task.spawn(entry, arg, out_handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_spawn_supervised")) {
        try writer.writeAll("function sa_task_spawn_supervised(entry, arg, sink, sink_ctx, out_handle) { return __sa_task.spawnSupervised(entry, arg, sink, sink_ctx, out_handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_trap_info")) {
        try writer.writeAll("function sa_task_trap_info(handle, out_code, out_msg_ptr, out_msg_len) { return __sa_task.trapInfo(handle, out_code, out_msg_ptr, out_msg_len); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_task_yield")) {
        try writer.writeAll("function sa_task_yield() { return __sa_task.yield_(); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_mfind_u32")) {
        try writer.writeAll(
            \\function sa_mfind_u32(ptr, len, needle) {
            \\  const a = __sa_addr(ptr), n = __sa_num(len), t = __sa_num(needle) >>> 0;
            \\  if ((a & 3) === 0) {
            \\    // NOTE: the subarray is load-bearing, NOT gratuitous:
            \\    // indexOf scans to the END of its receiver, so a direct
            \\    // __sa_tu32.indexOf(t, base) scans megabytes on every
            \\    // miss (measured 425us vs ~1us bounded). Keep bounded.
            \\    const r = __sa_tu32.subarray(a >> 2, (a >> 2) + n).indexOf(t);
            \\    return r < 0 ? n : r;
            \\  }
            \\  const u = __sa_u8;
            \\  const b0 = t & 255, b1 = (t >> 8) & 255, b2 = (t >> 16) & 255, b3 = (t >>> 24) & 255;
            \\  for (let i = 0; i < n; i++) {
            \\    const o = a + (i << 2);
            \\    if (u[o] === b0 && u[o + 1] === b1 && u[o + 2] === b2 && u[o + 3] === b3) return i;
            \\  }
            \\  return n;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_mfind_u8")) {
        try writer.writeAll(
            \\function sa_mfind_u8(hay_ptr, hay_len, ndl_ptr, ndl_len) {
            \\  const h = __sa_addr(hay_ptr), n = __sa_num(hay_len);
            \\  const q = __sa_addr(ndl_ptr), m = __sa_num(ndl_len), u = __sa_u8;
            \\  if (m === 0) return 0;
            \\  if (m > n) return n;
            \\  if (__sa_buf) {
            \\    const r = __sa_buf.indexOf(u.subarray(q, q + m), h);
            \\    if (r < h || r + m > h + n) return n;
            \\    return r - h;
            \\  }
            \\  const b0 = u[q], last = n - m;
            \\  for (let i = 0; i <= last; i++) {
            \\    if (u[h + i] !== b0) continue;
            \\    let k = 1;
            \\    for (; k < m; k++) { if (u[h + i + k] !== u[q + k]) break; }
            \\    if (k === m) return i;
            \\  }
            \\  return n;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_ceil")) {
        try writer.writeAll("function sa_math_ceil(x) { return Math.ceil(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_cos")) {
        try writer.writeAll("function sa_math_cos(x) { return Math.cos(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_floor")) {
        try writer.writeAll("function sa_math_floor(x) { return Math.floor(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_pow")) {
        try writer.writeAll("function sa_math_pow(base, exp) { return Math.pow(base, exp); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_random")) {
        // Native contract: policy-gated crypto draw of 53 bits in
        // [0, 1) — (u >> 11) * 2^-53 over a crypto u64. The JS host
        // crypto source is WebCrypto (Node >= 19, browsers, Deno);
        // a host without one traps loudly instead of silently
        // demoting to Math.random (a non-crypto source).
        try writer.writeAll(
            \\function sa_math_random() {
            \\  if (!__sa_policy_unit('random')) return 0;
            \\  const c = globalThis.crypto;
            \\  if (!c || typeof c.getRandomValues !== "function") __sa_trap("sa_math_random: no crypto source on this host");
            \\  const w = new Uint32Array(2);
            \\  c.getRandomValues(w);
            \\  const u = (BigInt(w[0]) << 32n) | BigInt(w[1]);
            \\  return Number(u >> 11n) * (1.0 / 9007199254740992.0);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_acos")) {
        try writer.writeAll("function sa_math_acos(x) { return Math.acos(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_asin")) {
        try writer.writeAll("function sa_math_asin(x) { return Math.asin(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_atan")) {
        try writer.writeAll("function sa_math_atan(x) { return Math.atan(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_atan2")) {
        try writer.writeAll("function sa_math_atan2(y, x) { return Math.atan2(y, x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_cosh")) {
        try writer.writeAll("function sa_math_cosh(x) { return Math.cosh(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_exp")) {
        try writer.writeAll("function sa_math_exp(x) { return Math.exp(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_expm1")) {
        try writer.writeAll("function sa_math_expm1(x) { return Math.expm1(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_hypot")) {
        try writer.writeAll("function sa_math_hypot(x, y) { return Math.hypot(x, y); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_log")) {
        try writer.writeAll("function sa_math_log(x) { return Math.log(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_log10")) {
        try writer.writeAll("function sa_math_log10(x) { return Math.log10(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_log1p")) {
        try writer.writeAll("function sa_math_log1p(x) { return Math.log1p(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_log2")) {
        try writer.writeAll("function sa_math_log2(x) { return Math.log2(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_sinh")) {
        try writer.writeAll("function sa_math_sinh(x) { return Math.sinh(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_tan")) {
        try writer.writeAll("function sa_math_tan(x) { return Math.tan(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_tanh")) {
        try writer.writeAll("function sa_math_tanh(x) { return Math.tanh(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_sin")) {
        try writer.writeAll("function sa_math_sin(x) { return Math.sin(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_math_sqrt")) {
        try writer.writeAll("function sa_math_sqrt(x) { return Math.sqrt(x); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_parse_float")) {
        try writer.writeAll(
            \\function sa_parse_float(ptr, len) {
            \\  const bytes = __sa_mem_bytes(ptr, len);
            \\  let i = 0;
            \\  while (i < bytes.length && __sa_is_ws(bytes[i])) i++;
            \\  let neg = false;
            \\  if (i < bytes.length && (bytes[i] === 43 || bytes[i] === 45)) { neg = bytes[i] === 45; i++; }
            \\  const rest = bytes.slice(i);
            \\  const rs = (t) => String.fromCharCode.apply(null, t);
            \\  if (rest.length >= 8 && rs(rest.slice(0, 8)) === "Infinity") return neg ? -Infinity : Infinity;
            \\  if (rest.length >= 3 && rs(rest.slice(0, 3)) === "NaN") return NaN;
            \\  let j = 0;
            \\  while (j < rest.length && rest[j] >= 48 && rest[j] <= 57) j++;
            \\  const ints = j;
            \\  if (j < rest.length && rest[j] === 46) {
            \\    j++;
            \\    while (j < rest.length && rest[j] >= 48 && rest[j] <= 57) j++;
            \\  }
            \\  const fracs = j - ints - ((j > ints && rest[ints] === 46) ? 1 : 0);
            \\  if (ints === 0 && fracs === 0) return NaN;
            \\  let k = j;
            \\  if (k < rest.length && (rest[k] === 101 || rest[k] === 69)) {
            \\    let m = k + 1;
            \\    if (m < rest.length && (rest[m] === 43 || rest[m] === 45)) m++;
            \\    const es = m;
            \\    while (m < rest.length && rest[m] >= 48 && rest[m] <= 57) m++;
            \\    if (m > es) k = m;
            \\  }
            \\  const num = parseFloat(rs(rest.slice(0, k)));
            \\  if (Number.isNaN(num)) return NaN;
            \\  if (!Number.isFinite(num)) return neg ? -Infinity : Infinity;
            \\  return neg ? -num : num;
            \\}
            \\
        );
        return true;
    }
    return false;
}
