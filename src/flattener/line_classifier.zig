const std = @import("std");
test "line_classifier_tests" { std.testing.refAllDecls(@import("line_classifier_test.zig")); }
const common_instruction = @import("../common/instruction.zig");
pub const common_signature = @import("../common/signature.zig");

pub const LineKind = enum {
    blank_or_comment,
    version,
    def,
    const_decl,
    import_decl,
    loc_hint,
    npm_bind,
    func_decl,
    ffi_wrapper_decl,
    extern_decl,
    export_decl,
    test_decl,
    gpu_decl,
    label,
    macro_start,
    macro_end,
    rep_start,
    rep_end,
    if_start,
    else_,
    if_end,
    expand,
    instruction,
    native,
    unknown,
};

pub const InstructionForm = enum {
    alloc,
    stack_alloc,
    load,
    store,
    atomic_load,
    atomic_store,
    cmpxchg,
    atomic_rmw,
    fence,
    borrow,
    move_,
    release,
    assign,
    op,
    ptr_add,
    jmp,
    br,
    br_null,
    call,
    call_indirect,
    try_,
    panic,
    panic_msg,
    return_,
    take,
    raw_cast,
    assume_safe,
    assume_borrow,
    va_start,
    va_arg,
    va_end,
    transfer,
    unknown,
};

pub const ClassifiedLine = struct {
    kind: LineKind,
    inst_form: ?InstructionForm = null,
    raw: []const u8,
    trimmed: []const u8,
    parts: [6][]const u8 = .{ "", "", "", "", "", "" },
    part_count: u8 = 0,
    /// C2 sab_carried_indirect_sig: a call_indirect line carried a
    /// ` : (params, ...) -> ret` signature suffix; the suffix text is
    /// the last part (index 2 in the dst form, index 1 in the no-dst
    /// form) and routes to operands[3].
    has_carried_sig: bool = false,
};

pub const isIdentStart = @import("line_classifier_parse.zig").isIdentStart;

pub const isIdentChar = @import("line_classifier_parse.zig").isIdentChar;

pub const isQualifiedDefName = @import("line_classifier_parse.zig").isQualifiedDefName;

pub const containsToken = @import("line_classifier_parse.zig").containsToken;

pub const startsWithWord = @import("line_classifier_parse.zig").startsWithWord;

pub const parseTestModifierPrefix = @import("line_classifier_parse.zig").parseTestModifierPrefix;

pub const makeLine = @import("line_classifier_parse.zig").makeLine;

pub const addPart = @import("line_classifier_parse.zig").addPart;

/// C2 sab_carried_indirect_sig: split a trailing ` : (params, ...) -> ret`
/// signature suffix off a call_indirect body. The suffix starts after the
/// argument list's balancing close paren; anything else leaves the body
/// untouched (the referee parser rejects trailing junk downstream).
pub const splitIndirectSigSuffix = @import("line_classifier_parse.zig").splitIndirectSigSuffix;

pub const splitFirstWord = @import("line_classifier_parse.zig").splitFirstWord;

pub const splitAssignment = @import("line_classifier_parse.zig").splitAssignment;

pub const parseConstDecl = @import("line_classifier_parse.zig").parseConstDecl;

pub const parseAddress = @import("line_classifier_parse.zig").parseAddress;

pub const parseCommaPair = @import("line_classifier_parse.zig").parseCommaPair;

pub const parseCommaTriple = @import("line_classifier_parse.zig").parseCommaTriple;

pub const TypedSuffix = @import("line_classifier_parse.zig").TypedSuffix;

pub const splitTrailingType = @import("line_classifier_parse.zig").splitTrailingType;

pub const splitPrimitiveTypedValue = @import("line_classifier_parse.zig").splitPrimitiveTypedValue;

pub const collectNativeRegisterNames = @import("line_classifier_parse.zig").collectNativeRegisterNames;

pub const parseFunctionHeader = @import("line_classifier_parse.zig").parseFunctionHeader;

pub const parseLocHint = @import("line_classifier_parse.zig").parseLocHint;

pub const parseImport = @import("line_classifier_parse.zig").parseImport;

pub const parseNpmBind = @import("line_classifier_parse.zig").parseNpmBind;

fn classifyAssignment(line: *ClassifiedLine, lhs_text: []const u8, rhs_text: []const u8) bool {
    const lhs = std.mem.trim(u8, lhs_text, " \t");
    const rhs = std.mem.trim(u8, rhs_text, " \t");
    if (lhs.len == 0 or rhs.len == 0) return false;

    const typed_rhs = splitPrimitiveTypedValue(rhs);
    const simple_rhs = if (typed_rhs) |typed| typed.body else rhs;

    if (std.mem.startsWith(u8, simple_rhs, "*")) {
        const source = std.mem.trim(u8, simple_rhs[1..], " \t");
        if (source.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .raw_cast;
        addPart(line, 0, lhs);
        addPart(line, 1, source);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "assume_safe")) {
        const rest = std.mem.trimStart(u8, simple_rhs["assume_safe".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .assume_safe;
        addPart(line, 0, lhs);
        addPart(line, 1, rest);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "assume_borrow")) {
        const rest = std.mem.trimStart(u8, simple_rhs["assume_borrow".len..], " \t");
        if (rest.len == 0) return false;
        const pair = parseCommaPair(rest);
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .assume_borrow;
        if (pair) |p| {
            addPart(line, 0, lhs);
            addPart(line, 1, p.left);
            addPart(line, 2, p.right);
        } else {
            addPart(line, 0, lhs);
            addPart(line, 1, rest);
        }
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "call_indirect")) {
        // Must be a word boundary: "call_indirect_foo" is a variable, not a call.
        // Check that the char after "call_indirect" is not alphanumeric or underscore.
        const after = simple_rhs["call_indirect".len..];
        if (after.len > 0 and (std.ascii.isAlphanumeric(after[0]) or after[0] == '_')) {
            // Not a call_indirect keyword, fall through to other handlers.
        } else {
            const rest = std.mem.trimStart(u8, after, " \t");
            if (rest.len == 0) return false;
            // C2 sab_carried_indirect_sig: a carried fn-pointer
            // signature suffix becomes its own part (flattener routes
            // it to operands[3]).
            const split = splitIndirectSigSuffix(rest);
            line.* = makeLine(.instruction, line.raw, line.trimmed);
            line.inst_form = .call_indirect;
            addPart(line, 0, lhs);
            addPart(line, 1, split.body);
            if (split.sig) |sig_text| {
                addPart(line, 2, sig_text);
                line.has_carried_sig = true;
            }
            return true;
        }
    }

    if (std.mem.startsWith(u8, simple_rhs, "ptr_add")) {
        const rest = std.mem.trimStart(u8, simple_rhs["ptr_add".len..], " \t");
        const pair = parseCommaPair(rest) orelse return false;
        if (pair.left.len == 0 or pair.right.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .ptr_add;
        addPart(line, 0, lhs);
        addPart(line, 1, pair.left);
        addPart(line, 2, pair.right);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "call")) {
        // Must be a word boundary: "calls_ptr" is a variable, not a call.
        // Check that the char after "call" is not alphanumeric or underscore.
        const after = simple_rhs["call".len..];
        if (after.len > 0 and (std.ascii.isAlphanumeric(after[0]) or after[0] == '_')) {
            // Not a call keyword, fall through to other handlers.
        } else {
            const rest = std.mem.trimStart(u8, after, " \t");
            if (rest.len == 0) return false;
            line.* = makeLine(.instruction, line.raw, line.trimmed);
            line.inst_form = .call;
            addPart(line, 0, lhs);
            addPart(line, 1, rest);
            return true;
        }
    }

    if (std.mem.startsWith(u8, simple_rhs, "atomic_load")) {
        const rest = std.mem.trimStart(u8, simple_rhs["atomic_load".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .atomic_load;
        addPart(line, 0, lhs);
        addPart(line, 1, rest);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "cmpxchg")) {
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .cmpxchg;
        addPart(line, 0, lhs);
        addPart(line, 1, simple_rhs);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "atomic_rmw_")) {
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .atomic_rmw;
        addPart(line, 0, lhs);
        addPart(line, 1, simple_rhs);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "?")) {
        const rest = std.mem.trim(u8, simple_rhs["?".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .try_;
        addPart(line, 0, lhs);
        addPart(line, 1, rest);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "&")) {
        var source = std.mem.trim(u8, simple_rhs["&".len..], " \t");
        if (source.len == 0) return false;
        // Rust-style exclusive borrow: `x = &mut y` takes a mutable borrow of
        // `y`, while `x = &y` keeps the shared borrow. The borrow mode is a
        // verifier-level discipline only; every backend lowers both forms to
        // the same pointer value.
        var mode: []const u8 = "read";
        if (std.mem.startsWith(u8, source, "mut")) {
            const rest = source["mut".len..];
            if (rest.len > 0 and (rest[0] == ' ' or rest[0] == '\t')) {
                mode = "mut";
                source = std.mem.trim(u8, rest, " \t");
            }
        }
        if (source.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .borrow;
        addPart(line, 0, lhs);
        addPart(line, 1, mode);
        addPart(line, 2, source);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "alloc ")) {
        const size = std.mem.trim(u8, simple_rhs["alloc ".len..], " \t");
        if (size.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .alloc;
        addPart(line, 0, lhs);
        addPart(line, 1, size);
        return true;
    }

    if (std.mem.eql(u8, simple_rhs, "va_start")) {
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .va_start;
        addPart(line, 0, lhs);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "va_arg ")) {
        const rest = std.mem.trim(u8, simple_rhs["va_arg ".len..], " \t");
        const pair = parseCommaPair(rest) orelse return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .va_arg;
        addPart(line, 0, lhs);
        addPart(line, 1, pair.left);
        addPart(line, 2, pair.right);
        return true;
    }

    if (std.mem.startsWith(u8, simple_rhs, "stack_alloc ")) {
        const size = std.mem.trim(u8, simple_rhs["stack_alloc ".len..], " \t");
        if (size.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .stack_alloc;
        addPart(line, 0, lhs);
        addPart(line, 1, size);
        return true;
    }

    if (std.mem.startsWith(u8, rhs, "load ")) {
        var address = std.mem.trim(u8, rhs["load ".len..], " \t");
        var ty_text: []const u8 = "";
        if (splitTrailingType(address)) |suffix| {
            address = suffix.body;
            ty_text = suffix.ty;
        }
        const parsed = parseAddress(address) orelse return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .load;
        addPart(line, 0, lhs);
        addPart(line, 1, parsed.base);
        addPart(line, 2, parsed.offset);
        if (ty_text.len != 0) addPart(line, 3, ty_text);
        return true;
    }

    if (std.mem.startsWith(u8, rhs, "take ")) {
        var address = std.mem.trim(u8, rhs["take ".len..], " \t");
        var ty_text: []const u8 = "";
        if (splitTrailingType(address)) |suffix| {
            address = suffix.body;
            ty_text = suffix.ty;
        }
        const parsed = parseAddress(address) orelse return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .take;
        addPart(line, 0, lhs);
        addPart(line, 1, parsed.base);
        addPart(line, 2, parsed.offset);
        if (ty_text.len != 0) addPart(line, 3, ty_text);
        return true;
    }

    const op = splitFirstWord(rhs);
    if (op.word.len != 0) {
        if (common_instruction.parseOpKind(op.word)) |op_kind| {
            line.* = makeLine(.instruction, line.raw, line.trimmed);
            line.inst_form = .op;
            addPart(line, 0, lhs);
            addPart(line, 1, op.word);

            const rest_trimmed = std.mem.trim(u8, op.rest, " \t");
            const typed = if (std.mem.lastIndexOf(u8, rest_trimmed, " as ")) |idx| blk: {
                const body = std.mem.trimEnd(u8, rest_trimmed[0..idx], " \t");
                const ty = std.mem.trim(u8, rest_trimmed[idx + 4 ..], " \t");
                if (ty.len == 0) break :blk null;
                break :blk .{ .body = body, .ty = ty };
            } else null;

            switch (op_kind) {
                .neg, .not, .fneg, .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext, .bitcast => {
                    const body = if (typed) |suffix| suffix.body else rest_trimmed;
                    if (body.len == 0) return false;
                    addPart(line, 2, body);
                    if (typed) |suffix| addPart(line, 3, suffix.ty);
                    return true;
                },
                .extract_lane => {
                    const pair = parseCommaPair(rest_trimmed) orelse return false;
                    addPart(line, 2, pair.left);
                    addPart(line, 3, pair.right);
                    return true;
                },
                .insert_lane, .shuffle_v128 => {
                    const triple = parseCommaTriple(rest_trimmed) orelse return false;
                    addPart(line, 2, triple.first);
                    addPart(line, 3, triple.second);
                    addPart(line, 4, triple.third);
                    return true;
                },
                else => {
                    const pair = parseCommaPair(rest_trimmed) orelse return false;
                    addPart(line, 2, pair.left);
                    addPart(line, 3, pair.right);
                    return true;
                },
            }
        }
    }

    if (op.word.len != 0 and std.mem.trim(u8, op.rest, " \t").len == 0) {
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .assign;
        addPart(line, 0, lhs);
        addPart(line, 1, op.word);
        return true;
    }

    if (typed_rhs) |typed| {
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .assign;
        addPart(line, 0, lhs);
        addPart(line, 1, typed.body);
        return true;
    }

    return false;
}

pub const classifyDirect = @import("line_classifier_direct.zig").classifyDirect;

pub fn classifyLine(line: []const u8) ClassifiedLine {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) {
        return makeLine(.blank_or_comment, line, trimmed);
    }

    if (trimmed.len >= 2 and trimmed[0] == '$' and trimmed[trimmed.len - 1] == '$') {
        var out = makeLine(.native, line, trimmed);
        addPart(&out, 0, trimmed[1 .. trimmed.len - 1]);
        return out;
    }

    if (std.mem.startsWith(u8, trimmed, "#version")) {
        const after = std.mem.trimStart(u8, trimmed["#version".len..], " \t");
        if (after.len == 0) return makeLine(.unknown, line, trimmed);
        var i: usize = 0;
        while (i < after.len and std.ascii.isDigit(after[i])) : (i += 1) {}
        if (i == 0 or std.mem.trim(u8, after[i..], " \t").len != 0) return makeLine(.unknown, line, trimmed);
        var out = makeLine(.version, line, trimmed);
        addPart(&out, 0, after[0..i]);
        return out;
    }

    if (std.mem.startsWith(u8, trimmed, "#def")) {
        const after = std.mem.trimStart(u8, trimmed["#def".len..], " \t");
        const eq = std.mem.indexOfScalar(u8, after, '=') orelse return makeLine(.unknown, line, trimmed);
        const name = std.mem.trim(u8, after[0..eq], " \t");
        const value = std.mem.trim(u8, after[eq + 1 ..], " \t");
        if (name.len == 0 or value.len == 0) return makeLine(.unknown, line, trimmed);
        if (!isQualifiedDefName(name)) return makeLine(.unknown, line, trimmed);
        var out = makeLine(.def, line, trimmed);
        addPart(&out, 0, name);
        addPart(&out, 1, value);
        return out;
    }

    if (parseConstDecl(line, trimmed)) |out| return out;

    if (parseLocHint(line, trimmed)) |out| return out;
    if (parseImport(line, trimmed)) |out| return out;
    if (parseNpmBind(line, trimmed)) |out| return out;

    if (parseFunctionHeader(line, trimmed, "@ffi_wrapper", .ffi_wrapper_decl, true)) |out| return out;
    if (parseFunctionHeader(line, trimmed, "@extern", .extern_decl, false)) |out| return out;
    if (parseFunctionHeader(line, trimmed, "@export", .export_decl, true)) |out| return out;
    if (parseFunctionHeader(line, trimmed, "@test", .test_decl, true)) |out| return out;
    if (parseFunctionHeader(line, trimmed, "@gpu", .gpu_decl, true)) |out| return out;
    if (parseFunctionHeader(line, trimmed, "@", .func_decl, true)) |out| return out;

    if (trimmed.len >= 3 and trimmed[0] == 'L' and trimmed[1] == '_' and trimmed[trimmed.len - 1] == ':') {
        const name = trimmed[0 .. trimmed.len - 1];
        if (name.len < 3) return makeLine(.unknown, line, trimmed);
        var valid = true;
        for (name[2..]) |c| {
            if (!isIdentChar(c)) {
                valid = false;
                break;
            }
        }
        if (valid) {
            var out = makeLine(.label, line, trimmed);
            addPart(&out, 0, name);
            return out;
        }
    }

    if (std.mem.startsWith(u8, trimmed, "[MACRO]")) {
        const after = std.mem.trimStart(u8, trimmed["[MACRO]".len..], " \t");
        const pair = splitFirstWord(after);
        if (pair.word.len != 0) {
            var out = makeLine(.macro_start, line, trimmed);
            addPart(&out, 0, pair.word);
            addPart(&out, 1, pair.rest);
            return out;
        }
    }

    if (std.mem.eql(u8, trimmed, "[END_MACRO]")) {
        return makeLine(.macro_end, line, trimmed);
    }

    if (std.mem.startsWith(u8, trimmed, "[REP")) {
        const close = std.mem.indexOfScalar(u8, trimmed, ']') orelse return makeLine(.unknown, line, trimmed);
        const count = std.mem.trim(u8, trimmed["[REP".len..close], " \t");
        if (count.len == 0) return makeLine(.unknown, line, trimmed);
        var out = makeLine(.rep_start, line, trimmed);
        addPart(&out, 0, count);
        return out;
    }

    if (std.mem.eql(u8, trimmed, "[END_REP]")) {
        return makeLine(.rep_end, line, trimmed);
    }

    if (std.mem.startsWith(u8, trimmed, "[IF")) {
        const close = std.mem.indexOfScalar(u8, trimmed, ']') orelse return makeLine(.unknown, line, trimmed);
        const condition = std.mem.trim(u8, trimmed["[IF".len..close], " \t");
        if (condition.len == 0) return makeLine(.unknown, line, trimmed);
        var out = makeLine(.if_start, line, trimmed);
        addPart(&out, 0, condition);
        return out;
    }

    if (std.mem.eql(u8, trimmed, "[ELSE]")) {
        return makeLine(.else_, line, trimmed);
    }

    if (std.mem.eql(u8, trimmed, "[END_IF]")) {
        return makeLine(.if_end, line, trimmed);
    }

    if (std.mem.startsWith(u8, trimmed, "EXPAND")) {
        const after = std.mem.trimStart(u8, trimmed["EXPAND".len..], " \t");
        const pair = splitFirstWord(after);
        if (pair.word.len != 0) {
            var out = makeLine(.expand, line, trimmed);
            addPart(&out, 0, pair.word);
            addPart(&out, 1, pair.rest);
            return out;
        }
    }

    const assignment = splitAssignment(trimmed);
    if (assignment) |assign| {
        var out = makeLine(.unknown, line, trimmed);
        if (classifyAssignment(&out, assign.lhs, assign.rhs)) return out;
    }

    var direct = makeLine(.unknown, line, trimmed);
    if (classifyDirect(&direct, trimmed)) return direct;

    return makeLine(.unknown, line, trimmed);
}


