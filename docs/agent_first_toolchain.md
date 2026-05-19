# Agent-First Toolchain (AI 优先的编译器工具链)

借用 `zero` 项目的先进理念，传统的编译器 CLI 设计主要是为了“人”看（彩色控制台、带波浪线的代码提示），而在 AI 编程时代，编译器的主力用户将变成 Agent。为此，`sci` (SA Compiler) 需要进行深度的 Agent-First 架构升级。

**核心定位：这是 `sci` 编译器主线的核心基础设施，绝对不是一个独立的插件。** 
所有的基础命令（`explain`, `fix`, `skills`）、全局的 JSON 结构化输出能力，都将直接实现在 `src/cli.zig` 和 `src/common/trap.zig` 中。插件（Plugin）系统的作用仅仅是**向这个核心基础设施注册自己特有的文档和能力**，以便主线能够统一调度和输出。

目标：**将 `sci` 打造为第一个原生对 Agent 友好的底层语言编译器。** 让 Agent 能够完全基于 CLI 输出进行自我学习、精准修复和图谱推理，消除“看终端报错 -> 猜原因 -> 瞎改”的幻觉循环 (Hallucination Loop)。

---

## 1. 结构化与确定性的诊断 (Structured JSON Diagnostics)

传统报错对于正则提取极其不友好，需要引入全局的 `--json` 标志。

### 1.1 稳定错误码与 JSON 输出
重构 `src/common/trap.zig` 和 `src/cli.zig` 的报错系统：
*   **分配稳定错误码 (Stable Codes)**：将原来的 `DuplicateDef`、`InvalidAtomicOrdering` 映射为稳定的错误码，例如 `SA-FLAT-001` (展开器错误)、`SA-REF-042` (语义验证错误)。
*   **执行 `sci build --json`**：将原本的彩色标准错误流（Stderr）输出转化为机器可读的 JSON 数组。

**JSON 数据模型：**
```json
{
  "diagnostics": [
    {
      "code": "SA-REF-010",
      "severity": "error",
      "message": "RegisterRedefinition: register %x is already defined.",
      "location": { "file": "src/main.saasm", "line": 45, "column": 4 },
      "repair": {
        "action": "rename",
        "hint": "Try using a fresh register name, e.g., %x_1.",
        "confidence": "high"
      }
    }
  ]
}
```

## 2. Agent 交互子命令 (Agent-Facing Commands)

引入专门给 Agent 调用的排障与学习命令：

### 2.1 `sci explain <code>` (知识直达)
当 Agent 遇到 `SA-REF-010` 错误时，无须搜索外部文档，直接调用：
`sci explain SA-REF-010`
输出该错误的触发原理、内存语义和正确用法的代码片段。让 Agent 实时学习，而非依赖其过期的预训练语料。

### 2.2 `sci fix --plan --json` (机器可读的修复计划)
当编译器能够推断出明确的修复路径（如拼写错误、缺少导出、签名不匹配）时，不自动改代码，而是向 Agent 提供“修补计划”。
输出 `diff` 或 JSON Patch，Agent 读取后可以选择应用。

### 2.3 `sci skills` (自解释的动态能力说明)
对于 `zero` 里的 `zero skills get zero --full`，在 `sci` 中意义更加重大：
由于我们的 `sci` 引入了**可插拔插件系统 (Plugin System)**（比如 `database`, `sax`, `package` 插件），CLI 的能力是动态组合的。
`sci skills` 命令将：
1. 遍历当前启用的所有 Plugin。
2. 聚合它们的 EBNF 语法、宏说明、内置原语和 API 契约。
3. 动态生成一份完整的 Markdown/JSON 指导文档直接吐给 Agent。
*效果：Agent 接手任何一个定制版本的 `sci` 编译器，只需一句 `sci skills`，就能获得完全对齐当前版本的“开发手册”，杜绝幻觉。*

## 3. 分析与图谱导出 (Graph & Inspection)

Agent 往往需要全知视角的 codebase 图谱才能做出架构级别的决定。

### 3.1 扩展现有的 Layout 功能
现有的 `sci layout` 将升级支持 `sci layout --json`，精确输出各结构的偏移量计算结果。

### 3.2 `sci graph --json`
分析整个 `sa.pkg` 的 import 依赖树、函数调用图 (Call Graph)，以 JSON 节点与边的形式输出。Agent 可借此精确判断某个修改的爆炸半径（Blast Radius）。
### 3.3 `sci size --json`
在编译后提供精确到函数的指令/字节对齐体积报告，方便 Agent 进行代码瘦身优化。

---

## 4. 与现有 Plugin 系统的整合设计

在刚设计的 `plugin.zig` 接口中，增加对 Agent-First 范式的支持：

```zig
pub const Plugin = struct {
    name: []const u8,
    // ... 原有的 init, executeCommand 等 ...

    /// 当用户调用 `sci skills` 时，插件需要注入自己的文档或能力描述
    exportSkills: ?*const fn (allocator: std.mem.Allocator) anyerror![]const u8 = null,

    /// 插件内部如果抛出错误，提供将内部错误转化为带 Code 的 Diagnostic 对象的钩子
    formatDiagnostic: ?*const fn (err: anyerror) ?Diagnostic = null,
};
```

## 实施建议

1.  **第一步 (Low Hanging Fruit)**：优先改造 `trap.zig`，为现有的约 30 种报错增加稳定的 `SA-XXX-NNN` 错误码，并实现 `sci build --json`。这是 Agent 编程中最立竿见影的改动。
2.  **第二步**：实现 `sci explain`。我们可以把 `docs/errorcode.md` 里的描述内置到可执行文件的大字典里。
3.  **第三步**：结合插件系统实现 `sci skills`，让各个独立模块自述其职。