const std = @import("std");
const classifier = @import("line_classifier.zig");
const common_instruction = @import("../common/instruction.zig");
const common_signature = @import("../common/signature.zig");
const common_upstream = @import("../common/upstream_loc.zig");
const LayoutVersion = @import("importexpansion.zig").LayoutVersion;
const Replacement = @import("importexpansion.zig").Replacement;
const SourceLine = @import("importexpansion.zig").SourceLine;
const packageNamespacePrefix = @import("injectimportedfile.zig").packageNamespacePrefix;


pub fn renderWithTokenReplacements(
    allocator: std.mem.Allocator,
    text: []const u8,
    replacements: []const Replacement,
) ![]const u8 {
    if (replacements.len == 0) {
        return try allocator.dupe(u8, text);
    }

    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];

        // String literal: copy until closing quote
        if (c == '"') {
            try result.append(c);
            i += 1;
            while (i < text.len and text[i] != '"') {
                try result.append(text[i]);
                i += 1;
            }
            if (i < text.len) {
                try result.append(text[i]); // closing quote
                i += 1;
            }
            continue;
        }

        // Line comment: copy to end
        if (c == '/' and i + 1 < text.len and text[i + 1] == '/') {
            while (i < text.len) {
                try result.append(text[i]);
                i += 1;
            }
            continue;
        }

        // @ and # prefixed identifiers: always copy as-is (function names, defs)
        if (c == '@' or c == '#') {
            try result.append(c);
            i += 1;
            while (i < text.len and isIdentChar(text[i])) {
                try result.append(text[i]);
                i += 1;
            }
            continue;
        }

        // % prefixed identifiers: collect full token and check for replacement
        if (c == '%') {
            const token_start = i;
            i += 1;
            while (i < text.len and isIdentChar(text[i])) {
                i += 1;
            }
            const token = text[token_start..i]; // e.g. %name_SIZE
            var found = false;
            for (replacements) |r| {
                if (std.mem.eql(u8, r.needle, token)) {
                    // Exact match: replace entire token
                    try result.appendSlice(r.replacement);
                    found = true;
                    break;
                }
            }
            if (!found) {
                // Try prefix match: needle like %name matches %name_SIZE
                for (replacements) |r| {
                    if (r.needle.len > 0 and r.needle[0] == '%' and
                        r.needle.len < token.len and
                        std.mem.eql(u8, r.needle, token[0..r.needle.len]))
                    {
                        try result.appendSlice(r.replacement);
                        try result.appendSlice(token[r.needle.len..]);
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                try result.appendSlice(token);
            }
            continue;
        }

        // Identifier: collect and try replacement
        if (isIdentStart(c)) {
            const ident_start = i;
            while (i < text.len and isIdentChar(text[i])) {
                i += 1;
            }
            const ident = text[ident_start..i];

            var found = false;
            for (replacements) |r| {
                if (std.mem.eql(u8, r.needle, ident)) {
                    try result.appendSlice(r.replacement);
                    found = true;
                    break;
                }
            }
            if (!found) {
                try result.appendSlice(ident);
            }
            continue;
        }

        // Other characters: copy as-is
        try result.append(c);
        i += 1;
    }

    return result.toOwnedSlice();
}

pub fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

pub fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn collectDefinedNames(
    allocator: std.mem.Allocator,
    lines: []const SourceLine,
    start: usize,
    end: usize,
) !std.StringHashMap(void) {
    var names = std.StringHashMap(void).init(allocator);

    for (start..end) |idx| {
        const line = lines[idx];
        switch (line.classified.kind) {
            .label => {
                const name = line.classified.parts[0];
                if (std.mem.startsWith(u8, name, "L_")) {
                    try names.put(name, {});
                }
            },
            .instruction => {
                const form = line.classified.inst_form orelse continue;
                const should_collect = switch (form) {
                    .alloc, .stack_alloc, .load, .borrow, .move_, .assign, .op, .ptr_add, .call, .call_indirect, .try_, .cmpxchg, .atomic_load, .atomic_rmw, .fence, .raw_cast, .assume_safe, .assume_borrow => true,
                    else => false,
                };
                if (should_collect) {
                    const name = line.classified.parts[0];
                    if (name.len > 0 and name[0] == '_') {
                        try names.put(name, {});
                    }
                }
            },
            else => {},
        }
    }

    return names;
}

pub fn collectDefinedNamesFromSlice(
    allocator: std.mem.Allocator,
    lines: []const SourceLine,
) !std.StringHashMap(void) {
    return collectDefinedNames(allocator, lines, 0, lines.len);
}

pub fn buildHygieneReplacements(
    allocator: std.mem.Allocator,
    defined_names: *std.StringHashMap(void),
    expansion_id: u64,
) !std.array_list.Managed(Replacement) {
    var replacements = std.array_list.Managed(Replacement).init(allocator);
    errdefer replacements.deinit();

    var it = defined_names.keyIterator();
    while (it.next()) |name_ptr| {
        const name = name_ptr.*;
        const replacement_text = try std.fmt.allocPrint(allocator, "{s}__sa_hyg{d}", .{ name, expansion_id });
        errdefer allocator.free(replacement_text);
        try replacements.append(.{ .needle = name, .replacement = replacement_text });
    }

    return replacements;
}

pub fn ownText(
    allocator: std.mem.Allocator,
    owned_text: *std.array_list.Managed([]const u8),
    text: []const u8,
) ![]const u8 {
    const dup = try allocator.dupe(u8, text);
    errdefer allocator.free(dup);
    try owned_text.append(dup);
    return dup;
}

pub fn ownFoldedText(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    owned_text: *std.array_list.Managed([]const u8),
    text: []const u8,
) ![]const u8 {
    const folded = try dict.foldText(allocator, text);
    errdefer allocator.free(folded);
    try owned_text.append(folded);
    return folded;
}

pub fn stripLeadingPlus(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len > 0 and trimmed[0] == '+') {
        return std.mem.trimStart(u8, trimmed[1..], " \t");
    }
    return trimmed;
}

pub fn parseIntAllowLeadingPlus(comptime T: type, text: []const u8) !T {
    const normalized = stripLeadingPlus(text);
    return std.fmt.parseInt(T, normalized, 10) catch |err| {
        return err;
    };
}

pub fn parseLayoutOffset(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    owned_text: *std.array_list.Managed([]const u8),
    current_package_identity: ?[]const u8,
    text: []const u8,
) !u64 {
    const folded = try ownFoldedText(allocator, dict, owned_text, text);
    if (parseIntAllowLeadingPlus(u64, folded)) |value| {
        return value;
    } else |err| switch (err) {
        error.InvalidCharacter => {},
        else => return err,
    }

    if (dict.get(folded)) |value_text| {
        return try parseIntAllowLeadingPlus(u64, value_text);
    }

    if (current_package_identity) |identity| {
        const prefix = try packageNamespacePrefix(allocator, identity);
        defer allocator.free(prefix);

        const qualified = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, folded });
        defer allocator.free(qualified);

        if (dict.get(qualified)) |value_text| {
            return try parseIntAllowLeadingPlus(u64, value_text);
        }
    }

    var it = dict.entries.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.endsWith(u8, key, folded) and key.len > folded.len) {
            const separator = key[key.len - folded.len - 1];
            if (separator != '.' and separator != '_') continue;
            return try parseIntAllowLeadingPlus(u64, entry.value_ptr.*);
        }
    }

    std.debug.print("\nparseLayoutOffset failed for folded: '{s}' (text: '{s}')\nAvailable keys in dict:\n", .{ folded, text });
    var it_keys = dict.entries.iterator();
    while (it_keys.next()) |entry| {
        std.debug.print("  - '{s}': '{s}'\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    return error.InvalidSyntax;
}

fn parseNumericOperand(text: []const u8) ?common_instruction.Operand {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return null;

    if (std.fmt.parseInt(i64, trimmed, 10)) |value| {
        return .{ .imm_i64 = value };
    } else |err| switch (err) {
        error.Overflow => {
            if (std.fmt.parseInt(u64, trimmed, 10)) |value| {
                return .{ .imm_u64 = value };
            } else |_| {}
        },
        error.InvalidCharacter => {
            const no_plus = stripLeadingPlus(trimmed);
            if (no_plus.len != trimmed.len) {
                if (std.fmt.parseInt(i64, no_plus, 10)) |value| {
                    return .{ .imm_i64 = value };
                } else |retry_err| switch (retry_err) {
                    error.Overflow => {
                        if (std.fmt.parseInt(u64, no_plus, 10)) |value| {
                            return .{ .imm_u64 = value };
                        } else |_| {}
                    },
                    else => {},
                }
            }
        },
    }

    if (std.mem.indexOfAny(u8, trimmed, ".eE")) |_| {
        if (std.fmt.parseFloat(f64, trimmed)) |value| {
            return .{ .imm_float = value };
        } else |_| {}
    }

    return null;
}

fn parseSizeOperand(text: []const u8) ?common_instruction.Operand {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return null;

    if (std.fmt.parseInt(i64, trimmed, 10)) |value| {
        if (value >= 0) {
            return .{ .imm_u64 = @as(u64, @intCast(value)) };
        }
        return .{ .imm_i64 = value };
    } else |err| switch (err) {
        error.Overflow => {
            if (std.fmt.parseInt(u64, trimmed, 10)) |value| {
                return .{ .imm_u64 = value };
            } else |_| {}
        },
        error.InvalidCharacter => {
            const no_plus = stripLeadingPlus(trimmed);
            if (no_plus.len != trimmed.len) {
                if (std.fmt.parseInt(i64, no_plus, 10)) |value| {
                    if (value >= 0) {
                        return .{ .imm_u64 = @as(u64, @intCast(value)) };
                    }
                    return .{ .imm_i64 = value };
                } else |retry_err| switch (retry_err) {
                    error.Overflow => {
                        if (std.fmt.parseInt(u64, no_plus, 10)) |value| {
                            return .{ .imm_u64 = value };
                        } else |_| {}
                    },
                    else => {},
                }
            }
        },
    }

    return null;
}

pub fn resolveOperandText(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    owned_text: *std.array_list.Managed([]const u8),
    symbols: *SymbolTable,
    text: []const u8,
) !common_instruction.Operand {
    const folded = try ownFoldedText(allocator, dict, owned_text, text);
    if (parseNumericOperand(folded)) |operand| return operand;
    return .{ .reg = try symbols.intern(folded) };
}

pub fn resolveSizeOperandText(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    owned_text: *std.array_list.Managed([]const u8),
    symbols: *SymbolTable,
    text: []const u8,
) !common_instruction.Operand {
    const folded = try ownFoldedText(allocator, dict, owned_text, text);
    if (parseSizeOperand(folded)) |operand| return operand;
    if (symbols.findId(folded)) |id| {
        return .{ .reg = id };
    }
    return .{ .reg = try symbols.intern(folded) };
}

pub fn consumePendingLoc(
    loc_table: *std.array_list.Managed(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
) !?common_upstream.UpstreamLoc {
    const loc = pending_loc.*;
    try loc_table.append(loc);
    pending_loc.* = null;
    return loc;
}

pub fn takePendingLoc(
    pending_loc: *?common_upstream.UpstreamLoc,
) ?common_upstream.UpstreamLoc {
    const loc = pending_loc.*;
    pending_loc.* = null;
    return loc;
}

pub fn appendNullLoc(loc_table: *std.array_list.Managed(?common_upstream.UpstreamLoc)) !void {
    try loc_table.append(null);
}

pub fn setPendingLoc(
    allocator: std.mem.Allocator,
    pending_loc: *?common_upstream.UpstreamLoc,
    file: []const u8,
    line: u32,
    col: u32,
) !void {
    if (line == 0 or col == 0) return error.InvalidLocHint;
    if (pending_loc.*) |current| {
        allocator.free(current.file);
        pending_loc.* = null;
    }
    const file_copy = try allocator.dupe(u8, file);
    pending_loc.* = .{
        .file = file_copy,
        .line = line,
        .col = col,
    };
}

pub fn recordLayoutVersion(
    allocator: std.mem.Allocator,
    layout_versions: *std.array_list.Managed(LayoutVersion),
    path: []const u8,
    source: []const u8,
) !void {
    var iterator = std.mem.splitScalar(u8, source, '\n');
    while (iterator.next()) |raw_line| {
        const classified = classifier.classifyLine(raw_line);
        if (classified.kind != .version) continue;

        const version = std.fmt.parseInt(u64, classified.parts[0], 10) catch return error.InvalidSyntax;
        const path_copy = try allocator.dupe(u8, path);
        errdefer allocator.free(path_copy);
        try layout_versions.append(.{
            .path = path_copy,
            .version = version,
        });
        return;
    }
}

pub fn findBlockEnd(lines: []const SourceLine, start: usize, close_kind: LineKind) ?usize {
    var idx = start;
    while (idx < lines.len) : (idx += 1) {
        if (lines[idx].classified.kind == close_kind) return idx;
    }
    return null;
}

pub fn findNestedRepEnd(lines: []const SourceLine, start: usize) ?usize {
    var depth: usize = 1;
    var idx = start;
    while (idx < lines.len) : (idx += 1) {
        switch (lines[idx].classified.kind) {
            .rep_start => depth += 1,
            .rep_end => {
                depth -= 1;
                if (depth == 0) return idx;
            },
            else => {},
        }
    }
    return null;
}

const IfBounds = struct {
    else_idx: ?usize,
    end_idx: usize,
};

pub fn findNestedIfBounds(lines: []const SourceLine, start: usize) ?IfBounds {
    var depth: usize = 1;
    var else_idx: ?usize = null;
    var idx = start;
    while (idx < lines.len) : (idx += 1) {
        switch (lines[idx].classified.kind) {
            .if_start => depth += 1,
            .else_ => {
                if (depth == 1 and else_idx == null) else_idx = idx;
            },
            .if_end => {
                depth -= 1;
                if (depth == 0) return .{ .else_idx = else_idx, .end_idx = idx };
            },
            else => {},
        }
    }
    return null;
}

pub fn macroConditionIsTrue(text: []const u8) !bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return false;
    if (std.mem.eql(u8, trimmed, "1") or std.mem.eql(u8, trimmed, "true") or std.mem.eql(u8, trimmed, "yes") or std.mem.eql(u8, trimmed, "on")) return true;
    if (std.mem.eql(u8, trimmed, "0") or std.mem.eql(u8, trimmed, "false") or std.mem.eql(u8, trimmed, "no") or std.mem.eql(u8, trimmed, "off")) return false;
    return error.InvalidMacroInvocation;
}

pub fn mapInstKind(form: InstructionForm) InstKind {
    return switch (form) {
        .alloc => .alloc,
        .stack_alloc => .stack_alloc,
        .load => .load,
        .store => .store,
        .atomic_load => .atomic_load,
        .atomic_store => .atomic_store,
        .cmpxchg => .cmpxchg,
        .atomic_rmw => .atomic_rmw,
        .fence => .fence,
        .borrow => .borrow,
        .move_ => .move_,
        .release => .release,
        .assign => .assign,
        .op => .op,
        .ptr_add => .ptr_add,
        .jmp => .jmp,
        .br => .br,
        .br_null => .br_null,
        .call => .call,
        .call_indirect => .call_indirect,
        .try_ => .early_return,
        .panic => .panic,
        .panic_msg => .panic_msg,
        .return_ => .return_,
        .take => .take,
        .raw_cast => .raw_cast,
        .assume_safe => .assume_safe,
        .assume_borrow => .assume_borrow,
        .va_start => .va_start,
        .va_arg => .va_arg,
        .va_end => .va_end,
        .transfer => .transfer,
        .unknown => .native,
    };
}

pub fn parseFunctionSigForKind(
    allocator: std.mem.Allocator,
    raw_line: []const u8,
    id: u32,
    entry_idx: u32,
    kind: FunctionKind,
    symbols: *SymbolTable,
) !FunctionSig {
    var sig = try common_signature.parseFunctionHeader(allocator, raw_line, id, entry_idx, kind);
    errdefer sig.deinit(allocator);
    if (sig.params.len == 0) {
        sig.param_ids = &.{};
        return sig;
    }
    const ids = try allocator.alloc(u32, sig.params.len);
    errdefer allocator.free(ids);
    for (sig.params, 0..) |param, idx| {
        ids[idx] = try symbols.intern(param.name);
    }
    sig.param_ids = ids;
    return sig;
}
