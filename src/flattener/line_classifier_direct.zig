const std = @import("std");
const ClassifiedLine = @import("line_classifier.zig").ClassifiedLine;
const addPart = @import("line_classifier.zig").addPart;
const makeLine = @import("line_classifier.zig").makeLine;
const parseAddress = @import("line_classifier.zig").parseAddress;
const parseCommaPair = @import("line_classifier.zig").parseCommaPair;
const splitIndirectSigSuffix = @import("line_classifier.zig").splitIndirectSigSuffix;
const splitTrailingType = @import("line_classifier.zig").splitTrailingType;
const startsWithWord = @import("line_classifier.zig").startsWithWord;

pub fn classifyDirect(line: *ClassifiedLine, trimmed: []const u8) bool {
    if (trimmed.len != 0 and trimmed[0] == '!') {
        const rest = std.mem.trim(u8, trimmed[1..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .release;
        addPart(line, 0, rest);
        return true;
    }

    if (trimmed.len != 0 and trimmed[0] == '^') {
        const rest = std.mem.trim(u8, trimmed[1..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .move_;
        addPart(line, 0, rest);
        return true;
    }

    // `transfer <container>, <value>` — ownership of `value` moves into
    // `container` (verifier-visible annotation, runtime no-op).
    if (startsWithWord(trimmed, "transfer")) {
        const rest = std.mem.trimStart(u8, trimmed["transfer".len..], " \t");
        const pair = parseCommaPair(rest) orelse return false;
        const container = std.mem.trim(u8, pair.left, " \t");
        const value = std.mem.trim(u8, pair.right, " \t");
        if (container.len == 0 or value.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .transfer;
        addPart(line, 0, container);
        addPart(line, 1, value);
        return true;
    }

    if (startsWithWord(trimmed, "store")) {
        const rest = std.mem.trimStart(u8, trimmed["store".len..], " \t");
        const pair = parseCommaPair(rest) orelse return false;
        const addr = parseAddress(pair.left) orelse return false;
        var value = pair.right;
        var ty_text: []const u8 = "";
        if (splitTrailingType(value)) |suffix| {
            value = suffix.body;
            ty_text = suffix.ty;
        }
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .store;
        addPart(line, 0, addr.base);
        addPart(line, 1, addr.offset);
        addPart(line, 2, value);
        if (ty_text.len != 0) addPart(line, 3, ty_text);
        return true;
    }

    if (startsWithWord(trimmed, "atomic_store")) {
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .atomic_store;
        addPart(line, 0, trimmed);
        return true;
    }

    if (startsWithWord(trimmed, "br_null")) {
        const rest = std.mem.trimStart(u8, trimmed["br_null".len..], " \t");
        const pair = parseCommaPair(std.mem.trimStart(u8, rest, " \t")) orelse return false;
        const arrow = std.mem.indexOf(u8, pair.left, "->") orelse return false;
        const reg = std.mem.trim(u8, pair.left[0..arrow], " \t");
        const label = std.mem.trim(u8, pair.left[arrow + 2 ..], " \t");
        if (reg.len == 0 or label.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .br_null;
        addPart(line, 0, reg);
        addPart(line, 1, label);
        addPart(line, 2, pair.right);
        return true;
    }

    if (startsWithWord(trimmed, "br")) {
        const rest = std.mem.trimStart(u8, trimmed["br".len..], " \t");
        const arrow = std.mem.indexOf(u8, rest, "->") orelse return false;
        const cond = std.mem.trim(u8, rest[0..arrow], " \t");
        const pair = parseCommaPair(std.mem.trimStart(u8, rest[arrow + 2 ..], " \t")) orelse return false;
        if (cond.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .br;
        addPart(line, 0, cond);
        addPart(line, 1, pair.left);
        addPart(line, 2, pair.right);
        return true;
    }

    if (startsWithWord(trimmed, "jmp")) {
        const rest = std.mem.trimStart(u8, trimmed["jmp".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .jmp;
        addPart(line, 0, rest);
        return true;
    }

    if (startsWithWord(trimmed, "call_indirect")) {
        const rest = std.mem.trimStart(u8, trimmed["call_indirect".len..], " \t");
        if (rest.len == 0) return false;
        // C2 sab_carried_indirect_sig: see the assignment form above.
        const split = splitIndirectSigSuffix(rest);
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .call_indirect;
        addPart(line, 0, split.body);
        if (split.sig) |sig_text| {
            addPart(line, 1, sig_text);
            line.has_carried_sig = true;
        }
        return true;
    }

    if (startsWithWord(trimmed, "call")) {
        const rest = std.mem.trimStart(u8, trimmed["call".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .call;
        addPart(line, 0, rest);
        return true;
    }

    if (startsWithWord(trimmed, "panic_msg")) {
        const rest = std.mem.trimStart(u8, trimmed["panic_msg".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .panic_msg;
        addPart(line, 0, rest);
        return true;
    }

    if (startsWithWord(trimmed, "?")) {
        const rest = std.mem.trim(u8, trimmed["?".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .try_;
        addPart(line, 0, rest);
        return true;
    }

    if (startsWithWord(trimmed, "panic")) {
        const rest = std.mem.trimStart(u8, trimmed["panic".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .panic;
        addPart(line, 0, rest);
        return true;
    }

    if (startsWithWord(trimmed, "va_end")) {
        const rest = std.mem.trimStart(u8, trimmed["va_end".len..], " \t");
        if (rest.len == 0) return false;
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .va_end;
        addPart(line, 0, rest);
        return true;
    }

    if (std.mem.startsWith(u8, trimmed, "fence")) {
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .fence;
        addPart(line, 0, trimmed);
        return true;
    }

    if (startsWithWord(trimmed, "return")) {
        const rest = std.mem.trimStart(u8, trimmed["return".len..], " \t");
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .return_;
        if (rest.len != 0) addPart(line, 0, rest);
        return true;
    }

    if (startsWithWord(trimmed, "ret")) {
        const rest = std.mem.trimStart(u8, trimmed["ret".len..], " \t");
        line.* = makeLine(.instruction, line.raw, line.trimmed);
        line.inst_form = .return_;
        if (rest.len != 0) addPart(line, 0, rest);
        return true;
    }

    return false;
}
