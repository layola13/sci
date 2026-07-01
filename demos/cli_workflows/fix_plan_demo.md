# `sa fix [--plan] <code>` — 修复计划

## 用途

当编译器能够推断出明确的修复路径时，`sa fix` 向 Agent 输出一个机器可读的修复计划。Agent 读取后可以选择应用。

**设计原则**：编译器不自动修改代码，只提供修补计划（`diff` 或 JSON Patch）。

## 命令签名

```
sa fix <code>
sa fix --plan <code>
sa fix --plan --json <code>
```

## 参数

| 参数 | 说明 |
|---|---|
| `<code>` | 错误码名称或 Trap 类型名 |
| `--plan` | 打印确定性修复计划（必选标志） |
| `--json` | 以 JSON 格式输出修复计划 |

**注意**：`--plan` 目前是显式标志（非默认）。`fix` 命令可能需要版本化增强后支持 `replan`、`apply` 等子命令。

## 示例

### 文本模式

```bash
$ sa fix --plan ForbiddenSyntax
code: ForbiddenSyntax
rationale: The flattener rejects structured syntax before semantic verification.
rationale: Agent-side patching should preserve the original semantics while removing unsupported surface forms.
plan: rewrite control-flow - lower braces and keywords into labels, br, and jmp
plan: re-run flattener - verify that the line stream no longer contains forbidden syntax
```

### JSON 模式

```bash
$ sa fix --plan --json ImportResolutionFailed
{"status":"ok","fix":{"code":"ImportResolutionFailed","plan":[{"action":"pin","target":"package-ref","detail":"choose a single version or local path and record it in the manifest"},{"action":"retry","target":"resolver","detail":"re-run the import resolution against the pinned source"}],"rationale":["The resolver needs one concrete source artifact, not an ambiguous graph.","The current CLI fallback already treats invalid import data as a structured trap."]}}
```

## 已知修复计划

| 错误码 | 步骤数 | 典型动作 |
|---|---|---|
| `ForbiddenSyntax` | 2 | rewrite → re-run |
| `ImportResolutionFailed` | 2 | pin → retry |
| `SA-CLI-001` | 2 | add positional-argument → retry |

## 错误处理

```
$ sa fix --plan NONEXISTENT
unknown code: NONEXISTENT
exit code: 1
```
