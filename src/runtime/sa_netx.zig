const std = @import("std");
const builtin = @import("builtin");
const backend_contract = @import("sa_netx_backend_contract.zig");

pub const backend = switch (builtin.os.tag) {
    .linux => @import("sa_net_uring.zig"),
    .macos => @import("sa_netx_macos.zig"),
    .windows => @import("sa_netx_windows.zig"),
    else => @compileError("Unsupported NetX target OS"),
};

comptime {
    backend_contract.assertBackend(backend);
}

pub const BackendTraits = struct {
    name: []const u8,
    reactor: []const u8,
    native_reactor: bool,
};

pub const supports_reactor = backend.supports_native_reactor;
pub const backend_name = backend.backend_name;
pub const backend_traits = switch (builtin.os.tag) {
    .linux, .macos, .windows => BackendTraits{
        .name = backend.backend_name,
        .reactor = backend.platform_reactor,
        .native_reactor = backend.supports_native_reactor,
    },
    else => unreachable,
};

pub usingnamespace backend;

test "NetX backend selection exposes the stable ABI surface" {
    _ = backend_name;
    _ = backend_traits;
    _ = supports_reactor;
    _ = &backend.sa_netx_init;
    _ = &backend.sa_netx_listen;
    _ = &backend.sa_netx_recv_ticket;
    _ = &backend.sa_netx_push_outbound;
    _ = &backend.sa_netx_broadcast;
    _ = &backend.sa_netx_close_slot;
    _ = &backend.sa_netx_shutdown;

    try std.testing.expect(backend_traits.name.len != 0);
    try std.testing.expect(backend_traits.reactor.len != 0);
    try std.testing.expectEqual(backend.supports_native_reactor, supports_reactor);
    try std.testing.expectEqual(backend.supports_native_reactor, backend_traits.native_reactor);
    switch (builtin.os.tag) {
        .linux => {
            try std.testing.expectEqualStrings("io_uring", backend_traits.name);
            try std.testing.expectEqualStrings("io_uring", backend_traits.reactor);
        },
        .macos => {
            try std.testing.expectEqualStrings("kqueue", backend_traits.name);
            try std.testing.expectEqualStrings("kqueue", backend_traits.reactor);
        },
        .windows => {
            try std.testing.expectEqualStrings("iocp", backend_traits.name);
            try std.testing.expectEqualStrings("iocp", backend_traits.reactor);
        },
        else => unreachable,
    }
    try std.testing.expect(backend_traits.native_reactor);
}
