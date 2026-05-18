// SAX CLI 命令集成
// 负责 build/check/new/dev 子命令

const std = @import("std");
const Allocator = std.mem.Allocator;

const sax = @import("mod.zig");
const sax_build = @import("build.zig");

pub const SaxCommand = enum {
    build,
    check,
    dev,
    new_project,
};

pub fn parseSaxCommand(cmd_str: []const u8) ?SaxCommand {
    if (std.mem.eql(u8, cmd_str, "build")) return .build;
    if (std.mem.eql(u8, cmd_str, "check")) return .check;
    if (std.mem.eql(u8, cmd_str, "dev")) return .dev;
    if (std.mem.eql(u8, cmd_str, "new")) return .new_project;
    return null;
}

const SaxArtifacts = struct {
    saasm_code: std.ArrayList(u8),
    airlock_js: std.ArrayList(u8),
    index_html: std.ArrayList(u8),
};

const SaxCompilation = struct {
    component_name: []const u8,
    artifacts: SaxArtifacts,
};

fn sourceStem(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const dot_idx = std.mem.lastIndexOfScalar(u8, basename, '.') orelse basename.len;
    return basename[0..dot_idx];
}

fn sourceDir(path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse ".";
}

fn sourceDirAbs(allocator: Allocator, path: []const u8) ![]const u8 {
    return try std.fs.cwd().realpathAlloc(allocator, sourceDir(path));
}

fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
}

fn writeAllFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn readSource(allocator: Allocator, sax_file: []const u8, stderr: anytype) ![]u8 {
    const source = std.fs.cwd().readFileAlloc(allocator, sax_file, 16 * 1024 * 1024) catch |err| {
        try stderr.print("error: failed to read {s}: {}\n", .{ sax_file, err });
        return error.ReadFailed;
    };
    return source;
}

fn compileSaxSource(allocator: Allocator, sax_file: []const u8, source: []const u8, stderr: anytype) !SaxCompilation {
    const component_name = sourceStem(sax_file);

    var compiler = sax.SaxCompiler.init(allocator);
    const artifacts = compiler.compile(source, component_name) catch |err| {
        try stderr.print("error: SAX compilation failed: {}\n", .{err});
        return error.CompileFailed;
    };

    return .{ .component_name = component_name, .artifacts = .{
        .saasm_code = artifacts.saasm_code,
        .airlock_js = artifacts.airlock_js,
        .index_html = artifacts.index_html,
    } };
}

pub fn executeSaxBuild(
    allocator: Allocator,
    sax_file: []const u8,
    output_dir: ?[]const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    const source = try readSource(allocator, sax_file, stderr);
    defer allocator.free(source);

    const compiled = compileSaxSource(allocator, sax_file, source, stderr) catch |err| switch (err) {
        error.CompileFailed => return 1,
        else => return err,
    };
    const component_name = compiled.component_name;
    const artifacts = compiled.artifacts;
    defer artifacts.saasm_code.deinit();
    defer artifacts.airlock_js.deinit();
    defer artifacts.index_html.deinit();

    const out_dir = output_dir orelse "dist";
    const source_dir_abs = try sourceDirAbs(allocator, sax_file);
    defer allocator.free(source_dir_abs);

    const generated_source_path = try std.fmt.allocPrint(allocator, "{s}/{s}.saasm", .{ source_dir_abs, component_name });
    defer allocator.free(generated_source_path);

    const saasm_path = try std.fmt.allocPrint(allocator, "{s}/{s}.saasm", .{ out_dir, component_name });
    defer allocator.free(saasm_path);

    const wasm_path = try std.fmt.allocPrint(allocator, "{s}/app.wasm", .{out_dir});
    defer allocator.free(wasm_path);

    const build_code = try sax_build.buildBrowserWasmFromSourceText(
        allocator,
        generated_source_path,
        artifacts.saasm_code.items,
        wasm_path,
        false,
        .release_small,
        .{},
        stderr,
    );
    if (build_code != 0) return build_code;

    try writeAllFile(saasm_path, artifacts.saasm_code.items);

    const airlock_path = try std.fmt.allocPrint(allocator, "{s}/airlock.js", .{out_dir});
    defer allocator.free(airlock_path);
    try writeAllFile(airlock_path, artifacts.airlock_js.items);

    const html_path = try std.fmt.allocPrint(allocator, "{s}/index.html", .{out_dir});
    defer allocator.free(html_path);
    try writeAllFile(html_path, artifacts.index_html.items);

    try stdout.print("✓ SAX build successful\n", .{});
    try stdout.print("  .saasm: {s}\n", .{saasm_path});
    try stdout.print("  app.wasm: {s}\n", .{wasm_path});
    try stdout.print("  airlock.js: {s}\n", .{airlock_path});
    try stdout.print("  index.html: {s}\n", .{html_path});
    return 0;
}

pub fn executeSaxCheck(
    allocator: Allocator,
    sax_file: []const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    const source = try readSource(allocator, sax_file, stderr);
    defer allocator.free(source);

    const compiled = compileSaxSource(allocator, sax_file, source, stderr) catch |err| switch (err) {
        error.CompileFailed => return 1,
        else => return err,
    };
    const component_name = compiled.component_name;
    const artifacts = compiled.artifacts;
    defer artifacts.saasm_code.deinit();
    defer artifacts.airlock_js.deinit();
    defer artifacts.index_html.deinit();

    const source_dir_abs = try sourceDirAbs(allocator, sax_file);
    defer allocator.free(source_dir_abs);

    const check_source_path = try std.fmt.allocPrint(allocator, "{s}/{s}.saasm", .{ source_dir_abs, component_name });
    defer allocator.free(check_source_path);

    const verified = try sax_build.compileSourceText(allocator, check_source_path, artifacts.saasm_code.items, .{});
    switch (verified) {
        .trap => |report| {
            try sax_build.printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            try stdout.print("✓ SAX check passed\n", .{});
            return 0;
        },
    }
}

pub fn executeSaxNew(
    allocator: Allocator,
    project_name: []const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    _ = stderr;

    try std.fs.cwd().makePath(project_name);

    const sax_template =
        \\<Component name="App">
        \\
        \\  <state>
        \\    count = 0
        \\  </state>
        \\
        \\  <div class="app">
        \\    <h1>Hello SAX</h1>
        \\    <p>Count: {count}</p>
        \\    <button onclick={^increment}>+1</button>
        \\  </div>
        \\
        \\  @increment:
        \\  L_ENTRY:
        \\    count = load state+App_count as i64
        \\    count = add count, 1
        \\    store state+App_count, count as i64
        \\    call @render()
        \\    ret
        \\
        \\  !count
        \\</Component>
    ;

    const sax_path = try std.fmt.allocPrint(allocator, "{s}/app.sax", .{project_name});
    defer allocator.free(sax_path);
    {
        var file = try std.fs.cwd().createFile(sax_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(sax_template);
    }

    const readme_template =
        \\# {s}
        \\
        \\SAX 项目脚手架
        \\
        \\## 编译
        \\
        \\```bash
        \\saasm sax build app.sax
        \\```
        \\
        \\## 开发
        \\
        \\```bash
        \\saasm sax dev
        \\```
        \\
        \\## 验证
        \\
        \\```bash
        \\saasm sax check app.sax
        \\```
    ;

    const readme_path = try std.fmt.allocPrint(allocator, "{s}/README.md", .{project_name});
    defer allocator.free(readme_path);
    {
        var file = try std.fs.cwd().createFile(readme_path, .{ .truncate = true });
        defer file.close();
        try file.writer().print(readme_template, .{project_name});
    }

    try stdout.print("✓ SAX project created: {s}\n", .{project_name});
    try stdout.print("  app.sax: {s}\n", .{sax_path});
    try stdout.print("  README.md: {s}\n", .{readme_path});
    return 0;
}

pub fn executeSaxDev(
    allocator: Allocator,
    sax_file: []const u8,
    port: u16,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    _ = allocator;
    _ = sax_file;
    _ = port;
    _ = stderr;

    try stdout.print("✓ SAX dev server (Phase 2)\n", .{});
    return 0;
}
