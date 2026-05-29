const std = @import("std");

const audit = @import("audit.zig");
const ci = @import("ci.zig");
const confirm = @import("confirm.zig");
const fetch = @import("fetch.zig");
const lock = @import("lock.zig");
const manifest = @import("manifest.zig");
const mirror = @import("mirror.zig");
const resolver = @import("resolver.zig");
const sum = @import("sum.zig");

test {
    std.testing.refAllDecls(audit);
    std.testing.refAllDecls(ci);
    std.testing.refAllDecls(confirm);
    std.testing.refAllDecls(fetch);
    std.testing.refAllDecls(lock);
    std.testing.refAllDecls(manifest);
    std.testing.refAllDecls(mirror);
    std.testing.refAllDecls(resolver);
    std.testing.refAllDecls(sum);
}

test "manifest parses plugin requirements" {
    const source =
        \\require deps/example/pkg @HEAD sha256:0000000000000000000000000000000000000000000000000000000000000000
        \\require_plugin ../plugins/sa_plugin_demo @0.1.0 abi 1
        \\
        \\permission_set dev {
        \\  env [HOME, SA_*]
        \\  read [$PROJECT/**]
        \\  write [$PROJECT/out/**]
        \\  net [https://api.example.com, http://localhost:8787]
        \\  run [/usr/bin/git]
        \\}
        \\
    ;
    var parsed = try manifest.parseManifestWithFile(std.testing.allocator, source, "sa.mod");
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), parsed.requires.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.plugin_requires.len);
    try std.testing.expectEqualStrings("../plugins/sa_plugin_demo", parsed.plugin_requires[0].identity);
    try std.testing.expectEqualStrings("0.1.0", parsed.plugin_requires[0].ref);
    try std.testing.expectEqual(@as(u32, 1), parsed.plugin_requires[0].abi);
    try std.testing.expectEqual(@as(usize, 1), parsed.permission_sets.len);
    try std.testing.expectEqualStrings("dev", parsed.permission_sets[0].name);
    try std.testing.expectEqualStrings("HOME", parsed.permission_sets[0].env[0]);
    try std.testing.expectEqualStrings("https://api.example.com", parsed.permission_sets[0].net[0]);
}
