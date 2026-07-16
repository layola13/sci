pub fn assertBackend(comptime backend: type) void {
    const backend_name: []const u8 = backend.backend_name;
    const platform_reactor: []const u8 = backend.platform_reactor;
    const supports_native_reactor: bool = backend.supports_native_reactor;
    _ = backend_name;
    _ = platform_reactor;
    _ = supports_native_reactor;

    _ = &backend.sa_netx_init;
    _ = &backend.sa_netx_listen;
    _ = &backend.sa_netx_recv_ticket;
    _ = &backend.sa_netx_push_outbound;
    _ = &backend.sa_netx_broadcast;
    _ = &backend.sa_netx_close_slot;
    _ = &backend.sa_netx_shutdown;

    _ = &backend.sa_std_ws_accept_key;
    _ = &backend.sa_std_ws_frame_parse;
    _ = &backend.sa_std_ws_unmask;
    _ = &backend.sa_std_ws_frame_build;
    _ = &backend.sa_std_ws_frame_build_unmasked;
    _ = &backend.sa_std_url_parse;
}
