const std = @import("std");
const BuildCtx = @import("ctx.zig").BuildCtx;
const pathFromRoot = @import("paths.zig").pathFromRoot;
const mirrorSaStdTree = @import("sastd_mirror.zig").mirrorSaStdTree;
const addLlvmcSupportToModule = @import("llvm.zig").addLlvmcSupportToModule;
const linkLLVMToCompile = @import("llvm.zig").linkLLVMToCompile;
const installLlvmCDll = @import("llvm.zig").installLlvmCDll;

/// build.zig lines 348-580.
pub fn buildCli(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const enable_llvm = ctx.enable_llvm;
    const llvm_include_dir = ctx.llvm_include_dir;
    const llvm_lib_dir = ctx.llvm_lib_dir;
    const llvm_lib_name = ctx.llvm_lib_name;
    const build_options = ctx.build_options;
    const sio_module = ctx.sio_module;
    const sa_std_static = ctx.sa_std_static;
    const install_sa_std_static = ctx.install_sa_std_static;
    const sync_sa_std_artifact = ctx.sync_sa_std_artifact;

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    cli_module.addImport("sio", sio_module);
    addLlvmcSupportToModule(b, cli_module, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    cli_module.addOptions("build_options", build_options);
    const exe = b.addExecutable(.{
        .name = "sa",
        .root_module = cli_module,
    });
    ctx.exe = exe;
    linkLLVMToCompile(exe, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    const install_sa_exe = b.addInstallArtifact(exe, .{});
    ctx.install_sa_exe = install_sa_exe;
    b.getInstallStep().dependOn(&install_sa_exe.step);

    // -- Shippable runtime bundle -------------------------------------
    // 'zig build sa-runtime-bundle' assembles what a distribution needs
    // so that first use compiles nothing on the user's machine:
    //   * the prebuilt sa_std archives (the plain install step already
    //     emits lib/<archive>; the wasm32-wasi archive comes from
    //     'zig build -Dtarget=wasm32-wasi sa-std-static'), and
    //   * a prewarmed zig global cache under share/sa/zig-cache.
    // 'zig cc' builds its support libraries (compiler_rt, libc stubs)
    // from source on first use and would otherwise write ~45 MB into
    // the user's ~/.cache/zig on every machine. The cache is
    // content-keyed, so the prewarmed copy hits for any install path
    // on the same zig version; src/driver/zigcc.zig points 'zig cc'
    // children at it via ZIG_GLOBAL_CACHE_DIR whenever it is present
    // and writable.
    const runtime_bundle_step = b.step("sa-runtime-bundle", "Install the toolchain and prewarm the shippable zig cache (share/sa/zig-cache)");
    runtime_bundle_step.dependOn(b.getInstallStep());
    {
        // Default: the default install prefix (zig-out) — i.e. exactly
        // the share/sa/zig-cache the installed sa resolves next to
        // bin/sa. Packagers installing elsewhere pass the matching
        // directory explicitly and ship it as <prefix>/share/sa/zig-cache.
        const bundle_cache_dir = b.option([]const u8, "runtime-bundle-cache-dir", "Directory the sa-runtime-bundle step prewarms as the shippable zig global cache.") orelse pathFromRoot(b, "zig-out/share/sa/zig-cache");
        const wf = b.addWriteFiles();
        const smoke_sa = wf.add("runtime_bundle_smoke.sa",
            \\@import "sa_std/io/print.sai"
            \\
            \\@main() -> i32:
            \\L_ENTRY:
            \\    @const S = utf8:"ok"
            \\    call @sa_print_bytes(&S, 2)
            \\    return 0
            \\
        );
        // The prewarm runs invoke the just-built 'sa', whose zigExe()
        // resolves 'zig' against PATH; make sure the zig running this
        // build is findable even when it was invoked by absolute path.
        const zig_bin_dir = std.fs.path.dirname(b.graph.zig_exe) orelse "";
        const prev_path = b.graph.environ_map.get("PATH") orelse "";
        const prewarm_path = if (zig_bin_dir.len == 0) prev_path else b.fmt("{s}{c}{s}", .{ zig_bin_dir, std.fs.path.delimiter, prev_path });
        const prewarm_native = b.addRunArtifact(exe);
        prewarm_native.addArg("build-exe");
        prewarm_native.addFileArg(smoke_sa);
        prewarm_native.addArg("-o");
        _ = prewarm_native.addOutputFileArg("runtime_bundle_smoke");
        prewarm_native.setEnvironmentVariable("PATH", prewarm_path);
        prewarm_native.setEnvironmentVariable("ZIG_GLOBAL_CACHE_DIR", bundle_cache_dir);
        prewarm_native.setEnvironmentVariable("SA_ZIG_GLOBAL_CACHE_DIR", bundle_cache_dir);
        prewarm_native.step.dependOn(&install_sa_std_static.step);
        prewarm_native.step.dependOn(&sync_sa_std_artifact.step);
        runtime_bundle_step.dependOn(&prewarm_native.step);
        // The wasm32-wasi link configuration has its own support
        // objects; prewarm it too when the cross archive has been built.
        if (std.Io.Dir.cwd().access(b.graph.io, "artifacts/sa_std/wasm32-wasi/libsa_std.a", .{})) {
            const prewarm_wasm = b.addRunArtifact(exe);
            prewarm_wasm.addArg("build-wasm");
            prewarm_wasm.addFileArg(smoke_sa);
            prewarm_wasm.addArg("-o");
            _ = prewarm_wasm.addOutputFileArg("runtime_bundle_smoke.wasm");
            prewarm_wasm.addArgs(&.{ "--target", "wasm32" });
            prewarm_wasm.setEnvironmentVariable("PATH", prewarm_path);
            prewarm_wasm.setEnvironmentVariable("ZIG_GLOBAL_CACHE_DIR", bundle_cache_dir);
            prewarm_wasm.setEnvironmentVariable("SA_ZIG_GLOBAL_CACHE_DIR", bundle_cache_dir);
            runtime_bundle_step.dependOn(&prewarm_wasm.step);
        } else |_| {
            std.debug.print("sa-runtime-bundle: artifacts/sa_std/wasm32-wasi/libsa_std.a missing; skipping wasm cache prewarm (build it with: zig build -Dtarget=wasm32-wasi sa-std-static)\n", .{});
        }
    }

    // -- SA-implemented std units in the static sa_std archive -----------
    // A few .sai externs are implemented in SA source rather than in the
    // Zig runtime (today exactly the GrowVec family:
    // sa_std/alloc/growvec.sa, pulled in via sa_std/growvec.sa). The
    // archive built above is Zig-only, so those symbols can never enter
    // it: text-backend clients that declare the externs fail at link
    // with undefined symbols, while SAB clients work because the SAB
    // compiler compiles the .sa unit in. Assemble the SA-implemented
    // units with a host build of the `sa` CLI and add the resulting
    // objects to the static archive as standalone members. Archive
    // member granularity is what makes this safe for the SAB path: a
    // program that already defines the symbols (because SAB compiled
    // the unit in) never pulls the member, so no duplicate definition
    // can occur; a text client with unresolved symbols pulls exactly
    // this member.
    if (enable_llvm and target.result.os.tag != .windows) {
        // Host-target copy of the CLI, used purely as a build-time
        // assembler for .sa std units. In host builds this has the same
        // artifact configuration as `exe` above and is served from the
        // build cache.
        // The tool needs its own host-target copy of the sio module:
        // importing the target-scoped sio_module would unify the whole
        // tool compile onto the cross target (zig module target
        // unification follows imported modules), which cannot run here.
        const sa_tool_sio_module = b.createModule(.{
            .root_source_file = b.path("src/sa_io.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        });
        const sa_tool_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .link_libc = true,
        });
        sa_tool_module.addImport("sio", sa_tool_sio_module);
        addLlvmcSupportToModule(b, sa_tool_module, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
        sa_tool_module.addOptions("build_options", build_options);
        const sa_tool = b.addExecutable(.{
            .name = "sa-std-asm",
            .root_module = sa_tool_module,
        });
        linkLLVMToCompile(sa_tool, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);

        const triple: []const u8 = if (target.result.os.tag == .wasi or target.result.abi == .none)
            b.fmt("{s}-{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag) })
        else
            b.fmt("{s}-{s}-{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag), @tagName(target.result.abi) });

        // Target-conditional declarations (C-upper): SA-implemented std
        // units may carry conditional declaration blocks (libc size_t
        // widths differ per target). Materialize the unit for this
        // archive's target before assembling, per the shared
        // specification implemented in tools/decl_materialize.zig. A
        // unit without conditional blocks is assembled in place,
        // byte-identical to before. Materialization problems are loud
        // configure-time failures, never a silent fallback.
        const decl_materialize = @import("../tools/decl_materialize.zig");
        const decl_target: decl_materialize.DeclTarget = if (target.result.cpu.arch == .wasm32) .wasm32 else .native;

        const asm_growvec = b.addRunArtifact(sa_tool);
        // The assembler must not reuse a project build cache populated
        // for another target (cross-target reuse corrupts the object);
        // --no-incremental disables that cache outright. Argument order
        // mirrors the proven manual invocation:
        //   sa build-obj <unit.sa> --no-incremental --target <triple> -o <out>
        asm_growvec.addArg("build-obj");
        const growvec_src_rel = "sa_std/alloc/growvec.sa";
        const growvec_abs = pathFromRoot(b, growvec_src_rel);
        const growvec_raw = std.Io.Dir.readFileAlloc(.cwd(), b.graph.io, growvec_abs, b.allocator, .limited(16 * 1024 * 1024)) catch |err|
            std.debug.panic("failed to read {s}: {s}", .{ growvec_src_rel, @errorName(err) });
        if (decl_materialize.containsTargetBlocks(growvec_raw)) {
            // The unit's relative @imports must resolve exactly as
            // they do in-tree, so the assembler is pointed at a
            // mirrored copy of the whole sa_std tree (in the build
            // cache) in which every file carrying conditional blocks
            // (this unit and any unit in its import closure, e.g.
            // core/mem.sa) has been materialized for the target.
            const wf = b.addWriteFiles();
            mirrorSaStdTree(b, wf, decl_target);
            asm_growvec.addFileArg(wf.getDirectory().path(b, "alloc/growvec.sa"));
            asm_growvec.step.dependOn(&wf.step);
        } else {
            asm_growvec.addFileArg(b.path(growvec_src_rel));
        }
        asm_growvec.addArgs(&.{ "--no-incremental", "--target", triple, "-o" });
        const growvec_obj = asm_growvec.addOutputFileArg("sa_growvec_unit.o");
        // The assembled unit's import closure (core/mem.sa, core/slice.sa,
        // num.sa) contributes its own @export definitions, which the
        // assembler emits as strong globals of the unit object
        // (sa_mem_copy / sa_mem_set / sa_mem_copy_nonoverlapping).
        // Text-backend clients include the same .sa sources textually and
        // therefore define those symbols in their own TU; when such a
        // client also pulls this member (for the GrowVec surface), lld
        // reports duplicate symbols and the link fails.  Localize every
        // global the unit's .sai does not declare, so the member exports
        // exactly the surface the design note above promises: clients
        // that already define the closure symbols never collide, and
        // clients with unresolved GrowVec symbols pull exactly this
        // member.  The keep list is read mechanically from growvec.sai,
        // the same declaration file that defines the surface.
        const growvec_sai_rel = "sa_std/growvec.sai";
        const growvec_sai_abs = pathFromRoot(b, growvec_sai_rel);
        const growvec_sai_raw = std.Io.Dir.readFileAlloc(.cwd(), b.graph.io, growvec_sai_abs, b.allocator, .limited(1024 * 1024)) catch |err|
            std.debug.panic("failed to read {s}: {s}", .{ growvec_sai_rel, @errorName(err) });
        var keeps_buf: std.ArrayList(u8) = .empty;
        {
            var lines = std.mem.splitScalar(u8, growvec_sai_raw, '\n');
            while (lines.next()) |line| {
                const t = std.mem.trim(u8, line, " \t\r");
                if (!std.mem.startsWith(u8, t, "@extern ")) continue;
                const rest = t["@extern ".len..];
                const end = std.mem.indexOfAny(u8, rest, "( \t") orelse rest.len;
                if (end == 0) continue;
                keeps_buf.appendSlice(b.allocator, rest[0..end]) catch @panic("OOM");
                keeps_buf.append(b.allocator, '\n') catch @panic("OOM");
            }
        }
        if (keeps_buf.items.len == 0) std.debug.panic("no @extern declarations parsed from {s}", .{growvec_sai_rel});
        const keeps_wf = b.addWriteFiles();
        const keeps_file = keeps_wf.add("growvec_keeps.txt", keeps_buf.items);
        const is_wasm_unit = target.result.cpu.arch == .wasm32;
        // GNU objcopy cannot process wasm objects; LLVM objcopy can.
        // A wasm unit built without llvm-objcopy keeps the raw object
        // (the pre-fix behaviour for that target) and says so in the
        // build output; native units require an objcopy -- a build
        // that silently shipped the unlocalized member would recreate
        // the duplicate-symbol defect, so absence is a loud failure.
        const objcopy_prog: ?[]const u8 = if (is_wasm_unit)
            b.findProgram(.{ .names = &.{"llvm-objcopy"} })
        else
            b.findProgram(.{ .names = &.{ "llvm-objcopy", "objcopy" } });
        if (objcopy_prog) |prog| {
            const localize = b.addSystemCommand(&.{prog});
            localize.addArg("--keep-global-symbols");
            localize.addFileArg(keeps_file);
            localize.addFileArg(growvec_obj);
            const localized_obj = localize.addOutputFileArg("sa_growvec_unit.o");
            sa_std_static.root_module.addObjectFile(localized_obj);
        } else if (is_wasm_unit) {
            std.debug.print("sa-std-static: llvm-objcopy not found; wasm GrowVec unit archived unlocalized (non-surface globals retained)\n", .{});
            sa_std_static.root_module.addObjectFile(growvec_obj);
        } else {
            std.debug.panic("sa-std-static: an objcopy (llvm-objcopy or objcopy) is required to localize the GrowVec archive unit", .{});
        }
    }
    if (enable_llvm) installLlvmCDll(b, llvm_lib_dir, target.result.os.tag);
}
