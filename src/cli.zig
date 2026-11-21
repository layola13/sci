const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const flattener = @import("flattener.zig");
const line_classifier = @import("flattener/line_classifier.zig");
const interp = @import("interp.zig");
const build_options = @import("build_options");
const driver = @import("driver/zigcc.zig");
const emit_options = @import("emit_options.zig");
const emit_llvm_llvmc = @import("emit_llvm_llvmc.zig");
const emit_js = @import("emit_js.zig");
const emit_js_types = @import("emit_js/types.zig");
const emit_c = @import("emit_c.zig");
const bc2sa = @import("llvm2sa.zig");
const layout = @import("layout.zig");
const sab = @import("sab.zig");
const plugin_bridge = @import("plugin_bridge.zig");
const sab_fragment = @import("sab_fragment.zig");
const plugins = @import("plugins.zig");
const manifest = @import("pkg/manifest.zig");
const pkg_audit = @import("pkg/audit.zig");
const pkg_ci = @import("pkg/ci.zig");
const pkg_confirm = @import("pkg/confirm.zig");
const pkg_fetch = @import("pkg/fetch.zig");
const pkg_mirror = @import("pkg/mirror.zig");
const pkg_resolver = @import("pkg/resolver.zig");
const pkg_sum = @import("pkg/sum.zig");
const pkg_workspace = @import("pkg/workspace.zig");
const referee_call = @import("referee/call.zig");
const referee = @import("referee.zig");
const test_formatter = @import("test_formatter.zig");
const test_meta = @import("test_meta.zig");
const test_runner = @import("test_runner.zig");
const trap = @import("common/trap.zig");
const affected_tests = @import("affected_tests.zig");
const daemon_cancel = @import("daemon_cancel.zig");
const daemon_client = @import("daemon_client.zig");
const dynlib_compat = @import("dynlib_compat.zig");
const incr_verify = @import("incr_verify.zig");
const common_signature = @import("common/signature.zig");
const common_upstream = @import("common/upstream_loc.zig");

const DceMode = emit_options.DceMode;

const intermediateArtifactPath = @import("cli/build_lib.zig").intermediateArtifactPath;

const CompileOk = @import("cli/types.zig").CompileOk;

const CompileResult = @import("cli/types.zig").CompileResult;

const GraphNodeKind = @import("cli/types.zig").GraphNodeKind;

const GraphNode = @import("cli/types.zig").GraphNode;

const GraphEdgeKind = @import("cli/types.zig").GraphEdgeKind;

const GraphEdge = @import("cli/types.zig").GraphEdge;

const FunctionSizeEntry = @import("cli/types.zig").FunctionSizeEntry;

const CompilePhaseMetrics = @import("cli/types.zig").CompilePhaseMetrics;

const VerifierMemoryMetrics = @import("cli/types.zig").VerifierMemoryMetrics;

const CompileMemoryMetrics = @import("cli/types.zig").CompileMemoryMetrics;

const BackendIrMetrics = @import("cli/types.zig").BackendIrMetrics;

const CompileMetrics = @import("cli/types.zig").CompileMetrics;

const BuildCacheMetrics = @import("cli/types.zig").BuildCacheMetrics;

const computeCompileMetrics = @import("cli/compile.zig").computeCompileMetrics;

const currentRssBytes = @import("cli/types.zig").currentRssBytes;

const elapsedNs = @import("cli/compile.zig").elapsedNs;

const finishProfileMetrics = @import("cli/types.zig").finishProfileMetrics;

const stageTimingEnabled = @import("cli/compile.zig").stageTimingEnabled;

const printStageTiming = @import("cli/types.zig").printStageTiming;

const recordMetricMemoryAfterEmit = @import("cli/compile.zig").recordMetricMemoryAfterEmit;

const recordMetricMemoryAfterLink = @import("cli/compile.zig").recordMetricMemoryAfterLink;

const recordMetricMemoryEnd = @import("cli/compile.zig").recordMetricMemoryEnd;

const cacheHitMemoryMetrics = @import("cli/build_exe.zig").cacheHitMemoryMetrics;

const estimateBackendIrMetrics = @import("cli/compile.zig").estimateBackendIrMetrics;

const attachBackendIrMetrics = @import("cli/compile.zig").attachBackendIrMetrics;

const computeFunctionSizes = @import("cli/misc_cmd.zig").computeFunctionSizes;

const GraphBuildContext = @import("cli/types.zig").GraphBuildContext;

const graphNodeId = @import("cli/misc_cmd.zig").graphNodeId;

const graphNodeKindName = @import("cli/misc_cmd.zig").graphNodeKindName;

const graphEdgeKindName = @import("cli/misc_cmd.zig").graphEdgeKindName;

const ensureGraphNode = @import("cli/misc_cmd.zig").ensureGraphNode;

const appendGraphEdge = @import("cli/misc_cmd.zig").appendGraphEdge;

const collectSourceGraph = @import("cli/misc_cmd.zig").collectSourceGraph;

const buildFunctionGraph = @import("cli/misc_cmd.zig").buildFunctionGraph;

const buildCallGraph = @import("cli/misc_cmd.zig").buildCallGraph;

const writeGraphJson = @import("cli/misc_cmd.zig").writeGraphJson;

const writeGraphText = @import("cli/misc_cmd.zig").writeGraphText;

const writeSizeJson = @import("cli/misc_cmd.zig").writeSizeJson;

const writeSizeText = @import("cli/misc_cmd.zig").writeSizeText;

const CompileOptions = @import("cli/types.zig").CompileOptions;

const TestCommandOptions = @import("cli/types.zig").TestCommandOptions;

const DiagnosticsMode = @import("cli/types.zig").DiagnosticsMode;

const ExplainEntry = @import("cli/types.zig").ExplainEntry;

const FixPlanStep = @import("cli/types.zig").FixPlanStep;

const FixPlan = @import("cli/types.zig").FixPlan;

const SkillSection = @import("cli/types.zig").SkillSection;

const SaStdSurface = @import("cli/types.zig").SaStdSurface;

const SaPluginsSurface = @import("cli/types.zig").SaPluginsSurface;

const AgentSkillPaths = @import("cli/types.zig").AgentSkillPaths;

const OwnedPluginRuntimeAuthorization = @import("cli/types.zig").OwnedPluginRuntimeAuthorization;

const CliErrorInfo = @import("cli/types.zig").CliErrorInfo;

const Command = @import("cli/types.zig").Command;

pub const hasJsonFlag = @import("cli/help.zig").hasJsonFlag;

fn stripJsonFlag(allocator: std.mem.Allocator, argv: []const []const u8) ![]const []const u8 {
    var items = std.array_list.Managed([]const u8).init(allocator);
    errdefer items.deinit();

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--json")) continue;
        try items.append(arg);
    }

    return try items.toOwnedSlice();
}

const ProjectTargetKind = enum {
    native,
    wasm32,
    wasm64,
};

const ProjectTarget = struct {
    kind: ProjectTargetKind,
    name: []const u8,
    output_suffix: []const u8,
    source_suffix: []const u8,
    wasm: ?WasmTarget = null,
    size_bits: u16,
};

const AuditHit = struct {
    capability: manifest.Capability,
    callee: []const u8,
    raw_text: []const u8,
    source_line: u32,
    upstream_loc: ?common_upstream.UpstreamLoc,

    fn deinit(self: *AuditHit, allocator: std.mem.Allocator) void {
        if (self.upstream_loc) |loc| allocator.free(loc.file);
        allocator.free(self.callee);
        allocator.free(self.raw_text);
        self.* = undefined;
    }
};

const PackageAudit = struct {
    identity: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    declared_grants: []const manifest.Capability,
    hits: std.array_list.Managed(AuditHit),
    requested_caps: std.array_list.Managed(manifest.Capability),
    risk_score: u8 = 100,
    approved_hash: ?[32]u8 = null,
    source_sha_matches: bool = true,
    lock_present: bool = false,
    lock_hash_matches: bool = false,

    fn deinit(self: *PackageAudit, allocator: std.mem.Allocator) void {
        for (self.hits.items) |*hit| hit.deinit(allocator);
        self.hits.deinit();
        allocator.free(self.identity);
        allocator.free(self.ref);
        allocator.free(self.declared_grants);
        self.requested_caps.deinit();
        self.* = undefined;
    }
};

const AuditReport = struct {
    packages: std.array_list.Managed(PackageAudit),
    fn deinit(self: *AuditReport, allocator: std.mem.Allocator) void {
        for (self.packages.items) |*item| item.deinit(allocator);
        self.packages.deinit();
        self.* = undefined;
    }
};

const ProjectAuditResult = union(enum) {
    ok: AuditReport,
    trap: trap.TrapReport,
};

const TemporaryApproval = struct {
    url: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    grants: []const manifest.Capability,
};

const ProjectBuildOptions = struct {
    ci: bool = false,
    allow_unaudited_risks: bool = false,
    offline: bool = false,
    all_targets: bool = false,
    lock_only: bool = false,
    debug: bool = false,
    release_fast: bool = false,
    out_path: ?[]const u8 = null,
    jobs: ?usize = null,
};

const ProjectAuditOptions = struct {
    update_lock: bool = false,
    offline: bool = false,
    all_targets: bool = false,
    jobs: ?usize = null,
};

const ProjectBuildArtifact = struct {
    name: []const u8,
    out_path: []const u8,
    artifact_path: []const u8,
    target_name: []const u8,
    source_suffix: []const u8,
    hash_key: []const u8,

    fn deinit(self: *ProjectBuildArtifact, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.out_path);
        allocator.free(self.artifact_path);
        allocator.free(self.target_name);
        allocator.free(self.source_suffix);
        allocator.free(self.hash_key);
        self.* = undefined;
    }
};

const ProjectContext = @import("cli/types.zig").ProjectContext;

const WasmTarget = @import("cli/types.zig").WasmTarget;

const nativeSizeBits = @import("cli/compile.zig").nativeSizeBits;

const sizeBitsForTriple = @import("cli/compile.zig").sizeBitsForTriple;

const tripleIsWindows = @import("cli/compile.zig").tripleIsWindows;

fn executableSuffixForTriple(triple: ?[]const u8) []const u8 {
    return if (tripleIsWindows(triple)) ".exe" else "";
}

const boolEnv = @import("cli/compile.zig").boolEnv;

const cguSeqShardCount = @import("cli/compile.zig").cguSeqShardCount;

// LINE-PEAK50-EMIT Form 1: size-gated sequential CGU emission.
// Sequential emission cuts the 50k peak from ~466 MB to ~277 MB (box,
// SA_CGU_SEQ_SHARDS=4): the CModule + LLVM IR of four concurrent shards
// no longer coexist. But sequential costs ~30% wall time at 10k (local
// rig: 1.22 s vs 0.94 s), which would flip the 10k time leg (box margin
// only 9.5%). So sequential is the default only above this fn-count gate;
// small modules keep the parallel path. synth10k = 1111 fns, synth50k =
// 5555 fns; the threshold sits between them.
const cgu_seq_fn_threshold = @import("cli/compile.zig").cgu_seq_fn_threshold;

const cguForceParallel = @import("cli/compile.zig").cguForceParallel;

const stdinIsTty = @import("cli/package.zig").stdinIsTty;

const StdinLineReader = @import("cli/types.zig").StdinLineReader;

fn isCiMode(options: ProjectBuildOptions) bool {
    return options.ci or boolEnv("CI") or boolEnv("GITHUB_ACTIONS") or !stdinIsTty();
}

fn isProjectRootPath(path: []const u8) bool {
    return std.fs.path.basename(path).len != 0;
}

const projectRootDir = @import("cli/misc_cmd.zig").projectRootDir;

const pathJoinAlloc = @import("cli/compile.zig").pathJoinAlloc;

const projectPathExists = @import("cli/cache.zig").projectPathExists;

const readTextFileAlloc = @import("cli/cache.zig").readTextFileAlloc;

fn readManifestTextFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try sio.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, manifest.max_manifest_bytes);
}

fn projectManifestPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.mod" });
}

const projectLockPath = @import("cli/compile.zig").projectLockPath;

const projectSumPath = @import("cli/compile.zig").projectSumPath;

const projectSourcePath = @import("cli/misc_cmd.zig").projectSourcePath;

fn readManifestFile(allocator: std.mem.Allocator, path: []const u8) !manifest.Manifest {
    const source = try readManifestTextFileAlloc(allocator, path);
    defer allocator.free(source);
    return try manifest.parseManifestWithFile(allocator, source, path);
}

const readLockFile = @import("cli/compile.zig").readLockFile;

const readSumFile = @import("cli/compile.zig").readSumFile;

const loadProjectContext = @import("cli/compile.zig").loadProjectContext;

const sourceHashHex = @import("cli/cache.zig").sourceHashHex;

fn hashBytes(bytes: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(bytes);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

const hashFileHex = @import("cli/cache.zig").hashFileHex;

const hashDirFileHex = @import("cli/misc_cmd.zig").hashDirFileHex;

const hashOpenFileHex = @import("cli/cache.zig").hashOpenFileHex;

const sourceStem = @import("cli/test_cmd.zig").sourceStem;

fn projectTargetKey(allocator: std.mem.Allocator, target_name: []const u8, source_suffix: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ target_name, source_suffix });
}

fn projectTargetDisplayName(allocator: std.mem.Allocator, target_name: []const u8, source_suffix: []const u8) ![]u8 {
    if (source_suffix.len == 0) return try allocator.dupe(u8, target_name);
    return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ target_name, source_suffix });
}

fn targetTripleName(target: builtin.Target) ![]u8 {
    return try target.zigTriple(std.heap.page_allocator);
}

fn emitSumFromManifest(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest) !manifest.SumFile {
    var entries = std.array_list.Managed(manifest.SumEntry).init(allocator);
    errdefer {
        for (entries.items) |*entry| entry.deinit(allocator);
        entries.deinit();
    }

    for (manifest_file.requires) |entry| {
        try entries.append(.{
            .url = try allocator.dupe(u8, entry.url),
            .ref = try allocator.dupe(u8, entry.ref),
            .source_sha256 = entry.source_sha256,
            .depth = 0,
        });
    }

    std.sort.insertion(manifest.SumEntry, entries.items, {}, struct {
        fn lessThan(_: void, lhs: manifest.SumEntry, rhs: manifest.SumEntry) bool {
            const order = std.mem.order(u8, lhs.url, rhs.url);
            if (order != .eq) return order == .lt;
            return std.mem.order(u8, lhs.ref, rhs.ref) == .lt;
        }
    }.lessThan);

    return .{ .entries = try entries.toOwnedSlice() };
}

fn targetHashKeyForName(allocator: std.mem.Allocator, name: []const u8, source_suffix: []const u8) ![]const u8 {
    return try projectTargetKey(allocator, name, source_suffix);
}

fn computeArtifactHash(source_path: []const u8, source_bytes: []const u8, target_name: []const u8, source_suffix: []const u8, out_path: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(source_path);
    hasher.update(&[_]u8{0});
    hasher.update(source_bytes);
    hasher.update(&[_]u8{0});
    hasher.update(target_name);
    hasher.update(&[_]u8{0});
    hasher.update(source_suffix);
    hasher.update(&[_]u8{0});
    hasher.update(out_path);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

const commandName = @import("cli/help.zig").commandName;

const commandFromName = @import("cli/help.zig").commandFromName;

fn commandSupported(name: []const u8) bool {
    return commandFromName(name) != null;
}

const isHelpFlag = @import("cli/help.zig").isHelpFlag;

const commandHelpRequested = @import("cli/help.zig").commandHelpRequested;

const writeCompileOptionsHelp = @import("cli/help.zig").writeCompileOptionsHelp;

const writeBuildOptionsHelp = @import("cli/help.zig").writeBuildOptionsHelp;

const printPkgHelp = @import("cli/help.zig").printPkgHelp;

const printCacheHelp = @import("cli/help.zig").printCacheHelp;

const printPluginHelp = @import("cli/help.zig").printPluginHelp;

const printCommandHelp = @import("cli/help.zig").printCommandHelp;

const printHelpTopic = @import("cli/help.zig").printHelpTopic;

const explainEntries = @import("cli/help.zig").explainEntries;

const explainEntryForCode = @import("cli/help.zig").explainEntryForCode;

const printTrapReport = @import("cli/errors.zig").printTrapReport;

const printUsage = @import("cli/help.zig").printUsage;

const printVersion = @import("cli/help.zig").printVersion;

    // NOTE (DEF-SCI-TMPWORKDIR-BASE64-SLASH): temp-dir names use url_safe base64. Standard base64 can emit slash, which turns the name into an absolute path and fails makePath with AccessDenied.
const TmpWorkDir = @import("cli/types.zig").TmpWorkDir;

const writeFile = @import("cli/build_lib.zig").writeFile;

const forbiddenHint = @import("cli/trap_errors.zig").forbiddenHint;

const lineContains = @import("cli/trap_errors.zig").lineContains;

const writeJsonString = @import("cli/json.zig").writeJsonString;

const writeMaybeJsonString = @import("cli/json.zig").writeMaybeJsonString;

const copyContextLine = @import("cli/trap_errors.zig").copyContextLine;

fn copyBadToken(report: *trap.TrapReport, token: []const u8) void {
    report.bad_token = null;
    report.bad_token_buf = std.mem.zeroes([64]u8);
    copyTextBuf(&report.bad_token_buf, token);
}

const setFile = @import("cli/trap_errors.zig").setFile;

fn setContextFromLine(report: *trap.TrapReport, line_no: u32, text: ?[]const u8) void {
    if (text) |line| {
        copyContextLine(report, 0, line_no, line);
        report.context_len = 1;
    }
}

const setRepairAlternatives = @import("cli/trap_errors.zig").setRepairAlternatives;

const firstBadTokenForTypeLine = @import("cli/trap_errors.zig").firstBadTokenForTypeLine;

const fillContextWindow = @import("cli/trap_errors.zig").fillContextWindow;

const setLineText = @import("cli/trap_errors.zig").setLineText;

const unsupportedTypeHint = @import("cli/trap_errors.zig").unsupportedTypeHint;

const cliErrorInfo = @import("cli/errors.zig").cliErrorInfo;

const printCliError = @import("cli/errors.zig").printCliError;

const printLlvmcEmitError = @import("cli/errors.zig").printLlvmcEmitError;

const importResolutionMessage = @import("cli/trap_errors.zig").importResolutionMessage;

const importResolutionHint = @import("cli/trap_errors.zig").importResolutionHint;

const lineAt = @import("cli/text.zig").lineAt;

const sourceExcerpt = @import("cli/trap_errors.zig").sourceExcerpt;

const copyTextBuf = @import("cli/text.zig").copyTextBuf;

const bufText = @import("cli/text.zig").bufText;

const textOrBuf = @import("cli/text.zig").textOrBuf;

const reportText = @import("cli/errors.zig").reportText;

const printUpstreamLocation = @import("cli/errors.zig").printUpstreamLocation;

const printMaskState = @import("cli/errors.zig").printMaskState;

const writeMetricsJson = @import("cli/errors.zig").writeMetricsJson;

const writeOptionalJsonU64 = @import("cli/errors.zig").writeOptionalJsonU64;

const writeOptionalJsonU64Field = @import("cli/errors.zig").writeOptionalJsonU64Field;

const writeSuccessJson = @import("cli/errors.zig").writeSuccessJson;

const writeMemoryAmount = @import("cli/compile.zig").writeMemoryAmount;

const writeMemoryDelta = @import("cli/compile.zig").writeMemoryDelta;

const writeMemoryStageLine = @import("cli/errors.zig").writeMemoryStageLine;

const writeMemoryStageSample = @import("cli/compile.zig").writeMemoryStageSample;

const writeMemoryStageSampleForOptions = @import("cli/compile.zig").writeMemoryStageSampleForOptions;

const MemoryStageReporterContext = @import("cli/types.zig").MemoryStageReporterContext;

const writeVerifierMemoryStage = @import("cli/compile.zig").writeVerifierMemoryStage;

const reportVerifierMemoryStage = @import("cli/compile.zig").reportVerifierMemoryStage;

const memoryEndPrevious = @import("cli/types.zig").memoryEndPrevious;

const writeMemoryReportText = @import("cli/errors.zig").writeMemoryReportText;

const writeSuccessDiagnostics = @import("cli/errors.zig").writeSuccessDiagnostics;

const writeJsonStringArray = @import("cli/json.zig").writeJsonStringArray;

const writeExplainEntryJson = @import("cli/help.zig").writeExplainEntryJson;

const writeExplainEntryText = @import("cli/help.zig").writeExplainEntryText;

const writeFixPlanJson = @import("cli/misc_cmd.zig").writeFixPlanJson;

const writeFixPlanText = @import("cli/misc_cmd.zig").writeFixPlanText;

const writeTrapExplanation = @import("cli/help.zig").writeTrapExplanation;

const explainCommand = @import("cli/help.zig").explainCommand;

const fixPlanForCode = @import("cli/misc_cmd.zig").fixPlanForCode;

const fixCommand = @import("cli/misc_cmd.zig").fixCommand;

const writeSkillSectionText = @import("cli/skills.zig").writeSkillSectionText;

const writeSkillsJson = @import("cli/skills.zig").writeSkillsJson;

const stringSliceLessThan = @import("cli/skills.zig").stringSliceLessThan;

const freeStringArrayListItems = @import("cli/skills.zig").freeStringArrayListItems;

const normalizeSkillPathAlloc = @import("cli/skills.zig").normalizeSkillPathAlloc;

const isSaStdSurfaceFile = @import("cli/skills.zig").isSaStdSurfaceFile;

const appendStdDeclarations = @import("cli/skills.zig").appendStdDeclarations;

const collectSaStdSurface = @import("cli/skills.zig").collectSaStdSurface;

const common_official_plugins = @import("cli/skills.zig").common_official_plugins;

const isCommonOfficialPluginName = @import("cli/skills.zig").isCommonOfficialPluginName;

const dirExistsAbsolute = @import("cli/compile.zig").dirExistsAbsolute;

const dirExistsCwd = @import("cli/skills.zig").dirExistsCwd;

const officialPluginsRootFromEnv = @import("cli/skills.zig").officialPluginsRootFromEnv;

const appendJsonStringArrayToCsv = @import("cli/skills.zig").appendJsonStringArrayToCsv;

const appendJsonObjectKeysToCsv = @import("cli/skills.zig").appendJsonObjectKeysToCsv;

const appendJsonInterfaceSummary = @import("cli/skills.zig").appendJsonInterfaceSummary;

const appendPermissionSummary = @import("cli/skills.zig").appendPermissionSummary;

const pluginInterfaceFileCandidate = @import("cli/skills.zig").pluginInterfaceFileCandidate;

const appendPluginDeclarations = @import("cli/skills.zig").appendPluginDeclarations;

const appendDocSummary = @import("cli/skills.zig").appendDocSummary;

const appendOfficialPluginInfo = @import("cli/skills.zig").appendOfficialPluginInfo;

const collectOfficialSaPluginsSurface = @import("cli/skills.zig").collectOfficialSaPluginsSurface;

const writeFrontmatterField = @import("cli/skills.zig").writeFrontmatterField;

const writeMarkdownCodeList = @import("cli/skills.zig").writeMarkdownCodeList;

const writeMarkdownTextList = @import("cli/skills.zig").writeMarkdownTextList;

const writeSaAgentSkillMarkdown = @import("cli/skills.zig").writeSaAgentSkillMarkdown;

const writeSaPluginsAgentSkillMarkdown = @import("cli/skills.zig").writeSaPluginsAgentSkillMarkdown;

const writeSaAgentSkills = @import("cli/skills.zig").writeSaAgentSkills;

const skillsCommand = @import("cli/skills.zig").skillsCommand;

const daemonWrite = @import("cli/daemon.zig").daemonWrite;

const daemonWorker = @import("cli/daemon.zig").daemonWorker;


const handleDaemonConnection = @import("cli/daemon.zig").handleDaemonConnection;

const parseDaemonArgv = @import("cli/daemon.zig").parseDaemonArgv;

const freeDaemonArgv = @import("cli/daemon.zig").freeDaemonArgv;

const restrictDaemonSocket = @import("cli/daemon.zig").restrictDaemonSocket;

fn daemonCommand(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    // The persistent daemon relies on Unix-domain sockets, which are not
    // available on Windows targets (Zig 0.14.1 std.net also fails to compile
    // initUnix/connectUnixSocket for windows-gnu). Comptime branch keeps the
    // unix-only body out of Windows semantic analysis.
    if (comptime builtin.os.tag == .windows) {
        try stderr.print("daemon: not supported on Windows\n", .{});
        return 1;
    } else {
        return try daemonCommandUnix(allocator, args, stdout, stderr);
    }
}

const daemonCommandUnix = @import("cli/daemon.zig").daemonCommandUnix;

const trapFromFlattenError = @import("cli/trap_errors.zig").trapFromFlattenError;

const PackageTrapInfo = @import("cli/types.zig").PackageTrapInfo;

const trapFromPackagePreflightError = @import("cli/trap_errors.zig").trapFromPackagePreflightError;

const pathExists = @import("cli/package.zig").pathExists;

const dirExists = @import("cli/package.zig").dirExists;

const globalCacheRoot = @import("cli/package.zig").globalCacheRoot;

const resolvePackageAuditRoot = @import("cli/package.zig").resolvePackageAuditRoot;

const hashesEqual = @import("cli/package.zig").hashesEqual;

const appendCiSummaryIfConfigured = @import("cli/package.zig").appendCiSummaryIfConfigured;

const preflightCiPackage = @import("cli/package.zig").preflightCiPackage;

const preflightInteractivePackage = @import("cli/package.zig").preflightInteractivePackage;

const verifyProjectPackageState = @import("cli/package.zig").verifyProjectPackageState;

const manifestPermissionSetExists = @import("cli/package.zig").manifestPermissionSetExists;

const compileOptionsHaveAllowList = @import("cli/package.zig").compileOptionsHaveAllowList;

const verifyModeByte = @import("cli/compile.zig").verifyModeByte;

const consumeCompileOption = @import("cli/options.zig").consumeCompileOption;

const consumePackageOption = @import("cli/options.zig").consumePackageOption;

const parseDceValue = @import("cli/options.zig").parseDceValue;

const consumeDceOption = @import("cli/options.zig").consumeDceOption;

const consumePermissionSetOption = @import("cli/options.zig").consumePermissionSetOption;

const consumeAllowOption = @import("cli/options.zig").consumeAllowOption;

const parseJobsValue = @import("cli/options.zig").parseJobsValue;

const consumeJobsOption = @import("cli/options.zig").consumeJobsOption;

const consumeProfileOption = @import("cli/options.zig").consumeProfileOption;

const consumeMemReportOption = @import("cli/options.zig").consumeMemReportOption;

const ExecuteOptions = @import("cli/types.zig").ExecuteOptions;

const applyExecuteOptions = @import("cli/types.zig").applyExecuteOptions;

const newCompileOptions = @import("cli/types.zig").newCompileOptions;

const configureCompileDiagnostics = @import("cli/types.zig").configureCompileDiagnostics;

const loadSource = @import("cli/compile.zig").loadSource;

const loadSabFlat = @import("cli/compile.zig").loadSabFlat;

const collectSabTestListFast = @import("cli/test_cmd.zig").collectSabTestListFast;

const hasExplicitTestSelection = @import("cli/test_cmd.zig").hasExplicitTestSelection;

const selectedTestNamesFromList = @import("cli/test_cmd.zig").selectedTestNamesFromList;

const sabPruneDebugEnabled = @import("cli/cache.zig").sabPruneDebugEnabled;

const SabFunctionRange = @import("cli/types.zig").SabFunctionRange;

const isSabFunctionDecl = @import("cli/cache.zig").isSabFunctionDecl;

const buildSabFunctionRanges = @import("cli/cache.zig").buildSabFunctionRanges;

const putSabFunctionAlias = @import("cli/cache.zig").putSabFunctionAlias;

const buildSabFunctionSigIndex = @import("cli/cache.zig").buildSabFunctionSigIndex;

const buildSabConstIndex = @import("cli/cache.zig").buildSabConstIndex;

const markSabReachableByName = @import("cli/cache.zig").markSabReachableByName;

const sabReferenceName = @import("cli/cache.zig").sabReferenceName;

const markSabReachableVtableConstByName = @import("cli/cache.zig").markSabReachableVtableConstByName;

const markSabReachableVtableConstFromOperand = @import("cli/cache.zig").markSabReachableVtableConstFromOperand;

const freeFlatInstructionMetadata = @import("cli/cache.zig").freeFlatInstructionMetadata;

const freeFlatLocEntry = @import("cli/cache.zig").freeFlatLocEntry;

const pruneSabVtableConsts = @import("cli/cache.zig").pruneSabVtableConsts;

const collectSabSelectedReachability = @import("cli/cache.zig").collectSabSelectedReachability;

fn cloneSabFunctionSig(allocator: std.mem.Allocator, source: flattener.FunctionSig) !flattener.FunctionSig {
    const name = try allocator.dupe(u8, source.name);
    errdefer allocator.free(name);

    const params = try allocator.alloc(common_signature.ParamSpec, source.params.len);
    errdefer allocator.free(params);
    var param_initialized: usize = 0;
    errdefer for (params[0..param_initialized]) |param| allocator.free(param.name);
    for (source.params, 0..) |param, idx| {
        params[idx] = .{
            .name = try allocator.dupe(u8, param.name),
            .ty = param.ty,
            .cap = param.cap,
        };
        param_initialized += 1;
    }

    const param_ids = try allocator.dupe(u32, source.param_ids);
    errdefer allocator.free(param_ids);
    const reg_ids = try allocator.dupe(u32, source.reg_ids);
    errdefer allocator.free(reg_ids);

    var upstream_file: ?[]u8 = null;
    errdefer if (upstream_file) |file| allocator.free(file);
    if (source.upstream_file) |file| upstream_file = try allocator.dupe(u8, file);

    var upstream_loc: ?common_upstream.UpstreamLoc = null;
    errdefer if (upstream_loc) |loc| allocator.free(loc.file);
    if (source.upstream_loc) |loc| {
        upstream_loc = .{
            .file = try allocator.dupe(u8, loc.file),
            .line = loc.line,
            .col = loc.col,
        };
    }

    var llvm_name: ?[]u8 = null;
    errdefer if (llvm_name) |value| allocator.free(value);
    if (source.llvm_name) |value| llvm_name = try allocator.dupe(u8, value);

    return .{
        .id = source.id,
        .name = name,
        .params = params,
        .kind = source.kind,
        .return_cap = source.return_cap,
        .return_ty = source.return_ty,
        .return_fallible = source.return_fallible,
        .entry_inst_idx = source.entry_inst_idx,
        .is_ffi_wrapper = source.is_ffi_wrapper,
        .upstream_file = upstream_file,
        .upstream_loc = upstream_loc,
        .param_ids = param_ids,
        .reg_ids = reg_ids,
        .llvm_name = llvm_name,
        .ignored = source.ignored,
        .should_panic = source.should_panic,
        .is_variadic = source.is_variadic,
    };
}

const trustedSabVerifyOk = @import("cli/compile.zig").trustedSabVerifyOk;


const resolveProjectFromSourcePath = @import("cli/compile.zig").resolveProjectFromSourcePath;

const projectRootFromSourcePath = @import("cli/compile.zig").projectRootFromSourcePath;

const stdRootFromEnv = @import("cli/cache.zig").stdRootFromEnv;

const defaultStableImportRoots = @import("cli/compile.zig").defaultStableImportRoots;

const readProjectManifest = @import("cli/plugin_cmd.zig").readProjectManifest;

const projectRootFromCurrentDir = @import("cli/package.zig").projectRootFromCurrentDir;

const parseAllowListFragment = @import("cli/plugin_cmd.zig").parseAllowListFragment;

const appendPermissionSetStrings = @import("cli/plugin_cmd.zig").appendPermissionSetStrings;

const validateRunAllowList = @import("cli/plugin_cmd.zig").validateRunAllowList;

const findPermissionSet = @import("cli/plugin_cmd.zig").findPermissionSet;

const buildPluginRuntimeAuthorization = @import("cli/plugin_cmd.zig").buildPluginRuntimeAuthorization;

const manifestDependencies = @import("cli/compile.zig").manifestDependencies;

const freeOwnedStringSlice = @import("cli/compile.zig").freeOwnedStringSlice;

const manifestPluginImportRoots = @import("cli/compile.zig").manifestPluginImportRoots;

const compileSource = @import("cli/compile.zig").compileSource;
const test_source_tree_load_count = @import("cli/compile.zig").test_source_tree_load_count;

const collectExternalSymbolNames = @import("cli/build_exe.zig").collectExternalSymbolNames;

const appendNativePluginLinkInputs = @import("cli/build_exe.zig").appendNativePluginLinkInputs;

fn deriveOutputPath(allocator: std.mem.Allocator, source_path: []const u8, suffix: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    const stem = sourceStem(source_path);
    if (dir) |parent| {
        return try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ parent, stem, suffix });
    }
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, suffix });
}

pub fn defaultExecutableSuffix() []const u8 {
    return if (builtin.os.tag == .windows) ".exe" else "";
}

const ensureParentDir = @import("cli/compile.zig").ensureParentDir;

fn writeAllFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try sio.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn writeTextFile(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    _ = allocator;
    try writeAllFile(path, bytes);
}

const copyFileAlloc = @import("cli/cache.zig").copyFileAlloc;

const makeExecutable = @import("cli/build_exe.zig").makeExecutable;

const cacheRootPath = @import("cli/cache.zig").cacheRootPath;

const BuildCacheKind = @import("cli/types.zig").BuildCacheKind;

const CacheCleanStats = @import("cli/types.zig").CacheCleanStats;

const CacheCleanOptions = @import("cli/types.zig").CacheCleanOptions;

const ProjectCacheKey = @import("cli/types.zig").ProjectCacheKey;

const cacheBytes = @import("cli/cache.zig").cacheBytes;

const cacheU64 = @import("cli/cache.zig").cacheU64;

const cacheBool = @import("cli/cache.zig").cacheBool;

const cacheKeyNormalizedPath = @import("cli/cache.zig").cacheKeyNormalizedPath;

const cacheKeyTreePath = @import("cli/source_tree.zig").cacheKeyTreePath;

// --- std tree semantic digest -------------------------------------------
// The cache key identifies the linked sa_std runtime by a content digest
// of the std source tree — the only "std version" that is a meaning.
// Neither the archive's stat (mtime moves on byte-identical rebuilds) nor
// its bytes (not reproducible across checkouts) can serve. The digest
// covers every regular source file under the std root as (relative path,
// content) pairs in sorted order; scratch/cache directories and the
// built archive itself (a product of the tree that hermetic layouts
// place inside it) are not std semantics and are skipped.

const StdTreeDigestEntry = @import("cli/source_tree.zig").StdTreeDigestEntry;

const std_tree_digest_mutex = @import("cli/source_tree.zig").std_tree_digest_mutex;
const std_tree_digest_cache = @import("cli/source_tree.zig").std_tree_digest_cache;

const stdTreeDigestCacheMap = @import("cli/source_tree.zig").stdTreeDigestCacheMap;

const lockStdTreeDigestCache = @import("cli/source_tree.zig").lockStdTreeDigestCache;

const freeStdTreeDigestEntry = @import("cli/source_tree.zig").freeStdTreeDigestEntry;

const stdTreeScratchDir = @import("cli/source_tree.zig").stdTreeScratchDir;

const stdTreeArchiveName = @import("cli/source_tree.zig").stdTreeArchiveName;

const hashFileContentsInto = @import("cli/source_tree.zig").hashFileContentsInto;

const collectStdTreeFiles = @import("cli/source_tree.zig").collectStdTreeFiles;

const stdTreeStatLessThan = @import("cli/source_tree.zig").stdTreeStatLessThan;

const stdTreeDigest = @import("cli/source_tree.zig").stdTreeDigest;

const stdTreeFileListsEqual = @import("cli/source_tree.zig").stdTreeFileListsEqual;

const cacheCompilerVersion = @import("cli/cache.zig").cacheCompilerVersion;

const projectFileMaybeHash = @import("cli/cache.zig").projectFileMaybeHash;

const SourceTreeFileStat = @import("cli/source_tree.zig").SourceTreeFileStat;

const SourceTreeHashCacheEntry = @import("cli/source_tree.zig").SourceTreeHashCacheEntry;

const source_tree_hash_cache_mutex = @import("cli/source_tree.zig").source_tree_hash_cache_mutex;
const source_tree_hash_cache = @import("cli/source_tree.zig").source_tree_hash_cache;
const source_tree_hash_cache_tick = @import("cli/source_tree.zig").source_tree_hash_cache_tick;
const test_source_tree_hash_cache_max_entries = @import("cli/source_tree.zig").test_source_tree_hash_cache_max_entries;

const sourceTreeHashCacheMap = @import("cli/source_tree.zig").sourceTreeHashCacheMap;

const freeSourceTreeHashCacheEntry = @import("cli/source_tree.zig").freeSourceTreeHashCacheEntry;

const sourceTreeHashCacheMaxEntries = @import("cli/source_tree.zig").sourceTreeHashCacheMaxEntries;

const nextSourceTreeHashCacheTickLocked = @import("cli/source_tree.zig").nextSourceTreeHashCacheTickLocked;

const buildSourceTreeHashCacheKey = @import("cli/source_tree.zig").buildSourceTreeHashCacheKey;

const appendCacheKeyBytes = @import("cli/source_tree.zig").appendCacheKeyBytes;

const sourceTreeHashCacheHit = @import("cli/source_tree.zig").sourceTreeHashCacheHit;

const storeSourceTreeHashCacheEntry = @import("cli/source_tree.zig").storeSourceTreeHashCacheEntry;

const evictSourceTreeHashCacheIfNeeded = @import("cli/source_tree.zig").evictSourceTreeHashCacheIfNeeded;

const addSourceTreeDigestToHasher = @import("cli/source_tree.zig").addSourceTreeDigestToHasher;

const hashResolvedSourceTreeUncached = @import("cli/source_tree.zig").hashResolvedSourceTreeUncached;

const hashResolvedSourceTree = @import("cli/source_tree.zig").hashResolvedSourceTree;

const cacheBuildSemanticFlags = @import("cli/cache.zig").cacheBuildSemanticFlags;

const computeProjectBuildKey = @import("cli/compile.zig").computeProjectBuildKey;

const projectCacheDir = @import("cli/cache.zig").projectCacheDir;

const projectCacheArtifactPath = @import("cli/cache.zig").projectCacheArtifactPath;

const projectCacheRemoveKey = @import("cli/cache.zig").projectCacheRemoveKey;

const projectCacheArtifactExistsNonEmpty = @import("cli/cache.zig").projectCacheArtifactExistsNonEmpty;

const projectCacheManifestPath = @import("cli/cache.zig").projectCacheManifestPath;

const jsonGetObject = @import("cli/cache.zig").jsonGetObject;

const jsonStringEquals = @import("cli/cache.zig").jsonStringEquals;

const jsonIntEquals = @import("cli/cache.zig").jsonIntEquals;

const projectCacheArtifactMatchesManifest = @import("cli/cache.zig").projectCacheArtifactMatchesManifest;

const projectCacheManifestValid = @import("cli/cache.zig").projectCacheManifestValid;

const writeCacheArtifactManifestEntry = @import("cli/cache.zig").writeCacheArtifactManifestEntry;

const projectCacheWriteManifest = @import("cli/cache.zig").projectCacheWriteManifest;

const projectCacheHit = @import("cli/compile.zig").projectCacheHit;

const projectCacheStore = @import("cli/cache.zig").projectCacheStore;

const projectCacheTestMetadataPath = @import("cli/cache.zig").projectCacheTestMetadataPath;

const writeOptionalJsonString = @import("cli/cache.zig").writeOptionalJsonString;

const projectCacheWriteTestMetadata = @import("cli/cache.zig").projectCacheWriteTestMetadata;

const projectCacheStoreTest = @import("cli/cache.zig").projectCacheStoreTest;

// --- cache budget: bounded, reachability-ordered eviction ---------------
// Keys decide identity; this decides how much history the disk keeps.
// The two are independent by design: eviction never changes what a key
// means, only how long an unused meaning's products survive.

const projectCacheTouchEntry = @import("cli/cache.zig").projectCacheTouchEntry;

const projectCacheBudgetBytes = @import("cli/cache.zig").projectCacheBudgetBytes;

const cacheDirTreeSize = @import("cli/cache.zig").cacheDirTreeSize;

const cacheEntryLastUsedNs = @import("cli/cache.zig").cacheEntryLastUsedNs;

const CacheEvictionCandidate = @import("cli/cache.zig").CacheEvictionCandidate;

const cacheEvictionCandidateLessThan = @import("cli/cache.zig").cacheEvictionCandidateLessThan;

const enforceProjectCacheBudget = @import("cli/cache.zig").enforceProjectCacheBudget;

const jsonBool = @import("cli/cache.zig").jsonBool;

const jsonU32 = @import("cli/cache.zig").jsonU32;

const jsonStringDup = @import("cli/cache.zig").jsonStringDup;

const jsonOptionalStringDup = @import("cli/cache.zig").jsonOptionalStringDup;

const projectCacheReadTestMetadata = @import("cli/cache.zig").projectCacheReadTestMetadata;

const isHexCacheKey = @import("cli/cache.zig").isHexCacheKey;

const cacheEntryExpired = @import("cli/misc_cmd.zig").cacheEntryExpired;

const cacheFilePresentNonEmpty = @import("cli/misc_cmd.zig").cacheFilePresentNonEmpty;

const cacheDirPresent = @import("cli/misc_cmd.zig").cacheDirPresent;

const cacheEntryComplete = @import("cli/misc_cmd.zig").cacheEntryComplete;

const cacheEntryArtifactMatchesManifest = @import("cli/misc_cmd.zig").cacheEntryArtifactMatchesManifest;

const cacheEntryManifestValid = @import("cli/misc_cmd.zig").cacheEntryManifestValid;

const cleanCacheKindDir = @import("cli/misc_cmd.zig").cleanCacheKindDir;

const cleanProjectCache = @import("cli/misc_cmd.zig").cleanProjectCache;

const executeCacheCommand = @import("cli/misc_cmd.zig").executeCacheCommand;

const projectFunctionCachePath = @import("cli/cache.zig").projectFunctionCachePath;

const projectFunctionCacheManifestPath = @import("cli/cache.zig").projectFunctionCacheManifestPath;

const cacheFunctionSig = @import("cli/cache.zig").cacheFunctionSig;

const computeFunctionObjectKey = @import("cli/cache.zig").computeFunctionObjectKey;

const buildIncrementalObject = @import("cli/build_exe.zig").buildIncrementalObject;

const ensureNewFile = @import("cli/misc_cmd.zig").ensureNewFile;

const executeInit = @import("cli/misc_cmd.zig").executeInit;

const InstallArgs = @import("cli/types.zig").InstallArgs;

fn fetchManifestRequires(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest, fetch_options: pkg_fetch.FetchOptions, stdout: anytype) !void {
    for (manifest_file.requires) |entry| {
        var entry_fetch_options = fetch_options;
        entry_fetch_options.expected_source_sha256 = entry.source_sha256;
        var result = try pkg_fetch.fetchPackage(allocator, entry.url, entry.ref, entry_fetch_options);
        defer result.deinit(allocator);
        if (!hashesEqual(result.source_sha256, entry.source_sha256)) return error.UpstreamShaMismatch;
        try stdout.print("{s}\n", .{result.root});
    }
}

fn installManifestPlugins(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest, stdout: anytype) !u8 {
    for (manifest_file.plugin_requires) |entry| {
        _ = entry.abi;
        _ = entry.ref;
        const code = try plugins.installFromPath(allocator, entry.identity, stdout, .{});
        if (code != 0) return code;
    }
    return 0;
}

const parseInstallArgs = @import("cli/misc_cmd.zig").parseInstallArgs;

fn installManifestDependencies(allocator: std.mem.Allocator, options: pkg_fetch.FetchOptions, package_name: ?[]const u8, stdout: anytype) !u8 {
    var resolution = try pkg_workspace.resolveFromCurrentDir(allocator, .{ .request = package_name });
    defer resolution.deinit(allocator);

    const project_root = resolution.workspace_root;
    const project_manifest = resolution.effective_manifest orelse return 0;

    const current_dir = try sio.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);

    if (package_name == null and
        resolution.workspace_manifest != null and
        resolution.workspace_manifest.?.workspace != null and
        std.mem.eql(u8, current_dir, resolution.workspace_root))
    {
        const members = try pkg_workspace.listWorkspaceMembers(allocator, resolution.workspace_root, &resolution.workspace_manifest.?);
        defer pkg_workspace.freeWorkspaceMembers(allocator, members);

        var member_manifests = std.array_list.Managed(manifest.Manifest).init(allocator);
        defer {
            for (member_manifests.items) |*member_manifest| member_manifest.deinit(allocator);
            member_manifests.deinit();
        }

        var member_manifest_ptrs = std.array_list.Managed(*const manifest.Manifest).init(allocator);
        defer member_manifest_ptrs.deinit();

        for (members) |member| {
            const member_manifest_path = try projectManifestPath(allocator, member.member_root);
            defer allocator.free(member_manifest_path);
            const member_manifest = try readManifestFile(allocator, member_manifest_path);
            try member_manifests.append(member_manifest);
        }

        for (member_manifests.items) |*member_manifest| {
            try member_manifest_ptrs.append(member_manifest);
        }

        var aggregate_manifest = try manifest.mergeWorkspaceMemberSet(
            allocator,
            &resolution.workspace_manifest.?,
            member_manifest_ptrs.items,
        );
        defer aggregate_manifest.deinit(allocator);

        var mirror_rules = try pkg_mirror.loadProjectRules(allocator, project_root, aggregate_manifest.mirrors);
        defer mirror_rules.deinit(allocator);

        var fetch_options = options;
        fetch_options.mirror_rules = mirror_rules.rules;

        try fetchManifestRequires(allocator, &aggregate_manifest, fetch_options, stdout);
        const plugin_code = try installManifestPlugins(allocator, &aggregate_manifest, stdout);
        if (plugin_code != 0) return plugin_code;

        var update = try pkg_sum.updateProjectSum(allocator, project_root, aggregate_manifest);
        defer update.deinit(allocator);
        return 0;
    }

    var mirror_rules = try pkg_mirror.loadProjectRules(allocator, project_root, project_manifest.mirrors);
    defer mirror_rules.deinit(allocator);

    var fetch_options = options;
    fetch_options.mirror_rules = mirror_rules.rules;

    try fetchManifestRequires(allocator, &project_manifest, fetch_options, stdout);
    const plugin_code = try installManifestPlugins(allocator, &project_manifest, stdout);
    if (plugin_code != 0) return plugin_code;

    var update = try pkg_sum.updateProjectSum(allocator, project_root, project_manifest);
    defer update.deinit(allocator);

    return 0;
}

fn executeInstall(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype) !u8 {
    const parsed = try parseInstallArgs(args);
    if (parsed.identity) |identity| {
        var result = try pkg_fetch.fetchPackage(allocator, identity, parsed.ref, parsed.options);
        defer result.deinit(allocator);
        try stdout.print("{s}\n", .{result.root});
        return 0;
    }
    return try installManifestDependencies(allocator, parsed.options, parsed.package_name, stdout);
}

fn executePkgCommandFallback(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !?u8 {
    if (args.len < 3) return null;
    const sub = args[2];
    if (std.mem.eql(u8, sub, "install")) {
        return try executeInstall(allocator, args[3..], stdout);
    }
    if (std.mem.eql(u8, sub, "add")) {
        return try executePkgAdd(allocator, args[3..], stdout, stderr);
    }
    if (std.mem.eql(u8, sub, "list")) {
        return try executePkgList(allocator, args[3..], stdout, stderr);
    }
    return null;
}

/// Render one canonical `require` line for sa.mod (the same shape
/// manifest.writeManifest emits, grants clause included when present).
fn renderRequireLine(allocator: std.mem.Allocator, url: []const u8, ref: []const u8, source_sha256: [32]u8, grants: []const manifest.Capability) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;
    try writer.print("require {s} @{s} sha256:{s}", .{ url, ref, std.fmt.bytesToHex(source_sha256, .lower) });
    if (grants.len != 0) {
        try writer.writeAll(" grants [");
        for (grants, 0..) |cap, idx| {
            if (idx != 0) try writer.writeAll(", ");
            try writer.writeAll(manifest.capabilityName(cap));
        }
        try writer.writeByte(']');
    }
    return aw.toOwnedSlice();
}

/// Return the byte range [start, end) of the manifest line whose first
/// two whitespace-separated tokens are `require` and `url`, or null.
fn findRequireLineRange(text: []const u8, url: []const u8) ?struct { start: usize, end: usize } {
    var start: usize = 0;
    while (start < text.len) {
        var end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        var line = text[start..end];
        if (line.len != 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        const trimmed = std.mem.trim(u8, line, " \t");
        var tokens = std.mem.tokenizeAny(u8, trimmed, " \t");
        const first = tokens.next() orelse "";
        const second = tokens.next() orelse "";
        if (std.mem.eql(u8, first, "require") and std.mem.eql(u8, second, url)) {
            if (end < text.len) end += 1; // consume the newline with the line
            return .{ .start = start, .end = end };
        }
        start = end + 1;
    }
    return null;
}

fn executePkgAdd(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const parsed = try parseInstallArgs(args);
    const identity = parsed.identity orelse {
        try stderr.writeAll("usage: sa pkg add [options] <identity>\n");
        return 1;
    };

    var resolution = pkg_workspace.resolveFromCurrentDir(allocator, .{}) catch |err| {
        try stderr.print("pkg add: no sa.mod project found from the current directory; run `sa init` or `sa sla init` first ({s})\n", .{@errorName(err)});
        return 1;
    };
    defer resolution.deinit(allocator);

    // The dependency belongs to the manifest that governs the current
    // directory: the workspace member's sa.mod when one is selected,
    // otherwise the workspace/project root sa.mod.
    const target_path: []const u8 = if (resolution.member_manifest != null)
        resolution.member_manifest_path
    else if (resolution.workspace_manifest != null)
        resolution.workspace_manifest_path
    else {
        try stderr.writeAll("pkg add: no sa.mod project found from the current directory; run `sa init` or `sa sla init` first\n");
        return 1;
    };
    const effective = resolution.effective_manifest orelse {
        try stderr.writeAll("pkg add: no sa.mod project found from the current directory; run `sa init` or `sa sla init` first\n");
        return 1;
    };

    var mirror_rules = try pkg_mirror.loadProjectRules(allocator, resolution.workspace_root, effective.mirrors);
    defer mirror_rules.deinit(allocator);

    var fetch_options = parsed.options;
    fetch_options.mirror_rules = mirror_rules.rules;
    var result = try pkg_fetch.fetchPackage(allocator, identity, parsed.ref, fetch_options);
    defer result.deinit(allocator);

    // Edit the manifest textually so hand-written content (comments,
    // ordering, unrelated sections) survives untouched: replace the
    // existing require line for this identity, or append a new one.
    const original_text = try readManifestTextFileAlloc(allocator, target_path);
    defer allocator.free(original_text);
    var existing_manifest = try manifest.parseManifestWithFile(allocator, original_text, target_path);
    defer existing_manifest.deinit(allocator);

    var kept_grants: []const manifest.Capability = &.{};
    for (existing_manifest.requires) |entry| {
        if (std.mem.eql(u8, entry.url, identity)) {
            kept_grants = entry.grants;
            break;
        }
    }
    const new_line = try renderRequireLine(allocator, identity, parsed.ref, result.source_sha256, kept_grants);
    defer allocator.free(new_line);

    var new_text = std.array_list.Managed(u8).init(allocator);
    defer new_text.deinit();
    if (findRequireLineRange(original_text, identity)) |range| {
        try new_text.appendSlice(original_text[0..range.start]);
        try new_text.appendSlice(new_line);
        try new_text.append('\n');
        try new_text.appendSlice(original_text[range.end..]);
    } else {
        try new_text.appendSlice(original_text);
        if (new_text.items.len != 0 and new_text.items[new_text.items.len - 1] != '\n') try new_text.append('\n');
        try new_text.appendSlice(new_line);
        try new_text.append('\n');
    }

    // Never write a manifest the parser would reject, and never write
    // one that lost the entry just added.
    var check_manifest = try manifest.parseManifestWithFile(allocator, new_text.items, target_path);
    defer check_manifest.deinit(allocator);
    var recorded = false;
    for (check_manifest.requires) |entry| {
        if (std.mem.eql(u8, entry.url, identity) and std.mem.eql(u8, entry.ref, parsed.ref) and hashesEqual(entry.source_sha256, result.source_sha256)) recorded = true;
    }
    if (!recorded) return error.InvalidManifestAfterAdd;

    var file = try sio.createFileAbsolute(target_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(new_text.items);

    // Refresh the project sum from a fresh resolution so the recorded
    // lock state matches the edited manifests (same tail as install).
    var next_resolution = try pkg_workspace.resolveFromCurrentDir(allocator, .{});
    defer next_resolution.deinit(allocator);
    if (next_resolution.effective_manifest) |*next_manifest| {
        var update = try pkg_sum.updateProjectSum(allocator, next_resolution.workspace_root, next_manifest.*);
        defer update.deinit(allocator);
    }

    try stdout.print("pkg add: {s} @{s} sha256:{s}\n", .{ identity, parsed.ref, std.fmt.bytesToHex(result.source_sha256, .lower) });
    try stdout.print("recorded in {s}\n", .{target_path});
    try stdout.print("{s}\n", .{result.root});
    return 0;
}

fn executePkgList(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (args) |arg| {
        if (!isHelpFlag(arg)) return error.UnexpectedArgument;
    }
    var resolution = pkg_workspace.resolveFromCurrentDir(allocator, .{}) catch {
        try stderr.writeAll("pkg list: no sa.mod project found from the current directory\n");
        return 1;
    };
    defer resolution.deinit(allocator);
    const effective = resolution.effective_manifest orelse {
        try stderr.writeAll("pkg list: no sa.mod project found from the current directory\n");
        return 1;
    };
    for (effective.requires) |entry| {
        const line = try renderRequireLine(allocator, entry.url, entry.ref, entry.source_sha256, entry.grants);
        defer allocator.free(line);
        try stdout.print("{s}\n", .{line});
    }
    for (effective.plugin_requires) |entry| {
        try stdout.print("require_plugin {s} @{s} abi {d}\n", .{ entry.identity, entry.ref, entry.abi });
    }
    return 0;
}

const reportPluginImportDiagnostic = @import("cli/compile.zig").reportPluginImportDiagnostic;

const executePluginCommand = @import("cli/plugin_cmd.zig").executePluginCommand;

const saStdArchivePath = @import("cli/compile.zig").saStdArchivePath;

const saStdArchivePathForTarget = @import("cli/compile.zig").saStdArchivePathForTarget;

const wasmStdArchivePath = @import("cli/build_exe.zig").wasmStdArchivePath;

const rejectNpmBindsUnlessJs = @import("cli/compile.zig").rejectNpmBindsUnlessJs;

const executeRun = @import("cli/misc_cmd.zig").executeRun;

const executeBuildExe = @import("cli/build_exe.zig").executeBuildExe;

const executeBuildObj = @import("cli/build_exe.zig").executeBuildObj;

const executeBuildWasm = @import("cli/build_exe.zig").executeBuildWasm;

fn executeBuildJs(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, js_format: emit_js.JsFormat, debug: bool, emit_dts: bool, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            try ensureParentDir(out_path);
            const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
            const size_bits = sizeBitsForTriple(compile_options.target_triple);
            emit_js.emitJsToFile(allocator, owned.verified, source_path, size_bits, .{ .format = js_format, .debug_comments = debug, .dce = compile_options.dce, .emit_dts = emit_dts }, &owned.flat.def_dict.npm_binds, out_path) catch |err| {
                try stderr.print("error: JS backend emit failed: {s}", .{@errorName(err)});
                if (emit_js_types.last_js_func.len != 0) try stderr.print(" in {s}", .{emit_js_types.last_js_func});
                if (emit_js_types.last_js_inst.len != 0) try stderr.print(": {s}", .{std.mem.trim(u8, emit_js_types.last_js_inst, " \t\r\n")});
                try stderr.writeAll("\n");
                return 1;
            };
            const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
            recordMetricMemoryAfterEmit(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);
            recordMetricMemoryEnd(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
            finishProfileMetrics(&owned.metrics, emit_ns, null, if (total_start) |start| elapsedNs(start) else null);
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}

const executeBuildC = @import("cli/build_exe.zig").executeBuildC;

// ---------------------------------------------------------------------------
// build-lib: native library target (shared/static) driven by an explicit
// export contract.
//
// The contract is a .sai-style declaration file: one `@export` line per
// public function, using the same surface syntax as SA @export headers.
// It is the single source for three generated artifacts:
//   * the C header (<contract stem>.h, written next to the output),
//   * the API table translation unit (function-pointer table plus the
//     single <stem>_get_api entry and <stem>_abi_version),
//   * the linker export control (ELF version script / PE .def / Mach-O
//     exported-symbols list), which hides every non-contract symbol so
//     the artifact defaults to zero exports.
// For .sla sources the user's functions lower to module-local `sla__*`
// symbols, so build-lib also generates a forwarding unit: a root .sla
// with one SLA forwarder per contract entry (which pulls the user's
// functions into the emitted module) and an SA glue unit whose @export
// wrappers carry the plain contract names. For .sa sources the user's
// own @export definitions bind directly and no glue is generated.
// ---------------------------------------------------------------------------

const LibKind = @import("cli/types.zig").LibKind;

const LibTargetFamily = @import("cli/types.zig").LibTargetFamily;

const LibContractParam = @import("cli/types.zig").LibContractParam;

const LibContractEntry = @import("cli/types.zig").LibContractEntry;

const LibContract = @import("cli/types.zig").LibContract;

const libContractTypeValid = @import("cli/build_lib.zig").libContractTypeValid;

const libContractIdentValid = @import("cli/build_lib.zig").libContractIdentValid;

const libContractCType = @import("cli/build_lib.zig").libContractCType;

const parseLibContract = @import("cli/build_lib.zig").parseLibContract;

const writeLibCParams = @import("cli/build_lib.zig").writeLibCParams;

const generateLibHeader = @import("cli/build_lib.zig").generateLibHeader;

const generateLibApiSource = @import("cli/build_lib.zig").generateLibApiSource;

const writeLibSaParams = @import("cli/build_lib.zig").writeLibSaParams;

const writeLibArgNames = @import("cli/build_lib.zig").writeLibArgNames;

const generateLibGlueSa = @import("cli/build_lib.zig").generateLibGlueSa;

const generateLibRootSla = @import("cli/build_lib.zig").generateLibRootSla;

const generateLibVersionScript = @import("cli/build_lib.zig").generateLibVersionScript;

const generateLibDefFile = @import("cli/build_lib.zig").generateLibDefFile;

const generateLibExportedSymbolsList = @import("cli/build_lib.zig").generateLibExportedSymbolsList;

const libTargetFamily = @import("cli/build_lib.zig").libTargetFamily;

fn libSharedSuffix(family: LibTargetFamily) []const u8 {
    return switch (family) {
        .elf => ".so",
        .pe => ".dll",
        .mach_o => ".dylib",
    };
}

fn libStaticSuffix(family: LibTargetFamily) []const u8 {
    return switch (family) {
        .elf, .mach_o => ".a",
        .pe => "_static.lib",
    };
}

const libDupeZ = @import("cli/build_lib.zig").libDupeZ;

const lowerSlaUnitViaFrontend = @import("cli/build_lib.zig").lowerSlaUnitViaFrontend;

const executeBuildLib = @import("cli/build_lib.zig").executeBuildLib;

const executeLayout = @import("cli/misc_cmd.zig").executeLayout;

const fragmentParseMessage = @import("cli/encode.zig").fragmentParseMessage;

const deriveFragmentOutputPath = @import("cli/encode.zig").deriveFragmentOutputPath;

const executeEncodeFragment = @import("cli/encode.zig").executeEncodeFragment;

const executeCheck = @import("cli/check.zig").executeCheck;

const compileSourceForCheck = @import("cli/check.zig").compileSourceForCheck;

const executeGraph = @import("cli/misc_cmd.zig").executeGraph;

const executeSize = @import("cli/misc_cmd.zig").executeSize;

fn parseTarget(text: []const u8) !WasmTarget {
    if (std.mem.eql(u8, text, "wasm32")) return .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
    if (std.mem.eql(u8, text, "wasm64")) return .{ .triple = "wasm64-freestanding", .no_entry = true, .size_bits = 64 };
    return error.InvalidTarget;
}

fn parseOptimizationFlag(arg: []const u8) ?driver.Optimization {
    if (std.mem.eql(u8, arg, "--release-fast")) return .release_fast;
    if (std.mem.eql(u8, arg, "--release-small")) return .release_small;
    return null;
}

const emitOptLevel = @import("cli/build_exe.zig").emitOptLevel;

const executeTest = @import("cli/test_cmd.zig").executeTest;

const FunctionBodyHashMap = @import("cli/test_cmd.zig").FunctionBodyHashMap;

const collectFunctionBodyHashes = @import("cli/test_cmd.zig").collectFunctionBodyHashes;

const freeFunctionBodyHashes = @import("cli/test_cmd.zig").freeFunctionBodyHashes;

const normalizeFnName = @import("cli/test_cmd.zig").normalizeFnName;

const collectCallEdges = @import("cli/test_cmd.zig").collectCallEdges;

const executeTestInner = @import("cli/test_cmd.zig").executeTestInner;

pub fn executeWithWritersAndOptions(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    exec_options: ExecuteOptions,
) !u8 {
    // Language-frontend routing (sala 05_plugins/20_system_redesign):
    // when a file-consuming verb names a source file whose extension is
    // owned by an installed kind=language plugin, the frontend compiles
    // or handles it first and the builtin pipeline continues from there.
    // A bare project verb (no source file named) inside a project whose
    // sa.mod selects a language frontend routes to that frontend first;
    // see routeProjectVerb for the guardrails.
    if (argv.len >= 2) {
        if (commandFromName(argv[1])) |verb| {
            if (try routeProjectVerb(allocator, verb, argv, stdout, stderr)) |route| {
                switch (route) {
                    .handled => |code| return code,
                    .rewritten => |new_argv| {
                        defer freeRewrittenArgs(allocator, new_argv);
                        return try executeWithWritersAndOptionsImpl(allocator, new_argv, stdout, stderr, exec_options);
                    },
                }
            }
            if (try routeLanguageFrontend(allocator, verb, argv, stdout, stderr)) |route| {
                switch (route) {
                    .handled => |code| return code,
                    .rewritten => |new_argv| {
                        defer freeRewrittenArgs(allocator, new_argv);
                        return try executeWithWritersAndOptionsImpl(allocator, new_argv, stdout, stderr, exec_options);
                    },
                }
            }
        }
    }
    return try executeWithWritersAndOptionsImpl(allocator, argv, stdout, stderr, exec_options);
}

const pluginRequireNamesFrontend = @import("cli/route.zig").pluginRequireNamesFrontend;

const routeProjectVerb = @import("cli/route.zig").routeProjectVerb;

const LanguageRoute = @import("cli/types.zig").LanguageRoute;

const freeRewrittenArgs = @import("cli/route.zig").freeRewrittenArgs;

const routeLanguageFrontend = @import("cli/route.zig").routeLanguageFrontend;

fn executeWithWritersAndOptionsImpl(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    exec_options: ExecuteOptions,
) !u8 {
    const normalized_args = try stripJsonFlag(allocator, argv);
    defer allocator.free(normalized_args);

    const args = normalized_args;
    const json_mode = hasJsonFlag(argv);

    // Global flags: --help / -h / --version (checked before command dispatch)
    if (args.len >= 2) {
        if (isHelpFlag(args[1])) {
            try printUsage(stdout);
            return 0;
        }
        if (std.mem.eql(u8, args[1], "--version")) {
            try printVersion(stdout);
            return 0;
        }
    }

    if (args.len < 2) {
        try printUsage(stderr);
        return 1;
    }

    const cmd: Command = if (commandFromName(args[1])) |known| known else {
        var plugin_auth = try buildPluginRuntimeAuthorization(allocator, args);
        defer plugin_auth.deinit(allocator);
        var plugin_runtime = try plugins.Runtime.initFromEnvWithAuthorization(allocator, plugin_auth.input);
        defer plugin_runtime.deinit();
        if (try plugin_runtime.dispatchCommand(args, stdout, stderr, json_mode)) |code| return code;
        for (plugin_runtime.diagnostics.items) |diagnostic| {
            try stderr.print("note: plugin load skipped: {s}: {s}\n", .{ diagnostic.path, diagnostic.reason });
        }
        return error.UnknownCommand;
    };

    if (commandHelpRequested(cmd, args)) {
        try printCommandHelp(stdout, cmd, args[2..]);
        return 0;
    }

    switch (cmd) {
        .help => {
            return try printHelpTopic(stdout, args[2..]);
        },
        .version => {
            try printVersion(stdout);
            return 0;
        },
        .layout => {
            return try executeLayout(allocator, args[2..], stdout, stderr);
        },
        .graph => {
            return try executeGraph(allocator, args[2..], stdout, stderr, json_mode, exec_options);
        },
        .pkg => {
            if (try executePkgCommandFallback(allocator, args, stdout, stderr)) |code| return code;
            var plugin_auth = try buildPluginRuntimeAuthorization(allocator, args);
            defer plugin_auth.deinit(allocator);
            var plugin_runtime = try plugins.Runtime.initFromEnvWithAuthorization(allocator, plugin_auth.input);
            defer plugin_runtime.deinit();
            if (try plugin_runtime.dispatchCommand(args, stdout, stderr, json_mode)) |code| return code;
            return error.UnknownCommand;
        },
        .cache => return try executeCacheCommand(allocator, args[2..], stdout),
        .audit => return error.UnknownCommand,
        .check => {
            return try executeCheck(allocator, args[2..], stdout, stderr, json_mode, exec_options);
        },
        .encode_fragment => {
            return try executeEncodeFragment(allocator, args[2..], stdout, stderr, json_mode, exec_options);
        },
        .explain => return try explainCommand(stdout, args, json_mode),
        .fix => return try fixCommand(stdout, args, json_mode),
        .skills => return try skillsCommand(allocator, stdout, json_mode),
        .daemon => return try daemonCommand(allocator, args[2..], stdout, stderr),
        .init => return try executeInit(allocator, args[2..], stdout),
        .install => return try executeInstall(allocator, args[2..], stdout),
        .plugin => return try executePluginCommand(allocator, args[2..], stdout, stderr),
        .build => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .none;
            var incremental = false;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--incremental")) {
                    incremental = true;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, executableSuffixForTriple(compile_options.target_triple));
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildExe(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, optimization, incremental, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_workspace => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .none;
            var incremental = false;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--incremental")) {
                    incremental = true;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const final_source_path = try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer allocator.free(final_source_path);
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, executableSuffixForTriple(compile_options.target_triple));
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildExe(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, optimization, incremental, compile_options, stderr, if (json_mode) .json else .human);
        },
        .fetch => {
            if (args.len < 3) return error.MissingSourcePath;
            var result = try pkg_fetch.fetchPackage(allocator, args[2], "HEAD", .{});
            defer result.deinit(allocator);
            try stdout.print("{s}\n", .{result.root});
            return 0;
        },
        .size => {
            return try executeSize(allocator, args[2..], stdout, stderr, json_mode, exec_options);
        },
        .run => {
            if (args.len < 3) return error.MissingSourcePath;
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var runtime_args = std.array_list.Managed([]const u8).init(allocator);
            defer runtime_args.deinit();

            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                try runtime_args.append(args[i]);
            }
            const source = source_path orelse return error.MissingSourcePath;
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeRun(allocator, source, compile_options, runtime_args.items, stdout, stderr, if (json_mode) .json else .human);
        },
        .build_exe => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .none;
            var incremental = false;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--incremental")) {
                    incremental = true;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, executableSuffixForTriple(compile_options.target_triple));
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildExe(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, optimization, incremental, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_obj => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .none;
            var incremental = false;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--incremental")) {
                    incremental = true;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, ".o");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildObj(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, optimization, incremental, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_lib => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var contract_path: ?[]const u8 = null;
            var kind: LibKind = .shared;
            var debug = false;
            var optimization: driver.Optimization = .none;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--contract")) {
                    if (i + 1 >= args.len) {
                        try stderr.print("error: --contract requires a file path\n", .{});
                        return 1;
                    }
                    contract_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--kind")) {
                    if (i + 1 >= args.len) {
                        try stderr.print("error: --kind requires 'shared' or 'static'\n", .{});
                        return 1;
                    }
                    if (std.mem.eql(u8, args[i + 1], "shared")) {
                        kind = .shared;
                    } else if (std.mem.eql(u8, args[i + 1], "static")) {
                        kind = .static;
                    } else {
                        try stderr.print("error: --kind expects 'shared' or 'static', got '{s}'\n", .{args[i + 1]});
                        return 1;
                    }
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            if (contract_path == null) {
                try stderr.print("error: sa build-lib requires --contract <file> (the export contract)\n", .{});
                return 1;
            }
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const lib_family = libTargetFamily(compile_options);
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, switch (kind) {
                .shared => libSharedSuffix(lib_family),
                .static => libStaticSuffix(lib_family),
            });
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildLib(allocator, final_source_path, if (out_path) |p| p else owned_out, kind, contract_path.?, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_wasm => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var target: WasmTarget = .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
            var debug = false;
            var optimization: driver.Optimization = .none;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--target")) {
                    if (i + 1 >= args.len) return error.MissingTarget;
                    target = try parseTarget(args[i + 1]);
                    i += 1;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, ".wasm");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildWasm(allocator, final_source_path, if (out_path) |p| p else owned_out, target, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_js => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var js_format: emit_js.JsFormat = .esm;
            var emit_dts = false;
            var debug = false;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--emit-dts")) {
                    emit_dts = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--format")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    js_format = emit_js.JsFormat.parse(args[i + 1]) orelse return error.UnexpectedArgument;
                    i += 1;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, ".js");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildJs(allocator, final_source_path, if (out_path) |p| p else owned_out, js_format, debug, emit_dts, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_c => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var debug = false;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, ".c");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildC(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, compile_options, stderr, if (json_mode) .json else .human);
        },
        .bc2sa => {
            if (args.len < 3) return error.MissingSourcePath;
            if (args.len > 3) return error.UnexpectedArgument;
            const source_path = args[2];
            const translated = bc2sa.translateBitcodeFile(allocator, source_path) catch |err| {
                try printCliError(stderr, err, if (json_mode) .json else .human);
                return 1;
            };
            defer allocator.free(translated);
            try stdout.writeAll(translated);
            if (translated.len == 0 or translated[translated.len - 1] != '\n') try stdout.writeByte('\n');
            return 0;
        },
        .test_cmd => {
            var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer diag_forward.writer().flush() catch {};
            var compile_options = newCompileOptions(exec_options, diag_forward.writer());
            var source_path: ?[]const u8 = null;
            var include_filters = std.array_list.Managed([]const u8).init(allocator);
            defer include_filters.deinit();
            var skip_filters = std.array_list.Managed([]const u8).init(allocator);
            defer skip_filters.deinit();
            var exact = false;
            var run_ignored = test_meta.RunIgnored.normal;
            var list_tests = false;
            var compile_only = false;
            var trace_panic = false;
            var affected_flag = false;
            var test_optimization: driver.Optimization = .none;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    test_optimization = mode;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--list")) {
                    list_tests = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--compile-only")) {
                    compile_only = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--trace-panic") or std.mem.eql(u8, args[i], "--test-debug")) {
                    trace_panic = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--affected")) {
                    affected_flag = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--filter")) {
                    if (i + 1 >= args.len) return error.MissingFilterValue;
                    try include_filters.append(args[i + 1]);
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--skip")) {
                    if (i + 1 >= args.len) return error.MissingFilterValue;
                    try skip_filters.append(args[i + 1]);
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--exact")) {
                    exact = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--ignored")) {
                    run_ignored = .only;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--include-ignored")) {
                    run_ignored = .include;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const selection = test_meta.TestSelection{
                .include_filters = include_filters.items,
                .skip_filters = skip_filters.items,
                .exact = exact,
                .ignored = run_ignored,
            };
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeTest(allocator, final_source_path, compile_options, .{
                .selection = selection,
                .list = list_tests,
                .compile_only = compile_only,
                .trace_panic = trace_panic,
                .affected = affected_flag,
                .optimization = test_optimization,
            }, stdout, stderr, if (json_mode) .json else .human);
        },
    }
}

pub fn executeWithWriters(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return executeWithWritersAndOptions(allocator, argv, stdout, stderr, .{});
}

pub fn execute(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_stream = sio.getStdOut().writer(&stdout_buf);
    var stderr_buf: [8192]u8 = undefined;
    var stderr_stream = sio.getStdErr().writer(&stderr_buf);
    const code: u8 = if (try daemon_client.tryDaemonClient(allocator, argv, &stdout_stream.interface)) |c|
        c
    else
        try executeWithWriters(allocator, argv, &stdout_stream.interface, &stderr_stream.interface);
    stdout_stream.interface.flush() catch {};
    stderr_stream.interface.flush() catch {};
    return code;
}

test "trap reports print a human summary and preserve json payload" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    var report = trap.TrapReport{
        .trap = .memory_leak,
        .trap_code = trap.trapCode(.memory_leak),
        .line = 12,
        .source_line = 9,
        .source_text_buf = std.mem.zeroes([256]u8),
        .original_text_buf = std.mem.zeroes([256]u8),
        .source_text = null,
        .original_text = null,
        .register_buf = std.mem.zeroes([64]u8),
        .register = null,
        .registers = &.{},
        .expected_mask = null,
        .actual_mask = 1,
        .expected_mask_name = null,
        .actual_mask_name = "Active",
        .upstream_loc = null,
        .upstream_file_buf = std.mem.zeroes([128]u8),
        .upstream_line = 42,
        .upstream_col = 7,
        .function_buf = std.mem.zeroes([64]u8),
        .function = null,
        .is_ffi_wrapper = false,
        .message = "live registers remain at function exit",
        .hint = "insert explicit release",
    };
    const source = "result = load node+0 as i32";
    std.mem.copyForwards(u8, report.source_text_buf[0..source.len], source);
    const register = "r1";
    std.mem.copyForwards(u8, report.register_buf[0..register.len], register);
    const upstream_file = "main.rs";
    std.mem.copyForwards(u8, report.upstream_file_buf[0..upstream_file.len], upstream_file);
    const function = "@main() -> i32:";
    std.mem.copyForwards(u8, report.function_buf[0..function.len], function);
    try printTrapReport(&aw.writer, report, .human);
    const output = aw.written();

    try std.testing.expect(std.mem.indexOf(u8, output, "error[MemoryLeak]: live registers remain at function exit") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  in function @main() -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  upstream main.rs:42:7") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  line 9 (expanded 12): result = load node+0 as i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  register: r1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  state: Active") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  help: insert explicit release") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"trap\":\"MemoryLeak\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"function\":\"@main() -> i32:\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"register\":\"r1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"hint\":\"insert explicit release\"") != null);
}

test "cli error printing is detailed and json capable" {
    var haw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer haw.deinit();
    try printCliError(&haw.writer, error.MissingSourcePath, .human);
    try std.testing.expect(std.mem.indexOf(u8, haw.written(), "error[SA-CLI-001]: missing required positional argument") != null);
    try std.testing.expect(std.mem.indexOf(u8, haw.written(), "help: pass the source file, project path, or required operand after the command") != null);

    var jaw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer jaw.deinit();
    try printCliError(&jaw.writer, error.InvalidTarget, .json);
    try std.testing.expect(std.mem.indexOf(u8, jaw.written(), "\"status\":\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jaw.written(), "\"code\":\"SA-CLI-006\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jaw.written(), "\"name\":\"InvalidTarget\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jaw.written(), "\"message\":\"invalid target\"") != null);
}

test "build-workspace command is recognized in help" {
    var law: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer law.deinit();

    try printUsage(&law.writer);
    try std.testing.expect(std.mem.indexOf(u8, law.written(), "build-workspace") != null);

    law.clearRetainingCapacity();
    try printCommandHelp(&law.writer, .build_workspace, &.{});
    try std.testing.expect(std.mem.indexOf(u8, law.written(), "usage: sa build-workspace [options]") != null);
}

test "source tree hash cache reuses mtime size digest without reloading unchanged files" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tdir.makePath("sa_std/core");

    {
        var file = try tdir.createFile("main.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/cache_probe.sai"
            \\@main() -> i32:
            \\return dep_value
            \\
        );
    }
    {
        var file = try tdir.createFile("sa_std/core/cache_probe.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def dep_value = 7\n");
    }

    const project_root = try sio.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try sio.cwd().realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);

    test_source_tree_load_count = 0;
    var first_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var first_digest: [32]u8 = undefined;
    first_hasher.final(&first_digest);
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);

    const resolve_ctx = flattener.ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };
    var warmed_import = try flattener.readImportSourceFile(std.testing.allocator, ".", "sa_std/core/cache_probe.sai", resolve_ctx);
    defer warmed_import.deinit(std.testing.allocator);
    try std.testing.expect(warmed_import.owned_source == null);

    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var second_digest: [32]u8 = undefined;
    second_hasher.final(&second_digest);
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);
    try std.testing.expectEqualSlices(u8, first_digest[0..], second_digest[0..]);

    {
        var file = try tdir.createFile("sa_std/core/cache_probe.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def dep_value = 777\n");
    }

    var third_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &third_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var third_digest: [32]u8 = undefined;
    third_hasher.final(&third_digest);
    try std.testing.expect(test_source_tree_load_count > 1);
    try std.testing.expect(!std.mem.eql(u8, first_digest[0..], third_digest[0..]));
}

test "source tree hash missing import returns PackageNotResolved without ownership errors" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tdir.makePath("sa_std/core");
    {
        var file = try tdir.createFile("main.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "missing.sa"
            \\@main() -> i32:
            \\return 0
            \\
        );
    }

    const project_root = try sio.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try sio.cwd().realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try std.testing.expectError(
        error.PackageNotResolved,
        hashResolvedSourceTree(std.testing.allocator, &hasher, &.{}, &.{}, project_root, std_root, false, "main.sa"),
    );
}

test "source tree hash cache LRU is opt-in" {
    const previous_limit = test_source_tree_hash_cache_max_entries;
    test_source_tree_hash_cache_max_entries = 1;
    defer test_source_tree_hash_cache_max_entries = previous_limit;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    {
        var file = try tdir.createFile("a.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@main() -> i32:
            \\return 1
            \\
        );
    }
    {
        var file = try tdir.createFile("b.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@main() -> i32:
            \\return 2
            \\
        );
    }

    const project_root = try sio.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);

    test_source_tree_load_count = 0;
    var first_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_hasher, &.{}, &.{}, project_root, project_root, false, "a.sa");
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);

    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hasher, &.{}, &.{}, project_root, project_root, false, "b.sa");
    try std.testing.expectEqual(@as(usize, 2), test_source_tree_load_count);

    var second_hit_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hit_hasher, &.{}, &.{}, project_root, project_root, false, "b.sa");
    try std.testing.expectEqual(@as(usize, 2), test_source_tree_load_count);

    var first_again_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_again_hasher, &.{}, &.{}, project_root, project_root, false, "a.sa");
    try std.testing.expectEqual(@as(usize, 3), test_source_tree_load_count);
}

test "std tree digest depends on content, not on location" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    defer original_cwd.setAsCwd() catch {};

    // Two std trees with identical content at different locations must
    // digest identically; editing content must change the digest;
    // reverting the edit must restore it; scratch dirs are invisible.
    var digests: [2][32]u8 = undefined;
    for (0..2) |i| {
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var tdir: sio.Dir = .{ .inner = tmp.dir };
        try tdir.setAsCwd();
        try tdir.makePath("sa_std/core");
        {
            var file = try tdir.createFile("sa_std/core/probe.sa", .{ .truncate = true });
            defer file.close();
            try file.writeAll("#def probe_value = 7\n");
        }
        {
            var file = try tdir.createFile("sa_std/top.sai", .{ .truncate = true });
            defer file.close();
            try file.writeAll("#def top_value = 1\n");
        }
        const digest = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
        digests[i] = digest;

        if (i == 0) {
            try tdir.makePath("sa_std/.sla-cache");
            {
                var file = try tdir.createFile("sa_std/.sla-cache/residue", .{ .truncate = true });
                defer file.close();
                try file.writeAll("residue\n");
            }
            const with_residue = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
            try std.testing.expectEqualSlices(u8, digest[0..], with_residue[0..]);

            // The built archive inside the tree is a product, not a
            // source: its presence must not move the digest either.
            {
                var file = try tdir.createFile("sa_std/libsa_std.a", .{ .truncate = true });
                defer file.close();
                try file.writeAll("not a real archive\n");
            }
            const with_archive = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
            try std.testing.expectEqualSlices(u8, digest[0..], with_archive[0..]);

            {
                var file = try tdir.createFile("sa_std/core/probe.sa", .{ .truncate = true });
                defer file.close();
                try file.writeAll("#def probe_value = 8\n");
            }
            const edited = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
            try std.testing.expect(!std.mem.eql(u8, digest[0..], edited[0..]));

            {
                var file = try tdir.createFile("sa_std/core/probe.sa", .{ .truncate = true });
                defer file.close();
                try file.writeAll("#def probe_value = 7\n");
            }
            const reverted = (try stdTreeDigest(std.testing.allocator, "sa_std")).?;
            try std.testing.expectEqualSlices(u8, digest[0..], reverted[0..]);
        }
    }
    try std.testing.expectEqualSlices(u8, digests[0][0..], digests[1][0..]);
}

test "cache key paths are project-relative, never checkout-absolute" {
    const allocator = std.testing.allocator;
    const root = "/home/tester/checkout";
    const inside = try cacheKeyNormalizedPath(allocator, root, "/home/tester/checkout/src/main.sa");
    defer allocator.free(inside);
    try std.testing.expectEqualStrings("src/main.sa", inside);
    // A sibling whose path merely shares the root as a string prefix is
    // not inside the project and must stay exact.
    const sibling_prefix = try cacheKeyNormalizedPath(allocator, root, "/home/tester/checkout2/main.sa");
    defer allocator.free(sibling_prefix);
    try std.testing.expectEqualStrings("/home/tester/checkout2/main.sa", sibling_prefix);
    const relative = try cacheKeyNormalizedPath(allocator, root, "src/main.sa");
    defer allocator.free(relative);
    try std.testing.expectEqualStrings("src/main.sa", relative);
}

test "cache key tree paths tag project and std roots" {
    const allocator = std.testing.allocator;
    const proj = try cacheKeyTreePath(allocator, "/p/work/src/a.sa", "/p/work", "/p/std");
    defer allocator.free(proj);
    try std.testing.expectEqualStrings("proj/src/a.sa", proj);
    const std_file = try cacheKeyTreePath(allocator, "/p/std/core/c.sa", "/p/work", "/p/std");
    defer allocator.free(std_file);
    try std.testing.expectEqualStrings("std/core/c.sa", std_file);
    const outside = try cacheKeyTreePath(allocator, "/q/other.sa", "/p/work", "/p/std");
    defer allocator.free(outside);
    try std.testing.expectEqualStrings("/q/other.sa", outside);
}

test "fast-math is a separate build cache dimension" {
    var off = std.crypto.hash.sha2.Sha256.init(.{});
    var on = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBuildSemanticFlags(&off, false, .release_fast, false, .std, false, false);
    cacheBuildSemanticFlags(&on, false, .release_fast, false, .std, false, true);
    var off_digest: [32]u8 = undefined;
    var on_digest: [32]u8 = undefined;
    off.final(&off_digest);
    on.final(&on_digest);
    try std.testing.expect(!std.mem.eql(u8, &off_digest, &on_digest));
    // The flag must not collapse with a different mode either: the default
    // artifact may never satisfy a --fast-math request once cached.
    var other = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBuildSemanticFlags(&other, false, .release_fast, false, .std, false, false);
    var other_digest: [32]u8 = undefined;
    other.final(&other_digest);
    try std.testing.expectEqualSlices(u8, &off_digest, &other_digest);
}

test "optimization level is a separate build cache dimension" {
    // A plain build (.none, O0) and a --release-small build
    // (.release_small, O1) emit different binaries, so their
    // cache keys must differ too. The previous form folded
    // only `optimization == .release_fast`, which collapsed
    // .none and .release_small to the same key and let a
    // cached plain binary silently satisfy a --release-small
    // build in the same directory.
    var none_h = std.crypto.hash.sha2.Sha256.init(.{});
    var small_h = std.crypto.hash.sha2.Sha256.init(.{});
    var fast_h = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBuildSemanticFlags(&none_h, false, .none, false, .std, false, false);
    cacheBuildSemanticFlags(&small_h, false, .release_small, false, .std, false, false);
    cacheBuildSemanticFlags(&fast_h, false, .release_fast, false, .std, false, false);
    var none_digest: [32]u8 = undefined;
    var small_digest: [32]u8 = undefined;
    var fast_digest: [32]u8 = undefined;
    none_h.final(&none_digest);
    small_h.final(&small_digest);
    fast_h.final(&fast_digest);
    try std.testing.expect(!std.mem.eql(u8, &none_digest, &small_digest));
    try std.testing.expect(!std.mem.eql(u8, &none_digest, &fast_digest));
    try std.testing.expect(!std.mem.eql(u8, &small_digest, &fast_digest));
    // Identical inputs still key identically.
    var again_h = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBuildSemanticFlags(&again_h, false, .release_small, false, .std, false, false);
    var again_digest: [32]u8 = undefined;
    again_h.final(&again_digest);
    try std.testing.expectEqualSlices(u8, &small_digest, &again_digest);
}

test "flatten error mapping keeps import resolution and unsupported type hints specific" {
    const import_source =
        \\@import "missing.sa"
        \\@main() -> i32:
        \\    return 0
    ;
    const import_report = trapFromFlattenError("/tmp/import.sa", import_source, error.PackageNotResolved, 1);
    try std.testing.expectEqual(trap.Trap.import_resolution_failed, import_report.trap);
    try std.testing.expectEqual(@as(u32, 1050), import_report.trap_code.?);
    try std.testing.expectEqualStrings("/tmp/import.sa", import_report.file.?);
    try std.testing.expectEqualStrings("import path could not be resolved", import_report.message);
    try std.testing.expectEqualStrings("check the import path, package identity, local vendor tree, and package cache", import_report.hint.?);
    try std.testing.expectEqualStrings("pin-import", import_report.repair_action.?);

    const type_source =
        \\@test "probe":
        \\    point = call @support_make_point(10, 20)
    ;
    const type_report = trapFromFlattenError("/tmp/type.sa", type_source, error.UnsupportedType, 2);
    try std.testing.expectEqual(trap.Trap.unsupported_type, type_report.trap);
    try std.testing.expectEqualStrings("/tmp/type.sa", type_report.file.?);
    try std.testing.expectEqualStrings("unsupported type annotation during flattening", type_report.message);
    try std.testing.expectEqualStrings("inspect the callee declaration referenced by this call site; the unsupported annotation is usually in the imported signature", type_report.hint.?);
}

test "duplicate definition trap gets a repair hint" {
    const source =
        \\#def X = 1
        \\#def X = 2
    ;
    const report = trapFromFlattenError("/tmp/dup.sa", source, error.DuplicateDef, 2);
    try std.testing.expectEqual(trap.Trap.duplicate_def, report.trap);
    try std.testing.expectEqualStrings("/tmp/dup.sa", report.file.?);
    try std.testing.expectEqualStrings("rename-def", report.repair_action.?);
    try std.testing.expectEqualStrings("change one of the conflicting names or namespace the symbol", report.repair_hint.?);
    try std.testing.expectEqualStrings("high", report.repair_confidence.?);
}

test "compileSource accepts true SAB without text flattener" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };
    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const reg_ids = [_]u32{1};
    const fsig = @import("common/signature.zig").FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .reg_ids = reg_ids[0..],
    };
    var decl = @import("common/instruction.zig").makeInstruction(.func_decl, 1, 0, null, "");
    decl.operands[0] = .{ .symbol = 0 };
    decl.operands[1] = .{ .func = 0 };
    var assign = @import("common/instruction.zig").makeInstruction(.assign, 2, 1, null, "");
    assign.operands[0] = .{ .reg = 1 };
    assign.operands[1] = .{ .imm_i64 = 7 };
    var ret = @import("common/instruction.zig").makeInstruction(.return_, 3, 2, null, "");
    ret.operands[0] = .{ .reg = 1 };

    const bytes = try sab.encodeProgram(std.testing.allocator, &.{ "main", "value" }, &.{fsig}, &.{ decl, assign, ret });
    defer std.testing.allocator.free(bytes);
    try tdir.writeFile(.{ .sub_path = "main.sab", .data = bytes });

    var compiled = try compileSource(std.testing.allocator, "main.sab", .{});
    switch (compiled) {
        .ok => |*ok| {
            defer ok.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), ok.verified.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "check --emit-sab roundtrips through compileSource without text fallback" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };
    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    // Write a minimal .sa program, compile it, encode to SAB via the same
    // plugin_bridge.encodeSabFromFlat that `check --emit-sab` uses, then
    // reload the .sab and verify the decoded program matches. The SAB path
    // must be standalone: a corrupt .sab must fail loudly, never silently
    // fall back to text.
    const sa_source =
        \\@main():
        \\L_ENTRY:
        \\    x = add 40, 2
        \\    return x
    ;
    try tdir.writeFile(.{ .sub_path = "rt.sa", .data = sa_source });

    var compiled_sa = try compileSource(std.testing.allocator, "rt.sa", .{});
    var ok_sa = switch (compiled_sa) {
        .ok => |*ok| ok,
        .trap => return error.TestUnexpectedResult,
    };
    defer ok_sa.deinit(std.testing.allocator);

    const sab_bytes = try plugin_bridge.encodeSabFromFlat(std.testing.allocator, &ok_sa.flat, false);
    defer std.testing.allocator.free(sab_bytes);
    // SAB magic "SAB\x00", version 4.0.
    try std.testing.expect(sab_bytes.len > 6);
    try std.testing.expectEqualStrings("SAB\x00", sab_bytes[0..4]);
    try std.testing.expectEqual(@as(u8, 4), sab_bytes[4]);
    try tdir.writeFile(.{ .sub_path = "rt.sab", .data = sab_bytes });

    var compiled_sab = try compileSource(std.testing.allocator, "rt.sab", .{});
    switch (compiled_sab) {
        .ok => |*ok| {
            defer ok.deinit(std.testing.allocator);
            try std.testing.expectEqual(ok_sa.flat.instructions.len, ok.flat.instructions.len);
            try std.testing.expectEqual(ok_sa.flat.symbols.names.items.len, ok.flat.symbols.names.items.len);
        },
        .trap => return error.TestUnexpectedResult,
    }

    // Corrupt SAB must fail with a SAB-specific error, not fall back to text.
    try tdir.writeFile(.{ .sub_path = "bad.sab", .data = sab_bytes[0..10] });
    try std.testing.expectError(error.TruncatedSab, compileSource(std.testing.allocator, "bad.sab", .{}));
    try tdir.writeFile(.{ .sub_path = "fake.sab", .data = "this is not a sab binary" });
    try std.testing.expectError(error.InvalidSabMagic, compileSource(std.testing.allocator, "fake.sab", .{}));
}

test "TmpWorkDir.init generates url-safe temp-dir names (DEF-SCI-TMPWORKDIR-BASE64-SLASH)" {
    // Standard base64 can emit slash as its first character (1/64 per call),
    // turning the temp-dir name into an absolute path: makePath then tries
    // to create it under the filesystem root and fails with AccessDenied.
    // url_safe emits dash/underscore instead of plus/slash. A
    // standard-base64 name fails this test with probability 1-(62/64)^16
    // per sample (any plus/slash in 16 chars), so 512 samples fail it
    // with probability 1-(62/64)^8192, i.e. for all practical purposes
    // certainly -- far more sensitive than the 1/64 first-char defect.
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        var tmp = try TmpWorkDir.init();
        try std.testing.expectEqual(@as(usize, 16), tmp.sub_path.len);
        try std.testing.expect(std.mem.indexOfAny(u8, &tmp.sub_path, "/+") == null);
        tmp.cleanup();
    }
}
