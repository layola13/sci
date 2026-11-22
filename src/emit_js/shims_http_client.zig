const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_http_client_async_cancel_v2")) {
        try writer.writeAll(
            \\function sa_http_client_async_cancel_v2(op) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
            \\  if (!o) return 5;
            \\  o.cancelled = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_async_free")) {
        try writer.writeAll(
            \\function sa_http_client_async_free(op) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  delete globalThis.__sa_http_op[__sa_addr(op)];
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_async_free_v2")) {
        try writer.writeAll(
            \\function sa_http_client_async_free_v2(op) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  delete globalThis.__sa_http_op[__sa_addr(op)];
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_async_poll")) {
        try writer.writeAll(
            \\function sa_http_client_async_poll(op, out_ready) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
            \\  if (!o) return 2;
            \\  __sa_store_i64(out_ready, BigInt(1));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_async_poll_v2")) {
        try writer.writeAll(
            \\function sa_http_client_async_poll_v2(op, timeout_ms, out_ready) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
            \\  if (!o) return 5;
            \\  __sa_store_i64(out_ready, BigInt(o.cancelled ? 0 : 1));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_async_take_response")) {
        try writer.writeAll(
            \\function sa_http_client_async_take_response(op, out_resp) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
            \\  if (!o || o.taken) return 2;
            \\  o.taken = true;
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_resp[__sa_addr(h)] = o.resp;
            \\  __sa_store_ptr(out_resp, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_async_take_response_v2")) {
        try writer.writeAll(
            \\function sa_http_client_async_take_response_v2(op, out_resp) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
            \\  if (!o || o.taken || o.cancelled) return 5;
            \\  o.taken = true;
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_resp[__sa_addr(h)] = o.resp;
            \\  __sa_store_ptr(out_resp, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_body_reader_free")) {
        try writer.writeAll("function sa_http_client_body_reader_free(reader) { delete globalThis.__sa_http_rd[__sa_addr(reader)]; return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_free")) {
        try writer.writeAll("function sa_http_client_free(client) { delete globalThis.__sa_http_c[__sa_addr(client)]; return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_new")) {
        try writer.writeAll(
            \\function sa_http_client_new(use_tls, out_client) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_c[__sa_addr(h)] = { tls: __sa_num(use_tls) };
            \\  __sa_store_ptr(out_client, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_new_v2")) {
        try writer.writeAll(
            \\function sa_http_client_new_v2(use_tls, ca_bundle_path, ca_bundle_path_len, out_client) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_c[__sa_addr(h)] = { tls: __sa_num(use_tls), v2: true };
            \\  __sa_store_ptr(out_client, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_add_header")) {
        try writer.writeAll(
            \\function sa_http_client_req_add_header(req, key, key_len, val, val_len) {
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 1;
            \\  const ka = __sa_addr(key), kn = __sa_num(key_len), va = __sa_addr(val), vn = __sa_num(val_len);
            \\  const dec = new globalThis.TextDecoder();
            \\  r.headers[dec.decode(__sa_u8.slice(ka, ka + kn))] = dec.decode(__sa_u8.slice(va, va + vn));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_add_header_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_add_header_v2(req, key, key_len, value, value_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 5;
            \\  const dec = new globalThis.TextDecoder();
            \\  const ka = __sa_addr(key), kn = __sa_num(key_len);
            \\  const va = __sa_addr(value), vn = __sa_num(value_len);
            \\  r.headers[dec.decode(__sa_u8.slice(ka, ka + kn))] = dec.decode(__sa_u8.slice(va, va + vn));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_add_openai_auth")) {
        try writer.writeAll(
            \\function sa_http_client_req_add_openai_auth(req, key, key_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 2;
            \\  const dec = new globalThis.TextDecoder();
            \\  const ka = __sa_addr(key), kn = __sa_num(key_len);
            \\  r.headers["authorization"] = "Bearer " + dec.decode(__sa_u8.slice(ka, ka + kn));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_free")) {
        try writer.writeAll("function sa_http_client_req_free(req) { delete globalThis.__sa_http_req[__sa_addr(req)]; return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_new")) {
        try writer.writeAll(
            \\function sa_http_client_req_new(client, method, url, url_len, out_req) {
            \\  const a = __sa_addr(url), n = __sa_num(url_len);
            \\  const u = new globalThis.TextDecoder().decode(__sa_u8.slice(a, a + n));
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_req[__sa_addr(h)] = { method: __sa_num(method), url: u, headers: {}, body: new Uint8Array(0) };
            \\  __sa_store_ptr(out_req, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_new_joined")) {
        try writer.writeAll(
            \\function sa_http_client_req_new_joined(client, method, target, target_len, path, path_len, preserve, out_req) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const dec = new globalThis.TextDecoder();
            \\  const ta = __sa_addr(target), tn = __sa_num(target_len);
            \\  const pa = __sa_addr(path), pn = __sa_num(path_len);
            \\  const url = dec.decode(__sa_u8.slice(ta, ta + tn)) + dec.decode(__sa_u8.slice(pa, pa + pn));
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_req[__sa_addr(h)] = { method: __sa_num(method), url: url, headers: {}, body: new Uint8Array(0) };
            \\  __sa_store_ptr(out_req, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_new_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_new_v2(client, method, url, url_len, out_req) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const dec = new globalThis.TextDecoder();
            \\  const a = __sa_addr(url), n = __sa_num(url_len);
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_req[__sa_addr(h)] = { method: __sa_num(method), url: dec.decode(__sa_u8.slice(a, a + n)), headers: {}, body: new Uint8Array(0), timeout: 0, max: 0 };
            \\  __sa_store_ptr(out_req, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_send")) {
        try writer.writeAll(
            \\function sa_http_client_req_send(req, out_resp) {
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 1;
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_resp[__sa_addr(h)] = { status: 200, body: r.body.slice() };
            \\  __sa_store_ptr(out_resp, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_send_async")) {
        try writer.writeAll(
            \\function sa_http_client_req_send_async(req, out_op) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 2;
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_op[__sa_addr(h)] = { resp: { status: 200, body: r.body.slice(), headers: Object.assign({}, r.headers) }, taken: false };
            \\  __sa_store_ptr(out_op, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_send_async_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_send_async_v2(req, out_op) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 5;
            \\  if (r.max && r.body.length > r.max) return 4;
            \\  const resp = { status: 200, body: r.body.slice(), headers: Object.assign({}, r.headers) };
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_op[__sa_addr(h)] = { resp: resp, taken: false, v2: true };
            \\  __sa_store_ptr(out_op, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_send_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_send_v2(req, out_resp) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 5;
            \\  if (r.max && r.body.length > r.max) return 4;
            \\  const resp = { status: 200, body: r.body.slice(), headers: Object.assign({}, r.headers) };
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_resp[__sa_addr(h)] = resp;
            \\  __sa_store_ptr(out_resp, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_set_body")) {
        try writer.writeAll(
            \\function sa_http_client_req_set_body(req, body, body_len) {
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 1;
            \\  const a = __sa_addr(body), n = __sa_num(body_len);
            \\  r.body = __sa_u8.slice(a, a + n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_set_body_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_set_body_v2(req, body, body_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 5;
            \\  const a = __sa_addr(body), n = __sa_num(body_len);
            \\  r.body = __sa_u8.slice(a, a + n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_set_max_response_bytes_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_set_max_response_bytes_v2(req, max_bytes) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 5;
            \\  r.max = __sa_num(max_bytes);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_set_timeout_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_set_timeout_v2(req, timeout_ms) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
            \\  if (!r) return 5;
            \\  r.timeout = __sa_num(timeout_ms);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_req_websocket_connect_unix_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_websocket_connect_unix_v2(req, socket_path, socket_path_len, timeout_ms, out_ws) {
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
    if (std.mem.eql(u8, name, "sa_http_client_req_websocket_connect_v2")) {
        try writer.writeAll(
            \\function sa_http_client_req_websocket_connect_v2(req, timeout_ms, out_ws) {
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
    if (std.mem.eql(u8, name, "sa_http_client_resp_body_len")) {
        try writer.writeAll(
            \\function sa_http_client_resp_body_len(resp) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
            \\  return r ? BigInt(r.body.length) : BigInt(0);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_resp_body_ptr")) {
        try writer.writeAll(
            \\function sa_http_client_resp_body_ptr(resp) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
            \\  if (!r) return 0;
            \\  if (!r.body_addr) { r.body_addr = __sa_alloc(r.body.length); __sa_u8.set(r.body, r.body_addr); }
            \\  return r.body_addr;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_resp_body_reader")) {
        try writer.writeAll(
            \\function sa_http_client_resp_body_reader(resp, out_reader) {
            \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
            \\  if (!r) return 1;
            \\  const h = __sa_alloc(8);
            \\  globalThis.__sa_http_rd[__sa_addr(h)] = { body: r.body, off: 0 };
            \\  __sa_store_ptr(out_reader, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_resp_body_slice")) {
        try writer.writeAll(
            \\function sa_http_client_resp_body_slice(resp, out_body, out_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
            \\  if (!r) return 2;
            \\  if (!r.body_addr) { r.body_addr = __sa_alloc(r.body.length); __sa_u8.set(r.body, r.body_addr); }
            \\  __sa_store_ptr(out_body, r.body_addr);
            \\  __sa_store_i64(out_len, BigInt(r.body.length));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_resp_free")) {
        try writer.writeAll("function sa_http_client_resp_free(resp) { delete globalThis.__sa_http_resp[__sa_addr(resp)]; return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_http_client_resp_get_header")) {
        try writer.writeAll(
            \\function sa_http_client_resp_get_header(resp, key, key_len, out_val, out_len) {
            \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
            \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
            \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
            \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
            \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
            \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
            \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
            \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
            \\  if (!r) return 2;
            \\  const dec = new globalThis.TextDecoder();
            \\  const ka = __sa_addr(key), kn = __sa_num(key_len);
            \\  const want = dec.decode(__sa_u8.slice(ka, ka + kn)).toLowerCase();
            \\  const headers = r.headers || {};
            \\  for (const k of Object.keys(headers)) {
            \\    if (k.toLowerCase() === want) {
            \\      const enc = new globalThis.TextEncoder();
            \\      const bytes = enc.encode(headers[k]);
            \\      const p = __sa_alloc(bytes.length);
            \\      __sa_u8.set(bytes, p);
            \\      __sa_store_ptr(out_val, p);
            \\      __sa_store_i64(out_len, BigInt(bytes.length));
            \\      return 0;
            \\    }
            \\  }
            \\  return 2;
            \\}
            \\
        );
        return true;
    }
    return false;
}
