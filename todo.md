# 未完成 TODO

## 当前优先级
- 当前执行顺序：Rust core 基础闭环收口 -> 标准库收口 -> HTTP Client/Server 插件 -> OpenAI 转发服务 (HubProxy) -> 单元测试框架 -> 零信任包管理 -> `sa_net_uring` 深化。
- 插件完成态只接受 runtime `.so` / hot reload / ABI 版本化 / descriptor 导出 / skills 元数据 / 失败隔离，不接受静态注册、静态库 `.a`、或主线程硬编码分支作为替代。
- 插件任务按目录并发推进：每个 agent 只改自己负责的插件目录和该插件自己的入口文件，不碰主线程命令分发、宿主业务逻辑、或其他插件目录。
- 构建期与运行期分开看：单个插件的编译错误只会影响对应 `.so` 产物与该插件自身测试，不应把已经编出来的宿主二进制退回到静态耦合模型。
- 任何插件任务的审核口径必须明确写出：`runtime .so`、`hot reload`、`skills`、`descriptor`、`失败隔离`、`目录隔离`、`不改主线程`。

## HTTP 增强与 HubProxy (NEW)
- [x] `sa_http_client` 插件实现，目标是独立 `.so`、runtime 热加载、命令一致性测试、HTTP 主路径、流式读取与 runtime descriptor
  - 说明：已补齐 `POST`、自定义 `--header`、请求 body 透传、流式请求 body、以及真实 loopback 回归测试
  - 说明：HTTPS/TLS 出站与证书管理先保留为后续增强，不阻塞当前 HTTP 插件主路径验收
  - 说明：`saasm run` 已接通 `sa_http_client_*` 插件 ABI，SA 侧可以直接调用客户端接口；仓库全量测试仍有独立回归待清理
- [x] `sa_http_server` 插件实现，目标是独立 `.so`、runtime 热加载、scaffold/serve 入口测试、最小 HTTP 响应闭环
  - 说明：已补齐请求头/请求体读取、按路径分发、`/echo` 反射和 `/stream` chunked SSE 回写；后续 HubProxy 仍需 upstream 转发 glue
  - 说明：`saasm run` 已接通 `sa_http_server_*` 插件 ABI，SA 侧可以直接调用服务端接口；仓库全量测试仍有独立回归待清理
- [x] `examples/hubproxy` 实现，作为可运行 OpenAI API 转发示例，不回写主线程分发
- [x] HubProxy 必须具备真实 `main()` 入口、可配置 upstream、路由 `/v1/chat/completions` 和 `/v1/responses`
- [x] HubProxy 必须支持 SSE / chunked 流式透传，不允许退化成一次性缓冲伪流
- [x] HTTP 插件本地验收必须覆盖 descriptor 导出、skills 元数据、命令入口、runtime reload 与失败隔离
- [x] `saasm run` 已接通 `sa_http_client_*` / `sa_http_server_*` 插件 ABI，并保持插件 handle 外部所有权，不回收为普通堆指针
- [ ] 仓库级 HTTP/SA 验收补完：修复 `cli_smoke.zig` 里与 HTTP 无关的既有回归后，再把 301/302 的 `saasm run` 过滤测试纳入主验收

## 可热插拔插件系统
- [x] 插件 ABI 版本号与 `plugin_descriptor` 导出
- [x] 运行时 `.so` 发现 / `dlopen` / `dlsym` / `dlclose`
- [x] 插件热重载与版本切换回归测试
- [x] 单插件失败隔离与结构化诊断
- [x] 至少一个插件完成独立 `.so` 化并可被宿主热加载
- [x] 插件目录隔离：每个插件只改自己的目录，不回写主线程命令分发
- [x] runtime hot reload 为最终形态，禁止把静态注册当成完成标准
- [x] `src/plugin_api.zig` / `src/plugins.zig` 的 runtime ABI/loader 收敛为稳定形态
- [x] `src/sax` 插件 runtime 热重载回归与 descriptor/skills 测试
- [x] `src/db` 插件 runtime 热重载回归与失败隔离测试
- [x] `src/pkg` 插件 runtime 热重载回归与 skills 测试
- [x] `src/llvm2sa` 插件 runtime 热重载回归与命令一致性测试
- [x] `src/http_server` 插件 runtime 热重载回归与 scaffold 入口测试

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
- `sax`、`db`、`llvm2sa`、`http_server` 由各自目录独立推进。
- 允许新增插件自己的辅助文件、测试、文档和 ABI 适配层。
- 不允许把插件功能向 `src/cli.zig` 追加新的静态命令分支来替代 runtime 加载。
- 不允许把插件产物降级回 `.a` 静态库或仅作编译期注册；最终交付必须是可热插拔 `.so`。
- 如果某个插件失败，只能影响这个插件自己的 `.so`、测试和 reload 回归，不得把主线程或其他插件拉回静态模式。
- 任何插件 agent 只允许修改自己负责的插件目录、该插件的本地测试、以及必要的 runtime wrapper；不得跨目录改别的插件，也不得改主线程命令分发。
- 如果需要改宿主，只允许改 runtime loader / 热重载 / 失败隔离这一层；不允许把插件语义回写进静态分发逻辑。

## 标准库
- [x] `sa_std/collections/vec_deque.saasm`
- [x] `sa_std/collections/binary_heap.saasm`
- [x] `sa_std/collections/btree_map.saasm`
- [x] HashMap 开放寻址恢复

## I/O
- [x] `sa_std/io/buf_reader.saasm`
- [x] `sa_std/io/buf_writer.saasm`
- [x] `sa_std/path.saasm`

## 运行时 / 辅助
- [x] `sa_std/env.saasm`
- [x] `sa_std/math.saasm`
- [x] `sa_std/string_format.saasm`
- [ ] `sa_std/sa.mod`（包管理项，后置到 v0.5；不计入当前标准库收口）

## 单元测试框架（Native Unit Test Framework）
- [ ] 编译器前端支持 `@test` 或宏声明测试用例
- [ ] 提取测试元数据并构建内存 `TestRegistry` 表
- [ ] `src/cli.zig` 增加 `saasm test` 命令与 `filter` 参数支持
- [ ] 动态生成测试驱动器（Test Harness）以隔离或连续执行所有测试
- [ ] `sa_std` 断言宏增强，包含详尽的源文件、行号及 expected/got 差异输出
- [ ] 整合原 bash 冒烟脚本，将其作为 SA 内部测试框架的基线覆盖

## 零信任包管理（v0.5，R31 + R31a–R31g）

> 完整设计文档：[`docs/package_management.md`](docs/package_management.md)
> 需求/设计/任务三件套：requirements.md R31–R31g、design.md §3.10 / §4.8、tasks.md task 35 / 35a–35f

### 工程清单 / 数据模型（task 35）
- [ ] `RequireEntry.grants` 缺省值统一为 `&.{}`（绝对零权限）
- [ ] 全树拍平 `sa.sum`：支持 100 依赖 ≤ 200ms

### AST X 光扫描（task 35a，R31d）
- [ ] `src/pkg/audit.zig`：单遍 token 扫描 `@sys_*`，单包 ≤ 50ms
- [ ] Trust Score 算法（100 / 80 / 50 / ≤ 20）
- [ ] `sa audit <URL>` 子命令；`--format json` 输出
- [ ] PBT **P33**：合成 pure/io/net 三类包，断言信用分等级

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
- [ ] `PkgMgr-Fetch-Smoke` / `PkgMgr-Audit-Score`
- [ ] `PkgMgr-Confirm-Tty` / `PkgMgr-Confirm-NonTty`
- [ ] `PkgMgr-Lock-Idempotency` / `PkgMgr-Sum-Transitive`
- [ ] `PkgMgr-Offline-Build` / `PkgMgr-CI-DualTrack`
- [ ] `PkgMgr-Tainted-Artifact` / `PkgMgr-ForbiddenGlobal`
- [ ] `PkgMgr-Mirror-Env` / `PkgMgr-PrecompiledRejected`

### v0.6+ 待决策议题（来自 talk.md，暂未进入需求文档）
- [ ] GPG/SSH 私钥签名 `sa.lock`（"军工级"模式 vs "宽容模式"开关）
- [ ] SARIF 输出 + GitHub Security Tab 集成
- [ ] SA 编译器自签名固件哈希（防御编译器本身被篡改）
- [ ] `sa fetch` X 光报告归档（默认仅 stdout，是否落盘可选）

---

## 极速网络基座与 llvm2sa 战略蓝图 (Claude 架构评估结论)

> 本节确立 SA-ASM 的长期生产力形态：首先通过 `sa_net_uring.zig` 构建 10Gbps+ 的极速 io_uring 网络底层（P0 优先级），然后在第二阶段通过 `llvm2sa`（P2 优先级）将 Rust/C 的无状态计算逻辑无缝、零开销地注入网络流水线。

### P0: 极速 io_uring 网络基座 (当前最高优，打败 Bun 的核心)
- [ ] `sa_net_uring.zig` 核心框架
- [ ] 全局预分配连接池 (Connection Slot Pool，零 allocation)
- [ ] io_uring SQ/CQ 环形轮询与无锁收发 (Zero-syscall overhead)
- [ ] 零拷贝 HTTP DFA 拆包 / WebSocket SIMD 解掩码
- [ ] IORING_OP_SEND_ZC 批量广播 (DMA Fanout)
- [ ] SA FFI 气闸舱对接 (入站/执行/出站三环)

### P1: 现有功能补齐
- [ ] SAX Phase 1 MVP (~1500-2000 行)
- [x] `sa_std` 收口完成（buf_reader, buf_writer, path, env, math, string_format）
- [ ] 零信任包管理 v0.5 (`sa.mod` / task 35)

### P2: `llvm2sa` 管道 (在网络引擎稳定后启动)

> **对称性分析原理**：`emit_llvm.zig` 将 SA 寄存器固化为 `alloca` (Mem-slotting)。`llvm2sa` 通过 `opt -passes=reg2mem` 可以得到完美的、无 `PHI` 节点的 LLVM IR，使得逆向翻译为 SA-ASM 成为可能且工程量极低。由于所有权在 LLVM 层丢失，`llvm2sa` 产出的将是 `Untracked` 模式的 SA-ASM，这对于从已通过安全检查的 Rust 降级而来的业务代码是安全且高性能的。

- [ ] **反向验证 PoC** (~200 行)：手工跑 `opt -passes=reg2mem`，用 Zig 解析 `hello.wasm.saasm.ll` 的 `define`、`gep` 和 `store/load`，还原回 `.saasm`。
- [ ] `src/llvm2sa.zig` (~800-1200 行)：核心文本 `.ll` 解析器与指令逆向翻译。
  - [ ] 降级 `alloca` -> `stack_alloc` / 虚拟寄存器。
  - [ ] 降级 `icmp`, `add`, `br` 为 SA 对等指令。
  - [ ] 降级定长偏移的 GEP (`getelementptr`)。
  - [ ] 降级动态变量偏移的 GEP (利用 `ptr_add` + `mul`)。
- [ ] 外部依赖降级（`call @malloc` / `@free`）。
- [ ] `src/cli.zig` 扩展：增加 `saasm llvm2sa <file.ll>` 子命令。
- [ ] 测试套件集成与黄金文件测试。
