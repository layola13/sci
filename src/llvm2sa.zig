const std = @import("std");

pub const TranslateError = error{
    OutOfMemory,
    InvalidLlvm,
    UnsupportedLlvm,
};

const FunctionMode = enum {
    normal,
    ffi_wrapper,
};

const ValueKind = enum {
    none,
    reg,
    global,
    constant,
    label,
    text,
};

const Value = struct {
    kind: ValueKind = .none,
    text: []const u8 = "",
};

const FunctionContext = struct {
    name: []const u8,
    sa_name: []const u8,
    mode: FunctionMode,
    return_ty: []const u8,
    is_entrypoint: bool = false,
};

const Translator = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    out: std.ArrayList(u8),
    pos: usize = 0,
    current: ?FunctionContext = null,
    pending_phi: std.StringHashMap([]const u8),
    pending_br: ?struct {
        cond: []const u8,
        t_label: []const u8,
        f_label: []const u8,
    } = null,
    label_fresh_id: u32 = 0,
    saw_main: bool = false,

    fn init(allocator: std.mem.Allocator, input: []const u8) Translator {
        return .{
            .allocator = allocator,
            .input = input,
            .out = std.ArrayList(u8).init(allocator),
            .pending_phi = std.StringHashMap([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Translator) void {
        self.pending_phi.deinit();
        self.out.deinit();
        self.* = undefined;
    }

    fn emitLine(self: *Translator, bytes: []const u8) !void {
        try self.out.appendSlice(bytes);
        try self.out.appendByte('\n');
    }

    fn trim(text: []const u8) []const u8 {
        return std.mem.trim(u8, text, " \t\r");
    }

    fn startsWithWord(text: []const u8, word: []const u8) bool {
        if (!std.mem.startsWith(u8, text, word)) return false;
        if (text.len == word.len) return true;
        const next = text[word.len];
        return std.ascii.isWhitespace(next) or next == '(' or next == '[' or next == ':' or next == '=' or next == '@' or next == '-' or next == '.';
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

    fn stripPercent(name: []const u8) []const u8 {
        if (name.len != 0 and name[0] == '%') return name[1..];
        return name;
    }

    fn stripAt(name: []const u8) []const u8 {
        if (name.len != 0 and name[0] == '@') return name[1..];
        return name;
    }

    fn nextLabelId(self: *Translator) u32 {
        const id = self.label_fresh_id;
        self.label_fresh_id += 1;
        return id;
    }

    fn mapMainName(name: []const u8, params_len: usize) []const u8 {
        if (std.mem.eql(u8, name, "main") and params_len == 0) return "saasm_main";
        return name;
    }

    fn sanitizeName(self: *Translator, name: []const u8) ![]const u8 {
        if (name.len == 0) return TranslateError.InvalidLlvm;
        if (isLocalName(name) or isGlobalName(name)) return name;
        if (isIdentStart(name[0])) {
            for (name[1..]) |c| {
                if (!isIdentChar(c)) return TranslateError.InvalidLlvm;
            }
            return name;
        }
        return TranslateError.InvalidLlvm;
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

    fn isIntegerLiteral(text: []const u8) bool {
        if (text.len == 0) return false;
        var start: usize = 0;
        if (text[0] == '-' or text[0] == '+') start = 1;
        if (start >= text.len) return false;
        for (text[start..]) |c| {
            if (!std.ascii.isDigit(c)) return false;
        }
        return true;
    }

    fn isFloatLiteral(text: []const u8) bool {
        return std.mem.indexOfScalar(u8, text, '.') != null or std.mem.indexOfScalar(u8, text, 'e') != null or std.mem.indexOfScalar(u8, text, 'E') != null;
    }

    fn isConstantToken(text: []const u8) bool {
        const trimmed = trim(text);
        if (trimmed.len == 0) return false;
        if (isIntegerLiteral(trimmed)) return true;
        if (isFloatLiteral(trimmed)) return true;
        if (std.mem.eql(u8, trimmed, "null")) return true;
        if (trimmed[0] == '@' or trimmed[0] == '%') return true;
        return false;
    }

    fn splitCommaArgs(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
        const trimmed = trim(text);
        if (trimmed.len == 0) return try allocator.alloc([]const u8, 0);
        var items = std.ArrayList([]const u8).init(allocator);
        errdefer items.deinit();
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
                ')' => if (depth > 0) depth -= 1,
                ',' => if (depth == 0) {
                    try items.append(trim(trimmed[start..idx]));
                    start = idx + 1;
                },
                else => {},
            }
        }
        try items.append(trim(trimmed[start..]));
        return try items.toOwnedSlice();
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
        if (eq + 1 < text.len and text[eq + 1] == '=') return null;
        if (eq > 0 and text[eq - 1] == '=') return null;
        return .{ .lhs = text[0..eq], .rhs = text[eq + 1 ..] };
    }

    fn parseValueToken(self: *Translator, text: []const u8) !Value {
        const trimmed = trim(text);
        if (trimmed.len == 0) return .{};
        if (trimmed[0] == '%') return .{ .kind = .reg, .text = trimmed[1..] };
        if (trimmed[0] == '@') return .{ .kind = .global, .text = stripAt(trimmed) };
        if (std.mem.eql(u8, trimmed, "null") or isConstantToken(trimmed)) return .{ .kind = .constant, .text = trimmed };
        if (trimmed[0] == '"') return .{ .kind = .constant, .text = trimmed };
        if (std.mem.eql(u8, trimmed, "true") or std.mem.eql(u8, trimmed, "false")) return .{ .kind = .constant, .text = trimmed };
        return .{ .kind = .text, .text = trimmed };
    }

    fn emitGlobals(self: *Translator, lines: []const []const u8) !void {
        for (lines) |line| {
            const trimmed = trim(line);
            if (!startsWithWord(trimmed, "@")) continue;
            if (startsWithWord(trimmed, "@saasm_argc")) continue;
            if (startsWithWord(trimmed, "@saasm_argv")) continue;
            if (startsWithWord(trimmed, "@stderr")) continue;
            if (startsWithWord(trimmed, "@.panic_code_fmt")) continue;
            if (startsWithWord(trimmed, "@.panic_msg_fmt")) continue;
            if (startsWithWord(trimmed, "declare")) continue;

            if (std.mem.startsWith(u8, trimmed, "@const ")) {
                try self.emitConst(trimmed);
                continue;
            }

            if (std.mem.startsWith(u8, trimmed, "@")) {
                try self.emitLine(trimmed);
            }
        }
    }

    fn emitConst(self: *Translator, line: []const u8) !void {
        const body = trim(line["@const".len..]);
        const eq = std.mem.indexOfScalar(u8, body, '=') orelse return TranslateError.InvalidLlvm;
        const name = trim(body[0..eq]);
        const literal = trim(body[eq + 1 ..]);
        if (name.len == 0 or literal.len == 0) return TranslateError.InvalidLlvm;
        if (std.mem.startsWith(u8, literal, "utf8:")) {
            const bytes = literal["utf8:".len..];
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "@const {s} = {s}", .{ name, literal }));
            _ = bytes;
            return;
        }
        if (std.mem.startsWith(u8, literal, "hex:")) {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "@const {s} = {s}", .{ name, literal }));
            return;
        }
        if (std.mem.startsWith(u8, literal, "repeat:")) {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "@const {s} = {s}", .{ name, literal }));
            return;
        }
        if (std.mem.startsWith(u8, literal, "struct ") or std.mem.startsWith(u8, literal, "vtable ")) {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "@const {s} = {s}", .{ name, literal }));
            return;
        }
        return TranslateError.UnsupportedLlvm;
    }

    fn emitFunctionHeader(self: *Translator, line: []const u8) !void {
        const trimmed = trim(line);
        if (!std.mem.startsWith(u8, trimmed, "define ")) return TranslateError.InvalidLlvm;
        const at = std.mem.indexOfScalar(u8, trimmed, '@') orelse return TranslateError.InvalidLlvm;
        const open = std.mem.indexOfScalar(u8, trimmed[at..], '(') orelse return TranslateError.InvalidLlvm;
        const close = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return TranslateError.InvalidLlvm;
        const sig_head = trimmed[0..at];
        const name = trimmed[at + 1 .. at + open];
        const params = trimmed[at + open + 1 .. close];
        const ret_ty = trim(sig_head["define".len..]);
        const sa_name = mapMainName(name, if (trim(params).len == 0) 0 else 1);
        const mode: FunctionMode = if (std.mem.eql(u8, name, "main") or std.mem.eql(u8, name, "__sa_panic") or std.mem.eql(u8, name, "saasm_main") or std.mem.eql(u8, name, "sys_print") or std.mem.eql(u8, name, "sys_exit") or std.mem.eql(u8, name, "sys_argc") or std.mem.eql(u8, name, "sys_argv") or std.mem.eql(u8, name, "sys_read_file") or std.mem.eql(u8, name, "sys_write_file")) .ffi_wrapper else .normal;
        self.current = .{
            .name = try self.allocator.dupe(u8, name),
            .sa_name = try self.allocator.dupe(u8, sa_name),
            .mode = mode,
            .return_ty = try self.allocator.dupe(u8, ret_ty),
            .is_entrypoint = std.mem.eql(u8, name, "main"),
        };
        try self.emitLine(try std.fmt.allocPrint(self.allocator, "@{s}({s}) -> {s}:", .{ sa_name, self.translateParams(params) catch "" , self.translateReturn(ret_ty) catch "void" }));
    }

    fn translateParams(self: *Translator, params: []const u8) ![]const u8 {
        const trimmed = trim(params);
        if (trimmed.len == 0) return try self.allocator.dupe(u8, "");
        var out = std.ArrayList(u8).init(self.allocator);
        errdefer out.deinit();
        const args = try splitCommaArgs(self.allocator, trimmed);
        defer self.allocator.free(args);
        for (args, 0..) |arg, idx| {
            if (idx != 0) try out.appendSlice(", ");
            const parsed = try self.translateParam(arg);
            try out.appendSlice(parsed);
        }
        return try out.toOwnedSlice();
    }

    fn translateParam(self: *Translator, arg: []const u8) ![]const u8 {
        const trimmed = trim(arg);
        if (trimmed.len == 0) return TranslateError.InvalidLlvm;
        const space = std.mem.lastIndexOfScalar(u8, trimmed, ' ') orelse return TranslateError.InvalidLlvm;
        const head = trim(trimmed[0..space]);
        const tail = trim(trimmed[space + 1 ..]);
        _ = head;
        const colon = std.mem.indexOfScalar(u8, tail, ':') orelse return TranslateError.InvalidLlvm;
        const name = stripPercent(trim(tail[0..colon]));
        const ty = parseTypeName(tail[colon + 1 ..]);
        const cap = if (head.len != 0 and head[0] == '*') "*" else if (head.len != 0 and head[0] == '^') "^" else if (head.len != 0 and head[0] == '&') "&" else "";
        return try std.fmt.allocPrint(self.allocator, "{s}{s}: {s}", .{ cap, name, ty });
    }

    fn translateReturn(self: *Translator, ret_ty: []const u8) ![]const u8 {
        return try self.allocator.dupe(u8, parseTypeName(ret_ty));
    }

    fn emitCall(self: *Translator, lhs: ?[]const u8, text: []const u8) !void {
        const trimmed = trim(text);
        if (trimmed.len == 0) return TranslateError.InvalidLlvm;
        if (!std.mem.startsWith(u8, trimmed, "call")) return TranslateError.InvalidLlvm;

        const call_pos = std.mem.indexOf(u8, trimmed, "call") orelse return TranslateError.InvalidLlvm;
        var rest = trim(trimmed[call_pos + 4 ..]);

        // handle typed call prefix like "i32 (ptr, ptr, ...) @fprintf(...)".
        if (rest.len != 0 and rest[0] != '@') {
            const at = std.mem.indexOfScalar(u8, rest, '@') orelse return TranslateError.InvalidLlvm;
            rest = rest[at..];
        }

        const open = std.mem.indexOfScalar(u8, rest, '(') orelse return TranslateError.InvalidLlvm;
        const close = std.mem.lastIndexOfScalar(u8, rest, ')') orelse return TranslateError.InvalidLlvm;
        const callee = stripAt(trim(rest[0..open]));
        const args_text = trim(rest[open + 1 .. close]);

        if (std.mem.eql(u8, callee, "fprintf")) {
            // Drop all fprintf calls in translated SA; panic helper is rewritten around them.
            return;
        }

        if (std.mem.eql(u8, callee, "exit")) {
            if (lhs) |_| {}
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "call @sys_exit({s})", .{ args_text }));
            return;
        }

        const lhs_text = if (lhs) |name| try std.fmt.allocPrint(self.allocator, "{s} = ", .{name}) else "";
        defer if (lhs_text.len != 0) self.allocator.free(lhs_text);

        if (std.mem.eql(u8, callee, "malloc")) {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s}alloc {s}", .{ lhs_text, args_text }));
            return;
        }
        if (std.mem.eql(u8, callee, "free")) {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "!{s}", .{ trim(args_text) }));
            return;
        }
        if (std.mem.eql(u8, callee, "memcpy")) {
            const parts = try splitCommaArgs(self.allocator, args_text);
            defer self.allocator.free(parts);
            if (parts.len < 3) return TranslateError.InvalidLlvm;
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "call @sa_mem_copy({s}, {s}, {s})", .{ parts[0], parts[1], parts[2] }));
            return;
        }
        if (std.mem.eql(u8, callee, "sa_print_bytes") or std.mem.eql(u8, callee, "sys_print") or std.mem.eql(u8, callee, "sys_exit") or std.mem.eql(u8, callee, "sys_argc") or std.mem.eql(u8, callee, "sys_argv") or std.mem.eql(u8, callee, "sys_read_file") or std.mem.eql(u8, callee, "sys_write_file")) {
            const args = try splitCommaArgs(self.allocator, args_text);
            defer self.allocator.free(args);
            var rendered = std.ArrayList(u8).init(self.allocator);
            defer rendered.deinit();
            for (args, 0..) |arg, idx| {
                if (idx != 0) try rendered.appendSlice(", ");
                try rendered.appendSlice(arg);
            }
            if (lhs) |name| {
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = call @{s}({s})", .{ name, callee, rendered.items }));
            } else {
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "call @{s}({s})", .{ callee, rendered.items }));
            }
            return;
        }

        if (lhs) |name| {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = call @{s}({s})", .{ name, callee, args_text }));
        } else {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "call @{s}({s})", .{ callee, args_text }));
        }
    }

    fn emitInstruction(self: *Translator, line: []const u8, prev_labels: *std.StringHashMap(bool)) !void {
        const trimmed = trim(line);
        if (trimmed.len == 0) return;
        if (trimmed[0] == ';') return;
        if (trimmed.len > 1 and trimmed[0] == '/' and trimmed[1] == '/') return;
        if (std.mem.startsWith(u8, trimmed, "declare ")) return;
        if (std.mem.startsWith(u8, trimmed, "source_filename")) return;
        if (std.mem.startsWith(u8, trimmed, "target ")) return;
        if (std.mem.startsWith(u8, trimmed, "attributes ")) return;
        if (std.mem.startsWith(u8, trimmed, "!" )) return;

        if (std.mem.endsWith(u8, trimmed, ":")) {
            const label = trim(trimmed[0 .. trimmed.len - 1]);
            if (label.len == 0) return TranslateError.InvalidLlvm;
            if (self.pending_br) |br| {
                _ = br;
                self.pending_br = null;
            }
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s}:", .{ stripPercent(label) }));
            if (try prev_labels.contains(stripPercent(label))) {
                // no-op
            } else {
                try prev_labels.put(try self.allocator.dupe(u8, stripPercent(label)), true);
            }
            return;
        }

        if (std.mem.startsWith(u8, trimmed, "%") or std.mem.startsWith(u8, trimmed, "@" )) {
            if (std.mem.startsWith(u8, trimmed, "ret ")) {
                const rest = trim(trimmed["ret".len..]);
                if (std.mem.eql(u8, rest, "void")) {
                    try self.emitLine("return");
                    return;
                }
                const val = trim(rest);
                const parts = splitFirstWord(val);
                _ = parts;
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "return {s}", .{ val }));
                return;
            }
        }

        if (std.mem.startsWith(u8, trimmed, "br ")) {
            if (std.mem.startsWith(u8, trimmed, "br i1 ")) {
                const rest = trim(trimmed["br i1".len..]);
                const comma1 = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
                const cond = trim(rest[0..comma1]);
                const tail = trim(rest[comma1 + 1 ..]);
                const label_parts = try splitCommaArgs(self.allocator, tail);
                defer self.allocator.free(label_parts);
                if (label_parts.len < 2) return TranslateError.InvalidLlvm;
                const t = stripLabelKeyword(label_parts[0]);
                const f = stripLabelKeyword(label_parts[1]);
                self.pending_br = .{ .cond = cond, .t_label = t, .f_label = f };
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "br {s} -> {s}, {s}", .{ cond, t, f }));
                return;
            }
            if (std.mem.startsWith(u8, trimmed, "br label ")) {
                const target = stripLabelKeyword(trim(trimmed["br label".len..]));
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "jmp {s}", .{ target }));
                return;
            }
        }

        if (std.mem.startsWith(u8, trimmed, "store ")) {
            const rest = trim(trimmed["store".len..]);
            const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
            const value_part = trim(rest[comma + 1 ..]);
            const addr_part = trim(rest[0..comma]);
            const ptr_plus = std.mem.indexOf(u8, addr_part, "getelementptr") != null;
            if (ptr_plus) {
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "store {s}, {s}", .{ addr_part, value_part }));
            } else {
                const pair = try splitStoreAddress(addr_part);
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "store {s}+{s}, {s}", .{ pair.base, pair.offset, value_part }));
            }
            return;
        }

        if (std.mem.startsWith(u8, trimmed, "%") and std.mem.indexOfScalar(u8, trimmed, '=') != null) {
            const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse return TranslateError.InvalidLlvm;
            const lhs = trim(trimmed[0..eq]);
            const rhs = trim(trimmed[eq + 1 ..]);

            if (std.mem.startsWith(u8, rhs, "load ")) {
                const load_body = trim(rhs["load".len..]);
                const as_pos = std.mem.lastIndexOf(u8, load_body, " as ");
                var source = load_body;
                var ty: []const u8 = "i64";
                if (as_pos) |idx| {
                    source = trim(load_body[0..idx]);
                    ty = parseTypeName(load_body[idx + 4 ..]);
                }
                if (std.mem.startsWith(u8, source, "ptr ")) {
                    source = trim(source["ptr".len..]);
                }
                if (std.mem.indexOfScalar(u8, source, ',') != null) {
                    try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = load {s}", .{ stripPercent(lhs), source }));
                } else {
                    try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = load {s} as {s}", .{ stripPercent(lhs), source, ty }));
                }
                return;
            }

            if (std.mem.startsWith(u8, rhs, "call ")) {
                try self.emitCall(stripPercent(lhs), rhs);
                return;
            }

            if (std.mem.startsWith(u8, rhs, "icmp ")) {
                const parts = splitFirstWord(rhs);
                const cmp_kind = parts.word;
                const rest = trim(parts.rest);
                const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
                const left = trim(rest[0..comma]);
                const right = trim(rest[comma + 1 ..]);
                const op = if (std.mem.endsWith(u8, cmp_kind, "eq")) "eq" else if (std.mem.endsWith(u8, cmp_kind, "ne")) "ne" else if (std.mem.endsWith(u8, cmp_kind, "slt")) "slt" else if (std.mem.endsWith(u8, cmp_kind, "sle")) "sle" else if (std.mem.endsWith(u8, cmp_kind, "sgt")) "sgt" else if (std.mem.endsWith(u8, cmp_kind, "sge")) "sge" else if (std.mem.endsWith(u8, cmp_kind, "ult")) "ult" else if (std.mem.endsWith(u8, cmp_kind, "ule")) "ule" else if (std.mem.endsWith(u8, cmp_kind, "ugt")) "ugt" else if (std.mem.endsWith(u8, cmp_kind, "uge")) "uge" else return TranslateError.UnsupportedLlvm;
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = {s} {s}, {s}", .{ stripPercent(lhs), op, left, right }));
                return;
            }

            const op_parts = splitFirstWord(rhs);
            if (std.mem.eql(u8, op_parts.word, "add") or std.mem.eql(u8, op_parts.word, "sub") or std.mem.eql(u8, op_parts.word, "mul") or std.mem.eql(u8, op_parts.word, "sdiv") or std.mem.eql(u8, op_parts.word, "udiv") or std.mem.eql(u8, op_parts.word, "srem") or std.mem.eql(u8, op_parts.word, "urem") or std.mem.eql(u8, op_parts.word, "and") or std.mem.eql(u8, op_parts.word, "or") or std.mem.eql(u8, op_parts.word, "xor") or std.mem.eql(u8, op_parts.word, "shl") or std.mem.eql(u8, op_parts.word, "lshr") or std.mem.eql(u8, op_parts.word, "ashr")) {
                const rest = trim(op_parts.rest);
                const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
                const left = trim(rest[0..comma]);
                const right = trim(rest[comma + 1 ..]);
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = {s} {s}, {s}", .{ stripPercent(lhs), op_parts.word, left, right }));
                return;
            }

            if (std.mem.eql(u8, op_parts.word, "trunc") or std.mem.eql(u8, op_parts.word, "zext") or std.mem.eql(u8, op_parts.word, "sext") or std.mem.eql(u8, op_parts.word, "fptosi") or std.mem.eql(u8, op_parts.word, "sitofp") or std.mem.eql(u8, op_parts.word, "uitofp") or std.mem.eql(u8, op_parts.word, "fptrunc") or std.mem.eql(u8, op_parts.word, "fpext") or std.mem.eql(u8, op_parts.word, "bitcast")) {
                const rest = trim(op_parts.rest);
                const to_pos = std.mem.lastIndexOf(u8, rest, " to ") orelse return TranslateError.UnsupportedLlvm;
                const value = trim(rest[0..to_pos]);
                const ty = parseTypeName(rest[to_pos + 4 ..]);
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = {s} {s} as {s}", .{ stripPercent(lhs), op_parts.word, value, ty }));
                return;
            }

            if (std.mem.eql(u8, op_parts.word, "getelementptr")) {
                const rest = trim(op_parts.rest);
                const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
                const comma2 = std.mem.indexOfScalar(u8, rest[comma + 1 ..], ',') orelse return TranslateError.UnsupportedLlvm;
                const base_part = trim(rest[comma + 1 .. comma + 1 + comma2]);
                const offset_part = trim(rest[comma + 1 + comma2 + 1 ..]);
                const base = stripAt(base_part);
                const offset = stripPercent(offset_part);
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = ptr_add {s}, {s}", .{ stripPercent(lhs), base, offset }));
                return;
            }

            if (std.mem.eql(u8, op_parts.word, "phi")) {
                const rest = trim(op_parts.rest);
                const entries = try splitCommaArgs(self.allocator, rest);
                defer self.allocator.free(entries);
                if (entries.len == 0) return TranslateError.UnsupportedLlvm;
                const first = entries[0];
                const lb = std.mem.indexOfScalar(u8, first, '[') orelse return TranslateError.UnsupportedLlvm;
                const rb = std.mem.indexOfScalarPos(u8, first, lb, ']') orelse return TranslateError.UnsupportedLlvm;
                const val = trim(first[lb + 1 .. rb]);
                try self.pending_phi.put(try self.allocator.dupe(u8, stripPercent(lhs)), stripPercent(val));
                return;
            }

            if (std.mem.eql(u8, op_parts.word, "alloca")) {
                const rest = trim(op_parts.rest);
                const count = if (std.mem.indexOf(u8, rest, ",") ) |comma| trim(rest[comma + 1 ..]) else "1";
                try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s} = stack_alloc {s}", .{ stripPercent(lhs), count }));
                return;
            }

            if (std.mem.eql(u8, op_parts.word, "trunc") or std.mem.eql(u8, op_parts.word, "zext")) {
                return TranslateError.UnsupportedLlvm;
            }
        }

        if (std.mem.startsWith(u8, trimmed, "br ")) {
            // handled above
        }

        if (std.mem.startsWith(u8, trimmed, "ret ")) {
            const rest = trim(trimmed["ret".len..]);
            if (std.mem.eql(u8, rest, "void")) {
                try self.emitLine("return");
                return;
            }
            const parts = splitFirstWord(rest);
            _ = parts;
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "return {s}", .{ rest }));
            return;
        }

        if (std.mem.startsWith(u8, trimmed, "unreachable")) {
            try self.emitLine("panic(102)");
            return;
        }

        return TranslateError.UnsupportedLlvm;
    }
};

fn stripLabelKeyword(text: []const u8) []const u8 {
    var t = Translator.trim(text);
    if (std.mem.startsWith(u8, t, "label ")) t = Translator.trim(t["label".len..]);
    if (t.len != 0 and t[0] == '%') t = t[1..];
    if (t.len != 0 and t[0] == '@') t = t[1..];
    return t;
}

fn splitStoreAddress(text: []const u8) !struct { base: []const u8, offset: []const u8 } {
    const plus = std.mem.lastIndexOfScalar(u8, text, '+') orelse return TranslateError.InvalidLlvm;
    const base = Translator.trim(text[0..plus]);
    const offset = Translator.trim(text[plus + 1 ..]);
    if (base.len == 0 or offset.len == 0) return TranslateError.InvalidLlvm;
    return .{ .base = stripAt(base), .offset = offset };
}

pub fn translateAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var translator = Translator.init(allocator, input);
    defer translator.deinit();

    const lines = try std.mem.splitScalar(u8, input, '\n');
    _ = lines;
    var all_lines = std.ArrayList([]const u8).init(allocator);
    defer all_lines.deinit();
    var iter = std.mem.splitScalar(u8, input, '\n');
    while (iter.next()) |line| {
        try all_lines.append(line);
    }

    try translator.emitLine("@ffi_wrapper __sa_panic(*code: ptr, *msg: ptr, len: u64) -> void:");
    try translator.emitLine("L_ENTRY:");
    try translator.emitLine("    panic(102)");
    try translator.emitLine("");

    try translator.emitGlobals(all_lines.items);

    var prev_labels = std.StringHashMap(bool).init(allocator);
    defer prev_labels.deinit();
    for (all_lines.items) |line| {
        const trimmed = Translator.trim(line);
        if (trimmed.len == 0 or trimmed[0] == ';') continue;
        if (std.mem.startsWith(u8, trimmed, "define ")) {
            try translator.emitFunctionHeader(trimmed);
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
        if (std.mem.startsWith(u8, trimmed, "entry:")) {
            try translator.emitLine("L_ENTRY:");
            continue;
        }
        try translator.emitInstruction(trimmed, &prev_labels);
    }

    return try translator.out.toOwnedSlice();
}

test "translator module imports" {
    _ = translateAlloc;
}
