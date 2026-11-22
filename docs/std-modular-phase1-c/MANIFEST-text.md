# 模块边界清单 — text 域

## 公共模块（Phase 1 零移动）

| 模块 | 内容 | 行数 | 公共入口 |
|---|---|---|---|
| `text/regex.sa` | 仅 2 行：`@import "regex.sal"` + `@import "regex.sai"`（无 SA 实现） | 2 | `text/prelude.sa` |
| `text/regex.sai` | `sa_regex_*` extern 声明（Zig 侧实现，u64 句柄约定） | 76 | 同胞自动注入 + 直接导入（`regex.sla`、`tests/regex_cflags_constants.sla`） |
| `text/regex.sal` | `SA_REGEX_*` 常量与 `REG_*` 错误码 | 33 | 同胞自动注入 |
| `text/regex.sla` | SLA 层 regex 包装（`sa_std/text/regex.sai`） | 23 | 直接导入 |
| `text/prelude.sa` | 聚合 `regex.sa`（1 行，无尾换行） | 1 | `sa_std/prelude.sa` |
| `text/prelude.sal` | `@import "../core/slice.sal"`（1 行，无尾换行） | 1 | `sa_std/prelude.sal` |

## 职责

- 正则表达式：编译、匹配、分组、全局迭代/替换/切分。实现在 Zig 宿主侧（`src/runtime/` 的 regex 模块），SA 侧只有 extern 声明 + 布局常量 + SLA 薄包装。
- text 域目前只有一个成员（regex）。未来的文本处理模块（如 unicode 分段、文本搜索）归入本域，不入 string 域。

## 允许的依赖方向

- ✅ `core/*`（`core/slice.sal`，经 `text/prelude.sal`）。
- ✅ Zig 宿主 extern（`sa_regex_*`，经 `regex.sai`）。
- ❌ 禁止：`io`、`net`、`db`、`http`、`ffi` 实现、`collections`（regex 不得依赖容器实现）、`string`（不得反向依赖 `string.sa`）。
- 注：regex 的文本输入是 `(ptr, len)` 字节对，不取 `String` 类型——这是 text 与 string 的边界：text 处理字节/切片，string 拥有字符串类型。

## 缺陷登记

- DEF-07：`regex.sa` 是 2 行 stub，无 SA 实现；regex 能力完全由 Zig 侧提供，SA 侧无可移植实现。
