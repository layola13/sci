// Target-conditional declaration materialization (C-upper).
//
// This module is the sci-side implementation of the shared spec (master
// copy: sa_plugin_sla docs/target_conditional_decls.md, golden corpus
// tests/decl_target/ there). It is consumed from two points:
//   - build.zig (via tools/decl_materialize.zig, a re-export of this
//     file) reduces target-conditional declaration blocks in
//     SA-implemented std units to the single concrete variant for the
//     archive's target before the `sa` assembler tool sees the file
//     (the build-time sa_std mirror);
//   - src/flattener.zig materializes imported sources carrying such
//     blocks before splicing them into a compilation (fork H, H1).
// The SA compiler itself never learns any conditional semantics.
//
// This is one implementation of the shared specification whose master
// copy lives in the sa_plugin_sla repository
// (docs/target_conditional_decls.md, golden corpus tests/decl_target/);
// the SLA front-end implementation is src/decl_materialize.zig there.
// The test vectors below are the golden vectors from that specification
// and must stay byte-identical across implementations.

const std = @import("std");

pub const DeclTarget = enum {
    native,
    wasm32,

    pub fn targetName(self: DeclTarget) []const u8 {
        return switch (self) {
            .native => "native",
            .wasm32 => "wasm32",
        };
    }

    pub fn fromName(name: []const u8) ?DeclTarget {
        if (std.mem.eql(u8, name, "native")) return .native;
        if (std.mem.eql(u8, name, "wasm32")) return .wasm32;
        return null;
    }
};

pub const MaterializeError = error{
    MissingTargetVariant,
    DuplicateTargetVariant,
    UnknownTargetName,
    EmptyTargetSection,
    TargetSectionOutsideBlock,
    ContentOutsideTargetSection,
    NestedTargetBlock,
    EndWithoutTargetBlock,
    UnterminatedTargetBlock,
    OutOfMemory,
};

const begin_marker = "// @target-begin";
const end_marker = "// @target-end";
const section_prefix = "// @target ";

pub fn containsTargetBlocks(source: []const u8) bool {
    if (std.mem.indexOf(u8, source, begin_marker) != null) return true;
    if (std.mem.indexOf(u8, source, end_marker) != null) return true;
    if (std.mem.startsWith(u8, source, section_prefix)) return true;
    return std.mem.indexOf(u8, source, "\n// @target ") != null;
}

const Marker = union(enum) {
    begin,
    end,
    section: []const u8,
    not_marker,
};

fn classifyMarker(trimmed_line: []const u8) Marker {
    if (std.mem.eql(u8, trimmed_line, begin_marker)) return .begin;
    if (std.mem.eql(u8, trimmed_line, end_marker)) return .end;
    if (std.mem.startsWith(u8, trimmed_line, section_prefix)) {
        const name = trimmed_line[section_prefix.len..];
        if (name.len == 0) return .not_marker;
        if (std.mem.indexOfAny(u8, name, " \t") != null) return .not_marker;
        return .{ .section = name };
    }
    return .not_marker;
}

pub fn materialize(allocator: std.mem.Allocator, source: []const u8, target: DeclTarget) MaterializeError![]const u8 {
    if (!containsTargetBlocks(source)) {
        return allocator.dupe(u8, source) catch return error.OutOfMemory;
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var in_block = false;
    var seen = [_]bool{ false, false };
    var section: ?DeclTarget = null;
    var section_lines: usize = 0;

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const is_last = lines.index == null;
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");

        switch (classifyMarker(trimmed)) {
            .begin => {
                if (in_block) return error.NestedTargetBlock;
                in_block = true;
                seen = [_]bool{ false, false };
                section = null;
                section_lines = 0;
            },
            .end => {
                if (!in_block) return error.EndWithoutTargetBlock;
                if (section == target and section_lines == 0) return error.EmptyTargetSection;
                if (!seen[@intFromEnum(target)]) return error.MissingTargetVariant;
                in_block = false;
                section = null;
            },
            .section => |name| {
                if (!in_block) return error.TargetSectionOutsideBlock;
                const named = DeclTarget.fromName(name) orelse return error.UnknownTargetName;
                if (section == target and section_lines == 0) return error.EmptyTargetSection;
                if (seen[@intFromEnum(named)]) return error.DuplicateTargetVariant;
                seen[@intFromEnum(named)] = true;
                section = named;
                section_lines = 0;
            },
            .not_marker => {
                if (!in_block) {
                    try appendLine(&out, raw_line, is_last);
                } else if (section == null) {
                    if (trimmed.len != 0) return error.ContentOutsideTargetSection;
                } else if (section == target) {
                    section_lines += 1;
                    try appendLine(&out, raw_line, is_last);
                } else {
                    section_lines += 1;
                }
            },
        }
    }
    if (in_block) {
        if (section == target and section_lines == 0) return error.EmptyTargetSection;
        return error.UnterminatedTargetBlock;
    }
    return out.toOwnedSlice() catch return error.OutOfMemory;
}

fn appendLine(out: *std.array_list.Managed(u8), line: []const u8, is_last: bool) MaterializeError!void {
    out.appendSlice(line) catch return error.OutOfMemory;
    if (!is_last) out.append('\n') catch return error.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Golden vectors (shared specification, see header). Keep in lockstep with
// the sa_plugin_sla implementation's tests.
// ---------------------------------------------------------------------------

const testing = std.testing;

const sample =
    \\const A: u32 = 1;
    \\// @target-begin
    \\// @target native
    \\extern fn mmap(addr: ptr, len: u64) -> ptr;
    \\// @target wasm32
    \\extern fn mmap(addr: ptr, len: u32) -> ptr;
    \\// @target-end
    \\const B: u32 = 2;
    \\
;

test "golden: native selection" {
    const out = try materialize(testing.allocator, sample, .native);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        \\const A: u32 = 1;
        \\extern fn mmap(addr: ptr, len: u64) -> ptr;
        \\const B: u32 = 2;
        \\
    , out);
}

test "golden: wasm32 selection" {
    const out = try materialize(testing.allocator, sample, .wasm32);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        \\const A: u32 = 1;
        \\extern fn mmap(addr: ptr, len: u32) -> ptr;
        \\const B: u32 = 2;
        \\
    , out);
}

test "golden: identity without blocks" {
    const src = "extern fn read(fd: i32, len: u64) -> i32;\n";
    const out = try materialize(testing.allocator, src, .wasm32);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(src, out);
}

test "golden: missing variant is a hard error" {
    const src =
        \\// @target-begin
        \\// @target native
        \\extern fn f(len: u64) -> void;
        \\// @target-end
        \\
    ;
    try testing.expectError(error.MissingTargetVariant, materialize(testing.allocator, src, .wasm32));
}

test "golden: duplicate variant is a hard error" {
    const src =
        \\// @target-begin
        \\// @target native
        \\extern fn f(len: u64) -> void;
        \\// @target native
        \\extern fn f(len: u64) -> void;
        \\// @target-end
        \\
    ;
    try testing.expectError(error.DuplicateTargetVariant, materialize(testing.allocator, src, .native));
}

test "golden: unknown target is a hard error" {
    const src =
        \\// @target-begin
        \\// @target mips
        \\extern fn f(len: u64) -> void;
        \\// @target-end
        \\
    ;
    try testing.expectError(error.UnknownTargetName, materialize(testing.allocator, src, .native));
}

test "golden: empty selected section is a hard error" {
    const src =
        \\// @target-begin
        \\// @target native
        \\// @target wasm32
        \\extern fn f(len: u32) -> void;
        \\// @target-end
        \\
    ;
    try testing.expectError(error.EmptyTargetSection, materialize(testing.allocator, src, .native));
}

test "golden: unterminated block and stray markers are hard errors" {
    const unterminated =
        \\// @target-begin
        \\// @target native
        \\extern fn f(len: u64) -> void;
        \\
    ;
    try testing.expectError(error.UnterminatedTargetBlock, materialize(testing.allocator, unterminated, .native));
    try testing.expectError(error.EndWithoutTargetBlock, materialize(testing.allocator, "// @target-end\n", .native));
    const stray_section =
        \\// @target native
        \\extern fn f(len: u64) -> void;
        \\
    ;
    try testing.expectError(error.TargetSectionOutsideBlock, materialize(testing.allocator, stray_section, .native));
}
