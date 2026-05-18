const std = @import("std");
const qmod = @import("qmod.zig");
const schema = @import("schema.zig");
const trap = @import("../common/trap.zig");
const dbtrap = @import("trap_db.zig");

pub const ExecError = error{
    OutOfMemory,
    InvalidFormat,
    InvalidPath,
    NotFound,
    DuplicateRegister,
};

pub const ExecResult = struct {
    hash: [32]u8,
    qmod_path: []u8,
    iface_path: []u8,
    registry_path: []u8,
    source_path: []u8,

    pub fn deinit(self: *ExecResult, allocator: std.mem.Allocator) void {
        allocator.free(self.qmod_path);
        allocator.free(self.iface_path);
        allocator.free(self.registry_path);
        allocator.free(self.source_path);
        self.* = undefined;
    }
};

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}

fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn registryRoot(project_root: []const u8) ![]u8 {
    return try qmod.registryDirectory(std.heap.page_allocator, project_root);
}

pub fn compileSchema(
    allocator: std.mem.Allocator,
    source_path: []const u8,
) ![]u8 {
    const source = try readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
    defer allocator.free(source);
    var compiled = try schema.compile(allocator, source, source_path);
    defer compiled.deinit();

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try schema.writeIface(out.writer(), compiled);
    return try out.toOwnedSlice();
}

fn buildQmodArtifact(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source: []const u8,
) !qmod.Qmod {
    return try qmod.compileFromSource(allocator, source, source_path);
}

pub fn registerQuery(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    project_root: []const u8,
) !ExecResult {
    const source = try readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
    defer allocator.free(source);
    var compiled = try buildQmodArtifact(allocator, source_path, source);
    defer compiled.deinit();

    const root = try registryRoot(project_root);
    defer std.heap.page_allocator.free(root);
    try std.fs.cwd().makePath(root);

    const qmod_path = try qmod.qmodFilePath(allocator, source_path, compiled.hash);
    const iface_path = try qmod.ifaceFilePath(allocator, source_path);
    const registry_path = try qmod.registryFilePath(allocator, project_root, compiled.hash);
    const source_copy = try allocator.dupe(u8, source_path);

    var qmod_bytes = std.ArrayList(u8).init(allocator);
    errdefer qmod_bytes.deinit();
    try qmod.writeQmod(qmod_bytes.writer(), compiled);
    try writeFile(qmod_path, qmod_bytes.items);

    var iface = std.ArrayList(u8).init(allocator);
    errdefer iface.deinit();
    try iface.writer().print("source_path={s}\nsha256=", .{source_path});
    try qmod.writeQmod(iface.writer(), compiled) catch {};
    try writeFile(iface_path, iface.items);

    var reg = std.ArrayList(u8).init(allocator);
    errdefer reg.deinit();
    try reg.writer().print("hash=", .{});
    try qmod.writeQmod(reg.writer(), compiled) catch {};
    try writeFile(registry_path, reg.items);

    return .{
        .hash = compiled.hash,
        .qmod_path = qmod_path,
        .iface_path = iface_path,
        .registry_path = registry_path,
        .source_path = source_copy,
    };
}

pub fn inspectRegistry(
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    hash_hex: []const u8,
) ![]u8 {
    const hash = try qmod.parseSha256Hex(hash_hex);
    const registry_path = try qmod.registryFilePath(allocator, root_dir, hash);
    defer allocator.free(registry_path);
    const source = try readFileAlloc(allocator, registry_path, 16 * 1024 * 1024);
    defer allocator.free(source);
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.writer().print("registry: {s}\n", .{registry_path});
    try out.writer().print("bytes: {d}\n", .{source.len});
    return try out.toOwnedSlice();
}

pub fn trapUnknownHash() trap.TrapReport {
    return .{
        .trap = .db_query_hash_unknown,
        .trap_code = trap.trapCode(.db_query_hash_unknown),
        .line = 1,
        .source_line = 1,
        .source_text_buf = [_]u8{0} ** 256,
        .original_text_buf = [_]u8{0} ** 256,
        .source_text = null,
        .original_text = null,
        .register_buf = [_]u8{0} ** 64,
        .register = null,
        .registers = &.{},
        .expected_mask = null,
        .actual_mask = null,
        .expected_mask_name = null,
        .actual_mask_name = null,
        .upstream_loc = null,
        .upstream_file_buf = [_]u8{0} ** 128,
        .upstream_line = 0,
        .upstream_col = 0,
        .function_buf = [_]u8{0} ** 64,
        .function = null,
        .is_ffi_wrapper = null,
        .message = dbtrap.dbTrapInfo(.query_hash_unknown).default_message,
        .hint = null,
    };
}

test "db exec can write schema and qmod artifacts" {
    const tmp_dir = try std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const schema_path = "flash_sale.sadb-schema";
    const qmod_path = "heavy_users.query.saasm";

    const schema_source =
        \\#def MAX_ROWS = 10
        \\#def COL_ID_STRIDE = 8
        \\#def TABLE_ROW_BYTES = 8
    ;
    try writeFile(schema_path, schema_source);
    const iface = try compileSchema(std.testing.allocator, schema_path);
    defer std.testing.allocator.free(iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, iface, 1, "TABLE_ROW_BYTES"));

    const qmod_source =
        \\grants [db_read:flash_sale]
        \\@main() -> i32:
        \\L_ENTRY:
        \\return 0
    ;
    try writeFile(qmod_path, qmod_source);
    var result = try registerQuery(std.testing.allocator, qmod_path, ".");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.hash[0] != 0);
}
