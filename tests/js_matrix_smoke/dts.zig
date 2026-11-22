const std = @import("std");
const builtin = @import("builtin");
const saasm = @import("saasm");
const sio = @import("sio");

pub fn readTmpFileAlloc(tmp_dir: anytype, name: []const u8) ![]u8 {
    const f = try tmp_dir.openFile(std.testing.io, name, .{});
    defer f.close(std.testing.io);
    var rbuf: [8192]u8 = undefined;
    var reader = f.reader(std.testing.io, &rbuf);
    return try reader.interface.allocRemaining(std.testing.allocator, .limited(1 << 24));
}

pub fn buildJsInTmp(source_path: []const u8, repo_root: []const u8, extra: []const []const u8, out_name: []const u8) !u8 {
    var argv = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer argv.deinit();
    try argv.append("sa");
    try argv.append("build-js");
    try argv.append(source_path);
    try argv.append("-o");
    try argv.append(out_name);
    for (extra) |arg| try argv.append(arg);
    try argv.append("--project-root");
    try argv.append(repo_root);
    return try saasm.cli.execute(std.testing.allocator, argv.items);
}

test "js backend --emit-dts writes declarations and leaves js bytes unchanged" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);
    const probe_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/dts_probe_types.sa");
    defer std.testing.allocator.free(probe_path);
    const handle_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/965_npm_handle_ctor_method/main.sa");
    defer std.testing.allocator.free(handle_path);
    const v128_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/dts_probe_v128.sa");
    defer std.testing.allocator.free(v128_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    // JS bytes must be identical with and without --emit-dts.
    try std.testing.expectEqual(@as(u8, 0), try buildJsInTmp(probe_path, repo_root, &.{}, "off.js"));
    try std.testing.expectEqual(@as(u8, 0), try buildJsInTmp(probe_path, repo_root, &.{"--emit-dts"}, "on.js"));
    const off_js = try readTmpFileAlloc(tmp.dir, "off.js");
    defer std.testing.allocator.free(off_js);
    const on_js = try readTmpFileAlloc(tmp.dir, "on.js");
    defer std.testing.allocator.free(on_js);
    try std.testing.expectEqualStrings(off_js, on_js);

    // The declaration product mirrors the measured boundary shapes.
    const dts = try readTmpFileAlloc(tmp.dir, "on.d.ts");
    defer std.testing.allocator.free(dts);
    for ([_][]const u8{
        "export type SaI64 = number | bigint;",
        "export type SaFallible<T> = { s: number; v: T };",
        "export declare function id_i32(x: number): number;",
        "export declare function id_i64(x: SaI64): SaI64;",
        "export declare function id_ptr(x: SaPtr): SaPtr;",
        "export declare function pair_len(p: SaPtr, len: SaU64): SaU64;",
        "export declare function noop(): number;",
        "export declare function fall_ok(x: number): SaFallible<number>;",
        "export declare function fall_void(): { s: number };",
        "export declare const __sa_memory: ArrayBuffer;",
        "export declare function __sa_alloc(size: number): number;",
    }) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, dts, needle) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, dts, "any") == null);

    // Handle wrappers are exported (and declared) under ESM...
    try std.testing.expectEqual(@as(u8, 0), try buildJsInTmp(handle_path, repo_root, &.{"--emit-dts"}, "h.js"));
    const h_dts = try readTmpFileAlloc(tmp.dir, "h.d.ts");
    defer std.testing.allocator.free(h_dts);
    for ([_][]const u8{
        "export declare function ee_new(): SaHandle;",
        "export declare function ee_max_listeners(self: SaHandle): number;",
        "export declare function main(): number;",
    }) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, h_dts, needle) != null);
    }
    // ...but the CJS product does not export them, so neither do we.
    try std.testing.expectEqual(@as(u8, 0), try buildJsInTmp(handle_path, repo_root, &.{ "--emit-dts", "--format", "cjs" }, "hc.js"));
    const hc_dts = try readTmpFileAlloc(tmp.dir, "hc.d.ts");
    defer std.testing.allocator.free(hc_dts);
    try std.testing.expect(std.mem.indexOf(u8, hc_dts, "export declare function main(): number;") != null);
    try std.testing.expect(std.mem.indexOf(u8, hc_dts, "ee_new") == null);

    // A v128 shape on the export surface has no JS representation:
    // declaration emission must fail the build loudly.
    const v128_code = try buildJsInTmp(v128_path, repo_root, &.{"--emit-dts"}, "v.js");
    try std.testing.expect(v128_code != 0);
    // ...while the same source still builds fine without --emit-dts.
    try std.testing.expectEqual(@as(u8, 0), try buildJsInTmp(v128_path, repo_root, &.{}, "v.js"));
}
