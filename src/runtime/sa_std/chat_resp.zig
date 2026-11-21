const std = @import("std");
pub const ChatToolCallState = @import("chat_norm.zig").ChatToolCallState;
pub const ThoughtStreamSplitter = @import("chat_norm.zig").ThoughtStreamSplitter;
pub const appendChatJsonMessageItem = @import("chat_norm.zig").appendChatJsonMessageItem;
pub const appendChatJsonReasoningItem = @import("chat_norm.zig").appendChatJsonReasoningItem;
pub const appendChatSseDataChunk = @import("chat_norm.zig").appendChatSseDataChunk;
pub const appendChatUsageJson = @import("chat_norm.zig").appendChatUsageJson;
pub const appendContinuationTool = @import("chat_norm.zig").appendContinuationTool;
pub const appendContinuationToolJson = @import("chat_norm.zig").appendContinuationToolJson;
pub const appendJsonString = @import("chat_norm.zig").appendJsonString;
pub const appendMergedReasoningText = @import("chat_norm.zig").appendMergedReasoningText;
pub const appendMessageDelta = @import("chat_norm.zig").appendMessageDelta;
pub const appendMessageDone = @import("chat_norm.zig").appendMessageDone;
pub const appendOutputComma = @import("chat_norm.zig").appendOutputComma;
pub const appendReasoningDelta = @import("chat_norm.zig").appendReasoningDelta;
pub const appendReasoningDone = @import("chat_norm.zig").appendReasoningDone;
pub const appendReasoningFields = @import("chat_norm.zig").appendReasoningFields;
pub const appendResponseCreated = @import("chat_norm.zig").appendResponseCreated;
pub const appendResponseDone = @import("chat_norm.zig").appendResponseDone;
pub const denormalizeMcpServerNameAlloc = @import("chat_norm.zig").denormalizeMcpServerNameAlloc;
pub const isProgressOnlyText = @import("chat_norm.zig").isProgressOnlyText;
pub const jsonArrayFirst = @import("chat_norm.zig").jsonArrayFirst;
pub const jsonObjectGetValue = @import("chat_norm.zig").jsonObjectGetValue;
pub const jsonStringValue = @import("chat_norm.zig").jsonStringValue;
pub const listWriter = @import("chat_norm.zig").listWriter;
pub const normalizeChatToolArguments = @import("chat_norm.zig").normalizeChatToolArguments;
pub const requestAllowsContinuation = @import("chat_norm.zig").requestAllowsContinuation;
pub const splitMcpNamespace = @import("chat_norm.zig").splitMcpNamespace;
pub const splitThoughtTextAlloc = @import("chat_norm.zig").splitThoughtTextAlloc;
pub const stringifyToList = @import("chat_norm.zig").stringifyToList;

pub fn appendNormalizedToolCall(out: *std.array_list.Managed(u8), req_body: []const u8, call: *const ChatToolCallState) !void {
    var normalized_namespace = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer normalized_namespace.deinit();
    var normalized_name = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer normalized_name.deinit();
    var normalized_args = std.array_list.Managed(u8).init(std.heap.page_allocator);
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

    const writer = listWriter(out);
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

pub fn appendNormalizedToolCallJson(out: *std.array_list.Managed(u8), req_body: []const u8, call: *const ChatToolCallState) !bool {
    var normalized_namespace = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer normalized_namespace.deinit();
    var normalized_name = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer normalized_name.deinit();
    var normalized_args = std.array_list.Managed(u8).init(std.heap.page_allocator);
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

    const writer = listWriter(out);
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

pub fn denoChatJsonToResponses(chat_body: []const u8, req_body: []const u8) ![]u8 {
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
    var visible = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer visible.deinit();
    var thought = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer thought.deinit();
    try splitter.consume(content, &visible, &thought);
    try splitter.flush(&visible, &thought);

    const trimmed_message_reasoning = std.mem.trim(u8, message_reasoning, " \t\r\n");
    const trimmed_thought = std.mem.trim(u8, thought.items, " \t\r\n");
    const trimmed_visible = std.mem.trim(u8, visible.items, " \t\r\n");

    var reasoning = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer reasoning.deinit();
    if (trimmed_message_reasoning.len != 0) try reasoning.appendSlice(trimmed_message_reasoning);
    if (trimmed_thought.len != 0 and !std.mem.eql(u8, trimmed_thought, trimmed_message_reasoning)) {
        if (reasoning.items.len != 0) try reasoning.append('\n');
        try reasoning.appendSlice(trimmed_thought);
    }

    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    const writer = listWriter(&out);
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
                        var item = std.array_list.Managed(u8).init(std.heap.page_allocator);
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

pub fn isNativeReasoningType(item_type: []const u8) bool {
    return std.mem.eql(u8, item_type, "reasoning") or
        std.mem.eql(u8, item_type, "thinking") or
        std.mem.eql(u8, item_type, "thought") or
        std.mem.eql(u8, item_type, "reason");
}

pub fn appendNativeReasoningItem(out: *std.array_list.Managed(u8), id: []const u8, text: []const u8) !void {
    const writer = listWriter(out);
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

pub fn appendNativeMessageItem(
    allocator: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
    item: std.json.Value,
    output_count: *usize,
    has_reasoning: *bool,
) !void {
    var item_reasoning = std.array_list.Managed(u8).init(allocator);
    defer item_reasoning.deinit();
    const reason_fields = [_][]const u8{ "reasoning", "reasoning_content", "thinking", "thought", "reason" };
    inline for (reason_fields) |field| {
        try appendMergedReasoningText(&item_reasoning, jsonStringValue(jsonObjectGetValue(item, field)));
    }

    var visible_content = std.array_list.Managed(u8).init(allocator);
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
                            try appendJsonString(listWriter(&visible_content), split.visible);
                            try visible_content.append('}');
                            content_count += 1;
                        }
                    } else {
                        if (content_count != 0) try visible_content.append(',');
                        try stringifyToList(&visible_content, part);
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
    const writer = listWriter(out);
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

pub fn appendNativeNormalizedOutput(
    allocator: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
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
                        var text = std.array_list.Managed(u8).init(allocator);
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
                    try stringifyToList(out, item);
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

pub fn nativeResponsesJsonNeedsNormalize(root: std.json.ObjectMap, output_text_reasoning: []const u8) bool {
    if (output_text_reasoning.len != 0) return true;
    const output = root.get("output") orelse return false;
    return switch (output) {
        .array => |array| {
            for (array.items) |item| {
                const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
                if (isNativeReasoningType(item_type)) return true;
                if (std.mem.eql(u8, item_type, "message")) {
                    const reason_fields = [_][]const u8{ "reasoning", "reasoning_content", "thinking", "thought", "reason" };
                    inline for (reason_fields) |field| {
                        if (std.mem.trim(u8, jsonStringValue(jsonObjectGetValue(item, field)), " \t\r\n").len != 0) return true;
                    }
                    if (jsonObjectGetValue(item, "content")) |content| {
                        switch (content) {
                            .array => |content_array| {
                                for (content_array.items) |part| {
                                    const part_type = jsonStringValue(jsonObjectGetValue(part, "type"));
                                    const text = jsonStringValue(jsonObjectGetValue(part, "text"));
                                    if (std.mem.eql(u8, part_type, "text")) return true;
                                    if (std.mem.eql(u8, part_type, "output_text") and
                                        (std.mem.indexOf(u8, text, "<thought>") != null or
                                            std.mem.indexOf(u8, text, "</thought>") != null))
                                    {
                                        return true;
                                    }
                                }
                            },
                            else => {},
                        }
                    }
                }
            }
            return false;
        },
        else => false,
    };
}

pub fn denoResponsesJsonNormalize(body: []const u8) ![]u8 {
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
    if (!nativeResponsesJsonNeedsNormalize(root, output_text_split.reasoning)) {
        return std.heap.page_allocator.dupe(u8, body);
    }

    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    try out.append('{');
    var field_count: usize = 0;
    var it = root.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, "output") or std.mem.eql(u8, entry.key_ptr.*, "output_text")) continue;
        if (field_count != 0) try out.append(',');
        try appendJsonString(listWriter(&out), entry.key_ptr.*);
        try out.append(':');
        try stringifyToList(&out, entry.value_ptr.*);
        field_count += 1;
    }
    if (field_count != 0) try out.append(',');
    try appendNativeNormalizedOutput(std.heap.page_allocator, &out, root.get("output"), output_text_split.reasoning);
    try out.appendSlice(",\"output_text\":");
    try appendJsonString(listWriter(&out), output_text_split.visible);
    try out.append('}');
    return try out.toOwnedSlice();
}

pub fn normalizeResponsesArgumentsString(allocator: std.mem.Allocator, arguments: []const u8) !?[]u8 {
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
    return try std.json.Stringify.valueAlloc(allocator, args_value, .{});
}

pub fn normalizeResponsesEventData(allocator: std.mem.Allocator, data: []const u8) !?[]u8 {
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
        var text = std.array_list.Managed(u8).init(allocator);
        defer text.deinit();
        try appendReasoningFields(item_ptr.*, &text);
        if (text.items.len != 0) {
            var out = std.array_list.Managed(u8).init(allocator);
            errdefer out.deinit();
            const writer = listWriter(&out);
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
        try item.put(allocator, "name", .{ .string = try allocator.dupe(u8, split.tool) });
        try item.put(allocator, "namespace", .{ .string = try allocator.dupe(u8, split.namespace) });
        try item.put(allocator, "output_kind", .{ .string = "function_call_output" });
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
    return try std.json.Stringify.valueAlloc(allocator, value, .{});
}

pub fn appendNormalizedResponsesSseBlock(out: *std.array_list.Managed(u8), event_line: ?[]const u8, data: []const u8) !void {
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

pub fn denoResponsesSseNormalize(sse_body: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    var data_buffer = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer data_buffer.deinit();
    var event_line: ?[]const u8 = null;

    var line_it = std.mem.splitScalar(u8, sse_body, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
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
            const data = std.mem.trimStart(u8, line[5..], " \t");
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

pub fn denoChatSseToResponses(chat_body: []const u8, req_body: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    var splitter = ThoughtStreamSplitter.init(std.heap.page_allocator);
    defer splitter.deinit();
    var reasoning_text = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer reasoning_text.deinit();
    var message_text = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer message_text.deinit();
    var reasoning_started = false;
    var reasoning_done = false;
    var reasoning_output_index: u64 = 0;
    var message_started = false;
    var message_output_index: u64 = 0;
    var next_output_index: u64 = 0;
    var saw_stop_without_tool = false;
    var tool_calls = std.array_list.Managed(ChatToolCallState).init(std.heap.page_allocator);
    defer {
        for (tool_calls.items) |*call| call.deinit();
        tool_calls.deinit();
    }
    var data_buffer = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer data_buffer.deinit();

    try appendResponseCreated(&out);

    var line_it = std.mem.splitScalar(u8, chat_body, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (std.mem.startsWith(u8, line, "data:")) {
            const data = std.mem.trimStart(u8, line[5..], " \t");
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

    var tail_visible = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer tail_visible.deinit();
    var tail_reasoning = std.array_list.Managed(u8).init(std.heap.page_allocator);
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
