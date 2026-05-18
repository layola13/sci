const std = @import("std");

pub const TranslateError = error{
    OutOfMemory,
    InvalidLlvm,
    UnsupportedLlvm,
};

const FunctionMode = enum {
    normal,
    ffi_wrapper,
    external,
};

const FunctionContext = struct {
    name: []const u8,
    kind: FunctionMode,
    sa_name: []const u8,
    rendered_header: bool = false,
};

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r");
}

const Translator = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    out: std.ArrayList(u8),
    current: ?FunctionContext = null,
    pending_labels: std.ArrayList([]const u8),
    emit_preamble: bool = true,

    fn init(allocator: std.mem.Allocator, input: []const u8) Translator {
        return .{
            .allocator = allocator,
            .input = input,
            .out = std.ArrayList(u8).init(allocator),
            .pending_labels = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Translator) void {
        self.pending_labels.deinit();
        self.out.deinit();
        self.* = undefined;
    }

    fn emitLine(self: *Translator, bytes: []const u8) !void {
        try self.out.appendSlice(bytes);
        try self.out.appendByte('\n');
    }

    fn emitFmt(self: *Translator, comptime fmt: []const u8, args: anytype) !void {
        try self.out.writer().print(fmt, args);
        try self.out.appendByte('\n');
    }

    fn startsWithWord(text: []const u8, word: []const u8) bool {
        if (!std.mem.startsWith(u8, text, word)) return false;
        if (text.len == word.len) return true;
        const next = text[word.len];
        return std.ascii.isWhitespace(next) or next == '(' or next == '[' or next == ':' or next == '=' or next == '@' or next == '-' or next == '.';
    }

    fn stripPrefix(text: []const u8, prefix: u8) []const u8 {
        if (text.len != 0 and text[0] == prefix) return text[1..];
        return text;
    }

    fn isIdentStart(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c == '_' or c == '.';
    }

    fn isIdentChar(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '$';
    }

    fn isLocalName(name: []const u8) bool {
        return name.len != 0 and name[0] == '%';
    }

    fn isGlobalName(name: []const u8) bool {
        return name.len != 0 and name[0] == '@';
    }

    fn sanitizeName(name: []const u8) ![]const u8 {
        if (name.len == 0) return TranslateError.InvalidLlvm;
        if (isLocalName(name) or isGlobalName(name)) return name;
        if (!isIdentStart(name[0])) return TranslateError.InvalidLlvm;
        for (name[1..]) |c| if (!isIdentChar(c)) return TranslateError.InvalidLlvm;
        return name;
    }

    fn parseTypeName(text: []const u8) []const u8 {
        const trimmed = trim(text);
        if (std.mem.eql(u8, trimmed, "void")) return "void";
        if (std.mem.eql(u8, trimmed, "ptr")) return "ptr";
        if (std.mem.eql(u8, trimmed, "i1")) return "i1";
        if (std.mem.eql(u8, trimmed, "i8")) return "i8";
        if (std.mem.eql(u8, trimmed, "i16")) return "i16";
        if (std.mem.eql(u8, trimmed, "i32")) return "i32";
        if (std.mem.eql(u8, trimmed, "i64")) return "i64";
        if (std.mem.eql(u8, trimmed, "u8")) return "u8";
        if (std.mem.eql(u8, trimmed, "u16")) return "u16";
        if (std.mem.eql(u8, trimmed, "u32")) return "u32";
        if (std.mem.eql(u8, trimmed, "u64")) return "u64";
        if (std.mem.eql(u8, trimmed, "f32")) return "f32";
        if (std.mem.eql(u8, trimmed, "f64")) return "f64";
        return trimmed;
    }

    fn splitCommaArgs(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
        const trimmed = trim(text);
        if (trimmed.len == 0) return try allocator.alloc([]const u8, 0);
        var list = std.ArrayList([]const u8).init(allocator);
        errdefer list.deinit();
        var start: usize = 0;
        var depth: usize = 0;
        var in_string = false;
        var escape = false;
        for (trimmed, 0..) |c, idx| {
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
                    if (depth > 0) depth -= 1;
                },
                ',' => if (depth == 0) {
                    try list.append(trim(trimmed[start..idx]));
                    start = idx + 1;
                },
                else => {},
            }
        }
        try list.append(trim(trimmed[start..]));
        return try list.toOwnedSlice();
    }

    fn splitFirstWord(text: []const u8) struct { word: []const u8, rest: []const u8 } {
        var i: usize = 0;
        while (i < text.len and !std.ascii.isWhitespace(text[i])) : (i += 1) {}
        var j: usize = i;
        while (j < text.len and std.ascii.isWhitespace(text[j])) : (j += 1) {}
        return .{ .word = text[0..i], .rest = text[j..] };
    }

    fn splitAssignment(text: []const u8) ?struct { lhs: []const u8, rhs: []const u8 } {
        const eq = std.mem.indexOfScalar(u8, text, '=') orelse return null;
        if (eq > 0 and text[eq - 1] == '=') return null;
        if (eq + 1 < text.len and text[eq + 1] == '=') return null;
        return .{ .lhs = text[0..eq], .rhs = text[eq + 1 ..] };
    }

    fn splitAddress(text: []const u8) !struct { base: []const u8, offset: []const u8 } {
        const plus = std.mem.lastIndexOfScalar(u8, text, '+') orelse return TranslateError.InvalidLlvm;
        const base = trim(text[0..plus]);
        const offset = trim(text[plus + 1 ..]);
        if (base.len == 0 or offset.len == 0) return TranslateError.InvalidLlvm;
        return .{ .base = stripPrefix(base, '%'), .offset = offset };
    }

    fn stripLabel(text: []const u8) []const u8 {
        var t = trim(text);
        if (std.mem.startsWith(u8, t, "label ")) t = trim(t["label".len..]);
        if (t.len != 0 and (t[0] == '%' or t[0] == '@')) t = t[1..];
        return t;
    }

    fn mapFunctionName(self: *Translator, name: []const u8, params: []const u8) ![]const u8 {
        _ = self;
        if (std.mem.eql(u8, name, "main") and trim(params).len == 0) return "saasm_main";
        return name;
    }

    fn parseFunctionHeader(self: *Translator, line: []const u8) !void {
        const trimmed = trim(line);
        if (!std.mem.startsWith(u8, trimmed, "define ")) return TranslateError.InvalidLlvm;
        const at = std.mem.indexOfScalar(u8, trimmed, '@') orelse return TranslateError.InvalidLlvm;
        const open = std.mem.indexOfScalar(u8, trimmed[at..], '(') orelse return TranslateError.InvalidLlvm;
        const close = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return TranslateError.InvalidLlvm;
        if (close <= at + open) return TranslateError.InvalidLlvm;
        const name = trimmed[at + 1 .. at + open];
        const params = trimmed[at + open + 1 .. close];
        const ret_ty = trim(trimmed["define".len..at]);
        const mapped = try self.mapFunctionName(name, params);
        const kind: FunctionMode = if (std.mem.eql(u8, name, "main") or std.mem.eql(u8, name, "saasm_main") or std.mem.eql(u8, name, "__sa_panic") or std.mem.eql(u8, name, "sys_print") or std.mem.eql(u8, name, "sys_exit") or std.mem.eql(u8, name, "sys_argc") or std.mem.eql(u8, name, "sys_argv") or std.mem.eql(u8, name, "sys_read_file") or std.mem.eql(u8, name, "sys_write_file") or std.mem.eql(u8, name, "fprintf") or std.mem.eql(u8, name, "exit") or std.mem.eql(u8, name, "malloc") or std.mem.eql(u8, name, "free") or std.mem.eql(u8, name, "memcpy") or std.mem.eql(u8, name, "fopen") or std.mem.eql(u8, name, "fseek") or std.mem.eql(u8, name, "ftell") or std.mem.eql(u8, name, "rewind") or std.mem.eql(u8, name, "fread") or std.mem.eql(u8, name, "fwrite") or std.mem.eql(u8, name, "fclose") or std.mem.eql(u8, name, "write") or std.mem.eql(u8, name, "getenv")) .ffi_wrapper else .normal;
        self.current = .{
            .name = try self.allocator.dupe(u8, name),
            .kind = kind,
            .sa_name = try self.allocator.dupe(u8, mapped),
        };
        try self.emitFunctionHeader(kind, mapped, params, ret_ty);
    }

    fn emitFunctionHeader(self: *Translator, kind: FunctionMode, name: []const u8, params: []const u8, ret_ty: []const u8) !void {
        switch (kind) {
            .normal => try self.out.appendByte('@'),
            .ffi_wrapper => try self.out.appendSlice("@ffi_wrapper "),
            .external => try self.out.appendSlice("@extern "),
        }
        try self.out.appendSlice(name);
        try self.out.appendByte('(');
        if (trim(params).len != 0) {
            const args = try splitCommaArgs(self.allocator, params);
            defer self.allocator.free(args);
            for (args, 0..) |arg, idx| {
                if (idx != 0) try self.out.appendSlice(", ");
                try self.out.appendSlice(try self.translateParam(arg));
            }
        }
        try self.out.appendByte(')');
        if (!std.mem.eql(u8, trim(ret_ty), "void")) {
            try self.out.appendSlice(" -> ");
            try self.out.appendSlice(try self.translateReturn(ret_ty));
        }
        try self.out.appendByte(':');
        try self.out.appendByte('\n');
        if (self.current) |*ctx| ctx.rendered_header = true;
    }

    fn translateParam(self: *Translator, arg: []const u8) ![]const u8 {
        const trimmed = trim(arg);
        if (trimmed.len == 0) return TranslateError.InvalidLlvm;
        const space = std.mem.lastIndexOfScalar(u8, trimmed, ' ') orelse return TranslateError.InvalidLlvm;
        const head = trim(trimmed[0..space]);
        const tail = trim(trimmed[space + 1 ..]);
        const colon = std.mem.indexOfScalar(u8, tail, ':') orelse return TranslateError.InvalidLlvm;
        const name = stripPrefix(trim(tail[0..colon]), '%');
        const ty = parseTypeName(tail[colon + 1 ..]);
        const cap = if (head.len != 0 and head[0] == '*') "*" else if (head.len != 0 and head[0] == '^') "^" else if (head.len != 0 and head[0] == '&') "&" else "";
        return try std.fmt.allocPrint(self.allocator, "{s}{s}: {s}", .{ cap, name, ty });
    }

    fn translateReturn(self: *Translator, ret_ty: []const u8) ![]const u8 {
        _ = self;
        return parseTypeName(ret_ty);
    }

    fn renderArgs(self: *Translator, args_text: []const u8) ![]const u8 {
        const args = try splitCommaArgs(self.allocator, args_text);
        defer self.allocator.free(args);
        var rendered = std.ArrayList(u8).init(self.allocator);
        errdefer rendered.deinit();
        for (args, 0..) |arg, idx| {
            if (idx != 0) try rendered.appendSlice(", ");
            try rendered.appendSlice(arg);
        }
        return try rendered.toOwnedSlice();
    }

    fn emitCall(self: *Translator, lhs: ?[]const u8, text: []const u8) !void {
        const trimmed = trim(text);
        if (!std.mem.startsWith(u8, trimmed, "call")) return TranslateError.InvalidLlvm;
        var rest = trim(trimmed["call".len..]);
        if (rest.len != 0 and rest[0] != '@') {
            const at = std.mem.indexOfScalar(u8, rest, '@') orelse return TranslateError.InvalidLlvm;
            rest = rest[at..];
        }
        const open = std.mem.indexOfScalar(u8, rest, '(') orelse return TranslateError.InvalidLlvm;
        const close = std.mem.lastIndexOfScalar(u8, rest, ')') orelse return TranslateError.InvalidLlvm;
        const callee = stripPrefix(trim(rest[0..open]), '@');
        const args_text = trim(rest[open + 1 .. close]);
        if (std.mem.eql(u8, callee, "fprintf")) return;
        const args = try self.renderArgs(args_text);
        defer self.allocator.free(args);

        if (std.mem.eql(u8, callee, "malloc")) {
            if (lhs) |name| try self.emitFmt("{s} = alloc {s}", .{ name, args }) else try self.emitFmt("alloc {s}", .{args});
            return;
        }
        if (std.mem.eql(u8, callee, "free")) {
            try self.emitFmt("!{s}", .{trim(args_text)});
            return;
        }
        if (std.mem.eql(u8, callee, "memcpy")) {
            const parts = try splitCommaArgs(self.allocator, args_text);
            defer self.allocator.free(parts);
            if (parts.len < 3) return TranslateError.InvalidLlvm;
            if (lhs) |name| try self.emitFmt("{s} = call @memcpy({s}, {s}, {s})", .{ name, parts[0], parts[1], parts[2] }) else try self.emitFmt("call @memcpy({s}, {s}, {s})", .{ parts[0], parts[1], parts[2] });
            return;
        }
        if (std.mem.eql(u8, callee, "exit")) {
            try self.emitFmt("call @sys_exit({s})", .{args});
            return;
        }
        if (std.mem.eql(u8, callee, "sa_print_bytes") or std.mem.eql(u8, callee, "sys_print") or std.mem.eql(u8, callee, "sys_exit") or std.mem.eql(u8, callee, "sys_argc") or std.mem.eql(u8, callee, "sys_argv") or std.mem.eql(u8, callee, "sys_read_file") or std.mem.eql(u8, callee, "sys_write_file")) {
            if (lhs) |name| try self.emitFmt("{s} = call @{s}({s})", .{ name, callee, args }) else try self.emitFmt("call @{s}({s})", .{ callee, args });
            return;
        }
        if (lhs) |name| try self.emitFmt("{s} = call @{s}({s})", .{ name, callee, args }) else try self.emitFmt("call @{s}({s})", .{ callee, args });
    }

    fn emitBranch(self: *Translator, trimmed: []const u8) !void {
        if (std.mem.startsWith(u8, trimmed, "br i1 ")) {
            const rest = trim(trimmed["br i1".len..]);
            const comma1 = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
            const cond = trim(rest[0..comma1]);
            const tail = trim(rest[comma1 + 1 ..]);
            const parts = try splitCommaArgs(self.allocator, tail);
            defer self.allocator.free(parts);
            if (parts.len < 2) return TranslateError.InvalidLlvm;
            try self.emitFmt("br {s} -> {s}, {s}", .{ cond, stripLabel(parts[0]), stripLabel(parts[1]) });
            return;
        }
        if (std.mem.startsWith(u8, trimmed, "br label ")) {
            const target = stripLabel(trim(trimmed["br label".len..]));
            try self.emitFmt("jmp {s}", .{target});
            return;
        }
        if (std.mem.startsWith(u8, trimmed, "br ")) {
            const rest = trim(trimmed["br".len..]);
            const arrow = std.mem.indexOf(u8, rest, "->") orelse return TranslateError.InvalidLlvm;
            const cond = trim(rest[0..arrow]);
            const parts = try splitCommaArgs(self.allocator, trim(rest[arrow + 2 ..]));
            defer self.allocator.free(parts);
            if (parts.len < 2) return TranslateError.InvalidLlvm;
            try self.emitFmt("br {s} -> {s}, {s}", .{ cond, stripLabel(parts[0]), stripLabel(parts[1]) });
            return;
        }
    }

    fn emitStore(self: *Translator, trimmed: []const u8) !void {
        const rest = trim(trimmed["store".len..]);
        const pair = std.mem.splitScalar(u8, rest, ',');
        var it = pair;
        const addr_text = it.next() orelse return TranslateError.InvalidLlvm;
        const value_text = it.next() orelse return TranslateError.InvalidLlvm;
        const addr = trim(addr_text);
        const value = trim(value_text);
        if (std.mem.indexOf(u8, addr, "getelementptr") != null) {
            try self.emitFmt("store {s}, {s}", .{ addr, value });
            return;
        }
        const parsed = try splitAddress(addr);
        try self.emitFmt("store {s}+{s}, {s}", .{ parsed.base, parsed.offset, value });
    }

    fn emitAssign(self: *Translator, lhs: []const u8, rhs: []const u8) !void {
        const op = splitFirstWord(rhs);
        if (std.mem.startsWith(u8, rhs, "load ")) {
            const body = trim(rhs["load".len..]);
            const suffix_idx = std.mem.lastIndexOf(u8, body, " as ");
            if (suffix_idx) |idx| {
                const source = trim(body[0..idx]);
                const ty = parseTypeName(body[idx + 4 ..]);
                try self.emitFmt("{s} = load {s} as {s}", .{ stripPrefix(lhs, '%'), source, ty });
            } else {
                try self.emitFmt("{s} = load {s}", .{ stripPrefix(lhs, '%'), body });
            }
            return;
        }
        if (std.mem.startsWith(u8, rhs, "call ")) {
            try self.emitCall(stripPrefix(lhs, '%'), rhs);
            return;
        }
        if (std.mem.startsWith(u8, rhs, "icmp ")) {
            const cmp = op.word;
            const rest = trim(op.rest);
            const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
            const left = trim(rest[0..comma]);
            const right = trim(rest[comma + 1 ..]);
            const kind = if (std.mem.endsWith(u8, cmp, "eq")) "eq" else if (std.mem.endsWith(u8, cmp, "ne")) "ne" else if (std.mem.endsWith(u8, cmp, "slt")) "slt" else if (std.mem.endsWith(u8, cmp, "sle")) "sle" else if (std.mem.endsWith(u8, cmp, "sgt")) "sgt" else if (std.mem.endsWith(u8, cmp, "sge")) "sge" else if (std.mem.endsWith(u8, cmp, "ult")) "ult" else if (std.mem.endsWith(u8, cmp, "ule")) "ule" else if (std.mem.endsWith(u8, cmp, "ugt")) "ugt" else if (std.mem.endsWith(u8, cmp, "uge")) "uge" else return TranslateError.UnsupportedLlvm;
            try self.emitFmt("{s} = {s} {s}, {s}", .{ stripPrefix(lhs, '%'), kind, left, right });
            return;
        }
        const kind = op.word;
        if (std.mem.eql(u8, kind, "add") or std.mem.eql(u8, kind, "sub") or std.mem.eql(u8, kind, "mul") or std.mem.eql(u8, kind, "sdiv") or std.mem.eql(u8, kind, "udiv") or std.mem.eql(u8, kind, "srem") or std.mem.eql(u8, kind, "urem") or std.mem.eql(u8, kind, "and") or std.mem.eql(u8, kind, "or") or std.mem.eql(u8, kind, "xor") or std.mem.eql(u8, kind, "shl") or std.mem.eql(u8, kind, "lshr") or std.mem.eql(u8, kind, "ashr") or std.mem.eql(u8, kind, "fadd") or std.mem.eql(u8, kind, "fsub") or std.mem.eql(u8, kind, "fmul") or std.mem.eql(u8, kind, "fdiv")) {
            const rest = trim(op.rest);
            const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
            const left = trim(rest[0..comma]);
            const right = trim(rest[comma + 1 ..]);
            try self.emitFmt("{s} = {s} {s}, {s}", .{ stripPrefix(lhs, '%'), kind, left, right });
            return;
        }
        if (std.mem.eql(u8, kind, "trunc") or std.mem.eql(u8, kind, "zext") or std.mem.eql(u8, kind, "sext") or std.mem.eql(u8, kind, "fptosi") or std.mem.eql(u8, kind, "sitofp") or std.mem.eql(u8, kind, "uitofp") or std.mem.eql(u8, kind, "fptrunc") or std.mem.eql(u8, kind, "fpext") or std.mem.eql(u8, kind, "bitcast")) {
            const rest = trim(op.rest);
            const to_pos = std.mem.lastIndexOf(u8, rest, " to ") orelse return TranslateError.UnsupportedLlvm;
            const value = trim(rest[0..to_pos]);
            const ty = parseTypeName(rest[to_pos + 4 ..]);
            try self.emitFmt("{s} = {s} {s} as {s}", .{ stripPrefix(lhs, '%'), kind, value, ty });
            return;
        }
        if (std.mem.eql(u8, kind, "getelementptr")) {
            const rest = trim(op.rest);
            const first_comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
            const second_comma = std.mem.indexOfScalar(u8, rest[first_comma + 1 ..], ',') orelse return TranslateError.InvalidLlvm;
            const base = trim(rest[first_comma + 1 .. first_comma + 1 + second_comma]);
            const offset = trim(rest[first_comma + 1 + second_comma + 1 ..]);
            try self.emitFmt("{s} = ptr_add {s}, {s}", .{ stripPrefix(lhs, '%'), stripPrefix(base, '@'), stripPrefix(offset, '%') });
            return;
        }
        if (std.mem.eql(u8, kind, "phi")) {
            const rest = trim(op.rest);
            const comma_entries = try splitCommaArgs(self.allocator, rest);
            defer self.allocator.free(comma_entries);
            if (comma_entries.len == 0) return TranslateError.UnsupportedLlvm;
            const first = comma_entries[0];
            const lb = std.mem.indexOfScalar(u8, first, '[') orelse return TranslateError.UnsupportedLlvm;
            const rb = std.mem.indexOfScalarPos(u8, first, lb, ']') orelse return TranslateError.UnsupportedLlvm;
            const val = trim(first[lb + 1 .. rb]);
            try self.pending_labels.append(try self.allocator.dupe(u8, stripPrefix(val, '%')));
            try self.emitFmt("{s} = {s}", .{ stripPrefix(lhs, '%'), val });
            return;
        }
        if (std.mem.eql(u8, kind, "alloca")) {
            const rest = trim(op.rest);
            const count = if (std.mem.indexOf(u8, rest, ",")) |idx| trim(rest[idx + 1 ..]) else "1";
            try self.emitFmt("{s} = stack_alloc {s}", .{ stripPrefix(lhs, '%'), count });
            return;
        }
        if (std.mem.eql(u8, kind, "unreachable")) {
            try self.emitLine("panic(102)");
            return;
        }
        return TranslateError.UnsupportedLlvm;
    }

    fn emitInstruction(self: *Translator, line: []const u8) !void {
        const trimmed = trim(line);
        if (trimmed.len == 0) return;
        if (trimmed[0] == ';') return;
        if (trimmed.len > 1 and trimmed[0] == '/' and trimmed[1] == '/') return;
        if (std.mem.startsWith(u8, trimmed, "declare ")) return;
        if (std.mem.startsWith(u8, trimmed, "source_filename")) return;
        if (std.mem.startsWith(u8, trimmed, "target ")) return;
        if (std.mem.startsWith(u8, trimmed, "attributes ")) return;
        if (std.mem.startsWith(u8, trimmed, "!")) return;
        if (std.mem.endsWith(u8, trimmed, ":")) {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s}:", .{stripLabel(trimmed[0 .. trimmed.len - 1])}));
            return;
        }
        if (std.mem.startsWith(u8, trimmed, "br ")) {
            try self.emitBranch(trimmed);
            return;
        }
        if (std.mem.startsWith(u8, trimmed, "store ")) {
            try self.emitStore(trimmed);
            return;
        }
        if (std.mem.startsWith(u8, trimmed, "ret ")) {
            const rest = trim(trimmed["ret".len..]);
            if (std.mem.eql(u8, rest, "void")) {
                try self.emitLine("return");
                return;
            }
            const parts = splitFirstWord(rest);
            _ = parts;
            try self.emitFmt("return {s}", .{rest});
            return;
        }
        if (std.mem.eql(u8, trimmed, "unreachable")) {
            try self.emitLine("panic(102)");
            return;
        }
        if (splitAssignment(trimmed)) |assign| {
            try self.emitAssign(trim(assign.lhs), trim(assign.rhs));
            return;
        }
        return TranslateError.UnsupportedLlvm;
    }
};

pub fn translateAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var translator = Translator.init(allocator, input);
    defer translator.deinit();

    try translator.emitLine("@ffi_wrapper __sa_panic(*code: ptr, *msg: ptr, len: u64) -> void:");
    try translator.emitLine("L_ENTRY:");
    try translator.emitLine("    panic(102)");
    try translator.emitLine("");

    const lines = try std.mem.splitScalar(u8, input, '\n');
    _ = lines;
    var all_lines = std.ArrayList([]const u8).init(allocator);
    defer all_lines.deinit();
    var iter = std.mem.splitScalar(u8, input, '\n');
    while (iter.next()) |line| {
        try all_lines.append(line);
    }

    var saw_io_iface = false;
    for (all_lines.items) |line| {
        const trimmed = trim(line);
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "@import ")) {
            try translator.emitLine(trimmed);
            if (std.mem.containsAtLeast(u8, trimmed, 1, "io/print.saasm-iface") or std.mem.containsAtLeast(u8, trimmed, 1, "io.saasm-iface") or std.mem.containsAtLeast(u8, trimmed, 1, "sa_std/io.saasm-iface")) {
                saw_io_iface = true;
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "@const ")) {
            try translator.emitLine(trimmed);
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "declare ")) {
            const declare = trim(trimmed["declare".len..]);
            if (std.mem.startsWith(u8, declare, "i32 @fprintf")) continue;
            if (std.mem.startsWith(u8, declare, "ptr @getenv")) continue;
            if (std.mem.startsWith(u8, declare, "void @exit")) continue;
            if (std.mem.startsWith(u8, declare, "ptr @malloc")) continue;
            if (std.mem.startsWith(u8, declare, "void @free")) continue;
            if (std.mem.startsWith(u8, declare, "ptr @memcpy")) continue;
            if (std.mem.startsWith(u8, declare, "ptr @fopen")) continue;
            if (std.mem.startsWith(u8, declare, "i32 @fseek")) continue;
            if (std.mem.startsWith(u8, declare, "i64 @ftell")) continue;
            if (std.mem.startsWith(u8, declare, "void @rewind")) continue;
            if (std.mem.startsWith(u8, declare, "i32 @fread")) continue;
            if (std.mem.startsWith(u8, declare, "i32 @fwrite")) continue;
            if (std.mem.startsWith(u8, declare, "i32 @fclose")) continue;
            if (std.mem.startsWith(u8, declare, "i32 @write")) continue;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "define ")) {
            try translator.parseFunctionHeader(trimmed);
            continue;
        }
        if (std.mem.eql(u8, trimmed, "entry:")) {
            try translator.emitLine("L_ENTRY:");
            continue;
        }
        try translator.emitInstruction(trimmed);
    }

    if (!saw_io_iface) {
        // Legacy hello-world compat: the probe IR expects sa_print_bytes to exist.
        try translator.out.insertSlice(0, "@import \"sa_std/io.saasm-iface\"\n");
    }

    return try translator.out.toOwnedSlice();
}

pub fn translateFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(bytes);
    return try translateAlloc(allocator, bytes);
}

test "translator module imports" {
    _ = translateAlloc;
    _ = translateFile;
}
