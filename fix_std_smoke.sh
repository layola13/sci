#!/bin/bash
sed -i 's/saasm.flattener.flattenFile(/flattenFixture(/g' tests/std_smoke.zig
sed -i '1i const build_options = @import("build_options");' tests/std_smoke.zig
cat << 'ZIG' >> tests/std_smoke.zig

fn flattenFixture(allocator: std.mem.Allocator, source_path: []const u8, source: []const u8) !saasm.flattener.FlattenResult {
    var resolve_ctx = saasm.pkg_resolver.ResolveContext.init(allocator);
    resolve_ctx.options.std_root = try std.fs.path.join(allocator, &.{ build_options.repo_root, "sa_std" });
    defer allocator.free(resolve_ctx.options.std_root.?);
    return saasm.flattener.flattenFileWithPackages(allocator, source_path, source, resolve_ctx);
}
ZIG
