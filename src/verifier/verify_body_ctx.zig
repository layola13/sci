const std = @import("std");
const inst = @import("../common/instruction.zig");
const classifier = @import("../flattener/line_classifier.zig");
const pkg_manifest = @import("../pkg/manifest.zig");
const sig = @import("../common/signature.zig");
const trap = @import("../common/trap.zig");
const AnnotatedInstruction = @import("reg_state_change.zig").AnnotatedInstruction;
const CollectResult = @import("reg_state_change.zig").CollectResult;
const FunctionRegScope = @import("reg_state_change.zig").FunctionRegScope;
const InteriorContext = @import("reg_state_change.zig").InteriorContext;
const LabelSnapshot = @import("reg_state_change.zig").LabelSnapshot;
const SaxValidationContext = @import("reg_state_change.zig").SaxValidationContext;
const VerifierBufferPool = @import("clear_borrow_ctx.zig").VerifierBufferPool;

pub const VerifyBodyCtx = struct {
    snapshot_scratch: []u16,
    sig_index: usize,
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
    consumed_in_function: []bool,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    interior_root: []?u32,
    interior_offset: []u64,
    interior_offset_known: []bool,
    alloc_size: []u64,
    alloc_size_known: []bool,
    buffers: VerifierBufferPool,
    current_scope: ?FunctionRegScope,
    interior: InteriorContext,
    atomic_history: std.AutoHashMap(u64, u8),
    labels: std.AutoHashMap(u32, LabelSnapshot),
    defined_labels: std.AutoHashMap(u32, void),
    annotated: std.array_list.Managed(AnnotatedInstruction),
    current_function_text: ?[]const u8,
    current_is_ffi_wrapper: bool,
    current_sig: ?sig.FunctionSig,
    body_seen: bool,
    terminated: bool,
    fatal_terminated: bool,
    gas_alloc_bytes: u64,
    gas_steps: u64,
    has_unbounded_loop: bool,
    last_seen_label: ?u32,
    deferred_exit_leak: ?trap.TrapReport,
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    classified_lines: []const classifier.ClassifiedLine,
    metadata: *const CollectResult,
    check_exit_leaks: bool,
    package_grants: []const pkg_manifest.RequireEntry,
    sax_context: ?SaxValidationContext,
    default_immutable: bool,
};
