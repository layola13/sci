const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_http_client_resp_read_chunk")) {
        try writer.writeAll(
            \\function sa_http_client_resp_read_chunk(reader, buf, cap, out_len) {
            \\  const r = globalThis.__sa_http_rd[__sa_addr(reader)];
            \\  if (!r) return 1;
            \\  const n = Math.min(__sa_num(cap), r.body.length - r.off);
            \\  __sa_u8.set(r.body.subarray(r.off, r.off + n), __sa_addr(buf));
            \\  r.off += n;
            \\  __sa_store_i64(out_len, n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_resp_status")) {
        try writer.writeAll(
            \\function sa_http_client_resp_status(resp) {
            \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
            \\  return r ? r.status : 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_sse_free")) {
        try writer.writeAll(
            \\function sa_http_client_sse_free(handle) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  delete globalThis.__sa_http_sse[__sa_addr(handle)];
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_sse_poll")) {
        try writer.writeAll(
            \\function sa_http_client_sse_poll(handle, out_done) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const rec = globalThis.__sa_http_sse[__sa_addr(handle)];
            \\  if (!rec) return 2;
            \\  __sa_store_i64(out_done, BigInt(rec.off >= rec.body.length ? 1 : 0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_sse_post")) {
        try writer.writeAll(
            \\function sa_http_client_sse_post(url, url_len, body, body_len, key, key_len, out_handle) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const a = __sa_addr(body), n = __sa_num(body_len);
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_sse[__sa_addr(h)] = { body: __sa_u8.slice(a, a + n), off: 0, status: 200 };
            \\  __sa_store_ptr(out_handle, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_sse_read")) {
        try writer.writeAll(
            \\function sa_http_client_sse_read(handle, buf, buf_cap, out_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const rec = globalThis.__sa_http_sse[__sa_addr(handle)];
            \\  if (!rec) return 2;
            \\  const cap = __sa_num(buf_cap);
            \\  const n = Math.min(cap, rec.body.length - rec.off);
            \\  __sa_u8.set(rec.body.subarray(rec.off, rec.off + n), __sa_addr(buf));
            \\  rec.off += n;
            \\  __sa_store_i64(out_len, BigInt(n));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_sse_status")) {
        try writer.writeAll(
            \\function sa_http_client_sse_status(handle) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const rec = globalThis.__sa_http_sse[__sa_addr(handle)];
            \\  return rec ? rec.status : 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_sse_turn")) {
        try writer.writeAll(
            \\function sa_http_client_sse_turn(url, url_len, body, body_len, key, key_len, api_mode, out_text, out_text_len, out_calls, out_calls_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const a = __sa_addr(body), n = __sa_num(body_len);
            \\  const text = __sa_u8.slice(a, a + n);
            \\  const tp = __sa_alloc(text.length);
            \\  __sa_u8.set(text, tp);
            \\  const cp = __sa_alloc(1);
            \\  __sa_store_ptr(out_text, tp);
            \\  __sa_store_i64(out_text_len, BigInt(text.length));
            \\  __sa_store_ptr(out_calls, cp);
            \\  __sa_store_i64(out_calls_len, BigInt(0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_sse_turn_free")) {
        try writer.writeAll("function sa_http_client_sse_turn_free(buf, len) { }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_websocket_connect")) {
        try writer.writeAll(
            \\function sa_http_client_websocket_connect(client, url, url_len, out_ws) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_ws[__sa_addr(h)] = { queue: [], stream: new Uint8Array(0), closed: false };
            \\  __sa_store_ptr(out_ws, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_websocket_connect_unix_v2")) {
        try writer.writeAll(
            \\function sa_http_client_websocket_connect_unix_v2(client, socket_path, socket_path_len, url, url_len, timeout_ms, out_ws) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_ws[__sa_addr(h)] = { queue: [], stream: new Uint8Array(0), off: 0, closed: false };
            \\  __sa_store_ptr(out_ws, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_websocket_connect_v2")) {
        try writer.writeAll(
            \\function sa_http_client_websocket_connect_v2(client, url, url_len, timeout_ms, out_ws) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_ws[__sa_addr(h)] = { queue: [], stream: new Uint8Array(0), off: 0, closed: false };
            \\  __sa_store_ptr(out_ws, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_accept")) {
        try writer.writeAll(
            \\function sa_http_server_accept(server, out_req) {
            \\  if (!globalThis.__sa_https[__sa_addr(server)]) return 1;
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_sreq[__sa_addr(h)] = {
            \\    path: new globalThis.TextEncoder().encode("/stream"),
            \\    hdr_val: new globalThis.TextEncoder().encode("text/plain"),
            \\    body: new Uint8Array(0),
            \\  };
            \\  __sa_store_ptr(out_req, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_free")) {
        try writer.writeAll("function sa_http_server_free(server) { delete globalThis.__sa_https[__sa_addr(server)]; return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_new")) {
        try writer.writeAll(
            \\function sa_http_server_new(out_server) {
            \\  globalThis.__sa_https = (globalThis.__sa_https || {});
            \\  globalThis.__sa_http_sreq = (globalThis.__sa_http_sreq || {});
            \\  globalThis.__sa_http_sresp = (globalThis.__sa_http_sresp || {});
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_https[__sa_addr(h)] = {};
            \\  __sa_store_ptr(out_server, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_req_free")) {
        try writer.writeAll("function sa_http_server_req_free(req) { delete globalThis.__sa_http_sreq[__sa_addr(req)]; return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_req_get_body")) {
        try writer.writeAll(
            \\function sa_http_server_req_get_body(req, out_body, out_len) {
            \\  const r = globalThis.__sa_http_sreq[__sa_addr(req)];
            \\  if (!r) return 1;
            \\  __sa_store_ptr(out_body, 0);
            \\  __sa_store_i64(out_len, 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_req_get_header")) {
        try writer.writeAll(
            \\function sa_http_server_req_get_header(req, key, key_len, out_val, out_len) {
            \\  const r = globalThis.__sa_http_sreq[__sa_addr(req)];
            \\  if (!r) return 1;
            \\  const p = __sa_alloc(r.hdr_val.length);
            \\  __sa_u8.set(r.hdr_val, p);
            \\  __sa_store_ptr(out_val, p);
            \\  __sa_store_i64(out_len, r.hdr_val.length);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_req_get_path")) {
        try writer.writeAll(
            \\function sa_http_server_req_get_path(req, out_path, out_len) {
            \\  const r = globalThis.__sa_http_sreq[__sa_addr(req)];
            \\  if (!r) return 1;
            \\  const p = __sa_alloc(r.path.length);
            \\  __sa_u8.set(r.path, p);
            \\  __sa_store_ptr(out_path, p);
            \\  __sa_store_i64(out_len, r.path.length);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_end")) {
        try writer.writeAll(
            \\function sa_http_server_resp_stream_end(resp) {
            \\  return globalThis.__sa_http_sresp[__sa_addr(resp)] ? 0 : 1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_flush")) {
        try writer.writeAll(
            \\function sa_http_server_resp_stream_flush(resp) {
            \\  return globalThis.__sa_http_sresp[__sa_addr(resp)] ? 0 : 1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_free")) {
        try writer.writeAll("function sa_http_server_resp_stream_free(resp) { delete globalThis.__sa_http_sresp[__sa_addr(resp)]; return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_new")) {
        try writer.writeAll(
            \\function sa_http_server_resp_stream_new(req, status, out_resp) {
            \\  if (!globalThis.__sa_http_sreq[__sa_addr(req)]) return 1;
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_sresp[__sa_addr(h)] = { status: __sa_num(status), chunks: [] };
            \\  __sa_store_ptr(out_resp, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_write")) {
        try writer.writeAll(
            \\function sa_http_server_resp_stream_write(resp, body, body_len) {
            \\  const r = globalThis.__sa_http_sresp[__sa_addr(resp)];
            \\  if (!r) return 1;
            \\  const a = __sa_addr(body), n = __sa_num(body_len);
            \\  r.chunks.push(__sa_u8.slice(a, a + n));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_server_start")) {
        try writer.writeAll(
            \\function sa_http_server_start(server, host, host_len, port) {
            \\  const s = globalThis.__sa_https[__sa_addr(server)];
            \\  if (!s) return 1;
            \\  const a = __sa_addr(host), n = __sa_num(host_len);
            \\  s.host = new globalThis.TextDecoder().decode(__sa_u8.slice(a, a + n));
            \\  s.port = __sa_num(port);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_websocket_close_v2")) {
        try writer.writeAll(
            \\function sa_http_websocket_close_v2(ws, code, reason, reason_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
            \\  if (!w) return 5;
            \\  w.closed = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_websocket_free")) {
        try writer.writeAll(
            \\function sa_http_websocket_free(ws) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  delete globalThis.__sa_http_ws[__sa_addr(ws)];
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_websocket_free_v2")) {
        try writer.writeAll(
            \\function sa_http_websocket_free_v2(ws) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  delete globalThis.__sa_http_ws[__sa_addr(ws)];
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_websocket_poll_v2")) {
        try writer.writeAll(
            \\function sa_http_websocket_poll_v2(ws, interests, timeout_ms, out_events) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
            \\  if (!w) return 5;
            \\  let ev = 2;
            \\  if (w.off < w.stream.length || w.queue.length) ev |= 1;
            \\  if (w.closed) ev |= 4;
            \\  __sa_store_i64(out_events, BigInt(ev));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_websocket_read")) {
        try writer.writeAll(
            \\function sa_http_websocket_read(ws, max_len, out_opcode, out_ptr, out_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
            \\  if (!w) return 2;
            \\  const msg = w.queue.shift();
            \\  if (!msg) { __sa_store_i64(out_len, BigInt(0)); return 2; }
            \\  const p = __sa_alloc(msg.bytes.length);
            \\  __sa_u8.set(msg.bytes, p);
            \\  __sa_store_i64(out_opcode, BigInt(msg.opcode));
            \\  __sa_store_ptr(out_ptr, p);
            \\  __sa_store_i64(out_len, BigInt(msg.bytes.length));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_websocket_read_v2")) {
        try writer.writeAll(
            \\function sa_http_websocket_read_v2(ws, max_len, out_opcode, out_ptr, out_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
            \\  if (!w) return 5;
            \\  const avail = w.stream.length - w.off;
            \\  if (avail <= 0) { __sa_store_i64(out_len, BigInt(0)); return w.closed ? 2 : 1; }
            \\  const n = Math.min(avail, __sa_num(max_len));
            \\  const chunk = w.stream.slice(w.off, w.off + n);
            \\  w.off += n;
            \\  if (!w.read_addr || w.read_cap < chunk.length) { w.read_addr = __sa_alloc(chunk.length); w.read_cap = chunk.length; }
            \\  __sa_u8.set(chunk, w.read_addr);
            \\  __sa_store_i64(out_opcode, BigInt(2));
            \\  __sa_store_ptr(out_ptr, w.read_addr);
            \\  __sa_store_i64(out_len, BigInt(n));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_websocket_write")) {
        try writer.writeAll(
            \\function sa_http_websocket_write(ws, opcode, data, data_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
            \\  if (!w) return 2;
            \\  const a = __sa_addr(data), n = __sa_num(data_len);
            \\  w.queue.push({ opcode: __sa_num(opcode), bytes: __sa_u8.slice(a, a + n) });
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_websocket_write_v2")) {
        try writer.writeAll(
            \\function sa_http_websocket_write_v2(ws, opcode, data, data_len, out_written) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
            \\  if (!w) return 5;
            \\  const a = __sa_addr(data), n = __sa_num(data_len);
            \\  const chunk = __sa_u8.slice(a, a + n);
            \\  const merged = new Uint8Array(w.stream.length + chunk.length);
            \\  merged.set(w.stream, 0);
            \\  merged.set(chunk, w.stream.length);
            \\  w.stream = merged;
            \\  __sa_store_i64(out_written, BigInt(n));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    return false;
}
