const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_NO_MEMORY = @import("../sa_std.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const mapError = @import("../sa_std.zig").mapError;
extern fn sa_host_pthread_create(thread: *std.c.pthread_t, attr: ?*const std.c.pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) callconv(.c) c_int;
extern fn sa_host_pthread_detach(thread: std.c.pthread_t) callconv(.c) c_int;
extern fn sa_host_pthread_join(thread: std.c.pthread_t, retval: ?*?*anyopaque) callconv(.c) c_int;

pub var pthread_registry_mutex: std.atomic.Mutex = .unlocked;

pub var pthread_slots = std.array_list.Managed(?*PthreadHandle).init(std.heap.page_allocator);

pub var pthread_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var raw_pthread_owners = std.array_list.Managed(RawPthreadOwner).init(std.heap.page_allocator);

const PthreadEntryFn = *const fn (?[*]u8) callconv(.c) i32;

const PthreadTask = struct {
    entry: PthreadEntryFn,
    arg: ?[*]u8,
    result: i32 = SA_STD_OK,
    destroy_on_finish: bool = false,
};

pub const PthreadHandle = struct {
    thread: std.c.pthread_t,
    task: *PthreadTask,
    joined: bool = false,
};

const RawPthreadOwner = struct {
    raw: u64,
    task: *PthreadTask,
};

const RawPthreadTransfer = struct {
    raw: u64,
    handle: *PthreadHandle,
};

fn pthreadToRaw(thread: std.c.pthread_t) u64 {
    return switch (@typeInfo(std.c.pthread_t)) {
        .int => @as(u64, @intCast(thread)),
        .pointer => @as(u64, @intFromPtr(thread)),
        else => @compileError("unsupported pthread_t representation"),
    };
}

fn rawToPthread(raw: u64) std.c.pthread_t {
    return switch (@typeInfo(std.c.pthread_t)) {
        .int => @as(std.c.pthread_t, @intCast(raw)),
        // wasm32-wasi: usize is 32-bit, raw handle is u64 ABI (zero-extended).
        .pointer => @as(std.c.pthread_t, @ptrFromInt(@as(usize, @intCast(raw)))),
        else => @compileError("unsupported pthread_t representation"),
    };
}

fn pthreadTaskMain(task: *PthreadTask) void {
    task.result = task.entry(task.arg);
    if (task.destroy_on_finish) {
        std.heap.page_allocator.destroy(task);
    }
}

fn pthreadTaskMainC(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const task: *PthreadTask = @ptrCast(@alignCast(arg orelse return null));
    pthreadTaskMain(task);
    return null;
}

fn mapPthreadCreateError(err: std.c.E) anyerror {
    return switch (err) {
        .AGAIN => error.SystemResources,
        .INVAL, .PERM => error.InvalidArgument,
        else => error.Io,
    };
}

fn spawnPthread(task: *PthreadTask) !std.c.pthread_t {
    var attr: std.c.pthread_attr_t = undefined;
    if (std.c.pthread_attr_init(&attr) != .SUCCESS) return error.SystemResources;
    defer _ = std.c.pthread_attr_destroy(&attr);
    if (std.c.pthread_attr_setstacksize(&attr, 2 * 1024 * 1024) != .SUCCESS) return error.InvalidArgument;
    if (std.c.pthread_attr_setguardsize(&attr, std.heap.pageSize()) != .SUCCESS) return error.InvalidArgument;

    var thread: std.c.pthread_t = undefined;
    const rc = sa_host_pthread_create(&thread, &attr, pthreadTaskMainC, @ptrCast(task));
    if (rc == 0) return thread;
    return mapPthreadCreateError(@fromBackingInt(@intCast(rc)));
}

fn joinPthreadHandle(thread: std.c.pthread_t) !void {
    return switch (@as(std.c.E, @fromBackingInt(@intCast(sa_host_pthread_join(thread, null))))) {
        .SUCCESS => {},
        .INVAL, .SRCH, .DEADLK => error.InvalidHandle,
        else => error.Io,
    };
}

pub fn allocPthreadHandle(handle: *PthreadHandle) !i32 {
    while (!pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer pthread_registry_mutex.unlock();
    while (pthread_free_slots.items.len != 0) {
        const idx = pthread_free_slots.pop().?;
        if (idx >= pthread_slots.items.len or pthread_slots.items[idx] != null) continue;
        pthread_slots.items[idx] = handle;
        return @intCast(idx + 1);
    }
    try pthread_slots.append(handle);
    return @intCast(pthread_slots.items.len);
}

fn takePthreadHandle(handle: i32) !*PthreadHandle {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    while (!pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer pthread_registry_mutex.unlock();
    if (idx >= pthread_slots.items.len) return error.InvalidHandle;
    return pthread_slots.items[idx] orelse return error.InvalidHandle;
}

pub fn freePthreadHandle(handle: i32) !*PthreadHandle {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    while (!pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer pthread_registry_mutex.unlock();
    if (idx >= pthread_slots.items.len) return error.InvalidHandle;
    const slot = pthread_slots.items[idx] orelse return error.InvalidHandle;
    try pthread_free_slots.append(idx);
    pthread_slots.items[idx] = null;
    return slot;
}

fn transferPthreadHandleToRaw(handle: i32) !RawPthreadTransfer {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    while (!pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer pthread_registry_mutex.unlock();
    if (idx >= pthread_slots.items.len) return error.InvalidHandle;
    const slot = pthread_slots.items[idx] orelse return error.InvalidHandle;
    try pthread_free_slots.ensureUnusedCapacity(1);
    try raw_pthread_owners.ensureUnusedCapacity(1);
    const owner = RawPthreadOwner{ .raw = pthreadToRaw(slot.thread), .task = slot.task };
    pthread_free_slots.appendAssumeCapacity(idx);
    pthread_slots.items[idx] = null;
    raw_pthread_owners.appendAssumeCapacity(owner);
    return .{ .raw = owner.raw, .handle = slot };
}

fn findRawPthreadTask(raw: u64) ?*PthreadTask {
    while (!pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer pthread_registry_mutex.unlock();
    for (raw_pthread_owners.items) |owner| {
        if (owner.raw == raw) return owner.task;
    }
    return null;
}

fn removeRawPthreadOwner(raw: u64) ?*PthreadTask {
    while (!pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer pthread_registry_mutex.unlock();
    for (raw_pthread_owners.items, 0..) |owner, i| {
        if (owner.raw == raw) return raw_pthread_owners.swapRemove(i).task;
    }
    return null;
}

pub fn pthread_spawn(entry: ?[*]const u8, arg: ?[*]const u8) callconv(.c) i32 {
    const entry_fn: PthreadEntryFn = @ptrCast(@alignCast(entry orelse return finish(SA_STD_ERR_INVALID_ARGUMENT)));
    const task = std.heap.page_allocator.create(PthreadTask) catch return finish(SA_STD_ERR_NO_MEMORY);
    task.* = .{ .entry = entry_fn, .arg = @ptrCast(@constCast(arg)) };
    const thread = spawnPthread(task) catch |err| {
        std.heap.page_allocator.destroy(task);
        return finish(mapError(err));
    };
    const handle = std.heap.page_allocator.create(PthreadHandle) catch |err| {
        joinPthreadHandle(thread) catch {};
        std.heap.page_allocator.destroy(task);
        return finish(mapError(err));
    };
    handle.* = .{ .thread = thread, .task = task };
    const id = allocPthreadHandle(handle) catch |err| {
        joinPthreadHandle(thread) catch {};
        std.heap.page_allocator.destroy(task);
        std.heap.page_allocator.destroy(handle);
        return finish(mapError(err));
    };
    sa_std.last_error = SA_STD_OK;
    return id;
}

pub fn pthread_spawn_detached(entry: ?[*]const u8, arg: ?[*]const u8) callconv(.c) i32 {
    const entry_fn: PthreadEntryFn = @ptrCast(@alignCast(entry orelse return finish(SA_STD_ERR_INVALID_ARGUMENT)));
    const task = std.heap.page_allocator.create(PthreadTask) catch return finish(SA_STD_ERR_NO_MEMORY);
    task.* = .{
        .entry = entry_fn,
        .arg = @ptrCast(@constCast(arg)),
        .destroy_on_finish = true,
    };
    const thread = spawnPthread(task) catch |err| {
        std.heap.page_allocator.destroy(task);
        return finish(mapError(err));
    };
    _ = sa_host_pthread_detach(thread);
    sa_std.last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn pthread_join(handle: i32, out: ?[*]u8) callconv(.c) i32 {
    const handle_ptr = freePthreadHandle(handle) catch |err| return finish(mapError(err));
    const out_ptr = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    joinPthreadHandle(handle_ptr.thread) catch |err| {
        std.heap.page_allocator.destroy(handle_ptr.task);
        std.heap.page_allocator.destroy(handle_ptr);
        return finishErr(err);
    };
    std.mem.copyForwards(u8, out_ptr[0..4], std.mem.asBytes(&handle_ptr.task.result));
    std.heap.page_allocator.destroy(handle_ptr.task);
    std.heap.page_allocator.destroy(handle_ptr);
    sa_std.last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn sa_thread_as_pthread_t(handle: i32, out_raw: ?*u64) callconv(.c) i32 {
    const out = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle_ptr = takePthreadHandle(handle) catch |err| return finish(mapError(err));
    out.* = pthreadToRaw(handle_ptr.thread);
    sa_std.last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn sa_thread_into_pthread_t(handle: i32, out_raw: ?*u64) callconv(.c) i32 {
    const out = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const transfer = transferPthreadHandleToRaw(handle) catch |err| return finish(mapError(err));
    out.* = transfer.raw;
    std.heap.page_allocator.destroy(transfer.handle);
    sa_std.last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn sa_thread_raw_pthread_join(raw: u64, out: ?[*]u8) callconv(.c) i32 {
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    std.mem.writeInt(u32, out_ptr[0..4], 0, .little);
    const task = findRawPthreadTask(raw) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    joinPthreadHandle(rawToPthread(raw)) catch |err| return finishErr(err);
    const removed_task = removeRawPthreadOwner(raw) orelse task;
    std.mem.copyForwards(u8, out_ptr[0..4], std.mem.asBytes(&removed_task.result));
    std.heap.page_allocator.destroy(removed_task);
    sa_std.last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn pthread_drop(handle: i32) callconv(.c) void {
    if (handle <= 0) {
        sa_std.last_error = SA_STD_ERR_INVALID_HANDLE;
        return;
    }
    const idx: usize = @intCast(handle - 1);
    var handle_ptr: ?*PthreadHandle = null;
    while (!pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    if (idx >= pthread_slots.items.len) {
        pthread_registry_mutex.unlock();
        sa_std.last_error = SA_STD_ERR_INVALID_HANDLE;
        return;
    }
    if (pthread_slots.items[idx]) |slot| {
        pthread_slots.items[idx] = null;
        handle_ptr = slot;
    }
    pthread_registry_mutex.unlock();
    if (handle_ptr) |slot| {
        joinPthreadHandle(slot.thread) catch {};
        std.heap.page_allocator.destroy(slot.task);
        std.heap.page_allocator.destroy(slot);
    }
    sa_std.last_error = SA_STD_OK;
}
