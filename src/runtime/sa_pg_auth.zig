const std = @import("std");
const ALLOC = @import("sa_pg.zig").ALLOC;
const BodyReader = @import("sa_pg.zig").BodyReader;
const Conn = @import("sa_pg.zig").Conn;
const MsgBuilder = @import("sa_pg.zig").MsgBuilder;
const PgErr = @import("sa_pg.zig").PgErr;
const freeSlice = @import("sa_pg.zig").freeSlice;
const parseErrorBody = @import("sa_pg.zig").parseErrorBody;
const readMessage = @import("sa_pg.zig").readMessage;
const sio = @import("sa_pg.zig").sio;

pub fn hexLower(bytes: []const u8, out: []u8) void {
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 0x0f];
    }
}

pub fn md5AuthResponse(user: []const u8, password: []const u8, salt: *const [4]u8, out: *[35]u8) void {
    var inner: [16]u8 = undefined;
    {
        var h = std.crypto.hash.Md5.init(.{});
        h.update(password);
        h.update(user);
        h.final(&inner);
    }
    var inner_hex: [32]u8 = undefined;
    hexLower(&inner, &inner_hex);
    var outer: [16]u8 = undefined;
    {
        var h = std.crypto.hash.Md5.init(.{});
        h.update(&inner_hex);
        h.update(salt);
        h.final(&outer);
    }
    @memcpy(out[0..3], "md5");
    hexLower(&outer, out[3..35]);
}

pub const HmacSha256 = std.crypto.auth.hmac.Hmac(std.crypto.hash.sha2.Sha256);

pub const ScramState = struct {
    client_nonce: []u8,
    client_first_bare: []u8,
    salted_password: [32]u8 = undefined,

    pub fn deinit(self: *ScramState) void {
        freeSlice(self.client_nonce);
        freeSlice(self.client_first_bare);
    }
};

pub fn saslEscape(name: []const u8, out: *std.array_list.Managed(u8)) PgErr!void {
    for (name) |c| {
        switch (c) {
            '=' => out.appendSlice("=3D") catch return error.OutOfMemory,
            ',' => out.appendSlice("=2C") catch return error.OutOfMemory,
            else => out.append(c) catch return error.OutOfMemory,
        }
    }
}

pub fn scramClientFirst(user: []const u8, state: *ScramState) PgErr![]u8 {
    var nonce_raw: [18]u8 = undefined;
    sio.io().randomSecure(&nonce_raw) catch return error.Io;
    var nonce_buf: [24]u8 = undefined;
    const nonce = std.base64.standard.Encoder.encode(&nonce_buf, &nonce_raw);
    state.client_nonce = ALLOC.dupe(u8, nonce) catch return error.OutOfMemory;

    var bare: std.array_list.Managed(u8) = .init(ALLOC);
    errdefer bare.deinit();
    bare.appendSlice("n=") catch return error.OutOfMemory;
    try saslEscape(user, &bare);
    bare.appendSlice(",r=") catch return error.OutOfMemory;
    bare.appendSlice(nonce) catch return error.OutOfMemory;
    state.client_first_bare = bare.toOwnedSlice() catch return error.OutOfMemory;

    var first: std.array_list.Managed(u8) = .init(ALLOC);
    errdefer first.deinit();
    first.appendSlice("n,,") catch return error.OutOfMemory;
    first.appendSlice(state.client_first_bare) catch return error.OutOfMemory;
    return first.toOwnedSlice() catch error.OutOfMemory;
}

pub fn scramClientFinal(state: *ScramState, password: []const u8, server_first: []const u8, expected_server_sig: *[32]u8) PgErr![]u8 {
    var server_nonce: []const u8 = "";
    var salt_b64: []const u8 = "";
    var iterations: u32 = 0;
    var it = std.mem.splitScalar(u8, server_first, ',');
    while (it.next()) |part| {
        if (part.len < 2 or part[1] != '=') return error.Protocol;
        switch (part[0]) {
            'r' => server_nonce = part[2..],
            's' => salt_b64 = part[2..],
            'i' => iterations = std.fmt.parseInt(u32, part[2..], 10) catch return error.Protocol,
            'e' => {
                return error.ServerError; // server sent a SASL error extension
            },
            else => return error.Protocol,
        }
    }
    if (server_nonce.len == 0 or salt_b64.len == 0 or iterations == 0) return error.Protocol;
    if (!std.mem.startsWith(u8, server_nonce, state.client_nonce)) return error.Protocol;
    if (iterations > 1_000_000) return error.Protocol; // sanity bound vs hostile servers

    var salt: [64]u8 = undefined;
    const salt_len = std.base64.standard.Decoder.calcSizeForSlice(salt_b64) catch return error.Protocol;
    if (salt_len > salt.len) return error.Protocol;
    std.base64.standard.Decoder.decode(salt[0..salt_len], salt_b64) catch return error.Protocol;

    std.crypto.pwhash.pbkdf2(&state.salted_password, password, salt[0..salt_len], iterations, HmacSha256) catch return error.Protocol;

    var client_key: [32]u8 = undefined;
    HmacSha256.create(&client_key, "Client Key", &state.salted_password);
    var stored_key: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&client_key, &stored_key, .{});

    // client-final-without-proof = "c=biws,r=<server nonce>"
    var without_proof: std.array_list.Managed(u8) = .init(ALLOC);
    defer without_proof.deinit();
    without_proof.appendSlice("c=biws,r=") catch return error.OutOfMemory;
    without_proof.appendSlice(server_nonce) catch return error.OutOfMemory;

    var auth_message: std.array_list.Managed(u8) = .init(ALLOC);
    defer auth_message.deinit();
    auth_message.appendSlice(state.client_first_bare) catch return error.OutOfMemory;
    auth_message.append(',') catch return error.OutOfMemory;
    auth_message.appendSlice(server_first) catch return error.OutOfMemory;
    auth_message.append(',') catch return error.OutOfMemory;
    auth_message.appendSlice(without_proof.items) catch return error.OutOfMemory;

    var client_signature: [32]u8 = undefined;
    HmacSha256.create(&client_signature, auth_message.items, &stored_key);
    var proof: [32]u8 = undefined;
    for (0..32) |i| proof[i] = client_key[i] ^ client_signature[i];

    var server_key: [32]u8 = undefined;
    HmacSha256.create(&server_key, "Server Key", &state.salted_password);
    HmacSha256.create(expected_server_sig, auth_message.items, &server_key);

    var proof_b64: [44]u8 = undefined;
    const proof_enc = std.base64.standard.Encoder.encode(&proof_b64, &proof);
    var final_msg: std.array_list.Managed(u8) = .init(ALLOC);
    errdefer final_msg.deinit();
    final_msg.appendSlice(without_proof.items) catch return error.OutOfMemory;
    final_msg.appendSlice(",p=") catch return error.OutOfMemory;
    final_msg.appendSlice(proof_enc) catch return error.OutOfMemory;
    return final_msg.toOwnedSlice() catch error.OutOfMemory;
}

pub fn scramVerifyServerFinal(expected: *const [32]u8, server_final: []const u8) PgErr!void {
    var it = std.mem.splitScalar(u8, server_final, ',');
    while (it.next()) |part| {
        if (part.len < 2 or part[1] != '=') return error.Protocol;
        switch (part[0]) {
            'v' => {
                var got: [32]u8 = undefined;
                const n = std.base64.standard.Decoder.calcSizeForSlice(part[2..]) catch return error.Protocol;
                if (n != 32) return error.Protocol;
                std.base64.standard.Decoder.decode(&got, part[2..]) catch return error.Protocol;
                if (!timingSafeEql32(&got, expected)) return error.Protocol;
                return;
            },
            'e' => return error.ServerError,
            else => return error.Protocol,
        }
    }
    return error.Protocol;
}

pub fn timingSafeEql32(a: *const [32]u8, b: *const [32]u8) bool {
    var diff: u8 = 0;
    for (a.*, b.*) |x, y| diff |= x ^ y;
    return diff == 0;
}

pub fn sendPassword(conn: *Conn, password: []const u8) PgErr!void {
    var b = MsgBuilder{};
    defer b.deinit();
    try b.cstr(password);
    try b.send(conn, 'p');
}

pub fn authenticate(conn: *Conn, user: []const u8, password: []const u8) PgErr!void {
    var scram: ?ScramState = null;
    defer {
        if (scram) |*s| s.deinit();
    }
    var expected_sig: [32]u8 = undefined;
    var have_expected_sig = false;

    while (true) {
        const msg = try readMessage(conn);
        defer msg.deinit();
        switch (msg.kind) {
            'R' => {
                var r = BodyReader{ .body = msg.body };
                const code = try r.u32v();
                switch (code) {
                    0 => return, // AuthenticationOk; startup continues in caller
                    3 => try sendPassword(conn, password),
                    5 => {
                        const salt = try r.bytes(4);
                        var salt4: [4]u8 = undefined;
                        @memcpy(&salt4, salt[0..4]);
                        var resp: [35]u8 = undefined;
                        md5AuthResponse(user, password, &salt4, &resp);
                        try sendPassword(conn, &resp);
                    },
                    10 => { // SASL: mechanism name list, empty string ends it
                        var offered_scram = false;
                        while (true) {
                            const name = try r.cstr();
                            if (name.len == 0) break;
                            if (std.mem.eql(u8, name, "SCRAM-SHA-256")) offered_scram = true;
                        }
                        if (!offered_scram) return error.Unsupported;
                        scram = .{ .client_nonce = "", .client_first_bare = "" };
                        const first = try scramClientFirst(user, &scram.?);
                        defer ALLOC.free(first);
                        var b = MsgBuilder{};
                        defer b.deinit();
                        try b.cstr("SCRAM-SHA-256");
                        try b.u32v(@intCast(first.len));
                        try b.bytes(first);
                        try b.send(conn, 'p');
                    },
                    11 => { // SASLContinue: server-first (body after the auth type code)
                        if (scram == null) return error.Protocol;
                        const final_msg = try scramClientFinal(&scram.?, password, msg.body[r.pos..], &expected_sig);
                        defer ALLOC.free(final_msg);
                        have_expected_sig = true;
                        var b = MsgBuilder{};
                        defer b.deinit();
                        try b.bytes(final_msg);
                        try b.send(conn, 'p');
                    },
                    12 => { // SASLFinal: verify server signature, then 'R' 0 follows
                        if (!have_expected_sig) return error.Protocol;
                        try scramVerifyServerFinal(&expected_sig, msg.body[r.pos..]);
                    },
                    else => return error.Unsupported, // e.g. GSSAPI / SSPI / SCM credentials
                }
            },
            'E' => {
                conn.setError(parseErrorBody(msg.body));
                return error.ServerError;
            },
            'N' => {},
            else => return error.Protocol,
        }
    }
}
