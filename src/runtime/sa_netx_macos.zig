const core = @import("sa_netx_kqueue.zig");
const pal = @import("pal_macos.zig");

pub usingnamespace core;

test "macOS NetX backend is bound to native kqueue socket I/O and the kqueue PAL surface" {
    _ = core.backend_name;
    _ = core.platform_reactor;
    _ = core.supports_native_reactor;
    _ = &pal.event_loop_create;
    _ = &pal.event_loop_submit;
    _ = &pal.event_loop_wait;
    _ = &pal.event_loop_close;
    _ = &core.sa_netx_init;
}
