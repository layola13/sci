const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_std_close")) {
        try writer.writeAll(
            \\function sa_std_close(handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e) return 2;
            \\  if (e.bridgeId !== undefined && e.bridgeId !== null) J.bridgeCall("sock_close", { id: e.bridgeId }, null, false);
            \\  J.netDel(__sa_num(handle));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_compress_buffer_data")) {
        try writer.writeAll(
            \\function sa_std_compress_buffer_data(buffer) {
            \\  const m = globalThis.__sa_cbuf;
            \\  const rec = m ? m.map[Number(buffer)] : null;
            \\  if (!rec) return 0;
            \\  if (!rec.addr) { rec.addr = __sa_alloc(rec.bytes.length); __sa_u8.set(rec.bytes, rec.addr); }
            \\  return rec.addr;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_compress_buffer_free")) {
        try writer.writeAll(
            \\function sa_std_compress_buffer_free(buffer) {
            \\  const m = globalThis.__sa_cbuf;
            \\  if (m) { const rec = m.map[Number(buffer)]; if (rec) { if (rec.addr) __sa_free(rec.addr); delete m.map[Number(buffer)]; } }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_compress_buffer_len")) {
        try writer.writeAll(
            \\function sa_std_compress_buffer_len(buffer) {
            \\  const m = globalThis.__sa_cbuf;
            \\  const rec = m ? m.map[Number(buffer)] : null;
            \\  return rec ? BigInt(rec.bytes.length) : BigInt(0);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_compress_decode")) {
        try writer.writeAll(
            \\function sa_std_compress_decode(format, data, data_len, out_handle) {
            \\  const z = __sa_node_builtin("node:zlib");
            \\  if (!z) return 8;
            \\  const f = __sa_num(format);
            \\  const a = __sa_addr(data), n = __sa_num(data_len);
            \\  const input = __sa_u8.slice(a, a + n);
            \\  let out = null;
            \\  try {
            \\    if (f === 1) out = z.gunzipSync(input);
            \\    else if (f === 2) out = z.inflateSync(input);
            \\    else if (f === 3) out = z.inflateRawSync(input);
            \\    else if (f === 4) { if (!z.brotliDecompressSync) return 8; out = z.brotliDecompressSync(input); }
            \\    else return 1;
            \\  } catch (e) { return 6; }
            \\  globalThis.__sa_cbuf = (globalThis.__sa_cbuf || { next: 1, map: {} });
            \\  const id = globalThis.__sa_cbuf.next++;
            \\  globalThis.__sa_cbuf.map[id] = { bytes: new Uint8Array(out), addr: 0 };
            \\  __sa_store_i64(out_handle, BigInt(id));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_compress_encode")) {
        try writer.writeAll(
            \\function sa_std_compress_encode(format, data, data_len, out_handle) {
            \\  const z = __sa_node_builtin("node:zlib");
            \\  if (!z) return 8;
            \\  const f = __sa_num(format);
            \\  const a = __sa_addr(data), n = __sa_num(data_len);
            \\  const input = __sa_u8.slice(a, a + n);
            \\  let out = null;
            \\  try {
            \\    if (f === 1) out = z.gzipSync(input);
            \\    else if (f === 2) out = z.deflateSync(input);
            \\    else if (f === 3) out = z.deflateRawSync(input);
            \\    else if (f === 4) { if (!z.brotliCompressSync) return 8; out = z.brotliCompressSync(input); }
            \\    else return 1;
            \\  } catch (e) { return 6; }
            \\  globalThis.__sa_cbuf = (globalThis.__sa_cbuf || { next: 1, map: {} });
            \\  const id = globalThis.__sa_cbuf.next++;
            \\  globalThis.__sa_cbuf.map[id] = { bytes: new Uint8Array(out), addr: 0 };
            \\  __sa_store_i64(out_handle, BigInt(id));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_compress_supported")) {
        try writer.writeAll(
            \\function sa_std_compress_supported(out_flags) {
            \\  let flags = 0;
            \\  const z = __sa_node_builtin("node:zlib");
            \\  if (z) { flags = 1; if (z.brotliCompressSync && z.brotliDecompressSync) flags |= 2; }
            \\  __sa_store_i64(out_flags, BigInt(flags));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_fd_into_raw")) {
        try writer.writeAll(
            \\function sa_std_fd_into_raw(handle, out_fd) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i32(out_fd, 0);
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e || e.kind !== "tcp") return 2;
            \\  // Detach: the SA handle is consumed; the bridge id moves to the
            \\  // detached table so start_tls can upgrade this socket in place.
            \\  const bid = e.bridgeId;
            \\  J.netDel(__sa_num(handle));
            \\  J.NET.detached.set(bid, true);
            \\  __sa_store_i32(out_fd, bid);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_fs_exists")) {
        try writer.writeAll(
            \\function sa_std_fs_exists(path_ptr, path_len) {
            \\  // Status-code shape (mirror native): 0 exists,
            \\  // NOT_FOUND(3) missing, INVALID_ARGUMENT(1) on bad input.
            \\  const fs = __sa_node_builtin("node:fs");
            \\  if (fs === null) return 1;
            \\  try {
            \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
            \\    return fs.existsSync(p) ? 0 : 3;
            \\  } catch (e) { return 1; }
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_buffer_data")) {
        try writer.writeAll(
            \\function sa_std_multipart_buffer_data(buffer) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const rec = globalThis.__sa_mp.bufs[Number(buffer)];
            \\  if (!rec) return 0;
            \\  if (!rec.addr) { rec.addr = __sa_alloc(rec.bytes.length); __sa_u8.set(rec.bytes, rec.addr); }
            \\  return rec.addr;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_buffer_free")) {
        try writer.writeAll(
            \\function sa_std_multipart_buffer_free(buffer) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const rec = globalThis.__sa_mp.bufs[Number(buffer)];
            \\  if (rec) { if (rec.addr) __sa_free(rec.addr); delete globalThis.__sa_mp.bufs[Number(buffer)]; }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_buffer_len")) {
        try writer.writeAll(
            \\function sa_std_multipart_buffer_len(buffer) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const rec = globalThis.__sa_mp.bufs[Number(buffer)];
            \\  return rec ? BigInt(rec.bytes.length) : BigInt(0);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_add_field")) {
        try writer.writeAll(
            \\function sa_std_multipart_builder_add_field(handle, name, name_len, value, value_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "builder") return 2;
            \\  const na = __sa_addr(name), nn = __sa_num(name_len);
            \\  const va = __sa_addr(value), vn = __sa_num(value_len);
            \\  it.list.push({ name: __sa_u8.slice(na, na + nn), filename: null, contentType: null, data: __sa_u8.slice(va, va + vn) });
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_add_file")) {
        try writer.writeAll(
            \\function sa_std_multipart_builder_add_file(handle, name, name_len, filename, filename_len, content_type, content_type_len, data, data_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "builder") return 2;
            \\  it.list.push({
            \\    name: __sa_u8.slice(__sa_addr(name), __sa_addr(name) + __sa_num(name_len)),
            \\    filename: __sa_u8.slice(__sa_addr(filename), __sa_addr(filename) + __sa_num(filename_len)),
            \\    contentType: __sa_u8.slice(__sa_addr(content_type), __sa_addr(content_type) + __sa_num(content_type_len)),
            \\    data: __sa_u8.slice(__sa_addr(data), __sa_addr(data) + __sa_num(data_len))
            \\  });
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_boundary")) {
        try writer.writeAll(
            \\function sa_std_multipart_builder_boundary(handle, out, cap, out_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "builder") return 2;
            \\  const value = it.boundary;
            \\  const enc = new globalThis.TextEncoder();
            \\  const bytes = enc.encode(value);
            \\  __sa_store_i64(out_len, BigInt(bytes.length));
            \\  if (__sa_num(cap) < bytes.length) return 9;
            \\  __sa_u8.set(bytes, __sa_addr(out));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_content_type")) {
        try writer.writeAll(
            \\function sa_std_multipart_builder_content_type(handle, out, cap, out_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "builder") return 2;
            \\  const value = "multipart/form-data; boundary=" + it.boundary;
            \\  const enc = new globalThis.TextEncoder();
            \\  const bytes = enc.encode(value);
            \\  __sa_store_i64(out_len, BigInt(bytes.length));
            \\  if (__sa_num(cap) < bytes.length) return 9;
            \\  __sa_u8.set(bytes, __sa_addr(out));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_finish")) {
        try writer.writeAll(
            \\function sa_std_multipart_builder_finish(handle, out_handle) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "builder") return 2;
            \\  const enc = new globalThis.TextEncoder();
            \\  const chunks = [];
            \\  let first = true;
            \\  for (const item of it.list) {
            \\    if (!first) chunks.push(enc.encode("\r\n"));
            \\    first = false;
            \\    chunks.push(enc.encode("--" + it.boundary + "\r\nContent-Disposition: form-data; name=\""));
            \\    chunks.push(item.name);
            \\    if (item.filename !== null) {
            \\      chunks.push(enc.encode("\"; filename=\""));
            \\      chunks.push(item.filename);
            \\    }
            \\    chunks.push(enc.encode("\""));
            \\    if (item.contentType !== null) {
            \\      chunks.push(enc.encode("\r\nContent-Type: "));
            \\      chunks.push(item.contentType);
            \\    }
            \\    chunks.push(enc.encode("\r\n\r\n"));
            \\    chunks.push(item.data);
            \\  }
            \\  chunks.push(enc.encode("\r\n--" + it.boundary + "--\r\n"));
            \\  let total = 0;
            \\  for (const c of chunks) total += c.length;
            \\  const bytes = new Uint8Array(total);
            \\  let off = 0;
            \\  for (const c of chunks) { bytes.set(c, off); off += c.length; }
            \\  const id = globalThis.__sa_mp.next++;
            \\  globalThis.__sa_mp.bufs[id] = { bytes: bytes, addr: 0 };
            \\  __sa_store_i64(out_handle, BigInt(id));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_free")) {
        try writer.writeAll(
            \\function sa_std_multipart_builder_free(handle) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  delete globalThis.__sa_mp.items[Number(handle)];
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_new")) {
        try writer.writeAll(
            \\function sa_std_multipart_builder_new(out_handle) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const id = globalThis.__sa_mp.next++;
            \\  globalThis.__sa_mp.items[id] = { kind: "builder", list: [], boundary: "----sa-std-multipart-js-" + id };
            \\  __sa_store_i64(out_handle, BigInt(id));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_count")) {
        try writer.writeAll(
            \\function sa_std_multipart_count(handle) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  return (it && it.kind === "parsed") ? BigInt(it.parts.length) : BigInt(0);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_free")) {
        try writer.writeAll(
            \\function sa_std_multipart_free(handle) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  delete globalThis.__sa_mp.items[Number(handle)];
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_parse")) {
        try writer.writeAll(
            \\function sa_std_multipart_parse(body, body_len, content_type, content_type_len, out_handle) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const dec = new globalThis.TextDecoder();
            \\  const ba = __sa_addr(body), bn = __sa_num(body_len);
            \\  const ca = __sa_addr(content_type), cn = __sa_num(content_type_len);
            \\  const ct = dec.decode(__sa_u8.slice(ca, ca + cn));
            \\  let boundary = null;
            \\  for (const part of ct.split(";")) {
            \\    const t = part.trim();
            \\    if (t.startsWith("boundary=")) { boundary = t.slice(9).trim(); if (boundary.startsWith("\"") && boundary.endsWith("\"")) boundary = boundary.slice(1, -1); }
            \\  }
            \\  if (!boundary) return 1;
            \\  const raw = __sa_u8.slice(ba, ba + bn);
            \\  let text = "";
            \\  for (let i = 0; i < raw.length; i += 8192) text += String.fromCharCode.apply(null, raw.subarray(i, i + 8192));
            \\  const segs = text.split("--" + boundary);
            \\  const parts = [];
            \\  for (let i = 1; i < segs.length; i++) {
            \\    let seg = segs[i];
            \\    if (seg.startsWith("--")) break;
            \\    if (!seg.startsWith("\r\n")) return 1;
            \\    seg = seg.slice(2);
            \\    if (seg.endsWith("\r\n")) seg = seg.slice(0, -2);
            \\    const cut = seg.indexOf("\r\n\r\n");
            \\    if (cut < 0) return 1;
            \\    const head = seg.slice(0, cut);
            \\    const pbody = seg.slice(cut + 4);
            \\    const part = { name: "", filename: null, contentType: null, headers: [], body: new Uint8Array(pbody.length) };
            \\    for (let j = 0; j < pbody.length; j++) part.body[j] = pbody.charCodeAt(j) & 255;
            \\    for (const line of head.split("\r\n")) {
            \\      const colon = line.indexOf(":");
            \\      if (colon < 0) continue;
            \\      const hn = line.slice(0, colon).trim();
            \\      const hv = line.slice(colon + 1).trim();
            \\      part.headers.push([hn, hv]);
            \\      const lhn = hn.toLowerCase();
            \\      if (lhn === "content-type") part.contentType = hv;
            \\      if (lhn === "content-disposition") {
            \\        for (const tok of hv.split(";")) {
            \\          const t = tok.trim();
            \\          const eq = t.indexOf("=");
            \\          if (eq < 0) continue;
            \\          const k = t.slice(0, eq).trim();
            \\          let v = t.slice(eq + 1).trim();
            \\          if (v.startsWith("\"") && v.endsWith("\"")) v = v.slice(1, -1);
            \\          if (k === "name") part.name = v;
            \\          if (k === "filename") part.filename = v;
            \\        }
            \\      }
            \\    }
            \\    parts.push(part);
            \\  }
            \\  const id = globalThis.__sa_mp.next++;
            \\  globalThis.__sa_mp.items[id] = { kind: "parsed", parts: parts };
            \\  __sa_store_i64(out_handle, BigInt(id));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_part_body")) {
        try writer.writeAll(
            \\function sa_std_multipart_part_body(handle, index, out_ptr, out_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "parsed") return 3;
            \\  const part = it.parts[__sa_num(index)];
            \\  if (!part) return 3;
            \\  if (!part.addr) { part.addr = __sa_alloc(part.body.length); __sa_u8.set(part.body, part.addr); }
            \\  __sa_store_ptr(out_ptr, part.addr);
            \\  __sa_store_i64(out_len, BigInt(part.body.length));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_part_content_type")) {
        try writer.writeAll(
            \\function sa_std_multipart_part_content_type(handle, index, out, cap, out_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "parsed") return 3;
            \\  const part = it.parts[__sa_num(index)];
            \\  if (!part) return 3;
            \\  const value = part.contentType;
            \\  if (value === null || value === undefined) return 100;
            \\  const enc = new globalThis.TextEncoder();
            \\  const bytes = enc.encode(value);
            \\  __sa_store_i64(out_len, BigInt(bytes.length));
            \\  if (__sa_num(cap) < bytes.length) return 9;
            \\  __sa_u8.set(bytes, __sa_addr(out));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_part_filename")) {
        try writer.writeAll(
            \\function sa_std_multipart_part_filename(handle, index, out, cap, out_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "parsed") return 3;
            \\  const part = it.parts[__sa_num(index)];
            \\  if (!part) return 3;
            \\  const value = part.filename;
            \\  if (value === null || value === undefined) return 100;
            \\  const enc = new globalThis.TextEncoder();
            \\  const bytes = enc.encode(value);
            \\  __sa_store_i64(out_len, BigInt(bytes.length));
            \\  if (__sa_num(cap) < bytes.length) return 9;
            \\  __sa_u8.set(bytes, __sa_addr(out));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_part_header")) {
        try writer.writeAll(
            \\function sa_std_multipart_part_header(handle, index, name, name_len, out, cap, out_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "parsed") return 3;
            \\  const part = it.parts[__sa_num(index)];
            \\  if (!part) return 3;
            \\  const dec = new globalThis.TextDecoder();
            \\  const na = __sa_addr(name), nn = __sa_num(name_len);
            \\  const want = dec.decode(__sa_u8.slice(na, na + nn)).toLowerCase();
            \\  let value = null;
            \\  for (const pair of part.headers) { if (pair[0].toLowerCase() === want) { value = pair[1]; break; } }
            \\  if (value === null) return 100;
            \\  const enc = new globalThis.TextEncoder();
            \\  const bytes = enc.encode(value);
            \\  __sa_store_i64(out_len, BigInt(bytes.length));
            \\  if (__sa_num(cap) < bytes.length) return 9;
            \\  __sa_u8.set(bytes, __sa_addr(out));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_multipart_part_name")) {
        try writer.writeAll(
            \\function sa_std_multipart_part_name(handle, index, out, cap, out_len) {
            \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
            \\  const it = globalThis.__sa_mp.items[Number(handle)];
            \\  if (!it || it.kind !== "parsed") return 3;
            \\  const part = it.parts[__sa_num(index)];
            \\  if (!part) return 3;
            \\  const value = part.name;
            \\  const enc = new globalThis.TextEncoder();
            \\  const bytes = enc.encode(value);
            \\  __sa_store_i64(out_len, BigInt(bytes.length));
            \\  if (__sa_num(cap) < bytes.length) return 9;
            \\  __sa_u8.set(bytes, __sa_addr(out));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_addr_format")) {
        try writer.writeAll(
            \\function sa_std_net_addr_format(addr, out, out_cap, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_len, 0n);
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!a || a.kind !== "addr") return 2;
            \\  const text = (a.family === 10) ? "[" + a.host + "]:" + a.port : a.host + ":" + a.port;
            \\  const b = J.bFromStr(text);
            \\  const cap = __sa_num(out_cap);
            \\  const n = Math.min(cap, b.length);
            \\  __sa_u8.set(b.subarray(0, n), __sa_addr(out));
            \\  __sa_store_i64(out_len, BigInt(n));
            \\  return (n < b.length) ? 9 : 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_free")) {
        try writer.writeAll(
            \\function sa_std_net_addr_list_free(list) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return J.netDel(__sa_num(list)) ? 0 : 2;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_next")) {
        try writer.writeAll(
            \\function sa_std_net_addr_list_next(list, out_ok, out_addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i32(out_ok, 0);
            \\  __sa_store_i64(out_addr, 0n);
            \\  const l = J.netGet(__sa_num(list));
            \\  if (!l || l.kind !== "addrlist") return 2;
            \\  if (l.idx >= l.addrs.length) return 0;
            \\  const a = l.addrs[l.idx++];
            \\  __sa_store_i32(out_ok, 1);
            \\  __sa_store_i64(out_addr, BigInt(J.netReg(a)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_remaining")) {
        try writer.writeAll(
            \\function sa_std_net_addr_list_remaining(list, out_remaining) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_remaining, 0n);
            \\  const l = J.netGet(__sa_num(list));
            \\  if (!l || l.kind !== "addrlist") return 2;
            \\  __sa_store_i64(out_remaining, BigInt(l.addrs.length - l.idx));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_reset")) {
        try writer.writeAll(
            \\function sa_std_net_addr_list_reset(list) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const l = J.netGet(__sa_num(list));
            \\  if (!l || l.kind !== "addrlist") return 2;
            \\  l.idx = 0;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    return false;
}
