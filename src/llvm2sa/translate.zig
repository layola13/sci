// Top-level translation: IR source -> SA, bitcode file -> SA.
const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const trim = @import("text.zig").trim;
const cleanInstructionLine = @import("text.zig").cleanInstructionLine;
const startsWithWord = @import("text.zig").startsWithWord;
const appendFunctionHeader = @import("values.zig").appendFunctionHeader;
const appendLabel = @import("values.zig").appendLabel;
const appendInstruction = @import("instr.zig").appendInstruction;
const appendSwitch = @import("instr.zig").appendSwitch;
const appendConstDecl = @import("decls.zig").appendConstDecl;
const isPhiInstruction = @import("phi.zig").isPhiInstruction;
const appendPhiSlots = @import("phi.zig").appendPhiSlots;
const appendPhiLoad = @import("phi.zig").appendPhiLoad;
const appendPhiStoresForBlock = @import("phi.zig").appendPhiStoresForBlock;
const types = @import("types.zig");

pub const TranslateError = error{
    OutOfMemory,
    InvalidBitcode,
    InvalidIr,
    LlvmDisFailed,
    LlvmDisNotFound,
    UnsupportedBitcodeInput,
    UnsupportedInstruction,
    UnsupportedPhi,
    StaticMemoryOverflow,
};

const bitcode_magic = [_]u8{ 'B', 'C', 0xc0, 0xde };

const max_bitcode_bytes = 64 * 1024 * 1024;

const max_ir_bytes = 64 * 1024 * 1024;

const llvm_dis_candidates = if (builtin.os.tag == .windows) [_][]const u8{ "llvm-dis-14.exe", "llvm-dis.exe", "llvm-dis-14" } else [_][]const u8{ "/usr/bin/llvm-dis-14", "llvm-dis-14", "llvm-dis" };

const clang_candidates = if (builtin.os.tag == .windows) [_][]const u8{ "clang.exe", "clang" } else [_][]const u8{ "/usr/bin/clang", "clang" };

const llvm_as_candidates = if (builtin.os.tag == .windows) [_][]const u8{ "llvm-as-14.exe", "llvm-as.exe", "llvm-as-14" } else [_][]const u8{ "llvm-as-14", "llvm-as" };

fn appendFunctionBody(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, header: []const u8, body: []const []const u8) !void {
    try appendFunctionHeader(out, allocator, header, false);

    var phi_lines = std.array_list.Managed([]const u8).init(allocator);
    defer phi_lines.deinit();
    for (body) |line| if (isPhiInstruction(line)) try phi_lines.append(line);

    var switch_text = std.array_list.Managed(u8).init(allocator);
    defer switch_text.deinit();
    var pending_switch = false;
    var switch_id: usize = 0;
    var need_entry_label = true;
    var phi_slots_emitted = false;
    var current_block: []const u8 = "entry";

    for (body) |raw_body_line| {
        const line = trim(cleanInstructionLine(raw_body_line));
        if (line.len == 0) continue;
        if (pending_switch) {
            try switch_text.appendSlice(line);
            try switch_text.append('\n');
            if (std.mem.indexOfScalar(u8, line, ']') != null) {
                try appendPhiStoresForBlock(out, allocator, phi_lines.items, current_block);
                try appendSwitch(out, allocator, switch_text.items, switch_id);
                switch_id += 1;
                switch_text.clearRetainingCapacity();
                pending_switch = false;
            }
            continue;
        }
        if (std.mem.endsWith(u8, line, ":")) {
            try appendLabel(out, allocator, line[0 .. line.len - 1]);
            current_block = line[0 .. line.len - 1];
            need_entry_label = false;
            if (!phi_slots_emitted) {
                try appendPhiSlots(out, allocator, phi_lines.items);
                phi_slots_emitted = true;
            }
            continue;
        }
        if (need_entry_label) {
            try out.appendSlice("L_ENTRY:\n");
            try appendPhiSlots(out, allocator, phi_lines.items);
            phi_slots_emitted = true;
            need_entry_label = false;
        }
        if (startsWithWord(line, "switch")) {
            switch_text.clearRetainingCapacity();
            try switch_text.appendSlice(line);
            try switch_text.append('\n');
            if (std.mem.indexOfScalar(u8, line, ']') != null) {
                try appendPhiStoresForBlock(out, allocator, phi_lines.items, current_block);
                try appendSwitch(out, allocator, switch_text.items, switch_id);
                switch_id += 1;
                switch_text.clearRetainingCapacity();
            } else {
                pending_switch = true;
            }
            continue;
        }
        if (startsWithWord(line, "br") or startsWithWord(line, "ret")) {
            try appendPhiStoresForBlock(out, allocator, phi_lines.items, current_block);
        }
        if (isPhiInstruction(line)) {
            try appendPhiLoad(out, allocator, line);
        } else {
            try appendInstruction(out, allocator, line);
        }
    }
    if (pending_switch) return error.InvalidIr;
    try out.append('\n');
}

fn collectTypeDefinitions(types: *std.StringHashMap([]const u8), source: []const u8) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = trim(raw_line);
        if (line.len == 0 or line[0] != '%') continue;
        const marker = std.mem.indexOf(u8, line, " = type ") orelse continue;
        const name = trim(line[0..marker]);
        const body = trim(line[marker + " = type ".len ..]);
        try types.put(name, body);
    }
}

pub fn translateIrSource(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var type_defs = std.StringHashMap([]const u8).init(allocator);
    defer type_defs.deinit();
    try collectTypeDefinitions(&type_defs, source);
    const previous_type_defs = types.active_type_defs;
    types.active_type_defs = &type_defs;
    defer types.active_type_defs = previous_type_defs;

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const trimmed_line = trim(raw_line);
        if (trimmed_line.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed_line, ";")) continue;

        const cleaned = cleanInstructionLine(trimmed_line);
        const line = trim(cleaned);
        if (line.len == 0) continue;
        if (try appendConstDecl(&out, allocator, line)) continue;
        if (startsWithWord(line, "declare")) {
            try appendFunctionHeader(&out, allocator, line, true);
            continue;
        }
        if (startsWithWord(line, "define")) {
            var body = std.array_list.Managed([]const u8).init(allocator);
            defer body.deinit();
            var closed = false;
            while (lines.next()) |raw_body_line| {
                const body_line = trim(cleanInstructionLine(trim(raw_body_line)));
                if (body_line.len == 0) continue;
                if (std.mem.eql(u8, body_line, "}")) {
                    closed = true;
                    break;
                }
                try body.append(body_line);
            }
            if (!closed) return error.InvalidIr;
            try appendFunctionBody(&out, allocator, line, body.items);
            continue;
        }
        continue;
    }
    return try out.toOwnedSlice();
}

fn runLlvmDisTool(allocator: std.mem.Allocator, exe: []const u8, path: []const u8) !?[]u8 {
    const argv = [_][]const u8{ exe, "-o", "-", path };
    const result = sio.Child.run(.{
        .allocator = allocator,
        .argv = argv[0..],
        .max_output_bytes = max_ir_bytes,
    }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code == 0) return result.stdout;
            return error.LlvmDisFailed;
        },
        else => return error.LlvmDisFailed,
    }
}

fn runClangDisTool(allocator: std.mem.Allocator, exe: []const u8, path: []const u8) !?[]u8 {
    const argv = [_][]const u8{ exe, "-S", "-emit-llvm", path, "-o", "-" };
    const result = sio.Child.run(.{
        .allocator = allocator,
        .argv = argv[0..],
        .max_output_bytes = max_ir_bytes,
    }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code == 0) return result.stdout;
            return error.LlvmDisFailed;
        },
        else => return error.LlvmDisFailed,
    }
}

fn disassembleBitcode(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    for (llvm_dis_candidates) |candidate| {
        if (try runLlvmDisTool(allocator, candidate, path)) |ir| return ir;
    }
    for (clang_candidates) |candidate| {
        if (try runClangDisTool(allocator, candidate, path)) |ir| return ir;
    }
    return error.LlvmDisNotFound;
}

pub fn translateBitcodeFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const source = sio.cwd().readFileAlloc(allocator, path, max_bitcode_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.UnsupportedBitcodeInput,
        else => return err,
    };
    defer allocator.free(source);

    if (source.len < bitcode_magic.len or !std.mem.eql(u8, source[0..bitcode_magic.len], bitcode_magic[0..])) {
        return error.UnsupportedBitcodeInput;
    }

    const ir = try disassembleBitcode(allocator, path);
    defer allocator.free(ir);
    return try translateIrSource(allocator, ir);
}

pub fn llvmAs(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
    for (llvm_as_candidates) |candidate| {
        const argv = [_][]const u8{ candidate, input_path, "-o", output_path };
        const result = sio.Child.run(.{
            .allocator = allocator,
            .argv = argv[0..],
        }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        switch (result.term) {
            .exited => |code| if (code == 0) return,
            else => {},
        }
    }
    return error.SkipZigTest;
}
