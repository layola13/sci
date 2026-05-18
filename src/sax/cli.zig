// SAX CLI 命令集成
// 在 saasm 主 CLI 中新增 sax 子命令

const std = @import("std");
const Allocator = std.mem.Allocator;

const sax = @import("mod.zig");

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

pub fn executeSaxBuild(
    allocator: Allocator,
    sax_file: []const u8,
    output_dir: ?[]const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    // 读取 .sax 源文件
    const source = std.fs.cwd().readFileAlloc(allocator, sax_file, 16 * 1024 * 1024) catch |err| {
        try stderr.print("error: failed to read {s}: {}\n", .{ sax_file, err });
        return 1;
    };
    defer allocator.free(source);

    // 提取组件名（从文件名）
    const basename = std.fs.path.basename(sax_file);
    const dot_idx = std.mem.lastIndexOfScalar(u8, basename, '.') orelse basename.len;
    const component_name = basename[0..dot_idx];

    // 编译
    var compiler = sax.SaxCompiler.init(allocator);
    const result = compiler.compile(source, component_name) catch |err| {
        try stderr.print("error: SAX compilation failed: {}\n", .{err});
        return 1;
    };
    defer result.saasm_code.deinit();
    defer result.airlock_js.deinit();
    defer result.index_html.deinit();

    // 确定输出目录
    const out_dir = output_dir orelse "dist";
    try std.fs.cwd().makePath(out_dir);

    // 写入 .saasm 中间文件
    const saasm_path = try std.fmt.allocPrint(allocator, "{s}/{s}.saasm", .{ out_dir, component_name });
    defer allocator.free(saasm_path);
    {
        var file = try std.fs.cwd().createFile(saasm_path, .{});
        defer file.close();
        try file.writeAll(result.saasm_code.items);
    }

    // 写入 airlock.js
    const airlock_path = try std.fmt.allocPrint(allocator, "{s}/airlock.js", .{out_dir});
    defer allocator.free(airlock_path);
    {
        var file = try std.fs.cwd().createFile(airlock_path, .{});
        defer file.close();
        try file.writeAll(result.airlock_js.items);
    }

    // 写入 index.html
    const html_path = try std.fmt.allocPrint(allocator, "{s}/index.html", .{out_dir});
    defer allocator.free(html_path);
    {
        var file = try std.fs.cwd().createFile(html_path, .{});
        defer file.close();
        try file.writeAll(result.index_html.items);
    }

    try stdout.print("✓ SAX build successful\n", .{});
    try stdout.print("  .saasm: {s}\n", .{saasm_path});
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
    // 读取 .sax 源文件
    const source = std.fs.cwd().readFileAlloc(allocator, sax_file, 16 * 1024 * 1024) catch |err| {
        try stderr.print("error: failed to read {s}: {}\n", .{ sax_file, err });
        return 1;
    };
    defer allocator.free(source);

    // 提取组件名
    const basename = std.fs.path.basename(sax_file);
    const dot_idx = std.mem.lastIndexOfScalar(u8, basename, '.') orelse basename.len;
    const component_name = basename[0..dot_idx];

    // 编译（仅验证，不产出）
    var compiler = sax.SaxCompiler.init(allocator);
    const result = compiler.compile(source, component_name) catch |err| {
        try stderr.print("error: SAX verification failed: {}\n", .{err});
        return 1;
    };
    defer result.saasm_code.deinit();
    defer result.airlock_js.deinit();
    defer result.index_html.deinit();

    try stdout.print("✓ SAX check passed\n", .{});
    return 0;
}

pub fn executeSaxNew(
    allocator: Allocator,
    project_name: []const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    _ = stderr;

    // 创建项目目录
    try std.fs.cwd().makePath(project_name);

    // 创建 app.sax 模板
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
        \\    count = load count_slot+0 as i64
        \\    count = add count, 1
        \\    store count_slot+0, count as i64
        \\    call @render()
        \\    ret
        \\
        \\  !count
        \\</Component>
    ;

    const sax_path = try std.fmt.allocPrint(allocator, "{s}/app.sax", .{project_name});
    defer allocator.free(sax_path);
    {
        var file = try std.fs.cwd().createFile(sax_path, .{});
        defer file.close();
        try file.writeAll(sax_template);
    }

    // 创建 README.md
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
        var file = try std.fs.cwd().createFile(readme_path, .{});
        defer file.close();
        try file.print(readme_template, .{project_name});
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

    // Phase 2: 实现开发服务器
    try stdout.print("✓ SAX dev server (Phase 2)\n", .{});
    return 0;
}
