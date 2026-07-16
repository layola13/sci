const core = @import("sa_netx_iocp.zig");
const pal = @import("pal_windows.zig");

pub usingnamespace core;

test "Windows NetX backend is bound to native IOCP socket I/O and the IOCP PAL surface" {
    _ = core.backend_name;
    _ = core.platform_reactor;
    _ = core.supports_native_reactor;
    _ = &pal.event_loop_create;
    _ = &pal.event_loop_submit;
    _ = &pal.event_loop_wait;
    _ = &pal.event_loop_close;
    _ = &core.sa_netx_init;
}
