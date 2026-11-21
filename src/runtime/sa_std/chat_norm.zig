const std = @import("std");
pub const appendJsonString = @import("../sa_std.zig").appendJsonString;
pub const jsonObjectGetValue = @import("../sa_std.zig").jsonObjectGetValue;
pub const jsonStringValue = @import("../sa_std.zig").jsonStringValue;
pub const listWriter = @import("../sa_std.zig").listWriter;
pub const stringifyToList = @import("../sa_std.zig").stringifyToList;

fn longestSuffixPrefix(text: []const u8, prefix: []const u8) usize {
    if (text.len == 0 or prefix.len == 0) return 0;
    const max_len = @min(text.len, prefix.len - 1);
    var len = max_len;
    while (len > 0) : (len -= 1) {
        if (std.mem.eql(u8, text[text.len - len ..], prefix[0..len])) return len;
    }
    return 0;
}

pub const ThoughtStreamSplitter = struct {
    allocator: std.mem.Allocator,
    pending: std.array_list.Managed(u8),
    in_thought: bool = false,

    pub fn init(allocator: std.mem.Allocator) ThoughtStreamSplitter {
        return .{
            .allocator = allocator,
            .pending = std.array_list.Managed(u8).init(allocator),
            .in_thought = false,
        };
    }

    pub fn deinit(self: *ThoughtStreamSplitter) void {
        self.pending.deinit();
    }

    pub fn consume(self: *ThoughtStreamSplitter, chunk: []const u8, visible: *std.array_list.Managed(u8), reasoning: *std.array_list.Managed(u8)) !void {
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

    pub fn flush(self: *ThoughtStreamSplitter, visible: *std.array_list.Managed(u8), reasoning: *std.array_list.Managed(u8)) !void {
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

fn jsonU64Value(value: ?std.json.Value) u64 {
    const actual = value orelse return 0;
    return switch (actual) {
        .integer => |inner| if (inner >= 0) @as(u64, @intCast(inner)) else 0,
        .float => |inner| if (inner >= 0 and inner <= @as(f64, @floatFromInt(std.math.maxInt(u64)))) @as(u64, @intFromFloat(inner)) else 0,
        else => 0,
    };
}

pub fn appendResponseCreated(out: *std.array_list.Managed(u8)) !void {
    try out.appendSlice("event: response.created\n");
    try out.appendSlice("data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_chat_fb\"}}\n\n");
}

pub fn appendReasoningDelta(
    out: *std.array_list.Managed(u8),
    reasoning_started: *bool,
    reasoning_done: *bool,
    reasoning_output_index: *u64,
    next_output_index: *u64,
    text: []const u8,
) !void {
    if (text.len == 0) return;
    const writer = listWriter(out);
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

pub fn appendReasoningDone(
    out: *std.array_list.Managed(u8),
    reasoning_started: bool,
    reasoning_done: *bool,
    reasoning_output_index: u64,
    reasoning_text: []const u8,
) !void {
    if (!reasoning_started) return;
    if (reasoning_done.*) return;
    const writer = listWriter(out);
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

pub fn appendMessageDelta(
    out: *std.array_list.Managed(u8),
    message_started: *bool,
    message_output_index: *u64,
    next_output_index: *u64,
    message_text: *std.array_list.Managed(u8),
    text: []const u8,
) !void {
    if (text.len == 0) return;
    const writer = listWriter(out);
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

pub fn appendMessageDone(out: *std.array_list.Managed(u8), message_started: bool, message_output_index: u64, message_text: []const u8) !void {
    if (!message_started) return;
    const writer = listWriter(out);
    try out.appendSlice("event: response.output_item.done\n");
    try out.appendSlice("data: {\"type\":\"response.output_item.done\",\"output_index\":");
    try writer.print("{}", .{message_output_index});
    try out.appendSlice(",\"item\":{\"id\":\"msg_chat_fb\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":");
    try appendJsonString(writer, message_text);
    try out.appendSlice("}]}}\n\n");
}

pub fn requestAllowsContinuation(req_body: []const u8) bool {
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

pub fn isProgressOnlyText(text: []const u8) bool {
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

pub fn appendContinuationTool(out: *std.array_list.Managed(u8)) !void {
    try out.appendSlice("event: response.output_item.done\n");
    try out.appendSlice("data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"tc_chat_continue\",\"type\":\"function_call\",\"call_id\":\"call_chat_continue\",\"name\":\"exec_command\",\"arguments\":\"{\\\"cmd\\\":\\\"printf '%s\\\\n' 'Progress-only message received in chat fallback. Continue now: call a read-only tool if more evidence is needed, otherwise provide the final answer.'\\\"}\"}}\n\n");
}

pub fn appendContinuationToolJson(out: *std.array_list.Managed(u8)) !void {
    try out.appendSlice("{\"type\":\"function_call\",\"id\":\"tc_chat_continue\",\"call_id\":\"call_chat_continue\",\"name\":\"exec_command\",\"arguments\":\"{\\\"cmd\\\":\\\"printf '%s\\\\n' 'Progress-only message received in chat fallback. Continue now: call a read-only tool if more evidence is needed, otherwise provide the final answer.'\\\"}\"}");
}

pub const ChatToolCallState = struct {
    allocator: std.mem.Allocator,
    index: usize,
    call_id: std.array_list.Managed(u8),
    name: std.array_list.Managed(u8),
    arguments: std.array_list.Managed(u8),

    pub fn init(allocator: std.mem.Allocator, index: usize) ChatToolCallState {
        return .{
            .allocator = allocator,
            .index = index,
            .call_id = std.array_list.Managed(u8).init(allocator),
            .name = std.array_list.Managed(u8).init(allocator),
            .arguments = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *ChatToolCallState) void {
        self.call_id.deinit();
        self.name.deinit();
        self.arguments.deinit();
    }
};

fn shellQuote(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
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

fn appendCommandArguments(out_arguments: *std.array_list.Managed(u8), command: []const u8) !void {
    try out_arguments.appendSlice("{\"cmd\":");
    try appendJsonString(listWriter(out_arguments), command);
    try out_arguments.append('}');
}

fn appendReadCommand(allocator: std.mem.Allocator, path: []const u8, out_arguments: *std.array_list.Managed(u8)) !void {
    const quoted = try shellQuote(allocator, path);
    defer allocator.free(quoted);
    var command = std.array_list.Managed(u8).init(allocator);
    defer command.deinit();
    if (isSensitiveEnvPath(path)) {
        try command.appendSlice("sed -E 's/(OPENAI_API_KEY|AUTH|TOKEN|KEY|SECRET)=.*/\\\\1=<redacted>/I' ");
    } else {
        try command.appendSlice("cat ");
    }
    try command.appendSlice(quoted);
    try appendCommandArguments(out_arguments, command.items);
}

pub fn splitMcpNamespace(name: []const u8) ?struct { namespace: []const u8, tool: []const u8 } {
    if (!std.mem.startsWith(u8, name, "mcp__")) return null;
    const rest_start: usize = 5;
    const rel_end = std.mem.indexOf(u8, name[rest_start..], "__") orelse return null;
    const ns_len = rest_start + rel_end + 2;
    if (name.len <= ns_len) return null;
    const tool_start = if (name[ns_len] == '.') ns_len + 1 else ns_len;
    if (tool_start >= name.len) return null;
    return .{ .namespace = name[0..ns_len], .tool = name[tool_start..] };
}

pub fn denormalizeMcpServerNameAlloc(allocator: std.mem.Allocator, server: []const u8) ![]u8 {
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

fn requestMentionsTool(req_body: []const u8, name: []const u8) bool {
    return name.len != 0 and std.mem.indexOf(u8, req_body, name) != null;
}

pub fn normalizeChatToolArguments(
    allocator: std.mem.Allocator,
    req_body: []const u8,
    name: []const u8,
    arguments: []const u8,
    out_namespace: *std.array_list.Managed(u8),
    out_name: *std.array_list.Managed(u8),
    out_arguments: *std.array_list.Managed(u8),
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
        var message = std.array_list.Managed(u8).init(allocator);
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
        var command = std.array_list.Managed(u8).init(allocator);
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

pub const appendNormalizedToolCall = @import("chat_resp.zig").appendNormalizedToolCall;

pub const appendNormalizedToolCallJson = @import("chat_resp.zig").appendNormalizedToolCallJson;

fn findToolCallState(calls: *std.array_list.Managed(ChatToolCallState), index: usize) !*ChatToolCallState {
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

pub fn appendResponseDone(out: *std.array_list.Managed(u8)) !void {
    try out.appendSlice("event: response.done\n");
    try out.appendSlice("data: {\"type\":\"response.done\",\"response\":{\"id\":\"resp_chat_fb\",\"status\":\"completed\"}}\n\n");
    try out.appendSlice("event: response.completed\n");
    try out.appendSlice("data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_chat_fb\",\"status\":\"completed\"}}\n\n");
}

pub fn appendChatUsageJson(out: *std.array_list.Managed(u8), usage: ?std.json.Value) !void {
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
    try listWriter(out).print(
        "\"usage\":{{\"input_tokens\":{},\"input_tokens_details\":{{\"cached_tokens\":{}}},\"output_tokens\":{},\"output_tokens_details\":{{\"reasoning_tokens\":{}}},\"total_tokens\":{}}}",
        .{ prompt_tokens, cached_tokens, completion_tokens, reasoning_tokens, total_tokens },
    );
}

pub fn appendChatJsonReasoningItem(out: *std.array_list.Managed(u8), text: []const u8) !void {
    const writer = listWriter(out);
    try out.appendSlice("{\"type\":\"reasoning\",\"summary\":[{\"type\":\"summary_text\",\"text\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}],\"encrypted_content\":null,\"content\":[{\"type\":\"reasoning_text\",\"text\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}]}");
}

pub fn appendChatJsonMessageItem(out: *std.array_list.Managed(u8), text: []const u8) !void {
    const writer = listWriter(out);
    try out.appendSlice("{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":");
    try appendJsonString(writer, text);
    try out.appendSlice("}]}");
}

pub fn appendOutputComma(out: *std.array_list.Managed(u8), count: *usize) !void {
    if (count.* != 0) try out.append(',');
    count.* += 1;
}

pub const denoChatJsonToResponses = @import("chat_resp.zig").denoChatJsonToResponses;

const ThoughtSplit = struct {
    visible: []u8,
    reasoning: []u8,
};

pub fn splitThoughtTextAlloc(allocator: std.mem.Allocator, text: []const u8) !ThoughtSplit {
    var splitter = ThoughtStreamSplitter.init(allocator);
    defer splitter.deinit();
    var visible = std.array_list.Managed(u8).init(allocator);
    errdefer visible.deinit();
    var reasoning = std.array_list.Managed(u8).init(allocator);
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

pub fn appendMergedReasoningText(out: *std.array_list.Managed(u8), text: []const u8) !void {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return;
    if (std.mem.indexOf(u8, out.items, trimmed) != null) return;
    if (out.items.len != 0) try out.append('\n');
    try out.appendSlice(trimmed);
}

pub fn appendReasoningFields(value: std.json.Value, out: *std.array_list.Managed(u8)) !void {
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

pub const isNativeReasoningType = @import("chat_resp.zig").isNativeReasoningType;

pub const appendNativeReasoningItem = @import("chat_resp.zig").appendNativeReasoningItem;

pub const appendNativeMessageItem = @import("chat_resp.zig").appendNativeMessageItem;

pub const appendNativeNormalizedOutput = @import("chat_resp.zig").appendNativeNormalizedOutput;

pub const nativeResponsesJsonNeedsNormalize = @import("chat_resp.zig").nativeResponsesJsonNeedsNormalize;

pub const denoResponsesJsonNormalize = @import("chat_resp.zig").denoResponsesJsonNormalize;

pub fn jsonArrayFirst(value: std.json.Value) ?std.json.Value {
    return switch (value) {
        .array => |array| if (array.items.len > 0) array.items[0] else null,
        else => null,
    };
}

pub const normalizeResponsesArgumentsString = @import("chat_resp.zig").normalizeResponsesArgumentsString;

pub const normalizeResponsesEventData = @import("chat_resp.zig").normalizeResponsesEventData;

pub const appendNormalizedResponsesSseBlock = @import("chat_resp.zig").appendNormalizedResponsesSseBlock;

pub const denoResponsesSseNormalize = @import("chat_resp.zig").denoResponsesSseNormalize;

pub fn appendChatSseDataChunk(
    out: *std.array_list.Managed(u8),
    data: []const u8,
    splitter: *ThoughtStreamSplitter,
    reasoning_started: *bool,
    reasoning_done: *bool,
    reasoning_output_index: *u64,
    reasoning_text: *std.array_list.Managed(u8),
    message_started: *bool,
    message_output_index: *u64,
    next_output_index: *u64,
    message_text: *std.array_list.Managed(u8),
    tool_calls: *std.array_list.Managed(ChatToolCallState),
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
            var visible = std.array_list.Managed(u8).init(std.heap.page_allocator);
            defer visible.deinit();
            var thought = std.array_list.Managed(u8).init(std.heap.page_allocator);
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

pub const denoChatSseToResponses = @import("chat_resp.zig").denoChatSseToResponses;
