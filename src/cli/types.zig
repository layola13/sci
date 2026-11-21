const sio = @import("sio");
const manifest = @import("../pkg/manifest.zig");
const builtin = @import("builtin");
const referee = @import("../referee.zig");
const flattener = @import("../flattener.zig");
const std = @import("std");
const DceMode = @import("../emit_options.zig").DceMode;
const trap = @import("../common/trap.zig");
/// Shared types for the CLI (moved out of cli.zig).

pub const Command = enum {
    run,
    init,
    install,
    plugin,
    pkg,
    cache,
    build,
    build_workspace,
    build_exe,
    build_wasm,
    build_js,
    build_c,
    build_obj,
    build_lib,
    bc2sa,
    audit,
    check,
    graph,
    layout,
    fetch,
    size,
    test_cmd,
    explain,
    fix,
    skills,
    daemon,
    help,
    version,
    encode_fragment,
};

pub const ExplainEntry = struct {
    codes: []const []const u8,
    title: []const u8,
    summary: []const u8,
    details: []const []const u8,
    fix_hint: ?[]const u8 = null,
};

pub const DiagnosticsMode = enum {
    human,
    json,
};

pub const CliErrorInfo = struct {
    code: ?[]const u8,
    message: []const u8,
    hint: ?[]const u8,
};

pub const PackageTrapInfo = struct {
    kind: trap.Trap,
    message: []const u8,
    hint: ?[]const u8,
};

pub const CompileOptions = struct {
    jobs: ?usize = null,
    jobs_explicit: bool = false,
    dce: DceMode = .std,
    incremental_cache: bool = true,
    offline: bool = false,
    ci: bool = false,
    allow_unaudited_risks: bool = false,
    auto_approve_requested: bool = false,
    permission_set: ?[]const u8 = null,
    allow_env_requested: bool = false,
    allow_net_requested: bool = false,
    allow_read_requested: bool = false,
    allow_write_requested: bool = false,
    allow_run_requested: bool = false,
    package_name: ?[]const u8 = null,
    project_root: ?[]const u8 = null,
    profile: bool = false,
    mem_report: bool = false,
    mem_report_live: bool = false,
    stdin_reader: ?*std.Io.Reader = null,
    stdin_is_tty: ?bool = null,
    diagnostic_writer: ?*std.Io.Writer = null,
    sab_selected_test_names: []const []const u8 = &.{},
    sab_skip_verify: bool = false,
    /// Skip the process-global verdict-cache fast path and always run the
    /// referee, leaving the returned FlattenResult pristine. Required by
    /// consumers that re-derive everything from the flat itself (check
    /// --emit-sab): the fast path's trusted shell repurposes the flat in
    /// place (reg operands localized to slots, symbols/function sigs moved
    /// out), which the standalone SAB encode/verify cannot consume
    /// (finding D: second in-process emit-sab on an identical stream
    /// trapped with a spurious verification trap).
    skip_verdict_cache: bool = false,
    target_triple: ?[]const u8 = null,
    /// Rust-style mutability: allocations bind immutable values and writing
    /// through them requires an explicit exclusive borrow.
    default_immutable: bool = false,
    /// EXPERIMENTAL: mark LLVM fadd/fmul/fsub/fdiv with 'fast' math flags
    /// so FP reductions vectorize (matmul ~2.5x). Opt-in; changes FP semantics.
    fast_math: bool = false,
};

pub const WasmTarget = struct {
    triple: []const u8,
    no_entry: bool,
    size_bits: u16,
};

pub const LibKind = enum {
    shared,
    static,
};

pub const LibContract = struct {
    entries: []const LibContractEntry,
    /// Library stem (contract file basename without extension); drives
    /// the header name, the <stem>_api type, and the generated entries.
    stem: []const u8,
    /// Uppercased stem with non-alphanumerics folded to '_'; the macro
    /// prefix (<STEM>_API, <STEM>_ABI_VERSION, <STEM>_STATIC, ...).
    macro_prefix: []const u8,
};

pub const CompileResult = union(enum) {
    ok: CompileOk,
    trap: trap.TrapReport,
};

pub const LibContractEntry = struct {
    name: []const u8,
    params: []const LibContractParam,
    return_type: []const u8,
};

pub const CompileOk = struct {
    flat: flattener.FlattenResult,
    verified: referee.VerifyOk,
    metrics: CompileMetrics,
    /// Set by releaseFlatInstructions(): the flat.instructions storage was
    /// freed at the emit seam, so the per-item allocations it shares with
    /// verified.annotated[].base (upstream_loc.file, native_reg_names) are
    /// released from the annotated copies in deinit instead of via
    /// flat.deinit's (then empty) per-item loop.
    flat_instructions_released: bool = false,

    fn deinit(self: *CompileOk, allocator: std.mem.Allocator) void {
        if (self.flat_instructions_released) {
            // Mirrors FlattenResult.deinit's per-item frees, minus
            // package_identity (already freed at the seam). The annotated
            // base entries are shallow copies of the flat instructions, so
            // these pointers are the same allocations, freed exactly once.
            for (self.verified.annotated) |ann| {
                if (ann.base.upstream_loc) |loc| allocator.free(loc.file);
                if (ann.base.native_reg_names.len != 0) allocator.free(ann.base.native_reg_names);
            }
        }
        self.verified.deinit(allocator);
        self.flat.deinit(allocator);
        self.* = undefined;
    }

    /// Emit-seam release of the flat instruction store: after
    /// compileSource, emit consumes only verified.annotated, so the flat
    /// array (one of the two full-size instruction copies held in
    /// residency) is dead. Frees the per-item package_identity strings
    /// (flat-owned; the emit paths never read them) and the array body.
    /// Per-item allocations shared with annotated[].base
    /// (upstream_loc.file, native_reg_names) deliberately stay alive for
    /// emit; deinit releases them (see above).
    fn releaseFlatInstructions(self: *CompileOk, allocator: std.mem.Allocator) void {
        for (self.flat.instructions) |ins| {
            if (ins.package_identity) |identity| allocator.free(identity);
        }
        allocator.free(self.flat.instructions);
        self.flat.instructions = &.{};
        self.flat_instructions_released = true;
    }
};

pub const CompilePhaseMetrics = struct {
    load_ns: u64 = 0,
    setup_ns: u64 = 0,
    flatten_ns: u64 = 0,
    verify_ns: u64 = 0,
    emit_ns: ?u64 = null,
    link_ns: ?u64 = null,
    total_ns: ?u64 = null,
};

pub const CompileMemoryMetrics = struct {
    start_rss_bytes: ?u64 = null,
    after_load_rss_bytes: ?u64 = null,
    after_setup_rss_bytes: ?u64 = null,
    after_flatten_rss_bytes: ?u64 = null,
    after_verify_rss_bytes: ?u64 = null,
    after_emit_rss_bytes: ?u64 = null,
    after_link_rss_bytes: ?u64 = null,
    end_rss_bytes: ?u64 = null,
    peak_rss_bytes: ?u64 = null,
    verifier: VerifierMemoryMetrics = .{},

    fn updatePeak(self: *CompileMemoryMetrics, rss: ?u64) void {
        const value = rss orelse return;
        if (self.peak_rss_bytes == null or value > self.peak_rss_bytes.?) {
            self.peak_rss_bytes = value;
        }
    }

    fn recordStart(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.start_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterLoad(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_load_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterSetup(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_setup_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterFlatten(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_flatten_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterVerify(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_verify_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterEmit(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_emit_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterLink(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_link_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordEnd(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.end_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordVerifierStage(self: *CompileMemoryMetrics, stage: []const u8, rss: ?u64) void {
        if (std.mem.eql(u8, stage, "start")) {
            self.verifier.start_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_classify")) {
            self.verifier.after_classify_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_metadata")) {
            self.verifier.after_metadata_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_chunks")) {
            self.verifier.after_chunks_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_start")) {
            self.verifier.parallel_start_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_after_worker_allocators")) {
            self.verifier.parallel_after_worker_allocators_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_after_body")) {
            self.verifier.parallel_after_body_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_merge")) {
            self.verifier.parallel_merge_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_body")) {
            self.verifier.after_body_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_finalize")) {
            self.verifier.after_finalize_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "empty")) {
            self.verifier.empty_rss_bytes = rss;
        }
        self.updatePeak(rss);
    }
};

pub const LibContractParam = struct {
    name: []const u8,
    type_name: []const u8,
    borrowed: bool,
};

pub const VerifierMemoryMetrics = struct {
    start_rss_bytes: ?u64 = null,
    after_classify_rss_bytes: ?u64 = null,
    after_metadata_rss_bytes: ?u64 = null,
    after_chunks_rss_bytes: ?u64 = null,
    parallel_start_rss_bytes: ?u64 = null,
    parallel_after_worker_allocators_rss_bytes: ?u64 = null,
    parallel_after_body_rss_bytes: ?u64 = null,
    parallel_merge_rss_bytes: ?u64 = null,
    after_body_rss_bytes: ?u64 = null,
    after_finalize_rss_bytes: ?u64 = null,
    empty_rss_bytes: ?u64 = null,
};

pub const CompileMetrics = struct {
    compile_tokens: u64,
    instruction_count: u64,
    phases: ?CompilePhaseMetrics = null,
    memory: ?CompileMemoryMetrics = null,
    backend_ir: ?BackendIrMetrics = null,
    cache: ?BuildCacheMetrics = null,
};

pub const ProjectContext = struct {
    root_path: []const u8,
    member_root_path: []const u8,
    workspace_manifest_path: []const u8,
    member_manifest_path: []const u8,
    manifest: ?manifest.Manifest,
    workspace_manifest: ?manifest.Manifest,
    member_manifest: ?manifest.Manifest,
    lock_file: ?manifest.LockFile,
    sum_file: ?manifest.SumFile,

    fn deinit(self: *ProjectContext, allocator: std.mem.Allocator) void {
        if (self.manifest) |*m| m.deinit(allocator);
        if (self.workspace_manifest) |*m| m.deinit(allocator);
        if (self.member_manifest) |*m| m.deinit(allocator);
        if (self.lock_file) |*lock| lock.deinit(allocator);
        if (self.sum_file) |*sum| sum.deinit(allocator);
        allocator.free(self.root_path);
        allocator.free(self.member_root_path);
        allocator.free(self.workspace_manifest_path);
        allocator.free(self.member_manifest_path);
        self.* = undefined;
    }
};

pub const LibTargetFamily = enum {
    elf,
    pe,
    mach_o,
};

pub const ProjectCacheKey = struct {
    hex: [64]u8,

    fn slice(self: *const ProjectCacheKey) []const u8 {
        return self.hex[0..];
    }
};

pub fn currentRssBytes() ?u64 {
    if (builtin.os.tag != .linux) return null;

    var file = sio.openFileAbsolute("/proc/self/statm", .{}) catch return null;
    defer file.close();

    var buf: [128]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        const n = file.read(buf[len..]) catch return null;
        if (n == 0) break;
        len += n;
    }
    var it = std.mem.tokenizeAny(u8, buf[0..len], " \t\r\n");
    _ = it.next() orelse return null;
    const rss_pages_text = it.next() orelse return null;
    const rss_pages = std.fmt.parseInt(u64, rss_pages_text, 10) catch return null;
    const page_size: u64 = @intCast(std.heap.pageSize());
    return rss_pages * page_size;
}

pub const BackendIrMetrics = struct {
    functions: u64 = 0,
    blocks: u64 = 0,
    instructions: u64 = 0,
    alloca_slots: u64 = 0,
    loads: u64 = 0,
    stores: u64 = 0,
};

pub const BuildCacheMetrics = struct {
    kind: []const u8,
    hit: bool,
};

pub const BuildCacheKind = enum {
    build_exe,
    build_obj,
    build_wasm,
    build_obj_incremental,
    test_cache,

    fn dirName(self: BuildCacheKind) []const u8 {
        return switch (self) {
            .build_exe => "build-exe",
            .build_obj => "build-obj",
            .build_wasm => "build-wasm",
            .build_obj_incremental => "build-obj-incremental",
            .test_cache => "test",
        };
    }
};

pub const SabFunctionRange = struct {
    sig_index: usize,
    start: usize,
    end: usize,
};

pub fn memoryEndPrevious(memory: CompileMemoryMetrics) ?u64 {
    return memory.after_link_rss_bytes orelse memory.after_emit_rss_bytes orelse memory.after_verify_rss_bytes;
}

pub fn finishProfileMetrics(metrics: *CompileMetrics, emit_ns: ?u64, link_ns: ?u64, total_ns: ?u64) void {
    if (metrics.phases) |phases| {
        metrics.phases = .{
            .load_ns = phases.load_ns,
            .setup_ns = phases.setup_ns,
            .flatten_ns = phases.flatten_ns,
            .verify_ns = phases.verify_ns,
            .emit_ns = emit_ns,
            .link_ns = link_ns,
            .total_ns = total_ns,
        };
    }
}

pub fn printStageTiming(writer: anytype, metrics: *const CompileMetrics) void {
    const phases = metrics.phases orelse return;
    writer.print(
        "[stage-timing] load: {d:.3}ms setup: {d:.3}ms flatten: {d:.3}ms verify: {d:.3}ms emit: {d:.3}ms link: {d:.3}ms total: {d:.3}ms\n",
        .{
            @as(f64, @floatFromInt(phases.load_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(phases.setup_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(phases.flatten_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(phases.verify_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(phases.emit_ns orelse 0)) / 1_000_000.0,
            @as(f64, @floatFromInt(phases.link_ns orelse 0)) / 1_000_000.0,
            @as(f64, @floatFromInt(phases.total_ns orelse 0)) / 1_000_000.0,
        },
    ) catch {};
}
