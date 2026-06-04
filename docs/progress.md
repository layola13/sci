# Progress Assessment

## Latest Result 2026-06-04

- 已按当前工作区重新评估 `tasks.md` 和 `/home/vscode/projects/sa_plugins/` 外部插件迁移状态；最新统计为 677 个任务行，其中 392 已勾、285 未勾。
- 本轮补勾的主要是已经有实现/文档/测试证据闭环的 NetX RFC 登记和 SAX 外部插件架构登记项；没有把缺测试、缺性能验收、缺原文语义的宽项强行标成完成。
- 命名口径已同步：旧英文展开名废弃，文档统一改为 `safe asm` / `安全汇编`；SAX 展开同步为 `safe asm XML` / `安全汇编 XML`，保留 `SA`、`SA-ASM`、`.sa/.sai/.sal` 作为工具链和文件格式名。
- 主仓全量门禁仍不能按全绿处理：`timeout 600 zig build test --summary all` 未在 10 分钟窗口完成，`std-smoke` 和 `plugin-host-smoke` 也未形成通过输出。
- 外部插件当前已纳入统一口径：pkg、DB、SAX、HTTP client/server、bc2sa、node、vm、wgpu 有当前测试通过证据；Deno 可构建但没有 test step；TS Debug 测试仍有 1 个 benchmark 阈值失败；3D engine 族完成结构验证和部分模块测试，但 Bevy parity 未完成。
- 详细条目见下方 `Detailed Reassessment 2026-06-04`；更早的 2026-06-01/06-02 计数保留为历史审计记录。

## Historical Assessment 2026-06-01

评估时间：2026-06-01，工作区：`/home/vscode/projects/sci`。

本次按用户要求对 `.kiro/specs/sa-asm-language/design.md`、`.kiro/specs/sa-asm-language/requirements.md`、`docs/whitepaper.md` 与根目录 `tasks.md` 做完成度核查。口径保持保守：只有同时具备实现证据和测试/运行证据的条目才在 `tasks.md` 勾选；文档、枚举、接口占位、descriptor/skills 文案、源码片段存在不单独算完成。Deno/pkg/db/SAX/HTTP 等已拆到 `/home/vscode/projects/sa_plugins/` 的模块，按外部插件仓库作为权威实现一起评估。

## 2026-06-01 Result

- 已完成全量检查，但项目没有全绿。
- `tasks.md` 当前统计：301 个未勾选项，376 个已勾选项，共 677 个任务行。
- 本轮保留/更新了有直接证据的勾选项；未把 0.2、0.3、0.4、0.5、0.6 整段全部勾选，因为各版本仍有明确未实现或未验证的硬要求。
- 主仓全量测试未通过。`timeout 600 zig build test --summary all` 中途复现确定失败后最终超时退出 124；失败点是 `std_smoke_core.test.sa_std Deno response text facade links through installed HTTP plugin`。
- 该失败的链接命令缺少 `sa_http_client_resp_body_slice`：`zig cc ... deno_response_text_link.sa.bc /home/vscode/.sa/std/libsa_std.a ...`，`ld.lld` 报 undefined symbol。
- 外部 HTTP client 插件确实导出该符号，`/home/vscode/projects/sa_plugins/sa_plugin_http_client/src/http_saasm_api.zig` 中有 `pub export fn sa_http_client_resp_body_slice`，且插件测试通过；问题集中在主仓 Deno facade 测试链接路径没有把 HTTP client 插件符号带进去。

## Verified Commands

- `zig test src/flattener.zig`：61/61 passed。
- `zig test src/runtime/sa_net_uring.zig -lc`：11/11 passed。
- `/home/vscode/projects/sa_plugins/sa_plugin_pkg`: `zig build test --summary all`，25/25 passed。
- `/home/vscode/projects/sa_plugins/sa_plugin_db`: `zig build test --summary all`，4/4 passed。
- `/home/vscode/projects/sa_plugins/sa_plugin_sax`: `zig build test --summary all`，35/35 passed。
- `/home/vscode/projects/sa_plugins/sa_plugin_http_client`: `zig build test --summary all`，7/7 passed。
- `/home/vscode/projects/sa_plugins/sa_plugin_http_server`: `zig build test --summary all`，7/7 passed。
- `/home/vscode/projects/sa_plugins/sa_plugin_deno`: 没有 `test` build step；`zig build -h` 只列出 `install` / `uninstall`。
- 主仓 DB CLI 过滤验证：`timeout 240 zig build test --summary all -- --test-filter "db cli"` 超时退出 124，未形成可计入完成度的通过证据。

## Confirmed Complete Areas

- v0.1 主编译器基础大部分已落地：flattener、Referee 基线、interpreter、LLVM-C bitcode、sys runtime、FFI airlock、panic runtime、layout CLI、`.sai` 导入和大量 CLI smoke/demo/trap 基线。
- Structured control-flow sugar 已完成并勾选：`src/flattener/line_classifier.zig` 识别 `[IF]` / `[ELSE]` / `[END_IF]`，`src/flattener.zig` 的 `macro-time conditionals select then else and nested branches` 覆盖 then/else/nested/reject，`zig test src/flattener.zig` 通过 61/61。
- v0.4 `.sai` 接口契约已完成：格式、导入、调用点校验、并行编译/依赖检测均有源码和测试证据；`.sal` 只完成格式和导入，不含版本冲突等后续项。
- v0.5 包管理有可用子集：manifest/fetch/install/audit/sum/lock/CI helper、TTY 确认、镜像、precompiled 拒绝等由外部 pkg 插件 25/25 测试覆盖；父任务仍未完成。
- v0.6 DB 有真实 schema/table 子集：schema 解析、容量检查、列段文件、metadata、verify、snapshot/restore、lock/compact 由外部 DB 插件 4/4 测试覆盖；DB CLI 和查询执行仍明显不完整。
- Deno 相关实现已按用户说明从主仓拆到 `/home/vscode/projects/sa_plugins/sa_plugin_deno`；该插件当前只有 install/uninstall build steps，缺少可运行 test step。主仓 Deno facade 的 HTTP response text 链接测试仍受 HTTP client 符号链接路径影响，不能按全绿处理。
- v0.8 netx 有可运行切片：Ticket layout、HTTP parser、WebSocket upgrade、masked payload、listen/accept/recv_ticket/outbound/broadcast、SA-facing `sa_std/netx.{sai,sal,sa}`，targeted tests 11/11 passed。
- v0.9 SAX Phase 1 外部插件较强：parser/lowerer/airlock/shell/CLI/Node runtime/browser-style E2E/负向 Trap 路径由 35/35 测试覆盖。

## Version-Level Gaps

### v0.1

- Checkpoint 12 仍不能勾：需要 Wasmtime `.wasm` 执行；当前环境未证明 Wasmtime 跑通。
- 14.2 CI 流水线仍不能勾：已有本地/预提交门禁，但不是任务要求的完整 CI 矩阵。
- 15 最终验收不能勾：主仓全量测试失败/超时，LLM pilot、AutoBevy、体积等硬约束也未全部满足。

### v0.2 WASM

- 可勾的是基础设施、部分 opcode、DCE、wasm64 smoke/validate 子集。
- 不能整体勾选：手写 atomics/SIMD/WASI import、DWARF custom sections、Wasmtime debug line breakpoint、默认切换到手写 emitter、`#mode compact` 都未完成或未验证。
- Hello-Compute `.wasm <= 32 KB` 不成立：先前实测约 41970 bytes，大于 32768 bytes。

### v0.3 / v0.4

- v0.3 仍有 SIMD 全启用、AutoBevy 1M、Referee stretch、产物体积 stretch、LLM 微调、`--debug-gas` / `--debug-san` 未完成。
- VTable signature static validation 仍未完成；`src/verifier.zig` 已有 `ConstVTableSlot.signature`、`CallProvenance.slot_signature`、`parseVtableSlots`、`collectConstVtables` 等签名记录雏形，但 `call_indirect` 路径没有发现调用点 tuple 比对，也没有发射 `Trap: VTableSignatureMismatch` 的实现或 P31 测试证据。
- v0.4 `.sal` 后半未完成：版本冲突检测、CI 版本递增检查、影响扫描仍未证明。
- 函数粒度增量编译和多 LLM 并行验证仍未完成。

### v0.5 Package Management

- 父任务 `35`、`35b`、`35c`、`35d`、`35e`、`35f` 保持未完成，因为仍有子项缺口。
- `sa fetch` 原文语义仍未完成：当前外部插件是 `sa pkg fetch`，不是根命令 `sa fetch` 的完整语义。
- 跨包能力提升 `NonTransitivePrimitive`、零状态生命周期 PBT、全平台 `--lock-only`、项目级孤岛 PBT、源码/机器码双轨 PBT、运行时 tainted artifact 红字警告、全平台 CI 矩阵仍未证明。
- lock helper 存在 idempotent/source-change 测试，但还不能等同于“第二次跳审判 + 改源码重弹”的完整审判台集成。

### v0.6 DB

- DB 插件 descriptor skills 列了很多命令，但 `/home/vscode/projects/sa_plugins/sa_plugin_db/src/plugin.zig` 当前真正 `handle_command` 实现只覆盖 `db init`，其它子命令返回 `UnexpectedArgument`；`src/db_stub.zig` 的 register/inspect/exec 仍返回 `UnsupportedOperation`。因此其它 DB CLI 子命令不能勾。
- `.sadb-schema` 生成的是 `.iface` 风格输出，不是任务 1.2 要求的 `.sai` 接口文件。
- 主仓 `tests/cli_smoke.zig` 内存在 DB lifecycle 测试文本，但 `build.zig` 当前只把 `cli_smoke` 的 3 个 bc2sa 过滤用例接入 `zig build test`；本轮尝试的 DB 过滤 build 超时退出 124，不能作为完成证据。
- Insert 算子、Blob Arena、qmod 编译/注册、DB Referee 权限、mmap/SIGSEGV 沙箱、冷热分层、Zstd/S3、性能基线、双 11 demo、12 条 DB Trap 边界覆盖仍未完成。

### v0.8 netx / HubProxy

- `ConnectionSlot` 还缺任务要求的 overflow chain 和显式 `inflight_zc`，46.1 不能勾。
- 47.4 要求编译期探测 `RECV_MULTISHOT` / `SEND_ZC` 能力并运行时 fallback，证据不足。
- 背压、三环 SPSC、Raw Binary RPC、K1/K2/M1-M6 性能验收、SEND_ZC broadcast lifetime/refcount、持续 benchmark 仍未完成。
- HubProxy main/routes/示例边界已有证据，但 SSE/chunked streaming 之前 smoke 表现为两块一起到达，不能勾；<1ms latency 未证明。
- `docs/std_rfc.md` 仍缺 netx RFC 条目，67 不能勾。

### v0.9 SAX

- Phase 1 插件实现强，但原任务中绑定主仓 `src/emit_wasm/` 和 `wasm32-unknown-unknown` 的项仍不能按原文勾；实际实现使用 LLVM-C `.sa.bc` + `wasm32-freestanding -fno-entry --import-symbols`。
- 73.8 未完成：当前 Trap 输出有 component/text/line 等，但没有证明每条 Trap 都完整携带 `component / handler / tag / event / upstream_loc`。
- 生命周期钩子签名校验、route mount/unmount、文件监听、WASM 热替换、VS Code 插件、native/js/WebGPU/style/package integration 未完成。
- `docs/sax_*.md` 与 `docs/std_rfc.md` 仍未同步到外部插件真实实现。

## Main Blocking Evidence

- 主仓全量门禁失败/超时：`std_smoke_core` 的 Deno response text facade 链接缺 `sa_http_client_resp_body_slice`。
- 外部 HTTP client 插件导出该符号且测试通过，所以应优先检查主仓测试/stdlib/plugin link step 如何把外部 HTTP client runtime 链入 Deno facade。
- `wasmtime` / `wasm-validate` 先前未在 PATH 中发现，Wasmtime debug/acceptance 类任务不能证明。
- Hello-Compute wasm size 约 41970 bytes，未达到 v0.2 的 32 KB 目标。

## Worktree Notes

- 本次未修改实现代码。
- 已更新 `tasks.md` 中有证据的完成项，并新增/更新本报告 `docs/progress.md`。
- 工作区仍存在与本评估无关的既有改动：`sci.code-workspace`、`src/runtime/sa_std.zig`，以及未跟踪 `SA_LIMITATIONS.md`；这些未被回退。

## Final Audit Status

- 全部检查已完成。覆盖范围包括根目录 `tasks.md` 全部任务行、`.kiro/specs/sa-asm-language/design.md`、`.kiro/specs/sa-asm-language/requirements.md`、`docs/whitepaper.md`，以及用户补充说明中拆分到 `/home/vscode/projects/sa_plugins/` 的 Deno/pkg/db/SAX/HTTP 插件工程。
- 第二轮复核没有发现新的可安全勾选项。原因不是未继续检查，而是剩余未勾选项缺少“实现 + 测试/运行通过”双证据，或任务原文要求与当前外部插件实际架构不完全一致。
- v0.2、v0.3、v0.4、v0.5、v0.6 均已逐项评估；只勾选了可证明完成的叶子任务和无缺口父任务。存在未完成子项的父任务保持未勾选，避免把阶段整体完成度误报为全绿。
- 外部插件复核结论：pkg、db、HTTP client/server、SAX 插件测试均能通过各自工程的 `zig build test --summary all`；Deno 插件已外置但当前没有 test build step，因此只能确认工程结构与导出符号，不能确认测试完成。
- 主仓仍不是可发布完成态：`zig build test --summary all` 未通过，核心阻塞是 Deno facade 链接 HTTP client response body 符号失败；在此修复并重跑全量测试前，最终验收类任务不能勾选。

## Continued Review Addendum

- 用户追问后又复核了剩余未勾选任务，重点覆盖 v0.2–v0.6、外部 pkg/db/Deno/SAX/HTTP 插件、主仓 WASM emitter、VTable、`.sal`、DB CLI、netx 和 SAX 文档登记项。
- 本次续查未修改实现代码，也未发现新的可安全勾选任务；`tasks.md` 仍为 301 个未勾选项、376 个已勾选项。
- WASM 相关未勾项仍有明确反证：`src/emit_wasm/opcodes.zig` 对 atomics/SIMD/WASI 路径返回 `UnsupportedAtomic` / `UnsupportedSimd` / `UnsupportedWasiImport`，测试也断言这些路径暂不支持；DWARF/name custom section 与 Wasmtime debug 行号没有可运行证据。
- pkg 相关未勾项仍缺完整语义：外部 pkg 插件覆盖 fetch/audit/sum/lock/CI helper 的可用子集，但 `sa fetch` 原文的根命令语义、跨包 `NonTransitivePrimitive`、审判台零状态 PBT、全平台 lock-only、双轨 PBT、运行时 tainted 红字和全平台 CI 矩阵仍未证明。
- DB 相关未勾项仍缺完整实现：外部 DB 插件 `handle_command` 只实际处理 `db init`，其余 DB CLI 子命令仍返回 `UnexpectedArgument`；`db_stub.zig` 仍有 `UnsupportedOperation`；`.sadb-schema` 当前输出 `.iface` 风格文件而非任务要求的 `.sai`；Insert/Blob/qmod/mmap/SIGSEGV/冷热分层/Zstd/S3/性能/12 条 Trap 边界仍缺实现或测试证据。
- Deno 已确认外置到 `/home/vscode/projects/sa_plugins/sa_plugin_deno`，但该工程没有 test build step；主仓 Deno facade 仍受 HTTP client response body 符号链接失败影响，不能作为全量完成证据。
- 结论保持不变：全部检查已完成；当前能证明完成的特性已经体现在 `tasks.md` 勾选中，剩余未勾项不是遗漏，而是尚未达到“实现 + 测试/运行通过”的评估标准。

## Final Closure Pass

- 收口复查再次确认没有遗漏的可安全勾选项。复查范围包括 layout tag、函数粒度增量编译、formal/FPGA、LLM pilot、AutoBevy、手写 WASM 后端与 DWARF-in-WASM 等剩余高风险簇。
- `#tag NAME` / `TagMismatch` / `MissingTag` 只在需求、白皮书、FAQ 等文档中出现；主仓源码没有发现 `#tag` 声明解析、`alloc N tag NAME` 语法、函数签名 `tag NAME` 校验或对应 Trap 测试，因此 36.x 保持未勾。
- `--incremental` / `.sa-cache` / 函数级 `.o` 的任务要求没有找到匹配实现。当前命中的 cache/hash 证据主要来自 package manager、demo cache、plugin cache 或普通 source hash，不等同于 v0.4 的函数粒度增量编译。
- formal/FPGA/LLM/AutoBevy 相关命中集中在设计文档、FAQ、路线图和任务描述，未找到 `formal/referee_spec.lean`、Coq/Lean 可检查证明、硬件 Referee 原型、pilot 30 题执行归档或 AutoBevy 1K/1M 验收脚本的可运行证据。
- 手写 WASM 后端继续存在明确缺口：`src/emit_wasm/opcodes.zig` 对 atomics/SIMD/WASI import 返回 unsupported；`wasmtime` / `wasm-validate` / `wasm-objdump` 也未作为可用工具链证据出现，不能补勾 DWARF-in-WASM、debug breakpoint 或完整 v0.2 验收。
- 本报告最终状态：`tasks.md` 301 个未勾选项、376 个已勾选项；评估文档已写入 [docs/progress.md](/home/vscode/projects/sci/docs/progress.md)。

## Final Verification Pass

- 收到用户要求保存详细评估后，再次复核了 `tasks.md` 当前全量任务行和关键反证检索结果。最终计数保持不变：301 个未勾选项、376 个已勾选项、共 677 个任务行。
- 本次没有继续修改 `tasks.md`。原因是剩余可疑项仍无法同时满足“源码实现存在”和“测试/运行证据通过”：Deno 插件无 test build step，主仓 Deno facade 链接仍缺 HTTP client body 符号；DB 插件 CLI 仍只接通 `db init`；pkg 仍是 `sa pkg fetch` 子命令而非任务原文完整 `sa fetch`；WASM opcode 对 atomics/SIMD/WASI 仍明确返回 unsupported；netx 和 SAX 的若干项仍是计划/文档或架构不匹配。
- 外部插件口径已纳入最终结论：`sa_plugin_pkg`、`sa_plugin_db`、`sa_plugin_sax`、`sa_plugin_http_client`、`sa_plugin_http_server` 有各自通过的 `zig build test --summary all` 证据；`sa_plugin_deno` 只确认了独立工程与接口文件，不能确认测试完成。
- 结构性复核结论：存在未完成子项的父任务保持未勾选；没有把 v0.2、v0.3、v0.4、v0.5、v0.6 按阶段整段勾选，因为这些阶段仍有明确缺口。当前 `tasks.md` 中可证明完成的特性已经勾选，剩余未勾项按严格口径不是遗漏。

## Recommended Next Checks

1. 修主仓 Deno facade 链接路径：让 `deno_response_text_link.sa.bc` 同时链接外部 HTTP client 插件导出的 `sa_http_client_resp_body_slice`，然后重新跑 `zig build test --summary all`。
2. 对 v0.2 补手写 WASM 的 atomics/SIMD/WASI/DWARF/Wasmtime debug 和 32 KB 体积证据。
3. 对 pkg 补审判台端到端、tainted runtime warning、全平台 lock-only、CI matrix 和 PBT 缺口。
4. 对 DB 补 `db init` 之外的 CLI 子命令、qmod/exec/referee/mmap/blob/性能/Trap 边界。
5. 对 SAX 统一任务文案与真实外部插件架构，或补齐原文要求的 `src/emit_wasm` / `wasm32-unknown-unknown` 兼容证据。

## Continuation Pass 2026-06-01

- 本轮继续按“实现证据 + 测试/运行通过证据”复核剩余未勾项，没有修改实现代码，也没有发现新的可安全补勾任务；`tasks.md` 计数保持 301 未勾、376 已勾、677 总任务行。
- 复跑目标测试：`/home/vscode/projects/sa_plugins/sa_plugin_pkg` 的 `timeout 240 zig build test --summary all` 通过 25/25；`/home/vscode/projects/sa_plugins/sa_plugin_db` 的 `timeout 240 zig build test --summary all` 通过 4/4；主仓 `timeout 240 zig test src/runtime/sa_net_uring.zig -lc` 通过 11/11；`/home/vscode/projects/sa_plugins/sa_plugin_sax` 的 `timeout 300 zig build test --summary all` 通过 35/35。
- pkg 复核结论：外部插件 `sa pkg fetch` 支持 `-g` / `--ref`，但根命令 `src/cli.zig` 的 `sa fetch` 分支仍只执行 `fetchPackage(args[2], "HEAD", .{})`，不解析 `-g` / `--ref`，所以 35.2 继续不能勾。35.5 只看到预编译产物拒绝有明确测试，未证明重复导出与版本冲突两项组合要求。
- pkg CI/PBT 复核结论：`src/pkg/ci.zig` / 外部插件有 CI 信号、双轨核验和 taint banner helper 单测，但没有覆盖 P37 要求的四种信号非空交集 PBT，也没有“任何 stdin 输入被拒绝”的完整证明；tainted artifact 仍未证明运行时三行红字无法被 `--release` 移除。
- DB 复核结论：外部 DB 插件当前 `handle_command` 仍只实际处理 `db init`，schema 输出仍是 `.iface`，不是任务 1.2 要求的 `.sai`。12 条 DB Trap 名称和编号存在于 trap 枚举/文档中，但没有 12 条边界用例覆盖，不能补勾 20.1 或 23.x。
- netx 复核结论：目标单测再次通过 11/11，证明当前 Ticket/layout、HTTP/WS、masked payload、listen/accept/outbound/broadcast 等可运行切片；但 `ConnectionSlot` 仍缺任务原文的 overflow 链和显式 `inflight_zc` 计数，出站满载返回仍映射到 `SA_NETX_ERR_IO` / `TRUNCATED` 而非 `EAGAIN`，也没有 1M fuzz、perf、K1/K2 或持续 benchmark 证据。
- SAX 复核结论：外部插件 Phase 1 仍强，35/35 测试通过；但真实 `sa sax dev` 插件入口目前只调用 build 并打印刷新结果，不启动长期 dev server，`src/sax/cli.zig` 内部轮询 mtime 的 dev server 没有通过插件入口接通，也没有 inotify/kqueue、WASM 热替换保留状态的测试证据。Router/Page 已有解析和 metadata/init，但 route change 触发 Page mount/unmount 仍未证明。
- VTable / `.sal` / debug 模式复核结论：`src/verifier.zig` 已有 `ConstVTableSlot.signature` 和 `slot_signature` provenance 雏形，但未找到断言槽位完整签名 tuple、调用点 tuple mismatch 触发 `VTableSignatureMismatch` 或 P31 的测试；`.sal` 仍只证明格式和导入，未证明版本冲突、版本递增 CI 或影响扫描；`--debug-gas` / `--debug-san` 仍停留在文档和预留 Trap 名称。

## Continuation Pass 2 2026-06-01

- 本轮继续按严格口径复核剩余未勾项，没有修改实现代码，也没有新增可安全勾选项；`tasks.md` 保持 301 未勾、376 已勾、677 总任务行。
- 额外纳入外部插件测试证据：`/home/vscode/projects/sa_plugins/sa_plugin_bc2sa` 的 `timeout 240 zig build test --summary all` 通过 4/4；`sa_plugin_node` 通过 3/3；`sa_plugin_ts` 通过 26/26；`sa_plugin_vm` 的 test step 成功。这些插件当前没有对应剩余未勾叶子任务，主要补强已勾的插件化/生态证据，因此未据此修改 `tasks.md`。
- Deno 插件状态未变：`/home/vscode/projects/sa_plugins/sa_plugin_deno` 的 build steps 仍只有 `install` / `uninstall`，没有 `test` step；主仓 Deno facade 仍受 HTTP client response body 符号链接问题影响，不能作为全量完成或最终验收证据。
- DB 复核更正：主仓 `tests/cli_smoke.zig` 中存在 DB lifecycle 和 register/inspect/exec 测试文本，但 `build.zig` 当前对 `cli_smoke` 固定只接入 3 个 bc2sa 过滤用例。手动给 `zig build bc2sa-smoke -- --test-filter "db ..."` 传参时实际仍只跑 bc2sa 过滤测试，因此不能把该输出当作 DB CLI 通过证据；当前主仓源码也没有可定位的 DB CLI 实现文件，外部 DB 插件入口仍只处理 `db init`。
- VTable、SIMD、Agent JSON、HubProxy/RFC 再查结论保持不变：`VTableSignatureMismatch` 仍是预留/文档级名称而非调用点 tuple mismatch 测试；SIMD 在前端类型/指令枚举有支持但 interpreter/手写 WASM 仍明确 unsupported；8.22 仍缺 trap 侧稳定 `SA-XXX` 词表；`docs/std_rfc.md` 没有登记 `sa_netx_*` 的 7 条 FFI + Ticket layout。
- 机械一致性检查结果：未发现“父项未勾但所有子项已勾”的结构性遗漏；未勾项附近带有“说明/已/通过/覆盖”的条目均为部分实现说明、反证说明或仍缺测试覆盖的宽项。

## Continuation Pass 3 2026-06-01

- 收到“全部检查完成了吗”后继续复核剩余未勾项，重点补查 package manager 的 lock/audit 细项、HubProxy SSE/chunked streaming、以及 43.1 demo-derived 原生测试迁移。没有修改实现代码，也没有发现新的可安全补勾项；`tasks.md` 仍为 301 个未勾选项、376 个已勾选项、677 个任务行。
- package manager 复核结论：外部 pkg 插件的 `src/pkg/lock.zig` 有 `updateProjectLock creates a project-local lock and is idempotent`、`updateProjectLock clears stale target hashes when source changes`、`updateProjectLock rejects global state paths` 等 helper 级测试；这些只证明项目锁文件 helper 的幂等和源码变化清理，不等同于任务 35d.2 / 35f.5 要求的“第二次运行跳过审判台 + 修改源码重新弹出审判台”的端到端集成。因此 35d.2、35f.5 保持未勾。
- 35.5 保持未勾：预编译产物拒绝有明确测试证据，但任务原文同时要求重复导出、版本冲突、预编译产物拒绝三类场景；当前未找到三者组合均被实现并通过测试的证据。
- HubProxy 复核结论：`examples/hubproxy/main.zig` 已有 `respondStreaming`、`isStreamingResponse`、chunked/content-type 检测和 streaming reader loop；`zig test examples/hubproxy/main.zig` 通过 2/2，但只覆盖配置解析和路由解析。用本地 Python chunked SSE upstream 做运行烟测时，第一次连接拒绝，第二次 HubProxy 启动阶段在 `std.net.Address.parseIp(config.listen_host, config.listen_port)` 报 `InvalidIPAddressFormat`，未形成端到端 SSE/chunked 透传通过证据；因此 65c 的 streaming 子项和 <1ms 验收继续不能勾。
- 43.1 复核结论：`tests/unit_framework/feature_suite.sa` 已包含大量 demo-derived `@test`，覆盖到 300 号 demo；`tests/unit_framework/runner.zig` 断言 `sa test` 输出 `270 passed; 0 failed; 0 skipped; 1 ignored`、`271 passed; 0 failed; 0 skipped`，源码证据很强。尝试 `zig build unit-framework --summary all` 失败，因为 `build.zig` 没有该 step；尝试 `timeout 240 zig build test --summary all -- --test-filter "native unit framework suite covers the demo-derived feature matrix"` 实际仍走总 `test` 依赖链，进入 unit framework 后最终超时退出 124。并且任务文本末尾明确写有“尚未全量迁移”，所以按严格口径不能把 43.1 整项勾选。
- 最终回答口径：全部检查已经完成，且当前可证明完成的特性已经体现在 `tasks.md` 勾选中；剩余未勾项不是漏查，而是缺少实现 + 测试/运行双证据，或任务原文要求仍未完全满足。

## Continuation Pass 4 2026-06-01

- 本轮在 Deno 已拆到 `/home/vscode/projects/sa_plugins/` 的口径下继续复核剩余未勾项，覆盖 DB、netx、SAX、CLI diagnostics、DB Trap codes、WASM/compact mode、VTable、CI/LLM/AutoBevy 和 pkg。没有修改实现代码，也没有发现新的可安全补勾任务；`tasks.md` 保持 301 个未勾选项、376 个已勾选项、677 个任务行。
- 复跑目标测试：`timeout 180 zig test src/common/trap.zig` 通过 8/8；`timeout 240 zig test src/runtime/sa_net_uring.zig -lc` 通过 11/11；`/home/vscode/projects/sa_plugins/sa_plugin_sax` 的 `timeout 240 zig build test --summary all` 通过，Build Summary 39/39，测试 35/35。`timeout 180 zig test src/emit_wasm/opcodes.zig` 失败原因是单文件直测的相对模块导入路径问题，不构成完成证据；源码本身仍显式对 atomics/SIMD/WASI 返回 unsupported。
- DB 复核结论保持不变：外部 DB 插件有真实 `schema.zig` / `table.zig` 子集，列段、metadata、snapshot/restore、lock/compact helper 已有证据并已反映在已勾项中；但 `schema.ifaceFilePath` 生成 `.iface` 而非任务 1.2 要求的 `.sai`，`plugin.zig` 的实际命令处理仍只覆盖 `db init`，descriptor 中列出的更多 skills 不能视为 CLI 实现。DB Trap 名称和编号存在，但 `docs/errorcode.md` 未完整登记 DB traps，测试也只抽样首尾，不能补勾 20.1 或 23.1-23.12。
- netx 复核结论保持不变：`src/runtime/sa_net_uring.zig` 和 `sa_std/netx.{sai,sal,sa}` 证明了当前已勾子集，目标测试 11/11 通过；剩余未勾项仍缺 `ConnectionSlot` overflow chain、显式 `inflight_zc`、出站满载 `EAGAIN` 语义、1M fuzz、K1/K2、benchmark 和 RFC 登记。`docs/std_rfc.md` 仍没有完整登记 `sa_netx_*` 七条 FFI 与 Ticket layout。
- SAX 复核结论保持不变：外部 SAX 插件 Phase 1/部分 Phase 2 证据强，生命周期 hook、selective render、router metadata 等已勾子项有 parser/lowerer 测试支撑；剩余未勾项仍包括 hook signature validation、route change mount/unmount、inotify/kqueue、热替换保留状态、VS Code、native/js/WebGPU/package/style。`docs/sax_whitepaper.md` 仍是 v0.1，`docs/sax_design.md` 仍描述主仓 `src/emit_wasm/` / `wasm32-unknown-unknown` 路径，和外部插件真实 LLVM-C `.sa.bc` + `wasm32-freestanding -fno-entry --import-symbols` 架构不完全一致，因此 SAX 文档同步项不能补勾。
- CLI diagnostics / Trap 复核结论：`src/cli_util.zig` 已有 `SA-CLI-*` 错误码和 JSON CLI error，`src/common/trap.zig` 有 `repair` 对象与 `trap_code`；但任务 8.22 要求 trap 侧稳定 `SA-XXX` 命名和统一 trap 词表，当前 trap side 仍主要是数字 `trap_code`，且 `docs/errorcode.md` 标注多项仍为 roadmap-only，所以保持未勾。
- WASM / compact mode 复核结论：`src/emit_wasm/opcodes.zig` 继续明确返回 `UnsupportedAtomic`、`UnsupportedSimd`、`UnsupportedWasiImport`；没有 `#mode compact` 的预处理语义、compact trap、DWARF-in-WASM、Wasmtime debug breakpoint 或 32 KB size 的通过证据。因此 v0.2 中这些后续项继续不能勾。
- VTable / `.sal` / CI 复核结论：`src/verifier.zig` 已有 `ConstVTableSlot.signature`、`CallProvenance.slot_signature`、`parseVtableSlots`、`collectConstVtables` 等签名记录雏形，但没有直接测试断言完整 slot signature tuple，也没有 `call_indirect` tuple mismatch 触发 `VTableSignatureMismatch` 的证据；`.sal` 仍缺版本冲突、版本递增 CI 和影响扫描；`.github/workflows/release.yml` 存在但不满足 14.2 的完整 CI matrix/gates 要求。LLM pilot、AutoBevy、formal/FPGA 仍只见文档或路线图证据。
- pkg 复核结论保持不变：外部 pkg 插件实现的是 `sa pkg fetch/install/audit`，支持 `-g` / `--ref`，但主仓原文的根命令 `sa fetch` 完整语义仍未完成；预编译产物拒绝已有证据，但 35.5 同时要求重复导出和版本冲突；lock helper 测试证明幂等和源码变化清理，不等同于端到端“第二次跳审判 + 源码变更重开审判台”；CI helper 未覆盖 P37 所有非空信号组合与 stdin 拒绝，运行时 tainted 三行红字也未证明不可被 `--release` 移除。
- 最终收口结论：全部检查已完成。当前 `tasks.md` 中可证明完成的特性已经勾选；剩余未勾项不是遗漏，而是缺少实现 + 测试/运行双证据，或任务原文要求与当前拆分插件架构/实际实现仍不一致。

## Continuation Pass 5 2026-06-01

- 本轮继续按“实现证据 + 测试/运行通过证据”复查剩余未勾项，优先检查可能漏勾的窄叶子：netx/HubProxy、SAX Phase 2、DB CLI、pkg lock/CI、VTable、`.sal`、debug-gas/debug-san、compact mode 与 8.22 Agent-First。没有修改实现代码，也没有发现新的可安全补勾项；`tasks.md` 仍保持 301 未勾、376 已勾、677 总任务行。
- 目标测试结果：`timeout 180 zig test src/common/trap.zig` 通过 8/8；`timeout 240 zig test src/runtime/sa_net_uring.zig -lc` 通过 11/11；`/home/vscode/projects/sa_plugins/sa_plugin_pkg` 的 `timeout 240 zig build test --summary all` 通过 25/25；`/home/vscode/projects/sa_plugins/sa_plugin_sax` 的 `timeout 240 zig build test --summary all` 通过 35/35，Build Summary 39/39。
- HubProxy 复核结论：`examples/hubproxy/main.zig` 源码确实使用 `request.respondStreaming`，并从 upstream reader 逐块 `writeAll`；但本地 chunked/SSE upstream 烟测无法形成通过证据，HubProxy 进程启动时报 `InvalidIPAddressFormat` 并退出，客户端连接 `127.0.0.1:18081` 被拒绝。因此 65c 的 SSE/chunked 端到端流式透传和 <1ms 性能目标继续不能勾。
- netx 复核结论：当前 `sa_netx_push_outbound` 路径在 `sendBytes` 遇到 `slot.outbound_inflight` 时返回 `error.WouldBlock`，但命令处理仍映射为 `SA_NETX_ERR_IO`，没有暴露任务原文要求的 `EAGAIN`；`ConnectionSlot` 仍只有 4KB inline buffer 与 `outbound_inflight` 布尔/zc mode，没有 overflow 链和显式 `inflight_zc` 计数。因此 46.1、56.2 以及 M1/M2/M3 性能验收继续不能勾。
- DB 复核结论：主仓 `tests/cli_smoke.zig` 中存在 `db cli init writes iface...` 与 `db cli register inspect exec...` 测试文本，但 `build.zig` 对 `cli_smoke` 只接入三个 bc2sa 过滤用例。本轮尝试 `timeout 360 zig build test --summary all -- --test-filter "db cli init writes iface and table lifecycle commands update storage"` 长时间无输出后终止，未得到可用通过证据；源码检索也没有在主仓 `src/cli.zig` 定位到 DB 子命令分发实现。外部 DB 插件入口仍只证明 `db init`。
- SAX Phase 2 复核结论：外部插件有 `lowerer emits lifecycle hooks for docs phase 2 shapes`、`lowerer emits selective render for state writes`、`lowerer emits router metadata and init when pages are present` 等测试，已支撑当前已勾的 79.1/79.2、80.1/80.2、81.1/81.2。剩余 80.3、81.3、82.2、82.3 不满足：未见 hook 无参无返签名校验测试，router 只有 metadata/init 而非 route change mount/unmount，dev server 代码是 mtime 轮询而非 inotify/kqueue，也没有 WASM 热替换保留 SA 状态的测试。
- pkg 复核结论：外部 pkg 插件测试再次通过 25/25。仍不能补勾的原因不变：35.5 只证明预编译产物拒绝，未证明重复导出和版本冲突；35d.2/35f.5 只有 lock helper 幂等和源码变化清理，不是端到端跳审判/重弹；35e.9 的 CI 测试只覆盖单信号/双轨子集，不是四种信号非空交集 PBT 和 stdin 全拒绝；35e.4/35f.9 仍缺运行时红字不可被 `--release` 移除的证据。
- 8.22 Agent-First 复核结论：`sa explain` / `sa fix --plan` / `sa skills` 与 CLI JSON 诊断已有测试和实现，但任务文本明确还要求 trap 侧稳定 `SA-XXX` 错误码与统一 trap 词表；当前 trap JSON 是 `trap_code` 数字与 `repair` 对象，`docs/errorcode.md` 仍标注多项 roadmap-only。因此 8.22 继续保持未勾。
- VTable / `.sal` / debug / compact mode 复核结论：`VTableSignatureMismatch`、`SnapshotVersionMismatch`、`GasExceeded` 仍在 `docs/errorcode.md` 标注为 roadmap-only 或未完全接线；`.sal` 后续缺版本冲突、版本递增 CI、影响扫描；`#mode compact` 仍只见文档和 trap `original_text` 字段，未见前处理器语义与非法糖基线；WASM atomics/SIMD/WASI 仍由 `src/emit_wasm/opcodes.zig` 明确返回 unsupported。
- 机械一致性检查：未发现“父项未勾但所有直接子项已勾”的结构性遗漏。剩余未勾项旁边的“已/通过/覆盖”描述均为部分实现说明、反证说明或覆盖范围不足的宽项，按当前严格口径不能据此补勾。

## Continuation Pass 6 2026-06-01

- 本轮按用户最新追问再次回看 CI、8.22、43.1、外部插件拆分状态与 `tasks.md` 关联项，仍然没有发现新的可安全勾选任务；`tasks.md` 计数维持 301 个未勾选项、376 个已勾选项、677 个任务行。
- CI 复核仍不成立：`.github/workflows/release.yml` 只是发布包矩阵，覆盖 package/release 产物打包与上传，不是任务 14.2 所要求的完整测试门禁链，也没有把 `zig build test`、PBT、性能基线和白皮书/体积类检查串成统一 CI gate。
- 8.22 复核结论不变：`src/cli.zig` 已有 `explain` / `fix --plan` / `skills`、`compile_tokens` / `instruction_count` 和 JSON 诊断输出，`tests/cli_smoke.zig` 也有对应 smoke；但 `src/common/trap.zig` 仍主要以数字 `trap_code` 和 `repair` 对象表达，`docs/errorcode.md` 仍保留 roadmap 语气，任务要求的 trap 侧稳定 `SA-XXX` 词表尚未闭环，因此不能补勾 8.22。
- 43.1 复核仍保持保守：`tests/unit_framework/runner.zig` 确认了 demo-derived feature matrix 的代表性基线与 `270 passed` / `271 passed` 文本，但任务原文明确写有“尚未全量迁移”，所以即使单测覆盖面很强，也不能把整项视为完成。
- 外部插件拆分状态再次确认：`sa_plugin_pkg`、`sa_plugin_db`、`sa_plugin_sax`、`sa_plugin_http_client`、`sa_plugin_http_server` 有各自通过的 `zig build test --summary all` 证据；`sa_plugin_deno` 仅确认存在独立工程与 `install` / `uninstall` build step，仍没有 test step，因此 Deno 相关父项和依赖它的全链路验收继续不能按完成处理。
- 最终结论保持不变：本轮检查已完成，但没有新的实现 + 测试/运行双证据可以写回 `tasks.md`；剩余未勾项继续按“未完成或未证明完成”处理。

## Completion Assessment Final 2026-06-01

- 全部检查已完成。评估覆盖根目录 `tasks.md` 全部 677 个任务行、`.kiro/specs/sa-asm-language/design.md`、`.kiro/specs/sa-asm-language/requirements.md`、`docs/whitepaper.md`，并按用户说明把 `/home/vscode/projects/sa_plugins/` 下已拆分的 Deno、pkg、DB、SAX、HTTP 等插件纳入同一完成度口径。
- 当前最终统计保持：301 个未勾选项、376 个已勾选项、677 个任务行。已完成且可证明的特性已经体现在 `tasks.md` 的勾选中；本次最终复核没有发现新的可安全补勾项。
- 判定标准保持严格：只有同时具备源码实现证据和测试/运行通过证据的任务才算完成。文档描述、descriptor/skills 声明、枚举常量、stub、测试文本未接入 build、或单独源码片段存在，均不单独构成完成证据。
- v0.2 不能整体勾选：手写 WASM 后端仍对 atomics、SIMD、WASI import 明确返回 unsupported，DWARF/name custom section、Wasmtime debug breakpoint、`#mode compact` 语义和 Hello-Compute 32 KB 体积目标仍缺通过证据。
- v0.3 不能整体勾选：SIMD 全链路、AutoBevy 1M、Referee stretch、LLM pilot、formal/FPGA、`--debug-gas` / `--debug-san` 等仍未达到实现加测试闭环。
- v0.4 不能整体勾选：`.sai` 接口契约主线已较完整，但 `.sal` 后续的版本冲突、版本递增 CI、影响扫描，以及函数粒度增量编译、多 LLM 并行验证、VTable signature mismatch 运行时/验证器测试仍缺证据。
- v0.5 不能整体勾选：外部 pkg 插件已有 fetch/install/audit/sum/lock/CI helper 等可用子集并通过测试，但任务原文中的根命令 `sa fetch` 完整语义、重复导出与版本冲突、NonTransitivePrimitive、审判台端到端 PBT、全平台 lock-only、tainted runtime warning 和 CI matrix 仍未证明。
- v0.6 不能整体勾选：外部 DB 插件已有 schema/table/verify/snapshot/restore/lock/compact 子集并通过测试，但 CLI 入口实际仍只证明 `db init`，schema 输出为 `.iface` 而非任务要求的 `.sai`，register/inspect/exec/qmod/Referee/mmap/blob/冷热分层/Zstd/S3/性能和 12 条 DB Trap 边界仍缺闭环。
- Deno 拆分状态已纳入评估：`sa_plugin_deno` 独立工程存在，但当前没有 test build step；主仓 Deno facade 仍有 HTTP client response body 符号链接问题。因此 Deno 相关链路不能作为全量完成或最终验收证据。
- 外部插件测试证据已记录：pkg、DB、SAX、HTTP client/server、bc2sa、node、ts、vm 等插件已有通过证据；这些证据只支持对应已勾子项，不能替代剩余任务原文要求。
- 主仓最终验收仍未完成：先前 `zig build test --summary all` 未全量通过，核心阻塞是 Deno facade 链接缺 `sa_http_client_resp_body_slice`；CI、Wasmtime、性能、体积和文档同步类验收也仍有缺口。
- 工作区说明：本评估没有修改实现代码。`tasks.md` 已保留先前按证据勾选的完成项；本文件作为最终详细评估报告保存。当前仍存在与本评估无关的既有改动 `sci.code-workspace`、`src/runtime/sa_std.zig`、未跟踪 `SA_LIMITATIONS.md`，未被回退或改动。

## Continuation Pass 7 2026-06-01

- 本轮继续按“有实现和测试证据才勾”的标准复核剩余未勾项，重点检查 DB、SAX、pkg、netx/HubProxy、WASM/Wasmtime、诊断/RFC 文档和 `--release` / debug 模式。没有修改实现代码，也没有发现新的可安全补勾项；`tasks.md` 计数仍为 301 未勾、376 已勾、677 总任务行。
- DB 复核结论：外部 DB 插件仍只证明 schema/table 的子集和 `db init`，`schema.ifaceFilePath` 仍输出 `.iface`，不是 1.2 要求的 `.sai`。12 条 DB Trap 名称和编号在 `src/common/trap.zig` / `src/db/common/trap.zig` / 外部插件副本中存在，`docs/database.md` 也列出设计表，但当前测试只抽样首尾 `DbCapabilityEscalation` / `DbForbiddenSqlString`，且 `docs/errorcode.md` 公共 Trap Catalog 未把 12 条 DB Trap 登记为 emitted，因此 23.x 继续不能补勾。
- pkg 复核结论：顶层 `sa fetch` 分支当前仍直接调用 `fetchPackage(args[2], "HEAD", .{})`，没有使用 `parseFetchArgs`，所以 `-g` / `--ref` 只在 `install` 或外部插件 `sa pkg fetch` 路径成立，35.2 保持未勾。其余剩余项仍缺 NonTransitivePrimitive、端到端审判台复弹、全平台 lock-only、PBT 和 tainted runtime warning 证据。
- netx 复核结论：`src/runtime/sa_net_uring.zig` 的 loopback 测试确实覆盖 listen/accept、ticket、outbound 和 broadcast，但不等同于任务原文的 curl/wscat/echo、1M fuzz、perf、K1/K2 或 EAGAIN 语义验收。`ConnectionSlot` 仍只有 `outbound_inflight` 布尔和 zc mode，没有 overflow chain 与显式 `inflight_zc` 计数，因此 46.1、49、53、56、60+ 继续不能补勾。
- HubProxy 复核结论：本轮重新构建 `/tmp/hubproxy-smoke` 并用本地 Python chunked SSE upstream 做运行烟测。结果代理只返回 `HTTP/1.1 200 OK`、`transfer-encoding: chunked`、`content-type: text/event-stream` 和空 chunk `0`，未透传 `data: first` / `data: second` 两段 SSE 数据；65c 的“SSE/chunked 流式响应透传”继续不能补勾。
- SAX 复核结论：Phase 1 和部分 Phase 2 已勾项仍有外部插件测试支撑，但剩余项继续缺证据。`docs/sax_syntax.md` 的属性白名单包含 `id/hidden/title/type/readonly/checked/name/src/alt/width/height` 等，宽于当前 parser 的 `class/style/value/placeholder/disabled`；`docs/sax_airlock.md` 也未完整同步 `sax_router_init`、`sax_ftoa_bits` 等生成器细节。因此 89.x 文档维护项不能补勾。
- WASM/Wasmtime 复核结论：当前 PATH 仍没有 `wasmtime`、`wasm-validate`、`wasm-objdump` 或 `wasmparser` 可执行文件，不能证明 Wasmtime debug breakpoint 或独立 wasm validation 类验收。手写 WASM 后端仍对 atomics/SIMD/WASI import 返回 unsupported，v0.2 剩余项保持未勾。
- 诊断与 debug 模式复核结论：8.22 的 CLI 子集已有 `SA-CLI-*`、`sa explain`、`sa fix --plan`、`sa skills` 和 JSON 输出测试，但 trap 侧仍主要是数字 `trap_code`，`docs/errorcode.md` 仍将 `GasExceeded`、`SnapshotVersionMismatch`、`VTableSignatureMismatch` 标为 roadmap-only。`--release` 默认 ReleaseSmall 存在，但没有测试证明产物不含 gas/sanitizer 簿记；`--debug-gas` / `--debug-san` 仍只有文档描述，30.1-30.3 保持未勾。

## Final Closeout Pass 2026-06-01

- 收到“完成评估后写份详细评估保存到 `docs/progress.md`”后做最终收口核验。本轮没有修改实现代码，也没有修改 `tasks.md`；最终计数仍为 301 个未勾选项、376 个已勾选项、677 个任务行。
- 纠正并确认外部插件 build-step 口径：这次所有 `zig build -h` 都在各插件目录作为 `cwd` 执行。`sa_plugin_deno` 只有 `install` / `uninstall`，没有 `test` step；`sa_plugin_pkg`、`sa_plugin_db`、`sa_plugin_sax`、`sa_plugin_http_client`、`sa_plugin_http_server`、`sa_plugin_bc2sa`、`sa_plugin_node`、`sa_plugin_ts` 均暴露 `test` step。该结果支持“Deno 已拆分但无测试入口证据”的结论。
- 机械一致性检查已重跑，且兼容 `- [ ]*` / `- [x]*` 任务标记；结果为 0 个“父项未勾但所有直接子项已勾”的结构性遗漏。此前脚本若不识别星号会误报 35c，但 35c.6 仍是未完成 PBT，因此 35c 父项保持未勾是正确的。
- 按严格完成标准复核后，没有新的可安全补勾项。剩余未勾项主要分为三类：原文功能尚未实现、实现存在但缺测试/运行通过证据、或当前拆分插件架构与任务原文要求不完全一致。
- 最终结论：全部检查已完成。当前可证明完成的特性已经反映在 `tasks.md` 的勾选中；v0.2、v0.3、v0.4、v0.5、v0.6 不能整段全勾，因为仍有明确缺口或缺少验收证据。后续若要提高完成度，应优先修复主仓 Deno facade 链接外部 HTTP client 符号、补齐 Deno 插件 test step、补 DB CLI/register/exec/qmod 与 `.sai` schema 输出、补 pkg 审判台端到端/PBT/tainted runtime 证据、补 WASM atomics/SIMD/WASI/DWARF/Wasmtime 证据。

## Continuation Pass 2026-06-02

- 本轮继续按“有实现和测试证据才勾”的标准，以当前工作区为准重新复核剩余未勾项；没有修改实现代码，也没有新增可安全补勾项。`tasks.md` 计数保持 301 个未勾选项、376 个已勾选项、677 个任务行。
- 当前外部插件 build-step 口径确认：`sa_plugin_bc2sa`、`sa_plugin_db`、`sa_plugin_http_client`、`sa_plugin_http_server`、`sa_plugin_node`、`sa_plugin_pkg`、`sa_plugin_sax`、`sa_plugin_ts`、`sa_plugin_vm` 均有 `test` step；`sa_plugin_deno` 仍只有 `install` / `uninstall`，没有 `test` step。因此 Deno 只能确认独立工程与接口/导出存在，不能确认测试完成。
- 本轮复跑验证命令：`timeout 180 zig test src/common/trap.zig` 通过 8/8；`timeout 240 zig test src/runtime/sa_net_uring.zig -lc` 通过 11/11；`/home/vscode/projects/sa_plugins/sa_plugin_pkg` 的 `timeout 240 zig build test --summary all` 通过 25/25；`/home/vscode/projects/sa_plugins/sa_plugin_db` 的 `timeout 240 zig build test --summary all` 通过 4/4；`/home/vscode/projects/sa_plugins/sa_plugin_sax` 的 `timeout 300 zig build test --summary all` 通过 35/35，Build Summary 39/39。
- 8.22 Agent-First 复核结论不变：`sa explain` / `sa fix --plan` / `sa skills`、`SA-CLI-*` 与 CLI JSON 诊断有实现和测试证据；但任务原文还要求 trap 侧稳定 `SA-XXX` 错误码与统一 trap 词表。当前 trap JSON 仍以数字 `trap_code` 和 `repair` 对象为主，`docs/errorcode.md` 仍把 `GasExceeded`、`SnapshotVersionMismatch`、`VTableSignatureMismatch` 标为 roadmap-only，因此 8.22 不能补勾。
- WASM v0.2 复核结论不变：`src/emit_wasm/opcodes.zig` 明确对 atomics/SIMD/WASI import 返回 `UnsupportedAtomic` / `UnsupportedSimd` / `UnsupportedWasiImport`，且测试断言这些路径暂不支持；DWARF-in-WASM、Wasmtime debug 行号、`#mode compact` 和 32 KB 体积目标仍缺通过证据。因此 v0.2 不能整段补勾。
- pkg 复核结论不变：外部 pkg 插件 `sa pkg fetch/install/audit` 子集通过 25/25 测试，但顶层 `sa fetch` 分支仍直接调用 `fetchPackage(args[2], "HEAD", .{})`，没有完整解析 `-g` / `--ref`；35.5 仍只证明预编译产物拒绝，没有同时证明重复导出与版本冲突；审判台复弹、PBT、tainted runtime warning 和全平台矩阵仍缺端到端证据。
- DB 复核结论不变：外部 DB 插件 4/4 测试证明 schema/table/verify/snapshot/restore/lock/compact 的可用子集，但 `plugin.zig` 的实际命令处理仍只证明 `db init`，`db_stub.zig` 的 register/inspect/exec 仍返回 `UnsupportedOperation`，`schema.ifaceFilePath` 输出 `.iface` 而非任务 1.2 要求的 `.sai`。DB CLI、qmod、Referee DB 权限、mmap/SIGSEGV、Blob、性能和 12 条 Trap 边界仍不能补勾。
- SAX 复核结论不变：外部 SAX 插件 Phase 1 和部分 Phase 2 证据强，35/35 测试通过；但剩余未勾项仍缺 hook 无参无返签名校验、route change mount/unmount、inotify/kqueue 文件监听、WASM 热替换保留状态、VS Code/native/js/WebGPU/package/style 证据。`docs/sax_*` 与 `docs/std_rfc.md` 仍未完全同步外部插件真实实现路径，因此文档维护项不能补勾。
- netx 复核结论不变：`src/runtime/sa_net_uring.zig` 目标测试 11/11 通过，支持当前已勾的 Ticket/layout、HTTP/WS、listen/accept/recv_ticket/outbound/broadcast 子集；但 `ConnectionSlot` 仍缺 overflow chain 与显式 `inflight_zc`，出站满载未暴露任务要求的 `EAGAIN`，也没有 1M fuzz、K1/K2、perf、持续 benchmark 或 RFC 登记证据。
- 机械一致性检查保持通过：未发现“父项未勾但所有直接子项已勾”的结构性遗漏。剩余未勾项不是漏查，而是原文功能尚未实现、缺测试/运行通过证据，或当前拆分插件架构与任务原文要求不完全一致。

## Detailed Reassessment 2026-06-04

- 本轮按用户要求重新做细致完成度评估，并把 `/home/vscode/projects/sa_plugins/` 下新增/迁移的插件一起纳入当前口径。`tasks.md` 当前统计是 677 个任务行，其中 392 已勾、285 未勾；本轮只把文档登记类和架构口径已经闭环的项补勾，没有把缺测试或缺原文语义的宽项强行完成。
- 术语统一：旧英文展开名不再作为 SA/SAX 的展开名；最新文档统一使用 `safe asm` / `安全汇编`，SAX 使用 `safe asm XML` / `安全汇编 XML`。所有权模型里的 `affine` / `仿射` 概念和 Bevy 的 `Affine3A` 数学类型不属于旧项目名，保留不改。
- 主仓全量门禁：`timeout 600 zig build test --summary all` 超时退出 124，期间进入 SA 标准库/矩阵路径并输出 `sa_std/sort.sa`、`core/mem.sa` import 解析，但 10 分钟窗口内未完成，因此不能作为主仓全绿证据。`timeout 180 zig build std-smoke --summary all` 同样超时；`timeout 180 zig build plugin-host-smoke --summary all` 未在窗口内形成通过输出。
- 外部插件当前验证：`sa_plugin_pkg` 25/25 通过，`sa_plugin_db` 4/4 通过，`sa_plugin_sax` 37/37 通过且 Build Summary 39/39，`sa_plugin_http_client` 7/7 通过，`sa_plugin_http_server` 7/7 通过，`sa_plugin_bc2sa` 4/4 通过，`sa_plugin_node` 3/3 通过，`sa_plugin_vm` 7/7 通过，`sa_plugin_wgpu` 5/5 通过。`sa_plugin_deno` 仍只有 install/uninstall step，本轮 `zig build -Doptimize=Debug --summary all` 可构建但没有 test step。`sa_plugin_ts` 当前 Debug 测试 25/26 通过，`benchmark: parsing speed for large input` 因约 812 lines/sec 未超过 1000 lines/sec 阈值失败。
- 3D engine 插件族新增纳入口径：`sa_plugin_3dengines/tools/verify_3d_modules.mjs` 成功验证 24 个 3D engine plugin module 的文件、manifest、依赖和 interface shape；`tools/build_all.mjs` 在 120 秒窗口内跑过 `3d_time`、`3d_app`、`3d_math`、`3d_color`、`3d_shader`、`3d_image`、`3d_transform` 的测试输出后超时，不能作为整族全绿证据。README/Bevy audit 明确还有多模块 behavior pending / Bevy parity 未完成。
- SAX 状态更新：Phase 1 和部分 Phase 2 已经很强，外部插件测试现为 37/37。任务文案和文档已同步为真实外部插件架构：SAX 通过 `/home/vscode/projects/sa_plugins/sa_plugin_sax` runtime plugin 接入，浏览器 WASM 当前走 LLVM-C `.sa.bc` + Zig `wasm32-freestanding -fno-entry --import-symbols`，不再按旧文档声称依赖主仓手写 `src/emit_wasm` / `wasm32-unknown-unknown`。据此补勾 `69`、`72`、`89`、`90` 的文档/架构闭环项；剩余 `79.3`、`80.3`、`81.3`、`82.2`、`82.3`、VS Code/native/js/package/style 等仍未完成。
- NetX 文档登记已补齐：`docs/std_rfc.md` 新增 `sa_netx` 小节，列出 7 条 `sa_netx_*` FFI、当前 `Ticket_*` layout 以及与 `sa_std/net.*` 的并行关系；因此补勾 `67.1` / `67.2`。实现侧仍缺 overflow chain、显式 `inflight_zc`、EAGAIN 背压语义、1M fuzz、K1/K2 和持续 benchmark，因此 46/47/49/52/53/56/58/59-65/68 继续未勾。
- DB 结论保持保守：外部 DB 插件证明 schema/table/verify/snapshot/restore/lock/compact 的可用子集，但 `src/plugin.zig` 的 runtime command 仍只实际处理 `db init`，descriptor skill 列出的 ingest/export/query/run/exec 不能等同实现；`src/db_stub.zig` 的 register/inspect/exec 仍返回 `UnsupportedOperation`；schema 输出仍是 `.iface` 风格而非任务 1.2 的 `.sai`。DB 后续 CLI、qmod、Referee DB 权限、mmap/SIGSEGV、Blob、冷热分层、Zstd/S3、性能和 12 条 Trap 边界继续未完成。
- pkg 结论保持保守：外部 pkg 插件通过 25/25，支持 `sa pkg fetch/install/audit/sum/lock/CI helper` 子集；但任务原文中的顶层 `sa fetch` 完整语义、重复导出与版本冲突、NonTransitivePrimitive、审判台生命周期 PBT、lock idempotency 端到端、tainted runtime warning 和全平台 CI matrix 仍未证明。
- Deno 结论更新为“可构建但无测试入口”：`sa_plugin_deno` 已有 `sap.json`、`deno.sai`、`deno.sal` 和 `libdeno.so` 构建证据，但没有 `zig build test` step。主仓 Deno facade 链接旧阻塞本轮未快速复现为 undefined symbol，但全量主仓测试也未完成，因此仍不能当作最终验收通过。
- 文档更新范围：`tasks.md` 顶部快照、SAX/NetX 文档登记任务；`docs/std_rfc.md` 新增 NetX/SAX 登记；`docs/sax_design.md`、`docs/sax_whitepaper.md`、`docs/sax_airlock.md`、`docs/sax_syntax.md` 同步外部插件真实路径和后端；本节作为最新评估记录追加到 `docs/progress.md`。
