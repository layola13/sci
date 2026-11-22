const std = @import("std");
const sa_std = @import("../sa_std.zig");
const Resource = @import("../sa_std.zig").Resource;
const SA_STD_ERR_ACCESS = @import("../sa_std.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SA_STD_STDERR = @import("../sa_std.zig").SA_STD_STDERR;
const SA_STD_STDIN = @import("../sa_std.zig").SA_STD_STDIN;
const SA_STD_STDOUT = @import("../sa_std.zig").SA_STD_STDOUT;
const builtin = @import("../sa_std.zig").builtin;
const constBytes = @import("../sa_std.zig").constBytes;
const errnoToAny = @import("../sa_std.zig").errnoToAny;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
const libc = @import("../sa_std.zig").libc;
const libcErrRc = @import("../sa_std.zig").libcErrRc;
const lxCheck = @import("../sa_std.zig").lxCheck;
const lxClose = @import("../sa_std.zig").lxClose;
const pathBytes = @import("../sa_std.zig").pathBytes;
const policyAllows = @import("../sa_std.zig").policyAllows;
const registerResource = @import("../sa_std.zig").registerResource;
extern "c" var environ: [*:null]?[*:0]u8;

pub const WasiSIG = struct {
    pub const KILL: u8 = 9;
};

pub const SIGT = if (is_wasm) WasiSIG else std.posix.SIG;

pub const FIRST_DYNAMIC_HANDLE: u64 = 4;

pub var registry_slots = std.array_list.Managed(?Resource).init(std.heap.page_allocator);

fn constU32s(ptr: ?[*]const u32, len: u64) ![]const u32 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

pub fn dynamicIndex(handle: u64) ?usize {
    if (handle < FIRST_DYNAMIC_HANDLE) return null;
    const raw = handle - FIRST_DYNAMIC_HANDLE;
    if (raw > @as(u64, @intCast(std.math.maxInt(usize)))) return null;
    return @as(usize, @intCast(raw));
}

pub fn takeResourceLocked(handle: u64) ?Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= registry_slots.items.len) return null;
    const resource = registry_slots.items[idx] orelse return null;
    registry_slots.items[idx] = null;
    return resource;
}

fn killAndWaitChild(pid: std.posix.pid_t) void {
    if (comptime is_wasm) return;
    std.posix.kill(pid, SIGT.KILL) catch |err| {
        // Child teardown is best-effort; waitpid below still reaps if the child already exited.
        _ = @errorName(err);
    };
    _ = lxWaitpid(pid, 0);
}

pub fn envpFromCurrentProcess(arena: std.mem.Allocator) ![:null]const ?[*:0]const u8 {
    var count: usize = 0;
    while (environ[count] != null) : (count += 1) {}

    const env_block = try arena.alloc(?[*:0]const u8, count + 1);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        env_block[i] = environ[i].?;
    }
    env_block[count] = null;
    return env_block[0..count :null];
}

pub const ProcessSpawnMode = enum {
    inherit,
    capture,
    stream,
};

pub const ProcessSpawnConfig = struct {
    arg0: ?[]const u8 = null,
    process_group: ?i32 = null,
    setsid: bool = false,
    create_pidfd: bool = false,
    uid: ?u32 = null,
    gid: ?u32 = null,
    groups: ?[]const u32 = null,
    chroot_path: ?[]const u8 = null,
    stdin: bool = false,
};

pub const SpawnResult = struct {
    process: u64 = 0,
    stdout: ?u64 = null,
    stderr: ?u64 = null,
    stdin: ?u64 = null,
};

fn openPidfd(pid: std.posix.pid_t) ?std.posix.fd_t {
    if (comptime builtin.os.tag != .linux) return null;
    const fd = std.os.linux.pidfd_open(pid, 0);
    return switch (std.os.linux.errno(fd)) {
        .SUCCESS => @as(std.posix.fd_t, @intCast(fd)),
        else => null,
    };
}

pub fn sendSignalToPidfd(fd: std.posix.fd_t, signum: u8, flags: u32) !void {
    if (comptime is_wasm) return error.Unsupported;
    const result = std.os.linux.pidfd_send_signal(fd, @fromBackingInt(@intCast(signum)), null, flags);
    switch (std.os.linux.errno(result)) {
        .SUCCESS => return,
        .INVAL => return error.InvalidArgument,
        .PERM => return error.PermissionDenied,
        .SRCH => return error.ProcessNotFound,
        else => return error.Unexpected,
    }
}

pub fn applyProcessCommandExtSetup(cwd: ?[]const u8, config: ProcessSpawnConfig, chroot_path_z: ?[*:0]const u8) !void {
    // wasm32-wasi has no process spawn; stub (linux errno types mismatch wasi).
    if (comptime is_wasm) return error.Unsupported;
    if (config.groups) |groups| try lxSetgroups(groups);
    if (config.gid) |gid| try lxSetgid(@as(std.posix.gid_t, @intCast(gid)));
    if (config.uid) |uid| try lxSetuid(@as(std.posix.uid_t, @intCast(uid)));
    if (chroot_path_z) |path| try lxChroot(path);
    if (cwd) |dir| try lxChdir(dir);
    if (config.process_group) |pgroup| try lxSetpgid(0, @as(std.posix.pid_t, @intCast(pgroup)));
    if (config.setsid) try lxSetsid();
}

pub fn spawnProcessConfiguredCwd(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode, cwd: ?[]const u8, config: ProcessSpawnConfig) !SpawnResult {
    // wasm32-wasi has no fork/exec/pipe2-CLOEXEC; stub.
    if (comptime is_wasm) return error.Unsupported;
    if (argv.len == 0) return error.InvalidArgument;
    if (config.stdin and mode != .stream) return error.InvalidArgument;
    if (!policyAllows(.{ .run = argv[0] })) return error.PolicyDenied;
    if (config.arg0) |arg0| {
        if (std.mem.indexOfScalar(u8, arg0, 0) != null) return error.InvalidArgument;
    }

    const use_pipes = mode != .inherit;
    var stdout_pipe: [2]std.posix.fd_t = .{ -1, -1 };
    var stderr_pipe: [2]std.posix.fd_t = .{ -1, -1 };
    var stdin_pipe: [2]std.posix.fd_t = .{ -1, -1 };
    defer {
        if (stdout_pipe[0] != -1) lxClose(stdout_pipe[0]);
        if (stdout_pipe[1] != -1) lxClose(stdout_pipe[1]);
        if (stderr_pipe[0] != -1) lxClose(stderr_pipe[0]);
        if (stderr_pipe[1] != -1) lxClose(stderr_pipe[1]);
        if (stdin_pipe[0] != -1) lxClose(stdin_pipe[0]);
        if (stdin_pipe[1] != -1) lxClose(stdin_pipe[1]);
    }
    if (use_pipes) {
        stdout_pipe = try lxPipe2(.{ .CLOEXEC = true });
        stderr_pipe = try lxPipe2(.{ .CLOEXEC = true });
    }
    if (config.stdin) {
        stdin_pipe = try lxPipe2(.{ .CLOEXEC = true });
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const exec_path = (try arena.allocator().dupeSentinel(u8, argv[0], 0)).ptr;
    const child_argv = try arena.allocator().alloc(?[*:0]const u8, argv.len + 1);
    for (argv, 0..) |arg, i| {
        const child_arg = if (i == 0 and config.arg0 != null) config.arg0.? else arg;
        child_argv[i] = (try arena.allocator().dupeSentinel(u8, child_arg, 0)).ptr;
    }
    child_argv[argv.len] = null;
    const envp = try envpFromCurrentProcess(arena.allocator());
    const chroot_path_z: ?[*:0]const u8 = if (config.chroot_path) |path| (try arena.allocator().dupeSentinel(u8, path, 0)).ptr else null;

    const pid = try lxFork();
    if (pid == 0) {
        if (cwd != null and chroot_path_z == null) {
            const dir = cwd.?;
            lxChdir(dir) catch lxExit(127);
        }
        if (config.process_group) |pgroup| {
            lxSetpgid(0, @as(std.posix.pid_t, @intCast(pgroup))) catch lxExit(127);
        }
        if (config.setsid) {
            lxSetsid() catch lxExit(127);
        }
        if (config.groups) |groups| {
            lxSetgroups(groups) catch lxExit(127);
        }
        if (config.gid) |gid| {
            lxSetgid(@as(std.posix.gid_t, @intCast(gid))) catch lxExit(127);
        }
        if (config.uid) |uid| {
            lxSetuid(@as(std.posix.uid_t, @intCast(uid))) catch lxExit(127);
        }
        if (chroot_path_z) |path| {
            lxChroot(path) catch lxExit(127);
            if (cwd) |dir| lxChdir(dir) catch lxExit(127);
        }
        if (use_pipes) {
            lxClose(stdout_pipe[0]);
            lxClose(stderr_pipe[0]);
            try lxDup2(stdout_pipe[1], std.posix.STDOUT_FILENO);
            try lxDup2(stderr_pipe[1], std.posix.STDERR_FILENO);
        }
        if (stdin_pipe[0] != -1) {
            lxClose(stdin_pipe[1]);
            try lxDup2(stdin_pipe[0], std.posix.STDIN_FILENO);
            lxClose(stdin_pipe[0]);
        }
        if (use_pipes) {
            lxClose(stdout_pipe[1]);
            lxClose(stderr_pipe[1]);
        }
        const argv_z: [*:null]const ?[*:0]const u8 = @ptrCast(child_argv.ptr);
        const envp_z: [*:null]const ?[*:0]const u8 = @ptrCast(envp.ptr);
        const exec_err = lxExecvpeZ(exec_path, argv_z, envp_z);
        switch (exec_err) {
            error.AccessDenied,
            error.SystemResources,
            error.Unexpected,
            error.FileNotFound,
            error.NameTooLong,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            error.IsDir,
            error.NotDir,
            error.FileBusy,
            error.FileSystem,
            error.InvalidExe,
            => lxExit(127),
            else => lxExit(127),
        }
        unreachable;
    }

    const effective_process_group: ?std.posix.pid_t = if (config.process_group) |pgroup|
        (if (pgroup == 0) pid else @as(std.posix.pid_t, @intCast(pgroup)))
    else
        null;
    if (effective_process_group) |pgid| {
        lxSetpgid(pid, pgid) catch |err| switch (err) {
            error.ProcessAlreadyExec => {},
            else => {
                killAndWaitChild(pid);
                return err;
            },
        };
    }

    var pidfd_fd: ?std.posix.fd_t = if (config.create_pidfd) openPidfd(pid) else null;
    defer if (pidfd_fd) |fd| lxClose(fd);

    if (use_pipes) {
        lxClose(stdout_pipe[1]);
        lxClose(stderr_pipe[1]);
        stdout_pipe[1] = -1;
        stderr_pipe[1] = -1;
    }
    if (stdin_pipe[0] != -1) {
        lxClose(stdin_pipe[0]);
        stdin_pipe[0] = -1;
    }

    var result: SpawnResult = .{};
    switch (mode) {
        .inherit => {
            result.process = try registerResource(.{ .process = .{
                .pid = pid,
                .process_group = effective_process_group,
                .pidfd = pidfd_fd,
                .capture_output = false,
            } });
            pidfd_fd = null;
            return result;
        },
        .capture => {
            result.process = registerResource(.{ .process = .{
                .pid = pid,
                .process_group = effective_process_group,
                .pidfd = pidfd_fd,
                .capture_output = true,
                .stdout_fd = stdout_pipe[0],
                .stderr_fd = stderr_pipe[0],
            } }) catch |err| {
                killAndWaitChild(pid);
                return err;
            };
            pidfd_fd = null;
            stdout_pipe[0] = -1;
            stderr_pipe[0] = -1;
            return result;
        },
        .stream => {
            result.stdout = registerResource(.{ .owned_fd = .{ .fd = stdout_pipe[0] } }) catch |err| {
                killAndWaitChild(pid);
                return err;
            };
            stdout_pipe[0] = -1;
            result.stderr = registerResource(.{ .owned_fd = .{ .fd = stderr_pipe[0] } }) catch |err| {
                if (result.stdout) |stdout_handle| _ = sa_std_close(stdout_handle);
                killAndWaitChild(pid);
                return err;
            };
            stderr_pipe[0] = -1;
            if (stdin_pipe[1] != -1) {
                result.stdin = registerResource(.{ .owned_fd = .{ .fd = stdin_pipe[1] } }) catch |err| {
                    if (result.stdout) |stdout_handle| _ = sa_std_close(stdout_handle);
                    if (result.stderr) |stderr_handle| _ = sa_std_close(stderr_handle);
                    killAndWaitChild(pid);
                    return err;
                };
                stdin_pipe[1] = -1;
            }
            result.process = registerResource(.{ .process = .{
                .pid = pid,
                .process_group = effective_process_group,
                .pidfd = pidfd_fd,
                .capture_output = false,
            } }) catch |err| {
                if (result.stdout) |stdout_handle| _ = sa_std_close(stdout_handle);
                if (result.stderr) |stderr_handle| _ = sa_std_close(stderr_handle);
                if (result.stdin) |stdin_handle| _ = sa_std_close(stdin_handle);
                killAndWaitChild(pid);
                return err;
            };
            pidfd_fd = null;
            return result;
        },
    }
}

pub fn spawnProcessCwd(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode, cwd: ?[]const u8) !SpawnResult {
    return spawnProcessConfiguredCwd(allocator, argv, mode, cwd, .{});
}

pub fn spawnProcess(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode) !SpawnResult {
    return spawnProcessCwd(allocator, argv, mode, null);
}

pub fn lxErr(e: std.os.linux.E) anyerror {
    if (comptime is_wasm) return error.Unsupported;
    return errnoToAny(e);
}

fn lxDup2(old: std.posix.fd_t, new: std.posix.fd_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.dup2(old, new));
        return;
    }
    try libcErrRc(libc.dup2(old, new));
}

fn lxFork() !std.posix.pid_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.fork());
        return @as(std.posix.pid_t, @bitCast(@as(u32, @truncate(rc))));
    }
    try libcErrRc(libc.fork());
    return 0;
}

fn lxPipe2(flags: std.posix.O) ![2]std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    var fds: [2]std.posix.fd_t = undefined;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.pipe2(&fds, flags));
        return fds;
    }
    var cfds: [2]c_int = undefined;
    try libcErrRc(libc.pipe(&cfds));
    fds = .{ cfds[0], cfds[1] };
    _ = libc.fcntl(fds[0], std.c.F.SETFD, @as(c_int, 1));
    _ = libc.fcntl(fds[1], std.c.F.SETFD, @as(c_int, 1));
    return fds;
}

fn lxChdir(path: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.chdir(&z));
        return;
    }
    try libcErrRc(libc.chdir(&z));
}

pub fn lxChroot(path: [*:0]const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.chroot(path));
        return;
    }
    try libcErrRc(libc.chroot(path));
}

fn lxSetgroups(groups: []const std.posix.gid_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const groups_ptr: [*]const std.os.linux.gid_t = @ptrCast(groups.ptr);
        _ = try lxCheck(std.os.linux.setgroups(groups.len, groups_ptr));
        return;
    }
    const groups_ptr: [*]const std.c.gid_t = @ptrCast(groups.ptr);
    try libcErrRc(libc.setgroups(@intCast(groups.len), groups_ptr));
}

fn lxSetsid() !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setsid());
        return;
    }
    try libcErrRc(libc.setsid());
}

fn lxSetgid(gid: std.posix.gid_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setgid(gid));
        return;
    }
    try libcErrRc(libc.setgid(@intCast(gid)));
}

fn lxSetuid(uid: std.posix.uid_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setuid(uid));
        return;
    }
    try libcErrRc(libc.setuid(@intCast(uid)));
}

fn lxSetpgid(pid: std.posix.pid_t, pgid: std.posix.pid_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setpgid(pid, pgid));
        return;
    }
    try libcErrRc(libc.setpgid(@intCast(pid), @intCast(pgid)));
}

pub const LxWaitResult = struct {
    pid: std.posix.pid_t,
    status: u32,
};

pub fn lxWaitpid(pid: std.posix.pid_t, flags: u32) LxWaitResult {
    if (comptime is_wasm) return .{ .pid = 0, .status = 0 };
    var status: i32 = 0;
    if (comptime is_linux) {
        while (true) {
            const rc = std.os.linux.waitpid(pid, &status, flags);
            const e = std.os.linux.errno(rc);
            if (e == .SUCCESS) return .{ .pid = @as(std.posix.pid_t, @bitCast(@as(u32, @truncate(rc)))), .status = @bitCast(status) };
            if (e == .INTR) continue;
            return .{ .pid = 0, .status = 0 };
        }
    }
    while (true) {
        const rc = libc.waitpid(@intCast(pid), &status, @intCast(flags));
        const e = std.posix.errno(rc);
        if (e == .SUCCESS) return .{ .pid = @intCast(rc), .status = @bitCast(status) };
        if (e == .INTR) continue;
        return .{ .pid = 0, .status = 0 };
    }
}

pub fn lxExecvpeZ(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) anyerror {
    if (comptime is_wasm) return error.Unsupported;
    const do_exec = struct {
        fn run(path: [*:0]const u8, av: [*:null]const ?[*:0]const u8, ev: [*:null]const ?[*:0]const u8) anyerror {
            if (comptime is_linux) {
                const rc = std.os.linux.execve(path, av, ev);
                return lxErr(std.os.linux.errno(rc));
            }
            const rc = libc.execve(path, av, ev);
            return errnoToAny(std.posix.errno(rc));
        }
    }.run;
    if (std.mem.indexOfScalar(u8, std.mem.span(file), '/') != null) {
        return do_exec(file, argv, envp);
    }
    var last: anyerror = error.FileNotFound;
    var idx: usize = 0;
    while (environ[idx] != null) : (idx += 1) {
        const entry = std.mem.span(environ[idx].?);
        if (!std.mem.startsWith(u8, entry, "PATH=")) continue;
        var it = std.mem.splitScalar(u8, entry["PATH=".len..], ':');
        while (it.next()) |dir| {
            const dir_use = if (dir.len == 0) "." else dir;
            var path_buf: [std.posix.PATH_MAX]u8 = undefined;
            const full = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir_use, std.mem.span(file) }) catch continue;
            var zbuf: [std.posix.PATH_MAX:0]u8 = undefined;
            if (full.len >= zbuf.len) continue;
            @memcpy(zbuf[0..full.len], full);
            zbuf[full.len] = 0;
            last = do_exec(zbuf[0..full.len :0], argv, envp);
        }
        return last;
    }
    return last;
}

fn lxExit(code: u8) noreturn {
    if (comptime is_linux) std.os.linux.exit(code);
    libc._exit(@intCast(code));
}

pub export fn sa_std_close(handle: u64) i32 {
    if (handle == SA_STD_STDIN or handle == SA_STD_STDOUT or handle == SA_STD_STDERR) return finish(SA_STD_ERR_INVALID_HANDLE);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    var resource = takeResourceLocked(handle) orelse {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    sa_std.registry_mutex.unlock();
    resource.close() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_dl_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub fn processCommandExtConfig(arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, create_pidfd: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, groups_ptr: ?[*]const u32, groups_len: u64, has_groups: u32, chroot_ptr: ?[*]const u8, chroot_len: u64, has_chroot: u32) !ProcessSpawnConfig {
    if (has_process_group != 0 and process_group < 0) return error.InvalidArgument;
    return .{
        .arg0 = if (has_arg0 != 0) try constBytes(arg0_ptr, arg0_len) else null,
        .process_group = if (has_process_group != 0) process_group else null,
        .setsid = setsid != 0,
        .create_pidfd = create_pidfd != 0,
        .uid = if (has_uid != 0) uid else null,
        .gid = if (has_gid != 0) gid else null,
        .groups = if (has_groups != 0) try constU32s(groups_ptr, groups_len) else null,
        .chroot_path = if (has_chroot != 0) try pathBytes(chroot_ptr, chroot_len) else null,
    };
}

pub export fn sa_std_pidfd_kill(handle: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .owned_fd => |fd| {
            sendSignalToPidfd(fd.fd, @backingInt(SIGT.KILL), 0) catch |err| switch (err) {
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

pub export fn sa_std_pidfd_send_signal(handle: u64, signum: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (signum < 0 or signum > std.math.maxInt(u8)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .owned_fd => |fd| {
            sendSignalToPidfd(fd.fd, @as(u8, @intCast(signum)), 0) catch |err| switch (err) {
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

pub export fn sa_std_fd_into_raw(handle: u64, out_fd: ?*i32) i32 {
    const fd_ptr = out_fd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fd_ptr.* = -1;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();

    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    switch (resource.*) {
        .file, .tcp_stream, .tcp_listener, .udp_socket, .owned_fd => {},
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    }

    const taken = takeResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    fd_ptr.* = switch (taken) {
        .file => |file| @as(i32, @intCast(file.inner.handle)),
        .tcp_stream => |stream| @as(i32, @intCast(stream)),
        .tcp_listener => |server| @as(i32, @intCast(server.fd)),
        .udp_socket => |fd_value| @as(i32, @intCast(fd_value)),
        .owned_fd => |fd_handle| @as(i32, @intCast(fd_handle.fd)),
        else => unreachable,
    };
    return finish(SA_STD_OK);
}
