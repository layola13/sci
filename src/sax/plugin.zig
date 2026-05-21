const std = @import("std");
const sax_cli = @import("cli.zig");
const plugin_api = @import("plugin_api.zig");
const plugin_helpers = @import("plugin_helpers.zig");

const sax_skills = [_]plugin_api.SkillSection{
    .{
        .name = "sax",
        .summary = "SAX project commands and lifecycle entry points",
        .items = &.{
            "sax build <file>",
            "sax check <file>",
            "sax dev <file>",
            "sax new <name>",
        },
    },
};

fn runSaxCommandImpl(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "sax")) return null;
    if (argv.len < 3) return error.MissingSourcePath;

    const sub = argv[2];
    if (sax_cli.parseSaxCommand(sub)) |sax_cmd| {
        switch (sax_cmd) {
            .build => {
                const sax_file = if (argv.len >= 4) argv[3] else return error.MissingSourcePath;
                return try sax_cli.executeSaxBuild(ctx.allocator, sax_file, null, stdout, stderr);
            },
            .check => {
                const sax_file = if (argv.len >= 4) argv[3] else return error.MissingSourcePath;
                return try sax_cli.executeSaxCheck(ctx.allocator, sax_file, stdout, stderr);
            },
            .dev => {
                const sax_file = if (argv.len >= 4) argv[3] else return error.MissingSourcePath;
                return try sax_cli.executeSaxDev(ctx.allocator, sax_file, 8080, stdout, stderr);
            },
            .new_project => {
                const project_name = if (argv.len >= 4) argv[3] else return error.MissingSourcePath;
                return try sax_cli.executeSaxNew(ctx.allocator, project_name, stdout, stderr);
            },
        }
    }

    return error.UnknownCommand;
}

fn runSaxCommandAbi(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
    const args = plugin_helpers.cArgvToSlice(argv, argv_len, ctx.allocator) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    defer ctx.allocator.free(args);

    var stdout_storage: plugin_helpers.StreamWriterCtx = undefined;
    var stderr_storage: plugin_helpers.StreamWriterCtx = undefined;
    const stdout_writer = plugin_helpers.makeAnyWriter(stdout, &stdout_storage) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const stderr_writer = plugin_helpers.makeAnyWriter(stderr, &stderr_storage) orelse return @intFromEnum(plugin_api.AbiStatus.failed);

    const result = runSaxCommandImpl(ctx, args, stdout_writer, stderr_writer) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    if (result) |code| {
        out_code.* = code;
        return @intFromEnum(plugin_api.AbiStatus.ok);
    }
    return @intFromEnum(plugin_api.AbiStatus.unknown_command);
}

const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "sax",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = runSaxCommandAbi,
    .skills_ptr = sax_skills[0..].ptr,
    .skills_len = sax_skills.len,
};

pub export const saasm_plugin_descriptor_v1: *const plugin_api.PluginDescriptor = &descriptor;
