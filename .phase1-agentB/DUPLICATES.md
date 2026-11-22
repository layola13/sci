# 重复文件判定（Phase 1 Agent B）

判定方法：逐字节 diff + 引用情况（谁 import 它）+ 内容语义对照。只记录结论，不修复（除已执行的“顶层改 shim”这一模块化动作本身）。

## 1. 已判定：真重复（已处理：规范版留域内，顶层改 shim）

### DUP-1 duration：顶层 `duration.sa/sal` vs `time/duration.sa/sal`
- diff 结果：`.sa` 仅注释措辞不同（顶层“Public Duration facade. Runtime and arithmetic macros live in time.sa.”；
  time/ 版“Duration namespace facade.”）+ import 路径前缀不同（`time.sal` vs `../time.sal`），其余逐行相同。
  `.sal` 同理（顶层“Standard layout aliases for Duration.” vs time/ 版仅一行 import）。
- 引用：顶层 duration.sa 被 tests 1 处 import（`sa_std/time/duration.sa` 形式 1 处）；time/duration.sa 被 time/prelude.sa + tests 1 处 import。
- 判定：**同一 facade 的两份拷贝，规范版 = `time/duration.sa/sal`**（在 time 域内，与 instant 对称，且 time/prelude.sa 已聚合它）。
  顶层已改为 shim（`@import "time/duration.sa"`）。另：`time/duration.sal` 缺尾换行（见 DEFECTS.md D2， cosmetic，未修）。

### DUP-2 instant：顶层 `instant.sa/sal` vs `time/instant.sa/sal`
- 与 DUP-1 完全同构：注释措辞 + 路径前缀不同，其余相同。规范版 = `time/instant.sa/sal`，顶层已改为 shim。

### DUP-3 顶层 `duration.sa` / `instant.sa` 与 `time.sa` 的关系
- 两者本身不含任何宏/定义，只是转发到 time.sa/time.sal；重复的不是实现，而是“入口”。处理同上。

## 2. 已判定：不是重复（曾怀疑，现排除）

### NODUP-1 io.sa 的 BUF_READER_*/BUF_WRITER_* vs `io/buf_reader.sa` / `io/buf_writer.sa`
- 初查时宏清单窗口重叠，曾怀疑 io.sa（925 行）内重复定义了 BUF_* 宏。
- 核实：`grep "^\[MACRO\]" sa_std/io.sa` 共 83 个，无任何 BUF_*；BUF_READER_*（8）只在 `io/buf_reader.sa`，
  BUF_WRITER_*（7）只在 `io/buf_writer.sa`。**无重复**。io.sa 拆分时这 15 个宏未被触碰。

### NODUP-2 `fmt.sa` / `term.sa` / `duration.sa` / `instant.sa`（2–3 行 facade）
- 它们只是 `@import` 两行，不是重复实现；是本仓既有的 facade 模式（prelude 聚合的同类做法），本次沿用该模式建 shim。

### NODUP-3 `io/print.sai` vs `io/io.sai`
- 不是重复文件：print.sai 只声明 `sa_print_bytes`（1 个 @extern）；io.sai 声明全部 16 个 `sa_io_*` + `sa_print_bytes`。
  但两者对 `sa_print_bytes` 的声明逐字相同——这是**符号级重复声明**，见 DEFECTS.md D1（未修）。

### NODUP-4 `fs.sai` 内的 `sa_fs_*` 与 `sa_std_fs_*` 两套 extern
- 不是文件重复，是同一文件内两个命名代际共存（142 行，约 60 个 `sa_fs_*` + 约 60 个 `sa_std_fs_*`）。
  见 DEFECTS.md D4（未修，只记录）。

## 3. 域外发现的重复（不属于本域，只登记，不处理）

### DUP-EXT-1 宏重复定义（全仓扫描发现，HEAD 已存在，本次未引入）
- `ASSERT_TRUE_MSG`：`sa_std/core/rust_patterns.sal` 与 `sa_std/core/sa_core.sa` 各定义一次。
- `CSTR_LEN`：`sa_std/ffi.sa` 与 `sa_std/core/rust_patterns.sal` 各定义一次。
- `FOR_RANGE`：`sa_std/control.sal` 与 `sa_std/core/loop.sa` 各定义一次。
- 核实：上述 5 个文件在本次 git status 中均为干净（未修改），且 `git show HEAD:` 已含这些定义——
  是上游既有问题。是否允许重复宏定义（后定义覆盖？报错？）需 Zig 侧确认，Phase 1 不碰。

## 4. 判定结论汇总

| 组 | 结论 | 处理 |
|---|---|---|
| duration 顶层 vs time/ | 真重复 | 规范版 time/，顶层 shim |
| instant 顶层 vs time/ | 真重复 | 规范版 time/，顶层 shim |
| io.sa BUF_* vs buf_reader/writer | 不是重复 | 无动作 |
| facade 文件（fmt/term/duration/instant） | 不是重复 | 沿用模式 |
| print.sai vs io.sai | 文件不重复；1 个符号重复声明 | 记录 D1，未修 |
| fs.sai 双命名代际 | 文件内两代 API 共存 | 记录 D4，未修 |
| 域外 3 组宏重复定义 | 真重复（HEAD 已有） | 登记，不处理 |
