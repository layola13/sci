# tree_sitter 域边界清单（MANIFEST）

- 域：tree-sitter 代码分析 + tsgosa JS 值薄柄助手
- 位置：`sa_std/tree_sitter/`
- Phase 1 状态：2026-11-22 已整理（分支 `sa-optimize`，工作仓 `sci2-agentS1F`，未 commit）
- 负责人域：F（db + crypto + testing + tree_sitter + 总清单）

## 1. 职责

本域分两组，职责不同，共用一个目录：

**A 组——tree-sitter 核心接口**：解析、语法树、节点导航、查询（query）。

- `tree_sitter.sai`：`sa_ts_*` extern 契约（parser/tree/node/query，dlopen 核心库与文法）。
- `tree_sitter.sla`：查询错误种常量（`SA_TS_QUERY_ERROR_*`）。
- `ts_host.sa` / `ts_host.sai`：JS 宿主探测（`sa_host_is_bun`）。

**B 组——tsgosa JS 值薄柄助手**（tsgosa 转译器的 SA 侧运行时件，为转译生成代码服务）：

- `ts_string.sa`：16 字节 `{ptr,len}` 串柄操作。
- `ts_array.sa`：16 字节薄柄数组操作。
- `ts_jsval.sa`：32 字节 tagged JS 值操作。
- `ts_object.sa`：实例字段匹配写入（`Object.fromEntries` 展开用）。
- `ts_jsx.sa`：JSX 元素描述子。
- `ts_math.sa`：i32 幂等薄整数数学。
- `ts_num.sa`：`Number.prototype.toFixed` 精确格式化。
- `ts_promise.sa`：ReadyFuture 组合子（Promise lowering 用）。
- `ts_unicode.sa` / `ts_unicode.sai`：Unicode 助手。

## 2. 结构

```
sa_std/tree_sitter/
  prelude.sa          # SA 侧公共面（见 §5）
  prelude.sal         # 空文件（域内无 .sal 布局伴生文件；空 prelude.sal 有 encoding/prelude.sal 先例）
  tree_sitter.sai     # A 组：sa_ts_* extern 契约
  tree_sitter.sla     # A 组：查询错误种常量
  ts_host.sa          # A 组：Bun 宿主探测包装
  ts_host.sai         # A 组：sa_host_is_bun extern
  ts_unicode.sa       # B 组
  ts_unicode.sai      # B 组
  ts_array.sa         # B 组
  ts_string.sa        # B 组
  ts_jsval.sa         # B 组
  ts_object.sa        # B 组
  ts_jsx.sa           # B 组
  ts_math.sa          # B 组
  ts_num.sa           # B 组
  ts_promise.sa       # B 组
```

### 模块映射表（旧路径 → 新路径）

| 旧路径 | 新路径 | 大小 | 组 | 说明 |
|---|---|---|---|---|
| `sa_std/tree_sitter.sai` | `tree_sitter/tree_sitter.sai` | 4036 字节 | A | 无 shim（见 §7） |
| `sa_std/tree_sitter.sla` | `tree_sitter/tree_sitter.sla` | 1000 字节 | A | 旧路径留 shim |
| `sa_std/ts_host.sa` | `tree_sitter/ts_host.sa` | 1374 字节 | A | 旧路径留 shim |
| `sa_std/ts_host.sai` | `tree_sitter/ts_host.sai` | 709 字节 | A | 无 shim（见 §7） |
| `sa_std/ts_unicode.sa` | `tree_sitter/ts_unicode.sa` | 2329 字节 | B | 旧路径留 shim |
| `sa_std/ts_unicode.sai` | `tree_sitter/ts_unicode.sai` | 896 字节 | B | 无 shim（见 §7） |
| `sa_std/ts_array.sa` | `tree_sitter/ts_array.sa` | 31468 字节 | B | 旧路径留 shim |
| `sa_std/ts_string.sa` | `tree_sitter/ts_string.sa` | 17219 字节 | B | 旧路径留 shim |
| `sa_std/ts_jsval.sa` | `tree_sitter/ts_jsval.sa` | 8177 字节 | B | 旧路径留 shim |
| `sa_std/ts_object.sa` | `tree_sitter/ts_object.sa` | 3243 字节 | B | 旧路径留 shim |
| `sa_std/ts_jsx.sa` | `tree_sitter/ts_jsx.sa` | 1997 字节 | B | 旧路径留 shim |
| `sa_std/ts_math.sa` | `tree_sitter/ts_math.sa` | 6144 字节 | B | 旧路径留 shim |
| `sa_std/ts_num.sa` | `tree_sitter/ts_num.sa` | 16831 字节 | B | 旧路径留 shim |
| `sa_std/ts_promise.sa` | `tree_sitter/ts_promise.sa` | 3532 字节 | B | 旧路径留 shim |

附带改动（移动必需的路径更新，非修 bug）：

- `tree_sitter/tree_sitter.sla`：`@import "sa_std/tree_sitter.sai"` → `"sa_std/tree_sitter/tree_sitter.sai"`。
- `tree_sitter/ts_string.sa`：`@import "string.sai"` → `"../string.sai"`，`@import "fmt.sai"` → `"../fmt.sai"`（`ts_array.sa` 同目录，不变）。
- 其余 B 组文件无 import 或只 import 同目录文件（`ts_jsval.sa` → `ts_string.sa`、`ts_object.sa` → `ts_string.sa`、`ts_host.sa` → `ts_host.sai`、`ts_unicode.sa` → `ts_unicode.sai`），无需改动。

## 3. 依赖方向

域内依赖（单向，无环）：

| 文件 | 依赖 | 说明 |
|---|---|---|
| `ts_jsval.sa` | `ts_string.sa` | jsval 判等经串内容判等；不触 `ts_array` |
| `ts_object.sa` | `ts_string.sa` | 字段名匹配经 `@ts_str_equals` |
| `ts_string.sa` | `../string.sai`、`ts_array.sa`、`../fmt.sai` | 串柄 + 切片 |
| `ts_host.sa` | `ts_host.sai` | 仅本域 |
| `ts_unicode.sa` | `ts_unicode.sai` | 仅本域 |
| 其余 B 组文件 | 无 | `ts_array`、`ts_jsx`、`ts_math`、`ts_num`、`ts_promise` 无 import |
| `tree_sitter.sai` / `.sla` | （`.sla` import 本域 `.sai`） | 仅本域 |

域外依赖：`string.sai`、`fmt.sai`（顶层，未移动；属 string/fmt 域）。禁止依赖 io、net、http、db、crypto。

## 4. Zig 宿主侧（只记录，不动 `src/`）

- `tree_sitter.sai` 的 extern 由 `src/runtime/sa_tree_sitter*.zig` 实现（`sa_tree_sitter.zig`、`sa_tree_sitter_node.zig`、`sa_tree_sitter_query.zig`）；核心库与文法运行时 dlopen，缺失时 `sa_ts_available()` 返回 0、解析失败状态 8（见 `.sai` 头注释）。
- `ts_host.sai` 的 `sa_host_is_bun`：native 实现恒返 0（无 JS 宿主是契约本身）；JS 目标由 `emit_js.zig` 的 shim 实现 `typeof Bun !== "undefined"` 判定。
- 核查结论：`src/` 与 `build.zig` 中没有按文件路径硬编码引用上述 `.sai`/`.sla` 的地方；extern 按符号名链接。因此移动文件不要求 Zig 侧改名。**但 Phase 2 必须构建验证**（新子目录能被编译器找到）。

## 5. Prelude 与公共面

- `tree_sitter/prelude.sa` 聚合 SA 侧公共面：`tree_sitter.sai`、`ts_host.sa`、`ts_unicode.sa`、`ts_array.sa`、`ts_string.sa`、`ts_jsval.sa`、`ts_object.sa`、`ts_jsx.sa`、`ts_math.sa`、`ts_num.sa`、`ts_promise.sa`（相对路径 `@import` 聚合，沿用既有 prelude 模式）。
- `tree_sitter/prelude.sal`：空文件（域内无 `.sal` 文件）。
- `tree_sitter.sla`（查询错误种常量）**不进 `prelude.sa`**：全仓零个 `.sa` 文件 import `.sla` 文件，且不存在 `prelude.sla` 先例，按完整新路径单独 import。
- 顶层 `sa_std/prelude.sa` 未改动（本域此前不在顶层门面内）。是否纳入顶层门面，是 Phase 2 决策。

## 6. 兼容策略

- 旧路径留薄 shim（2 行：注释 + `@import`），沿用仓内既有模式。shim 清单：`tree_sitter.sla`、`ts_host.sa`、`ts_unicode.sa`、`ts_array.sa`、`ts_string.sa`、`ts_jsval.sa`、`ts_object.sa`、`ts_jsx.sa`、`ts_math.sa`、`ts_num.sa`、`ts_promise.sa`。
- **`.sai` 文件无 shim**：全仓核查，零个 `.sai` 文件包含 `@import`，`.sai` shim 未经验证，不造先例。`.sai` 的 import 方全部可控：
  - `tree_sitter.sai`：仅 `tree_sitter/tree_sitter.sla` import（已同步更新）。
  - `ts_host.sai`：仅 `tree_sitter/ts_host.sa` import（同目录移动，无需更新）。
  - `ts_unicode.sai`：仅 `tree_sitter/ts_unicode.sa` import（同目录移动，无需更新）。
- 引用方核查（`@import` 全仓扫描，排除 `.zig-cache`）：`tests/ts_query_error_constants.sla` import `tree_sitter.sla`（经 shim 兼容），未动 `tests/`；`demos/*/335_ts_slice_inverted_bounds/main.sa` import `sa_std/ts_string.sa`（经 shim 兼容），未动 `demos/`。

## 7. 发现的问题（未修复，仅记录）

1. **B 组 4 个文件全仓零个 SA 侧 import 方**：`ts_jsx.sa`、`ts_math.sa`、`ts_num.sa`、`ts_promise.sa` 在 `sa_std/`、`tests/`、`demos/`、`src/` 中均无 import 引用。按文件头注释，它们是 tsgosa 转译器生成代码的运行时件（仓外消费方），现状属“仓外消费、无仓内引用”，不是孤儿文件误删的依据；但建议 Phase 2 由 tree_sitter 域确认一次：是否应有仓内 smoke 引用以防静默失修。
2. **A/B 两组职责不同却同处一域**：A 组是通用代码分析接口，B 组是 tsgosa 专用的 JS 值助手。Phase 2 可考虑 `tree_sitter/` 下分 `core/`（A 组）与 `jsval/`（B 组）子目录；Phase 1 只把顶层文件收进同一域，不再细分。
3. `ts_host.sa` 头注释记载：tsgosa 发射器 v1 未接线该助手（`seed_source folded_only_refuse_otherwise`），包装先行存在供未来接线。属已知状态。
4. `ts_string.sa` 头注释记载：`substring` 另交换逆序界、`substr` 下溢 quirk 原样保留（与 JS 语义对齐的刻意保留）。属已知契约，非 bug。
