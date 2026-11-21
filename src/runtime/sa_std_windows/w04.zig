const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const FallibleU64 = @import("w01.zig").FallibleU64;
const GetProcessId = @import("w02.zig").GetProcessId;
const JsonNode = @import("w01.zig").JsonNode;
const ProcessMode = @import("w01.zig").ProcessMode;
const ProcessResource = @import("w01.zig").ProcessResource;
const SA_JSON_KIND_ARRAY = @import("w01.zig").SA_JSON_KIND_ARRAY;
const SA_JSON_KIND_BOOL = @import("w01.zig").SA_JSON_KIND_BOOL;
const SA_JSON_KIND_FLOAT = @import("w01.zig").SA_JSON_KIND_FLOAT;
const SA_JSON_KIND_INTEGER = @import("w01.zig").SA_JSON_KIND_INTEGER;
const SA_JSON_KIND_NULL = @import("w01.zig").SA_JSON_KIND_NULL;
const SA_JSON_KIND_NUMBER_STRING = @import("w01.zig").SA_JSON_KIND_NUMBER_STRING;
const SA_JSON_KIND_OBJECT = @import("w01.zig").SA_JSON_KIND_OBJECT;
const SA_JSON_KIND_STRING = @import("w01.zig").SA_JSON_KIND_STRING;
const SA_STD_ABI_VERSION = @import("w01.zig").SA_STD_ABI_VERSION;
const SA_STD_ERR_ACCESS = @import("w01.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("w01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NET = @import("w01.zig").SA_STD_ERR_NET;
const SA_STD_ERR_NOT_FOUND = @import("w01.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("w01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_TRUNCATED = @import("w01.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const SA_STD_STDERR = @import("w01.zig").SA_STD_STDERR;
const SA_STD_STDIN = @import("w01.zig").SA_STD_STDIN;
const SA_STD_STDOUT = @import("w01.zig").SA_STD_STDOUT;
const SaProcessArgv = @import("w01.zig").SaProcessArgv;
const allocCompatArgv = @import("w02.zig").allocCompatArgv;
const argvFromEntries = @import("w02.zig").argvFromEntries;
const commandInterpreterPathAlloc = @import("w02.zig").commandInterpreterPathAlloc;
const constBytes = @import("w02.zig").constBytes;
const dirEntriesSlotLocked = @import("w03.zig").dirEntriesSlotLocked;
const dirEntrySlotLocked = @import("w03.zig").dirEntrySlotLocked;
const dir_entries_free_slots = @import("w02.zig").dir_entries_free_slots;
const dir_entries_slots = @import("w02.zig").dir_entries_slots;
const dir_entry_free_slots = @import("w02.zig").dir_entry_free_slots;
const dir_entry_slots = @import("w02.zig").dir_entry_slots;
const dir_mutex = @import("w02.zig").dir_mutex;
const envKeyBytes = @import("w02.zig").envKeyBytes;
const failU64 = @import("w02.zig").failU64;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const gethostname = @import("w01.zig").gethostname;
const last_error = @import("w01.zig").last_error;
const lenAsUsize = @import("w02.zig").lenAsUsize;
const mapError = @import("w02.zig").mapError;
const metadataSlotLocked = @import("w03.zig").metadataSlotLocked;
const metadata_free_slots = @import("w02.zig").metadata_free_slots;
const metadata_mutex = @import("w02.zig").metadata_mutex;
const metadata_slots = @import("w02.zig").metadata_slots;
const okU64 = @import("w02.zig").okU64;
const openOwnedByteBuffer = @import("w02.zig").openOwnedByteBuffer;
const pathBytes = @import("w02.zig").pathBytes;
const processArgsJsonAlloc = @import("w02.zig").processArgsJsonAlloc;
const processSlotLocked = @import("w03.zig").processSlotLocked;
const process_free_slots = @import("w02.zig").process_free_slots;
const process_mutex = @import("w02.zig").process_mutex;
const process_slots = @import("w02.zig").process_slots;
const registerProcess = @import("w03.zig").registerProcess;
const registerStream = @import("w03.zig").registerStream;
const setEnvValue = @import("w02.zig").setEnvValue;
const spawnDebugLogFmt = @import("w01.zig").spawnDebugLogFmt;
const streamSlotLocked = @import("w03.zig").streamSlotLocked;
const stream_free_slots = @import("w02.zig").stream_free_slots;
const stream_mutex = @import("w02.zig").stream_mutex;
const stream_slots = @import("w02.zig").stream_slots;
const tempPathAlloc = @import("w02.zig").tempPathAlloc;
const writeFormattedInto = @import("w02.zig").writeFormattedInto;
const wsaError = @import("w01.zig").wsaError;
const wsaStartup = @import("w01.zig").wsaStartup;

pub fn jsonKind(value: std.json.Value) u32 {
    return switch (value) {
        .null => SA_JSON_KIND_NULL,
        .bool => SA_JSON_KIND_BOOL,
        .integer => SA_JSON_KIND_INTEGER,
        .float => SA_JSON_KIND_FLOAT,
        .number_string => SA_JSON_KIND_NUMBER_STRING,
        .string => SA_JSON_KIND_STRING,
        .array => SA_JSON_KIND_ARRAY,
        .object => SA_JSON_KIND_OBJECT,
    };
}

pub fn jsonText(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text_value| text_value,
        .number_string => |text_value| text_value,
        else => null,
    };
}

pub fn jsonAsF64(value: std.json.Value) !f64 {
    return switch (value) {
        .integer => |inner| @as(f64, @floatFromInt(inner)),
        .float => |inner| if (std.math.isFinite(inner)) inner else error.InvalidArgument,
        .number_string => |text_value| blk: {
            const parsed = std.fmt.parseFloat(f64, text_value) catch return error.InvalidArgument;
            if (!std.math.isFinite(parsed)) return error.InvalidArgument;
            break :blk parsed;
        },
        else => error.InvalidArgument,
    };
}

pub fn jsonAsI64(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |inner| inner,
        .float => |inner| blk: {
            if (!std.math.isFinite(inner) or @round(inner) != inner) return error.InvalidArgument;
            if (inner > @as(f64, @floatFromInt(std.math.maxInt(i64))) or inner < @as(f64, @floatFromInt(std.math.minInt(i64)))) return error.InvalidArgument;
            break :blk @as(i64, @intFromFloat(inner));
        },
        .number_string => |text_value| std.fmt.parseInt(i64, text_value, 10) catch return error.InvalidArgument,
        else => error.InvalidArgument,
    };
}

pub fn jsonAsBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |inner| inner,
        else => error.InvalidArgument,
    };
}

pub fn jsonObjectValue(node: JsonNode, key: []const u8) !std.json.Value {
    return switch (node.value) {
        .object => |object| object.get(key) orelse error.FileNotFound,
        else => error.InvalidArgument,
    };
}

pub fn spawnProcessCwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, mode: ProcessMode, cwd: ?[]const u8, arg0_override: ?[]const u8) !u64 {
    const argv = try argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len);
    defer std.heap.page_allocator.free(argv);
    var compat = try allocCompatArgv(std.heap.page_allocator, argv, arg0_override);
    defer compat.deinit(std.heap.page_allocator);

    var child = sio.Child.init(compat.argv, std.heap.page_allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = if (mode == .inherit) .Inherit else .Pipe;
    child.stderr_behavior = if (mode == .inherit) .Inherit else .Pipe;
    child.cwd = cwd;
    spawnDebugLogFmt("spawnProcessCwd: attempting spawn argv_len={d}", .{compat.argv.len});
    for (compat.argv) |a| spawnDebugLogFmt("  argv: {s}", .{a});
    child.spawn() catch |err| {
        spawnDebugLogFmt("spawnProcessCwd: spawn FAILED err={s}", .{@errorName(err)});
        return err;
    };
    spawnDebugLogFmt("spawnProcessCwd: spawn succeeded", .{});
    errdefer _ = child.kill() catch {};

    const child_inner = child.inner orelse return error.ChildNotSpawned;
    const child_pid = child_inner.id orelse return error.ChildNotSpawned;
    const resource = try std.heap.page_allocator.create(ProcessResource);
    errdefer std.heap.page_allocator.destroy(resource);
    resource.* = .{
        .child = child,
        .pid = GetProcessId(child_pid),
        .mode = mode,
    };
    return registerProcess(resource);
}

pub fn spawnProcess(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, mode: ProcessMode) !u64 {
    return spawnProcessCwd(argv_ptr, argv_len, mode, null, null);
}

pub fn spawnStreamProcessCwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd: ?[]const u8, arg0_override: ?[]const u8, out_process: *u64, out_stdout: *u64, out_stderr: *u64) !void {
    const process = try spawnProcessCwd(argv_ptr, argv_len, .stream, cwd, arg0_override);
    errdefer _ = closeProcessHandle(process);

    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = processSlotLocked(process) orelse {
        process_mutex.unlock();
        return error.InvalidHandle;
    };
    const resource = process_slots.items[idx].?;
    const stdout_file = resource.child.stdout orelse {
        process_mutex.unlock();
        return error.InvalidHandle;
    };
    const stderr_file = resource.child.stderr orelse {
        process_mutex.unlock();
        return error.InvalidHandle;
    };
    resource.child.stdout = null;
    resource.child.stderr = null;
    process_mutex.unlock();

    const stdout_handle = registerStream(stdout_file) catch |err| {
        stdout_file.close();
        stderr_file.close();
        return err;
    };
    errdefer _ = closeStreamHandle(stdout_handle);
    const stderr_handle = registerStream(stderr_file) catch |err| {
        stderr_file.close();
        return err;
    };
    out_process.* = process;
    out_stdout.* = stdout_handle;
    out_stderr.* = stderr_handle;
}

pub fn spawnProcessNoArgs(mode: ProcessMode, compat_first: []const u8, compat_rest: []const u8) !u64 {
    const program = try commandInterpreterPathAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(program);
    const argv = &[_][]const u8{ program, "/d", "/c", compat_first, compat_rest };
    return spawnProcessCwd(@as(?[*]const SaProcessArgv, @ptrCast(argv.ptr)), argv.len, mode, null, null);
}

pub fn spawnStreamProcess(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: *u64, out_stdout: *u64, out_stderr: *u64) !void {
    return spawnStreamProcessCwd(argv_ptr, argv_len, null, null, out_process, out_stdout, out_stderr);
}

pub fn closeProcessHandle(handle: u64) i32 {
    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = processSlotLocked(handle) orelse {
        process_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const resource = process_slots.items[idx].?;
    process_slots.items[idx] = null;
    process_free_slots.append(idx) catch {
        process_mutex.unlock();
        resource.close();
        std.heap.page_allocator.destroy(resource);
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    process_mutex.unlock();
    resource.close();
    std.heap.page_allocator.destroy(resource);
    return finish(SA_STD_OK);
}

pub fn closeStreamHandle(handle: u64) i32 {
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = stream_slots.items[idx].?;
    resource.close();
    stream_slots.items[idx] = null;
    stream_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub fn closeMetadataHandle(handle: u64) i32 {
    while (!metadata_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer metadata_mutex.unlock();
    const idx = metadataSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    metadata_slots.items[idx] = null;
    metadata_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub fn closeDirEntriesHandle(handle: u64) i32 {
    while (!dir_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dir_mutex.unlock();
    const idx = dirEntriesSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = dir_entries_slots.items[idx].?;
    resource.close();
    dir_entries_slots.items[idx] = null;
    dir_entries_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub fn closeDirEntryHandle(handle: u64) i32 {
    while (!dir_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dir_mutex.unlock();
    const idx = dirEntrySlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = dir_entry_slots.items[idx].?;
    resource.close();
    dir_entry_slots.items[idx] = null;
    dir_entry_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub fn statusName(code: i32) []const u8 {
    return switch (code) {
        SA_STD_OK => "OK",
        SA_STD_ERR_INVALID_ARGUMENT => "INVALID_ARGUMENT",
        SA_STD_ERR_INVALID_HANDLE => "INVALID_HANDLE",
        SA_STD_ERR_NOT_FOUND => "NOT_FOUND",
        SA_STD_ERR_ACCESS => "ACCESS",
        SA_STD_ERR_NO_MEMORY => "NO_MEMORY",
        SA_STD_ERR_IO => "IO",
        SA_STD_ERR_NET => "NET",
        SA_STD_ERR_UNSUPPORTED => "UNSUPPORTED",
        SA_STD_ERR_TRUNCATED => "TRUNCATED",
        else => "UNKNOWN",
    };
}

pub export fn sa_std_version() u32 {
    return SA_STD_ABI_VERSION;
}

// --- Checked i64 arithmetic (sa_std/num.sai; mirror of sa_std.zig) -------
// Exact-result arithmetic; overflow traps (stderr diagnostic + process
// abort, PANIC_ARITH_OVERFLOW=9001 in the SA-level mirror) instead of
// wrapping. Pure arithmetic, so the Windows root implements it too
// rather than listing it as unsupported.
pub fn saNumCheckedTrap(comptime symbol: []const u8, a: i64, b: i64) noreturn {
    std.debug.print("[sa-std] {s}({d}, {d}): i64 overflow, trapping (PANIC_ARITH_OVERFLOW=9001)\n", .{ symbol, a, b });
    std.process.abort();
}

pub export fn sa_num_add_checked(a: i64, b: i64) i64 {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_add_checked", a, b);
    return result[0];
}

pub export fn sa_num_sub_checked(a: i64, b: i64) i64 {
    const result = @subWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_sub_checked", a, b);
    return result[0];
}

pub export fn sa_num_mul_checked(a: i64, b: i64) i64 {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_mul_checked", a, b);
    return result[0];
}

pub export fn sa_std_last_error() i32 {
    return last_error;
}

pub export fn sa_std_net_error_code_from_status(status: i32) i32 {
    return switch (status) {
        SA_STD_OK => 0,
        SA_STD_ERR_INVALID_ARGUMENT => 10,
        SA_STD_ERR_INVALID_HANDLE => 11,
        SA_STD_ERR_NOT_FOUND => 12,
        SA_STD_ERR_ACCESS => 8,
        SA_STD_ERR_NO_MEMORY => 13,
        SA_STD_ERR_IO => 14,
        SA_STD_ERR_NET => 15,
        SA_STD_ERR_UNSUPPORTED => 9,
        SA_STD_ERR_TRUNCATED => 14,
        else => 1,
    };
}

pub export fn sa_std_net_error_code_from_posix_errno(errno: i32) i32 {
    return switch (errno) {
        0 => 0,
        1, 13 => 8,
        2, 20 => 12,
        4 => 24,
        9 => 11,
        11 => 6,
        12 => 13,
        14, 22 => 10,
        17 => 23,
        32 => 22,
        98 => 16,
        99 => 17,
        100 => 27,
        101 => 15,
        103 => 19,
        104 => 18,
        107 => 20,
        110 => 4,
        111 => 3,
        113 => 21,
        -2, -4, -5 => 2,
        -3 => 4,
        -6, -7 => 9,
        -8 => 10,
        -10 => 13,
        -11 => 14,
        else => 1,
    };
}

pub export fn sa_std_net_error_code_from_wsa_error(native_error: i32) i32 {
    return switch (native_error) {
        0 => 0,
        10004 => 24,
        10013 => 8,
        10022 => 10,
        10024, 10055 => 13,
        10035, 10036, 10037 => 6,
        10038 => 11,
        10040 => 26,
        10041, 10042, 10043, 10044, 10045, 10046, 10047 => 9,
        10048 => 16,
        10049 => 17,
        10050, 10052 => 27,
        10051 => 15,
        10053 => 19,
        10054 => 18,
        10057, 10058 => 20,
        10060 => 4,
        10061 => 3,
        10064, 10065 => 21,
        11001, 11003, 11004 => 2,
        11002 => 4,
        else => 1,
    };
}

pub fn netErrorCodeName(code: i32) []const u8 {
    return switch (code) {
        0 => "ok",
        1 => "unknown",
        2 => "dns",
        3 => "connection_refused",
        4 => "timed_out",
        5 => "connection_closed",
        6 => "would_block",
        7 => "invalid_address",
        8 => "permission_denied",
        9 => "unsupported",
        10 => "invalid_input",
        11 => "invalid_handle",
        12 => "not_found",
        13 => "out_of_memory",
        14 => "io",
        15 => "network_unreachable",
        16 => "addr_in_use",
        17 => "addr_not_available",
        18 => "connection_reset",
        19 => "connection_aborted",
        20 => "not_connected",
        21 => "host_unreachable",
        22 => "broken_pipe",
        23 => "already_exists",
        24 => "interrupted",
        25 => "unexpected_eof",
        26 => "invalid_data",
        27 => "network_down",
        28 => "write_zero",
        else => "unknown",
    };
}

pub export fn sa_std_net_error_code_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = netErrorCodeName(code);
    if (out_len) |len_ptr| len_ptr.* = @as(u64, @intCast(name.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const cap = lenAsUsize(out_cap) catch |err| return finishErr(err);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const copy_len = @min(cap, name.len);
    @memcpy(out_ptr[0..copy_len], name[0..copy_len]);
    if (copy_len != name.len) return finish(SA_STD_ERR_TRUNCATED);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_error_platform() i32 {
    return 2;
}

pub export fn sa_std_net_error_code_from_native_error(native_error: i32) i32 {
    return sa_std_net_error_code_from_wsa_error(native_error);
}

pub export fn sa_std_net_hostname(out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    _ = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    wsaStartup() catch |err| return finishErr(err);
    var buffer: [256]u8 = undefined;
    if (gethostname(&buffer, @intCast(buffer.len)) != 0) {
        return finishErr(wsaError());
    }
    const name = std.mem.sliceTo(&buffer, 0);
    return writeFormattedInto(out, out_cap, out_len, name);
}

pub export fn sa_std_error_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = statusName(code);
    if (out_len) |len_ptr| len_ptr.* = @as(u64, @intCast(name.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const cap = lenAsUsize(out_cap) catch |err| return finishErr(err);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const copy_len = @min(cap, name.len);
    @memcpy(out_ptr[0..copy_len], name[0..copy_len]);
    if (copy_len != name.len) return finish(SA_STD_ERR_TRUNCATED);
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

pub export fn sa_io_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_io_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_io_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_deno_cwd() u64 {
    const cwd = sio.getCwdAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(cwd) catch return 0;
}

pub export fn sa_deno_chdir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.changeCurDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_env_set(key_ptr: ?[*]const u8, key_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const value = constBytes(value_ptr, value_len) catch |err| return finishErr(err);
    setEnvValue(key, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_env_delete(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    setEnvValue(key, "") catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_random_uuid() u64 {
    var bytes: [16]u8 = undefined;
    sio.io().random(&bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    var text: [36]u8 = undefined;
    _ = std.fmt.bufPrint(
        &text,
        "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        },
    ) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, &text) catch return 0;
    return openOwnedByteBuffer(owned) catch {
        std.heap.page_allocator.free(owned);
        return 0;
    };
}

pub export fn sa_deno_make_temp_dir(prefix_ptr: ?[*]const u8, prefix_len: u64) FallibleU64 {
    const prefix = constBytes(prefix_ptr, prefix_len) catch |err| return failU64(mapError(err));
    if (std.mem.indexOfScalar(u8, prefix, 0) != null) return failU64(SA_STD_ERR_INVALID_ARGUMENT);
    const allocator = std.heap.page_allocator;
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = tempPathAlloc(allocator, prefix, "") catch |err| return failU64(mapError(err));
        sio.cwd().makeDir(path) catch |err| {
            allocator.free(path);
            if (err == error.PathAlreadyExists) continue;
            return failU64(mapError(err));
        };
        const handle = openOwnedByteBuffer(path) catch |err| {
            sio.cwd().deleteDir(path) catch {};
            allocator.free(path);
            return failU64(mapError(err));
        };
        return okU64(handle);
    }
    return failU64(SA_STD_ERR_IO);
}

pub export fn sa_deno_make_temp_file(
    prefix_ptr: ?[*]const u8,
    prefix_len: u64,
    suffix_ptr: ?[*]const u8,
    suffix_len: u64,
) FallibleU64 {
    const prefix = constBytes(prefix_ptr, prefix_len) catch |err| return failU64(mapError(err));
    const suffix = constBytes(suffix_ptr, suffix_len) catch |err| return failU64(mapError(err));
    if (std.mem.indexOfScalar(u8, prefix, 0) != null or std.mem.indexOfScalar(u8, suffix, 0) != null) {
        return failU64(SA_STD_ERR_INVALID_ARGUMENT);
    }
    const allocator = std.heap.page_allocator;
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = tempPathAlloc(allocator, prefix, suffix) catch |err| return failU64(mapError(err));
        const file = sio.cwd().createFile(path, .{ .read = true, .exclusive = true }) catch |err| {
            allocator.free(path);
            if (err == error.PathAlreadyExists) continue;
            return failU64(mapError(err));
        };
        file.close();
        const handle = openOwnedByteBuffer(path) catch |err| {
            sio.cwd().deleteFile(path) catch {};
            allocator.free(path);
            return failU64(mapError(err));
        };
        return okU64(handle);
    }
    return failU64(SA_STD_ERR_IO);
}

pub export fn sa_deno_args_json() u64 {
    const json = processArgsJsonAlloc(std.heap.page_allocator, true) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_btoa(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch return 0;
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return openOwnedByteBuffer(encoded) catch {
        std.heap.page_allocator.free(encoded);
        return 0;
    };
}

pub export fn sa_deno_atob(data_ptr: ?[*]const u8, len: u64) u64 {
    const encoded = constBytes(data_ptr, len) catch return 0;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return 0;
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch return 0;
    std.base64.standard.Decoder.decode(decoded, encoded) catch {
        std.heap.page_allocator.free(decoded);
        return 0;
    };
    return openOwnedByteBuffer(decoded) catch {
        std.heap.page_allocator.free(decoded);
        return 0;
    };
}

pub export fn sa_deno_text_encode(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
    return openOwnedByteBuffer(owned) catch {
        std.heap.page_allocator.free(owned);
        return 0;
    };
}

pub export fn sa_deno_text_decode(data_ptr: ?[*]const u8, len: u64) u64 {
    return sa_deno_text_encode(data_ptr, len);
}

pub export fn sa_deno_version_json() u64 {
    const json = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"deno\":\"sa-std\",\"v8\":\"\",\"typescript\":\"\",\"sci\":\"{s}\"}}",
        .{builtin.zig_version_string},
    ) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_version_deno() u64 {
    const owned = std.heap.page_allocator.dupe(u8, "sa-std") catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}
