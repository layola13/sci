const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;
const writeBytes = helpers.writeBytes;
const extractLineValue = helpers.extractLineValue;
const wasmImportNames = helpers.wasmImportNames;

test "build-wasm supports wasm64 freestanding no-entry" {
    const source =
        \\@main() -> i32:
        \\return 0
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "wasm64.sa", source);

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", "wasm64.sa", "-o", "wasm64.wasm", "--target", "wasm64" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const wasm_file = try tmp.dir.openFile(std.testing.io, "wasm64.wasm", .{});
    defer wasm_file.close(std.testing.io);
    const wasm_bytes = try sio.readToEndAlloc(wasm_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
    const import_names = try wasmImportNames(wasm_bytes, std.testing.allocator);
    defer std.testing.allocator.free(import_names);
    try std.testing.expectEqual(@as(usize, 0), import_names.len);
}

test "db cli init writes iface and table lifecycle commands update storage" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "flash_sale.sadb-schema",
        \\#def MAX_ROWS = 10
        \\#def COL_ID_STRIDE = 8 // u64
        \\#def COL_PRICE_STRIDE = 4 // f32
    );
    try writeSource(tmp.dir, "rows.csv",
        \\ID,PRICE
        \\1,9.5
        \\2,10.25
    );
    try writeSource(tmp.dir, "more.jsonl",
        \\{"ID":3,"PRICE":11.75}
    );

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const init_argv = [_][]const u8{ "sa", "db", "init", "flash_sale.sadb-schema" };
    const init_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        init_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), init_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "flash_sale.iface"));

    const iface_file = try tmp.dir.openFile(std.testing.io, "flash_sale.iface", .{});
    defer iface_file.close(std.testing.io);
    const iface_bytes = try sio.readToEndAlloc(iface_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(iface_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, iface_bytes, 1, "#def MAX_ROWS = 10"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iface_bytes, 1, "#def TABLE_ROW_BYTES = 12"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iface_bytes, 1, "#def flash_sale_ROW_BYTES = 12"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const ingest_argv = [_][]const u8{ "sa", "db", "ingest", "flash_sale", "rows.csv" };
    const ingest_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        ingest_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), ingest_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "row_count: 2"));

    const meta_file = try tmp.dir.openFile(std.testing.io, "flash_sale.meta", .{});
    defer meta_file.close(std.testing.io);
    const meta_bytes = try sio.readToEndAlloc(meta_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(meta_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, meta_bytes, 1, "\"row_count\":2"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const snapshot_argv = [_][]const u8{ "sa", "db", "snapshot", "flash_sale" };
    const snapshot_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        snapshot_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), snapshot_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "epoch: 1"));
    const snapshot_meta = try tmp.dir.openFile(std.testing.io, ".sa/db/snapshots/flash_sale/1/flash_sale.meta", .{});
    defer snapshot_meta.close();

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const second_ingest_argv = [_][]const u8{ "sa", "db", "ingest", "flash_sale", "more.jsonl" };
    const second_ingest_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        second_ingest_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), second_ingest_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "row_count: 3"));

    const updated_meta_file = try tmp.dir.openFile(std.testing.io, "flash_sale.meta", .{});
    defer updated_meta_file.close(std.testing.io);
    const updated_meta_bytes = try sio.readToEndAlloc(updated_meta_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(updated_meta_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, updated_meta_bytes, 1, "\"row_count\":3"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const verify_argv = [_][]const u8{ "sa", "db", "verify", "flash_sale" };
    const verify_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        verify_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), verify_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "row_count: 3"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const compact_argv = [_][]const u8{ "sa", "db", "compact", "flash_sale" };
    const compact_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        compact_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), compact_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "segment_count: 1"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const restore_argv = [_][]const u8{ "sa", "db", "restore", "flash_sale", "1" };
    const restore_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        restore_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), restore_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "row_count: 2"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const lock_argv = [_][]const u8{ "sa", "db", "lock", "flash_sale" };
    const lock_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        lock_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), lock_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "locked: true"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const locked_compact_argv = [_][]const u8{ "sa", "db", "compact", "flash_sale" };
    const locked_compact_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        locked_compact_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), locked_compact_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "error: Locked"));
}

test "db cli register inspect exec round trip through registry" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "simple.sadb-schema",
        \\#def MAX_ROWS = 10
        \\#def COL_ID_STRIDE = 8 // u64
        \\#def COL_FACTOR_STRIDE = 8 // u64
        \\#def TABLE_ROW_BYTES = 16
    );
    try writeSource(tmp.dir, "simple.query.sa",
        \\@import "simple.sadb-schema"
        \\grants [db_read:simple]
        \\@main(id: u64, factor: u64) -> u64:
        \\L_ENTRY:
        \\total = add id, factor
        \\!id
        \\!factor
        \\return total
    );

    var params = std.array_list.Managed(u8).init(std.testing.allocator);
    defer params.deinit();
    try sio.managedWriter(&params).writeInt(u64, 7, .little);
    try sio.managedWriter(&params).writeInt(u64, 5, .little);
    try writeBytes(tmp.dir, "params.bin", params.items);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const register_argv = [_][]const u8{ "sa", "db", "register", "simple.query.sa" };
    const register_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        register_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), register_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "Compiled: simple.query.sa"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "Registered:"));

    const hash_hex = try std.testing.allocator.dupe(u8, try extractLineValue(stdout_buffer.items, "Hash: "));
    defer std.testing.allocator.free(hash_hex);
    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const inspect_argv = [_][]const u8{ "sa", "db", "inspect", hash_hex };
    const inspect_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        inspect_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), inspect_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "imports: 1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "grants: 1"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const exec_argv = [_][]const u8{ "sa", "db", "exec", hash_hex, "--params", "params.bin" };
    const exec_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        exec_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 12), exec_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "layout cli prints text, json, and debug macro outputs" {
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const text_argv = [_][]const u8{ "sa", "layout", "--name", "Entity", "--fields", "id:u32, pos_x:f64, pos_y:f64, hp:i32" };
    const text_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        text_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), text_code);
    try std.testing.expectEqualStrings(
        "#def Entity_SIZE  = 32\n#def Entity_id = +0\n// 4 bytes padding\n#def Entity_pos_x = +8\n#def Entity_pos_y = +16\n#def Entity_hp = +24\n// 4 bytes tail padding\n",
        stdout_buffer.items,
    );
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const json_argv = [_][]const u8{ "sa", "layout", "--name", "Pair", "--fields", "head:ptr, count:u32", "--format", "json", "--target", "32" };
    const json_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        json_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), json_code);
    try std.testing.expectEqualStrings(
        "{\"name\":\"Pair\",\"size\":8,\"fields\":[{\"name\":\"head\",\"offset\":0,\"size\":4,\"ty\":\"ptr\"},{\"name\":\"count\",\"offset\":4,\"size\":4,\"ty\":\"u32\"}]}\n",
        stdout_buffer.items,
    );
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const debug_argv = [_][]const u8{ "sa", "layout", "--name", "Entity", "--fields", "id:u64, pos:f64, active:i1", "--format", "debug" };
    const debug_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        debug_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), debug_code);
    try std.testing.expectEqualStrings(
        \\#def Entity_SIZE  = 24
        \\#def Entity_id = +0
        \\#def Entity_pos = +8
        \\#def Entity_active = +16
        \\// 7 bytes tail padding
        \\
        \\[MACRO] DEBUG_PRINT_Entity %ptr
        \\    EXPAND PRINT! "Entity { "
        \\    __dbg_Entity_id = load %ptr+Entity_id as u64
        \\    EXPAND PRINT! "id: {:u}, ", __dbg_Entity_id
        \\    !__dbg_Entity_id
        \\    __dbg_Entity_pos = load %ptr+Entity_pos as f64
        \\    EXPAND PRINT! "pos: {:f}, ", __dbg_Entity_pos
        \\    !__dbg_Entity_pos
        \\    EXPAND PRINT! "active: <unsupported:i1>"
        \\    EXPAND PRINT! " }\n"
        \\[END_MACRO]
        \\
    , stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const dict_argv = [_][]const u8{ "sa", "layout", "--name", "Entity", "--fields", "id:u64, pos:f64", "--format", "dict" };
    const dict_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        dict_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), dict_code);
    try std.testing.expectEqualStrings(
        \\#def LAYOUT_Entity_SIZE = 16
        \\#def LAYOUT_Entity_ALIGN = 8
        \\#def LAYOUT_Entity_id_OFFSET = +0
        \\#def LAYOUT_Entity_id_SIZE = 8
        \\#def LAYOUT_Entity_id_ALIGN = 8
        \\// LAYOUT_Entity_id_TYPE = u64
        \\#def LAYOUT_Entity_pos_OFFSET = +8
        \\#def LAYOUT_Entity_pos_SIZE = 8
        \\#def LAYOUT_Entity_pos_ALIGN = 8
        \\// LAYOUT_Entity_pos_TYPE = f64
        \\
    , stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
