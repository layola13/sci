const std = @import("std");

pub fn emitTlscfgSetVerifySelfSigned(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_set_verify_self_signed(a0, (uint32_t)a1); }\n");
}

pub fn emitTlsPeerCertJson(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_tls_client_peer_cert_json(a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTlsShapedSupported(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t v = 0; int32_t st = sa_std_tls_shaped_supported(&v); sa_store_u32(a0, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTlsShapedConnect(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Pre-dial profile validation happens inside libsa_std.a
    // (a malformed profile is -22 before any socket is opened),
    // so forwarding preserves the no-network test contract.
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_tls_shaped_connect(sa_glue_cptr(a0, a1), a1, (uint32_t)a2, sa_glue_cptr(a3, a4), a4, &v); sa_store_u64(a5, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTlsCbufData(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // The native accessor returns a host pointer into the
    // buffer's bytes; the guest form copies the bytes into a
    // fresh guest allocation and returns its address (the
    // copy is never invalidated, unlike the native borrow).
    try writer.writeAll(" { uint64_t n = sa_std_tls_client_buffer_len(a0); const uint8_t *hp = sa_std_tls_client_buffer_data(a0); if (hp == 0) return 0; { sa_u64 g = sa_alloc(n == 0 ? 1 : n); uint32_t d = sa_checked_addr(g, (size_t)(n == 0 ? 1 : n)); if (n != 0) memcpy(&sa_mem[d], hp, (size_t)n); return g; } } }\n");
}

pub fn emitTlsCbufLen(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return sa_std_tls_client_buffer_len(a0); }\n");
}

pub fn emitTlsCbufFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_buffer_free(a0); }\n");
}

pub fn emitNaFormat(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t n = 0; int32_t st = sa_std_net_addr_format(a0, sa_glue_mptr(a1, a2), a2, &n); sa_store_u64(a3, n); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitSkGet(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Direct link: the real getsockopt syscall wrapper in
    // libsa_std.a runs against the real socket behind the
    // handle; only the out span is guest memory.
    try writer.writeAll(" { uint64_t n = 0; int32_t st = sa_std_net_socket_getsockopt(a0, (int32_t)a1, (uint32_t)a2, sa_glue_mptr(a3, a4), a4, &n); sa_store_u64(a5, n); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitSkGetInt(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { int32_t v = 0; int32_t st = sa_std_net_socket_getsockopt_int(a0, (int32_t)a1, (uint32_t)a2, &v); sa_store_u32(a3, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitSkSet(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_net_socket_setsockopt(a0, (int32_t)a1, (uint32_t)a2, sa_glue_cptr(a3, a4), a4); }\n");
}

pub fn emitSkSetInt(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_net_socket_setsockopt_int(a0, (int32_t)a1, (uint32_t)a2, (int32_t)a3); }\n");
}

pub fn emitNaToFirst(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_net_to_socket_addr_first(sa_glue_cptr(a0, a1), a1, (uint32_t)a2, &v); sa_store_u64(a3, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUdpBindH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_net_udp_bind(sa_glue_cptr(a0, a1), a1, (uint32_t)a2, &v); sa_store_u64(a3, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUdpBroadcastH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { int32_t v = 0; int32_t st = sa_std_net_udp_broadcast(a0, &v); sa_store_u32(a1, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUdpConnectAddrH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_net_udp_connect_addr(a0, a1); }\n");
}

pub fn emitUdpLocalAddrH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_net_udp_local_addr(a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUdpRecvMsgH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t rd = 0, saddr = 0, daddr = 0, ts = 0; uint32_t ix = 0, fl = 0; int32_t st = sa_std_net_udp_recv_msg(a0, sa_glue_mptr(a1, a2), a2, &rd, &saddr, &daddr, &ix, &ts, &fl); sa_store_u64(a3, rd); sa_store_u64(a4, saddr); sa_store_u64(a5, daddr); sa_store_u32(a6, (sa_u64)ix); sa_store_u64(a7, ts); sa_store_u32(a8, (sa_u64)fl); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUdpRecvMultiH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // The lens/addrs out arrays are staged in host scratch
    // and stored back element-wise (guest slots are byte
    // addressed; a direct uint64_t* cast would assume guest
    // alignment the SA allocator does not guarantee).
    try writer.writeAll(" { uint64_t cnt = 0; uint64_t *lens = (uint64_t *)malloc((a4 == 0 ? 1 : a4) * 8); uint64_t *addrs = (uint64_t *)malloc((a4 == 0 ? 1 : a4) * 8); if (lens == 0 || addrs == 0) { free(lens); free(addrs); return 5; } { int32_t st = sa_std_net_udp_recv_multi(a0, sa_glue_mptr(a1, a2), a2, a3, a4, &cnt, lens, addrs); sa_u64 i; for (i = 0; i < cnt; i++) { sa_store_u64(a6 + i * 8, lens[i]); sa_store_u64(a7 + i * 8, addrs[i]); } free(lens); free(addrs); sa_store_u64(a5, cnt); return (sa_u64)(sa_i64)st; } } }\n");
}

pub fn emitUdpSendH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t w = 0; int32_t st = sa_std_net_udp_send(a0, sa_glue_cptr(a1, a2), a2, &w); sa_store_u64(a3, w); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUdpSetReadTimeoutH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_net_udp_set_read_timeout(a0, a1); }\n");
}

pub fn emitUdpTtlH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t v = 0; int32_t st = sa_std_net_udp_ttl(a0, &v); sa_store_u32(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUnixPairH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t l = 0, r = 0; int32_t st = sa_std_net_unix_datagram_pair(&l, &r); sa_store_u64(a0, l); sa_store_u64(a1, r); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUnixPeerCredH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { int32_t pid = 0; uint32_t uid = 0, gid = 0; int32_t st = sa_std_net_unix_datagram_peer_cred(a0, &pid, &uid, &gid); sa_store_u32(a1, (sa_u64)(uint32_t)pid); sa_store_u32(a2, (sa_u64)uid); sa_store_u32(a3, (sa_u64)gid); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitUnixUnboundH(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_net_unix_datagram_unbound(&v); sa_store_u64(a0, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitProcId(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)sa_std_process_id(); }\n");
}

pub fn emitProcUserId(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" return (sa_u64)sa_std_process_user_id(); }\n");
}

pub fn emitNetUnsupported8(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { return 8; } }\n");
}

pub fn emitModstateGetU64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_u64 i; for (i = 0; i < SA_MODSTATE_MAX; i++)");
    try writer.writeAll(" if (sa_modstate_used[i] && sa_modstate_keys[i] == a0)");
    try writer.writeAll(" return sa_modstate_vals[i]; return 0; } }\n");
}

pub fn emitModstateSetU64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_u64 i; for (i = 0; i < SA_MODSTATE_MAX; i++)");
    try writer.writeAll(" if (sa_modstate_used[i] && sa_modstate_keys[i] == a0)");
    try writer.writeAll(" { sa_modstate_vals[i] = a1; return 0; }");
    try writer.writeAll(" for (i = 0; i < SA_MODSTATE_MAX; i++)");
    try writer.writeAll(" if (!sa_modstate_used[i])");
    try writer.writeAll(" { sa_modstate_used[i] = 1; sa_modstate_keys[i] = a0;");
    try writer.writeAll(" sa_modstate_vals[i] = a1; return 0; } return 5; } }\n");
}
