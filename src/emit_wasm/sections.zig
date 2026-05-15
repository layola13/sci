const std = @import("std");

const wasm = std.wasm;

const encoder = struct {
    fn writeUleb128(writer: anytype, value: anytype) !void {
        try std.leb.writeUleb128(writer, value);
    }

    fn writeIleb128(writer: anytype, value: anytype) !void {
        try std.leb.writeIleb128(writer, value);
    }
};

pub const SectionId = enum(u8) {
    custom = 0,
    type = 1,
    import = 2,
    function = 3,
    table = 4,
    memory = 5,
    global = 6,
    @"export" = 7,
    start = 8,
    element = 9,
    code = 10,
    data = 11,
    data_count = 12,
    _,
};

pub const Valtype = wasm.Valtype;
pub const ExternalKind = wasm.ExternalKind;
pub const MemoryType = wasm.Memory;
pub const InitExpression = wasm.InitExpression;

pub const FunctionType = struct {
    params: []const Valtype = &[_]Valtype{},
    results: []const Valtype = &[_]Valtype{},
};

pub const LocalDecl = struct {
    count: u32,
    valtype: Valtype,
};

pub const GlobalType = struct {
    valtype: Valtype,
    mutable: bool = false,
};

pub const Import = struct {
    module: []const u8,
    name: []const u8,
    desc: ImportDesc,

    pub const ImportDesc = union(enum) {
        function: u32,
        memory: MemoryType,
        global: GlobalType,
    };
};

pub const Export = struct {
    name: []const u8,
    kind: ExternalKind,
    index: u32,
};

pub const Global = struct {
    ty: GlobalType,
    init: InitExpression,
};

pub const FunctionBody = struct {
    /// Local groups are encoded as count + valtype entries.
    locals: []const LocalDecl = &[_]LocalDecl{},
    /// Raw opcode bytes for the function body, excluding the trailing `end`.
    instructions: []const u8 = &[_]u8{},
};

pub const DataSegment = union(enum) {
    active: struct {
        memory_index: u32 = 0,
        offset: InitExpression,
        bytes: []const u8,
    },
    passive: struct {
        bytes: []const u8,
    },
};

pub const TypeSection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(FunctionType),

    pub fn init(allocator: std.mem.Allocator) TypeSection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(FunctionType).init(allocator),
        };
    }

    pub fn deinit(self: *TypeSection) void {
        self.items.deinit();
    }

    pub fn append(self: *TypeSection, func_type: FunctionType) !void {
        try self.items.append(func_type);
    }

    pub fn write(self: *const TypeSection, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const payload_writer = payload.writer();
        try encoder.writeUleb128(payload_writer, try u32FromLen(self.items.items.len));
        for (self.items.items) |func_type| {
            try writeFunctionType(payload_writer, func_type);
        }

        try emitSection(writer, .type, payload.items);
    }
};

pub const ImportSection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Import),

    pub fn init(allocator: std.mem.Allocator) ImportSection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(Import).init(allocator),
        };
    }

    pub fn deinit(self: *ImportSection) void {
        self.items.deinit();
    }

    pub fn append(self: *ImportSection, entry: Import) !void {
        try self.items.append(entry);
    }

    pub fn write(self: *const ImportSection, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const payload_writer = payload.writer();
        try encoder.writeUleb128(payload_writer, try u32FromLen(self.items.items.len));
        for (self.items.items) |entry| {
            try writeName(payload_writer, entry.module);
            try writeName(payload_writer, entry.name);
            switch (entry.desc) {
                .function => |type_index| {
                    try payload_writer.writeByte(@intFromEnum(ExternalKind.function));
                    try encoder.writeUleb128(payload_writer, type_index);
                },
                .memory => |memory| {
                    try payload_writer.writeByte(@intFromEnum(ExternalKind.memory));
                    try writeMemoryType(payload_writer, memory);
                },
                .global => |global_ty| {
                    try payload_writer.writeByte(@intFromEnum(ExternalKind.global));
                    try writeGlobalType(payload_writer, global_ty);
                },
            }
        }

        try emitSection(writer, .import, payload.items);
    }
};

pub const FunctionSection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator) FunctionSection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *FunctionSection) void {
        self.items.deinit();
    }

    pub fn append(self: *FunctionSection, type_index: u32) !void {
        try self.items.append(type_index);
    }

    pub fn write(self: *const FunctionSection, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const payload_writer = payload.writer();
        try encoder.writeUleb128(payload_writer, try u32FromLen(self.items.items.len));
        for (self.items.items) |type_index| {
            try encoder.writeUleb128(payload_writer, type_index);
        }

        try emitSection(writer, .function, payload.items);
    }
};

pub const MemorySection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(MemoryType),

    pub fn init(allocator: std.mem.Allocator) MemorySection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(MemoryType).init(allocator),
        };
    }

    pub fn deinit(self: *MemorySection) void {
        self.items.deinit();
    }

    pub fn append(self: *MemorySection, memory: MemoryType) !void {
        try self.items.append(memory);
    }

    pub fn write(self: *const MemorySection, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const payload_writer = payload.writer();
        try encoder.writeUleb128(payload_writer, try u32FromLen(self.items.items.len));
        for (self.items.items) |memory| {
            try writeMemoryType(payload_writer, memory);
        }

        try emitSection(writer, .memory, payload.items);
    }
};

pub const GlobalSection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Global),

    pub fn init(allocator: std.mem.Allocator) GlobalSection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(Global).init(allocator),
        };
    }

    pub fn deinit(self: *GlobalSection) void {
        self.items.deinit();
    }

    pub fn append(self: *GlobalSection, global: Global) !void {
        try self.items.append(global);
    }

    pub fn write(self: *const GlobalSection, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const payload_writer = payload.writer();
        try encoder.writeUleb128(payload_writer, try u32FromLen(self.items.items.len));
        for (self.items.items) |global| {
            try writeGlobalType(payload_writer, global.ty);
            try writeInitExpression(payload_writer, global.init);
        }

        try emitSection(writer, .global, payload.items);
    }
};

pub const ExportSection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Export),

    pub fn init(allocator: std.mem.Allocator) ExportSection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(Export).init(allocator),
        };
    }

    pub fn deinit(self: *ExportSection) void {
        self.items.deinit();
    }

    pub fn append(self: *ExportSection, entry: Export) !void {
        try self.items.append(entry);
    }

    pub fn write(self: *const ExportSection, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const payload_writer = payload.writer();
        try encoder.writeUleb128(payload_writer, try u32FromLen(self.items.items.len));
        for (self.items.items) |entry| {
            try writeName(payload_writer, entry.name);
            try payload_writer.writeByte(@intFromEnum(entry.kind));
            try encoder.writeUleb128(payload_writer, entry.index);
        }

        try emitSection(writer, .@"export", payload.items);
    }
};

pub const CodeSection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(FunctionBody),

    pub fn init(allocator: std.mem.Allocator) CodeSection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(FunctionBody).init(allocator),
        };
    }

    pub fn deinit(self: *CodeSection) void {
        self.items.deinit();
    }

    pub fn append(self: *CodeSection, body: FunctionBody) !void {
        try self.items.append(body);
    }

    pub fn write(self: *const CodeSection, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const payload_writer = payload.writer();
        try encoder.writeUleb128(payload_writer, try u32FromLen(self.items.items.len));
        for (self.items.items) |body| {
            try writeFunctionBody(self.allocator, payload_writer, body);
        }

        try emitSection(writer, .code, payload.items);
    }
};

pub const DataSection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(DataSegment),

    pub fn init(allocator: std.mem.Allocator) DataSection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(DataSegment).init(allocator),
        };
    }

    pub fn deinit(self: *DataSection) void {
        self.items.deinit();
    }

    pub fn append(self: *DataSection, segment: DataSegment) !void {
        try self.items.append(segment);
    }

    pub fn write(self: *const DataSection, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const payload_writer = payload.writer();
        try encoder.writeUleb128(payload_writer, try u32FromLen(self.items.items.len));
        for (self.items.items) |segment| {
            try writeDataSegment(payload_writer, segment);
        }

        try emitSection(writer, .data, payload.items);
    }
};

pub const ModuleAssembly = struct {
    allocator: std.mem.Allocator,
    types: TypeSection,
    imports: ImportSection,
    functions: FunctionSection,
    memories: MemorySection,
    globals: GlobalSection,
    exports: ExportSection,
    codes: CodeSection,
    data: DataSection,

    pub fn init(allocator: std.mem.Allocator) ModuleAssembly {
        return .{
            .allocator = allocator,
            .types = TypeSection.init(allocator),
            .imports = ImportSection.init(allocator),
            .functions = FunctionSection.init(allocator),
            .memories = MemorySection.init(allocator),
            .globals = GlobalSection.init(allocator),
            .exports = ExportSection.init(allocator),
            .codes = CodeSection.init(allocator),
            .data = DataSection.init(allocator),
        };
    }

    pub fn deinit(self: *ModuleAssembly) void {
        self.data.deinit();
        self.codes.deinit();
        self.exports.deinit();
        self.globals.deinit();
        self.memories.deinit();
        self.functions.deinit();
        self.imports.deinit();
        self.types.deinit();
    }

    pub fn write(self: *const ModuleAssembly, writer: anytype) !void {
        try self.validate();

        try writer.writeAll(wasm.magic[0..]);
        try writer.writeAll(wasm.version[0..]);

        try self.types.write(writer);
        try self.imports.write(writer);
        try self.functions.write(writer);
        try self.memories.write(writer);
        try self.globals.write(writer);
        try self.exports.write(writer);
        try self.codes.write(writer);
        try self.data.write(writer);
    }

    pub fn toOwnedBytes(self: *const ModuleAssembly, allocator: std.mem.Allocator) ![]u8 {
        var bytes = std.ArrayList(u8).init(allocator);
        errdefer bytes.deinit();
        try self.write(bytes.writer());
        return try bytes.toOwnedSlice();
    }

    fn validate(self: *const ModuleAssembly) !void {
        if (self.functions.items.items.len != self.codes.items.items.len) {
            return error.FunctionBodyCountMismatch;
        }
    }
};

fn emitSection(writer: anytype, id: SectionId, payload: []const u8) !void {
    try writer.writeByte(@intFromEnum(id));
    try encoder.writeUleb128(writer, try u32FromLen(payload.len));
    try writer.writeAll(payload);
}

fn writeName(writer: anytype, bytes: []const u8) !void {
    try encoder.writeUleb128(writer, try u32FromLen(bytes.len));
    try writer.writeAll(bytes);
}

fn writeFunctionType(writer: anytype, func_type: FunctionType) !void {
    try writer.writeByte(wasm.function_type);
    try encoder.writeUleb128(writer, try u32FromLen(func_type.params.len));
    for (func_type.params) |param| {
        try writer.writeByte(@intFromEnum(param));
    }
    try encoder.writeUleb128(writer, try u32FromLen(func_type.results.len));
    for (func_type.results) |result| {
        try writer.writeByte(@intFromEnum(result));
    }
}

fn writeMemoryType(writer: anytype, memory: MemoryType) !void {
    if (memory.limits.flags.is_shared and !memory.limits.flags.has_max) {
        return error.InvalidMemoryLimits;
    }

    var flags: u32 = 0;
    if (memory.limits.flags.has_max) flags |= 0x01;
    if (memory.limits.flags.is_shared) flags |= 0x02;

    try encoder.writeUleb128(writer, flags);
    try encoder.writeUleb128(writer, memory.limits.min);
    if (memory.limits.flags.has_max) {
        try encoder.writeUleb128(writer, memory.limits.max);
    }
}

fn writeGlobalType(writer: anytype, global_ty: GlobalType) !void {
    try writer.writeByte(@intFromEnum(global_ty.valtype));
    try writer.writeByte(if (global_ty.mutable) 0x01 else 0x00);
}

fn writeInitExpression(writer: anytype, expr: InitExpression) !void {
    switch (expr) {
        .i32_const => |value| {
            try writer.writeByte(@intFromEnum(wasm.Opcode.i32_const));
            try encoder.writeIleb128(writer, value);
        },
        .i64_const => |value| {
            try writer.writeByte(@intFromEnum(wasm.Opcode.i64_const));
            try encoder.writeIleb128(writer, value);
        },
        .f32_const => |value| {
            try writer.writeByte(@intFromEnum(wasm.Opcode.f32_const));
            var bytes: [4]u8 = undefined;
            const bits: u32 = @bitCast(value);
            std.mem.writeInt(u32, bytes[0..], bits, .little);
            try writer.writeAll(bytes[0..]);
        },
        .f64_const => |value| {
            try writer.writeByte(@intFromEnum(wasm.Opcode.f64_const));
            var bytes: [8]u8 = undefined;
            const bits: u64 = @bitCast(value);
            std.mem.writeInt(u64, bytes[0..], bits, .little);
            try writer.writeAll(bytes[0..]);
        },
        .global_get => |index| {
            try writer.writeByte(@intFromEnum(wasm.Opcode.global_get));
            try encoder.writeUleb128(writer, index);
        },
    }

    try writer.writeByte(@intFromEnum(wasm.Opcode.end));
}

fn writeFunctionBody(allocator: std.mem.Allocator, writer: anytype, body: FunctionBody) !void {
    var body_payload = std.ArrayList(u8).init(allocator);
    defer body_payload.deinit();

    const body_writer = body_payload.writer();
    try encoder.writeUleb128(body_writer, try u32FromLen(body.locals.len));
    for (body.locals) |local| {
        try encoder.writeUleb128(body_writer, local.count);
        try body_writer.writeByte(@intFromEnum(local.valtype));
    }
    try body_writer.writeAll(body.instructions);
    try body_writer.writeByte(@intFromEnum(wasm.Opcode.end));

    try encoder.writeUleb128(writer, try u32FromLen(body_payload.items.len));
    try writer.writeAll(body_payload.items);
}

fn writeDataSegment(writer: anytype, segment: DataSegment) !void {
    switch (segment) {
        .active => |active| {
            if (active.memory_index == 0) {
                try writer.writeByte(0x00);
            } else {
                try writer.writeByte(0x02);
                try encoder.writeUleb128(writer, active.memory_index);
            }
            try writeInitExpression(writer, active.offset);
            try encoder.writeUleb128(writer, try u32FromLen(active.bytes.len));
            try writer.writeAll(active.bytes);
        },
        .passive => |passive| {
            try writer.writeByte(0x01);
            try encoder.writeUleb128(writer, try u32FromLen(passive.bytes.len));
            try writer.writeAll(passive.bytes);
        },
    }
}

fn u32FromLen(len: usize) !u32 {
    return std.math.cast(u32, len) orelse error.ValueTooLarge;
}

test "module assembly emits canonical section order" {
    var module = ModuleAssembly.init(std.testing.allocator);
    defer module.deinit();

    try module.data.append(.{ .active = .{
        .memory_index = 0,
        .offset = .{ .i32_const = 0 },
        .bytes = "abc",
    } });
    try module.exports.append(.{
        .name = "run",
        .kind = .function,
        .index = 1,
    });
    try module.types.append(.{
        .params = &[_]Valtype{},
        .results = &[_]Valtype{},
    });
    try module.codes.append(.{
        .locals = &[_]LocalDecl{},
        .instructions = &[_]u8{},
    });
    try module.globals.append(.{
        .ty = .{ .valtype = .i32, .mutable = false },
        .init = .{ .i32_const = 42 },
    });
    try module.functions.append(0);
    try module.imports.append(.{
        .module = "env",
        .name = "tick",
        .desc = .{ .function = 0 },
    });
    try module.memories.append(.{
        .limits = .{
            .flags = .{ .has_max = true, .is_shared = false, .reserved = 0 },
            .min = 1,
            .max = 2,
        },
    });

    const bytes = try module.toOwnedBytes(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 8);
    try std.testing.expectEqualSlices(u8, wasm.magic[0..], bytes[0..4]);
    try std.testing.expectEqualSlices(u8, wasm.version[0..], bytes[4..8]);

    var fbs = std.io.fixedBufferStream(bytes[8..]);
    const reader = fbs.reader();
    var seen = std.ArrayList(SectionId).init(std.testing.allocator);
    defer seen.deinit();

    while (fbs.pos < fbs.buffer.len) {
        const id = try reader.readByte();
        const section = std.meta.intToEnum(SectionId, id) catch return error.InvalidWasm;
        const section_len = try std.leb.readUleb128(u32, reader);
        const section_end = fbs.pos + @as(usize, @intCast(section_len));
        if (section_end > fbs.buffer.len) return error.InvalidWasm;
        try seen.append(section);
        fbs.pos = section_end;
    }

    try std.testing.expectEqualSlices(
        SectionId,
        &[_]SectionId{ .type, .import, .function, .memory, .global, .@"export", .code, .data },
        seen.items,
    );
}

test "module assembly emits a minimal valid module" {
    var module = ModuleAssembly.init(std.testing.allocator);
    defer module.deinit();

    try module.types.append(.{
        .params = &[_]Valtype{},
        .results = &[_]Valtype{},
    });
    try module.functions.append(0);
    try module.exports.append(.{
        .name = "main",
        .kind = .function,
        .index = 0,
    });
    try module.codes.append(.{
        .locals = &[_]LocalDecl{},
        .instructions = &[_]u8{},
    });

    const bytes = try module.toOwnedBytes(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    const expected = [_]u8{
        0x00, 0x61, 0x73, 0x6D,
        0x01, 0x00, 0x00, 0x00,
        0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
        0x03, 0x02, 0x01, 0x00,
        0x07, 0x08, 0x01, 0x04, 0x6D, 0x61, 0x69, 0x6E, 0x00, 0x00,
        0x0A, 0x04, 0x01, 0x02, 0x00, 0x0B,
    };
    try std.testing.expectEqualSlices(u8, expected[0..], bytes);
}
