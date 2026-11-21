const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_NOT_FOUND = @import("../sa_std.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("../sa_std.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNKNOWN = @import("../sa_std.zig").SA_STD_ERR_UNKNOWN;
const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const builtin = @import("../sa_std.zig").builtin;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const pathBytes = @import("../sa_std.zig").pathBytes;
const registerResource = @import("../sa_std.zig").registerResource;

var compatibility_dlopen_cookie: [1]u8 = .{0};

var compatibility_dl_error: [:0]const u8 = "unsupported";

pub const DynamicLibHandle = struct {
    // wasm32-wasi has no dlopen; std.DynLib itself is @compileError on wasm,
    // so the field must be conditional to keep the type compilable.
    lib: if (builtin.cpu.arch.isWasm()) void else std.DynLib,

    pub fn deinit(self: *DynamicLibHandle) void {
        if (!builtin.cpu.arch.isWasm()) {
            self.lib.close();
        }
    }
};

pub fn dlopen(path_ptr: ?[*]const u8, flags: i32) callconv(.c) ?[*]u8 {
    _ = path_ptr;
    _ = flags;
    sa_std.last_error = SA_STD_ERR_UNSUPPORTED;
    return compatibility_dlopen_cookie[0..].ptr;
}

pub export fn sa_dl_open(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    // wasm32-wasi has no dlopen; comptime guard keeps std.DynLib refs out of wasm build.
    if (comptime builtin.cpu.arch.isWasm()) return finish(SA_STD_ERR_UNSUPPORTED);
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);

    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const path_z = std.heap.page_allocator.dupeSentinel(u8, path, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(path_z);

    const lib = std.DynLib.openZ(path_z) catch |err| switch (err) {
        error.FileNotFound, error.NotElfFile, error.NotDynamicLibrary => {
            compatibility_dl_error = "not_found";
            return finish(SA_STD_ERR_NOT_FOUND);
        },
        error.OutOfMemory => return finish(SA_STD_ERR_NO_MEMORY),
        else => return finish(SA_STD_ERR_UNKNOWN),
    };

    const handle = std.heap.page_allocator.create(DynamicLibHandle) catch |err| {
        var lib_copy = lib;
        lib_copy.close();
        return finishErr(err);
    };
    handle.* = .{ .lib = lib };

    const resource_handle = registerResource(.{ .dynamic_lib = handle }) catch |err| {
        handle.deinit();
        std.heap.page_allocator.destroy(handle);
        return finishErr(err);
    };

    handle_ptr.* = resource_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_dl_sym(handle: u64, symbol_ptr: ?[*]const u8, symbol_len: u64, out_ptr: ?*?*anyopaque) i32 {
    const result_ptr = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result_ptr.* = null;
    if (comptime builtin.cpu.arch.isWasm()) return finish(SA_STD_ERR_UNSUPPORTED);
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);

    const symbol = pathBytes(symbol_ptr, symbol_len) catch |err| return finishErr(err);
    const symbol_z = std.heap.page_allocator.dupeSentinel(u8, symbol, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(symbol_z);

    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const lib_handle = switch (resource.*) {
        .dynamic_lib => |lib| lib,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    result_ptr.* = lib_handle.lib.lookup(*anyopaque, symbol_z) orelse {
        compatibility_dl_error = "not_found";
        return finish(SA_STD_ERR_NOT_FOUND);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_dl_error() ?[*:0]const u8 {
    return compatibility_dl_error.ptr;
}
