const std = @import("std");
const LibContractParam = @import("types.zig").LibContractParam;
const ensureParentDir = @import("compile.zig").ensureParentDir;
const LibTargetFamily = @import("types.zig").LibTargetFamily;
const LibContractEntry = @import("types.zig").LibContractEntry;
const CompileOptions = @import("types.zig").CompileOptions;
const LibContract = @import("types.zig").LibContract;
const LibKind = @import("types.zig").LibKind;
const builtin = @import("builtin");
const sio = @import("sio");
const build_options = @import("build_options");
const flattener = @import("../flattener.zig");
const emit_js = @import("../emit_js.zig");
const emit_c = @import("../emit_c.zig");
const emit_llvm_llvmc = @import("../emit_llvm_llvmc.zig");
const emit_options = @import("../emit_options.zig");
const driver = @import("../driver/zigcc.zig");
const bc2sa = @import("../llvm2sa.zig");
const layout = @import("../layout.zig");
const sab = @import("../sab.zig");
const plugins = @import("../plugins.zig");
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;

pub fn parseLibContract(arena: std.mem.Allocator, contract_path: []const u8, source: []const u8, stderr: anytype) !?LibContract {
    const stem_raw = std.fs.path.stem(contract_path);
    if (!libContractIdentValid(stem_raw)) {
        try stderr.print("error: build-lib contract file name '{s}' is not a valid C identifier stem\n", .{stem_raw});
        return null;
    }
    const stem = try arena.dupe(u8, stem_raw);
    const macro_prefix = try arena.alloc(u8, stem.len);
    for (stem, 0..) |ch, i| {
        macro_prefix[i] = if (std.ascii.isAlphanumeric(ch)) std.ascii.toUpper(ch) else '_';
    }

    var entries = std.array_list.Managed(LibContractEntry).init(arena);
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw_line| {
        line_no += 1;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "//")) continue;
        if (!std.mem.startsWith(u8, line, "@export ")) {
            try stderr.print("error: {s}:{d}: expected an @export declaration line\n", .{ contract_path, line_no });
            return null;
        }
        const rest = std.mem.trimStart(u8, line["@export".len..], " \t");
        const paren = std.mem.indexOfScalar(u8, rest, '(') orelse {
            try stderr.print("error: {s}:{d}: missing '(' in @export declaration\n", .{ contract_path, line_no });
            return null;
        };
        const name = std.mem.trim(u8, rest[0..paren], " \t");
        if (!libContractIdentValid(name)) {
            try stderr.print("error: {s}:{d}: invalid export name '{s}'\n", .{ contract_path, line_no, name });
            return null;
        }
        for (entries.items) |existing| {
            if (std.mem.eql(u8, existing.name, name)) {
                try stderr.print("error: {s}:{d}: duplicate export '{s}'\n", .{ contract_path, line_no, name });
                return null;
            }
        }
        const close = std.mem.lastIndexOfScalar(u8, rest, ')') orelse {
            try stderr.print("error: {s}:{d}: missing ')' in @export declaration\n", .{ contract_path, line_no });
            return null;
        };
        var tail = std.mem.trim(u8, rest[close + 1 ..], " \t");
        if (tail.len != 0 and (tail[tail.len - 1] == ':' or tail[tail.len - 1] == ';')) {
            tail = std.mem.trimEnd(u8, tail[0 .. tail.len - 1], " \t");
        }
        if (!std.mem.startsWith(u8, tail, "->")) {
            try stderr.print("error: {s}:{d}: expected '-> <type>' after the parameter list\n", .{ contract_path, line_no });
            return null;
        }
        const return_type = std.mem.trim(u8, tail[2..], " \t");
        if (!libContractTypeValid(return_type, true)) {
            try stderr.print("error: {s}:{d}: unsupported return type '{s}'\n", .{ contract_path, line_no, return_type });
            return null;
        }
        var params = std.array_list.Managed(LibContractParam).init(arena);
        const params_text = std.mem.trim(u8, rest[paren + 1 .. close], " \t");
        if (params_text.len != 0) {
            var param_iter = std.mem.splitScalar(u8, params_text, ',');
            while (param_iter.next()) |param_raw| {
                var param_text = std.mem.trim(u8, param_raw, " \t");
                var borrowed = false;
                if (std.mem.startsWith(u8, param_text, "&")) {
                    borrowed = true;
                    param_text = std.mem.trimStart(u8, param_text[1..], " \t");
                }
                const colon = std.mem.lastIndexOfScalar(u8, param_text, ':') orelse {
                    try stderr.print("error: {s}:{d}: parameter '{s}' is missing ': <type>'\n", .{ contract_path, line_no, param_text });
                    return null;
                };
                const param_name = std.mem.trim(u8, param_text[0..colon], " \t");
                const param_type = std.mem.trim(u8, param_text[colon + 1 ..], " \t");
                if (!libContractIdentValid(param_name)) {
                    try stderr.print("error: {s}:{d}: invalid parameter name '{s}'\n", .{ contract_path, line_no, param_name });
                    return null;
                }
                if (!libContractTypeValid(param_type, false)) {
                    try stderr.print("error: {s}:{d}: unsupported parameter type '{s}'\n", .{ contract_path, line_no, param_type });
                    return null;
                }
                if (borrowed and !std.mem.eql(u8, param_type, "ptr")) {
                    try stderr.print("error: {s}:{d}: borrowed parameter '&{s}' must be of type ptr in build-lib v1\n", .{ contract_path, line_no, param_name });
                    return null;
                }
                try params.append(.{ .name = param_name, .type_name = param_type, .borrowed = borrowed });
            }
        }
        try entries.append(.{
            .name = name,
            .params = try params.toOwnedSlice(),
            .return_type = return_type,
        });
    }
    return .{
        .entries = try entries.toOwnedSlice(),
        .stem = stem,
        .macro_prefix = macro_prefix,
    };
}

pub fn executeBuildLib(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, kind: LibKind, contract_path: []const u8, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // 1. Export contract (single source for header, table, export control).
    const contract_source = sio.cwd().readFileAlloc(allocator, contract_path, 16 * 1024 * 1024) catch |err| {
        try stderr.print("error: cannot read build-lib contract '{s}': {s}\n", .{ contract_path, @errorName(err) });
        return 1;
    };
    defer allocator.free(contract_source);
    const contract = (try parseLibContract(arena, contract_path, contract_source, stderr)) orelse return 1;

    // Paths for the deliverables and the generated intermediates. The
    // header is a deliverable and lands next to the library output; the
    // generated sources sit next to it too, named after the output.
    const out_dir = std.fs.path.dirname(out_path) orelse ".";
    const header_path = try std.fs.path.join(arena, &.{ out_dir, try std.fmt.allocPrint(arena, "{s}.h", .{contract.stem}) });
    const artifact_path = try intermediateArtifactPath(arena, out_path);
    const object_path = try std.fmt.allocPrint(arena, "{s}.lib.o", .{out_path});
    const api_source_path = try std.fmt.allocPrint(arena, "{s}.lib_api.c", .{out_path});
    const family = libTargetFamily(compile_options);

    // 2. For .sla sources, generate the forwarding unit (root + SA glue)
    //    and compile that instead of the user's file.
    var compile_path = source_path;
    if (std.mem.eql(u8, std.fs.path.extension(source_path), ".sla")) {
        if (std.mem.indexOfAny(u8, source_path, "\"\n") != null) {
            try stderr.print("error: build-lib cannot quote source path '{s}' into the generated root unit\n", .{source_path});
            return 1;
        }
        const glue_path = try std.fmt.allocPrint(arena, "{s}.lib_glue.sa", .{out_path});
        const root_path = try std.fmt.allocPrint(arena, "{s}.lib_root.sla", .{out_path});
        try ensureParentDir(glue_path);
        const abs_source = try sio.cwd().realpathAlloc(arena, source_path);
        const abs_glue_dir = try sio.cwd().realpathAlloc(arena, std.fs.path.dirname(glue_path) orelse ".");
        const abs_glue_path = try std.fs.path.join(arena, &.{ abs_glue_dir, std.fs.path.basename(glue_path) });
        try writeFile(sio.cwd(), glue_path, try generateLibGlueSa(arena, contract));
        try writeFile(sio.cwd(), root_path, try generateLibRootSla(arena, contract, abs_source, abs_glue_path));
        const lowered_path = try std.fmt.allocPrint(arena, "{s}.lib_root.sa", .{out_path});
        lowerSlaUnitViaFrontend(allocator, root_path, lowered_path, stderr) catch |err| switch (err) {
            error.LanguageFrontendMissing, error.FrontendBuildFailed => return 1,
            else => return err,
        };
        compile_path = lowered_path;
    }

    // 3. Compile the (possibly generated) source to a verified module.
    const compiled = try compileSource(allocator, compile_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            rejectNpmBindsUnlessJs("sa build-lib", &owned.flat, stderr) catch return 1;
            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);
            const std_archive_path = saStdArchivePathForTarget(allocator, compile_options.target_triple) catch |err| {
                if (err == error.ArchiveNotFoundForTarget) {
                    try stderr.print("error: no sa_std archive for target '{s}'. Build it with:\n", .{compile_options.target_triple.?});
                    try stderr.writeAll("  zig build -Dtarget=<triple> sa-std-static\n");
                    try stderr.writeAll("then copy zig-out/lib/<libsa_std.a|sa_std.lib> to $SA_STD_DIR/<triple>/\n");
                    return 1;
                }
                return err;
            };
            defer allocator.free(std_archive_path);
            const size_bits = sizeBitsForTriple(compile_options.target_triple);

            try ensureParentDir(artifact_path);
            emit_llvm_llvmc.emitLlvmcToArtifacts(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, compile_path, size_bits, .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = emitOptLevel(debug, optimization), .dce = compile_options.dce, .fast_math = compile_options.fast_math, .std_root = emit_std_root, .target_triple = compile_options.target_triple }, artifact_path, object_path, emitOptLevel(debug, optimization)) catch |err| {
                try printLlvmcEmitError(stderr, err, diagnostics_mode);
                return 1;
            };

            // 4. Header + API table unit (deliverable header is written
            //    before linking so it exists even if the link fails).
            try ensureParentDir(header_path);
            try writeFile(sio.cwd(), header_path, try generateLibHeader(arena, contract));
            const abs_header = try sio.cwd().realpathAlloc(arena, header_path);
            try writeFile(sio.cwd(), api_source_path, try generateLibApiSource(arena, contract, kind, abs_header));

            // 5. Link or archive. The sa_std archive is an input of the
            //    shared link, and is folded into the static archive
            //    through a relocatable combine, so both artifacts are
            //    self-contained.
            switch (kind) {
                .shared => {
                    var control = driver.SharedExportControl{};
                    switch (family) {
                        .elf => {
                            const script_path = try std.fmt.allocPrint(arena, "{s}.lib_exports.map", .{out_path});
                            try writeFile(sio.cwd(), script_path, try generateLibVersionScript(arena, contract));
                            control.soname_arg = try std.fmt.allocPrint(arena, "-Wl,-soname,{s}", .{std.fs.path.basename(out_path)});
                            control.version_script_arg = try std.fmt.allocPrint(arena, "-Wl,--version-script,{s}", .{script_path});
                        },
                        .mach_o => {
                            const list_path = try std.fmt.allocPrint(arena, "{s}.lib_exports.txt", .{out_path});
                            try writeFile(sio.cwd(), list_path, try generateLibExportedSymbolsList(arena, contract));
                            control.exported_symbols_list_arg = try std.fmt.allocPrint(arena, "-Wl,-exported_symbols_list,{s}", .{list_path});
                        },
                        .pe => {
                            const def_path = try std.fmt.allocPrint(arena, "{s}.lib_exports.def", .{out_path});
                            try writeFile(sio.cwd(), def_path, try generateLibDefFile(arena, contract));
                            control.def_file_path = def_path;
                            const implib_path = try std.fs.path.join(arena, &.{ out_dir, try std.fmt.allocPrint(arena, "{s}.lib", .{contract.stem}) });
                            control.implib_arg = try std.fmt.allocPrint(arena, "-Wl,--out-implib,{s}", .{implib_path});
                        },
                    }
                    driver.compileShared(allocator, object_path, api_source_path, out_path, optimization, std_archive_path, debug, stderr, compile_options.target_triple, control) catch |err| switch (err) {
                        error.ChildProcessFailed => return 1,
                        else => return err,
                    };
                    // 6. Post-link surface check on host-target builds:
                    //    every contract symbol plus the two generated
                    //    entries must resolve in the produced artifact.
                    if (compile_options.target_triple == null) {
                        var dyn_lib = dynlib_compat.DynLib.open(out_path) catch {
                            try stderr.print("error: build-lib produced '{s}' but it cannot be opened as a shared library\n", .{out_path});
                            return 1;
                        };
                        defer dyn_lib.close();
                        var names = std.array_list.Managed([:0]const u8).init(arena);
                        for (contract.entries) |entry| {
                            try names.append(try libDupeZ(arena, entry.name));
                        }
                        try names.append(try libDupeZ(arena, try std.fmt.allocPrint(arena, "{s}_get_api", .{contract.stem})));
                        try names.append(try libDupeZ(arena, try std.fmt.allocPrint(arena, "{s}_abi_version", .{contract.stem})));
                        for (names.items) |symbol| {
                            if (dyn_lib.lookup(*anyopaque, symbol) == null) {
                                try stderr.print("error: build-lib artifact '{s}' does not export contract symbol '{s}'\n", .{ out_path, symbol });
                                return 1;
                            }
                        }
                    }
                },
                .static => {
                    const api_object_path = try std.fmt.allocPrint(arena, "{s}.lib_api.o", .{out_path});
                    const combined_path = try std.fmt.allocPrint(arena, "{s}.lib_combined.o", .{out_path});
                    driver.compileObj(allocator, api_source_path, api_object_path, optimization, debug, stderr, compile_options.target_triple) catch |err| switch (err) {
                        error.ChildProcessFailed => return 1,
                        else => return err,
                    };
                    driver.compileRelocatableObj(allocator, &.{ object_path, api_object_path, std_archive_path }, combined_path, stderr) catch |err| switch (err) {
                        error.ChildProcessFailed => return 1,
                        else => return err,
                    };
                    driver.compileArchive(allocator, out_path, &.{combined_path}, stderr) catch |err| switch (err) {
                        error.ChildProcessFailed => return 1,
                        else => return err,
                    };
                },
            }

            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}

pub fn libContractIdentValid(name: []const u8) bool {
    if (name.len == 0) return false;
    const first = name[0];
    if (!(std.ascii.isAlphabetic(first) or first == '_')) return false;
    for (name[1..]) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) return false;
    }
    return true;
}

pub fn intermediateArtifactPath(allocator: std.mem.Allocator, out_path: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}.sa.bc", .{out_path});
}

pub fn libContractTypeValid(type_name: []const u8, allow_void: bool) bool {
    const scalar = [_][]const u8{
        "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "f32", "f64", "ptr",
    };
    for (scalar) |candidate| {
        if (std.mem.eql(u8, type_name, candidate)) return true;
    }
    return allow_void and std.mem.eql(u8, type_name, "void");
}

pub fn libTargetFamily(compile_options: CompileOptions) LibTargetFamily {
    if (compile_options.target_triple) |triple| {
        if (std.mem.indexOf(u8, triple, "windows") != null) return .pe;
        if (std.mem.indexOf(u8, triple, "macos") != null or std.mem.indexOf(u8, triple, "darwin") != null) return .mach_o;
        return .elf;
    }
    return switch (builtin.os.tag) {
        .windows => .pe,
        .macos => .mach_o,
        else => .elf,
    };
}

pub fn writeFile(dir: sio.Dir, path: []const u8, bytes: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}
