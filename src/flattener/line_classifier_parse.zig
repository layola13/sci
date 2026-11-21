const std = @import("std");
const ClassifiedLine = @import("line_classifier.zig").ClassifiedLine;
const LineKind = @import("line_classifier.zig").LineKind;
const common_signature = @import("line_classifier.zig").common_signature;

pub fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

pub fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn isQualifiedDefName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '.' or name[name.len - 1] == '.') return false;

    var segment_start: usize = 0;
    var idx: usize = 0;
    while (idx < name.len) : (idx += 1) {
        if (name[idx] != '.') continue;
        if (idx == segment_start) return false;
        if (!isIdentStart(name[segment_start])) return false;
        var seg_idx = segment_start + 1;
        while (seg_idx < idx) : (seg_idx += 1) {
            if (!isIdentChar(name[seg_idx])) return false;
        }
        segment_start = idx + 1;
    }

    if (segment_start >= name.len) return false;
    if (!isIdentStart(name[segment_start])) return false;
    var seg_idx = segment_start + 1;
    while (seg_idx < name.len) : (seg_idx += 1) {
        if (!isIdentChar(name[seg_idx])) return false;
    }
    return true;
}

pub fn containsToken(tokens: []const []const u8, needle: []const u8) bool {
    for (tokens) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

pub fn startsWithWord(s: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, s, word)) return false;
    if (s.len == word.len) return true;
    const next = s[word.len];
    return std.ascii.isWhitespace(next) or next == '(' or next == '[' or next == ':' or next == '=' or next == '@' or next == '-';
}

pub fn parseTestModifierPrefix(body: []const u8) ?[]const u8 {
    var rest = std.mem.trimStart(u8, body, " \t");
    while (rest.len != 0 and rest[0] != '"') {
        const token_end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
        const token = rest[0..token_end];
        if (std.mem.eql(u8, token, "ignored") or std.mem.eql(u8, token, "should_panic")) {
            rest = std.mem.trimStart(u8, rest[token_end..], " \t");
            continue;
        }
        break;
    }
    return rest;
}

pub fn makeLine(kind: LineKind, raw: []const u8, trimmed: []const u8) ClassifiedLine {
    return .{
        .kind = kind,
        .raw = raw,
        .trimmed = trimmed,
    };
}

pub fn addPart(line: *ClassifiedLine, index: usize, value: []const u8) void {
    line.parts[index] = value;
    const count: u8 = @intCast(index + 1);
    if (line.part_count < count) line.part_count = count;
}

pub fn splitIndirectSigSuffix(rest: []const u8) struct { body: []const u8, sig: ?[]const u8 } {
    const open = std.mem.indexOfScalar(u8, rest, '(') orelse return .{ .body = rest, .sig = null };
    var depth: usize = 0;
    var in_string = false;
    var escape = false;
    for (rest[open..], 0..) |c, offset| {
        if (in_string) {
            if (escape) {
                escape = false;
                continue;
            }
            switch (c) {
                '\\' => escape = true,
                '"' => in_string = false,
                else => {},
            }
            continue;
        }
        switch (c) {
            '"' => in_string = true,
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) {
                    const close = open + offset;
                    const tail = std.mem.trim(u8, rest[close + 1 ..], " \t");
                    if (tail.len < 2 or tail[0] != ':') return .{ .body = rest, .sig = null };
                    const sig_text = std.mem.trim(u8, tail[1..], " \t");
                    if (sig_text.len == 0 or sig_text[0] != '(') return .{ .body = rest, .sig = null };
                    return .{ .body = std.mem.trimEnd(u8, rest[0 .. close + 1], " \t"), .sig = sig_text };
                }
            },
            else => {},
        }
    }
    return .{ .body = rest, .sig = null };
}

pub fn splitFirstWord(text: []const u8) struct { word: []const u8, rest: []const u8 } {
    var i: usize = 0;
    while (i < text.len and !std.ascii.isWhitespace(text[i])) : (i += 1) {}
    var j: usize = i;
    while (j < text.len and std.ascii.isWhitespace(text[j])) : (j += 1) {}
    return .{ .word = text[0..i], .rest = text[j..] };
}

pub fn splitAssignment(text: []const u8) ?struct { lhs: []const u8, rhs: []const u8 } {
    const eq = std.mem.indexOfScalar(u8, text, '=') orelse return null;
    if (eq + 1 < text.len and text[eq + 1] == '=') return null;
    if (eq > 0 and text[eq - 1] == '=') return null;
    return .{
        .lhs = text[0..eq],
        .rhs = text[eq + 1 ..],
    };
}

pub fn parseConstDecl(raw: []const u8, trimmed: []const u8) ?ClassifiedLine {
    if (!startsWithWord(trimmed, "@const")) return null;

    const after = std.mem.trimStart(u8, trimmed["@const".len..], " \t");
    const eq = std.mem.indexOfScalar(u8, after, '=') orelse return null;
    const name = std.mem.trim(u8, after[0..eq], " \t");
    const literal = std.mem.trim(u8, after[eq + 1 ..], " \t");
    if (name.len == 0 or literal.len == 0) return null;
    if (!isIdentStart(name[0])) return null;
    for (name[1..]) |c| {
        if (!isIdentChar(c)) return null;
    }

    var out = makeLine(.const_decl, raw, trimmed);
    addPart(&out, 0, name);
    addPart(&out, 1, literal);
    return out;
}

pub fn parseAddress(text: []const u8) ?struct { base: []const u8, offset: []const u8 } {
    const plus = std.mem.indexOfScalar(u8, text, '+') orelse return null;
    const base = std.mem.trim(u8, text[0..plus], " \t");
    const offset = std.mem.trim(u8, text[plus + 1 ..], " \t");
    if (base.len == 0 or offset.len == 0) return null;
    return .{ .base = base, .offset = offset };
}

pub fn parseCommaPair(text: []const u8) ?struct { left: []const u8, right: []const u8 } {
    const comma = std.mem.indexOfScalar(u8, text, ',') orelse return null;
    const left = std.mem.trim(u8, text[0..comma], " \t");
    const right = std.mem.trim(u8, text[comma + 1 ..], " \t");
    if (left.len == 0 or right.len == 0) return null;
    return .{ .left = left, .right = right };
}

pub fn parseCommaTriple(text: []const u8) ?struct { first: []const u8, second: []const u8, third: []const u8 } {
    const first_comma = std.mem.indexOfScalar(u8, text, ',') orelse return null;
    const first = std.mem.trim(u8, text[0..first_comma], " \t");
    const rest = std.mem.trimStart(u8, text[first_comma + 1 ..], " \t");
    const second_comma = std.mem.indexOfScalar(u8, rest, ',') orelse return null;
    const second = std.mem.trim(u8, rest[0..second_comma], " \t");
    const third = std.mem.trim(u8, rest[second_comma + 1 ..], " \t");
    if (first.len == 0 or second.len == 0 or third.len == 0) return null;
    return .{ .first = first, .second = second, .third = third };
}

pub const TypedSuffix = struct { body: []const u8, ty: []const u8 };

pub fn splitTrailingType(text: []const u8) ?TypedSuffix {
    const trimmed = std.mem.trim(u8, text, " \t");
    const idx = std.mem.lastIndexOf(u8, trimmed, " as ") orelse return null;
    const body = std.mem.trimEnd(u8, trimmed[0..idx], " \t");
    const ty = std.mem.trim(u8, trimmed[idx + 4 ..], " \t");
    if (body.len == 0 or ty.len == 0) return null;
    return .{ .body = body, .ty = ty };
}

pub fn splitPrimitiveTypedValue(text: []const u8) ?TypedSuffix {
    const suffix = splitTrailingType(text) orelse return null;
    if (common_signature.parsePrimType(suffix.ty)) |_| {
        const body = splitFirstWord(suffix.body);
        if (body.word.len != 0 and std.mem.trim(u8, body.rest, " \t").len == 0) return suffix;
    } else |_| {}
    return null;
}

pub fn collectNativeRegisterNames(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var names = std.array_list.Managed([]const u8).init(allocator);
    errdefer names.deinit();

    var idx: usize = 0;
    while (idx < text.len) {
        if (text[idx] == '"') {
            idx += 1;
            while (idx < text.len) : (idx += 1) {
                if (text[idx] == '\\' and idx + 1 < text.len) {
                    idx += 1;
                    continue;
                }
                if (text[idx] == '"') {
                    idx += 1;
                    break;
                }
            }
            continue;
        }

        if (!isIdentStart(text[idx])) {
            idx += 1;
            continue;
        }

        const prev = if (idx == 0) 0 else text[idx - 1];
        const start = idx;
        idx += 1;
        while (idx < text.len and isIdentChar(text[idx])) : (idx += 1) {}
        const token = text[start..idx];

        if (prev == '@' or prev == '%') continue;
        if (!containsToken(names.items, token)) {
            try names.append(token);
        }
    }

    return try names.toOwnedSlice();
}

pub fn parseFunctionHeader(
    raw: []const u8,
    trimmed: []const u8,
    prefix: []const u8,
    kind: LineKind,
    require_colon: bool,
) ?ClassifiedLine {
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;

    const body = if (require_colon) blk: {
        if (trimmed.len <= prefix.len or trimmed[trimmed.len - 1] != ':') return null;
        break :blk trimmed[prefix.len .. trimmed.len - 1];
    } else blk: {
        const body_raw = trimmed[prefix.len..];
        break :blk std.mem.trimEnd(u8, body_raw, ": \t\r");
    };

    const effective_body = if (kind == .test_decl) blk: {
        const modifiers_rest = parseTestModifierPrefix(body) orelse return null;
        break :blk modifiers_rest;
    } else body;

    const after_name = std.mem.trimStart(u8, effective_body, " \t");
    const open = std.mem.indexOfScalar(u8, after_name, '(') orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, after_name, ')') orelse return null;
    if (close < open) return null;

    const name_part = std.mem.trim(u8, after_name[0..open], " \t");
    if (name_part.len == 0) return null;

    // For @test functions, allow string literals as names
    const name = if (kind == .test_decl and name_part[0] == '"') blk: {
        const end_quote = std.mem.indexOfScalarPos(u8, name_part, 1, '"') orelse return null;
        break :blk name_part[0 .. end_quote + 1];
    } else blk: {
        if (!isIdentStart(name_part[0])) return null;
        for (name_part[1..]) |c| {
            if (!isIdentChar(c)) return null;
        }
        break :blk name_part;
    };

    const params = std.mem.trim(u8, after_name[open + 1 .. close], " \t");
    const tail = std.mem.trim(u8, after_name[close + 1 ..], " \t");

    var out = makeLine(kind, raw, trimmed);
    addPart(&out, 0, name);
    addPart(&out, 1, params);
    if (tail.len != 0) {
        if (!std.mem.startsWith(u8, tail, "->")) return null;
        addPart(&out, 2, std.mem.trim(u8, tail[2..], " \t"));
    }
    return out;
}

pub fn parseLocHint(raw: []const u8, trimmed: []const u8) ?ClassifiedLine {
    if (!std.mem.startsWith(u8, trimmed, "#loc")) return null;

    const after = std.mem.trimStart(u8, trimmed["#loc".len..], " \t");
    if (after.len < 6 or after[0] != '"') return null;

    const end_quote = std.mem.indexOfScalarPos(u8, after, 1, '"') orelse return null;
    const file = after[1..end_quote];
    const rest = std.mem.trimStart(u8, after[end_quote + 1 ..], " \t");
    if (rest.len < 2 or rest[0] != ':') return null;

    const after_file = rest[1..];
    const line_sep = std.mem.indexOfScalar(u8, after_file, ':') orelse return null;
    const line_text = std.mem.trim(u8, after_file[0..line_sep], " \t");
    const col_text = std.mem.trim(u8, after_file[line_sep + 1 ..], " \t");
    if (line_text.len == 0 or col_text.len == 0) return null;

    var out = makeLine(.loc_hint, raw, trimmed);
    addPart(&out, 0, file);
    addPart(&out, 1, line_text);
    addPart(&out, 2, col_text);
    return out;
}

pub fn parseImport(raw: []const u8, trimmed: []const u8) ?ClassifiedLine {
    if (!std.mem.startsWith(u8, trimmed, "@import")) return null;

    const after = std.mem.trimStart(u8, trimmed["@import".len..], " \t");
    if (after.len < 2 or after[0] != '"') return null;
    const end_quote = std.mem.indexOfScalarPos(u8, after, 1, '"') orelse return null;
    const path = after[1..end_quote];
    const rest = std.mem.trim(u8, after[end_quote + 1 ..], " \t\r");
    if (path.len == 0 or rest.len != 0) return null;

    var out = makeLine(.import_decl, raw, trimmed);
    addPart(&out, 0, path);
    return out;
}

pub fn parseNpmBind(raw: []const u8, trimmed: []const u8) ?ClassifiedLine {
    if (!startsWithWord(trimmed, "#npm_bind")) return null;

    const after = std.mem.trimStart(u8, trimmed["#npm_bind".len..], " \t");
    const first = splitFirstWord(after);
    if (first.word.len == 0 or first.rest.len == 0) return null;
    if (!isIdentStart(first.word[0])) return null;
    for (first.word[1..]) |c| {
        if (!isIdentChar(c)) return null;
    }
    const spec = std.mem.trim(u8, first.rest, " \t");
    if (spec.len < 2 or spec[0] != '"') return null;
    const end_quote = std.mem.indexOfScalarPos(u8, spec, 1, '"') orelse return null;
    const inner = spec[1..end_quote];
    const rest = std.mem.trim(u8, spec[end_quote + 1 ..], " \t\r");
    if (rest.len != 0) return null;
    // Binding shape is "<specifier>#<export>" with both sides non-empty;
    // split at the last '#' so scoped specifiers keep working.
    const hash = std.mem.lastIndexOfScalar(u8, inner, '#') orelse return null;
    if (hash == 0 or hash + 1 >= inner.len) return null;

    var out = makeLine(.npm_bind, raw, trimmed);
    addPart(&out, 0, first.word);
    addPart(&out, 1, inner);
    return out;
}
