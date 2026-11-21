const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_json_array_get")) {
        try writer.writeAll(
            \\function sa_json_array_get(node, index, out_handle) {
            \\  __sa_store_i64(out_handle, 0n);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || !Array.isArray(v)) return 2;
            \\  const i = __sa_tou(index);
            \\  if (!(i >= 0) || i >= v.length) return 3;
            \\  const h = __sa_jsonnext++;
            \\  __sa_jsonnodes.set(h, v[i]);
            \\  __sa_store_i64(out_handle, BigInt(h));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_array_push_bool")) {
        try writer.writeAll(
            \\function sa_json_array_push_bool(node, value) {
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || !Array.isArray(v)) return 2;
            \\  v.push(__sa_num(value) !== 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_array_push_f64")) {
        try writer.writeAll(
            \\function sa_json_array_push_f64(node, value) {
            \\  if (!Number.isFinite(+value)) return 1;
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || !Array.isArray(v)) return 2;
            \\  v.push(+value);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_array_push_i64")) {
        try writer.writeAll(
            \\function sa_json_array_push_i64(node, value) {
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || !Array.isArray(v)) return 2;
            \\  v.push(Number(BigInt.asIntN(64, BigInt(__sa_num(value)))));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_array_push_node")) {
        try writer.writeAll(
            \\function sa_json_array_push_node(node, child) {
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || !Array.isArray(v)) return 2;
            \\  const cv = __sa_jsonnodes.get(__sa_num(child));
            \\  if (cv === undefined) return 2;
            \\  v.push(__sa_json_clone(cv));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_array_push_null")) {
        try writer.writeAll(
            \\function sa_json_array_push_null(node) {
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || !Array.isArray(v)) return 2;
            \\  v.push(null);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_array_push_string")) {
        try writer.writeAll(
            \\function sa_json_array_push_string(node, data_ptr, len) {
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || !Array.isArray(v)) return 2;
            \\  v.push(new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, len)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_as_bool")) {
        try writer.writeAll(
            \\function sa_json_as_bool(node, out_value) {
            \\  __sa_store_u8(out_value, 0);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined) return 2;
            \\  if (typeof v !== "boolean") return 1;
            \\  __sa_store_u8(out_value, v ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_as_f64")) {
        try writer.writeAll(
            \\function sa_json_as_f64(node, out_value) {
            \\  __sa_store_f64(out_value, 0);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined) return 2;
            \\  const n = __sa_json_f64_of(v);
            \\  if (n === null) return 1;
            \\  __sa_store_f64(out_value, n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_as_i64")) {
        try writer.writeAll(
            \\function sa_json_as_i64(node, out_value) {
            \\  __sa_store_i64(out_value, 0n);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined) return 2;
            \\  const n = __sa_json_i64_of(v);
            \\  if (n === null) return 1;
            \\  __sa_store_i64(out_value, n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_buffer_data")) {
        try writer.writeAll(
            \\function sa_json_buffer_data(handle) {
            \\  const b = __sa_jsonbufs.get(__sa_num(handle));
            \\  if (b === undefined) return 0;
            \\  const p = __sa_alloc(b.length);
            \\  __sa_u8.set(b, p);
            \\  return p;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_buffer_free")) {
        try writer.writeAll(
            \\function sa_json_buffer_free(handle) { __sa_jsonbufs.delete(__sa_num(handle)); return 0; }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_buffer_len")) {
        try writer.writeAll(
            \\function sa_json_buffer_len(handle) {
            \\  const b = __sa_jsonbufs.get(__sa_num(handle));
            \\  return (b === undefined) ? 0n : BigInt(b.length);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_free")) {
        try writer.writeAll(
            \\function sa_json_free(node) { __sa_jsonnodes.delete(__sa_num(node)); return 0; }
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_kind")) {
        try writer.writeAll(
            \\function sa_json_kind(node) {
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined) return 4294967295;
            \\  return __sa_json_kind_of(v);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_get")) {
        try writer.writeAll(
            \\function sa_json_object_get(node, key_ptr, key_len, out_handle) {
            \\  __sa_store_i64(out_handle, 0n);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
            \\  const h = __sa_jsonnext++;
            \\  __sa_jsonnodes.set(h, v[key]);
            \\  __sa_store_i64(out_handle, BigInt(h));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_get_bool")) {
        try writer.writeAll(
            \\function sa_json_object_get_bool(node, key_ptr, key_len, out_value) {
            \\  __sa_store_u8(out_value, 0);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
            \\  const b = v[key];
            \\  if (typeof b !== "boolean") return 1;
            \\  __sa_store_u8(out_value, b ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_get_f64")) {
        try writer.writeAll(
            \\function sa_json_object_get_f64(node, key_ptr, key_len, out_value) {
            \\  __sa_store_f64(out_value, 0);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
            \\  const n = __sa_json_f64_of(v[key]);
            \\  if (n === null) return 1;
            \\  __sa_store_f64(out_value, n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_get_i64")) {
        try writer.writeAll(
            \\function sa_json_object_get_i64(node, key_ptr, key_len, out_value) {
            \\  __sa_store_i64(out_value, 0n);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
            \\  const n = __sa_json_i64_of(v[key]);
            \\  if (n === null) return 1;
            \\  __sa_store_i64(out_value, n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_get_string")) {
        try writer.writeAll(
            \\function sa_json_object_get_string(node, key_ptr, key_len, out_ptr, out_len) {
            \\  __sa_store_i64(out_ptr, 0n);
            \\  __sa_store_i64(out_len, 0n);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
            \\  const s = v[key];
            \\  if (typeof s !== "string") return 1;
            \\  const bytes = new globalThis.TextEncoder().encode(s);
            \\  const p = __sa_alloc(bytes.length);
            \\  __sa_u8.set(bytes, p);
            \\  __sa_store_i64(out_ptr, p);
            \\  __sa_store_i64(out_len, bytes.length);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_key_at")) {
        try writer.writeAll(
            \\function sa_json_object_key_at(node, index, out_ptr, out_len) {
            \\  __sa_store_i64(out_ptr, 0n);
            \\  __sa_store_i64(out_len, 0n);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  const keys = Object.keys(v);
            \\  const i = __sa_tou(index);
            \\  if (!(i >= 0) || i >= keys.length) return 3;
            \\  const bytes = new globalThis.TextEncoder().encode(keys[i]);
            \\  const p = __sa_alloc(bytes.length);
            \\  __sa_u8.set(bytes, p);
            \\  __sa_store_i64(out_ptr, p);
            \\  __sa_store_i64(out_len, bytes.length);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_remove")) {
        try writer.writeAll(
            \\function sa_json_object_remove(node, key_ptr, key_len) {
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
            \\  delete v[key];
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_set_bool")) {
        try writer.writeAll(
            \\function sa_json_object_set_bool(node, key_ptr, key_len, value) {
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  v[key] = __sa_num(value) !== 0;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_set_f64")) {
        try writer.writeAll(
            \\function sa_json_object_set_f64(node, key_ptr, key_len, value) {
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  if (!Number.isFinite(+value)) return 1;
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  v[key] = +value;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_set_i64")) {
        try writer.writeAll(
            \\function sa_json_object_set_i64(node, key_ptr, key_len, value) {
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  v[key] = Number(BigInt.asIntN(64, BigInt(__sa_num(value))));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_set_node")) {
        try writer.writeAll(
            \\function sa_json_object_set_node(node, key_ptr, key_len, child) {
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  const cv = __sa_jsonnodes.get(__sa_num(child));
            \\  if (cv === undefined) return 2;
            \\  v[key] = __sa_json_clone(cv);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_set_null")) {
        try writer.writeAll(
            \\function sa_json_object_set_null(node, key_ptr, key_len) {
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  v[key] = null;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_object_set_string")) {
        try writer.writeAll(
            \\function sa_json_object_set_string(node, key_ptr, key_len, data_ptr, len) {
            \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
            \\  if (key.length === 0) return 1;
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
            \\  v[key] = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, len));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_parse")) {
        try writer.writeAll(
            \\function sa_json_parse(json_ptr, len) {
            \\  const bytes = __sa_mem_bytes(json_ptr, len);
            \\  let text = "";
            \\  try { text = new globalThis.TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch (e) { return 0n; }
            \\  let value;
            \\  try { value = globalThis.JSON.parse(text); } catch (e) { return 0n; }
            \\  if (value === undefined) return 0n;
            \\  const h = __sa_jsonnext++;
            \\  __sa_jsonnodes.set(h, value);
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_value_count")) {
        try writer.writeAll(
            \\function sa_json_value_count(node, out_count) {
            \\  __sa_store_i64(out_count, 0n);
            \\  const v = __sa_jsonnodes.get(__sa_num(node));
            \\  if (v === undefined) return 2;
            \\  if (Array.isArray(v)) { __sa_store_i64(out_count, v.length); return 0; }
            \\  if (v !== null && typeof v === "object") { __sa_store_i64(out_count, Object.keys(v).length); return 0; }
            \\  return 1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_begin_array")) {
        try writer.writeAll(
            \\function sa_json_writer_begin_array(writer) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_begin(w, '[');
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_begin_object")) {
        try writer.writeAll(
            \\function sa_json_writer_begin_object(writer) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_begin(w, '{');
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_end_array")) {
        try writer.writeAll(
            \\function sa_json_writer_end_array(writer) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_end(w, ']');
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_end_object")) {
        try writer.writeAll(
            \\function sa_json_writer_end_object(writer) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_end(w, '}');
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_field_bool")) {
        try writer.writeAll(
            \\function sa_json_writer_field_bool(writer, key_ptr, key_len, value) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
            \\  if (rc !== 0) return rc;
            \\  w.parts.push(__sa_num(value) !== 0 ? "true" : "false");
            \\  if (w.stack.length === 0) w.root_done = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_field_f64")) {
        try writer.writeAll(
            \\function sa_json_writer_field_f64(writer, key_ptr, key_len, value) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
            \\  if (rc !== 0) return rc;
            \\  w.parts.push(__sa_json_f64_str(value));
            \\  if (w.stack.length === 0) w.root_done = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_field_i64")) {
        try writer.writeAll(
            \\function sa_json_writer_field_i64(writer, key_ptr, key_len, value) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
            \\  if (rc !== 0) return rc;
            \\  w.parts.push(BigInt.asIntN(64, BigInt(__sa_num(value))).toString(10));
            \\  if (w.stack.length === 0) w.root_done = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_field_null")) {
        try writer.writeAll(
            \\function sa_json_writer_field_null(writer, key_ptr, key_len) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
            \\  if (rc !== 0) return rc;
            \\  w.parts.push("null");
            \\  if (w.stack.length === 0) w.root_done = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_field_string")) {
        try writer.writeAll(
            \\function sa_json_writer_field_string(writer, key_ptr, key_len, data_ptr, data_len) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
            \\  if (rc !== 0) return rc;
            \\  w.parts.push(__sa_json_quote(__sa_mem_bytes(data_ptr, data_len), w.esc_uni));
            \\  if (w.stack.length === 0) w.root_done = true;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_finish")) {
        try writer.writeAll(
            \\function sa_json_writer_finish(writer, out_handle) {
            \\  __sa_store_i64(out_handle, 0n);
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  if (w.result !== null) { __sa_store_i64(out_handle, BigInt(w.result)); return 0; }
            \\  if (!w.root_done || w.stack.length !== 0) return 1;
            \\  const bytes = new globalThis.TextEncoder().encode(w.parts.join(""));
            \\  const h = __sa_jsonbufnext++;
            \\  __sa_jsonbufs.set(h, bytes);
            \\  w.result = h;
            \\  __sa_store_i64(out_handle, BigInt(h));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_finish_buffer")) {
        try writer.writeAll(
            \\function sa_json_writer_finish_buffer(writer) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 0n;
            \\  if (w.result !== null) return BigInt(w.result);
            \\  if (!w.root_done || w.stack.length !== 0) return 0n;
            \\  const bytes = new globalThis.TextEncoder().encode(w.parts.join(""));
            \\  const h = __sa_jsonbufnext++;
            \\  __sa_jsonbufs.set(h, bytes);
            \\  w.result = h;
            \\  return BigInt(h);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_free")) {
        try writer.writeAll(
            \\function sa_json_writer_free(writer) { __sa_jsonwriters.delete(__sa_num(writer)); return 0; }
            \\
        );
        return true;
    }
    return false;
}
