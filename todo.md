# 未完成 TODO

## 标准库
- [x] `sa_std/collections/vec_deque.saasm`
- [x] `sa_std/collections/binary_heap.saasm`
- [x] `sa_std/collections/btree_map.saasm`
- [x] HashMap 开放寻址恢复

## I/O
- [ ] `sa_std/io/buf_reader.saasm`
- [ ] `sa_std/io/buf_writer.saasm`
- [ ] `sa_std/path.saasm`

## 运行时 / 辅助
- [ ] `sa_std/env.saasm`
- [ ] `sa_std/math.saasm`
- [ ] `sa_std/string_format.saasm`
- [ ] `sa_std/sa.mod`（替代旧 `sa.pkg`，按 v0.5 零信任包格式产出）

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

## 单元测试框架（Native Unit Test Framework）
- [ ] 编译器前端支持 `@test` 或宏声明测试用例
- [ ] 提取测试元数据并构建内存 `TestRegistry` 表
- [ ] `src/cli.zig` 增加 `saasm test` 命令与 `filter` 参数支持
- [ ] 动态生成测试驱动器（Test Harness）以隔离或连续执行所有测试
- [ ] `sa_std` 断言宏增强，包含详尽的源文件、行号及 expected/got 差异输出
- [ ] 整合原 bash 冒烟脚本，将其作为 SA 内部测试框架的基线覆盖

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
- [ ] `sa_std` 剩余模块 (buf_reader, math, env)
- [ ] 零信任包管理 v0.5 (task 35)

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
