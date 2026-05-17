// SAX Lowerer: Component/state/DOM → SA 指令序列
// 将高层 SAX 结构降级为合法的 .saasm 指令流

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SaxLowerer = struct {
    allocator: Allocator,
    component_name: []const u8,
    state_vars: std.StringHashMap(usize), // var_name → memory offset
    state_size: usize = 0,
    dom_nodes: std.StringHashMap(usize), // node_id → handle
    next_handle: usize = 0,

    pub fn init(allocator: Allocator, component_name: []const u8) SaxLowerer {
        return .{
            .allocator = allocator,
            .component_name = component_name,
            .state_vars = std.StringHashMap(usize).init(allocator),
            .dom_nodes = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *SaxLowerer) void {
        self.state_vars.deinit();
        self.dom_nodes.deinit();
    }

    /// 为状态变量分配内存槽
    pub fn allocateStateVar(self: *SaxLowerer, var_name: []const u8, size: usize) !void {
        const offset = self.state_size;
        try self.state_vars.put(var_name, offset);
        self.state_size += size;
    }

    /// 生成初始化函数（组件挂载）
    pub fn generateInit(self: *SaxLowerer, output: *std.ArrayList(u8)) !void {
        try output.writer().print(
            "// === SAX Component: {s} ===\n",
            .{self.component_name},
        );

        try output.writer().print(
            "@export sax_{s}_init():\nL_ENTRY:\n",
            .{self.component_name},
        );

        // 分配状态内存
        if (self.state_size > 0) {
            try output.writer().print(
                "  state = alloc {}\n",
                .{self.state_size},
            );
        }

        // 初始化状态变量（这里简化，Phase 2 完善）
        try output.writer().writeAll("  ret\n\n");
    }

    /// 生成渲染函数
    pub fn generateRender(self: *SaxLowerer, output: *std.ArrayList(u8)) !void {
        try output.writer().print(
            "@export sax_{s}_render():\nL_ENTRY:\n",
            .{self.component_name},
        );

        // 遍历所有 DOM 节点，更新绑定了状态的节点
        // Phase 2 实现细粒度响应式
        try output.writer().writeAll("  ret\n\n");
    }

    /// 生成销毁函数
    pub fn generateDestroy(self: *SaxLowerer, output: *std.ArrayList(u8)) !void {
        try output.writer().print(
            "@export sax_{s}_destroy():\nL_ENTRY:\n",
            .{self.component_name},
        );

        // 释放所有状态变量
        var iter = self.state_vars.keyIterator();
        while (iter.next()) |var_name| {
            try output.writer().print("  !{s}\n", .{var_name.*});
        }

        try output.writer().writeAll("  ret\n\n");
    }

    /// 为 DOM 节点分配句柄
    pub fn allocateDOMNode(self: *SaxLowerer, node_id: []const u8) !usize {
        const handle = self.next_handle;
        self.next_handle += 1;
        try self.dom_nodes.put(node_id, handle);
        return handle;
    }

    /// 生成 DOM 查询指令
    pub fn generateDOMQuery(
        self: *SaxLowerer,
        output: *std.ArrayList(u8),
        selector: []const u8,
        node_id: []const u8,
    ) !void {
        const handle = try self.allocateDOMNode(node_id);
        try output.writer().print(
            "  node_{} = call @sax_dom_query(utf8:\"{}\", {})\n",
            .{ handle, selector, selector.len },
        );
    }

    /// 生成事件绑定指令
    pub fn generateEventBinding(
        self: *SaxLowerer,
        output: *std.ArrayList(u8),
        node_id: []const u8,
        event_name: []const u8,
        handler_name: []const u8,
    ) !void {
        const handle = self.dom_nodes.get(node_id) orelse return error.UnknownNode;
        try output.writer().print(
            "  call @sax_dom_bind_event(node_{}, utf8:\"{}\", {}, ^sax_{s}_{s})\n",
            .{ handle, event_name, event_name.len, self.component_name, handler_name },
        );
    }

    /// 生成文本插值更新指令
    pub fn generateTextUpdate(
        self: *SaxLowerer,
        output: *std.ArrayList(u8),
        node_id: []const u8,
        state_var: []const u8,
    ) !void {
        const handle = self.dom_nodes.get(node_id) orelse return error.UnknownNode;
        const offset = self.state_vars.get(state_var) orelse return error.UnknownStateVar;

        try output.writer().print(
            "  val = load state+{} as i64\n",
            .{offset},
        );
        try output.writer().print(
            "  call @sax_dom_set_text(node_{}, &val, 8)\n",
            .{handle},
        );
    }
};
