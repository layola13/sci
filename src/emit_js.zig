const std = @import("std");

const emit_options = @import("emit_options.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const call = @import("referee/call.zig");
const const_decl = @import("common/const_decl.zig");
const sio = @import("sio");
const shims_std_fs_compress_multipart = @import("emit_js/shims_std_fs_compress_multipart.zig");
const shims_std_net_tcp_udp = @import("emit_js/shims_std_net_tcp_udp.zig");
const shims_std_udp_ssh_tls = @import("emit_js/shims_std_udp_ssh_tls.zig");
const shims_std_tls_shaped = @import("emit_js/shims_std_tls_shaped.zig");
const shims_http_client = @import("emit_js/shims_http_client.zig");
const shims_http_server_sse_ws = @import("emit_js/shims_http_server_sse_ws.zig");
const shims_json_core = @import("emit_js/shims_json_core.zig");
const shims_json_writer_write = @import("emit_js/shims_json_writer_write.zig");
const shims_cookie = @import("emit_js/shims_cookie.zig");
const shims_cookie_value = @import("emit_js/shims_cookie_value.zig");
const shims_misc_regex_string = @import("emit_js/shims_misc_regex_string.zig");
const shims_misc_fmt_node_time = @import("emit_js/shims_misc_fmt_node_time.zig");
const shims_misc_deno_math_sync_task = @import("emit_js/shims_misc_deno_math_sync_task.zig");
const shims_misc_chan_mem_globals = @import("emit_js/shims_misc_chan_mem_globals.zig");

pub const EmitOptions = emit_options.EmitOptions;
pub const JsEmitError = @import("emit_js/types.zig").JsEmitError;
const types = @import("emit_js/types.zig");

/// Last instruction raw text seen by the emitter (diagnostics only).

pub const JsFormat = @import("emit_js/types.zig").JsFormat;

pub const JsEmitOptions = @import("emit_js/types.zig").JsEmitOptions;

const isJsReserved = @import("emit_js/ident.zig").isJsReserved;
const isEmitterReserved = @import("emit_js/ident.zig").isEmitterReserved;
const jsIdent = @import("emit_js/ident.zig").jsIdent;
const jsFuncName = @import("emit_js/ident.zig").jsFuncName;
const tagToPrim = @import("emit_js/ident.zig").tagToPrim;
const constBytesLen = @import("emit_js/ident.zig").constBytesLen;
const fillConstBytes = @import("emit_js/ident.zig").fillConstBytes;
const writeJsStrEscaped = @import("emit_js/ident.zig").writeJsStrEscaped;
const writeConstSlot = @import("emit_js/ident.zig").writeConstSlot;
const loadedPrimType = @import("emit_js/ident.zig").loadedPrimType;
const memPrimType = @import("emit_js/ident.zig").memPrimType;
const memLoadFn = @import("emit_js/ident.zig").memLoadFn;
const memStoreFn = @import("emit_js/ident.zig").memStoreFn;
const opIsFloat = @import("emit_js/ident.zig").opIsFloat;
const FuncTask = @import("emit_js/types.zig").FuncTask;

const NpmShape = @import("emit_js/npm.zig").NpmShape;
const NpmBytesView = @import("emit_js/npm.zig").NpmBytesView;
const NpmImport = @import("emit_js/npm.zig").NpmImport;
const npmStrOut = @import("emit_js/npm.zig").npmStrOut;
const collectNpmImports = @import("emit_js/npm.zig").collectNpmImports;
const npmImportFor = @import("emit_js/npm.zig").npmImportFor;
const isNpmExportIdent = @import("emit_js/npm.zig").isNpmExportIdent;
const isNpmIntType = @import("emit_js/npm.zig").isNpmIntType;
const isNpmNumericType = @import("emit_js/npm.zig").isNpmNumericType;
const emitNpmWrapper = @import("emit_js/npm.zig").emitNpmWrapper;
const collectFuncTasks = @import("emit_js/entry.zig").collectFuncTasks;

const policy_runtime_js = @import("emit_js/runtime_policy.zig").policy_runtime_js;
const writeRuntimeHeader = @import("emit_js/entry.zig").writeRuntimeHeader;

const resolveTextToJs = @import("emit_js/instr.zig").resolveTextToJs;

/// Peephole predicate: address offset operand is a constant zero in any
/// integer domain (x+0 == x in both Number and BigInt semantics), so the
/// `__sa_ptr_add` wrapper can be skipped on the hot path.
const offIsZero = @import("emit_js/ident.zig").offIsZero;

const fnIndexOf = @import("emit_js/instr.zig").fnIndexOf;

const resolveValueToJs = @import("emit_js/instr.zig").resolveValueToJs;

const labelPcOf = @import("emit_js/dispatch.zig").labelPcOf;

const taskUsesGlobalRegIds = @import("emit_js/funcs.zig").taskUsesGlobalRegIds;

const regSlot = @import("emit_js/slots.zig").regSlot;

const cvtTargetSuffix = @import("emit_js/instr.zig").cvtTargetSuffix;

const cvtShapeValid = @import("emit_js/instr.zig").cvtShapeValid;

const opNameForCvt = @import("emit_js/instr.zig").opNameForCvt;

const emitCvtExpr = @import("emit_js/instr.zig").emitCvtExpr;

const WidthMap = @import("emit_js/widths.zig").WidthMap;
const WidthSignBit = @import("emit_js/widths.zig").WidthSignBit;
const WidthFloatBit = @import("emit_js/widths.zig").WidthFloatBit;
const packWidth = @import("emit_js/widths.zig").packWidth;
const widthIsFloat = @import("emit_js/widths.zig").widthIsFloat;
const widthIsSigned = @import("emit_js/widths.zig").widthIsSigned;
const widthBits = @import("emit_js/widths.zig").widthBits;
const widthRemoveSlot = @import("emit_js/widths.zig").widthRemoveSlot;
const widthCopySlot = @import("emit_js/widths.zig").widthCopySlot;
const OpndKind = @import("emit_js/widths.zig").OpndKind;
const operandKind = @import("emit_js/widths.zig").operandKind;
const combinedKind = @import("emit_js/widths.zig").combinedKind;
const u32SafeOperand = @import("emit_js/widths.zig").u32SafeOperand;
const useFastU32 = @import("emit_js/widths.zig").useFastU32;
const trackWidths = @import("emit_js/widths.zig").trackWidths;
const aliasCallee = @import("emit_js/instr.zig").aliasCallee;

const emitAliasOperands = @import("emit_js/instr.zig").emitAliasOperands;

const emitOpExpr = @import("emit_js/instr.zig").emitOpExpr;
const dstSlot = @import("emit_js/slots.zig").dstSlot;

/// Slots proven (within the current straight-line block) to hold owned heap
/// bases produced by `alloc`. `release` emits a real `__sa_free` only for
/// these; every other release stays a no-op comment. This mirrors the
/// interpreter, which frees exact owned bases but never interior pointers,
/// borrows, consts, or stack slots (value-equality alone is unsound: e.g.
/// `sa_mem_copy` releases borrow params whose values may equal a live base,
/// which corrupted `sort_probe` under unconditional freeing).
const BaseSet = @import("emit_js/types.zig").BaseSet;

const provSlotOf = @import("emit_js/slots.zig").provSlotOf;

const provKill = @import("emit_js/prov.zig").provKill;

const provTextSlot = @import("emit_js/prov.zig").provTextSlot;

const provKillStoreValue = @import("emit_js/prov.zig").provKillStoreValue;

const provMark = @import("emit_js/prov.zig").provMark;

const emitReturnStmt = @import("emit_js/dispatch.zig").emitReturnStmt;

const callDestSlot = @import("emit_js/instr.zig").callDestSlot;

const emitCallInstruction = @import("emit_js/instr.zig").emitCallInstruction;

const emitCallIndirectInstruction = @import("emit_js/instr.zig").emitCallIndirectInstruction;

const PromoInfo = @import("emit_js/prov.zig").PromoInfo;
const PromoMap = @import("emit_js/prov.zig").PromoMap;

const promoNarrowBits = @import("emit_js/prov.zig").promoNarrowBits;

const promoMentionSlot = @import("emit_js/prov.zig").promoMentionSlot;

const collectPromotableSlots = @import("emit_js/prov.zig").collectPromotableSlots;

const promoBaseSlot = @import("emit_js/dispatch.zig").promoBaseSlot;

const emitLinearInstruction = @import("emit_js/dispatch.zig").emitLinearInstruction;

const emitPcInstruction = @import("emit_js/dispatch.zig").emitPcInstruction;

const BlockRange = @import("emit_js/prov.zig").BlockRange;

const provTransfer = @import("emit_js/prov.zig").provTransfer;

const provSetEq = @import("emit_js/prov.zig").provSetEq;

const provLabelId = @import("emit_js/prov.zig").provLabelId;

/// Callee summary for base provenance: either every return carries a fresh
/// owned base from the callee body (alloc), or every return passes through
/// the same by_value/move parameter (param). Anything else is unprovable.
const RetBaseInfo = @import("emit_js/types.zig").RetBaseInfo;
const RetBaseTable = @import("emit_js/types.zig").RetBaseTable;

/// Declared return types of the program's callees (extern and defined
/// alike — both are static signatures in a verified program), keyed by
/// signature name. Lets width tracking type a direct call's destination
/// by declaration instead of dropping its value domain.
const CalleeRetTable = @import("emit_js/types.zig").CalleeRetTable;

const isAllocatorShim = @import("emit_js/shim_names.zig").isAllocatorShim;

const isJsHandleBuiltin = @import("emit_js/shim_names.zig").isJsHandleBuiltin;

// Goroutine runtime chunk for the JS target: a faithful port of
// src/runtime/sa_task_coop.zig (the cooperative scheduler the wasm
// target runs) to a single-threaded JS host. Two frame protocols
// share one scheduler: coop state-machine steps (the SA_COOP_BLOCKED
// protocol, driven by sa_coop_run_main) and plain JS frames (what
// build-js receives from the native lowering), whose blocking calls
// register the same waiter records and then pump the scheduler from
// their own frame until the wait completes. Registered limit of
// the plain track, mirroring the coop track's own v1 limits: a wait
// whose satisfaction requires an ancestor frame on the pump stack
// to advance is a loud deadlock trap, never a silent fallback.
// Emitted once per program that declares any task/chan/sync/coop
// extern (gate below); other programs pay nothing for it.
const jstask_runtime_js = @import("emit_js/runtime_task.zig").jstask_runtime_js;

// JS value-handle runtime chunk: the handle table behind the npm
// ctor/method/get binding shapes, string-out writeback, zero-copy
// TypedArray views, and the queue-drain callback pump (the JS closure
// only enqueues; SA dispatches in its own flow via sa_js_callback_poll).
// Emitted once per program that uses any of those (gate below).
// Handle encoding: gen * 2^32 + (index + 1), returned as BigInt; 0 is
// never a valid handle. Release bumps the slot generation, so a stale
// handle traps instead of silently aliasing a recycled slot's value.
const jshandle_runtime_js = @import("emit_js/runtime_handle.zig").jshandle_runtime_js;

/// Every extern name with a built-in host lowering in the emitter (as
/// opposed to a trap stub). A same-module `@export` never shadows these.
// sa2js net runtime chunk (BP): cookie engine, TLS config model,
// synchronous socket bridge (worker + SAB + Atomics.wait), netinfo.
// Emitted once per program that declares any BP net shim (gate below).
const jsnet_runtime_js = @import("emit_js/runtime_net_cookie_jar.zig").jsnet_runtime_js_cookie_jar ++ "\n" ++ @import("emit_js/runtime_net_sockets_tls.zig").jsnet_runtime_js_sockets_tls;

const isKnownShim = @import("emit_js/shim_names.zig").isKnownShim;

const isJsPolicyShim = @import("emit_js/shim_names.zig").isJsPolicyShim;

const isJsTaskShim = @import("emit_js/shim_names.zig").isJsTaskShim;

const isJsGlobalsShim = @import("emit_js/shim_names.zig").isJsGlobalsShim;

/// JS port of the sa_std global-cell registry (native implementation:
/// src/runtime/sa_globals.zig). Process-wide named cells in two
/// independent namespaces (u64 / bytes), keyed by the raw name bytes
/// (latin1-exact key strings, so arbitrary name bytes stay distinct).
/// Status codes mirror the native registry (OK=0, INVALID_ARGUMENT=1,
/// NOT_FOUND=3, TRUNCATED=9); u64 arithmetic wraps, add is a
/// read-modify-write starting from 0 on a fresh name, and every out
/// slot is zeroed before the lookup, exactly like the native exports.
/// The host is single-threaded, so the native mutex has no observable
/// effect and plain Maps are faithful. Emitted once per program that
/// declares any sa_global_* extern (gate below); other programs pay
/// nothing for it.
const globals_runtime_js = @import("emit_js/runtime_globals.zig").globals_runtime_js;

const isJsNetShim = @import("emit_js/shim_names.zig").isJsNetShim;

/// Slot of a call argument by its bare name (prefix already stripped by the
/// call parser). Used to test by_value/move argument provenance.
const provArgSlot = @import("emit_js/slots.zig").provArgSlot;

const provCallDestBase = @import("emit_js/slots.zig").provCallDestBase;

const ProvBody = @import("emit_js/prov.zig").ProvBody;

const provSolveBody = @import("emit_js/prov.zig").provSolveBody;

const provAllReturnsProven = @import("emit_js/prov.zig").provAllReturnsProven;

const emitBodyAsPcMachine = @import("emit_js/funcs.zig").emitBodyAsPcMachine;

const emitOneFunction = @import("emit_js/funcs.zig").emitOneFunction;

const jsNameKey = @import("emit_js/entry.zig").jsNameKey;

const putJsNameKey = @import("emit_js/entry.zig").putJsNameKey;

const collectReferencedJsNames = @import("emit_js/entry.zig").collectReferencedJsNames;

pub const emitJsToString = @import("emit_js/entry.zig").emitJsToString;

pub const emitJsToFile = @import("emit_js/entry.zig").emitJsToFile;


// ---------------------------------------------------------------------------
// .d.ts declaration emission (`sa build-js --emit-dts`): the JS target's
// outbound mirror of `sla convert` (.d.ts -> .sai). The declarations are
// a pure function of the verified module and mirror the JS product's
// export surface per format (census: SURFACE.md; mapping table:
// DTS_EMIT_DESIGN.md). Shapes with no JS representation (v128) fail
// loudly with UnsupportedDtsType instead of silently emitting `any`;
// the emitter never emits `any`.
// ---------------------------------------------------------------------------

const DtsAliases = @import("emit_js/entry.zig").DtsAliases;

const dtsTypeName = @import("emit_js/entry.zig").dtsTypeName;

const writeDtsReturnType = @import("emit_js/entry.zig").writeDtsReturnType;

const writeDtsDecl = @import("emit_js/entry.zig").writeDtsDecl;

const dtsNameAlloc = @import("emit_js/entry.zig").dtsNameAlloc;

pub const emitDtsToString = @import("emit_js/entry.zig").emitDtsToString;

pub const dtsPathForJsPath = @import("emit_js/entry.zig").dtsPathForJsPath;

pub const emitDtsToFile = @import("emit_js/entry.zig").emitDtsToFile;

test "js ident sanitizes names" {
    var buf: [64]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&buf);
    try jsIdent(&fbs, "hello-world.foo");
    try std.testing.expectEqualStrings("hello_world_foo", fbs.buffered());
}

test "js format parses esm and cjs" {
    try std.testing.expectEqual(JsFormat.esm, JsFormat.parse("esm").?);
    try std.testing.expectEqual(JsFormat.cjs, JsFormat.parse("cjs").?);
    try std.testing.expect(JsFormat.parse("bad") == null);
}

test "dts path replaces the js extension" {
    const a = std.testing.allocator;
    const p1 = try dtsPathForJsPath(a, "out/foo.mjs");
    defer a.free(p1);
    try std.testing.expectEqualStrings("out/foo.d.ts", p1);
    const p2 = try dtsPathForJsPath(a, "foo.cjs");
    defer a.free(p2);
    try std.testing.expectEqualStrings("foo.d.ts", p2);
    const p3 = try dtsPathForJsPath(a, "foo");
    defer a.free(p3);
    try std.testing.expectEqualStrings("foo.d.ts", p3);
}

