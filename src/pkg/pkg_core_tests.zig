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
