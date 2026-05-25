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
};

const PthreadHandle = struct {
    thread: std.Thread,
    task: *PthreadTask,
    joined: bool = false,
};

fn pthreadTaskMain(task: *PthreadTask) void {
    task.result = task.entry(task.arg);
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
        slot.* = if (n == 0) &.{ } else entry.data[0..n];
    }
    return args;
}

fn envpFromCurrentProcess(arena: std.mem.Allocator) ![:null]const ?[*:0]const u8 {
    const env_block = try arena.alloc(?[*:0]const u8, std.os.environ.len + 1);
    for (std.os.environ, 0..) |entry, i| {
        env_block[i] = entry;
    }
    env_block[std.os.environ.len] = null;
    return env_block[0 .. std.os.environ.len :null];
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

fn spawnProcess(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode) !SpawnResult {
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

fn openOwnedBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .fmt = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
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
        .allocated_number,
        .allocated_string,
        .partial_string_escaped_1, .partial_string_escaped_2, .partial_string_escaped_3, .partial_string_escaped_4 => {
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
        .allocated_number,
        .allocated_string,
        .partial_string_escaped_1, .partial_string_escaped_2, .partial_string_escaped_3, .partial_string_escaped_4 => {
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
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    writer_handle.stream.objectField(field) catch |err| return finishErr(err);
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

pub export fn sa_std_process_spawn(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const argv = argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(argv);
    const result = spawnProcess(std.heap.page_allocator, argv, .inherit) catch |err| return finishErr(err);
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

pub export fn sa_fs_file_close(handle: u64) i32 { return sa_std_close(handle); }
pub export fn sa_fs_file_read(handle: u64, out: ?[*]u8, cap: u64) i32 { return sa_std_read(handle, out, cap, null); }
pub export fn sa_fs_file_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 { return sa_io_read_exact(handle, out, len); }
pub export fn sa_fs_file_write(handle: u64, out: ?[*]const u8, len: u64) i32 { return sa_io_write_all(handle, out, len); }
pub export fn sa_fs_file_write_all(handle: u64, out: ?[*]const u8, len: u64) i32 { return sa_io_write_all(handle, out, len); }
pub export fn sa_fs_file_flush(handle: u64) i32 { _ = handle; return finish(SA_STD_OK); }
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

pub export fn sa_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return finishErr(err);
    errdefer file.close();
    const cap = lenAsUsize(max_bytes) catch |err| return finishErr(err);
    const bytes = file.readToEndAlloc(std.heap.page_allocator, cap) catch |err| return finishErr(err);
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| return finishErr(err);
    return @as(i32, @intCast(handle));
}

pub export fn sa_fs_write_file(path_ptr: ?[*]const u8, path_len: u64, buf: ?[*]const u8, len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_buffer_data(buffer: ?*const BufferHandle) ?[*]u8 {
    return sa_io_buffer_data(buffer);
}

pub export fn sa_fs_read_buffer_len(buffer: ?*const BufferHandle) u64 {
    return sa_io_buffer_len(buffer);
}

pub export fn sa_fs_read_buffer_free(buffer: ?*BufferHandle) i32 {
    _ = buffer;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_metadata(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const stat = std.fs.cwd().statFile(path) catch |err| return finishErr(err);
    const handle = registerResource(.{ .metadata = .{ .allocator = std.heap.page_allocator, .stat = stat } }) catch |err| return finishErr(err);
    return @as(i32, @intCast(handle));
}

pub export fn sa_fs_metadata_free(handle: u64) i32 {
    return sa_std_close(handle);
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
    std.fs.cwd().makeDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteTree(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32) Fallible(u64) {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_connect(host_ptr, host_len, port, &handle);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, handle);
}

pub export fn sa_net_tcp_stream_read(stream: u64, out: ?[*]u8, cap: u64) Fallible(u64) { var read: u64 = 0; const status = sa_std_read(stream, out, cap, &read); if (status != SA_STD_OK) return fail(u64, status); return ok(u64, read); }
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
pub export fn sa_net_tcp_stream_write(stream: u64, out: ?[*]const u8, len: u64) i32 { return sa_io_write_all(stream, out, len); }
pub export fn sa_net_tcp_stream_write_all(stream: u64, out: ?[*]const u8, len: u64) Fallible(i32) { const status = sa_io_write_all(stream, out, len); if (status != SA_STD_OK) return fail(i32, status); return ok(i32, 0); }
pub export fn sa_net_tcp_stream_flush(stream: u64) i32 { _ = stream; return finish(SA_STD_OK); }
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
pub export fn sa_net_udp_close(socket: u64) i32 { return sa_std_close(socket); }
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

pub export fn sa_fmt_buffer_free(handle: u64) Fallible(i32) {
    const status = sa_std_close(handle);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
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
