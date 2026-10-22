const std = @import("std");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;

extern "kernel32" fn LoadLibraryExW(
    lp_lib_file_name: [*:0]const u16,
    h_file: ?std.os.windows.HANDLE,
    dw_flags: u32,
) callconv(.winapi) ?std.os.windows.HANDLE;
extern "kernel32" fn GetProcAddress(
    h_module: std.os.windows.HANDLE,
    lp_proc_name: [*:0]const u8,
) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn FreeLibrary(h_module: std.os.windows.HANDLE) callconv(.winapi) std.os.windows.BOOL;

pub const DynLib = if (is_windows) WindowsDynLib else std.DynLib;

const WindowsDynLib = struct {
    handle: std.os.windows.HANDLE,

    pub const OpenError = error{
        FileNotFound,
        AccessDenied,
        InvalidFile,
        Unexpected,
    };

    pub fn open(path: []const u8) OpenError!WindowsDynLib {
        const path_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, path) catch return error.Unexpected;
        defer std.heap.page_allocator.free(path_w);
        return openWide(path_w);
    }

    pub fn openWide(path_w: [:0]const u16) OpenError!WindowsDynLib {
        const load_with_altered_search_path: u32 = 0x00000008;
        const handle = LoadLibraryExW(path_w.ptr, null, load_with_altered_search_path) orelse return error.FileNotFound;
        return .{ .handle = handle };
    }

    pub fn fromHandle(handle: std.os.windows.HANDLE) WindowsDynLib {
        return .{ .handle = handle };
    }

    pub fn close(self: *const WindowsDynLib) void {
        _ = FreeLibrary(self.handle);
    }

    pub fn lookup(self: *const WindowsDynLib, comptime T: type, name: [:0]const u8) ?T {
        const proc = GetProcAddress(self.handle, name.ptr) orelse return null;
        return @ptrCast(@alignCast(proc));
    }
};
