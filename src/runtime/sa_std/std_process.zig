const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_ERR_ACCESS = @import("../sa_std.zig").SA_STD_ERR_ACCESS;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
pub const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
pub const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SIGT = @import("../sa_std.zig").SIGT;
pub const SaProcessArgv = @import("../sa_std.zig").SaProcessArgv;
const WT = @import("../sa_std.zig").WT;
const applyProcessCommandExtSetup = @import("../sa_std.zig").applyProcessCommandExtSetup;
pub const argvFromEntries = @import("../sa_std.zig").argvFromEntries;
const envpFromCurrentProcess = @import("../sa_std.zig").envpFromCurrentProcess;
const finalizeProcessExit = @import("../sa_std.zig").finalizeProcessExit;
pub const finish = @import("../sa_std.zig").finish;
pub const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const is_linux = @import("../sa_std.zig").is_linux;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
const lxClose = @import("../sa_std.zig").lxClose;
const lxDup = @import("../sa_std.zig").lxDup;
const lxExecvpeZ = @import("../sa_std.zig").lxExecvpeZ;
const lxKill = @import("../sa_std.zig").lxKill;
const lxWaitpid = @import("../sa_std.zig").lxWaitpid;
const openOwnedByteBuffer = @import("../sa_std.zig").openOwnedByteBuffer;
pub const pathBytes = @import("../sa_std.zig").pathBytes;
pub const processCommandExtConfig = @import("../sa_std.zig").processCommandExtConfig;
const readProcessOutput = @import("../sa_std.zig").readProcessOutput;
const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const sendSignalToPidfd = @import("../sa_std.zig").sendSignalToPidfd;
const sendSignalToProcessGroup = @import("../sa_std.zig").sendSignalToProcessGroup;
pub const spawnProcess = @import("../sa_std.zig").spawnProcess;
pub const spawnProcessConfiguredCwd = @import("../sa_std.zig").spawnProcessConfiguredCwd;
pub const spawnProcessCwd = @import("../sa_std.zig").spawnProcessCwd;
const w_exited = @import("../sa_std.zig").w_exited;
const w_nohang = @import("../sa_std.zig").w_nohang;
const waitPidfdStatus = @import("../sa_std.zig").waitPidfdStatus;
const waitStatusCode = @import("../sa_std.zig").waitStatusCode;
const waitStatusContinued = @import("../sa_std.zig").waitStatusContinued;
const waitStatusCoreDumped = @import("../sa_std.zig").waitStatusCoreDumped;
const waitStatusSignal = @import("../sa_std.zig").waitStatusSignal;
const waitStatusStoppedSignal = @import("../sa_std.zig").waitStatusStoppedSignal;
extern fn getgid() c_uint;
extern fn getpid() c_int;
extern fn getppid() c_int;
extern fn getuid() c_uint;

pub export fn sa_std_process_run(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const result = spawnProcess(std.heap.page_allocator, argv, .capture) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    const result = spawnProcessCwd(std.heap.page_allocator, argv, .capture, cwd) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const result = spawnProcess(std.heap.page_allocator, argv, .inherit) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub const sa_std_process_spawn_cwd = @import("std_process_spawn.zig").sa_std_process_spawn_cwd;

pub const sa_std_process_spawn_stream = @import("std_process_spawn.zig").sa_std_process_spawn_stream;

pub const sa_std_process_spawn_stream_cwd = @import("std_process_spawn.zig").sa_std_process_spawn_stream_cwd;

pub const sa_std_process_spawn_bidi = @import("std_process_spawn.zig").sa_std_process_spawn_bidi;

pub const sa_std_process_spawn_bidi_cwd = @import("std_process_spawn.zig").sa_std_process_spawn_bidi_cwd;

pub export fn sa_std_process_run_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .capture, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub const sa_std_process_spawn_command_ext = @import("std_process_spawn.zig").sa_std_process_spawn_command_ext;

pub const sa_std_process_spawn_stream_command_ext = @import("std_process_spawn.zig").sa_std_process_spawn_stream_command_ext;

pub export fn sa_std_process_run_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, create_pidfd: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, create_pidfd, 0, 0, 0, 0, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .capture, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub const sa_std_process_spawn_command_ext_pidfd = @import("std_process_spawn.zig").sa_std_process_spawn_command_ext_pidfd;

pub const sa_std_process_spawn_stream_command_ext_pidfd = @import("std_process_spawn.zig").sa_std_process_spawn_stream_command_ext_pidfd;

pub export fn sa_std_process_run_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, uid, has_uid, gid, has_gid, null, 0, 0, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .capture, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub const sa_std_process_spawn_command_ext_uid_gid = @import("std_process_spawn.zig").sa_std_process_spawn_command_ext_uid_gid;

pub const sa_std_process_spawn_stream_command_ext_uid_gid = @import("std_process_spawn.zig").sa_std_process_spawn_stream_command_ext_uid_gid;

pub export fn sa_std_process_run_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, groups_ptr: ?[*]const u32, groups_len: u64, has_groups: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, groups_ptr, groups_len, has_groups, null, 0, 0) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .capture, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub const sa_std_process_spawn_command_ext_groups = @import("std_process_spawn.zig").sa_std_process_spawn_command_ext_groups;

pub const sa_std_process_spawn_stream_command_ext_groups = @import("std_process_spawn.zig").sa_std_process_spawn_stream_command_ext_groups;

pub export fn sa_std_process_run_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, chroot_ptr: ?[*]const u8, chroot_len: u64, has_chroot: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, 0, 0, 0, 0, null, 0, 0, chroot_ptr, chroot_len, has_chroot) catch |err| return finishErr(err);
    const result = spawnProcessConfiguredCwd(std.heap.page_allocator, argv, .capture, cwd, config) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub const sa_std_process_spawn_command_ext_chroot = @import("std_process_spawn.zig").sa_std_process_spawn_command_ext_chroot;

pub const sa_std_process_spawn_stream_command_ext_chroot = @import("std_process_spawn.zig").sa_std_process_spawn_stream_command_ext_chroot;

pub export fn sa_std_process_exec_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, groups_ptr: ?[*]const u32, groups_len: u64, has_groups: u32, chroot_ptr: ?[*]const u8, chroot_len: u64, has_chroot: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    if (argv.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const config = processCommandExtConfig(arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, 0, uid, has_uid, gid, has_gid, groups_ptr, groups_len, has_groups, chroot_ptr, chroot_len, has_chroot) catch |err| return finishErr(err);
    if (config.arg0) |arg0| {
        if (std.mem.indexOfScalar(u8, arg0, 0) != null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const exec_path = (arena.allocator().dupeSentinel(u8, argv[0], 0) catch |err| return finishErr(err)).ptr;
    const child_argv = arena.allocator().alloc(?[*:0]const u8, argv.len + 1) catch |err| return finishErr(err);
    for (argv, 0..) |arg, i| {
        const child_arg = if (i == 0 and config.arg0 != null) config.arg0.? else arg;
        child_argv[i] = (arena.allocator().dupeSentinel(u8, child_arg, 0) catch |err| return finishErr(err)).ptr;
    }
    child_argv[argv.len] = null;
    const envp = envpFromCurrentProcess(arena.allocator()) catch |err| return finishErr(err);
    const chroot_path_z: ?[*:0]const u8 = if (config.chroot_path) |path| (arena.allocator().dupeSentinel(u8, path, 0) catch |err| return finishErr(err)).ptr else null;

    applyProcessCommandExtSetup(cwd, config, chroot_path_z) catch |err| return finishErr(err);
    const argv_z: [*:null]const ?[*:0]const u8 = @ptrCast(child_argv.ptr);
    const envp_z: [*:null]const ?[*:0]const u8 = @ptrCast(envp.ptr);
    const exec_err = lxExecvpeZ(exec_path, argv_z, envp_z);
    return finishErr(exec_err);
}

pub export fn sa_std_process_id() u32 {
    if (comptime is_wasm) return 0;
    return @intCast(getpid());
}

pub export fn sa_std_process_parent_id() u32 {
    if (comptime is_wasm) return 0;
    return @intCast(getppid());
}

pub export fn sa_std_process_user_id() u32 {
    if (comptime is_wasm) return 0;
    if (comptime is_linux) return @intCast(std.os.linux.getuid());
    return @intCast(getuid());
}

pub export fn sa_std_process_group_id() u32 {
    if (comptime is_wasm) return 0;
    if (comptime is_linux) return @intCast(std.os.linux.getgid());
    return @intCast(getgid());
}

pub export fn sa_std_process_abort() noreturn {
    if (comptime is_wasm) std.process.abort();
    std.process.abort();
}

pub export fn sa_std_process_child_id(handle: u64, out_pid: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const pid_ptr = out_pid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pid_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            pid_ptr.* = @intCast(proc.pid);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_wait(handle: u64, out_code: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.exited) {
                if (proc.pidfd) |fd| {
                    const raw_status = waitPidfdStatus(fd, w_exited) catch |err| return finishErr(err);
                    finalizeProcessExit(proc, raw_status orelse return finish(SA_STD_OK)) catch |err| return finishErr(err);
                } else {
                    const waited = lxWaitpid(proc.pid, 0);
                    finalizeProcessExit(proc, waited.status) catch |err| return finishErr(err);
                }
            }
            code_ptr.* = proc.code;
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_wait_raw(handle: u64, out_raw: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    raw_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.exited) {
                if (proc.pidfd) |fd| {
                    const raw_status = waitPidfdStatus(fd, w_exited) catch |err| return finishErr(err);
                    finalizeProcessExit(proc, raw_status orelse return finish(SA_STD_OK)) catch |err| return finishErr(err);
                } else {
                    const waited = lxWaitpid(proc.pid, 0);
                    finalizeProcessExit(proc, waited.status) catch |err| return finishErr(err);
                }
            }
            raw_ptr.* = @bitCast(proc.raw_status);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_try_wait(handle: u64, out_ready: ?*i32, out_code: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ready_ptr.* = 0;
    code_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.exited) {
                if (proc.pidfd) |fd| {
                    const raw_status = waitPidfdStatus(fd, w_exited | w_nohang) catch |err| return finishErr(err);
                    if (raw_status == null) return finish(SA_STD_OK);
                    finalizeProcessExit(proc, raw_status.?) catch |err| return finishErr(err);
                } else {
                    const waited = lxWaitpid(proc.pid, WT.NOHANG);
                    if (waited.pid == 0) return finish(SA_STD_OK);
                    finalizeProcessExit(proc, waited.status) catch |err| return finishErr(err);
                }
            }
            ready_ptr.* = 1;
            code_ptr.* = proc.code;
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_try_wait_raw(handle: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ready_ptr.* = 0;
    raw_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.exited) {
                if (proc.pidfd) |fd| {
                    const raw_status = waitPidfdStatus(fd, w_exited | w_nohang) catch |err| return finishErr(err);
                    if (raw_status == null) return finish(SA_STD_OK);
                    finalizeProcessExit(proc, raw_status.?) catch |err| return finishErr(err);
                } else {
                    const waited = lxWaitpid(proc.pid, WT.NOHANG);
                    if (waited.pid == 0) return finish(SA_STD_OK);
                    finalizeProcessExit(proc, waited.status) catch |err| return finishErr(err);
                }
            }
            ready_ptr.* = 1;
            raw_ptr.* = @bitCast(proc.raw_status);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_kill(handle: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.exited) {
                if (proc.pidfd) |fd| {
                    sendSignalToPidfd(fd, @backingInt(SIGT.KILL), 0) catch |err| switch (err) {
                        error.ProcessNotFound => {},
                        else => return finishErr(err),
                    };
                    const raw_status = waitPidfdStatus(fd, w_exited) catch |err| return finishErr(err);
                    finalizeProcessExit(proc, raw_status orelse return finish(SA_STD_OK)) catch |err| return finishErr(err);
                } else {
                    std.posix.kill(proc.pid, SIGT.KILL) catch |err| switch (err) {
                        error.ProcessNotFound => {},
                        else => return finishErr(err),
                    };
                    const waited = lxWaitpid(proc.pid, 0);
                    finalizeProcessExit(proc, waited.status) catch |err| return finishErr(err);
                }
            }
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_send_signal(handle: u64, signum: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (signum < 0 or signum > std.math.maxInt(u8)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (proc.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
            if (proc.pidfd) |fd| {
                sendSignalToPidfd(fd, @as(u8, @intCast(signum)), 0) catch |err| switch (err) {
                    error.InvalidArgument => return finish(SA_STD_ERR_INVALID_ARGUMENT),
                    error.PermissionDenied => return finish(SA_STD_ERR_ACCESS),
                    error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                    else => return finishErr(err),
                };
                return finish(SA_STD_OK);
            }
            lxKill(proc.pid, @as(u8, @intCast(signum))) catch |err| switch (err) {
                error.InvalidArgument => return finish(SA_STD_ERR_INVALID_ARGUMENT),
                error.PermissionDenied => return finish(SA_STD_ERR_ACCESS),
                error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                else => return finishErr(err),
            };
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_send_process_group_signal(handle: u64, signum: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (signum < 0 or signum > 64) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (proc.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
            const pgid = proc.process_group orelse proc.pid;
            if (pgid <= 0) return finish(SA_STD_ERR_INVALID_HANDLE);
            sendSignalToProcessGroup(pgid, @as(u8, @intCast(signum))) catch |err| switch (err) {
                error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                error.PermissionDenied => return finish(SA_STD_ERR_ACCESS),
                else => return finishErr(err),
            };
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_kill_process_group(handle: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_process_send_process_group_signal(handle, @backingInt(SIGT.KILL));
}

pub export fn sa_std_process_pidfd(handle: u64, out_pidfd: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const pidfd_ptr = out_pidfd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pidfd_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            const pidfd = proc.pidfd orelse return finish(SA_STD_ERR_INVALID_HANDLE);
            const dup_fd = lxDup(pidfd) catch |err| return finishErr(err);
            const dup_handle = registerResourceLocked(.{ .owned_fd = .{ .fd = dup_fd } }) catch |err| {
                lxClose(dup_fd);
                return finishErr(err);
            };
            pidfd_ptr.* = dup_handle;
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_into_pidfd(handle: u64, out_pidfd: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const pidfd_ptr = out_pidfd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pidfd_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            const pidfd = proc.pidfd orelse return finish(SA_STD_ERR_INVALID_HANDLE);
            proc.pidfd = null;
            const pidfd_handle = registerResourceLocked(.{ .owned_fd = .{ .fd = pidfd } }) catch |err| {
                proc.pidfd = pidfd;
                return finishErr(err);
            };
            pidfd_ptr.* = pidfd_handle;
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_exit_status_code(raw: i32) u32 {
    if (comptime is_wasm) {
        return 127;
    }
    return waitStatusCode(raw);
}

pub export fn sa_std_process_exit_status_signal(raw: i32) i32 {
    if (comptime is_wasm) {
        return -1;
    }
    return waitStatusSignal(raw);
}

pub export fn sa_std_process_exit_status_core_dumped(raw: i32) u8 {
    if (comptime is_wasm) {
        return 0;
    }
    return waitStatusCoreDumped(raw);
}

pub export fn sa_std_process_exit_status_stopped_signal(raw: i32) i32 {
    if (comptime is_wasm) {
        return -1;
    }
    return waitStatusStoppedSignal(raw);
}

pub export fn sa_std_process_exit_status_continued(raw: i32) u8 {
    if (comptime is_wasm) {
        return 0;
    }
    return waitStatusContinued(raw);
}

pub export fn sa_std_process_read_stdout(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return readProcessOutput(handle, .stdout, out, out_cap, out_read);
}

pub export fn sa_std_process_read_stderr(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return readProcessOutput(handle, .stderr, out, out_cap, out_read);
}

pub export fn sa_std_process_exec_capture(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;

    var process: u64 = 0;
    var run_status = sa_std_process_run(argv_ptr, argv_len, &process);
    if (run_status != SA_STD_OK) return run_status;
    errdefer _ = sa_std_process_close(process);

    run_status = sa_std_process_wait(process, code_ptr);
    if (run_status != SA_STD_OK) return run_status;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_len: u64 = 0;
    run_status = sa_std_process_read_stdout(process, &stdout_buf, stdout_buf.len, &stdout_len);
    if (run_status != SA_STD_OK) return run_status;

    var stderr_buf: [8192]u8 = undefined;
    var stderr_len: u64 = 0;
    run_status = sa_std_process_read_stderr(process, &stderr_buf, stderr_buf.len, &stderr_len);
    if (run_status != SA_STD_OK) return run_status;

    const stdout_owned = std.heap.page_allocator.dupe(u8, stdout_buf[0..@as(usize, @intCast(stdout_len))]) catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(stdout_owned);
    const stderr_owned = std.heap.page_allocator.dupe(u8, stderr_buf[0..@as(usize, @intCast(stderr_len))]) catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(stderr_owned);

    stdout_ptr.* = openOwnedByteBuffer(stdout_owned) catch |err| return finishErr(err);
    errdefer _ = sa_std_close(stdout_ptr.*);
    stderr_ptr.* = openOwnedByteBuffer(stderr_owned) catch |err| return finishErr(err);
    _ = sa_std_process_close(process);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_exec_capture_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;

    var process: u64 = 0;
    var run_status = sa_std_process_run_cwd(argv_ptr, argv_len, cwd_ptr, cwd_len, &process);
    if (run_status != SA_STD_OK) return run_status;
    errdefer _ = sa_std_process_close(process);

    run_status = sa_std_process_wait(process, code_ptr);
    if (run_status != SA_STD_OK) return run_status;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_len: u64 = 0;
    run_status = sa_std_process_read_stdout(process, &stdout_buf, stdout_buf.len, &stdout_len);
    if (run_status != SA_STD_OK) return run_status;

    var stderr_buf: [8192]u8 = undefined;
    var stderr_len: u64 = 0;
    run_status = sa_std_process_read_stderr(process, &stderr_buf, stderr_buf.len, &stderr_len);
    if (run_status != SA_STD_OK) return run_status;

    const stdout_owned = std.heap.page_allocator.dupe(u8, stdout_buf[0..@as(usize, @intCast(stdout_len))]) catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(stdout_owned);
    const stderr_owned = std.heap.page_allocator.dupe(u8, stderr_buf[0..@as(usize, @intCast(stderr_len))]) catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(stderr_owned);

    stdout_ptr.* = openOwnedByteBuffer(stdout_owned) catch |err| return finishErr(err);
    errdefer _ = sa_std_close(stdout_ptr.*);
    stderr_ptr.* = openOwnedByteBuffer(stderr_owned) catch |err| return finishErr(err);
    _ = sa_std_process_close(process);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_close(handle: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_close(handle);
}
