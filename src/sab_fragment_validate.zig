const std = @import("std");
const Contract = @import("sab_fragment.zig").Contract;
const containsName = @import("sab_fragment.zig").containsName;
const flattener = @import("sab_fragment.zig").flattener;
const instruction = @import("sab_fragment.zig").instruction;
const isIdentByte = @import("sab_fragment.zig").isIdentByte;
const stringLessThan = @import("sab_fragment.zig").stringLessThan;

pub const ViolationKind = enum {
    program_entry,
    unsupported_function_kind,
    entry_not_found,
    multiple_entry_functions,
    undeclared_external,
    unused_read,
    undeclared_own,
    unused_own,
    return_outside_contract,
    foreign_release,
    release_of_returned,
};

pub const Violation = struct {
    kind: ViolationKind,
    /// Offending register name when the violation is about one
    /// register (owned by the Validation's allocator).
    register: ?[]const u8 = null,
    detail: []const u8 = "",
};

pub const Validation = union(enum) {
    ok,
    violation: Violation,

    pub fn deinit(self: *Validation, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => {},
            .violation => |v| if (v.register) |name| allocator.free(name),
        }
        self.* = undefined;
    }
};

pub fn violation(allocator: std.mem.Allocator, kind: ViolationKind, register: ?[]const u8, detail: []const u8) !Validation {
    return .{ .violation = .{
        .kind = kind,
        .register = if (register) |name| try allocator.dupe(u8, name) else null,
        .detail = detail,
    } };
}

pub fn isDefiningKind(kind: instruction.InstKind) bool {
    return switch (kind) {
        .alloc,
        .stack_alloc,
        .load,
        .atomic_load,
        .borrow,
        .move_,
        .assign,
        .op,
        .ptr_add,
        .call,
        .call_indirect,
        .try_,
        .take,
        .raw_cast,
        .assume_safe,
        .assume_borrow,
        .va_arg,
        => true,
        else => false,
    };
}

pub fn isDeclKind(kind: instruction.InstKind) bool {
    return switch (kind) {
        .func_decl, .test_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .gpu_decl, .label => true,
        else => false,
    };
}

pub fn nameInList(list: []const []const u8, name: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    return false;
}

pub fn isPrimitiveTextName(name: []const u8) bool {
    const names = [_][]const u8{
        "u8", "u16", "u32", "u64", "u128", "i8", "i16", "i32", "i64", "i128",
        "f16", "f32", "f64", "bool", "void", "ptr", "usize", "isize",
        "as", "true", "false", "null",
    };
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

pub fn scanCallText(used: *std.StringHashMap(void), text: []const u8) !void {
    // Only the parenthesised argument list carries arguments; the
    // callee name in front of it is not an argument.
    const open = std.mem.indexOfScalar(u8, text, '(') orelse return;
    const close = std.mem.lastIndexOfScalar(u8, text, ')') orelse return;
    if (close <= open + 1) return;
    const args = text[open + 1 .. close];
    var i: usize = 0;
    while (i < args.len) {
        const c = args[i];
        if (c == '"') {
            // Skip a string literal span.
            i += 1;
            while (i < args.len and args[i] != '"') : (i += 1) {}
            if (i < args.len) i += 1;
            continue;
        }
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
            const start = i;
            while (i < args.len and isIdentByte(args[i])) : (i += 1) {}
            const token = args[start..i];
            const prev: u8 = if (start > 0) args[start - 1] else 0;
            const before_paren = i < args.len and args[i] == '(';
            if (prev != '@' and prev != '.' and !before_paren and !isPrimitiveTextName(token)) {
                try used.put(token, {});
            }
            continue;
        }
        i += 1;
    }
}

pub fn scanOwnDeclarations(
    allocator: std.mem.Allocator,
    stripped_source: []const u8,
    contract: *const Contract,
) !Validation {
    var own_count: usize = 0;
    var in_macro = false;
    var line_start: usize = 0;
    while (line_start <= stripped_source.len) {
        const line_end = std.mem.indexOfScalarPos(u8, stripped_source, line_start, '\n') orelse stripped_source.len;
        const line = stripped_source[line_start..line_end];
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "[MACRO]")) in_macro = true;
        if (std.mem.startsWith(u8, trimmed, "[END_MACRO]")) in_macro = false;
        if (!in_macro and trimmed.len != 0 and trimmed[0] == '@') {
            var word_end: usize = 1;
            while (word_end < trimmed.len and isIdentByte(trimmed[word_end])) : (word_end += 1) {}
            const word = trimmed[1..word_end];
            if (std.mem.eql(u8, word, "test")) {
                return violation(allocator, .program_entry, null, "fragment source declares a @test function");
            } else if (std.mem.eql(u8, word, "export")) {
                return violation(allocator, .program_entry, null, "fragment source declares an @export (module-level program surface)");
            } else if (std.mem.eql(u8, word, "ffi_wrapper")) {
                return violation(allocator, .unsupported_function_kind, null, "fragment source declares an @ffi_wrapper function");
            } else if (std.mem.eql(u8, word, "gpu")) {
                return violation(allocator, .unsupported_function_kind, null, "fragment source declares a @gpu function");
            } else if (!std.mem.eql(u8, word, "import") and !std.mem.eql(u8, word, "const") and !std.mem.eql(u8, word, "extern")) {
                if (std.mem.eql(u8, word, "main")) {
                    return violation(allocator, .program_entry, null, "fragment source declares @main (a program entry)");
                }
                own_count += 1;
                if (own_count > 1) {
                    return violation(allocator, .multiple_entry_functions, null, "fragment source declares more than one function");
                }
                if (!std.mem.eql(u8, word, contract.function_name)) {
                    return violation(allocator, .entry_not_found, null, "the function declared in the fragment source does not match #fragment-function");
                }
            }
        }
        if (line_end == stripped_source.len) break;
        line_start = line_end + 1;
    }
    if (own_count == 0) {
        return violation(allocator, .entry_not_found, null, "fragment source declares no function");
    }
    return .ok;
}

pub fn validateContract(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
    contract: *const Contract,
    stripped_source: []const u8,
) !Validation {
    const text_scan = try scanOwnDeclarations(allocator, stripped_source, contract);
    switch (text_scan) {
        .ok => {},
        .violation => return text_scan,
    }

    if (flat.test_sigs.len != 0) {
        return violation(allocator, .program_entry, null, "flattened module contains a test function");
    }
    var entry: ?*const flattener.FunctionSig = null;
    for (flat.function_sigs) |*fsig| {
        if (std.mem.eql(u8, fsig.name, contract.function_name)) {
            entry = fsig;
            break;
        }
    }
    const entry_sig = entry orelse {
        return violation(allocator, .entry_not_found, null, "wrapper function not found in the flattened module");
    };
    switch (entry_sig.kind) {
        .normal => {},
        .test_func => return violation(allocator, .program_entry, null, "wrapper function is a test function"),
        else => return violation(allocator, .unsupported_function_kind, null, "wrapper function is not a plain function"),
    }

    const body_start = entry_sig.entry_inst_idx;
    var body_end: usize = flat.instructions.len;
    for (flat.function_sigs) |*fsig| {
        if (fsig.entry_inst_idx > body_start and fsig.entry_inst_idx < body_end) {
            body_end = fsig.entry_inst_idx;
        }
    }
    if (body_start >= body_end or flat.instructions[body_start].kind != .func_decl) {
        return violation(allocator, .entry_not_found, null, "wrapper function has no declaration instruction at its entry index");
    }

    var defined = std.StringHashMap(void).init(allocator);
    defer defined.deinit();
    var used = std.StringHashMap(void).init(allocator);
    defer used.deinit();
    var release_targets = std.array_list.Managed([]const u8).init(allocator);
    defer release_targets.deinit();
    var returned_regs = std.array_list.Managed([]const u8).init(allocator);
    defer returned_regs.deinit();

    for (flat.instructions[body_start..body_end]) |item| {
        if (isDeclKind(item.kind)) continue;
        // Register names carried in an instruction's native name
        // list count as uses (call argument registers live in the
        // call's textual operand instead; see the .text scan below).
        for (item.native_reg_names) |name| try used.put(name, {});
        if (item.kind == .native) continue;
        if (item.kind == .release) {
            if (item.operands[0] == .reg) {
                if (flat.symbols.lookupName(item.operands[0].reg)) |name| {
                    try used.put(name, {});
                    try release_targets.append(name);
                }
            }
            continue;
        }
        if (item.kind == .return_) {
            if (item.operands[0] == .reg) {
                if (flat.symbols.lookupName(item.operands[0].reg)) |name| {
                    try used.put(name, {});
                    try returned_regs.append(name);
                }
            }
            continue;
        }
        const defining = isDefiningKind(item.kind);
        for (item.operands, 0..) |operand, op_idx| {
            switch (operand) {
                .reg => {
                    const name = flat.symbols.lookupName(operand.reg) orelse continue;
                    if (defining and op_idx == 0) {
                        try defined.put(name, {});
                    } else {
                        try used.put(name, {});
                    }
                },
                .text => |text| {
                    // A call's callee+argument list lives in a
                    // textual operand (`@sa_vec_len(&a1)`); its
                    // argument registers are parsed strictly.
                    if (item.kind == .call or item.kind == .call_indirect) {
                        try scanCallText(&used, text);
                    }
                    // Textual operands — above all a call's
                    // callee+argument list (`@sa_vec_len(&a1)`) —
                    // carry register references as raw text. A name
                    // that occurs only inside such text is never
                    // interned into the symbol table, so a token
                    // counts as a use when it either names a
                    // symbol-table entry or belongs to the declared
                    // contract vocabulary; the callee token directly
                    // after '@' never counts.
                    var i: usize = 0;
                    while (i < text.len) {
                        const c = text[i];
                        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
                            const start = i;
                            while (i < text.len and isIdentByte(text[i])) : (i += 1) {}
                            const token = text[start..i];
                            if (start > 0 and text[start - 1] == '@') continue;
                            if (flat.symbols.findId(token) != null or
                                nameInList(contract.reads, token) or
                                nameInList(contract.owns, token) or
                                nameInList(contract.returns, token))
                            {
                                try used.put(token, {});
                            }
                        } else {
                            i += 1;
                        }
                    }
                },
                else => {},
            }
        }
    }

    // Release accounting: a fragment may only close accounts it owns —
    // registers it defined, or input registers it consumes (declared
    // reads that are not handed back). Releasing a register that is
    // handed back, or one that was never the fragment's, is rejected.
    for (release_targets.items) |target| {
        if (nameInList(contract.returns, target)) {
            return violation(allocator, .release_of_returned, target, "fragment releases a register it declares as handed back");
        }
        if (defined.contains(target)) continue;
        if (nameInList(contract.reads, target)) continue;
        return violation(allocator, .foreign_release, target, "fragment releases a register it neither defines nor declares as a consumed input");
    }
    for (returned_regs.items) |name| {
        if (!nameInList(contract.returns, name)) {
            return violation(allocator, .return_outside_contract, name, "wrapper returns a register that is not declared in #fragment-returns");
        }
    }

    // External registers = used but never defined (wrapper parameters
    // included: they are used in the body and defined by no
    // instruction). The declared reads must match this set exactly.
    var externals = std.array_list.Managed([]const u8).init(allocator);
    defer externals.deinit();
    var used_it = used.keyIterator();
    while (used_it.next()) |key| {
        if (!defined.contains(key.*)) try externals.append(key.*);
    }
    std.mem.sort([]const u8, externals.items, {}, stringLessThan);
    for (externals.items) |name| {
        if (!nameInList(contract.reads, name)) {
            return violation(allocator, .undeclared_external, name, "body uses an external register that is not declared in #fragment-reads");
        }
    }
    const reads_sorted = try allocator.dupe([]const u8, contract.reads);
    defer allocator.free(reads_sorted);
    std.mem.sort([]const u8, reads_sorted, {}, stringLessThan);
    for (reads_sorted) |name| {
        if (!containsName(externals.items, name)) {
            return violation(allocator, .unused_read, name, "#fragment-reads declares a register the body never uses as an external");
        }
    }
    var defined_list = std.array_list.Managed([]const u8).init(allocator);
    defer defined_list.deinit();
    var def_it = defined.keyIterator();
    while (def_it.next()) |key| try defined_list.append(key.*);
    std.mem.sort([]const u8, defined_list.items, {}, stringLessThan);
    for (defined_list.items) |name| {
        if (!nameInList(contract.owns, name)) {
            return violation(allocator, .undeclared_own, name, "body defines a register that is not declared in #fragment-owns");
        }
    }
    const owns_sorted = try allocator.dupe([]const u8, contract.owns);
    defer allocator.free(owns_sorted);
    std.mem.sort([]const u8, owns_sorted, {}, stringLessThan);
    for (owns_sorted) |name| {
        if (!defined.contains(name)) {
            return violation(allocator, .unused_own, name, "#fragment-owns declares a register the body never defines");
        }
    }
    const returns_sorted = try allocator.dupe([]const u8, contract.returns);
    defer allocator.free(returns_sorted);
    std.mem.sort([]const u8, returns_sorted, {}, stringLessThan);
    for (returns_sorted) |name| {
        if (!nameInList(contract.reads, name) and !nameInList(contract.owns, name)) {
            return violation(allocator, .return_outside_contract, name, "#fragment-returns names a register that is neither read nor owned");
        }
    }
    return .ok;
}
