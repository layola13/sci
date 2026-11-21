const std = @import("std");
const sio = @import("sio");
const classifier = @import("line_classifier.zig");
const common_const_decl = @import("../common/const_decl.zig");
const common_upstream = @import("../common/upstream_loc.zig");
const ConstDecl = @import("../common/const_decl.zig").ConstDecl;
const DefDict = @import("def_dict.zig").DefDict;
const FunctionSig = @import("../common/signature.zig").FunctionSig;
const Instruction = @import("../common/instruction.zig").Instruction;
const LocTable = @import("../common/upstream_loc.zig").LocTable;
const SymbolTable = @import("symbol.zig").SymbolTable;
const ErrorContext = @import("importexpansion.zig").ErrorContext;
const MacroDef = @import("importexpansion.zig").MacroDef;
const Replacement = @import("importexpansion.zig").Replacement;
const SourceLine = @import("importexpansion.zig").SourceLine;
const buildHygieneReplacements = @import("renderwithtokenreplacements.zig").buildHygieneReplacements;
const bumpMacroExpansionCounter = @import("importexpansion.zig").bumpMacroExpansionCounter;
const collectDefinedNames = @import("renderwithtokenreplacements.zig").collectDefinedNames;
const collectDefinedNamesFromSlice = @import("renderwithtokenreplacements.zig").collectDefinedNamesFromSlice;
const collectMacroDefinitions = @import("emitparsedline.zig").collectMacroDefinitions;
const emitParsedLine = @import("emitparsedline.zig").emitParsedLine;
const ensureRepExpansionBudget = @import("importexpansion.zig").ensureRepExpansionBudget;
const expandImports = @import("expandimportsinto.zig").expandImports;
const expandPrintOrFormat = @import("expandprintorformat.zig").expandPrintOrFormat;
const expandSourceLocationMacro = @import("emitparsedline.zig").expandSourceLocationMacro;
const findNestedIfBounds = @import("renderwithtokenreplacements.zig").findNestedIfBounds;
const findNestedRepEnd = @import("renderwithtokenreplacements.zig").findNestedRepEnd;
const includeFileAsConst = @import("emitparsedline.zig").includeFileAsConst;
const joinTokens = @import("appendexpandedimportcachehit.zig").joinTokens;
const macroConditionIsTrue = @import("renderwithtokenreplacements.zig").macroConditionIsTrue;
const macroDefBodyLines = @import("appendexpandedimportcachehit.zig").macroDefBodyLines;
const max_macro_recursion_depth = @import("importexpansion.zig").max_macro_recursion_depth;
const parseTokenList = @import("appendexpandedimportcachehit.zig").parseTokenList;
const recordErrorLine = @import("importexpansion.zig").recordErrorLine;
const renderWithTokenReplacements = @import("renderwithtokenreplacements.zig").renderWithTokenReplacements;
const scanSourceWithOrigins = @import("cloneremappedsymboltext.zig").scanSourceWithOrigins;
const setErrorDetail = @import("importexpansion.zig").setErrorDetail;
const setPendingLoc = @import("renderwithtokenreplacements.zig").setPendingLoc;
const takePendingLoc = @import("renderwithtokenreplacements.zig").takePendingLoc;
const unquoteString = @import("expandprintorformat.zig").unquoteString;


fn expandStringify(
    allocator: std.mem.Allocator,
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
    const comma = std.mem.indexOfScalar(u8, args_text, ',') orelse return error.InvalidMacroInvocation;
    const out_reg = std.mem.trim(u8, args_text[0..comma], " \t\r\n");
    const expr_text = std.mem.trim(u8, args_text[comma + 1 ..], " \t\r\n");
    if (out_reg.len == 0 or expr_text.len == 0) return error.InvalidMacroInvocation;

    const const_name = try std.fmt.allocPrint(allocator, "__STRINGIFY_LIT_{d}_{d}", .{ source_line, const_decls.items.len });
    defer allocator.free(const_name);

    var hex = std.array_list.Managed(u8).init(allocator);
    errdefer hex.deinit();
    try hex.appendSlice("hex:");
    for (expr_text) |b| {
        var hex_byte_buf: [4]u8 = undefined;
        try hex.appendSlice(try std.fmt.bufPrint(&hex_byte_buf, "\\x{X:0>2}", .{b}));
    }

    const const_line = try std.fmt.allocPrint(allocator, "@const {s} = {s}", .{ const_name, hex.items });
    defer allocator.free(const_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    hex.deinit();

    const len = expr_text.len;
    const ptr_line = try std.fmt.allocPrint(allocator, "store {s}+Slice_ptr, &{s} as ptr", .{ out_reg, const_name });
    defer allocator.free(ptr_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

    const len_line = try std.fmt.allocPrint(allocator, "store {s}+Slice_len, {d} as u64", .{ out_reg, len });
    defer allocator.free(len_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
}

fn expandEnvMacro(
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
    const comma = std.mem.indexOfScalar(u8, args_text, ',') orelse return error.InvalidMacroInvocation;
    const out_reg = std.mem.trim(u8, args_text[0..comma], " \t\r\n");
    const key_text = std.mem.trim(u8, args_text[comma + 1 ..], " \t\r\n");
    if (out_reg.len == 0 or key_text.len == 0) return error.InvalidMacroInvocation;

    const key_raw = try unquoteString(allocator, key_text);
    defer allocator.free(key_raw);
    if (key_raw.len == 0) return error.InvalidMacroInvocation;

    const env_value = sio.getEnvVarOwned(allocator, key_raw) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            if (std.mem.eql(u8, macro_name, "OPTION_ENV!")) {
                const none_tag_line = try std.fmt.allocPrint(allocator, "store {s}+Option_tag, Option_NONE as u64", .{out_reg});
                defer allocator.free(none_tag_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, none_tag_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

                const none_value_line = try std.fmt.allocPrint(allocator, "store {s}+Option_value, 0 as u64", .{out_reg});
                defer allocator.free(none_value_line);
                try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, none_value_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
                return;
            }
            return error.InvalidMacroInvocation;
        },
        else => return err,
    };
    defer allocator.free(env_value);

    const const_name = try std.fmt.allocPrint(allocator, "__ENV_LIT_{d}_{d}", .{ source_line, const_decls.items.len });
    defer allocator.free(const_name);

    var hex = std.array_list.Managed(u8).init(allocator);
    errdefer hex.deinit();
    try hex.appendSlice("hex:");
    for (env_value) |b| {
        var hex_byte_buf: [4]u8 = undefined;
        try hex.appendSlice(try std.fmt.bufPrint(&hex_byte_buf, "\\x{X:0>2}", .{b}));
    }

    const const_line = try std.fmt.allocPrint(allocator, "@const {s} = {s}", .{ const_name, hex.items });
    defer allocator.free(const_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    hex.deinit();

    const value_len = env_value.len;
    if (std.mem.eql(u8, macro_name, "ENV!")) {
        const ptr_line = try std.fmt.allocPrint(allocator, "store {s}+Slice_ptr, &{s} as ptr", .{ out_reg, const_name });
        defer allocator.free(ptr_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

        const len_line = try std.fmt.allocPrint(allocator, "store {s}+Slice_len, {d} as u64", .{ out_reg, value_len });
        defer allocator.free(len_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, len_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
        return;
    }

    if (!std.mem.eql(u8, macro_name, "OPTION_ENV!")) return error.InvalidMacroInvocation;

    const slice_reg = try std.fmt.allocPrint(allocator, "__ENV_SLICE_{d}_{d}", .{ source_line, const_decls.items.len });
    defer allocator.free(slice_reg);

    const slice_alloc_line = try std.fmt.allocPrint(allocator, "{s} = stack_alloc Slice_SIZE", .{slice_reg});
    defer allocator.free(slice_alloc_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, slice_alloc_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

    const slice_ptr_line = try std.fmt.allocPrint(allocator, "store {s}+Slice_ptr, &{s} as ptr", .{ slice_reg, const_name });
    defer allocator.free(slice_ptr_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, slice_ptr_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

    const slice_len_line = try std.fmt.allocPrint(allocator, "store {s}+Slice_len, {d} as u64", .{ slice_reg, value_len });
    defer allocator.free(slice_len_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, slice_len_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

    const some_tag_line = try std.fmt.allocPrint(allocator, "store {s}+Option_tag, Option_SOME as u64", .{out_reg});
    defer allocator.free(some_tag_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, some_tag_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

    const some_value_line = try std.fmt.allocPrint(allocator, "store {s}+Option_value, {s} as ptr", .{ out_reg, slice_reg });
    defer allocator.free(some_value_line);
    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, some_value_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
}

pub fn emitRange(
    allocator: std.mem.Allocator,
    lines: []const SourceLine,
    start: usize,
    end: usize,
    depth: u16,
    source_line_override: ?u32,
    source_path: ?[]const u8,
    include_stack: *std.array_list.Managed([]const u8),
    macro_call_stack: *std.array_list.Managed(*const MacroDef),
    replacements: []const Replacement,
    top_level: bool,
    macros: *std.StringHashMap(MacroDef),
    dict: *DefDict,
    symbols: *SymbolTable,
    loc_table: *std.array_list.Managed(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
    instructions: *std.array_list.Managed(Instruction),
    const_decls: *std.array_list.Managed(ConstDecl),
    function_sigs: *std.array_list.Managed(FunctionSig),
    owned_text: *std.array_list.Managed([]const u8),
    error_ctx: ?*ErrorContext,
    current_package_identity: ?[]const u8,
    current_package_hash: ?[32]u8,
    expansion_counter: *u64,
) !void {
    if (depth > max_macro_recursion_depth) return error.MacroRecursionLimit;

    var idx = start;
    while (idx < end) : (idx += 1) {
        const line = lines[idx];
        const source_line = source_line_override orelse line.line_no;
        const effective_package_identity = line.package_identity orelse current_package_identity;
        recordErrorLine(error_ctx, line, source_line);

        switch (line.classified.kind) {
            .blank_or_comment, .import_decl, .version => {},
            .const_decl => {
                if (!top_level) return error.InvalidMacroDefinitionContext;
                const upstream_loc = takePendingLoc(pending_loc);
                errdefer if (upstream_loc) |loc| allocator.free(loc.file);
                var decl = try common_const_decl.parseConstDecl(
                    allocator,
                    line.text,
                    source_line,
                    @intCast(instructions.items.len),
                    upstream_loc,
                );
                errdefer decl.deinit(allocator);
                _ = try symbols.intern(decl.name);
                try const_decls.append(decl);
            },
            .loc_hint => {
                const line_no = try std.fmt.parseInt(u32, line.classified.parts[1], 10);
                const col_no = try std.fmt.parseInt(u32, line.classified.parts[2], 10);
                try setPendingLoc(allocator, pending_loc, line.classified.parts[0], line_no, col_no);
            },
            .def, .npm_bind, .label, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl, .instruction, .native, .unknown => {
                const should_render = source_line_override != null or replacements.len != 0;
                if (should_render) {
                    const rendered = try renderWithTokenReplacements(allocator, line.text, replacements);
                    try owned_text.append(rendered);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, rendered, source_line, instructions, const_decls, function_sigs, owned_text, effective_package_identity, line.package_source_sha256 orelse current_package_hash);
                } else {
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, line.text, source_line, instructions, const_decls, function_sigs, owned_text, effective_package_identity, line.package_source_sha256 orelse current_package_hash);
                }
            },
            .macro_start => {
                if (!top_level) return error.InvalidMacroDefinitionContext;
                const def = macros.get(line.classified.parts[0]) orelse return error.InvalidMacroInvocation;
                idx = def.body_end;
            },
            .macro_end => return error.UnbalancedMacro,
            .rep_start => {
                const count_text = try dict.foldText(allocator, line.classified.parts[0]);
                try owned_text.append(count_text);
                const count = std.fmt.parseInt(usize, count_text, 10) catch return error.MacroExpansionBudget;
                const rep_end = findNestedRepEnd(lines, idx + 1) orelse return error.UnbalancedRep;
                try ensureRepExpansionBudget(count, rep_end - (idx + 1));

                var rep_index: usize = 0;
                while (rep_index < count) : (rep_index += 1) {
                    const expansion_id = try bumpMacroExpansionCounter(expansion_counter);
                    var rep_defined_names = try collectDefinedNames(allocator, lines, idx + 1, rep_end);
                    defer rep_defined_names.deinit();
                    var hygiene_replacements = try buildHygieneReplacements(allocator, &rep_defined_names, expansion_id);
                    defer {
                        for (hygiene_replacements.items) |r| allocator.free(r.replacement);
                        hygiene_replacements.deinit();
                    }

                    const rep_value = try std.fmt.allocPrint(allocator, "{d}", .{rep_index});
                    defer allocator.free(rep_value);

                    var list = std.array_list.Managed(Replacement).init(allocator);
                    errdefer list.deinit();
                    try list.appendSlice(hygiene_replacements.items);
                    try list.appendSlice(replacements);
                    try list.append(.{ .needle = "%i", .replacement = rep_value });
                    const combined = try list.toOwnedSlice();
                    defer allocator.free(combined);

                    try emitRange(
                        allocator,
                        lines,
                        idx + 1,
                        rep_end,
                        depth + 1,
                        source_line_override orelse line.line_no,
                        source_path,
                        include_stack,
                        macro_call_stack,
                        combined,
                        false,
                        macros,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        error_ctx,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                        expansion_counter,
                    );
                }

                idx = rep_end;
            },
            .rep_end => return error.UnbalancedRep,
            .if_start => {
                const bounds = findNestedIfBounds(lines, idx + 1) orelse return error.InvalidMacroInvocation;
                const condition_text = if (replacements.len == 0)
                    try allocator.dupe(u8, line.classified.parts[0])
                else
                    try renderWithTokenReplacements(allocator, line.classified.parts[0], replacements);
                defer allocator.free(condition_text);
                try owned_text.append(try allocator.dupe(u8, condition_text));

                const condition_true = try macroConditionIsTrue(condition_text);
                const selected_start = if (condition_true) idx + 1 else (if (bounds.else_idx) |else_idx| else_idx + 1 else bounds.end_idx);
                const selected_end = if (condition_true) (bounds.else_idx orelse bounds.end_idx) else bounds.end_idx;
                if (selected_start < selected_end) {
                    try emitRange(
                        allocator,
                        lines,
                        selected_start,
                        selected_end,
                        depth + 1,
                        source_line_override orelse line.line_no,
                        source_path,
                        include_stack,
                        macro_call_stack,
                        replacements,
                        false,
                        macros,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        error_ctx,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                        expansion_counter,
                    );
                }
                idx = bounds.end_idx;
            },
            .else_, .if_end => return error.InvalidMacroInvocation,
            .expand => {
                const rendered_line = if (replacements.len == 0) line.text else blk: {
                    const rendered = try renderWithTokenReplacements(allocator, line.text, replacements);
                    try owned_text.append(rendered);
                    break :blk rendered;
                };
                const rendered_classified = classifier.classifyLine(rendered_line);
                if (rendered_classified.kind != .expand) return error.InvalidSyntax;
                const macro_name = rendered_classified.parts[0];
                if (std.mem.eql(u8, macro_name, "PRINT!") or std.mem.eql(u8, macro_name, "FORMAT!")) {
                    try expandPrintOrFormat(
                        allocator,
                        macro_name,
                        rendered_classified.parts[1],
                        source_line,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                    );
                } else if (std.mem.eql(u8, macro_name, "STRINGIFY!")) {
                    try expandStringify(
                        allocator,
                        rendered_classified.parts[1],
                        source_line,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                    );
                } else if (std.mem.eql(u8, macro_name, "CFG!")) {
                    const cfg_args = try parseTokenList(allocator, rendered_classified.parts[1]);
                    defer allocator.free(cfg_args);
                    if (cfg_args.len != 2) return error.InvalidMacroInvocation;
                    const cfg_macro_line = try std.fmt.allocPrint(allocator, "EXPAND CFG {s}, {s}", .{ cfg_args[0], cfg_args[1] });
                    defer allocator.free(cfg_macro_line);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, cfg_macro_line, source_line, instructions, const_decls, function_sigs, owned_text, effective_package_identity, line.package_source_sha256 orelse current_package_hash);
                } else if (std.mem.eql(u8, macro_name, "ENV!") or std.mem.eql(u8, macro_name, "OPTION_ENV!")) {
                    try expandEnvMacro(
                        allocator,
                        macro_name,
                        rendered_classified.parts[1],
                        source_line,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                    );
                } else if (std.mem.eql(u8, macro_name, "LINE!") or std.mem.eql(u8, macro_name, "FILE!") or std.mem.eql(u8, macro_name, "COLUMN!") or std.mem.eql(u8, macro_name, "MODULE_PATH!")) {
                    try expandSourceLocationMacro(
                        allocator,
                        macro_name,
                        rendered_classified.parts[1],
                        source_line,
                        source_path,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                    );
                } else if (std.mem.eql(u8, macro_name, "INCLUDE!")) {
                    const include_args = try parseTokenList(allocator, rendered_classified.parts[1]);
                    defer allocator.free(include_args);
                    if (include_args.len != 1) return error.InvalidMacroInvocation;
                    const include_path_raw = try unquoteString(allocator, include_args[0]);
                    defer allocator.free(include_path_raw);

                    const resolved_path = if (std.fs.path.isAbsolute(include_path_raw)) blk: {
                        break :blk try allocator.dupe(u8, include_path_raw);
                    } else if (source_path) |sp| blk: {
                        const base = std.fs.path.dirname(sp) orelse ".";
                        break :blk try std.fs.path.join(allocator, &.{ base, include_path_raw });
                    } else blk: {
                        break :blk try allocator.dupe(u8, include_path_raw);
                    };
                    defer allocator.free(resolved_path);

                    for (include_stack.items) |active| {
                        if (std.mem.eql(u8, active, resolved_path)) return error.IncludeCycle;
                    }

                    const source = try sio.cwd().readFileAlloc(allocator, resolved_path, 1 << 20);
                    defer allocator.free(source);
                    try include_stack.append(try allocator.dupe(u8, resolved_path));
                    defer {
                        const popped = include_stack.pop();
                        allocator.free(popped.?);
                    }

                    var expanded = try expandImports(allocator, source, resolved_path, error_ctx, null);
                    defer expanded.deinit(allocator);
                    const included_lines = try scanSourceWithOrigins(allocator, expanded.source, expanded.line_package_identities.items[0..], expanded.line_package_hashes.items[0..], expanded.line_origin_paths.items[0..], expanded.line_origin_lines.items[0..]);
                    defer allocator.free(included_lines);
                    try collectMacroDefinitions(allocator, included_lines, macros, error_ctx);
                    try emitRange(
                        allocator,
                        included_lines,
                        0,
                        included_lines.len,
                        depth + 1,
                        null,
                        resolved_path,
                        include_stack,
                        macro_call_stack,
                        replacements,
                        false,
                        macros,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        error_ctx,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                        expansion_counter,
                    );
                } else if (std.mem.eql(u8, macro_name, "INCLUDE_STR!") or std.mem.eql(u8, macro_name, "INCLUDE_BYTES!")) {
                    try includeFileAsConst(
                        allocator,
                        if (std.mem.eql(u8, macro_name, "INCLUDE_STR!")) .str else .bytes,
                        rendered_classified.parts[1],
                        source_line,
                        line.package_identity,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                    );
                } else {
                    const def = macros.getPtr(macro_name) orelse {
                        // Name the missing macro and keep the EXPAND line's
                        // origin (recorded at the top of this loop iteration)
                        // so the diagnostic points at the real invocation
                        // site instead of an unrelated expanded-source line.
                        setErrorDetail(error_ctx, macro_name);
                        return error.UndefinedMacro;
                    };
                    for (macro_call_stack.items) |active_macro| {
                        if (active_macro == def) return error.MacroRecursionLimit;
                    }
                    try macro_call_stack.append(def);
                    defer _ = macro_call_stack.pop();
                    const body_lines = try macroDefBodyLines(def);
                    const args = try parseTokenList(allocator, rendered_classified.parts[1]);
                    defer allocator.free(args);
                    if (def.variadic_param) |variadic_param| {
                        if (args.len < def.params.len) return error.InvalidMacroInvocation;

                        const expansion_id = try bumpMacroExpansionCounter(expansion_counter);
                        var var_defined_names = try collectDefinedNamesFromSlice(allocator, body_lines);
                        defer var_defined_names.deinit();
                        var var_hygiene = try buildHygieneReplacements(allocator, &var_defined_names, expansion_id);
                        defer {
                            for (var_hygiene.items) |r| allocator.free(r.replacement);
                            var_hygiene.deinit();
                        }

                        var local_replacements = std.array_list.Managed(Replacement).init(allocator);
                        errdefer local_replacements.deinit();
                        try local_replacements.appendSlice(var_hygiene.items);
                        for (def.params, 0..) |param, iarg| {
                            try local_replacements.append(.{ .needle = param, .replacement = args[iarg] });
                        }
                        const variadic_args = args[def.params.len..];
                        const joined = try joinTokens(allocator, variadic_args);
                        defer allocator.free(joined);
                        try local_replacements.append(.{ .needle = variadic_param, .replacement = joined });
                        const local_slice = try local_replacements.toOwnedSlice();
                        defer allocator.free(local_slice);
                        try emitRange(
                            allocator,
                            body_lines,
                            0,
                            body_lines.len,
                            depth + 1,
                            source_line_override orelse line.line_no,
                            source_path,
                            include_stack,
                            macro_call_stack,
                            local_slice,
                            false,
                            macros,
                            dict,
                            symbols,
                            loc_table,
                            pending_loc,
                            instructions,
                            const_decls,
                            function_sigs,
                            owned_text,
                            error_ctx,
                            effective_package_identity,
                            line.package_source_sha256 orelse current_package_hash,
                            expansion_counter,
                        );
                        continue;
                    }

                    if (args.len != def.params.len) return error.InvalidMacroInvocation;

                    const expansion_id = try bumpMacroExpansionCounter(expansion_counter);
                    var nv_defined_names = try collectDefinedNamesFromSlice(allocator, body_lines);
                    defer nv_defined_names.deinit();
                    var nv_hygiene = try buildHygieneReplacements(allocator, &nv_defined_names, expansion_id);
                    defer {
                        for (nv_hygiene.items) |r| allocator.free(r.replacement);
                        nv_hygiene.deinit();
                    }

                    var local_replacements = std.array_list.Managed(Replacement).init(allocator);
                    errdefer local_replacements.deinit();
                    try local_replacements.appendSlice(nv_hygiene.items);
                    for (def.params, 0..) |param, iarg| {
                        try local_replacements.append(.{ .needle = param, .replacement = args[iarg] });
                    }
                    const local_slice = try local_replacements.toOwnedSlice();
                    defer allocator.free(local_slice);
                    try emitRange(
                        allocator,
                        body_lines,
                        0,
                        body_lines.len,
                        depth + 1,
                        source_line_override orelse line.line_no,
                        source_path,
                        include_stack,
                        macro_call_stack,
                        local_slice,
                        false,
                        macros,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        error_ctx,
                        effective_package_identity,
                        line.package_source_sha256 orelse current_package_hash,
                        expansion_counter,
                    );
                }
            },
        }
    }
}

pub fn collectLocTableEntries(
    allocator: std.mem.Allocator,
    instructions: []const Instruction,
) !LocTable {
    var table = std.array_list.Managed(?common_upstream.UpstreamLoc).init(allocator);
    errdefer table.deinit();

    for (instructions) |item| {
        const keep_loc = switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .label => false,
            else => true,
        };
        if (keep_loc) {
            if (item.upstream_loc) |loc| {
                const file_copy = try allocator.dupe(u8, loc.file);
                errdefer allocator.free(file_copy);
                try table.append(.{
                    .file = file_copy,
                    .line = loc.line,
                    .col = loc.col,
                });
            } else {
                try table.append(null);
            }
        } else {
            try table.append(null);
        }
    }

    return try table.toOwnedSlice();
}
