const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;
const containsPortablePath = helpers.containsPortablePath;
const writeManifestForPackage = helpers.writeManifestForPackage;
const writeProjectSum = helpers.writeProjectSum;

test "cli init creates a binary project and install syncs manifest dependencies" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const init_argv = [_][]const u8{ "sa", "init", "app" };
    const init_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        init_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), init_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "Initialized SA binary project: app"));
    try tmp.dir.access(std.testing.io, "app/sa.mod", .{ .read = true });
    try tmp.dir.access(std.testing.io, "app/src/main.sa", .{ .read = true });
    try tmp.dir.access(std.testing.io, "app/.gitignore", .{ .read = true });

    var app_dir = try tmp.dir.openDir(std.testing.io, "app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();
    const run_argv = [_][]const u8{ "sa", "run", "src/main.sa" };
    const run_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), run_code);

    try original_cwd.setAsCwd();
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    try tmp.dir.createDirPath(std.testing.io, "app/deps/example/pkg");
    try writeSource(tmp.dir, "app/deps/example/pkg/index.sa",
        \\@pkg_value() -> i32:
        \\return 42
    );
    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, "app/deps/example/pkg", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);
    var pkg_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/pkg", "HEAD", pkg_root, &.{});
    defer pkg_report.deinit(std.testing.allocator);
    const pkg_hash_hex = std.fmt.bytesToHex(pkg_report.source_sha256, .lower);
    const manifest_source = try std.fmt.allocPrint(
        std.testing.allocator,
        "require deps/example/pkg @HEAD sha256:{s}\n",
        .{pkg_hash_hex[0..]},
    );
    defer std.testing.allocator.free(manifest_source);
    try writeSource(tmp.dir, "app/sa.mod", manifest_source);
    try app_dir.setAsCwd();
    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const install_argv = [_][]const u8{ "sa", "install" };
    const install_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        install_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), install_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(try containsPortablePath(std.testing.allocator, stdout_buffer.items, "sa_vendor/deps/example/pkg"));
    try tmp.dir.access(std.testing.io, "app/sa_vendor/deps/example/pkg/index.sa", .{ .read = true });
    try tmp.dir.access(std.testing.io, "app/sa.sum", .{ .read = true });
}

test "workspace install aggregates member manifests at root and pkg install falls back to builtin workspace flow" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "members/app/src");
    try tmp.dir.createDirPath(std.testing.io, "members/tool/src");
    try tmp.dir.createDirPath(std.testing.io, "deps/example/shared");
    try tmp.dir.createDirPath(std.testing.io, "deps/example/app");
    try tmp.dir.createDirPath(std.testing.io, "deps/example/tool");

    try writeSource(tmp.dir, "members/app/src/main.sa",
        \\@main() -> i32:
        \\return 1
    );
    try writeSource(tmp.dir, "members/tool/src/main.sa",
        \\@main() -> i32:
        \\return 2
    );
    try writeSource(tmp.dir, "deps/example/shared/index.sa",
        \\@shared_value() -> i32:
        \\return 10
    );
    try writeSource(tmp.dir, "deps/example/app/index.sa",
        \\@app_value() -> i32:
        \\return 20
    );
    try writeSource(tmp.dir, "deps/example/tool/index.sa",
        \\@tool_value() -> i32:
        \\return 30
    );

    const shared_root = try tmp.dir.realPathFileAlloc(std.testing.io, "deps/example/shared", std.testing.allocator);
    defer std.testing.allocator.free(shared_root);
    const app_root = try tmp.dir.realPathFileAlloc(std.testing.io, "deps/example/app", std.testing.allocator);
    defer std.testing.allocator.free(app_root);
    const tool_root = try tmp.dir.realPathFileAlloc(std.testing.io, "deps/example/tool", std.testing.allocator);
    defer std.testing.allocator.free(tool_root);

    var shared_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/shared", "HEAD", shared_root, &.{});
    defer shared_report.deinit(std.testing.allocator);
    var app_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/app", "HEAD", app_root, &.{});
    defer app_report.deinit(std.testing.allocator);
    var tool_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/tool", "HEAD", tool_root, &.{});
    defer tool_report.deinit(std.testing.allocator);

    const shared_hash = std.fmt.bytesToHex(shared_report.source_sha256, .lower);
    const app_hash = std.fmt.bytesToHex(app_report.source_sha256, .lower);
    const tool_hash = std.fmt.bytesToHex(tool_report.source_sha256, .lower);

    const root_manifest_source = try std.fmt.allocPrint(std.testing.allocator,
        \\workspace {{
        \\  members ["members/app", "members/tool"]
        \\  default_member "app"
        \\}}
        \\
        \\require deps/example/shared @HEAD sha256:{s}
    , .{shared_hash[0..]});
    defer std.testing.allocator.free(root_manifest_source);
    try writeSource(tmp.dir, "sa.mod", root_manifest_source);

    const app_manifest_source = try std.fmt.allocPrint(std.testing.allocator,
        \\package "app"
        \\
        \\require deps/example/shared @HEAD sha256:{s}
        \\require deps/example/app @HEAD sha256:{s}
    , .{ shared_hash[0..], app_hash[0..] });
    defer std.testing.allocator.free(app_manifest_source);
    try writeSource(tmp.dir, "members/app/sa.mod", app_manifest_source);

    const tool_manifest_source = try std.fmt.allocPrint(std.testing.allocator,
        \\package "tool"
        \\
        \\require deps/example/shared @HEAD sha256:{s}
        \\require deps/example/tool @HEAD sha256:{s}
    , .{ shared_hash[0..], tool_hash[0..] });
    defer std.testing.allocator.free(tool_manifest_source);
    try writeSource(tmp.dir, "members/tool/sa.mod", tool_manifest_source);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const install_argv = [_][]const u8{ "sa", "install" };
    const install_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        install_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), install_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(try containsPortablePath(std.testing.allocator, stdout_buffer.items, "sa_vendor/deps/example/shared"));
    try std.testing.expect(try containsPortablePath(std.testing.allocator, stdout_buffer.items, "sa_vendor/deps/example/app"));
    try std.testing.expect(try containsPortablePath(std.testing.allocator, stdout_buffer.items, "sa_vendor/deps/example/tool"));
    try tmp.dir.access(std.testing.io, "sa_vendor/deps/example/shared/index.sa", .{ .read = true });
    try tmp.dir.access(std.testing.io, "sa_vendor/deps/example/app/index.sa", .{ .read = true });
    try tmp.dir.access(std.testing.io, "sa_vendor/deps/example/tool/index.sa", .{ .read = true });
    try tmp.dir.access(std.testing.io, "sa.sum", .{ .read = true });

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const pkg_install_argv = [_][]const u8{ "sa", "pkg", "install", "-p", "tool" };
    const pkg_install_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        pkg_install_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), pkg_install_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(try containsPortablePath(std.testing.allocator, stdout_buffer.items, "sa_vendor/deps/example/tool"));
}

test "package preflight rejects tampered project sum as structured trap" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "app/src");
    try tmp.dir.createDirPath(std.testing.io, "app/deps/example/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/deps/example/pkg/index.sa",
        \\@pkg_value() -> i32:
        \\return 42
    );

    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, "app/deps/example/pkg", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);
    var pkg_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/pkg", "HEAD", pkg_root, &.{});
    defer pkg_report.deinit(std.testing.allocator);
    const pkg_hash_hex = std.fmt.bytesToHex(pkg_report.source_sha256, .lower);
    const manifest_source = try std.fmt.allocPrint(
        std.testing.allocator,
        "require deps/example/pkg @HEAD sha256:{s}\n",
        .{pkg_hash_hex[0..]},
    );
    defer std.testing.allocator.free(manifest_source);
    try writeSource(tmp.dir, "app/sa.mod", manifest_source);

    var app_dir = try tmp.dir.openDir(std.testing.io, "app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const install_argv = [_][]const u8{ "sa", "install" };
    const install_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        install_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), install_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const bad_sum =
        \\deps/example/pkg @HEAD sha256:0000000000000000000000000000000000000000000000000000000000000000
        \\
    ;
    try writeSource(std.Io.Dir.cwd(), "sa.sum", bad_sum);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const run_argv = [_][]const u8{ "sa", "run", "src/main.sa", "--json" };
    const run_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), run_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"SumHashMismatch\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"status\":\"error\""));
}

test "PkgMgr-Confirm-NonTty rejects risky package preflight before build output" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "app/src");
    try tmp.dir.createDirPath(std.testing.io, "app/sa_vendor/risky/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/risky/pkg/index.sa",
        \\call @sys_net_tx(*BUF, 4)
        \\
    );
    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, "app/sa_vendor/risky/pkg", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);
    try writeManifestForPackage(tmp.dir, "app", "risky/pkg", pkg_root, "");
    try writeProjectSum(tmp.dir, "app");

    var app_dir = try tmp.dir.openDir(std.testing.io, "app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    var input = std.io.fixedBufferStream("");
    const build_argv = [_][]const u8{ "sa", "build-exe", "src/main.sa", "-o", "blocked.out", "--json" };
    const code = try saasm.cli.executeWithWritersAndOptions(
        std.testing.allocator,
        build_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
        .{ .stdin_reader = input.reader().any(), .stdin_is_tty = false },
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"MissingTtyForConfirmation\""));
    try std.testing.expectError(error.FileNotFound, sio.cwd().access("blocked.out", .{ .read = true }));
}

test "PkgMgr-Confirm-Tty accepts exact URL through compile preflight" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "app/src");
    try tmp.dir.createDirPath(std.testing.io, "app/sa_vendor/risky/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/risky/pkg/index.sa",
        \\call @sys_net_tx(*BUF, 4)
        \\
    );
    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, "app/sa_vendor/risky/pkg", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);
    try writeManifestForPackage(tmp.dir, "app", "risky/pkg", pkg_root, "");
    try writeProjectSum(tmp.dir, "app");

    var app_dir = try tmp.dir.openDir(std.testing.io, "app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    var input = std.io.fixedBufferStream("risky/pkg\n");
    const run_argv = [_][]const u8{ "sa", "run", "src/main.sa" };
    const code = try saasm.cli.executeWithWritersAndOptions(
        std.testing.allocator,
        run_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
        .{ .stdin_reader = input.reader().any(), .stdin_is_tty = true },
    );
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "SA ZERO-TRUST PACKAGE REVIEW REQUIRED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "type the exact package URL to continue: risky/pkg"));
}

test "PkgMgr-CI-DualTrack rejects mismatched source and unauthorized primitives" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "app/src");
    try tmp.dir.createDirPath(std.testing.io, "app/sa_vendor/ci/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/ci/pkg/index.sa",
        \\call @sys_net_tx(*BUF, 4)
        \\
    );
    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, "app/sa_vendor/ci/pkg", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);

    const bad_manifest =
        \\require ci/pkg @HEAD sha256:0000000000000000000000000000000000000000000000000000000000000000
        \\
    ;
    try writeSource(tmp.dir, "app/sa.mod", bad_manifest);

    var app_dir = try tmp.dir.openDir(std.testing.io, "app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const run_ci_argv = [_][]const u8{ "sa", "run", "src/main.sa", "--ci", "--json" };
    var code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_ci_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UpstreamShaMismatch\""));

    try original_cwd.setAsCwd();
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    try writeManifestForPackage(tmp.dir, "app", "ci/pkg", pkg_root, "");
    try app_dir.setAsCwd();

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_ci_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UnauthorizedPrimitive\""));
}

test "PkgMgr-Offline-Build uses vendored sources and project sum" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "app/src");
    try tmp.dir.createDirPath(std.testing.io, "app/sa_vendor/safe/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/safe/pkg/index.sa",
        \\@pkg_value() -> i32:
        \\return 42
    );
    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, "app/sa_vendor/safe/pkg", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);
    try writeManifestForPackage(tmp.dir, "app", "safe/pkg", pkg_root, "");
    try writeProjectSum(tmp.dir, "app");

    var app_dir = try tmp.dir.openDir(std.testing.io, "app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "src/main.sa", "--offline" };
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
