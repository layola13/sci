const std = @import("std");
const ALLOC = @import("sa_pg.zig").ALLOC;
const Conn = @import("sa_pg.zig").Conn;
const Field = @import("sa_pg.zig").Field;
const PgErr = @import("sa_pg.zig").PgErr;
const freeSlice = @import("sa_pg.zig").freeSlice;

pub fn writeAll(conn: *Conn, bytes: []const u8) PgErr!void {
    conn.net_writer.interface.writeAll(bytes) catch return error.Io;
}

pub fn flushWrites(conn: *Conn) PgErr!void {
    conn.net_writer.interface.flush() catch return error.Io;
}

pub fn readExact(conn: *Conn, out: []u8) PgErr!void {
    var off: usize = 0;
    while (off < out.len) {
        const n = conn.net_reader.interface.readSliceShort(out[off..]) catch return error.Io;
        if (n == 0) return error.Io; // orderly shutdown mid-conversation
        off += n;
    }
}

pub const Message = struct {
    kind: u8,
    body: []u8, // owned by caller

    pub fn deinit(self: *const Message) void {
        ALLOC.free(self.body);
    }
};

pub fn readMessage(conn: *Conn) PgErr!Message {
    var head: [5]u8 = undefined;
    try readExact(conn, &head);
    const len = std.mem.readInt(u32, head[1..5], .big);
    // Length counts itself but not the type byte; 4 is an empty body.
    // Cap at 1 GiB: anything beyond that is a corrupt stream.
    if (len < 4 or len > (1 << 30)) {
        conn.dead = true;
        return error.Protocol;
    }
    const body = ALLOC.alloc(u8, len - 4) catch return error.OutOfMemory;
    errdefer ALLOC.free(body);
    try readExact(conn, body);
    return .{ .kind = head[0], .body = body };
}

pub const MsgBuilder = struct {
    buf: std.array_list.Managed(u8) = .init(ALLOC),

    pub fn deinit(self: *MsgBuilder) void {
        self.buf.deinit();
    }
    pub fn u8v(self: *MsgBuilder, v: u8) PgErr!void {
        self.buf.append(v) catch return error.OutOfMemory;
    }
    pub fn u16v(self: *MsgBuilder, v: u16) PgErr!void {
        var b: [2]u8 = undefined;
        std.mem.writeInt(u16, &b, v, .big);
        self.buf.appendSlice(&b) catch return error.OutOfMemory;
    }
    pub fn u32v(self: *MsgBuilder, v: u32) PgErr!void {
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, v, .big);
        self.buf.appendSlice(&b) catch return error.OutOfMemory;
    }
    pub fn bytes(self: *MsgBuilder, v: []const u8) PgErr!void {
        self.buf.appendSlice(v) catch return error.OutOfMemory;
    }
    pub fn cstr(self: *MsgBuilder, v: []const u8) PgErr!void {
        try self.bytes(v);
        try self.u8v(0);
    }
    /// Frame the accumulated body with a type byte + length and send.
    pub fn send(self: *MsgBuilder, conn: *Conn, kind: u8) PgErr!void {
        var head: [5]u8 = undefined;
        head[0] = kind;
        std.mem.writeInt(u32, head[1..5], @intCast(self.buf.items.len + 4), .big);
        try writeAll(conn, &head);
        try writeAll(conn, self.buf.items);
        try flushWrites(conn);
    }
    /// Startup-family messages carry no type byte.
    pub fn sendUntyped(self: *MsgBuilder, conn: *Conn) PgErr!void {
        var head: [4]u8 = undefined;
        std.mem.writeInt(u32, &head, @intCast(self.buf.items.len + 4), .big);
        try writeAll(conn, &head);
        try writeAll(conn, self.buf.items);
        try flushWrites(conn);
    }
};

pub const BodyReader = struct {
    body: []const u8,
    pos: usize = 0,

    pub fn u8v(self: *BodyReader) PgErr!u8 {
        if (self.pos + 1 > self.body.len) return error.Protocol;
        defer self.pos += 1;
        return self.body[self.pos];
    }
    pub fn u16v(self: *BodyReader) PgErr!u16 {
        if (self.pos + 2 > self.body.len) return error.Protocol;
        defer self.pos += 2;
        return std.mem.readInt(u16, self.body[self.pos..][0..2], .big);
    }
    pub fn u32v(self: *BodyReader) PgErr!u32 {
        if (self.pos + 4 > self.body.len) return error.Protocol;
        defer self.pos += 4;
        return std.mem.readInt(u32, self.body[self.pos..][0..4], .big);
    }
    pub fn i32v(self: *BodyReader) PgErr!i32 {
        return @bitCast(try self.u32v());
    }
    pub fn bytes(self: *BodyReader, n: usize) PgErr![]const u8 {
        if (self.pos + n > self.body.len) return error.Protocol;
        defer self.pos += n;
        return self.body[self.pos..][0..n];
    }
    pub fn cstr(self: *BodyReader) PgErr![]const u8 {
        const start = self.pos;
        while (self.pos < self.body.len) : (self.pos += 1) {
            if (self.body[self.pos] == 0) {
                defer self.pos += 1;
                return self.body[start..self.pos];
            }
        }
        return error.Protocol;
    }
};

pub const ErrorFields = struct {
    severity: []const u8 = "",
    code: []const u8 = "",
    message: []const u8 = "",
    detail: []const u8 = "",
};

pub fn parseErrorBody(body: []const u8) ErrorFields {
    var out = ErrorFields{};
    var r = BodyReader{ .body = body };
    while (true) {
        const kind = r.u8v() catch return out;
        if (kind == 0) return out;
        const value = r.cstr() catch return out;
        switch (kind) {
            // 'S' is the localized severity, 'V' the invariant one;
            // V wins regardless of field order.
            'S' => {
                if (out.severity.len == 0) out.severity = value;
            },
            'V' => out.severity = value,
            'C' => out.code = value,
            'M' => out.message = value,
            'D' => out.detail = value,
            else => {},
        }
    }
}

pub fn parseRowDescription(body: []const u8, fields: *std.array_list.Managed(Field)) PgErr!void {
    var r = BodyReader{ .body = body };
    const count = try r.u16v();
    var i: u16 = 0;
    while (i < count) : (i += 1) {
        const name = try r.cstr();
        _ = try r.u32v(); // table oid
        _ = try r.u16v(); // column attribute number
        const type_oid = try r.u32v();
        _ = try r.u16v(); // type length
        _ = try r.i32v(); // type modifier
        _ = try r.u16v(); // format code (text in v1)
        fields.append(.{ .name = ALLOC.dupe(u8, name) catch return error.OutOfMemory, .type_oid = type_oid }) catch return error.OutOfMemory;
    }
}

pub fn parseDataRow(body: []const u8, row: *std.array_list.Managed(?[]u8)) PgErr!void {
    var r = BodyReader{ .body = body };
    const count = try r.u16v();
    var i: u16 = 0;
    while (i < count) : (i += 1) {
        const len = try r.i32v();
        if (len == -1) {
            row.append(null) catch return error.OutOfMemory;
        } else if (len < 0) {
            return error.Protocol;
        } else {
            const raw = try r.bytes(@intCast(len));
            row.append(ALLOC.dupe(u8, raw) catch return error.OutOfMemory) catch return error.OutOfMemory;
        }
    }
}

pub fn cleanTag(body: []const u8) []const u8 {
    if (body.len > 0 and body[body.len - 1] == 0) return body[0 .. body.len - 1];
    return body;
}

pub fn parseTagCount(tag: []const u8) ?u64 {
    var end = tag.len;
    while (end > 0 and tag[end - 1] == ' ') end -= 1;
    if (end == 0) return null;
    var start = end;
    while (start > 0 and std.ascii.isDigit(tag[start - 1])) start -= 1;
    if (start == end) return null;
    if (start > 0 and tag[start - 1] != ' ') return null;
    return std.fmt.parseInt(u64, tag[start..end], 10) catch null;
}

pub fn drainUntilReady(conn: *Conn, collect: bool, desc_fields: ?*std.array_list.Managed(Field)) PgErr!void {
    var saw_error = false;
    while (true) {
        const msg = try readMessage(conn);
        defer msg.deinit();
        switch (msg.kind) {
            'Z' => {
                if (msg.body.len == 1) conn.txn_status = msg.body[0];
                if (saw_error) return error.ServerError;
                return;
            },
            'T' => {
                if (collect) {
                    conn.result.clear();
                    try parseRowDescription(msg.body, &conn.result.fields);
                    conn.has_result = true;
                } else if (desc_fields) |df| {
                    try parseRowDescription(msg.body, df);
                }
            },
            'D' => {
                if (collect) {
                    var row: std.array_list.Managed(?[]u8) = .init(ALLOC);
                    errdefer {
                        for (row.items) |c| if (c) |b| ALLOC.free(b);
                        row.deinit();
                    }
                    try parseDataRow(msg.body, &row);
                    conn.result.rows.append(row) catch return error.OutOfMemory;
                }
            },
            'C' => {
                if (collect) {
                    freeSlice(conn.result.tag);
                    conn.result.tag = ALLOC.dupe(u8, cleanTag(msg.body)) catch return error.OutOfMemory;
                    conn.has_result = true;
                }
            },
            'E' => {
                conn.setError(parseErrorBody(msg.body));
                saw_error = true;
            },
            'I' => { // EmptyQueryResponse
                if (collect) {
                    conn.result.clear();
                    conn.has_result = true;
                }
            },
            'n', 't', '1', '2', 's' => {
                // NoData / ParameterDescription / ParseComplete /
                // BindComplete / PortalSuspended: statement machinery
                // messages the caller accounts for. PortalSuspended
                // cannot occur: Execute always asks for all rows.
            },
            'S' => { // ParameterStatus can arrive at any time
                var r = BodyReader{ .body = msg.body };
                const name = r.cstr() catch continue;
                const value = r.cstr() catch continue;
                if (std.mem.eql(u8, name, "server_version")) {
                    freeSlice(conn.server_version);
                    conn.server_version = ALLOC.dupe(u8, value) catch return error.OutOfMemory;
                }
            },
            'N', 'A', 'K' => {}, // notices, notifications, key data
            else => {
                conn.dead = true;
                return error.Protocol;
            },
        }
    }
}
