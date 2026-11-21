const std = @import("std");
const CLIENT_BASE_FLAGS = @import("sa_mysql_client.zig").CLIENT_BASE_FLAGS;
const CLIENT_CONNECT_WITH_DB = @import("sa_mysql_client.zig").CLIENT_CONNECT_WITH_DB;
const CLIENT_PLUGIN_AUTH = @import("sa_mysql_client.zig").CLIENT_PLUGIN_AUTH;
const CLIENT_PROTOCOL_41 = @import("sa_mysql_client.zig").CLIENT_PROTOCOL_41;
const CLIENT_SECURE_CONNECTION = @import("sa_mysql_client.zig").CLIENT_SECURE_CONNECTION;
const Conn = @import("sa_mysql_client.zig").Conn;
const MYSQL_CHARSET_UTF8MB4 = @import("sa_mysql_client.zig").MYSQL_CHARSET_UTF8MB4;
const SA_MYSQL_ERR_AUTH_PLUGIN = @import("sa_mysql_client.zig").SA_MYSQL_ERR_AUTH_PLUGIN;
const SA_MYSQL_ERR_FULL_AUTH = @import("sa_mysql_client.zig").SA_MYSQL_ERR_FULL_AUTH;
const SA_MYSQL_ERR_PROTOCOL = @import("sa_mysql_client.zig").SA_MYSQL_ERR_PROTOCOL;
const SA_MYSQL_ERR_SERVER = @import("sa_mysql_client.zig").SA_MYSQL_ERR_SERVER;
const SA_STD_ERR_NO_MEMORY = @import("sa_mysql_client.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_OK = @import("sa_mysql_client.zig").SA_STD_OK;
const alloc = @import("sa_mysql_client.zig").alloc;
const mapIoErr = @import("sa_mysql_client.zig").mapIoErr;
const readPacket = @import("sa_mysql_client.zig").readPacket;
const writePacket = @import("sa_mysql_client.zig").writePacket;

pub fn nativePasswordToken(password: []const u8, salt: []const u8, out: *[20]u8) usize {
    if (password.len == 0) return 0;
    var stage1: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(password, &stage1, .{});
    var stage2: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(&stage1, &stage2, .{});
    var h = std.crypto.hash.Sha1.init(.{});
    h.update(salt);
    h.update(&stage2);
    var mask: [20]u8 = undefined;
    h.final(&mask);
    for (0..20) |i| out[i] = stage1[i] ^ mask[i];
    return 20;
}

pub fn cachingSha2Token(password: []const u8, salt: []const u8, out: *[32]u8) usize {
    if (password.len == 0) return 0;
    const Sha256 = std.crypto.hash.sha2.Sha256;
    var stage1: [32]u8 = undefined;
    Sha256.hash(password, &stage1, .{});
    var stage2: [32]u8 = undefined;
    Sha256.hash(&stage1, &stage2, .{});
    var h = Sha256.init(.{});
    h.update(&stage2);
    h.update(salt);
    var mask: [32]u8 = undefined;
    h.final(&mask);
    for (0..32) |i| out[i] = stage1[i] ^ mask[i];
    return 32;
}

pub const AuthPlugin = enum { native_password, caching_sha2, unsupported };

pub fn authPluginFromName(name: []const u8) AuthPlugin {
    if (std.mem.eql(u8, name, "mysql_native_password")) return .native_password;
    if (std.mem.eql(u8, name, "caching_sha2_password")) return .caching_sha2;
    return .unsupported;
}

pub fn authToken(plugin: AuthPlugin, password: []const u8, salt: []const u8, out: *[32]u8) ?usize {
    switch (plugin) {
        .native_password => {
            var t: [20]u8 = undefined;
            const n = nativePasswordToken(password, salt, &t);
            @memcpy(out[0..n], t[0..n]);
            return n;
        },
        .caching_sha2 => return cachingSha2Token(password, salt, out),
        .unsupported => return null,
    }
}

pub const Handshake = struct {
    server_version: []const u8,
    connection_id: u32,
    salt: [20]u8,
    salt_len: usize,
    capabilities: u32,
    plugin_name: []const u8,
};

pub fn parseHandshake(payload: []const u8) ?Handshake {
    // HandshakeV10.
    if (payload.len < 1 or payload[0] == 0xFF) return null;
    var pos: usize = 1; // protocol version
    const ver_end = std.mem.indexOfScalarPos(u8, payload, pos, 0) orelse return null;
    const version = payload[pos..ver_end];
    pos = ver_end + 1;
    // conn_id(4) salt1(8) filler(1) cap_lo(2) charset(1) status(2)
    // cap_hi(2) auth_len(1) reserved(10) = 31 fixed bytes must follow.
    if (pos + 31 > payload.len) return null;
    const conn_id = std.mem.readInt(u32, payload[pos..][0..4], .little);
    pos += 4;
    var salt: [20]u8 = @splat(0);
    @memcpy(salt[0..8], payload[pos..][0..8]);
    var salt_len: usize = 8;
    pos += 8;
    pos += 1; // filler
    const cap_lo = std.mem.readInt(u16, payload[pos..][0..2], .little);
    pos += 2;
    var caps: u32 = cap_lo;
    pos += 1; // charset
    pos += 2; // status flags
    const cap_hi = std.mem.readInt(u16, payload[pos..][0..2], .little);
    pos += 2;
    caps |= @as(u32, cap_hi) << 16;
    const auth_data_len: usize = payload[pos];
    pos += 1;
    pos += 10; // reserved
    const part2_len: usize = if (caps & CLIENT_SECURE_CONNECTION != 0)
        @max(13, if (auth_data_len > 8) auth_data_len - 8 else 0)
    else
        0;
    if (pos + part2_len > payload.len) return null;
    const copy2 = @min(part2_len, 20 - salt_len);
    // The salt's second part is NUL-terminated inside its field; the
    // terminator is not part of the scramble input.
    var eff2 = copy2;
    if (eff2 > 0 and payload[pos + eff2 - 1] == 0) eff2 -= 1;
    @memcpy(salt[salt_len..][0..eff2], payload[pos..][0..eff2]);
    salt_len += eff2;
    pos += part2_len;
    var plugin_name: []const u8 = "mysql_native_password";
    if (caps & CLIENT_PLUGIN_AUTH != 0 and pos < payload.len) {
        const end = std.mem.indexOfScalarPos(u8, payload, pos, 0) orelse payload.len;
        plugin_name = payload[pos..end];
    }
    return .{
        .server_version = version,
        .connection_id = conn_id,
        .salt = salt,
        .salt_len = salt_len,
        .capabilities = caps,
        .plugin_name = plugin_name,
    };
}

pub fn runAuth(conn: *Conn, hs: Handshake, user: []const u8, password: []const u8, database: []const u8) i32 {
    var plugin = authPluginFromName(hs.plugin_name);
    if (plugin == .unsupported) return SA_MYSQL_ERR_AUTH_PLUGIN;
    var salt_buf: [20]u8 = hs.salt;
    var salt: []const u8 = salt_buf[0..hs.salt_len];

    var caps = CLIENT_BASE_FLAGS & hs.capabilities;
    caps |= CLIENT_PROTOCOL_41 | CLIENT_SECURE_CONNECTION | CLIENT_PLUGIN_AUTH;
    if (database.len > 0) caps |= CLIENT_CONNECT_WITH_DB;

    var token_buf: [32]u8 = undefined;
    const token_len = authToken(plugin, password, salt, &token_buf) orelse
        return SA_MYSQL_ERR_AUTH_PLUGIN;

    var pkt: std.ArrayList(u8) = .empty;
    defer pkt.deinit(alloc);
    {
        var fixed: [4 + 4 + 1 + 23]u8 = undefined;
        std.mem.writeInt(u32, fixed[0..4], caps, .little);
        std.mem.writeInt(u32, fixed[4..8], 0, .little); // max packet size: server default
        fixed[8] = MYSQL_CHARSET_UTF8MB4;
        @memset(fixed[9..32], 0);
        pkt.appendSlice(alloc, &fixed) catch return SA_STD_ERR_NO_MEMORY;
        pkt.appendSlice(alloc, user) catch return SA_STD_ERR_NO_MEMORY;
        pkt.append(alloc, 0) catch return SA_STD_ERR_NO_MEMORY;
        // Auth response: 1-byte length (CLIENT_PLUGIN_AUTH_LENENC_CLIENT_DATA
        // is not negotiated).
        pkt.append(alloc, @intCast(token_len)) catch return SA_STD_ERR_NO_MEMORY;
        pkt.appendSlice(alloc, token_buf[0..token_len]) catch return SA_STD_ERR_NO_MEMORY;
        if (database.len > 0) {
            pkt.appendSlice(alloc, database) catch return SA_STD_ERR_NO_MEMORY;
            pkt.append(alloc, 0) catch return SA_STD_ERR_NO_MEMORY;
        }
    }
    // Plugin name (NUL-terminated).
    const plugin_name_str: []const u8 = switch (plugin) {
        .native_password => "mysql_native_password",
        .caching_sha2 => "caching_sha2_password",
        .unsupported => unreachable,
    };
    pkt.appendSlice(alloc, plugin_name_str) catch return SA_STD_ERR_NO_MEMORY;
    pkt.append(alloc, 0) catch return SA_STD_ERR_NO_MEMORY;

    writePacket(conn, pkt.items) catch |e| return mapIoErr(e);

    // Auth conversation.
    while (true) {
        const resp = readPacket(conn) catch |e| return mapIoErr(e);
        if (resp.len == 0) {
            conn.markDead();
            return SA_MYSQL_ERR_PROTOCOL;
        }
        switch (resp[0]) {
            0x00 => return SA_STD_OK, // OK packet: authenticated
            0xFF => {
                conn.recordServerError(resp);
                return SA_MYSQL_ERR_SERVER;
            },
            0xFE => {
                // Auth switch request: plugin name (NUL-terminated),
                // then the new salt (trailing NUL not included).
                const name_end = std.mem.indexOfScalarPos(u8, resp, 1, 0) orelse {
                    conn.markDead();
                    return SA_MYSQL_ERR_PROTOCOL;
                };
                plugin = authPluginFromName(resp[1..name_end]);
                if (plugin == .unsupported) return SA_MYSQL_ERR_AUTH_PLUGIN;
                var new_salt = resp[name_end + 1 ..];
                if (new_salt.len > 0 and new_salt[new_salt.len - 1] == 0)
                    new_salt = new_salt[0 .. new_salt.len - 1];
                if (new_salt.len > salt_buf.len) {
                    conn.markDead();
                    return SA_MYSQL_ERR_PROTOCOL;
                }
                @memcpy(salt_buf[0..new_salt.len], new_salt);
                salt = salt_buf[0..new_salt.len];
                const tl = authToken(plugin, password, salt, &token_buf) orelse
                    return SA_MYSQL_ERR_AUTH_PLUGIN;
                writePacket(conn, token_buf[0..tl]) catch |e| return mapIoErr(e);
            },
            0x01 => {
                // AuthMoreData (caching_sha2_password conversation).
                if (plugin != .caching_sha2 or resp.len < 2) {
                    conn.markDead();
                    return SA_MYSQL_ERR_PROTOCOL;
                }
                switch (resp[1]) {
                    0x03 => {
                        // Fast auth succeeded; the OK packet follows.
                        continue;
                    },
                    0x04 => {
                        // Full auth: requires TLS (clear password) or
                        // RSA encryption. Neither is available in v1;
                        // refuse explicitly and hang up.
                        conn.markDead();
                        return SA_MYSQL_ERR_FULL_AUTH;
                    },
                    else => {
                        conn.markDead();
                        return SA_MYSQL_ERR_PROTOCOL;
                    },
                }
            },
            else => {
                conn.markDead();
                return SA_MYSQL_ERR_PROTOCOL;
            },
        }
    }
}
