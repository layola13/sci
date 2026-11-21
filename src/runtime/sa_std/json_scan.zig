const std = @import("std");
pub const SA_JSON_TOKEN_INVALID = @import("../sa_std.zig").SA_JSON_TOKEN_INVALID;

pub const JsonScannerHandle = struct {
    allocator: std.mem.Allocator,
    scanner: std.json.Scanner,
    pending_input: []const u8 = &.{},
    pending_input_owned: bool = false,
    pending_text: std.array_list.Managed(u8),
    current_text: ?[]const u8 = null,
    current_token: u32 = SA_JSON_TOKEN_INVALID,

    pub fn init(allocator: std.mem.Allocator) !*JsonScannerHandle {
        const handle = try allocator.create(JsonScannerHandle);
        handle.* = .{
            .allocator = allocator,
            .scanner = std.json.Scanner.initStreaming(allocator),
            .pending_input = &.{},
            .pending_input_owned = false,
            .pending_text = std.array_list.Managed(u8).init(allocator),
            .current_text = null,
            .current_token = SA_JSON_TOKEN_INVALID,
        };
        return handle;
    }

    pub fn initCompleteInput(allocator: std.mem.Allocator, input: []const u8) !*JsonScannerHandle {
        const handle = try allocator.create(JsonScannerHandle);
        handle.* = .{
            .allocator = allocator,
            .scanner = std.json.Scanner.initCompleteInput(allocator, input),
            .pending_input = input,
            .pending_input_owned = false,
            .pending_text = std.array_list.Managed(u8).init(allocator),
            .current_text = null,
            .current_token = SA_JSON_TOKEN_INVALID,
        };
        return handle;
    }

    pub fn deinit(self: *JsonScannerHandle) void {
        self.pending_text.deinit();
        self.scanner.deinit();
        if (self.pending_input_owned and self.pending_input.len != 0) self.allocator.free(self.pending_input);
        self.pending_input = &.{};
        self.pending_input_owned = false;
        self.current_text = null;
        self.current_token = SA_JSON_TOKEN_INVALID;
    }

    pub fn destroy(self: *JsonScannerHandle) void {
        self.deinit();
        self.allocator.destroy(self);
    }
};

pub const JsonStreamHandle = struct {
    allocator: std.mem.Allocator,
    owned_input: []u8,
    scanner: *JsonScannerHandle,
    last_token: u32 = SA_JSON_TOKEN_INVALID,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) !*JsonStreamHandle {
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

    pub fn deinit(self: *JsonStreamHandle) void {
        self.scanner.destroy();
        if (self.owned_input.len != 0) self.allocator.free(self.owned_input);
        self.owned_input = &.{};
        self.allocator.destroy(self);
    }
};

pub fn tokenTextBytes(scanner_handle: *JsonScannerHandle, token: std.json.Token) ![]const u8 {
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

pub fn jsonScannerFeed(scanner_handle: *JsonScannerHandle, input: []const u8, end_input: bool) !void {
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
