const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const trackWidths = @import("widths.zig").trackWidths;
const writePreamble = @import("preamble.zig").writePreamble;

pub const CEmitOptions = struct {
    mem_pages: u32 = 256, // 256 * 64KiB = 16MiB initial
    debug_comments: bool = true,
    gas: bool = true, // emit SA_GAS_CHECK metering (fn entry + every label)
};

pub const FuncTask = struct {
    fsig_index: usize,
    start_idx: usize,
    end_idx: usize,
    kind: inst.InstKind,
};

/// Statically tracked value widths per slot, ported from the JS backend
/// (see emit_js trackWidths). Keyed by local slot. Cleared at labels;
/// seeded from parameter types and known callee return types, which the
/// C backend can do exactly (both sides share the u64-bits invariant).
/// Packing: low 8 bits = width, bit 30 = signed int domain,
/// bit 31 = float domain.
pub const WidthMap = std.AutoHashMap(u32, u32);

pub const WidthSignBit: u32 = 0x40000000;

pub const WidthFloatBit: u32 = 0x80000000;

/// Operand domain for kind-driven compat aliases (div/rem/gt/lt/shr),
/// mirroring the interpreter and the JS backend: float wins, then signed,
/// else unsigned. Unknown preserves forced-signed lowering, so only
/// statically-known shapes change behavior.
pub const COpndKind = enum { float, signed, unsigned, unknown };

/// Float-domain decision for binary float ops: .f32 uses the 32-bit
/// helper, .f64 the 64-bit one. f32 iff both sides are proven f32;
/// everything else computes in f64 (int sides convert with JS Numbers
/// parity; unknowns go raw, with f32 sides promoted). Unknowns are
/// overwhelmingly f64 loop vars/indirect results, and promotion of a
/// known f32 side is exact, so f64 is the safe default.
pub const FDom = enum { f32, f64 };

/// Runtime helper catalog. The always-needed core (includes, memory,
/// sa_trap, gas) is emitted unconditionally by writePreamble; everything
/// below is emitted ONLY when the generated body references it (plus
/// transitive deps). `name` doubles as the usage needle (`name ++ "("`),
/// so it must be the exact C function name. `deps` lists other catalog
/// entries required by `code` (`sa_trap` is implicit: always emitted).
/// Emission preserves table order, which keeps callees before callers.
pub const HelperDef = struct {
    name: []const u8,
    code: []const u8,
    deps: []const []const u8,
};

/// Slots proven (within the current straight-line stretch) to hold
/// owned heap bases produced by `alloc`/`stack_alloc` (both lower to
/// sa_alloc in the C model). `.release` emits a real `sa_free` only
/// for these; every other release stays a no-op comment. This mirrors
/// the interpreter, which frees exact owned bases but never interior
/// pointers, borrows, consts, or stack slots — and mirrors emit_js's
/// provenance gate, adopted here when sa_free became a real free
/// (DEF deep-drop batch, DESIGN §3): unconditional freeing corrupts
/// live buffers whose pointers pass through load/store registers
/// (value equality alone is unsound). Conservative direction is
/// leak-only: labels clear the set, call results are unknown,
/// move/by-value call arguments and stored values escape (killed),
/// borrow arguments are only read through (kept).
pub const CBaseSet = std.AutoHashMap(u32, void);

pub const TfSyncInfo = struct {
    id: u32,
    reload: []const u32,
};

pub const TfFnCtx = struct {
    prog: *const TfProgram,
    fnid: u32,
};

pub const TfProgram = struct {
    fnid_of_fsig: std.AutoHashMap(usize, u32),
    fnid_by_name: std.StringHashMap(u32),
    fsig_of_fnid: []usize = &.{},
    may_store: [][]bool = &.{},
    may_store_any: []bool = &.{},

    fn count(self: *const TfProgram) usize {
        return self.fsig_of_fnid.len;
    }

    fn deinit(self: *TfProgram, allocator: std.mem.Allocator) void {
        self.fnid_of_fsig.deinit();
        self.fnid_by_name.deinit();
        if (self.fsig_of_fnid.len > 0) allocator.free(self.fsig_of_fnid);
        for (self.may_store) |row| {
            if (row.len > 0) allocator.free(row);
        }
        if (self.may_store.len > 0) allocator.free(self.may_store);
        if (self.may_store_any.len > 0) allocator.free(self.may_store_any);
    }
};

// Provenance sentinel: a pointer slot that may alias ANY parameter.
pub const TF_PROV_ANY: u32 = 0xFFFFFFFF;
