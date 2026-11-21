const std = @import("std");
const sio = @import("sio");
const trap = @import("../common/trap.zig");
const flattener = @import("../flattener.zig");
const sab = @import("../sab.zig");
const plugin_bridge = @import("../plugin_bridge.zig");
const compileSource = @import("compile.zig").compileSource;
const test_source_tree_load_count = @import("compile.zig").test_source_tree_load_count;
const cacheBuildSemanticFlags = @import("cache.zig").cacheBuildSemanticFlags;
const cacheKeyNormalizedPath = @import("cache.zig").cacheKeyNormalizedPath;
const cacheKeyTreePath = @import("source_tree.zig").cacheKeyTreePath;
const hashResolvedSourceTree = @import("source_tree.zig").hashResolvedSourceTree;
const stdTreeDigest = @import("source_tree.zig").stdTreeDigest;
const test_source_tree_hash_cache_max_entries = @import("source_tree.zig").test_source_tree_hash_cache_max_entries;
const encodeSabFromFlat = @import("../plugin_bridge.zig").encodeSabFromFlat;
const encodeProgram = @import("../sab.zig").encodeProgram;
const readImportSourceFile = @import("../flattener.zig").readImportSourceFile;
const TmpWorkDir = @import("types.zig").TmpWorkDir;
const printTrapReport = @import("trap_errors.zig").printTrapReport;
const trapFromFlattenError = @import("trap_errors.zig").trapFromFlattenError;
const printCliError = @import("errors.zig").printCliError;
const printCommandHelp = @import("help.zig").printCommandHelp;
const printUsage = @import("help.zig").printUsage;

test "trap reports print a human summary and preserve json payload" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    var report = trap.TrapReport{
        .trap = .memory_leak,
        .trap_code = trap.trapCode(.memory_leak),
        .line = 12,
        .source_line = 9,
        .source_text_buf = std.mem.zeroes([256]u8),
        .original_text_buf = std.mem.zeroes([256]u8),
        .source_text = null,
        .original_text = null,
        .register_buf = std.mem.zeroes([64]u8),
        .register = null,
        .registers = &.{},
        .expected_mask = null,
        .actual_mask = 1,
        .expected_mask_name = null,
        .actual_mask_name = "Active",
        .upstream_loc = null,
        .upstream_file_buf = std.mem.zeroes([128]u8),
        .upstream_line = 42,
        .upstream_col = 7,
        .function_buf = std.mem.zeroes([64]u8),
        .function = null,
        .is_ffi_wrapper = false,
        .message = "live registers remain at function exit",
        .hint = "insert explicit release",
    };
    const source = "result = load node+0 as i32";
    std.mem.copyForwards(u8, report.source_text_buf[0..source.len], source);
    const register = "r1";
    std.mem.copyForwards(u8, report.register_buf[0..register.len], register);
    const upstream_file = "main.rs";
    std.mem.copyForwards(u8, report.upstream_file_buf[0..upstream_file.len], upstream_file);
    const function = "@main() -> i32:";
    std.mem.copyForwards(u8, report.function_buf[0..function.len], function);
    try printTrapReport(&aw.writer, report, .human);
    const output = aw.written();

    try std.testing.expect(std.mem.indexOf(u8, output, "error[MemoryLeak]: live registers remain at function exit") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  in function @main() -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  upstream main.rs:42:7") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  line 9 (expanded 12): result = load node+0 as i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  register: r1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  state: Active") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  help: insert explicit release") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"trap\":\"MemoryLeak\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"function\":\"@main() -> i32:\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"register\":\"r1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"hint\":\"insert explicit release\"") != null);
}

test "cli error printing is detailed and json capable" {
    var haw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer haw.deinit();
    try printCliError(&haw.writer, error.MissingSourcePath, .human);
    try std.testing.expect(std.mem.indexOf(u8, haw.written(), "error[SA-CLI-001]: missing required positional argument") != null);
    try std.testing.expect(std.mem.indexOf(u8, haw.written(), "help: pass the source file, project path, or required operand after the command") != null);

    var jaw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer jaw.deinit();
    try printCliError(&jaw.writer, error.InvalidTarget, .json);
    try std.testing.expect(std.mem.indexOf(u8, jaw.written(), "\"status\":\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jaw.written(), "\"code\":\"SA-CLI-006\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jaw.written(), "\"name\":\"InvalidTarget\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jaw.written(), "\"message\":\"invalid target\"") != null);
}

test "build-workspace command is recognized in help" {
    var law: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer law.deinit();

    try printUsage(&law.writer);
    try std.testing.expect(std.mem.indexOf(u8, law.written(), "build-workspace") != null);

    law.clearRetainingCapacity();
    try printCommandHelp(&law.writer, .build_workspace, &.{});
    try std.testing.expect(std.mem.indexOf(u8, law.written(), "usage: sa build-workspace [options]") != null);
}

test "source tree hash cache reuses mtime size digest without reloading unchanged files" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tdir.makePath("sa_std/core");

    {
        var file = try tdir.createFile("main.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/cache_probe.sai"
            \\@main() -> i32:
            \\return dep_value
            \\
        );
    }
    {
        var file = try tdir.createFile("sa_std/core/cache_probe.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def dep_value = 7\n");
    }

    const project_root = try sio.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try sio.cwd().realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);

    test_source_tree_load_count = 0;
    var first_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var first_digest: [32]u8 = undefined;
    first_hasher.final(&first_digest);
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);

    const resolve_ctx = flattener.ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };
    var warmed_import = try flattener.readImportSourceFile(std.testing.allocator, ".", "sa_std/core/cache_probe.sai", resolve_ctx);
    defer warmed_import.deinit(std.testing.allocator);
    try std.testing.expect(warmed_import.owned_source == null);

    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var second_digest: [32]u8 = undefined;
    second_hasher.final(&second_digest);
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);
    try std.testing.expectEqualSlices(u8, first_digest[0..], second_digest[0..]);

    {
        var file = try tdir.createFile("sa_std/core/cache_probe.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def dep_value = 777\n");
    }

    var third_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &third_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var third_digest: [32]u8 = undefined;
    third_hasher.final(&third_digest);
    try std.testing.expect(test_source_tree_load_count > 1);
    try std.testing.expect(!std.mem.eql(u8, first_digest[0..], third_digest[0..]));
}

test "source tree hash missing import returns PackageNotResolved without ownership errors" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tdir.makePath("sa_std/core");
    {
        var file = try tdir.createFile("main.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "missing.sa"
            \\@main() -> i32:
            \\return 0
            \\
        );
    }

    const project_root = try sio.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try sio.cwd().realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try std.testing.expectError(
        error.PackageNotResolved,
        hashResolvedSourceTree(std.testing.allocator, &hasher, &.{}, &.{}, project_root, std_root, false, "main.sa"),
    );
}

test "source tree hash cache LRU is opt-in" {
    const previous_limit = test_source_tree_hash_cache_max_entries;
    test_source_tree_hash_cache_max_entries = 1;
    defer test_source_tree_hash_cache_max_entries = previous_limit;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    {
        var file = try tdir.createFile("a.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@main() -> i32:
            \\return 1
            \\
        );
    }
    {
        var file = try tdir.createFile("b.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@main() -> i32:
            \\return 2
            \\
        );
    }

    const project_root = try sio.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);

    test_source_tree_load_count = 0;
    var first_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_hasher, &.{}, &.{}, project_root, project_root, false, "a.sa");
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);

    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hasher, &.{}, &.{}, project_root, project_root, false, "b.sa");
    try std.testing.expectEqual(@as(usize, 2), test_source_tree_load_count);

    var second_hit_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hit_hasher, &.{}, &.{}, project_root, project_root, false, "b.sa");
    try std.testing.expectEqual(@as(usize, 2), test_source_tree_load_count);

    var first_again_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_again_hasher, &.{}, &.{}, project_root, project_root, false, "a.sa");
    try std.testing.expectEqual(@as(usize, 3), test_source_tree_load_count);
}

test "std tree digest depends on content, not on location" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    defer original_cwd.setAsCwd() catch {};

    // Two std trees with identical content at different locations must
    // digest identically; editing content must change the digest;
    // reverting the edit must restore it; scratch dirs are invisible.
    var digests: [2][32]u8 = undefined;
    for (0..2) |i| {
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var tdir: sio.Dir = .{ .inner = tmp.dir };
        try tdir.setAsCwd();
        try tdir.makePath("sa_std/core");
        {
            var file = try tdir.createFile("sa_std/core/probe.sa", .{ .truncate = true });
            defer file.close();
            try file.writeAll("#def probe_value = 7\n");
        }
        {
            var file = try tdir.createFile("sa_std/top.sai", .{ .truncate = true });
            defer file.close();
            try file.writeAll("#def top_value = 1\n");
        }
        const digest = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
        digests[i] = digest;

        if (i == 0) {
            try tdir.makePath("sa_std/.sla-cache");
            {
                var file = try tdir.createFile("sa_std/.sla-cache/residue", .{ .truncate = true });
                defer file.close();
                try file.writeAll("residue\n");
            }
            const with_residue = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
            try std.testing.expectEqualSlices(u8, digest[0..], with_residue[0..]);

            // The built archive inside the tree is a product, not a
            // source: its presence must not move the digest either.
            {
                var file = try tdir.createFile("sa_std/libsa_std.a", .{ .truncate = true });
                defer file.close();
                try file.writeAll("not a real archive\n");
            }
            const with_archive = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
            try std.testing.expectEqualSlices(u8, digest[0..], with_archive[0..]);

            {
                var file = try tdir.createFile("sa_std/core/probe.sa", .{ .truncate = true });
                defer file.close();
                try file.writeAll("#def probe_value = 8\n");
            }
            const edited = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
            try std.testing.expect(!std.mem.eql(u8, digest[0..], edited[0..]));

            {
                var file = try tdir.createFile("sa_std/core/probe.sa", .{ .truncate = true });
                defer file.close();
                try file.writeAll("#def probe_value = 7\n");
            }
            const reverted = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
            try std.testing.expectEqualSlices(u8, digest[0..], reverted[0..]);
        }
    }
    try std.testing.expectEqualSlices(u8, digests[0][0..], digests[1][0..]);
}

test "cache key paths are project-relative, never checkout-absolute" {
    const allocator = std.testing.allocator;
    const root = "/home/tester/checkout";
    const inside = try cacheKeyNormalizedPath(allocator, root, "/home/tester/checkout/src/main.sa");
    defer allocator.free(inside);
    try std.testing.expectEqualStrings("src/main.sa", inside);
    // A sibling whose path merely shares the root as a string prefix is
    // not inside the project and must stay exact.
    const sibling_prefix = try cacheKeyNormalizedPath(allocator, root, "/home/tester/checkout2/main.sa");
    defer allocator.free(sibling_prefix);
    try std.testing.expectEqualStrings("/home/tester/checkout2/main.sa", sibling_prefix);
    const relative = try cacheKeyNormalizedPath(allocator, root, "src/main.sa");
    defer allocator.free(relative);
    try std.testing.expectEqualStrings("src/main.sa", relative);
}

test "cache key tree paths tag project and std roots" {
    const allocator = std.testing.allocator;
    const proj = try cacheKeyTreePath(allocator, "/p/work/src/a.sa", "/p/work", "/p/std");
    defer allocator.free(proj);
    try std.testing.expectEqualStrings("proj/src/a.sa", proj);
    const std_file = try cacheKeyTreePath(allocator, "/p/std/core/c.sa", "/p/work", "/p/std");
    defer allocator.free(std_file);
    try std.testing.expectEqualStrings("std/core/c.sa", std_file);
    const outside = try cacheKeyTreePath(allocator, "/q/other.sa", "/p/work", "/p/std");
    defer allocator.free(outside);
    try std.testing.expectEqualStrings("/q/other.sa", outside);
}

test "fast-math is a separate build cache dimension" {
    var off = std.crypto.hash.sha2.Sha256.init(.{});
    var on = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBuildSemanticFlags(&off, false, true, false, .std, false, false);
    cacheBuildSemanticFlags(&on, false, true, false, .std, false, true);
    var off_digest: [32]u8 = undefined;
    var on_digest: [32]u8 = undefined;
    off.final(&off_digest);
    on.final(&on_digest);
    try std.testing.expect(!std.mem.eql(u8, &off_digest, &on_digest));
    // The flag must not collapse with a different mode either: the default
    // artifact may never satisfy a --fast-math request once cached.
    var other = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBuildSemanticFlags(&other, false, true, false, .std, false, false);
    var other_digest: [32]u8 = undefined;
    other.final(&other_digest);
    try std.testing.expectEqualSlices(u8, &off_digest, &other_digest);
}

test "flatten error mapping keeps import resolution and unsupported type hints specific" {
    const import_source =
        \\@import "missing.sa"
        \\@main() -> i32:
        \\    return 0
    ;
    const import_report = trapFromFlattenError("/tmp/import.sa", import_source, error.PackageNotResolved, 1);
    try std.testing.expectEqual(trap.Trap.import_resolution_failed, import_report.trap);
    try std.testing.expectEqual(@as(u32, 1050), import_report.trap_code.?);
    try std.testing.expectEqualStrings("/tmp/import.sa", import_report.file.?);
    try std.testing.expectEqualStrings("import path could not be resolved", import_report.message);
    try std.testing.expectEqualStrings("check the import path, package identity, local vendor tree, and package cache", import_report.hint.?);
    try std.testing.expectEqualStrings("pin-import", import_report.repair_action.?);

    const type_source =
        \\@test "probe":
        \\    point = call @support_make_point(10, 20)
    ;
    const type_report = trapFromFlattenError("/tmp/type.sa", type_source, error.UnsupportedType, 2);
    try std.testing.expectEqual(trap.Trap.unsupported_type, type_report.trap);
    try std.testing.expectEqualStrings("/tmp/type.sa", type_report.file.?);
    try std.testing.expectEqualStrings("unsupported type annotation during flattening", type_report.message);
    try std.testing.expectEqualStrings("inspect the callee declaration referenced by this call site; the unsupported annotation is usually in the imported signature", type_report.hint.?);
}

test "duplicate definition trap gets a repair hint" {
    const source =
        \\#def X = 1
        \\#def X = 2
    ;
    const report = trapFromFlattenError("/tmp/dup.sa", source, error.DuplicateDef, 2);
    try std.testing.expectEqual(trap.Trap.duplicate_def, report.trap);
    try std.testing.expectEqualStrings("/tmp/dup.sa", report.file.?);
    try std.testing.expectEqualStrings("rename-def", report.repair_action.?);
    try std.testing.expectEqualStrings("change one of the conflicting names or namespace the symbol", report.repair_hint.?);
    try std.testing.expectEqualStrings("high", report.repair_confidence.?);
}

test "compileSource accepts true SAB without text flattener" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };
    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const reg_ids = [_]u32{1};
    const fsig = @import("../common/signature.zig").FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .reg_ids = reg_ids[0..],
    };
    var decl = @import("../common/instruction.zig").makeInstruction(.func_decl, 1, 0, null, "");
    decl.operands[0] = .{ .symbol = 0 };
    decl.operands[1] = .{ .func = 0 };
    var assign = @import("../common/instruction.zig").makeInstruction(.assign, 2, 1, null, "");
    assign.operands[0] = .{ .reg = 1 };
    assign.operands[1] = .{ .imm_i64 = 7 };
    var ret = @import("../common/instruction.zig").makeInstruction(.return_, 3, 2, null, "");
    ret.operands[0] = .{ .reg = 1 };

    const bytes = try sab.encodeProgram(std.testing.allocator, &.{ "main", "value" }, &.{fsig}, &.{ decl, assign, ret });
    defer std.testing.allocator.free(bytes);
    try tdir.writeFile(.{ .sub_path = "main.sab", .data = bytes });

    var compiled = try compileSource(std.testing.allocator, "main.sab", .{});
    switch (compiled) {
        .ok => |*ok| {
            defer ok.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), ok.verified.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "check --emit-sab roundtrips through compileSource without text fallback" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };
    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    // Write a minimal .sa program, compile it, encode to SAB via the same
    // plugin_bridge.encodeSabFromFlat that `check --emit-sab` uses, then
    // reload the .sab and verify the decoded program matches. The SAB path
    // must be standalone: a corrupt .sab must fail loudly, never silently
    // fall back to text.
    const sa_source =
        \\@main():
        \\L_ENTRY:
        \\    x = add 40, 2
        \\    return x
    ;
    try tdir.writeFile(.{ .sub_path = "rt.sa", .data = sa_source });

    var compiled_sa = try compileSource(std.testing.allocator, "rt.sa", .{});
    var ok_sa = switch (compiled_sa) {
        .ok => |*ok| ok,
        .trap => return error.TestUnexpectedResult,
    };
    defer ok_sa.deinit(std.testing.allocator);

    const sab_bytes = try plugin_bridge.encodeSabFromFlat(std.testing.allocator, &ok_sa.flat, false);
    defer std.testing.allocator.free(sab_bytes);
    // SAB magic "SAB\x00", version 4.0.
    try std.testing.expect(sab_bytes.len > 6);
    try std.testing.expectEqualStrings("SAB\x00", sab_bytes[0..4]);
    try std.testing.expectEqual(@as(u8, 4), sab_bytes[4]);
    try tdir.writeFile(.{ .sub_path = "rt.sab", .data = sab_bytes });

    var compiled_sab = try compileSource(std.testing.allocator, "rt.sab", .{});
    switch (compiled_sab) {
        .ok => |*ok| {
            defer ok.deinit(std.testing.allocator);
            try std.testing.expectEqual(ok_sa.flat.instructions.len, ok.flat.instructions.len);
            try std.testing.expectEqual(ok_sa.flat.symbols.names.items.len, ok.flat.symbols.names.items.len);
        },
        .trap => return error.TestUnexpectedResult,
    }

    // Corrupt SAB must fail with a SAB-specific error, not fall back to text.
    try tdir.writeFile(.{ .sub_path = "bad.sab", .data = sab_bytes[0..10] });
    try std.testing.expectError(error.TruncatedSab, compileSource(std.testing.allocator, "bad.sab", .{}));
    try tdir.writeFile(.{ .sub_path = "fake.sab", .data = "this is not a sab binary" });
    try std.testing.expectError(error.InvalidSabMagic, compileSource(std.testing.allocator, "fake.sab", .{}));
}

test "TmpWorkDir.init generates url-safe temp-dir names (DEF-SCI-TMPWORKDIR-BASE64-SLASH)" {
    // Standard base64 can emit slash as its first character (1/64 per call),
    // turning the temp-dir name into an absolute path: makePath then tries
    // to create it under the filesystem root and fails with AccessDenied.
    // url_safe emits dash/underscore instead of plus/slash. A
    // standard-base64 name fails this test with probability 1-(62/64)^16
    // per sample (any plus/slash in 16 chars), so 512 samples fail it
    // with probability 1-(62/64)^8192, i.e. for all practical purposes
    // certainly -- far more sensitive than the 1/64 first-char defect.
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        var tmp = try TmpWorkDir.init();
        try std.testing.expectEqual(@as(usize, 16), tmp.sub_path.len);
        try std.testing.expect(std.mem.indexOfAny(u8, &tmp.sub_path, "/+") == null);
        tmp.cleanup();
    }
}
