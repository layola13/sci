# testing 域边界清单（MANIFEST）

- 域：测试支持（test support：断言、mock IO）
- 位置：`sa_std/testing/`
- Phase 1 状态：2026-11-22 已确认——本域早已是独立子目录，**本次零移动**，只补边界清单
- 负责人域：F（db + crypto + testing + tree_sitter + 总清单）

## 1. 职责

本域提供 SA 程序内测试与测试替身：

- 断言 extern 声明（`assert.sai`）。
- Mock IO 门面（`mock_io.sa` + `mock_io.sal`）：内存缓冲读写替身，供测试替身用。

本域不提供：测试运行器、测试发现、用例注册（均无文件；`tests/unit_framework/` 下的夹具与框架属 `tests/`，不在 `sa_std` 内，Phase 1 不动）。

## 2. 结构

```
sa_std/testing/
  prelude.sa          # @import "assert.sai"、@import "mock_io.sa"
  prelude.sal         # @import "mock_io.sal"
  assert.sai          # 断言 extern：sa_assert_eq_i64[_at]、sa_test_debug_i64、sa_test_fallible_i32_value
  mock_io.sa          # MockIo 门面：sa_mock_io_init/rewind/len/…（@export）
  mock_io.sal         # MockIo 布局：MockIo_SIZE=32，buf/cap/len/pos
```

### 模块映射表

| 旧路径 | 新路径 | 说明 |
|---|---|---|
| — | — | 无移动。`testing/` 在 Phase 1 开始前已是独立子目录，5 个文件原地不动。 |

## 3. 依赖方向

本域**零 SA 侧依赖**：`mock_io.sa` 只 import 同目录 `mock_io.sal`；`assert.sai` 无 import；`mock_io.sal` 无 import。

被依赖方：

- `tests/unit_framework/std_testing_prelude_import_surface.sa` import `sa_std/testing/prelude.sa`（并验证 mock 读写 2/2 通过，见 `docs/progress.md`）。
- `tests/unit_framework/std_*_macro_surface.sa` 等夹具 import `testing/assert.sai`（断言面）。

禁止依赖：本域不得依赖 io（mock 是 io 的替身，反向依赖会成环）、不得依赖 task/sync。

## 4. Zig 宿主侧（只记录，不动 `src/`）

- `assert.sai` 的 extern 由 `src/runtime/sa_std.zig`、`src/runtime/sa_std/test_debug.zig`、`src/runtime/sa_std.h` 实现（符号名链接，不按文件路径）。
- `mock_io` 是纯 SA 门面，`src/` 中无对应实现。

## 5. Prelude 与公共面

- `testing/prelude.sa` / `prelude.sal` 已存在，沿用。
- 顶层 `sa_std/prelude.sa` / `prelude.sal` **未纳入** `testing/prelude.sa`（现状如此，Phase 1 不改）。是否纳入顶层门面，是 Phase 2 决策。

## 6. 发现的问题（未修复，仅记录）

1. `mock_io` 全仓除 prelude 与一处 surface 测试外，无其他 SA 侧 import 方。属“有实现、少调用”状态；是否应扩大仓内使用，由 testing 域后续决定；不是 bug。
2. 本域没有测试运行器/发现机制：`tests/unit_framework/` 的框架与 `sa_std/testing/` 的断言面之间无显式归属说明。属文档缺口，登记。
3. `assert.sai` 只有 i64 断言与一个 `i32!` fallible 探针（`sa_test_fallible_i32_value`），断言面偏窄。属能力缺口，不在 Phase 1 扩充。
