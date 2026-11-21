const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_multi")) {
        try writer.writeAll(
            \\function sa_std_net_udp_recv_multi(socket, buf, buf_cap, slot_size, max_msgs, out_count, out_lens, out_addrs) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // No recvmmsg in Node: explicit UNSUPPORTED.
            \\  __sa_store_i64(out_count, 0n);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  return 8;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_send")) {
        try writer.writeAll(
            \\function sa_std_net_udp_send(socket, buf, len, out_written) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_written, 0n);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const payload = __sa_mem_bytes(buf, len);
            \\  const r = J.bridgeCall("udp_send", { id: e.bridgeId }, payload, false);
            \\  if (r.status !== 0) return r.status;
            \\  __sa_store_i64(out_written, BigInt(r.json.written || 0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_send_to")) {
        try writer.writeAll(
            \\function sa_std_net_udp_send_to(socket, buf, len, host, host_len, port, out_written) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_written, 0n);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const payload = __sa_mem_bytes(buf, len);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.bridgeCall("udp_send", { id: e.bridgeId, dest: { host: h, port: __sa_num(port) } }, payload, false);
            \\  if (r.status !== 0) return r.status;
            \\  __sa_store_i64(out_written, BigInt(r.json.written || 0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_broadcast")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_broadcast(socket, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const r = J.bridgeCall("udp_set_broadcast", { id: e.bridgeId, enabled: __sa_num(enabled) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  e.opts.set("1:6", __sa_num(enabled) !== 0 ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_hops_v6")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_multicast_hops_v6(socket, hops) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // No Node API for IPv6 multicast hops on a bound socket: explicit UNSUPPORTED.
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  return 8;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_loop_v4")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_multicast_loop_v4(socket, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const r = J.bridgeCall("udp_set_multicast_loop", { id: e.bridgeId, enabled: __sa_num(enabled) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  e.opts.set("0:34", __sa_num(enabled) !== 0 ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_loop_v6")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_multicast_loop_v6(socket, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // No Node API for IPv6 multicast loop on a bound socket: explicit UNSUPPORTED.
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  return 8;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_ttl_v4")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_multicast_ttl_v4(socket, ttl) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const r = J.bridgeCall("udp_set_multicast_ttl", { id: e.bridgeId, ttl: __sa_num(ttl) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  e.opts.set("0:33", __sa_num(ttl));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_nonblocking")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_nonblocking(socket, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // The bridge model is blocking-only (worker queue + Atomics.wait).
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  return 8;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_only_v6")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_only_v6(socket, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // Socket family is fixed at bind time; it cannot change afterwards.
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  return 8;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_read_timeout")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_read_timeout(socket, timeout_ns) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const ms = __sa_num(timeout_ns) / 1000000;
            \\  e.readTimeoutMs = ms;
            \\  const r = J.bridgeCall("udp_set_read_timeout", { id: e.bridgeId, timeoutMs: ms }, null, false);
            \\  return r.status;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_ttl")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_ttl(socket, ttl) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const r = J.bridgeCall("udp_set_ttl", { id: e.bridgeId, ttl: __sa_num(ttl) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  e.opts.set("0:2", __sa_num(ttl));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_write_timeout")) {
        try writer.writeAll(
            \\function sa_std_net_udp_set_write_timeout(socket, timeout_ns) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  e.writeTimeoutMs = __sa_num(timeout_ns) / 1000000;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_ttl")) {
        try writer.writeAll(
            \\function sa_std_net_udp_ttl(socket, out_ttl) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_u32(out_ttl, 0);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const v = e.opts.get("0:2");
            \\  if (v === undefined) return 8;
            \\  __sa_store_u32(out_ttl, v);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_peer_cred")) {
        try writer.writeAll(
            \\function sa_std_net_unix_datagram_peer_cred(socket, out_pid, out_uid, out_gid) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // No peer-credentials API in Node: explicit UNSUPPORTED.
            \\  __sa_store_i64(out_pid, 0n);
            \\  __sa_store_i64(out_uid, 0n);
            \\  __sa_store_i64(out_gid, 0n);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e) return 2;
            \\  return 8;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_unix_stream_peer_cred")) {
        try writer.writeAll(
            \\function sa_std_net_unix_stream_peer_cred(stream, out_pid, out_uid, out_gid) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // No peer-credentials API in Node: explicit UNSUPPORTED.
            \\  __sa_store_i64(out_pid, 0n);
            \\  __sa_store_i64(out_uid, 0n);
            \\  __sa_store_i64(out_gid, 0n);
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e) return 2;
            \\  return 8;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_auth_keyfile")) {
        try writer.writeAll("function sa_std_ssh_auth_keyfile() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_auth_password")) {
        try writer.writeAll("function sa_std_ssh_auth_password() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_buffer_data")) {
        try writer.writeAll("function sa_std_ssh_buffer_data(buffer) { return 0; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_buffer_free")) {
        try writer.writeAll("function sa_std_ssh_buffer_free() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_buffer_len")) {
        try writer.writeAll("function sa_std_ssh_buffer_len(buffer) { return BigInt(0); }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_channel_close")) {
        try writer.writeAll("function sa_std_ssh_channel_close() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_channel_read")) {
        try writer.writeAll("function sa_std_ssh_channel_read() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_channel_send_exit")) {
        try writer.writeAll("function sa_std_ssh_channel_send_exit() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_channel_write")) {
        try writer.writeAll("function sa_std_ssh_channel_write() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_client_connect")) {
        try writer.writeAll("function sa_std_ssh_client_connect(host, host_len, port, out_session) { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_exec")) {
        try writer.writeAll("function sa_std_ssh_exec(session, command, command_len, out_stdout, out_stderr, out_exit) { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_hostkey_fingerprint")) {
        try writer.writeAll("function sa_std_ssh_hostkey_fingerprint() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_accept")) {
        try writer.writeAll("function sa_std_ssh_server_accept() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_accept")) {
        try writer.writeAll("function sa_std_ssh_server_auth_accept() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_deny")) {
        try writer.writeAll("function sa_std_ssh_server_auth_deny() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_next")) {
        try writer.writeAll("function sa_std_ssh_server_auth_next() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_bind_close")) {
        try writer.writeAll("function sa_std_ssh_server_bind_close() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_channel_accept")) {
        try writer.writeAll("function sa_std_ssh_server_channel_accept() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_channel_exec")) {
        try writer.writeAll("function sa_std_ssh_server_channel_exec() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_listen")) {
        try writer.writeAll("function sa_std_ssh_server_listen() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_server_session_close")) {
        try writer.writeAll("function sa_std_ssh_server_session_close() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_session_close")) {
        try writer.writeAll("function sa_std_ssh_session_close() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_sftp_read")) {
        try writer.writeAll("function sa_std_ssh_sftp_read() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_sftp_stat")) {
        try writer.writeAll("function sa_std_ssh_sftp_stat() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_sftp_write")) {
        try writer.writeAll("function sa_std_ssh_sftp_write() { return 8; }\n");
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_ssh_supported")) {
        try writer.writeAll(
            \\function sa_std_ssh_supported(out_flags) {
            \\  __sa_store_i64(out_flags, BigInt(0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_add_ca_file")) {
        try writer.writeAll(
            \\function sa_std_tls_client_add_ca_file(path, path_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const p = __sa_mem_bytes(path, path_len);
            \\  const s = J.bToStr(p);
            \\  if (s.length === 0 || s[0] !== "/") return -22;
            \\  try {
            \\    const fs = __sa_node_builtin("node:fs");
            \\    J.TLS.processCas.push(fs.readFileSync(s, "utf8"));
            \\  } catch (e) { return -5; }
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_data")) {
        try writer.writeAll(
            \\function sa_std_tls_client_buffer_data(buffer) {
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
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_free")) {
        try writer.writeAll(
            \\function sa_std_tls_client_buffer_free(buffer) {
            \\  const J = globalThis.__sa_jsnet;
            \\  return __sa_buffers.delete(__sa_num(buffer)) ? 0 : -22;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_len")) {
        try writer.writeAll(
            \\function sa_std_tls_client_buffer_len(buffer) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const b = __sa_buf_get(buffer);
            \\  return b === null ? 0n : BigInt(b.length);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_close")) {
        try writer.writeAll(
            \\function sa_std_tls_client_close(handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e || e.kind !== "tls") return -22;
            \\  J.bridgeCall("sock_close", { id: e.bridgeId }, null, true);
            \\  J.netDel(__sa_num(handle));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_file")) {
        try writer.writeAll(
            \\function sa_std_tls_client_config_add_ca_file(config, path, path_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.tlsCfgGet(__sa_num(config));
            \\  if (!c) return -22;
            \\  const p = __sa_mem_bytes(path, path_len);
            \\  const s = J.bToStr(p);
            \\  if (s.length === 0 || s[0] !== "/") return -22;
            \\  c.caFiles.push(p.slice());
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_memory")) {
        try writer.writeAll(
            \\function sa_std_tls_client_config_add_ca_memory(config, pem, pem_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.tlsCfgGet(__sa_num(config));
            \\  if (!c) return -22;
            \\  const p = __sa_mem_bytes(pem, pem_len);
            \\  if (p.length === 0) return -22;
            \\  const n = J.pemUsableCount(J.bToStr(p));
            \\  if (n <= 0) return -22;
            \\  c.caPems.push(J.bToStr(p));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_free")) {
        try writer.writeAll(
            \\function sa_std_tls_client_config_free(config) {
            \\  const J = globalThis.__sa_jsnet;
            \\  if (__sa_num(config) === 0) return 0;
            \\  J.tlsCfgFree(__sa_num(config));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_new")) {
        try writer.writeAll(
            \\function sa_std_tls_client_config_new(out_config) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_config, 0n);
            \\  __sa_store_i64(out_config, BigInt(J.tlsCfgNew()));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_insecure_no_verification")) {
        try writer.writeAll(
            \\function sa_std_tls_client_config_set_insecure_no_verification(config, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.tlsCfgGet(__sa_num(config));
            \\  if (!c) return -22;
            \\  c.insecure = __sa_num(enabled) !== 0;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_server_name")) {
        try writer.writeAll(
            \\function sa_std_tls_client_config_set_server_name(config, name, name_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.tlsCfgGet(__sa_num(config));
            \\  if (!c) return -22;
            \\  const n = __sa_mem_bytes(name, name_len);
            \\  c.serverName = (n.length === 0) ? null : n.slice();
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_verify_self_signed")) {
        try writer.writeAll(
            \\function sa_std_tls_client_config_set_verify_self_signed(config, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.tlsCfgGet(__sa_num(config));
            \\  if (!c) return -22;
            \\  c.verifySelfSigned = __sa_num(enabled) !== 0;
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_connect")) {
        try writer.writeAll(
            \\function sa_std_tls_client_connect(host, host_len, port, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.tlsConnectFull(h, __sa_num(port), null, null);
            \\  if (r.status !== 0) return r.status;
            \\  __sa_store_i64(out_handle, BigInt(r.saHandle));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_connect_config")) {
        try writer.writeAll(
            \\function sa_std_tls_client_connect_config(host, host_len, port, config, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  let cfg = null;
            \\  if (__sa_num(config) !== 0) {
            \\    cfg = J.tlsCfgGet(__sa_num(config));
            \\    if (!cfg) return -22;
            \\  }
            \\  const r = J.tlsConnectFull(h, __sa_num(port), cfg, null);
            \\  if (r.status !== 0) return r.status;
            \\  __sa_store_i64(out_handle, BigInt(r.saHandle));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_peer_cert_json")) {
        try writer.writeAll(
            \\function sa_std_tls_client_peer_cert_json(handle, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // UNSUPPORTED by construction on this backend too (std.crypto.tls does
            \\  // not retain the peer certificate; Node could, but the contract mirrors
            \\  // native exactly): handle 0 -> -22, anything else -> -1, out untouched.
            \\  if (__sa_num(handle) === 0) return -22;
            \\  return -1;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_read")) {
        try writer.writeAll(
            \\function sa_std_tls_client_read(handle, buf, cap, out_read) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_read, 0n);
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e || e.kind !== "tls") return -22;
            \\  const r = J.bridgeCall("stream_read", { id: e.bridgeId, cap: __sa_num(cap), tlsSpace: true }, null, true);
            \\  if (r.status !== 0) return r.status;
            \\  if (r.bytes) __sa_u8.set(r.bytes, __sa_addr(buf));
            \\  __sa_store_i64(out_read, BigInt(r.json.read || 0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_tls_client_start_tls")) {
        try writer.writeAll(
            \\function sa_std_tls_client_start_tls(fd, host, host_len, config, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  let cfg = null;
            \\  if (__sa_num(config) !== 0) {
            \\    cfg = J.tlsCfgGet(__sa_num(config));
            \\    if (!cfg) return -22;
            \\  }
            \\  const r = J.tlsConnectFull(h, 0, cfg, __sa_num(fd));
            \\  // The port comes from the existing connection; the chunk skips the
            \\  // port check on the upgrade branch.
            \\  if (r.status !== 0) return r.status;
            \\  __sa_store_i64(out_handle, BigInt(r.saHandle));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    return false;
}
