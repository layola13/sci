//! Standing golden/negative corpus for the SAB fragment contract
//! (`sa encode-fragment`, src/sab_fragment.zig). Wired into
//! `zig build test` as the fragment-smoke step in build.zig: test
//! blocks inside src/ modules are not collected by this repository's
//! test steps under lazy analysis, so the corpus lives in a tests/
//! root like the other smoke suites.

const std = @import("std");
const testing = std.testing;
const saasm = @import("saasm");
const sab = saasm.sab;
const sab_fragment = saasm.sab_fragment;
const flattener = saasm.flattener;
const plugin_bridge = saasm.plugin_bridge;
const instruction = saasm.common.instruction;

const Contract = sab_fragment.Contract;
const Validation = sab_fragment.Validation;
const ViolationKind = sab_fragment.ViolationKind;
const parseFragmentSource = sab_fragment.parseFragmentSource;
const validateContract = sab_fragment.validateContract;
const encodeFragment = sab_fragment.encodeFragment;
const decodeFragment = sab_fragment.decodeFragment;
const encodeContainer = sab_fragment.encodeContainer;
const isFragment = sab_fragment.isFragment;
const format_major = sab_fragment.format_major;
const format_minor = sab_fragment.format_minor;

test "fragment header parses and strips in place" {
    const source =
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads: __sla_macro_arg_1
        \\#fragment-owns: __sla_macro_arg_0, tmp_0
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: test-frontend 1.2.3
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    return
        \\
    ;
    var parsed = try parseFragmentSource(testing.allocator, source);
    defer parsed.deinit(testing.allocator);
    try testing.expectEqualStrings("__sla_macro_fragment_0", parsed.contract.function_name);
    try testing.expectEqual(@as(usize, 1), parsed.contract.reads.len);
    try testing.expectEqualStrings("__sla_macro_arg_1", parsed.contract.reads[0]);
    try testing.expectEqual(@as(usize, 2), parsed.contract.owns.len);
    try testing.expectEqual(@as(usize, 1), parsed.contract.returns.len);
    try testing.expectEqualStrings("test-frontend 1.2.3", parsed.contract.caller);
    // Stripping preserves the line count and the body text.
    try testing.expectEqual(source.len, parsed.stripped_source.len);
    try testing.expect(std.mem.indexOf(u8, parsed.stripped_source, "#fragment") == null);
    try testing.expect(std.mem.indexOf(u8, parsed.stripped_source, "@__sla_macro_fragment_0() -> void:") != null);
    try testing.expectEqual(
        std.mem.count(u8, source, "\n"),
        std.mem.count(u8, parsed.stripped_source, "\n"),
    );
}

test "fragment header rejects malformed sources" {
    try testing.expectError(error.FragmentMissingHeader, parseFragmentSource(testing.allocator,
        \\@f() -> void:
        \\L_ENTRY:
        \\    return
        \\
    ));
    try testing.expectError(error.FragmentVersionMismatch, parseFragmentSource(testing.allocator,
        \\#fragment 2
        \\#fragment-function: f
        \\#fragment-reads:
        \\#fragment-owns:
        \\#fragment-caller: t 1
        \\@f() -> void:
        \\L_ENTRY:
        \\    return
        \\
    ));
    try testing.expectError(error.FragmentMissingField, parseFragmentSource(testing.allocator,
        \\#fragment 1
        \\#fragment-function: f
        \\#fragment-reads:
        \\#fragment-caller: t 1
        \\@f() -> void:
        \\L_ENTRY:
        \\    return
        \\
    ));
    try testing.expectError(error.FragmentUnknownDirective, parseFragmentSource(testing.allocator,
        \\#fragment 1
        \\#fragment-function: f
        \\#fragment-reads:
        \\#fragment-owns:
        \\#fragment-caller: t 1
        \\#fragment-surprise: x
        \\@f() -> void:
        \\L_ENTRY:
        \\    return
        \\
    ));
    try testing.expectError(error.FragmentDuplicateDirective, parseFragmentSource(testing.allocator,
        \\#fragment 1
        \\#fragment-function: f
        \\#fragment-reads:
        \\#fragment-reads:
        \\#fragment-owns:
        \\#fragment-caller: t 1
        \\@f() -> void:
        \\L_ENTRY:
        \\    return
        \\
    ));
    try testing.expectError(error.FragmentDuplicateRegister, parseFragmentSource(testing.allocator,
        \\#fragment 1
        \\#fragment-function: f
        \\#fragment-reads: a, a
        \\#fragment-owns:
        \\#fragment-caller: t 1
        \\@f() -> void:
        \\L_ENTRY:
        \\    return
        \\
    ));
    try testing.expectError(error.FragmentHeaderAfterCode, parseFragmentSource(testing.allocator,
        \\#fragment 1
        \\#fragment-function: f
        \\@f() -> void:
        \\L_ENTRY:
        \\    return
        \\#fragment-reads:
        \\
    ));
}

test "fragment container roundtrips and is not a program" {
    var contract: Contract = .{
        .function_name = try testing.allocator.dupe(u8, "__sla_macro_fragment_0"),
        .reads = try testing.allocator.dupe([]const u8, &.{try testing.allocator.dupe(u8, "__sla_macro_arg_1")}),
        .owns = try testing.allocator.dupe([]const u8, &.{try testing.allocator.dupe(u8, "__sla_macro_arg_0")}),
        .returns = try testing.allocator.dupe([]const u8, &.{try testing.allocator.dupe(u8, "__sla_macro_arg_0")}),
        .caller = try testing.allocator.dupe(u8, "test-frontend 1.2.3"),
    };
    defer contract.deinit(testing.allocator);
    var sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("source text", &sha, .{});
    const payload = "payload-bytes";
    const bytes = try encodeContainer(testing.allocator, &contract, &sha, payload);
    defer testing.allocator.free(bytes);

    try testing.expect(isFragment(bytes));
    var artifact = try decodeFragment(testing.allocator, bytes);
    defer artifact.deinit(testing.allocator);
    try testing.expectEqualStrings("__sla_macro_fragment_0", artifact.contract.function_name);
    try testing.expectEqualStrings("test-frontend 1.2.3", artifact.contract.caller);
    try testing.expectEqual(@as(usize, 1), artifact.contract.reads.len);
    try testing.expectEqualSlices(u8, payload, artifact.payload);
    try testing.expectEqualSlices(u8, &sha, &artifact.source_sha256);
    try testing.expectEqual(sab.version_major, artifact.sab_major);

    // A bare fragment must never decode as a program module.
    try testing.expectError(error.SabFragmentNotAProgram, sab.decodeModule(testing.allocator, bytes));
    try testing.expectError(error.SabFragmentNotAProgram, sab.decodeFunctionSigsOnly(testing.allocator, bytes));
    try testing.expectError(error.SabFragmentNotAProgram, sab.decodeTestFunctionSigsOnly(testing.allocator, bytes));
    // And the fragment decoder rejects plain SAB bytes / bad versions.
    try testing.expectError(error.InvalidFragmentMagic, decodeFragment(testing.allocator, "SAB\x00\x04\x00xxxx"));
    var corrupted = try testing.allocator.dupe(u8, bytes);
    defer testing.allocator.free(corrupted);
    corrupted[sab.fragment_magic.len] = format_major + 1;
    try testing.expectError(error.UnsupportedFragmentVersion, decodeFragment(testing.allocator, corrupted));
    try testing.expectError(error.TruncatedFragment, decodeFragment(testing.allocator, bytes[0 .. bytes.len - 2]));
}

fn flattenForTest(allocator: std.mem.Allocator, stripped_source: []const u8) !flattener.FlattenResult {
    // The build step runs this binary with the repository root as
    // cwd, so the std root resolves from there.
    return flattener.flattenWithPackages(allocator, stripped_source, .{ .options = .{ .std_root = "sa_std" } });
}

fn expectGoldenFragment(source: []const u8) !void {
    var parsed = try parseFragmentSource(testing.allocator, source);
    defer parsed.deinit(testing.allocator);
    var flat = try flattenForTest(testing.allocator, parsed.stripped_source);
    defer flat.deinit(testing.allocator);
    var validation = try validateContract(testing.allocator, &flat, &parsed.contract, parsed.stripped_source);
    defer validation.deinit(testing.allocator);
    switch (validation) {
        .ok => {},
        .violation => |v| {
            std.debug.print("golden fragment contract violation: {s} register={?s}: {s}\n", .{ @tagName(v.kind), v.register, v.detail });
            return error.FragmentContractViolation;
        },
    }
    const container = try encodeFragment(testing.allocator, &flat, &parsed.contract, source);
    defer testing.allocator.free(container);
    var artifact = try decodeFragment(testing.allocator, container);
    defer artifact.deinit(testing.allocator);
    // The payload must be byte-identical to the plugin's in-process
    // unchecked encode of the same flat (single encoder guarantee).
    const expected_payload = try plugin_bridge.encodeSabFromFlatUnchecked(testing.allocator, &flat);
    defer testing.allocator.free(expected_payload);
    try testing.expectEqualSlices(u8, expected_payload, artifact.payload);
    // The payload itself is a decodable module (the assembler's input).
    var module = try sab.decodeModule(testing.allocator, artifact.payload);
    defer module.deinit(testing.allocator);
}

test "golden fragment: VEC_NEW (Vec method class)" {
    try expectGoldenFragment(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads:
        \\#fragment-owns: __sla_macro_arg_0
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/vec.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND VEC_NEW __sla_macro_arg_0
        \\    return
        \\
    );
}

test "golden fragment: VEC_LEN (Vec method class)" {
    try expectGoldenFragment(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads: __sla_macro_arg_1
        \\#fragment-owns: __sla_macro_arg_0
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/vec.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND VEC_LEN __sla_macro_arg_0, __sla_macro_arg_1
        \\    return
        \\
    );
}

test "golden fragment: VEC_AS_PTR (Vec method class, releases its own borrow)" {
    try expectGoldenFragment(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads: __sla_macro_arg_1
        \\#fragment-owns: __vec_view___sla_macro_arg_0, __sla_macro_arg_0
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/vec.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND VEC_AS_PTR __sla_macro_arg_0, __sla_macro_arg_1
        \\    return
        \\
    );
}

test "golden fragment: STR_LEN (string class)" {
    try expectGoldenFragment(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads: __sla_macro_arg_1
        \\#fragment-owns: __sla_macro_arg_0
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/string.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND STR_LEN __sla_macro_arg_0, __sla_macro_arg_1
        \\    return
        \\
    );
}

fn expectViolation(source: []const u8, expected: ViolationKind) !void {
    var parsed = try parseFragmentSource(testing.allocator, source);
    defer parsed.deinit(testing.allocator);
    var flat = try flattenForTest(testing.allocator, parsed.stripped_source);
    defer flat.deinit(testing.allocator);
    var validation = try validateContract(testing.allocator, &flat, &parsed.contract, parsed.stripped_source);
    defer validation.deinit(testing.allocator);
    switch (validation) {
        .ok => {
            std.debug.print("expected violation {s}, got ok\n", .{@tagName(expected)});
            return error.ExpectedViolation;
        },
        .violation => |v| try testing.expectEqual(expected, v.kind),
    }
}

test "contract validation rejects program surface in the fragment source" {
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: main
        \\#fragment-reads:
        \\#fragment-owns:
        \\#fragment-caller: sci-golden 1.0
        \\@main() -> i32:
        \\L_ENTRY:
        \\    zero = 0
        \\    return zero
        \\
    , .program_entry);
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads:
        \\#fragment-owns:
        \\#fragment-caller: sci-golden 1.0
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    return
        \\@test "nope"():
        \\L_TEST:
        \\    return
        \\
    , .program_entry);
}

test "contract validation rejects a second function and a name mismatch" {
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads:
        \\#fragment-owns:
        \\#fragment-caller: sci-golden 1.0
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    return
        \\@helper() -> void:
        \\L_ENTRY2:
        \\    return
        \\
    , .multiple_entry_functions);
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: some_other_name
        \\#fragment-reads:
        \\#fragment-owns:
        \\#fragment-caller: sci-golden 1.0
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    return
        \\
    , .entry_not_found);
}

test "contract validation rejects register contract mismatches" {
    // Input placeholder used but not declared as read.
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads:
        \\#fragment-owns: __sla_macro_arg_0
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/vec.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND VEC_LEN __sla_macro_arg_0, __sla_macro_arg_1
        \\    return
        \\
    , .undeclared_external);
    // Declared read that the body never uses.
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads: ghost_reg
        \\#fragment-owns: __sla_macro_arg_0
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/vec.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND VEC_NEW __sla_macro_arg_0
        \\    return
        \\
    , .unused_read);
    // Body defines a register the header does not own.
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads:
        \\#fragment-owns:
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/vec.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND VEC_NEW __sla_macro_arg_0
        \\    return
        \\
    , .undeclared_own);
    // Header owns a register the body never defines.
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads:
        \\#fragment-owns: __sla_macro_arg_0, ghost_reg
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/vec.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND VEC_NEW __sla_macro_arg_0
        \\    return
        \\
    , .unused_own);
}

test "contract validation rejects foreign and returned releases" {
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: frag
        \\#fragment-reads:
        \\#fragment-owns: cell
        \\#fragment-caller: sci-golden 1.0
        \\@frag() -> void:
        \\L_ENTRY:
        \\    cell = alloc 8
        \\    !cell
        \\    !ghost
        \\    return
        \\
    , .foreign_release);
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: frag
        \\#fragment-reads:
        \\#fragment-owns: cell
        \\#fragment-returns: cell
        \\#fragment-caller: sci-golden 1.0
        \\@frag() -> void:
        \\L_ENTRY:
        \\    cell = alloc 8
        \\    !cell
        \\    return
        \\
    , .release_of_returned);
}

test "contract validation rejects an undeclared return register" {
    try expectViolation(
        \\#fragment 1
        \\#fragment-function: frag
        \\#fragment-reads:
        \\#fragment-owns: cell
        \\#fragment-caller: sci-golden 1.0
        \\@frag() -> ptr:
        \\L_ENTRY:
        \\    cell = alloc 8
        \\    return cell
        \\
    , .return_outside_contract);
}

test "fragment assembly: VEC_NEW body spliced into a host main passes whole-module verification" {
    const allocator = testing.allocator;
    const source =
        \\#fragment 1
        \\#fragment-function: __sla_macro_fragment_0
        \\#fragment-reads:
        \\#fragment-owns: __sla_macro_arg_0
        \\#fragment-returns: __sla_macro_arg_0
        \\#fragment-caller: sci-golden 1.0
        \\@import "sa_std/vec.sa"
        \\@__sla_macro_fragment_0() -> void:
        \\L_ENTRY:
        \\    EXPAND VEC_NEW __sla_macro_arg_0
        \\    return
        \\
    ;
    var parsed = try parseFragmentSource(allocator, source);
    defer parsed.deinit(allocator);
    var frag_flat = try flattenForTest(allocator, parsed.stripped_source);
    defer frag_flat.deinit(allocator);
    var validation = try validateContract(allocator, &frag_flat, &parsed.contract, parsed.stripped_source);
    defer validation.deinit(allocator);
    switch (validation) {
        .ok => {},
        .violation => return error.FragmentContractViolation,
    }
    const container = try encodeFragment(allocator, &frag_flat, &parsed.contract, source);
    defer allocator.free(container);

    // The assembler's half: decode the container, decode the payload
    // module, and take the wrapper body (skipping the function
    // declaration, its entry label, and the trailing return, exactly
    // like the SLA codegen's template extraction).
    var artifact = try decodeFragment(allocator, container);
    defer artifact.deinit(allocator);
    var module = try sab.decodeModule(allocator, artifact.payload);
    defer module.deinit(allocator);
    var entry_idx: ?usize = null;
    var body_end: usize = module.instructions.len;
    for (module.function_sigs, 0..) |fsig, idx| {
        if (std.mem.eql(u8, fsig.name, artifact.contract.function_name)) {
            entry_idx = fsig.entry_inst_idx;
            if (idx + 1 < module.function_sigs.len) body_end = module.function_sigs[idx + 1].entry_inst_idx;
            break;
        }
    }
    const body_start = entry_idx orelse return error.TestUnexpectedResult;
    var slice_lo = body_start;
    var slice_hi = body_end;
    if (slice_lo < slice_hi and module.instructions[slice_lo].kind == .func_decl) slice_lo += 1;
    if (slice_lo < slice_hi and module.instructions[slice_lo].kind == .label) slice_lo += 1;
    if (slice_hi > slice_lo and module.instructions[slice_hi - 1].kind == .return_) slice_hi -= 1;
    try testing.expect(slice_hi > slice_lo);

    // Host program: uses `myvec` (defined only by the spliced body),
    // pushes two elements, checks the length, and frees the vector.
    const host_source =
        \\@import "sa_std/vec.sa"
        \\@main() -> i32:
        \\L_ENTRY:
        \\    myvec = call @sa_vec_push(^myvec, 42, 8)
        \\    myvec = call @sa_vec_push(^myvec, 43, 8)
        \\    len = call @sa_vec_len(&myvec)
        \\    call @sa_vec_free(^myvec)
        \\    expected = 2
        \\    failed = ne len, expected
        \\    !len
        \\    !expected
        \\    br failed -> L_FAIL, L_OK
        \\L_FAIL:
        \\    !failed
        \\    panic(9)
        \\L_OK:
        \\    !failed
        \\    zero = 0
        \\    return zero
        \\
    ;
    var host_flat = try flattenForTest(allocator, host_source);
    defer host_flat.deinit(allocator);

    // Remap the fragment body's symbol ids into the host symbol table
    // by name; the placeholder maps to the host's `myvec`.
    var spliced = std.array_list.Managed(instruction.Instruction).init(allocator);
    defer spliced.deinit();
    for (module.instructions[slice_lo..slice_hi]) |inst| {
        var cloned = inst;
        for (&cloned.operands) |*operand| {
            switch (operand.*) {
                .reg, .func, .symbol => |id| {
                    const name = module.symbols[id];
                    const host_name = if (std.mem.eql(u8, name, "__sla_macro_arg_0")) "myvec" else name;
                    const host_id = try host_flat.symbols.intern(host_name);
                    switch (operand.*) {
                        .reg => operand.* = .{ .reg = host_id },
                        .func => operand.* = .{ .func = host_id },
                        .symbol => operand.* = .{ .symbol = host_id },
                        else => unreachable,
                    }
                },
                else => {},
            }
        }
        try spliced.append(cloned);
    }

    var main_entry: ?usize = null;
    for (host_flat.function_sigs) |fsig| {
        if (std.mem.eql(u8, fsig.name, "main")) {
            main_entry = fsig.entry_inst_idx;
            break;
        }
    }
    const insert_at = (main_entry orelse return error.TestUnexpectedResult) + 2;
    try testing.expect(host_flat.instructions[insert_at - 1].kind == .label);
    var assembled_instructions = std.array_list.Managed(instruction.Instruction).init(allocator);
    defer assembled_instructions.deinit();
    try assembled_instructions.appendSlice(host_flat.instructions[0..insert_at]);
    try assembled_instructions.appendSlice(spliced.items);
    try assembled_instructions.appendSlice(host_flat.instructions[insert_at..]);

    var assembled = host_flat;
    assembled.instructions = assembled_instructions.items;
    // The assembled module must pass the ordinary verified encode —
    // there is no fragment-to-product verification bypass.
    const assembled_bytes = try plugin_bridge.encodeSabFromFlat(allocator, &assembled, false);
    defer allocator.free(assembled_bytes);
    var roundtrip = try sab.decodeModule(allocator, assembled_bytes);
    defer roundtrip.deinit(allocator);

    // E2E export: when SAB_FRAG_E2E_OUT is set (box acceptance runs),
    // also write the assembled module so `sa build-exe` can run it.
    if (std.c.getenv("SAB_FRAG_E2E_OUT")) |out_path_c| {
        if (out_path_c[0] != 0) {
            const file = std.c.fopen(out_path_c, "wb") orelse return error.TestUnexpectedResult;
            defer _ = std.c.fclose(file);
            try testing.expectEqual(assembled_bytes.len, std.c.fwrite(assembled_bytes.ptr, 1, assembled_bytes.len, file));
        }
    }
}
