const std = @import("std");
const sio = @import("sio");
const forbidden = @import("forbidden.zig");
const common_instruction = @import("../common/instruction.zig");
const common_upstream = @import("../common/upstream_loc.zig");
const ErrorContext = @import("importexpansion.zig").ErrorContext;
const LayoutVersion = @import("importexpansion.zig").LayoutVersion;
const MacroDef = @import("importexpansion.zig").MacroDef;
const Replacement = @import("importexpansion.zig").Replacement;
const ResolveContext = @import("importexpansion.zig").ResolveContext;
const appendFlattenFragment = @import("cloneremappedsymboltext.zig").appendFlattenFragment;
const captureCachedMacroDefs = @import("appendexpandedimportcachehit.zig").captureCachedMacroDefs;
const collectMacroDefinitions = @import("emitparsedline.zig").collectMacroDefinitions;
const deinitCachedMacroDefs = @import("appendexpandedimportcachehit.zig").deinitCachedMacroDefs;
const deinitMacroMap = @import("appendexpandedimportcachehit.zig").deinitMacroMap;
const emitRange = @import("emitrange.zig").emitRange;
const errorReport = @import("importexpansion.zig").errorReport;
const findFirstForbiddenLine = @import("expandimportsinto.zig").findFirstForbiddenLine;
const flatten = @import("expandimportsinto.zig").flatten;
const flattenFile = @import("expandimportsinto.zig").flattenFile;
const flattenFileWithContext = @import("expandimportsinto.zig").flattenFileWithContext;
const macroDefBodyLines = @import("appendexpandedimportcachehit.zig").macroDefBodyLines;
const ownText = @import("renderwithtokenreplacements.zig").ownText;
const readImportFile = @import("injectimportedfile.zig").readImportFile;
const restoreCachedMacroDefs = @import("appendexpandedimportcachehit.zig").restoreCachedMacroDefs;
const scanSource = @import("cloneremappedsymboltext.zig").scanSource;


test "frontend cache append fragment remaps and merges end to end" {
    const source =
        \\#def SIZE = 8
        \\@const HELLO = utf8:"hello"
        \\@main() -> i32:
        \\L_MAIN:
        \\tmp = alloc SIZE
        \\return 0
        \\@test should_panic "panic path"():
        \\L_TEST:
        \\panic 32
    ;
    var fragment = try flatten(std.testing.allocator, source);
    defer fragment.deinit(std.testing.allocator);

    std.testing.allocator.free(fragment.layout_versions);
    fragment.layout_versions = try std.testing.allocator.alloc(LayoutVersion, 1);
    fragment.layout_versions[0] = .{
        .path = try std.testing.allocator.dupe(u8, "pkg/layout.sal"),
        .version = 42,
    };
    try fragment.package_identities.put(try std.testing.allocator.dupe(u8, "pkg/core"), {});

    var target_instructions = std.array_list.Managed(Instruction).init(std.testing.allocator);
    defer {
        for (target_instructions.items) |item| {
            if (item.package_identity) |identity| std.testing.allocator.free(identity);
            if (item.upstream_loc) |loc| std.testing.allocator.free(loc.file);
            if (item.native_reg_names.len != 0) std.testing.allocator.free(item.native_reg_names);
        }
        target_instructions.deinit();
    }
    var target_const_decls = std.array_list.Managed(ConstDecl).init(std.testing.allocator);
    defer {
        for (target_const_decls.items) |*decl| decl.deinit(std.testing.allocator);
        target_const_decls.deinit();
    }
    var target_function_sigs = std.array_list.Managed(FunctionSig).init(std.testing.allocator);
    defer {
        for (target_function_sigs.items) |*sig| sig.deinit(std.testing.allocator);
        target_function_sigs.deinit();
    }
    var target_test_sigs = std.array_list.Managed(FunctionSig).init(std.testing.allocator);
    defer {
        for (target_test_sigs.items) |*sig| sig.deinit(std.testing.allocator);
        target_test_sigs.deinit();
    }
    var target_def_dict = DefDict.init(std.testing.allocator);
    defer target_def_dict.deinit();
    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();
    var target_layout_versions = std.array_list.Managed(LayoutVersion).init(std.testing.allocator);
    defer {
        for (target_layout_versions.items) |*item| item.deinit(std.testing.allocator);
        target_layout_versions.deinit();
    }
    var target_package_identities = std.StringHashMap(void).init(std.testing.allocator);
    defer {
        var it = target_package_identities.iterator();
        while (it.next()) |entry| std.testing.allocator.free(entry.key_ptr.*);
        target_package_identities.deinit();
    }
    var target_owned_text = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer {
        for (target_owned_text.items) |text| std.testing.allocator.free(text);
        target_owned_text.deinit();
    }
    var target_macros = std.StringHashMap(MacroDef).init(std.testing.allocator);
    defer deinitMacroMap(std.testing.allocator, &target_macros);

    _ = try target_symbols.intern("occupied");
    try target_def_dict.putExpression("EXISTING", "1");
    try target_package_identities.put(try std.testing.allocator.dupe(u8, "pkg/seed"), {});
    try target_function_sigs.append(.{
        .id = 99,
        .name = try std.testing.allocator.dupe(u8, "seed"),
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .void,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
    });
    try target_instructions.append(common_instruction.makeInstruction(
        .label,
        1,
        0,
        null,
        try ownText(std.testing.allocator, &target_owned_text, "L_SEED:"),
    ));

    try appendFlattenFragment(
        std.testing.allocator,
        &target_instructions,
        &target_const_decls,
        &target_function_sigs,
        &target_test_sigs,
        &target_def_dict,
        &target_symbols,
        &target_layout_versions,
        &target_package_identities,
        &target_owned_text,
        &target_macros,
        &fragment,
        10,
        20,
    );

    try std.testing.expectEqual(@as(usize, 1 + fragment.instructions.len), target_instructions.items.len);
    try std.testing.expectEqual(@as(usize, 1), target_const_decls.items.len);
    try std.testing.expectEqual(@as(usize, 1 + fragment.function_sigs.len), target_function_sigs.items.len);
    try std.testing.expectEqual(@as(usize, fragment.test_sigs.len), target_test_sigs.items.len);
    try std.testing.expectEqualStrings("8", target_def_dict.get("SIZE").?);
    try std.testing.expectEqualStrings("1", target_def_dict.get("EXISTING").?);
    try std.testing.expectEqual(@as(u32, 2), target_package_identities.count());
    try std.testing.expectEqual(@as(usize, 1), target_layout_versions.items.len);
    try std.testing.expectEqualStrings("pkg/layout.sal", target_layout_versions.items[0].path);
    try std.testing.expectEqual(@as(u64, 42), target_layout_versions.items[0].version);
    try std.testing.expect(target_layout_versions.items[0].path.ptr != fragment.layout_versions[0].path.ptr);

    try std.testing.expectEqualStrings("HELLO", target_const_decls.items[0].name);
    try std.testing.expectEqual(@as(u32, fragment.const_decls[0].source_line + 10), target_const_decls.items[0].source_line);
    try std.testing.expectEqual(@as(u32, fragment.const_decls[0].expanded_line + 20), target_const_decls.items[0].expanded_line);

    try std.testing.expectEqual(@as(u32, 99), target_function_sigs.items[0].id);
    try std.testing.expectEqual(@as(u32, fragment.function_sigs[0].id + 1), target_function_sigs.items[1].id);
    try std.testing.expectEqual(@as(u32, fragment.function_sigs[1].id + 1), target_function_sigs.items[2].id);
    try std.testing.expectEqual(@as(u32, fragment.function_sigs[0].entry_inst_idx + 1), target_function_sigs.items[1].entry_inst_idx);
    try std.testing.expectEqual(@as(u32, fragment.function_sigs[1].entry_inst_idx + 1), target_function_sigs.items[2].entry_inst_idx);
    try std.testing.expect(target_function_sigs.items[2].should_panic);
    try std.testing.expectEqualStrings("\"panic path\"", target_test_sigs.items[0].name);
    try std.testing.expect(target_test_sigs.items[0].name.ptr != target_function_sigs.items[2].name.ptr);

    try std.testing.expectEqual(@as(u32, fragment.instructions[0].source_line + 10), target_instructions.items[1].source_line);
    try std.testing.expectEqual(@as(u32, fragment.instructions[0].expanded_line + 20), target_instructions.items[1].expanded_line);
    try std.testing.expectEqualStrings(fragment.instructions[0].raw_text, target_instructions.items[1].raw_text);
    try std.testing.expect(target_instructions.items[1].raw_text.ptr != fragment.instructions[0].raw_text.ptr);

    try std.testing.expect(target_macros.contains("SIZE") == false);
}

test "frontend cache append fragment restores imported macro defs for later expansion" {
    const imported_source =
        \\[MACRO] MAKE_TMP %out
        \\    _tmp = add 0, 7
        \\    %out = add _tmp, 0
        \\[END_MACRO]
    ;
    var fragment = try flatten(std.testing.allocator, imported_source);
    defer fragment.deinit(std.testing.allocator);

    var target_instructions = std.array_list.Managed(Instruction).init(std.testing.allocator);
    defer {
        for (target_instructions.items) |item| {
            if (item.package_identity) |identity| std.testing.allocator.free(identity);
            if (item.upstream_loc) |loc| std.testing.allocator.free(loc.file);
            if (item.native_reg_names.len != 0) std.testing.allocator.free(item.native_reg_names);
        }
        target_instructions.deinit();
    }
    var target_const_decls = std.array_list.Managed(ConstDecl).init(std.testing.allocator);
    defer {
        for (target_const_decls.items) |*decl| decl.deinit(std.testing.allocator);
        target_const_decls.deinit();
    }
    var target_function_sigs = std.array_list.Managed(FunctionSig).init(std.testing.allocator);
    defer {
        for (target_function_sigs.items) |*sig| sig.deinit(std.testing.allocator);
        target_function_sigs.deinit();
    }
    var target_test_sigs = std.array_list.Managed(FunctionSig).init(std.testing.allocator);
    defer {
        for (target_test_sigs.items) |*sig| sig.deinit(std.testing.allocator);
        target_test_sigs.deinit();
    }
    var target_def_dict = DefDict.init(std.testing.allocator);
    defer target_def_dict.deinit();
    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();
    var target_layout_versions = std.array_list.Managed(LayoutVersion).init(std.testing.allocator);
    defer {
        for (target_layout_versions.items) |*item| item.deinit(std.testing.allocator);
        target_layout_versions.deinit();
    }
    var target_package_identities = std.StringHashMap(void).init(std.testing.allocator);
    defer {
        var it = target_package_identities.iterator();
        while (it.next()) |entry| std.testing.allocator.free(entry.key_ptr.*);
        target_package_identities.deinit();
    }
    var target_owned_text = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer {
        for (target_owned_text.items) |text| std.testing.allocator.free(text);
        target_owned_text.deinit();
    }
    var target_macros = std.StringHashMap(MacroDef).init(std.testing.allocator);
    defer deinitMacroMap(std.testing.allocator, &target_macros);

    try appendFlattenFragment(
        std.testing.allocator,
        &target_instructions,
        &target_const_decls,
        &target_function_sigs,
        &target_test_sigs,
        &target_def_dict,
        &target_symbols,
        &target_layout_versions,
        &target_package_identities,
        &target_owned_text,
        &target_macros,
        &fragment,
        0,
        0,
    );

    const source =
        \\@main() -> i32:
        \\    EXPAND MAKE_TMP out
        \\    return out
    ;
    const lines = try scanSource(std.testing.allocator, source, &.{}, &.{});
    defer std.testing.allocator.free(lines);

    const empty_replacements = [_]Replacement{};
    var pending_loc: ?common_upstream.UpstreamLoc = null;
    defer if (pending_loc) |loc| std.testing.allocator.free(loc.file);
    var loc_table = std.array_list.Managed(?common_upstream.UpstreamLoc).init(std.testing.allocator);
    defer {
        for (loc_table.items) |entry| {
            if (entry) |loc| std.testing.allocator.free(loc.file);
        }
        loc_table.deinit();
    }
    var include_stack = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer include_stack.deinit();
    var macro_call_stack = std.array_list.Managed(*const MacroDef).init(std.testing.allocator);
    defer macro_call_stack.deinit();
    var expansion_counter: u64 = 0;

    try emitRange(
        std.testing.allocator,
        lines,
        0,
        lines.len,
        0,
        null,
        null,
        &include_stack,
        &macro_call_stack,
        empty_replacements[0..],
        true,
        &target_macros,
        &target_def_dict,
        &target_symbols,
        &loc_table,
        &pending_loc,
        &target_instructions,
        &target_const_decls,
        &target_function_sigs,
        &target_owned_text,
        null,
        null,
        null,
        &expansion_counter,
    );

    try std.testing.expect(target_symbols.findId("out") != null);
    try std.testing.expect(target_symbols.findId("_tmp__sa_hyg1") != null);
}

test "cached macro helper path survives allocation failure injection" {
    const Ctx = struct {
        fn run(allocator: std.mem.Allocator) !void {
            const package_identity = "pkg:macro-cache-test";
            const source =
                \\[MACRO] MAKE_TMP %out
                \\    _tmp = add 0, 7
                \\    %out = add _tmp, 0
                \\[END_MACRO]
            ;
            const identities = [_]?[]const u8{
                package_identity,
                package_identity,
                package_identity,
                package_identity,
            };
            const lines = try scanSource(allocator, source, identities[0..], &.{});
            defer allocator.free(lines);

            var source_macros = std.StringHashMap(MacroDef).init(allocator);
            defer deinitMacroMap(allocator, &source_macros);
            try collectMacroDefinitions(allocator, lines, &source_macros, null);

            const cached_defs = try captureCachedMacroDefs(allocator, &source_macros);
            defer deinitCachedMacroDefs(allocator, cached_defs);

            var target_macros = std.StringHashMap(MacroDef).init(allocator);
            defer deinitMacroMap(allocator, &target_macros);

            try restoreCachedMacroDefs(allocator, cached_defs, &target_macros);
            const restored = target_macros.getPtr("MAKE_TMP") orelse return error.MissingRestoredMacro;
            try std.testing.expectEqual(@as(usize, 1), restored.params.len);
            try std.testing.expectEqualStrings("%out", restored.params[0]);
            try std.testing.expectEqual(@as(usize, 2), restored.owned_body_lines.len);
            try std.testing.expectEqualStrings(package_identity, restored.owned_body_lines[0].package_identity.?);
        }
    };

    try std.testing.checkAllAllocationFailures(std.testing.allocator, Ctx.run, .{});
}

test "macroDefBodyLines rejects missing owned macro body" {
    const macro_params = [_][]const u8{"%out"};
    const def = MacroDef{
        .params = macro_params[0..],
        .body_start = 1,
        .body_end = 3,
    };

    try std.testing.expectError(error.InvalidMacroInvocation, macroDefBodyLines(&def));
}

test "findFirstForbiddenLine skips native blocks and catches keywords" {
    const source =
        \\$if not scanned$
        \\let x = 1
        \\foo.a.b
    ;
    const hit = findFirstForbiddenLine(source).?;
    try std.testing.expectEqual(@as(u32, 3), hit.line_no);
    try std.testing.expectEqual(forbidden.ForbiddenToken.property_chain, hit.hit.token);
}

test "flatten builds instruction stream with symbol and def tables" {
    const source =
        \\#def SIZE = 8
        \\@entry() -> i32:
        \\L_ENTRY:
        \\node = alloc SIZE
        \\return node
    ;
    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), result.instructions.len);
    try std.testing.expectEqual(@as(usize, 1), result.function_sigs.len);
    try std.testing.expectEqual(InstKind.func_decl, result.instructions[0].kind);
    try std.testing.expectEqual(InstKind.label, result.instructions[1].kind);
    try std.testing.expectEqual(InstKind.alloc, result.instructions[2].kind);
    try std.testing.expectEqual(InstKind.return_, result.instructions[3].kind);
    try std.testing.expectEqualStrings("8", result.def_dict.get("SIZE").?);
    try std.testing.expectEqualStrings("entry", result.symbols.lookupName(0).?);
    try std.testing.expectEqualStrings("L_ENTRY", result.symbols.lookupName(1).?);
    try std.testing.expectEqualStrings("entry", result.function_sigs[0].name);
    try std.testing.expectEqual(@as(usize, result.instructions.len), result.loc_table.len);
}

test "flatten preserves structured const declarations separately from instructions" {
    const source =
        \\#loc "main.rs":7:3
        \\@const HELLO = utf8:"hello"
        \\@main() -> i32:
        \\L_ENTRY:
        \\return 0
    ;
    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), result.instructions.len);
    try std.testing.expectEqual(@as(usize, 1), result.const_decls.len);
    try std.testing.expectEqualStrings("HELLO", result.const_decls[0].name);
    try std.testing.expectEqualStrings("utf8:\"hello\"", result.const_decls[0].literal_text);
    try std.testing.expect(result.const_decls[0].upstream_loc != null);
    try std.testing.expectEqualStrings("main.rs", result.const_decls[0].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 7), result.const_decls[0].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 3), result.const_decls[0].upstream_loc.?.col);
    switch (result.const_decls[0].value) {
        .utf8 => |literal| try std.testing.expectEqualStrings("hello", literal.bytes),
        else => return error.TestUnexpectedResult,
    }
}

test "flatten keeps native escape text and extracted register names" {
    const source =
        \\@main() -> i32:
        \\value = alloc 8
        \\$call side(ptr value, i32 7, @glob, %tmp)$
        \\return 0
    ;
    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), result.instructions.len);
    try std.testing.expectEqual(InstKind.native, result.instructions[2].kind);
    try std.testing.expectEqualStrings("call side(ptr value, i32 7, @glob, %tmp)", result.instructions[2].operands[0].native_text);
    try std.testing.expectEqual(@as(usize, 5), result.instructions[2].native_reg_names.len);
    try std.testing.expectEqualStrings("call", result.instructions[2].native_reg_names[0]);
    try std.testing.expectEqualStrings("side", result.instructions[2].native_reg_names[1]);
    try std.testing.expectEqualStrings("ptr", result.instructions[2].native_reg_names[2]);
    try std.testing.expectEqualStrings("value", result.instructions[2].native_reg_names[3]);
    try std.testing.expectEqualStrings("i32", result.instructions[2].native_reg_names[4]);
}

test "flatten attaches loc hint to the next real instruction only" {
    const source =
        \\#loc "up.rs":12:3
        \\@entry() -> i32:
        \\#loc "up.rs":13:5
        \\L_ENTRY:
        \\#loc "up.rs":14:7
        \\node = alloc 8
        \\return node
    ;
    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), result.instructions.len);
    try std.testing.expect(result.instructions[0].upstream_loc != null);
    try std.testing.expectEqualStrings("up.rs", result.instructions[0].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 12), result.instructions[0].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 3), result.instructions[0].upstream_loc.?.col);
    try std.testing.expect(result.instructions[1].upstream_loc == null);
    try std.testing.expect(result.instructions[2].upstream_loc != null);
    try std.testing.expectEqualStrings("up.rs", result.instructions[2].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 14), result.instructions[2].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 7), result.instructions[2].upstream_loc.?.col);
    try std.testing.expect(result.instructions[3].upstream_loc == null);
    try std.testing.expectEqual(@as(usize, result.instructions.len), result.loc_table.len);
    try std.testing.expect(result.loc_table[0] == null);
    try std.testing.expect(result.loc_table[1] == null);
    try std.testing.expect(result.loc_table[2] != null);
    try std.testing.expectEqualStrings("up.rs", result.loc_table[2].?.file);
    try std.testing.expect(result.loc_table[3] == null);
    try std.testing.expectEqualStrings("up.rs", result.function_sigs[0].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 12), result.function_sigs[0].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 3), result.function_sigs[0].upstream_loc.?.col);
}

test "flatten rejects zero loc hint coordinates" {
    const source =
        \\#loc "up.rs":0:0
        \\@entry() -> i32:
        \\return 0
    ;
    try std.testing.expectError(error.InvalidLocHint, flatten(std.testing.allocator, source));
}

test "flattenFile expands relative @import files" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_std/io");
    var iface = try tdir.createFile("sa_std/io/print.sai", .{ .truncate = true });
    try iface.writeAll("@extern sa_print_bytes(&msg: ptr, len: u64) -> void\n");
    iface.close();

    var main_file = try tdir.createFile("main.sa", .{ .truncate = true });
    try main_file.writeAll(
        \\@import "sa_std/io/print.sai"
        \\@main() -> i32:
        \\L_ENTRY:
        \\    return 0
    );
    main_file.close();

    const source = try tdir.readFileAlloc(std.testing.allocator, "main.sa", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tdir.realpathAlloc(std.testing.allocator, "main.sa");
    defer std.testing.allocator.free(source_path);

    var result = try flattenFile(std.testing.allocator, source_path, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.function_sigs.len);
    try std.testing.expectEqual(FunctionKind.external, result.function_sigs[0].kind);
    try std.testing.expectEqualStrings("sa_print_bytes", result.function_sigs[0].name);
    try std.testing.expectEqual(FunctionKind.normal, result.function_sigs[1].kind);
    try std.testing.expectEqualStrings("main", result.function_sigs[1].name);
}

test "flattenFile reports undefined macro at its origin line, not the expanded line" {
    // Regression (DEF-ASM-AND-NAMED-REG): an EXPAND naming a macro that no
    // imported source defines used to surface as ForbiddenSyntax /
    // InvalidMacroInvocation, with the error position taken from the
    // expanded source and rendered as a line of the root file — fabricating
    // context from an unrelated instruction (an innocent `and` line in the
    // slaredis build). The diagnostic must name the macro and point at the
    // EXPAND line in its own file.
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    // Padding in the imported file pushes the EXPAND far down the expanded
    // source, while it sits at line 4 of the root file.
    var module_file = try tdir.createFile("module.sa", .{ .truncate = true });
    for (0..40) |_| try module_file.writeAll("// pad\n");
    module_file.close();

    var main_file = try tdir.createFile("main.sa", .{ .truncate = true });
    try main_file.writeAll(
        \\@import "module.sa"
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND MISSING_MACRO tmp_1
        \\    return 0
    );
    main_file.close();

    const source = try tdir.readFileAlloc(std.testing.allocator, "main.sa", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tdir.realpathAlloc(std.testing.allocator, "main.sa");
    defer std.testing.allocator.free(source_path);

    var error_ctx: ErrorContext = .{};
    try std.testing.expectError(error.UndefinedMacro, flattenFileWithContext(std.testing.allocator, source_path, source, &error_ctx));
    const report = errorReport(&error_ctx);
    try std.testing.expectEqual(@as(?u32, 4), report.line);
    // A null path means the root file (its spelling is owned by the caller).
    try std.testing.expect(report.path == null);
    try std.testing.expectEqualStrings("MISSING_MACRO", report.detail.?);
}

test "flattenFile attributes undefined macro inside an imported file to that file" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    var module_file = try tdir.createFile("module.sa", .{ .truncate = true });
    try module_file.writeAll(
        \\// header
        \\@helper() -> i32:
        \\L_ENTRY:
        \\    EXPAND INNER_MISSING tmp_1
        \\    return 7
    );
    module_file.close();

    var main_file = try tdir.createFile("main.sa", .{ .truncate = true });
    try main_file.writeAll(
        \\@import "module.sa"
        \\@main() -> i32:
        \\L_ENTRY:
        \\    return 0
    );
    main_file.close();

    const source = try tdir.readFileAlloc(std.testing.allocator, "main.sa", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tdir.realpathAlloc(std.testing.allocator, "main.sa");
    defer std.testing.allocator.free(source_path);
    const module_path = try tdir.realpathAlloc(std.testing.allocator, "module.sa");
    defer std.testing.allocator.free(module_path);

    var error_ctx: ErrorContext = .{};
    try std.testing.expectError(error.UndefinedMacro, flattenFileWithContext(std.testing.allocator, source_path, source, &error_ctx));
    const report = errorReport(&error_ctx);
    try std.testing.expectEqual(@as(?u32, 4), report.line);
    try std.testing.expectEqualStrings(module_path, report.path.?);
    try std.testing.expectEqualStrings("INNER_MISSING", report.detail.?);
}

test "flattenFile tags imported functions with imported source path" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    var module_file = try tdir.createFile("module.sa", .{ .truncate = true });
    try module_file.writeAll(
        \\@helper() -> i32:
        \\L_ENTRY:
        \\    return 7
    );
    module_file.close();

    var main_file = try tdir.createFile("main.sa", .{ .truncate = true });
    try main_file.writeAll(
        \\@import "module.sa"
        \\@main() -> i32:
        \\L_ENTRY:
        \\    return 0
    );
    main_file.close();

    const source = try tdir.readFileAlloc(std.testing.allocator, "main.sa", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tdir.realpathAlloc(std.testing.allocator, "main.sa");
    defer std.testing.allocator.free(source_path);
    const module_path = try tdir.realpathAlloc(std.testing.allocator, "module.sa");
    defer std.testing.allocator.free(module_path);

    var result = try flattenFile(std.testing.allocator, source_path, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.function_sigs.len);
    try std.testing.expectEqualStrings("helper", result.function_sigs[0].name);
    try std.testing.expect(result.function_sigs[0].upstream_loc != null);
    try std.testing.expectEqualStrings(module_path, result.function_sigs[0].upstream_loc.?.file);
}

test "std import source cache reuses source without cloning on hit" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_std/core");
    var iface = try tdir.createFile("sa_std/core/cache_probe.sai", .{ .truncate = true });
    try iface.writeAll("@extern cache_probe() -> i32\n");
    iface.close();

    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try tdir.realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);
    const resolve_ctx = ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };

    var first = try readImportFile(std.testing.allocator, project_root, "sa_std/core/cache_probe.sai", resolve_ctx);
    defer first.deinit(std.testing.allocator);
    try std.testing.expect(first.owned_source != null);
    try std.testing.expectEqualStrings("@extern cache_probe() -> i32\n", first.source);

    var second = try readImportFile(std.testing.allocator, project_root, "sa_std/core/cache_probe.sai", resolve_ctx);
    defer second.deinit(std.testing.allocator);
    try std.testing.expect(second.owned_source == null);
    try std.testing.expectEqualStrings(first.source, second.source);
}
