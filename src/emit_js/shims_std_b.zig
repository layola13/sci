const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_std_net_addr_reverse_lookup")) {
        try writer.writeAll(
            \\function sa_std_net_addr_reverse_lookup(addr, out, out_cap, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_len, 0n);
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!a || a.kind !== "addr") return 2;
            \\  const r = J.bridgeCall("reverse", { host: a.host }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  const name = J.bFromStr(r.json.name);
            \\  const cap = __sa_num(out_cap);
            \\  const n = Math.min(cap, name.length);
            \\  __sa_u8.set(name.subarray(0, n), __sa_addr(out));
            \\  __sa_store_i64(out_len, BigInt(n));
            \\  return (n < name.length) ? 9 : 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_interface_addresses_json")) {
        try writer.writeAll(
            \\function sa_std_net_interface_addresses_json(out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const bytes = J.netinfoJson();
            \\  const h = __sa_buf_open(bytes);
            \\  __sa_store_i64(out_handle, h);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt")) {
        try writer.writeAll(
            \\function sa_std_net_socket_getsockopt(handle, level, optname, out, out_cap, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  function sockoptApply(e, level, optname, value) {
            \\    const key = level + ":" + optname;
            \\    if (level === 1 && optname === 3) return 8;
            \\    const opmap = { "1:6": "udp_set_broadcast", "0:2": "udp_set_ttl", "0:33": "udp_set_multicast_ttl", "0:34": "udp_set_multicast_loop", "6:1": "tcp_set_nodelay", "1:9": "tcp_set_keepalive" };
            \\    const op = opmap[key];
            \\    if (!op) return 8;
            \\    if (op === "udp_set_broadcast" || op === "udp_set_multicast_loop" || op === "tcp_set_keepalive") {
            \\      if (e.kind !== "udp" && op !== "tcp_set_keepalive") return 8;
            \\      if (op === "tcp_set_keepalive" && e.kind !== "tcp") return 8;
            \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    } else if (op === "tcp_set_nodelay") {
            \\      if (e.kind !== "tcp") return 8;
            \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    } else {
            \\      if (e.kind !== "udp") return 8;
            \\      const field = (op === "udp_set_ttl" || op === "udp_set_multicast_ttl") ? "ttl" : "enabled";
            \\      const params = { id: e.bridgeId }; params[field] = value;
            \\      const r = J.bridgeCall(op, params, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    }
            \\    e.opts.set(key, value);
            \\    return 0;
            \\  }
            \\  function sockoptRead(e, level, optname) {
            \\    if (level === 1 && optname === 3) return e.kind === "udp" ? 2 : 1;
            \\    const v = e.opts.get(level + ":" + optname);
            \\    return (v === undefined) ? null : v;
            \\  }
            \\  __sa_store_i64(out_len, 0n);
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e || (e.kind !== "udp" && e.kind !== "tcp")) return 2;
            \\  const v = sockoptRead(e, __sa_num(level), __sa_num(optname));
            \\  if (v === null) return 8;
            \\  const cap = __sa_num(out_cap);
            \\  if (cap < 4) return 9;
            \\  __sa_view.setInt32(__sa_addr(out), v, true);
            \\  __sa_store_i64(out_len, 4n);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt_int")) {
        try writer.writeAll(
            \\function sa_std_net_socket_getsockopt_int(handle, level, optname, out_value) {
            \\  const J = globalThis.__sa_jsnet;
            \\  function sockoptApply(e, level, optname, value) {
            \\    const key = level + ":" + optname;
            \\    if (level === 1 && optname === 3) return 8;
            \\    const opmap = { "1:6": "udp_set_broadcast", "0:2": "udp_set_ttl", "0:33": "udp_set_multicast_ttl", "0:34": "udp_set_multicast_loop", "6:1": "tcp_set_nodelay", "1:9": "tcp_set_keepalive" };
            \\    const op = opmap[key];
            \\    if (!op) return 8;
            \\    if (op === "udp_set_broadcast" || op === "udp_set_multicast_loop" || op === "tcp_set_keepalive") {
            \\      if (e.kind !== "udp" && op !== "tcp_set_keepalive") return 8;
            \\      if (op === "tcp_set_keepalive" && e.kind !== "tcp") return 8;
            \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    } else if (op === "tcp_set_nodelay") {
            \\      if (e.kind !== "tcp") return 8;
            \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    } else {
            \\      if (e.kind !== "udp") return 8;
            \\      const field = (op === "udp_set_ttl" || op === "udp_set_multicast_ttl") ? "ttl" : "enabled";
            \\      const params = { id: e.bridgeId }; params[field] = value;
            \\      const r = J.bridgeCall(op, params, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    }
            \\    e.opts.set(key, value);
            \\    return 0;
            \\  }
            \\  function sockoptRead(e, level, optname) {
            \\    if (level === 1 && optname === 3) return e.kind === "udp" ? 2 : 1;
            \\    const v = e.opts.get(level + ":" + optname);
            \\    return (v === undefined) ? null : v;
            \\  }
            \\  __sa_store_i32(out_value, 0);
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e || (e.kind !== "udp" && e.kind !== "tcp")) return 2;
            \\  const v = sockoptRead(e, __sa_num(level), __sa_num(optname));
            \\  if (v === null) return 8;
            \\  __sa_store_i32(out_value, v);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt")) {
        try writer.writeAll(
            \\function sa_std_net_socket_setsockopt(handle, level, optname, value, value_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  function sockoptApply(e, level, optname, value) {
            \\    const key = level + ":" + optname;
            \\    if (level === 1 && optname === 3) return 8;
            \\    const opmap = { "1:6": "udp_set_broadcast", "0:2": "udp_set_ttl", "0:33": "udp_set_multicast_ttl", "0:34": "udp_set_multicast_loop", "6:1": "tcp_set_nodelay", "1:9": "tcp_set_keepalive" };
            \\    const op = opmap[key];
            \\    if (!op) return 8;
            \\    if (op === "udp_set_broadcast" || op === "udp_set_multicast_loop" || op === "tcp_set_keepalive") {
            \\      if (e.kind !== "udp" && op !== "tcp_set_keepalive") return 8;
            \\      if (op === "tcp_set_keepalive" && e.kind !== "tcp") return 8;
            \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    } else if (op === "tcp_set_nodelay") {
            \\      if (e.kind !== "tcp") return 8;
            \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    } else {
            \\      if (e.kind !== "udp") return 8;
            \\      const field = (op === "udp_set_ttl" || op === "udp_set_multicast_ttl") ? "ttl" : "enabled";
            \\      const params = { id: e.bridgeId }; params[field] = value;
            \\      const r = J.bridgeCall(op, params, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    }
            \\    e.opts.set(key, value);
            \\    return 0;
            \\  }
            \\  function sockoptRead(e, level, optname) {
            \\    if (level === 1 && optname === 3) return e.kind === "udp" ? 2 : 1;
            \\    const v = e.opts.get(level + ":" + optname);
            \\    return (v === undefined) ? null : v;
            \\  }
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e || (e.kind !== "udp" && e.kind !== "tcp")) return 2;
            \\  const lv = __sa_num(level), on = __sa_num(optname);
            \\  const bytes = __sa_mem_bytes(value, value_len);
            \\  if (bytes.length < 4) return 1;
            \\  const v = (bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24));
            \\  return sockoptApply(e, lv, on, v);
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt_int")) {
        try writer.writeAll(
            \\function sa_std_net_socket_setsockopt_int(handle, level, optname, value) {
            \\  const J = globalThis.__sa_jsnet;
            \\  function sockoptApply(e, level, optname, value) {
            \\    const key = level + ":" + optname;
            \\    if (level === 1 && optname === 3) return 8;
            \\    const opmap = { "1:6": "udp_set_broadcast", "0:2": "udp_set_ttl", "0:33": "udp_set_multicast_ttl", "0:34": "udp_set_multicast_loop", "6:1": "tcp_set_nodelay", "1:9": "tcp_set_keepalive" };
            \\    const op = opmap[key];
            \\    if (!op) return 8;
            \\    if (op === "udp_set_broadcast" || op === "udp_set_multicast_loop" || op === "tcp_set_keepalive") {
            \\      if (e.kind !== "udp" && op !== "tcp_set_keepalive") return 8;
            \\      if (op === "tcp_set_keepalive" && e.kind !== "tcp") return 8;
            \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    } else if (op === "tcp_set_nodelay") {
            \\      if (e.kind !== "tcp") return 8;
            \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    } else {
            \\      if (e.kind !== "udp") return 8;
            \\      const field = (op === "udp_set_ttl" || op === "udp_set_multicast_ttl") ? "ttl" : "enabled";
            \\      const params = { id: e.bridgeId }; params[field] = value;
            \\      const r = J.bridgeCall(op, params, null, false);
            \\      if (r.status !== 0) return r.status;
            \\    }
            \\    e.opts.set(key, value);
            \\    return 0;
            \\  }
            \\  function sockoptRead(e, level, optname) {
            \\    if (level === 1 && optname === 3) return e.kind === "udp" ? 2 : 1;
            \\    const v = e.opts.get(level + ":" + optname);
            \\    return (v === undefined) ? null : v;
            \\  }
            \\  const e = J.netGet(__sa_num(handle));
            \\  if (!e || (e.kind !== "udp" && e.kind !== "tcp")) return 2;
            \\  return sockoptApply(e, __sa_num(level), __sa_num(optname), __sa_num(value));
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_connect(host, host_len, port, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.bridgeCall("tcp_connect", { host: h, port: __sa_num(port), timeoutMs: 0 }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  const e = { kind: "tcp", bridgeId: r.json.id, localHost: r.json.local.host, localPort: r.json.local.port,
            \\    peerHost: r.json.peer.host, peerPort: r.json.peer.port,
            \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
            \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_connect_timeout(host, host_len, port, timeout_ns, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.bridgeCall("tcp_connect", { host: h, port: __sa_num(port), timeoutMs: __sa_num(timeout_ns) / 1000000 }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  const e = { kind: "tcp", bridgeId: r.json.id, localHost: r.json.local.host, localPort: r.json.local.port,
            \\    peerHost: r.json.peer.host, peerPort: r.json.peer.port,
            \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
            \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout_addr")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_connect_timeout_addr(addr, timeout_ns, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!a || a.kind !== "addr") return 2;
            \\  const r = J.bridgeCall("tcp_connect", { host: a.host, port: a.port, timeoutMs: __sa_num(timeout_ns) / 1000000 }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  const e = { kind: "tcp", bridgeId: r.json.id, localHost: r.json.local.host, localPort: r.json.local.port,
            \\    peerHost: r.json.peer.host, peerPort: r.json.peer.port,
            \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
            \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout_all")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_connect_timeout_all(host, host_len, port, timeout_ns, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // Best-effort alias of connect_timeout: Node resolves and tries the
            \\  // address family selection itself (autoSelectFamily).
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.bridgeCall("tcp_connect", { host: h, port: __sa_num(port), timeoutMs: __sa_num(timeout_ns) / 1000000 }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  const e = { kind: "tcp", bridgeId: r.json.id, localHost: r.json.local.host, localPort: r.json.local.port,
            \\    peerHost: r.json.peer.host, peerPort: r.json.peer.port,
            \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
            \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_read")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_stream_read(stream, buf, cap, out_read) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_read, 0n);
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
            \\  const r = J.bridgeCall("stream_read", { id: e.bridgeId, cap: __sa_num(cap) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  if (r.bytes) __sa_u8.set(r.bytes, __sa_addr(buf));
            \\  __sa_store_i64(out_read, BigInt(r.json.read || 0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_read_timeout")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_stream_read_timeout(stream, out_timeout_ns) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_timeout_ns, 0n);
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
            \\  __sa_store_i64(out_timeout_ns, BigInt(Math.round(e.readTimeoutMs * 1000000)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_keepalive")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_stream_set_keepalive(stream, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e || e.kind !== "tcp") return 2;
            \\  const r = J.bridgeCall("tcp_set_keepalive", { id: e.bridgeId, enabled: __sa_num(enabled) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  e.opts.set("1:9", __sa_num(enabled) !== 0 ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_nodelay")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_stream_set_nodelay(stream, enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e || e.kind !== "tcp") return 2;
            \\  const r = J.bridgeCall("tcp_set_nodelay", { id: e.bridgeId, enabled: __sa_num(enabled) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  e.opts.set("6:1", __sa_num(enabled) !== 0 ? 1 : 0);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_read_timeout")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_stream_set_read_timeout(stream, timeout_ns) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
            \\  const ms = __sa_num(timeout_ns) / 1000000;
            \\  e.readTimeoutMs = ms;
            \\  const r = J.bridgeCall("stream_set_read_timeout", { id: e.bridgeId, timeoutMs: ms }, null, false);
            \\  return r.status;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_write_timeout")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_stream_set_write_timeout(stream, timeout_ns) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
            \\  const ms = __sa_num(timeout_ns) / 1000000;
            \\  e.writeTimeoutMs = ms;
            \\  const r = J.bridgeCall("stream_set_write_timeout", { id: e.bridgeId, timeoutMs: ms }, null, false);
            \\  return r.status;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_write")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_stream_write(stream, buf, len, out_written) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_written, 0n);
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
            \\  const payload = __sa_mem_bytes(buf, len);
            \\  const r = J.bridgeCall("stream_write", { id: e.bridgeId }, payload, false);
            \\  if (r.status !== 0) return r.status;
            \\  __sa_store_i64(out_written, BigInt(r.json.written || 0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_write_timeout")) {
        try writer.writeAll(
            \\function sa_std_net_tcp_stream_write_timeout(stream, out_timeout_ns) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_timeout_ns, 0n);
            \\  const e = J.netGet(__sa_num(stream));
            \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
            \\  __sa_store_i64(out_timeout_ns, BigInt(Math.round(e.writeTimeoutMs * 1000000)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_to_socket_addr_first")) {
        try writer.writeAll(
            \\function sa_std_net_to_socket_addr_first(host, host_len, port, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  function addrFromWorker(a, port) {
            \\    return { kind: "addr", host: a.host, port: port, family: (a.family === 4 || a.family === "IPv4") ? 2 : 10, scopeId: 0 };
            \\  }
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.bridgeCall("resolve", { host: h }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  if (!r.json.addrs || r.json.addrs.length === 0) return 7;
            \\  const a = addrFromWorker(r.json.addrs[0], __sa_num(port));
            \\  __sa_store_i64(out_handle, BigInt(J.netReg(a)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_to_socket_addr_list")) {
        try writer.writeAll(
            \\function sa_std_net_to_socket_addr_list(host, host_len, port, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  function addrFromWorker(a, port) {
            \\    return { kind: "addr", host: a.host, port: port, family: (a.family === 4 || a.family === "IPv4") ? 2 : 10, scopeId: 0 };
            \\  }
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.bridgeCall("resolve", { host: h }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  const addrs = (r.json.addrs || []).map((a) => addrFromWorker(a, __sa_num(port)));
            \\  __sa_store_i64(out_handle, BigInt(J.netReg({ kind: "addrlist", addrs: addrs, idx: 0 })));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_bind")) {
        try writer.writeAll(
            \\function sa_std_net_udp_bind(host, host_len, port, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.bridgeCall("udp_bind", { host: h, port: __sa_num(port) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  const e = { kind: "udp", bridgeId: r.json.id, localHost: r.json.host, localPort: r.json.port,
            \\    localFamily: (r.json.family === "IPv4" || r.json.family === 4) ? 2 : 10,
            \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
            \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_broadcast")) {
        try writer.writeAll(
            \\function sa_std_net_udp_broadcast(socket, out_enabled) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i32(out_enabled, 0);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const v = e.opts.get("1:6");
            \\  if (v === undefined) return 8;
            \\  __sa_store_i32(out_enabled, v);
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_connect")) {
        try writer.writeAll(
            \\function sa_std_net_udp_connect(socket, host, host_len, port) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
            \\  const r = J.bridgeCall("udp_connect", { id: e.bridgeId, host: h, port: __sa_num(port) }, null, false);
            \\  return r.status;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_connect_addr")) {
        try writer.writeAll(
            \\function sa_std_net_udp_connect_addr(socket, addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const e = J.netGet(__sa_num(socket));
            \\  const a = J.netGet(__sa_num(addr));
            \\  if (!e || e.kind !== "udp" || !a || a.kind !== "addr") return 2;
            \\  const r = J.bridgeCall("udp_connect", { id: e.bridgeId, host: a.host, port: a.port }, null, false);
            \\  return r.status;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_local_addr")) {
        try writer.writeAll(
            \\function sa_std_net_udp_local_addr(socket, out_handle) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_handle, 0n);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const a = { kind: "addr", host: e.localHost, port: e.localPort, family: e.localFamily, scopeId: 0 };
            \\  __sa_store_i64(out_handle, BigInt(J.netReg(a)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv")) {
        try writer.writeAll(
            \\function sa_std_net_udp_recv(socket, buf, cap, out_read) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_read, 0n);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const r = J.bridgeCall("udp_recv", { id: e.bridgeId, cap: __sa_num(cap) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  if (r.bytes) __sa_u8.set(r.bytes, __sa_addr(buf));
            \\  __sa_store_i64(out_read, BigInt(r.json.read || 0));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_from")) {
        try writer.writeAll(
            \\function sa_std_net_udp_recv_from(socket, buf, cap, out_read, out_addr) {
            \\  const J = globalThis.__sa_jsnet;
            \\  __sa_store_i64(out_read, 0n);
            \\  __sa_store_i64(out_addr, 0n);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  const r = J.bridgeCall("udp_recv", { id: e.bridgeId, cap: __sa_num(cap) }, null, false);
            \\  if (r.status !== 0) return r.status;
            \\  if (r.bytes) __sa_u8.set(r.bytes, __sa_addr(buf));
            \\  __sa_store_i64(out_read, BigInt(r.json.read || 0));
            \\  const s = r.json.src;
            \\  const a = { kind: "addr", host: s.host, port: s.port, family: (s.family === "IPv4" || s.family === 4) ? 2 : 10, scopeId: 0 };
            \\  __sa_store_i64(out_addr, BigInt(J.netReg(a)));
            \\  return 0;
            \\}
            \\
        );
        return true;
    }
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_msg")) {
        try writer.writeAll(
            \\function sa_std_net_udp_recv_msg(socket, buf, cap, out_read, out_addr, out_dest_addr, out_ifindex, out_timestamp_ns, out_flags) {
            \\  const J = globalThis.__sa_jsnet;
            \\  // No pktinfo / SO_TIMESTAMP in Node: explicit UNSUPPORTED.
            \\  __sa_store_i64(out_read, 0n);
            \\  __sa_store_i64(out_addr, 0n);
            \\  __sa_store_i64(out_dest_addr, 0n);
            \\  __sa_store_i64(out_ifindex, 0n);
            \\  __sa_store_i64(out_timestamp_ns, 0n);
            \\  __sa_store_i64(out_flags, 0n);
            \\  const e = J.netGet(__sa_num(socket));
            \\  if (!e || e.kind !== "udp") return 2;
            \\  return 8;
            \\}
            \\
        );
        return true;
    }
    return false;
}
