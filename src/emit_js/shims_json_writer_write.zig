const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_json_writer_new")) {
        try writer.writeAll(
            \\function sa_json_writer_new(whitespace, e_null, e_arr, esc_uni, e_nonport, out_handle) {
            \\  __sa_store_i64(out_handle, 0n);
            \\  if (__sa_num(whitespace) !== 0) return 1;
            \\  const h = __sa_jsonwriternext++;
            \\  __sa_jsonwriters.set(h, { parts: [], stack: [], root_done: false, result: null, esc_uni: __sa_num(esc_uni) !== 0 });
            \\  __sa_store_i64(out_handle, BigInt(h));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_object_field")) {
        try writer.writeAll(
            \\function sa_json_writer_object_field(writer, key_ptr, key_len) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_write_bool")) {
        try writer.writeAll(
            \\function sa_json_writer_write_bool(writer, value) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_scalar(w, __sa_num(value) !== 0 ? "true" : "false");
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_write_f64")) {
        try writer.writeAll(
            \\function sa_json_writer_write_f64(writer, value) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_scalar(w, __sa_json_f64_str(value));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_write_i64")) {
        try writer.writeAll(
            \\function sa_json_writer_write_i64(writer, value) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_scalar(w, BigInt.asIntN(64, BigInt(__sa_num(value))).toString(10));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_write_null")) {
        try writer.writeAll(
            \\function sa_json_writer_write_null(writer) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_scalar(w, "null");
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_json_writer_write_string")) {
        try writer.writeAll(
            \\function sa_json_writer_write_string(writer, data_ptr, data_len) {
            \\  const w = __sa_jsonwriters.get(__sa_num(writer));
            \\  if (w === undefined) return 2;
            \\  return __sa_jw_scalar(w, __sa_json_quote(__sa_mem_bytes(data_ptr, data_len), w.esc_uni));
            \\}
            \\
        );
        return true;
    }
    return false;
}
