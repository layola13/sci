const std = @import("std");
const driver = @import("../driver/zigcc.zig");
const sio = @import("sio");
const referee = @import("../referee.zig");
const build_options = @import("build_options");
const DceMode = @import("../emit_options.zig").DceMode;
const builtin = @import("builtin");
const manifest = @import("../pkg/manifest.zig");

pub fn cacheBytes(hasher: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    hasher.update(bytes);
    hasher.update(&[_]u8{0});
}

pub fn cacheCompilerVersion() []const u8 {
    if (builtin.is_test) return "test";
    return build_options.version;
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
    optimization: driver.Optimization,
    incremental: bool,
    dce: DceMode,
    default_immutable: bool,
    fast_math: bool,
) void {
    cacheBool(hasher, debug);
    // The optimization level is a semantic dimension of the build,
    // so it is part of the key: a plain (O0) artifact can never
    // satisfy a --release-small (O1) request or vice versa. The
    // previous form folded only a single bool (whether the
    // optimization was release-fast), which collapsed .none and
    // .release_small to the same value, so a cached plain binary
    // silently satisfied a --release-small build in the same
    // directory.
    cacheBytes(hasher, @tagName(optimization));
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
