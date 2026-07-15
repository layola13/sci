const std = @import("std");

pub const SA_STD_ABI_VERSION: u32 = 1;
pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = 1;
pub const SA_STD_ERR_INVALID_HANDLE: i32 = 2;
pub const SA_STD_ERR_NOT_FOUND: i32 = 3;
pub const SA_STD_ERR_ACCESS: i32 = 4;
pub const SA_STD_ERR_NO_MEMORY: i32 = 5;
pub const SA_STD_ERR_IO: i32 = 6;
pub const SA_STD_ERR_NET: i32 = 7;
pub const SA_STD_ERR_UNSUPPORTED: i32 = 8;
pub const SA_STD_ERR_TRUNCATED: i32 = 9;
pub const SA_STD_ERR_UNKNOWN: i32 = 127;
pub const SA_STD_STDIN: u64 = 1;
pub const SA_STD_STDOUT: u64 = 2;
pub const SA_STD_STDERR: u64 = 3;
pub const SA_FS_FILE_REGULAR: u32 = 1;
pub const SA_FS_FILE_DIR: u32 = 2;
pub const SA_FS_FILE_SYMLINK: u32 = 3;
pub const SA_FS_FILE_OTHER: u32 = 255;

pub const SaJsonToken = extern struct { kind: u32, text_ptr: ?[*]const u8, text_len: u64 };
pub const SaProcessArgv = extern struct { data: [*]const u8, len: u64 };
pub const SaTermWinsize = extern struct { row: u16, col: u16, xpixel: u16, ypixel: u16 };
pub const SaTermEpollEvent = extern struct { events: u32, data: u64 };
pub const TimeDate = extern struct { unix_ms: i64, unix_ns: i64, year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8, millisecond: u16 };
const BufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
};
pub fn Fallible(comptime T: type) type {
    return extern struct { status: i32, value: T };
}

const FIRST_DYNAMIC_HANDLE: u64 = 4;
const DEFAULT_CAPTURE_LIMIT: usize = 8 * 1024 * 1024;

const MetadataHandle = struct {
    stat: std.fs.File.Stat,
};

const DirEntrySnapshot = struct {
    name: []u8,
    kind: u32,
};

const DirEntriesHandle = struct {
    entries: []DirEntrySnapshot,

    fn deinit(self: *DirEntriesHandle) void {
        for (self.entries) |entry| {
            if (entry.name.len != 0) std.heap.page_allocator.free(entry.name);
        }
        if (self.entries.len != 0) std.heap.page_allocator.free(self.entries);
        self.* = undefined;
    }
};

const DirEntryHandle = struct {
    name: []u8,
    kind: u32,

    fn deinit(self: *DirEntryHandle) void {
        if (self.name.len != 0) std.heap.page_allocator.free(self.name);
        self.* = undefined;
    }
};

const NetAddrHandle = struct {
    address: std.net.Address,
    host: []u8,

    fn deinit(self: *NetAddrHandle) void {
        std.heap.page_allocator.free(self.host);
        self.* = undefined;
    }
};

const ProcessSpawnMode = enum {
    inherit,
    capture,
    stream,
};

const ProcessCaptureStream = enum {
    stdout,
    stderr,
};

const ProcessCapturePoller = std.io.Poller(ProcessCaptureStream);

const ProcessHandle = struct {
    mutex: std.Thread.Mutex = .{},
    lifetime_mutex: std.Thread.Mutex = .{},
    lifetime_condition: std.Thread.Condition = .{},
    active_operations: usize = 0,
    child: ?std.process.Child = null,
    args: [][]u8 = &.{},
    argv: [][]const u8 = &.{},
    mode: ProcessSpawnMode = .inherit,
    capture_poller: ?ProcessCapturePoller = null,
    pid: u32 = 0,
    exited: bool = false,
    code: u32 = 0,
    completion_status: i32 = SA_STD_OK,
    stdout_bytes: []u8 = &.{},
    stderr_bytes: []u8 = &.{},
    stdout_pos: usize = 0,
    stderr_pos: usize = 0,

    fn deinit(self: *ProcessHandle) void {
        cancelProcessCapture(self);
        if (self.child) |*child| {
            if (!self.exited) _ = child.kill() catch child.wait() catch .{ .Unknown = 0 };
        }
        self.child = null;
        for (self.args) |arg| if (arg.len != 0) std.heap.page_allocator.free(arg);
        if (self.args.len != 0) std.heap.page_allocator.free(self.args);
        if (self.argv.len != 0) std.heap.page_allocator.free(self.argv);
        if (self.stdout_bytes.len != 0) std.heap.page_allocator.free(self.stdout_bytes);
        if (self.stderr_bytes.len != 0) std.heap.page_allocator.free(self.stderr_bytes);
        self.args = &.{};
        self.argv = &.{};
        self.stdout_bytes = &.{};
        self.stderr_bytes = &.{};
        self.stdout_pos = 0;
        self.stderr_pos = 0;
    }
};

const Resource = union(enum) {
    file: std.fs.File,
    buffer: []u8,
    metadata: MetadataHandle,
    dir_entries: DirEntriesHandle,
    dir_entry: DirEntryHandle,
    net_addr: NetAddrHandle,
    dynamic_lib: std.DynLib,
    tcp_stream: std.net.Stream,
    tcp_listener: std.net.Server,
    udp_socket: std.posix.socket_t,
    process: *ProcessHandle,

    fn close(self: *Resource) void {
        switch (self.*) {
            .file => |file| file.close(),
            .buffer => |bytes| if (bytes.len != 0) std.heap.page_allocator.free(bytes),
            .metadata => {},
            .dir_entries => |*entries| entries.deinit(),
            .dir_entry => |*entry| entry.deinit(),
            .net_addr => |*addr| addr.deinit(),
            .dynamic_lib => |*lib| lib.close(),
            .tcp_stream => |stream| stream.close(),
            .tcp_listener => |*server| server.deinit(),
            .udp_socket => |socket| (std.net.Stream{ .handle = socket }).close(),
            .process => |process| {
                process.lifetime_mutex.lock();
                while (process.active_operations != 0) {
                    process.lifetime_condition.wait(&process.lifetime_mutex);
                }
                process.lifetime_mutex.unlock();
                process.mutex.lock();
                process.deinit();
                process.mutex.unlock();
                std.heap.page_allocator.destroy(process);
            },
        }
        self.* = undefined;
    }
};

var registry_mutex: std.Thread.Mutex = .{};
var time_mutex: std.Thread.Mutex = .{};
var registry_slots = std.ArrayList(?Resource).init(std.heap.page_allocator);
var monotonic_origin: ?std.time.Instant = null;
threadlocal var last_error: i32 = SA_STD_OK;

fn finish(status: i32) i32 {
    last_error = status;
    return status;
}

fn mapError(err: anyerror) i32 {
    return switch (err) {
        error.InvalidArgument, error.BadPathName, error.NameTooLong, error.InvalidUtf8, error.InvalidWtf8, error.NotDir, error.IsDir => SA_STD_ERR_INVALID_ARGUMENT,
        error.InvalidHandle, error.NotOpenForReading, error.NotOpenForWriting => SA_STD_ERR_INVALID_HANDLE,
        error.FileNotFound, error.ProcessNotFound, error.EnvironmentVariableNotFound => SA_STD_ERR_NOT_FOUND,
        error.AccessDenied, error.PermissionDenied => SA_STD_ERR_ACCESS,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.ConnectionRefused, error.ConnectionResetByPeer, error.ConnectionTimedOut, error.NetworkUnreachable, error.AddressNotAvailable, error.AddressInUse => SA_STD_ERR_NET,
        error.Unsupported, error.OperationNotSupported, error.AddressFamilyNotSupported => SA_STD_ERR_UNSUPPORTED,
        else => SA_STD_ERR_IO,
    };
}

fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

fn dynamicIndex(handle: u64) ?usize {
    if (handle < FIRST_DYNAMIC_HANDLE) return null;
    return std.math.cast(usize, handle - FIRST_DYNAMIC_HANDLE);
}

fn registerResourceLocked(resource: Resource) !u64 {
    for (registry_slots.items, 0..) |slot, index| {
        if (slot == null) {
            registry_slots.items[index] = resource;
            return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(index));
        }
    }
    const index = registry_slots.items.len;
    try registry_slots.append(resource);
    return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(index));
}

fn registerResource(resource: Resource) !u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    return registerResourceLocked(resource);
}

fn getResourceLocked(handle: u64) ?*Resource {
    const index = dynamicIndex(handle) orelse return null;
    if (index >= registry_slots.items.len) return null;
    return if (registry_slots.items[index]) |*resource| resource else null;
}

fn takeResourceLocked(handle: u64) ?Resource {
    const index = dynamicIndex(handle) orelse return null;
    if (index >= registry_slots.items.len) return null;
    const resource = registry_slots.items[index] orelse return null;
    registry_slots.items[index] = null;
    return resource;
}

fn lenAsUsize(len: u64) !usize {
    return std.math.cast(usize, len) orelse error.InvalidArgument;
}

fn constBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const size = try lenAsUsize(len);
    if (size == 0) return &.{};
    return (ptr orelse return error.InvalidArgument)[0..size];
}

fn mutBytes(ptr: ?[*]u8, len: u64) ![]u8 {
    const size = try lenAsUsize(len);
    if (size == 0) return &.{};
    return (ptr orelse return error.InvalidArgument)[0..size];
}

fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

fn registerOwnedBytes(bytes: []u8) !u64 {
    errdefer if (bytes.len != 0) std.heap.page_allocator.free(bytes);
    return registerResource(.{ .buffer = bytes });
}

fn duplicateAndRegister(bytes: []const u8) !u64 {
    return registerOwnedBytes(try std.heap.page_allocator.dupe(u8, bytes));
}

const ProcessSpawnResult = struct {
    process: u64,
    stdout: u64 = 0,
    stderr: u64 = 0,
};

fn initProcessHandle(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, mode: ProcessSpawnMode) !ProcessHandle {
    const count = try lenAsUsize(argv_len);
    if (count == 0) return error.InvalidArgument;
    const entries = argv_ptr orelse return error.InvalidArgument;

    var process: ProcessHandle = .{ .mode = mode };
    errdefer process.deinit();
    process.args = try std.heap.page_allocator.alloc([]u8, count);
    for (process.args) |*arg| arg.* = &.{};
    process.argv = try std.heap.page_allocator.alloc([]const u8, count);

    for (process.args, process.argv, 0..) |*owned, *view, index| {
        const entry = entries[index];
        const len = try lenAsUsize(entry.len);
        if (len == 0) {
            view.* = &.{};
            continue;
        }
        if (@intFromPtr(entry.data) == 0) return error.InvalidArgument;
        const bytes = entry.data[0..len];
        if (std.mem.indexOfScalar(u8, bytes, 0) != null) return error.InvalidArgument;
        owned.* = try std.heap.page_allocator.dupe(u8, bytes);
        view.* = owned.*;
    }
    if (process.argv[0].len == 0) return error.InvalidArgument;
    return process;
}

fn windowsProcessInfo(handle: std.os.windows.HANDLE) !std.os.windows.PROCESS_BASIC_INFORMATION {
    const windows = std.os.windows;
    var info: windows.PROCESS_BASIC_INFORMATION = undefined;
    var returned: windows.ULONG = 0;
    const status = windows.ntdll.NtQueryInformationProcess(
        handle,
        .ProcessBasicInformation,
        &info,
        @sizeOf(windows.PROCESS_BASIC_INFORMATION),
        &returned,
    );
    return switch (status) {
        .SUCCESS => info,
        .ACCESS_DENIED => error.AccessDenied,
        .INVALID_HANDLE => error.InvalidHandle,
        else => windows.unexpectedStatus(status),
    };
}

fn windowsProcessExitCode(handle: std.os.windows.HANDLE) !u32 {
    const windows = std.os.windows;
    var code: windows.DWORD = 0;
    if (windows.kernel32.GetExitCodeProcess(handle, &code) == 0) {
        return windows.unexpectedError(windows.GetLastError());
    }
    return code;
}

fn spawnWindowsProcess(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd: ?[]const u8, mode: ProcessSpawnMode) !ProcessSpawnResult {
    const process = try std.heap.page_allocator.create(ProcessHandle);
    process.* = initProcessHandle(argv_ptr, argv_len, mode) catch |err| {
        std.heap.page_allocator.destroy(process);
        return err;
    };
    var process_owned = true;
    defer if (process_owned) {
        process.deinit();
        std.heap.page_allocator.destroy(process);
    };

    var child = std.process.Child.init(process.argv, std.heap.page_allocator);
    child.cwd = cwd;
    switch (mode) {
        .inherit => {
            child.stdin_behavior = .Inherit;
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
        },
        .capture, .stream => {
            child.stdin_behavior = .Inherit;
            child.stdout_behavior = .Pipe;
            child.stderr_behavior = .Pipe;
        },
    }
    try child.spawn();
    child.cwd = null;
    process.child = child;
    const spawned_child = if (process.child) |*value| value else unreachable;

    const info = try windowsProcessInfo(spawned_child.id);
    process.pid = std.math.cast(u32, info.UniqueProcessId) orelse return error.InvalidArgument;

    if (mode == .capture) {
        process.capture_poller = std.io.poll(std.heap.page_allocator, ProcessCaptureStream, .{
            .stdout = spawned_child.stdout orelse return error.InvalidHandle,
            .stderr = spawned_child.stderr orelse return error.InvalidHandle,
        });
    }

    var stdout_handle: u64 = 0;
    errdefer {
        if (stdout_handle != 0) _ = sa_std_close(stdout_handle);
    }
    var stderr_handle: u64 = 0;
    errdefer {
        if (stderr_handle != 0) _ = sa_std_close(stderr_handle);
    }
    if (mode == .stream) {
        const stdout_file = spawned_child.stdout orelse return error.InvalidHandle;
        spawned_child.stdout = null;
        stdout_handle = registerResource(.{ .file = stdout_file }) catch |err| {
            stdout_file.close();
            return err;
        };

        const stderr_file = spawned_child.stderr orelse return error.InvalidHandle;
        spawned_child.stderr = null;
        stderr_handle = registerResource(.{ .file = stderr_file }) catch |err| {
            stderr_file.close();
            return err;
        };
    }

    const process_handle = try registerResource(.{ .process = process });
    process_owned = false;
    return .{ .process = process_handle, .stdout = stdout_handle, .stderr = stderr_handle };
}

fn lockProcessHandle(handle: u64) !*ProcessHandle {
    registry_mutex.lock();
    const resource = getResourceLocked(handle) orelse {
        registry_mutex.unlock();
        return error.InvalidHandle;
    };
    const process = switch (resource.*) {
        .process => |value| value,
        else => {
            registry_mutex.unlock();
            return error.InvalidHandle;
        },
    };
    process.lifetime_mutex.lock();
    process.active_operations += 1;
    process.lifetime_mutex.unlock();
    registry_mutex.unlock();
    process.mutex.lock();
    return process;
}

fn unlockProcessHandle(process: *ProcessHandle) void {
    process.mutex.unlock();
    process.lifetime_mutex.lock();
    std.debug.assert(process.active_operations != 0);
    process.active_operations -= 1;
    if (process.active_operations == 0) process.lifetime_condition.broadcast();
    process.lifetime_mutex.unlock();
}

fn captureLimitExceeded(poller: *ProcessCapturePoller) bool {
    const stdout_len = poller.fifo(.stdout).readableLength();
    const stderr_len = poller.fifo(.stderr).readableLength();
    return stdout_len > DEFAULT_CAPTURE_LIMIT or stderr_len > DEFAULT_CAPTURE_LIMIT - stdout_len;
}

fn drainProcessCaptureAvailable(poller: *ProcessCapturePoller) !bool {
    while (true) {
        const before = poller.fifo(.stdout).readableLength() + poller.fifo(.stderr).readableLength();
        const streams_open = try poller.pollTimeout(0);
        if (captureLimitExceeded(poller)) return false;
        const after = poller.fifo(.stdout).readableLength() + poller.fifo(.stderr).readableLength();
        if (!streams_open or after == before) return true;
    }
}

fn settleProcessCaptureIo(poller: *ProcessCapturePoller, preserve_completed: bool) !void {
    const windows = std.os.windows;
    var transferred_by_stream = [_]windows.DWORD{0} ** 2;
    var first_error: ?anyerror = null;
    const active_count: usize = @intCast(poller.windows.active.count);
    for (0..active_count) |active_index| {
        const handle = poller.windows.active.handles_buf[active_index];
        const stream = poller.windows.active.stream_map[active_index];
        const stream_index = @intFromEnum(stream);
        const overlapped = &poller.windows.overlapped[stream_index];

        if (windows.kernel32.CancelIoEx(handle, overlapped) == 0) switch (windows.GetLastError()) {
            .NOT_FOUND => {},
            else => |err| if (first_error == null) {
                first_error = windows.unexpectedError(err);
            },
        };

        var transferred: windows.DWORD = 0;
        if (windows.kernel32.GetOverlappedResult(handle, overlapped, &transferred, windows.TRUE) == 0) switch (windows.GetLastError()) {
            .OPERATION_ABORTED, .BROKEN_PIPE, .HANDLE_EOF => {},
            else => |err| if (first_error == null) {
                first_error = windows.unexpectedError(err);
            },
        } else transferred_by_stream[stream_index] = transferred;
    }
    poller.windows.active.count = 0;

    if (preserve_completed) {
        const stdout_len = transferred_by_stream[@intFromEnum(ProcessCaptureStream.stdout)];
        if (stdout_len != 0) poller.fifo(.stdout).write(poller.windows.small_bufs[@intFromEnum(ProcessCaptureStream.stdout)][0..stdout_len]) catch |err| {
            if (first_error == null) first_error = err;
        };
        const stderr_len = transferred_by_stream[@intFromEnum(ProcessCaptureStream.stderr)];
        if (stderr_len != 0) poller.fifo(.stderr).write(poller.windows.small_bufs[@intFromEnum(ProcessCaptureStream.stderr)][0..stderr_len]) catch |err| {
            if (first_error == null) first_error = err;
        };
    }
    if (first_error) |err| return err;
}

fn cancelProcessCapture(process: *ProcessHandle) void {
    if (process.capture_poller) |*poller| {
        settleProcessCaptureIo(poller, false) catch {};
        poller.deinit();
    }
    process.capture_poller = null;
}

fn forceProcessCompletion(process: *ProcessHandle, status: i32) void {
    const windows = std.os.windows;
    cancelProcessCapture(process);
    if (process.child) |*child| {
        windows.TerminateProcess(child.id, 1) catch {};
        windows.WaitForSingleObjectEx(child.id, windows.INFINITE, false) catch {};
        if (windowsProcessExitCode(child.id)) |code| process.code = code else |_| {}
        _ = child.wait() catch {};
        process.child = null;
    }
    process.exited = true;
    process.completion_status = status;
}

fn collectProcessCapture(process: *ProcessHandle) !void {
    var poller = process.capture_poller orelse return error.InvalidHandle;
    process.capture_poller = null;
    defer poller.deinit();
    try settleProcessCaptureIo(&poller, true);

    const stdout_bytes = try poller.fifo(.stdout).toOwnedSlice();
    errdefer if (stdout_bytes.len != 0) std.heap.page_allocator.free(stdout_bytes);
    const stderr_bytes = try poller.fifo(.stderr).toOwnedSlice();
    process.stdout_bytes = stdout_bytes;
    process.stderr_bytes = stderr_bytes;
    process.stdout_pos = 0;
    process.stderr_pos = 0;
}

fn waitForWindowsProcess(process: *ProcessHandle, nohang: bool) !bool {
    const child = if (process.child) |*value| value else return error.InvalidHandle;
    std.os.windows.WaitForSingleObjectEx(child.id, if (nohang) 0 else std.os.windows.INFINITE, false) catch |err| switch (err) {
        error.WaitTimeOut => return false,
        else => return err,
    };
    return true;
}

fn reapWindowsProcess(process: *ProcessHandle) !void {
    const child = if (process.child) |*value| value else return error.InvalidHandle;
    const code_result = windowsProcessExitCode(child.id);
    const wait_result = child.wait();
    process.child = null;
    process.exited = true;
    process.code = try code_result;
    _ = try wait_result;
}

fn advanceWindowsProcess(process: *ProcessHandle, nohang: bool) bool {
    if (process.exited) return true;

    var ready = false;
    if (process.mode == .capture) {
        const poller = &(process.capture_poller orelse {
            forceProcessCompletion(process, SA_STD_ERR_INVALID_HANDLE);
            return true;
        });
        if (nohang) {
            const within_limit = drainProcessCaptureAvailable(poller) catch |err| {
                forceProcessCompletion(process, mapError(err));
                return true;
            };
            if (!within_limit) {
                forceProcessCompletion(process, SA_STD_ERR_TRUNCATED);
                return true;
            }
        } else {
            while (true) {
                const streams_open = poller.pollTimeout(10 * std.time.ns_per_ms) catch |err| {
                    forceProcessCompletion(process, mapError(err));
                    return true;
                };
                if (captureLimitExceeded(poller)) {
                    forceProcessCompletion(process, SA_STD_ERR_TRUNCATED);
                    return true;
                }
                ready = waitForWindowsProcess(process, true) catch |err| {
                    forceProcessCompletion(process, mapError(err));
                    return true;
                };
                if (ready or !streams_open) break;
            }
        }
    }

    if (!ready) ready = waitForWindowsProcess(process, nohang) catch |err| {
        forceProcessCompletion(process, mapError(err));
        return true;
    };
    if (!ready) return false;

    if (process.mode == .capture) {
        const poller = &(process.capture_poller orelse {
            forceProcessCompletion(process, SA_STD_ERR_INVALID_HANDLE);
            return true;
        });
        const within_limit = drainProcessCaptureAvailable(poller) catch |err| {
            forceProcessCompletion(process, mapError(err));
            return true;
        };
        if (!within_limit) {
            forceProcessCompletion(process, SA_STD_ERR_TRUNCATED);
            return true;
        }
        collectProcessCapture(process) catch |err| {
            forceProcessCompletion(process, mapError(err));
            return true;
        };
        if (process.stdout_bytes.len > DEFAULT_CAPTURE_LIMIT or process.stderr_bytes.len > DEFAULT_CAPTURE_LIMIT - process.stdout_bytes.len) {
            forceProcessCompletion(process, SA_STD_ERR_TRUNCATED);
            return true;
        }
    }
    reapWindowsProcess(process) catch |err| {
        process.completion_status = mapError(err);
        return true;
    };
    return true;
}

fn processSingleSpawnExport(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd: ?[]const u8, mode: ProcessSpawnMode, out_handle: ?*u64) i32 {
    if (out_handle) |handle| handle.* = 0;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const result = spawnWindowsProcess(argv_ptr, argv_len, cwd, mode) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

fn processStreamSpawnExport(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd: ?[]const u8, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (out_process) |handle| handle.* = 0;
    if (out_stdout) |handle| handle.* = 0;
    if (out_stderr) |handle| handle.* = 0;
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const result = spawnWindowsProcess(argv_ptr, argv_len, cwd, .stream) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout;
    stderr_ptr.* = result.stderr;
    return finish(SA_STD_OK);
}

fn processExtUnsupported(has_arg0: u32, has_process_group: u32, setsid: u32, has_platform_feature: u32) bool {
    return has_arg0 != 0 or has_process_group != 0 or setsid != 0 or has_platform_feature != 0;
}

fn processExtSingleSpawnExport(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, has_arg0: u32, has_process_group: u32, setsid: u32, has_platform_feature: u32, mode: ProcessSpawnMode, out_handle: ?*u64) i32 {
    if (out_handle) |handle| handle.* = 0;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (processExtUnsupported(has_arg0, has_process_group, setsid, has_platform_feature)) return finish(SA_STD_ERR_UNSUPPORTED);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const result = spawnWindowsProcess(argv_ptr, argv_len, cwd, mode) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

fn processExtStreamSpawnExport(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, has_arg0: u32, has_process_group: u32, setsid: u32, has_platform_feature: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (out_process) |handle| handle.* = 0;
    if (out_stdout) |handle| handle.* = 0;
    if (out_stderr) |handle| handle.* = 0;
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (processExtUnsupported(has_arg0, has_process_group, setsid, has_platform_feature)) return finish(SA_STD_ERR_UNSUPPORTED);
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    const result = spawnWindowsProcess(argv_ptr, argv_len, cwd, .stream) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout;
    stderr_ptr.* = result.stderr;
    return finish(SA_STD_OK);
}

fn processReadCaptured(handle: u64, use_stderr: bool, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |read| read.* = 0;
    const target = mutBytes(out, out_cap) catch |err| return finishErr(err);
    const process = lockProcessHandle(handle) catch |err| return finishErr(err);
    defer unlockProcessHandle(process);
    if (process.mode != .capture or !process.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (process.completion_status != SA_STD_OK) return finish(process.completion_status);
    const source = if (use_stderr) process.stderr_bytes else process.stdout_bytes;
    const pos = if (use_stderr) &process.stderr_pos else &process.stdout_pos;
    const count = @min(target.len, source.len -| pos.*);
    if (count != 0) @memcpy(target[0..count], source[pos.* .. pos.* + count]);
    pos.* += count;
    if (out_read) |read| read.* = @intCast(count);
    return finish(SA_STD_OK);
}

fn processExecCaptureExport(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd: ?[]const u8, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (out_code) |code| code.* = 0;
    if (out_stdout) |handle| handle.* = 0;
    if (out_stderr) |handle| handle.* = 0;
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);

    const spawned = spawnWindowsProcess(argv_ptr, argv_len, cwd, .capture) catch |err| return finishErr(err);
    defer _ = sa_std_process_close(spawned.process);
    var code: u32 = 0;
    const wait_status = sa_std_process_wait(spawned.process, &code);
    if (wait_status != SA_STD_OK) return wait_status;

    var stdout_bytes: []u8 = &.{};
    var stderr_bytes: []u8 = &.{};
    {
        const process = lockProcessHandle(spawned.process) catch |err| return finishErr(err);
        defer unlockProcessHandle(process);
        if (process.mode != .capture or !process.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
        if (process.completion_status != SA_STD_OK) return finish(process.completion_status);
        stdout_bytes = process.stdout_bytes;
        stderr_bytes = process.stderr_bytes;
        process.stdout_bytes = &.{};
        process.stderr_bytes = &.{};
    }

    const stdout_handle = registerOwnedBytes(stdout_bytes) catch |err| {
        if (stderr_bytes.len != 0) std.heap.page_allocator.free(stderr_bytes);
        return finishErr(err);
    };
    const stderr_handle = registerOwnedBytes(stderr_bytes) catch |err| {
        _ = sa_std_close(stdout_handle);
        return finishErr(err);
    };
    code_ptr.* = code;
    stdout_ptr.* = stdout_handle;
    stderr_ptr.* = stderr_handle;
    return finish(SA_STD_OK);
}

fn ok(comptime T: type, value: T) Fallible(T) {
    _ = finish(SA_STD_OK);
    return .{ .status = SA_STD_OK, .value = value };
}

fn fail(comptime T: type, status: i32) Fallible(T) {
    _ = finish(status);
    return .{ .status = status, .value = 0 };
}

fn fillUtcNow(out: *TimeDate) !void {
    const unix_ms = std.time.milliTimestamp();
    const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
    if (unix_s < 0) return error.Unsupported;

    const unix_ns = std.math.cast(i64, std.time.nanoTimestamp()) orelse return error.InvalidArgument;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(unix_s) };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    out.* = .{
        .unix_ms = unix_ms,
        .unix_ns = unix_ns,
        .year = year_day.year,
        .month = @intFromEnum(month_day.month),
        .day = @intCast(month_day.day_index + 1),
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
        .millisecond = @intCast(@mod(unix_ms, std.time.ms_per_s)),
    };
}

fn monotonicNowNs() !u64 {
    time_mutex.lock();
    defer time_mutex.unlock();
    const current = try std.time.Instant.now();
    if (monotonic_origin) |origin| return current.since(origin);
    monotonic_origin = current;
    return 0;
}

fn fileKindCode(kind: std.fs.File.Kind) u32 {
    return switch (kind) {
        .file => SA_FS_FILE_REGULAR,
        .directory => SA_FS_FILE_DIR,
        .sym_link => SA_FS_FILE_SYMLINK,
        else => SA_FS_FILE_OTHER,
    };
}

fn saFsOpenFile(path: []const u8, flags: u32, custom_flags: u32) !std.fs.File {
    if (custom_flags != 0) return error.Unsupported;
    const read = (flags & 1) != 0;
    const write = (flags & 2) != 0;
    const create = (flags & 4) != 0;
    const truncate = (flags & 8) != 0;
    const append = (flags & 16) != 0;
    const wants_write = write or append;
    if (!read and !wants_write) return error.InvalidArgument;

    var file = if (create)
        try std.fs.cwd().createFile(path, .{ .read = read, .truncate = truncate })
    else
        try std.fs.cwd().openFile(path, .{ .mode = if (read and wants_write) .read_write else if (wants_write) .write_only else .read_only });
    errdefer file.close();
    if (!create and truncate) try file.setEndPos(0);
    if (append) try file.seekFromEnd(0);
    return file;
}

fn readFileOwned(path: []const u8, max_bytes: u64) ![]u8 {
    const limit = try lenAsUsize(max_bytes);
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();
    return file.readToEndAlloc(std.heap.page_allocator, limit);
}

fn metadataStat(handle: u64) ?std.fs.File.Stat {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .metadata => |metadata| metadata.stat,
        else => null,
    };
}

fn windowsPathStatNoFollow(path: []const u8) !std.fs.File.Stat {
    const windows = std.os.windows;
    const path_w = try windows.sliceToPrefixedFileW(std.fs.cwd().fd, path);
    const handle = try windows.OpenFile(path_w.span(), .{
        .access_mask = windows.FILE_READ_ATTRIBUTES,
        .creation = windows.FILE_OPEN,
        .filter = .any,
        .follow_symlinks = false,
    });
    const file = std.fs.File{ .handle = handle };
    defer file.close();
    return file.stat();
}

fn windowsOpenPathForAttributeUpdate(path: []const u8) !std.fs.File {
    const windows = std.os.windows;
    const path_w = try windows.sliceToPrefixedFileW(std.fs.cwd().fd, path);
    return .{ .handle = try windows.OpenFile(path_w.span(), .{
        .access_mask = windows.FILE_READ_ATTRIBUTES | windows.FILE_WRITE_ATTRIBUTES | windows.SYNCHRONIZE,
        .creation = windows.FILE_OPEN,
        .filter = .any,
    }) };
}

fn windowsTimestampNs(unix_ms: i64) !i128 {
    const ns = @as(i128, unix_ms) * std.time.ns_per_ms;
    const hundred_ns = std.math.cast(i64, @divFloor(ns, 100)) orelse return error.InvalidArgument;
    const epoch_offset = std.time.epoch.windows * (std.time.ns_per_s / 100);
    const file_time = std.math.sub(i64, hundred_ns, epoch_offset) catch return error.InvalidArgument;
    if (file_time < 0) return error.InvalidArgument;
    return ns;
}

fn symlinkTargetIsDirectory(target: []const u8, link: []const u8) !bool {
    var candidate_owned: ?[]u8 = null;
    defer if (candidate_owned) |candidate| std.heap.page_allocator.free(candidate);

    const candidate = if (std.fs.path.isAbsolute(target))
        target
    else if (std.fs.path.dirname(link)) |link_parent| blk: {
        const joined = try std.fs.path.join(std.heap.page_allocator, &.{ link_parent, target });
        candidate_owned = joined;
        break :blk joined;
    } else target;

    const stat = std.fs.cwd().statFile(candidate) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |other| return other,
    };
    return stat.kind == .directory;
}

fn nsToMs(value: i128) i64 {
    return std.math.cast(i64, @divFloor(value, std.time.ns_per_ms)) orelse 0;
}

fn nsToSec(value: i128) i64 {
    return std.math.cast(i64, @divFloor(value, std.time.ns_per_s)) orelse 0;
}

fn nsRemainder(value: i128) i64 {
    return std.math.cast(i64, @mod(value, std.time.ns_per_s)) orelse 0;
}

fn unsupportedStatus() i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

fn unsupported() i32 {
    return unsupportedStatus();
}
fn unsupportedU64() u64 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedU32() u32 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedU8() u8 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedI64() i64 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedF64() f64 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedFallible(comptime T: type) Fallible(T) {
    _ = unsupportedStatus();
    return .{ .status = SA_STD_ERR_UNSUPPORTED, .value = 0 };
}

pub export fn sa_http_client_resp_body_slice(_: ?*anyopaque, _: ?*?[*]const u8, _: ?*u64) u32 {
    return unsupportedU32();
}

pub export fn sa_std_version() u32 {
    return SA_STD_ABI_VERSION;
}

pub export fn sa_std_last_error() i32 {
    return last_error;
}

pub export fn sa_std_error_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = switch (code) {
        SA_STD_OK => "ok",
        SA_STD_ERR_INVALID_ARGUMENT => "invalid_argument",
        SA_STD_ERR_INVALID_HANDLE => "invalid_handle",
        SA_STD_ERR_NOT_FOUND => "not_found",
        SA_STD_ERR_ACCESS => "access",
        SA_STD_ERR_NO_MEMORY => "no_memory",
        SA_STD_ERR_IO => "io",
        SA_STD_ERR_NET => "net",
        SA_STD_ERR_UNSUPPORTED => "unsupported",
        SA_STD_ERR_TRUNCATED => "truncated",
        else => "unknown",
    };
    if (out_len) |len| len.* = @intCast(name.len);
    if (out_cap == 0) return finish(SA_STD_OK);
    const target = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (target.len < name.len) return finish(SA_STD_ERR_TRUNCATED);
    @memcpy(target[0..name.len], name);
    return finish(SA_STD_OK);
}

pub export fn sa_std_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_std_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_std_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_std_print(data_ptr: ?[*]const u8, len: u64) i32 {
    const data = constBytes(data_ptr, len) catch |err| return finishErr(err);
    std.io.getStdOut().writeAll(data) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_println(data_ptr: ?[*]const u8, len: u64) i32 {
    const status = sa_std_print(data_ptr, len);
    if (status != SA_STD_OK) return status;
    std.io.getStdOut().writeAll("\n") catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_cwd() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_chdir(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_deno_env_set(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_deno_env_delete(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_deno_random_uuid() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_make_temp_dir(_: ?[*]const u8, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_deno_make_temp_file(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_deno_args_json() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_btoa(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_atob(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_text_encode(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_text_decode(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_chat_sse_to_responses(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_chat_json_to_responses(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_responses_sse_normalize(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_responses_json_normalize(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_responses_request_normalize(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_responses_chat_fallback_request(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: u8) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_jsonrpc_params_string_literal(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: u8) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_version_json() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_version_deno() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_build_json() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_build_os() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_build_platform_family() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_date_now_iso() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_hostname() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_os_release() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_os_uptime() f64 {
    return unsupportedF64();
}

pub export fn sa_deno_loadavg(_: ?*f64) i32 {
    return unsupported();
}

pub export fn sa_deno_system_memory_info() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_network_interfaces() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_pid() u32 {
    return unsupportedU32();
}

pub export fn sa_deno_ppid() u32 {
    return unsupportedU32();
}

pub export fn sa_deno_uid() u32 {
    return unsupportedU32();
}

pub export fn sa_deno_gid() u32 {
    return unsupportedU32();
}

pub export fn sa_deno_exec_path() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_memory_usage() u64 {
    return unsupportedU64();
}

pub export fn sa_json_parse(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_kind(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_json_object_get(_: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_array_get(_: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_object_key_at(_: u64, _: u64, _: ?*?[*]const u8, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_object_get_string(_: u64, _: ?[*]const u8, _: u64, _: ?*?[*]const u8, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_object_get_bool(_: u64, _: ?[*]const u8, _: u64, _: ?*u8) i32 {
    return unsupported();
}

pub export fn sa_json_object_get_i64(_: u64, _: ?[*]const u8, _: u64, _: ?*i64) i32 {
    return unsupported();
}

pub export fn sa_json_object_get_f64(_: u64, _: ?[*]const u8, _: u64, _: ?*f64) i32 {
    return unsupported();
}

pub export fn sa_json_as_f64(_: u64, _: ?*f64) i32 {
    return unsupported();
}

pub export fn sa_json_as_i64(_: u64, _: ?*i64) i32 {
    return unsupported();
}

pub export fn sa_json_as_bool(_: u64, _: ?*u8) i32 {
    return unsupported();
}

pub export fn sa_json_string_ptr(_: u64) ?[*]const u8 {
    return null;
}

pub export fn sa_json_string_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_value_count(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_json_stringify(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_new(_: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_feed(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_end_input(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_next(_: u64, _: ?*SaJsonToken) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_stream_new(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_stream_next(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_json_stream_get_slice_ptr(_: u64) ?[*]const u8 {
    return null;
}

pub export fn sa_json_stream_get_slice_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_stream_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_json_writer_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_new(_: u32, _: u8, _: u8, _: u8, _: u8, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_begin_object(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_end_object(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_begin_array(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_end_array(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_object_field(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_string(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_bool(_: u64, _: ?[*]const u8, _: u64, _: u8) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_i64(_: u64, _: ?[*]const u8, _: u64, _: i64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_f64(_: u64, _: ?[*]const u8, _: u64, _: f64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_null(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_node(_: u64, _: ?[*]const u8, _: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_bool(_: u64, _: u8) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_i64(_: u64, _: i64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_f64(_: u64, _: f64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_string(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_null(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_node(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_finish(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_regex_compile(_: ?[*]const u8, _: u64, _: i32) u64 {
    return unsupportedU64();
}

pub export fn sa_regex_match(_: u64, _: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_regex_group_ptr(_: u64, _: u32) ?[*]const u8 {
    return null;
}

pub export fn sa_regex_group_len(_: u64, _: u32) u64 {
    return unsupportedU64();
}

pub export fn sa_regex_group_count(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_regex_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_regex_match_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_json_buffer_data(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_json_buffer_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_buffer_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_time_instant_ns() u64 {
    return monotonicNowNs() catch |err| {
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_time_unix_s() i64 {
    _ = finish(SA_STD_OK);
    return std.time.timestamp();
}

pub export fn sa_time_unix_ms() i64 {
    _ = finish(SA_STD_OK);
    return std.time.milliTimestamp();
}

pub export fn sa_time_unix_ns() i64 {
    const value = std.math.cast(i64, std.time.nanoTimestamp()) orelse {
        _ = finish(SA_STD_ERR_INVALID_ARGUMENT);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return value;
}

pub export fn sa_time_utc_now(out_date: ?*TimeDate) i32 {
    const out = out_date orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fillUtcNow(out) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ns(ns: u64) i32 {
    std.Thread.sleep(ns);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ms(ms: u64) i32 {
    const ns = std.math.mul(u64, ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return sa_time_sleep_ns(ns);
}

pub export fn sa_std_write(handle: u64, data_ptr: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const data = constBytes(data_ptr, len) catch |err| return finishErr(err);
    if (out_written) |written| written.* = 0;
    const count = switch (handle) {
        SA_STD_STDOUT => std.io.getStdOut().write(data) catch |err| return finishErr(err),
        SA_STD_STDERR => std.io.getStdErr().write(data) catch |err| return finishErr(err),
        else => blk: {
            registry_mutex.lock();
            defer registry_mutex.unlock();
            const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
            break :blk switch (resource.*) {
                .file => |file| file.write(data) catch |err| return finishErr(err),
                .tcp_stream => |stream| stream.write(data) catch |err| return finishErr(err),
                else => return finish(SA_STD_ERR_INVALID_HANDLE),
            };
        },
    };
    if (out_written) |written| written.* = @intCast(count);
    return finish(SA_STD_OK);
}

pub export fn sa_std_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    const target = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (out_read) |read| read.* = 0;
    const count = switch (handle) {
        SA_STD_STDIN => std.io.getStdIn().read(target) catch |err| return finishErr(err),
        else => blk: {
            registry_mutex.lock();
            defer registry_mutex.unlock();
            const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
            break :blk switch (resource.*) {
                .file => |file| file.read(target) catch |err| return finishErr(err),
                .tcp_stream => |stream| stream.read(target) catch |err| return finishErr(err),
                else => return finish(SA_STD_ERR_INVALID_HANDLE),
            };
        },
    };
    if (out_read) |read| read.* = @intCast(count);
    return finish(SA_STD_OK);
}

pub export fn sa_std_close(handle: u64) i32 {
    if (handle < FIRST_DYNAMIC_HANDLE) return finish(SA_STD_ERR_INVALID_HANDLE);
    registry_mutex.lock();
    var resource = takeResourceLocked(handle) orelse {
        registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    registry_mutex.unlock();
    resource.close();
    return finish(SA_STD_OK);
}

pub export fn sa_io_read_line(_: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_dl_open(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var lib = std.DynLib.open(path) catch |err| return finishErr(err);
    const handle = registerResource(.{ .dynamic_lib = lib }) catch |err| {
        lib.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_dl_sym(handle: u64, symbol_ptr: ?[*]const u8, symbol_len: u64, out_ptr: ?*?*anyopaque) i32 {
    const target = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    target.* = null;
    const symbol = constBytes(symbol_ptr, symbol_len) catch |err| return finishErr(err);
    if (symbol.len == 0 or std.mem.indexOfScalar(u8, symbol, 0) != null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const symbol_z = std.heap.page_allocator.dupeZ(u8, symbol) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(symbol_z);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .dynamic_lib => |*lib| {
            target.* = lib.lookup(*anyopaque, symbol_z) orelse return finish(SA_STD_ERR_NOT_FOUND);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_dl_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_dl_error() ?[*:0]const u8 {
    return "unsupported";
}

pub export fn sa_std_fs_open_read(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return finishErr(err);
    const handle = registerResource(.{ .file = file }) catch |err| {
        file.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_open_write(path_ptr: ?[*]const u8, path_len: u64, truncate: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = truncate != 0 }) catch |err| return finishErr(err);
    const handle = registerResource(.{ .file = file }) catch |err| {
        file.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_remove(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteFile(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_exists(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().access(path, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_try_exists(path_ptr: ?[*]const u8, path_len: u64, out_exists: ?*u8) i32 {
    const exists = out_exists orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    exists.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return finish(SA_STD_OK),
        else => return finishErr(err),
    };
    exists.* = 1;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_len(path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const size = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    size.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const stat = std.fs.cwd().statFile(path) catch |err| return finishErr(err);
    size.* = stat.size;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    return processSingleSpawnExport(argv_ptr, argv_len, null, .capture, out_handle);
}

pub export fn sa_std_process_run_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    if (out_handle) |handle| handle.* = 0;
    if (out_handle == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    return processSingleSpawnExport(argv_ptr, argv_len, cwd, .capture, out_handle);
}

pub export fn sa_std_process_spawn(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    return processSingleSpawnExport(argv_ptr, argv_len, null, .inherit, out_handle);
}

pub export fn sa_std_process_spawn_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    if (out_handle) |handle| handle.* = 0;
    if (out_handle == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    return processSingleSpawnExport(argv_ptr, argv_len, cwd, .inherit, out_handle);
}

pub export fn sa_std_process_spawn_stream(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return processStreamSpawnExport(argv_ptr, argv_len, null, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_spawn_stream_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (out_process) |handle| handle.* = 0;
    if (out_stdout) |handle| handle.* = 0;
    if (out_stderr) |handle| handle.* = 0;
    if (out_process == null or out_stdout == null or out_stderr == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    return processStreamSpawnExport(argv_ptr, argv_len, cwd, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, 0, .capture, out_handle);
}

pub export fn sa_std_process_spawn_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, 0, .inherit, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return processExtStreamSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, 0, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, create_pidfd: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, create_pidfd, .capture, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, create_pidfd: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, create_pidfd, .inherit, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, create_pidfd: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return processExtStreamSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, create_pidfd, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: u32, has_uid: u32, _: u32, has_gid: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_uid | has_gid, .capture, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: u32, has_uid: u32, _: u32, has_gid: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_uid | has_gid, .inherit, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: u32, has_uid: u32, _: u32, has_gid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return processExtStreamSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_uid | has_gid, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, has_groups: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_groups, .capture, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, has_groups: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_groups, .inherit, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, has_groups: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return processExtStreamSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_groups, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, has_chroot: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_chroot, .capture, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, has_chroot: u32, out_handle: ?*u64) i32 {
    return processExtSingleSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_chroot, .inherit, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, _: ?[*]const u8, _: u64, has_arg0: u32, _: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, has_chroot: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return processExtStreamSpawnExport(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, has_arg0, has_process_group, setsid, has_chroot, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_exec_command_ext(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, _: u32, _: u32, _: u32, _: ?[*]const u32, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_process_id() u32 {
    _ = finish(SA_STD_OK);
    return std.os.windows.GetCurrentProcessId();
}

pub export fn sa_std_process_parent_id() u32 {
    const info = windowsProcessInfo(std.os.windows.GetCurrentProcess()) catch |err| {
        _ = finishErr(err);
        return 0;
    };
    const pid = std.math.cast(u32, info.InheritedFromUniqueProcessId) orelse {
        _ = finish(SA_STD_ERR_IO);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return pid;
}

pub export fn sa_std_process_user_id() u32 {
    return unsupportedU32();
}

pub export fn sa_std_process_group_id() u32 {
    return unsupportedU32();
}

pub export fn sa_std_process_abort() noreturn {
    std.posix.abort();
}

pub export fn sa_std_process_child_id(handle: u64, out_pid: ?*u32) i32 {
    if (out_pid) |pid| pid.* = 0;
    const pid_ptr = out_pid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const process = lockProcessHandle(handle) catch |err| return finishErr(err);
    defer unlockProcessHandle(process);
    pid_ptr.* = process.pid;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_wait(handle: u64, out_code: ?*u32) i32 {
    if (out_code) |code| code.* = 0;
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const process = lockProcessHandle(handle) catch |err| return finishErr(err);
    defer unlockProcessHandle(process);
    _ = advanceWindowsProcess(process, false);
    if (process.completion_status != SA_STD_OK) return finish(process.completion_status);
    code_ptr.* = process.code;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_wait_raw(handle: u64, out_raw: ?*i32) i32 {
    if (out_raw) |raw| raw.* = 0;
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const process = lockProcessHandle(handle) catch |err| return finishErr(err);
    defer unlockProcessHandle(process);
    _ = advanceWindowsProcess(process, false);
    if (process.completion_status != SA_STD_OK) return finish(process.completion_status);
    raw_ptr.* = @bitCast(process.code);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_try_wait(handle: u64, out_ready: ?*i32, out_code: ?*u32) i32 {
    if (out_ready) |ready| ready.* = 0;
    if (out_code) |code| code.* = 0;
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const process = lockProcessHandle(handle) catch |err| return finishErr(err);
    defer unlockProcessHandle(process);
    if (!advanceWindowsProcess(process, true)) return finish(SA_STD_OK);
    if (process.completion_status != SA_STD_OK) return finish(process.completion_status);
    ready_ptr.* = 1;
    code_ptr.* = process.code;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_try_wait_raw(handle: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    if (out_ready) |ready| ready.* = 0;
    if (out_raw) |raw| raw.* = 0;
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const process = lockProcessHandle(handle) catch |err| return finishErr(err);
    defer unlockProcessHandle(process);
    if (!advanceWindowsProcess(process, true)) return finish(SA_STD_OK);
    if (process.completion_status != SA_STD_OK) return finish(process.completion_status);
    ready_ptr.* = 1;
    raw_ptr.* = @bitCast(process.code);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_kill(handle: u64) i32 {
    const process = lockProcessHandle(handle) catch |err| return finishErr(err);
    defer unlockProcessHandle(process);
    if (process.exited) return finish(SA_STD_OK);
    const child = if (process.child) |*value| value else return finish(SA_STD_ERR_INVALID_HANDLE);
    std.os.windows.TerminateProcess(child.id, 1) catch |err| switch (err) {
        error.PermissionDenied => std.os.windows.WaitForSingleObjectEx(child.id, 0, false) catch |wait_err| switch (wait_err) {
            error.WaitTimeOut => return finish(SA_STD_ERR_ACCESS),
            else => return finishErr(wait_err),
        },
        else => return finishErr(err),
    };
    _ = advanceWindowsProcess(process, false);
    if (process.completion_status != SA_STD_OK) return finish(process.completion_status);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_send_signal(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_process_send_process_group_signal(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_process_kill_process_group(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_pidfd(_: u64, out_pidfd: ?*u64) i32 {
    if (out_pidfd) |pidfd| pidfd.* = 0;
    if (out_pidfd == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return unsupported();
}

pub export fn sa_std_process_into_pidfd(_: u64, out_pidfd: ?*u64) i32 {
    if (out_pidfd) |pidfd| pidfd.* = 0;
    if (out_pidfd == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return unsupported();
}

pub export fn sa_std_pidfd_kill(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_pidfd_send_signal(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_pidfd_wait_raw(_: u64, out_raw: ?*i32) i32 {
    if (out_raw) |raw| raw.* = 0;
    if (out_raw == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return unsupported();
}

pub export fn sa_std_pidfd_wait(_: u64, out_code: ?*u32) i32 {
    if (out_code) |code| code.* = 0;
    if (out_code == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return unsupported();
}

pub export fn sa_std_pidfd_try_wait_raw(_: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    if (out_ready) |ready| ready.* = 0;
    if (out_raw) |raw| raw.* = 0;
    if (out_ready == null or out_raw == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return unsupported();
}

pub export fn sa_std_pidfd_try_wait(_: u64, out_ready: ?*i32, out_code: ?*u32) i32 {
    if (out_ready) |ready| ready.* = 0;
    if (out_code) |code| code.* = 0;
    if (out_ready == null or out_code == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return unsupported();
}

pub export fn sa_std_process_exit_status_code(raw: i32) u32 {
    return @bitCast(raw);
}

pub export fn sa_std_process_exit_status_signal(_: i32) i32 {
    return -1;
}

pub export fn sa_std_process_exit_status_core_dumped(_: i32) u8 {
    return 0;
}

pub export fn sa_std_process_exit_status_stopped_signal(_: i32) i32 {
    return -1;
}

pub export fn sa_std_process_exit_status_continued(_: i32) u8 {
    return 0;
}

pub export fn sa_std_process_read_stdout(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return processReadCaptured(handle, false, out, out_cap, out_read);
}

pub export fn sa_std_process_read_stderr(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return processReadCaptured(handle, true, out, out_cap, out_read);
}

pub export fn sa_std_process_exec_capture(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return processExecCaptureExport(argv_ptr, argv_len, null, out_code, out_stdout, out_stderr);
}

pub export fn sa_std_process_exec_capture_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    if (out_code) |code| code.* = 0;
    if (out_stdout) |handle| handle.* = 0;
    if (out_stderr) |handle| handle.* = 0;
    if (out_code == null or out_stdout == null or out_stderr == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    return processExecCaptureExport(argv_ptr, argv_len, cwd, out_code, out_stdout, out_stderr);
}

pub export fn sa_std_process_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_std_fd_as_raw(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_fd_dup(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fd_dup_raw(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fd_from_raw(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fd_into_raw(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_fd_close_raw(_: i32) i32 {
    return unsupported();
}

pub export fn sa_std_fd_is_terminal(_: u64, _: ?*u8) i32 {
    return unsupported();
}

pub export fn sa_thread_current_id() u64 {
    return unsupportedU64();
}

pub export fn sa_thread_yield_now() i32 {
    return unsupported();
}

pub export fn sa_term_raw_enter(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_term_raw_leave(_: u64) i32 {
    return unsupported();
}

pub export fn sa_term_winsize(_: u64, _: ?*SaTermWinsize) i32 {
    return unsupported();
}

pub export fn sa_term_epoll_create(_: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_term_epoll_ctl(_: u64, _: u32, _: u64, _: u32, _: u64) i32 {
    return unsupported();
}

pub export fn sa_term_epoll_wait(_: u64, _: ?[*]SaTermEpollEvent, _: u64, _: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_term_epoll_close(_: u64) i32 {
    return unsupported();
}

pub export fn sa_io_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_io_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_io_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_io_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return sa_std_read(handle, out, out_cap, out_read);
}

pub export fn sa_io_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    const target = mutBytes(out, len) catch |err| return finishErr(err);
    var offset: usize = 0;
    while (offset < target.len) {
        var count: u64 = 0;
        const status = sa_std_read(handle, target.ptr + offset, target.len - offset, &count);
        if (status != SA_STD_OK) return status;
        if (count == 0) return finish(SA_STD_ERR_TRUNCATED);
        offset += @intCast(count);
    }
    return finish(SA_STD_OK);
}

pub export fn sa_io_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    return sa_std_write(handle, data, len, out_written);
}

pub export fn sa_io_write_all(handle: u64, data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    var offset: usize = 0;
    while (offset < bytes.len) {
        var count: u64 = 0;
        const status = sa_std_write(handle, bytes.ptr + offset, bytes.len - offset, &count);
        if (status != SA_STD_OK) return status;
        if (count == 0) return finish(SA_STD_ERR_IO);
        offset += @intCast(count);
    }
    return finish(SA_STD_OK);
}

pub export fn sa_io_flush(handle: u64) i32 {
    if (handle == SA_STD_STDOUT or handle == SA_STD_STDERR) return finish(SA_STD_OK);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |file| blk: {
            file.sync() catch |err| return finishErr(err);
            break :blk finish(SA_STD_OK);
        },
        .tcp_stream => finish(SA_STD_OK),
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_io_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_io_buffer_data(buffer: ?*const BufferHandle) ?[*]u8 {
    return if (buffer) |value| value.bytes.ptr else null;
}

pub export fn sa_io_buffer_len(buffer: ?*const BufferHandle) u64 {
    return if (buffer) |value| @intCast(value.bytes.len) else 0;
}

pub export fn sa_io_buffer_free(buffer: ?*BufferHandle) i32 {
    const value = buffer orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (value.bytes.len != 0) value.allocator.free(value.bytes);
    value.bytes = &.{};
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_open(path_ptr: ?[*]const u8, path_len: u64, flags: u32) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = saFsOpenFile(path, flags, 0) catch |err| return finishErr(err);
    const handle = registerResource(.{ .file = file }) catch |err| {
        file.close();
        return finishErr(err);
    };
    if (handle > std.math.maxInt(i32)) {
        _ = sa_std_close(handle);
        return finish(SA_STD_ERR_NO_MEMORY);
    }
    _ = finish(SA_STD_OK);
    return @intCast(handle);
}

pub export fn sa_fs_file_create(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_fs_file_open(path_ptr, path_len, 2 | 4 | 8);
}

pub export fn sa_fs_file_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_std_fs_open_options(path_ptr: ?[*]const u8, path_len: u64, flags: u32, create_mode: u32, custom_flags: u32, out_handle: ?*u64) i32 {
    _ = create_mode;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = saFsOpenFile(path, flags, custom_flags) catch |err| return finishErr(err);
    const handle = registerResource(.{ .file = file }) catch |err| {
        file.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_file_from_raw_fd(_: i32, out_handle: ?*u64) i32 {
    if (out_handle) |handle| handle.* = 0;
    return unsupported();
}

pub export fn sa_std_fs_file_read(handle: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    return sa_std_read(handle, out, cap, out_read);
}

pub export fn sa_fs_file_read(handle: u64, out: ?[*]u8, cap: u64) i32 {
    return sa_std_read(handle, out, cap, null);
}

pub export fn sa_std_fs_file_read_at(handle: u64, out: ?[*]u8, cap: u64, offset: u64, out_read: ?*u64) i32 {
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |file| blk: {
            const count = file.pread(buffer, offset) catch |err| return finishErr(err);
            read_ptr.* = @intCast(count);
            break :blk finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_fs_file_read_exact_at(handle: u64, out: ?[*]u8, len: u64, offset: u64) i32 {
    const buffer = mutBytes(out, len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |file| blk: {
            const count = file.preadAll(buffer, offset) catch |err| return finishErr(err);
            if (count != buffer.len) return finish(SA_STD_ERR_TRUNCATED);
            break :blk finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_file_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    return sa_io_read_exact(handle, out, len);
}

pub export fn sa_std_fs_file_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    return sa_std_write(handle, data, len, out_written);
}

pub export fn sa_std_fs_file_write_at(handle: u64, data: ?[*]const u8, len: u64, offset: u64, out_written: ?*u64) i32 {
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    const buffer = constBytes(data, len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |file| blk: {
            const count = file.pwrite(buffer, offset) catch |err| return finishErr(err);
            written_ptr.* = @intCast(count);
            break :blk finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_fs_file_write_all_at(handle: u64, data: ?[*]const u8, len: u64, offset: u64) i32 {
    const buffer = constBytes(data, len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |file| blk: {
            file.pwriteAll(buffer, offset) catch |err| return finishErr(err);
            break :blk finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_file_write(handle: u64, data: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, data, len);
}

pub export fn sa_fs_file_write_all(handle: u64, data: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, data, len);
}

pub export fn sa_fs_file_flush(handle: u64) i32 {
    return sa_io_flush(handle);
}

pub export fn sa_fs_file_sync_data(handle: u64) i32 {
    return sa_io_flush(handle);
}

pub export fn sa_fs_file_sync(handle: u64) i32 {
    return sa_io_flush(handle);
}

pub export fn sa_fs_file_truncate(handle: u64, len: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |file| blk: {
            file.setEndPos(len) catch |err| return finishErr(err);
            break :blk finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_file_seek(handle: u64, whence: u32, offset: i64) i32 {
    return sa_std_fs_file_seek(handle, whence, offset, null);
}

pub export fn sa_std_fs_file_seek(handle: u64, whence: u32, offset: i64, out_pos: ?*u64) i32 {
    if (out_pos) |pos| pos.* = 0;
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |file| blk: {
            switch (whence) {
                0 => if (offset < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT) else file.seekTo(@intCast(offset)) catch |err| return finishErr(err),
                1 => file.seekBy(offset) catch |err| return finishErr(err),
                2 => file.seekFromEnd(offset) catch |err| return finishErr(err),
                else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            }
            const pos = file.getPos() catch |err| return finishErr(err);
            if (out_pos) |target| target.* = pos;
            break :blk finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) Fallible(u64) {
    var handle: u64 = 0;
    const status = sa_std_fs_read_file(path_ptr, path_len, max_bytes, &handle);
    return if (status == SA_STD_OK) ok(u64, handle) else fail(u64, status);
}

pub export fn sa_std_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const bytes = readFileOwned(path, max_bytes) catch |err| return finishErr(err);
    const handle = registerOwnedBytes(bytes) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_to_string(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) Fallible(u64) {
    return sa_fs_read_file(path_ptr, path_len, max_bytes);
}

pub export fn sa_std_fs_read_to_string(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    return sa_std_fs_read_file(path_ptr, path_len, max_bytes, out_handle);
}

pub export fn sa_fs_write_file(path_ptr: ?[*]const u8, path_len: u64, data_ptr: ?[*]const u8, data_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const data = constBytes(data_ptr, data_len) catch |err| return finishErr(err);
    var file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(data) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_buffer_data(handle: u64) ?[*]u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .buffer => |bytes| bytes.ptr,
        else => null,
    };
}

pub export fn sa_fs_read_buffer_len(handle: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .buffer => |bytes| @intCast(bytes.len),
        else => 0,
    };
}

pub export fn sa_fs_read_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_read_file_base64(_: ?[*]const u8, _: u64, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_fs_read_file_base64(_: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_write_file_base64(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_read_dir_json(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const limit = lenAsUsize(max_entries) catch |err| return fail(u64, mapError(err));
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| return fail(u64, mapError(err));
    defer dir.close();

    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    const writer = out.writer();
    writer.writeAll("{\"entries\":[") catch |err| return fail(u64, mapError(err));
    var iterator = dir.iterate();
    var count: usize = 0;
    while (count < limit) {
        const maybe_entry = iterator.next() catch |err| return fail(u64, mapError(err));
        const entry = maybe_entry orelse break;
        if (count != 0) writer.writeByte(',') catch |err| return fail(u64, mapError(err));
        writer.writeAll("{\"name\":") catch |err| return fail(u64, mapError(err));
        std.json.stringify(entry.name, .{}, writer) catch |err| return fail(u64, mapError(err));
        writer.print(",\"isDirectory\":{},\"isFile\":{}}}", .{ entry.kind == .directory, entry.kind == .file }) catch |err| return fail(u64, mapError(err));
        count += 1;
    }
    writer.writeAll("]}") catch |err| return fail(u64, mapError(err));
    const bytes = out.toOwnedSlice() catch |err| return fail(u64, mapError(err));
    const handle = registerOwnedBytes(bytes) catch |err| return fail(u64, mapError(err));
    return ok(u64, handle);
}

pub export fn sa_std_fs_read_dir_json(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_dir_json(path_ptr, path_len, max_entries);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_dir_buffer_data(handle: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(handle);
}

pub export fn sa_fs_dir_buffer_len(handle: u64) u64 {
    return sa_fs_read_buffer_len(handle);
}

pub export fn sa_fs_dir_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_read_dir_entries(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const limit = lenAsUsize(max_entries) catch |err| return fail(u64, mapError(err));
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| return fail(u64, mapError(err));
    defer dir.close();

    var snapshots = std.ArrayList(DirEntrySnapshot).init(std.heap.page_allocator);
    errdefer {
        for (snapshots.items) |entry| if (entry.name.len != 0) std.heap.page_allocator.free(entry.name);
        snapshots.deinit();
    }
    var iterator = dir.iterate();
    while (snapshots.items.len < limit) {
        const maybe_entry = iterator.next() catch |err| return fail(u64, mapError(err));
        const entry = maybe_entry orelse break;
        const name = std.heap.page_allocator.dupe(u8, entry.name) catch |err| return fail(u64, mapError(err));
        snapshots.append(.{ .name = name, .kind = fileKindCode(entry.kind) }) catch |err| {
            std.heap.page_allocator.free(name);
            return fail(u64, mapError(err));
        };
    }
    var entries = DirEntriesHandle{ .entries = snapshots.toOwnedSlice() catch |err| return fail(u64, mapError(err)) };
    const handle = registerResource(.{ .dir_entries = entries }) catch |err| {
        entries.deinit();
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
}

pub export fn sa_std_fs_read_dir_entries(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_dir_entries(path_ptr, path_len, max_entries);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_dir_entries_len(handle: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .dir_entries => |entries| @intCast(entries.entries.len),
        else => 0,
    };
}

pub export fn sa_std_fs_dir_entries_get(handle: u64, index: u64, out_entry_handle: ?*u64) i32 {
    const out = out_entry_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const idx = lenAsUsize(index) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .dir_entries => |entries| blk: {
            if (idx >= entries.entries.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
            const snapshot = entries.entries[idx];
            const name = std.heap.page_allocator.dupe(u8, snapshot.name) catch |err| return finishErr(err);
            const entry_handle = registerResourceLocked(.{ .dir_entry = .{ .name = name, .kind = snapshot.kind } }) catch |err| {
                std.heap.page_allocator.free(name);
                return finishErr(err);
            };
            out.* = entry_handle;
            break :blk finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_dir_entries_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_dir_entry_name_ptr(handle: u64) ?[*]u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .dir_entry => |entry| entry.name.ptr,
        else => null,
    };
}

pub export fn sa_fs_dir_entry_name_len(handle: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .dir_entry => |entry| @intCast(entry.name.len),
        else => 0,
    };
}

pub export fn sa_fs_dir_entry_file_name_ptr(handle: u64) ?[*]u8 {
    return sa_fs_dir_entry_name_ptr(handle);
}

pub export fn sa_fs_dir_entry_file_name_len(handle: u64) u64 {
    return sa_fs_dir_entry_name_len(handle);
}

pub export fn sa_fs_dir_entry_kind(handle: u64) u32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .dir_entry => |entry| entry.kind,
        else => 0,
    };
}

pub export fn sa_fs_dir_entry_ino(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_dir_entry_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_metadata(path_ptr: ?[*]const u8, path_len: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const stat = windowsPathStatNoFollow(path) catch |err| return fail(u64, mapError(err));
    const handle = registerResource(.{ .metadata = .{ .stat = stat } }) catch |err| return fail(u64, mapError(err));
    return ok(u64, handle);
}

pub export fn sa_std_fs_metadata(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const result = sa_fs_metadata(path_ptr, path_len);
    if (result.status != SA_STD_OK) return finish(result.status);
    out.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_metadata_json(path_ptr: ?[*]const u8, path_len: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const stat = windowsPathStatNoFollow(path) catch |err| return fail(u64, mapError(err));
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    out.writer().print(
        "{{\"isFile\":{},\"isDirectory\":{},\"isSymlink\":{},\"len\":{d},\"modifiedMs\":{d},\"createdMs\":{d},\"accessedMs\":{d}}}",
        .{ stat.kind == .file, stat.kind == .directory, stat.kind == .sym_link, stat.size, nsToMs(stat.mtime), nsToMs(stat.ctime), nsToMs(stat.atime) },
    ) catch |err| return fail(u64, mapError(err));
    const bytes = out.toOwnedSlice() catch |err| return fail(u64, mapError(err));
    const handle = registerOwnedBytes(bytes) catch |err| return fail(u64, mapError(err));
    return ok(u64, handle);
}

pub export fn sa_std_fs_metadata_json(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const result = sa_fs_metadata_json(path_ptr, path_len);
    if (result.status != SA_STD_OK) return finish(result.status);
    out.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_metadata_is_file(handle: u64) u8 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return if (stat.kind == .file) 1 else 0;
}

pub export fn sa_fs_metadata_is_directory(handle: u64) u8 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return if (stat.kind == .directory) 1 else 0;
}

pub export fn sa_fs_metadata_is_symlink(handle: u64) u8 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return if (stat.kind == .sym_link) 1 else 0;
}

pub export fn sa_fs_metadata_is_block_device(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_char_device(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_fifo(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_socket(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_modified_ms(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsToMs(stat.mtime);
}

pub export fn sa_fs_metadata_created_ms(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsToMs(stat.ctime);
}

pub export fn sa_fs_metadata_accessed_ms(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsToMs(stat.atime);
}

pub export fn sa_fs_metadata_changed_ms(handle: u64) i64 {
    return sa_fs_metadata_created_ms(handle);
}

pub export fn sa_fs_metadata_len(handle: u64) u64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return stat.size;
}

pub export fn sa_fs_metadata_mode(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_uid(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_gid(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_ino(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_dev(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_nlink(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_rdev(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_blksize(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_blocks(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_dev(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_ino(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_mode(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_st_nlink(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_uid(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_st_gid(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_st_rdev(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_size(handle: u64) u64 {
    return sa_fs_metadata_len(handle);
}

pub export fn sa_fs_metadata_st_atime(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsToSec(stat.atime);
}

pub export fn sa_fs_metadata_st_atime_nsec(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsRemainder(stat.atime);
}

pub export fn sa_fs_metadata_st_mtime(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsToSec(stat.mtime);
}

pub export fn sa_fs_metadata_st_mtime_nsec(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsRemainder(stat.mtime);
}

pub export fn sa_fs_metadata_st_ctime(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsToSec(stat.ctime);
}

pub export fn sa_fs_metadata_st_ctime_nsec(handle: u64) i64 {
    const stat = metadataStat(handle) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    _ = finish(SA_STD_OK);
    return nsRemainder(stat.ctime);
}

pub export fn sa_fs_metadata_st_blksize(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_blocks(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_free(handle: u64) Fallible(i32) {
    const status = sa_std_close(handle);
    return if (status == SA_STD_OK) ok(i32, 0) else fail(i32, status);
}

pub export fn sa_std_fs_metadata_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_std_fs_canonicalize(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const canonical = std.fs.cwd().realpathAlloc(std.heap.page_allocator, path) catch |err| return finishErr(err);
    const handle = registerOwnedBytes(canonical) catch |err| return finishErr(err);
    out.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_file(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteFile(path) catch |err| switch (err) {
        error.IsDir => {
            const stat = windowsPathStatNoFollow(path) catch |stat_err| return finishErr(stat_err);
            if (stat.kind != .sym_link) return finishErr(err);
            std.fs.cwd().deleteDir(path) catch |delete_err| return finishErr(delete_err);
        },
        else => return finishErr(err),
    };
    return finish(SA_STD_OK);
}

pub export fn sa_fs_rename(from_ptr: ?[*]const u8, from_len: u64, to_ptr: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_ptr, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_ptr, to_len) catch |err| return finishErr(err);
    std.fs.cwd().rename(from, to) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_make_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().makePath(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_make_dir_mode(_: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_create_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().makeDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_create_dir_mode(_: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_remove_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_dir_all(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteTree(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_path(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteTree(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_copy_file(from_ptr: ?[*]const u8, from_len: u64, to_ptr: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_ptr, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_ptr, to_len) catch |err| return finishErr(err);
    std.fs.cwd().copyFile(from, std.fs.cwd(), to, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_set_permissions(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var file = windowsOpenPathForAttributeUpdate(path) catch |err| return finishErr(err);
    defer file.close();
    const metadata = file.metadata() catch |err| return finishErr(err);
    var permissions = metadata.permissions();
    permissions.setReadOnly(mode & 0o222 == 0);
    file.setPermissions(permissions) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_set_times_ms(path_ptr: ?[*]const u8, path_len: u64, accessed_ms: i64, modified_ms: i64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const atime_ns = windowsTimestampNs(accessed_ms) catch |err| return finishErr(err);
    const mtime_ns = windowsTimestampNs(modified_ms) catch |err| return finishErr(err);
    var file = windowsOpenPathForAttributeUpdate(path) catch |err| return finishErr(err);
    defer file.close();
    file.updateTimes(atime_ns, mtime_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_hard_link(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_symlink(target_ptr: ?[*]const u8, target_len: u64, link_ptr: ?[*]const u8, link_len: u64) i32 {
    const target = pathBytes(target_ptr, target_len) catch |err| return finishErr(err);
    const link = pathBytes(link_ptr, link_len) catch |err| return finishErr(err);
    const is_directory = symlinkTargetIsDirectory(target, link) catch |err| return finishErr(err);
    std.fs.cwd().symLink(target, link, .{ .is_directory = is_directory }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_chown(_: ?[*]const u8, _: u64, _: u32, _: u32, _: u32, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_lchown(_: ?[*]const u8, _: u64, _: u32, _: u32, _: u32, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_fchown(_: u64, _: u32, _: u32, _: u32, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_chroot(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_mkfifo(_: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_fs_read_link(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var stack_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const target = std.fs.cwd().readLink(path, &stack_buffer) catch |err| return finishErr(err);
    const handle = duplicateAndRegister(target) catch |err| return finishErr(err);
    out.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_net_tcp_connect(_: ?[*]const u8, _: u64, _: u32) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_net_to_socket_addr_first(_: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_read(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_read(_: u64, _: ?[*]u8, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_net_tcp_stream_peek(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_peek(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_write(_: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_write(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_write_all(_: u64, _: ?[*]const u8, _: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_net_tcp_stream_flush(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_peer_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_peer_addr(_: u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_shutdown(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_read_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_write_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_nodelay(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_close(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_net_tcp_listener_bind(_: ?[*]const u8, _: u64, _: u16) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_net_tcp_listener_accept(_: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_net_tcp_listener_local_addr(_: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_net_tcp_listener_close(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_std_net_tcp_stream_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_nodelay(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_quickack(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_quickack(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_deferaccept(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_deferaccept(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_keepalive(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_keepalive_params(_: u64, _: u32, _: u32, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_set_reuseaddr(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_set_reuseport(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_read_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_write_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_read_timeout(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_write_timeout(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_nodelay(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_ttl(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_take_error(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_ttl(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_take_error(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_bind(_: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_peer_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_connect(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_read_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_write_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_broadcast(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_multicast_loop_v4(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_multicast_ttl_v4(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_join_multicast_v4(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_leave_multicast_v4(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_join_multicast_v6(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_leave_multicast_v6(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_broadcast(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_read_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_write_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_read_timeout(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_write_timeout(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_broadcast(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_multicast_loop_v4(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_multicast_ttl_v4(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_multicast_loop_v4(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_multicast_ttl_v4(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_join_multicast_v4(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_leave_multicast_v4(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_join_multicast_v6(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_leave_multicast_v6(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_ttl(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_take_error(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_send(_: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_recv(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_peek(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_send_to(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_recv_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_peek_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_bind(_: ?[*]const u8, _: u64, _: u16) i32 {
    return unsupported();
}

pub export fn sa_net_udp_connect(_: u64, _: ?[*]const u8, _: u64, _: u16) i32 {
    return unsupported();
}

pub export fn sa_net_udp_local_addr(_: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_send(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_recv(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_peek(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_send_to(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: u16) i32 {
    return unsupported();
}

pub export fn sa_net_udp_recv_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_peek_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_close(_: u64) i32 {
    return unsupported();
}

pub export fn sa_net_addr_host(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_net_addr_host_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_net_addr_port(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_net_addr_family(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_net_addr_scope_id(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_std_net_addr_format(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_addr_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_net_ipv4_parse_ascii(_: ?[*]const u8, _: u64, _: ?[*]u8) i32 {
    return unsupported();
}

pub export fn sa_net_socket_addr_v4_parse_ascii(_: ?[*]const u8, _: u64, _: ?[*]u8) i32 {
    return unsupported();
}

pub export fn sa_net_ipv6_parse_ascii(_: ?[*]const u8, _: u64, _: ?[*]u8) i32 {
    return unsupported();
}

pub export fn sa_net_socket_addr_v6_parse_ascii(_: ?[*]const u8, _: u64, _: ?[*]u8) i32 {
    return unsupported();
}

pub export fn sa_net_ipv4_format_ascii(_: ?[*]const u8, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_ipv6_format_ascii(_: ?[*]const u8, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_socket_addr_v4_format_ascii(_: ?[*]const u8, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_socket_addr_v6_format_ascii(_: ?[*]const u8, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_i64(_: i64, _: u32) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_i64_into(_: i64, _: u32, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_test_debug_i64(_: ?[*]const u8, _: u64, _: i64) void {}

pub export fn sa_assert_eq_i64(_: i64, _: i64, _: i32) void {}

pub export fn sa_assert_eq_i64_at(_: i64, _: i64, _: i32, _: ?[*]const u8, _: u64, _: u32, _: u32) void {}

pub export fn sa_fmt_u64(_: u64, _: u32) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_u64_into(_: u64, _: u32, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_f64(_: f64, _: u32) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_f64_into(_: f64, _: u32, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_bool(_: bool) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_bool_into(_: bool, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_bytes(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_bytes_into(_: ?[*]const u8, _: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_env_get(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_env_current_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_set_current_dir(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_env_temp_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_current_exe() u64 {
    return unsupportedU64();
}

pub export fn sa_env_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_args_json() u64 {
    return unsupportedU64();
}

pub export fn sa_env_vars_json() u64 {
    return unsupportedU64();
}

pub export fn sa_env_split_paths_json(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_env_join_paths_json(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_data_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_config_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_state_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_cache_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_data_dirs() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_config_dirs() u64 {
    return unsupportedU64();
}

pub export fn sa_env_has(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_env_set_var(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_env_remove_var(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_env_buffer_data(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_env_buffer_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_env_buffer_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_string_concat(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_str_is_ascii(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_str_eq_ignore_ascii_case(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_char_count(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_str_utf8_validate(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_char_at(_: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_char_at_byte(_: ?[*]const u8, _: u64, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_lossy_next(_: ?[*]const u8, _: u64, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_char_range_at(_: ?[*]const u8, _: u64, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_str_trim_ascii_start_index(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_str_trim_ascii_end_len(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_buffer_data(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_fmt_buffer_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_buffer_write_to(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_buffer_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_print_bytes(_: ?[*]const u8, _: u64) void {}

pub export fn sa_std_net_tcp_listen(_: ?[*]const u8, _: u64, _: u32, _: ?*u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_accept(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_connect(_: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listen(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_addr_from_abstract_name(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_addr_from_pathname(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listen_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_accept(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_accept_addr(_: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_pair(_: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listener_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listener_try_clone(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listener_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_try_clone(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_peer_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_set_passcred(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_passcred(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_set_mark(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_peer_cred(_: u64, _: ?*i32, _: ?*u32, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_unbound(_: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_bind(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_bind_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_pair(_: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_connect(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_connect_addr(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_try_clone(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_peer_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_set_passcred(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_passcred(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_set_mark(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_shutdown(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_send_to(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_send_to_addr(_: u64, _: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_recv_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_peek_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_connect(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_connect_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_unix_addr_kind(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_net_unix_addr_is_unnamed(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_net_unix_addr_path_ptr(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_net_unix_addr_path_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_net_unix_addr_abstract_ptr(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_net_unix_addr_abstract_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_net_unix_addr_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_std_net_ja3_hash(_: ?[*]const u8, _: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_sha256_hex(_: ?[*]const u8, _: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_ja4_hash12(_: ?[*]const u8, _: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

test "windows fs path APIs reject invalid paths and clear failure output" {
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_remove_file(null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_rename(null, 0, null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_make_dir(null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_create_dir(null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_remove_dir(null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_remove_dir_all(null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_copy_file(null, 0, null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_set_permissions(null, 0, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_set_times_ms(null, 0, 0, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_symlink(null, 0, null, 0));

    var handle: u64 = 123;
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_fs_read_link(null, 0, &handle));
    try std.testing.expectEqual(@as(u64, 0), handle);
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_last_error());
}

test "windows fs path lifecycle" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);
    const nested = try std.fs.path.join(allocator, &.{ root, "parent", "nested" });
    defer allocator.free(nested);
    const empty_dir = try std.fs.path.join(allocator, &.{ root, "empty" });
    defer allocator.free(empty_dir);
    const source = try std.fs.path.join(allocator, &.{ nested, "source.txt" });
    defer allocator.free(source);
    const copied = try std.fs.path.join(allocator, &.{ nested, "copied.txt" });
    defer allocator.free(copied);
    const renamed = try std.fs.path.join(allocator, &.{ nested, "renamed.txt" });
    defer allocator.free(renamed);

    try std.testing.expectEqual(SA_STD_OK, sa_fs_make_dir(nested.ptr, @intCast(nested.len)));
    try std.testing.expectEqual(SA_STD_OK, sa_fs_create_dir(empty_dir.ptr, @intCast(empty_dir.len)));
    try std.testing.expectEqual(SA_STD_OK, sa_fs_remove_dir(empty_dir.ptr, @intCast(empty_dir.len)));

    const contents = "portable windows fs";
    try std.testing.expectEqual(SA_STD_OK, sa_fs_write_file(source.ptr, @intCast(source.len), contents.ptr, contents.len));
    try std.testing.expectEqual(SA_STD_OK, sa_fs_copy_file(source.ptr, @intCast(source.len), copied.ptr, @intCast(copied.len)));
    try std.testing.expectEqual(SA_STD_OK, sa_fs_rename(copied.ptr, @intCast(copied.len), renamed.ptr, @intCast(renamed.len)));
    const timestamp = std.time.milliTimestamp() - 10_000;
    try std.testing.expectEqual(SA_STD_OK, sa_fs_set_times_ms(renamed.ptr, @intCast(renamed.len), timestamp, timestamp));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_fs_set_times_ms(renamed.ptr, @intCast(renamed.len), std.math.maxInt(i64), timestamp));
    try std.testing.expectEqual(SA_STD_OK, sa_fs_set_permissions(renamed.ptr, @intCast(renamed.len), 0o444));
    try std.testing.expectEqual(SA_STD_OK, sa_fs_set_permissions(renamed.ptr, @intCast(renamed.len), 0o666));

    const copied_contents = try std.fs.cwd().readFileAlloc(allocator, renamed, contents.len);
    defer allocator.free(copied_contents);
    try std.testing.expectEqualStrings(contents, copied_contents);

    try std.testing.expectEqual(SA_STD_OK, sa_fs_remove_file(source.ptr, @intCast(source.len)));
    try std.testing.expectEqual(SA_STD_OK, sa_fs_remove_file(renamed.ptr, @intCast(renamed.len)));
    const parent = std.fs.path.dirname(nested).?;
    try std.testing.expectEqual(SA_STD_OK, sa_fs_remove_dir_all(parent.ptr, @intCast(parent.len)));
}

test "windows symlink metadata and readlink preserve the link" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);
    const target = try std.fs.path.join(allocator, &.{ root, "target-dir" });
    defer allocator.free(target);
    const link = try std.fs.path.join(allocator, &.{ root, "dir-link" });
    defer allocator.free(link);

    try std.testing.expectEqual(SA_STD_OK, sa_fs_create_dir(target.ptr, @intCast(target.len)));
    const relative_target = "target-dir";
    const link_status = sa_fs_symlink(relative_target.ptr, relative_target.len, link.ptr, @intCast(link.len));
    if (link_status == SA_STD_ERR_ACCESS or link_status == SA_STD_ERR_UNSUPPORTED) return error.SkipZigTest;
    try std.testing.expectEqual(SA_STD_OK, link_status);
    defer _ = sa_fs_remove_path(link.ptr, @intCast(link.len));

    const metadata = sa_fs_metadata(link.ptr, @intCast(link.len));
    try std.testing.expectEqual(SA_STD_OK, metadata.status);
    defer _ = sa_std_fs_metadata_free(metadata.value);
    try std.testing.expectEqual(@as(u8, 1), sa_fs_metadata_is_symlink(metadata.value));

    var target_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_read_link(link.ptr, @intCast(link.len), &target_handle));
    defer _ = sa_fs_read_buffer_free(target_handle);
    const target_ptr = sa_fs_read_buffer_data(target_handle) orelse return error.TestUnexpectedResult;
    const target_len = sa_fs_read_buffer_len(target_handle);
    try std.testing.expectEqualStrings(relative_target, target_ptr[0..@intCast(target_len)]);
}

test "windows process argv is owned and rejects invalid entries" {
    try std.testing.expectError(error.InvalidArgument, initProcessHandle(null, 0, .inherit));

    const empty = [_]SaProcessArgv{.{ .data = "".ptr, .len = 0 }};
    try std.testing.expectError(error.InvalidArgument, initProcessHandle(&empty, empty.len, .inherit));

    const executable = "tool";
    const bad_arg = [_]u8{ 'a', 0, 'b' };
    const invalid = [_]SaProcessArgv{
        .{ .data = executable.ptr, .len = executable.len },
        .{ .data = bad_arg[0..].ptr, .len = bad_arg.len },
    };
    try std.testing.expectError(error.InvalidArgument, initProcessHandle(&invalid, invalid.len, .inherit));

    var mutable_executable = [_]u8{ 't', 'o', 'o', 'l' };
    const valid = [_]SaProcessArgv{.{ .data = mutable_executable[0..].ptr, .len = mutable_executable.len }};
    var process = try initProcessHandle(&valid, valid.len, .inherit);
    defer process.deinit();
    mutable_executable[0] = 'x';
    try std.testing.expectEqualStrings("tool", process.argv[0]);
}

test "windows process spawn failure leaves no live child handle" {
    const missing = "Z:\\sci-missing-7f4d2c89\\never-exists.exe";
    const argv = [_]SaProcessArgv{.{ .data = missing.ptr, .len = missing.len }};
    if (spawnWindowsProcess(&argv, argv.len, null, .inherit)) |spawned| {
        defer _ = sa_std_process_close(spawned.process);
        return error.TestUnexpectedResult;
    } else |_| {}
}

test "windows process unsupported extensions clear handles" {
    var handle: u64 = 123;
    try std.testing.expectEqual(
        SA_STD_ERR_UNSUPPORTED,
        sa_std_process_spawn_command_ext(null, 0, null, 0, 0, null, 0, 1, 0, 0, 0, &handle),
    );
    try std.testing.expectEqual(@as(u64, 0), handle);

    var process: u64 = 123;
    var stdout_handle: u64 = 456;
    var stderr_handle: u64 = 789;
    try std.testing.expectEqual(
        SA_STD_ERR_UNSUPPORTED,
        sa_std_process_spawn_stream_command_ext(null, 0, null, 0, 0, null, 0, 0, 0, 0, 1, &process, &stdout_handle, &stderr_handle),
    );
    try std.testing.expectEqual(@as(u64, 0), process);
    try std.testing.expectEqual(@as(u64, 0), stdout_handle);
    try std.testing.expectEqual(@as(u64, 0), stderr_handle);
}

test "windows process and pidfd failures clear wait outputs" {
    var ready: i32 = 123;
    var raw: i32 = 456;
    var code: u32 = 789;

    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_process_wait(0, &code));
    try std.testing.expectEqual(@as(u32, 0), code);
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_process_wait_raw(0, &raw));
    try std.testing.expectEqual(@as(i32, 0), raw);
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_process_try_wait(0, &ready, &code));
    try std.testing.expectEqual(@as(i32, 0), ready);
    try std.testing.expectEqual(@as(u32, 0), code);
    ready = 123;
    raw = 456;
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_process_try_wait_raw(0, &ready, &raw));
    try std.testing.expectEqual(@as(i32, 0), ready);
    try std.testing.expectEqual(@as(i32, 0), raw);

    var pidfd: u64 = 123;
    try std.testing.expectEqual(SA_STD_ERR_UNSUPPORTED, sa_std_process_pidfd(0, &pidfd));
    try std.testing.expectEqual(@as(u64, 0), pidfd);
    pidfd = 123;
    try std.testing.expectEqual(SA_STD_ERR_UNSUPPORTED, sa_std_process_into_pidfd(0, &pidfd));
    try std.testing.expectEqual(@as(u64, 0), pidfd);
    raw = 456;
    try std.testing.expectEqual(SA_STD_ERR_UNSUPPORTED, sa_std_pidfd_wait_raw(0, &raw));
    try std.testing.expectEqual(@as(i32, 0), raw);
    code = 789;
    try std.testing.expectEqual(SA_STD_ERR_UNSUPPORTED, sa_std_pidfd_wait(0, &code));
    try std.testing.expectEqual(@as(u32, 0), code);
    ready = 123;
    raw = 456;
    try std.testing.expectEqual(SA_STD_ERR_UNSUPPORTED, sa_std_pidfd_try_wait_raw(0, &ready, &raw));
    try std.testing.expectEqual(@as(i32, 0), ready);
    try std.testing.expectEqual(@as(i32, 0), raw);
    ready = 123;
    code = 789;
    try std.testing.expectEqual(SA_STD_ERR_UNSUPPORTED, sa_std_pidfd_try_wait(0, &ready, &code));
    try std.testing.expectEqual(@as(i32, 0), ready);
    try std.testing.expectEqual(@as(u32, 0), code);
}

test "windows raw process status preserves the full dword" {
    const expected: u32 = 0xfedc_ba98;
    const raw: i32 = @bitCast(expected);
    try std.testing.expectEqual(expected, sa_std_process_exit_status_code(raw));
}

test "windows process capture preserves completion failures" {
    const process = try std.heap.page_allocator.create(ProcessHandle);
    process.* = .{
        .mode = .capture,
        .exited = true,
        .completion_status = SA_STD_ERR_TRUNCATED,
    };
    const handle = registerResource(.{ .process = process }) catch |err| {
        process.deinit();
        std.heap.page_allocator.destroy(process);
        return err;
    };
    defer _ = sa_std_close(handle);

    var read: u64 = 123;
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_process_read_stdout(handle, null, 0, &read));
    try std.testing.expectEqual(@as(u64, 0), read);
}
