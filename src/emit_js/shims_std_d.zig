const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_std_tls_client_status_json")) {
        try writer.writeAll(
            \\function sa_std_tls_client_status_json(out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const text = JSON.stringify({ module: "tls_client", backend: "node:tls", supported: true, protocolMachine: true });
            \\  const h = __sa_buf_open(new globalThis.TextEncoder().encode(text));
            \\  __sa_store_i64(out_handle, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_supported")) {
        try writer.writeAll(
            \\function sa_std_tls_client_supported(out_supported) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_u32(out_supported, 1);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_write")) {
        try writer.writeAll(
            \\function sa_std_tls_client_write(handle, buf, len, out_written) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_written, 0n);
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e || e.kind !== "tls") return -22;
            \\  const payload = __sa_mem_bytes(buf, len);
            \\  const r = J.bridgeCall("stream_write", { id: e.bridgeId, tlsSpace: true }, payload, true);
            \\  if (r.status !== 0) return r.status;
            \\  __sa_store_i64(out_written, BigInt(r.json.written || 0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_data")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_buffer_data(buffer) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_free")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_buffer_free(buffer) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return -22;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_len")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_buffer_len(buffer) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return 0n;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_close")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_close(handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_connect")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_connect(host, host_len, port, profile, profile_len, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja3")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_hello_ja3(handle, out, out_cap, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_len, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja3_string")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_hello_ja3_string(handle, out, out_cap, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_len, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja4")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_hello_ja4(handle, out, out_cap, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_len, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_negotiated_json")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_negotiated_json(handle, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_peer_cert_chain_json")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_peer_cert_chain_json(handle, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_read")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_read(handle, buf, cap, out_read) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_read, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_session_blob")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_session_blob(handle, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_start_tls")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_start_tls(fd, host, host_len, profile, profile_len, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_supported")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_supported(out_supported) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_u32(out_supported, 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_write")) {
        try writer.writeAll(
            \\function sa_std_tls_shaped_write(handle, buf, len, out_written) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_written, 0n);
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    return false;
}
