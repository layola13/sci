// Regression corpus for DEF-WASM32-SCI-COLD-BUILD (2026-11-08).
//
// The landed width batch assembled the target-materialized growvec unit
// from an isolated single file inside .zig-cache; its line-1 relative
// import `@import "../core/mem.sa"` resolved against that cache directory
// and every cold build died with ImportResolutionFailed (trap 1050).
//
// This test pins the fix's invariant inside the sci tree itself:
//   1. the materializer keeps a conditional unit's relative imports
//      verbatim and selects exactly one target's declaration widths;
//   2. build.zig must wire std assembly through the mirrored sa_std tree
//      (materialized unit + its whole relative-import closure co-located),
//      never through an isolated materialized file in the build cache;
//   3. after a build, no orphaned `growvec_materialized.sa` may exist in
//      .zig-cache whose `../core/mem.sa` sibling does not resolve, and a
//      mirrored `alloc/growvec.sa` with a resolvable `core/mem.sa` sibling
//      must exist.
//
// Run after `zig build sa-std-static` (both targets) in this tree.
// NOTE (landing disposition, 2026-11-08): a bare
// `zig test tests/wasm32_std_mirror_smoke.zig` does NOT work on
// zig 0.17 (module-external @import of ../tools/decl_materialize.zig).
// Working form: put a one-line runner at the tree root,
//   comptime { _ = @import("tests/wasm32_std_mirror_smoke.zig"); }
// in e.g. smoke_runner_scratch.zig, then `zig test smoke_runner_scratch.zig`.
// On the pre-fix tree this fails (isolated cache file + no mirror wiring);
// on the fixed tree it passes; on a tree whose std carries no conditional
// units it skips.
const std = @import("std");
const dm = @import("../tools/decl_materialize.zig");

const io = std.testing.io;

fn readRepoFile(allocator: std.mem.Allocator, rel: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, rel, allocator, .limited(16 * 1024 * 1024));
}

test "materialized std unit keeps relative imports and per-target widths" {
    const allocator = std.testing.allocator;
    const growvec = readRepoFile(allocator, "sa_std/alloc/growvec.sa") catch return error.SkipZigTest;
    defer allocator.free(growvec);
    if (!dm.containsTargetBlocks(growvec)) return error.SkipZigTest;

    const native = try dm.materialize(allocator, growvec, .native);
    defer allocator.free(native);
    // Relative imports survive materialization byte-for-byte: they are the
    // reason the unit must be assembled from inside a mirrored tree.
    try std.testing.expect(std.mem.indexOf(u8, native, "@import \"../core/mem.sa\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, native, "@import \"../core/slice.sal\"") != null);
    // Exactly the native (u64) size_t declarations remain.
    try std.testing.expect(std.mem.indexOf(u8, native, "@extern mmap(addr: ptr, len: u64,") != null);
    try std.testing.expect(std.mem.indexOf(u8, native, "@extern mmap(addr: ptr, len: u32,") == null);
    try std.testing.expect(std.mem.indexOf(u8, native, "@target") == null);

    const wasm = try dm.materialize(allocator, growvec, .wasm32);
    defer allocator.free(wasm);
    try std.testing.expect(std.mem.indexOf(u8, wasm, "@import \"../core/mem.sa\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wasm, "@extern mmap(addr: ptr, len: u32,") != null);
    try std.testing.expect(std.mem.indexOf(u8, wasm, "@extern mmap(addr: ptr, len: u64,") == null);
    try std.testing.expect(std.mem.indexOf(u8, wasm, "@target") == null);
}

test "std assembly is wired through a mirrored tree, never an isolated file" {
    const allocator = std.testing.allocator;
    const growvec = readRepoFile(allocator, "sa_std/alloc/growvec.sa") catch return error.SkipZigTest;
    defer allocator.free(growvec);
    if (!dm.containsTargetBlocks(growvec)) return error.SkipZigTest;

    const build_src = try readRepoFile(allocator, "build.zig");
    defer allocator.free(build_src);
    // The defect form: a lone materialized file handed to the assembler.
    try std.testing.expect(std.mem.indexOf(u8, build_src, "growvec_materialized.sa") == null);
    // The fix form: the whole sa_std tree is mirrored into the build cache
    // and the assembler is pointed at alloc/growvec.sa inside the mirror.
    try std.testing.expect(std.mem.indexOf(u8, build_src, "mirrorSaStdTree") != null);
    try std.testing.expect(std.mem.indexOf(u8, build_src, "\"alloc/growvec.sa\"") != null);
}

fn scanCacheDir(dir: std.Io.Dir, path: []const u8, state: *ScanState) void {
    var it = dir.iterate();
    while (it.next(io) catch return) |entry| {
        const child = std.fs.path.join(state.allocator, &.{ path, entry.name }) catch return;
        defer state.allocator.free(child);
        switch (entry.kind) {
            .directory => {
                var sub = dir.openDir(io, entry.name, .{ .iterate = true }) catch continue;
                defer sub.close(io);
                scanCacheDir(sub, child, state);
            },
            .file, .sym_link => {
                if (std.mem.eql(u8, entry.name, "growvec_materialized.sa")) {
                    // Isolated materialized unit: its first relative import
                    // must resolve from its own location. On the pre-fix
                    // tree this file sits alone in .zig-cache/o/<hash>/ and
                    // ../core/mem.sa does not exist -> the defect.
                    const parent = std.fs.path.dirname(path) orelse ".";
                    const sibling = std.fs.path.join(state.allocator, &.{ parent, "core", "mem.sa" }) catch return;
                    defer state.allocator.free(sibling);
                    std.Io.Dir.cwd().access(io, sibling, .{}) catch {
                        state.isolated_unresolvable = true;
                    };
                }
                if (std.mem.eql(u8, entry.name, "growvec.sa") and
                    std.mem.endsWith(u8, path, "alloc"))
                {
                    const parent = std.fs.path.dirname(path) orelse ".";
                    const sibling = std.fs.path.join(state.allocator, &.{ parent, "core", "mem.sa" }) catch return;
                    defer state.allocator.free(sibling);
                    std.Io.Dir.cwd().access(io, sibling, .{}) catch return;
                    state.mirror_resolvable = true;
                }
            },
            else => {},
        }
    }
}

const ScanState = struct {
    allocator: std.mem.Allocator,
    isolated_unresolvable: bool = false,
    mirror_resolvable: bool = false,
};

test "build cache holds a resolvable mirror and no orphaned materialized unit" {
    const allocator = std.testing.allocator;
    const growvec = readRepoFile(allocator, "sa_std/alloc/growvec.sa") catch return error.SkipZigTest;
    defer allocator.free(growvec);
    if (!dm.containsTargetBlocks(growvec)) return error.SkipZigTest;

    var cache = std.Io.Dir.cwd().openDir(io, ".zig-cache", .{ .iterate = true }) catch
        return error.SkipZigTest; // no build has run in this tree yet
    defer cache.close(io);
    var state = ScanState{ .allocator = allocator };
    scanCacheDir(cache, ".zig-cache", &state);
    try std.testing.expect(!state.isolated_unresolvable);
    try std.testing.expect(state.mirror_resolvable);
}
