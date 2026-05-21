const std = @import("std");
const http_client = @import("http_client/plugin.zig");

test "http client plugin wrapper exports runtime descriptor" {
    const exported = &http_client.descriptor;
    try std.testing.expectEqualStrings("http-client", std.mem.span(exported.name));
}
