const std = @import("std");
const emit_options = @import("../emit_options.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");

pub const JsEmitError = error{ Failed, InvalidOperand, UnknownFunction, UnsupportedInstruction, UnsupportedVariadic, UnsupportedNpmBinding, UnsupportedDtsType, OutOfMemory };

pub const JsFormat = enum {
    esm,
    cjs,

    pub fn parse(text: []const u8) ?JsFormat {
        if (std.mem.eql(u8, text, "esm") or std.mem.eql(u8, text, "mjs")) return .esm;
        if (std.mem.eql(u8, text, "cjs") or std.mem.eql(u8, text, "cjs")) return .cjs;
        return null;
    }
};

pub const JsEmitOptions = struct {
    format: JsFormat = .esm,
    mem_pages: u32 = 256, // 256 * 64KiB = 16MiB initial
    debug_comments: bool = true,
    /// Extern trap-stub dead-code elimination, threaded in from
    /// CompileOptions.dce by `sa build-js --dce`: .no keeps every
    /// unbound extern's trap stub (the pre-DCE behavior, kept for
    /// debugging); .std/.full drop stubs for externs that no emitted
    /// code references. The struct default is .full so existing
    /// callers keep the current (trimming) behavior unchanged.
    dce: emit_options.DceMode = .full,
    emit_dts: bool = false,
};

pub const FuncTask = struct {
    fsig_index: usize,
    start_idx: usize, // index of func_decl in annotated
    end_idx: usize, // exclusive
    kind: inst.InstKind,
};

/// Maps a callee name to its declared return primitive type.
pub const CalleeRetTable = std.StringHashMap(sig.PrimType);

pub const RetBaseInfo = union(enum) { alloc: void, param: usize };
pub const RetBaseTable = std.StringHashMap(RetBaseInfo);

pub const BaseSet = std.AutoHashMap(u32, void);

/// Last instruction raw text seen by the emitter (diagnostics only).
pub threadlocal var last_js_inst: []const u8 = "";
pub threadlocal var last_js_func: []const u8 = "";
