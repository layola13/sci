const std = @import("std");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;

pub const LowerError = error{
    OutOfMemory,
    UnknownNode,
    UnknownStateVar,
    UnknownHandler,
    InvalidInterpolation,
    InvalidTextExpression,
};

pub const LowerOptions = struct {
    emit_shared_decls: bool = true,
    emit_app_alias: bool = false,
};

const StringPool = struct {
    allocator: Allocator,
    items: std.ArrayList([]const u8),

    fn init(allocator: Allocator) StringPool {
        return .{
            .allocator = allocator,
            .items = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *StringPool) void {
        for (self.items.items) |item| self.allocator.free(item);
        self.items.deinit();
        self.* = undefined;
    }

    fn add(self: *StringPool, text: []const u8) !usize {
        try self.items.append(try self.allocator.dupe(u8, text));
        return self.items.items.len - 1;
    }
};

const StateSlot = struct {
    offset: usize,
    size: usize,
};

const NodeSlots = struct {
    tag_const: usize,
    handle_slot: usize,
    text_slot: ?usize,
};

pub const SaxLowerer = struct {
    allocator: Allocator,
    component: parser.Component,
    state_slots: []StateSlot,
    state_size: usize,
    node_slots: []NodeSlots,
    string_pool: StringPool,
    event_handlers: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator, component: parser.Component) !SaxLowerer {
        var pool = StringPool.init(allocator);
        errdefer pool.deinit();

        const state_slots = try allocator.alloc(StateSlot, component.state_vars.len);
        errdefer allocator.free(state_slots);
        var state_size: usize = 0;
        for (component.state_vars, 0..) |sv, idx| {
            const size = stateVarSize(sv.ty);
            state_slots[idx] = .{ .offset = state_size, .size = size };
            state_size += size;
        }

        const node_slots = try allocator.alloc(NodeSlots, component.dom_nodes.len);
        errdefer allocator.free(node_slots);
        for (component.dom_nodes, 0..) |node, idx| {
            const tag_const = try pool.add(node.tag);
            node_slots[idx] = .{
                .tag_const = tag_const,
                .handle_slot = idx,
                .text_slot = null,
            };
        }

        var event_handlers = std.StringHashMap([]const u8).init(allocator);
        errdefer event_handlers.deinit();
        for (component.handlers) |handler| {
            try event_handlers.put(handler.name, handler.body);
        }

        return .{
            .allocator = allocator,
            .component = component,
            .state_slots = state_slots,
            .state_size = state_size,
            .node_slots = node_slots,
            .string_pool = pool,
            .event_handlers = event_handlers,
        };
    }

    pub fn deinit(self: *SaxLowerer) void {
        self.event_handlers.deinit();
        self.string_pool.deinit();
        self.allocator.free(self.node_slots);
        self.allocator.free(self.state_slots);
        self.* = undefined;
    }

    fn stateVarIndex(self: *const SaxLowerer, name: []const u8) ?usize {
        for (self.component.state_vars, 0..) |sv, idx| {
            if (std.mem.eql(u8, sv.name, name)) return idx;
        }
        return null;
    }

    fn stateSlot(self: *const SaxLowerer, name: []const u8) !StateSlot {
        const idx = self.stateVarIndex(name) orelse return LowerError.UnknownStateVar;
        return self.state_slots[idx];
    }

    fn nodeIndex(self: *const SaxLowerer, alias: []const u8) ?usize {
        for (self.component.dom_nodes, 0..) |node, idx| {
            if (std.mem.eql(u8, node.alias, alias)) return idx;
        }
        return null;
    }

    fn escapeText(allocator: Allocator, text: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();
        for (text) |c| {
            switch (c) {
                '\\' => try out.appendSlice("\\\\"),
                '"' => try out.appendSlice("\\\""),
                '\n' => try out.appendSlice("\\n"),
                '\r' => try out.appendSlice("\\r"),
                '\t' => try out.appendSlice("\\t"),
                else => try out.append(c),
            }
        }
        return try out.toOwnedSlice();
    }

    fn stringConstName(component_name: []const u8, kind: []const u8, index: usize) ![]const u8 {
        return try std.fmt.allocPrint(std.heap.page_allocator, "sax_{s}_{s}_{d}", .{ component_name, kind, index });
    }

    fn stateVarSize(ty: parser.StateType) usize {
        return switch (ty) {
            .i1, .i32, .i64, .f64, .ptr => 8,
        };
    }

    fn stateTypeName(ty: parser.StateType) []const u8 {
        return switch (ty) {
            .i1 => "i1",
            .i32 => "i32",
            .i64 => "i64",
            .f64 => "f64",
            .ptr => "ptr",
        };
    }

    fn stateSlotConstName(self: *const SaxLowerer, state_name: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_{s}_slot", .{ self.component.name, state_name });
    }

    fn stateSizeConstName(self: *const SaxLowerer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_STATE_SIZE", .{self.component.name});
    }

    fn domSizeConstName(self: *const SaxLowerer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_DOM_SIZE", .{self.component.name});
    }

    fn stateSlotExpr(self: *const SaxLowerer, name: []const u8) ![]const u8 {
        return try self.stateSlotConstName(name);
    }

    fn stateAllocSize(self: *const SaxLowerer) usize {
        return @max(self.state_size, 8);
    }

    fn domAllocSize(self: *const SaxLowerer) usize {
        const bytes = self.node_slots.len * 8;
        return @max(bytes, 8);
    }

    fn nodeTextBufferSize(self: *const SaxLowerer, node: parser.DomNode) usize {
        _ = self;
        var size: usize = 1;
        for (node.children) |child| {
            switch (child) {
                .text => |piece| switch (piece) {
                    .text => |txt| size += txt.len,
                    .interpolation => size += 64,
                },
                else => {},
            }
        }
        return size;
    }

    fn stateValueExpr(self: *const SaxLowerer, var_name: []const u8) ![]const u8 {
        const slot = try self.stateSlot(var_name);
        return try std.fmt.allocPrint(self.allocator, "state+{}", .{slot.offset});
    }

    fn appendConstDecls(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        for (self.string_pool.items.items, 0..) |text, idx| {
            const escaped = try escapeText(self.allocator, text);
            defer self.allocator.free(escaped);
            try out.writer().print("@sax_{s}_{d} = private unnamed_addr constant [{d} x i8] c\"{s}\"\n", .{
                self.component.name,
                idx,
                text.len,
                escaped,
            });
        }
        if (self.string_pool.items.items.len != 0) try out.appendByte('\n');
    }

    fn appendExternDecls(_: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        const decls = [_][]const u8{
            "@extern sax_dom_create(*tag_ptr: ptr, tag_len: i64) -> i64",
            "@extern sax_dom_append_child(parent_h: i64, child_h: i64) -> void",
            "@extern sax_dom_set_text(node_h: i64, *text_ptr: ptr, text_len: i64) -> void",
            "@extern sax_dom_set_attr(node_h: i64, *key_ptr: ptr, key_len: i64, *val_ptr: ptr, val_len: i64) -> void",
            "@extern sax_dom_add_class(node_h: i64, *cls_ptr: ptr, cls_len: i64) -> void",
            "@extern sax_dom_bind_event(node_h: i64, *evt_ptr: ptr, evt_len: i64, handler_export_idx: i64) -> void",
            "@extern sax_dom_remove_self(node_h: i64) -> void",
            "@extern sax_dom_get_value(node_h: i64, *buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_get_time() -> i64",
            "@extern sax_itoa(value: i64, *buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_mem_copy(*dst_ptr: ptr, *src_ptr: ptr, len: i64) -> void",
        };
        for (decls) |decl| try out.writer().print("{s}\n", .{decl});
        try out.appendByte('\n');
    }

    fn emitLoadState(self: *const SaxLowerer, out: *std.ArrayList(u8), dest: []const u8, name: []const u8) !void {
        const slot = try self.stateSlot(name);
        try out.writer().print("  {s} = load state+{} as {}\n", .{ dest, slot.offset, stateTypeName(self.component.state_vars[self.stateVarIndex(name).?].ty) });
    }

    fn emitStoreState(self: *const SaxLowerer, out: *std.ArrayList(u8), name: []const u8, value: []const u8, ty: parser.StateType) !void {
        const slot = try self.stateSlot(name);
        try out.writer().print("  store state+{}, {s} as {}\n", .{ slot.offset, value, stateTypeName(ty) });
    }

    fn emitStringSliceCopy(self: *const SaxLowerer, out: *std.ArrayList(u8), dst_ptr: []const u8, src_const_idx: usize) !void {
        const const_name = try std.fmt.allocPrint(self.allocator, "@sax_{s}_{d}", .{ self.component.name, src_const_idx });
        defer self.allocator.free(const_name);
        try out.writer().print("  call @sax_mem_copy({s}, {s}, {})\n", .{ dst_ptr, const_name, self.string_pool.items.items[src_const_idx].len });
    }

    fn emitTextValue(
        self: *const SaxLowerer,
        out: *std.ArrayList(u8),
        node_name: []const u8,
        value_expr: []const u8,
        is_attr: bool,
        attr_key_idx: ?usize,
    ) !void {
        const key = if (is_attr) try std.fmt.allocPrint(self.allocator, "@sax_{s}_{d}", .{ self.component.name, attr_key_idx.? }) else "";
        defer if (is_attr) self.allocator.free(key);

        const buf_name = try std.fmt.allocPrint(self.allocator, "tmp_buf_{s}", .{node_name});
        defer self.allocator.free(buf_name);
        try out.writer().print("  {s} = stack_alloc 64\n", .{buf_name});
        try out.writer().print("  tmp_len_{s} = call @sax_itoa({s}, &{s}, 64)\n", .{ node_name, value_expr, buf_name });
        if (is_attr) {
            try out.writer().print("  call @sax_dom_set_attr({s}, {s}, {}, &{s}, tmp_len_{s})\n", .{ node_name, key, self.string_pool.items.items[attr_key_idx.?].len, buf_name, node_name });
        } else {
            try out.writer().print("  call @sax_dom_set_text({s}, &{s}, tmp_len_{s})\n", .{ node_name, buf_name, node_name });
        }
    }

    fn emitNodeInit(self: *const SaxLowerer, out: *std.ArrayList(u8), idx: usize) !void {
        const node = self.component.dom_nodes[idx];
        const slot = self.node_slots[idx];
        const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
        defer self.allocator.free(node_var);

        const tag_const = try std.fmt.allocPrint(self.allocator, "@sax_{s}_{d}", .{ self.component.name, slot.tag_const });
        defer self.allocator.free(tag_const);
        try out.writer().print("  {s} = call @sax_dom_create({s}, {})\n", .{ node_var, tag_const, self.string_pool.items.items[slot.tag_const].len });
        try out.writer().print("  store dom+{}, {s} as i64\n", .{ slot.handle_slot * 8, node_var });

        for (node.attrs) |attr| {
            if (attr.is_event) {
                const handler_name = attr.event_handler orelse return LowerError.UnknownHandler;
                if (self.event_handlers.get(handler_name) == null) return LowerError.UnknownHandler;
                const evt_idx = try self.string_pool.add(attr.name);
                const evt_const = try std.fmt.allocPrint(self.allocator, "@sax_{s}_{d}", .{ self.component.name, evt_idx });
                defer self.allocator.free(evt_const);
                const handler_export_idx = try std.fmt.allocPrint(self.allocator, "sax_{s}_{s}", .{ self.component.name, handler_name });
                defer self.allocator.free(handler_export_idx);
                try out.writer().print("  call @sax_dom_bind_event({s}, {s}, {}, @{s})\n", .{ node_var, evt_const, attr.name.len, handler_export_idx });
                continue;
            }

            switch (attr.value) {
                .literal => |lit| {
                    const key_idx = try self.string_pool.add(attr.name);
                    const val_idx = try self.string_pool.add(lit);
                    const key_const = try std.fmt.allocPrint(self.allocator, "@sax_{s}_{d}", .{ self.component.name, key_idx });
                    defer self.allocator.free(key_const);
                    const val_const = try std.fmt.allocPrint(self.allocator, "@sax_{s}_{d}", .{ self.component.name, val_idx });
                    defer self.allocator.free(val_const);
                    try out.writer().print("  call @sax_dom_set_attr({s}, {s}, {}, {s}, {})\n", .{
                        node_var,
                        key_const,
                        attr.name.len,
                        val_const,
                        lit.len,
                    });
                },
                .interpolation => |expr| {
                    try self.emitInterpolatedValue(out, node_var, attr.name, expr, true);
                },
            }
        }

        if (node.self_closing) return;

        var text_idx: usize = 0;
        for (node.children) |child| {
            switch (child) {
                .node_index => |child_idx| {
                    const child_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{child_idx});
                    defer self.allocator.free(child_var);
                    try out.writer().print("  call @sax_dom_append_child({s}, {s})\n", .{ node_var, child_var });
                },
                .text => |piece| {
                    switch (piece) {
                        .text => |txt| {
                            const text_idx_added = try self.string_pool.add(txt);
                            const text_const = try std.fmt.allocPrint(self.allocator, "@sax_{s}_{d}", .{ self.component.name, text_idx_added });
                            defer self.allocator.free(text_const);
                            const tmp_buf = try std.fmt.allocPrint(self.allocator, "tmp_text_{d}", .{text_idx});
                            defer self.allocator.free(tmp_buf);
                            try out.writer().print("  {s} = stack_alloc {}\n", .{ tmp_buf, txt.len + 8 });
                            try out.writer().print("  call @sax_mem_copy(&{s}, {s}, {})\n", .{ tmp_buf, text_const, txt.len });
                            try out.writer().print("  call @sax_dom_set_text({s}, &{s}, {})\n", .{ node_var, tmp_buf, txt.len });
                        },
                        .interpolation => |expr| {
                            try self.emitInterpolatedValue(out, node_var, node.tag, expr, false);
                        },
                    }
                    text_idx += 1;
                },
            }
        }
    }

    fn emitInterpolatedValue(self: *const SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, key_name: []const u8, expr: []const u8, is_attr: bool) !void {
        if (std.mem.indexOfAny(u8, expr, "^!") != null) return LowerError.InvalidInterpolation;
        const trimmed = std.mem.trim(u8, expr, " \t\r");
        if (trimmed.len == 0) return LowerError.InvalidTextExpression;

        const state_name = trimmed;
        const slot = try self.stateSlot(state_name);
        const ty = self.component.state_vars[self.stateVarIndex(state_name).?].ty;
        const tmp_val = try std.fmt.allocPrint(self.allocator, "interp_{d}", .{slot.offset});
        defer self.allocator.free(tmp_val);

        try out.writer().print("  {s} = load state+{} as {}\n", .{ tmp_val, slot.offset, stateTypeName(ty) });

        const buf_name = try std.fmt.allocPrint(self.allocator, "interp_buf_{d}", .{slot.offset});
        defer self.allocator.free(buf_name);
        try out.writer().print("  {s} = stack_alloc 64\n", .{buf_name});
        try out.writer().print("  interp_len_{d} = call @sax_itoa({s}, &{s}, 64)\n", .{ slot.offset, tmp_val, buf_name });
        if (is_attr) {
            const key_idx = try self.string_pool.add(key_name);
            const key_const = try std.fmt.allocPrint(self.allocator, "@sax_{s}_{d}", .{ self.component.name, key_idx });
            defer self.allocator.free(key_const);
            try out.writer().print("  call @sax_dom_set_attr({s}, {s}, {}, &{s}, interp_len_{d})\n", .{
                node_var,
                key_const,
                key_name.len,
                buf_name,
                slot.offset,
            });
        } else {
            try out.writer().print("  call @sax_dom_set_text({s}, &{s}, interp_len_{d})\n", .{
                node_var,
                buf_name,
                slot.offset,
            });
        }
    }

    fn emitHandler(self: *const SaxLowerer, out: *std.ArrayList(u8), handler: parser.Handler) !void {
        const body = handler.body;
        try out.writer().print("@export sax_{s}_{s}():\n", .{ self.component.name, handler.name });
        var lines = std.mem.splitScalar(u8, body, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trimRight(u8, line, "\r");
            if (trimmed.len == 0) continue;
            if (std.mem.containsAtLeast(u8, trimmed, 1, "call @render()")) {
                try out.writer().print("  call @sax_{s}_render()\n", .{self.component.name});
                continue;
            }
            try out.writer().print("{s}\n", .{trimmed});
        }
        try out.appendByte('\n');
    }

    fn emitInit(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        try out.writer().print("@export sax_{s}_init():\nL_ENTRY:\n", .{self.component.name});
        if (self.state_size > 0) {
            try out.writer().print("  state = alloc {}\n", .{self.state_size});
        }
        for (self.component.state_vars, 0..) |sv, idx| {
            const slot = self.state_slots[idx];
            switch (sv.ty) {
                .ptr => {
                    const init_expr = std.mem.trim(u8, sv.init_expr, " \t\r");
                    if (std.mem.startsWith(u8, init_expr, "alloc ")) {
                        const sz = std.mem.trim(u8, init_expr["alloc ".len..], " \t\r");
                        try out.writer().print("  tmp_ptr_{d} = stack_alloc {}\n", .{ idx, sz });
                        try out.writer().print("  store state+{}, tmp_ptr_{d} as ptr\n", .{ slot.offset, idx });
                    } else {
                        try out.writer().print("  store state+{}, 0 as ptr\n", .{slot.offset});
                    }
                },
                else => {
                    try out.writer().print("  store state+{}, {} as {}\n", .{ slot.offset, sv.init_expr, stateTypeName(sv.ty) });
                },
            }
        }

        for (self.component.dom_nodes, 0..) |_, idx| {
            try self.emitNodeInit(out, idx);
        }
        try out.writer().print("  call @sax_{s}_render()\n", .{self.component.name});
        try out.writeAll("  return\n\n");
    }

    fn emitRender(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        try out.writer().print("@export sax_{s}_render():\nL_ENTRY:\n", .{self.component.name});
        for (self.component.dom_nodes, 0..) |node, idx| {
            const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
            defer self.allocator.free(node_var);
            if (node.text_index) |text_idx| {
                const child = node.children[text_idx];
                switch (child) {
                    .text => |piece| switch (piece) {
                        .interpolation => |expr| try self.emitInterpolatedValue(out, node_var, node.tag, expr, false),
                        .text => {},
                    },
                    else => {},
                }
            }
        }
        try out.writeAll("  return\n\n");
    }

    fn emitDestroy(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        try out.writer().print("@export sax_{s}_destroy():\nL_ENTRY:\n", .{self.component.name});
        for (self.component.state_vars) |sv| {
            try out.writer().print("  !{s}\n", .{sv.name});
        }
        for (self.component.dom_nodes, 0..) |_, idx| {
            const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
            defer self.allocator.free(node_var);
            try out.writer().print("  call @sax_dom_remove_self({s})\n", .{node_var});
        }
        try out.writeAll("  return\n\n");
    }

    pub fn lower(self: *const SaxLowerer, out: *std.ArrayList(u8), options: LowerOptions) !void {
        _ = options;
        try self.appendConstDecls(out);
        try self.appendExternDecls(out);
        try self.emitInit(out);
        try self.emitRender(out);
        for (self.component.handlers) |handler| {
            try self.emitHandler(out, handler);
        }
        try self.emitDestroy(out);
    }
};
