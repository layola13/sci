const std = @import("std");
const saasm = @import("saasm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const suite_path = "tests/unit_framework/feature_suite.sa";
    const source = try std.fs.cwd().readFileAlloc(allocator, suite_path, 10 * 1024 * 1024);
    defer allocator.free(source);

    var resolve_ctx = saasm.pkg.ResolveContext{
        .allocator = allocator,
        .dependencies = &.{},
        .options = .{},
    };
    resolve_ctx.options.std_root = "sa_std";

    var err_ctx = saasm.flattener.ErrorContext{};

    var flat = saasm.flattener.flattenFileWithContextAndPackages(
        allocator,
        suite_path,
        source,
        &err_ctx,
        resolve_ctx,
    ) catch |err| {
        std.debug.print("Flatten failed: {}\n", .{err});
        if (err_ctx.source_line) |line| {
            std.debug.print("Error occurred at source line {?}\n", .{line});
        }
        return err;
    };
    defer flat.deinit(allocator);

    std.debug.print("Flatten succeeded! Total instructions: {}\n", .{flat.instructions.len});
    var it = flat.def_dict.entries.iterator();
    std.debug.print("Dictionary keys:\n", .{});
    while (it.next()) |entry| {
        if (std.mem.containsAtLeast(u8, entry.key_ptr.*, 1, "Result")) {
            std.debug.print("  - '{s}': '{s}'\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
}
