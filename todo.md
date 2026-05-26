# 设计与架构导读 (Design & Architecture Links)

> 在开始实施以下任务前，请务必阅读 `design.md` 中的对应章节以确保实现与架构目标对齐：
> - **物理极限性能架构**：参见 [`design.md §1.10 工业级可伸缩性架构`](.kiro/specs/sa-asm-language/design.md#110-工业级可伸缩性架构-industrial-scalability-architecture---紧急-p0)
> - **宏驱动高级特性**：参见 [`design.md §1.4 宏驱动高级特性演进`](.kiro/specs/sa-asm-language/design.md#14-宏驱动高级特性演进-macro-driven-advanced-features)
> - **零信任包管理**：参见 [`design.md §3.10 包管理子系统`](.kiro/specs/sa-asm-language/design.md#310-包管理子系统new对应-r31r31gv05)
> - **极速网络引擎**：参见 [`design.md §6 网络引擎 sa_netx`](.kiro/specs/sa-asm-language/design.md#§6-sa-极速网络引擎-sa_netxv08--物理打败魔法的网络基座)

---


> **评估结论**：当前 SA 在 10,000+ 函数规模下存在 $O(N^2)$ 内存爆炸风险（指令数 × 全局寄存器数），导致大规模编译 OOM。这是达成“Zig 速度”宗旨的头号障碍，必须立即修复。

- [x] **1. 寄存器 ID 局部化 (Function-Local Register Scoping)**
  - **问题**：目前 `reg_count` 是全局的，函数 A 的快照包含函数 B 的寄存器。
  - **方案**：重构 `flattener.zig` 和 `verifier.zig`，使寄存器 ID 在函数边界内重置。每个函数的校验快照大小仅取决于本函数活跃寄存器数。
- [x] **2. 稀疏状态追踪 (Sparse State Tracking)**
  - **问题**：`AnnotatedInstruction` 为每条指令存储全量掩码数组，内存占用 $\approx$ $O(Inst \times Reg)$。
  - **方案**：仅存储在该指令中**发生状态变更**的寄存器差异（Delta），大幅降低长序列下的内存压强。
- [x] **3. 流式 IR 发射与 Buffer 复用 (Streaming IR & Buffer Reuse)**
  - **问题**：历史 `emit_llvm.zig` legacy text emitter 全量缓存 IR 文本且存在大量字符串拼接；现已从主线删除，防止文本 IR 后门。
  - **方案**：引入 `StreamingEmitter`，边校验边写盘/写管道；使用 `std.SegmentedList` 或高效 Buffer 池减少分配。
- [x] **4. 声明级后端并行化 (Decl-level Backend Parallelism)**
  - **启发**：借鉴 Zig 源码 `Zcu.PerThread` 模型。
  - **方案**：将发射任务打散至函数（Decl）粒度，利用多线程并行驱动后端生成，消除全局巨大 `.bc` 文件的单线程解析瓶颈。
- [x] **5. 内存直通 Emitter (In-memory LLVM bitcode Construction)**
  - **启发**：借鉴 Zig 源码 `codegen/llvm.zig`。
  - **方案**：放弃文本 `.ll` 发射，集成 LLVM C API (llvm-c)。在内存中并发构造指令流，消除磁盘 I/O 和文本解析开销，实现真正的“瞬发级”编译。
  - [x] 核心闭环：默认通过 C shim 调 LLVM-C builder 直接写 `.sa.bc`，覆盖 hello / loop / while / FFI handle，且后端代码无文本 IR parse bridge。
  - [x] 默认纯 `.bc` 流：CLI / SAX 构建默认使用 LLVM-C artifact，`build-exe` / `build-obj` / `build-wasm` / `test` 不再走文本 `.ll` 发射路径；公共库不再导出文本 emitter；SAX 测试替身也不再写 dummy 文本 bitcode，已用真实 LLVM bitcode 魔数和 `llvm-dis` 回归兜底。
  - [x] atomic 覆盖：`atomic_load` / `atomic_store` / `atomic_rmw_*` / `cmpxchg` / `fence` 已走 LLVM-C builder，atomic smoke 通过 `.sa.bc` native 运行。
  - [x] fallible ABI 覆盖：LLVM-C 后端支持 `{i32, payload}` fallible return、fallible call、`?` 分支传播、成功值打包与 main wrapper 状态返回；多层 `?` rosetta smoke 通过。
  - [x] vtable / 间接调用覆盖：LLVM-C 后端支持 vtable 常量、slot provenance、`call_indirect` typed pointer cast，`07_trait_vtable` / `110_trait_super_vtable` / `32_trait_object_vector` 已通过纯 `.sa.bc` native smoke。
  - [x] sys runtime / wasm32 覆盖：LLVM-C 后端内建 `@sys_print` / `@sys_exit` / `@sys_argc` / `@sys_argv` / `@sys_read_file` / `@sys_write_file`，并修正 wasm32 size ABI；`sys_runtime_probe.sa` 已通过 native 与 Node/WASI wasm 运行。
  - [x] mem-slot 等价覆盖：LLVM-C 后端按函数实际寄存器上限分配 entry `i64` slot，普通 SA 寄存器通过 load/store 读写，fallible 聚合保留 SSA；`sort_probe` / `hashmap_probe` / `hashset_probe` / `once_probe` / `mpsc_probe` 已通过纯 `.sa.bc` native smoke，均无 `.ll` 产物。
  - [x] 最小 debug metadata：LLVM-C 后端在纯 `.sa.bc` 流中写入 compile unit / subprogram / instruction location；`build-exe -g` 通过，`llvm-bcanalyzer-14` 可见 `llvm.dbg.cu`，且无 `.ll` 产物。
  - [x] bitcode reader 可读性：修正 LLVM-C sys argv runtime 的 typed-pointer GEP，`sys_runtime_probe.sa` 的 `.sa.bc` 可被 `llvm-dis-14` 严格反汇编，native 运行输出 `ok`，且无 `.ll` 产物。
  - [x] 变量级 debug metadata：LLVM-C 后端在 debug 模式下为函数参数和 SA slot alloca 写入 `llvm.dbg.declare` / `DILocalVariable`；`build-exe -g` 产物可被 `llvm-dis-14` 反汇编并可见变量元数据，native 运行输出 `21`，且无 `.ll` 产物。
  - [x] wasm sys runtime E2E：`sys_runtime_probe.sa` 已在 `tests/cli_smoke.zig` 中覆盖 native + wasm32-WASI 双轨，验证 argv、文件读写、打印、退出码、`.wasm.sa.bc` 产物和 Node/WASI 运行，且无 `.ll` 产物。
  - [x] wasm demo matrix 等价覆盖：新增独立 `zig build wasm-matrix` rosetta/support native + wasm32-WASI 双轨矩阵，覆盖 110 个 demo：基础 print/control-flow/struct/array/slice/string/loop/while/break/nested-loop/factorial/fibonacci、mutability/box/reference/move/borrow/refcount/resource、常量结构体、Option、generic、method、associated fn、enum/match/tuple/destructuring/tagged union、iterator map/filter/fold、module/import/export/config、cache/mem fill/queue、router/parser/serializer、service/pipeline/graph/component、metrics/workflow/kv/sql/blob/sync/scheduler、protocol/text/job/db/query/log/build/release、state/event/channel/actor/async/counter、fallible `?`/Result、vtable/trait object、callback contract、sort/hashmap/hashset/once/mpsc；修正 wasm32 vtable 固定 8 字节槽宽 ABI，补 `sa_time_sleep_ns` fallible weak fallback，并补 LLVM-C `struct_` 常量字节展开；验证通过且主线不保留文本 LLVM 产物路径，并已从 `cli_smoke` 拆出以降低单项验证编译成本。
  - [x] 等价覆盖：现有 rosetta/support native stdout smoke demos 已全部纳入 wasm/native 等价矩阵；argv / panic-hook 命名 demo 当前源码为纯确定性输出，也已覆盖。

---



## 极简格式化打印 (Minimal Formatted Printing)
为了提升开发者体验，计划在 `sa_std` 中实现类似 Rust 的高层级打印宏（基于变长宏特性）：

- [x] **1. `PRINT!` / `FORMAT!` 静态展开宏**
  - 功能：解析 `%fmt` 字符串字面量，自动拆解为 `STRFMT_*` 调用链。
  - 约束：展开结果必须符合所有权契约，自动清理中间生成的 `^ptr`。
- [x] **2. 结构体自动反射打印 (`{:?}`)**
  - 功能：`sa layout --format debug` 生成自包含布局 `#def` + `DEBUG_PRINT_<Type>` 静态宏，当前覆盖 `i64` / `u64` / `f64` 字段；不支持字段输出 `<unsupported:ty>` 占位，避免生成不可编译调用。
- [x] **3. 零分配打印模式 (No-Alloc Printing)**
  - 功能：`sa_fmt_i64_into` / `sa_fmt_u64_into` / `sa_fmt_f64_into` / `sa_fmt_bool_into` / `sa_fmt_bytes_into` 直接写入调用方提供的缓冲区并返回长度，空间不足返回 `SA_STD_ERR_TRUNCATED`；`STRFMT_*_INTO` 宏已暴露该路径，避免创建 owned fmt buffer。

---

## 宏系统后续演进 (Macro Evolution)
为了支撑类似 Bevy/ECS 的工业级框架重构，计划引入以下极简宏增强（保持 Zero-AST 原则）：

- [x] **1. 变长参数支持 (Variadic Macro Parameters)**
  - 语法：`[MACRO] SYS %name, %params...`；仅最后一个形参允许 `...`，展开时 `%params` 替换为剩余实参的 `, ` 拼接文本，零个剩余实参替换为空字符串。
  - 场景：自动展开任意数量组件的查询与借用。
- [x] **2. 编译期条件分支 (Macro-time Conditionals)**
  - 语法：`[IF %is_mut] ... [ELSE] ... [END_IF]`；条件支持 `1/true/yes/on` 与 `0/false/no/off/空`，支持嵌套分支。
  - 场景：根据组件读写标记自动发射 `&` 或 `=&`。
- [x] **3. 工具辅助增强 (Enhanced sa layout)**
  - 功能：`sa layout --format dict` 导出 `LAYOUT_<Type>_*` 查找常量，覆盖结构体总大小/对齐和字段 offset/size/align，字段类型以注释形式输出，供宏按组件名拼接偏移量。
  - 哲学：复杂度留给工具，极简留给宏。

---

## 宏驱动高级特性演进 (Macro-Driven Advanced Features)
为了保持 SA-ASM 的核心指令集（ISA）极简（Zero-ISA 扩展），且同时具备等同于 Rust 的高级特性，我们确立了**纯宏与静态校验驱动**的实现路线。以下是后续亟待通过 `[MACRO]` 和 `referee.zig` 实现的 5 大特性（优先级按从高到低）：

- [ ] **1. 动态分发与间接调用 (Defunctionalization 代替 `dyn Trait`)**
  - **痛点**：目前 SA 缺乏 `call_indirect` 函数指针指令，无法优雅实现事件循环（Event Loop）和插件钩子。
  - **实现方案**：坚决不修改 ISA。通过宏 `[MACRO] DISPATCH` 生成基于 Enum Tag 的静态分支路由树（`eq` + `br`），实现去功能化（Defunctionalization），以 O(log N) 的极低性能损耗模拟动态分发。
- [ ] **2. 安全的枚举与模式匹配 (Tagged Unions / Sum Types)**
  - **痛点**：通过原生内存偏移和整数标记手工模拟 `Option/Result` 极易引发内存安全或越界漏洞。
  - **实现方案**：通过定义标准宏 `[MACRO] MATCH_RESULT`，自动根据内存 Layout 中的 Tag 执行安全解包和条件分支跳转（Exhaustive Match），屏蔽底层的裸指针计算。
- [ ] **3. 细粒度的结构体字段级借用 (Disjoint Field Borrows)**
  - **痛点**：目前 `referee.zig` 将借用绑定在整块内存上，造成网络引擎中大结构体（如 `ConnectionSlot`）频繁整块锁死。
  - **实现方案**：不增加任何新语法，仅强化编译器 `referee.zig` 中对 `ptr_add` 的识别。让编译器认识到借用 `ptr_add obj, 4` 和 `ptr_add obj, 8` 是独立互不干涉的。
- [ ] **4. RAII 自动清理与 Drop 语义保护**
  - **痛点**：异常路径或中途 `return` 极易漏写 `!p` 导致内存或文件描述符泄漏。
  - **实现方案**：不引入运行时的 `defer`，而是通过强制规范化的作用域收尾宏（如 `[MACRO] DROP_AND_RETURN`）将资源释放指令与 `return` 强制捆绑。
- [ ] **5. 跨线程安全边界约束 (Send / Sync 类似机制)**
  - **痛点**：`sa_net_uring` 中的 SpscRing 进行线程间通信时，缺乏机制保证指针跨核心的安全传递。
  - **实现方案**：在 `verifier.zig` 层面增加对 Capability 的多线程逃逸校验，保障跨核数据投递不发生 Data Race。

## Rust Core 核心模式需求表
为了补齐 Rust 核心语义的低层实现路径，后续需要把以下模式稳定落到宏、布局文件和 Referee 约束上：

- [x] **1. 内部可变性模式 (Cell / RefCell)**
  - `Cell` 走单字段 `store` 包装
  - `RefCell` 走借用计数器 + 显式归零宏
  - 借用计数不为 0 时的独占借用必须回退或 Trap
- [x] **2. 共享所有权模式 (Rc / Arc / Weak)**
  - 控制块采用 Strong / Weak 双计数模型
  - `Rc::clone` / `Rc::drop` / `Weak::upgrade` / `Weak::drop` 都必须有可验证的布局与级联顺序
  - 对齐要求必须显式写入 `.sal`
- [x] **3. SA 原生单测覆盖 (cell / refcell / rc / weak)**
  - `tests/rust_core_unit.sa` 已补齐 `CELL_*` / `REFCELL_*` / `RC_*` / `WEAK_*` 的 SA 单测
  - 单测入口改为仓库内相对导入，避免依赖外部安装态旧标准库
- [x] **3. 异步与多态模式 (Waker / Trait Object)**
  - `Waker` 走 vtable 或等价函数指针表
  - Trait Object 继续采用胖指针布局与间接调用
  - 宏展开末尾必须清理临时寄存器并避免标签冲突

## 需求落点
- [x] 将上述 Rust core 模式补入 `.kiro/specs/sa-asm-language/requirements.md` / `design.md`
- [x] 将 `docs/faq.md` 中关于 `Cell` / `RefCell` / `Rc` / `Arc` / `Weak` 的边界解释补齐
- [x] 为对应模式补充后续的 tasks 追踪项，确保最终实现以宏和布局文件为主，不回写到 ISA

## 当前优先级
- 当前执行顺序：Rust core 基础闭环收口 -> 标准库收口 -> HTTP Client/Server 插件 -> OpenAI 转发服务 (HubProxy) -> 单元测试框架 -> 零信任包管理 -> `sa_net_uring` 深化。
- 插件完成态只接受 runtime `.so` / hot reload / ABI 版本化 / descriptor 导出 / skills 元数据 / 失败隔离，不接受静态注册、静态库 `.a`、或主线程硬编码分支作为替代。
- 插件任务按目录并发推进：每个 agent 只改自己负责的插件目录和该插件自己的入口文件，不碰主线程命令分发、宿主业务逻辑、或其他插件目录。
- 构建期与运行期分开看：单个插件的编译错误只会影响对应 `.so` 产物与该插件自身测试，不应把已经编出来的宿主二进制退回到静态耦合模型。
- 任何插件任务的审核口径必须明确写出：`runtime .so`、`hot reload`、`skills`、`descriptor`、`失败隔离`、`目录隔离`、`不改主线程`。

## HTTP 增强与 HubProxy (NEW)
- [x] `sa_http_client` 插件实现，目标是独立 `.so`、runtime 热加载、命令一致性测试、HTTP 主路径、流式读取与 runtime descriptor
  - 说明：已在 `/home/vscode/projects/sa_plugins/sa_plugin_http_client` 独立工程完成，补齐 `POST`、自定义 `--header`、请求 body 透传、流式请求 body、HTTPS/TLS 出站与证书管理，以及真实 loopback 回归测试
  - 说明：`sa run` 已接通 `sa_http_client_*` 插件 ABI，SA 侧可以直接调用客户端接口；仓库全量测试仍有独立回归待清理
- [x] `sa_http_server` 插件实现，目标是独立 `.so`、runtime 热加载、scaffold/serve 入口测试、最小 HTTP 响应闭环
  - 说明：已在 `/home/vscode/projects/sa_plugins/sa_plugin_http_server` 独立工程完成，补齐请求头/请求体读取、按路径分发、`/echo` 反射、`/stream` chunked SSE 回写，以及 scaffold/serve 回归测试；后续 HubProxy 仍需 upstream 转发 glue
  - 说明：`sa run` 已接通 `sa_http_server_*` 插件 ABI，SA 侧可以直接调用服务端接口；仓库全量测试仍有独立回归待清理
- [x] `examples/hubproxy` 实现，作为可运行 OpenAI API 转发示例，不回写主线程分发
- [x] HubProxy 必须具备真实 `main()` 入口、可配置 upstream、路由 `/v1/chat/completions` 和 `/v1/responses`
- [x] HubProxy 必须支持 SSE / chunked 流式透传，不允许退化成一次性缓冲伪流
- [x] HTTP 插件本地验收必须覆盖 descriptor 导出、skills 元数据、命令入口、runtime reload 与失败隔离
- [x] `sa run` 已接通 `sa_http_client_*` / `sa_http_server_*` 插件 ABI，并保持插件 handle 外部所有权，不回收为普通堆指针
- [x] 仓库级 HTTP/SA 验收补完：301/302 HTTP SAASM demo 已纳入 `cli-special` 主验收，`zig build test --summary all` 覆盖并通过。

## 可热插拔插件系统
- 现阶段插件实现已外置到 `/home/vscode/projects/sa_plugins/` 的独立工程；主仓库只保留薄宿主层、ABI 约定和最小 loader 入口，不再承载插件业务逻辑。
- [x] 插件 ABI 版本号与 `plugin_descriptor` 导出
- [x] 运行时 `.so` 发现 / `dlopen` / `dlsym` / `dlclose`
- [x] 插件热重载与版本切换回归测试
- [x] 单插件失败隔离与结构化诊断
- [x] 至少一个插件完成独立 `.so` 化并可被宿主热加载
- [x] 插件目录隔离：每个插件只改自己的目录，不回写主线程命令分发
- [x] runtime hot reload 为最终形态，禁止把静态注册当成完成标准
- [x] `runtime ABI module` / `runtime loader boundary` 的 runtime ABI/loader 收敛为稳定形态
- [x] `sax` 外部插件 runtime 热重载回归与 descriptor/skills 测试
- [x] `sax` 外部插件 Phase 1 自动化闭环：Parser/Lowerer/Airlock/HTML shell/`sa sax check|build|new` 已由插件本地 `zig build test --summary all` 覆盖；Counter / TodoList / typed-state demos 覆盖真实 `app.wasm + airlock.js` Node 运行时挂载、点击更新、输入框读写和 `i32` / `i1` / `f64 bits` 插值，7 条 SAX trap 负向路径、Airlock 对 `<script>` / `innerHTML` / `onclick=eval(...)` 的拒绝路径、以及 CLI exit code 映射均已自动验收
- [x] `db` 外部插件 runtime 热重载回归与失败隔离测试
- [x] `pkg` 外部插件 runtime 热重载回归与 skills 测试
- [x] `pkg` 外部插件 `install`/`fetch` runtime 命令一致性测试，`install` 无参数读取 `sa.mod` 并真实 vendor 依赖，`install <identity>` 复用真实 fetch 路径
- [x] `bc2sa` 外部插件 runtime 热重载回归与命令一致性测试
- [x] `http_server` 外部插件 runtime 热重载回归与 scaffold 入口测试

### 插件验收口径
- 宿主保持最小职责：发现、加载、卸载、热重载、运行时派发、失败隔离。
- 每个插件目录独立交付自己的 `.so`、skills 元数据、命令实现、生命周期钩子和回归测试。
- 运行时遇到坏插件时必须可跳过并打印结构化诊断，不应阻止其他插件加载，也不应影响已加载插件的派发。
- 构建期遇到坏插件时只影响对应插件产物与构建目标，不应回写到主线程命令分发逻辑。
- 任何“完成”都必须以 runtime hot reload 为准，不接受仅静态编译通过或仅本地函数调用通过。
- 每个插件必须有自己的 `.so` 产物、descriptor 导出、skills 元数据、命令入口、和插件本地测试。
- 插件编译失败只允许让该插件的 `.so` 和插件本地测试失败，不得要求宿主切回静态注册模型。
- 任何插件实现都必须允许同名新 `.so` 覆盖旧版本，并通过 reload 回归证明切换生效。
- 插件验收必须同时覆盖：runtime 发现、descriptor 读取、skills 收集、命令执行、热重载、失败隔离。

### 当前插件切分规则
- `sax`、`db`、`bc2sa`、`http_server` 由各自目录独立推进。
- 允许新增插件自己的辅助文件、测试、文档和 ABI 适配层。
- 不允许把插件功能向 `src/cli.zig` 追加新的静态命令分支来替代 runtime 加载。
- 不允许把插件产物降级回 `.a` 静态库或仅作编译期注册；最终交付必须是可热插拔 `.so`。
- 如果某个插件失败，只能影响这个插件自己的 `.so`、测试和 reload 回归，不得把主线程或其他插件拉回静态模式。
- 任何插件 agent 只允许修改自己负责的插件目录、该插件的本地测试、以及必要的 runtime wrapper；不得跨目录改别的插件，也不得改主线程命令分发。
- 如果需要改宿主，只允许改 runtime loader / 热重载 / 失败隔离这一层；不允许把插件语义回写进静态分发逻辑。

## 标准库
- [x] `sa_std/collections/vec_deque.sa`
- [x] `sa_std/collections/binary_heap.sa`
- [x] `sa_std/collections/btree_map.sa`
- [x] HashMap 开放寻址恢复

## I/O
- [x] `sa_std/io/buf_reader.sa`
- [x] `sa_std/io/buf_writer.sa`
- [x] `sa_std/path.sa`

## 运行时 / 辅助
- [x] `sa_std/env.sa`
- [x] `sa_std/math.sa`
- [x] `sa_std/string_format.sa`
- [x] `sa_std/sa.mod`（包管理项，后置到 v0.5；不计入当前标准库收口）

## 单元测试框架（Native Unit Test Framework）
- [x] 编译器前端支持 `@test` 声明测试用例，含 `ignored` / `should_panic` 修饰符，并由 verifier 强制无返回值签名
- [x] 提取测试元数据并构建内存 `TestRegistry` 表（`test_meta.TestList` / `TestDescAndFn`）
- [x] `src/cli.zig` 增加 `sa test` 命令与 `--filter` / `--skip` / `--exact` / `--ignored` / `--include-ignored` 参数支持
- [x] 动态生成测试驱动器（Test Harness）并按 `SA_TEST_NAME` 隔离子进程执行，支持 `--jobs` 并行调度
- [x] `sa_std` 断言宏增强：新增 `ASSERT_TRUE_MSG` / `ASSERT_EQ_MSG` / `ASSERT_NE_MSG`，调用者可携带源文件、行号及 expected/got diff 到 `panic_msg`
- [x] `sa_std/testing/mock_io.sa` / `.sal` 基础 Mock I/O：内存缓冲支持 init/write/read/rewind/len/pos，并由 `sa test` 回归覆盖
- [ ] 整合原 bash 冒烟脚本，将其作为 SA 内部测试框架的基线覆盖（已有 `tests/unit_framework/feature_suite.sa` demo-derived 基线；已迁入二十八批控制流/递归/迭代、Rust core 语义、trait/vtable、tuple/destructuring、array/slice、associated fn/method、closures、guard、iterator map/filter、impl state、export visibility、config merge、enum branch、newtype/generic/router、cache、mem fill、state machine、parser/serializer、integration/pipeline/graph、scene/component/metrics/workflow/sql/blob/sync/scheduler/protocol/text-index、job/app/db/query/log/task/sync-service/build/release/full-app、drop/RAII/labeled-break/if-let/let-else/cell/refcell/atomic/vtable-super、extern/raw-pointer/union/callback/opaque/variadic/global/simd/volatile、rwlock/condvar/barrier/tls/once/mpmc/hazard/rcu/seqlock/park-unpark、waker/pinning/select/join/async-stream/executor/io-uring/epoll/cancellation/yield、DST/ZST/never/phantom/opaque/repr-layout、global-alloc/layout/box/raw/arena/slab/aligned/custom-DST/mem-forget/manually-drop、GAT/auto-trait/object-safety/upcasting/blanket/specialization/const-generic/TAIT/negative-impl/marker-trait、dynamic-error/color-eyre/catch-unwind/backtrace/thiserror/result-flattening/panic-hook/assert/Try-v2、fd/mmap/signal/pthread/dlopen/sqlite/opengl/websocket/protobuf/base64、macro/proc-macro/attribute/cfg/build-script/LTO/PGO/CFI/ASAN/quine、package manifest/dependency/workspace/conflict diagnostic、workspace inheritance/feature flags/target deps/profile/metadata/bin/dynamic lib、module import/visibility/reexport/namespace/iface/layout/prelude diagnostic、directory/conditional/alias/unused/transitive/extern-group/inline/path-order/version-suffix/entry-override、contract layout/opaque/sig diagnostic/vtable/generic/semver/ffi/macro/const、resource/error-code/callback/plugin/allocator/panic/log/tls/static-init/deprecated、build-codegen/bindgen/asset/env/linker/hooks/cross-compile/sysroot、build optimization/sanitizer/test-harness/bench/doc/cache/parallel/repro/remote/ci、FFI wrapper/linkage/export/opaque-handle/callback-thunk、ecosystem host/memory/embedded/kernel/BPF/GPU/ECS/crypto/LSP/registry 用例，尚未全量迁移 `test_all_300.sh`）

## 零信任包管理（v0.5，R31 + R31a–R31g）

> 完整设计文档：[`docs/package_management.md`](docs/package_management.md)
> 需求/设计/任务三件套：requirements.md R31–R31g、design.md §3.10 / §4.8、tasks.md task 35 / 35a–35f

### 工程清单 / 数据模型（task 35）
- [ ] `RequireEntry.grants` 缺省值统一为 `&.{}`（绝对零权限）
- [x] 全树拍平 `sa.sum`：支持 100 依赖 ≤ 200ms

### AST X 光扫描（task 35a，R31d）
- [x] `src/pkg/audit.zig`：单遍 token 扫描 `@sys_*`，单包 ≤ 50ms
- [x] Trust Score 算法（100 / 80 / 50 / ≤ 20）
- [x] `sa audit <URL>` 子命令；`--format json` 输出
- [x] PBT **P33**：合成 pure/io/net 三类包，断言信用分等级

### 模块级零权限沙箱（task 35b，R31c）
- [ ] 源码物理路径 → 所属包反推
- [ ] `Trap: UnauthorizedPrimitive`（含 `upstream_loc` + grants 列表）
- [ ] `Trap: NonTransitivePrimitive`（零权限包跨包能力提升拦截）

### 破窗确权审判台（task 35c，R31e）
- [ ] `src/pkg/confirm.zig`：`BLOCKED_RISK` 内存态机
- [ ] 完整 URL 字符串校验（不接受 y/n 简写、不接受裁剪）
- [ ] TTY 探测 + `MissingTtyForConfirmation`
- [ ] 拒绝 `--yes` / `--auto-approve` 在 TTY 模式下绕过
- [ ] PBT **P35**：零状态生命周期（进程退出蒸发，绝不写盘）

### 指令级哈希钉版与项目级孤岛（task 35d，R31f）
- [ ] `src/pkg/lock.zig`：机器码 SHA-256 → `sa.lock`（仅项目根）
- [ ] 增量哈希命中跳过审判（AOT 红利）
- [ ] `Trap: MachineCodeHashMismatch` + 重弹审判台
- [ ] `sa audit --update-lock` 子命令（**唯一**允许写 `sa.lock` 的命令）
- [ ] `sa build --all-targets --lock-only`：全平台机器码哈希并行写入
- [ ] PBT **P34**：源码 SHA / 机器码 SHA 双轨独立性
- [ ] PBT **P36**：项目级孤岛信任不漂移

### CI/CD 双轨执行 + 内网/断网（task 35e，R31g）
- [ ] `src/pkg/ci.zig`：自动探测 CI 模式（`CI` / `GITHUB_ACTIONS` / `isatty` / `--ci`）
- [ ] 双轨核验（grants + 源码 SHA）
- [ ] 默认冷酷熔断 vs `--allow-unaudited-risks` 染色放行
- [ ] 染色产物元数据 `TAINTED_UNAUDITED_CODE` + 运行时 stderr 红字
- [ ] `sa build --offline` 完全断网
- [ ] `src/pkg/mirror.zig`：`SA_MIRROR_<HOST>` 环境变量 / 项目本地 `.sa_env`
- [ ] `Trap: ForbiddenGlobalConfig`（探测 `~/.sa/*.toml` / `/etc/sa/*` 立即拒绝启动）
- [ ] 全平台 CI 矩阵核验（Ubuntu / Windows / macOS Runner）
- [ ] PBT **P37**：CI 模式探测非欺骗性

### 包管理集成测试基线（task 35f，design.md §8.5 第 16–27 条）
- [x] `PkgMgr-Fetch-Smoke` / [x] `PkgMgr-Audit-Score`
- [ ] `PkgMgr-Confirm-Tty` / `PkgMgr-Confirm-NonTty`
- [ ] `PkgMgr-Lock-Idempotency` / [x] `PkgMgr-Sum-Transitive`
- [ ] `PkgMgr-Offline-Build` / `PkgMgr-CI-DualTrack`
- [ ] `PkgMgr-Tainted-Artifact` / `PkgMgr-ForbiddenGlobal`
- [ ] `PkgMgr-Mirror-Env` / [x] `PkgMgr-PrecompiledRejected`

### v0.6+ 待决策议题（来自 talk.md，暂未进入需求文档）
- [ ] GPG/SSH 私钥签名 `sa.lock`（"军工级"模式 vs "宽容模式"开关）
- [ ] SARIF 输出 + GitHub Security Tab 集成
- [ ] SA 编译器自签名固件哈希（防御编译器本身被篡改）
- [ ] `sa fetch` X 光报告归档（默认仅 stdout，是否落盘可选）

---

## 极速网络基座与 bc2sa 战略蓝图 (Claude 架构评估结论)

> 本节确立 SA-ASM 的长期生产力形态：首先通过 `sa_net_uring.zig` 构建 10Gbps+ 的极速 io_uring 网络底层（P0 优先级），然后在第二阶段通过 `bc2sa`（P2 优先级）将 Rust/C 的无状态计算逻辑无缝、零开销地注入网络流水线。

### P0: 极速 io_uring 网络基座 (当前最高优，打败 Bun 的核心)
- [ ] `sa_net_uring.zig` 核心框架
- [ ] 全局预分配连接池 (Connection Slot Pool，零 allocation)
- [ ] io_uring SQ/CQ 环形轮询与无锁收发 (Zero-syscall overhead)
- [ ] 零拷贝 HTTP DFA 拆包 / WebSocket SIMD 解掩码
- [ ] IORING_OP_SEND_ZC 批量广播 (DMA Fanout)
- [ ] SA FFI 气闸舱对接 (入站/执行/出站三环)

### P1: 现有功能补齐
- [x] SAX Phase 1 MVP 自动化闭环（外部插件 `/home/vscode/projects/sa_plugins/sa_plugin_sax`；已覆盖真实 `app.wasm + airlock.js` Node 运行时挂载、Counter `+1/-1/reset`、TodoList 增删项与输入框读写、typed-state/dashboard 事件更新、7 条 SAX trap 负向路径、Airlock 对 `<script>` / `innerHTML` / `onclick=eval(...)` 的拒绝路径，以及 CLI exit code 映射；三浏览器人工点击与 React 体积对比仍按 `tasks.md` 保留为未验收项）
- [x] `sa_std` 收口完成（buf_reader, buf_writer, path, env, math, string_format）
- [ ] 零信任包管理 v0.5 (`sa.mod` / task 35)

### P2: `bc2sa` 管道 (在网络引擎稳定后启动)

> **对称性分析原理**：`emit_llvm_llvmc.zig` 将 SA 寄存器固化为 entry mem-slot（基于 LLVM-C builder）。`bc2sa` 通过 `opt -passes=reg2mem` 可以得到完美的、无 `PHI` 节点的 LLVM bitcode，使得逆向翻译为 SA-ASM 成为可能且工程量极低。由于所有权在 LLVM 层丢失，`bc2sa` 产出的将是 `Untracked` 模式的 SA-ASM，这对于从已通过安全检查的 Rust 降级而来的业务代码是安全且高性能的。

- [ ] **反向验证 PoC** (~200 行)：手工跑 `opt -passes=reg2mem`，用 LLVM-C bitcode reader 读取 `hello.out.sa.bc` 后降级 `define`、`gep` 和 `store/load`，还原回 `.sa`。
- [ ] `src/bc2sa.zig` (~800-1200 行)：LLVM bitcode reader与指令逆向翻译。
  - [ ] 降级 `alloca` -> `stack_alloc` / 虚拟寄存器。
  - [ ] 降级 `icmp`, `add`, `br` 为 SA 对等指令。
  - [ ] 降级定长偏移的 GEP (`getelementptr`)。
  - [ ] 降级动态变量偏移的 GEP (利用 `ptr_add` + `mul`)。
- [ ] 外部依赖降级（`call @malloc` / `@free`）。
- [ ] `src/cli.zig` 扩展：增加 `sa bc2sa <file.bc>` 子命令。
- [ ] 测试套件集成与黄金文件测试。

### sa_std: Standardized Derive and Trait Simulation Macros
- [x] **Establish "Naming Contracts" for Derived Operations:** Define a standard naming convention for operations that would typically be derived in Rust (e.g., `[MACRO] {STRUCT}_CLONE`, `[MACRO] {STRUCT}_FREE`, `[MACRO] FMT_{STRUCT}`).
- [x] **Implement `sa_std/core/derive.sa`:** Create a new module providing generic structural operation macros (e.g., `STRUCT_COPY`, `STRUCT_EQ_FIELD`) to aid LLMs and frontends in generating boilerplate code for complex types.
- [x] **Standardize `DISPATCH` and Trait Simulation:** Solidify the `[MACRO] DISPATCH` pattern for defunctionalized dynamic dispatch and standardize the usage of `trait_object.sa` for explicit vtable dispatch where required.

### sa_std: Macro Priority for Data-Structure Portability
优先补下面几类宏，它们会直接提升当前这类数据结构移植的速度。优先级按“最值得先做”的顺序排列：

优先级建议：先做容器构造与字段访问、`Option` / `Result` 便捷宏、循环与索引宏，再补位运算 / 掩码、哈希与容器 probe、资源清理、结构化控制流糖衣。

1. 容器构造与字段访问宏
   - `STRUCT_NEW`
   - `FIELD_GET`
   - `FIELD_SET`
   - `STRUCT_FREE`
   - `PTR_FIELD`
   - 用途：初始化结构体时少写很多 `alloc + store`；读写字段时少写重复 `load/store`；让代码更接近 Rust 里的 `self.field`。
   - 直接收益：对 `stack` / `queue` / `heap` / `linked_list` / `union_find` / `hash_table` / `fenwick_tree` 这一类重复样板压缩最明显。
2. `Option` / `Result` 便捷宏
   - `OPTION_MATCH_SOME_NONE`
   - `OPTION_UNWRAP_OR_RETURN`
   - `RESULT_MATCH_OK_ERR`
   - `RESULT_RETURN_ERR`
   - `RESULT_MAP_OK`
   - `RESULT_IS_OK` / `RESULT_IS_ERR` 的更高层封装
   - 用途：少写分支标签、清理寄存器、错误返回路径。
   - 直接收益：对 `trie` / `bloom_filter` / `segment_tree` / `graph` 很有价值。
3. 循环与索引宏
   - `FOR_RANGE`
   - `WHILE`
   - `WHILE_COND`
   - `INDEX_LOOP`
   - `ARRAY_FOR_EACH`
   - `ARRAY_SCAN_MIN/MAX`
   - `SLICE_GET_U64`
   - 用途：把手写 `jmp` / `branch` / `idx_slot` 变成模板展开。
   - 直接收益：降低 `PhiStateConflict` 和循环临时寄存器泄漏，`segment_tree` / `rmq` / `bloom_filter` / `count_min_sketch` 会明显更稳。
4. 位运算 / 掩码宏
   - `BIT_SET`
   - `BIT_GET`
   - `BIT_CLEAR`
   - `BIT_TEST`
   - `BIT_MASK`
   - `BIT_INDEX_BYTE`
   - `BIT_INDEX_BIT`
   - 用途：让 `bloom_filter` / `bitset` / `bitmap` / 压缩型 `segment tree` 少写 byte/bit 计算。
5. 哈希与容器 probe 宏
   - `HASH_PTR`
   - `HASH_MIX`
   - `HASH_MOD`
   - `PROBE_START`
   - `PROBE_NEXT`
   - `MAP_LOOKUP`
   - `MAP_INSERT_OR_UPDATE`
   - 用途：封装散列、探测与分支。
   - 直接收益：降低 `hashmap` / `hashset` / `bloom_filter` / `count_min_sketch` 的移植错误密度。
6. 资源清理宏
   - `DEFER`
   - `CLEANUP_ON_ERROR`
   - `WITH_TEMP`
   - `RETURN_CLEAN`
   - `FREE_AND_RETURN`
   - 用途：统一临时 alloc、失败路径和资源释放。
   - 直接收益：减少漏写 `!reg` 的问题，也能缓和很多 `UseAfterMove` 和控制流清理顺序问题。
7. 结构化控制流糖衣
   - `IF`
   - `ELSE`
   - `ELIF`
   - `MATCH_BOOL`
   - `MATCH_OPTION`
   - `MATCH_RESULT`
   - `WHILE_LET`
   - `BREAK_IF`
   - `CONTINUE_IF`
   - 用途：让算法代码更接近 Rust。
   - 约束：只做低层展开糖衣，不引入新的语义层，否则调试会更难。

### sa_std: macro test policy
- 每个新宏族都必须补 SA 单测。
- 先做存在性 smoke，再做行为测试。
- 新宏测试优先放入 `tests/rust_core_unit.sa`，必要时拆出独立宏测试文件。

### sa_std: Advanced Core Macros (Arc, RwLock, Full RefCell)
- [x] **Implement `sa_std/core/arc.sa`**: Provide atomic reference counting (Arc) for multi-threaded shared ownership, mirroring `Rc` but using atomic RMW operations.
- [x] **Enhance `RefCell` for Shared Borrows**: Update `refcell.sa` to support multiple shared borrows (readers) and one exclusive borrow (writer), utilizing a signed or bit-masked counter.
- [x] **Implement `sa_std/sync/rwlock.sa`**: Provide a multi-reader, single-writer lock based on atomic state transitions.
- [x] **Standardize `Box` Macros**: Add `BOX_NEW` and `BOX_FREE` to `sa_std/core/mem.sa` for consistent heap management ergonomics.
