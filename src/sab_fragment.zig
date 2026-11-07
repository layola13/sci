//! SAB fragment container: the host-side encode path for compiler
//! surface fragments (for example one std macro expansion wrapped in a
//! synthetic function, as produced by the SLA SAB codegen for Vec method
//! calls).
//!
//! A fragment is NOT a program. Its wrapper function body references
//! placeholder registers owned by the assembling compiler (declared in
//! the contract header) and defines registers the assembler must treat
//! as fragment-owned, so the verified whole-program encoder
//! (`sa check --emit-sab`, plugin_bridge.encodeSabFromFlat) rejects it:
//! inputs trap as UnknownRegister, outputs as MemoryLeak at function
//! exit. The Zig SLA plugin sidesteps this in-process with
//! plugin_bridge.encodeSabFromFlatUnchecked; external frontends (the
//! Rust standalone) cannot. This module is the versioned host contract
//! for that encode:
//!
//!   * `sa encode-fragment` (see cli.zig) parses the contract header,
//!     validates it against the flattened wrapper body, encodes the
//!     payload with the SAME unchecked encoder implementation the
//!     plugin uses, and wraps it in this container.
//!   * The container carries the fragment magic (sab.fragment_magic),
//!     so every ordinary SAB decode entry point rejects it with
//!     error.SabFragmentNotAProgram: a bare fragment can never be
//!     built, run, or checked as a whole program. Assembly (decoding
//!     the payload and inlining the wrapper body into a real module)
//!     is the consumer's job, and the assembled module must pass the
//!     ordinary whole-module verification — there is no
//!     fragment-to-product verification bypass.
//!
//! Fragment source format: the SA text starts with a header block
//! (each line is blanked out before flattening, so line numbers and
//! byte offsets of the body are preserved):
//!
//!   #fragment 1
//!   #fragment-function: __sla_macro_fragment_0
//!   #fragment-reads: __sla_macro_arg_1
//!   #fragment-owns: __sla_macro_arg_0, tmp_0
//!   #fragment-returns: __sla_macro_arg_0
//!   #fragment-caller: sla-rust 0.1.0
//!
//! `reads` names the external registers the body uses without defining
//! (the assembler's placeholders, including the wrapper's parameters);
//! `owns` names every register the body defines; `returns` names the
//! registers whose value/ownership is handed back to the assembler
//! (a subset of reads + owns; a read register not in `returns` is
//! consumed by the fragment). The host recomputes all three sets from
//! the flattened body and rejects any mismatch, plus program surface
//! in the fragment's own text (a @main, @test, @export, @ffi_wrapper,
//! or @gpu declaration, or a second function).

const std = @import("std");
const flattener = @import("flattener.zig");
const sab = @import("sab.zig");
const plugin_bridge = @import("plugin_bridge.zig");
const instruction = @import("common/instruction.zig");

/// Fragment container format version. Frontends pin this version; a
/// mismatch is a loud error, never a silent reinterpretation.
pub const format_major: u8 = 1;
pub const format_minor: u8 = 0;

/// The dedicated subcommand that produces fragment containers. The
/// name deliberately says "fragment", not "unchecked"/"no-verify":
/// the product is a different artifact kind, not a relaxed program.
pub const subcommand_name = "encode-fragment";

pub const ParseError = error{
    FragmentMissingHeader,
    FragmentVersionMismatch,
    FragmentMissingField,
    FragmentUnknownDirective,
    FragmentDuplicateDirective,
    FragmentDuplicateRegister,
    FragmentBadHeaderLine,
    FragmentHeaderAfterCode,
    OutOfMemory,
};

pub const DecodeError = error{
    InvalidFragmentMagic,
    UnsupportedFragmentVersion,
    TruncatedFragment,
    OutOfMemory,
};

pub const Contract = struct {
    /// Name of the wrapper function whose body is the fragment.
    function_name: []const u8,
    /// External registers the body reads (assembler-owned).
    reads: []const []const u8,
    /// Registers the body defines (fragment-owned).
    owns: []const []const u8,
    /// Registers handed back to the assembler (subset of reads+owns).
    returns: []const []const u8,
    /// Calling frontend name + version (attribution record).
    caller: []const u8,

    pub fn deinit(self: *Contract, allocator: std.mem.Allocator) void {
        allocator.free(self.function_name);
        freeNames(allocator, self.reads);
        freeNames(allocator, self.owns);
        freeNames(allocator, self.returns);
        allocator.free(self.caller);
        self.* = undefined;
    }
};

fn freeNames(allocator: std.mem.Allocator, names: []const []const u8) void {
    for (names) |name| allocator.free(name);
    if (names.len != 0) allocator.free(names);
}

pub const ParsedFragment = struct {
    contract: Contract,
    /// The source with every header line blanked to spaces (newlines
    /// kept), so flattening reports the body's original line numbers.
    stripped_source: []u8,

    pub fn deinit(self: *ParsedFragment, allocator: std.mem.Allocator) void {
        self.contract.deinit(allocator);
        allocator.free(self.stripped_source);
        self.* = undefined;
    }
};

const Directive = enum { version, function, reads, owns, returns, caller };

fn isIdentByte(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

fn validRegisterName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (c == ' ' or c == '\t' or c == '\r' or c == ',' or c == ':') return false;
    }
    return true;
}

fn parseRegisterList(allocator: std.mem.Allocator, raw: []const u8) ParseError![]const []const u8 {
    var names = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit();
    }
    const trimmed = std.mem.trim(u8, raw, " \t\r");
    if (trimmed.len == 0) return try names.toOwnedSlice();
    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |part| {
        const name = std.mem.trim(u8, part, " \t\r");
        if (!validRegisterName(name)) return error.FragmentBadHeaderLine;
        for (names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) return error.FragmentDuplicateRegister;
        }
        try names.append(try allocator.dupe(u8, name));
    }
    return try names.toOwnedSlice();
}

/// Parse the contract header at the top of a fragment source. Header
/// lines may be interleaved with blank lines but must all precede the
/// first code line; a `#fragment` line after code is an error.
pub fn parseFragmentSource(allocator: std.mem.Allocator, source: []const u8) ParseError!ParsedFragment {
    var stripped = try allocator.dupe(u8, source);
    errdefer allocator.free(stripped);

    var seen_version = false;
    var seen_bits: u32 = 0;
    var function_name: ?[]const u8 = null;
    var reads: ?[]const []const u8 = null;
    var owns: ?[]const []const u8 = null;
    var returns: ?[]const []const u8 = null;
    var caller: ?[]const u8 = null;
    errdefer {
        if (function_name) |name| allocator.free(name);
        if (reads) |list| freeNames(allocator, list);
        if (owns) |list| freeNames(allocator, list);
        if (returns) |list| freeNames(allocator, list);
        if (caller) |text| allocator.free(text);
    }

    var in_header = true;
    var line_start: usize = 0;
    while (line_start <= source.len) {
        const line_end = std.mem.indexOfScalarPos(u8, source, line_start, '\n') orelse source.len;
        const line = source[line_start..line_end];
        const trimmed = std.mem.trim(u8, line, " \t\r");
        const is_fragment_line = std.mem.startsWith(u8, trimmed, "#fragment");
        if (is_fragment_line and !in_header) return error.FragmentHeaderAfterCode;
        if (in_header and trimmed.len != 0 and !is_fragment_line) in_header = false;
        if (is_fragment_line and in_header) {
            // Blank the header line in the stripped copy (keep bytes
            // before it and the newline itself untouched).
            const lead = line.len - std.mem.trimStart(u8, line, " \t\r").len;
            @memset(stripped[line_start .. line_start + lead + trimmed.len], ' ');

            if (std.mem.startsWith(u8, trimmed, "#fragment-")) {
                const rest = trimmed["#fragment-".len..];
                const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return error.FragmentBadHeaderLine;
                const key = rest[0..colon];
                const value = rest[colon + 1 ..];
                const directive: Directive = if (std.mem.eql(u8, key, "function"))
                    .function
                else if (std.mem.eql(u8, key, "reads"))
                    .reads
                else if (std.mem.eql(u8, key, "owns"))
                    .owns
                else if (std.mem.eql(u8, key, "returns"))
                    .returns
                else if (std.mem.eql(u8, key, "caller"))
                    .caller
                else
                    return error.FragmentUnknownDirective;
                const directive_bit = @as(u32, 1) << @intFromEnum(directive);
                if (seen_bits & directive_bit != 0) return error.FragmentDuplicateDirective;
                seen_bits |= directive_bit;
                switch (directive) {
                    .function => {
                        const name = std.mem.trim(u8, value, " \t\r");
                        if (!validRegisterName(name)) return error.FragmentBadHeaderLine;
                        function_name = try allocator.dupe(u8, name);
                    },
                    .reads => reads = try parseRegisterList(allocator, value),
                    .owns => owns = try parseRegisterList(allocator, value),
                    .returns => returns = try parseRegisterList(allocator, value),
                    .caller => {
                        const text = std.mem.trim(u8, value, " \t\r");
                        if (text.len == 0) return error.FragmentBadHeaderLine;
                        caller = try allocator.dupe(u8, text);
                    },
                    .version => unreachable,
                }
            } else if (std.mem.startsWith(u8, trimmed, "#fragment") and
                trimmed.len > "#fragment".len and
                (trimmed["#fragment".len] == ' ' or trimmed["#fragment".len] == '\t'))
            {
                if (seen_version) return error.FragmentDuplicateDirective;
                const value = std.mem.trim(u8, trimmed["#fragment".len..], " \t\r");
                const dot = std.mem.indexOfScalar(u8, value, '.');
                const major_text = if (dot) |d| value[0..d] else value;
                const major = std.fmt.parseInt(u32, major_text, 10) catch return error.FragmentBadHeaderLine;
                if (dot) |d| {
                    const minor = std.fmt.parseInt(u32, value[d + 1 ..], 10) catch return error.FragmentBadHeaderLine;
                    if (minor != format_minor) return error.FragmentVersionMismatch;
                }
                if (major != format_major) return error.FragmentVersionMismatch;
                seen_version = true;
            } else {
                return error.FragmentBadHeaderLine;
            }
        }
        if (line_end == source.len) break;
        line_start = line_end + 1;
    }

    if (!seen_version) return error.FragmentMissingHeader;
    if (function_name == null or reads == null or owns == null or caller == null) {
        return error.FragmentMissingField;
    }

    return .{
        .contract = .{
            .function_name = function_name.?,
            .reads = reads.?,
            .owns = owns.?,
            .returns = returns orelse &.{},
            .caller = caller.?,
        },
        .stripped_source = stripped,
    };
}

// ---------------------------------------------------------------------
// Contract validation against the flattened wrapper body
// ---------------------------------------------------------------------

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

fn violation(allocator: std.mem.Allocator, kind: ViolationKind, register: ?[]const u8, detail: []const u8) !Validation {
    return .{ .violation = .{
        .kind = kind,
        .register = if (register) |name| try allocator.dupe(u8, name) else null,
        .detail = detail,
    } };
}

/// Instruction kinds whose operands[0] (when a register) is a
/// definition of that register. Every other register operand is a
/// use. This mirrors the operand layout the verifier relies on.
fn isDefiningKind(kind: instruction.InstKind) bool {
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

fn isDeclKind(kind: instruction.InstKind) bool {
    return switch (kind) {
        .func_decl, .test_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .gpu_decl, .label => true,
        else => false,
    };
}

fn nameInList(list: []const []const u8, name: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    return false;
}

/// SA primitive type and keyword names: these can appear inside a
/// call's textual argument list (casts, literals) but are never
/// register names.
fn isPrimitiveTextName(name: []const u8) bool {
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

/// Strictly scan a call instruction's textual operand
/// (`@callee(arg, &arg2, ^arg3)`) for argument registers. Every
/// identifier in argument position counts as a use, whether or not
/// it was interned into the symbol table — a placeholder that occurs
/// only here is exactly the case the contract exists to catch.
/// Callee tokens (after '@', or directly before '(') and primitive
/// type/keyword names never count.
fn scanCallText(used: *std.StringHashMap(void), text: []const u8) !void {
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

/// Scan the fragment's own (stripped) source text for declarations.
/// The fragment's own text may declare exactly one function — the
/// wrapper named by the contract. Program surface (@main, @test,
/// @export) and other function kinds (@ffi_wrapper, @gpu) are
/// rejected; @import/@const/@extern lines are environment, not
/// declarations of the fragment itself. Lines inside [MACRO] blocks
/// are macro text, not declarations.
fn scanOwnDeclarations(
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

/// Validate a flattened fragment against its contract. `flat` is the
/// flatten of the header-stripped source (imports included — only the
/// wrapper function's body is the fragment; imported functions are
/// its environment). Returns the first violation found, with set
/// mismatches reported in sorted register-name order so diagnostics
/// are deterministic.
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

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn containsName(list: []const []const u8, name: []const u8) bool {
    return nameInList(list, name);
}

// ---------------------------------------------------------------------
// Container encode/decode
// ---------------------------------------------------------------------

pub const FragmentArtifact = struct {
    contract: Contract,
    /// SHA-256 of the fragment source text (attribution record).
    source_sha256: [32]u8,
    /// SAB version of the payload encoding.
    sab_major: u8,
    sab_minor: u8,
    /// The unchecked-encoded SAB module bytes (borrowed from the
    /// container bytes passed to decodeFragment).
    payload: []const u8,

    pub fn deinit(self: *FragmentArtifact, allocator: std.mem.Allocator) void {
        self.contract.deinit(allocator);
        self.* = undefined;
    }
};

/// Encode a validated fragment: the payload is produced by
/// plugin_bridge.encodeSabFromFlatUnchecked — the exact
/// implementation the Zig plugin uses in-process (there is no second
/// encoder) — and wrapped in the fragment container.
pub fn encodeFragment(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
    contract: *const Contract,
    source_text: []const u8,
) ![]u8 {
    const payload = try plugin_bridge.encodeSabFromFlatUnchecked(allocator, flat);
    defer allocator.free(payload);
    var source_sha256: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source_text, &source_sha256, .{});
    return encodeContainer(allocator, contract, &source_sha256, payload);
}

pub fn encodeContainer(
    allocator: std.mem.Allocator,
    contract: *const Contract,
    source_sha256: *const [32]u8,
    payload: []const u8,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    try writer.writeAll(sab.fragment_magic);
    try writer.writeByte(format_major);
    try writer.writeByte(format_minor);
    try writer.writeByte(sab.version_major);
    try writer.writeByte(sab.version_minor);
    try writer.writeAll(source_sha256);
    try writeName(writer, contract.caller);
    try writeName(writer, contract.function_name);
    try writeNameList(writer, contract.reads);
    try writeNameList(writer, contract.owns);
    try writeNameList(writer, contract.returns);
    try sab.encodeUleb128(writer, payload.len);
    try writer.writeAll(payload);
    return try out.toOwnedSlice();
}

fn writeName(writer: *std.Io.Writer, name: []const u8) !void {
    try sab.encodeUleb128(writer, name.len);
    try writer.writeAll(name);
}

fn writeNameList(writer: *std.Io.Writer, names: []const []const u8) !void {
    try sab.encodeUleb128(writer, names.len);
    for (names) |name| try writeName(writer, name);
}

const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    fn readByte(self: *Cursor) DecodeError!u8 {
        if (self.index >= self.bytes.len) return error.TruncatedFragment;
        const byte = self.bytes[self.index];
        self.index += 1;
        return byte;
    }

    fn readSlice(self: *Cursor, len: usize) DecodeError![]const u8 {
        if (len > self.bytes.len - self.index) return error.TruncatedFragment;
        const start = self.index;
        self.index += len;
        return self.bytes[start..self.index];
    }

    fn readUleb(self: *Cursor) DecodeError!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        while (true) {
            const byte = try self.readByte();
            result |= @as(u64, byte & 0x7f) << shift;
            if ((byte & 0x80) == 0) return result;
            if (shift >= 63) return error.TruncatedFragment;
            shift += 7;
        }
    }

    fn readName(self: *Cursor, allocator: std.mem.Allocator) DecodeError![]const u8 {
        const len = try self.readUleb();
        if (len > self.bytes.len) return error.TruncatedFragment;
        return try allocator.dupe(u8, try self.readSlice(@intCast(len)));
    }

    fn readNameList(self: *Cursor, allocator: std.mem.Allocator) DecodeError![]const []const u8 {
        const count = try self.readUleb();
        if (count > self.bytes.len) return error.TruncatedFragment;
        const names = try allocator.alloc([]const u8, @intCast(count));
        var filled: usize = 0;
        errdefer {
            for (names[0..filled]) |name| allocator.free(name);
            allocator.free(names);
        }
        while (filled < count) : (filled += 1) {
            names[filled] = try self.readName(allocator);
        }
        return names;
    }
};

pub fn isFragment(bytes: []const u8) bool {
    return sab.isFragmentBytes(bytes);
}

/// Decode a fragment container. Version fields are checked loudly:
/// a container written by a newer fragment format, or carrying a
/// payload in a SAB version this host does not speak, is rejected
/// instead of being reinterpreted.
pub fn decodeFragment(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!FragmentArtifact {
    if (!sab.isFragmentBytes(bytes)) return error.InvalidFragmentMagic;
    var cursor = Cursor{ .bytes = bytes, .index = sab.fragment_magic.len };
    const fmt_major = try cursor.readByte();
    const fmt_minor = try cursor.readByte();
    if (fmt_major != format_major or fmt_minor != format_minor) return error.UnsupportedFragmentVersion;
    const sab_major = try cursor.readByte();
    const sab_minor = try cursor.readByte();
    if (sab_major != sab.version_major) return error.UnsupportedFragmentVersion;
    const sha_bytes = try cursor.readSlice(32);
    var source_sha256: [32]u8 = undefined;
    @memcpy(&source_sha256, sha_bytes);
    const caller = try cursor.readName(allocator);
    errdefer allocator.free(caller);
    const function_name = try cursor.readName(allocator);
    errdefer allocator.free(function_name);
    const reads = try cursor.readNameList(allocator);
    errdefer freeNames(allocator, reads);
    const owns = try cursor.readNameList(allocator);
    errdefer freeNames(allocator, owns);
    const returns = try cursor.readNameList(allocator);
    errdefer freeNames(allocator, returns);
    const payload_len = try cursor.readUleb();
    if (payload_len > cursor.bytes.len) return error.TruncatedFragment;
    const payload = try cursor.readSlice(@intCast(payload_len));
    return .{
        .contract = .{
            .function_name = function_name,
            .reads = reads,
            .owns = owns,
            .returns = returns,
            .caller = caller,
        },
        .source_sha256 = source_sha256,
        .sab_major = sab_major,
        .sab_minor = sab_minor,
        .payload = payload,
    };
}
