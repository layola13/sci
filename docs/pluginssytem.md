# 可插拔插件系统实施计划（详尽版）

## 背景与动机
目前，`src/cli.zig` 是一个庞大的、单体式的命令分发器。它硬编码了一个 `Command` 枚举，并使用一个巨大的 `switch (cmd)` 语句来将执行路由到 `sax`、`db`、`llvm2sa` 等子模块以及包管理 (`fetch`) 等功能。这种结构导致如果不修改核心的 CLI 逻辑就很难添加新功能，违反了开闭原则（Open-Closed Principle）。

我们需要一个灵活的、基于 `comptime`（编译时）的静态注册表，允许各个模块完全自包含。这些模块必须能够挂载（hook）到命令解析器以及全局的 CLI 生命周期事件中（例如：`init` 初始化、`prebuild` 构建前、`postbuild` 构建后）。

## 范围与影响
- **受影响的文件:** `src/cli.zig`, `src/sax/cli.zig` (及其新建的 `plugin.zig`), `src/db/mod.zig` (及其新建的 `plugin.zig`), `src/llvm2sa.zig` (及其新建的 `plugin.zig`), `src/pkg/fetch.zig` (及其新建的 `plugin.zig`).
- **新建文件:** `src/plugin.zig` (接口定义), `src/plugins.zig` (注册表).
- **核心 CLI 执行逻辑 (`sci build/run/etc.`):** 逻辑本身保持不变，但在其执行前后包裹了 `prebuild` 和 `postbuild` 钩子的分发逻辑。
- **自定义命令 (`sci sax`, `sci db`, `sci llvm2sa`, `sci fetch`):** 完全委托给具体的插件模块处理。`Command` 枚举将不再包含 `.sax`, `.db`, `.llvm2sa`, `.fetch` 等。

## 拟定架构方案

### 1. `src/plugin.zig` - 核心接口
定义 `Context`（上下文）和 `Plugin`（插件）结构体。

```zig
const std = @import("std");
const cli = @import("cli.zig");

// 由于我们想向插件传递 Writer 等上下文，我们需要确保类型匹配。
// 为了简化和灵活性，我们在 Context 中保存 allocator，插件内部如果需要可以获取自己的 Writer。
pub const Context = struct {
    allocator: std.mem.Allocator,
    // 可以在这里扩展更多全局状态
};

pub const Plugin = struct {
    name: []const u8,
    
    /// 全局初始化，在 CLI 启动时最早调用。
    init: ?*const fn (ctx: *Context) anyerror!void = null,
    
    /// 在核心 CLI 命令（build, run, test 等）执行之前调用。
    prebuild: ?*const fn (ctx: *Context, options: *cli.CompileOptions) anyerror!void = null,
    
    /// 在核心 CLI 命令成功执行完毕后调用。
    postbuild: ?*const fn (ctx: *Context) anyerror!void = null,
    
    /// 尝试处理自定义命令行。
    /// 如果插件认领了该命令（例如遇到了 "sax"），则执行并返回 `true`，此时核心执行将停止。
    /// 如果它不认识该命令，返回 `false`，将其留给下一个插件或核心解析器。
    executeCommand: ?*const fn (ctx: *Context, argv: []const []const u8) anyerror!bool = null,
};
```

### 2. `src/plugins.zig` - 编译时注册表与独立编译机制
这是在编译时注册所有插件的中心枢纽。结合 Zig 的构建系统 (`build.zig`) 和 `build_options`，我们可以实现**独立编译与按需启用**。这意味着如果某个插件代码损坏，它不会影响主线（main）`sci` 的编译。

```zig
const plugin = @import("plugin.zig");
const build_options = @import("build_options");

// 仅在 build_options 启用了对应插件时才引入它
const sax_plugin = if (build_options.enable_plugin_sax) @import("sax/plugin.zig") else null;
const db_plugin = if (build_options.enable_plugin_db) @import("db/plugin.zig") else null;
const llvm2sa_plugin = if (build_options.enable_plugin_llvm2sa) @import("llvm2sa_plugin.zig") else null;
const package_plugin = if (build_options.enable_plugin_package) @import("pkg/plugin.zig") else null;

// 在编译时动态构建激活的插件数组
pub const active_plugins = blk: {
    var count = 0;
    if (sax_plugin != null) count += 1;
    if (db_plugin != null) count += 1;
    if (llvm2sa_plugin != null) count += 1;
    if (package_plugin != null) count += 1;
    
    var arr: [count]plugin.Plugin = undefined;
    var i = 0;
    
    if (sax_plugin) |p| { arr[i] = p.plugin; i += 1; }
    if (db_plugin) |p| { arr[i] = p.plugin; i += 1; }
    if (llvm2sa_plugin) |p| { arr[i] = p.plugin; i += 1; }
    if (package_plugin) |p| { arr[i] = p.plugin; i += 1; }
    
    break :blk arr;
};
```
在 `build.zig` 中，我们可以为每个插件提供独立的构建选项和单独的测试步骤（如 `zig build test-sax`），确保它们各自拥有**独立的编译系统，完全不影响 main 主线**。

### 3. 重构 `src/cli.zig` 的生命周期钩子集成

**在 `executeWithWriters` 中注入钩子分发器:**

```zig
// 在 src/cli.zig 中, fn executeWithWriters(...) 内部

const plugin = @import("plugin.zig");
const plugins = @import("plugins.zig");

var ctx = plugin.Context{ .allocator = allocator };

// 1. 执行 Init 钩子
inline for (plugins.active_plugins) |p| {
    if (p.init) |init_fn| try init_fn(&ctx);
}

// 2. 插件命令分发器
// 赋予插件拦截参数的首要机会，在核心解析器执行之前。
if (argv.len > 1) {
    inline for (plugins.active_plugins) |p| {
        if (p.executeCommand) |exec_fn| {
            if (try exec_fn(&ctx, argv)) {
                return 0; // 插件成功处理并接管了执行流程
            }
        }
    }
}

// ... 这里保留现有的参数解析逻辑，以确定 `cmd: Command` ...
// ... 以及提取 `compile_options` 等 ...

// 3. 执行 Prebuild 钩子
inline for (plugins.active_plugins) |p| {
    if (p.prebuild) |pre_fn| try pre_fn(&ctx, &compile_options);
}

// ... 保留现有的 switch (cmd) 用于处理核心命令 (build, run, 等) ...

// 4. 执行 Postbuild 钩子
inline for (plugins.active_plugins) |p| {
    if (p.postbuild) |post_fn| try post_fn(&ctx);
}

return 0;
```

## 详细实施步骤 (拆分旧实现 -> 做成新插件)

### 阶段 1：建立核心系统与构建支持
1. **更新构建系统 (`build.zig`):** 
   - 增加四个自定义构建选项：`enable_plugin_package`, `enable_plugin_db`, `enable_plugin_sax`, `enable_plugin_llvm2sa`（通常默认开启）。
   - 为这四个模块配置独立的测试子步骤（例如 `test-sax`, `test-db`），确保独立的编译机制可以剥离开主线。
2. **定义核心接口:** 创建 `src/plugin.zig` 定义 `Context` 与 `Plugin` 接口，并创建 `src/plugins.zig` 按照上述方案动态构建注册表。

### 阶段 2：逐步拆分与提取具体的插件模块
我们将会把目前深耦合在 `src/cli.zig` 中的硬编码命令分支一一拆离。

1. **Package 插件 (`package`)**
   - **创建:** 在处理包管理命令的目录下（例如 `src/pkg/`）新建 `plugin.zig` 包装器。
   - **拆分开步骤:** 找到原 `src/cli.zig` 中解析 `fetch` 或任何依赖项拉取命令的地方。将其移出。
   - **做成新插件:** 把逻辑放入 `executeCommand` 中（即：遇到 `"fetch"` 时调用原有的执行逻辑并返回 `true`）。清理核心 CLI 中的 `.fetch` 枚举及相关 switch 分支。
2. **Database 插件 (`database`)**
   - **创建:** 在 `src/db/` 目录下新建 `plugin.zig`。
   - **拆分开步骤:** 从 `src/cli.zig` 定位硬编码遇到 `db` 的部分。
   - **做成新插件:** 将其包裹并委托到 `db` 插件的 `executeCommand` 中。在 `Command` 中移除 `.db`。
3. **SAX 插件 (`sax`)**
   - **创建:** 在 `src/sax/` 目录下新建 `plugin.zig`。
   - **拆分开步骤:** 找到原本分发给 `sax_cli.execute(...)` 的代码。
   - **做成新插件:** 将这些控制权转移给插件模块。从全局 Command 中删除 `.sax` 分支及相关的 `std.mem.eql(u8, argv[1], "sax")` 检测。
4. **LLVM2SA 插件 (`llvm2sa`)**
   - **创建:** 新建 `src/llvm2sa_plugin.zig`（或视后续整理放入专有文件夹）。
   - **拆分开步骤:** 剥离对 `.llvm2sa` 的全局调用解析。
   - **做成新插件:** 转移进 `executeCommand`。将其移出核心 `cli.zig` 中。

### 阶段 3：生命周期钩子集成与全面验证
1. **注入生命周期:** 在 `cli.executeWithWriters` 主入口处将上面规划的钩子循环 (`init`, 命令接管分发, `prebuild`, `postbuild`) 完整引入。
2. **解决依赖:** 此时如果存在插件内部调用被剥离前的函数引起了循环依赖，逐一排查解决。
3. **全面验证:** 
   - 验证独立测试：`zig build test-package`, `zig build test-sax` 等。
   - 验证主线测试：`zig build test`。
   - 行为一致性校验：手工执行 `sci sax`, `sci db`, `sci fetch`, `sci llvm2sa`，确保使用体验毫无破坏。