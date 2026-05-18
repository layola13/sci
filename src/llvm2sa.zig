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
    aliases: std.StringHashMap([]const u8),
    skip_function: bool = false,
    current_block_is_entry: bool = false,
    emit_preamble: bool = true,

    fn init(allocator: std.mem.Allocator, input: []const u8) Translator {
        return .{
            .allocator = allocator,
            .input = input,
            .out = std.ArrayList(u8).init(allocator),
            .pending_labels = std.ArrayList([]const u8).init(allocator),
            .aliases = std.StringHashMap([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Translator) void {
        var alias_iter = self.aliases.iterator();
        while (alias_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.aliases.deinit();
        for (self.pending_labels.items) |label| self.allocator.free(label);
        self.pending_labels.deinit();
        self.out.deinit();
        self.* = undefined;
    }

    fn emitLine(self: *Translator, bytes: []const u8) !void {
        try self.out.appendSlice(bytes);
        try self.out.append('\n');
    }

    fn emitFmt(self: *Translator, comptime fmt: []const u8, args: anytype) !void {
        try self.out.writer().print(fmt, args);
        try self.out.append('\n');
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
        if (std.mem.eql(u8, trimmed, "float")) return "f32";
        if (std.mem.eql(u8, trimmed, "double")) return "f64";
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
                '[' => depth += 1,
                '{' => depth += 1,
                ']' => {
                    if (depth > 0) depth -= 1;
                },
                '}' => {
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

    fn isLlvmTypeWord(word: []const u8) bool {
        return std.mem.eql(u8, word, "void") or
            std.mem.eql(u8, word, "ptr") or
            std.mem.eql(u8, word, "i1") or
            std.mem.eql(u8, word, "i8") or
            std.mem.eql(u8, word, "i16") or
            std.mem.eql(u8, word, "i32") or
            std.mem.eql(u8, word, "i64") or
            std.mem.eql(u8, word, "u8") or
            std.mem.eql(u8, word, "u16") or
            std.mem.eql(u8, word, "u32") or
            std.mem.eql(u8, word, "u64") or
            std.mem.eql(u8, word, "f32") or
            std.mem.eql(u8, word, "f64") or
            std.mem.eql(u8, word, "float") or
            std.mem.eql(u8, word, "double");
    }

    fn firstTypeToken(text: []const u8) ?[]const u8 {
        var iter = std.mem.splitScalar(u8, trim(text), ' ');
        while (iter.next()) |token| {
            const trimmed = trim(token);
            if (trimmed.len != 0 and isLlvmTypeWord(trimmed)) return trimmed;
        }
        return null;
    }

    fn lastTypeToken(text: []const u8) ?[]const u8 {
        const trimmed = trim(text);
        var end = trimmed.len;
        while (end > 0) {
            var start = end;
            while (start > 0 and !std.ascii.isWhitespace(trimmed[start - 1])) : (start -= 1) {}
            const token = trim(trimmed[start..end]);
            if (token.len != 0 and isLlvmTypeWord(token)) return token;
            if (start == 0) break;
            end = start - 1;
            while (end > 0 and std.ascii.isWhitespace(trimmed[end - 1])) : (end -= 1) {}
        }
        return null;
    }

    fn isIntegerLiteral(text: []const u8) bool {
        const trimmed = trim(text);
        if (trimmed.len == 0) return false;
        var idx: usize = 0;
        if (trimmed[0] == '+' or trimmed[0] == '-') idx = 1;
        if (idx >= trimmed.len) return false;
        var saw_digit = false;
        while (idx < trimmed.len) : (idx += 1) {
            if (!std.ascii.isDigit(trimmed[idx])) return false;
            saw_digit = true;
        }
        return saw_digit;
    }

    fn setAlias(self: *Translator, name: []const u8, expr: []const u8) !void {
        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);
        const value = try self.allocator.dupe(u8, expr);
        errdefer self.allocator.free(value);
        try self.aliases.put(key, value);
    }

    fn resolveAlias(self: *Translator, name: []const u8) []const u8 {
        var resolved = name;
        var guard: usize = 0;
        while (guard < 8) : (guard += 1) {
            const alias = self.aliases.get(resolved) orelse break;
            resolved = alias;
        }
        return resolved;
    }

    fn ensureBlankLineBeforeFunction(self: *Translator) !void {
        if (self.out.items.len == 0) return;
        if (self.out.items.len >= 2 and self.out.items[self.out.items.len - 1] == '\n' and self.out.items[self.out.items.len - 2] == '\n') {
            return;
        }
        if (self.out.items[self.out.items.len - 1] != '\n') {
            try self.out.append('\n');
        }
        try self.out.append('\n');
    }

    fn stripTypedValue(text: []const u8) []const u8 {
        const trimmed = trim(text);
        const parts = splitFirstWord(trimmed);
        if (parts.word.len != 0 and isLlvmTypeWord(parts.word) and parts.rest.len != 0) {
            return trim(parts.rest);
        }
        return trimmed;
    }

    fn stripLlvmSymbol(text: []const u8) []const u8 {
        const trimmed = stripTypedValue(text);
        if (trimmed.len != 0 and (trimmed[0] == '%' or trimmed[0] == '@')) return trimmed[1..];
        return trimmed;
    }

    fn renderPlainValue(self: *Translator, text: []const u8) ![]const u8 {
        const stripped = stripLlvmSymbol(text);
        const resolved = self.resolveAlias(stripped);
        if (std.mem.eql(u8, resolved, "null")) return "0";
        return resolved;
    }

    fn renderTypeAndValue(self: *Translator, text: []const u8) !struct { ty: []const u8, value: []const u8 } {
        const trimmed = trim(text);
        const type_token = firstTypeToken(trimmed) orelse return TranslateError.InvalidLlvm;
        const remainder = trimmed[type_token.len..];
        const value_text = trim(remainder);
        if (value_text.len == 0) return TranslateError.InvalidLlvm;
        return .{ .ty = parseTypeName(type_token), .value = try self.renderPlainValue(value_text) };
    }

    fn renderTypedCallArg(self: *Translator, callee: []const u8, arg_index: usize, text: []const u8) ![]const u8 {
        const rendered = try self.renderTypeAndValue(text);
        if (std.mem.eql(u8, callee, "sa_print_bytes") and arg_index == 0) {
            return try std.fmt.allocPrint(self.allocator, "&{s}", .{rendered.value});
        }
        if (std.mem.eql(u8, callee, "sys_print") or std.mem.eql(u8, callee, "sys_read_file") or std.mem.eql(u8, callee, "sys_write_file")) {
            if (arg_index == 0 or (std.mem.eql(u8, callee, "sys_read_file") and arg_index == 2) or (std.mem.eql(u8, callee, "sys_write_file") and arg_index == 2)) {
                return try std.fmt.allocPrint(self.allocator, "*{s}", .{rendered.value});
            }
        }
        _ = rendered.ty;
        return rendered.value;
    }

    fn renderLabelName(self: *Translator, text: []const u8) ![]const u8 {
        _ = self;
        return stripLabel(text);
    }

    fn decodeLlvmCString(allocator: std.mem.Allocator, literal: []const u8) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        var i: usize = 0;
        while (i < literal.len) : (i += 1) {
            const c = literal[i];
            if (c == '"') break;
            if (c != '\\') {
                try list.append(c);
                continue;
            }
            if (i + 1 >= literal.len) return TranslateError.InvalidLlvm;
            const esc = literal[i + 1];
            switch (esc) {
                '\\' => {
                    try list.append('\\');
                    i += 1;
                },
                '"' => {
                    try list.append('"');
                    i += 1;
                },
                'n' => {
                    try list.append('\n');
                    i += 1;
                },
                'r' => {
                    try list.append('\r');
                    i += 1;
                },
                't' => {
                    try list.append('\t');
                    i += 1;
                },
                else => {
                    const hi = std.fmt.charToDigit(esc, 16) catch return TranslateError.InvalidLlvm;
                    if (i + 2 >= literal.len) return TranslateError.InvalidLlvm;
                    const lo = std.fmt.charToDigit(literal[i + 2], 16) catch return TranslateError.InvalidLlvm;
                    try list.append(@as(u8, @intCast((hi << 4) | lo)));
                    i += 2;
                },
            }
        }

        return try list.toOwnedSlice();
    }

    fn emitConstFromBytes(self: *Translator, name: []const u8, bytes: []const u8) !void {
        var rendered = std.ArrayList(u8).init(self.allocator);
        errdefer rendered.deinit();

        try rendered.appendSlice("@const ");
        try rendered.appendSlice(name);
        try rendered.appendSlice(" = ");

        const utf8_ok = std.unicode.utf8ValidateSlice(bytes);
        if (utf8_ok) {
            try rendered.appendSlice("utf8:\"");
            for (bytes) |byte| {
                switch (byte) {
                    '\\' => try rendered.appendSlice("\\\\"),
                    '"' => try rendered.appendSlice("\\\""),
                    '\n' => try rendered.appendSlice("\\n"),
                    '\r' => try rendered.appendSlice("\\r"),
                    '\t' => try rendered.appendSlice("\\t"),
                    0 => try rendered.appendSlice("\\0"),
                    else => if (byte >= 0x20 and byte < 0x7f) {
                        try rendered.append(byte);
                    } else {
                        try rendered.writer().print("\\x{X:0>2}", .{byte});
                    },
                }
            }
            try rendered.append('"');
        } else {
            try rendered.appendSlice("hex:");
            for (bytes) |byte| {
                try rendered.writer().print("\\x{X:0>2}", .{byte});
            }
        }

        try self.emitLine(rendered.items);
    }

    fn shouldSkipTopLevelLine(trimmed: []const u8) bool {
        if (trimmed.len == 0) return true;
        if (trimmed[0] == ';') return true;
        if (trimmed.len > 1 and trimmed[0] == '/' and trimmed[1] == '/') return true;
        if (std.mem.startsWith(u8, trimmed, "source_filename")) return true;
        if (std.mem.startsWith(u8, trimmed, "target ")) return true;
        if (std.mem.startsWith(u8, trimmed, "attributes ")) return true;
        if (std.mem.startsWith(u8, trimmed, "!")) return true;
        return false;
    }

    fn isRuntimeFunctionName(name: []const u8) bool {
        return std.mem.eql(u8, name, "__sa_panic") or
            std.mem.eql(u8, name, "saasm_strdupz") or
            std.mem.eql(u8, name, "saasm_streq") or
            std.mem.eql(u8, name, "sys_print") or
            std.mem.eql(u8, name, "sys_exit") or
            std.mem.eql(u8, name, "sys_argc") or
            std.mem.eql(u8, name, "sys_argv") or
            std.mem.eql(u8, name, "sys_read_file") or
            std.mem.eql(u8, name, "sys_write_file") or
            std.mem.eql(u8, name, "fprintf") or
            std.mem.eql(u8, name, "exit") or
            std.mem.eql(u8, name, "malloc") or
            std.mem.eql(u8, name, "free") or
            std.mem.eql(u8, name, "memcpy") or
            std.mem.eql(u8, name, "fopen") or
            std.mem.eql(u8, name, "fseek") or
            std.mem.eql(u8, name, "ftell") or
            std.mem.eql(u8, name, "rewind") or
            std.mem.eql(u8, name, "fread") or
            std.mem.eql(u8, name, "fwrite") or
            std.mem.eql(u8, name, "fclose") or
            std.mem.eql(u8, name, "write") or
            std.mem.eql(u8, name, "getenv") or
            std.mem.eql(u8, name, "sa_print_bytes");
    }

    fn shouldSkipFunction(name: []const u8, params: []const u8) bool {
        if (std.mem.eql(u8, name, "main") and trim(params).len != 0) return true;
        return isRuntimeFunctionName(name);
    }

    fn parseTypedOperand(self: *Translator, text: []const u8) !struct { ty: []const u8, value: []const u8 } {
        const trimmed = trim(text);
        const type_token = firstTypeToken(trimmed) orelse return TranslateError.InvalidLlvm;
        const value_text = trim(trimmed[type_token.len..]);
        if (value_text.len == 0) return TranslateError.InvalidLlvm;
        return .{ .ty = parseTypeName(type_token), .value = try self.renderPlainValue(value_text) };
    }

    fn renderAddressExpr(self: *Translator, text: []const u8) ![]const u8 {
        const trimmed = trim(text);
        if (std.mem.startsWith(u8, trimmed, "getelementptr")) {
            const rest = trim(trimmed["getelementptr".len..]);
            const first_comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
            const after_type = trim(rest[first_comma + 1 ..]);
            const parts = try splitCommaArgs(self.allocator, after_type);
            defer self.allocator.free(parts);
            if (parts.len < 2) return TranslateError.InvalidLlvm;
            const base = try self.renderPlainValue(parts[0]);
            const offset = try self.renderPlainValue(parts[parts.len - 1]);
            return try std.fmt.allocPrint(self.allocator, "{s}+{s}", .{ base, offset });
        }
        const plain = try self.renderPlainValue(trimmed);
        return try std.fmt.allocPrint(self.allocator, "{s}+0", .{plain});
    }

    fn emitAddressExpr(self: *Translator, text: []const u8) ![]const u8 {
        return try self.renderAddressExpr(text);
    }

    fn extractLlvmConstBytes(allocator: std.mem.Allocator, rhs: []const u8) !?[]u8 {
        const literal_start = std.mem.indexOf(u8, rhs, " c\"") orelse return null;
        const literal = rhs[literal_start + 3 ..];
        const bytes = try decodeLlvmCString(allocator, literal);
        return bytes;
    }

    fn emitTopLevelGlobal(self: *Translator, line: []const u8) !bool {
        const assign = splitAssignment(line) orelse return false;
        const lhs = trim(assign.lhs);
        const rhs = trim(assign.rhs);
        if (!isGlobalName(lhs)) return false;

        const name = stripPrefix(lhs, '@');
        if (std.mem.eql(u8, name, "saasm_argc") or
            std.mem.eql(u8, name, "saasm_argv") or
            std.mem.eql(u8, name, ".mode_rb") or
            std.mem.eql(u8, name, ".mode_wb") or
            std.mem.eql(u8, name, ".panic_code_fmt") or
            std.mem.eql(u8, name, ".panic_msg_fmt") or
            std.mem.eql(u8, name, "stderr"))
        {
            return true;
        }

        if (std.mem.startsWith(u8, rhs, "private unnamed_addr constant") or
            std.mem.startsWith(u8, rhs, "internal unnamed_addr constant") or
            std.mem.startsWith(u8, rhs, "constant"))
        {
            if (try extractLlvmConstBytes(self.allocator, rhs)) |bytes| {
                defer self.allocator.free(bytes);
                try self.emitConstFromBytes(name, bytes);
                return true;
            }
        }

        if (std.mem.startsWith(u8, rhs, "external global") or std.mem.startsWith(u8, rhs, "internal global")) {
            return true;
        }

        return true;
    }

    fn mapFunctionName(self: *Translator, name: []const u8, params: []const u8) ![]const u8 {
        _ = self;
        if (std.mem.eql(u8, name, "saasm_main")) return "main";
        if (std.mem.eql(u8, name, "main") and trim(params).len != 0) return "main";
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
        const ret_ty = lastTypeToken(trimmed["define".len..at]) orelse return TranslateError.InvalidLlvm;
        if (shouldSkipFunction(name, params)) {
            self.skip_function = true;
            self.current = null;
            return;
        }
        const mapped = try self.mapFunctionName(name, params);
        const kind: FunctionMode = if (isRuntimeFunctionName(name)) .ffi_wrapper else .normal;
        try self.ensureBlankLineBeforeFunction();
        self.current = .{
            .name = try self.allocator.dupe(u8, name),
            .kind = kind,
            .sa_name = try self.allocator.dupe(u8, mapped),
        };
        try self.emitFunctionHeader(kind, mapped, params, ret_ty);
    }

    fn emitFunctionHeader(self: *Translator, kind: FunctionMode, name: []const u8, params: []const u8, ret_ty: []const u8) !void {
        switch (kind) {
            .normal => try self.out.append('@'),
            .ffi_wrapper => try self.out.appendSlice("@ffi_wrapper "),
            .external => try self.out.appendSlice("@extern "),
        }
        try self.out.appendSlice(name);
        try self.out.append('(');
        if (trim(params).len != 0) {
            const args = try splitCommaArgs(self.allocator, params);
            defer self.allocator.free(args);
            for (args, 0..) |arg, idx| {
                if (idx != 0) try self.out.appendSlice(", ");
                try self.out.appendSlice(try self.translateParam(arg));
            }
        }
        try self.out.append(')');
        if (!std.mem.eql(u8, trim(ret_ty), "void")) {
            try self.out.appendSlice(" -> ");
            try self.out.appendSlice(try self.translateReturn(ret_ty));
        }
        try self.out.append(':');
        try self.out.append('\n');
        if (self.current) |*ctx| ctx.rendered_header = true;
    }

    fn translateParam(self: *Translator, arg: []const u8) ![]const u8 {
        const trimmed = trim(arg);
        if (trimmed.len == 0) return TranslateError.InvalidLlvm;
        if (std.mem.eql(u8, trimmed, "...")) return try self.allocator.dupe(u8, "...");
        const name_pos = std.mem.lastIndexOfScalar(u8, trimmed, '%') orelse return TranslateError.InvalidLlvm;
        const name_end = blk: {
            var end = name_pos + 1;
            while (end < trimmed.len and !std.ascii.isWhitespace(trimmed[end]) and trimmed[end] != ',') : (end += 1) {}
            break :blk end;
        };
        const name = stripPrefix(trim(trimmed[name_pos..name_end]), '%');
        const ty = firstTypeToken(trimmed[0..name_pos]) orelse return TranslateError.InvalidLlvm;
        return try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ name, parseTypeName(ty) });
    }

    fn translateReturn(self: *Translator, ret_ty: []const u8) ![]const u8 {
        _ = self;
        return parseTypeName(ret_ty);
    }

    fn renderArgs(self: *Translator, callee: []const u8, args_text: []const u8) ![]const u8 {
        const args = try splitCommaArgs(self.allocator, args_text);
        defer self.allocator.free(args);
        var rendered = std.ArrayList(u8).init(self.allocator);
        errdefer rendered.deinit();
        for (args, 0..) |arg, idx| {
            if (idx != 0) try rendered.appendSlice(", ");
            try rendered.appendSlice(try self.renderTypedCallArg(callee, idx, arg));
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
        const args = try self.renderArgs(callee, args_text);
        defer self.allocator.free(args);

        if (std.mem.eql(u8, callee, "malloc")) {
            if (lhs) |name| try self.emitFmt("{s} = alloc {s}", .{ name, args }) else try self.emitFmt("alloc {s}", .{args});
            return;
        }
        if (std.mem.eql(u8, callee, "free")) {
            try self.emitFmt("!{s}", .{args});
            return;
        }
        if (std.mem.eql(u8, callee, "memcpy")) {
            if (lhs) |name| try self.emitFmt("{s} = call @memcpy({s})", .{ name, args }) else try self.emitFmt("call @memcpy({s})", .{args});
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
            const cond = try self.renderPlainValue(rest[0..comma1]);
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
        const pair = try splitCommaArgs(self.allocator, rest);
        defer self.allocator.free(pair);
        if (pair.len < 2) return TranslateError.InvalidLlvm;
        const addr = trim(pair[1]);
        const value = trim(pair[0]);
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
                const addr = try self.emitAddressExpr(source);
                defer self.allocator.free(addr);
                try self.emitFmt("{s} = load {s} as {s}", .{ stripPrefix(lhs, '%'), addr, ty });
            } else {
                const addr = try self.emitAddressExpr(body);
                defer self.allocator.free(addr);
                try self.emitFmt("{s} = load {s}", .{ stripPrefix(lhs, '%'), addr });
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
            const resolved = try self.renderPlainValue(value);
            if (isIntegerLiteral(resolved)) {
                try self.setAlias(stripPrefix(lhs, '%'), resolved);
                return;
            }
            try self.emitFmt("{s} = {s} {s} as {s}", .{ stripPrefix(lhs, '%'), kind, resolved, ty });
            return;
        }
        if (std.mem.eql(u8, kind, "getelementptr")) {
            const rest = trim(op.rest);
            const first_comma = std.mem.indexOfScalar(u8, rest, ',') orelse return TranslateError.InvalidLlvm;
            const second_comma = std.mem.indexOfScalar(u8, rest[first_comma + 1 ..], ',') orelse return TranslateError.InvalidLlvm;
            const base = trim(rest[first_comma + 1 .. first_comma + 1 + second_comma]);
            const offset = trim(rest[first_comma + 1 + second_comma + 1 ..]);
            try self.emitFmt("{s} = ptr_add {s}, {s}", .{ stripPrefix(lhs, '%'), try self.renderPlainValue(base), try self.renderPlainValue(offset) });
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
            const comma = std.mem.indexOfScalar(u8, val, ',') orelse return TranslateError.UnsupportedLlvm;
            const incoming = trim(val[0..comma]);
            const resolved = try self.renderPlainValue(incoming);
            if (isIntegerLiteral(resolved)) {
                try self.setAlias(stripPrefix(lhs, '%'), resolved);
                return;
            }
            try self.setAlias(stripPrefix(lhs, '%'), resolved);
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
        if (shouldSkipTopLevelLine(trimmed)) return;
        if (std.mem.startsWith(u8, trimmed, "declare ")) return;
        if (std.mem.eql(u8, trimmed, "entry:")) {
            try self.emitLine("L_ENTRY:");
            return;
        }
        if (std.mem.endsWith(u8, trimmed, ":")) {
            try self.emitLine(try std.fmt.allocPrint(self.allocator, "{s}:", .{try self.renderLabelName(trimmed[0 .. trimmed.len - 1])}));
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
            try self.emitFmt("return {s}", .{try self.renderPlainValue(rest)});
            return;
        }
        if (std.mem.eql(u8, trimmed, "unreachable")) {
            try self.emitLine("panic(102)");
            return;
        }
        if (std.mem.startsWith(u8, trimmed, "call ")) {
            try self.emitCall(null, trimmed);
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

    try translator.emitLine("@import \"../../../sa_std/io/print.saasm-iface\"");
    try translator.emitLine("");

    var all_lines = std.ArrayList([]const u8).init(allocator);
    defer all_lines.deinit();
    var iter = std.mem.splitScalar(u8, input, '\n');
    while (iter.next()) |line| {
        try all_lines.append(line);
    }

    for (all_lines.items) |line| {
        const trimmed = trim(line);
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "define ")) {
            try translator.parseFunctionHeader(trimmed);
            continue;
        }
        if (translator.skip_function) {
            if (std.mem.eql(u8, trimmed, "}")) translator.skip_function = false;
            continue;
        }
        if (translator.current == null and std.mem.eql(u8, trimmed, "}")) continue;
        if (try translator.emitTopLevelGlobal(trimmed)) continue;
        if (std.mem.startsWith(u8, trimmed, "declare ")) {
            const declare = trim(trimmed["declare".len..]);
            if (std.mem.startsWith(u8, declare, "void @sa_print_bytes")) continue;
            continue;
        }
        if (std.mem.eql(u8, trimmed, "}")) {
            translator.current = null;
            continue;
        }
        if (translator.current == null) {
            continue;
        }
        if (std.mem.eql(u8, trimmed, "entry:")) {
            try translator.emitLine("L_ENTRY:");
            continue;
        }
        try translator.emitInstruction(trimmed);
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

pub fn translatePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try translateFile(allocator, path);
}

test "translator module imports" {
    _ = translateAlloc;
    _ = translateFile;
    _ = translatePath;
}
