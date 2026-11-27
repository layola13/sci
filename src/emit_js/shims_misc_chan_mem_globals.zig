const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_msum_u32")) {
        try writer.writeAll(
            \\function sa_msum_u32(ptr, len) {
            \\  const a = __sa_addr(ptr), n = __sa_num(len);
            \\  if ((a & 3) === 0) {
            \\  const w = __sa_tu32, o = a >> 2, e = o + (n >> 2);
            \\  let s = 0;
            \\  for (let i = o; i < e; i++) s += w[i];
            \\  return s > 4294967295 ? BigInt(s) : s;
            \\  }
            \\  const u = __sa_u8;
            \\  let s = 0;
            \\  for (let i = 0; i < n; i += 4) s += (((u[a + i] | (u[a + i + 1] << 8)) | (u[a + i + 2] << 16)) | (u[a + i + 3] << 24)) >>> 0;
            \\  return s;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_msum_u8")) {
        try writer.writeAll(
            \\function sa_msum_u8(ptr, len) {
            \\  const a = __sa_addr(ptr), n = __sa_num(len), u8 = __sa_u8;
            \\  let s = 0, i = 0;
            \\  const h = Math.min(n, (4 - (a & 3)) & 3);
            \\  for (; i < h; i++) s += u8[a + i];
            \\  const w = new Uint32Array(__sa_memory, a + i, ((n - i) >> 2));
            \\  for (let j = 0; j < w.length; j++) { const v = w[j]; s += (v & 255) + ((v >> 8) & 255) + ((v >> 16) & 255) + (v >>> 24); }
            \\  i += w.length << 2;
            \\  for (; i < n; i++) s += u8[a + i];
            \\  return s;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_data")) {
        try writer.writeAll(
            \\function sa_fs_read_buffer_data(buffer) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const b = __sa_buf_get(buffer);
            \\  if (b === null) return 0;
            \\  const p = __sa_alloc(b.length);
            \\  __sa_u8.set(b, p);
            \\  return p;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_free")) {
        try writer.writeAll(
            \\function sa_fs_read_buffer_free(buffer) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return __sa_buffers.delete(__sa_num(buffer)) ? 0 : 2;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_len")) {
        try writer.writeAll(
            \\function sa_fs_read_buffer_len(buffer) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const b = __sa_buf_get(buffer);
            \\  return b === null ? 0n : BigInt(b.length);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_chan_cap")) {
        try writer.writeAll("function sa_chan_cap(handle, out_cap) { return __sa_task.chanCap(handle, out_cap); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_chan_close")) {
        try writer.writeAll("function sa_chan_close(handle) { return __sa_task.chanClose(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_chan_destroy")) {
        try writer.writeAll("function sa_chan_destroy(handle) { return __sa_task.chanDestroy(handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_chan_len")) {
        try writer.writeAll("function sa_chan_len(handle, out_len) { return __sa_task.chanLen(handle, out_len); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_chan_make")) {
        try writer.writeAll("function sa_chan_make(capacity, out_handle) { return __sa_task.chanMake(capacity, out_handle); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_chan_recv")) {
        try writer.writeAll("function sa_chan_recv(handle, out_value, out_closed) { return __sa_task.chanRecv(handle, out_value, out_closed); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_chan_select")) {
        try writer.writeAll("function sa_chan_select(cases, ops, slots, count, has_default, timeout_ns, out_index, out_closed) { return __sa_task.chanSelect(cases, ops, slots, count, has_default, timeout_ns, out_index, out_closed); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_chan_send")) {
        try writer.writeAll("function sa_chan_send(handle, value) { return __sa_task.chanSend(handle, value); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "pthread_drop")) {
        try writer.writeAll("function pthread_drop(handle) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "pthread_join")) {
        // Entry already ran inside pthread_spawn; nothing to wait for.
        try writer.writeAll("function pthread_join(handle, out) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "pthread_spawn")) {
        // Single-threaded: run the entry synchronously via the fn table,
        // then hand out a joinable handle.
        try writer.writeAll(
            \\function pthread_spawn(entry, arg) {
            \\  const i = __sa_fnval(entry);
            \\  if (i >= 0) __sa_ftable[i](arg);
            \\  globalThis.__sa_next_thr = (globalThis.__sa_next_thr || 1);
            \\  return globalThis.__sa_next_thr++;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_pthread_join")) {
        // Entry already ran inside pthread_spawn; nothing to wait for.
        try writer.writeAll("function sa_pthread_join(handle, out) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_esc_html")) {
        try writer.writeAll(
            \\function sa_esc_html(in_ptr, in_len, out_ptr) {
            \\  const a = __sa_addr(in_ptr), n = __sa_num(in_len), o = __sa_addr(out_ptr), u = __sa_u8;
            \\  let T = sa_esc_html.T;
            \\  if (!T) {
            \\    const L = new Uint8Array(256).fill(1), S = new Uint8Array(1536);
            \\    const put = (c, s) => { L[c] = s.length; for (let k = 0; k < s.length; k++) S[c * 6 + k] = s.charCodeAt(k); };
            \\    put(60, "&lt;"); put(62, "&gt;"); put(38, "&amp;"); put(34, "&quot;"); put(39, "&#39;");
            \\    T = sa_esc_html.T = [L, S];
            \\  }
            \\  const L = T[0], S = T[1];
            \\  let w = o;
            \\  for (let i = 0; i < n; i++) {
            \\    const c = u[a + i], l = L[c];
            \\    if (l === 1) { u[w++] = c; continue; }
            \\    const t = c * 6;
            \\    u[w] = S[t]; u[w + 1] = S[t + 1]; u[w + 2] = S[t + 2]; u[w + 3] = S[t + 3];
            \\    if (l > 4) { u[w + 4] = S[t + 4]; if (l > 5) u[w + 5] = S[t + 5]; }
            \\    w += l;
            \\  }
            \\  return w - o;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_js_callback_poll")) {
        try writer.writeAll(
            \\function sa_js_callback_poll(fn_out, argc_out, args_out) {
            \\  return BigInt(__sa_jsh_cb_poll(fn_out, argc_out, args_out));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_js_make_callback")) {
        try writer.writeAll(
            \\function sa_js_make_callback(fn) {
            \\  return __sa_jsh_make_callback(fn);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_js_value_release")) {
        try writer.writeAll(
            \\function sa_js_value_release(handle) {
            \\  return __sa_jsh_release(handle);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_global_bytes_get")) {
        try writer.writeAll("function sa_global_bytes_get(name, name_len, buf, cap, out_len) { return __sa_globals.bytesGet(name, name_len, buf, cap, out_len); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_global_bytes_set")) {
        try writer.writeAll("function sa_global_bytes_set(name, name_len, value, value_len) { return __sa_globals.bytesSet(name, name_len, value, value_len); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_global_u64_add")) {
        try writer.writeAll("function sa_global_u64_add(name, name_len, delta, out) { return __sa_globals.u64Add(name, name_len, delta, out); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_global_u64_get")) {
        try writer.writeAll("function sa_global_u64_get(name, name_len, out) { return __sa_globals.u64Get(name, name_len, out); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_global_u64_set")) {
        try writer.writeAll("function sa_global_u64_set(name, name_len, value) { return __sa_globals.u64Set(name, name_len, value); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_global_u64_set_once")) {
        try writer.writeAll("function sa_global_u64_set_once(name, name_len, value, out_already) { return __sa_globals.u64SetOnce(name, name_len, value, out_already); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_modstate_get_u64")) {
        try writer.writeAll(
            \\function sa_modstate_get_u64(key) {
            \\  const v = __sa_modstate.get(__sa_tou(key));
            \\  return (v === undefined) ? 0n : BigInt.asUintN(64, v);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_modstate_set_u64")) {
        try writer.writeAll(
            \\function sa_modstate_set_u64(key, value) {
            \\  __sa_modstate.set(__sa_tou(key), BigInt.asUintN(64, BigInt(__sa_num(value))));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_unicode_normalize")) {
        try writer.writeAll(
            \\function sa_unicode_normalize(text, text_len, form, out, out_cap) {
            \\  const bytes = __sa_mem_bytes(text, text_len);
            \\  const s = new globalThis.TextDecoder().decode(bytes);
            \\  const forms = ["NFC", "NFD", "NFKC", "NFKD"];
            \\  const f = __sa_num(form);
            \\  if (f < 0 || f > 3) throw new globalThis.RangeError("Invalid normalization form");
            \\  const norm = s.normalize(forms[f]);
            \\  const enc = new globalThis.TextEncoder().encode(norm);
            \\  if (__sa_num(out_cap) === 0) return BigInt(enc.length);
            \\  if (enc.length > __sa_num(out_cap)) return BigInt(enc.length);
            \\  __sa_u8.set(enc, __sa_addr(out));
            \\  return BigInt(enc.length);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "fd_close")) {
        try writer.writeAll("function fd_close(fd) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "fd_open")) {
        try writer.writeAll(
            \\function fd_open(path) {
            \\  globalThis.__sa_next_fd = (globalThis.__sa_next_fd || 3);
            \\  return globalThis.__sa_next_fd++;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "fd_read")) {
        // Staged simulation: matches the rosetta oracle (read yields 3).
        try writer.writeAll("function fd_read(fd) { return 3; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_print_bytes")) {
        try writer.writeAll(
            \\function sa_print_bytes(ptr, len) {
            \\  const a = __sa_addr(ptr), n = __sa_num(len);
            \\  const s = new globalThis.TextDecoder().decode(__sa_u8.slice(a, a + n));
            \\  if (typeof globalThis.process !== "undefined" && globalThis.process.stdout) { globalThis.process.stdout.write(s); }
            \\  else { globalThis.console.log(s); }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_b64dec")) {
        try writer.writeAll(
            \\function sa_b64dec(in_ptr, in_len, out_ptr) {
            \\  if (!__sa_buf) __sa_trap("no host Buffer for base64");
            \\  const a = __sa_addr(in_ptr), n = __sa_num(in_len), o = __sa_addr(out_ptr);
            \\  const w = __sa_buf.write(__sa_buf.toString("latin1", a, a + n), o, "base64");
            \\  if (w * 4 < n - 4) __sa_trap("base64 decode short output");
            \\  return w;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_hexdec")) {
        try writer.writeAll(
            \\function sa_hexdec(in_ptr, in_len, out_ptr) {
            \\  if (!__sa_buf) __sa_trap("no host Buffer for hex");
            \\  const a = __sa_addr(in_ptr), n = __sa_num(in_len), o = __sa_addr(out_ptr);
            \\  const w = __sa_buf.write(__sa_buf.toString("latin1", a, a + n), o, "hex");
            \\  if ((w << 1) < (n & ~1)) __sa_trap("hex decode short output");
            \\  return w;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_mfill")) {
        try writer.writeAll(
    \\function sa_mfill(ptr, len, byte) {
    \\  const a = __sa_addr(ptr), n = __sa_num(len), b = __sa_num(byte) & 255;
    \\  if (__sa_buf) __sa_buf.fill(b, a, a + n);
    \\  else __sa_u8.subarray(a, a + n).fill(b);
    \\  return 0;
    \\}
    \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_mcopy")) {
        try writer.writeAll(
            \\function sa_mcopy(dst, src, len) {
            \\  const d = __sa_addr(dst), s = __sa_addr(src), n = __sa_num(len);
            \\  if (__sa_buf) __sa_buf.copy(__sa_buf, d, s, s + n);
            \\  else __sa_u8.copyWithin(d, s, s + n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_mem_free")) {
        // Native sa_mem_free releases blocks handed out by the SA
        // `alloc` path (raw free for alloc blocks; Vec buffer
        // regrowth/free, GrowVec handles and StringBuf drop all route
        // through it). On JS, `alloc` lowers to __sa_alloc, so
        // __sa_free is the exact counterpart, including its discipline
        // of silently ignoring null/foreign/interior pointers. Without
        // this branch every Vec regrow/free trapped at run time with
        // "extern not linked: sa_mem_free".
        try writer.writeAll("function sa_mem_free(ptr) { return __sa_free(ptr); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "realloc")) {
        // C realloc over the JS heap (__sa_alloc): grow the block, copy
        // the live range, free the old block. sa_mem_realloc (sa_std)
        // calls this on every Vec/StringBuf/GrowVec regrow; without it
        // the call trapped at run time with "extern not linked: realloc".
        try writer.writeAll("function realloc(ptr, size) { return __sa_realloc(ptr, size); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_coop_finish")) {
        try writer.writeAll("function sa_coop_finish() { return __sa_task.coopFinish(); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_coop_run_main")) {
        try writer.writeAll("function sa_coop_run_main(entry, arg) { return __sa_task.coopRunMain(entry, arg); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_coop_take_result")) {
        try writer.writeAll("function sa_coop_take_result(out_status) { return __sa_task.coopTakeResult(out_status); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sqlite3_finalize")) {
        try writer.writeAll("function sqlite3_finalize(stmt) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sqlite3_prepare")) {
        try writer.writeAll("function sqlite3_prepare(sqlite, sql, len, stmt_out) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sqlite3_step")) {
        try writer.writeAll("function sqlite3_step(stmt) { return 100; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_mwrite_u8")) {
        try writer.writeAll(
            \\function sa_mwrite_u8(ptr, len) {
            \\  const a = __sa_addr(ptr), n = __sa_num(len), w = __sa_u8.subarray(a, a + n);
            \\  for (let i = 0; i < n; i++) w[i] = i & 255;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_host_is_bun")) {
        try writer.writeAll(
            \\function sa_host_is_bun() {
            \\  return typeof Bun !== "undefined" ? 1 : 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "munmap")) {
        // mmap above hands out __sa_alloc blocks, so munmap releases
        // them; __sa_free no-ops on pointers it does not own, so
        // foreign ranges stay safe. This used to be a bare no-op,
        // which leaked the whole mapping (a default GrowVec reserves
        // 8 MiB of the 16 MiB heap) on every free.
        try writer.writeAll("function munmap(map, len) { __sa_free(map); return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "mmap")) {
        // Zero-filled bump allocation stands in for an anonymous mapping.
        try writer.writeAll("function mmap(fd, len) { return __sa_alloc(__sa_num(len)); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "signal")) {
        // Echo the signal number back (staged oracle semantics).
        try writer.writeAll("function signal(sig, handler) { return __sa_num(sig); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dlopen")) {
        try writer.writeAll("function dlopen(path, flags) { return __sa_alloc(8); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dlsym")) {
        try writer.writeAll("function dlsym(handle, symbol) { return __sa_alloc(8); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dlclose")) {
        try writer.writeAll("function dlclose(handle) { return 0; }\n");
        return true;
    }
    return false;
}
