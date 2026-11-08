// Regression corpus for DEF-WASM32-STD-HYBRID-INPROCESS-FLATTEN
// (fork H, H1 form; client-expansion face of the same defect).
//
// Imported .sa sources that carry target-conditional declaration blocks
// (`// @target-begin` sections -- sa_std/core/mem.sa's memcpy extern and
// the body of sa_mem_copy_nonoverlapping, sa_std/alloc/growvec.sa) used to
// be spliced into a compilation with BOTH variants present. In a function
// body the non-selected variant's blocks do not terminate the way the
// selected one's do, so the verifier rejected the module with
// FallthroughForbidden (1014, "basic blocks must end with jmp, br,
// br_null, or return"). The flattener now materializes imported sources
// for the compilation target at the import read point
// (flattener.materializeImportedSource); this smoke pins that behavior on
// a distilled fixture and on the real sa_std/core/mem.sa.
//
// On the pre-fix tree the distilled fixture fails verification with
// error.VerificationTrap and the real mem.sa closure does the same;
// on the fixed tree both verify.
//
// Run via the named step: `zig build decl-target-smoke --summary all`
// (also wired into the default test step).
const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const test_build_options = @import("test_build_options");

const helper_source =
    \\// @target-begin
    \\// @target native
    \\@extern memcpy(dst: ptr, src: ptr, n: u64) -> ptr
    \\// @target wasm32
    \\@extern memcpy(dst: ptr, src: ptr, n: u32) -> ptr
    \\// @target-end
    \\
    \\@export dt_copy(&dst: ptr, &src: ptr, count: u64) -> void:
    \\L_ENTRY:
    \\    nonzero = ne count, 0
    \\    br nonzero -> L_DO, L_DONE
    \\L_DO:
    \\// @target-begin
    \\// @target native
    \\    r = call @memcpy(dst, src, count)
    \\    !r
    \\    !nonzero
    \\    !count
    \\    !src
    \\    !dst
    \\    return
    \\// @target wasm32
    \\    count_ok = ule count, 4294967295
    \\    br count_ok -> L_DO_COPY, L_TOO_BIG
    \\L_TOO_BIG:
    \\    panic(1703)
    \\L_DO_COPY:
    \\    count_sz = count as u32
    \\    r = call @memcpy(dst, src, count_sz)
    \\    !count_sz
    \\    !count_ok
    \\    !r
    \\    !nonzero
    \\    !count
    \\    !src
    \\    !dst
    \\    return
    \\// @target-end
    \\L_DONE:
    \\    !nonzero
    \\    !count
    \\    !src
    \\    !dst
    \\    return
    \\
;

const main_source =
    \\@import "helper.sa"
    \\
    \\@main() -> i32:
    \\L_ENTRY:
    \\    return 0
    \\
;

fn expectVerifyOk(allocator: std.mem.Allocator, flat: *const saasm.flattener.FlattenResult) !void {
    const bytes = try saasm.plugin_bridge.encodeSabFromFlat(allocator, flat, false);
    allocator.free(bytes);
}

test "flattener materializes @target blocks in imported sources" {
    // The process-global import caches may hold unmaterialized fragments
    // stored by other tests in this binary; start from a clean slate.
    saasm.flattener.clearImportCachesForTest();
    const allocator = std.testing.allocator;
    var tdir = std.testing.tmpDir(.{});
    defer tdir.cleanup();
    const io = std.testing.io;
    try tdir.dir.writeFile(io, .{ .sub_path = "helper.sa", .data = helper_source });
    try tdir.dir.writeFile(io, .{ .sub_path = "main.sa", .data = main_source });

    var path_buf: [512]u8 = undefined;
    const base_len = try tdir.dir.realPath(io, &path_buf);
    const main_path = try std.fs.path.join(allocator, &.{ path_buf[0..base_len], "main.sa" });
    defer allocator.free(main_path);
    const source = try tdir.dir.readFileAlloc(io, "main.sa", allocator, .limited(4096));
    defer allocator.free(source);

    var flat = try saasm.flattener.flattenFile(allocator, main_path, source);
    defer flat.deinit(allocator);

    // The spliced instruction stream must not contain the non-selected
    // (wasm32) variant of the imported function body.
    for (flat.instructions) |inst| {
        try std.testing.expect(std.mem.indexOf(u8, inst.raw_text, "count_ok") == null);
        try std.testing.expect(std.mem.indexOf(u8, inst.raw_text, "@target") == null);
    }
    try expectVerifyOk(allocator, &flat);
}

test "real sa_std/core/mem.sa import closure verifies after materialization" {
    saasm.flattener.clearImportCachesForTest();
    const allocator = std.testing.allocator;

    // Materialize a root file inside the repo tree so its relative import
    // resolves against the tree's sa_std (same shape as std_smoke's
    // flattenFixture: repo-root-relative read + flattenFile).
    const root_path = try std.fs.path.join(allocator, &.{ test_build_options.repo_root, "decl_target_smoke_root.sa" });
    defer allocator.free(root_path);
    defer sio.cwd().deleteFile(root_path) catch {};

    // vec.sa's import closure reaches core/mem.sa (the hybrid file).
    const root_source =
        \\@import "sa_std/alloc/vec.sa"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    return 0
        \\
    ;
    try sio.cwd().writeFile(.{ .sub_path = root_path, .data = root_source });

    var flat = try saasm.flattener.flattenFile(allocator, root_path, root_source);
    defer flat.deinit(allocator);
    try expectVerifyOk(allocator, &flat);
    // The mem closure must have contributed the copy export, in its
    // native variant only (no wasm32 body lines spliced in).
    var copy_exports: usize = 0;
    for (flat.instructions) |inst| {
        if (std.mem.indexOf(u8, inst.raw_text, "sa_mem_copy_nonoverlapping") != null) copy_exports += 1;
        try std.testing.expect(std.mem.indexOf(u8, inst.raw_text, "count_ok") == null);
    }
    try std.testing.expect(copy_exports > 0);
}
