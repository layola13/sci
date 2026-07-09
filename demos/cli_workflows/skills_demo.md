# `sa skills [--json]` — 编译器能力自描述

## 用途

`sa skills` 遍历当前启用的所有插件，聚合它们在独立工程中导出的能力描述，动态生成一份完整的文档直接输出给 Agent。

**效果**：Agent 接手任何一个定制版本的 `sci` 编译器，只需一句 `sa skills`，就能获得完全对齐当前版本的"开发手册"，杜绝幻觉。

## 命令签名

```
sa skills
sa skills --json
```

## 参数

| 参数 | 说明 |
|---|---|
| `--json` | 以 JSON 格式输出能力清单（只输出，不写文件） |

## 文本模式行为

文本模式下，`sa skills` 除了打印到 stdout，还会刷新当前工作目录下的 Agent skill 文件：

| 路径 | 内容 |
|---|---|
| `.codex/skills/sa/SKILL.md` | 基础编译/测试命令、`sa_std` 文件清单、宏清单、@extern/@export 清单 |
| `.claude/skills/sa/SKILL.md` | 同上（Claude 同步副本） |
| `.codex/skills/sa_plugins/SKILL.md` | 常用官方插件可选目录索引 |
| `.claude/skills/sa_plugins/SKILL.md` | 同上 |

插件 skill 只提示能力、接口文件和安装命令，不假设插件已安装。使用前仍需通过 `sa plugin list` 或 `sa skills --json` 确认当前环境已启用。

## 示例

### 文本模式（stdout 输出示例）

```
$ sa skills
=== SA Compiler Skills ===

  build          Compile .sa source to native executable
  build-wasm     Compile .sa source to WebAssembly module
  build-obj      Build object file from .sa source
  run            Compile and execute .sa source
  test           Run @test blocks
  bc2sa          Translate LLVM bitcode to SA assembly
  layout         Compute struct layout information
  size           Print function-size statistics
  graph          Output dependency/call graph
  explain        Explain a diagnostic error code
  fix            Suggest fixes for diagnostics

=== Plugin Skills ===

  sax            SAX frontend framework
                 -> sa plugin install <path-to-sap.json>
                 Interfaces: sax/sax*.sai, sax/sax*.sal

  pkg            Package management
                 -> sa plugin install <path-to-sap.json>
                 Interfaces: pkg/*.sal

  deno           Deno runtime integration
                 -> sa plugin install <path-to-sap.json>
                 Interfaces: deno.sai, deno.sal

=== Generated Skills ===
  Written .codex/skills/sa/SKILL.md
  Written .claude/skills/sa/SKILL.md
```

### JSON 模式

```bash
$ sa skills --json
{"status":"ok","skills":{"compiler":{"commands":[{"name":"build","summary":"Compile .sa source to native executable"},{"name":"build-wasm","summary":"Compile .sa source to WebAssembly module"},{"name":"build-obj","summary":"Build object file from .sa source"},{"name":"run","summary":"Compile and execute .sa source"},{"name":"test","summary":"Run @test blocks"},{"name":"bc2sa","summary":"Translate LLVM bitcode to SA assembly"},{"name":"layout","summary":"Compute struct layout information"},{"name":"size","summary":"Print function-size statistics"},{"name":"graph","summary":"Output dependency/call graph"},{"name":"explain","summary":"Explain a diagnostic error code"},{"name":"fix","summary":"Suggest fixes for diagnostics"}]},"plugins":[{"name":"sax","summary":"SAX frontend framework","install":"sa plugin install <path-to-sap.json>","interfaces":["sax/sax*.sai","sax/sax*.sal"]},{"name":"pkg","summary":"Package management","install":"sa plugin install <path-to-sap.json>","interfaces":["pkg/*.sal"]},{"name":"deno","summary":"Deno runtime integration","install":"sa plugin install <path-to-sap.json>","interfaces":["deno.sai","deno.sal"]}]}}
```

## Agent 使用模式

```bash
# Agent 第一次接手项目时
$ sa skills

# 安装新插件后确认能力
$ sa plugin install ~/projects/sa_plugins/sa_plugin_sax/sap.json
$ sa skills --json | jq '.plugins[].name'
"sax"

# 确认插件可用后编写代码
# Agent 现在知道 sax/*.sai 接口的存在
```
