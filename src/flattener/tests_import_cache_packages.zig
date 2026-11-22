const std = @import("std");
const sio = @import("sio");
const pkg_resolver = @import("../pkg/resolver.zig");
const ResolveContext = @import("importexpansion.zig").ResolveContext;
const expanded_import_cache = @import("importexpansion.zig").expanded_import_cache;
const expanded_import_cache_mutex = @import("importexpansion.zig").expanded_import_cache_mutex;
const expanded_import_cache_tick = @import("importexpansion.zig").expanded_import_cache_tick;
const flattenFile = @import("expandimportsinto.zig").flattenFile;
const flattenFileWithPackages = @import("expandimportsinto.zig").flattenFileWithPackages;
const freeExpandedImportCacheEntry = @import("importexpansion.zig").freeExpandedImportCacheEntry;
const freeImportSourceCacheEntry = @import("importexpansion.zig").freeImportSourceCacheEntry;
const import_source_cache = @import("importexpansion.zig").import_source_cache;
const import_source_cache_mutex = @import("importexpansion.zig").import_source_cache_mutex;
const import_source_cache_tick = @import("importexpansion.zig").import_source_cache_tick;
const isFunctionSigDeclared = @import("emitparsedline.zig").isFunctionSigDeclared;
const packageNamespacePrefix = @import("injectimportedfile.zig").packageNamespacePrefix;
const readImportFile = @import("injectimportedfile.zig").readImportFile;
const test_expanded_import_cache_hits = @import("importexpansion.zig").test_expanded_import_cache_hits;
const test_expanded_import_cache_max_entries = @import("importexpansion.zig").test_expanded_import_cache_max_entries;
const test_expanded_import_cache_stores = @import("importexpansion.zig").test_expanded_import_cache_stores;
const test_import_source_cache_max_entries = @import("importexpansion.zig").test_import_source_cache_max_entries;


pub fn clearImportSourceCacheForTest() void {
    while (!import_source_cache_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer import_source_cache_mutex.unlock();
    if (import_source_cache) |*cache| {
        var it = cache.iterator();
        while (it.next()) |entry| {
            std.heap.page_allocator.free(entry.key_ptr.*);
            freeImportSourceCacheEntry(entry.value_ptr.*, true);
        }
        cache.deinit();
        import_source_cache = null;
    }
    import_source_cache_tick = 0;
    test_import_source_cache_max_entries = null;
}

fn importSourceCacheHasEntryPathForTest(path: []const u8) bool {
    while (!import_source_cache_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer import_source_cache_mutex.unlock();
    const cache = if (import_source_cache) |*cache| cache else return false;
    var it = cache.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.entry_path, path)) return true;
    }
    return false;
}

pub fn clearExpandedImportCacheForTest() void {
    while (!expanded_import_cache_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer expanded_import_cache_mutex.unlock();
    if (expanded_import_cache) |*cache| {
        var it = cache.iterator();
        while (it.next()) |entry| {
            std.heap.page_allocator.free(entry.key_ptr.*);
            freeExpandedImportCacheEntry(entry.value_ptr.*);
        }
        cache.deinit();
        expanded_import_cache = null;
    }
    expanded_import_cache_tick = 0;
    test_expanded_import_cache_max_entries = null;
    test_expanded_import_cache_hits = 0;
    test_expanded_import_cache_stores = 0;
}

test "expanded import cache reuses expanded std fragments across flatten calls" {
    clearImportSourceCacheForTest();
    defer clearImportSourceCacheForTest();
    clearExpandedImportCacheForTest();
    defer clearExpandedImportCacheForTest();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_std/core");
    {
        var file = try tdir.createFile("sa_std/core/cache_expanded.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def EXPANDED_CACHE_VALUE = 7\n");
    }
    {
        var file = try tdir.createFile("main_a.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/cache_expanded.sai"
            \\@main() -> i32:
            \\return EXPANDED_CACHE_VALUE
            \\
        );
    }
    {
        var file = try tdir.createFile("main_b.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/cache_expanded.sai"
            \\@main() -> i32:
            \\return EXPANDED_CACHE_VALUE
            \\
        );
    }

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try tdir.realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);
    const resolve_ctx = ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };

    const source_a = try tdir.readFileAlloc(std.testing.allocator, "main_a.sa", 4096);
    defer std.testing.allocator.free(source_a);
    const source_path_a = try tdir.realpathAlloc(std.testing.allocator, "main_a.sa");
    defer std.testing.allocator.free(source_path_a);
    var first = try flattenFileWithPackages(std.testing.allocator, source_path_a, source_a, resolve_ctx);
    defer first.deinit(std.testing.allocator);
    try std.testing.expect(test_expanded_import_cache_stores > 0);
    try std.testing.expectEqual(@as(usize, 0), test_expanded_import_cache_hits);

    const source_b = try tdir.readFileAlloc(std.testing.allocator, "main_b.sa", 4096);
    defer std.testing.allocator.free(source_b);
    const source_path_b = try tdir.realpathAlloc(std.testing.allocator, "main_b.sa");
    defer std.testing.allocator.free(source_path_b);
    var second = try flattenFileWithPackages(std.testing.allocator, source_path_b, source_b, resolve_ctx);
    defer second.deinit(std.testing.allocator);
    try std.testing.expect(test_expanded_import_cache_hits > 0);
    try std.testing.expectEqual(first.instructions.len, second.instructions.len);
}

test "expanded import cache invalidates when transitive import changes" {
    clearImportSourceCacheForTest();
    defer clearImportSourceCacheForTest();
    clearExpandedImportCacheForTest();
    defer clearExpandedImportCacheForTest();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_std/core");
    {
        var file = try tdir.createFile("sa_std/core/cache_mutable.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def EXPANDED_CACHE_VALUE = 7\n");
    }
    const main_source =
        \\@import "sa_std/core/cache_mutable.sai"
        \\@main() -> i32:
        \\return EXPANDED_CACHE_VALUE
        \\
    ;
    {
        var file = try tdir.createFile("main_a.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(main_source);
    }
    {
        var file = try tdir.createFile("main_b.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(main_source);
    }

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try tdir.realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);
    const resolve_ctx = ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };

    const source_a = try tdir.readFileAlloc(std.testing.allocator, "main_a.sa", 4096);
    defer std.testing.allocator.free(source_a);
    const source_path_a = try tdir.realpathAlloc(std.testing.allocator, "main_a.sa");
    defer std.testing.allocator.free(source_path_a);
    var first = try flattenFileWithPackages(std.testing.allocator, source_path_a, source_a, resolve_ctx);
    defer first.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("7", first.def_dict.get("EXPANDED_CACHE_VALUE").?);

    {
        var file = try tdir.createFile("sa_std/core/cache_mutable.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def EXPANDED_CACHE_VALUE = 777\n");
    }
    test_expanded_import_cache_hits = 0;
    const source_b = try tdir.readFileAlloc(std.testing.allocator, "main_b.sa", 4096);
    defer std.testing.allocator.free(source_b);
    const source_path_b = try tdir.realpathAlloc(std.testing.allocator, "main_b.sa");
    defer std.testing.allocator.free(source_path_b);
    var second = try flattenFileWithPackages(std.testing.allocator, source_path_b, source_b, resolve_ctx);
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), test_expanded_import_cache_hits);
    try std.testing.expectEqualStrings("777", second.def_dict.get("EXPANDED_CACHE_VALUE").?);
}

test "expanded import cache does not store fragments that skipped caller-seen imports" {
    clearImportSourceCacheForTest();
    defer clearImportSourceCacheForTest();
    clearExpandedImportCacheForTest();
    defer clearExpandedImportCacheForTest();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_std/core");
    {
        var file = try tdir.createFile("sa_std/core/dep.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@dep_value() -> u64:
            \\L_ENTRY:
            \\    return 42
            \\
        );
    }
    {
        var file = try tdir.createFile("sa_std/core/wrapper.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "dep.sa"
            \\
            \\[MACRO] WRAP_CALL %out
            \\    %out = call @dep_value()
            \\[END_MACRO]
            \\
        );
    }
    {
        var file = try tdir.createFile("main_a.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/dep.sa"
            \\@import "sa_std/core/wrapper.sa"
            \\@main() -> i32:
            \\L_ENTRY:
            \\    EXPAND WRAP_CALL value
            \\    !value
            \\    return 0
            \\
        );
    }
    {
        var file = try tdir.createFile("main_b.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/wrapper.sa"
            \\@main() -> i32:
            \\L_ENTRY:
            \\    EXPAND WRAP_CALL value
            \\    !value
            \\    return 0
            \\
        );
    }

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try tdir.realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);
    const resolve_ctx = ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };

    const source_a = try tdir.readFileAlloc(std.testing.allocator, "main_a.sa", 4096);
    defer std.testing.allocator.free(source_a);
    const source_path_a = try tdir.realpathAlloc(std.testing.allocator, "main_a.sa");
    defer std.testing.allocator.free(source_path_a);
    var first = try flattenFileWithPackages(std.testing.allocator, source_path_a, source_a, resolve_ctx);
    defer first.deinit(std.testing.allocator);

    const source_b = try tdir.readFileAlloc(std.testing.allocator, "main_b.sa", 4096);
    defer std.testing.allocator.free(source_b);
    const source_path_b = try tdir.realpathAlloc(std.testing.allocator, "main_b.sa");
    defer std.testing.allocator.free(source_path_b);
    var second = try flattenFileWithPackages(std.testing.allocator, source_path_b, source_b, resolve_ctx);
    defer second.deinit(std.testing.allocator);

    var saw_dep = false;
    for (second.function_sigs) |sig| {
        if (std.mem.eql(u8, sig.name, "dep_value")) saw_dep = true;
    }
    try std.testing.expect(saw_dep);
}

test "expanded import cache LRU is opt-in" {
    clearImportSourceCacheForTest();
    defer clearImportSourceCacheForTest();
    clearExpandedImportCacheForTest();
    defer clearExpandedImportCacheForTest();
    test_expanded_import_cache_max_entries = 1;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_std/core");
    {
        var file = try tdir.createFile("sa_std/core/cache_lru_a.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def EXPANDED_CACHE_VALUE = 11\n");
    }
    {
        var file = try tdir.createFile("sa_std/core/cache_lru_b.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def EXPANDED_CACHE_VALUE = 22\n");
    }
    {
        var file = try tdir.createFile("main_a.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/cache_lru_a.sai"
            \\@main() -> i32:
            \\return EXPANDED_CACHE_VALUE
            \\
        );
    }
    {
        var file = try tdir.createFile("main_b.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/cache_lru_b.sai"
            \\@main() -> i32:
            \\return EXPANDED_CACHE_VALUE
            \\
        );
    }

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try tdir.realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);
    const resolve_ctx = ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };

    const source_a = try tdir.readFileAlloc(std.testing.allocator, "main_a.sa", 4096);
    defer std.testing.allocator.free(source_a);
    const source_path_a = try tdir.realpathAlloc(std.testing.allocator, "main_a.sa");
    defer std.testing.allocator.free(source_path_a);
    var first_a = try flattenFileWithPackages(std.testing.allocator, source_path_a, source_a, resolve_ctx);
    defer first_a.deinit(std.testing.allocator);

    const source_b = try tdir.readFileAlloc(std.testing.allocator, "main_b.sa", 4096);
    defer std.testing.allocator.free(source_b);
    const source_path_b = try tdir.realpathAlloc(std.testing.allocator, "main_b.sa");
    defer std.testing.allocator.free(source_path_b);
    var first_b = try flattenFileWithPackages(std.testing.allocator, source_path_b, source_b, resolve_ctx);
    defer first_b.deinit(std.testing.allocator);

    test_expanded_import_cache_hits = 0;
    var second_a = try flattenFileWithPackages(std.testing.allocator, source_path_a, source_a, resolve_ctx);
    defer second_a.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), test_expanded_import_cache_hits);
    try std.testing.expectEqualStrings("11", second_a.def_dict.get("EXPANDED_CACHE_VALUE").?);
}

test "layout import exposes sibling extern declarations from sai" {
    clearImportSourceCacheForTest();
    defer clearImportSourceCacheForTest();
    clearExpandedImportCacheForTest();
    defer clearExpandedImportCacheForTest();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    {
        var sai = try tdir.createFile("db.sai", .{ .truncate = true });
        defer sai.close();
        try sai.writeAll("@extern sa_db_tx_insert_rows(handle: ptr, &rows: ptr, rows_len: u64, row_count: u64, &out_info: ptr) -> u32\n");
    }
    {
        var sal = try tdir.createFile("db.sal", .{ .truncate = true });
        defer sal.close();
        try sal.writeAll("@import \"db.sai\"\n");
    }
    {
        var main = try tdir.createFile("main.sa", .{ .truncate = true });
        defer main.close();
        try main.writeAll(
            \\@import "db.sal"
            \\
            \\@main() -> i32:
            \\L_ENTRY:
            \\    rows = stack_alloc 8
            \\    info = stack_alloc 32
            \\    handle = stack_alloc 8
            \\    store handle+0, 0 as ptr
            \\    status = call @sa_db_tx_insert_rows(handle, &rows, 8, 1, &info)
            \\    return status
            \\
        );
    }

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const resolve_ctx = ResolveContext{ .options = .{ .project_root = project_root } };
    const source = try tdir.readFileAlloc(std.testing.allocator, "main.sa", 4096);
    defer std.testing.allocator.free(source);
    const source_path = try tdir.realpathAlloc(std.testing.allocator, "main.sa");
    defer std.testing.allocator.free(source_path);

    var result = try flattenFileWithPackages(std.testing.allocator, source_path, source, resolve_ctx);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(isFunctionSigDeclared(result.function_sigs, "sa_db_tx_insert_rows"));
}

test "import source cache LRU is opt-in and avoids borrowed hits" {
    clearImportSourceCacheForTest();
    defer clearImportSourceCacheForTest();
    test_import_source_cache_max_entries = 2;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_std/core");
    var a_file = try tdir.createFile("sa_std/core/cache_a.sai", .{ .truncate = true });
    try a_file.writeAll("#def CACHE_A = 1\n");
    a_file.close();
    var b_file = try tdir.createFile("sa_std/core/cache_b.sai", .{ .truncate = true });
    try b_file.writeAll("#def CACHE_B = 2\n");
    b_file.close();
    var c_file = try tdir.createFile("sa_std/core/cache_c.sai", .{ .truncate = true });
    try c_file.writeAll("#def CACHE_C = 3\n");
    c_file.close();

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try tdir.realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);
    const a_path = try tdir.realpathAlloc(std.testing.allocator, "sa_std/core/cache_a.sai");
    defer std.testing.allocator.free(a_path);
    const b_path = try tdir.realpathAlloc(std.testing.allocator, "sa_std/core/cache_b.sai");
    defer std.testing.allocator.free(b_path);
    const c_path = try tdir.realpathAlloc(std.testing.allocator, "sa_std/core/cache_c.sai");
    defer std.testing.allocator.free(c_path);
    const resolve_ctx = ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };

    var first_a = try readImportFile(std.testing.allocator, project_root, "sa_std/core/cache_a.sai", resolve_ctx);
    defer first_a.deinit(std.testing.allocator);
    var first_b = try readImportFile(std.testing.allocator, project_root, "sa_std/core/cache_b.sai", resolve_ctx);
    defer first_b.deinit(std.testing.allocator);

    var second_a = try readImportFile(std.testing.allocator, project_root, "sa_std/core/cache_a.sai", resolve_ctx);
    defer second_a.deinit(std.testing.allocator);
    try std.testing.expect(second_a.owned_source != null);

    var first_c = try readImportFile(std.testing.allocator, project_root, "sa_std/core/cache_c.sai", resolve_ctx);
    defer first_c.deinit(std.testing.allocator);
    try std.testing.expect(importSourceCacheHasEntryPathForTest(a_path));
    try std.testing.expect(!importSourceCacheHasEntryPathForTest(b_path));
    try std.testing.expect(importSourceCacheHasEntryPathForTest(c_path));
}

test "stable import roots participate in import source cache" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("tests/unit_framework/support");
    var support = try tdir.createFile("tests/unit_framework/support/index.sa", .{ .truncate = true });
    try support.writeAll("@support_value() -> i32:\nreturn 42\n");
    support.close();

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const stable_root = try tdir.realpathAlloc(std.testing.allocator, "tests/unit_framework/support");
    defer std.testing.allocator.free(stable_root);
    const base_dir = try tdir.realpathAlloc(std.testing.allocator, "tests/unit_framework");
    defer std.testing.allocator.free(base_dir);
    const stable_roots = [_][]const u8{stable_root};
    const resolve_ctx = ResolveContext{ .options = .{ .project_root = project_root, .stable_import_roots = stable_roots[0..] } };

    var first = try readImportFile(std.testing.allocator, base_dir, "support/index.sa", resolve_ctx);
    defer first.deinit(std.testing.allocator);
    try std.testing.expect(first.owned_source != null);
    try std.testing.expectEqualStrings("@support_value() -> i32:\nreturn 42\n", first.source);

    var second = try readImportFile(std.testing.allocator, base_dir, "support/index.sa", resolve_ctx);
    defer second.deinit(std.testing.allocator);
    try std.testing.expect(second.owned_source == null);
    try std.testing.expectEqualStrings(first.source, second.source);
}

test "flattenFileWithPackages injects package iface and namespaced layout defs once" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_vendor/github.com/example/pkg");

    var pkg_main = try tdir.createFile("sa_vendor/github.com/example/pkg/index.sa", .{ .truncate = true });
    try pkg_main.writeAll("// package body intentionally empty\n");
    pkg_main.close();

    var pkg_iface = try tdir.createFile("sa_vendor/github.com/example/pkg/index.sai", .{ .truncate = true });
    try pkg_iface.writeAll("@extern pkg_iface() -> i32\n");
    pkg_iface.close();

    var pkg_layout = try tdir.createFile("sa_vendor/github.com/example/pkg/index.sal", .{ .truncate = true });
    try pkg_layout.writeAll(
        \\#version 1
        \\#def Pkg_SIZE = 4
    );
    pkg_layout.close();

    var main_file = try tdir.createFile("main.sa", .{ .truncate = true });
    try main_file.writeAll(
        \\@import "github.com/example/pkg"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    return 0
    );
    main_file.close();

    const source = try tdir.readFileAlloc(std.testing.allocator, "main.sa", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tdir.realpathAlloc(std.testing.allocator, "main.sa");
    defer std.testing.allocator.free(source_path);

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);

    var result = try flattenFileWithPackages(
        std.testing.allocator,
        source_path,
        source,
        .{
            .options = .{ .project_root = project_root },
        },
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.function_sigs.len);
    try std.testing.expectEqualStrings("pkg_iface", result.function_sigs[0].name);
    try std.testing.expectEqualStrings("main", result.function_sigs[1].name);
    try std.testing.expectEqual(@as(usize, 1), result.layout_versions.len);
    try std.testing.expectEqual(@as(u64, 1), result.layout_versions[0].version);

    const prefix = try packageNamespacePrefix(std.testing.allocator, "github.com/example/pkg");
    defer std.testing.allocator.free(prefix);
    const namespaced_key = try std.fmt.allocPrint(std.testing.allocator, "{s}.Pkg_SIZE", .{prefix});
    defer std.testing.allocator.free(namespaced_key);
    try std.testing.expectEqualStrings("4", result.def_dict.get(namespaced_key).?);
}

test "flattenFileWithPackages preserves package identity on imported instructions" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_vendor/github.com/example/pkg");

    var pkg_main = try tdir.createFile("sa_vendor/github.com/example/pkg/index.sa", .{ .truncate = true });
    try pkg_main.writeAll(
        \\@main() -> i32:
        \\L_ENTRY:
        \\path = alloc 8
        \\data = alloc 8
        \\value = call @sys_write_file(*path, 4, *data, 4)
        \\!path
        \\!data
        \\return value
    );
    pkg_main.close();

    var main_file = try tdir.createFile("main.sa", .{ .truncate = true });
    try main_file.writeAll(
        \\@import "github.com/example/pkg"
    );
    main_file.close();

    const source = try tdir.readFileAlloc(std.testing.allocator, "main.sa", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tdir.realpathAlloc(std.testing.allocator, "main.sa");
    defer std.testing.allocator.free(source_path);

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);

    var resolved = try pkg_resolver.resolveImport(
        std.testing.allocator,
        &.{},
        project_root,
        "github.com/example/pkg",
        .{ .project_root = project_root },
    );
    defer resolved.deinit(std.testing.allocator);
    const expected_hash = resolved.source_sha256 orelse return error.TestUnexpectedResult;

    var result = try flattenFileWithPackages(
        std.testing.allocator,
        source_path,
        source,
        .{
            .options = .{ .project_root = project_root },
        },
    );
    defer result.deinit(std.testing.allocator);

    var saw_pkg_instruction = false;
    var saw_pkg_call = false;
    for (result.instructions) |item| {
        if (item.package_identity) |identity| {
            if (std.mem.eql(u8, identity, "github.com/example/pkg")) {
                saw_pkg_instruction = true;
                try std.testing.expect(item.package_source_sha256 != null);
                const actual_hash = item.package_source_sha256.?;
                try std.testing.expect(std.mem.eql(u8, actual_hash[0..], expected_hash[0..]));
                if (std.mem.eql(u8, item.raw_text, "value = call @sys_write_file(*path, 4, *data, 4)")) {
                    saw_pkg_call = true;
                }
            }
        }
    }
    try std.testing.expect(saw_pkg_instruction);
    try std.testing.expect(saw_pkg_call);
}

test "flattenFile rejects import cycles" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    var a_file = try tdir.createFile("a.sa", .{ .truncate = true });
    try a_file.writeAll("@import \"b.sa\"\n");
    a_file.close();

    var b_file = try tdir.createFile("b.sa", .{ .truncate = true });
    try b_file.writeAll("@import \"a.sa\"\n");
    b_file.close();

    const source = try tdir.readFileAlloc(std.testing.allocator, "a.sa", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tdir.realpathAlloc(std.testing.allocator, "a.sa");
    defer std.testing.allocator.free(source_path);

    try std.testing.expectError(error.ImportCycle, flattenFile(std.testing.allocator, source_path, source));
}
