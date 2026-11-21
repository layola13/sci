const std = @import("std");
const OK = @import("sa_ssh.zig").OK;
const lxClose = @import("sa_ssh.zig").lxClose;
const sa_std_ssh_auth_keyfile = @import("sa_ssh.zig").sa_std_ssh_auth_keyfile;
const sa_std_ssh_auth_password = @import("sa_ssh.zig").sa_std_ssh_auth_password;
const sa_std_ssh_buffer_data = @import("sa_ssh.zig").sa_std_ssh_buffer_data;
const sa_std_ssh_buffer_free = @import("sa_ssh.zig").sa_std_ssh_buffer_free;
const sa_std_ssh_buffer_len = @import("sa_ssh.zig").sa_std_ssh_buffer_len;
const sa_std_ssh_channel_close = @import("sa_ssh.zig").sa_std_ssh_channel_close;
const sa_std_ssh_channel_send_exit = @import("sa_ssh.zig").sa_std_ssh_channel_send_exit;
const sa_std_ssh_channel_write = @import("sa_ssh.zig").sa_std_ssh_channel_write;
const sa_std_ssh_client_connect = @import("sa_ssh.zig").sa_std_ssh_client_connect;
const sa_std_ssh_exec = @import("sa_ssh.zig").sa_std_ssh_exec;
const sa_std_ssh_hostkey_fingerprint = @import("sa_ssh.zig").sa_std_ssh_hostkey_fingerprint;
const sa_std_ssh_server_accept = @import("sa_ssh.zig").sa_std_ssh_server_accept;
const sa_std_ssh_server_auth_accept = @import("sa_ssh.zig").sa_std_ssh_server_auth_accept;
const sa_std_ssh_server_auth_deny = @import("sa_ssh.zig").sa_std_ssh_server_auth_deny;
const sa_std_ssh_server_auth_next = @import("sa_ssh.zig").sa_std_ssh_server_auth_next;
const sa_std_ssh_server_bind_close = @import("sa_ssh.zig").sa_std_ssh_server_bind_close;
const sa_std_ssh_server_channel_accept = @import("sa_ssh.zig").sa_std_ssh_server_channel_accept;
const sa_std_ssh_server_channel_exec = @import("sa_ssh.zig").sa_std_ssh_server_channel_exec;
const sa_std_ssh_server_listen = @import("sa_ssh.zig").sa_std_ssh_server_listen;
const sa_std_ssh_server_session_close = @import("sa_ssh.zig").sa_std_ssh_server_session_close;
const sa_std_ssh_session_close = @import("sa_ssh.zig").sa_std_ssh_session_close;
const sa_std_ssh_sftp_read = @import("sa_ssh.zig").sa_std_ssh_sftp_read;
const sa_std_ssh_sftp_stat = @import("sa_ssh.zig").sa_std_ssh_sftp_stat;
const sa_std_ssh_sftp_write = @import("sa_ssh.zig").sa_std_ssh_sftp_write;
const sa_std_ssh_supported = @import("sa_ssh.zig").sa_std_ssh_supported;
const sio = @import("sa_ssh.zig").sio;

const testing = std.testing;

fn stackOrSkip() !bool {
    var flags: u32 = 0;
    _ = sa_std_ssh_supported(&flags);
    if (flags & 3 == 3) return true;
    // Hard-fail when the environment demands SSH coverage.
    if (std.c.getenv("SCI_REQUIRE_SSH")) |v| {
        if (v[0] == '1') return error.SshStackRequiredButMissing;
    }
    return false;
}

fn sh(cmd: []const u8) !void {
    const result = try sio.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ "sh", "-c", cmd },
        .max_output_bytes = 1024 * 1024,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.ShellFailed,
        else => return error.ShellFailed,
    }
}

fn freePort() !u16 {
    const rc = std.os.linux.socket(std.posix.AF.INET, std.os.linux.SOCK.STREAM | std.os.linux.SOCK.CLOEXEC, 0);
    if (@as(isize, @bitCast(rc)) < 0) return error.SocketFailed;
    const fd: i32 = @intCast(rc);
    defer lxClose(fd);
    var addr = std.posix.sockaddr.in{ .family = std.posix.AF.INET, .port = 0, .addr = @bitCast([4]u8{ 127, 0, 0, 1 }) };
    if (@as(isize, @bitCast(std.os.linux.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in)))) < 0) return error.BindFailed;
    var alen: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    if (@as(isize, @bitCast(std.os.linux.getsockname(fd, @ptrCast(&addr), &alen))) < 0) return error.GetsocknameFailed;
    return std.mem.bigToNative(u16, addr.port);
}

var test_dir_counter = std.atomic.Value(u64).init(0);

fn makeTestDir(buf: []u8) ![]const u8 {
    const n = test_dir_counter.fetchAdd(1, .monotonic);
    const dir = try std.fmt.bufPrint(buf, "/tmp/sa_ssh_test_{d}_{d}", .{ std.os.linux.getpid(), n });
    var cmd_buf: [1024]u8 = undefined;
    const cmd = try std.fmt.bufPrint(&cmd_buf, "rm -rf {s} && mkdir -p {s}", .{ dir, dir });
    try sh(cmd);
    return dir;
}

fn removeTestDir(dir: []const u8) void {
    var cmd_buf: [1024]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf, "rm -rf {s}", .{dir}) catch return;
    sh(cmd) catch {};
}

fn bufferText(handle: u64) []const u8 {
    const p = sa_std_ssh_buffer_data(handle) orelse return "";
    return p[0..@intCast(sa_std_ssh_buffer_len(handle))];
}

const ServerOutcome = struct {
    auth_user: [128]u8 = @splat(0),
    auth_user_len: usize = 0,
    command: [256]u8 = @splat(0),
    command_len: usize = 0,
    err: i32 = -999,
    pk_states: u32 = 0,
};

fn runTestServer(bind_handle: ?*anyopaque, expect_password: bool, expected_key_b64: []const u8, outcome: *ServerOutcome) void {
    var session: ?*anyopaque = null;
    if (sa_std_ssh_server_accept(bind_handle, &session) != OK) {
        outcome.err = -1;
        return;
    }
    defer _ = sa_std_ssh_server_session_close(session);
    // auth pump: pubkey clients do query (state 0) then signed (state 1)
    var authed = false;
    var rounds: usize = 0;
    while (!authed and rounds < 4) : (rounds += 1) {
        var kind: u32 = 0;
        var user_h: u64 = 0;
        var secret_h: u64 = 0;
        var state: i32 = 0;
        if (sa_std_ssh_server_auth_next(session, &kind, &user_h, &secret_h, &state) != OK) {
            outcome.err = -2;
            return;
        }
        const user_text = bufferText(user_h);
        @memcpy(outcome.auth_user[0..user_text.len], user_text);
        outcome.auth_user_len = user_text.len;
        if (expect_password) {
            if (kind == 1 and std.mem.eql(u8, bufferText(secret_h), "s3cret")) {
                _ = sa_std_ssh_server_auth_accept(session);
                authed = true;
            } else {
                _ = sa_std_ssh_server_auth_deny(session);
            }
        } else {
            // Pubkey mode verifies for real: only a kind-2 attempt
            // carrying the expected key blob counts. A password
            // attempt (kind 1) means the client fell back because the
            // publickey path failed -- record it as an error instead
            // of masking it as a successful auth. Error codes: -6
            // unexpected kind, -7 wrong user, -8 wrong key blob.
            if (kind != 2) {
                outcome.err = -6;
                _ = sa_std_ssh_server_auth_deny(session);
                return;
            }
            if (!std.mem.eql(u8, user_text, "root")) {
                outcome.err = -7;
                _ = sa_std_ssh_server_auth_deny(session);
                return;
            }
            if (!std.mem.eql(u8, bufferText(secret_h), expected_key_b64)) {
                outcome.err = -8;
                _ = sa_std_ssh_server_auth_deny(session);
                return;
            }
            if (state == 0) outcome.pk_states |= 1;
            if (state == 1) outcome.pk_states |= 2;
            _ = sa_std_ssh_server_auth_accept(session);
            if (state == 1) authed = true;
        }
        _ = sa_std_ssh_buffer_free(user_h);
        _ = sa_std_ssh_buffer_free(secret_h);
    }
    if (!authed) {
        outcome.err = -3;
        return;
    }
    var channel: ?*anyopaque = null;
    if (sa_std_ssh_server_channel_accept(session, &channel) != OK) {
        outcome.err = -4;
        return;
    }
    defer _ = sa_std_ssh_channel_close(channel);
    var kind: u32 = 0;
    var cmd_h: u64 = 0;
    if (sa_std_ssh_server_channel_exec(session, &kind, &cmd_h) != OK) {
        outcome.err = -5;
        return;
    }
    const cmd_text = bufferText(cmd_h);
    @memcpy(outcome.command[0..cmd_text.len], cmd_text);
    outcome.command_len = cmd_text.len;
    // build the greeting BEFORE freeing cmd_h (cmd_text borrows it)
    var greeting_buf: [320]u8 = undefined;
    const greeting = std.fmt.bufPrint(&greeting_buf, "pong:{s}", .{cmd_text}) catch "pong";
    _ = sa_std_ssh_buffer_free(cmd_h);
    var written: u64 = 0;
    _ = sa_std_ssh_channel_write(channel, 0, greeting.ptr, greeting.len, &written);
    // Pace the teardown like a real exec server (a real command takes
    // time between producing output and exiting): a data + exit + EOF
    // + CLOSE burst in one transport batch makes libssh2 clients drop
    // the payload (verified against libssh/libssh2 C probes).
    _ = std.os.linux.nanosleep(&.{ .sec = 0, .nsec = 150 * std.time.ns_per_ms }, null);
    _ = sa_std_ssh_channel_send_exit(channel, 3);
    outcome.err = 0;
}

test "ssh client vs system sshd: key auth, exec, sftp round trip" {
    if (!try stackOrSkip()) return;
    var dir_buf: [512]u8 = undefined;
    const dir = try makeTestDir(&dir_buf);
    defer removeTestDir(dir);

    var cmd_buf: [2048]u8 = undefined;
    const setup = try std.fmt.bufPrint(&cmd_buf,
        \\mkdir -p /run/sshd
        \\ssh-keygen -q -t ed25519 -N '' -f {s}/hostkey
        \\ssh-keygen -q -t ed25519 -N '' -f {s}/userkey
        \\cp {s}/userkey.pub {s}/authorized_keys
        \\chmod 600 {s}/authorized_keys
    , .{ dir, dir, dir, dir, dir });
    try sh(setup);

    const port = try freePort();
    var cfg_buf: [2048]u8 = undefined;
    const cfg = try std.fmt.bufPrint(&cfg_buf,
        \\Port {d}
        \\ListenAddress 127.0.0.1
        \\HostKey {s}/hostkey
        \\AuthorizedKeysFile {s}/authorized_keys
        \\PermitRootLogin yes
        \\PasswordAuthentication no
        \\PubkeyAuthentication yes
        \\StrictModes no
        \\UsePAM no
        \\Subsystem sftp internal-sftp
        \\PidFile {s}/sshd.pid
    , .{ port, dir, dir, dir });
    var cfgpath_buf: [1024]u8 = undefined;
    const cfgpath = try std.fmt.bufPrint(&cfgpath_buf, "{s}/sshd_config", .{dir});
    const cfg_file = try sio.cwd().createFile(cfgpath, .{});
    try cfg_file.writeAll(cfg);
    cfg_file.close();
    var start_buf: [1024]u8 = undefined;
    const start_cmd = try std.fmt.bufPrint(&start_buf, "/usr/sbin/sshd -f {s}", .{cfgpath});
    try sh(start_cmd);
    defer {
        var kill_buf: [1024]u8 = undefined;
        if (std.fmt.bufPrint(&kill_buf, "kill $(cat {s}/sshd.pid) 2>/dev/null; true", .{dir}) catch null) |c| sh(c) catch {};
    }

    // connect (retry briefly while sshd comes up)
    var session: ?*anyopaque = null;
    var attempt: usize = 0;
    while (attempt < 40) : (attempt += 1) {
        const host = "127.0.0.1";
        if (sa_std_ssh_client_connect(host.ptr, host.len, port, &session) == OK) break;
        _ = std.os.linux.nanosleep(&.{ .sec = 0, .nsec = 100 * std.time.ns_per_ms }, null);
    }
    try testing.expect(session != null);
    defer _ = sa_std_ssh_session_close(session);

    var fp_buf: [128]u8 = undefined;
    var fp_len: u64 = 0;
    try testing.expectEqual(OK, sa_std_ssh_hostkey_fingerprint(session, &fp_buf, fp_buf.len, &fp_len));
    try testing.expect(fp_len > 20);

    var keypath_buf: [1024]u8 = undefined;
    const keypath = try std.fmt.bufPrint(&keypath_buf, "{s}/userkey", .{dir});
    const user = "root";
    try testing.expectEqual(OK, sa_std_ssh_auth_keyfile(session, user.ptr, user.len, null, 0, keypath.ptr, keypath.len, null, 0));

    const command = "echo hello-from-sshd";
    var so: u64 = 0;
    var se: u64 = 0;
    var exit_code: i32 = -1;
    try testing.expectEqual(OK, sa_std_ssh_exec(session, command.ptr, command.len, &so, &se, &exit_code));
    defer _ = sa_std_ssh_buffer_free(so);
    defer _ = sa_std_ssh_buffer_free(se);
    try testing.expectEqual(@as(i32, 0), exit_code);
    try testing.expectEqualStrings("hello-from-sshd\n", bufferText(so));

    // sftp write + read back
    var remote_buf: [1024]u8 = undefined;
    const remote = try std.fmt.bufPrint(&remote_buf, "{s}/via-sftp.txt", .{dir});
    const payload = "sftp-payload-123";
    try testing.expectEqual(OK, sa_std_ssh_sftp_write(session, remote.ptr, remote.len, payload.ptr, payload.len));
    var back: u64 = 0;
    try testing.expectEqual(OK, sa_std_ssh_sftp_read(session, remote.ptr, remote.len, &back));
    defer _ = sa_std_ssh_buffer_free(back);
    try testing.expectEqualStrings(payload, bufferText(back));
    var size: u64 = 0;
    var is_dir: u32 = 0;
    try testing.expectEqual(OK, sa_std_ssh_sftp_stat(session, remote.ptr, remote.len, &size, &is_dir));
    try testing.expectEqual(@as(u64, payload.len), size);
    try testing.expectEqual(@as(u32, 0), is_dir);
}

test "ssh server vs system ssh client: pubkey auth + exec" {
    if (!try stackOrSkip()) return;
    var dir_buf: [512]u8 = undefined;
    const dir = try makeTestDir(&dir_buf);
    defer removeTestDir(dir);
    var cmd_buf: [2048]u8 = undefined;
    const setup = try std.fmt.bufPrint(&cmd_buf,
        \\ssh-keygen -q -t ed25519 -N '' -f {s}/hostkey
        \\ssh-keygen -q -t ed25519 -N '' -f {s}/userkey
    , .{ dir, dir });
    try sh(setup);

    const port = try freePort();
    var hk_buf: [1024]u8 = undefined;
    const hk = try std.fmt.bufPrint(&hk_buf, "{s}/hostkey", .{dir});
    const addr = "127.0.0.1";
    var bind_handle: ?*anyopaque = null;
    try testing.expectEqual(OK, sa_std_ssh_server_listen(addr.ptr, addr.len, port, hk.ptr, hk.len, &bind_handle));
    defer _ = sa_std_ssh_server_bind_close(bind_handle);

    // Expected secret for a publickey attempt: the base64 key blob
    // from userkey.pub (second whitespace-separated field).
    var cut_buf: [1024]u8 = undefined;
    const cut_cmd = try std.fmt.bufPrint(&cut_buf, "cut -d' ' -f2 {s}/userkey.pub", .{dir});
    const kres = try sio.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ "sh", "-c", cut_cmd },
        .max_output_bytes = 4096,
    });
    defer testing.allocator.free(kres.stdout);
    defer testing.allocator.free(kres.stderr);
    switch (kres.term) {
        .exited => |code| if (code != 0) return error.ShellFailed,
        else => return error.ShellFailed,
    }
    var exp_buf: [512]u8 = undefined;
    const blob = std.mem.trim(u8, kres.stdout, " \r\n");
    if (blob.len > exp_buf.len) return error.KeyBlobTooLong;
    @memcpy(exp_buf[0..blob.len], blob);
    const expected_b64 = exp_buf[0..blob.len];

    var outcome = ServerOutcome{};
    const thread = try std.Thread.spawn(.{}, runTestServer, .{ bind_handle, false, expected_b64, &outcome });
    defer thread.join();

    var ssh_buf: [2048]u8 = undefined;
    const ssh_cmd = try std.fmt.bufPrint(&ssh_buf, "ssh -i {s}/userkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p {d} root@127.0.0.1 'echo marker-cmd'", .{ dir, port });
    const result = try sio.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ "sh", "-c", ssh_cmd },
        .max_output_bytes = 1024 * 1024,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(@as(i32, 0), outcome.err);
    try testing.expectEqualStrings("root", outcome.auth_user[0..outcome.auth_user_len]);
    // Both publickey states must have been seen: query (0) then
    // signed (1); a run that only surfaces a password fallback can
    // never set either bit.
    try testing.expectEqual(@as(u32, 3), outcome.pk_states);
    try testing.expectEqualStrings("echo marker-cmd", outcome.command[0..outcome.command_len]);
    try testing.expectEqualStrings("pong:echo marker-cmd", result.stdout);
    switch (result.term) {
        .exited => |code| try testing.expectEqual(@as(u32, 3), code),
        else => return error.BadTerm,
    }
}

test "ssh client+server: password auth + exec round trip" {
    if (!try stackOrSkip()) return;
    var dir_buf: [512]u8 = undefined;
    const dir = try makeTestDir(&dir_buf);
    defer removeTestDir(dir);
    var cmd_buf: [1024]u8 = undefined;
    const setup = try std.fmt.bufPrint(&cmd_buf, "ssh-keygen -q -t ed25519 -N '' -f {s}/hostkey", .{dir});
    try sh(setup);

    const port = try freePort();
    var hk_buf: [1024]u8 = undefined;
    const hk = try std.fmt.bufPrint(&hk_buf, "{s}/hostkey", .{dir});
    const addr = "127.0.0.1";
    var bind_handle: ?*anyopaque = null;
    try testing.expectEqual(OK, sa_std_ssh_server_listen(addr.ptr, addr.len, port, hk.ptr, hk.len, &bind_handle));
    defer _ = sa_std_ssh_server_bind_close(bind_handle);

    var outcome = ServerOutcome{};
    const thread = try std.Thread.spawn(.{}, runTestServer, .{ bind_handle, true, "", &outcome });
    defer thread.join();

    var session: ?*anyopaque = null;
    try testing.expectEqual(OK, sa_std_ssh_client_connect(addr.ptr, addr.len, port, &session));
    defer _ = sa_std_ssh_session_close(session);
    const user = "alice";
    const pass = "s3cret";
    try testing.expectEqual(OK, sa_std_ssh_auth_password(session, user.ptr, user.len, pass.ptr, pass.len));
    const command = "ping";
    var so: u64 = 0;
    var se: u64 = 0;
    var exit_code: i32 = -1;
    try testing.expectEqual(OK, sa_std_ssh_exec(session, command.ptr, command.len, &so, &se, &exit_code));
    defer _ = sa_std_ssh_buffer_free(so);
    defer _ = sa_std_ssh_buffer_free(se);
    try testing.expectEqual(@as(i32, 0), outcome.err);
    try testing.expectEqualStrings("alice", outcome.auth_user[0..outcome.auth_user_len]);
    try testing.expectEqualStrings("pong:ping", bufferText(so));
    try testing.expectEqual(@as(i32, 3), exit_code);
}
