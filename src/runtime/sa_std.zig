const std = @import("std");
const builtin = @import("builtin");

const RegexC = extern struct {
    buffer: ?*anyopaque,
    allocated: c_ulong,
    used: c_ulong,
    syntax: c_ulong,
    fastmap: ?[*]u8,
    translate: ?[*]u8,
    re_nsub: usize,
    flags: u32,
};

const RegexMatchC = extern struct {
    rm_so: c_int,
    rm_eo: c_int,
};

extern fn regcomp(preg: ?*RegexC, pattern: [*c]const u8, cflags: c_int) c_int;
extern fn regexec(preg: ?*const RegexC, text: [*c]const u8, nmatch: usize, pmatch: [*]RegexMatchC, eflags: c_int) c_int;
extern fn regfree(preg: ?*RegexC) void;
extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn unsetenv(name: [*:0]const u8) c_int;

extern "c" var environ: [*:null]?[*:0]u8;

comptime {
    std.debug.assert(@sizeOf(RegexC) == 64);
    std.debug.assert(@alignOf(RegexC) == 8);
    std.debug.assert(@offsetOf(RegexC, "re_nsub") == 48);
    std.debug.assert(@offsetOf(RegexC, "flags") == 56);
    std.debug.assert(@sizeOf(RegexMatchC) == 8);
    std.debug.assert(@offsetOf(RegexMatchC, "rm_so") == 0);
    std.debug.assert(@offsetOf(RegexMatchC, "rm_eo") == 4);
}

pub const SA_STD_ABI_VERSION: u32 = 1;

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = 1;
pub const SA_STD_ERR_INVALID_HANDLE: i32 = 2;
pub const SA_STD_ERR_NOT_FOUND: i32 = 3;
pub const SA_STD_ERR_ACCESS: i32 = 4;
pub const SA_STD_ERR_NO_MEMORY: i32 = 5;
pub const SA_STD_ERR_IO: i32 = 6;
pub const SA_STD_ERR_NET: i32 = 7;
pub const SA_STD_ERR_UNSUPPORTED: i32 = 8;
pub const SA_STD_ERR_TRUNCATED: i32 = 9;
pub const SA_STD_ERR_UNKNOWN: i32 = 127;

pub const SA_STD_STDIN: u64 = 1;
pub const SA_STD_STDOUT: u64 = 2;
pub const SA_STD_STDERR: u64 = 3;

pub const SA_PLUGIN_DESCRIPTOR_SYMBOL: [:0]const u8 = "saasm_plugin_descriptor_v1";

pub const SaPluginDescriptor = extern struct {
    abi_version: u32,
    descriptor_size: u32,
    name: [*:0]const u8,
};

pub const SA_JSON_KIND_INVALID: u32 = std.math.maxInt(u32);
pub const SA_JSON_KIND_NULL: u32 = 0;
pub const SA_JSON_KIND_BOOL: u32 = 1;
pub const SA_JSON_KIND_INTEGER: u32 = 2;
pub const SA_JSON_KIND_FLOAT: u32 = 3;
pub const SA_JSON_KIND_NUMBER_STRING: u32 = 4;
pub const SA_JSON_KIND_STRING: u32 = 5;
pub const SA_JSON_KIND_ARRAY: u32 = 6;
pub const SA_JSON_KIND_OBJECT: u32 = 7;

pub const SA_JSON_TOKEN_INVALID: u32 = std.math.maxInt(u32);
pub const SA_JSON_TOKEN_OBJECT_BEGIN: u32 = 0;
pub const SA_JSON_TOKEN_OBJECT_END: u32 = 1;
pub const SA_JSON_TOKEN_ARRAY_BEGIN: u32 = 2;
pub const SA_JSON_TOKEN_ARRAY_END: u32 = 3;
pub const SA_JSON_TOKEN_TRUE: u32 = 4;
pub const SA_JSON_TOKEN_FALSE: u32 = 5;
pub const SA_JSON_TOKEN_NULL: u32 = 6;
pub const SA_JSON_TOKEN_NUMBER: u32 = 7;
pub const SA_JSON_TOKEN_PARTIAL_NUMBER: u32 = 8;
pub const SA_JSON_TOKEN_STRING: u32 = 9;
pub const SA_JSON_TOKEN_PARTIAL_STRING: u32 = 10;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1: u32 = 11;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2: u32 = 12;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3: u32 = 13;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4: u32 = 14;
pub const SA_JSON_TOKEN_END_OF_DOCUMENT: u32 = 15;
pub const SA_JSON_TOKEN_ALLOCATED_NUMBER: u32 = 16;
pub const SA_JSON_TOKEN_ALLOCATED_STRING: u32 = 17;

pub const SA_JSON_WHITESPACE_MINIFIED: u32 = 0;
pub const SA_JSON_WHITESPACE_INDENT_1: u32 = 1;
pub const SA_JSON_WHITESPACE_INDENT_2: u32 = 2;
pub const SA_JSON_WHITESPACE_INDENT_3: u32 = 3;
pub const SA_JSON_WHITESPACE_INDENT_4: u32 = 4;
pub const SA_JSON_WHITESPACE_INDENT_8: u32 = 5;
pub const SA_JSON_WHITESPACE_INDENT_TAB: u32 = 6;

pub const SA_REGEX_EXTENDED: c_int = 1;
pub const SA_REGEX_ICASE: c_int = 2;
pub const SA_REGEX_NEWLINE: c_int = 4;
pub const SA_REGEX_NOSUB: c_int = 8;
pub const SA_REGEX_NOTBOL: c_int = 1;
pub const SA_REGEX_NOTEOL: c_int = 2;
pub const SA_REGEX_REG_NOERROR: c_int = 0;
pub const SA_REGEX_REG_OK: c_int = 0;
pub const SA_REGEX_REG_NOMATCH: c_int = 1;
pub const SA_REGEX_REG_BADPAT: c_int = 2;
pub const SA_REGEX_REG_ECOLLATE: c_int = 3;
pub const SA_REGEX_REG_ECTYPE: c_int = 4;
pub const SA_REGEX_REG_EESCAPE: c_int = 5;
pub const SA_REGEX_REG_ESUBREG: c_int = 6;
pub const SA_REGEX_REG_EBRACK: c_int = 7;
pub const SA_REGEX_REG_EPAREN: c_int = 8;
pub const SA_REGEX_REG_EBRACE: c_int = 9;
pub const SA_REGEX_REG_BADBR: c_int = 10;
pub const SA_REGEX_REG_ERANGE: c_int = 11;
pub const SA_REGEX_REG_ESPACE: c_int = 12;
pub const SA_REGEX_REG_BADRPT: c_int = 13;
pub const SA_REGEX_REG_ENOSYS: c_int = -1;

pub const SaJsonToken = extern struct {
    kind: u32,
    text_ptr: ?[*]const u8,
    text_len: u64,
};

pub const SaJsonStringifyOptions = extern struct {
    whitespace: u32 = SA_JSON_WHITESPACE_MINIFIED,
    emit_null_optional_fields: u8 = 1,
    emit_strings_as_arrays: u8 = 0,
    escape_unicode: u8 = 0,
    emit_nonportable_numbers_as_strings: u8 = 0,
};

const FIRST_DYNAMIC_HANDLE: u64 = 4;
const DEFAULT_CAPTURE_LIMIT: usize = 50 * 1024;

const empty_bytes: [0]u8 = .{};
const empty_mut_bytes: [0]u8 = .{};

const BufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *BufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

const MetadataHandle = struct {
    allocator: std.mem.Allocator,
    stat: std.fs.File.Stat,

    fn deinit(self: *MetadataHandle) void {
        _ = self;
    }
};

const NetAddrHandle = struct {
    allocator: std.mem.Allocator,
    host: []u8,
    addr: std.net.Address,

    fn deinit(self: *NetAddrHandle) void {
        if (self.host.len != 0) self.allocator.free(self.host);
        self.host = &.{};
    }

    fn init(allocator: std.mem.Allocator, address: std.net.Address) !NetAddrHandle {
        const host = try addressHostText(allocator, address);
        return .{
            .allocator = allocator,
            .host = host,
            .addr = address,
        };
    }
};

fn addressHostText(allocator: std.mem.Allocator, address: std.net.Address) ![]u8 {
    return switch (address.any.family) {
        std.posix.AF.INET => blk: {
            const ip = @as(*const [4]u8, @ptrCast(&address.in.sa.addr)).*;
            break :blk try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ ip[0], ip[1], ip[2], ip[3] });
        },
        std.posix.AF.INET6 => blk: {
            const full = try std.fmt.allocPrint(allocator, "{}", .{address});
            if (full.len >= 4 and full[0] == '[') {
                const closing = std.mem.lastIndexOfScalar(u8, full, ']') orelse return full;
                if (closing + 2 <= full.len and full[closing + 1] == ':') {
                    const host = try allocator.dupe(u8, full[1..closing]);
                    allocator.free(full);
                    break :blk host;
                }
            }
            if (std.mem.lastIndexOfScalar(u8, full, ':')) |sep| {
                const host = try allocator.dupe(u8, full[0..sep]);
                allocator.free(full);
                break :blk host;
            }
            break :blk full;
        },
        std.posix.AF.UNIX => try allocator.dupe(u8, std.mem.sliceTo(&address.un.path, 0)),
        else => try allocator.dupe(u8, ""),
    };
}

const FmtHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *FmtHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

const JsonDocumentHandle = struct {
    allocator: std.mem.Allocator,
    parsed: std.json.Parsed(std.json.Value),
    ref_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    fn retain(self: *JsonDocumentHandle) void {
        _ = self.ref_count.fetchAdd(1, .monotonic);
    }

    fn release(self: *JsonDocumentHandle) void {
        if (self.ref_count.fetchSub(1, .release) == 1) {
            _ = self.ref_count.load(.acquire);
            self.parsed.deinit();
            self.allocator.destroy(self);
        }
    }
};

const JsonNodeHandle = struct {
    document: *JsonDocumentHandle,
    value: std.json.Value,

    fn deinit(self: *JsonNodeHandle) void {
        self.document.release();
    }
};

const JsonBufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *JsonBufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

const JsonScannerHandle = struct {
    allocator: std.mem.Allocator,
    scanner: std.json.Scanner,
    pending_input: []const u8 = &.{},
    pending_input_owned: bool = false,
    pending_text: std.ArrayList(u8),
    current_text: ?[]const u8 = null,
    current_token: u32 = SA_JSON_TOKEN_INVALID,

    fn init(allocator: std.mem.Allocator) !*JsonScannerHandle {
        const handle = try allocator.create(JsonScannerHandle);
        handle.* = .{
            .allocator = allocator,
            .scanner = std.json.Scanner.initStreaming(allocator),
            .pending_input = &.{},
            .pending_input_owned = false,
            .pending_text = std.ArrayList(u8).init(allocator),
            .current_text = null,
            .current_token = SA_JSON_TOKEN_INVALID,
        };
        return handle;
    }

    fn initCompleteInput(allocator: std.mem.Allocator, input: []const u8) !*JsonScannerHandle {
        const handle = try allocator.create(JsonScannerHandle);
        handle.* = .{
            .allocator = allocator,
            .scanner = std.json.Scanner.initCompleteInput(allocator, input),
            .pending_input = input,
            .pending_input_owned = false,
            .pending_text = std.ArrayList(u8).init(allocator),
            .current_text = null,
            .current_token = SA_JSON_TOKEN_INVALID,
        };
        return handle;
    }

    fn deinit(self: *JsonScannerHandle) void {
        self.pending_text.deinit();
        self.scanner.deinit();
        if (self.pending_input_owned and self.pending_input.len != 0) self.allocator.free(self.pending_input);
        self.pending_input = &.{};
        self.pending_input_owned = false;
        self.current_text = null;
        self.current_token = SA_JSON_TOKEN_INVALID;
    }

    fn destroy(self: *JsonScannerHandle) void {
        self.deinit();
        self.allocator.destroy(self);
    }
};

const JsonStreamHandle = struct {
    allocator: std.mem.Allocator,
    owned_input: []u8,
    scanner: *JsonScannerHandle,
    last_token: u32 = SA_JSON_TOKEN_INVALID,

    fn init(allocator: std.mem.Allocator, input: []const u8) !*JsonStreamHandle {
        const owned_input = try allocator.alloc(u8, input.len);
        errdefer allocator.free(owned_input);
        @memcpy(owned_input, input);
        const scanner = try JsonScannerHandle.initCompleteInput(allocator, owned_input);
        errdefer scanner.destroy();
        const handle = try allocator.create(JsonStreamHandle);
        handle.* = .{
            .allocator = allocator,
            .owned_input = owned_input,
            .scanner = scanner,
            .last_token = SA_JSON_TOKEN_INVALID,
        };
        return handle;
    }

    fn deinit(self: *JsonStreamHandle) void {
        self.scanner.destroy();
        if (self.owned_input.len != 0) self.allocator.free(self.owned_input);
        self.owned_input = &.{};
        self.allocator.destroy(self);
    }
};

const JsonWriterHandle = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    stream: std.json.WriteStream(std.ArrayList(u8).Writer, .checked_to_arbitrary_depth),
    options: std.json.StringifyOptions,
    root_value_started: bool = false,
    root_value_complete: bool = false,
    open_depth: u32 = 0,
    result_buffer: ?u64 = null,

    fn init(allocator: std.mem.Allocator, options: std.json.StringifyOptions) !*JsonWriterHandle {
        const handle = try allocator.create(JsonWriterHandle);
        handle.* = .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .stream = undefined,
            .options = options,
            .root_value_started = false,
            .root_value_complete = false,
            .open_depth = 0,
            .result_buffer = null,
        };
        handle.stream = std.json.writeStreamArbitraryDepth(allocator, handle.buffer.writer(), options);
        return handle;
    }

    fn deinit(self: *JsonWriterHandle) void {
        self.stream.deinit();
        self.buffer.deinit();
        self.allocator.destroy(self);
    }
};

const RegexHandle = struct {
    allocator: std.mem.Allocator,
    pattern_z: []u8,
    compiled: RegexC,
    compiled_valid: bool = false,

    fn init(allocator: std.mem.Allocator, pattern: []const u8, cflags: c_int) !*RegexHandle {
        if (std.mem.indexOfScalar(u8, pattern, 0) != null) return error.InvalidArgument;
        const owned_pattern = try allocator.alloc(u8, pattern.len + 1);
        errdefer allocator.free(owned_pattern);
        @memcpy(owned_pattern[0..pattern.len], pattern);
        owned_pattern[pattern.len] = 0;
        const handle = try allocator.create(RegexHandle);
        errdefer allocator.destroy(handle);
        handle.* = .{
            .allocator = allocator,
            .pattern_z = owned_pattern,
            .compiled = undefined,
            .compiled_valid = false,
        };
        const pattern_c: [*:0]const u8 = @ptrCast(owned_pattern.ptr);
        const rc = regcomp(&handle.compiled, pattern_c, cflags);
        if (rc != SA_REGEX_REG_NOERROR) {
            return regexErrorToZig(rc);
        }
        handle.compiled_valid = true;
        return handle;
    }

    fn deinit(self: *RegexHandle) void {
        if (self.compiled_valid) regfree(&self.compiled);
        if (self.pattern_z.len != 0) self.allocator.free(self.pattern_z);
        self.pattern_z = &.{};
        self.compiled_valid = false;
    }

    fn destroy(self: *RegexHandle) void {
        self.deinit();
        self.allocator.destroy(self);
    }
};

const RegexMatchHandle = struct {
    allocator: std.mem.Allocator,
    text_z: []u8,
    matches: []RegexMatchC,

    fn init(allocator: std.mem.Allocator, text: []const u8, group_count: usize) !*RegexMatchHandle {
        const owned_text = try allocator.alloc(u8, text.len + 1);
        errdefer allocator.free(owned_text);
        @memcpy(owned_text[0..text.len], text);
        owned_text[text.len] = 0;
        const matches = try allocator.alloc(RegexMatchC, group_count);
        errdefer allocator.free(matches);
        const handle = try allocator.create(RegexMatchHandle);
        errdefer allocator.destroy(handle);
        handle.* = .{
            .allocator = allocator,
            .text_z = owned_text,
            .matches = matches,
        };
        return handle;
    }

    fn deinit(self: *RegexMatchHandle) void {
        if (self.matches.len != 0) self.allocator.free(self.matches);
        if (self.text_z.len != 0) self.allocator.free(self.text_z);
        self.matches = &.{};
        self.text_z = &.{};
    }

    fn destroy(self: *RegexMatchHandle) void {
        self.deinit();
        self.allocator.destroy(self);
    }
};

fn regexErrorToZig(rc: c_int) anyerror {
    return switch (rc) {
        SA_REGEX_REG_NOMATCH => error.FileNotFound,
        SA_REGEX_REG_BADPAT => error.SyntaxError,
        SA_REGEX_REG_ESPACE => error.OutOfMemory,
        SA_REGEX_REG_ENOSYS => error.Unsupported,
        else => error.InvalidArgument,
    };
}

fn regexGroupCount(regex_handle: *RegexHandle) usize {
    return @as(usize, @intCast(regex_handle.compiled.re_nsub)) + 1;
}

fn regexMatchHandle(regex_handle: *RegexHandle, text: []const u8) !*RegexMatchHandle {
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidArgument;
    const allocator = regex_handle.allocator;
    const owned_text = try allocator.alloc(u8, text.len + 1);
    errdefer allocator.free(owned_text);
    @memcpy(owned_text[0..text.len], text);
    owned_text[text.len] = 0;

    const groups = try allocator.alloc(RegexMatchC, regexGroupCount(regex_handle));
    errdefer allocator.free(groups);

    const rc = regexec(&regex_handle.compiled, @ptrCast(owned_text.ptr), groups.len, groups.ptr, 0);
    if (rc == SA_REGEX_REG_NOMATCH) {
        allocator.free(groups);
        allocator.free(owned_text);
        return error.FileNotFound;
    }
    if (rc != SA_REGEX_REG_NOERROR) {
        allocator.free(groups);
        allocator.free(owned_text);
        return regexErrorToZig(rc);
    }

    const handle = try allocator.create(RegexMatchHandle);
    handle.* = .{
        .allocator = allocator,
        .text_z = owned_text,
        .matches = groups,
    };
    return handle;
}

fn jsonKindOf(value: std.json.Value) u32 {
    return switch (value) {
        .null => SA_JSON_KIND_NULL,
        .bool => SA_JSON_KIND_BOOL,
        .integer => SA_JSON_KIND_INTEGER,
        .float => SA_JSON_KIND_FLOAT,
        .number_string => SA_JSON_KIND_NUMBER_STRING,
        .string => SA_JSON_KIND_STRING,
        .array => SA_JSON_KIND_ARRAY,
        .object => SA_JSON_KIND_OBJECT,
    };
}

fn jsonTextSlice(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        .number_string => |text| text,
        else => null,
    };
}

fn jsonValueAsF64(value: std.json.Value) !f64 {
    return switch (value) {
        .integer => |inner| @as(f64, @floatFromInt(inner)),
        .float => |inner| {
            if (!std.math.isFinite(inner)) return error.InvalidArgument;
            return inner;
        },
        .number_string => |text| blk: {
            const parsed = std.fmt.parseFloat(f64, text) catch return error.InvalidArgument;
            if (!std.math.isFinite(parsed)) break :blk error.InvalidArgument;
            break :blk parsed;
        },
        else => error.InvalidArgument,
    };
}

fn jsonValueAsI64(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |inner| inner,
        .float => |inner| blk: {
            if (!std.math.isFinite(inner)) break :blk error.InvalidArgument;
            if (@round(inner) != inner) break :blk error.InvalidArgument;
            if (inner > @as(f64, @floatFromInt(std.math.maxInt(i64)))) break :blk error.InvalidArgument;
            if (inner < @as(f64, @floatFromInt(std.math.minInt(i64)))) break :blk error.InvalidArgument;
            break :blk @as(i64, @intFromFloat(inner));
        },
        .number_string => |text| std.fmt.parseInt(i64, text, 10) catch |err| switch (err) {
            error.Overflow, error.InvalidCharacter => return error.InvalidArgument,
        },
        else => error.InvalidArgument,
    };
}

fn jsonValueAsBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |inner| inner,
        else => error.InvalidArgument,
    };
}

fn registerJsonNode(document: *JsonDocumentHandle, value: std.json.Value, retain_document: bool) !u64 {
    if (retain_document) document.retain();
    return registerResource(.{ .json_node = .{ .document = document, .value = value } }) catch |err| {
        document.release();
        return err;
    };
}

fn acquireJsonNode(handle: u64) !JsonNodeHandle {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
    return switch (resource.*) {
        .json_node => |node| blk: {
            node.document.retain();
            break :blk node;
        },
        else => error.InvalidHandle,
    };
}

fn jsonDocumentFromSlice(allocator: std.mem.Allocator, input: []const u8) !*JsonDocumentHandle {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    errdefer parsed.deinit();
    const document = try allocator.create(JsonDocumentHandle);
    document.* = .{
        .allocator = allocator,
        .parsed = parsed,
        .ref_count = std.atomic.Value(usize).init(1),
    };
    return document;
}

fn jsonObjectGet(node: JsonNodeHandle, key: []const u8) !JsonNodeHandle {
    return switch (node.value) {
        .object => |object| {
            const child = object.get(key) orelse return error.FileNotFound;
            return .{
                .document = node.document,
                .value = child,
            };
        },
        else => error.InvalidHandle,
    };
}

fn jsonArrayGet(node: JsonNodeHandle, index: u64) !JsonNodeHandle {
    return switch (node.value) {
        .array => |array| {
            const idx: usize = @intCast(index);
            if (idx >= array.items.len) return error.FileNotFound;
            return .{
                .document = node.document,
                .value = array.items[idx],
            };
        },
        else => error.InvalidHandle,
    };
}

fn jsonObjectKeyAt(node: JsonNodeHandle, index: u64) ![]const u8 {
    return switch (node.value) {
        .object => |object| {
            const idx: usize = @intCast(index);
            if (idx >= object.count()) return error.FileNotFound;
            var it = object.iterator();
            var current: usize = 0;
            while (it.next()) |entry| : (current += 1) {
                if (current == idx) return entry.key_ptr.*;
            }
            return error.FileNotFound;
        },
        else => error.InvalidHandle,
    };
}

fn jsonStringifyAlloc(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try std.json.stringify(value, .{}, list.writer());
    return try list.toOwnedSlice();
}

fn jsonSerializeBuffer(allocator: std.mem.Allocator, value: std.json.Value) !u64 {
    const bytes = try jsonStringifyAlloc(allocator, value);
    return registerResource(.{ .json_buffer = .{ .allocator = allocator, .bytes = bytes } }) catch |err| {
        allocator.free(bytes);
        return err;
    };
}

fn acquireJsonWriterForWrite(writer: u64) !*JsonWriterHandle {
    const resource = getResourceLocked(writer) orelse return error.InvalidHandle;
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return error.InvalidHandle,
    };
    if (writer_handle.result_buffer != null) return error.InvalidHandle;
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return error.InvalidArgument;
    return writer_handle;
}

fn markJsonWriterValueComplete(writer_handle: *JsonWriterHandle) void {
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
}

fn jsonWriterObjectFieldLocked(writer_handle: *JsonWriterHandle, key: []const u8) !void {
    if (writer_handle.result_buffer != null) return error.InvalidHandle;
    if (writer_handle.open_depth == 0) return error.InvalidArgument;
    try writer_handle.stream.objectField(key);
}

fn tokenTypeOf(token: std.json.Token) u32 {
    return switch (token) {
        .object_begin => SA_JSON_TOKEN_OBJECT_BEGIN,
        .object_end => SA_JSON_TOKEN_OBJECT_END,
        .array_begin => SA_JSON_TOKEN_ARRAY_BEGIN,
        .array_end => SA_JSON_TOKEN_ARRAY_END,
        .true => SA_JSON_TOKEN_TRUE,
        .false => SA_JSON_TOKEN_FALSE,
        .null => SA_JSON_TOKEN_NULL,
        .number => SA_JSON_TOKEN_NUMBER,
        .partial_number => SA_JSON_TOKEN_PARTIAL_NUMBER,
        .allocated_number => SA_JSON_TOKEN_ALLOCATED_NUMBER,
        .string => SA_JSON_TOKEN_STRING,
        .partial_string => SA_JSON_TOKEN_PARTIAL_STRING,
        .partial_string_escaped_1 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1,
        .partial_string_escaped_2 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2,
        .partial_string_escaped_3 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3,
        .partial_string_escaped_4 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4,
        .allocated_string => SA_JSON_TOKEN_ALLOCATED_STRING,
        .end_of_document => SA_JSON_TOKEN_END_OF_DOCUMENT,
    };
}

fn tokenTextSlice(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .number => |slice| slice,
        .partial_number => |slice| slice,
        .string => |slice| slice,
        .partial_string => |slice| slice,
        else => null,
    };
}

fn tokenTextBytes(scanner_handle: *JsonScannerHandle, token: std.json.Token) ![]const u8 {
    scanner_handle.pending_text.clearRetainingCapacity();
    switch (token) {
        .number => |slice| try scanner_handle.pending_text.appendSlice(slice),
        .partial_number => |slice| try scanner_handle.pending_text.appendSlice(slice),
        .allocated_number => |slice| {
            errdefer scanner_handle.allocator.free(slice);
            try scanner_handle.pending_text.appendSlice(slice);
            scanner_handle.allocator.free(slice);
        },
        .string => |slice| try scanner_handle.pending_text.appendSlice(slice),
        .partial_string => |slice| try scanner_handle.pending_text.appendSlice(slice),
        .partial_string_escaped_1 => |slice| try scanner_handle.pending_text.appendSlice(slice[0..]),
        .partial_string_escaped_2 => |slice| try scanner_handle.pending_text.appendSlice(slice[0..]),
        .partial_string_escaped_3 => |slice| try scanner_handle.pending_text.appendSlice(slice[0..]),
        .partial_string_escaped_4 => |slice| try scanner_handle.pending_text.appendSlice(slice[0..]),
        .allocated_string => |slice| {
            errdefer scanner_handle.allocator.free(slice);
            try scanner_handle.pending_text.appendSlice(slice);
            scanner_handle.allocator.free(slice);
        },
        else => return error.InvalidArgument,
    }
    return scanner_handle.pending_text.items;
}

fn jsonScannerFeed(scanner_handle: *JsonScannerHandle, input: []const u8, end_input: bool) !void {
    if (scanner_handle.pending_input.len != 0) {
        if (scanner_handle.scanner.cursor != scanner_handle.scanner.input.len) return error.InvalidArgument;
        if (scanner_handle.pending_input_owned) scanner_handle.allocator.free(scanner_handle.pending_input);
        scanner_handle.pending_input = &.{};
        scanner_handle.pending_input_owned = false;
    }
    const owned = try scanner_handle.allocator.dupe(u8, input);
    scanner_handle.pending_input = owned;
    scanner_handle.pending_input_owned = true;
    scanner_handle.scanner.feedInput(owned);
    if (end_input) scanner_handle.scanner.endInput();
}

const EnvHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *EnvHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

const TimeDate = extern struct {
    unix_ms: i64,
    unix_ns: i64,
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
};

const SaNetAddr = extern struct {
    family: u32,
    port: u32,
    host_ptr: [*]u8,
    host_len: u64,
    scope_id: u64,
};

const Timeval = std.posix.timeval;
const TimevalSec = @TypeOf(@as(Timeval, .{ .sec = 0, .usec = 0 }).sec);
const TimevalUsec = @TypeOf(@as(Timeval, .{ .sec = 0, .usec = 0 }).usec);

const OwnedFdHandle = struct {
    fd: std.posix.fd_t,

    fn deinit(self: *OwnedFdHandle) void {
        std.posix.close(self.fd);
        self.fd = -1;
    }
};

const TerminalSession = struct {
    fd: std.posix.fd_t,
    saved: std.posix.termios,

    fn deinit(self: *TerminalSession) !void {
        try std.posix.tcsetattr(self.fd, .FLUSH, self.saved);
    }
};

const SaProcessArgv = extern struct {
    data: [*]const u8,
    len: u64,
};

const SaTermWinsize = extern struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
};

const SaTermEpollEvent = extern struct {
    events: u32,
    data: u64,
};

const ProcessHandle = struct {
    pid: std.posix.pid_t,
    capture_output: bool = false,
    stdout_fd: ?std.posix.fd_t = null,
    stderr_fd: ?std.posix.fd_t = null,
    stdout_buf: []u8 = &.{},
    stderr_buf: []u8 = &.{},
    stdout_pos: usize = 0,
    stderr_pos: usize = 0,
    exited: bool = false,
    code: u32 = 0,

    fn deinit(self: *ProcessHandle) void {
        if (!self.exited) {
            _ = std.posix.waitpid(self.pid, 0);
            self.exited = true;
        }
        if (self.stdout_fd) |fd| std.posix.close(fd);
        if (self.stderr_fd) |fd| std.posix.close(fd);
        if (self.stdout_buf.len != 0) std.heap.page_allocator.free(self.stdout_buf);
        if (self.stderr_buf.len != 0) std.heap.page_allocator.free(self.stderr_buf);
        self.stdout_buf = &.{};
        self.stderr_buf = &.{};
        self.stdout_pos = 0;
        self.stderr_pos = 0;
        self.stdout_fd = null;
        self.stderr_fd = null;
    }
};

const Resource = union(enum) {
    file: std.fs.File,
    dynamic_lib: *DynamicLibHandle,
    tcp_stream: std.net.Stream,
    tcp_listener: std.net.Server,
    udp_socket: std.posix.socket_t,
    buffer: BufferHandle,
    metadata: MetadataHandle,
    net_addr: NetAddrHandle,
    fmt: FmtHandle,
    env: EnvHandle,
    json_node: JsonNodeHandle,
    json_buffer: JsonBufferHandle,
    json_scanner: *JsonScannerHandle,
    json_stream: *JsonStreamHandle,
    json_writer: *JsonWriterHandle,
    regex: *RegexHandle,
    regex_match: *RegexMatchHandle,
    owned_fd: OwnedFdHandle,
    terminal_session: TerminalSession,
    process: ProcessHandle,

    fn close(self: *Resource) !void {
        switch (self.*) {
            .file => |file| file.close(),
            .dynamic_lib => |handle| {
                handle.deinit();
                std.heap.page_allocator.destroy(handle);
            },
            .tcp_stream => |stream| stream.close(),
            .tcp_listener => |*server| server.deinit(),
            .udp_socket => |fd| std.posix.close(fd),
            .buffer => |*buffer| buffer.deinit(),
            .metadata => |*metadata| metadata.deinit(),
            .net_addr => |*addr| addr.deinit(),
            .fmt => |*fmt| fmt.deinit(),
            .env => |*env| env.deinit(),
            .json_node => |*node| node.deinit(),
            .json_buffer => |*buffer| buffer.deinit(),
            .json_scanner => |scanner| scanner.destroy(),
            .json_stream => |stream| stream.deinit(),
            .json_writer => |writer| writer.deinit(),
            .regex => |regex| regex.destroy(),
            .regex_match => |match| match.destroy(),
            .owned_fd => |*fd| fd.deinit(),
            .terminal_session => |*session| try session.deinit(),
            .process => |*proc| proc.deinit(),
        }
        self.* = undefined;
    }
};

var registry_mutex: std.Thread.Mutex = .{};
var time_mutex: std.Thread.Mutex = .{};
var registry_slots = std.ArrayList(?Resource).init(std.heap.page_allocator);
var pthread_registry_mutex: std.Thread.Mutex = .{};
var pthread_slots = std.ArrayList(?*PthreadHandle).init(std.heap.page_allocator);
var monotonic_origin: ?std.time.Instant = null;
threadlocal var last_error: i32 = SA_STD_OK;
var compatibility_mmap_page: [4096]u8 = [_]u8{0} ** 4096;
var compatibility_dlopen_cookie: [1]u8 = .{0};
var compatibility_dlsym_cookie: [1]u8 = .{0};
var compatibility_dl_error: [:0]const u8 = "unsupported";

const DynamicLibHandle = struct {
    lib: std.DynLib,

    fn deinit(self: *DynamicLibHandle) void {
        self.lib.close();
    }
};

const PthreadEntryFn = *const fn (?[*]u8) callconv(.c) i32;

const PthreadTask = struct {
    entry: PthreadEntryFn,
    arg: ?[*]u8,
    result: i32 = SA_STD_OK,
    destroy_on_finish: bool = false,
};

const PthreadHandle = struct {
    thread: std.Thread,
    task: *PthreadTask,
    joined: bool = false,
};

fn pthreadTaskMain(task: *PthreadTask) void {
    task.result = task.entry(task.arg);
    if (task.destroy_on_finish) {
        std.heap.page_allocator.destroy(task);
    }
}

fn allocPthreadHandle(handle: *PthreadHandle) !i32 {
    pthread_registry_mutex.lock();
    defer pthread_registry_mutex.unlock();
    for (pthread_slots.items, 0..) |slot, idx| {
        if (slot == null) {
            pthread_slots.items[idx] = handle;
            return @intCast(idx + 1);
        }
    }
    try pthread_slots.append(handle);
    return @intCast(pthread_slots.items.len);
}

fn takePthreadHandle(handle: i32) !*PthreadHandle {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    pthread_registry_mutex.lock();
    defer pthread_registry_mutex.unlock();
    if (idx >= pthread_slots.items.len) return error.InvalidHandle;
    return pthread_slots.items[idx] orelse return error.InvalidHandle;
}

fn freePthreadHandle(handle: i32) !*PthreadHandle {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    pthread_registry_mutex.lock();
    defer pthread_registry_mutex.unlock();
    if (idx >= pthread_slots.items.len) return error.InvalidHandle;
    const slot = pthread_slots.items[idx] orelse return error.InvalidHandle;
    pthread_slots.items[idx] = null;
    return slot;
}

fn finish(status: i32) i32 {
    last_error = status;
    return status;
}

fn mapError(err: anyerror) i32 {
    return switch (err) {
        error.InvalidArgument => SA_STD_ERR_INVALID_ARGUMENT,
        error.InvalidHandle => SA_STD_ERR_INVALID_HANDLE,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.FileNotFound => SA_STD_ERR_NOT_FOUND,
        error.AccessDenied, error.PermissionDenied => SA_STD_ERR_ACCESS,
        error.WouldBlock => SA_STD_ERR_IO,
        error.NotATerminal, error.ProcessOrphaned => SA_STD_ERR_UNSUPPORTED,
        error.FileDescriptorAlreadyPresentInSet, error.OperationCausesCircularLoop => SA_STD_ERR_INVALID_ARGUMENT,
        error.FileDescriptorNotRegistered => SA_STD_ERR_INVALID_HANDLE,
        error.FileDescriptorIncompatibleWithEpoll => SA_STD_ERR_UNSUPPORTED,
        error.SyntaxError,
        error.UnexpectedEndOfInput,
        error.UnexpectedToken,
        error.InvalidNumber,
        error.DuplicateField,
        error.UnknownField,
        error.MissingField,
        error.LengthMismatch,
        error.InvalidEnumTag,
        error.ValueTooLong,
        error.BufferUnderrun,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.AlreadyConnected,
        error.ConnectionPending,
        error.SocketNotConnected,
        error.UnreachableAddress,
        error.NetworkSubsystemFailed,
        => SA_STD_ERR_NET,
        error.MessageTooBig => SA_STD_ERR_TRUNCATED,
        error.Unsupported, error.SystemResources, error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded => SA_STD_ERR_UNSUPPORTED,
        error.ProcessNotFound, error.AlreadyTerminated => SA_STD_ERR_INVALID_HANDLE,
        error.NameTooLong,
        error.BadPathName,
        error.InvalidUtf8,
        error.InvalidWtf8,
        error.NotDir,
        error.IsDir,
        error.InvalidIPAddressFormat,
        error.InvalidCharacter,
        error.InvalidEnd,
        error.Incomplete,
        error.NonCanonical,
        error.InvalidIpv4Mapping,
        error.Overflow,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.RegexInvalidArgument,
        error.RegexNoMatch,
        error.RegexBadPattern,
        error.RegexOutOfMemory,
        error.UnknownHostName,
        error.TemporaryNameServerFailure,
        error.NameServerFailure,
        error.NetworkUnreachable,
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.AddressInUse,
        error.AddressNotAvailable,
        error.HostLacksNetworkAddresses,
        error.ServiceUnavailable,
        => SA_STD_ERR_NET,
        else => SA_STD_ERR_IO,
    };
}

fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

fn fillUtcNow(out: *TimeDate) !void {
    const unix_ms = std.time.milliTimestamp();
    const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
    if (unix_s < 0) return error.Unsupported;

    const unix_ns_raw = std.time.nanoTimestamp();
    const unix_ns = std.math.cast(i64, unix_ns_raw) orelse return error.Overflow;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(unix_s)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    out.* = .{
        .unix_ms = unix_ms,
        .unix_ns = unix_ns,
        .year = year_day.year,
        .month = @intFromEnum(month_day.month),
        .day = @as(u8, @intCast(month_day.day_index + 1)),
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
        .millisecond = @as(u16, @intCast(@mod(unix_ms, std.time.ms_per_s))),
    };
}

fn monotonicNowNs() !u64 {
    time_mutex.lock();
    defer time_mutex.unlock();

    const current = try std.time.Instant.now();
    if (monotonic_origin) |origin| {
        return current.since(origin);
    }
    monotonic_origin = current;
    return 0;
}

fn lenAsUsize(len: u64) !usize {
    if (len > @as(u64, @intCast(std.math.maxInt(usize)))) return error.InvalidArgument;
    return @as(usize, @intCast(len));
}

fn constBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

fn mutBytes(ptr: ?[*]u8, len: u64) ![]u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return empty_mut_bytes[0..];
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

fn portFromU32(port: u32) !u16 {
    if (port > std.math.maxInt(u16)) return error.InvalidArgument;
    return @as(u16, @intCast(port));
}

fn timevalFromNs(ns: u64) !Timeval {
    const sec = ns / std.time.ns_per_s;
    const usec = (ns % std.time.ns_per_s) / std.time.ns_per_us;
    return .{
        .sec = std.math.cast(TimevalSec, sec) orelse return error.InvalidArgument,
        .usec = std.math.cast(TimevalUsec, usec) orelse return error.InvalidArgument,
    };
}

fn nsFromTimeval(tv: Timeval) !u64 {
    const sec = std.math.cast(u64, tv.sec) orelse return error.InvalidArgument;
    const usec = std.math.cast(u64, tv.usec) orelse return error.InvalidArgument;
    const sec_ns = std.math.mul(u64, sec, std.time.ns_per_s) catch return error.InvalidArgument;
    const usec_ns = std.math.mul(u64, usec, std.time.ns_per_us) catch return error.InvalidArgument;
    return std.math.add(u64, sec_ns, usec_ns) catch return error.InvalidArgument;
}

fn setSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32, enabled: bool) !void {
    var value: i32 = if (enabled) 1 else 0;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&value));
}

fn setSocketOptInt(fd: std.posix.fd_t, level: i32, optname: u32, value: i32) !void {
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

fn setSocketOptTimeval(fd: std.posix.fd_t, level: i32, optname: u32, ns: u64) !void {
    const tv = try timevalFromNs(ns);
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&tv));
}

fn getSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32) !bool {
    var value: i32 = 0;
    var len: std.posix.socklen_t = @sizeOf(i32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {
            std.debug.assert(len == @sizeOf(i32));
            return value != 0;
        },
        else => return error.InvalidArgument,
    }
}

fn getSocketOptInt(fd: std.posix.fd_t, level: i32, optname: u32) !i32 {
    var value: i32 = 0;
    var len: std.posix.socklen_t = @sizeOf(i32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {
            std.debug.assert(len == @sizeOf(i32));
            return value;
        },
        else => return error.InvalidArgument,
    }
}

fn getSocketOptTimeval(fd: std.posix.fd_t, level: i32, optname: u32) !u64 {
    var tv: Timeval = .{ .sec = 0, .usec = 0 };
    var len: std.posix.socklen_t = @sizeOf(Timeval);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&tv)), &len);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {
            std.debug.assert(len == @sizeOf(Timeval));
            return try nsFromTimeval(tv);
        },
        else => return error.InvalidArgument,
    }
}

fn socketFdFromHandle(handle: u64) !std.posix.fd_t {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    return try handleToFd(handle);
}

fn ensureSocketHandle(handle: u64) !struct { fd: std.posix.fd_t, kind: enum { tcp_stream, tcp_listener, udp_socket } } {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
    return switch (resource.*) {
        .tcp_stream => |stream| .{ .fd = stream.handle, .kind = .tcp_stream },
        .tcp_listener => |server| .{ .fd = server.stream.handle, .kind = .tcp_listener },
        .udp_socket => |fd| .{ .fd = fd, .kind = .udp_socket },
        else => error.InvalidHandle,
    };
}

fn dynamicIndex(handle: u64) ?usize {
    if (handle < FIRST_DYNAMIC_HANDLE) return null;
    const raw = handle - FIRST_DYNAMIC_HANDLE;
    if (raw > @as(u64, @intCast(std.math.maxInt(usize)))) return null;
    return @as(usize, @intCast(raw));
}

fn getResourceLocked(handle: u64) ?*Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= registry_slots.items.len) return null;
    if (registry_slots.items[idx]) |*resource| return resource;
    return null;
}

fn registerResourceLocked(resource: Resource) !u64 {
    for (registry_slots.items, 0..) |slot, idx| {
        if (slot == null) {
            registry_slots.items[idx] = resource;
            return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
        }
    }
    const idx = registry_slots.items.len;
    try registry_slots.append(resource);
    return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
}

fn registerResource(resource: Resource) !u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    return try registerResourceLocked(resource);
}

fn takeResourceLocked(handle: u64) ?Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= registry_slots.items.len) return null;
    const resource = registry_slots.items[idx] orelse return null;
    registry_slots.items[idx] = null;
    return resource;
}

fn handleToFd(handle: u64) !std.posix.fd_t {
    return switch (handle) {
        SA_STD_STDIN => std.posix.STDIN_FILENO,
        SA_STD_STDOUT => std.posix.STDOUT_FILENO,
        SA_STD_STDERR => std.posix.STDERR_FILENO,
        else => {
            const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
            return switch (resource.*) {
                .file => |file| file.handle,
                .tcp_stream => |stream| stream.handle,
                .tcp_listener => |server| server.stream.handle,
                .udp_socket => |fd| fd,
                .owned_fd => |fd| fd.fd,
                .terminal_session => |session| session.fd,
                else => error.InvalidHandle,
            };
        },
    };
}

fn applyRawMode(term: *std.posix.termios) void {
    term.iflag.IGNBRK = false;
    term.iflag.BRKINT = false;
    term.iflag.PARMRK = false;
    term.iflag.ISTRIP = false;
    term.iflag.INLCR = false;
    term.iflag.IGNCR = false;
    term.iflag.ICRNL = false;
    term.iflag.IXON = false;
    term.iflag.IXOFF = false;
    term.oflag.OPOST = false;
    term.cflag.CSIZE = .CS8;
    term.cflag.PARENB = false;
    term.cflag.CREAD = true;
    term.lflag.ISIG = false;
    term.lflag.ICANON = false;
    term.lflag.ECHO = false;
    term.lflag.IEXTEN = false;
    term.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    term.cc[@intFromEnum(std.posix.V.TIME)] = 0;
}

fn killAndWaitChild(pid: std.posix.pid_t) void {
    std.posix.kill(pid, std.posix.SIG.KILL) catch {};
    _ = std.posix.waitpid(pid, 0);
}

fn writeHandleLocked(handle: u64, data: []const u8) !usize {
    return switch (handle) {
        SA_STD_STDOUT => try std.io.getStdOut().write(data),
        SA_STD_STDERR => try std.io.getStdErr().write(data),
        SA_STD_STDIN => error.InvalidHandle,
        else => {
            const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
            return switch (resource.*) {
                .file => |file| try file.write(data),
                .tcp_stream => |stream| try stream.write(data),
                .owned_fd => |fd| try std.posix.write(fd.fd, data),
                .terminal_session => |session| try std.posix.write(session.fd, data),
                else => error.InvalidHandle,
            };
        },
    };
}

fn readHandleLocked(handle: u64, buffer: []u8) !usize {
    return switch (handle) {
        SA_STD_STDIN => try std.io.getStdIn().read(buffer),
        SA_STD_STDOUT, SA_STD_STDERR => error.InvalidHandle,
        else => {
            const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
            return switch (resource.*) {
                .file => |file| try file.read(buffer),
                .tcp_stream => |stream| try stream.read(buffer),
                .owned_fd => |fd| try std.posix.read(fd.fd, buffer),
                .terminal_session => |session| try std.posix.read(session.fd, buffer),
                .buffer => |*buf| blk: {
                    const copy_len = @min(buffer.len, buf.bytes.len);
                    @memcpy(buffer[0..copy_len], buf.bytes[0..copy_len]);
                    break :blk copy_len;
                },
                .process => |*proc| {
                    if (!proc.capture_output) return error.InvalidHandle;
                    if (!proc.exited) return error.InvalidHandle;
                    if (proc.stdout_pos < proc.stdout_buf.len) {
                        const remaining = proc.stdout_buf.len - proc.stdout_pos;
                        const copy_len = @min(buffer.len, remaining);
                        @memcpy(buffer[0..copy_len], proc.stdout_buf[proc.stdout_pos .. proc.stdout_pos + copy_len]);
                        proc.stdout_pos += copy_len;
                        return copy_len;
                    }
                    if (proc.stderr_pos < proc.stderr_buf.len) {
                        const remaining = proc.stderr_buf.len - proc.stderr_pos;
                        const copy_len = @min(buffer.len, remaining);
                        @memcpy(buffer[0..copy_len], proc.stderr_buf[proc.stderr_pos .. proc.stderr_pos + copy_len]);
                        proc.stderr_pos += copy_len;
                        return copy_len;
                    }
                    return 0;
                },
                else => error.InvalidHandle,
            };
        },
    };
}

fn statusName(code: i32) []const u8 {
    return switch (code) {
        SA_STD_OK => "ok",
        SA_STD_ERR_INVALID_ARGUMENT => "invalid_argument",
        SA_STD_ERR_INVALID_HANDLE => "invalid_handle",
        SA_STD_ERR_NOT_FOUND => "not_found",
        SA_STD_ERR_ACCESS => "access",
        SA_STD_ERR_NO_MEMORY => "no_memory",
        SA_STD_ERR_IO => "io",
        SA_STD_ERR_NET => "net",
        SA_STD_ERR_UNSUPPORTED => "unsupported",
        SA_STD_ERR_TRUNCATED => "truncated",
        SA_STD_ERR_UNKNOWN => "unknown",
        else => "unknown",
    };
}

fn statusFromTerm(term: std.process.Child.Term) u32 {
    return switch (term) {
        .Exited => |code| code,
        .Signal => |_| 128,
        .Stopped => |_| 130,
        .Unknown => |_| 127,
    };
}

fn argvFromBlob(allocator: std.mem.Allocator, blob: []const u8) ![]const []const u8 {
    var count: usize = 1;
    for (blob) |b| {
        if (b == 0) count += 1;
    }
    const args = try allocator.alloc([]const u8, count);
    errdefer allocator.free(args);

    var start: usize = 0;
    var index: usize = 0;
    while (start <= blob.len) {
        const end = std.mem.indexOfScalarPos(u8, blob, start, 0) orelse blob.len;
        if (end == start) {
            if (end == blob.len) break;
            start = end + 1;
            continue;
        }
        args[index] = blob[start..end];
        index += 1;
        if (end == blob.len) break;
        start = end + 1;
    }
    return args[0..index];
}

fn argvFromEntries(allocator: std.mem.Allocator, argv_ptr: ?[*]const SaProcessArgv, argv_len: u64) ![]const []const u8 {
    const count = try lenAsUsize(argv_len);
    if (count == 0) return error.InvalidArgument;
    const entries = argv_ptr orelse return error.InvalidArgument;
    const args = try allocator.alloc([]const u8, count);
    errdefer allocator.free(args);

    for (args, 0..) |*slot, index| {
        const entry = entries[index];
        const n = try lenAsUsize(entry.len);
        slot.* = if (n == 0) &.{} else entry.data[0..n];
    }
    return args;
}

fn envpFromCurrentProcess(arena: std.mem.Allocator) ![:null]const ?[*:0]const u8 {
    if (builtin.is_test) {
        const env_block = try arena.alloc(?[*:0]const u8, std.os.environ.len + 1);
        for (std.os.environ, 0..) |entry, i| {
            env_block[i] = entry;
        }
        env_block[std.os.environ.len] = null;
        return env_block[0..std.os.environ.len :null];
    }

    var count: usize = 0;
    while (environ[count] != null) : (count += 1) {}

    const env_block = try arena.alloc(?[*:0]const u8, count + 1);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        env_block[i] = environ[i].?;
    }
    env_block[count] = null;
    return env_block[0..count :null];
}

fn capture_fd_to_owned(allocator: std.mem.Allocator, fd: std.posix.fd_t) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &buf) catch |err| switch (err) {
            error.WouldBlock => break,
            else => return err,
        };
        if (n == 0) break;
        try list.appendSlice(buf[0..n]);
    }
    return try list.toOwnedSlice();
}

const ProcessSpawnMode = enum {
    inherit,
    capture,
    stream,
};

const SpawnResult = struct {
    process: u64 = 0,
    stdout: ?u64 = null,
    stderr: ?u64 = null,
};

fn statusFromWaitStatus(status: u32) u32 {
    if (std.posix.W.IFEXITED(status)) return @as(u32, @intCast(std.posix.W.EXITSTATUS(status)));
    if (std.posix.W.IFSIGNALED(status)) return 128 + @as(u32, @intCast(std.posix.W.TERMSIG(status)));
    if (std.posix.W.IFSTOPPED(status)) return 130;
    return 127;
}

fn spawnProcessCwd(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode, cwd: ?[]const u8) !SpawnResult {
    if (argv.len == 0) return error.InvalidArgument;

    const use_pipes = mode != .inherit;
    var stdout_pipe: [2]std.posix.fd_t = .{ -1, -1 };
    var stderr_pipe: [2]std.posix.fd_t = .{ -1, -1 };
    defer {
        if (stdout_pipe[0] != -1) std.posix.close(stdout_pipe[0]);
        if (stdout_pipe[1] != -1) std.posix.close(stdout_pipe[1]);
        if (stderr_pipe[0] != -1) std.posix.close(stderr_pipe[0]);
        if (stderr_pipe[1] != -1) std.posix.close(stderr_pipe[1]);
    }
    if (use_pipes) {
        stdout_pipe = try std.posix.pipe2(.{ .CLOEXEC = true });
        stderr_pipe = try std.posix.pipe2(.{ .CLOEXEC = true });
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const child_argv = try arena.allocator().alloc(?[*:0]const u8, argv.len + 1);
    for (argv, 0..) |arg, i| {
        child_argv[i] = (try arena.allocator().dupeZ(u8, arg)).ptr;
    }
    child_argv[argv.len] = null;
    const envp = try envpFromCurrentProcess(arena.allocator());

    const pid = try std.posix.fork();
    if (pid == 0) {
        if (cwd) |dir| {
            std.posix.chdir(dir) catch std.posix.exit(127);
        }
        if (use_pipes) {
            std.posix.close(stdout_pipe[0]);
            std.posix.close(stderr_pipe[0]);
            try std.posix.dup2(stdout_pipe[1], std.posix.STDOUT_FILENO);
            try std.posix.dup2(stderr_pipe[1], std.posix.STDERR_FILENO);
        }
        if (use_pipes) {
            std.posix.close(stdout_pipe[1]);
            std.posix.close(stderr_pipe[1]);
        }
        const path = child_argv[0].?;
        const argv_z: [*:null]const ?[*:0]const u8 = @ptrCast(child_argv.ptr);
        const envp_z: [*:null]const ?[*:0]const u8 = @ptrCast(envp.ptr);
        const exec_err = std.posix.execvpeZ(path, argv_z, envp_z);
        switch (exec_err) {
            error.AccessDenied,
            error.SystemResources,
            error.Unexpected,
            error.FileNotFound,
            error.NameTooLong,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            error.IsDir,
            error.NotDir,
            error.FileBusy,
            error.FileSystem,
            error.InvalidExe,
            => std.posix.exit(127),
        }
        unreachable;
    }

    if (use_pipes) {
        std.posix.close(stdout_pipe[1]);
        std.posix.close(stderr_pipe[1]);
        stdout_pipe[1] = -1;
        stderr_pipe[1] = -1;
    }

    var result: SpawnResult = .{};
    switch (mode) {
        .inherit => {
            result.process = try registerResource(.{ .process = .{
                .pid = pid,
                .capture_output = false,
            } });
            return result;
        },
        .capture => {
            result.process = registerResource(.{ .process = .{
                .pid = pid,
                .capture_output = true,
                .stdout_fd = stdout_pipe[0],
                .stderr_fd = stderr_pipe[0],
            } }) catch |err| {
                killAndWaitChild(pid);
                return err;
            };
            stdout_pipe[0] = -1;
            stderr_pipe[0] = -1;
            return result;
        },
        .stream => {
            result.stdout = registerResource(.{ .owned_fd = .{ .fd = stdout_pipe[0] } }) catch |err| {
                killAndWaitChild(pid);
                return err;
            };
            stdout_pipe[0] = -1;
            result.stderr = registerResource(.{ .owned_fd = .{ .fd = stderr_pipe[0] } }) catch |err| {
                if (result.stdout) |stdout_handle| _ = sa_std_close(stdout_handle);
                killAndWaitChild(pid);
                return err;
            };
            stderr_pipe[0] = -1;
            result.process = registerResource(.{ .process = .{
                .pid = pid,
                .capture_output = false,
            } }) catch |err| {
                if (result.stdout) |stdout_handle| _ = sa_std_close(stdout_handle);
                if (result.stderr) |stderr_handle| _ = sa_std_close(stderr_handle);
                killAndWaitChild(pid);
                return err;
            };
            return result;
        },
    }
}

fn spawnProcess(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode) !SpawnResult {
    return spawnProcessCwd(allocator, argv, mode, null);
}

fn formatInteger(value: anytype, base: u32) ![]u8 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return error.InvalidArgument,
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrintIntToSlice(&buf, value, actual_base, case, .{});
    return std.heap.page_allocator.dupe(u8, text);
}

fn formatFloat(value: f64, precision: u32) ![]u8 {
    var buf: [256]u8 = undefined;
    const text = try std.fmt.formatFloat(&buf, value, .{ .mode = .decimal, .precision = @as(usize, @intCast(precision)) });
    return std.heap.page_allocator.dupe(u8, text);
}

fn formatBool(value: bool) ![]u8 {
    return std.heap.page_allocator.dupe(u8, if (value) "true" else "false");
}

fn formatBytes(bytes: []const u8) ![]u8 {
    return std.heap.page_allocator.dupe(u8, bytes);
}

fn writeFormattedInto(out: ?[*]u8, out_cap: u64, out_len: ?*u64, text: []const u8) i32 {
    if (out_len) |ptr| ptr.* = @as(u64, @intCast(text.len));
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (buffer.len < text.len) return finish(SA_STD_ERR_TRUNCATED);
    if (text.len != 0) @memcpy(buffer[0..text.len], text);
    return finish(SA_STD_OK);
}

fn stringConcat(left: []const u8, right: []const u8) ![]u8 {
    var bytes = try std.heap.page_allocator.alloc(u8, left.len + right.len);
    if (left.len != 0) std.mem.copyForwards(u8, bytes[0..left.len], left);
    if (right.len != 0) std.mem.copyForwards(u8, bytes[left.len .. left.len + right.len], right);
    return bytes;
}

fn longestSuffixPrefix(text: []const u8, prefix: []const u8) usize {
    if (text.len == 0 or prefix.len == 0) return 0;
    const max_len = @min(text.len, prefix.len - 1);
    var len = max_len;
    while (len > 0) : (len -= 1) {
        if (std.mem.eql(u8, text[text.len - len ..], prefix[0..len])) return len;
    }
    return 0;
}

fn openOwnedBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .fmt = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}

fn openOwnedByteBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}

fn openOwnedEnvBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .env = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}

const ThoughtStreamSplitter = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(u8),
    in_thought: bool = false,

    fn init(allocator: std.mem.Allocator) ThoughtStreamSplitter {
        return .{
            .allocator = allocator,
            .pending = std.ArrayList(u8).init(allocator),
            .in_thought = false,
        };
    }

    fn deinit(self: *ThoughtStreamSplitter) void {
        self.pending.deinit();
    }

    fn consume(self: *ThoughtStreamSplitter, chunk: []const u8, visible: *std.ArrayList(u8), reasoning: *std.ArrayList(u8)) !void {
        const open_tag = "<thought>";
        const close_tag = "</thought>";
        try self.pending.appendSlice(chunk);

        while (self.pending.items.len != 0) {
            if (!self.in_thought) {
                if (std.mem.indexOf(u8, self.pending.items, open_tag)) |open_index| {
                    if (open_index > 0) try visible.appendSlice(self.pending.items[0..open_index]);
                    try self.pending.replaceRange(0, open_index + open_tag.len, &.{});
                    self.in_thought = true;
                    continue;
                }

                const keep = longestSuffixPrefix(self.pending.items, open_tag);
                const emit_len = self.pending.items.len - keep;
                if (emit_len > 0) try visible.appendSlice(self.pending.items[0..emit_len]);
                try self.pending.replaceRange(0, emit_len, &.{});
                break;
            }

            if (std.mem.indexOf(u8, self.pending.items, close_tag)) |close_index| {
                if (close_index > 0) try reasoning.appendSlice(self.pending.items[0..close_index]);
                try self.pending.replaceRange(0, close_index + close_tag.len, &.{});
                self.in_thought = false;
                continue;
            }

            const keep = longestSuffixPrefix(self.pending.items, close_tag);
            const emit_len = self.pending.items.len - keep;
            if (emit_len > 0) try reasoning.appendSlice(self.pending.items[0..emit_len]);
            try self.pending.replaceRange(0, emit_len, &.{});
            break;
        }
    }

    fn flush(self: *ThoughtStreamSplitter, visible: *std.ArrayList(u8), reasoning: *std.ArrayList(u8)) !void {
        if (self.pending.items.len != 0) {
            if (self.in_thought) {
                try reasoning.appendSlice(self.pending.items);
            } else {
                try visible.appendSlice(self.pending.items);
            }
            self.pending.clearRetainingCapacity();
        }
        self.in_thought = false;
    }
};

fn appendJsonString(writer: anytype, text: []const u8) !void {
    try std.json.stringify(text, .{}, writer);
}

fn jsonStringLiteralAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try appendJsonString(out.writer(), text);
    return try out.toOwnedSlice();
}

fn jsonRpcParamLookupKey(key: []const u8) []const u8 {
    if (key.len > 2 and key[0] == '"') {
        if (std.mem.indexOfScalar(u8, key[1..], '"')) |end| {
            if (end > 0) return key[1 .. 1 + end];
        }
    }
    return key;
}

fn jsonRpcParamsStringLiteralAlloc(body: []const u8, key: []const u8, fallback: []const u8, emit_null_if_missing: bool) ![]u8 {
    const lookup_key = jsonRpcParamLookupKey(key);
    if (lookup_key.len != 0) {
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch null;
        if (parsed) |*document| {
            defer document.deinit();
            if (jsonObjectGetValue(document.value, "params")) |params| {
                if (jsonObjectGetValue(params, lookup_key)) |value| {
                    if (jsonTextSlice(value)) |text| {
                        return try jsonStringLiteralAlloc(std.heap.page_allocator, text);
                    }
                }
            }
        }
    }

    if (emit_null_if_missing) return try std.heap.page_allocator.dupe(u8, "null");
    return try jsonStringLiteralAlloc(std.heap.page_allocator, fallback);
}

fn jsonU64Value(value: ?std.json.Value) u64 {
    const actual = value orelse return 0;
    return switch (actual) {
        .integer => |inner| if (inner >= 0) @as(u64, @intCast(inner)) else 0,
        .float => |inner| if (inner >= 0 and inner <= @as(f64, @floatFromInt(std.math.maxInt(u64)))) @as(u64, @intFromFloat(inner)) else 0,
        else => 0,
    };
}

fn appendResponseCreated(out: *std.ArrayList(u8)) !void {
    try out.appendSlice("event: response.created\n");
    try out.appendSlice("data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_chat_fb\"}}\n\n");
}

fn appendReasoningDelta(
    out: *std.ArrayList(u8),
    reasoning_started: *bool,
    reasoning_done: *bool,
    reasoning_output_index: *u64,
    next_output_index: *u64,
    text: []const u8,
) !void {
    if (text.len == 0) return;
    const writer = out.writer();
    if (reasoning_done.*) {
        reasoning_started.* = false;
        reasoning_done.* = false;
    }
    if (!reasoning_started.*) {
        reasoning_output_index.* = next_output_index.*;
        next_output_index.* += 1;
        try out.appendSlice("event: response.output_item.added\n");
        try out.appendSlice("data: {\"type\":\"response.output_item.added\",\"output_index\":");
        try writer.print("{}", .{reasoning_output_index.*});
        try out.appendSlice(",\"item\":{\"id\":\"think_chat_fb\",\"type\":\"reasoning\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"\"}]}}\n\n");
        try out.appendSlice("event: response.reasoning_summary_part.added\n");
        try out.appendSlice("data: {\"type\":\"response.reasoning_summary_part.added\",\"item_id\":\"think_chat_fb\",\"output_index\":");
        try writer.print("{}", .{reasoning_output_index.*});
        try out.appendSlice(",\"summary_index\":0}\n\n");
        reasoning_started.* = true;
    }
    try out.appendSlice("event: response.reasoning_summary_text.delta\n");
    try out.appendSlice("data: {\"type\":\"response.reasoning_summary_text.delta\",\"item_id\":\"think_chat_fb\",\"output_index\":");
    try writer.print("{}", .{reasoning_output_index.*});
    try out.appendSlice(",\"summary_index\":0,\"delta\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}\n\n");
}

fn appendReasoningDone(
    out: *std.ArrayList(u8),
    reasoning_started: bool,
    reasoning_done: *bool,
    reasoning_output_index: u64,
    reasoning_text: []const u8,
) !void {
    if (!reasoning_started) return;
    if (reasoning_done.*) return;
    const writer = out.writer();
    try out.appendSlice("event: response.output_item.done\n");
    try out.appendSlice("data: {\"type\":\"response.output_item.done\",\"output_index\":");
    try writer.print("{}", .{reasoning_output_index});
    try out.appendSlice(",\"item\":{\"id\":\"think_chat_fb\",\"type\":\"reasoning\",\"summary\":[{\"type\":\"summary_text\",\"text\":");
    try appendJsonString(writer, reasoning_text);
    try out.appendSlice("}],\"encrypted_content\":null,\"content\":[{\"type\":\"reasoning_text\",\"text\":");
    try appendJsonString(writer, reasoning_text);
    try out.appendSlice("}]}}\n\n");
    reasoning_done.* = true;
}

fn appendMessageDelta(
    out: *std.ArrayList(u8),
    message_started: *bool,
    message_output_index: *u64,
    next_output_index: *u64,
    message_text: *std.ArrayList(u8),
    text: []const u8,
) !void {
    if (text.len == 0) return;
    const writer = out.writer();
    if (!message_started.*) {
        message_output_index.* = next_output_index.*;
        next_output_index.* += 1;
        try out.appendSlice("event: response.output_item.added\n");
        try out.appendSlice("data: {\"type\":\"response.output_item.added\",\"output_index\":");
        try writer.print("{}", .{message_output_index.*});
        try out.appendSlice(",\"item\":{\"id\":\"msg_chat_fb\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"\"}]}}\n\n");
        message_started.* = true;
    }
    try message_text.appendSlice(text);
    try out.appendSlice("event: response.output_text.delta\n");
    try out.appendSlice("data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_chat_fb\",\"output_index\":");
    try writer.print("{}", .{message_output_index.*});
    try out.appendSlice(",\"content_index\":0,\"delta\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}\n\n");
}

fn appendMessageDone(out: *std.ArrayList(u8), message_started: bool, message_output_index: u64, message_text: []const u8) !void {
    if (!message_started) return;
    const writer = out.writer();
    try out.appendSlice("event: response.output_item.done\n");
    try out.appendSlice("data: {\"type\":\"response.output_item.done\",\"output_index\":");
    try writer.print("{}", .{message_output_index});
    try out.appendSlice(",\"item\":{\"id\":\"msg_chat_fb\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":");
    try appendJsonString(writer, message_text);
    try out.appendSlice("}]}}\n\n");
}

fn requestAllowsContinuation(req_body: []const u8) bool {
    if (std.mem.indexOf(u8, req_body, "\"name\":\"exec_command\"") == null) return false;
    if (std.mem.indexOf(u8, req_body, "<goal_context>") != null) return true;
    if (std.mem.indexOf(u8, req_body, "\"mode\":\"goal\"") != null) return true;
    if (std.mem.indexOf(u8, req_body, "\"kind\":\"goal\"") != null) return true;
    if (std.mem.indexOf(u8, req_body, "\"collaborationModeKind\":\"goal\"") != null) return true;
    if (std.mem.indexOf(u8, req_body, "\"mode\":\"code\"") != null) return true;
    if (std.mem.indexOf(u8, req_body, "\"kind\":\"code\"") != null) return true;
    if (std.mem.indexOf(u8, req_body, "\"collaborationModeKind\":\"code\"") != null) return true;
    if (std.mem.indexOf(u8, req_body, "# Collaboration Mode: Default") != null) return true;
    return false;
}

fn isProgressOnlyText(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return false;
    if (std.mem.indexOf(u8, trimmed, "<proposed_plan>") != null or
        std.mem.indexOf(u8, trimmed, "</proposed_plan>") != null or
        std.mem.indexOf(u8, trimmed, "我已完成") != null or
        std.mem.indexOf(u8, trimmed, "结论") != null or
        std.mem.indexOf(u8, trimmed, "总结") != null or
        std.mem.indexOf(u8, trimmed, "summary") != null or
        std.mem.indexOf(u8, trimmed, "conclusion") != null or
        std.mem.indexOf(u8, trimmed, "completed") != null)
    {
        return false;
    }
    if (std.mem.indexOf(u8, trimmed, "Let me ") != null or
        std.mem.indexOf(u8, trimmed, "let me ") != null or
        std.mem.indexOf(u8, trimmed, "I'll ") != null or
        std.mem.indexOf(u8, trimmed, "I will ") != null or
        std.mem.indexOf(u8, trimmed, "我先") != null or
        std.mem.indexOf(u8, trimmed, "我会") != null or
        std.mem.indexOf(u8, trimmed, "接下来") != null)
    {
        return std.mem.indexOf(u8, trimmed, "check") != null or
            std.mem.indexOf(u8, trimmed, "inspect") != null or
            std.mem.indexOf(u8, trimmed, "read") != null or
            std.mem.indexOf(u8, trimmed, "run") != null or
            std.mem.indexOf(u8, trimmed, "verify") != null or
            std.mem.indexOf(u8, trimmed, "review") != null or
            std.mem.indexOf(u8, trimmed, "analyze") != null or
            std.mem.indexOf(u8, trimmed, "analyse") != null or
            std.mem.indexOf(u8, trimmed, "查看") != null or
            std.mem.indexOf(u8, trimmed, "检查") != null or
            std.mem.indexOf(u8, trimmed, "读取") != null or
            std.mem.indexOf(u8, trimmed, "运行") != null or
            std.mem.indexOf(u8, trimmed, "执行") != null or
            std.mem.indexOf(u8, trimmed, "评估") != null or
            std.mem.indexOf(u8, trimmed, "分析") != null;
    }
    return false;
}

fn appendContinuationTool(out: *std.ArrayList(u8)) !void {
    try out.appendSlice("event: response.output_item.done\n");
    try out.appendSlice("data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"tc_chat_continue\",\"type\":\"function_call\",\"call_id\":\"call_chat_continue\",\"name\":\"exec_command\",\"arguments\":\"{\\\"cmd\\\":\\\"printf '%s\\\\n' 'Progress-only message received in chat fallback. Continue now: call a read-only tool if more evidence is needed, otherwise provide the final answer.'\\\"}\"}}\n\n");
}

fn appendContinuationToolJson(out: *std.ArrayList(u8)) !void {
    try out.appendSlice("{\"type\":\"function_call\",\"id\":\"tc_chat_continue\",\"call_id\":\"call_chat_continue\",\"name\":\"exec_command\",\"arguments\":\"{\\\"cmd\\\":\\\"printf '%s\\\\n' 'Progress-only message received in chat fallback. Continue now: call a read-only tool if more evidence is needed, otherwise provide the final answer.'\\\"}\"}");
}

const ChatToolCallState = struct {
    allocator: std.mem.Allocator,
    index: usize,
    call_id: std.ArrayList(u8),
    name: std.ArrayList(u8),
    arguments: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator, index: usize) ChatToolCallState {
        return .{
            .allocator = allocator,
            .index = index,
            .call_id = std.ArrayList(u8).init(allocator),
            .name = std.ArrayList(u8).init(allocator),
            .arguments = std.ArrayList(u8).init(allocator),
        };
    }

    fn deinit(self: *ChatToolCallState) void {
        self.call_id.deinit();
        self.name.deinit();
        self.arguments.deinit();
    }
};

fn shellQuote(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.append('\'');
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice("'\\''");
        } else {
            try out.append(ch);
        }
    }
    try out.append('\'');
    return try out.toOwnedSlice();
}

fn isSensitiveEnvPath(path: []const u8) bool {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse std.math.maxInt(usize);
    const base = if (slash == std.math.maxInt(usize)) path else path[slash + 1 ..];
    if (base.len < 4) return false;
    if (!std.ascii.eqlIgnoreCase(base[0..4], ".env")) return false;
    return base.len == 4 or base[4] == '.';
}

fn appendCommandArguments(out_arguments: *std.ArrayList(u8), command: []const u8) !void {
    try out_arguments.appendSlice("{\"cmd\":");
    try appendJsonString(out_arguments.writer(), command);
    try out_arguments.append('}');
}

fn appendReadCommand(allocator: std.mem.Allocator, path: []const u8, out_arguments: *std.ArrayList(u8)) !void {
    const quoted = try shellQuote(allocator, path);
    defer allocator.free(quoted);
    var command = std.ArrayList(u8).init(allocator);
    defer command.deinit();
    if (isSensitiveEnvPath(path)) {
        try command.appendSlice("sed -E 's/(OPENAI_API_KEY|AUTH|TOKEN|KEY|SECRET)=.*/\\\\1=<redacted>/I' ");
    } else {
        try command.appendSlice("cat ");
    }
    try command.appendSlice(quoted);
    try appendCommandArguments(out_arguments, command.items);
}

fn splitMcpNamespace(name: []const u8) ?struct { namespace: []const u8, tool: []const u8 } {
    if (!std.mem.startsWith(u8, name, "mcp__")) return null;
    const rest_start: usize = 5;
    const rel_end = std.mem.indexOf(u8, name[rest_start..], "__") orelse return null;
    const ns_len = rest_start + rel_end + 2;
    if (name.len <= ns_len) return null;
    const tool_start = if (name[ns_len] == '.') ns_len + 1 else ns_len;
    if (tool_start >= name.len) return null;
    return .{ .namespace = name[0..ns_len], .tool = name[tool_start..] };
}

fn denormalizeMcpServerNameAlloc(allocator: std.mem.Allocator, server: []const u8) ![]u8 {
    var source = server;
    if (std.mem.startsWith(u8, source, "mcp__") and std.mem.endsWith(u8, source, "__") and source.len > 7) {
        source = source[5 .. source.len - 2];
    }
    var out = try allocator.alloc(u8, source.len);
    for (source, 0..) |ch, idx| {
        out[idx] = switch (ch) {
            '_', ' ' => '-',
            else => std.ascii.toLower(ch),
        };
    }
    return out;
}

fn normalizeMcpServerNameAlloc(allocator: std.mem.Allocator, server: []const u8) ![]u8 {
    if (std.mem.eql(u8, server, "Code Index") or
        std.mem.eql(u8, server, "code-index") or
        std.mem.eql(u8, server, "code_index"))
    {
        return allocator.dupe(u8, "mcp__code_index__");
    }
    if (std.mem.eql(u8, server, "Mimir") or std.mem.eql(u8, server, "mimir")) {
        return allocator.dupe(u8, "mcp__mimir__");
    }
    if (std.mem.startsWith(u8, server, "mcp__mcp_") and std.mem.endsWith(u8, server, "___") and server.len > 11) {
        const inner = server[9 .. server.len - 3];
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();
        try out.appendSlice("mcp__");
        try out.appendSlice(inner);
        try out.appendSlice("__");
        return try out.toOwnedSlice();
    }
    if (std.mem.startsWith(u8, server, "mcp__") and std.mem.endsWith(u8, server, "__") and server.len > 7) {
        return allocator.dupe(u8, server);
    }

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.appendSlice("mcp__");
    var last_sep = false;
    for (server) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            try out.append(std.ascii.toLower(ch));
            last_sep = false;
        } else if (!last_sep) {
            try out.append('_');
            last_sep = true;
        }
    }
    while (out.items.len > 5 and out.items[out.items.len - 1] == '_') _ = out.pop();
    try out.appendSlice("__");
    return try out.toOwnedSlice();
}

fn requestMentionsTool(req_body: []const u8, name: []const u8) bool {
    return name.len != 0 and std.mem.indexOf(u8, req_body, name) != null;
}

fn normalizeChatToolArguments(
    allocator: std.mem.Allocator,
    req_body: []const u8,
    name: []const u8,
    arguments: []const u8,
    out_namespace: *std.ArrayList(u8),
    out_name: *std.ArrayList(u8),
    out_arguments: *std.ArrayList(u8),
) !bool {
    if (std.mem.eql(u8, name, "exec_command")) {
        if (!requestMentionsTool(req_body, "exec_command")) return false;
        try out_name.appendSlice("exec_command");
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, arguments, .{}) catch {
            try out_arguments.appendSlice(arguments);
            return true;
        };
        defer parsed.deinit();
        const command = jsonStringValue(jsonObjectGetValue(parsed.value, "command"));
        if (command.len != 0) {
            try appendCommandArguments(out_arguments, command);
            return true;
        }
        try out_arguments.appendSlice(arguments);
        return true;
    }

    if (std.mem.eql(u8, name, "read")) {
        if (!requestMentionsTool(req_body, "exec_command")) return false;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, arguments, .{}) catch return false;
        defer parsed.deinit();
        var path = jsonStringValue(jsonObjectGetValue(parsed.value, "filePath"));
        if (path.len == 0) path = jsonStringValue(jsonObjectGetValue(parsed.value, "path"));
        if (path.len == 0) return false;
        try out_name.appendSlice("exec_command");
        try appendReadCommand(allocator, path, out_arguments);
        return true;
    }

    if (splitMcpNamespace(name)) |split| {
        if (!requestMentionsTool(req_body, split.namespace)) return false;
        try out_namespace.appendSlice(split.namespace);
        try out_name.appendSlice(split.tool);
        try out_arguments.appendSlice(arguments);
        return true;
    }

    if (!requestMentionsTool(req_body, name)) {
        if (!requestMentionsTool(req_body, "exec_command")) return false;
        try out_name.appendSlice("exec_command");
        var message = std.ArrayList(u8).init(allocator);
        defer message.deinit();
        try message.appendSlice("Tool ");
        if (name.len != 0) {
            try message.appendSlice(name);
        } else {
            try message.appendSlice("unknown");
        }
        try message.appendSlice(" is unavailable in chat fallback; continue with exec_command/MCP tools or provide the final answer.");
        const quoted = try shellQuote(allocator, message.items);
        defer allocator.free(quoted);
        var command = std.ArrayList(u8).init(allocator);
        defer command.deinit();
        try command.appendSlice("printf '%s\\n' ");
        try command.appendSlice(quoted);
        try appendCommandArguments(out_arguments, command.items);
        return true;
    }

    try out_name.appendSlice(name);
    try out_arguments.appendSlice(arguments);
    return name.len != 0;
}

fn appendNormalizedToolCall(out: *std.ArrayList(u8), req_body: []const u8, call: *const ChatToolCallState) !void {
    var normalized_namespace = std.ArrayList(u8).init(std.heap.page_allocator);
    defer normalized_namespace.deinit();
    var normalized_name = std.ArrayList(u8).init(std.heap.page_allocator);
    defer normalized_name.deinit();
    var normalized_args = std.ArrayList(u8).init(std.heap.page_allocator);
    defer normalized_args.deinit();
    const ok_norm = try normalizeChatToolArguments(
        std.heap.page_allocator,
        req_body,
        call.name.items,
        call.arguments.items,
        &normalized_namespace,
        &normalized_name,
        &normalized_args,
    );
    if (!ok_norm) return;

    const writer = out.writer();
    try out.appendSlice("event: response.output_item.done\n");
    try out.appendSlice("data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"tc_chat_fb_");
    try writer.print("{}", .{call.index});
    try out.appendSlice("\",\"type\":\"function_call\",\"call_id\":");
    if (call.call_id.items.len != 0) {
        try appendJsonString(writer, call.call_id.items);
    } else {
        try appendJsonString(writer, normalized_name.items);
    }
    try out.appendSlice(",\"name\":");
    try appendJsonString(writer, normalized_name.items);
    try out.appendSlice(",\"arguments\":");
    try appendJsonString(writer, normalized_args.items);
    if (normalized_namespace.items.len != 0) {
        try out.appendSlice(",\"namespace\":");
        try appendJsonString(writer, normalized_namespace.items);
        try out.appendSlice(",\"output_kind\":\"function_call_output\"");
    }
    try out.appendSlice("}}\n\n");
}

fn appendNormalizedToolCallJson(out: *std.ArrayList(u8), req_body: []const u8, call: *const ChatToolCallState) !bool {
    var normalized_namespace = std.ArrayList(u8).init(std.heap.page_allocator);
    defer normalized_namespace.deinit();
    var normalized_name = std.ArrayList(u8).init(std.heap.page_allocator);
    defer normalized_name.deinit();
    var normalized_args = std.ArrayList(u8).init(std.heap.page_allocator);
    defer normalized_args.deinit();
    const ok_norm = try normalizeChatToolArguments(
        std.heap.page_allocator,
        req_body,
        call.name.items,
        call.arguments.items,
        &normalized_namespace,
        &normalized_name,
        &normalized_args,
    );
    if (!ok_norm) return false;

    const writer = out.writer();
    try out.appendSlice("{\"id\":\"tc_chat_fb_");
    try writer.print("{}", .{call.index});
    try out.appendSlice("\",\"type\":\"function_call\",\"call_id\":");
    if (call.call_id.items.len != 0) {
        try appendJsonString(writer, call.call_id.items);
    } else {
        try appendJsonString(writer, normalized_name.items);
    }
    try out.appendSlice(",\"name\":");
    try appendJsonString(writer, normalized_name.items);
    try out.appendSlice(",\"arguments\":");
    try appendJsonString(writer, normalized_args.items);
    if (normalized_namespace.items.len != 0) {
        try out.appendSlice(",\"namespace\":");
        try appendJsonString(writer, normalized_namespace.items);
        try out.appendSlice(",\"output_kind\":\"function_call_output\"");
    }
    try out.append('}');
    return true;
}

fn findToolCallState(calls: *std.ArrayList(ChatToolCallState), index: usize) !*ChatToolCallState {
    for (calls.items) |*call| {
        if (call.index == index) return call;
    }
    try calls.append(ChatToolCallState.init(std.heap.page_allocator, index));
    return &calls.items[calls.items.len - 1];
}

fn parseToolCallIndex(value: std.json.Value) usize {
    return switch (value) {
        .integer => |inner| if (inner >= 0) @as(usize, @intCast(inner)) else 0,
        .float => |inner| if (inner >= 0 and inner <= @as(f64, @floatFromInt(std.math.maxInt(usize)))) @as(usize, @intFromFloat(inner)) else 0,
        else => 0,
    };
}

fn appendResponseDone(out: *std.ArrayList(u8)) !void {
    try out.appendSlice("event: response.done\n");
    try out.appendSlice("data: {\"type\":\"response.done\",\"response\":{\"id\":\"resp_chat_fb\",\"status\":\"completed\"}}\n\n");
    try out.appendSlice("event: response.completed\n");
    try out.appendSlice("data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_chat_fb\",\"status\":\"completed\"}}\n\n");
}

fn appendChatUsageJson(out: *std.ArrayList(u8), usage: ?std.json.Value) !void {
    const prompt_tokens = if (usage) |u| blk: {
        const prompt = jsonU64Value(jsonObjectGetValue(u, "prompt_tokens"));
        break :blk if (prompt != 0) prompt else jsonU64Value(jsonObjectGetValue(u, "input_tokens"));
    } else 0;
    const completion_tokens = if (usage) |u| blk: {
        const completion = jsonU64Value(jsonObjectGetValue(u, "completion_tokens"));
        break :blk if (completion != 0) completion else jsonU64Value(jsonObjectGetValue(u, "output_tokens"));
    } else 0;
    const total_tokens = if (usage) |u| blk: {
        const total = jsonU64Value(jsonObjectGetValue(u, "total_tokens"));
        break :blk if (total != 0) total else prompt_tokens + completion_tokens;
    } else prompt_tokens + completion_tokens;
    const cached_tokens = if (usage) |u| jsonU64Value(jsonObjectGetValue(jsonObjectGetValue(u, "prompt_tokens_details") orelse .null, "cached_tokens")) else 0;
    const reasoning_tokens = if (usage) |u| jsonU64Value(jsonObjectGetValue(jsonObjectGetValue(u, "completion_tokens_details") orelse .null, "reasoning_tokens")) else 0;
    try out.writer().print(
        "\"usage\":{{\"input_tokens\":{},\"input_tokens_details\":{{\"cached_tokens\":{}}},\"output_tokens\":{},\"output_tokens_details\":{{\"reasoning_tokens\":{}}},\"total_tokens\":{}}}",
        .{ prompt_tokens, cached_tokens, completion_tokens, reasoning_tokens, total_tokens },
    );
}

fn appendChatJsonReasoningItem(out: *std.ArrayList(u8), text: []const u8) !void {
    const writer = out.writer();
    try out.appendSlice("{\"type\":\"reasoning\",\"summary\":[{\"type\":\"summary_text\",\"text\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}],\"encrypted_content\":null,\"content\":[{\"type\":\"reasoning_text\",\"text\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}]}");
}

fn appendChatJsonMessageItem(out: *std.ArrayList(u8), text: []const u8) !void {
    const writer = out.writer();
    try out.appendSlice("{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}]}");
}

fn appendOutputComma(out: *std.ArrayList(u8), count: *usize) !void {
    if (count.* != 0) try out.append(',');
    count.* += 1;
}

fn denoChatJsonToResponses(chat_body: []const u8, req_body: []const u8) ![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, chat_body, .{}) catch {
        return std.heap.page_allocator.dupe(u8, chat_body);
    };
    defer parsed.deinit();

    const first_choice = jsonArrayFirst(jsonObjectGetValue(parsed.value, "choices") orelse .null);
    const message = if (first_choice) |choice| jsonObjectGetValue(choice, "message") else null;
    const content = if (message) |msg| jsonStringValue(jsonObjectGetValue(msg, "content")) else "";
    const message_reasoning = if (message) |msg| jsonStringValue(jsonObjectGetValue(msg, "reasoning_content")) else "";

    var splitter = ThoughtStreamSplitter.init(std.heap.page_allocator);
    defer splitter.deinit();
    var visible = std.ArrayList(u8).init(std.heap.page_allocator);
    defer visible.deinit();
    var thought = std.ArrayList(u8).init(std.heap.page_allocator);
    defer thought.deinit();
    try splitter.consume(content, &visible, &thought);
    try splitter.flush(&visible, &thought);

    const trimmed_message_reasoning = std.mem.trim(u8, message_reasoning, " \t\r\n");
    const trimmed_thought = std.mem.trim(u8, thought.items, " \t\r\n");
    const trimmed_visible = std.mem.trim(u8, visible.items, " \t\r\n");

    var reasoning = std.ArrayList(u8).init(std.heap.page_allocator);
    defer reasoning.deinit();
    if (trimmed_message_reasoning.len != 0) try reasoning.appendSlice(trimmed_message_reasoning);
    if (trimmed_thought.len != 0 and !std.mem.eql(u8, trimmed_thought, trimmed_message_reasoning)) {
        if (reasoning.items.len != 0) try reasoning.append('\n');
        try reasoning.appendSlice(trimmed_thought);
    }

    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    const writer = out.writer();
    try out.appendSlice("{\"id\":\"resp_chat_fb\",\"object\":\"response\",\"output\":[");
    var output_count: usize = 0;
    if (reasoning.items.len != 0) {
        try appendOutputComma(&out, &output_count);
        try appendChatJsonReasoningItem(&out, reasoning.items);
    }
    if (trimmed_visible.len != 0) {
        try appendOutputComma(&out, &output_count);
        try appendChatJsonMessageItem(&out, trimmed_visible);
    }

    var tool_count: usize = 0;
    if (message) |msg| {
        if (jsonObjectGetValue(msg, "tool_calls")) |tool_calls_value| {
            switch (tool_calls_value) {
                .array => |array| {
                    for (array.items, 0..) |entry, idx| {
                        const fn_value = jsonObjectGetValue(entry, "function") orelse .null;
                        const call_id = jsonStringValue(jsonObjectGetValue(entry, "id"));
                        const name = jsonStringValue(jsonObjectGetValue(fn_value, "name"));
                        const args = jsonStringValue(jsonObjectGetValue(fn_value, "arguments"));
                        var call = ChatToolCallState.init(std.heap.page_allocator, idx);
                        defer call.deinit();
                        try call.call_id.appendSlice(call_id);
                        try call.name.appendSlice(name);
                        try call.arguments.appendSlice(args);
                        var item = std.ArrayList(u8).init(std.heap.page_allocator);
                        defer item.deinit();
                        if (try appendNormalizedToolCallJson(&item, req_body, &call)) {
                            try appendOutputComma(&out, &output_count);
                            try out.appendSlice(item.items);
                            tool_count += 1;
                        }
                    }
                },
                else => {},
            }
        }
    }

    if (tool_count == 0 and trimmed_visible.len != 0 and requestAllowsContinuation(req_body) and isProgressOnlyText(trimmed_visible)) {
        try appendOutputComma(&out, &output_count);
        try appendContinuationToolJson(&out);
    }

    try out.appendSlice("],\"output_text\":");
    try appendJsonString(writer, trimmed_visible);
    try out.append(',');
    try appendChatUsageJson(&out, if (jsonObjectGetValue(parsed.value, "usage")) |usage| usage else null);
    try out.appendSlice(",\"status\":\"completed\"}");
    return try out.toOwnedSlice();
}

const ThoughtSplit = struct {
    visible: []u8,
    reasoning: []u8,
};

fn splitThoughtTextAlloc(allocator: std.mem.Allocator, text: []const u8) !ThoughtSplit {
    var splitter = ThoughtStreamSplitter.init(allocator);
    defer splitter.deinit();
    var visible = std.ArrayList(u8).init(allocator);
    errdefer visible.deinit();
    var reasoning = std.ArrayList(u8).init(allocator);
    errdefer reasoning.deinit();
    try splitter.consume(text, &visible, &reasoning);
    try splitter.flush(&visible, &reasoning);
    const trimmed_visible = std.mem.trim(u8, visible.items, " \t\r\n");
    const trimmed_reasoning = std.mem.trim(u8, reasoning.items, " \t\r\n");
    const owned_visible = try allocator.dupe(u8, trimmed_visible);
    const owned_reasoning = try allocator.dupe(u8, trimmed_reasoning);
    visible.deinit();
    reasoning.deinit();
    return .{ .visible = owned_visible, .reasoning = owned_reasoning };
}

fn appendMergedReasoningText(out: *std.ArrayList(u8), text: []const u8) !void {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return;
    if (std.mem.indexOf(u8, out.items, trimmed) != null) return;
    if (out.items.len != 0) try out.append('\n');
    try out.appendSlice(trimmed);
}

fn appendReasoningFields(value: std.json.Value, out: *std.ArrayList(u8)) !void {
    const fields = [_][]const u8{ "reasoning", "reasoning_content", "thinking", "thought", "reason", "text" };
    inline for (fields) |field| {
        try appendMergedReasoningText(out, jsonStringValue(jsonObjectGetValue(value, field)));
    }
    if (jsonObjectGetValue(value, "summary")) |summary| {
        switch (summary) {
            .string => |text| try appendMergedReasoningText(out, text),
            .array => |array| {
                for (array.items) |part| {
                    switch (part) {
                        .string => |text| try appendMergedReasoningText(out, text),
                        .object => try appendMergedReasoningText(out, jsonStringValue(jsonObjectGetValue(part, "text"))),
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
    if (jsonObjectGetValue(value, "content")) |content| {
        switch (content) {
            .array => |array| {
                for (array.items) |part| {
                    const part_type = jsonStringValue(jsonObjectGetValue(part, "type"));
                    if (std.mem.eql(u8, part_type, "reasoning_text") or std.mem.eql(u8, part_type, "summary_text")) {
                        try appendMergedReasoningText(out, jsonStringValue(jsonObjectGetValue(part, "text")));
                    }
                }
            },
            else => {},
        }
    }
}

fn isNativeReasoningType(item_type: []const u8) bool {
    return std.mem.eql(u8, item_type, "reasoning") or
        std.mem.eql(u8, item_type, "thinking") or
        std.mem.eql(u8, item_type, "thought") or
        std.mem.eql(u8, item_type, "reason");
}

fn appendNativeReasoningItem(out: *std.ArrayList(u8), id: []const u8, text: []const u8) !void {
    const writer = out.writer();
    try out.appendSlice("{\"id\":");
    if (id.len != 0) {
        try appendJsonString(writer, id);
    } else {
        try appendJsonString(writer, "rs_native_json");
    }
    try out.appendSlice(",\"type\":\"reasoning\",\"summary\":[{\"type\":\"summary_text\",\"text\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}],\"encrypted_content\":null,\"content\":[{\"type\":\"reasoning_text\",\"text\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}]}");
}

fn appendNativeMessageItem(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    item: std.json.Value,
    output_count: *usize,
    has_reasoning: *bool,
) !void {
    var item_reasoning = std.ArrayList(u8).init(allocator);
    defer item_reasoning.deinit();
    const reason_fields = [_][]const u8{ "reasoning", "reasoning_content", "thinking", "thought", "reason" };
    inline for (reason_fields) |field| {
        try appendMergedReasoningText(&item_reasoning, jsonStringValue(jsonObjectGetValue(item, field)));
    }

    var visible_content = std.ArrayList(u8).init(allocator);
    defer visible_content.deinit();
    var content_count: usize = 0;
    if (jsonObjectGetValue(item, "content")) |content| {
        switch (content) {
            .array => |array| {
                for (array.items) |part| {
                    const part_type = jsonStringValue(jsonObjectGetValue(part, "type"));
                    const text = jsonStringValue(jsonObjectGetValue(part, "text"));
                    if ((std.mem.eql(u8, part_type, "output_text") or std.mem.eql(u8, part_type, "text")) and text.len != 0) {
                        const split = try splitThoughtTextAlloc(allocator, text);
                        defer allocator.free(split.visible);
                        defer allocator.free(split.reasoning);
                        try appendMergedReasoningText(&item_reasoning, split.reasoning);
                        if (split.visible.len != 0) {
                            if (content_count != 0) try visible_content.append(',');
                            try visible_content.appendSlice("{\"type\":\"output_text\",\"text\":");
                            try appendJsonString(visible_content.writer(), split.visible);
                            try visible_content.append('}');
                            content_count += 1;
                        }
                    } else {
                        if (content_count != 0) try visible_content.append(',');
                        try std.json.stringify(part, .{}, visible_content.writer());
                        content_count += 1;
                    }
                }
            },
            else => {},
        }
    }

    if (item_reasoning.items.len != 0) {
        try appendOutputComma(out, output_count);
        try appendNativeReasoningItem(out, "", item_reasoning.items);
        has_reasoning.* = true;
    }

    try appendOutputComma(out, output_count);
    const writer = out.writer();
    try out.appendSlice("{\"type\":\"message\",\"role\":");
    const role = jsonStringValue(jsonObjectGetValue(item, "role"));
    try appendJsonString(writer, if (role.len != 0) role else "assistant");
    if (jsonStringValue(jsonObjectGetValue(item, "id")).len != 0) {
        try out.appendSlice(",\"id\":");
        try appendJsonString(writer, jsonStringValue(jsonObjectGetValue(item, "id")));
    }
    try out.appendSlice(",\"content\":[");
    try out.appendSlice(visible_content.items);
    try out.appendSlice("]}");
}

fn appendNativeNormalizedOutput(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    output: ?std.json.Value,
    output_text_reasoning: []const u8,
) !void {
    try out.appendSlice("\"output\":[");
    var output_count: usize = 0;
    var has_reasoning = false;
    if (output) |output_value| {
        switch (output_value) {
            .array => |array| {
                for (array.items) |item| {
                    const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
                    if (isNativeReasoningType(item_type)) {
                        var text = std.ArrayList(u8).init(allocator);
                        defer text.deinit();
                        try appendReasoningFields(item, &text);
                        if (text.items.len != 0) {
                            try appendOutputComma(out, &output_count);
                            try appendNativeReasoningItem(out, jsonStringValue(jsonObjectGetValue(item, "id")), text.items);
                            has_reasoning = true;
                        }
                        continue;
                    }
                    if (std.mem.eql(u8, item_type, "message")) {
                        try appendNativeMessageItem(allocator, out, item, &output_count, &has_reasoning);
                        continue;
                    }
                    try appendOutputComma(out, &output_count);
                    try std.json.stringify(item, .{}, out.writer());
                }
            },
            else => {},
        }
    }
    if (!has_reasoning and output_text_reasoning.len != 0) {
        try appendOutputComma(out, &output_count);
        try appendNativeReasoningItem(out, "", output_text_reasoning);
    }
    try out.append(']');
}

fn denoResponsesJsonNormalize(body: []const u8) ![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch {
        return std.heap.page_allocator.dupe(u8, body);
    };
    defer parsed.deinit();
    const root = switch (parsed.value) {
        .object => |object| object,
        else => return std.heap.page_allocator.dupe(u8, body),
    };

    const output_text = jsonStringValue(root.get("output_text"));
    const output_text_split = try splitThoughtTextAlloc(std.heap.page_allocator, output_text);
    defer std.heap.page_allocator.free(output_text_split.visible);
    defer std.heap.page_allocator.free(output_text_split.reasoning);

    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    try out.append('{');
    var field_count: usize = 0;
    var it = root.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, "output") or std.mem.eql(u8, entry.key_ptr.*, "output_text")) continue;
        if (field_count != 0) try out.append(',');
        try appendJsonString(out.writer(), entry.key_ptr.*);
        try out.append(':');
        try std.json.stringify(entry.value_ptr.*, .{}, out.writer());
        field_count += 1;
    }
    if (field_count != 0) try out.append(',');
    try appendNativeNormalizedOutput(std.heap.page_allocator, &out, root.get("output"), output_text_split.reasoning);
    try out.appendSlice(",\"output_text\":");
    try appendJsonString(out.writer(), output_text_split.visible);
    try out.append('}');
    return try out.toOwnedSlice();
}

fn jsonObjectGetValue(value: std.json.Value, key: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |object| object.get(key),
        else => null,
    };
}

fn jsonArrayFirst(value: std.json.Value) ?std.json.Value {
    return switch (value) {
        .array => |array| if (array.items.len > 0) array.items[0] else null,
        else => null,
    };
}

fn jsonStringValue(value: ?std.json.Value) []const u8 {
    const actual = value orelse return "";
    return switch (actual) {
        .string => |text| text,
        else => "",
    };
}

fn jsonBoolValue(value: ?std.json.Value, default_value: bool) bool {
    const actual = value orelse return default_value;
    return switch (actual) {
        .bool => |inner| inner,
        else => default_value,
    };
}

fn appendJsonFieldName(out: *std.ArrayList(u8), field_count: *usize, name: []const u8) !void {
    if (field_count.* != 0) try out.append(',');
    try appendJsonString(out.writer(), name);
    try out.append(':');
    field_count.* += 1;
}

fn appendSystemText(system_texts: *std.ArrayList(u8), text: []const u8) !void {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return;
    if (system_texts.items.len != 0) try system_texts.appendSlice("\n\n");
    try system_texts.appendSlice(trimmed);
}

fn responseContentTextOnlyAlloc(allocator: std.mem.Allocator, content: std.json.Value) !?[]u8 {
    switch (content) {
        .string => |text| return try allocator.dupe(u8, text),
        .array => |array| {
            var has_non_text = false;
            for (array.items) |part| {
                const part_type = jsonStringValue(jsonObjectGetValue(part, "type"));
                if (!std.mem.eql(u8, part_type, "input_text") and
                    !std.mem.eql(u8, part_type, "text") and
                    !std.mem.eql(u8, part_type, "output_text"))
                {
                    has_non_text = true;
                    break;
                }
            }
            if (has_non_text) return null;
            var out = std.ArrayList(u8).init(allocator);
            errdefer out.deinit();
            for (array.items) |part| {
                try out.appendSlice(jsonStringValue(jsonObjectGetValue(part, "text")));
            }
            return try out.toOwnedSlice();
        },
        else => return null,
    }
}

fn appendMappedResponseContentPart(out: *std.ArrayList(u8), part: std.json.Value) !void {
    const writer = out.writer();
    const part_type = jsonStringValue(jsonObjectGetValue(part, "type"));
    if (std.mem.eql(u8, part_type, "input_text") or
        std.mem.eql(u8, part_type, "text") or
        std.mem.eql(u8, part_type, "output_text"))
    {
        try out.appendSlice("{\"type\":\"text\",\"text\":");
        try appendJsonString(writer, jsonStringValue(jsonObjectGetValue(part, "text")));
        try out.append('}');
        return;
    }
    if (std.mem.eql(u8, part_type, "input_image")) {
        try out.appendSlice("{\"type\":\"image_url\",\"image_url\":{\"url\":");
        try appendJsonString(writer, jsonStringValue(jsonObjectGetValue(part, "image_url")));
        try out.appendSlice("}}");
        return;
    }
    if (std.mem.eql(u8, part_type, "image_url")) {
        try out.appendSlice("{\"type\":\"image_url\",\"image_url\":");
        const image_url = jsonObjectGetValue(part, "image_url") orelse .null;
        switch (image_url) {
            .object => try std.json.stringify(image_url, .{}, writer),
            .string => |url| {
                try out.appendSlice("{\"url\":");
                try appendJsonString(writer, url);
                try out.append('}');
            },
            else => try out.appendSlice("{\"url\":\"\"}"),
        }
        try out.append('}');
        return;
    }
    try std.json.stringify(part, .{}, writer);
}

fn appendResponseContentAsChat(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    content: std.json.Value,
) !bool {
    if (try responseContentTextOnlyAlloc(allocator, content)) |text| {
        try appendJsonString(out.writer(), text);
        return text.len != 0;
    }

    const array = switch (content) {
        .array => |items| items,
        else => return false,
    };
    if (array.items.len == 0) return false;
    try out.append('[');
    var count: usize = 0;
    for (array.items) |part| {
        switch (part) {
            .object => {},
            else => continue,
        }
        if (count != 0) try out.append(',');
        try appendMappedResponseContentPart(out, part);
        count += 1;
    }
    try out.append(']');
    return count != 0;
}

fn isResponsesToolCallType(item_type: []const u8) bool {
    return std.mem.eql(u8, item_type, "function_call") or
        std.mem.eql(u8, item_type, "custom_tool_call") or
        std.mem.eql(u8, item_type, "tool_search_call") or
        std.mem.eql(u8, item_type, "mcp_tool_call");
}

fn isResponsesToolOutputType(item_type: []const u8) bool {
    return std.mem.eql(u8, item_type, "function_call_output") or
        std.mem.eql(u8, item_type, "custom_tool_call_output") or
        std.mem.eql(u8, item_type, "tool_search_output") or
        std.mem.eql(u8, item_type, "mcp_tool_call_output");
}

fn responseToolCallNameForChat(allocator: std.mem.Allocator, item: std.json.Value) ![]const u8 {
    const raw_name = std.mem.trim(u8, jsonStringValue(jsonObjectGetValue(item, "name")), " \t\r\n");
    const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
    if (std.mem.eql(u8, item_type, "mcp_tool_call")) {
        const server = jsonStringValue(jsonObjectGetValue(item, "server"));
        if (server.len != 0 and !std.mem.startsWith(u8, raw_name, server)) {
            var out = std.ArrayList(u8).init(allocator);
            errdefer out.deinit();
            try out.appendSlice(server);
            try out.appendSlice(raw_name);
            return try out.toOwnedSlice();
        }
    }
    return raw_name;
}

fn collectResponseToolCallNames(
    allocator: std.mem.Allocator,
    input_items: []const std.json.Value,
) !std.StringHashMap([]const u8) {
    var call_names = std.StringHashMap([]const u8).init(allocator);
    errdefer call_names.deinit();
    for (input_items) |item| {
        const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
        if (!isResponsesToolCallType(item_type)) continue;
        const call_id = jsonStringValue(jsonObjectGetValue(item, "call_id"));
        if (call_id.len == 0) continue;
        const name = try responseToolCallNameForChat(allocator, item);
        if (name.len == 0) continue;
        try call_names.put(call_id, name);
    }
    return call_names;
}

fn appendChatMessagePrefix(out: *std.ArrayList(u8), message_count: *usize, role: []const u8) !void {
    if (message_count.* != 0) try out.append(',');
    try out.appendSlice("{\"role\":");
    try appendJsonString(out.writer(), role);
    try out.appendSlice(",\"content\":");
    message_count.* += 1;
}

fn appendResponseMessageAsChat(
    allocator: std.mem.Allocator,
    messages: *std.ArrayList(u8),
    message_count: *usize,
    system_texts: *std.ArrayList(u8),
    item: std.json.Value,
) !void {
    const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
    if (!std.mem.eql(u8, item_type, "message") and !std.mem.eql(u8, item_type, "assistant_message")) return;
    const raw_role = blk: {
        const role = jsonStringValue(jsonObjectGetValue(item, "role"));
        if (role.len != 0) break :blk role;
        break :blk if (std.mem.eql(u8, item_type, "message")) "user" else "assistant";
    };
    const role = if (std.mem.eql(u8, raw_role, "developer")) "system" else raw_role;
    const content = jsonObjectGetValue(item, "content") orelse .null;
    if (std.mem.eql(u8, role, "system")) {
        if (try responseContentTextOnlyAlloc(allocator, content)) |text| try appendSystemText(system_texts, text);
        return;
    }

    var content_buf = std.ArrayList(u8).init(allocator);
    errdefer content_buf.deinit();
    if (!try appendResponseContentAsChat(allocator, &content_buf, content)) {
        content_buf.deinit();
        return;
    }
    try appendChatMessagePrefix(messages, message_count, role);
    try messages.appendSlice(content_buf.items);
    try messages.append('}');
}

fn appendResponseToolCallAsChat(
    allocator: std.mem.Allocator,
    input_items: []const std.json.Value,
    index: *usize,
    messages: *std.ArrayList(u8),
    message_count: *usize,
) !void {
    const start_len = messages.items.len;
    if (message_count.* != 0) try messages.append(',');
    try messages.appendSlice("{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[");
    var call_count: usize = 0;
    while (index.* < input_items.len) : (index.* += 1) {
        const item = input_items[index.*];
        const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
        if (!isResponsesToolCallType(item_type)) break;
        const call_id = jsonStringValue(jsonObjectGetValue(item, "call_id"));
        const arguments = jsonStringValue(jsonObjectGetValue(item, "arguments"));
        const chat_name = try responseToolCallNameForChat(allocator, item);
        if (chat_name.len == 0) continue;
        if (call_count != 0) try messages.append(',');
        try messages.appendSlice("{\"id\":");
        if (call_id.len != 0) {
            try appendJsonString(messages.writer(), call_id);
        } else {
            try messages.writer().print("\"call_{}\"", .{index.*});
        }
        try messages.appendSlice(",\"type\":\"function\",\"function\":{\"name\":");
        try appendJsonString(messages.writer(), chat_name);
        try messages.appendSlice(",\"arguments\":");
        try appendJsonString(messages.writer(), if (arguments.len != 0) arguments else "{}");
        try messages.appendSlice("}}");
        call_count += 1;
    }
    try messages.appendSlice("]}");
    if (call_count == 0) {
        messages.shrinkRetainingCapacity(start_len);
        if (index.* != 0) index.* -= 1;
        return;
    }
    message_count.* += 1;
    if (index.* != 0) index.* -= 1;
}

fn appendResponseToolOutputAsChat(
    allocator: std.mem.Allocator,
    messages: *std.ArrayList(u8),
    message_count: *usize,
    call_names: *const std.StringHashMap([]const u8),
    item: std.json.Value,
) !void {
    const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
    if (!isResponsesToolOutputType(item_type)) return;
    var output_text = jsonStringValue(jsonObjectGetValue(item, "output"));
    if (output_text.len == 0) {
        if (jsonObjectGetValue(item, "output")) |output| {
            const owned_output = try std.json.stringifyAlloc(allocator, output, .{});
            output_text = owned_output;
        } else {
            output_text = jsonStringValue(jsonObjectGetValue(item, "content"));
        }
    }
    if (output_text.len == 0) return;
    try appendChatMessagePrefix(messages, message_count, "tool");
    try appendJsonString(messages.writer(), output_text);
    const call_id = jsonStringValue(jsonObjectGetValue(item, "call_id"));
    if (call_id.len != 0) {
        try messages.appendSlice(",\"tool_call_id\":");
        try appendJsonString(messages.writer(), call_id);
    }
    const explicit_name = std.mem.trim(u8, jsonStringValue(jsonObjectGetValue(item, "name")), " \t\r\n");
    const name = if (explicit_name.len != 0) explicit_name else blk: {
        if (call_id.len == 0) break :blk "";
        break :blk call_names.get(call_id) orelse "";
    };
    if (name.len != 0) {
        try messages.appendSlice(",\"name\":");
        try appendJsonString(messages.writer(), name);
    }
    try messages.append('}');
}

fn appendNormalizedChatTool(
    out: *std.ArrayList(u8),
    tool: std.json.Value,
    namespace_prefix: []const u8,
    tool_count: *usize,
) !void {
    const tool_type = jsonStringValue(jsonObjectGetValue(tool, "type"));
    if (std.mem.eql(u8, tool_type, "namespace")) {
        const nested_prefix = jsonStringValue(jsonObjectGetValue(tool, "name"));
        const nested_tools = jsonObjectGetValue(tool, "tools") orelse .null;
        switch (nested_tools) {
            .array => |array| {
                for (array.items) |nested| try appendNormalizedChatTool(out, nested, nested_prefix, tool_count);
            },
            else => {},
        }
        return;
    }
    if (tool_type.len != 0 and !std.mem.eql(u8, tool_type, "function")) return;

    const fn_value = jsonObjectGetValue(tool, "function") orelse .null;
    const source = switch (fn_value) {
        .object => fn_value,
        else => tool,
    };
    const raw_name = blk: {
        const fn_name = jsonStringValue(jsonObjectGetValue(source, "name"));
        if (fn_name.len != 0) break :blk fn_name;
        break :blk jsonStringValue(jsonObjectGetValue(tool, "name"));
    };
    if (raw_name.len == 0) return;
    if (tool_count.* != 0) try out.append(',');
    try out.appendSlice("{\"type\":\"function\",\"function\":{\"name\":");
    if (namespace_prefix.len != 0 and !std.mem.startsWith(u8, raw_name, namespace_prefix)) {
        var prefixed = std.ArrayList(u8).init(std.heap.page_allocator);
        defer prefixed.deinit();
        try prefixed.appendSlice(namespace_prefix);
        try prefixed.appendSlice(raw_name);
        try appendJsonString(out.writer(), prefixed.items);
    } else {
        try appendJsonString(out.writer(), raw_name);
    }

    const description = blk: {
        const fn_desc = jsonStringValue(jsonObjectGetValue(source, "description"));
        if (fn_desc.len != 0) break :blk fn_desc;
        break :blk jsonStringValue(jsonObjectGetValue(tool, "description"));
    };
    if (description.len != 0) {
        try out.appendSlice(",\"description\":");
        try appendJsonString(out.writer(), description);
    }
    if (jsonObjectGetValue(source, "parameters")) |parameters| {
        try out.appendSlice(",\"parameters\":");
        try std.json.stringify(parameters, .{}, out.writer());
    } else if (jsonObjectGetValue(tool, "parameters")) |parameters| {
        try out.appendSlice(",\"parameters\":");
        try std.json.stringify(parameters, .{}, out.writer());
    }
    const has_strict = jsonObjectGetValue(source, "strict") != null or jsonObjectGetValue(tool, "strict") != null;
    if (has_strict) {
        try out.appendSlice(",\"strict\":");
        try out.appendSlice(if (jsonBoolValue(jsonObjectGetValue(source, "strict"), jsonBoolValue(jsonObjectGetValue(tool, "strict"), false))) "true" else "false");
    }
    try out.appendSlice("}}");
    tool_count.* += 1;
}

fn appendNormalizedChatToolsField(out: *std.ArrayList(u8), field_count: *usize, tools: std.json.Value) !void {
    const array = switch (tools) {
        .array => |items| items,
        else => return,
    };
    var tools_json = std.ArrayList(u8).init(std.heap.page_allocator);
    defer tools_json.deinit();
    var tool_count: usize = 0;
    for (array.items) |tool| try appendNormalizedChatTool(&tools_json, tool, "", &tool_count);
    if (tool_count == 0) return;
    try appendJsonFieldName(out, field_count, "tools");
    try out.append('[');
    try out.appendSlice(tools_json.items);
    try out.append(']');
}

fn appendResponseFormatFromText(out: *std.ArrayList(u8), field_count: *usize, text_value: ?std.json.Value) !void {
    const text = text_value orelse return;
    const format = jsonObjectGetValue(text, "format") orelse return;
    const format_type = jsonStringValue(jsonObjectGetValue(format, "type"));
    if (format_type.len == 0) return;
    try appendJsonFieldName(out, field_count, "response_format");
    if (std.mem.eql(u8, format_type, "json_schema")) {
        try out.appendSlice("{\"type\":\"json_schema\",\"json_schema\":{\"name\":");
        const name = jsonStringValue(jsonObjectGetValue(format, "name"));
        try appendJsonString(out.writer(), if (name.len != 0) name else "codex_output_schema");
        if (jsonObjectGetValue(format, "schema")) |schema| {
            try out.appendSlice(",\"schema\":");
            try std.json.stringify(schema, .{}, out.writer());
        }
        try out.appendSlice(",\"strict\":");
        try out.appendSlice(if (jsonBoolValue(jsonObjectGetValue(format, "strict"), false)) "true" else "false");
        try out.appendSlice("}}");
        return;
    }
    try std.json.stringify(format, .{}, out.writer());
}

fn shouldSkipResponsesFallbackField(key: []const u8) bool {
    return std.mem.eql(u8, key, "input") or
        std.mem.eql(u8, key, "instructions") or
        std.mem.eql(u8, key, "reasoning") or
        std.mem.eql(u8, key, "stream") or
        std.mem.eql(u8, key, "tools") or
        std.mem.eql(u8, key, "content") or
        std.mem.eql(u8, key, "text") or
        std.mem.eql(u8, key, "store") or
        std.mem.eql(u8, key, "prompt_cache_key") or
        std.mem.eql(u8, key, "include") or
        std.mem.eql(u8, key, "model") or
        std.mem.eql(u8, key, "messages") or
        std.mem.eql(u8, key, "response_format");
}

fn denoResponsesChatFallbackRequest(body: []const u8, default_model: []const u8, plan_mode_like: bool) !?[]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, body, .{}) catch return null;
    const root = switch (parsed) {
        .object => |object| object,
        else => return null,
    };
    const model = blk: {
        const body_model = jsonStringValue(root.get("model"));
        break :blk if (body_model.len != 0) body_model else default_model;
    };

    var system_texts = std.ArrayList(u8).init(allocator);
    var messages = std.ArrayList(u8).init(allocator);
    var message_count: usize = 0;
    if (plan_mode_like) {
        try appendSystemText(&system_texts, "Compatibility note: you are using Chat Completions as a Responses API fallback. Do not stop after only a progress update or plan. If you say you will inspect or run something, call an available tool in the same response; otherwise provide the final answer.");
    }
    try appendSystemText(&system_texts, jsonStringValue(root.get("instructions")));

    const input = root.get("input") orelse .null;
    switch (input) {
        .array => |input_array| {
            var call_names = try collectResponseToolCallNames(allocator, input_array.items);
            defer call_names.deinit();
            var index: usize = 0;
            while (index < input_array.items.len) : (index += 1) {
                const item = input_array.items[index];
                const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
                if (isResponsesToolCallType(item_type)) {
                    try appendResponseToolCallAsChat(allocator, input_array.items, &index, &messages, &message_count);
                    continue;
                }
                if (std.mem.eql(u8, item_type, "message") or std.mem.eql(u8, item_type, "assistant_message")) {
                    try appendResponseMessageAsChat(allocator, &messages, &message_count, &system_texts, item);
                    continue;
                }
                if (std.mem.eql(u8, item_type, "reasoning")) continue;
                if (isResponsesToolOutputType(item_type)) {
                    try appendResponseToolOutputAsChat(allocator, &messages, &message_count, &call_names, item);
                }
            }
        },
        else => {},
    }
    if (message_count == 0) {
        const top_text = blk: {
            const input_text = jsonStringValue(root.get("input"));
            if (input_text.len != 0) break :blk input_text;
            const content_text = jsonStringValue(root.get("content"));
            if (content_text.len != 0) break :blk content_text;
            break :blk jsonStringValue(root.get("text"));
        };
        if (top_text.len != 0) {
            try appendChatMessagePrefix(&messages, &message_count, "user");
            try appendJsonString(messages.writer(), top_text);
            try messages.append('}');
        }
    }
    if (system_texts.items.len != 0) {
        var with_system = std.ArrayList(u8).init(allocator);
        var system_count: usize = 0;
        try appendChatMessagePrefix(&with_system, &system_count, "system");
        try appendJsonString(with_system.writer(), system_texts.items);
        try with_system.append('}');
        if (messages.items.len != 0) try with_system.append(',');
        try with_system.appendSlice(messages.items);
        messages = with_system;
        message_count += 1;
    }
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    try out.append('{');
    var field_count: usize = 0;
    var it = root.iterator();
    while (it.next()) |entry| {
        if (shouldSkipResponsesFallbackField(entry.key_ptr.*)) continue;
        try appendJsonFieldName(&out, &field_count, entry.key_ptr.*);
        try std.json.stringify(entry.value_ptr.*, .{}, out.writer());
    }
    try appendResponseFormatFromText(&out, &field_count, root.get("text"));
    try appendJsonFieldName(&out, &field_count, "model");
    try appendJsonString(out.writer(), model);
    try appendJsonFieldName(&out, &field_count, "messages");
    try out.append('[');
    try out.appendSlice(messages.items);
    try out.append(']');
    if (root.get("tools")) |tools| try appendNormalizedChatToolsField(&out, &field_count, tools);
    const stream = jsonBoolValue(root.get("stream"), true);
    try appendJsonFieldName(&out, &field_count, "stream");
    try out.appendSlice(if (stream) "true" else "false");
    if (stream) {
        try appendJsonFieldName(&out, &field_count, "stream_options");
        try out.appendSlice("{\"include_usage\":true}");
    }
    try out.append('}');
    return try out.toOwnedSlice();
}

fn normalizeResponsesArgumentsString(allocator: std.mem.Allocator, arguments: []const u8) !?[]u8 {
    var args_value = std.json.parseFromSliceLeaky(std.json.Value, allocator, arguments, .{}) catch return null;
    const args_object = switch (args_value) {
        .object => |*object| object,
        else => return null,
    };
    const server_ptr = args_object.getPtr("server") orelse return null;
    const server = jsonStringValue(server_ptr.*);
    if (server.len == 0) return null;
    const denormalized = try denormalizeMcpServerNameAlloc(allocator, server);
    server_ptr.* = .{ .string = denormalized };
    return try std.json.stringifyAlloc(allocator, args_value, .{});
}

fn normalizeResponsesRequestArgumentsString(allocator: std.mem.Allocator, arguments: []const u8) !?[]u8 {
    var args_value = std.json.parseFromSliceLeaky(std.json.Value, allocator, arguments, .{}) catch return null;
    const args_object = switch (args_value) {
        .object => |*object| object,
        else => return null,
    };
    const server_ptr = args_object.getPtr("server") orelse return null;
    const server = jsonStringValue(server_ptr.*);
    if (server.len == 0) return null;
    const normalized = try normalizeMcpServerNameAlloc(allocator, server);
    if (std.mem.eql(u8, normalized, server)) return null;
    server_ptr.* = .{ .string = normalized };
    return try std.json.stringifyAlloc(allocator, args_value, .{});
}

fn normalizeResponsesRequestValue(allocator: std.mem.Allocator, value: *std.json.Value) !bool {
    switch (value.*) {
        .object => |*object| {
            var changed = false;
            const item_type = jsonStringValue(object.get("type"));
            if (std.mem.eql(u8, item_type, "function_call")) {
                if (object.getPtr("arguments")) |arguments_ptr| {
                    const arguments = jsonStringValue(arguments_ptr.*);
                    if (arguments.len != 0) {
                        if (try normalizeResponsesRequestArgumentsString(allocator, arguments)) |normalized_arguments| {
                            arguments_ptr.* = .{ .string = normalized_arguments };
                            changed = true;
                        }
                    }
                }
            }
            var it = object.iterator();
            while (it.next()) |entry| {
                if (try normalizeResponsesRequestValue(allocator, entry.value_ptr)) changed = true;
            }
            return changed;
        },
        .array => |*array| {
            var changed = false;
            for (array.items) |*item| {
                if (try normalizeResponsesRequestValue(allocator, item)) changed = true;
            }
            return changed;
        },
        else => return false,
    }
}

fn denoResponsesRequestNormalize(body: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var value = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), body, .{}) catch {
        return std.heap.page_allocator.dupe(u8, body);
    };
    const changed = try normalizeResponsesRequestValue(arena.allocator(), &value);
    if (!changed) return std.heap.page_allocator.dupe(u8, body);
    return try std.json.stringifyAlloc(std.heap.page_allocator, value, .{});
}

fn normalizeResponsesEventData(allocator: std.mem.Allocator, data: []const u8) !?[]u8 {
    var value = std.json.parseFromSliceLeaky(std.json.Value, allocator, data, .{}) catch return null;
    const root = switch (value) {
        .object => |*object| object,
        else => return null,
    };
    const item_ptr = root.getPtr("item") orelse return null;
    const item = switch (item_ptr.*) {
        .object => |*object| object,
        else => return null,
    };

    var changed = false;
    const item_type = jsonStringValue(item.get("type"));
    if (isNativeReasoningType(item_type)) {
        var text = std.ArrayList(u8).init(allocator);
        defer text.deinit();
        try appendReasoningFields(item_ptr.*, &text);
        if (text.items.len != 0) {
            var out = std.ArrayList(u8).init(allocator);
            errdefer out.deinit();
            const writer = out.writer();
            try out.appendSlice("{\"type\":");
            try appendJsonString(writer, jsonStringValue(root.get("type")));
            try out.appendSlice(",\"item\":");
            try appendNativeReasoningItem(&out, jsonStringValue(item.get("id")), text.items);
            try out.append('}');
            return try out.toOwnedSlice();
        }
    }

    if (!std.mem.eql(u8, item_type, "function_call")) return null;

    const name = jsonStringValue(item.get("name"));
    if (splitMcpNamespace(name)) |split| {
        try item.put("name", .{ .string = try allocator.dupe(u8, split.tool) });
        try item.put("namespace", .{ .string = try allocator.dupe(u8, split.namespace) });
        try item.put("output_kind", .{ .string = "function_call_output" });
        changed = true;
    }

    if (item.getPtr("arguments")) |arguments_ptr| {
        const arguments = jsonStringValue(arguments_ptr.*);
        if (arguments.len != 0) {
            if (try normalizeResponsesArgumentsString(allocator, arguments)) |normalized_arguments| {
                arguments_ptr.* = .{ .string = normalized_arguments };
                changed = true;
            }
        }
    }

    if (!changed) return null;
    return try std.json.stringifyAlloc(allocator, value, .{});
}

fn appendNormalizedResponsesSseBlock(out: *std.ArrayList(u8), event_line: ?[]const u8, data: []const u8) !void {
    if (event_line) |line| {
        try out.appendSlice(line);
        try out.append('\n');
    }
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const normalized = try normalizeResponsesEventData(arena.allocator(), data) orelse data;
    try out.appendSlice("data: ");
    try out.appendSlice(normalized);
    try out.appendSlice("\n\n");
}

fn denoResponsesSseNormalize(sse_body: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    var data_buffer = std.ArrayList(u8).init(std.heap.page_allocator);
    defer data_buffer.deinit();
    var event_line: ?[]const u8 = null;

    var line_it = std.mem.splitScalar(u8, sse_body, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (std.mem.startsWith(u8, line, "event:")) {
            if (data_buffer.items.len != 0) {
                try appendNormalizedResponsesSseBlock(&out, event_line, data_buffer.items);
                data_buffer.clearRetainingCapacity();
            } else if (event_line) |pending_event| {
                try out.appendSlice(pending_event);
                try out.append('\n');
            }
            event_line = line;
            continue;
        }
        if (std.mem.startsWith(u8, line, "data:")) {
            const data = std.mem.trimLeft(u8, line[5..], " \t");
            try data_buffer.appendSlice(data);
            continue;
        }
        if (std.mem.trim(u8, line, " \t\r").len == 0) {
            if (data_buffer.items.len != 0) {
                try appendNormalizedResponsesSseBlock(&out, event_line, data_buffer.items);
                data_buffer.clearRetainingCapacity();
                event_line = null;
            } else if (event_line) |pending_event| {
                try out.appendSlice(pending_event);
                try out.appendSlice("\n\n");
                event_line = null;
            } else {
                try out.append('\n');
            }
            continue;
        }
        if (event_line) |pending_event| {
            try out.appendSlice(pending_event);
            try out.append('\n');
            event_line = null;
        }
        try out.appendSlice(line);
        try out.append('\n');
    }
    if (data_buffer.items.len != 0) {
        try appendNormalizedResponsesSseBlock(&out, event_line, data_buffer.items);
    } else if (event_line) |pending_event| {
        try out.appendSlice(pending_event);
        try out.append('\n');
    }
    return try out.toOwnedSlice();
}

fn appendChatSseDataChunk(
    out: *std.ArrayList(u8),
    data: []const u8,
    splitter: *ThoughtStreamSplitter,
    reasoning_started: *bool,
    reasoning_done: *bool,
    reasoning_output_index: *u64,
    reasoning_text: *std.ArrayList(u8),
    message_started: *bool,
    message_output_index: *u64,
    next_output_index: *u64,
    message_text: *std.ArrayList(u8),
    tool_calls: *std.ArrayList(ChatToolCallState),
    saw_stop_without_tool: *bool,
    req_body: []const u8,
) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, data, .{}) catch return;
    defer parsed.deinit();
    const first_choice = jsonArrayFirst(jsonObjectGetValue(parsed.value, "choices") orelse return) orelse return;
    const delta = jsonObjectGetValue(first_choice, "delta");
    if (delta) |delta_value| {
        const reason = jsonStringValue(jsonObjectGetValue(delta_value, "reasoning_content"));
        if (reason.len != 0) {
            if (!message_started.*) {
                try appendReasoningDelta(out, reasoning_started, reasoning_done, reasoning_output_index, next_output_index, reason);
            }
            try reasoning_text.appendSlice(reason);
        }
        const thinking = jsonStringValue(jsonObjectGetValue(delta_value, "thinking"));
        if (thinking.len != 0) {
            if (!message_started.*) {
                try appendReasoningDelta(out, reasoning_started, reasoning_done, reasoning_output_index, next_output_index, thinking);
            }
            try reasoning_text.appendSlice(thinking);
        }
        const content = jsonStringValue(jsonObjectGetValue(delta_value, "content"));
        if (content.len != 0) {
            var visible = std.ArrayList(u8).init(std.heap.page_allocator);
            defer visible.deinit();
            var thought = std.ArrayList(u8).init(std.heap.page_allocator);
            defer thought.deinit();
            try splitter.consume(content, &visible, &thought);
            if (thought.items.len != 0) {
                if (!message_started.*) {
                    try appendReasoningDelta(out, reasoning_started, reasoning_done, reasoning_output_index, next_output_index, thought.items);
                }
                try reasoning_text.appendSlice(thought.items);
            }
            if (visible.items.len != 0) {
                if (!message_started.*) {
                    try appendReasoningDone(out, reasoning_started.*, reasoning_done, reasoning_output_index.*, reasoning_text.items);
                }
                try appendMessageDelta(out, message_started, message_output_index, next_output_index, message_text, visible.items);
            }
        }
        if (jsonObjectGetValue(delta_value, "tool_calls")) |tool_calls_value| {
            switch (tool_calls_value) {
                .array => |array| {
                    for (array.items) |entry| {
                        const index = if (jsonObjectGetValue(entry, "index")) |idx_value| parseToolCallIndex(idx_value) else 0;
                        const state = try findToolCallState(tool_calls, index);
                        const call_id = jsonStringValue(jsonObjectGetValue(entry, "id"));
                        if (call_id.len != 0) {
                            state.call_id.clearRetainingCapacity();
                            try state.call_id.appendSlice(call_id);
                        }
                        if (jsonObjectGetValue(entry, "function")) |fn_value| {
                            const name = jsonStringValue(jsonObjectGetValue(fn_value, "name"));
                            if (name.len != 0) {
                                state.name.clearRetainingCapacity();
                                try state.name.appendSlice(name);
                            }
                            const args_part = jsonStringValue(jsonObjectGetValue(fn_value, "arguments"));
                            if (args_part.len != 0) try state.arguments.appendSlice(args_part);
                        }
                    }
                },
                else => {},
            }
        }
    }
    const finish_reason = jsonStringValue(jsonObjectGetValue(first_choice, "finish_reason"));
    if (std.mem.eql(u8, finish_reason, "stop")) saw_stop_without_tool.* = tool_calls.items.len == 0;
    if (std.mem.eql(u8, finish_reason, "tool_calls") or std.mem.eql(u8, finish_reason, "stop")) {
        std.mem.sort(ChatToolCallState, tool_calls.items, {}, struct {
            fn lessThan(_: void, lhs: ChatToolCallState, rhs: ChatToolCallState) bool {
                return lhs.index < rhs.index;
            }
        }.lessThan);
        for (tool_calls.items) |*call| try appendNormalizedToolCall(out, req_body, call);
        for (tool_calls.items) |*call| call.deinit();
        tool_calls.clearRetainingCapacity();
    }
}

fn denoChatSseToResponses(chat_body: []const u8, req_body: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    var splitter = ThoughtStreamSplitter.init(std.heap.page_allocator);
    defer splitter.deinit();
    var reasoning_text = std.ArrayList(u8).init(std.heap.page_allocator);
    defer reasoning_text.deinit();
    var message_text = std.ArrayList(u8).init(std.heap.page_allocator);
    defer message_text.deinit();
    var reasoning_started = false;
    var reasoning_done = false;
    var reasoning_output_index: u64 = 0;
    var message_started = false;
    var message_output_index: u64 = 0;
    var next_output_index: u64 = 0;
    var saw_stop_without_tool = false;
    var tool_calls = std.ArrayList(ChatToolCallState).init(std.heap.page_allocator);
    defer {
        for (tool_calls.items) |*call| call.deinit();
        tool_calls.deinit();
    }
    var data_buffer = std.ArrayList(u8).init(std.heap.page_allocator);
    defer data_buffer.deinit();

    try appendResponseCreated(&out);

    var line_it = std.mem.splitScalar(u8, chat_body, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (std.mem.startsWith(u8, line, "data:")) {
            const data = std.mem.trimLeft(u8, line[5..], " \t");
            if (!std.mem.eql(u8, data, "[DONE]")) {
                try data_buffer.appendSlice(data);
            }
            continue;
        }
        if (std.mem.trim(u8, line, " \t\r").len != 0 or data_buffer.items.len == 0) continue;
        try appendChatSseDataChunk(
            &out,
            data_buffer.items,
            &splitter,
            &reasoning_started,
            &reasoning_done,
            &reasoning_output_index,
            &reasoning_text,
            &message_started,
            &message_output_index,
            &next_output_index,
            &message_text,
            &tool_calls,
            &saw_stop_without_tool,
            req_body,
        );
        data_buffer.clearRetainingCapacity();
    }
    if (data_buffer.items.len != 0) {
        try appendChatSseDataChunk(
            &out,
            data_buffer.items,
            &splitter,
            &reasoning_started,
            &reasoning_done,
            &reasoning_output_index,
            &reasoning_text,
            &message_started,
            &message_output_index,
            &next_output_index,
            &message_text,
            &tool_calls,
            &saw_stop_without_tool,
            req_body,
        );
    }

    var tail_visible = std.ArrayList(u8).init(std.heap.page_allocator);
    defer tail_visible.deinit();
    var tail_reasoning = std.ArrayList(u8).init(std.heap.page_allocator);
    defer tail_reasoning.deinit();
    try splitter.flush(&tail_visible, &tail_reasoning);
    if (tail_reasoning.items.len != 0) {
        try appendReasoningDelta(&out, &reasoning_started, &reasoning_done, &reasoning_output_index, &next_output_index, tail_reasoning.items);
        try reasoning_text.appendSlice(tail_reasoning.items);
    }
    if (tail_visible.items.len != 0) {
        try appendReasoningDone(&out, reasoning_started, &reasoning_done, reasoning_output_index, reasoning_text.items);
        try appendMessageDelta(&out, &message_started, &message_output_index, &next_output_index, &message_text, tail_visible.items);
    }
    try appendReasoningDone(&out, reasoning_started, &reasoning_done, reasoning_output_index, reasoning_text.items);
    try appendMessageDone(&out, message_started, message_output_index, message_text.items);
    if (saw_stop_without_tool and requestAllowsContinuation(req_body) and isProgressOnlyText(message_text.items)) {
        try appendContinuationTool(&out);
    }
    try appendResponseDone(&out);
    return try out.toOwnedSlice();
}

fn envKeyBytes(key_ptr: ?[*]const u8, key_len: u64) ![]const u8 {
    const key = try constBytes(key_ptr, key_len);
    if (key.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, 0) != null) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, '=') != null) return error.InvalidArgument;
    return key;
}

fn envValueFromCurrentProcess(key: []const u8) ?[]const u8 {
    if (builtin.is_test) {
        for (std.os.environ) |line| {
            const entry = std.mem.span(line);
            const eq = std.mem.indexOfScalar(u8, entry, '=') orelse continue;
            if (!std.mem.eql(u8, entry[0..eq], key)) continue;
            return entry[eq + 1 ..];
        }
        return null;
    }

    const key_z = std.heap.page_allocator.dupeZ(u8, key) catch return null;
    defer std.heap.page_allocator.free(key_z);

    const getenv = @extern(*const fn ([*:0]const u8) callconv(.c) ?[*:0]u8, .{ .name = "getenv" });
    const value = getenv(key_z.ptr) orelse return null;
    return std.mem.span(value);
}

fn envGetOwned(key: []const u8) ![]u8 {
    const value = envValueFromCurrentProcess(key) orelse return error.FileNotFound;
    return std.heap.page_allocator.dupe(u8, value);
}

pub fn Fallible(comptime T: type) type {
    return extern struct {
        status: i32,
        value: T,
    };
}

pub fn ok(comptime T: type, value: T) Fallible(T) {
    return .{ .status = SA_STD_OK, .value = value };
}

pub fn fail(comptime T: type, status: i32) Fallible(T) {
    return .{ .status = status, .value = @as(T, @bitCast(@as(std.meta.Int(.unsigned, @bitSizeOf(T)), 0))) };
}

pub export fn sa_std_version() u32 {
    return SA_STD_ABI_VERSION;
}

pub export fn sa_std_last_error() i32 {
    return last_error;
}

pub export fn sa_std_error_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = statusName(code);
    if (out_len) |len_ptr| len_ptr.* = @as(u64, @intCast(name.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const cap = lenAsUsize(out_cap) catch |err| return finishErr(err);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const copy_len = @min(cap, name.len);
    @memcpy(out_ptr[0..copy_len], name[0..copy_len]);
    if (copy_len != name.len) return finish(SA_STD_ERR_TRUNCATED);
    return finish(SA_STD_OK);
}

pub export fn sa_std_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_std_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_std_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_std_print(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    std.io.getStdOut().writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_println(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    std.io.getStdOut().writeAll(bytes) catch |err| return finishErr(err);
    std.io.getStdOut().writeAll("\n") catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_cwd() u64 {
    const cwd = std.process.getCwdAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(cwd) catch return 0;
}

pub export fn sa_deno_chdir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.process.changeCurDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_env_set(key_ptr: ?[*]const u8, key_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const value = constBytes(value_ptr, value_len) catch |err| return finishErr(err);
    if (std.mem.indexOfScalar(u8, value, 0) != null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const key_z = std.heap.page_allocator.dupeZ(u8, key) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(key_z);
    const value_z = std.heap.page_allocator.dupeZ(u8, value) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(value_z);
    if (setenv(key_z.ptr, value_z.ptr, 1) != 0) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_env_delete(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const key_z = std.heap.page_allocator.dupeZ(u8, key) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(key_z);
    if (unsetenv(key_z.ptr) != 0) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_random_uuid() u64 {
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    var text: [36]u8 = undefined;
    _ = std.fmt.bufPrint(
        &text,
        "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        },
    ) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, &text) catch return 0;
    return openOwnedBuffer(owned) catch return 0;
}

fn tempRootAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (envValueFromCurrentProcess("TMPDIR")) |value| {
        if (value.len != 0) return allocator.dupe(u8, value);
    }
    if (envValueFromCurrentProcess("TMP")) |value| {
        if (value.len != 0) return allocator.dupe(u8, value);
    }
    if (envValueFromCurrentProcess("TEMP")) |value| {
        if (value.len != 0) return allocator.dupe(u8, value);
    }
    return allocator.dupe(u8, "/tmp");
}

fn tempPathAlloc(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    suffix: []const u8,
) ![]u8 {
    const root = try tempRootAlloc(allocator);
    defer allocator.free(root);
    const normalized_prefix = if (prefix.len == 0) "sa-deno-" else prefix;
    const a = std.crypto.random.int(u64);
    const b = std.crypto.random.int(u64);
    const name = try std.fmt.allocPrint(allocator, "{s}{x:0>16}{x:0>16}{s}", .{ normalized_prefix, a, b, suffix });
    defer allocator.free(name);
    return std.fs.path.join(allocator, &.{ root, name });
}

pub export fn sa_deno_make_temp_dir(prefix_ptr: ?[*]const u8, prefix_len: u64) Fallible(u64) {
    const prefix = constBytes(prefix_ptr, prefix_len) catch |err| return fail(u64, mapError(err));
    if (std.mem.indexOfScalar(u8, prefix, 0) != null) return fail(u64, SA_STD_ERR_INVALID_ARGUMENT);
    const allocator = std.heap.page_allocator;
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = tempPathAlloc(allocator, prefix, "") catch |err| return fail(u64, mapError(err));
        std.fs.cwd().makeDir(path) catch |err| {
            allocator.free(path);
            if (err == error.PathAlreadyExists) continue;
            return fail(u64, mapError(err));
        };
        const handle = openOwnedByteBuffer(path) catch |err| return fail(u64, mapError(err));
        return ok(u64, handle);
    }
    return fail(u64, SA_STD_ERR_IO);
}

pub export fn sa_deno_make_temp_file(
    prefix_ptr: ?[*]const u8,
    prefix_len: u64,
    suffix_ptr: ?[*]const u8,
    suffix_len: u64,
) Fallible(u64) {
    const prefix = constBytes(prefix_ptr, prefix_len) catch |err| return fail(u64, mapError(err));
    const suffix = constBytes(suffix_ptr, suffix_len) catch |err| return fail(u64, mapError(err));
    if (std.mem.indexOfScalar(u8, prefix, 0) != null) return fail(u64, SA_STD_ERR_INVALID_ARGUMENT);
    if (std.mem.indexOfScalar(u8, suffix, 0) != null) return fail(u64, SA_STD_ERR_INVALID_ARGUMENT);
    const allocator = std.heap.page_allocator;
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = tempPathAlloc(allocator, prefix, suffix) catch |err| return fail(u64, mapError(err));
        const file = std.fs.cwd().createFile(path, .{ .read = true, .exclusive = true }) catch |err| {
            allocator.free(path);
            if (err == error.PathAlreadyExists) continue;
            return fail(u64, mapError(err));
        };
        file.close();
        const handle = openOwnedByteBuffer(path) catch |err| return fail(u64, mapError(err));
        return ok(u64, handle);
    }
    return fail(u64, SA_STD_ERR_IO);
}

pub export fn sa_deno_args_json() u64 {
    var args = std.process.argsAlloc(std.heap.page_allocator) catch return 0;
    defer std.process.argsFree(std.heap.page_allocator, args);

    const deno_args = if (args.len > 0) args[1..] else args[0..0];
    const json = std.json.stringifyAlloc(std.heap.page_allocator, deno_args, .{}) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_btoa(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch return 0;
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return openOwnedBuffer(encoded) catch return 0;
}

pub export fn sa_deno_atob(data_ptr: ?[*]const u8, len: u64) u64 {
    const encoded = constBytes(data_ptr, len) catch return 0;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return 0;
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch return 0;
    errdefer std.heap.page_allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded) catch return 0;
    return openOwnedBuffer(decoded) catch return 0;
}

pub export fn sa_deno_text_encode(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_text_decode(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_chat_sse_to_responses(
    chat_body_ptr: ?[*]const u8,
    chat_body_len: u64,
    req_body_ptr: ?[*]const u8,
    req_body_len: u64,
) u64 {
    const chat_body = constBytes(chat_body_ptr, chat_body_len) catch return 0;
    const req_body = constBytes(req_body_ptr, req_body_len) catch return 0;
    const converted = denoChatSseToResponses(chat_body, req_body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_chat_json_to_responses(
    chat_body_ptr: ?[*]const u8,
    chat_body_len: u64,
    req_body_ptr: ?[*]const u8,
    req_body_len: u64,
) u64 {
    const chat_body = constBytes(chat_body_ptr, chat_body_len) catch return 0;
    const req_body = constBytes(req_body_ptr, req_body_len) catch return 0;
    const converted = denoChatJsonToResponses(chat_body, req_body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_responses_sse_normalize(
    sse_body_ptr: ?[*]const u8,
    sse_body_len: u64,
) u64 {
    const sse_body = constBytes(sse_body_ptr, sse_body_len) catch return 0;
    const converted = denoResponsesSseNormalize(sse_body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_responses_json_normalize(
    body_ptr: ?[*]const u8,
    body_len: u64,
) u64 {
    const body = constBytes(body_ptr, body_len) catch return 0;
    const converted = denoResponsesJsonNormalize(body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_responses_request_normalize(
    body_ptr: ?[*]const u8,
    body_len: u64,
) u64 {
    const body = constBytes(body_ptr, body_len) catch return 0;
    const converted = denoResponsesRequestNormalize(body) catch return 0;
    return openOwnedByteBuffer(converted) catch return 0;
}

pub export fn sa_deno_responses_chat_fallback_request(
    body_ptr: ?[*]const u8,
    body_len: u64,
    default_model_ptr: ?[*]const u8,
    default_model_len: u64,
    plan_mode_like: u8,
) u64 {
    const body = constBytes(body_ptr, body_len) catch return 0;
    const default_model = constBytes(default_model_ptr, default_model_len) catch return 0;
    const converted = denoResponsesChatFallbackRequest(body, default_model, plan_mode_like != 0) catch return 0;
    const actual = converted orelse return 0;
    return openOwnedByteBuffer(actual) catch return 0;
}

pub export fn sa_deno_jsonrpc_params_string_literal(
    body_ptr: ?[*]const u8,
    body_len: u64,
    key_ptr: ?[*]const u8,
    key_len: u64,
    fallback_ptr: ?[*]const u8,
    fallback_len: u64,
    emit_null_if_missing: u8,
) u64 {
    const body = constBytes(body_ptr, body_len) catch return 0;
    const key = constBytes(key_ptr, key_len) catch return 0;
    const fallback = constBytes(fallback_ptr, fallback_len) catch return 0;
    const literal = jsonRpcParamsStringLiteralAlloc(body, key, fallback, emit_null_if_missing != 0) catch return 0;
    return openOwnedByteBuffer(literal) catch return 0;
}

pub export fn sa_deno_version_json() u64 {
    const json = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"deno\":\"sa-std\",\"v8\":\"\",\"typescript\":\"\",\"sci\":\"{s}\"}}",
        .{builtin.zig_version_string},
    ) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_version_deno() u64 {
    const owned = std.heap.page_allocator.dupe(u8, "sa-std") catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_build_json() u64 {
    const os = @tagName(builtin.os.tag);
    const arch = @tagName(builtin.cpu.arch);
    const vendor = @tagName(builtin.abi);
    const json = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"os\":\"{s}\",\"arch\":\"{s}\",\"target\":\"{s}-{s}\"}}",
        .{ os, arch, arch, vendor },
    ) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_build_os() u64 {
    const os = @tagName(builtin.os.tag);
    const owned = std.heap.page_allocator.dupe(u8, os) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_build_platform_family() u64 {
    const family = if (builtin.os.tag == .windows) "windows" else "unix";
    const owned = std.heap.page_allocator.dupe(u8, family) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_date_now_iso() u64 {
    var date: TimeDate = undefined;
    fillUtcNow(&date) catch return 0;
    const text = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z",
        .{
            date.year,
            date.month,
            date.day,
            date.hour,
            date.minute,
            date.second,
            date.millisecond,
        },
    ) catch return 0;
    return openOwnedByteBuffer(text) catch return 0;
}

const struct_sockaddr = extern struct {
    sa_family: u16,
    sa_data: [14]u8,
};
const struct_ifaddrs = extern struct {
    ifa_next: ?*struct_ifaddrs,
    ifa_name: [*:0]const u8,
    ifa_flags: c_uint,
    ifa_addr: ?*struct_sockaddr,
    ifa_netmask: ?*struct_sockaddr,
    ifa_ifu: extern union {
        ifu_broadaddr: ?*struct_sockaddr,
        ifu_dstaddr: ?*struct_sockaddr,
    },
    ifa_data: ?*anyopaque,
};
extern fn getifaddrs(ifap: *?*struct_ifaddrs) c_int;
extern fn freeifaddrs(ifa: ?*struct_ifaddrs) void;
extern fn inet_ntop(af: c_int, src: ?*const anyopaque, dst: [*]u8, size: c_uint) ?[*:0]const u8;

pub export fn sa_deno_hostname() u64 {
    const uname = std.posix.uname();
    const nodename = std.mem.sliceTo(&uname.nodename, 0);
    const owned = std.heap.page_allocator.dupe(u8, nodename) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_os_release() u64 {
    const uname = std.posix.uname();
    const release = std.mem.sliceTo(&uname.release, 0);
    const owned = std.heap.page_allocator.dupe(u8, release) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_os_uptime() f64 {
    var file = std.fs.openFileAbsolute("/proc/uptime", .{}) catch return -1.0;
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.readAll(&buf) catch return -1.0;
    const content = buf[0..n];
    const space_idx = std.mem.indexOfScalar(u8, content, ' ') orelse content.len;
    const uptime_str = std.mem.trim(u8, content[0..space_idx], " \t\r\n");
    return std.fmt.parseFloat(f64, uptime_str) catch -1.0;
}

pub export fn sa_deno_loadavg(out_ptr: ?*f64) i32 {
    const ptr = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var file = std.fs.openFileAbsolute("/proc/loadavg", .{}) catch return finish(SA_STD_ERR_IO);
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.readAll(&buf) catch return finish(SA_STD_ERR_IO);
    const content = buf[0..n];
    var it = std.mem.tokenizeScalar(u8, content, ' ');
    const l1_str = it.next() orelse return finish(SA_STD_ERR_IO);
    const l2_str = it.next() orelse return finish(SA_STD_ERR_IO);
    const l3_str = it.next() orelse return finish(SA_STD_ERR_IO);
    const l1 = std.fmt.parseFloat(f64, l1_str) catch return finish(SA_STD_ERR_IO);
    const l2 = std.fmt.parseFloat(f64, l2_str) catch return finish(SA_STD_ERR_IO);
    const l3 = std.fmt.parseFloat(f64, l3_str) catch return finish(SA_STD_ERR_IO);
    const dest: [*]f64 = @ptrCast(ptr);
    dest[0] = l1;
    dest[1] = l2;
    dest[2] = l3;
    return finish(SA_STD_OK);
}

pub export fn sa_deno_system_memory_info() u64 {
    var file = std.fs.openFileAbsolute("/proc/meminfo", .{}) catch return 0;
    defer file.close();
    var buf: [2048]u8 = undefined;
    const n = file.readAll(&buf) catch return 0;
    const content = buf[0..n];

    var total: u64 = 0;
    var free: u64 = 0;
    var available: u64 = 0;
    var buffers: u64 = 0;
    var cached: u64 = 0;
    var swapTotal: u64 = 0;
    var swapFree: u64 = 0;

    var it = std.mem.tokenizeScalar(u8, content, '\n');
    while (it.next()) |line| {
        var line_it = std.mem.tokenizeAny(u8, line, " \t:");
        const key = line_it.next() orelse continue;
        const val_str = line_it.next() orelse continue;
        const val = std.fmt.parseInt(u64, val_str, 10) catch continue;
        const bytes = val * 1024;
        if (std.mem.eql(u8, key, "MemTotal")) {
            total = bytes;
        } else if (std.mem.eql(u8, key, "MemFree")) {
            free = bytes;
        } else if (std.mem.eql(u8, key, "MemAvailable")) {
            available = bytes;
        } else if (std.mem.eql(u8, key, "Buffers")) {
            buffers = bytes;
        } else if (std.mem.eql(u8, key, "Cached")) {
            cached = bytes;
        } else if (std.mem.eql(u8, key, "SwapTotal")) {
            swapTotal = bytes;
        } else if (std.mem.eql(u8, key, "SwapFree")) {
            swapFree = bytes;
        }
    }

    var out_buf: [512]u8 = undefined;
    const json = std.fmt.bufPrint(&out_buf, "{{\"total\":{d},\"free\":{d},\"available\":{d},\"buffers\":{d},\"cached\":{d},\"swapTotal\":{d},\"swapFree\":{d}}}", .{ total, free, available, buffers, cached, swapTotal, swapFree }) catch return 0;

    const owned = std.heap.page_allocator.dupe(u8, json) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_network_interfaces() u64 {
    var ifap: ?*struct_ifaddrs = null;
    if (getifaddrs(&ifap) != 0) return 0;
    defer {
        if (ifap) |ptr| freeifaddrs(ptr);
    }

    var list = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer list.deinit();
    list.append('[') catch return 0;

    var first = true;
    var current = ifap;
    while (current) |ifa| : (current = ifa.ifa_next) {
        const addr_ptr = ifa.ifa_addr orelse continue;
        const family = addr_ptr.sa_family;
        if (family != 2 and family != 10) continue;

        const name = std.mem.sliceTo(ifa.ifa_name, 0);

        var ip_buf: [46]u8 = undefined;
        const family_str = if (family == 2) "IPv4" else "IPv6";
        const af: c_int = if (family == 2) 2 else 10;

        const ip_src = if (family == 2)
            @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                sa_family: u16,
                sin_port: u16,
                sin_addr: [4]u8,
            }, @ptrCast(addr_ptr)).sin_addr))
        else
            @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                sa_family: u16,
                sin6_port: u16,
                sin6_flowinfo: u32,
                sin6_addr: [16]u8,
                sin6_scope_id: u32,
            }, @ptrCast(addr_ptr)).sin6_addr));

        const ip_z = inet_ntop(af, ip_src, &ip_buf, ip_buf.len) orelse continue;
        const ip_str = std.mem.sliceTo(ip_z, 0);

        var mask_buf: [46]u8 = undefined;
        var cidr: u32 = 0;
        var mask_str: []const u8 = "000.000.000.000";
        if (ifa.ifa_netmask) |mask_ptr| {
            const mask_src = if (family == 2)
                @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                    sa_family: u16,
                    sin_port: u16,
                    sin_addr: [4]u8,
                }, @ptrCast(mask_ptr)).sin_addr))
            else
                @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                    sa_family: u16,
                    sin6_port: u16,
                    sin6_flowinfo: u32,
                    sin6_addr: [16]u8,
                    sin6_scope_id: u32,
                }, @ptrCast(mask_ptr)).sin6_addr));
            if (inet_ntop(af, mask_src, &mask_buf, mask_buf.len)) |mask_z| {
                mask_str = std.mem.sliceTo(mask_z, 0);
            }

            if (family == 2) {
                const sin_addr = @as(*align(1) const extern struct {
                    sa_family: u16,
                    sin_port: u16,
                    sin_addr: [4]u8,
                }, @ptrCast(mask_ptr)).sin_addr;
                const mask_val = @as(u32, @bitCast(sin_addr));
                cidr = @popCount(mask_val);
            } else {
                const sin6_addr = @as(*align(1) const extern struct {
                    sa_family: u16,
                    sin6_port: u16,
                    sin6_flowinfo: u32,
                    sin6_addr: [16]u8,
                    sin6_scope_id: u32,
                }, @ptrCast(mask_ptr)).sin6_addr;
                for (sin6_addr) |b| {
                    cidr += @popCount(b);
                }
            }
        }

        var mac_buf: [32]u8 = undefined;
        var mac_path_buf: [128]u8 = undefined;
        const mac_path = std.fmt.bufPrint(&mac_path_buf, "/sys/class/net/{s}/address", .{name}) catch "";
        var mac_str: []const u8 = "00:00:00:00:00:00";
        if (mac_path.len != 0) {
            if (std.fs.openFileAbsolute(mac_path, .{})) |mac_file| {
                defer mac_file.close();
                if (mac_file.readAll(&mac_buf)) |mac_len| {
                    mac_str = std.mem.trim(u8, mac_buf[0..mac_len], " \t\r\n");
                } else |_| {}
            } else |_| {}
        }

        if (!first) {
            list.append(',') catch return 0;
        }
        first = false;

        var json_buf: [512]u8 = undefined;
        const entry = std.fmt.bufPrint(&json_buf, "{{\"name\":\"{s}\",\"family\":\"{s}\",\"address\":\"{s}\",\"netmask\":\"{s}\",\"scopeid\":null,\"cidr\":\"{s}/{d}\",\"mac\":\"{s}\"}}", .{ name, family_str, ip_str, mask_str, ip_str, cidr, mac_str }) catch return 0;

        list.appendSlice(entry) catch return 0;
    }

    list.append(']') catch return 0;
    const owned = list.toOwnedSlice() catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

extern fn getpid() c_int;
extern fn getppid() c_int;
extern fn getuid() c_uint;
extern fn getgid() c_uint;
extern fn getpagesize() c_int;

pub export fn sa_deno_pid() u32 {
    return @intCast(getpid());
}

pub export fn sa_deno_ppid() u32 {
    return @intCast(getppid());
}

pub export fn sa_deno_uid() u32 {
    return @intCast(getuid());
}

pub export fn sa_deno_gid() u32 {
    return @intCast(getgid());
}

pub export fn sa_deno_exec_path() u64 {
    const path = std.fs.selfExePathAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_deno_memory_usage() u64 {
    var file = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return 0;
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.readAll(&buf) catch return 0;
    const content = buf[0..n];
    var it = std.mem.tokenizeScalar(u8, content, ' ');
    _ = it.next() orelse return 0;
    const rss_pages_str = it.next() orelse return 0;
    const rss_pages = std.fmt.parseInt(u64, rss_pages_str, 10) catch return 0;

    const page_size: u64 = @intCast(getpagesize());
    const rss = rss_pages * page_size;

    var out_buf: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&out_buf, "{{\"rss\":{d},\"heapTotal\":{d},\"heapUsed\":{d},\"external\":0}}", .{ rss, rss, rss }) catch return 0;

    const owned = std.heap.page_allocator.dupe(u8, json) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_json_parse(json_bytes: ?[*]const u8, len: u64) u64 {
    const input = constBytes(json_bytes, len) catch return 0;
    const document = jsonDocumentFromSlice(std.heap.page_allocator, input) catch return 0;
    return registerJsonNode(document, document.parsed.value, false) catch return 0;
}

pub export fn sa_json_kind(node: u64) u32 {
    var node_value = acquireJsonNode(node) catch return SA_JSON_KIND_INVALID;
    defer node_value.deinit();
    return jsonKindOf(node_value.value);
}

pub export fn sa_json_object_get(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const handle = registerJsonNode(child.document, child.value, true) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_get(node: u64, index: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonArrayGet(node_value, index) catch |err| return finishErr(err);
    const handle = registerJsonNode(child.document, child.value, true) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_key_at(node: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = null;
    len_slot.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const key = jsonObjectKeyAt(node_value, index) catch |err| return finishErr(err);
    ptr_slot.* = key.ptr;
    len_slot.* = @as(u64, @intCast(key.len));
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_string(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = null;
    len_slot.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const text = jsonTextSlice(child.value) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = text.ptr;
    len_slot.* = @as(u64, @intCast(text.len));
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_bool(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*u8) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const parsed = jsonValueAsBool(child.value) catch |err| return finishErr(err);
    value_ptr.* = if (parsed) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_i64(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*i64) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const parsed = jsonValueAsI64(child.value) catch |err| return finishErr(err);
    value_ptr.* = parsed;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_f64(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*f64) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const parsed = jsonValueAsF64(child.value) catch |err| return finishErr(err);
    value_ptr.* = parsed;
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_f64(node: u64, out_value: ?*f64) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const parsed = jsonValueAsF64(node_value.value) catch |err| return finishErr(err);
    value_ptr.* = parsed;
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_i64(node: u64, out_value: ?*i64) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const parsed = jsonValueAsI64(node_value.value) catch |err| return finishErr(err);
    value_ptr.* = parsed;
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_bool(node: u64, out_value: ?*u8) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const parsed = jsonValueAsBool(node_value.value) catch |err| return finishErr(err);
    value_ptr.* = if (parsed) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_string_ptr(node: u64) ?[*]const u8 {
    var node_value = acquireJsonNode(node) catch return null;
    defer node_value.deinit();
    return if (jsonTextSlice(node_value.value)) |text| text.ptr else null;
}

pub export fn sa_json_string_len(node: u64) u64 {
    var node_value = acquireJsonNode(node) catch return 0;
    defer node_value.deinit();
    return if (jsonTextSlice(node_value.value)) |text| @as(u64, @intCast(text.len)) else 0;
}

pub export fn sa_json_value_count(node: u64, out_count: ?*u64) i32 {
    const count_ptr = out_count orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    count_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    return switch (node_value.value) {
        .array => |array| {
            count_ptr.* = @as(u64, @intCast(array.items.len));
            return finish(SA_STD_OK);
        },
        .object => |object| {
            count_ptr.* = @as(u64, @intCast(object.count()));
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
}

pub export fn sa_json_free(node: u64) Fallible(i32) {
    const status = sa_std_close(node);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_json_stringify(node: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const handle = jsonSerializeBuffer(std.heap.page_allocator, node_value.value) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_new(out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const scanner_handle = JsonScannerHandle.init(std.heap.page_allocator) catch |err| return finishErr(err);
    const handle = registerResource(.{ .json_scanner = scanner_handle }) catch |err| {
        scanner_handle.destroy();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_feed(scanner: u64, input: ?[*]const u8, len: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(scanner) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const scanner_handle = switch (resource.*) {
        .json_scanner => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    const bytes = constBytes(input, len) catch |err| return finishErr(err);
    jsonScannerFeed(scanner_handle, bytes, false) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_end_input(scanner: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(scanner) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const scanner_handle = switch (resource.*) {
        .json_scanner => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    scanner_handle.scanner.endInput();
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_next(scanner: u64, out_token: ?*SaJsonToken) i32 {
    const token_ptr = out_token orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    token_ptr.* = .{ .kind = SA_JSON_TOKEN_INVALID, .text_ptr = null, .text_len = 0 };
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(scanner) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const scanner_handle = switch (resource.*) {
        .json_scanner => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };

    scanner_handle.pending_text.clearRetainingCapacity();
    const token = scanner_handle.scanner.next() catch |err| switch (err) {
        error.BufferUnderrun => return finish(SA_STD_ERR_TRUNCATED),
        else => return finishErr(err),
    };
    token_ptr.kind = tokenTypeOf(token);
    if (tokenTextSlice(token)) |text| {
        token_ptr.text_ptr = text.ptr;
        token_ptr.text_len = @as(u64, @intCast(text.len));
    } else switch (token) {
        .allocated_number, .allocated_string, .partial_string_escaped_1, .partial_string_escaped_2, .partial_string_escaped_3, .partial_string_escaped_4 => {
            const text = tokenTextBytes(scanner_handle, token) catch |err| return finishErr(err);
            token_ptr.text_ptr = text.ptr;
            token_ptr.text_len = @as(u64, @intCast(text.len));
        },
        else => {},
    }
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_free(scanner: u64) i32 {
    return sa_std_close(scanner);
}

pub export fn sa_json_stream_new(json_bytes: ?[*]const u8, len: u64) u64 {
    const input = constBytes(json_bytes, len) catch return 0;
    const stream_handle = JsonStreamHandle.init(std.heap.page_allocator, input) catch return 0;
    return registerResource(.{ .json_stream = stream_handle }) catch |err| {
        stream_handle.deinit();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_json_stream_next(stream: u64) u32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return SA_JSON_TOKEN_INVALID;
    const stream_handle = switch (resource.*) {
        .json_stream => |handle| handle,
        else => return SA_JSON_TOKEN_INVALID,
    };
    stream_handle.scanner.pending_text.clearRetainingCapacity();
    const token = stream_handle.scanner.scanner.next() catch return SA_JSON_TOKEN_INVALID;
    stream_handle.last_token = tokenTypeOf(token);
    if (tokenTextSlice(token)) |text| {
        stream_handle.scanner.current_text = text;
    } else switch (token) {
        .allocated_number, .allocated_string, .partial_string_escaped_1, .partial_string_escaped_2, .partial_string_escaped_3, .partial_string_escaped_4 => {
            const text = tokenTextBytes(stream_handle.scanner, token) catch return SA_JSON_TOKEN_INVALID;
            stream_handle.scanner.current_text = text;
        },
        else => {
            stream_handle.scanner.current_text = null;
        },
    }
    stream_handle.scanner.current_token = stream_handle.last_token;
    return stream_handle.last_token;
}

pub export fn sa_json_stream_get_slice_ptr(stream: u64) ?[*]const u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return null;
    const stream_handle = switch (resource.*) {
        .json_stream => |handle| handle,
        else => return null,
    };
    return if (stream_handle.scanner.current_text) |text| text.ptr else null;
}

pub export fn sa_json_stream_get_slice_len(stream: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return 0;
    const stream_handle = switch (resource.*) {
        .json_stream => |handle| handle,
        else => return 0,
    };
    return if (stream_handle.scanner.current_text) |text| @as(u64, @intCast(text.len)) else 0;
}

pub export fn sa_json_stream_free(stream: u64) Fallible(i32) {
    const status = sa_std_close(stream);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_json_writer_free(writer: u64) i32 {
    return sa_std_close(writer);
}

pub export fn sa_json_writer_new(whitespace: u32, emit_null_optional_fields: u8, emit_strings_as_arrays: u8, escape_unicode: u8, emit_nonportable_numbers_as_strings: u8, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const options: std.json.StringifyOptions = .{
        .whitespace = switch (whitespace) {
            SA_JSON_WHITESPACE_MINIFIED => .minified,
            SA_JSON_WHITESPACE_INDENT_1 => .indent_1,
            SA_JSON_WHITESPACE_INDENT_2 => .indent_2,
            SA_JSON_WHITESPACE_INDENT_3 => .indent_3,
            SA_JSON_WHITESPACE_INDENT_4 => .indent_4,
            SA_JSON_WHITESPACE_INDENT_8 => .indent_8,
            SA_JSON_WHITESPACE_INDENT_TAB => .indent_tab,
            else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
        },
        .emit_null_optional_fields = emit_null_optional_fields != 0,
        .emit_strings_as_arrays = emit_strings_as_arrays != 0,
        .escape_unicode = escape_unicode != 0,
        .emit_nonportable_numbers_as_strings = emit_nonportable_numbers_as_strings != 0,
    };
    const writer_handle = JsonWriterHandle.init(std.heap.page_allocator, options) catch |err| return finishErr(err);
    const handle = registerResource(.{ .json_writer = writer_handle }) catch |err| {
        writer_handle.deinit();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_begin_object(writer: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.beginObject() catch |err| return finishErr(err);
    writer_handle.open_depth += 1;
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = false;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_end_object(writer: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.endObject() catch |err| return finishErr(err);
    writer_handle.open_depth -= 1;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_begin_array(writer: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.beginArray() catch |err| return finishErr(err);
    writer_handle.open_depth += 1;
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = false;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_end_array(writer: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.endArray() catch |err| return finishErr(err);
    writer_handle.open_depth -= 1;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_object_field(writer: u64, key: ?[*]const u8, key_len: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_string(writer: u64, key: ?[*]const u8, key_len: u64, data: ?[*]const u8, len: u64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(bytes) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_bool(writer: u64, key: ?[*]const u8, key_len: u64, value: u8) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(value != 0) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_i64(writer: u64, key: ?[*]const u8, key_len: u64, value: i64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(value) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_f64(writer: u64, key: ?[*]const u8, key_len: u64, value: f64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(value) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_null(writer: u64, key: ?[*]const u8, key_len: u64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(null) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_node(writer: u64, key: ?[*]const u8, key_len: u64, node: u64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(node_value.value) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_bool(writer: u64, value: u8) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(value != 0) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_i64(writer: u64, value: i64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(value) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_f64(writer: u64, value: f64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(value) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_string(writer: u64, data: ?[*]const u8, len: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    writer_handle.stream.write(bytes) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_null(writer: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(null) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_node(writer: u64, node: u64) i32 {
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(node_value.value) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_finish(writer: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer) |existing| {
        const existing_resource = getResourceLocked(existing) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
        switch (existing_resource.*) {
            .json_buffer => {},
            else => return finish(SA_STD_ERR_INVALID_HANDLE),
        }
        handle_ptr.* = existing;
        return finish(SA_STD_OK);
    }
    if (!writer_handle.root_value_started or !writer_handle.root_value_complete or writer_handle.open_depth != 0) {
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    }
    const bytes = writer_handle.buffer.toOwnedSlice() catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(bytes);
    const buffer_handle = registerResourceLocked(.{ .json_buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    writer_handle.result_buffer = buffer_handle;
    handle_ptr.* = buffer_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_regex_compile(pattern: ?[*]const u8, pattern_len: u64, cflags: i32) u64 {
    const input = constBytes(pattern, pattern_len) catch return 0;
    const handle = RegexHandle.init(std.heap.page_allocator, input, cflags) catch return 0;
    return registerResource(.{ .regex = handle }) catch |err| {
        handle.destroy();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_regex_match(regex: u64, text: ?[*]const u8, text_len: u64) u64 {
    const input = constBytes(text, text_len) catch return 0;
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(regex) orelse return 0;
    const regex_handle = switch (resource.*) {
        .regex => |handle| handle,
        else => return 0,
    };
    const match_handle = regexMatchHandle(regex_handle, input) catch return 0;
    return registerResourceLocked(.{ .regex_match = match_handle }) catch |err| {
        match_handle.destroy();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_regex_group_ptr(match: u64, group_idx: u32) ?[*]const u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(match) orelse return null;
    const match_handle = switch (resource.*) {
        .regex_match => |handle| handle,
        else => return null,
    };
    const idx = @as(usize, @intCast(group_idx));
    if (idx >= match_handle.matches.len) return null;
    const reg = match_handle.matches[idx];
    if (reg.rm_so < 0 or reg.rm_eo < 0) return null;
    const start: usize = @intCast(reg.rm_so);
    return match_handle.text_z[start..].ptr;
}

pub export fn sa_regex_group_len(match: u64, group_idx: u32) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(match) orelse return 0;
    const match_handle = switch (resource.*) {
        .regex_match => |handle| handle,
        else => return 0,
    };
    const idx = @as(usize, @intCast(group_idx));
    if (idx >= match_handle.matches.len) return 0;
    const reg = match_handle.matches[idx];
    if (reg.rm_so < 0 or reg.rm_eo < 0) return 0;
    return @as(u64, @intCast(reg.rm_eo - reg.rm_so));
}

pub export fn sa_regex_group_count(regex: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(regex) orelse return 0;
    const regex_handle = switch (resource.*) {
        .regex => |handle| handle,
        else => return 0,
    };
    return @as(u64, @intCast(regexGroupCount(regex_handle)));
}

pub export fn sa_regex_free(regex: u64) Fallible(i32) {
    const status = sa_std_close(regex);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_regex_match_free(match: u64) Fallible(i32) {
    const status = sa_std_close(match);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_json_buffer_data(buffer: u64) ?[*]u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return null;
    return switch (resource.*) {
        .json_buffer => |*json_buffer| json_buffer.bytes.ptr,
        else => null,
    };
}

pub export fn sa_json_buffer_len(buffer: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return 0;
    return switch (resource.*) {
        .json_buffer => |json_buffer| @as(u64, @intCast(json_buffer.bytes.len)),
        else => 0,
    };
}

pub export fn sa_json_buffer_free(buffer: u64) Fallible(i32) {
    const status = sa_std_close(buffer);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_time_instant_ns() u64 {
    return monotonicNowNs() catch return 0;
}

pub export fn sa_time_unix_s() i64 {
    return std.time.timestamp();
}

pub export fn sa_time_unix_ms() i64 {
    return std.time.milliTimestamp();
}

pub export fn sa_time_unix_ns() i64 {
    const ts = std.time.nanoTimestamp();
    return @as(i64, @intCast(ts));
}

pub export fn sa_time_utc_now(out_date: ?*TimeDate) i32 {
    const ptr = out_date orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fillUtcNow(ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ns(ns: u64) i32 {
    std.Thread.sleep(ns);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ms(ms: u64) i32 {
    const ns = std.math.mul(u64, ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return sa_time_sleep_ns(ns);
}

pub export fn sa_std_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    if (out_written) |ptr| ptr.* = 0;
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const written = writeHandleLocked(handle, bytes) catch |err| return finishErr(err);
    if (out_written) |ptr| ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const read = readHandleLocked(handle, buffer) catch |err| return finishErr(err);
    if (out_read) |ptr| ptr.* = @as(u64, @intCast(read));
    return finish(SA_STD_OK);
}

pub export fn sa_std_close(handle: u64) i32 {
    if (handle == SA_STD_STDIN or handle == SA_STD_STDOUT or handle == SA_STD_STDERR) return finish(SA_STD_ERR_INVALID_HANDLE);
    registry_mutex.lock();
    var resource = takeResourceLocked(handle) orelse {
        registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    registry_mutex.unlock();
    resource.close() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_io_read_line(handle: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const limit = lenAsUsize(max_bytes) catch |err| return finishErr(err);

    registry_mutex.lock();
    defer registry_mutex.unlock();

    var list = std.ArrayList(u8).init(std.heap.page_allocator);
    defer list.deinit();

    var count: usize = 0;
    while (count < limit) {
        var ch: [1]u8 = undefined;
        const read = readHandleLocked(handle, ch[0..]) catch |err| return finishErr(err);
        if (read == 0) break;
        if (ch[0] == '\n') break;
        if (ch[0] == '\r') continue;
        list.append(ch[0]) catch |err| return finishErr(err);
        count += 1;
    }

    const bytes = list.toOwnedSlice() catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(bytes);
    const resource = Resource{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } };
    const buf_handle = registerResourceLocked(resource) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    handle_ptr.* = buf_handle;
    return finish(SA_STD_OK);
}

// Compatibility shims for the rosetta demos that model host APIs directly.
pub fn fd_open(path_ptr: ?[*]const u8) callconv(.c) i32 {
    _ = path_ptr;
    last_error = SA_STD_OK;
    return 3;
}

pub fn fd_read(fd: i32) callconv(.c) i32 {
    _ = fd;
    last_error = SA_STD_OK;
    return 3;
}

pub fn fd_close(fd: i32) callconv(.c) i32 {
    _ = fd;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return SA_STD_ERR_UNSUPPORTED;
}

pub fn mmap(fd: i32, len: i32) callconv(.c) ?[*]u8 {
    _ = fd;
    _ = len;
    last_error = SA_STD_OK;
    return compatibility_mmap_page[0..].ptr;
}

pub fn munmap(map: ?[*]u8, len: i32) callconv(.c) i32 {
    _ = map;
    _ = len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn signal(sig: i32, handler: ?[*]const u8) callconv(.c) i32 {
    _ = handler;
    last_error = SA_STD_OK;
    return sig;
}

pub fn pthread_spawn(entry: ?[*]const u8, arg: ?[*]const u8) callconv(.c) i32 {
    const entry_fn: PthreadEntryFn = @ptrCast(entry orelse return finish(SA_STD_ERR_INVALID_ARGUMENT));
    const task = std.heap.page_allocator.create(PthreadTask) catch return finish(SA_STD_ERR_NO_MEMORY);
    task.* = .{ .entry = entry_fn, .arg = @ptrCast(@constCast(arg)) };
    const thread = std.Thread.spawn(.{}, pthreadTaskMain, .{task}) catch |err| {
        std.heap.page_allocator.destroy(task);
        return finish(mapError(err));
    };
    const handle = std.heap.page_allocator.create(PthreadHandle) catch |err| {
        thread.join();
        std.heap.page_allocator.destroy(task);
        return finish(mapError(err));
    };
    handle.* = .{ .thread = thread, .task = task };
    const id = allocPthreadHandle(handle) catch |err| {
        thread.join();
        std.heap.page_allocator.destroy(task);
        std.heap.page_allocator.destroy(handle);
        return finish(mapError(err));
    };
    last_error = SA_STD_OK;
    return id;
}

pub fn pthread_spawn_detached(entry: ?[*]const u8, arg: ?[*]const u8) callconv(.c) i32 {
    const entry_fn: PthreadEntryFn = @ptrCast(entry orelse return finish(SA_STD_ERR_INVALID_ARGUMENT));
    const task = std.heap.page_allocator.create(PthreadTask) catch return finish(SA_STD_ERR_NO_MEMORY);
    task.* = .{
        .entry = entry_fn,
        .arg = @ptrCast(@constCast(arg)),
        .destroy_on_finish = true,
    };
    const thread = std.Thread.spawn(.{}, pthreadTaskMain, .{task}) catch |err| {
        std.heap.page_allocator.destroy(task);
        return finish(mapError(err));
    };
    thread.detach();
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn pthread_join(handle: i32, out: ?[*]u8) callconv(.c) i32 {
    const handle_ptr = freePthreadHandle(handle) catch |err| return finish(mapError(err));
    handle_ptr.thread.join();
    const out_ptr = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    std.mem.copyForwards(u8, out_ptr[0..4], std.mem.asBytes(&handle_ptr.task.result));
    std.heap.page_allocator.destroy(handle_ptr.task);
    std.heap.page_allocator.destroy(handle_ptr);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn pthread_drop(handle: i32) callconv(.c) void {
    if (handle <= 0) {
        last_error = SA_STD_ERR_INVALID_HANDLE;
        return;
    }
    const idx: usize = @intCast(handle - 1);
    var handle_ptr: ?*PthreadHandle = null;
    pthread_registry_mutex.lock();
    if (idx >= pthread_slots.items.len) {
        pthread_registry_mutex.unlock();
        last_error = SA_STD_ERR_INVALID_HANDLE;
        return;
    }
    if (pthread_slots.items[idx]) |slot| {
        pthread_slots.items[idx] = null;
        handle_ptr = slot;
    }
    pthread_registry_mutex.unlock();
    if (handle_ptr) |slot| {
        slot.thread.join();
        std.heap.page_allocator.destroy(slot.task);
        std.heap.page_allocator.destroy(slot);
    }
    last_error = SA_STD_OK;
}

pub fn dlopen(path_ptr: ?[*]const u8, flags: i32) callconv(.c) ?[*]u8 {
    _ = path_ptr;
    _ = flags;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return compatibility_dlopen_cookie[0..].ptr;
}

pub fn dlsym(handle: ?[*]u8, symbol_ptr: ?[*]const u8) callconv(.c) ?[*]u8 {
    _ = handle;
    _ = symbol_ptr;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return compatibility_dlsym_cookie[0..].ptr;
}

pub fn dlclose(handle: ?[*]u8) callconv(.c) i32 {
    _ = handle;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return SA_STD_ERR_UNSUPPORTED;
}

pub export fn sa_dl_open(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);

    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const path_z = std.heap.page_allocator.dupeZ(u8, path) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(path_z);

    const lib = std.DynLib.openZ(path_z) catch |err| switch (err) {
        error.FileNotFound, error.NotElfFile, error.NotDynamicLibrary => {
            compatibility_dl_error = "not_found";
            return finish(SA_STD_ERR_NOT_FOUND);
        },
        error.OutOfMemory => return finish(SA_STD_ERR_NO_MEMORY),
        else => return finish(SA_STD_ERR_UNKNOWN),
    };

    const handle = std.heap.page_allocator.create(DynamicLibHandle) catch |err| {
        var lib_copy = lib;
        lib_copy.close();
        return finishErr(err);
    };
    handle.* = .{ .lib = lib };

    const resource_handle = registerResource(.{ .dynamic_lib = handle }) catch |err| {
        handle.deinit();
        std.heap.page_allocator.destroy(handle);
        return finishErr(err);
    };

    handle_ptr.* = resource_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_dl_sym(handle: u64, symbol_ptr: ?[*]const u8, symbol_len: u64, out_ptr: ?*?*anyopaque) i32 {
    const result_ptr = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result_ptr.* = null;
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);

    const symbol = pathBytes(symbol_ptr, symbol_len) catch |err| return finishErr(err);
    const symbol_z = std.heap.page_allocator.dupeZ(u8, symbol) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(symbol_z);

    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const lib_handle = switch (resource.*) {
        .dynamic_lib => |lib| lib,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    result_ptr.* = lib_handle.lib.lookup(*anyopaque, symbol_z) orelse {
        compatibility_dl_error = "not_found";
        return finish(SA_STD_ERR_NOT_FOUND);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_dl_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_dl_error() ?[*:0]const u8 {
    return compatibility_dl_error.ptr;
}

pub fn sqlite3_prepare(sqlite: ?[*]u8, sql: ?[*]const u8, len: i32, stmt_out: ?[*]u8) callconv(.c) i32 {
    _ = sqlite;
    _ = sql;
    _ = len;
    _ = stmt_out;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn sqlite3_step(stmt: ?[*]u8) callconv(.c) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return 1;
}

pub fn sqlite3_finalize(stmt: ?[*]u8) callconv(.c) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

comptime {
    if (!builtin.is_test) {
        @export(&fd_open, .{ .name = "fd_open" });
        @export(&fd_read, .{ .name = "fd_read" });
        @export(&fd_close, .{ .name = "fd_close" });
        @export(&mmap, .{ .name = "mmap" });
        @export(&munmap, .{ .name = "munmap" });
        @export(&signal, .{ .name = "signal" });
        @export(&pthread_spawn, .{ .name = "pthread_spawn" });
        @export(&pthread_spawn_detached, .{ .name = "pthread_spawn_detached" });
        @export(&pthread_join, .{ .name = "pthread_join" });
        @export(&pthread_drop, .{ .name = "pthread_drop" });
        @export(&dlopen, .{ .name = "dlopen" });
        @export(&dlsym, .{ .name = "dlsym" });
        @export(&dlclose, .{ .name = "dlclose" });
        @export(&sqlite3_prepare, .{ .name = "sqlite3_prepare" });
        @export(&sqlite3_step, .{ .name = "sqlite3_step" });
        @export(&sqlite3_finalize, .{ .name = "sqlite3_finalize" });
    }
}

pub export fn sa_std_fs_open_read(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return finishErr(err);
    errdefer file.close();
    const handle = registerResource(.{ .file = file }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_open_write(path_ptr: ?[*]const u8, path_len: u64, truncate: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = truncate != 0 }) catch |err| return finishErr(err);
    errdefer file.close();
    const handle = registerResource(.{ .file = file }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_remove(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteFile(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_exists(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().access(path, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_len(path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const stat = std.fs.cwd().statFile(path) catch |err| return finishErr(err);
    len_ptr.* = stat.size;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const result = spawnProcess(std.heap.page_allocator, argv, .capture) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    const result = spawnProcessCwd(std.heap.page_allocator, argv, .capture, cwd) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const result = spawnProcess(std.heap.page_allocator, argv, .inherit) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    const result = spawnProcessCwd(std.heap.page_allocator, argv, .inherit, cwd) catch |err| return finishErr(err);
    handle_ptr.* = result.process;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const result = spawnProcess(std.heap.page_allocator, argv, .stream) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    const result = spawnProcessCwd(std.heap.page_allocator, argv, .stream, cwd) catch |err| return finishErr(err);
    process_ptr.* = result.process;
    stdout_ptr.* = result.stdout orelse 0;
    stderr_ptr.* = result.stderr orelse 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_wait(handle: u64, out_code: ?*u32) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.exited) {
                const waited = std.posix.waitpid(proc.pid, 0);
                proc.code = statusFromWaitStatus(waited.status);
                proc.exited = true;
                if (proc.capture_output) {
                    if (proc.stdout_fd) |fd| {
                        const captured = capture_fd_to_owned(std.heap.page_allocator, fd) catch |err| return finishErr(err);
                        proc.stdout_buf = captured;
                        std.posix.close(fd);
                        proc.stdout_fd = null;
                    }
                    if (proc.stderr_fd) |fd| {
                        const captured = capture_fd_to_owned(std.heap.page_allocator, fd) catch |err| return finishErr(err);
                        proc.stderr_buf = captured;
                        std.posix.close(fd);
                        proc.stderr_fd = null;
                    }
                }
                proc.stdout_pos = 0;
                proc.stderr_pos = 0;
            }
            code_ptr.* = proc.code;
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

const ProcessOutputStream = enum { stdout, stderr };

fn readProcessOutput(handle: u64, stream: ProcessOutputStream, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.capture_output or !proc.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
            const src = switch (stream) {
                .stdout => proc.stdout_buf,
                .stderr => proc.stderr_buf,
            };
            const pos_ptr = switch (stream) {
                .stdout => &proc.stdout_pos,
                .stderr => &proc.stderr_pos,
            };
            if (pos_ptr.* >= src.len) return finish(SA_STD_OK);
            const remaining = src.len - pos_ptr.*;
            const copy_len = @min(output.len, remaining);
            @memcpy(output[0..copy_len], src[pos_ptr.* .. pos_ptr.* + copy_len]);
            pos_ptr.* += copy_len;
            if (out_read) |ptr| ptr.* = @as(u64, @intCast(copy_len));
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_process_read_stdout(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return readProcessOutput(handle, .stdout, out, out_cap, out_read);
}

pub export fn sa_std_process_read_stderr(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return readProcessOutput(handle, .stderr, out, out_cap, out_read);
}

pub export fn sa_std_process_exec_capture(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;

    var process: u64 = 0;
    var run_status = sa_std_process_run(argv_ptr, argv_len, &process);
    if (run_status != SA_STD_OK) return run_status;
    errdefer _ = sa_std_process_close(process);

    run_status = sa_std_process_wait(process, code_ptr);
    if (run_status != SA_STD_OK) return run_status;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_len: u64 = 0;
    run_status = sa_std_process_read_stdout(process, &stdout_buf, stdout_buf.len, &stdout_len);
    if (run_status != SA_STD_OK) return run_status;

    var stderr_buf: [8192]u8 = undefined;
    var stderr_len: u64 = 0;
    run_status = sa_std_process_read_stderr(process, &stderr_buf, stderr_buf.len, &stderr_len);
    if (run_status != SA_STD_OK) return run_status;

    const stdout_owned = std.heap.page_allocator.dupe(u8, stdout_buf[0..@as(usize, @intCast(stdout_len))]) catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(stdout_owned);
    const stderr_owned = std.heap.page_allocator.dupe(u8, stderr_buf[0..@as(usize, @intCast(stderr_len))]) catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(stderr_owned);

    stdout_ptr.* = openOwnedByteBuffer(stdout_owned) catch |err| return finishErr(err);
    errdefer _ = sa_std_close(stdout_ptr.*);
    stderr_ptr.* = openOwnedByteBuffer(stderr_owned) catch |err| return finishErr(err);
    _ = sa_std_process_close(process);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_exec_capture_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;

    var process: u64 = 0;
    var run_status = sa_std_process_run_cwd(argv_ptr, argv_len, cwd_ptr, cwd_len, &process);
    if (run_status != SA_STD_OK) return run_status;
    errdefer _ = sa_std_process_close(process);

    run_status = sa_std_process_wait(process, code_ptr);
    if (run_status != SA_STD_OK) return run_status;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_len: u64 = 0;
    run_status = sa_std_process_read_stdout(process, &stdout_buf, stdout_buf.len, &stdout_len);
    if (run_status != SA_STD_OK) return run_status;

    var stderr_buf: [8192]u8 = undefined;
    var stderr_len: u64 = 0;
    run_status = sa_std_process_read_stderr(process, &stderr_buf, stderr_buf.len, &stderr_len);
    if (run_status != SA_STD_OK) return run_status;

    const stdout_owned = std.heap.page_allocator.dupe(u8, stdout_buf[0..@as(usize, @intCast(stdout_len))]) catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(stdout_owned);
    const stderr_owned = std.heap.page_allocator.dupe(u8, stderr_buf[0..@as(usize, @intCast(stderr_len))]) catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(stderr_owned);

    stdout_ptr.* = openOwnedByteBuffer(stdout_owned) catch |err| return finishErr(err);
    errdefer _ = sa_std_close(stdout_ptr.*);
    stderr_ptr.* = openOwnedByteBuffer(stderr_owned) catch |err| return finishErr(err);
    _ = sa_std_process_close(process);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_term_raw_enter(handle: u64, out_session: ?*u64) i32 {
    const session_ptr = out_session orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    session_ptr.* = 0;
    registry_mutex.lock();
    defer registry_mutex.unlock();

    const fd = handleToFd(handle) catch |err| return finishErr(err);
    const original = std.posix.tcgetattr(fd) catch |err| return finishErr(err);
    var raw = original;
    applyRawMode(&raw);
    std.posix.tcsetattr(fd, .FLUSH, raw) catch |err| return finishErr(err);

    const session = registerResourceLocked(.{ .terminal_session = .{ .fd = fd, .saved = original } }) catch |err| {
        std.posix.tcsetattr(fd, .FLUSH, original) catch |restore_err| return finishErr(restore_err);
        return finishErr(err);
    };
    session_ptr.* = session;
    return finish(SA_STD_OK);
}

pub export fn sa_term_raw_leave(session_handle: u64) i32 {
    return sa_std_close(session_handle);
}

pub export fn sa_term_winsize(handle: u64, out_size: ?*SaTermWinsize) i32 {
    const size_ptr = out_size orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    size_ptr.* = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    registry_mutex.lock();
    defer registry_mutex.unlock();

    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    const fd = handleToFd(handle) catch |err| return finishErr(err);
    var wsz: std.posix.winsize = undefined;
    while (true) {
        const rc = std.os.linux.ioctl(fd, std.os.linux.T.IOCGWINSZ, @intFromPtr(&wsz));
        switch (std.os.linux.E.init(rc)) {
            .SUCCESS => {
                size_ptr.* = .{
                    .row = wsz.row,
                    .col = wsz.col,
                    .xpixel = wsz.xpixel,
                    .ypixel = wsz.ypixel,
                };
                return finish(SA_STD_OK);
            },
            .INTR => continue,
            .BADF => return finish(SA_STD_ERR_INVALID_HANDLE),
            .NOTTY => return finish(SA_STD_ERR_UNSUPPORTED),
            else => return finish(SA_STD_ERR_IO),
        }
    }
}

pub export fn sa_term_epoll_create(flags: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const cloexec_flag: u32 = @as(u32, @intCast(std.os.linux.EPOLL.CLOEXEC));
    if ((flags & ~cloexec_flag) != 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const fd = std.posix.epoll_create1(flags) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const handle = registerResourceLocked(.{ .owned_fd = .{ .fd = fd } }) catch |err| {
        std.posix.close(fd);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_term_epoll_ctl(epoll_handle: u64, op: u32, target_handle: u64, events: u32, data: u64) i32 {
    if (op != std.os.linux.EPOLL.CTL_ADD and op != std.os.linux.EPOLL.CTL_MOD and op != std.os.linux.EPOLL.CTL_DEL) {
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    }
    if (op != std.os.linux.EPOLL.CTL_DEL and events == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    registry_mutex.lock();
    defer registry_mutex.unlock();

    const epoll_fd = handleToFd(epoll_handle) catch |err| return finishErr(err);
    const target_fd = handleToFd(target_handle) catch |err| return finishErr(err);
    var event: std.os.linux.epoll_event = .{
        .events = events,
        .data = .{ .u64 = data },
    };
    const event_ptr = if (op == std.os.linux.EPOLL.CTL_DEL) null else &event;
    std.posix.epoll_ctl(epoll_fd, op, target_fd, event_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_term_epoll_wait(epoll_handle: u64, out_events: ?[*]SaTermEpollEvent, max_events: u64, timeout_ms: i32, out_count: ?*u64) i32 {
    const events_ptr = out_events orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count_ptr = out_count orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    count_ptr.* = 0;
    const event_count = lenAsUsize(max_events) catch |err| return finishErr(err);
    if (event_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);

    registry_mutex.lock();
    defer registry_mutex.unlock();

    const epoll_fd = handleToFd(epoll_handle) catch |err| return finishErr(err);
    const kernel_events = std.heap.page_allocator.alloc(std.os.linux.epoll_event, event_count) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(kernel_events);

    const ready = std.posix.epoll_wait(epoll_fd, kernel_events, timeout_ms);
    for (kernel_events[0..ready], 0..) |event, i| {
        events_ptr[i] = .{
            .events = event.events,
            .data = event.data.u64,
        };
    }
    count_ptr.* = @as(u64, @intCast(ready));
    return finish(SA_STD_OK);
}

pub export fn sa_term_epoll_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_io_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_io_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_io_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_io_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return sa_std_read(handle, out, out_cap, out_read);
}

pub export fn sa_io_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    var count: u64 = 0;
    const status = sa_std_read(handle, out, len, &count);
    if (status != SA_STD_OK or count != len) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_io_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    return sa_std_write(handle, data, len, out_written);
}

pub export fn sa_io_write_all(handle: u64, data: ?[*]const u8, len: u64) i32 {
    var written: u64 = 0;
    const status = sa_std_write(handle, data, len, &written);
    if (status != SA_STD_OK or written != len) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_io_flush(handle: u64) i32 {
    _ = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_io_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_io_buffer_data(buffer: ?*const BufferHandle) ?[*]u8 {
    return if (buffer) |buf| buf.bytes.ptr else null;
}

pub export fn sa_io_buffer_len(buffer: ?*const BufferHandle) u64 {
    return if (buffer) |buf| @as(u64, @intCast(buf.bytes.len)) else 0;
}

pub export fn sa_io_buffer_free(buffer: ?*BufferHandle) i32 {
    _ = buffer;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_open(path_ptr: ?[*]const u8, path_len: u64, flags: u32) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const read = (flags & 1) != 0;
    const write = (flags & 2) != 0;
    const create = (flags & 4) != 0;
    const truncate = (flags & 8) != 0;
    const append = (flags & 16) != 0;
    const handle = if (create or write or append or truncate) blk: {
        const file = std.fs.cwd().createFile(path, .{ .read = read or write, .truncate = truncate, .exclusive = false }) catch |err| return finishErr(err);
        break :blk registerResource(.{ .file = file }) catch |err| return finishErr(err);
    } else blk: {
        const file = std.fs.cwd().openFile(path, .{ .mode = if (read and !write) .read_only else .read_write }) catch |err| return finishErr(err);
        break :blk registerResource(.{ .file = file }) catch |err| return finishErr(err);
    };
    return @as(i32, @intCast(handle));
}

pub export fn sa_fs_file_create(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_std_fs_open_write(path_ptr, path_len, 1, null);
}

pub export fn sa_fs_file_close(handle: u64) i32 {
    return sa_std_close(handle);
}
pub export fn sa_fs_file_read(handle: u64, out: ?[*]u8, cap: u64) i32 {
    return sa_std_read(handle, out, cap, null);
}
pub export fn sa_fs_file_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    return sa_io_read_exact(handle, out, len);
}
pub export fn sa_fs_file_write(handle: u64, out: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, out, len);
}
pub export fn sa_fs_file_write_all(handle: u64, out: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, out, len);
}
pub export fn sa_fs_file_flush(handle: u64) i32 {
    _ = handle;
    return finish(SA_STD_OK);
}
pub export fn sa_fs_file_sync(handle: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |f| {
            f.sync() catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_file_truncate(handle: u64, new_size: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |f| {
            f.setEndPos(new_size) catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_file_seek(handle: u64, whence: u32, offset: i64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |f| {
            const seek_result = switch (whence) {
                0 => f.seekTo(@as(u64, @intCast(offset))),
                1 => f.seekBy(offset),
                2 => f.seekFromEnd(offset),
                else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            };
            seek_result catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return fail(u64, mapError(err));
    defer file.close();
    const cap = lenAsUsize(max_bytes) catch |err| return fail(u64, mapError(err));
    const bytes = file.readToEndAlloc(std.heap.page_allocator, cap) catch |err| return fail(u64, mapError(err));
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
}

pub export fn sa_fs_write_file(path_ptr: ?[*]const u8, path_len: u64, buf: ?[*]const u8, len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_buffer_data(handle: u64) ?[*]u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .buffer => |*buf| buf.bytes.ptr,
        else => null,
    };
}

pub export fn sa_fs_read_buffer_len(handle: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .buffer => |*buf| @as(u64, @intCast(buf.bytes.len)),
        else => 0,
    };
}

pub export fn sa_fs_read_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_read_file_base64(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return fail(u64, mapError(err));
    defer file.close();
    const cap = lenAsUsize(max_bytes) catch |err| return fail(u64, mapError(err));
    const bytes = file.readToEndAlloc(std.heap.page_allocator, cap) catch |err| return fail(u64, mapError(err));
    defer std.heap.page_allocator.free(bytes);
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch |err| return fail(u64, mapError(err));
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = encoded } }) catch |err| {
        std.heap.page_allocator.free(encoded);
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
}

pub export fn sa_fs_write_file_base64(path_ptr: ?[*]const u8, path_len: u64, encoded_ptr: ?[*]const u8, encoded_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const encoded = constBytes(encoded_ptr, encoded_len) catch |err| return finishErr(err);
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(decoded) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn writeJsonBoolField(writer: anytype, name: []const u8, value: bool) !void {
    try writer.writeAll("\"");
    try writer.writeAll(name);
    try writer.writeAll("\":");
    try writer.writeAll(if (value) "true" else "false");
}

fn nsToMs(ns: i128) i64 {
    const ms = @divTrunc(ns, std.time.ns_per_ms);
    if (ms > std.math.maxInt(i64)) return std.math.maxInt(i64);
    if (ms < std.math.minInt(i64)) return std.math.minInt(i64);
    return @intCast(ms);
}

fn writeJsonIntField(writer: anytype, name: []const u8, value: anytype) !void {
    try writer.writeAll("\"");
    try writer.writeAll(name);
    try writer.writeAll("\":");
    try writer.print("{}", .{value});
}

fn writeMetadataJson(writer: anytype, stat: std.fs.File.Stat) !void {
    try writer.writeAll("{");
    try writeJsonIntField(writer, "createdAtMs", nsToMs(stat.ctime));
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isDirectory", stat.kind == .directory);
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isFile", stat.kind == .file);
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isSymlink", stat.kind == .sym_link);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "modifiedAtMs", nsToMs(stat.mtime));
    try writer.writeAll("}");
}

pub export fn sa_fs_read_dir_json(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| return fail(u64, mapError(err));
    defer dir.close();

    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    const writer = out.writer();
    writer.writeAll("{\"entries\":[") catch |err| return fail(u64, mapError(err));
    const limit = lenAsUsize(max_entries) catch |err| return fail(u64, mapError(err));
    var it = dir.iterate();
    var count: usize = 0;
    var first = true;
    while (count < limit) {
        const maybe_entry = it.next() catch |err| return fail(u64, mapError(err));
        const entry = maybe_entry orelse break;
        if (!first) writer.writeAll(",") catch |err| return fail(u64, mapError(err));
        first = false;
        writer.writeAll("{\"name\":") catch |err| return fail(u64, mapError(err));
        std.json.stringify(entry.name, .{}, writer) catch |err| return fail(u64, mapError(err));
        writer.writeAll(",") catch |err| return fail(u64, mapError(err));
        writeJsonBoolField(writer, "isDirectory", entry.kind == .directory) catch |err| return fail(u64, mapError(err));
        writer.writeAll(",") catch |err| return fail(u64, mapError(err));
        writeJsonBoolField(writer, "isFile", entry.kind == .file) catch |err| return fail(u64, mapError(err));
        writer.writeAll("}") catch |err| return fail(u64, mapError(err));
        count += 1;
    }
    writer.writeAll("]}") catch |err| return fail(u64, mapError(err));
    const bytes = out.toOwnedSlice() catch |err| return fail(u64, mapError(err));
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
}

pub export fn sa_fs_dir_buffer_data(handle: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(handle);
}

pub export fn sa_fs_dir_buffer_len(handle: u64) u64 {
    return sa_fs_read_buffer_len(handle);
}

pub export fn sa_fs_dir_buffer_free(handle: u64) i32 {
    return sa_fs_read_buffer_free(handle);
}

pub export fn sa_fs_metadata(path_ptr: ?[*]const u8, path_len: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const posix_stat = std.posix.fstatat(std.fs.cwd().fd, path, std.posix.AT.SYMLINK_NOFOLLOW) catch |err| return fail(u64, mapError(err));
    const stat = std.fs.File.Stat.fromPosix(posix_stat);
    const handle = registerResource(.{ .metadata = .{ .allocator = std.heap.page_allocator, .stat = stat } }) catch |err| return fail(u64, mapError(err));
    return ok(u64, handle);
}

pub export fn sa_fs_metadata_json(path_ptr: ?[*]const u8, path_len: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const posix_stat = std.posix.fstatat(std.fs.cwd().fd, path, std.posix.AT.SYMLINK_NOFOLLOW) catch |err| return fail(u64, mapError(err));
    const stat = std.fs.File.Stat.fromPosix(posix_stat);
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    writeMetadataJson(out.writer(), stat) catch |err| return fail(u64, mapError(err));
    const bytes = out.toOwnedSlice() catch |err| return fail(u64, mapError(err));
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
}

pub export fn sa_fs_metadata_is_file(handle: u64) u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if (metadata.stat.kind == .file) 1 else 0,
        else => 0,
    };
}

pub export fn sa_fs_metadata_is_directory(handle: u64) u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if (metadata.stat.kind == .directory) 1 else 0,
        else => 0,
    };
}

pub export fn sa_fs_metadata_is_symlink(handle: u64) u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if (metadata.stat.kind == .sym_link) 1 else 0,
        else => 0,
    };
}

pub export fn sa_fs_metadata_modified_ms(handle: u64) i64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| nsToMs(metadata.stat.mtime),
        else => 0,
    };
}

pub export fn sa_fs_metadata_created_ms(handle: u64) i64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| nsToMs(metadata.stat.ctime),
        else => 0,
    };
}

pub export fn sa_fs_metadata_free(handle: u64) Fallible(i32) {
    const status = sa_std_close(handle);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_fs_remove_file(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_std_fs_remove(path_ptr, path_len);
}

pub export fn sa_fs_rename(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    std.fs.cwd().rename(from, to) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_make_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().makePath(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteTree(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_path(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteTree(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_copy_file(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    std.fs.cwd().copyFile(from, std.fs.cwd(), to, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32) Fallible(u64) {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_connect(host_ptr, host_len, port, &handle);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, handle);
}

pub export fn sa_net_tcp_stream_read(stream: u64, out: ?[*]u8, cap: u64) Fallible(u64) {
    var read: u64 = 0;
    const status = sa_std_read(stream, out, cap, &read);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, read);
}
pub export fn sa_net_tcp_stream_peek(stream: u64, out: ?[*]u8, cap: u64) i32 {
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);

    registry_mutex.lock();
    const fd = blk: {
        const resource = getResourceLocked(stream) orelse {
            registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        };
        break :blk switch (resource.*) {
            .tcp_stream => |s| s.handle,
            else => {
                registry_mutex.unlock();
                return finish(SA_STD_ERR_INVALID_HANDLE);
            },
        };
    };
    registry_mutex.unlock();

    const read = std.posix.recv(fd, buffer, std.posix.MSG.PEEK) catch |err| return finishErr(err);
    return finish(@as(i32, @intCast(read)));
}
pub export fn sa_net_tcp_stream_write(stream: u64, out: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(stream, out, len);
}
pub export fn sa_net_tcp_stream_write_all(stream: u64, out: ?[*]const u8, len: u64) Fallible(i32) {
    const status = sa_io_write_all(stream, out, len);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}
pub export fn sa_net_tcp_stream_flush(stream: u64) i32 {
    _ = stream;
    return finish(SA_STD_OK);
}
pub export fn sa_net_tcp_stream_peer_addr(stream: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .tcp_stream => |s| {
            var addr: std.net.Address = undefined;
            var len: std.posix.socklen_t = @sizeOf(std.net.Address);
            std.posix.getpeername(s.handle, &addr.any, &len) catch |err| return finishErr(err);
            var net_addr = NetAddrHandle.init(std.heap.page_allocator, addr) catch |err| return finishErr(err);
            const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
                net_addr.deinit();
                return finishErr(err);
            };
            return finish(@as(i32, @intCast(handle)));
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}
pub export fn sa_net_tcp_stream_shutdown(stream: u64, how: u32) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .tcp_stream => |s| {
            const shutdown: std.posix.ShutdownHow = switch (how) {
                0 => .recv,
                1 => .send,
                2 => .both,
                else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            };
            std.posix.shutdown(s.handle, shutdown) catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}
pub export fn sa_net_tcp_stream_set_read_timeout(stream: u64, timeout_ns: u64) i32 {
    return sa_std_net_tcp_stream_set_read_timeout(stream, timeout_ns);
}

pub export fn sa_net_tcp_stream_set_write_timeout(stream: u64, timeout_ns: u64) i32 {
    return sa_std_net_tcp_stream_set_write_timeout(stream, timeout_ns);
}

pub export fn sa_net_tcp_stream_set_nonblocking(stream: u64, enabled: i32) i32 {
    return sa_std_net_tcp_stream_set_nonblocking(stream, enabled);
}

pub export fn sa_net_tcp_stream_set_nodelay(stream: u64, enabled: i32) i32 {
    return sa_std_net_tcp_stream_set_nodelay(stream, enabled);
}

pub export fn sa_net_tcp_stream_set_ttl(stream: u64, ttl: u32) i32 {
    return sa_std_net_tcp_stream_set_ttl(stream, ttl);
}
pub export fn sa_net_tcp_stream_close(stream: u64) Fallible(i32) {
    const status = sa_std_close(stream);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}
pub export fn sa_net_tcp_listener_bind(host_ptr: ?[*]const u8, host_len: u64, port: u16) Fallible(u64) {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_listen(host_ptr, host_len, port, &handle, null);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, handle);
}
pub export fn sa_net_tcp_listener_accept(listener: u64) Fallible(u64) {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_accept(listener, &handle);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, handle);
}
pub export fn sa_net_tcp_listener_local_addr(listener: u64) Fallible(u64) {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(listener) orelse return fail(u64, SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .tcp_listener => |server| {
            var addr: std.net.Address = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);
            std.posix.getsockname(server.stream.handle, &addr.any, &addr_len) catch |err| return fail(u64, mapError(err));
            var net_addr = NetAddrHandle.init(std.heap.page_allocator, addr) catch |err| return fail(u64, mapError(err));
            const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
                net_addr.deinit();
                return fail(u64, mapError(err));
            };
            return ok(u64, handle);
        },
        else => fail(u64, SA_STD_ERR_INVALID_HANDLE),
    };
}
pub export fn sa_net_tcp_listener_close(listener: u64) Fallible(i32) {
    const status = sa_std_close(listener);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_std_net_tcp_stream_set_nonblocking(stream: u64, enabled: i32) i32 {
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    const flags = std.posix.fcntl(handle.fd, std.posix.F.GETFL, 0) catch |err| return finishErr(err);
    const new_flags = if (enabled != 0)
        flags | @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK")
    else
        flags & ~(@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"));
    _ = std.posix.fcntl(handle.fd, std.posix.F.SETFL, new_flags) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_nodelay(stream: u64, enabled: i32) i32 {
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptBool(handle.fd, std.posix.IPPROTO.TCP, std.posix.TCP.NODELAY, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_read_timeout(stream: u64, timeout_ns: u64) i32 {
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptTimeval(handle.fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_write_timeout(stream: u64, timeout_ns: u64) i32 {
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptTimeval(handle.fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_ttl(stream: u64, ttl: u32) i32 {
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (ttl > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, std.posix.IPPROTO.IP, std.os.linux.IP.TTL, @as(i32, @intCast(ttl))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_bind(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const host = constBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    const address = std.net.Address.resolveIp(host, port16) catch |err| return finishErr(err);
    const fd = std.posix.socket(address.any.family, std.posix.SOCK.DGRAM | std.posix.SOCK.CLOEXEC, std.posix.IPPROTO.UDP) catch |err| return finishErr(err);
    errdefer std.posix.close(fd);
    var bind_addr = address;
    std.posix.bind(fd, &bind_addr.any, bind_addr.getOsSockLen()) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const handle = registerResourceLocked(.{ .udp_socket = fd }) catch |err| {
        std.posix.close(fd);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_local_addr(socket: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .udp_socket => |fd| {
            var addr: std.net.Address = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);
            std.posix.getsockname(fd, &addr.any, &addr_len) catch |err| return finishErr(err);
            var net_addr = NetAddrHandle.init(std.heap.page_allocator, addr) catch |err| return finishErr(err);
            const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
                net_addr.deinit();
                return finishErr(err);
            };
            handle_ptr.* = handle;
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}
pub export fn sa_std_net_udp_connect(socket: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32) i32 {
    const host = constBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    const address = std.net.Address.resolveIp(host, port16) catch |err| return finishErr(err);

    registry_mutex.lock();
    defer registry_mutex.unlock();

    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .udp_socket => |fd| fd,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    std.posix.connect(fd, &address.any, address.getOsSockLen()) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
pub export fn sa_net_udp_set_read_timeout(socket: u64, timeout_ns: u64) i32 {
    return sa_std_net_udp_set_read_timeout(socket, timeout_ns);
}

pub export fn sa_net_udp_set_write_timeout(socket: u64, timeout_ns: u64) i32 {
    return sa_std_net_udp_set_write_timeout(socket, timeout_ns);
}

pub export fn sa_net_udp_set_nonblocking(socket: u64, enabled: i32) i32 {
    return sa_std_net_udp_set_nonblocking(socket, enabled);
}

pub export fn sa_net_udp_set_broadcast(socket: u64, enabled: i32) i32 {
    return sa_std_net_udp_set_broadcast(socket, enabled);
}

pub export fn sa_net_udp_set_ttl(socket: u64, ttl: u32) i32 {
    return sa_std_net_udp_set_ttl(socket, ttl);
}

pub export fn sa_std_net_udp_set_nonblocking(socket: u64, enabled: i32) i32 {
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const flags = std.posix.fcntl(handle.fd, std.posix.F.GETFL, 0) catch |err| return finishErr(err);
    const new_flags = if (enabled != 0)
        flags | @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK")
    else
        flags & ~(@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"));
    _ = std.posix.fcntl(handle.fd, std.posix.F.SETFL, new_flags) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_broadcast(socket: u64, enabled: i32) i32 {
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptBool(handle.fd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_ttl(socket: u64, ttl: u32) i32 {
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (ttl > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, std.posix.IPPROTO.IP, std.os.linux.IP.TTL, @as(i32, @intCast(ttl))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_read_timeout(socket: u64, timeout_ns: u64) i32 {
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptTimeval(handle.fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_write_timeout(socket: u64, timeout_ns: u64) i32 {
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptTimeval(handle.fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_send(socket: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);

    registry_mutex.lock();
    defer registry_mutex.unlock();

    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .udp_socket => |fd| fd,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    const written = std.posix.send(fd, bytes, 0) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_recv(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);

    registry_mutex.lock();
    defer registry_mutex.unlock();

    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .udp_socket => |fd| fd,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    const read = std.posix.recv(fd, buffer, 0) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_send_to(socket: u64, buf: ?[*]const u8, len: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32, out_written: ?*u64) i32 {
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const host = constBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    const address = std.net.Address.resolveIp(host, port16) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const fd = handleToFd(socket) catch |err| return finishErr(err);
    const written = std.posix.sendto(fd, bytes, 0, &address.any, address.getOsSockLen()) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_recv_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const fd = handleToFd(socket) catch |err| return finishErr(err);
    var addr: std.net.Address = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);
    const read = std.posix.recvfrom(fd, buffer, 0, &addr.any, &addr_len) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    if (out_addr) |ptr| {
        var net_addr = NetAddrHandle.init(std.heap.page_allocator, addr) catch |err| return finishErr(err);
        const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
            net_addr.deinit();
            return finishErr(err);
        };
        ptr.* = handle;
    }
    return finish(SA_STD_OK);
}
pub export fn sa_net_udp_bind(host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    var handle: u64 = 0;
    const status = sa_std_net_udp_bind(host_ptr, host_len, port, &handle);
    if (status != SA_STD_OK) return status;
    return @as(i32, @intCast(handle));
}
pub export fn sa_net_udp_connect(socket: u64, host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    return sa_std_net_udp_connect(socket, host_ptr, host_len, port);
}
pub export fn sa_net_udp_local_addr(socket: u64) i32 {
    var handle: u64 = 0;
    const status = sa_std_net_udp_local_addr(socket, &handle);
    if (status != SA_STD_OK) return status;
    return @as(i32, @intCast(handle));
}
pub export fn sa_net_udp_send(socket: u64, buf: ?[*]const u8, len: u64) i32 {
    var written: u64 = 0;
    const status = sa_std_net_udp_send(socket, buf, len, &written);
    if (status != SA_STD_OK) return status;
    return @as(i32, @intCast(written));
}
pub export fn sa_net_udp_recv(socket: u64, out: ?[*]u8, cap: u64) i32 {
    var read: u64 = 0;
    const status = sa_std_net_udp_recv(socket, out, cap, &read);
    if (status != SA_STD_OK) return status;
    return @as(i32, @intCast(read));
}
pub export fn sa_net_udp_send_to(socket: u64, buf: ?[*]const u8, len: u64, host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    var written: u64 = 0;
    const status = sa_std_net_udp_send_to(socket, buf, len, host_ptr, host_len, port, &written);
    if (status != SA_STD_OK) return status;
    return @as(i32, @intCast(written));
}
pub export fn sa_net_udp_recv_from(socket: u64, out: ?[*]u8, cap: u64, out_addr: ?*u64) i32 {
    var read: u64 = 0;
    const status = sa_std_net_udp_recv_from(socket, out, cap, &read, out_addr);
    if (status != SA_STD_OK) return status;
    return @as(i32, @intCast(read));
}
pub export fn sa_net_udp_close(socket: u64) i32 {
    return sa_std_close(socket);
}
pub export fn sa_net_addr_host(addr: u64) ?[*]u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return null;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| net_addr.host.ptr,
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return null;
        },
    };
}
pub export fn sa_net_addr_host_len(addr: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| @as(u64, @intCast(net_addr.host.len)),
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return 0;
        },
    };
}
pub export fn sa_net_addr_port(addr: u64) u32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| @as(u32, net_addr.addr.getPort()),
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return 0;
        },
    };
}
pub export fn sa_net_addr_family(addr: u64) u32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| @as(u32, @intCast(net_addr.addr.any.family)),
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return 0;
        },
    };
}
pub export fn sa_net_addr_free(addr: u64) Fallible(i32) {
    const status = sa_std_close(addr);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_fmt_i64(value: i64, base: u32) u64 {
    const bytes = formatInteger(value, base) catch return 0;
    return openOwnedBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_i64_into(value: i64, base: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrintIntToSlice(&buf, value, actual_base, case, .{});
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_u64(value: u64, base: u32) u64 {
    const bytes = formatInteger(value, base) catch return 0;
    return openOwnedBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_u64_into(value: u64, base: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrintIntToSlice(&buf, value, actual_base, case, .{});
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_f64(value: f64, precision: u32) u64 {
    const bytes = formatFloat(value, precision) catch return 0;
    return openOwnedBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_f64_into(value: f64, precision: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    var buf: [256]u8 = undefined;
    const text = std.fmt.formatFloat(&buf, value, .{ .mode = .decimal, .precision = @as(usize, @intCast(precision)) }) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_bool(value: bool) u64 {
    const bytes = formatBool(value) catch return 0;
    return openOwnedBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_bool_into(value: bool, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    return writeFormattedInto(out, out_cap, out_len, if (value) "true" else "false");
}

pub export fn sa_fmt_bytes(buf: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(buf, len) catch return 0;
    const owned = formatBytes(bytes) catch return 0;
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_fmt_bytes_into(buf: ?[*]const u8, len: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    return writeFormattedInto(out, out_cap, out_len, bytes);
}

pub export fn sa_env_get(key_ptr: ?[*]const u8, key_len: u64) u64 {
    const key = envKeyBytes(key_ptr, key_len) catch return 0;
    const owned = envGetOwned(key) catch return 0;
    return openOwnedEnvBuffer(owned) catch return 0;
}

pub export fn sa_env_has(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const present = envValueFromCurrentProcess(key) != null;
    return finish(if (present) SA_STD_OK else SA_STD_ERR_NOT_FOUND);
}

pub export fn sa_env_buffer_data(buffer: u64) ?[*]u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return null;
    return switch (resource.*) {
        .env => |*env| env.bytes.ptr,
        else => null,
    };
}

pub export fn sa_env_buffer_len(buffer: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return 0;
    return switch (resource.*) {
        .env => |env| @as(u64, @intCast(env.bytes.len)),
        else => 0,
    };
}

pub export fn sa_env_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_string_concat(left_ptr: ?[*]const u8, left_len: u64, right_ptr: ?[*]const u8, right_len: u64) u64 {
    const left = constBytes(left_ptr, left_len) catch return 0;
    const right = constBytes(right_ptr, right_len) catch return 0;
    const owned = stringConcat(left, right) catch return 0;
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_fmt_buffer_data(buffer: u64) ?[*]u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return null;
    return switch (resource.*) {
        .fmt => |*fmt| fmt.bytes.ptr,
        else => null,
    };
}

pub export fn sa_fmt_buffer_len(buffer: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return 0;
    return switch (resource.*) {
        .fmt => |fmt| @as(u64, @intCast(fmt.bytes.len)),
        else => 0,
    };
}

pub export fn sa_fmt_buffer_write_to(buffer: u64, writer: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const bytes = switch (resource.*) {
        .fmt => |fmt| fmt.bytes,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    const written = writeHandleLocked(writer, bytes) catch |err| return finishErr(err);
    if (written != bytes.len) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_fmt_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_print_bytes(msg: ?[*]const u8, len: u64) void {
    _ = sa_std_print(msg, len);
}

pub export fn sa_std_net_tcp_listen(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64, out_bound_port: ?*u32) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (out_bound_port) |port_ptr| port_ptr.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);

    const address = std.net.Address.resolveIp(host, port16) catch |err| return finishErr(err);
    var server = address.listen(.{ .reuse_address = true }) catch |err| return finishErr(err);
    errdefer server.deinit();
    const handle = registerResource(.{ .tcp_listener = server }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    if (out_bound_port) |port_ptr| {
        var addr: std.net.Address = undefined;
        var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);
        std.posix.getsockname(server.stream.handle, &addr.any, &addr_len) catch |err| return finishErr(err);
        port_ptr.* = addr.getPort();
    }
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_accept(listener_handle: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    registry_mutex.lock();
    const resource = getResourceLocked(listener_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const listener = switch (resource.*) {
        .tcp_listener => |server| server,
        else => {
            registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        },
    };
    registry_mutex.unlock();

    var listener_copy = listener;
    const connection = listener_copy.accept() catch |err| return finishErr(err);
    var stream = connection.stream;
    registry_mutex.lock();
    const handle = registerResourceLocked(.{ .tcp_stream = stream }) catch |err| {
        registry_mutex.unlock();
        stream.close();
        return finishErr(err);
    };
    registry_mutex.unlock();
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);

    const stream = std.net.tcpConnectToHost(std.heap.page_allocator, host, port16) catch |err| return finishErr(err);
    errdefer stream.close();
    const handle = registerResource(.{ .tcp_stream = stream }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

fn expectTimeoutRoundedUpWithin(requested_ns: u64, observed_ns: u64) !void {
    try std.testing.expect(observed_ns >= requested_ns);
    try std.testing.expect(observed_ns - requested_ns <= 10 * std.time.ns_per_ms);
}

test "socket helper round trip on raw udp socket" {
    const fd = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM | std.posix.SOCK.CLOEXEC, std.posix.IPPROTO.UDP);
    defer std.posix.close(fd);

    try setSocketOptBool(fd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, true);
    try std.testing.expect(try getSocketOptBool(fd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST));
    try setSocketOptBool(fd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, false);
    try std.testing.expect(!(try getSocketOptBool(fd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST)));

    try setSocketOptInt(fd, std.posix.IPPROTO.IP, std.os.linux.IP.TTL, 64);
    try std.testing.expectEqual(@as(i32, 64), try getSocketOptInt(fd, std.posix.IPPROTO.IP, std.os.linux.IP.TTL));

    const timeout_ns: u64 = 1_234_567_890;
    try setSocketOptTimeval(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, timeout_ns);
    try expectTimeoutRoundedUpWithin(timeout_ns, try getSocketOptTimeval(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO));

    const tv = try timevalFromNs(timeout_ns);
    try std.testing.expectEqual(@as(u64, 1_234_567_000), try nsFromTimeval(tv));
}

test "exported tcp and udp socket setters update live handles" {
    const host = "127.0.0.1";

    var udp_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &udp_handle));
    defer _ = sa_std_close(udp_handle);

    const udp = try ensureSocketHandle(udp_handle);
    try std.testing.expectEqual(@as(@TypeOf(udp.kind), .udp_socket), udp.kind);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_nonblocking(udp_handle, 1));
    const udp_flags = try std.posix.fcntl(udp.fd, std.posix.F.GETFL, 0);
    try std.testing.expect((udp_flags & (@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"))) != 0);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_broadcast(udp_handle, 1));
    try std.testing.expect(try getSocketOptBool(udp.fd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_ttl(udp_handle, 64));
    try std.testing.expectEqual(@as(i32, 64), try getSocketOptInt(udp.fd, std.posix.IPPROTO.IP, std.os.linux.IP.TTL));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_read_timeout(udp_handle, 250_000_000));
    try expectTimeoutRoundedUpWithin(250_000_000, try getSocketOptTimeval(udp.fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_write_timeout(udp_handle, 250_000_000));
    try expectTimeoutRoundedUpWithin(250_000_000, try getSocketOptTimeval(udp.fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO));

    var listener_handle: u64 = 0;
    var bound_port: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listen(host.ptr, host.len, 0, &listener_handle, &bound_port));
    defer _ = sa_std_close(listener_handle);
    try std.testing.expect(bound_port != 0);

    var client_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_connect(host.ptr, host.len, bound_port, &client_handle));
    defer _ = sa_std_close(client_handle);

    var server_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_accept(listener_handle, &server_handle));
    defer _ = sa_std_close(server_handle);

    const server = try ensureSocketHandle(server_handle);
    try std.testing.expectEqual(@as(@TypeOf(server.kind), .tcp_stream), server.kind);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_nonblocking(server_handle, 1));
    const server_flags = try std.posix.fcntl(server.fd, std.posix.F.GETFL, 0);
    try std.testing.expect((server_flags & (@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"))) != 0);
    var peek_buf: [1]u8 = undefined;
    try std.testing.expectEqual(SA_STD_ERR_IO, sa_net_tcp_stream_peek(server_handle, &peek_buf, peek_buf.len));

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_nodelay(server_handle, 1));
    try std.testing.expect(try getSocketOptBool(server.fd, std.posix.IPPROTO.TCP, std.posix.TCP.NODELAY));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_ttl(server_handle, 64));
    try std.testing.expectEqual(@as(i32, 64), try getSocketOptInt(server.fd, std.posix.IPPROTO.IP, std.os.linux.IP.TTL));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_read_timeout(server_handle, 250_000_000));
    try expectTimeoutRoundedUpWithin(250_000_000, try getSocketOptTimeval(server.fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_write_timeout(server_handle, 250_000_000));
    try expectTimeoutRoundedUpWithin(250_000_000, try getSocketOptTimeval(server.fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO));
}
