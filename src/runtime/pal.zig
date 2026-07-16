const std = @import("std");
const builtin = @import("builtin");

pub const sys = switch (builtin.os.tag) {
    .linux => @import("pal_linux.zig"),
    .macos => @import("pal_macos.zig"),
    .windows => @import("pal_windows.zig"),
    else => @compileError("Unsupported OS"),
};

pub const SaEvent = sys.SaEvent;

test "PAL selector event loop drains submitted events through sys" {
    var loop: ?*anyopaque = null;
    try std.testing.expectEqual(sys.SA_STD_OK, sys.event_loop_create(&loop));
    defer std.testing.expectEqual(sys.SA_STD_OK, sys.event_loop_close(loop)) catch unreachable;
    try std.testing.expect(loop != null);

    const event = SaEvent{ .user_data = 0x5a17, .flags = 3, .res = -9 };
    try std.testing.expectEqual(sys.SA_STD_OK, sys.event_loop_submit(loop, &event));

    var out = [_]SaEvent{.{ .user_data = 0, .flags = 0, .res = 0 }};
    try std.testing.expectEqual(@as(i32, 1), sys.event_loop_wait(loop, &out, 1, 0));
    try std.testing.expectEqual(event.user_data, out[0].user_data);
    try std.testing.expectEqual(event.flags, out[0].flags);
    try std.testing.expectEqual(event.res, out[0].res);
    try std.testing.expectEqual(@as(i32, 0), sys.event_loop_wait(loop, &out, 1, 0));
}

const WaiterResult = struct {
    ready: i32 = -1,
    event: SaEvent = .{ .user_data = 0, .flags = 0, .res = 0 },
};

fn waitForSubmittedEvent(loop: ?*anyopaque, result: *WaiterResult) void {
    var out = [_]SaEvent{.{ .user_data = 0, .flags = 0, .res = 0 }};
    result.ready = sys.event_loop_wait(loop, &out, 1, 2000);
    if (result.ready == 1) result.event = out[0];
}

test "PAL selector event loop wait blocks until submit wakes sys backend" {
    var loop: ?*anyopaque = null;
    try std.testing.expectEqual(sys.SA_STD_OK, sys.event_loop_create(&loop));
    defer std.testing.expectEqual(sys.SA_STD_OK, sys.event_loop_close(loop)) catch unreachable;

    var result = WaiterResult{};
    const waiter = try std.Thread.spawn(.{}, waitForSubmittedEvent, .{ loop, &result });
    std.time.sleep(10 * std.time.ns_per_ms);

    const event = SaEvent{ .user_data = 0x7a11, .flags = 9, .res = 17 };
    try std.testing.expectEqual(sys.SA_STD_OK, sys.event_loop_submit(loop, &event));
    waiter.join();

    try std.testing.expectEqual(@as(i32, 1), result.ready);
    try std.testing.expectEqual(event.user_data, result.event.user_data);
    try std.testing.expectEqual(event.flags, result.event.flags);
    try std.testing.expectEqual(event.res, result.event.res);
}
