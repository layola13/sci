const std = @import("std");
pub const api = @import("plugin_api.zig");
pub const SkillSection = api.SkillSection;
pub const Context = api.Context;
pub const abi_version = api.abi_version;
pub const descriptor_symbol_name = api.descriptor_symbol_name;
pub const AbiStatus = api.AbiStatus;
pub const PluginDescriptor = api.PluginDescriptor;
pub const DescriptorFn = api.DescriptorFn;
pub const StreamWriteAllFn = api.StreamWriteAllFn;
pub const HostStream = api.HostStream;

pub const Plugin = struct {
    name: []const u8,
    init: ?*const fn (ctx: *const Context) anyerror!void = null,
    prebuild: ?*const fn (ctx: *const Context, compile_options: *anyopaque) anyerror!void = null,
    postbuild: ?*const fn (ctx: *const Context) anyerror!void = null,
    handleCommand: ?*const fn (ctx: *const Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 = null,
    skills: ?[]const SkillSection = null,
};

pub const LoadedPlugin = struct {
    lib: std.DynLib,
    descriptor: *const PluginDescriptor,

    pub fn deinit(self: *LoadedPlugin) void {
        self.lib.close();
        self.* = undefined;
    }
};
