const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const manifest = @import("pkg/manifest.zig");
const daemon_client = @import("daemon_client.zig");


pub const hasJsonFlag = @import("cli/help.zig").hasJsonFlag;

// LINE-PEAK50-EMIT Form 1: size-gated sequential CGU emission.
// Sequential emission cuts the 50k peak from ~466 MB to ~277 MB (box,
// SA_CGU_SEQ_SHARDS=4): the CModule + LLVM IR of four concurrent shards
// no longer coexist. But sequential costs ~30% wall time at 10k (local
// rig: 1.22 s vs 0.94 s), which would flip the 10k time leg (box margin
// only 9.5%). So sequential is the default only above this fn-count gate;
// small modules keep the parallel path. synth10k = 1111 fns, synth50k =
// 5555 fns; the threshold sits between them.

const commandFromName = @import("cli/help.zig").commandFromName;

    // NOTE (DEF-SCI-TMPWORKDIR-BASE64-SLASH): temp-dir names use url_safe base64. Standard base64 can emit slash, which turns the name into an absolute path and fails makePath with AccessDenied.

const ExecuteOptions = @import("cli/types.zig").ExecuteOptions;

pub fn defaultExecutableSuffix() []const u8 {
    return if (builtin.os.tag == .windows) ".exe" else "";
}

// --- std tree semantic digest -------------------------------------------
// The cache key identifies the linked sa_std runtime by a content digest
// of the std source tree — the only "std version" that is a meaning.
// Neither the archive's stat (mtime moves on byte-identical rebuilds) nor
// its bytes (not reproducible across checkouts) can serve. The digest
// covers every regular source file under the std root as (relative path,
// content) pairs in sorted order; scratch/cache directories and the
// built archive itself (a product of the tree that hermetic layouts
// place inside it) are not std semantics and are skipped.

// --- cache budget: bounded, reachability-ordered eviction ---------------
// Keys decide identity; this decides how much history the disk keeps.
// The two are independent by design: eviction never changes what a key
// means, only how long an unused meaning's products survive.

/// Return the byte range [start, end) of the manifest line whose first
/// two whitespace-separated tokens are `require` and `url`, or null.

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

const routeProjectVerb = @import("cli/route.zig").routeProjectVerb;

const freeRewrittenArgs = @import("cli/route.zig").freeRewrittenArgs;

const routeLanguageFrontend = @import("cli/route.zig").routeLanguageFrontend;

const executeWithWritersAndOptionsImpl = @import("cli/dispatch.zig").executeWithWritersAndOptionsImpl;

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

const cli_tests = @import("cli/cli_tests.zig");