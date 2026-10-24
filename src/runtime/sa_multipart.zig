//! sa_std multipart/form-data: parser + builder.
//!
//! Parser: pass the full body and its Content-Type header value (the
//! boundary is extracted from it; a bare boundary is also accepted).
//! Part bodies are borrowed slices into an owned copy of the body.
//! Builder: accumulates fields/files and finishes into a buffer
//! handle (multipart_buffer_data/_len/_free trio).
//! Status codes mirror sa_std.zig (0 ok, 1 invalid argument,
//! 2 invalid handle, 3 not found, 5 no memory, 9 truncated).

const std = @import("std");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_TRUNCATED: i32 = 9;

const MAX_BODY: usize = 512 * 1024 * 1024;

// ---------------- parser ----------------

const Part = struct {
    name: []const u8,
    filename: ?[]const u8,
    content_type: ?[]const u8,
    headers: []const u8, // raw header block, for generic lookup
    body: []const u8,
};

const Parsed = struct {
    allocator: std.mem.Allocator,
    owned_body: []u8,
    boundary: []u8,
    parts: []Part,

    fn deinit(self: *Parsed) void {
        self.allocator.free(self.owned_body);
        self.allocator.free(self.boundary);
        self.allocator.free(self.parts);
        self.allocator.destroy(self);
    }
};

var parsed_mu = std.Io.Mutex.init;
var parsed_map: std.AutoHashMapUnmanaged(u64, *Parsed) = .empty;
var parsed_next: u64 = 1;

fn registerParsed(p: *Parsed) !u64 {
    parsed_mu.lockUncancelable(sio.io());
    defer parsed_mu.unlock(sio.io());
    const h = parsed_next;
    parsed_next += 1;
    try parsed_map.put(std.heap.page_allocator, h, p);
    return h;
}

fn getParsed(handle: u64) ?*Parsed {
    parsed_mu.lockUncancelable(sio.io());
    defer parsed_mu.unlock(sio.io());
    return parsed_map.get(handle);
}

fn extractBoundary(content_type: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, content_type, "boundary=")) |i| {
        var rest = content_type[i + "boundary=".len..];
        rest = std.mem.trim(u8, rest, " \t");
        if (rest.len > 0 and rest[0] == '"') {
            const end = std.mem.indexOfScalarPos(u8, rest, 1, '"') orelse return null;
            return rest[1..end];
        }
        const end = std.mem.indexOfAny(u8, rest, "; \t\r\n") orelse rest.len;
        return rest[0..end];
    }
    // bare boundary (no parameters, no MIME type shape)
    if (std.mem.indexOf(u8, content_type, "/") == null and std.mem.indexOf(u8, content_type, ";") == null) {
        const t = std.mem.trim(u8, content_type, " \t\r\n");
        if (t.len > 0) return t;
    }
    return null;
}

fn dispositionParam(disposition: []const u8, param: []const u8) ?[]const u8 {
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, disposition, search_from, param)) |i| {
        // whole-token match only: "name" must not match inside "filename"
        if (i > 0 and disposition[i - 1] != ';' and disposition[i - 1] != ' ' and disposition[i - 1] != '\t') {
            search_from = i + param.len;
            continue;
        }
        var j = i + param.len;
        j = skipWs(disposition, j);
        if (j >= disposition.len or disposition[j] != '=') {
            search_from = i + param.len;
            continue;
        }
        j = skipWs(disposition, j + 1);
        if (j < disposition.len and disposition[j] == '"') {
            const end = std.mem.indexOfScalarPos(u8, disposition, j + 1, '"') orelse return null;
            return disposition[j + 1 .. end];
        }
        const end = std.mem.indexOfAnyPos(u8, disposition, j, "; \t") orelse disposition.len;
        return disposition[j..end];
    }
    return null;
}

fn skipWs(s: []const u8, start: usize) usize {
    var i = start;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) i += 1;
    return i;
}

fn headerValue(headers: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), name)) {
            return std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
    }
    return null;
}

pub export fn sa_std_multipart_parse(body: ?[*]const u8, body_len: u64, content_type: ?[*]const u8, content_type_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return ERR_INVALID;
    slot.* = 0;
    if (body_len > MAX_BODY) return ERR_INVALID;
    const body_ptr = body orelse return ERR_INVALID;
    const ct_ptr = content_type orelse return ERR_INVALID;
    const ct = ct_ptr[0..@intCast(content_type_len)];
    const boundary = extractBoundary(ct) orelse return ERR_INVALID;
    if (boundary.len == 0 or boundary.len > 200) return ERR_INVALID;

    const allocator = std.heap.page_allocator;
    const parsed = allocator.create(Parsed) catch return ERR_NOMEM;
    errdefer allocator.destroy(parsed);
    parsed.allocator = allocator;
    parsed.owned_body = allocator.dupe(u8, body_ptr[0..@intCast(body_len)]) catch return ERR_NOMEM;
    errdefer allocator.free(parsed.owned_body);
    parsed.boundary = allocator.dupe(u8, boundary) catch return ERR_NOMEM;
    errdefer allocator.free(parsed.boundary);

    var parts = std.array_list.Managed(Part).init(allocator);
    errdefer parts.deinit();

    // Delimiter: --boundary ; parts end at --boundary--
    var delim_buf: [212]u8 = undefined;
    const delim = std.fmt.bufPrint(&delim_buf, "--{s}", .{boundary}) catch return ERR_INVALID;
    const owned = parsed.owned_body;
    var cursor: usize = 0;
    // skip preamble up to the first delimiter
    cursor = (std.mem.indexOf(u8, owned, delim) orelse return ERR_INVALID) + delim.len;
    while (true) {
        // after a delimiter: "--" means the final boundary
        if (cursor + 2 <= owned.len and std.mem.eql(u8, owned[cursor..][0..2], "--")) break;
        // expect CRLF
        if (cursor + 2 <= owned.len and std.mem.eql(u8, owned[cursor..][0..2], "\r\n")) cursor += 2 else return ERR_INVALID;
        const headers_end = std.mem.indexOfPos(u8, owned, cursor, "\r\n\r\n") orelse return ERR_INVALID;
        const headers = owned[cursor..headers_end];
        const content_start = headers_end + 4;
        const next_delim = std.mem.indexOfPos(u8, owned, content_start, delim) orelse return ERR_INVALID;
        // part body runs to the CRLF immediately before the delimiter
        var content_end = next_delim;
        if (content_end >= content_start + 2 and std.mem.eql(u8, owned[content_end - 2 .. content_end], "\r\n")) content_end -= 2;
        const disposition = headerValue(headers, "content-disposition") orelse return ERR_INVALID;
        const name = dispositionParam(disposition, "name") orelse return ERR_INVALID;
        parts.append(.{
            .name = name,
            .filename = dispositionParam(disposition, "filename"),
            .content_type = headerValue(headers, "content-type"),
            .headers = headers,
            .body = owned[content_start..content_end],
        }) catch return ERR_NOMEM;
        cursor = next_delim + delim.len;
    }
    parsed.parts = parts.toOwnedSlice() catch return ERR_NOMEM;
    slot.* = registerParsed(parsed) catch {
        parsed.deinit();
        return ERR_NOMEM;
    };
    return OK;
}

pub export fn sa_std_multipart_free(handle: u64) i32 {
    parsed_mu.lockUncancelable(sio.io());
    const kv = parsed_map.fetchRemove(handle);
    parsed_mu.unlock(sio.io());
    const p = (kv orelse return ERR_HANDLE).value;
    p.deinit();
    return OK;
}

pub export fn sa_std_multipart_count(handle: u64) u64 {
    const p = getParsed(handle) orelse return 0;
    return p.parts.len;
}

fn partAt(handle: u64, index: u64) ?*const Part {
    const p = getParsed(handle) orelse return null;
    if (index >= p.parts.len) return null;
    return &p.parts[@intCast(index)];
}

fn writeOut(value: []const u8, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return ERR_INVALID;
    len_slot.* = value.len;
    if (cap < value.len) return ERR_TRUNCATED;
    const buf = out orelse return ERR_INVALID;
    if (value.len > 0) @memcpy(buf[0..value.len], value);
    return OK;
}

pub export fn sa_std_multipart_part_name(handle: u64, index: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const part = partAt(handle, index) orelse return ERR_NOT_FOUND;
    return writeOut(part.name, out, cap, out_len);
}

/// Returns OK with out_len set, or a positive "absent" code 100 when
/// the part has no filename (plain form field).
pub export fn sa_std_multipart_part_filename(handle: u64, index: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const part = partAt(handle, index) orelse return ERR_NOT_FOUND;
    const filename = part.filename orelse {
        if (out_len) |l| l.* = 0;
        return 100;
    };
    return writeOut(filename, out, cap, out_len);
}

pub export fn sa_std_multipart_part_content_type(handle: u64, index: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const part = partAt(handle, index) orelse return ERR_NOT_FOUND;
    const ct = part.content_type orelse {
        if (out_len) |l| l.* = 0;
        return 100;
    };
    return writeOut(ct, out, cap, out_len);
}

pub export fn sa_std_multipart_part_header(handle: u64, index: u64, name: ?[*]const u8, name_len: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const part = partAt(handle, index) orelse return ERR_NOT_FOUND;
    const name_ptr = name orelse return ERR_INVALID;
    const value = headerValue(part.headers, name_ptr[0..@intCast(name_len)]) orelse return ERR_NOT_FOUND;
    return writeOut(value, out, cap, out_len);
}

pub export fn sa_std_multipart_part_body(handle: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const part = partAt(handle, index) orelse return ERR_NOT_FOUND;
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = part.body.ptr;
    len_slot.* = part.body.len;
    return OK;
}

// ---------------- builder ----------------

const Builder = struct {
    allocator: std.mem.Allocator,
    boundary: []u8,
    body: std.array_list.Managed(u8),
    finished: bool = false,

    fn deinit(self: *Builder) void {
        self.allocator.free(self.boundary);
        self.body.deinit();
        self.allocator.destroy(self);
    }
};

var builder_mu = std.Io.Mutex.init;
var builder_map: std.AutoHashMapUnmanaged(u64, *Builder) = .empty;
var builder_next: u64 = 1;

var boundary_counter = std.atomic.Value(u64).init(0);

pub export fn sa_std_multipart_builder_new(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return ERR_INVALID;
    slot.* = 0;
    const allocator = std.heap.page_allocator;
    const b = allocator.create(Builder) catch return ERR_NOMEM;
    errdefer allocator.destroy(b);
    const n = boundary_counter.fetchAdd(1, .monotonic);
    const pid = std.os.linux.getpid();
    b.boundary = std.fmt.allocPrint(allocator, "----sa-std-multipart-{d}-{d}", .{ pid, n }) catch return ERR_NOMEM;
    b.allocator = allocator;
    b.body = std.array_list.Managed(u8).init(allocator);
    b.finished = false;
    builder_mu.lockUncancelable(sio.io());
    defer builder_mu.unlock(sio.io());
    const h = builder_next;
    builder_next += 1;
    builder_map.put(allocator, h, b) catch {
        b.deinit();
        return ERR_NOMEM;
    };
    slot.* = h;
    return OK;
}

fn getBuilder(handle: u64) ?*Builder {
    builder_mu.lockUncancelable(sio.io());
    defer builder_mu.unlock(sio.io());
    return builder_map.get(handle);
}

pub export fn sa_std_multipart_builder_free(handle: u64) i32 {
    builder_mu.lockUncancelable(sio.io());
    const kv = builder_map.fetchRemove(handle);
    builder_mu.unlock(sio.io());
    const b = (kv orelse return ERR_HANDLE).value;
    b.deinit();
    return OK;
}

fn escapeQuoted(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    for (value) |c| {
        if (c == '"' or c == '\\') try out.append('\\');
        if (c == '\r' or c == '\n') continue;
        try out.append(c);
    }
    return out.toOwnedSlice();
}

pub export fn sa_std_multipart_builder_add_field(handle: u64, name: ?[*]const u8, name_len: u64, value: ?[*]const u8, value_len: u64) i32 {
    const b = getBuilder(handle) orelse return ERR_HANDLE;
    if (b.finished) return ERR_INVALID;
    const name_ptr = name orelse return ERR_INVALID;
    const value_ptr = value orelse return ERR_INVALID;
    const esc = escapeQuoted(b.allocator, name_ptr[0..@intCast(name_len)]) catch return ERR_NOMEM;
    defer b.allocator.free(esc);
    b.body.appendSlice("--") catch return ERR_NOMEM;
    b.body.appendSlice(b.boundary) catch return ERR_NOMEM;
    b.body.appendSlice("\r\nContent-Disposition: form-data; name=\"") catch return ERR_NOMEM;
    b.body.appendSlice(esc) catch return ERR_NOMEM;
    b.body.appendSlice("\"\r\n\r\n") catch return ERR_NOMEM;
    b.body.appendSlice(value_ptr[0..@intCast(value_len)]) catch return ERR_NOMEM;
    b.body.appendSlice("\r\n") catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_std_multipart_builder_add_file(handle: u64, name: ?[*]const u8, name_len: u64, filename: ?[*]const u8, filename_len: u64, content_type: ?[*]const u8, content_type_len: u64, data: ?[*]const u8, data_len: u64) i32 {
    const b = getBuilder(handle) orelse return ERR_HANDLE;
    if (b.finished) return ERR_INVALID;
    const name_ptr = name orelse return ERR_INVALID;
    const filename_ptr = filename orelse return ERR_INVALID;
    const data_ptr = data orelse return ERR_INVALID;
    const ct: []const u8 = if (content_type) |c| c[0..@intCast(content_type_len)] else "application/octet-stream";
    const esc_name = escapeQuoted(b.allocator, name_ptr[0..@intCast(name_len)]) catch return ERR_NOMEM;
    defer b.allocator.free(esc_name);
    const esc_file = escapeQuoted(b.allocator, filename_ptr[0..@intCast(filename_len)]) catch return ERR_NOMEM;
    defer b.allocator.free(esc_file);
    b.body.appendSlice("--") catch return ERR_NOMEM;
    b.body.appendSlice(b.boundary) catch return ERR_NOMEM;
    b.body.appendSlice("\r\nContent-Disposition: form-data; name=\"") catch return ERR_NOMEM;
    b.body.appendSlice(esc_name) catch return ERR_NOMEM;
    b.body.appendSlice("\"; filename=\"") catch return ERR_NOMEM;
    b.body.appendSlice(esc_file) catch return ERR_NOMEM;
    b.body.appendSlice("\"\r\nContent-Type: ") catch return ERR_NOMEM;
    b.body.appendSlice(ct) catch return ERR_NOMEM;
    b.body.appendSlice("\r\n\r\n") catch return ERR_NOMEM;
    b.body.appendSlice(data_ptr[0..@intCast(data_len)]) catch return ERR_NOMEM;
    b.body.appendSlice("\r\n") catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_std_multipart_builder_boundary(handle: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const b = getBuilder(handle) orelse return ERR_HANDLE;
    return writeOut(b.boundary, out, cap, out_len);
}

pub export fn sa_std_multipart_builder_content_type(handle: u64, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const b = getBuilder(handle) orelse return ERR_HANDLE;
    var buf: [256]u8 = undefined;
    const ct = std.fmt.bufPrint(&buf, "multipart/form-data; boundary={s}", .{b.boundary}) catch return ERR_INVALID;
    return writeOut(ct, out, cap, out_len);
}

// finished bodies share the compress-style handle trio, multipart flavor
var out_mu = std.Io.Mutex.init;
var out_map: std.AutoHashMapUnmanaged(u64, []u8) = .empty;
var out_next: u64 = 1;

pub export fn sa_std_multipart_builder_finish(handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return ERR_INVALID;
    slot.* = 0;
    const b = getBuilder(handle) orelse return ERR_HANDLE;
    if (b.finished) return ERR_INVALID;
    b.finished = true;
    b.body.appendSlice("--") catch return ERR_NOMEM;
    b.body.appendSlice(b.boundary) catch return ERR_NOMEM;
    b.body.appendSlice("--\r\n") catch return ERR_NOMEM;
    const bytes = b.body.toOwnedSlice() catch return ERR_NOMEM;
    out_mu.lockUncancelable(sio.io());
    defer out_mu.unlock(sio.io());
    const h = out_next;
    out_next += 1;
    out_map.put(std.heap.page_allocator, h, bytes) catch {
        std.heap.page_allocator.free(bytes);
        return ERR_NOMEM;
    };
    slot.* = h;
    return OK;
}

pub export fn sa_std_multipart_buffer_data(handle: u64) ?[*]const u8 {
    out_mu.lockUncancelable(sio.io());
    defer out_mu.unlock(sio.io());
    const b = out_map.get(handle) orelse return null;
    return b.ptr;
}

pub export fn sa_std_multipart_buffer_len(handle: u64) u64 {
    out_mu.lockUncancelable(sio.io());
    defer out_mu.unlock(sio.io());
    const b = out_map.get(handle) orelse return 0;
    return b.len;
}

pub export fn sa_std_multipart_buffer_free(handle: u64) i32 {
    out_mu.lockUncancelable(sio.io());
    const kv = out_map.fetchRemove(handle);
    out_mu.unlock(sio.io());
    const b = (kv orelse return ERR_HANDLE).value;
    std.heap.page_allocator.free(b);
    return OK;
}

// ---------------- tests ----------------
const testing = std.testing;

test "multipart: build then parse round trip" {
    var b: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_builder_new(&b));
    defer _ = sa_std_multipart_builder_free(b);
    const field = "providerId";
    const fval = "openai";
    try testing.expectEqual(OK, sa_std_multipart_builder_add_field(b, field.ptr, field.len, fval.ptr, fval.len));
    const fname = "file";
    const filename = "note.bin";
    const ct = "application/octet-stream";
    const data = "bin\x00ary\r\nwith crlf\xff";
    try testing.expectEqual(OK, sa_std_multipart_builder_add_file(b, fname.ptr, fname.len, filename.ptr, filename.len, ct.ptr, ct.len, data.ptr, data.len));
    var ct_buf: [256]u8 = undefined;
    var ct_len: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_builder_content_type(b, &ct_buf, ct_buf.len, &ct_len));
    var out: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_builder_finish(b, &out));
    defer _ = sa_std_multipart_buffer_free(out);
    const body = sa_std_multipart_buffer_data(out).?[0..@intCast(sa_std_multipart_buffer_len(out))];

    var parsed: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_parse(body.ptr, body.len, &ct_buf, ct_len, &parsed));
    defer _ = sa_std_multipart_free(parsed);
    try testing.expectEqual(@as(u64, 2), sa_std_multipart_count(parsed));
    var name_buf: [64]u8 = undefined;
    var name_len: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_part_name(parsed, 0, &name_buf, name_buf.len, &name_len));
    try testing.expectEqualStrings("providerId", name_buf[0..@intCast(name_len)]);
    var body_ptr: ?[*]const u8 = null;
    var body_len: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_part_body(parsed, 0, &body_ptr, &body_len));
    try testing.expectEqualStrings("openai", body_ptr.?[0..@intCast(body_len)]);
    try testing.expectEqual(OK, sa_std_multipart_part_body(parsed, 1, &body_ptr, &body_len));
    try testing.expectEqualStrings(data, body_ptr.?[0..@intCast(body_len)]);
    var fn_len: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_part_filename(parsed, 1, &name_buf, name_buf.len, &fn_len));
    try testing.expectEqualStrings("note.bin", name_buf[0..@intCast(fn_len)]);
}

test "multipart: parse canned upload body" {
    const body = "--AaB03x\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello file\r\n--AaB03x\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\nmake it blue\r\n--AaB03x--\r\n";
    const ct = "multipart/form-data; boundary=AaB03x";
    var parsed: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_parse(body.ptr, body.len, ct.ptr, ct.len, &parsed));
    defer _ = sa_std_multipart_free(parsed);
    try testing.expectEqual(@as(u64, 2), sa_std_multipart_count(parsed));
    var body_ptr: ?[*]const u8 = null;
    var body_len: u64 = 0;
    try testing.expectEqual(OK, sa_std_multipart_part_body(parsed, 0, &body_ptr, &body_len));
    try testing.expectEqualStrings("hello file", body_ptr.?[0..@intCast(body_len)]);
    try testing.expectEqual(OK, sa_std_multipart_part_body(parsed, 1, &body_ptr, &body_len));
    try testing.expectEqualStrings("make it blue", body_ptr.?[0..@intCast(body_len)]);
}
