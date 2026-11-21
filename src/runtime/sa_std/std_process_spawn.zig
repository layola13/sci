const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("std_process.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_UNSUPPORTED = @import("std_process.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("std_process.zig").SA_STD_OK;
const SaProcessArgv = @import("std_process.zig").SaProcessArgv;
const argvFromEntries = @import("std_process.zig").argvFromEntries;
const finish = @import("std_process.zig").finish;
const finishErr = @import("std_process.zig").finishErr;
const is_wasm = @import("std_process.zig").is_wasm;
const pathBytes = @import("std_process.zig").pathBytes;
const processCommandExtConfig = @import("std_process.zig").processCommandExtConfig;
const spawnProcess = @import("std_process.zig").spawnProcess;
const spawnProcessConfiguredCwd = @import("std_process.zig").spawnProcessConfiguredCwd;
const spawnProcessCwd = @import("std_process.zig").spawnProcessCwd;

pub export fn sa_std_process_spawn_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    const result = spawnProcessCwd(std.heap.page_allocator, argv, .inherit, cwd) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const result = spawnProcess(std.heap.page_allocator, argv, .stream) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    const result = spawnProcessCwd(std.heap.page_allocator, argv, .stream, cwd) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_bidi(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: ?*u64, out_stdin: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdin_ptr = out_stdin orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdin_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .stream, null, .{ .stdin = true }) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdin_ptr.* = result.stdin orelse 0;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_bidi_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_process: ?*u64, out_stdin: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdin_ptr = out_stdin orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdin_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .stream, cwd, .{ .stdin = true }) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdin_ptr.* = result.stdin orelse 0;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .inherit, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .stream, cwd, config) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, create_pidfd: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, create_pidfd, 0, 0, 0, 0, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .inherit, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, create_pidfd: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, create_pidfd, 0, 0, 0, 0, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .stream, cwd, config) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, uid, has_uid, gid, has_gid, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .inherit, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, uid, has_uid, gid, has_gid, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .stream, cwd, config) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, groups_ptr: ?[*]const u32, groups_len: u64, has_groups: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, groups_ptr, groups_len, has_groups, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .inherit, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, groups_ptr: ?[*]const u32, groups_len: u64, has_groups: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, groups_ptr, groups_len, has_groups, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .stream, cwd, config) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, chroot_ptr: ?[*]const u8, chroot_len: u64, has_chroot: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, null, 0, 0, chroot_ptr, chroot_len, has_chroot) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .inherit, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, chroot_ptr: ?[*]const u8, chroot_len: u64, has_chroot: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, null, 0, 0, chroot_ptr, chroot_len, has_chroot) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .stream, cwd, config) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}
