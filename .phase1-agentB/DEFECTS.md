# 发现的缺陷清单（未修，Phase 1 只记录）

用户亲令：模块化完成前不修 bug、不跑测试。以下全部只记录文件与行号/描述，未动手改。
行号以重组后路径为准（旧路径见括号）。

## D1 重复 @extern 声明：`sa_print_bytes`（符号级重复）
- `sa_std/io/io.sai:29`（旧 `sa_std/io.sai:29`）与 `sa_std/io/print/print.sai:3`（旧 `sa_std/io/print.sai:3`）
  逐字相同的声明：`@extern sa_print_bytes(&msg: ptr, len: u64) -> void`。
- 影响：同时 import 两者（经 prelude.sa/prelude.sal 就会同时引入）的程序会得到两次同一声明。
  当前能工作说明 loader 容忍重复 @extern（或去重），但属于契约分裂：print 的唯一 extern 不应同时住在 io.sai 里。
  建议（后续阶段）：从 io.sai 删掉该行，只留 print.sai；改前须确认有无程序只 import io.sai 就用 PRINT 宏。
  未修原因：删声明是语义改动，需构建验证。

## D2 `time/duration.sal` 缺尾换行（cosmetic）
- `sa_std/time/duration.sal`（1 行）文件末尾无 `\n`（diff 显示 `\ No newline at end of file`）；
  同目录 `time/instant.sal` 同样缺尾换行；顶层旧 shim 有尾换行。
- 未修：纯格式问题，等后续统一格式化时处理。

## D3 死布局面：`fmt.sal` 的 SA_FMT_* / SaFmtBuffer / FmtResult 全仓无使用者
- 全仓 grep：`SA_FMT_`、`FmtResult`、`SaFmtBuffer`、`SaFmtOptions`、`FMT_RESULT` 在 `sa_std/fmt/fmt.sal`（旧 `fmt.sal`）之外零命中；
  `string_format.sa`（fmt 的唯一实现文件）一个也没用。
- 即 fmt.sal 定义的整套状态码/布局目前是死代码面。未删：删布局是 ABI 面改动，需确认 Zig 侧 `src/runtime/sa_std/fmt.zig` 是否引用这些常量名。

## D4 `fs.sai` 双命名代际共存
- `sa_std/io/file/fs.sai`（旧 `sa_std/fs.sai`，142 行）同时声明约 60 个 `sa_fs_*` 与约 60 个 `sa_std_fs_*` extern，
  如 `sa_fs_file_open` 与 `sa_std_fs_open_read` 并存。疑似两代 API 未收敛。
- 未修：需确认哪一代是现行契约、另一代是否可废弃，涉及 Zig 侧导出表。

## D5 `os/fd.sal` 有一条可疑错误码：`SA_FD_ERR_NET = 7`
- `sa_std/os/fd.sal:8`（未移动）：fd（文件描述符）错误码表里混入一条 NET（网络）错误码。
  与 fd 域职责不符，疑似从别处拷贝粘贴遗留。未修：改常量是 ABI 面改动，需确认 Zig 侧是否使用该值。

## D6 `io/buffer/bufio.sal` 从 .sal 里 import .sa 实现文件
- `sa_std/io/buffer/bufio.sal`（旧 `sa_std/io/bufio.sal`）内含 `@import "buf_reader.sa"`、`@import "buf_writer.sa"`——
  布局文件（.sal）拉入实现文件（.sa），跨种类 import。本仓仅此一处这种写法。
- 目前能工作（@import 是纯文本包含，不分种类）。未修：是否应把这两行移到 bufio.sa、让 .sal 只聚合 .sal，
  需确认 .sal 聚合的既定规范（sync/prelude.sal 只聚合 .sal；core/prelude.sal 混有 .sa）。

## D7 fmt/display/ 与 fmt/debug/ 无内容（结构性缺口，非 bug）
- 全仓 grep `\b(Display|Debug)\b`（.sa/.sai/.sal/.sla）零命中：SA 标准库目前没有任何 Display/Debug 概念。
  用户提案的 fmt/display/、fmt/debug/ 子目录本次只有占位 prelude.sa（说明注释，无 import、无宏）。
- 待 Display/Debug API 设计落地后再填。不要把 FORMAT_* 改名充数。

## D8 `time.sla` shim 未经构建验证（残留风险）
- `sa_std/time.sla` 现为 shim（`@import "sa_std/time/time.sla"`），规范文件为 `sa_std/time/time.sla`。
  .sa 的 shim 机制已从 Zig 源码验证（文本包含 + 规范路径去重），但 .sla 的 @import 由 SLA 编译器（插件/Rust 版）解析，
  其 shim 转发是否同样去重、无环，未经构建验证——Phase 1 禁跑构建。
- 跟进：下一阶段首次构建时优先验证 `sa_std/time/time.sla` 经 shim 与经直引两路；若 SLA 侧不支持 shim，
  备选是把 time.sla 移回顶层或改 async.sla/timer.sla 的 import（它俩已改到新路径）。

## D9 prelude.sa 曾同时 import `io.sa` 与 `io/prelude.sa`（已顺手消除一处）
- HEAD 的 `sa_std/prelude.sa` 同时含 `@import "io/prelude.sa"`（子 prelude 块）与 `@import "io.sa"`（模块块），
  后者内容是前者的超集，纯冗余（loader 去重，无行为问题）。本次重组删除了 `io.sa` 这一行（唯一一处删除型改动）。
  其余类似冗余（如 `os/prelude.sa` 与 `env.sa`/`process.sa`/`term.sa` 行并存）按“只重定向、不重构”原则保留，待清理阶段收敛。

## D10 path.sa 对 hash.sa 是隐式（传递）依赖
- `sa_std/io/file/path.sa` EXPAND `DEFAULT_HASHER_*` / `RANDOM_STATE_BUILD` 等宏，但只 @import 了
  core/slice、core/slice.sa、fs.sa、string.sa、os/unix_ffi.sa、num.sa——hash.sa 是经 os/unix_ffi.sa 与 string.sa
  传递进来的，文件级直接边不可见。
- 风险：若将来有人给 unix_ffi/string 瘦身去掉 hash import，path.sa 会静默断裂。建议后续给 path.sa 补一行直接
  `@import "../hash.sa"`（本次未补：补 import 是依赖面改动，虽小但应由构建验证；且“只整理边界”的 Phase 1 不宜扩大）。
  同类传递依赖另有：time.sa → hash.sa 是直接 import（好的对照）。

## D11 文档与 .zig 烟雾测试里的旧路径字符串（非 @import，未改）
- `docs/std_missing.md`、`docs/tutorial/06_std_library.md`、`current_plan.md`、
  `tests/std_smoke/{io_string,deno_facade,env_fs,formats_time_net}.zig`、`tests/std_smoke_core/primitives.zig`
  含有 `sa_std/io.sa` / `sa_std/fs.sa` / `sa_std/time.sa` 等旧路径字面量。
- 它们不是 @import 引用（.md 是文档，.zig 是宿主测试的字符串/注释），且旧路径 shim 仍在，功能不受影响。
  未改：docs 与 tests 不在本次范围；待消费者迁移阶段统一处理。

## D12（已由本次重组消除，不再是缺陷，仅记账）
- io↔fmt 双向边：重组前 io.sa 的 FORMAT_INT（调 `@sa_fmt_i64`）造成 io→fmt，
  同时 string_format.sa 的 FORMAT_WRITE_*（调 `@sa_io_write_all`）造成 fmt→io，文件级双向。
  本次 FORMAT_INT 随宏移入 `fmt/format/format.sa`，io→fmt 边消失，现为单向 fmt→io。已验证（CHECKS.md）。
