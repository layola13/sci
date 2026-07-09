# `sa explain <code>` — 错误码解释

## 用途

当编译器输出一个错误码（如 `SA-REF-010` 或 `ForbiddenSyntax`）时，调用 `sa explain` 获取该错误的触发原理、内存语义和修复建议。Agent 无需搜索外部文档即可实时学习。

## 命令签名

```
sa explain <code>
sa explain <code> --json
```

## 参数

| 参数 | 说明 |
|---|---|
| `<code>` | 错误码名称（如 `SA-REF-010`）或 Trap 类型名（如 `ForbiddenSyntax`） |
| `--json` | 以 JSON 格式输出解释内容 |

## 示例

### 文本模式

```bash
$ sa explain SA-REF-010
code: SA-REF-010
aliases: RegisterRedefinition
title: Live register re-bound
summary: A register that is still live cannot be assigned a second time without an explicit move or release.
detail: The referee checks register ownership and capability masks on every instruction.
detail: Rebinding a live register without consuming the previous value violates the linear ownership model.
fix: Rename the destination register or release/move the old value first.
```

### JSON 模式

```bash
$ sa explain SA-REF-010 --json
{"status":"ok","explain":{"codes":["RegisterRedefinition","SA-REF-010"],"title":"Live register re-bound","summary":"A register that is still live cannot be assigned a second time without an explicit move or release.","details":["The referee checks register ownership and capability masks on every instruction.","Rebinding a live register without consuming the previous value violates the linear ownership model."],"fix_hint":"Rename the destination register or release/move the old value first."}}
```

### 已知错误码

| 代码 | 别名 | 域 |
|---|---|---|
| `SA-FLAT-001` | `ForbiddenSyntax` | Flattener — 拒绝非法的表层语法 |
| `SA-FLAT-050` | `ImportResolutionFailed` | Flattener — 导入解析失败 |
| `SA-REF-010` | `RegisterRedefinition` | Referee — 寄存器重复绑定 |
| `SA-REF-011` | `UnknownRegister` | Referee — 寄存器未定义 |
| `SA-CLI-001` | — | CLI — 缺少必需的操作数 |
| `SA-CLI-002` | — | CLI — 缺少 -o 输出路径 |
| `SA-CLI-012` | — | CLI — 不支持的位码输入 |
| `SA-CLI-016` | — | CLI — llvm-dis 未找到 |

完整错误码目录见 `docs/errorcode.md`。

## 错误处理

```
$ sa explain NONEXISTENT
unknown code: NONEXISTENT
exit code: 1
```

## 典型 Agent 工作流

```bash
# 1. 尝试构建
$ sa build demo.sa --json
{"status":"error","diagnostics":[{"code":"SA-REF-010",...}]}

# 2. 查询错误含义
$ sa explain SA-REF-010

# 3. 根据 fix hint 修复后重新构建
$ sa build demo.sa --json
{"status":"ok","metrics":{"compile_tokens":412,"instruction_count":86}}
```
