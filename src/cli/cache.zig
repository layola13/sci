const std = @import("std");
const SabFunctionRange = @import("types.zig").SabFunctionRange;
const flattener = @import("../flattener.zig");
const pathJoinAlloc = @import("compile.zig").pathJoinAlloc;
const ProjectContext = @import("types.zig").ProjectContext;
const BuildCacheKind = @import("types.zig").BuildCacheKind;
const manifest = @import("../pkg/manifest.zig");
const build_options = @import("build_options");
const referee_call = @import("../referee/call.zig");
const sio = @import("sio");
const builtin = @import("builtin");
const WasmTarget = @import("types.zig").WasmTarget;
const ProjectCacheKey = @import("types.zig").ProjectCacheKey;
const common_upstream = @import("../common/upstream_loc.zig");
const DceMode = @import("../emit_options.zig").DceMode;
const ensureParentDir = @import("compile.zig").ensureParentDir;
const referee = @import("../referee.zig");
const writeJsonString = @import("json.zig").writeJsonString;
const stdTreeDigest = @import("source_tree.zig").stdTreeDigest;
const pkg_resolver = @import("../pkg/resolver.zig");
const freeOwnedStringSlice = @import("compile.zig").freeOwnedStringSlice;
const manifestDependencies = @import("compile.zig").manifestDependencies;
const manifestPluginImportRoots = @import("compile.zig").manifestPluginImportRoots;
const hashResolvedSourceTree = @import("source_tree.zig").hashResolvedSourceTree;
const test_meta = @import("../test_meta.zig");

pub fn pruneSabFlatToSelectedTests(allocator: std.mem.Allocator, flat: *flattener.FlattenResult, selected_test_names: []const []const u8) !void {
    if (selected_test_names.len == 0 or flat.function_sigs.len == 0 or flat.instructions.len == 0) return;
    const original_function_count = flat.function_sigs.len;
    const original_test_count = flat.test_sigs.len;
    const original_instruction_count = flat.instructions.len;
    const original_const_count = flat.const_decls.len;

    const ranges = try buildSabFunctionRanges(allocator, flat.instructions);
    defer allocator.free(ranges);
    if (ranges.len == 0) return;

    var sig_index_by_name = try buildSabFunctionSigIndex(allocator, flat.function_sigs);
    defer sig_index_by_name.deinit();

    var const_index_by_name = try buildSabConstIndex(allocator, flat.const_decls);
    defer const_index_by_name.deinit();

    var reachable_vtable_consts = std.AutoHashMap(usize, void).init(allocator);
    defer reachable_vtable_consts.deinit();

    var reachable = try collectSabSelectedReachability(allocator, flat, ranges, &sig_index_by_name, &const_index_by_name, selected_test_names, &reachable_vtable_consts);
    defer reachable.deinit();
    if (reachable.count() == 0) return;

    var kept_sigs = std.array_list.Managed(flattener.FunctionSig).init(allocator);
    errdefer kept_sigs.deinit();
    var kept_test_sigs = std.array_list.Managed(flattener.FunctionSig).init(allocator);
    errdefer kept_test_sigs.deinit();
    var kept_instructions = std.array_list.Managed(flattener.Instruction).init(allocator);
    errdefer kept_instructions.deinit();
    var kept_loc_table = std.array_list.Managed(?common_upstream.UpstreamLoc).init(allocator);
    errdefer kept_loc_table.deinit();

    var keep_ranges = try allocator.alloc(bool, ranges.len);
    defer allocator.free(keep_ranges);
    @memset(keep_ranges, false);
    for (ranges, 0..) |range, range_idx| {
        if (range.sig_index >= flat.function_sigs.len) continue;
        if (!reachable.contains(range.sig_index)) continue;
        keep_ranges[range_idx] = true;

        const function_sig = flat.function_sigs[range.sig_index];
        try kept_sigs.append(function_sig);
        if (function_sig.kind == .test_func) try kept_test_sigs.append(function_sig);
        try kept_instructions.appendSlice(flat.instructions[range.start..range.end]);
        try kept_loc_table.appendSlice(flat.loc_table[range.start..range.end]);
    }
    if (kept_sigs.items.len == 0) return;

    const new_function_sigs = try kept_sigs.toOwnedSlice();
    errdefer allocator.free(new_function_sigs);
    const new_test_sigs = try kept_test_sigs.toOwnedSlice();
    errdefer allocator.free(new_test_sigs);
    const new_instructions = try kept_instructions.toOwnedSlice();
    errdefer allocator.free(new_instructions);
    const new_loc_table = try kept_loc_table.toOwnedSlice();
    errdefer allocator.free(new_loc_table);

    try pruneSabVtableConsts(allocator, flat, &reachable_vtable_consts);

    var range_index: usize = 0;
    var instruction_index: usize = 0;
    while (instruction_index < flat.instructions.len) {
        if (range_index < ranges.len and instruction_index == ranges[range_index].start) {
            const range = ranges[range_index];
            if (!keep_ranges[range_index]) {
                for (flat.instructions[range.start..range.end]) |item| freeFlatInstructionMetadata(allocator, item);
                for (flat.loc_table[range.start..range.end]) |entry| freeFlatLocEntry(allocator, entry);
            }
            instruction_index = range.end;
            range_index += 1;
            continue;
        }
        freeFlatInstructionMetadata(allocator, flat.instructions[instruction_index]);
        freeFlatLocEntry(allocator, flat.loc_table[instruction_index]);
        instruction_index += 1;
    }

    var sig_keep = try allocator.alloc(bool, flat.function_sigs.len);
    defer allocator.free(sig_keep);
    @memset(sig_keep, false);
    for (ranges, 0..) |range, range_idx| {
        if (range.sig_index < sig_keep.len and keep_ranges[range_idx]) sig_keep[range.sig_index] = true;
    }
    for (flat.function_sigs, 0..) |*function_sig, sig_index| {
        if (!sig_keep[sig_index]) function_sig.deinit(allocator);
    }

    allocator.free(flat.function_sigs);
    allocator.free(flat.test_sigs);
    allocator.free(flat.instructions);
    allocator.free(flat.loc_table);

    flat.function_sigs = new_function_sigs;
    flat.test_sigs = new_test_sigs;
    flat.instructions = new_instructions;
    flat.loc_table = new_loc_table;

    if (sabPruneDebugEnabled(allocator)) {
        std.debug.print(
            "sab prune: funcs {d}->{d}, tests {d}->{d}, inst {d}->{d}, consts {d}->{d}, vtables_kept {d}\n",
            .{
                original_function_count,
                flat.function_sigs.len,
                original_test_count,
                flat.test_sigs.len,
                original_instruction_count,
                flat.instructions.len,
                original_const_count,
                flat.const_decls.len,
                reachable_vtable_consts.count(),
            },
        );
    }
}

pub fn buildSabFunctionRanges(allocator: std.mem.Allocator, instructions: []const flattener.Instruction) ![]SabFunctionRange {
    var ranges = std.array_list.Managed(SabFunctionRange).init(allocator);
    errdefer ranges.deinit();

    var current_start: ?usize = null;
    var current_sig_index: usize = 0;
    var next_sig_index: usize = 0;
    for (instructions, 0..) |item, idx| {
        if (!isSabFunctionDecl(item.kind)) continue;
        if (current_start) |start| {
            try ranges.append(.{
                .sig_index = current_sig_index,
                .start = start,
                .end = idx,
            });
        }
        current_start = idx;
        current_sig_index = next_sig_index;
        next_sig_index += 1;
    }
    if (current_start) |start| {
        try ranges.append(.{
            .sig_index = current_sig_index,
            .start = start,
            .end = instructions.len,
        });
    }
    return try ranges.toOwnedSlice();
}

pub fn buildSabFunctionSigIndex(allocator: std.mem.Allocator, function_sigs: []const flattener.FunctionSig) !std.StringHashMap(usize) {
    var index = std.StringHashMap(usize).init(allocator);
    errdefer index.deinit();
    const max_aliases = std.math.mul(usize, function_sigs.len, 2) catch function_sigs.len;
    try index.ensureTotalCapacity(@intCast(max_aliases));
    for (function_sigs, 0..) |function_sig, sig_index| {
        try putSabFunctionAlias(&index, function_sig.name, sig_index);
        if (function_sig.llvm_name) |llvm_name| try putSabFunctionAlias(&index, llvm_name, sig_index);
    }
    return index;
}

pub fn isSabFunctionDecl(kind: flattener.InstKind) bool {
    return switch (kind) {
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => true,
        else => false,
    };
}

pub fn projectLockPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.lock" });
}

pub fn computeProjectBuildKey(
    allocator: std.mem.Allocator,
    project_context: *const ProjectContext,
    project_root: []const u8,
    source_path: []const u8,
    target_name: []const u8,
    source_suffix: []const u8,
    kind: BuildCacheKind,
    debug: bool,
    release_fast: bool,
    incremental: bool,
    wasm: ?WasmTarget,
    hash_source_tree: bool,
    offline: bool,
    dce: DceMode,
    default_immutable: bool,
    fast_math: bool,
) !ProjectCacheKey {
    const std_root = try stdRootFromEnv(allocator);
    defer allocator.free(std_root);

    // Cache keys are semantic identities (cache-dedup P3): they are built
    // only from what the build means — source contents, compiler version,
    // flags, the std tree's content digest — never from where anything
    // happens to live on disk. The checkout path of the project, the
    // absolute spelling of the source path, and file timestamps of build
    // products must not appear here, or the same meaning keys differently
    // in every tree and sharing is impossible by construction. The domain
    // literal carries a generation marker so entries minted by the old
    // location-based formula can never be mistaken for semantic ones.
    const project_root_real = sio.cwd().realpathAlloc(allocator, project_root) catch try allocator.dupe(u8, project_root);
    defer allocator.free(project_root_real);
    const key_source_path = try cacheKeyNormalizedPath(allocator, project_root_real, source_path);
    defer allocator.free(key_source_path);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBytes(&hasher, "sa-build-cache-v2");
    cacheBytes(&hasher, cacheCompilerVersion());
    cacheBytes(&hasher, kind.dirName());
    cacheBytes(&hasher, key_source_path);
    cacheBytes(&hasher, target_name);
    cacheBytes(&hasher, source_suffix);
    cacheBuildSemanticFlags(&hasher, debug, release_fast, incremental, dce, default_immutable, fast_math);
    // The linked sa_std runtime is identified by the semantic digest of
    // the std source tree it is built from. The previous formula fed the
    // archive's (size, mtime) stat pair: a byte-identical archive rebuild
    // — the normal case when a suite loop rebuilds its tree each round —
    // changed only the mtime and still invalidated every cached entry in
    // every project (measured invalidation radius: 100%). The archive
    // bytes themselves cannot key anything either: they are not
    // reproducible across checkouts. The source tree is the version of
    // the std that the archive means, so its content digest is the key.
    if (try stdTreeDigest(allocator, std_root)) |digest| {
        cacheBytes(&hasher, "std-tree-digest-v1");
        hasher.update(&digest);
    }
    if (wasm) |target| {
        cacheBytes(&hasher, target.triple);
        cacheBool(&hasher, target.no_entry);
        cacheU64(&hasher, target.size_bits);
        // The wasm sa_std archive is stripped at build time (see build.zig:
        // `.strip = true` for wasi). The std source-tree digest alone cannot
        // distinguish a stripped from an unstripped archive built from the
        // same source, so cache entries minted before this change would be
        // revived with the old 14 MB runtime. Bump this generation marker to
        // invalidate them; byte-identical function is preserved.
        cacheBytes(&hasher, "wasm-std-stripped-v1");
    }

    const project_manifest = project_context.manifest;
    if (project_manifest) |*m| {
        // Manifest identity is the project-relative path (its layout role)
        // plus its content; the absolute spelling would reintroduce the
        // checkout location into the key.
        const key_workspace_manifest_path = try cacheKeyNormalizedPath(allocator, project_root_real, project_context.workspace_manifest_path);
        defer allocator.free(key_workspace_manifest_path);
        cacheBytes(&hasher, key_workspace_manifest_path);
        if (projectPathExists(project_context.workspace_manifest_path)) {
            const workspace_manifest_bytes = try readTextFileAlloc(allocator, project_context.workspace_manifest_path);
            defer allocator.free(workspace_manifest_bytes);
            cacheBytes(&hasher, workspace_manifest_bytes);
        }
        if (!std.mem.eql(u8, project_context.member_manifest_path, project_context.workspace_manifest_path)) {
            const key_member_manifest_path = try cacheKeyNormalizedPath(allocator, project_root_real, project_context.member_manifest_path);
            defer allocator.free(key_member_manifest_path);
            cacheBytes(&hasher, key_member_manifest_path);
            if (projectPathExists(project_context.member_manifest_path)) {
                const member_manifest_bytes = try readTextFileAlloc(allocator, project_context.member_manifest_path);
                defer allocator.free(member_manifest_bytes);
                cacheBytes(&hasher, member_manifest_bytes);
            }
        }
        if (project_context.lock_file != null) {
            const lock_path = try projectLockPath(allocator, project_context.root_path);
            defer allocator.free(lock_path);
            try projectFileMaybeHash(&hasher, allocator, lock_path);
        }
        if (project_context.sum_file != null) {
            const sum_path = try projectSumPath(allocator, project_context.root_path);
            defer allocator.free(sum_path);
            try projectFileMaybeHash(&hasher, allocator, sum_path);
        }
        var dependency_slice: []pkg_resolver.Dependency = &.{};
        defer if (dependency_slice.len != 0) allocator.free(dependency_slice);
        var plugin_import_roots: []const []const u8 = &.{};
        defer if (plugin_import_roots.len != 0) freeOwnedStringSlice(allocator, plugin_import_roots);
        if (m.requires.len != 0) {
            dependency_slice = try manifestDependencies(m, allocator);
        }
        if (m.plugin_requires.len != 0) {
            plugin_import_roots = try manifestPluginImportRoots(m, allocator);
        }

        if (hash_source_tree) {
            try hashResolvedSourceTree(allocator, &hasher, dependency_slice, plugin_import_roots, project_context.root_path, std_root, offline, source_path);
        }
    } else {
        try projectFileMaybeHash(&hasher, allocator, project_context.workspace_manifest_path);
        if (!std.mem.eql(u8, project_context.member_manifest_path, project_context.workspace_manifest_path)) {
            try projectFileMaybeHash(&hasher, allocator, project_context.member_manifest_path);
        }
        if (hash_source_tree) {
            try hashResolvedSourceTree(allocator, &hasher, &.{}, &.{}, project_context.root_path, std_root, offline, source_path);
        }
    }

    var out: [32]u8 = undefined;
    hasher.final(&out);
    return .{ .hex = std.fmt.bytesToHex(out, .lower) };
}

pub fn projectSumPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.sum" });
}

pub fn readSumFile(allocator: std.mem.Allocator, path: []const u8) !?manifest.SumFile {
    const source = sio.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer source.close();
    const bytes = try source.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(bytes);
    return try manifest.parseSum(allocator, bytes);
}

pub fn projectCacheHit(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) !bool {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin");
    defer allocator.free(cached_output);
    const cached_test_metadata = if (kind == .test_cache) try projectCacheTestMetadataPath(allocator, project_root, key) else null;
    defer if (cached_test_metadata) |path| allocator.free(path);
    if (!projectCacheArtifactExistsNonEmpty(cached_artifact) or
        !projectCacheArtifactExistsNonEmpty(cached_output) or
        (if (cached_test_metadata) |path| !projectCacheArtifactExistsNonEmpty(path) else false) or
        !projectCacheManifestValid(allocator, project_root, kind, key, cached_artifact, cached_output))
    {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return false;
    }
    copyFileAlloc(allocator, cached_artifact, artifact_path) catch |err| {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return err;
    };
    copyFileAlloc(allocator, cached_output, out_path) catch |err| {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return err;
    };
    projectCacheTouchEntry(allocator, project_root, kind, key);
    return true;
}

pub fn projectCacheArtifactPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, filename: []const u8) ![]u8 {
    const dir = try projectCacheDir(allocator, project_root, kind, key);
    defer allocator.free(dir);
    return try pathJoinAlloc(allocator, &.{ dir, filename });
}

pub fn stdRootFromEnv(allocator: std.mem.Allocator) ![]u8 {
    const repo_std_root = try std.fs.path.join(allocator, &.{ build_options.repo_root, "sa_std" });
    errdefer allocator.free(repo_std_root);

    if (builtin.is_test) return repo_std_root;

    const env_root = sio.getEnvVarOwned(allocator, "SA_STD_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return repo_std_root,
        else => return err,
    };
    errdefer allocator.free(env_root);

    const required_files = [_][]const u8{
        "io/print.sai",
        "core/sa_core.sa",
        "core/result.sa",
        "core/option.sa",
    };
    for (required_files) |rel| {
        const probe_path = try std.fs.path.join(allocator, &.{ env_root, rel });
        defer allocator.free(probe_path);
        if (sio.cwd().openFile(probe_path, .{})) |file| {
            file.close();
        } else |err| switch (err) {
            error.FileNotFound => {
                allocator.free(env_root);
                return repo_std_root;
            },
            else => return err,
        }
    }

    allocator.free(repo_std_root);
    return env_root;
}

pub fn buildSabConstIndex(allocator: std.mem.Allocator, const_decls: []const flattener.ConstDecl) !std.StringHashMap(usize) {
    var index = std.StringHashMap(usize).init(allocator);
    errdefer index.deinit();
    try index.ensureTotalCapacity(@intCast(const_decls.len));
    for (const_decls, 0..) |decl, const_index| {
        if (!index.contains(decl.name)) try index.put(decl.name, const_index);
    }
    return index;
}

pub fn putSabFunctionAlias(index: *std.StringHashMap(usize), name: []const u8, sig_index: usize) !void {
    if (name.len == 0 or index.contains(name)) return;
    try index.put(name, sig_index);
}

pub fn markSabReachableByName(
    reachable: *std.AutoHashMap(usize, void),
    sig_index_by_name: *const std.StringHashMap(usize),
    name: []const u8,
) !bool {
    const sig_index = sig_index_by_name.get(name) orelse return false;
    if (reachable.contains(sig_index)) return false;
    try reachable.put(sig_index, {});
    return true;
}

pub fn markSabReachableVtableConstByName(
    reachable_functions: *std.AutoHashMap(usize, void),
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    const_decls: []const flattener.ConstDecl,
    name: []const u8,
) !bool {
    const normalized = sabReferenceName(name);
    if (normalized.len == 0) return false;
    const const_index = const_index_by_name.get(normalized) orelse return false;
    switch (const_decls[const_index].value) {
        .vtable => |literal| {
            var changed = false;
            if (!reachable_vtable_consts.contains(const_index)) {
                try reachable_vtable_consts.put(const_index, {});
                changed = true;
            }
            for (literal.slots) |slot| {
                changed = (try markSabReachableByName(reachable_functions, sig_index_by_name, slot.func_name)) or changed;
            }
            return changed;
        },
        else => return false,
    }
}

pub fn markSabReachableVtableConstFromOperand(
    reachable_functions: *std.AutoHashMap(usize, void),
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    flat: *const flattener.FlattenResult,
    operand: anytype,
) !bool {
    const text = switch (operand) {
        .reg => |id| flat.symbols.lookupName(id),
        .symbol => |id| flat.symbols.lookupName(id),
        .label => |id| flat.symbols.lookupName(id),
        .func => |id| flat.symbols.lookupName(id),
        .text => |value| value,
        .native_text => |value| value,
        else => null,
    } orelse return false;
    return try markSabReachableVtableConstByName(reachable_functions, reachable_vtable_consts, sig_index_by_name, const_index_by_name, flat.const_decls, text);
}

pub fn collectSabSelectedReachability(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
    ranges: []const SabFunctionRange,
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    selected_test_names: []const []const u8,
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
) !std.AutoHashMap(usize, void) {
    var reachable = std.AutoHashMap(usize, void).init(allocator);
    errdefer reachable.deinit();

    for (selected_test_names) |name| {
        _ = try markSabReachableByName(&reachable, sig_index_by_name, name);
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (ranges) |range| {
            if (!reachable.contains(range.sig_index)) continue;
            for (flat.instructions[range.start..range.end]) |item| {
                if (item.kind != .call and item.kind != .call_indirect) continue;
                var parsed = referee_call.parseInstructionCall(allocator, item, &flat.symbols) catch |err| switch (err) {
                    error.InvalidCallSyntax => continue,
                    else => return err,
                };
                defer parsed.deinit(allocator);
                if (parsed.is_indirect) continue;
                changed = (try markSabReachableByName(&reachable, sig_index_by_name, parsed.callee)) or changed;
            }
            for (flat.instructions[range.start..range.end]) |item| {
                inline for (0..4) |operand_index| {
                    changed = (try markSabReachableVtableConstFromOperand(&reachable, reachable_vtable_consts, sig_index_by_name, const_index_by_name, flat, item.operands[operand_index])) or changed;
                }
            }
        }
    }

    return reachable;
}

pub fn sabReferenceName(text: []const u8) []const u8 {
    var trimmed = std.mem.trim(u8, text, " \t\r");
    while (trimmed.len != 0 and (trimmed[0] == '&' or trimmed[0] == '^' or trimmed[0] == '*')) {
        trimmed = std.mem.trim(u8, trimmed[1..], " \t\r");
    }
    return trimmed;
}

pub fn pruneSabVtableConsts(
    allocator: std.mem.Allocator,
    flat: *flattener.FlattenResult,
    reachable_vtable_consts: *const std.AutoHashMap(usize, void),
) !void {
    if (flat.const_decls.len == 0) return;

    var keep = try allocator.alloc(bool, flat.const_decls.len);
    defer allocator.free(keep);
    var pruned_any = false;
    var kept_count: usize = 0;
    for (flat.const_decls, 0..) |decl, const_index| {
        keep[const_index] = switch (decl.value) {
            .vtable => reachable_vtable_consts.contains(const_index),
            else => true,
        };
        if (keep[const_index]) {
            kept_count += 1;
        } else {
            pruned_any = true;
        }
    }
    if (!pruned_any) return;

    const new_const_decls = try allocator.alloc(flattener.ConstDecl, kept_count);
    var kept_index: usize = 0;
    for (flat.const_decls, 0..) |decl, const_index| {
        if (keep[const_index]) {
            new_const_decls[kept_index] = decl;
            kept_index += 1;
        } else {
            var dropped = decl;
            dropped.deinit(allocator);
        }
    }
    allocator.free(flat.const_decls);
    flat.const_decls = new_const_decls;
}

pub fn projectCacheDir(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", kind.dirName(), key.slice() });
}

pub fn projectCacheTestMetadataPath(allocator: std.mem.Allocator, project_root: []const u8, key: ProjectCacheKey) ![]u8 {
    return try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "test-metadata.json");
}

pub fn freeFlatInstructionMetadata(allocator: std.mem.Allocator, item: flattener.Instruction) void {
    if (item.package_identity) |identity| allocator.free(identity);
    if (item.upstream_loc) |loc| allocator.free(loc.file);
    if (item.native_reg_names.len != 0) allocator.free(item.native_reg_names);
}

/// The spelling of a path as fed into a cache key. An absolute path under
/// the project root is reduced to its project-relative form: the layout
/// role of the file is part of the build's meaning, its checkout location
/// is not. Relative paths are already location-free and pass through, as
/// do absolute paths outside the project (no honest relative form exists
/// for them; they stay exact and simply never share across trees).
pub fn cacheKeyNormalizedPath(allocator: std.mem.Allocator, project_root_real: []const u8, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path) and
        path.len > project_root_real.len and
        std.mem.startsWith(u8, path, project_root_real) and
        path[project_root_real.len] == std.fs.path.sep)
    {
        return allocator.dupe(u8, path[project_root_real.len + 1 ..]);
    }
    return allocator.dupe(u8, path);
}

pub fn projectCacheArtifactExistsNonEmpty(path: []const u8) bool {
    const stat = sio.cwd().statFile(path) catch return false;
    return stat.kind == .file and stat.size != 0;
}

pub fn freeFlatLocEntry(allocator: std.mem.Allocator, entry: ?common_upstream.UpstreamLoc) void {
    if (entry) |loc| allocator.free(loc.file);
}

pub fn cacheBytes(hasher: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    hasher.update(bytes);
    hasher.update(&[_]u8{0});
}

pub fn projectCacheManifestValid(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) bool {
    const manifest_path = projectCacheManifestPath(allocator, project_root, kind, key) catch return false;
    defer allocator.free(manifest_path);
    const manifest_bytes = readTextFileAlloc(allocator, manifest_path) catch return false;
    defer allocator.free(manifest_bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, manifest_bytes, .{}) catch return false;
    defer parsed.deinit();
    if (!jsonIntEquals(jsonGetObject(parsed.value, "version") catch return false, 1)) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "kind") catch return false, kind.dirName())) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "key") catch return false, key.slice())) return false;
    if (!(projectCacheArtifactMatchesManifest(allocator, jsonGetObject(parsed.value, "artifact") catch return false, artifact_path) catch return false)) return false;
    if (!(projectCacheArtifactMatchesManifest(allocator, jsonGetObject(parsed.value, "output") catch return false, out_path) catch return false)) return false;
    return true;
}

pub fn projectCacheManifestPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try projectCacheArtifactPath(allocator, project_root, kind, key, "manifest.json");
}

pub fn jsonGetObject(value: std.json.Value, key: []const u8) !std.json.Value {
    const object = switch (value) {
        .object => |object| object,
        else => return error.InvalidCacheManifest,
    };
    return object.get(key) orelse return error.InvalidCacheManifest;
}

pub fn jsonStringEquals(value: std.json.Value, expected: []const u8) bool {
    return switch (value) {
        .string => |text| std.mem.eql(u8, text, expected),
        else => false,
    };
}

pub fn jsonIntEquals(value: std.json.Value, expected: u64) bool {
    return switch (value) {
        .integer => |v| v >= 0 and @as(u64, @intCast(v)) == expected,
        else => false,
    };
}

pub fn projectCacheArtifactMatchesManifest(allocator: std.mem.Allocator, artifact_value: std.json.Value, path: []const u8) !bool {
    const stat = sio.cwd().statFile(path) catch return false;
    if (stat.kind != .file or stat.size == 0) return false;
    if (!jsonIntEquals(try jsonGetObject(artifact_value, "size"), stat.size)) return false;
    const hash_hex = try hashFileHex(allocator, path);
    return jsonStringEquals(try jsonGetObject(artifact_value, "sha256"), hash_hex[0..]);
}

pub fn readTextFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try sio.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

pub fn projectCacheStore(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) !void {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin");
    defer allocator.free(cached_output);
    try copyFileAlloc(allocator, artifact_path, cached_artifact);
    try copyFileAlloc(allocator, out_path, cached_output);
    try projectCacheWriteManifest(allocator, project_root, kind, key, cached_artifact, cached_output);
    enforceProjectCacheBudget(allocator, project_root, kind, key);
}

pub fn copyFileAlloc(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    _ = allocator;
    try ensureParentDir(dst_path);
    try sio.cwd().copyFile(src_path, sio.cwd(), dst_path, .{});
}

pub fn projectCacheWriteManifest(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    cached_artifact: []const u8,
    cached_output: []const u8,
) !void {
    const manifest_path = try projectCacheManifestPath(allocator, project_root, kind, key);
    defer allocator.free(manifest_path);
    try ensureParentDir(manifest_path);
    var file = try sio.cwd().createFile(manifest_path, .{ .truncate = true });
    defer file.close();
    var fbuf: [8192]u8 = undefined;
    var fw = file.writer(&fbuf);
    const writer = &fw.interface;
    try writer.writeAll("{\"version\":1,\"kind\":");
    try writeJsonString(writer, kind.dirName());
    try writer.writeAll(",\"key\":");
    try writeJsonString(writer, key.slice());
    try writer.writeByte(',');
    try writeCacheArtifactManifestEntry(writer, allocator, "artifact", cached_artifact);
    try writer.writeByte(',');
    try writeCacheArtifactManifestEntry(writer, allocator, "output", cached_output);
    try writer.writeAll("}\n");
    try fw.interface.flush();
}

/// After each store, if the project's .sa_cache exceeds the budget,
/// delete least-recently-used entries until it fits. An entry that keeps
/// being hit keeps a fresh last-used stamp and survives; entries whose
/// meaning fell out of use age out first — reachability as observed by
/// the cache itself. The just-stored entry is never a victim. Every
/// failure is silent: eviction is housekeeping, never a build error.
pub fn enforceProjectCacheBudget(allocator: std.mem.Allocator, project_root: []const u8, protected_kind: BuildCacheKind, protected_key: ProjectCacheKey) void {
    const budget = projectCacheBudgetBytes() orelse return;
    const protected_dir = projectCacheDir(allocator, project_root, protected_kind, protected_key) catch return;
    defer allocator.free(protected_dir);
    const cache_root = cacheRootPath(allocator, project_root) catch return;
    defer allocator.free(cache_root);

    var candidates = std.array_list.Managed(CacheEvictionCandidate).init(allocator);
    defer {
        for (candidates.items) |cand| allocator.free(cand.dir_path);
        candidates.deinit();
    }
    var total: u64 = 0;
    for ([_]BuildCacheKind{ .build_exe, .build_obj, .build_wasm, .build_obj_incremental, .test_cache }) |kind| {
        const kind_path = std.fs.path.join(allocator, &.{ cache_root, kind.dirName() }) catch return;
        defer allocator.free(kind_path);
        var kind_dir = sio.cwd().openDir(kind_path, .{ .iterate = true }) catch continue;
        defer kind_dir.close();
        var iter = kind_dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .directory or !isHexCacheKey(entry.name)) continue;
            const dir_path = std.fs.path.join(allocator, &.{ kind_path, entry.name }) catch return;
            var entry_dir = sio.cwd().openDir(dir_path, .{ .iterate = true }) catch {
                allocator.free(dir_path);
                continue;
            };
            const size = cacheDirTreeSize(entry_dir, 0);
            entry_dir.close();
            const last_used_ns = cacheEntryLastUsedNs(allocator, dir_path);
            candidates.append(.{ .dir_path = dir_path, .size = size, .last_used_ns = last_used_ns }) catch {
                allocator.free(dir_path);
                return;
            };
            total += size;
        }
    }
    if (total <= budget) return;
    std.mem.sort(CacheEvictionCandidate, candidates.items, {}, cacheEvictionCandidateLessThan);
    for (candidates.items) |cand| {
        if (total <= budget) break;
        if (std.mem.eql(u8, cand.dir_path, protected_dir)) continue;
        sio.cwd().deleteTree(cand.dir_path) catch continue;
        total -|= cand.size;
    }
}

pub fn sabPruneDebugEnabled(allocator: std.mem.Allocator) bool {
    const value = sio.getEnvVarOwned(allocator, "SA_DEBUG_SAB_PRUNE") catch return false;
    defer allocator.free(value);
    return value.len != 0 and !std.mem.eql(u8, value, "0");
}

pub fn cacheCompilerVersion() []const u8 {
    if (builtin.is_test) return "test";
    return build_options.version;
}

pub fn projectCacheRemoveKey(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) void {
    const dir = projectCacheDir(allocator, project_root, kind, key) catch return;
    defer allocator.free(dir);
    sio.cwd().deleteTree(dir) catch |err| {
        // Build cache repair is opportunistic here; callers fall back to recompilation on unusable entries.
        _ = @errorName(err);
    };
}

pub fn hashFileHex(allocator: std.mem.Allocator, path: []const u8) ![64]u8 {
    _ = allocator;
    var file = try sio.cwd().openFile(path, .{});
    defer file.close();
    return try hashOpenFileHex(&file);
}

pub fn hashOpenFileHex(file: *sio.File) ![64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return sourceHashHex(out);
}

pub fn cacheFunctionSig(hasher: *std.crypto.hash.sha2.Sha256, sig_item: anytype) void {
    cacheBytes(hasher, sig_item.name);
    cacheU64(hasher, @backingInt(sig_item.kind));
    cacheBool(hasher, sig_item.return_fallible);
    cacheBool(hasher, sig_item.is_ffi_wrapper);
    cacheBool(hasher, sig_item.ignored);
    cacheBool(hasher, sig_item.should_panic);
    cacheU64(hasher, @backingInt(sig_item.return_ty));
    if (sig_item.return_cap) |cap| {
        cacheBool(hasher, true);
        cacheU64(hasher, @backingInt(cap));
    } else {
        cacheBool(hasher, false);
    }
    if (sig_item.llvm_name) |name| cacheBytes(hasher, name) else cacheBytes(hasher, "");
    for (sig_item.params) |param| {
        cacheBytes(hasher, param.name);
        cacheU64(hasher, @backingInt(param.ty));
        cacheU64(hasher, @backingInt(param.cap));
    }
}

pub fn cacheU64(hasher: *std.crypto.hash.sha2.Sha256, value: u64) void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    hasher.update(&buf);
}

pub fn cacheBool(hasher: *std.crypto.hash.sha2.Sha256, value: bool) void {
    hasher.update(&.{if (value) 1 else 0});
}

pub fn computeFunctionObjectKey(allocator: std.mem.Allocator, source_path: []const u8, verified: *const referee.VerifyOk, sig_index: usize, start_idx: usize, end_idx: usize) ![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBytes(&hasher, "sa-build-obj-function-cache");
    cacheBytes(&hasher, cacheCompilerVersion());
    cacheBytes(&hasher, source_path);
    for (verified.function_sigs) |sig_item| {
        cacheFunctionSig(&hasher, sig_item);
    }
    for (verified.const_decls) |decl| {
        cacheBytes(&hasher, decl.raw_text);
    }
    cacheU64(&hasher, sig_index);
    cacheFunctionSig(&hasher, verified.function_sigs[sig_index]);
    for (verified.annotated[start_idx..end_idx]) |item| {
        cacheBytes(&hasher, item.base.raw_text);
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    const hex = std.fmt.bytesToHex(out, .lower);
    return try allocator.dupe(u8, hex[0..]);
}

/// Fold the semantic build-mode flags into a project build key. Kept as a
/// helper so the cache-dimension regression (e.g. --fast-math must key
/// separately) can be unit-tested without a full project tree.
pub fn cacheBuildSemanticFlags(
    hasher: *std.crypto.hash.sha2.Sha256,
    debug: bool,
    release_fast: bool,
    incremental: bool,
    dce: DceMode,
    default_immutable: bool,
    fast_math: bool,
) void {
    cacheBool(hasher, debug);
    cacheBool(hasher, release_fast);
    cacheBool(hasher, incremental);
    cacheBytes(hasher, dce.name());
    // The mutability mode is a semantic dimension of the build, so it is
    // part of the key: a mutable-mode artifact can never satisfy an
    // immutable-mode request or vice versa. (This replaces the old
    // --default-immutable cache bypass, which existed only because the
    // key could not tell the two modes apart.)
    cacheBool(hasher, default_immutable);
    // --fast-math changes the LLVM IR (fast flags on every FP op) and the
    // resulting binary's floating-point semantics. It must be a semantic
    // dimension of the key: otherwise a cached artifact built without the
    // flag silently satisfies a --fast-math request (and vice versa), which
    // is why the flag previously required --no-incremental to take effect.
    cacheBool(hasher, fast_math);
}

/// Refresh an entry's last-used marker after a hit. Eviction ages an
/// entry by the newest of (entry directory, manifest, this marker), so
/// a hit moves the entry's clock without rewriting payload files.
pub fn projectCacheTouchEntry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) void {
    const marker_path = projectCacheArtifactPath(allocator, project_root, kind, key, "last-used") catch return;
    defer allocator.free(marker_path);
    var file = sio.cwd().createFile(marker_path, .{ .truncate = true }) catch return;
    defer file.close();
    file.writeAll("1") catch {};
}

/// Per-project .sa_cache size budget in bytes. SA_CACHE_MAX_MB overrides
/// (0 disables automatic eviction). The 2 GiB default sits far above a
/// healthy working set: once keys are semantic, a project's entries stop
/// churning, so the budget is a backstop against pathological growth —
/// the failure mode where every round minted a fresh full set of keys
/// and nothing ever deleted the old ones.
pub fn projectCacheBudgetBytes() ?u64 {
    const raw = sio.getEnvVarOwned(std.heap.page_allocator, "SA_CACHE_MAX_MB") catch return 2 * 1024 * 1024 * 1024;
    defer std.heap.page_allocator.free(raw);
    const mb = std.fmt.parseUnsigned(u64, std.mem.trim(u8, raw, " \t\r\n"), 10) catch return 2 * 1024 * 1024 * 1024;
    if (mb == 0) return null;
    return mb * 1024 * 1024;
}

pub fn sourceHashHex(hash: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(hash, .lower);
}

pub fn cacheRootPath(allocator: std.mem.Allocator, project_root: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache" });
}

pub fn projectFunctionCachePath(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    function_key: []const u8,
) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.o", .{function_key});
    defer allocator.free(filename);
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", BuildCacheKind.build_obj_incremental.dirName(), key.slice(), "functions", filename });
}

pub fn projectPathExists(path: []const u8) bool {
    sio.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn writeCacheArtifactManifestEntry(writer: anytype, allocator: std.mem.Allocator, name: []const u8, path: []const u8) !void {
    const stat = try sio.cwd().statFile(path);
    const hash_hex = try hashFileHex(allocator, path);
    try writer.writeByte('"');
    try writer.writeAll(name);
    try writer.writeAll("\":{\"size\":");
    try writer.print("{d}", .{stat.size});
    try writer.writeAll(",\"sha256\":");
    try writeJsonString(writer, hash_hex[0..]);
    try writer.writeByte('}');
}

pub const CacheEvictionCandidate = struct {
    dir_path: []u8,
    size: u64,
    last_used_ns: i128,
};

pub fn cacheEvictionCandidateLessThan(_: void, a: CacheEvictionCandidate, b: CacheEvictionCandidate) bool {
    return a.last_used_ns < b.last_used_ns;
}

pub fn projectFileMaybeHash(hasher: *std.crypto.hash.sha2.Sha256, allocator: std.mem.Allocator, path: []const u8) !void {
    if (!projectPathExists(path)) return;
    const bytes = try readTextFileAlloc(allocator, path);
    defer allocator.free(bytes);
    cacheBytes(hasher, bytes);
}

pub fn isHexCacheKey(name: []const u8) bool {
    if (name.len != 64) return false;
    for (name) |c| {
        switch (c) {
            '0'...'9', 'a'...'f' => {},
            else => return false,
        }
    }
    return true;
}

pub fn cacheDirTreeSize(dir: sio.Dir, depth: usize) u64 {
    if (depth > 16) return 0;
    var total: u64 = 0;
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        switch (entry.kind) {
            .file, .sym_link => {
                const stat = dir.statFile(entry.name) catch continue;
                if (stat.kind == .file) total += stat.size;
            },
            .directory => {
                var sub = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                const sub_total = cacheDirTreeSize(sub, depth + 1);
                sub.close();
                total += sub_total;
            },
            else => {},
        }
    }
    return total;
}

pub fn projectFunctionCacheManifestPath(allocator: std.mem.Allocator, project_root: []const u8, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", BuildCacheKind.build_obj_incremental.dirName(), key.slice(), "manifest.json" });
}

pub fn cacheEntryLastUsedNs(allocator: std.mem.Allocator, entry_dir_path: []const u8) i128 {
    var latest: i128 = 0;
    if (sio.cwd().statFile(entry_dir_path)) |stat| {
        latest = @max(latest, stat.mtime.toNanoseconds());
    } else |_| {}
    for ([_][]const u8{ "manifest.json", "last-used" }) |name| {
        const path = std.fs.path.join(allocator, &.{ entry_dir_path, name }) catch continue;
        defer allocator.free(path);
        if (sio.cwd().statFile(path)) |stat| {
            latest = @max(latest, stat.mtime.toNanoseconds());
        } else |_| {}
    }
    return latest;
}

pub fn jsonBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |v| v,
        else => error.InvalidCacheManifest,
    };
}

pub fn jsonU32(value: std.json.Value) !u32 {
    return switch (value) {
        .integer => |v| if (v >= 0 and v <= std.math.maxInt(u32)) @intCast(v) else error.InvalidCacheManifest,
        else => error.InvalidCacheManifest,
    };
}

pub fn jsonStringDup(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return switch (value) {
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCacheManifest,
    };
}

pub fn jsonOptionalStringDup(allocator: std.mem.Allocator, value: std.json.Value) !?[]u8 {
    return switch (value) {
        .null => null,
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCacheManifest,
    };
}

pub fn projectCacheReadTestMetadata(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
) !test_meta.TestList {
    const metadata_path = try projectCacheTestMetadataPath(allocator, project_root, key);
    defer allocator.free(metadata_path);
    const metadata_bytes = try readTextFileAlloc(allocator, metadata_path);
    defer allocator.free(metadata_bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, metadata_bytes, .{});
    defer parsed.deinit();
    if (!jsonIntEquals(try jsonGetObject(parsed.value, "version"), 1)) return error.InvalidCacheManifest;
    const tests_value = try jsonGetObject(parsed.value, "tests");
    const tests_array = switch (tests_value) {
        .array => |array| array.items,
        else => return error.InvalidCacheManifest,
    };

    var tests = std.array_list.Managed(test_meta.TestDescAndFn).init(allocator);
    errdefer {
        for (tests.items) |*test_case| test_case.deinit(allocator);
        tests.deinit();
    }
    for (tests_array) |item| {
        switch (item) {
            .object => {},
            else => return error.InvalidCacheManifest,
        }
        const name = try jsonStringDup(allocator, try jsonGetObject(item, "name"));
        errdefer allocator.free(name);
        const selector = try jsonStringDup(allocator, try jsonGetObject(item, "selector"));
        errdefer allocator.free(selector);
        const source_file = try jsonOptionalStringDup(allocator, try jsonGetObject(item, "source_file"));
        errdefer if (source_file) |file| allocator.free(file);
        try tests.append(.{
            .desc = .{
                .id = try jsonU32(try jsonGetObject(item, "id")),
                .name = name,
                .source_file = source_file,
                .line = try jsonU32(try jsonGetObject(item, "line")),
                .col = try jsonU32(try jsonGetObject(item, "col")),
                .ignored = try jsonBool(try jsonGetObject(item, "ignored")),
                .should_panic = try jsonBool(try jsonGetObject(item, "should_panic")),
            },
            .testfn = .{ .selector_name = selector },
        });
    }
    return .{ .tests = try tests.toOwnedSlice(), .order = .Unsorted };
}

pub fn projectCacheStoreTest(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    test_list: test_meta.TestList,
) !void {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "output.bin");
    defer allocator.free(cached_output);
    try copyFileAlloc(allocator, artifact_path, cached_artifact);
    try copyFileAlloc(allocator, out_path, cached_output);
    try projectCacheWriteTestMetadata(allocator, project_root, key, test_list);
    try projectCacheWriteManifest(allocator, project_root, .test_cache, key, cached_artifact, cached_output);
    enforceProjectCacheBudget(allocator, project_root, .test_cache, key);
}

pub fn projectCacheWriteTestMetadata(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    test_list: test_meta.TestList,
) !void {
    const metadata_path = try projectCacheTestMetadataPath(allocator, project_root, key);
    defer allocator.free(metadata_path);
    try ensureParentDir(metadata_path);
    var file = try sio.cwd().createFile(metadata_path, .{ .truncate = true });
    defer file.close();
    var fbuf: [8192]u8 = undefined;
    var fw = file.writer(&fbuf);
    const writer = &fw.interface;
    try writer.writeAll("{\"version\":1,\"tests\":[");
    for (test_list.tests, 0..) |test_case, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll("{\"id\":");
        try writer.print("{d}", .{test_case.desc.id});
        try writer.writeAll(",\"name\":");
        try writeJsonString(writer, test_case.desc.name);
        try writer.writeAll(",\"selector\":");
        try writeJsonString(writer, test_case.testfn.selector_name);
        try writer.writeAll(",\"source_file\":");
        try writeOptionalJsonString(writer, test_case.desc.source_file);
        try writer.writeAll(",\"line\":");
        try writer.print("{d}", .{test_case.desc.line});
        try writer.writeAll(",\"col\":");
        try writer.print("{d}", .{test_case.desc.col});
        try writer.writeAll(",\"ignored\":");
        try writer.writeAll(if (test_case.desc.ignored) "true" else "false");
        try writer.writeAll(",\"should_panic\":");
        try writer.writeAll(if (test_case.desc.should_panic) "true" else "false");
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
    try fw.interface.flush();
}

pub fn writeOptionalJsonString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}
