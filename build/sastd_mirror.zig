const std = @import("std");
const pathFromRoot = @import("paths.zig").pathFromRoot;

/// Mirror the sa_std tree into a WriteFiles step, materializing
/// every SA source file that carries target-conditional declaration
/// blocks for `decl_target` and copying all other files verbatim.
/// Used by the target-conditional declaration materialization at the
/// sa-std-static assembly point: materialized units keep their
/// in-tree relative paths, so relative @imports resolve exactly as
/// they do in the real tree, and a conditional block anywhere in an
/// assembled unit's import closure is reduced before the assembler
/// sees it. Materialization problems are loud configure-time
/// failures, never a silent fallback.
pub fn mirrorSaStdTree(b: *std.Build, wf: *std.Build.Step.WriteFile, decl_target: @import("../tools/decl_materialize.zig").DeclTarget) void {
    const io = b.graph.io;
    const root_abs = pathFromRoot(b, "sa_std");
    var root_dir = std.Io.Dir.openDirAbsolute(io, root_abs, .{ .iterate = true }) catch |err|
        std.debug.panic("decl materialize: cannot open sa_std tree: {s}", .{@errorName(err)});
    defer root_dir.close(io);
    mirrorSaStdDir(b, wf, root_dir, "", decl_target);
}

pub fn mirrorSaStdDir(b: *std.Build, wf: *std.Build.Step.WriteFile, dir: std.Io.Dir, rel_prefix: []const u8, decl_target: @import("../tools/decl_materialize.zig").DeclTarget) void {
    const decl_materialize = @import("../tools/decl_materialize.zig");
    const io = b.graph.io;
    var it = dir.iterate();
    while (it.next(io) catch |err| std.debug.panic("decl materialize: sa_std walk failed: {s}", .{@errorName(err)})) |entry| {
        const rel = if (rel_prefix.len == 0)
            b.allocator.dupe(u8, entry.name) catch @panic("OOM")
        else
            std.fs.path.join(b.allocator, &.{ rel_prefix, entry.name }) catch @panic("OOM");
        switch (entry.kind) {
            .directory => {
                var sub = dir.openDir(io, entry.name, .{ .iterate = true }) catch |err|
                    std.debug.panic("decl materialize: cannot open sa_std/{s}: {s}", .{ rel, @errorName(err) });
                defer sub.close(io);
                mirrorSaStdDir(b, wf, sub, rel, decl_target);
            },
            .file, .sym_link => {
                const src = std.fs.path.join(b.allocator, &.{ "sa_std", rel }) catch @panic("OOM");
                if (std.mem.endsWith(u8, rel, ".sa") or std.mem.endsWith(u8, rel, ".sal")) {
                    const abs = pathFromRoot(b, src);
                    const raw = std.Io.Dir.readFileAlloc(.cwd(), io, abs, b.allocator, .limited(16 * 1024 * 1024)) catch |err|
                        std.debug.panic("decl materialize: failed to read {s}: {s}", .{ src, @errorName(err) });
                    if (decl_materialize.containsTargetBlocks(raw)) {
                        const materialized = decl_materialize.materialize(b.allocator, raw, decl_target) catch |err|
                            std.debug.panic("decl materialize failed for {s} (target {s}): {s}", .{ src, decl_target.targetName(), @errorName(err) });
                        _ = wf.add(rel, materialized);
                        continue;
                    }
                }
                _ = wf.addCopyFile(b.path(src), rel);
            },
            else => {},
        }
    }
}
