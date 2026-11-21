const std = @import("std");
const appendJsonString = @import("../sa_std.zig").appendJsonString;
const jsonObjectGetValue = @import("../sa_std.zig").jsonObjectGetValue;
const jsonStringValue = @import("../sa_std.zig").jsonStringValue;
const listWriter = @import("../sa_std.zig").listWriter;
const stringifyToList = @import("../sa_std.zig").stringifyToList;

fn jsonBoolValue(value: ?std.json.Value, default_value: bool) bool {
    const actual = value orelse return default_value;
    return switch (actual) {
        .bool => |inner| inner,
        else => default_value,
    };
}

fn appendJsonFieldName(out: *std.array_list.Managed(u8), field_count: *usize, name: []const u8) !void {
    if (field_count.* != 0) try out.append(',');
    try appendJsonString(listWriter(out), name);
    try out.append(':');
    field_count.* += 1;
}

fn appendSystemText(system_texts: *std.array_list.Managed(u8), text: []const u8) !void {
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
            var out = std.array_list.Managed(u8).init(allocator);
            errdefer out.deinit();
            for (array.items) |part| {
                try out.appendSlice(jsonStringValue(jsonObjectGetValue(part, "text")));
            }
            return try out.toOwnedSlice();
        },
        else => return null,
    }
}

fn appendMappedResponseContentPart(out: *std.array_list.Managed(u8), part: std.json.Value) !void {
    const writer = listWriter(out);
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
            .object => try stringifyToList(writer.list, image_url),
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
    try stringifyToList(writer.list, part);
}

fn appendResponseContentAsChat(
    allocator: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
    content: std.json.Value,
) !bool {
    if (try responseContentTextOnlyAlloc(allocator, content)) |text| {
        try appendJsonString(listWriter(out), text);
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
            var out = std.array_list.Managed(u8).init(allocator);
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

fn appendChatMessagePrefix(out: *std.array_list.Managed(u8), message_count: *usize, role: []const u8) !void {
    if (message_count.* != 0) try out.append(',');
    try out.appendSlice("{\"role\":");
    try appendJsonString(listWriter(out), role);
    try out.appendSlice(",\"content\":");
    message_count.* += 1;
}

fn appendResponseMessageAsChat(
    allocator: std.mem.Allocator,
    messages: *std.array_list.Managed(u8),
    message_count: *usize,
    system_texts: *std.array_list.Managed(u8),
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

    var content_buf = std.array_list.Managed(u8).init(allocator);
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
    messages: *std.array_list.Managed(u8),
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
            try appendJsonString(listWriter(messages), call_id);
        } else {
            try listWriter(messages).print("\"call_{}\"", .{index.*});
        }
        try messages.appendSlice(",\"type\":\"function\",\"function\":{\"name\":");
        try appendJsonString(listWriter(messages), chat_name);
        try messages.appendSlice(",\"arguments\":");
        try appendJsonString(listWriter(messages), if (arguments.len != 0) arguments else "{}");
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
    messages: *std.array_list.Managed(u8),
    message_count: *usize,
    call_names: *const std.StringHashMap([]const u8),
    item: std.json.Value,
) !void {
    const item_type = jsonStringValue(jsonObjectGetValue(item, "type"));
    if (!isResponsesToolOutputType(item_type)) return;
    var output_text = jsonStringValue(jsonObjectGetValue(item, "output"));
    if (output_text.len == 0) {
        if (jsonObjectGetValue(item, "output")) |output| {
            const owned_output = try std.json.Stringify.valueAlloc(allocator, output, .{});
            output_text = owned_output;
        } else {
            output_text = jsonStringValue(jsonObjectGetValue(item, "content"));
        }
    }
    if (output_text.len == 0) return;
    try appendChatMessagePrefix(messages, message_count, "tool");
    try appendJsonString(listWriter(messages), output_text);
    const call_id = jsonStringValue(jsonObjectGetValue(item, "call_id"));
    if (call_id.len != 0) {
        try messages.appendSlice(",\"tool_call_id\":");
        try appendJsonString(listWriter(messages), call_id);
    }
    const explicit_name = std.mem.trim(u8, jsonStringValue(jsonObjectGetValue(item, "name")), " \t\r\n");
    const name = if (explicit_name.len != 0) explicit_name else blk: {
        if (call_id.len == 0) break :blk "";
        break :blk call_names.get(call_id) orelse "";
    };
    if (name.len != 0) {
        try messages.appendSlice(",\"name\":");
        try appendJsonString(listWriter(messages), name);
    }
    try messages.append('}');
}

fn appendNormalizedChatTool(
    out: *std.array_list.Managed(u8),
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
        var prefixed = std.array_list.Managed(u8).init(std.heap.page_allocator);
        defer prefixed.deinit();
        try prefixed.appendSlice(namespace_prefix);
        try prefixed.appendSlice(raw_name);
        try appendJsonString(listWriter(out), prefixed.items);
    } else {
        try appendJsonString(listWriter(out), raw_name);
    }

    const description = blk: {
        const fn_desc = jsonStringValue(jsonObjectGetValue(source, "description"));
        if (fn_desc.len != 0) break :blk fn_desc;
        break :blk jsonStringValue(jsonObjectGetValue(tool, "description"));
    };
    if (description.len != 0) {
        try out.appendSlice(",\"description\":");
        try appendJsonString(listWriter(out), description);
    }
    if (jsonObjectGetValue(source, "parameters")) |parameters| {
        try out.appendSlice(",\"parameters\":");
        try stringifyToList(out, parameters);
    } else if (jsonObjectGetValue(tool, "parameters")) |parameters| {
        try out.appendSlice(",\"parameters\":");
        try stringifyToList(out, parameters);
    }
    const has_strict = jsonObjectGetValue(source, "strict") != null or jsonObjectGetValue(tool, "strict") != null;
    if (has_strict) {
        try out.appendSlice(",\"strict\":");
        try out.appendSlice(if (jsonBoolValue(jsonObjectGetValue(source, "strict"), jsonBoolValue(jsonObjectGetValue(tool, "strict"), false))) "true" else "false");
    }
    try out.appendSlice("}}");
    tool_count.* += 1;
}

fn appendNormalizedChatToolsField(out: *std.array_list.Managed(u8), field_count: *usize, tools: std.json.Value) !void {
    const array = switch (tools) {
        .array => |items| items,
        else => return,
    };
    var tools_json = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer tools_json.deinit();
    var tool_count: usize = 0;
    for (array.items) |tool| try appendNormalizedChatTool(&tools_json, tool, "", &tool_count);
    if (tool_count == 0) return;
    try appendJsonFieldName(out, field_count, "tools");
    try out.append('[');
    try out.appendSlice(tools_json.items);
    try out.append(']');
}

fn appendResponseFormatFromText(out: *std.array_list.Managed(u8), field_count: *usize, text_value: ?std.json.Value) !void {
    const text = text_value orelse return;
    const format = jsonObjectGetValue(text, "format") orelse return;
    const format_type = jsonStringValue(jsonObjectGetValue(format, "type"));
    if (format_type.len == 0) return;
    try appendJsonFieldName(out, field_count, "response_format");
    if (std.mem.eql(u8, format_type, "json_schema")) {
        try out.appendSlice("{\"type\":\"json_schema\",\"json_schema\":{\"name\":");
        const name = jsonStringValue(jsonObjectGetValue(format, "name"));
        try appendJsonString(listWriter(out), if (name.len != 0) name else "codex_output_schema");
        if (jsonObjectGetValue(format, "schema")) |schema| {
            try out.appendSlice(",\"schema\":");
            try stringifyToList(out, schema);
        }
        try out.appendSlice(",\"strict\":");
        try out.appendSlice(if (jsonBoolValue(jsonObjectGetValue(format, "strict"), false)) "true" else "false");
        try out.appendSlice("}}");
        return;
    }
    try stringifyToList(out, format);
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

pub fn denoResponsesChatFallbackRequest(body: []const u8, default_model: []const u8, plan_mode_like: bool) !?[]u8 {
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

    var system_texts = std.array_list.Managed(u8).init(allocator);
    var messages = std.array_list.Managed(u8).init(allocator);
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
            try appendJsonString(listWriter(&messages), top_text);
            try messages.append('}');
        }
    }
    if (system_texts.items.len != 0) {
        var with_system = std.array_list.Managed(u8).init(allocator);
        var system_count: usize = 0;
        try appendChatMessagePrefix(&with_system, &system_count, "system");
        try appendJsonString(listWriter(&with_system), system_texts.items);
        try with_system.append('}');
        if (messages.items.len != 0) try with_system.append(',');
        try with_system.appendSlice(messages.items);
        messages = with_system;
        message_count += 1;
    }
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    try out.append('{');
    var field_count: usize = 0;
    var it = root.iterator();
    while (it.next()) |entry| {
        if (shouldSkipResponsesFallbackField(entry.key_ptr.*)) continue;
        try appendJsonFieldName(&out, &field_count, entry.key_ptr.*);
        try stringifyToList(&out, entry.value_ptr.*);
    }
    try appendResponseFormatFromText(&out, &field_count, root.get("text"));
    try appendJsonFieldName(&out, &field_count, "model");
    try appendJsonString(listWriter(&out), model);
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
