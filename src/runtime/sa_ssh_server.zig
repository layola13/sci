const std = @import("std");
const ALLOC = @import("sa_ssh.zig").ALLOC;
const ERR_HANDLE = @import("sa_ssh.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_ssh.zig").ERR_INVALID;
const ERR_IO = @import("sa_ssh.zig").ERR_IO;
const ERR_NET = @import("sa_ssh.zig").ERR_NET;
const ERR_NOMEM = @import("sa_ssh.zig").ERR_NOMEM;
const ERR_UNSUPPORTED = @import("sa_ssh.zig").ERR_UNSUPPORTED;
const OK = @import("sa_ssh.zig").OK;
const Ssh = @import("sa_ssh.zig").Ssh;
const loadSsh = @import("sa_ssh.zig").loadSsh;
const registerBuffer = @import("sa_ssh.zig").registerBuffer;
const toZ = @import("sa_ssh.zig").toZ;

const ServerBind = struct { api: *const Ssh, bind: ?*anyopaque };

const ServerSession = struct {
    api: *const Ssh,
    session: ?*anyopaque,
    pending_msg: ?*anyopaque = null,
    pending_kind: u32 = 0,
    pending_state: i32 = 0,
};

const ServerChannel = struct { api: *const Ssh, channel: ?*anyopaque };

pub export fn sa_std_ssh_server_listen(bind_addr: ?[*]const u8, bind_addr_len: u64, port: u32, hostkey_path: ?[*]const u8, hostkey_path_len: u64, out_bind: ?*?*anyopaque) i32 {
    const slot = out_bind orelse return ERR_INVALID;
    slot.* = null;
    const api = loadSsh() orelse return ERR_UNSUPPORTED;
    const hk_ptr = hostkey_path orelse return ERR_INVALID;
    const bind = api.bind_new() orelse return ERR_IO;
    errdefer api.bind_free(bind);
    const hk_z = toZ(ALLOC, hk_ptr[0..@intCast(hostkey_path_len)]) orelse return ERR_NOMEM;
    defer ALLOC.free(hk_z);
    if (api.bind_options_set(bind, 3, hk_z.ptr) != 0) return ERR_IO; // HOSTKEY
    if (bind_addr) |ba| {
        if (bind_addr_len > 0) {
            const addr_z = toZ(ALLOC, ba[0..@intCast(bind_addr_len)]) orelse return ERR_NOMEM;
            defer ALLOC.free(addr_z);
            if (api.bind_options_set(bind, 0, addr_z.ptr) != 0) return ERR_IO; // BINDADDR
        }
    }
    var port_v: c_uint = @intCast(port);
    if (api.bind_options_set(bind, 1, &port_v) != 0) return ERR_IO; // BINDPORT
    if (api.bind_listen(bind) != 0) return ERR_IO;
    const out = ALLOC.create(ServerBind) catch return ERR_NOMEM;
    out.* = .{ .api = api, .bind = bind };
    slot.* = out;
    return OK;
}

pub export fn sa_std_ssh_server_bind_close(bind_handle: ?*anyopaque) i32 {
    const h = bind_handle orelse return ERR_HANDLE;
    const b: *ServerBind = @ptrCast(@alignCast(h));
    b.api.bind_free(b.bind);
    ALLOC.destroy(b);
    return OK;
}

pub export fn sa_std_ssh_server_accept(bind_handle: ?*anyopaque, out_session: ?*?*anyopaque) i32 {
    const slot = out_session orelse return ERR_INVALID;
    slot.* = null;
    const h = bind_handle orelse return ERR_HANDLE;
    const b: *ServerBind = @ptrCast(@alignCast(h));
    const session = b.api.new_session() orelse return ERR_IO;
    errdefer b.api.free_session(session);
    if (b.api.bind_accept(b.bind, session) != 0) return ERR_NET;
    if (b.api.handle_key_exchange(session) != 0) return ERR_NET;
    const out = ALLOC.create(ServerSession) catch return ERR_NOMEM;
    out.* = .{ .api = b.api, .session = session };
    slot.* = out;
    return OK;
}

fn serverSessionOf(handle: ?*anyopaque) ?*ServerSession {
    const h = handle orelse return null;
    return @ptrCast(@alignCast(h));
}

pub export fn sa_std_ssh_server_auth_next(session_handle: ?*anyopaque, out_kind: ?*u32, out_user: ?*u64, out_secret: ?*u64, out_state: ?*i32) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    const kind_slot = out_kind orelse return ERR_INVALID;
    const user_slot = out_user orelse return ERR_INVALID;
    const secret_slot = out_secret orelse return ERR_INVALID;
    const state_slot = out_state orelse return ERR_INVALID;
    if (ss.pending_msg != null) return ERR_INVALID;
    while (true) {
        const msg = ss.api.message_get(ss.session) orelse return ERR_IO;
        const mtype = ss.api.message_get_type(msg);
        if (mtype != 1) { // not AUTH
            _ = ss.api.message_reply_default(msg);
            ss.api.message_free(msg);
            continue;
        }
        const method = ss.api.message_subtype(msg);
        const user = ss.api.auth_user(msg) orelse "";
        if (method == 2) { // password
            const pass = ss.api.auth_password(msg) orelse "";
            const user_buf = ALLOC.dupe(u8, std.mem.span(user)) catch return ERR_NOMEM;
            const pass_buf = ALLOC.dupe(u8, std.mem.span(pass)) catch {
                ALLOC.free(user_buf);
                return ERR_NOMEM;
            };
            user_slot.* = registerBuffer(user_buf) catch return ERR_NOMEM;
            secret_slot.* = registerBuffer(pass_buf) catch return ERR_NOMEM;
            kind_slot.* = 1;
            state_slot.* = 0;
            ss.pending_msg = msg;
            ss.pending_kind = 1;
            return OK;
        }
        if (method == 4) { // publickey
            // ssh_message_auth_pubkey returns the message-owned
            // ssh_key (never freed here); export its base64 blob
            // directly. The legacy route (ssh_message_auth_publickey
            // + publickey_to_string) cannot be used: on libssh 0.10
            // publickey_to_string returns NULL for a key taken from
            // an auth message, which silently default-rejected every
            // real publickey offer (DEF-SSH-AUTHNEXT-PUBKEY). The
            // export below was verified byte-identical to the blob
            // in the client's .pub file.
            const key = ss.api.auth_pubkey(msg) orelse {
                _ = ss.api.message_reply_default(msg);
                ss.api.message_free(msg);
                continue;
            };
            var b64: ?[*:0]u8 = null;
            if (ss.api.pki_export_pubkey_base64(key, &b64) != 0 or b64 == null) {
                _ = ss.api.message_reply_default(msg);
                ss.api.message_free(msg);
                continue;
            }
            defer ss.api.string_free_char(b64);
            const blob = std.mem.span(b64.?);
            const user_buf = ALLOC.dupe(u8, std.mem.span(user)) catch return ERR_NOMEM;
            const key_buf = ALLOC.dupe(u8, blob) catch {
                ALLOC.free(user_buf);
                return ERR_NOMEM;
            };
            user_slot.* = registerBuffer(user_buf) catch return ERR_NOMEM;
            secret_slot.* = registerBuffer(key_buf) catch return ERR_NOMEM;
            kind_slot.* = 2;
            state_slot.* = ss.api.auth_publickey_state(msg);
            ss.pending_msg = msg;
            ss.pending_kind = 2;
            ss.pending_state = state_slot.*;
            return OK;
        }
        _ = ss.api.message_reply_default(msg);
        ss.api.message_free(msg);
    }
}

pub export fn sa_std_ssh_server_auth_accept(session_handle: ?*anyopaque) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    const msg = ss.pending_msg orelse return ERR_INVALID;
    const rc = if (ss.pending_kind == 2 and ss.pending_state == 0)
        ss.api.auth_reply_pk_ok_simple(msg)
    else
        ss.api.auth_reply_success(msg, 0);
    ss.api.message_free(msg);
    ss.pending_msg = null;
    ss.pending_kind = 0;
    return if (rc == 0) OK else ERR_IO;
}

pub export fn sa_std_ssh_server_auth_deny(session_handle: ?*anyopaque) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    const msg = ss.pending_msg orelse return ERR_INVALID;
    _ = ss.api.message_reply_default(msg);
    ss.api.message_free(msg);
    ss.pending_msg = null;
    ss.pending_kind = 0;
    return OK;
}

pub export fn sa_std_ssh_server_channel_accept(session_handle: ?*anyopaque, out_channel: ?*?*anyopaque) i32 {
    const slot = out_channel orelse return ERR_INVALID;
    slot.* = null;
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    while (true) {
        const msg = ss.api.message_get(ss.session) orelse return ERR_IO;
        const mtype = ss.api.message_get_type(msg);
        if (mtype == 2 and ss.api.message_subtype(msg) == 1) { // CHANNEL_OPEN / SESSION
            const channel = ss.api.channel_open_reply_accept(msg) orelse {
                ss.api.message_free(msg);
                return ERR_IO;
            };
            ss.api.message_free(msg);
            const out = ALLOC.create(ServerChannel) catch return ERR_NOMEM;
            out.* = .{ .api = ss.api, .channel = channel };
            slot.* = out;
            return OK;
        }
        _ = ss.api.message_reply_default(msg);
        ss.api.message_free(msg);
    }
}

pub export fn sa_std_ssh_server_channel_exec(session_handle: ?*anyopaque, out_kind: ?*u32, out_command: ?*u64) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    const kind_slot = out_kind orelse return ERR_INVALID;
    const cmd_slot = out_command orelse return ERR_INVALID;
    cmd_slot.* = 0;
    while (true) {
        const msg = ss.api.message_get(ss.session) orelse return ERR_IO;
        const mtype = ss.api.message_get_type(msg);
        if (mtype == 3) { // CHANNEL request
            const subtype = ss.api.message_subtype(msg);
            if (subtype == 2) { // EXEC
                if (ss.api.channel_request_reply_success(msg) != 0) {
                    ss.api.message_free(msg);
                    return ERR_IO;
                }
                const cmd = ss.api.channel_request_command(msg) orelse "";
                const buf = ALLOC.dupe(u8, std.mem.span(cmd)) catch return ERR_NOMEM;
                cmd_slot.* = registerBuffer(buf) catch return ERR_NOMEM;
                kind_slot.* = 1;
                ss.api.message_free(msg);
                return OK;
            }
            if (subtype == 3) { // SHELL
                if (ss.api.channel_request_reply_success(msg) != 0) {
                    ss.api.message_free(msg);
                    return ERR_IO;
                }
                kind_slot.* = 2;
                ss.api.message_free(msg);
                return OK;
            }
            // PTY / ENV / others: accept and keep pumping
            _ = ss.api.channel_request_reply_success(msg);
            ss.api.message_free(msg);
            continue;
        }
        _ = ss.api.message_reply_default(msg);
        ss.api.message_free(msg);
    }
}

fn serverChannelOf(handle: ?*anyopaque) ?*ServerChannel {
    const h = handle orelse return null;
    return @ptrCast(@alignCast(h));
}

pub export fn sa_std_ssh_channel_write(channel_handle: ?*anyopaque, stream: u32, data: ?[*]const u8, data_len: u64, out_written: ?*u64) i32 {
    const ch = serverChannelOf(channel_handle) orelse return ERR_HANDLE;
    const data_ptr = data orelse return ERR_INVALID;
    const slot = out_written orelse return ERR_INVALID;
    const bytes = data_ptr[0..@intCast(data_len)];
    var off: usize = 0;
    while (off < bytes.len) {
        const n = if (stream == 1)
            ch.api.channel_write_stderr(ch.channel, bytes[off..].ptr, @intCast(bytes.len - off))
        else
            ch.api.channel_write(ch.channel, bytes[off..].ptr, @intCast(bytes.len - off));
        if (n < 0) return ERR_IO;
        off += @intCast(n);
    }
    slot.* = off;
    return OK;
}

pub export fn sa_std_ssh_channel_read(channel_handle: ?*anyopaque, stream: u32, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const ch = serverChannelOf(channel_handle) orelse return ERR_HANDLE;
    const buf = out orelse return ERR_INVALID;
    const slot = out_read orelse return ERR_INVALID;
    const n = ch.api.channel_read(ch.channel, buf, @intCast(@min(cap, std.math.maxInt(u32))), @intCast(stream));
    if (n == -127) { // SSH_EOF
        slot.* = 0;
        return OK;
    }
    if (n < 0) return ERR_IO;
    slot.* = @intCast(n);
    return OK;
}

pub export fn sa_std_ssh_channel_send_exit(channel_handle: ?*anyopaque, exit_code: i32) i32 {
    const ch = serverChannelOf(channel_handle) orelse return ERR_HANDLE;
    return if (ch.api.channel_exit_status(ch.channel, exit_code) == 0) OK else ERR_IO;
}

pub export fn sa_std_ssh_channel_close(channel_handle: ?*anyopaque) i32 {
    const ch = serverChannelOf(channel_handle) orelse return ERR_HANDLE;
    _ = ch.api.channel_send_eof(ch.channel);
    _ = ch.api.channel_close(ch.channel);
    ch.api.channel_free(ch.channel);
    ALLOC.destroy(ch);
    return OK;
}

pub export fn sa_std_ssh_server_session_close(session_handle: ?*anyopaque) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    if (ss.pending_msg) |msg| ss.api.message_free(msg);
    ss.api.disconnect(ss.session);
    ss.api.free_session(ss.session);
    ALLOC.destroy(ss);
    return OK;
}
