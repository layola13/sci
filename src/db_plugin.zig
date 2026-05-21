const std = @import("std");
pub const pkg_manifest = @import("pkg/manifest.zig");
pub const pkg_resolver = @import("pkg/resolver.zig");
const db = @import("db/plugin.zig");

pub export const saasm_plugin_descriptor_v1 = &db.descriptor;

test "db plugin wrapper exports runtime descriptor" {
    const exported = saasm_plugin_descriptor_v1;
    try std.testing.expectEqualStrings("db", std.mem.span(exported.name));
}
