const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const Dependency = @import("resolver.zig").Dependency;
const packageTreeHash = @import("resolver.zig").packageTreeHash;
const pathEndsWithPortable = @import("resolver.zig").pathEndsWithPortable;
const resolveImport = @import("resolver.zig").resolveImport;

test "resolveImport prefers a relative source file" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "src");
    var source_file = try tmp.dir.createFile(std.testing.io, "src/module.sa", .{ .truncate = true });
    defer source_file.close(sio.io());
    {
        var wbuf: [8192]u8 = undefined;
        var wfb = source_file.writer(sio.io(), &wbuf);
        try wfb.interface.writeAll("@main() -> i32:\n    return 0\n");
        try wfb.interface.flush();
    }

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    const resolved = try resolveImport(
        std.testing.allocator,
        &.{},
        root,
        "src/module.sa",
        .{},
    );
    defer {
        var owned = resolved;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(pathEndsWithPortable(resolved.entry_path, "src/module.sa"));
    try std.testing.expectEqualStrings("@main() -> i32:\n    return 0\n", resolved.source);
    try std.testing.expect(resolved.root_dir == null);
}

test "resolveImport falls back to local vendor package roots" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "sa_vendor/github.com/example/pkg");
    var index = try tmp.dir.createFile(std.testing.io, "sa_vendor/github.com/example/pkg/index.sa", .{ .truncate = true });
    defer index.close(sio.io());
    {
        var wbuf: [8192]u8 = undefined;
        var wfb = index.writer(sio.io(), &wbuf);
        try wfb.interface.writeAll("@pkg() -> i32:\n    return 123\n");
        try wfb.interface.flush();
    }

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    const resolved = try resolveImport(
        std.testing.allocator,
        &.{},
        root,
        "github.com/example/pkg",
        .{ .project_root = root },
    );
    defer {
        var owned = resolved;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(resolved.root_dir != null);
    try std.testing.expect(pathEndsWithPortable(resolved.entry_path, "sa_vendor/github.com/example/pkg/index.sa"));
    try std.testing.expectEqualStrings("@pkg() -> i32:\n    return 123\n", resolved.source);
    try std.testing.expect(!resolved.is_global);
}

test "resolveImport maps global cache entries read-only" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, ".sa/pkg/github.com/example/pkg@v1");
    var index = try tmp.dir.createFile(std.testing.io, ".sa/pkg/github.com/example/pkg@v1/index.sa", .{ .truncate = true });
    defer index.close(sio.io());
    {
        var wbuf: [8192]u8 = undefined;
        var wfb = index.writer(sio.io(), &wbuf);
        try wfb.interface.writeAll("@global() -> i32:\n    return 7\n");
        try wfb.interface.flush();
    }

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);

    const dependency = Dependency{
        .url = "github.com/example/pkg",
        .ref = "v1",
    };

    const resolved = try resolveImport(
        std.testing.allocator,
        &.{dependency},
        home,
        "github.com/example/pkg",
        .{ .project_root = home, .home_dir = home },
    );
    defer {
        var owned = resolved;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(resolved.is_global);
    try std.testing.expect(resolved.mapped != null);
    try std.testing.expect(pathEndsWithPortable(resolved.entry_path, ".sa/pkg/github.com/example/pkg@v1/index.sa"));
    try std.testing.expectEqualStrings("@global() -> i32:\n    return 7\n", resolved.source);
}

test "resolveImport rejects package source when pinned sha mismatches" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, ".sa/pkg/github.com/example/pkg@v1");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".sa/pkg/github.com/example/pkg@v1/index.sa", .data = "@global() -> i32:\n    return 7\n" });

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);
    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, ".sa/pkg/github.com/example/pkg@v1", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);

    var pinned_hash = try packageTreeHash(std.testing.allocator, pkg_root);
    pinned_hash[0] ^= 0xff;
    const dependency = Dependency{
        .url = "github.com/example/pkg",
        .ref = "v1",
        .source_sha256 = pinned_hash,
    };

    try std.testing.expectError(
        error.UpstreamShaMismatch,
        resolveImport(
            std.testing.allocator,
            &.{dependency},
            home,
            "github.com/example/pkg",
            .{ .project_root = home, .home_dir = home },
        ),
    );
}

test "resolveImport accepts package source matching pinned sha" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, ".sa/pkg/github.com/example/pkg@v1");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".sa/pkg/github.com/example/pkg@v1/index.sa", .data = "@global() -> i32:\n    return 7\n" });

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);
    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, ".sa/pkg/github.com/example/pkg@v1", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);

    const dependency = Dependency{
        .url = "github.com/example/pkg",
        .ref = "v1",
        .source_sha256 = try packageTreeHash(std.testing.allocator, pkg_root),
    };

    const resolved = try resolveImport(
        std.testing.allocator,
        &.{dependency},
        home,
        "github.com/example/pkg",
        .{ .project_root = home, .home_dir = home },
    );
    defer {
        var owned = resolved;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(resolved.is_global);
}

test "resolveImport rejects package entry symlinks escaping the package root" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, ".sa/pkg/github.com/example/pkg@v1");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "outside.sa", .data = "@outside() -> i32:\n    return 9\n" });
    const outside_abs = try tmp.dir.realPathFileAlloc(std.testing.io, "outside.sa", std.testing.allocator);
    defer std.testing.allocator.free(outside_abs);
    try tmp.dir.symLink(std.testing.io, outside_abs, ".sa/pkg/github.com/example/pkg@v1/index.sa", .{});

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);
    const dependency = Dependency{
        .url = "github.com/example/pkg",
        .ref = "v1",
    };

    try std.testing.expectError(
        error.InvalidImportPath,
        resolveImport(
            std.testing.allocator,
            &.{dependency},
            home,
            "github.com/example/pkg",
            .{ .project_root = home, .home_dir = home },
        ),
    );
}

test "resolveImport returns PackageNotResolved when cache misses" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    try std.testing.expectError(
        error.PackageNotResolved,
        resolveImport(
            std.testing.allocator,
            &.{},
            root,
            "github.com/example/missing",
            .{ .project_root = root, .offline = true },
        ),
    );
}

test "resolveImport falls back to declared plugin interface roots" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "plugins/installed/deno/current/sa");
    var layout = try tmp.dir.createFile(std.testing.io, "plugins/installed/deno/current/sa/deno.sal", .{ .truncate = true });
    defer layout.close(sio.io());
    {
        var wbuf: [8192]u8 = undefined;
        var wfb = layout.writer(sio.io(), &wbuf);
        try wfb.interface.writeAll("@const DENO_OK: u64 = 1\n");
        try wfb.interface.flush();
    }

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const plugin_root = try tmp.dir.realPathFileAlloc(std.testing.io, "plugins/installed/deno/current/sa", std.testing.allocator);
    defer std.testing.allocator.free(plugin_root);

    const resolved = try resolveImport(
        std.testing.allocator,
        &.{},
        root,
        "deno.sal",
        .{ .project_root = root, .plugin_import_roots = &.{plugin_root} },
    );
    defer {
        var owned = resolved;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(resolved.is_global);
    try std.testing.expect(pathEndsWithPortable(resolved.entry_path, "plugins/installed/deno/current/sa/deno.sal"));
    try std.testing.expectEqualStrings("@const DENO_OK: u64 = 1\n", resolved.source);
}

test "resolveImport bounds globally mapped source size" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, ".sa/pkg/github.com/example/large@v1");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = ".sa/pkg/github.com/example/large@v1/index.sa",
        .data = "@large() -> i32:\n    return 123456789\n",
    });

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);
    const dependency = Dependency{ .url = "github.com/example/large", .ref = "v1" };

    try std.testing.expectError(
        error.PackageNotResolved,
        resolveImport(
            std.testing.allocator,
            &.{dependency},
            home,
            "github.com/example/large",
            .{ .project_root = home, .home_dir = home, .max_local_file_bytes = 8 },
        ),
    );
}

test "resolveImport resolves qualified plugin imports inside the named plugin only" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "plugins/installed/deno/current/sa");
    try tmp.dir.createDirPath(std.testing.io, "plugins/installed/node/current/sa");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "plugins/installed/deno/current/sa/shared.sal",
        .data = "@const ORIGIN: u64 = 1\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "plugins/installed/node/current/sa/shared.sal",
        .data = "@const ORIGIN: u64 = 2\n",
    });

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const deno_root = try tmp.dir.realPathFileAlloc(std.testing.io, "plugins/installed/deno/current/sa", std.testing.allocator);
    defer std.testing.allocator.free(deno_root);
    const node_root = try tmp.dir.realPathFileAlloc(std.testing.io, "plugins/installed/node/current/sa", std.testing.allocator);
    defer std.testing.allocator.free(node_root);
    const roots = [_][]const u8{ deno_root, node_root };

    // Bare imports keep the legacy first-root-wins behavior.
    {
        const resolved = try resolveImport(std.testing.allocator, &.{}, root, "shared.sal", .{ .project_root = root, .plugin_import_roots = &roots });
        defer {
            var owned = resolved;
            owned.deinit(std.testing.allocator);
        }
        try std.testing.expectEqualStrings("@const ORIGIN: u64 = 1\n", resolved.source);
    }
    // A qualified import names its plugin and resolves there even
    // when an earlier root ships the same relative path.
    {
        const resolved = try resolveImport(std.testing.allocator, &.{}, root, "plugin/node/shared.sal", .{ .project_root = root, .plugin_import_roots = &roots });
        defer {
            var owned = resolved;
            owned.deinit(std.testing.allocator);
        }
        try std.testing.expectEqualStrings("@const ORIGIN: u64 = 2\n", resolved.source);
        try std.testing.expect(pathEndsWithPortable(resolved.entry_path, "plugins/installed/node/current/sa/shared.sal"));
    }
    {
        const resolved = try resolveImport(std.testing.allocator, &.{}, root, "plugin/deno/shared.sal", .{ .project_root = root, .plugin_import_roots = &roots });
        defer {
            var owned = resolved;
            owned.deinit(std.testing.allocator);
        }
        try std.testing.expectEqualStrings("@const ORIGIN: u64 = 1\n", resolved.source);
    }
    // Qualified imports never fall through: unknown plugin names and
    // files the named plugin does not ship are explicit failures.
    try std.testing.expectError(error.PackageNotResolved, resolveImport(std.testing.allocator, &.{}, root, "plugin/missing/shared.sal", .{ .project_root = root, .plugin_import_roots = &roots }));
    try std.testing.expectError(error.PackageNotResolved, resolveImport(std.testing.allocator, &.{}, root, "plugin/deno/absent.sal", .{ .project_root = root, .plugin_import_roots = &roots }));
}

test "resolveImport reports ambiguous bare plugin imports through the diagnostics sink" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "plugins/installed/deno/current/sa");
    try tmp.dir.createDirPath(std.testing.io, "plugins/installed/node/current/sa");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "plugins/installed/deno/current/sa/shared.sal",
        .data = "@const ORIGIN: u64 = 1\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "plugins/installed/node/current/sa/shared.sal",
        .data = "@const ORIGIN: u64 = 2\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "plugins/installed/deno/current/sa/only_deno.sal",
        .data = "@const ORIGIN: u64 = 3\n",
    });

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const deno_root = try tmp.dir.realPathFileAlloc(std.testing.io, "plugins/installed/deno/current/sa", std.testing.allocator);
    defer std.testing.allocator.free(deno_root);
    const node_root = try tmp.dir.realPathFileAlloc(std.testing.io, "plugins/installed/node/current/sa", std.testing.allocator);
    defer std.testing.allocator.free(node_root);
    const roots = [_][]const u8{ deno_root, node_root };

    const Capture = struct {
        messages: std.array_list.Managed([]u8),

        fn onDiagnostic(ctx: ?*anyopaque, message: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            const copy = std.testing.allocator.dupe(u8, message) catch return;
            self.messages.append(copy) catch std.testing.allocator.free(copy);
        }
    };
    var capture = Capture{ .messages = std.array_list.Managed([]u8).init(std.testing.allocator) };
    defer {
        for (capture.messages.items) |message| std.testing.allocator.free(message);
        capture.messages.deinit();
    }

    // Bare import provided by both roots: first root still wins, and
    // exactly one diagnostic names the winner and the shadowed plugin.
    {
        const resolved = try resolveImport(std.testing.allocator, &.{}, root, "shared.sal", .{
            .project_root = root,
            .plugin_import_roots = &roots,
            .diagnostics = &Capture.onDiagnostic,
            .diagnostics_ctx = &capture,
        });
        defer {
            var owned = resolved;
            owned.deinit(std.testing.allocator);
        }
        try std.testing.expectEqualStrings("@const ORIGIN: u64 = 1\n", resolved.source);
    }
    try std.testing.expectEqual(@as(usize, 1), capture.messages.items.len);
    const message = capture.messages.items[0];
    try std.testing.expect(std.mem.indexOf(u8, message, "ambiguous plugin import 'shared.sal'") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "using deno") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "shadowed: node") != null);

    // A bare import only one root provides stays quiet.
    {
        const resolved = try resolveImport(std.testing.allocator, &.{}, root, "only_deno.sal", .{
            .project_root = root,
            .plugin_import_roots = &roots,
            .diagnostics = &Capture.onDiagnostic,
            .diagnostics_ctx = &capture,
        });
        defer {
            var owned = resolved;
            owned.deinit(std.testing.allocator);
        }
        try std.testing.expectEqualStrings("@const ORIGIN: u64 = 3\n", resolved.source);
    }
    try std.testing.expectEqual(@as(usize, 1), capture.messages.items.len);

    // A qualified import is explicit by construction: no diagnostic.
    {
        const resolved = try resolveImport(std.testing.allocator, &.{}, root, "plugin/node/shared.sal", .{
            .project_root = root,
            .plugin_import_roots = &roots,
            .diagnostics = &Capture.onDiagnostic,
            .diagnostics_ctx = &capture,
        });
        defer {
            var owned = resolved;
            owned.deinit(std.testing.allocator);
        }
        try std.testing.expectEqualStrings("@const ORIGIN: u64 = 2\n", resolved.source);
    }
    try std.testing.expectEqual(@as(usize, 1), capture.messages.items.len);
}
