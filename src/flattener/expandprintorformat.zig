const std = @import("std");
const common_upstream = @import("../common/upstream_loc.zig");
const emitParsedLine = @import("emitparsedline.zig").emitParsedLine;
const isFunctionSigDeclared = @import("emitparsedline.zig").isFunctionSigDeclared;


fn parsePrintArgs(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
    var args = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit();
    }

    var i: usize = 0;
    var start: usize = 0;
    var in_quotes: bool = false;
    var escaped: bool = false;

    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (in_quotes) {
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                in_quotes = false;
            }
        } else {
            if (c == '"') {
                in_quotes = true;
            } else if (c == ',') {
                const arg = std.mem.trim(u8, text[start..i], " \t\r\n");
                if (arg.len > 0) {
                    const arg_dup = try allocator.dupe(u8, arg);
                    try args.append(arg_dup);
                }
                start = i + 1;
            }
        }
    }

    const arg = std.mem.trim(u8, text[start..], " \t\r\n");
    if (arg.len > 0) {
        const arg_dup = try allocator.dupe(u8, arg);
        try args.append(arg_dup);
    }
    return try args.toOwnedSlice();
}

pub fn unquoteString(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var raw = text;
    if (std.mem.startsWith(u8, raw, "utf8:\"") and std.mem.endsWith(u8, raw, "\"")) {
        raw = raw[5 .. raw.len - 1];
    } else if (std.mem.startsWith(u8, raw, "\"") and std.mem.endsWith(u8, raw, "\"")) {
        raw = raw[1 .. raw.len - 1];
    } else {
        return error.InvalidFormatString;
    }
    return try allocator.dupe(u8, raw);
}

const FormatSegmentKind = enum {
    literal,
    placeholder,
};

const Specifier = enum {
    none,
    i64,
    u64,
    f64,
    bytes,
};

const FormatSegment = struct {
    kind: FormatSegmentKind,
    text: []const u8,
    specifier: Specifier,
};

fn parseFormatString(allocator: std.mem.Allocator, fmt_str: []const u8) ![]FormatSegment {
    var segments = std.array_list.Managed(FormatSegment).init(allocator);
    errdefer {
        for (segments.items) |seg| {
            if (seg.kind == .literal) allocator.free(seg.text);
        }
        segments.deinit();
    }

    var i: usize = 0;
    var start: usize = 0;
    while (i < fmt_str.len) {
        if (fmt_str[i] == '{') {
            if (i > start) {
                const lit_text = try allocator.dupe(u8, fmt_str[start..i]);
                try segments.append(.{
                    .kind = .literal,
                    .text = lit_text,
                    .specifier = .none,
                });
            }

            const close_idx = std.mem.indexOfScalar(u8, fmt_str[i..], '}') orelse return error.UnbalancedPlaceholder;
            const absolute_close = i + close_idx;
            const spec_text = fmt_str[i + 1 .. absolute_close];

            var spec = Specifier.none;
            if (spec_text.len == 0) {
                spec = .none;
            } else if (std.mem.eql(u8, spec_text, ":i") or std.mem.eql(u8, spec_text, ":d")) {
                spec = .i64;
            } else if (std.mem.eql(u8, spec_text, ":u")) {
                spec = .u64;
            } else if (std.mem.eql(u8, spec_text, ":f")) {
                spec = .f64;
            } else if (std.mem.eql(u8, spec_text, ":b") or std.mem.eql(u8, spec_text, ":s")) {
                spec = .bytes;
            } else {
                return error.InvalidSpecifier;
            }

            try segments.append(.{
                .kind = .placeholder,
                .text = &.{},
                .specifier = spec,
            });

            i = absolute_close + 1;
            start = i;
        } else {
            i += 1;
        }
    }

    if (start < fmt_str.len) {
        const lit_text = try allocator.dupe(u8, fmt_str[start..]);
        try segments.append(.{
            .kind = .literal,
            .text = lit_text,
            .specifier = .none,
        });
    }

    return try segments.toOwnedSlice();
}

fn unescapeLength(text: []const u8) usize {
    var len: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '\\' and i + 1 < text.len) {
            i += 2;
        } else {
            i += 1;
        }
        len += 1;
    }
    return len;
}

const EXTERN_SA_FMT_I64 = "@extern sa_fmt_i64(value: i64, base: u32) -> u64";
const EXTERN_SA_FMT_U64 = "@extern sa_fmt_u64(value: u64, base: u32) -> u64";
const EXTERN_SA_FMT_F64 = "@extern sa_fmt_f64(value: f64, precision: u32) -> u64";
const EXTERN_SA_FMT_BYTES = "@extern sa_fmt_bytes(&buf: ptr, len: u64) -> u64";
const EXTERN_SA_FMT_BUFFER_DATA = "@extern sa_fmt_buffer_data(buffer: u64) -> &ptr";
const EXTERN_SA_FMT_BUFFER_LEN = "@extern sa_fmt_buffer_len(buffer: u64) -> u64";
const EXTERN_SA_FMT_BUFFER_FREE = "@extern sa_fmt_buffer_free(^buffer: u64) -> i32";
const EXTERN_SA_STRING_CONCAT = "@extern sa_string_concat(left: ptr, left_len: u64, right: ptr, right_len: u64) -> u64";

fn ensureExternSigs(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    symbols: *SymbolTable,
    loc_table: *std.array_list.Managed(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
    source_line: u32,
    instructions: *std.array_list.Managed(Instruction),
    const_decls: *std.array_list.Managed(ConstDecl),
    function_sigs: *std.array_list.Managed(FunctionSig),
    owned_text: *std.array_list.Managed([]const u8),
    current_package_identity: ?[]const u8,
    current_package_hash: ?[32]u8,
) !void {
    const sigs = function_sigs.items;
    if (!isFunctionSigDeclared(sigs, "sa_fmt_i64")) {
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, EXTERN_SA_FMT_I64, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    }
    if (!isFunctionSigDeclared(sigs, "sa_fmt_u64")) {
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, EXTERN_SA_FMT_U64, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    }
    if (!isFunctionSigDeclared(sigs, "sa_fmt_f64")) {
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, EXTERN_SA_FMT_F64, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    }
    if (!isFunctionSigDeclared(sigs, "sa_fmt_bytes")) {
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, EXTERN_SA_FMT_BYTES, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    }
    if (!isFunctionSigDeclared(sigs, "sa_fmt_buffer_data")) {
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, EXTERN_SA_FMT_BUFFER_DATA, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    }
    if (!isFunctionSigDeclared(sigs, "sa_fmt_buffer_len")) {
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, EXTERN_SA_FMT_BUFFER_LEN, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    }
    if (!isFunctionSigDeclared(sigs, "sa_fmt_buffer_free")) {
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, EXTERN_SA_FMT_BUFFER_FREE, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    }
    if (!isFunctionSigDeclared(sigs, "sa_string_concat")) {
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, EXTERN_SA_STRING_CONCAT, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    }
}

pub fn expandPrintOrFormat(
    allocator: std.mem.Allocator,
    macro_name: []const u8,
    args_text: []const u8,
    source_line: u32,
    dict: *DefDict,
    symbols: *SymbolTable,
    loc_table: *std.array_list.Managed(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
    instructions: *std.array_list.Managed(Instruction),
    const_decls: *std.array_list.Managed(ConstDecl),
    function_sigs: *std.array_list.Managed(FunctionSig),
    owned_text: *std.array_list.Managed([]const u8),
    current_package_identity: ?[]const u8,
    current_package_hash: ?[32]u8,
) !void {
    try ensureExternSigs(
        allocator,
        dict,
        symbols,
        loc_table,
        pending_loc,
        source_line,
        instructions,
        const_decls,
        function_sigs,
        owned_text,
        current_package_identity,
        current_package_hash,
    );

    const args = try parsePrintArgs(allocator, args_text);
    defer {
        for (args) |arg| allocator.free(arg);
        allocator.free(args);
    }

    if (std.mem.eql(u8, macro_name, "PRINT!")) {
        if (args.len < 1) return error.InvalidMacroInvocation;
        const fmt_str_raw = args[0];
        const format_args = args[1..];

        const fmt_str = try unquoteString(allocator, fmt_str_raw);
        defer allocator.free(fmt_str);

        const segments = try parseFormatString(allocator, fmt_str);
        defer {
            for (segments) |seg| {
                if (seg.kind == .literal) allocator.free(seg.text);
            }
            allocator.free(segments);
        }

        var expected_args: usize = 0;
        for (segments) |seg| {
            if (seg.kind == .placeholder) {
                switch (seg.specifier) {
                    .none, .i64, .u64, .f64 => expected_args += 1,
                    .bytes => expected_args += 2,
                }
            }
        }

        if (expected_args != format_args.len) {
            return error.ArgCountMismatch;
        }

        var var_counter: usize = 0;
        var arg_idx: usize = 0;
        for (segments) |seg| {
            if (seg.kind == .literal) {
                const unescaped_len = unescapeLength(seg.text);
                const const_id = const_decls.items.len;
                const const_name = try std.fmt.allocPrint(allocator, "__PRINT_LIT_{d}_{d}", .{ source_line, const_id });
                defer allocator.free(const_name);

                const const_line = try std.fmt.allocPrint(allocator, "@const {s} = utf8:\"{s}\"", .{ const_name, seg.text });
                defer allocator.free(const_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const print_line = try std.fmt.allocPrint(allocator, "call @sys_print(*{s}, {d})", .{ const_name, unescaped_len });
                defer allocator.free(print_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, print_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
            } else {
                const spec = seg.specifier;
                const fmt_buf = try std.fmt.allocPrint(allocator, "__fmt_buf_{d}_{d}", .{ source_line, var_counter });
                const fmt_ptr = try std.fmt.allocPrint(allocator, "__fmt_ptr_{d}_{d}", .{ source_line, var_counter });
                const fmt_len = try std.fmt.allocPrint(allocator, "__fmt_len_{d}_{d}", .{ source_line, var_counter });
                const fmt_free_ok = try std.fmt.allocPrint(allocator, "__fmt_free_ok_{d}_{d}", .{ source_line, var_counter });
                defer {
                    allocator.free(fmt_buf);
                    allocator.free(fmt_ptr);
                    allocator.free(fmt_len);
                    allocator.free(fmt_free_ok);
                }
                var_counter += 1;

                const call_line = switch (spec) {
                    .none, .i64 => try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_i64({s}, 10)", .{ fmt_buf, format_args[arg_idx] }),
                    .u64 => try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_u64({s}, 10)", .{ fmt_buf, format_args[arg_idx] }),
                    .f64 => try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_f64({s}, 6)", .{ fmt_buf, format_args[arg_idx] }),
                    .bytes => try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_bytes(&{s}, {s})", .{ fmt_buf, format_args[arg_idx], format_args[arg_idx + 1] }),
                };
                defer allocator.free(call_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, call_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                switch (spec) {
                    .none, .i64, .u64, .f64 => arg_idx += 1,
                    .bytes => arg_idx += 2,
                }

                const ptr_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_data({s})", .{ fmt_ptr, fmt_buf });
                defer allocator.free(ptr_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const len_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_len({s})", .{ fmt_len, fmt_buf });
                defer allocator.free(len_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const print_line = try std.fmt.allocPrint(allocator, "call @sys_print({s}, {s})", .{ fmt_ptr, fmt_len });
                defer allocator.free(print_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, print_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const ptr_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{fmt_ptr});
                defer allocator.free(ptr_release_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_release_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const len_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{fmt_len});
                defer allocator.free(len_release_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_release_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const free_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_free(^{s})", .{ fmt_free_ok, fmt_buf });
                defer allocator.free(free_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, free_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const free_discard_line = try std.fmt.allocPrint(allocator, "! {s}", .{fmt_free_ok});
                defer allocator.free(free_discard_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, free_discard_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
            }
        }
    } else {
        if (args.len < 2) return error.InvalidMacroInvocation;
        const dest_reg = args[0];
        const fmt_str_raw = args[1];
        const format_args = args[2..];

        const fmt_str = try unquoteString(allocator, fmt_str_raw);
        defer allocator.free(fmt_str);

        const segments = try parseFormatString(allocator, fmt_str);
        defer {
            for (segments) |seg| {
                if (seg.kind == .literal) allocator.free(seg.text);
            }
            allocator.free(segments);
        }

        var expected_args: usize = 0;
        for (segments) |seg| {
            if (seg.kind == .placeholder) {
                switch (seg.specifier) {
                    .none, .i64, .u64, .f64 => expected_args += 1,
                    .bytes => expected_args += 2,
                }
            }
        }

        if (expected_args != format_args.len) {
            return error.ArgCountMismatch;
        }

        const SegmentData = struct {
            ptr: []const u8,
            len: []const u8,
            owned: bool,
            owned_buf_name: ?[]const u8,
            release_ptr_len: bool,
        };

        var segment_datas = std.array_list.Managed(SegmentData).init(allocator);
        defer {
            for (segment_datas.items) |sd| {
                allocator.free(sd.ptr);
                allocator.free(sd.len);
                if (sd.owned_buf_name) |ob| allocator.free(ob);
            }
            segment_datas.deinit();
        }

        var var_counter: usize = 0;
        var arg_idx: usize = 0;
        for (segments) |seg| {
            if (seg.kind == .literal) {
                const unescaped_len = unescapeLength(seg.text);
                const const_id = const_decls.items.len;
                const const_name = try std.fmt.allocPrint(allocator, "__PRINT_LIT_{d}_{d}", .{ source_line, const_id });
                defer allocator.free(const_name);

                const const_line = try std.fmt.allocPrint(allocator, "@const {s} = utf8:\"{s}\"", .{ const_name, seg.text });
                defer allocator.free(const_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const ptr_str = try std.fmt.allocPrint(allocator, "*{s}", .{const_name});
                const len_str = try std.fmt.allocPrint(allocator, "{d}", .{unescaped_len});

                try segment_datas.append(.{
                    .ptr = ptr_str,
                    .len = len_str,
                    .owned = false,
                    .owned_buf_name = null,
                    .release_ptr_len = false,
                });
            } else {
                const spec = seg.specifier;
                const fmt_buf = try std.fmt.allocPrint(allocator, "__fmt_buf_{d}_{d}", .{ source_line, var_counter });
                const fmt_ptr = try std.fmt.allocPrint(allocator, "__fmt_ptr_{d}_{d}", .{ source_line, var_counter });
                const fmt_len = try std.fmt.allocPrint(allocator, "__fmt_len_{d}_{d}", .{ source_line, var_counter });
                defer {
                    allocator.free(fmt_ptr);
                    allocator.free(fmt_len);
                }
                var_counter += 1;

                const call_line = switch (spec) {
                    .none, .i64 => try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_i64({s}, 10)", .{ fmt_buf, format_args[arg_idx] }),
                    .u64 => try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_u64({s}, 10)", .{ fmt_buf, format_args[arg_idx] }),
                    .f64 => try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_f64({s}, 6)", .{ fmt_buf, format_args[arg_idx] }),
                    .bytes => try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_bytes(&{s}, {s})", .{ fmt_buf, format_args[arg_idx], format_args[arg_idx + 1] }),
                };
                defer allocator.free(call_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, call_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                switch (spec) {
                    .none, .i64, .u64, .f64 => arg_idx += 1,
                    .bytes => arg_idx += 2,
                }

                const ptr_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_data({s})", .{ fmt_ptr, fmt_buf });
                defer allocator.free(ptr_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const len_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_len({s})", .{ fmt_len, fmt_buf });
                defer allocator.free(len_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const ptr_str = try allocator.dupe(u8, fmt_ptr);
                const len_str = try allocator.dupe(u8, fmt_len);

                try segment_datas.append(.{
                    .ptr = ptr_str,
                    .len = len_str,
                    .owned = true,
                    .owned_buf_name = fmt_buf,
                    .release_ptr_len = true,
                });
            }
        }

        if (segment_datas.items.len == 0) {
            const const_id = const_decls.items.len;
            const const_name = try std.fmt.allocPrint(allocator, "__PRINT_LIT_{d}_{d}", .{ source_line, const_id });
            defer allocator.free(const_name);

            const const_line = try std.fmt.allocPrint(allocator, "@const {s} = utf8:\"\"", .{const_name});
            defer allocator.free(const_line);
            try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

            const empty_const_id = const_decls.items.len;
            const empty_const_name = try std.fmt.allocPrint(allocator, "__PRINT_LIT_{d}_{d}", .{ source_line, empty_const_id });
            defer allocator.free(empty_const_name);

            const empty_const_line = try std.fmt.allocPrint(allocator, "@const {s} = utf8:\"\"", .{empty_const_name});
            defer allocator.free(empty_const_line);
            try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, empty_const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

            const concat_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_string_concat(*{s}, 0, *{s}, 0)", .{ dest_reg, const_name, empty_const_name });
            defer allocator.free(concat_line);
            try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, concat_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
        } else if (segment_datas.items.len == 1) {
            const first = segment_datas.items[0];
            if (first.owned) {
                if (first.release_ptr_len) {
                    const ptr_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{first.ptr});
                    defer allocator.free(ptr_release_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_release_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                    const len_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{first.len});
                    defer allocator.free(len_release_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_release_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
                }

                const assign_line = try std.fmt.allocPrint(allocator, "{s} = {s}", .{ dest_reg, first.owned_buf_name.? });
                defer allocator.free(assign_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, assign_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
            } else {
                const const_id = const_decls.items.len;
                const const_name = try std.fmt.allocPrint(allocator, "__PRINT_LIT_{d}_{d}", .{ source_line, const_id });
                defer allocator.free(const_name);

                const const_line = try std.fmt.allocPrint(allocator, "@const {s} = utf8:\"\"", .{const_name});
                defer allocator.free(const_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const concat_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_string_concat({s}, {s}, *{s}, 0)", .{ dest_reg, first.ptr, first.len, const_name });
                defer allocator.free(concat_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, concat_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
            }
        } else {
            const left = segment_datas.items[0];
            var left_owned = left.owned;
            var left_buf_name: ?[]const u8 = if (left_owned) try allocator.dupe(u8, left.owned_buf_name.?) else null;
            var left_release_ptr_len = left.release_ptr_len;
            defer if (left_buf_name) |lbn| allocator.free(lbn);

            var left_ptr = try allocator.dupe(u8, left.ptr);
            var left_len = try allocator.dupe(u8, left.len);
            defer {
                allocator.free(left_ptr);
                allocator.free(left_len);
            }

            var acc_name: ?[]const u8 = null;
            defer if (acc_name) |an| allocator.free(an);

            var i: usize = 1;
            while (i < segment_datas.items.len) : (i += 1) {
                const right = segment_datas.items[i];
                const is_last = (i == segment_datas.items.len - 1);

                const new_acc = if (is_last)
                    dest_reg
                else
                    try std.fmt.allocPrint(allocator, "__fmt_acc_{d}_{d}", .{ source_line, var_counter });
                defer if (!is_last) allocator.free(new_acc);
                if (!is_last) var_counter += 1;

                const concat_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_string_concat({s}, {s}, {s}, {s})", .{ new_acc, left_ptr, left_len, right.ptr, right.len });
                defer allocator.free(concat_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, concat_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                if (left_release_ptr_len) {
                    const ptr_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{left_ptr});
                    defer allocator.free(ptr_release_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_release_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                    const len_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{left_len});
                    defer allocator.free(len_release_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_release_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
                }

                if (left_owned) {
                    const free_ok = try std.fmt.allocPrint(allocator, "__fmt_free_ok_{d}_{d}", .{ source_line, var_counter });
                    defer allocator.free(free_ok);
                    var_counter += 1;

                    const free_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_free(^{s})", .{ free_ok, left_buf_name.? });
                    defer allocator.free(free_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, free_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                    const discard_line = try std.fmt.allocPrint(allocator, "! {s}", .{free_ok});
                    defer allocator.free(discard_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, discard_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
                }

                if (right.release_ptr_len) {
                    const ptr_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{right.ptr});
                    defer allocator.free(ptr_release_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_release_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                    const len_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{right.len});
                    defer allocator.free(len_release_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_release_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
                }

                if (right.owned) {
                    const free_ok = try std.fmt.allocPrint(allocator, "__fmt_free_ok_{d}_{d}", .{ source_line, var_counter });
                    defer allocator.free(free_ok);
                    var_counter += 1;

                    const free_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_free(^{s})", .{ free_ok, right.owned_buf_name.? });
                    defer allocator.free(free_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, free_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                    const discard_line = try std.fmt.allocPrint(allocator, "! {s}", .{free_ok});
                    defer allocator.free(discard_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, discard_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
                }

                if (!is_last) {
                    left_owned = true;
                    left_release_ptr_len = true;
                    if (left_buf_name) |lbn| allocator.free(lbn);
                    left_buf_name = try allocator.dupe(u8, new_acc);

                    const new_ptr = try std.fmt.allocPrint(allocator, "__fmt_ptr_{d}_{d}", .{ source_line, var_counter });
                    const new_len = try std.fmt.allocPrint(allocator, "__fmt_len_{d}_{d}", .{ source_line, var_counter });
                    defer {
                        allocator.free(new_ptr);
                        allocator.free(new_len);
                    }
                    var_counter += 1;

                    const ptr_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_data({s})", .{ new_ptr, new_acc });
                    defer allocator.free(ptr_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                    const len_line = try std.fmt.allocPrint(allocator, "{s} = call @sa_fmt_buffer_len({s})", .{ new_len, new_acc });
                    defer allocator.free(len_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                    allocator.free(left_ptr);
                    allocator.free(left_len);
                    left_ptr = try allocator.dupe(u8, new_ptr);
                    left_len = try allocator.dupe(u8, new_len);

                    if (acc_name) |an| allocator.free(an);
                    acc_name = try allocator.dupe(u8, new_acc);
                } else {
                    left_owned = false;
                    left_release_ptr_len = false;
                    if (left_buf_name) |lbn| {
                        allocator.free(lbn);
                        left_buf_name = null;
                    }
                }
            }
        }
    }
}
