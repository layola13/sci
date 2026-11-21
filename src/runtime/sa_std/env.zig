const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NOT_FOUND = @import("../sa_std.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const constBytes = @import("../sa_std.zig").constBytes;
const envGetOwned = @import("../sa_std.zig").envGetOwned;
const envJoinPathsJsonAlloc = @import("../sa_std.zig").envJoinPathsJsonAlloc;
const envKeyBytes = @import("../sa_std.zig").envKeyBytes;
const envSplitPathsJsonAlloc = @import("../sa_std.zig").envSplitPathsJsonAlloc;
const envValueFromCurrentProcess = @import("../sa_std.zig").envValueFromCurrentProcess;
const envVarsJsonAlloc = @import("../sa_std.zig").envVarsJsonAlloc;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const openOwnedEnvBuffer = @import("../sa_std.zig").openOwnedEnvBuffer;
const pathBytes = @import("../sa_std.zig").pathBytes;
const policyAllows = @import("../sa_std.zig").policyAllows;
const processArgsJsonAlloc = @import("../sa_std.zig").processArgsJsonAlloc;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const sio = @import("../sa_std.zig").sio;
const tempRootAlloc = @import("../sa_std.zig").tempRootAlloc;
const xdgDirsAlloc = @import("../sa_std.zig").xdgDirsAlloc;
const xdgHomeSubdirAlloc = @import("../sa_std.zig").xdgHomeSubdirAlloc;
extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn unsetenv(name: [*:0]const u8) c_int;

pub export fn sa_env_get(key_ptr: ?[*]const u8, key_len: u64) u64 {
    const key = envKeyBytes(key_ptr, key_len) catch return 0;
    if (!policyAllows(.{ .env = key })) return 0;
    const owned = envGetOwned(key) catch return 0;
    return openOwnedEnvBuffer(owned) catch return 0;
}

pub export fn sa_env_current_dir() u64 {
    const cwd = sio.getCwdAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedEnvBuffer(cwd) catch return 0;
}

pub export fn sa_env_set_current_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.changeCurDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_env_temp_dir() u64 {
    const path = tempRootAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedEnvBuffer(path) catch return 0;
}

pub export fn sa_env_current_exe() u64 {
    const path = sio.selfExePathAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedEnvBuffer(path) catch return 0;
}

pub export fn sa_env_home_dir() u64 {
    const owned = envGetOwned("HOME") catch return 0;
    return openOwnedEnvBuffer(owned) catch return 0;
}

pub export fn sa_env_args_json() u64 {
    const json = processArgsJsonAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedEnvBuffer(json) catch return 0;
}

pub export fn sa_env_vars_json() u64 {
    const json = envVarsJsonAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedEnvBuffer(json) catch return 0;
}

pub export fn sa_env_split_paths_json(path_list_ptr: ?[*]const u8, path_list_len: u64) u64 {
    const path_list = constBytes(path_list_ptr, path_list_len) catch return 0;
    const json = envSplitPathsJsonAlloc(std.heap.page_allocator, path_list) catch return 0;
    return openOwnedEnvBuffer(json) catch return 0;
}

pub export fn sa_env_join_paths_json(paths_json_ptr: ?[*]const u8, paths_json_len: u64) u64 {
    const paths_json = constBytes(paths_json_ptr, paths_json_len) catch return 0;
    const joined = envJoinPathsJsonAlloc(std.heap.page_allocator, paths_json) catch return 0;
    return openOwnedEnvBuffer(joined) catch return 0;
}

pub export fn sa_env_xdg_data_home_dir() u64 {
    const path = xdgHomeSubdirAlloc(std.heap.page_allocator, "XDG_DATA_HOME", ".local/share") catch return 0;
    return openOwnedEnvBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_config_home_dir() u64 {
    const path = xdgHomeSubdirAlloc(std.heap.page_allocator, "XDG_CONFIG_HOME", ".config") catch return 0;
    return openOwnedEnvBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_state_home_dir() u64 {
    const path = xdgHomeSubdirAlloc(std.heap.page_allocator, "XDG_STATE_HOME", ".local/state") catch return 0;
    return openOwnedEnvBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_cache_home_dir() u64 {
    const path = xdgHomeSubdirAlloc(std.heap.page_allocator, "XDG_CACHE_HOME", ".cache") catch return 0;
    return openOwnedEnvBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_data_dirs() u64 {
    const dirs = xdgDirsAlloc(std.heap.page_allocator, "XDG_DATA_DIRS", "/usr/local/share/:/usr/share/") catch return 0;
    return openOwnedEnvBuffer(dirs) catch return 0;
}

pub export fn sa_env_xdg_config_dirs() u64 {
    const dirs = xdgDirsAlloc(std.heap.page_allocator, "XDG_CONFIG_DIRS", "/etc/xdg") catch return 0;
    return openOwnedEnvBuffer(dirs) catch return 0;
}

pub export fn sa_env_has(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const present = envValueFromCurrentProcess(key) != null;
    return finish(if (present) SA_STD_OK else SA_STD_ERR_NOT_FOUND);
}

pub export fn sa_env_set_var(key_ptr: ?[*]const u8, key_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const value = constBytes(value_ptr, value_len) catch |err| return finishErr(err);
    if (std.mem.indexOfScalar(u8, value, 0) != null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const key_z = std.heap.page_allocator.dupeSentinel(u8, key, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(key_z);
    const value_z = std.heap.page_allocator.dupeSentinel(u8, value, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(value_z);
    if (setenv(key_z.ptr, value_z.ptr, 1) != 0) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_env_remove_var(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const key_z = std.heap.page_allocator.dupeSentinel(u8, key, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(key_z);
    if (unsetenv(key_z.ptr) != 0) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_env_buffer_data(buffer: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return null;
    return switch (resource.*) {
        .env => |*env| env.bytes.ptr,
        else => null,
    };
}

pub export fn sa_env_buffer_len(buffer: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return 0;
    return switch (resource.*) {
        .env => |env| @as(u64, @intCast(env.bytes.len)),
        else => 0,
    };
}

pub export fn sa_env_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}
