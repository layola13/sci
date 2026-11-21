const std = @import("std");
const builtin = @import("sa_http2.zig").builtin;
const sio = @import("sa_http2.zig").sio;

pub const Nghttp2Session = opaque {};

pub const Nghttp2SessionCallbacks = opaque {};

pub const Nghttp2Frame = opaque {};

pub const Nghttp2Nv = extern struct {
    name: [*]u8,
    value: [*]u8,
    namelen: usize,
    valuelen: usize,
    flags: u8,
};

pub const Nghttp2DataSource = extern union {
    fd: c_int,
    ptr: ?*anyopaque,
};

pub const Nghttp2DataProvider = extern struct {
    source: Nghttp2DataSource,
    read_callback: ?*const fn (?*Nghttp2Session, i32, [*]u8, usize, *u32, *Nghttp2DataSource, ?*anyopaque) callconv(.c) isize,
};

pub const Nghttp2Version = extern struct {
    age: c_int,
    version_num: c_int,
    // The full nghttp2_version struct also exposes version_str/proto_str, but
    // their offset/availability differs across nghttp2 releases. We only need
    // version_num (stable int at offset 4), so the struct is intentionally
    // truncated here.
};

pub const Nghttp2OnHeaderCallback = *const fn (?*Nghttp2Session, ?*const Nghttp2Frame, [*]const u8, usize, [*]const u8, usize, u8, ?*anyopaque) callconv(.c) c_int;

pub const Nghttp2OnDataChunkRecvCallback = *const fn (?*Nghttp2Session, u8, i32, [*]const u8, usize, ?*anyopaque) callconv(.c) c_int;

pub const Nghttp2OnFrameRecvCallback = *const fn (?*Nghttp2Session, ?*const Nghttp2Frame, ?*anyopaque) callconv(.c) c_int;

pub const Nghttp2CallbacksNewFn = *const fn (*?*Nghttp2SessionCallbacks) callconv(.c) c_int;

pub const Nghttp2CallbacksDelFn = *const fn (?*Nghttp2SessionCallbacks) callconv(.c) void;

pub const Nghttp2SetOnHeaderFn = *const fn (?*Nghttp2SessionCallbacks, Nghttp2OnHeaderCallback) callconv(.c) void;

pub const Nghttp2SetOnDataChunkRecvFn = *const fn (?*Nghttp2SessionCallbacks, Nghttp2OnDataChunkRecvCallback) callconv(.c) void;

pub const Nghttp2SetOnFrameRecvFn = *const fn (?*Nghttp2SessionCallbacks, Nghttp2OnFrameRecvCallback) callconv(.c) void;

pub const Nghttp2SessionClientNewFn = *const fn (*?*Nghttp2Session, ?*const Nghttp2SessionCallbacks, ?*anyopaque) callconv(.c) c_int;

pub const Nghttp2SessionDelFn = *const fn (?*Nghttp2Session) callconv(.c) void;

pub const Nghttp2SubmitRequestFn = *const fn (?*Nghttp2Session, ?*const anyopaque, [*]const Nghttp2Nv, usize, ?*const Nghttp2DataProvider, ?*anyopaque) callconv(.c) i32;

pub const Nghttp2SubmitSettingsFn = *const fn (?*Nghttp2Session, u8, ?*const anyopaque, usize) callconv(.c) c_int;

pub const Nghttp2SessionMemSendFn = *const fn (?*Nghttp2Session, *?[*]const u8) callconv(.c) isize;

pub const Nghttp2SessionMemRecvFn = *const fn (?*Nghttp2Session, [*]const u8, usize) callconv(.c) isize;

pub const Nghttp2SessionWantFn = *const fn (?*Nghttp2Session) callconv(.c) c_int;

pub const Nghttp2VersionFn = *const fn (c_int) callconv(.c) ?*const Nghttp2Version;

pub const Nghttp2Api = struct {
    lib: if (builtin.cpu.arch.isWasm()) void else std.DynLib,
    callbacks_new: Nghttp2CallbacksNewFn,
    callbacks_del: Nghttp2CallbacksDelFn,
    callbacks_set_on_header_callback: Nghttp2SetOnHeaderFn,
    callbacks_set_on_data_chunk_recv_callback: Nghttp2SetOnDataChunkRecvFn,
    callbacks_set_on_frame_recv_callback: Nghttp2SetOnFrameRecvFn,
    session_client_new: Nghttp2SessionClientNewFn,
    session_del: Nghttp2SessionDelFn,
    submit_request: Nghttp2SubmitRequestFn,
    submit_settings: Nghttp2SubmitSettingsFn,
    session_mem_send: Nghttp2SessionMemSendFn,
    session_mem_recv: Nghttp2SessionMemRecvFn,
    session_want_read: Nghttp2SessionWantFn,
    session_want_write: Nghttp2SessionWantFn,
    version: Nghttp2VersionFn,
};

pub var nghttp2_api: ?Nghttp2Api = null;

pub var nghttp2_api_mutex = std.Io.Mutex.init;

pub fn loadNghttp2Api() ?*Nghttp2Api {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return loadNghttp2ApiNative();
    }
}

pub fn loadNghttp2ApiNative() ?*Nghttp2Api {
    if (comptime builtin.cpu.arch.isWasm()) return null;
    nghttp2_api_mutex.lockUncancelable(sio.io());
    defer nghttp2_api_mutex.unlock(sio.io());
    if (nghttp2_api) |*api| return api;

    const candidates = [_][]const u8{
        "libnghttp2.so.14",
        "/lib/x86_64-linux-gnu/libnghttp2.so.14",
        "/usr/lib/x86_64-linux-gnu/libnghttp2.so.14",
    };

    for (candidates) |candidate| {
        var lib = std.DynLib.open(candidate) catch continue;
        const callbacks_new = lib.lookup(Nghttp2CallbacksNewFn, "nghttp2_session_callbacks_new") orelse {
            lib.close();
            continue;
        };
        const callbacks_del = lib.lookup(Nghttp2CallbacksDelFn, "nghttp2_session_callbacks_del") orelse {
            lib.close();
            continue;
        };
        const set_header = lib.lookup(Nghttp2SetOnHeaderFn, "nghttp2_session_callbacks_set_on_header_callback") orelse {
            lib.close();
            continue;
        };
        const set_data = lib.lookup(Nghttp2SetOnDataChunkRecvFn, "nghttp2_session_callbacks_set_on_data_chunk_recv_callback") orelse {
            lib.close();
            continue;
        };
        const set_frame = lib.lookup(Nghttp2SetOnFrameRecvFn, "nghttp2_session_callbacks_set_on_frame_recv_callback") orelse {
            lib.close();
            continue;
        };
        const session_client_new = lib.lookup(Nghttp2SessionClientNewFn, "nghttp2_session_client_new") orelse {
            lib.close();
            continue;
        };
        const session_del = lib.lookup(Nghttp2SessionDelFn, "nghttp2_session_del") orelse {
            lib.close();
            continue;
        };
        const submit_request = lib.lookup(Nghttp2SubmitRequestFn, "nghttp2_submit_request") orelse {
            lib.close();
            continue;
        };
        const submit_settings = lib.lookup(Nghttp2SubmitSettingsFn, "nghttp2_submit_settings") orelse {
            lib.close();
            continue;
        };
        const mem_send = lib.lookup(Nghttp2SessionMemSendFn, "nghttp2_session_mem_send") orelse {
            lib.close();
            continue;
        };
        const mem_recv = lib.lookup(Nghttp2SessionMemRecvFn, "nghttp2_session_mem_recv") orelse {
            lib.close();
            continue;
        };
        const want_read = lib.lookup(Nghttp2SessionWantFn, "nghttp2_session_want_read") orelse {
            lib.close();
            continue;
        };
        const want_write = lib.lookup(Nghttp2SessionWantFn, "nghttp2_session_want_write") orelse {
            lib.close();
            continue;
        };
        const version = lib.lookup(Nghttp2VersionFn, "nghttp2_version") orelse {
            lib.close();
            continue;
        };
        nghttp2_api = .{
            .lib = lib,
            .callbacks_new = callbacks_new,
            .callbacks_del = callbacks_del,
            .callbacks_set_on_header_callback = set_header,
            .callbacks_set_on_data_chunk_recv_callback = set_data,
            .callbacks_set_on_frame_recv_callback = set_frame,
            .session_client_new = session_client_new,
            .session_del = session_del,
            .submit_request = submit_request,
            .submit_settings = submit_settings,
            .session_mem_send = mem_send,
            .session_mem_recv = mem_recv,
            .session_want_read = want_read,
            .session_want_write = want_write,
            .version = version,
        };
        return &nghttp2_api.?;
    }
    return null;
}

pub const Nghttp2SettingsEntry = extern struct {
    settings_id: i32,
    value: u32,
};
