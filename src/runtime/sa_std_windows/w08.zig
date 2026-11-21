const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const CloseHandle = @import("w01.zig").CloseHandle;
const CreateThread = @import("w01.zig").CreateThread;
const CreateToolhelp32Snapshot = @import("w01.zig").CreateToolhelp32Snapshot;
const JsonDocument = @import("w01.zig").JsonDocument;
const JsonNode = @import("w01.zig").JsonNode;
const NtQueryInformationProcess = @import("w01.zig").NtQueryInformationProcess;
const Process32FirstW = @import("w01.zig").Process32FirstW;
const Process32NextW = @import("w01.zig").Process32NextW;
const ProcessEntry32W = @import("w01.zig").ProcessEntry32W;
const SA_JSON_KIND_INVALID = @import("w01.zig").SA_JSON_KIND_INVALID;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("w01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NOT_FOUND = @import("w01.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("w01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const TimeDate = @import("w01.zig").TimeDate;
const WaitForSingleObject = @import("w01.zig").WaitForSingleObject;
const acquireJsonNode = @import("w03.zig").acquireJsonNode;
const civilPartsWin = @import("w07.zig").civilPartsWin;
const constBytes = @import("w02.zig").constBytes;
const fillUtcNow = @import("w02.zig").fillUtcNow;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const jsonAsBool = @import("w04.zig").jsonAsBool;
const jsonAsF64 = @import("w04.zig").jsonAsF64;
const jsonAsI64 = @import("w04.zig").jsonAsI64;
const jsonKind = @import("w04.zig").jsonKind;
const jsonObjectValue = @import("w04.zig").jsonObjectValue;
const jsonText = @import("w04.zig").jsonText;
const last_error = @import("w01.zig").last_error;
const openOwnedByteBuffer = @import("w02.zig").openOwnedByteBuffer;
const registerJsonNode = @import("w03.zig").registerJsonNode;
const weekdayNamesWin = @import("w07.zig").weekdayNamesWin;

pub const monthNamesWin = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

pub fn appendTwoWin(out: *std.array_list.Managed(u8), val: i64) !void {
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < 2) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

pub fn appendFourWin(out: *std.array_list.Managed(u8), val: i64) !void {
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < 4) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

/// Fixed UTC string forms (mirrors the non-Windows variant).
pub export fn sa_time_format_utc(ms: i64, fmt_id: u64) u64 {
    if (fmt_id > 3) {
        const empty = std.heap.page_allocator.alloc(u8, 0) catch return 0;
        return openOwnedByteBuffer(empty) catch return 0;
    }
    const c = civilPartsWin(ms);
    const wday: usize = @as(usize, @intCast(@mod(c.days + 4, 7)));
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    switch (fmt_id) {
        0 => {
            out.appendSlice(weekdayNamesWin[wday]) catch return 0;
            out.append(' ') catch return 0;
            out.appendSlice(monthNamesWin[@as(usize, @intCast(c.month - 1))]) catch return 0;
            out.append(' ') catch return 0;
            appendTwoWin(&out, c.day) catch return 0;
            out.append(' ') catch return 0;
            appendFourWin(&out, c.year) catch return 0;
            out.append(' ') catch return 0;
            appendTwoWin(&out, c.hour) catch return 0;
            out.append(':') catch return 0;
            appendTwoWin(&out, c.minute) catch return 0;
            out.append(':') catch return 0;
            appendTwoWin(&out, c.second) catch return 0;
            out.appendSlice(" GMT+0000 (Coordinated Universal Time)") catch return 0;
        },
        1 => {
            out.appendSlice(weekdayNamesWin[wday]) catch return 0;
            out.append(' ') catch return 0;
            out.appendSlice(monthNamesWin[@as(usize, @intCast(c.month - 1))]) catch return 0;
            out.append(' ') catch return 0;
            appendTwoWin(&out, c.day) catch return 0;
            out.append(' ') catch return 0;
            appendFourWin(&out, c.year) catch return 0;
        },
        2 => {
            appendTwoWin(&out, c.hour) catch return 0;
            out.append(':') catch return 0;
            appendTwoWin(&out, c.minute) catch return 0;
            out.append(':') catch return 0;
            appendTwoWin(&out, c.second) catch return 0;
            out.appendSlice(" GMT+0000 (Coordinated Universal Time)") catch return 0;
        },
        3 => {
            out.appendSlice(weekdayNamesWin[wday]) catch return 0;
            out.appendSlice(", ") catch return 0;
            appendTwoWin(&out, c.day) catch return 0;
            out.append(' ') catch return 0;
            out.appendSlice(monthNamesWin[@as(usize, @intCast(c.month - 1))]) catch return 0;
            out.append(' ') catch return 0;
            appendFourWin(&out, c.year) catch return 0;
            out.append(' ') catch return 0;
            appendTwoWin(&out, c.hour) catch return 0;
            out.append(':') catch return 0;
            appendTwoWin(&out, c.minute) catch return 0;
            out.append(':') catch return 0;
            appendTwoWin(&out, c.second) catch return 0;
            out.appendSlice(" GMT") catch return 0;
        },
        else => unreachable,
    }
    const text = out.toOwnedSlice() catch return 0;
    return openOwnedByteBuffer(text) catch return 0;
}

pub fn daysFromCivilWin(y_in: i64, m_in: i64, d: i64) i64 {
    const y: i64 = if (m_in <= 2) y_in - 1 else y_in;
    const era: i64 = if (y >= 0) @divFloor(y, 400) else @divFloor(y - 399, 400);
    const yoe: i64 = y - era * 400;
    const mp: i64 = @mod(m_in - 3, 12);
    const doy: i64 = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// JS Date setters (mirrors the non-Windows variant).
pub export fn sa_time_set_field(ms: i64, field: u64, value: i64) i64 {
    const c = civilPartsWin(ms);
    var y = c.year;
    var mo = c.month;
    var d = c.day;
    var tod: i64 = c.hour * 3600000 + c.minute * 60000 + c.second * 1000 + c.milli;
    switch (field) {
        0 => y = value,
        1 => {
            const tm = y * 12 + value;
            y = @divFloor(tm, 12);
            mo = @mod(tm, 12) + 1;
        },
        2 => d = value,
        3 => tod = value * 3600000 + @mod(tod, 3600000),
        4 => tod = (tod - @mod(tod, 3600000)) + value * 60000 + @mod(tod, 60000),
        5 => tod = (tod - @mod(tod, 60000)) + value * 1000 + @mod(tod, 1000),
        6 => tod = tod - @mod(tod, 1000) + value,
        else => return ms,
    }
    const tm = y * 12 + (mo - 1);
    const y2 = @divFloor(tm, 12);
    const m2 = @mod(tm, 12) + 1;
    const days = daysFromCivilWin(y2, m2, 1) + (d - 1);
    const total_days = days + @divFloor(tod, 86400000);
    const tod_norm = tod - @divFloor(tod, 86400000) * 86400000;
    return (total_days * 86400) * 1000 + tod_norm;
}

pub export fn sa_time_unix_ns() i64 {
    const ts = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
    return @as(i64, @intCast(ts));
}

pub export fn sa_time_utc_now(out_date: ?*TimeDate) i32 {
    const ptr = out_date orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fillUtcNow(ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ns(ns: u64) i32 {
    std.Io.sleep(sio.io(), .{ .nanoseconds = @intCast(ns) }, .awake) catch {};
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ms(ms: u64) i32 {
    const ns = std.math.mul(u64, ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return sa_time_sleep_ns(ns);
}

pub const PthreadEntryFn = *const fn (?[*]u8) callconv(.c) i32;

pub const WinThreadTask = struct {
    entry: PthreadEntryFn,
    arg: ?[*]u8,
    result: i32 = 0,
    destroy_on_finish: bool = false,
};

pub const WinThreadHandle = struct {
    handle: std.os.windows.HANDLE,
    task: *WinThreadTask,
};

pub var win_thread_mutex: std.atomic.Mutex = .unlocked;

pub var win_thread_slots = std.array_list.Managed(?*WinThreadHandle).init(std.heap.page_allocator);

pub var win_thread_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var raw_win_thread_owners = std.array_list.Managed(RawWinThreadOwner).init(std.heap.page_allocator);

pub const RawWinThreadOwner = struct {
    raw: u64,
    task: *WinThreadTask,
};

pub fn winThreadTaskMain(task: *WinThreadTask) void {
    task.result = task.entry(task.arg);
    if (task.destroy_on_finish) {
        std.heap.page_allocator.destroy(task);
    }
}

pub fn winThreadTaskMainC(lp_parameter: ?*anyopaque) callconv(.c) std.os.windows.DWORD {
    if (lp_parameter) |raw| {
        const task: *WinThreadTask = @ptrCast(@alignCast(raw));
        winThreadTaskMain(task);
    }
    return 0;
}

pub fn allocWinThreadHandle(handle: *WinThreadHandle) !i32 {
    while (!win_thread_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer win_thread_mutex.unlock();
    while (win_thread_free_slots.items.len != 0) {
        const idx = win_thread_free_slots.pop().?;
        if (idx >= win_thread_slots.items.len or win_thread_slots.items[idx] != null) continue;
        win_thread_slots.items[idx] = handle;
        return @intCast(idx + 1);
    }
    try win_thread_slots.append(handle);
    return @intCast(win_thread_slots.items.len);
}

pub fn takeWinThreadHandle(handle: i32) !*WinThreadHandle {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    while (!win_thread_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer win_thread_mutex.unlock();
    if (idx >= win_thread_slots.items.len) return error.InvalidHandle;
    return win_thread_slots.items[idx] orelse return error.InvalidHandle;
}

pub fn freeWinThreadHandle(handle: i32) !*WinThreadHandle {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    while (!win_thread_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer win_thread_mutex.unlock();
    if (idx >= win_thread_slots.items.len) return error.InvalidHandle;
    const slot = win_thread_slots.items[idx] orelse return error.InvalidHandle;
    try win_thread_free_slots.append(idx);
    win_thread_slots.items[idx] = null;
    return slot;
}

pub fn findRawWinThreadTask(raw: u64) ?*WinThreadTask {
    while (!win_thread_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer win_thread_mutex.unlock();
    for (raw_win_thread_owners.items) |owner| {
        if (owner.raw == raw) return owner.task;
    }
    return null;
}

pub fn removeRawWinThreadOwner(raw: u64) ?*WinThreadTask {
    while (!win_thread_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer win_thread_mutex.unlock();
    for (raw_win_thread_owners.items, 0..) |owner, i| {
        if (owner.raw == raw) return raw_win_thread_owners.swapRemove(i).task;
    }
    return null;
}

pub export fn pthread_spawn(entry_ptr: ?[*]const u8, arg_ptr: ?[*]const u8) callconv(.c) i32 {
    const entry_fn: PthreadEntryFn = @alignCast(@ptrCast(entry_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT)));
    const task = std.heap.page_allocator.create(WinThreadTask) catch return finish(SA_STD_ERR_NO_MEMORY);
    task.* = .{ .entry = entry_fn, .arg = @ptrCast(@constCast(arg_ptr)) };

    const handle = std.heap.page_allocator.create(WinThreadHandle) catch {
        std.heap.page_allocator.destroy(task);
        return finish(SA_STD_ERR_NO_MEMORY);
    };

    const thread_handle = windowsCreateThread(task) catch {
        std.heap.page_allocator.destroy(handle);
        std.heap.page_allocator.destroy(task);
        return finish(SA_STD_ERR_IO);
    };

    handle.* = .{ .handle = thread_handle, .task = task };
    const id = allocWinThreadHandle(handle) catch {
        _ = CloseHandle(thread_handle);
        std.heap.page_allocator.destroy(handle);
        std.heap.page_allocator.destroy(task);
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    last_error = SA_STD_OK;
    return id;
}

pub export fn pthread_spawn_detached(entry_ptr: ?[*]const u8, arg_ptr: ?[*]const u8) callconv(.c) i32 {
    const entry_fn: PthreadEntryFn = @alignCast(@ptrCast(entry_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT)));
    const task = std.heap.page_allocator.create(WinThreadTask) catch return finish(SA_STD_ERR_NO_MEMORY);
    task.* = .{
        .entry = entry_fn,
        .arg = @ptrCast(@constCast(arg_ptr)),
        .destroy_on_finish = true,
    };
    const thread_handle = windowsCreateThread(task) catch {
        std.heap.page_allocator.destroy(task);
        return finish(SA_STD_ERR_IO);
    };
    _ = CloseHandle(thread_handle);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_pthread_join(handle_id: i32, out: ?[*]u8) callconv(.c) i32 {
    const handle_ptr = freeWinThreadHandle(handle_id) catch return finish(SA_STD_ERR_INVALID_HANDLE);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const wait_result = WaitForSingleObject(handle_ptr.handle, 0xFFFFFFFF);
    if (wait_result != 0x00000000) {
        std.heap.page_allocator.destroy(handle_ptr.task);
        std.heap.page_allocator.destroy(handle_ptr);
        return finish(SA_STD_ERR_IO);
    }
    std.mem.copyForwards(u8, out_ptr[0..4], std.mem.asBytes(&handle_ptr.task.result));
    _ = CloseHandle(handle_ptr.handle);
    std.heap.page_allocator.destroy(handle_ptr.task);
    std.heap.page_allocator.destroy(handle_ptr);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn pthread_drop(handle_id: i32) callconv(.c) void {
    if (handle_id <= 0) {
        last_error = SA_STD_ERR_INVALID_HANDLE;
        return;
    }
    const handle_ptr = freeWinThreadHandle(handle_id) catch {
        last_error = SA_STD_ERR_INVALID_HANDLE;
        return;
    };
    const wait_result = WaitForSingleObject(handle_ptr.handle, 0xFFFFFFFF);
    if (wait_result != 0x00000000) {}
    _ = CloseHandle(handle_ptr.handle);
    std.heap.page_allocator.destroy(handle_ptr.task);
    std.heap.page_allocator.destroy(handle_ptr);
    last_error = SA_STD_OK;
}

pub export fn sa_thread_current_id() u64 {
    return @as(u64, @intCast(std.Thread.getCurrentId()));
}

pub export fn sa_thread_yield_now() i32 {
    std.Thread.yield() catch {};
    return finish(SA_STD_OK);
}

pub export fn sa_thread_as_pthread_t(handle_id: i32, out_raw: ?*u64) i32 {
    const out = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const handle_ptr = takeWinThreadHandle(handle_id) catch {
        if (out_raw) |o| o.* = 0;
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    out.* = @intFromPtr(handle_ptr.handle);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_thread_into_pthread_t(handle_id: i32, out_raw: ?*u64) i32 {
    const out = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (handle_id <= 0) {
        if (out_raw) |o| o.* = 0;
        return finish(SA_STD_ERR_INVALID_HANDLE);
    }
    const idx: usize = @intCast(handle_id - 1);
    while (!win_thread_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer win_thread_mutex.unlock();
    if (idx >= win_thread_slots.items.len) {
        if (out_raw) |o| o.* = 0;
        return finish(SA_STD_ERR_INVALID_HANDLE);
    }
    const slot = win_thread_slots.items[idx] orelse {
        if (out_raw) |o| o.* = 0;
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    win_thread_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    win_thread_slots.items[idx] = null;
    const raw = @intFromPtr(slot.handle);
    raw_win_thread_owners.append(.{ .raw = raw, .task = slot.task }) catch return finish(SA_STD_ERR_NO_MEMORY);
    out.* = raw;
    std.heap.page_allocator.destroy(slot);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_thread_raw_pthread_join(raw: u64, out: ?[*]u8) i32 {
    const out_ptr = out orelse {
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    };
    const task = findRawWinThreadTask(raw) orelse {
        if (out) |o| {
            var k: usize = 0;
            while (k < 4) : (k += 1) o[k] = 0;
        }
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const handle: std.os.windows.HANDLE = @ptrFromInt(raw);
    const wait_result = WaitForSingleObject(handle, 0xFFFFFFFF);
    if (wait_result != 0x00000000) return finish(SA_STD_ERR_IO);
    const removed_task = removeRawWinThreadOwner(raw) orelse task;
    std.mem.copyForwards(u8, out_ptr[0..4], std.mem.asBytes(&removed_task.result));
    _ = CloseHandle(handle);
    std.heap.page_allocator.destroy(removed_task);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn windowsCreateThread(task: *WinThreadTask) !std.os.windows.HANDLE {
    var thread_id: std.os.windows.DWORD = 0;
    const handle = CreateThread(
        null,
        0,
        @ptrCast(@constCast(&winThreadTaskMainC)),
        task,
        0,
        &thread_id,
    ) orelse return error.SystemResources;
    return handle;
}

pub export fn sa_std_process_id() u32 {
    return std.os.windows.GetCurrentProcessId();
}

pub fn currentParentProcessId() u32 {
    const PROCESS_BASIC_INFORMATION = extern struct {
        reserved1: ?*anyopaque,
        peb_base_address: ?*anyopaque,
        reserved2: [2]?*anyopaque,
        unique_process_id: std.os.windows.ULONG_PTR,
        parent_process_id: std.os.windows.ULONG_PTR,
    };
    var info: PROCESS_BASIC_INFORMATION = undefined;
    var ret_len: std.os.windows.ULONG = 0;
    const status = NtQueryInformationProcess(
        std.os.windows.GetCurrentProcess(),
        0,
        &info,
        @sizeOf(PROCESS_BASIC_INFORMATION),
        &ret_len,
    );
    if (status == 0 and ret_len >= @sizeOf(PROCESS_BASIC_INFORMATION)) {
        return @as(u32, @intCast(info.parent_process_id));
    }
    const TH32CS_SNAPPROCESS: std.os.windows.DWORD = 0x0000_0002;
    const INVALID_HANDLE_VALUE = @as(std.os.windows.HANDLE, @ptrFromInt(std.math.maxInt(usize)));
    const current_pid = std.os.windows.GetCurrentProcessId();
    const snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    defer _ = CloseHandle(snapshot);

    var entry = std.mem.zeroes(ProcessEntry32W);
    entry.dwSize = @sizeOf(ProcessEntry32W);
    if (!Process32FirstW(snapshot, &entry).toBool()) return 0;
    while (true) {
        if (entry.th32ProcessID == current_pid) return entry.th32ParentProcessID;
        if (!Process32NextW(snapshot, &entry).toBool()) return 0;
    }
}

pub export fn sa_std_process_parent_id() u32 {
    return currentParentProcessId();
}

pub export fn sa_std_process_user_id() u32 {
    return 0;
}

pub export fn sa_std_process_group_id() u32 {
    return 0;
}

pub export fn sa_json_parse(json_bytes: ?[*]const u8, len: u64) u64 {
    const input = constBytes(json_bytes, len) catch return 0;
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{}) catch return 0;
    const document = std.heap.page_allocator.create(JsonDocument) catch {
        parsed.deinit();
        return 0;
    };
    document.* = .{ .parsed = parsed };
    return registerJsonNode(document, parsed.value, false) catch return 0;
}

pub export fn sa_json_kind(handle: u64) u32 {
    const node = acquireJsonNode(handle) catch return SA_JSON_KIND_INVALID;
    defer node.release();
    return jsonKind(node.value);
}

pub export fn sa_json_object_get(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const value = jsonObjectValue(node, key) catch |err| return finishErr(err);
    output.* = registerJsonNode(node.document, value, true) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_get(handle: u64, index: u64, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const value = switch (node.value) {
        .array => |array| blk: {
            const idx = std.math.cast(usize, index) orelse return finish(SA_STD_ERR_NOT_FOUND);
            if (idx >= array.items.len) return finish(SA_STD_ERR_NOT_FOUND);
            break :blk array.items[idx];
        },
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    output.* = registerJsonNode(node.document, value, true) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_key_at(handle: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = null;
    len_slot.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const object = switch (node.value) {
        .object => |value| value,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const idx = std.math.cast(usize, index) orelse return finish(SA_STD_ERR_NOT_FOUND);
    if (idx >= object.count()) return finish(SA_STD_ERR_NOT_FOUND);
    var iterator = object.iterator();
    var current: usize = 0;
    while (iterator.next()) |entry| : (current += 1) {
        if (current != idx) continue;
        ptr_slot.* = entry.key_ptr.*.ptr;
        len_slot.* = @as(u64, @intCast(entry.key_ptr.*.len));
        return finish(SA_STD_OK);
    }
    return finish(SA_STD_ERR_NOT_FOUND);
}

pub export fn sa_json_object_get_string(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = null;
    len_slot.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const value = jsonObjectValue(node, key) catch |err| return finishErr(err);
    const text_value = jsonText(value) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = text_value.ptr;
    len_slot.* = @as(u64, @intCast(text_value.len));
    return finish(SA_STD_OK);
}

pub fn jsonObjectTyped(handle: u64, key_ptr: ?[*]const u8, key_len: u64) !JsonNode {
    const key = try constBytes(key_ptr, key_len);
    if (key.len == 0) return error.InvalidArgument;
    const node = try acquireJsonNode(handle);
    errdefer node.release();
    return .{ .document = node.document, .value = try jsonObjectValue(node, key) };
}

pub export fn sa_json_object_get_bool(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*u8) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = jsonObjectTyped(handle, key_ptr, key_len) catch |err| return finishErr(err);
    defer node.release();
    output.* = if (jsonAsBool(node.value) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_i64(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*i64) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = jsonObjectTyped(handle, key_ptr, key_len) catch |err| return finishErr(err);
    defer node.release();
    output.* = jsonAsI64(node.value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_f64(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*f64) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = jsonObjectTyped(handle, key_ptr, key_len) catch |err| return finishErr(err);
    defer node.release();
    output.* = jsonAsF64(node.value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_f64(handle: u64, out_value: ?*f64) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    output.* = jsonAsF64(node.value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_i64(handle: u64, out_value: ?*i64) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    output.* = jsonAsI64(node.value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_bool(handle: u64, out_value: ?*u8) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    output.* = if (jsonAsBool(node.value) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}
