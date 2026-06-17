# SA 多 Agent 并发开发协议（草案）

> **文档版本**：v0.1-草案 / 2026-06-15
> **状态**：仅规范，不含实现代码
> **目标读者**：SA 内核开发者、外部插件 / 业务工程使用者、多 LLM Agent 协调者
> **关联文档**：
> - [`design.md §3.1`](./design.md) 源码文本协议（`.sa` / `.sai` / `.sal`）
> - [`design.md §3.10`](./design.md) 包管理与 `sa.lock`
> - [`faq.md`](./faq.md) "为什么没有 X" 设计哲学
> - [`agent_first_toolchain.md`](./agent_first_toolchain.md) Agent-First CLI / `--json`
> - [`kernel_improvement_evaluation_cn.md`](./kernel_improvement_evaluation_cn.md) 内核改进评估

---

## 1. 摘要

**问题**：多个 LLM Agent 并发书写 SA 代码时，仍然遇到传统软件工程中"必须 A → B 等待"的依赖瓶颈，无法达到预期的全并行开发速度。

**诊断**：并发的物理上限是**接口依赖图的拓扑层数**，不是 Agent 数量。任何不消除接口的并发方案，都终将卡在某条 A → B 链路上。

**解法**：三阶段协议——**契约冻结 → 拓扑分层 → 函数级提交**——把"无序全并发"重构为"短串行契约 + 大并行实现 + 增量提交"。借助 SA 的函数局部 Referee、`.sai`/`.sal` 物理分离、SHA-256 钉版机制等独特能力，把并发上限抬到接近理论极限。

**本规范不引入新关键字、不改变 SA 五符号契约、不修改 Referee 物理模型**，仅约定：

1. 多 Agent 协作的三阶段流程
2. 五个 CLI 子命令的接口规范（`sa contract freeze` / `diff` / `lock` / 函数级 emit / 协调者脚手架）
3. 两个新声明 `@reserved` / `@stub` 的语法与语义
4. 契约漂移（drift）处理协议
5. 函数级提交与冲突解决规则

实现工程量约 2.5 个月，分布在内核 CLI 层（不动 Flattener / Referee 核心）。

---

## 2. 问题诊断

### 2.1 6 类天然同步点

即使 Referee 是函数局部、emit 是声明级并行，**写**依然有以下不可消除的依赖：

| 同步点 | 现象 | 影响范围 |
|--------|------|---------|
| **调用契约** | B 写 `call @foo(^x)` 之前必须知道 A 的 `@foo` 第一参是 `^` / `&` / value | 所有依赖 A 的调用方 |
| **布局共享** | 多个 Agent 都 `load entity+Entity_pos as i64`，偏移由谁决定？ | 所有读写该结构的代码 |
| **`#def` 命名空间** | 两个 Agent 各自 `#def NODE_SIZE = 16` 但值不同 | 跨文件的 `#def` 合并冲突 |
| **`@const` 引用** | A 定义 `@const VTABLE_FOO`，B 在 `call_indirect` 引用 | 间接调用 / vtable 派发 |
| **`grants` 权限** | 模块级权限决定 B 能不能调用 A 暴露的 `@sys_*` | 跨模块能力图 |
| **测试 / 标签命名** | `@test "name"` 两个 Agent 撞同名 | 测试装配 / 报告 |

**结论**：6 类同步点合起来就是"接口"。任何并发协议都不能消除接口，只能**收缩、固化、版本化**接口。

### 2.2 SA 已具备的并发原生杠杆

| 杠杆 | 出处 | 利用方式 |
|------|------|---------|
| 函数局部 Referee | tasks.md P0.1 | 函数 = 最小同步单元，验证可独立 |
| `.sai` 接口契约 | design.md §3.1 | 物理上把"签名"和"实现"分文件 |
| `.sal` 布局契约 | design.md §3.1 | 物理上把"偏移 + 宏 facade"和"使用"分文件 |
| SHA-256 钉版 | design.md §3.10 / pkg | 同样思路可用于"钉契约" |
| 声明级并行 emit | tasks.md P0.4 | 同一时刻多函数同时 codegen |
| 函数级增量缓存（地基） | progress.md issue6 IMP-1 | `appendFlattenFragment` 已就绪 |
| 结构化 Trap JSON | agent_first_toolchain.md | 冲突时 LLM 机器可读、机器可修 |

### 2.3 SA 没有的"伪同步杀手"

相比 Rust / Scala / Haskell，SA 主动放弃了一批跨函数依赖来源（FAQ 详述）：

- ❌ 泛型约束求解（"A 实现 trait B 才能 compile"那种 100s 量级延迟）
- ❌ 跨文件类型推导
- ❌ Lifetime 推断
- ❌ Drop trait 引发的析构顺序依赖
- ❌ 隐式数值提升 / impl coherence

**这意味着只要接口锁定，函数实现真的可以独立并发**。SA 是少数能把这个承诺兑现的语言。

---

## 3. 三阶段并发协议

### 3.1 总览

```
┌─────────────────────────────────────────────────────────┐
│ 阶段 0：契约冻结 (Contract Freeze)                       │
│   单一协调者 Agent，串行                                  │
│   输入：业务需求描述                                       │
│   输出：完整 .sai + .sal + contract.lock(SHA-256)         │
│   耗时：分钟级（10K 行规模工程约 3-10 分钟）              │
└──────────────────────────┬─────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────┐
│ 阶段 1：拓扑分层 + 层内并发实现                            │
│   依赖图 L₀, L₁, ..., Lₖ                                  │
│   层内 N 个 Agent 并发，N = 该层函数数                     │
│   每个 Agent 仅看 .sai + .sal + contract.lock，不看他人实现 │
│   输出：每个函数的 .sa body                                │
│   耗时：每层时间 = 单函数实现时间（层数 ≈ 5-10）           │
└──────────────────────────┬─────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────┐
│ 阶段 2：函数级提交、增量验证、漂移协商                      │
│   每函数：单函数 Referee verify (毫秒级)                   │
│   通过 → 写入 cache + sa.lock                              │
│   失败 → Trap JSON 反馈 Agent，自修复重提交                 │
│   契约 drift → 协调者裁决 + 受影响 Agent rebase            │
└─────────────────────────────────────────────────────────┘
```

### 3.2 阶段 0：契约冻结

**输入**：人类或上层 Agent 描述的业务需求（一段自然语言 / 一份 spec）。

**单一"协调者 Agent"负责**：

1. **拆解需求** 为 N 个函数 + M 个结构体 + K 个常量 / vtable
2. **写出 `.sai` 签名集**：
   - 每个函数的 `@name(params) -> ret:` 头
   - 所有权前缀（`^` / `&` / value）必须明确
   - `@extern` / `@ffi_wrapper` / `@export` 必须明确标记
   - `?` 后缀（fallible）必须明确
3. **写出 `.sal` 布局集**：
   - 每个结构体的 `#def *_SIZE` / `#def *_field = +offset`（建议通过 `sa layout` 工具生成）
   - 必须的 `[MACRO]` facade 声明
   - vtable 槽位声明（不含函数体引用）
4. **写出 `contract.lock`**：
   - 全部 `.sai` 文件路径 + 单文件 SHA-256
   - 全部 `.sal` 文件路径 + 单文件 SHA-256
   - 聚合 `contract_sha256`（所有 `.sai` + `.sal` 字节流的稳定哈希）
   - 函数依赖图（DAG）
   - 拓扑分层结果（L₀..Lₖ）
   - 容量信息：函数总数 / 层数 / 最大层宽度
5. **校验**：
   - 所有 `.sai` 中引用的 `.sal` 布局都存在
   - 所有 `@const` 引用都有声明
   - 依赖图无环（环 → 协调者必须重新拆分）

**输出位置**：项目根 `contracts/<feature-name>/`，目录内含 `*.sai` / `*.sal` / `contract.lock`。

**协调者 Agent 的边界**：
- ✅ 可以写函数签名
- ✅ 可以写布局常量
- ✅ 可以写 vtable 声明
- ❌ **不可以**写函数体（哪怕 stub 也不可以——stub 由阶段 1 的实现 Agent 写）
- ❌ **不可以**实现宏体（宏 facade 可以；宏体是实现细节）

**契约冻结的不可逆性**：
- 一旦 `contract.lock` 生成，阶段 1 即开始
- 阶段 1 期间发现契约必须变 → 走 §6 "契约漂移协商"，不能默默改 `.sai`

### 3.3 阶段 1：拓扑分层 + 层内并发实现

**依赖图分层**（阶段 0 已输出）：

- **L₀** = 不调用任何其他业务函数的函数（叶子函数；可以调用 `sa_std` 和 `@extern`）
- **Lᵢ** = 所有调用都落在 ⋃_{j<i} Lⱼ 内的函数

**层内调度**：
- 每层 N 个函数 = N 个并发实现 Agent
- 每个 Agent 拿到：
  - 自己的目标函数签名（`.sai` 中的一行）
  - 完整的 `.sai` 集合（看依赖签名）
  - 完整的 `.sal` 集合（看布局）
  - `contract.lock` 的 `contract_sha256`
  - 函数依赖图（避免误调用未定义函数）

**Agent 提交格式**（建议 JSON）：

```json
{
  "function_name": "parse_route",
  "function_body_sa": "@parse_route(...) -> ...:\nL_ENTRY:\n  ...\n",
  "contract_sha256": "<阶段 0 输出的 contract_sha256>",
  "agent_id": "agent-impl-04",
  "claimed_layer": 2,
  "depends_on": ["@parse_path", "@trim_whitespace"],
  "macros_used": ["DROP_AND_RETURN", "ASSERT_EQ"],
  "consts_used": ["VTABLE_ROUTER"],
  "elapsed_ms": 4321
}
```

**层间屏障**：
- 每层全部完成 → 协调者触发"层内验证 batch"
- 全过 → 进入下一层
- 有失败 → 该函数 Agent rebase 重试；其他函数继续推进下一层（不阻塞）

### 3.4 阶段 2：函数级提交、增量验证、漂移协商

**单函数 verify**：
- 输入：函数 `.sa` body + 同 `contract_sha256` 下的 `.sai` / `.sal` + 已通过的下层函数缓存
- 调用 `sa func verify <func_name>.sa --contract contract.lock`（§4.3）
- 输出：Pass / Trap JSON

**通过路径**：
1. 写入 `cache/functions/<func_sha>.{sa,o,annotated.json}`
2. 更新项目 `sa.lock`：
   ```toml
   [functions.parse_route]
   function_sha256 = "..."
   contract_sha256 = "..."
   object_sha256 = "..."
   committed_by = "agent-impl-04"
   ```
3. 通知所有等待该函数的上层 Agent

**失败路径**：
1. 返回结构化 Trap JSON（agent_first_toolchain.md 既有）
2. Agent 收到后**最多重试 K 次**（默认 K=3）
3. K 次都失败 → 升级到协调者，可能触发契约 drift 协商（§6）

**所有层完成后**：
- 协调者触发"全量 link"：`sa link --contract contract.lock --cache cache/`
- 增量链接所有 `.o`
- 完整 Referee pass（已 verified 函数也再扫一次，确保函数间一致性，速度极快——纯 metadata 检查）
- 最终产物：可执行 / WASM / `.a`

---

## 4. 五个新 CLI 子命令规范

> **设计原则**：CLI 不改 Flattener / Referee / Emitter 核心，只新增子命令包装现有能力。

### 4.1 `sa contract freeze`

**用途**：阶段 0 的输出固化。

**用法**：

```
sa contract freeze <input-dir> [--out <out-dir>] [--json]
```

**输入**：包含 `.sai` 和 `.sal` 的目录。

**输出文件**：`<out-dir>/contract.lock`，建议 TOML 格式（可读 + 机器解析）：

```toml
schema = "sa.contract/1"
contract_sha256 = "<aggregated hash>"
generated_at = "2026-06-15T10:30:00Z"
generator = "agent-coordinator-v1"

[[sai_files]]
path = "contracts/router/router.sai"
sha256 = "..."
functions = ["parse_route", "match_route", "build_router"]

[[sal_files]]
path = "contracts/router/router.sal"
sha256 = "..."
layouts = ["Route_SIZE", "Router_SIZE"]
consts = ["VTABLE_ROUTER"]
macros = ["ROUTE_INIT", "ROUTE_CLEANUP"]

[dependency_graph]
"parse_route" = []
"trim_whitespace" = []
"match_route" = ["parse_route", "trim_whitespace"]
"build_router" = ["match_route"]

[topology]
layers = [
  ["parse_route", "trim_whitespace"],
  ["match_route"],
  ["build_router"]
]
max_layer_width = 2
total_functions = 4
```

**`--json` 模式**：同样信息以 JSON 输出到 stdout，便于协调者 Agent 直接消费。

**错误**：
- `ContractCycle`：依赖图有环
- `MissingLayout`：`.sai` 引用了未声明的布局
- `MissingConst`：`.sai` 引用了未声明的 `@const`
- `DuplicateSignature`：两个 `.sai` 文件声明了同名函数

### 4.2 `sa contract diff`

**用途**：阶段 1/2 中检测契约变化，触发 Agent rebase。

**用法**：

```
sa contract diff <old.lock> <new.lock> [--json]
```

**输出**（人类可读形式）：

```
Contract diff: contract_a → contract_b

CHANGES (1):
  ~ contract_sha256: aaa... → bbb...

FUNCTIONS:
  + added:    @parse_v2(s: ptr, len: u64) -> ptr
  - removed:  @parse_legacy
  ~ changed:  @foo  [BREAKING]
              param 0: ^x → &x

LAYOUTS:
  ~ Route_SIZE:  32 → 40  [BREAKING for L2+]
  + added field: Route_method @ +24
  ~ moved field: Route_path  +16 → +20  [BREAKING]

CONSTS:
  ~ VTABLE_ROUTER: 3 slots → 4 slots  [BREAKING for callers using slot 3]

GRANTS:
  + module router: added [net_tx]

AFFECTED FUNCTIONS (8):
  @match_route       (depends on @foo signature)
  @build_router      (depends on Route layout)
  @route_dispatch    (depends on VTABLE_ROUTER)
  ...
```

**`--json` 模式**：结构化输出，列出 `breaking_changes[]` / `affected_functions[]` / `recommended_rebase_layers[]`。

### 4.3 `sa func verify` / `sa func emit`

**用途**：阶段 2 的函数级提交入口。

**用法**：

```
sa func verify <func.sa> --contract <contract.lock> [--json]
sa func emit   <func.sa> --contract <contract.lock> --out <func.o> [--cache <dir>]
```

**职责**：
- `verify`：单函数走 Flattener → Referee；不 emit。返回 pass / Trap JSON。
- `emit`：单函数走 Flattener → Referee → LLVM-C → `.o`；缓存命中时直接 copy。

**缓存命中条件**（必须全部）：
1. `function_sha256` 匹配
2. `contract_sha256` 匹配
3. 依赖函数的 `object_sha256` 列表全部匹配
4. 编译器版本匹配

**输出**：

```json
{
  "function_name": "parse_route",
  "function_sha256": "...",
  "contract_sha256": "...",
  "object_sha256": "...",
  "instructions_emitted": 142,
  "gas_max_steps": "bounded(580)",
  "compile_tokens": 5230,
  "cache_hit": false,
  "elapsed_ms": 38
}
```

**与现有 P0.4 / P0.5 的关系**：
- P0.4 的 per-decl 并行 emit 是"一个进程内并行多函数"
- 本命令是"多进程 / 多 Agent 各自 emit 一个函数"——更细粒度但 IPC 成本略高

### 4.4 `sa link --contract`

**用途**：阶段 2 末尾的最终链接。

**用法**：

```
sa link --contract <contract.lock> --cache <dir> --out <output> \
        [--target exe|wasm|obj|wasm-wasi]
```

**职责**：
- 收集 `cache/functions/*.o`
- 校验每个 `.o` 对应的 `function_sha256` 与 `contract.lock` 中记录的版本一致
- 全函数 metadata 一致性检查（调用契约 / 布局偏移 / vtable 引用）
- 调用 `zig cc` 链接为最终产物

**错误**：
- `CacheStaleObject`：缓存 `.o` 对应的 contract 已变
- `MissingFunctionImpl`：契约声明了但无实现
- `ContractDriftAtLink`：函数声明的 contract 与 lock 不一致

### 4.5 `sa coordinate`（协调者脚手架）

**用途**：阶段 0/1/2 的端到端编排。可作为参考实现，鼓励社区自写更智能版本。

**用法**：

```
sa coordinate plan --req <requirement.md> --out <plan.json>
sa coordinate dispatch <plan.json> --workers <N>
sa coordinate reconcile --commits <dir>
sa coordinate status  [--json]
```

**`plan`**：调用大模型 / Agent，从需求生成 `.sai` / `.sal` 草稿（不冻结）。

**`dispatch`**：把每层任务分发给 N 个 worker Agent（worker 接口约定见 §5）。

**`reconcile`**：聚合所有 Agent 的函数提交，触发 verify + link。

**`status`**：当前进度（已完成 / 待完成 / 阻塞中的函数列表）。

**实现**：建议先以 Python / Bash 脚本实现，作为 reference impl；不进 Zig 内核。

---

## 5. 两个新源码声明

### 5.1 `@reserved`

**语法**：

```
@reserved <function_name>(<params>) -> <ret>
```

或：

```
@reserved <const_name> = <type>
```

**语义**：占位声明。Referee 在校验调用方时把它当作"已知存在"处理，不要求实现存在。链接器阶段才校验"reserved 必须有对应 `@stub` 或真实实现"。

**用例**：

```sa
// 阶段 0 协调者写入：
@reserved @parse_route(s: ptr, len: u64) -> ptr
@reserved @match_route(&router: ptr, path: ptr, path_len: u64) -> u64
```

阶段 1 实现 Agent 把 `@reserved` 替换为真实实现。

### 5.2 `@stub`

**语法**：

```
@stub @<function_name>(<params>) -> <ret>:
    panic(SA_STUB_NOT_IMPLEMENTED)
```

**语义**：可编译、可链接、可运行（运行即 panic）。让上层函数能在下层未实现时仍然 build 通过、跑测试。

**用例**：

```sa
// Agent 阶段 1 提交，正在等下层函数：
@stub @match_route(&router: ptr, path: ptr, path_len: u64) -> u64:
L_ENTRY:
    panic(SA_STUB_NOT_IMPLEMENTED)
```

**约束**：
- 编译产物中 `@stub` 函数计入 `tainted_stub_count`
- `--release-fast` 模式拒绝包含 `@stub` 的工程（强制实现）
- `sa.lock` 记录哪些函数是 stub，方便 CI 卡 gate

### 5.3 与现有语法的兼容性

- `@reserved` / `@stub` 是已有 `@` 修饰符家族的新成员（与 `@extern` / `@export` / `@ffi_wrapper` / `@test` 并列）
- Flattener 加一类 `LineKind`，不影响其他 16 形态
- Referee 加一条 "stub allowed at exit if SA_STUB_NOT_IMPLEMENTED panic" 的特例
- 不引入新关键字，不破坏五符号契约

---

## 6. 契约漂移（drift）协商协议

### 6.1 何时触发

阶段 1/2 进行中，发现契约必须变。来源有三：

1. **实现 Agent 自发**：写实现时发现签名不合理（如发现某参数应为 `&` 而非 `^`）
2. **Referee 反馈**：实现 Agent 提交函数被拒，Trap 指向 contract 不一致
3. **外部需求变更**：人类追加/修改需求

### 6.2 漂移流程

```
1. 漂移请求方 (Agent 或人类) 提交 ContractDriftRequest
   ├── 修改后的 .sai / .sal
   ├── 修改理由
   └── 估计影响范围（受影响函数列表）

2. 协调者审核
   ├── 自动跑 `sa contract diff`
   ├── 列出 breaking 变更
   ├── 计算受影响函数（依赖图反向遍历）
   └── 决策：批准 / 拒绝 / 改良后批准

3. 批准 → 生成新 contract.lock_v2
   ├── contract_sha256 更新
   ├── 全局广播到所有在跑 Agent
   └── 所有在跑 Agent 收到"contract drift"信号

4. 在跑 Agent 处理
   ├── 检查自己的提交是否在 affected_functions 列表
   ├── 在列表 → 中止当前实现，rebase 到新契约
   └── 不在列表 → 继续，但提交时用新 contract_sha256

5. 已提交函数的处理
   ├── 缓存条目自动失效（contract_sha256 不匹配）
   ├── 受影响函数需要重新实现
   └── sa.lock 记录漂移历史
```

### 6.3 漂移频率上限

**软约束**：单 sprint 漂移次数 > 5 → 协调者算法有 bug，应触发"契约设计回审"。

**硬约束**：每次漂移必须有明确的 ContractDriftRequest 记录；不允许"静默改 `.sai`"。

### 6.4 漂移成本最小化

| 策略 | 效果 |
|------|------|
| 让协调者多想 30 秒再冻结 | 减少阶段 1 漂移 |
| 把"调用方期望的 ownership 前缀"纳入需求 | 减少 `^` ↔ `&` 漂移 |
| 用 `sa layout` 工具生成布局而非手写 | 减少偏移漂移 |
| Agent 优先实现 L₀（叶子），L₀ 通过后再开 L₁ | 缩小漂移波及面 |

---

## 7. 函数级提交与冲突解决

### 7.1 提交粒度

**规则**：一次提交 = 一个函数 + 它独占的 `@const` / `@stub`。

**不允许**：一次提交跨多个函数（强行串行化）。

**多函数原子提交的真实需求**：通常说明这两个函数应该合并成一个，或应该提到 `.sai` / `.sal` 层。

### 7.2 冲突类型

| 冲突 | 何时发现 | 处理 |
|------|---------|------|
| 两个 Agent 实现同一函数 | 提交时（先到先得） | 后到方丢弃实现，去做其他函数 |
| 两个 Agent 都用了 `#def NODE_SIZE` 但值不同 | 阶段 0 已禁止——`#def` 只在 `.sal` 出现 | 不会发生 |
| 两个函数都声明 `@const FOO` | 阶段 0 已分配 `@const` 命名空间 | 不会发生 |
| 测试名重复 `@test "X"` | verify 阶段 | 后到方加后缀 `X_2` |
| 函数声明 `grants [net_tx]`，调用方无 | verify 阶段 | Trap，调用方 rebase 或协调者补 |
| Agent 提交时 `contract_sha256` 已变 | verify 阶段 | drift 触发（§6）|

### 7.3 提交日志格式

每个提交必须能溯源：

```json
{
  "commit_id": "<random uuid>",
  "function_name": "parse_route",
  "function_sha256": "...",
  "contract_sha256": "...",
  "agent_id": "agent-impl-04",
  "agent_model": "claude-opus-4-7",
  "elapsed_ms": 4321,
  "retries": 0,
  "previous_traps": [],
  "committed_at": "2026-06-15T10:42:11Z"
}
```

进 `sa.lock` 的 `[[commits]]` 数组。

---

## 8. 与现有 SA 特性的对接

### 8.1 与包管理（`sa pkg`）的关系

| 概念 | sa.mod / sap.json | contract.lock |
|------|-------------------|--------------|
| 作用域 | 跨工程的依赖 | 单工程的并发开发协议 |
| 钉版对象 | 第三方包源码 SHA | 内部 `.sai` / `.sal` SHA |
| 信任模型 | 零信任 + grants 白名单 | 单工程内可信，但要求强一致性 |
| 持久性 | 长期，提交到 Git | 单 sprint，可丢弃 |

**关系**：互补，不重叠。`contract.lock` 是 `sa.lock` 的子集（具体是 `[contracts]` 段）。

### 8.2 与 Agent-First Toolchain 的关系

- `--json` 输出：本协议所有 CLI 命令必须支持
- `compile_tokens`：每次 `sa func emit` 报告，便于 Agent 多轮博弈优化
- `sa explain`：Trap 反馈环节复用现有能力
- `sa fix --plan`：drift 时可用于建议 rebase 路径

### 8.3 与函数级增量缓存的关系

本协议**强依赖**函数级增量缓存（参见 `kernel_improvement_evaluation_cn.md` §⭐⭐⭐⭐⭐ 1）。地基已铺好：
- `appendFlattenFragment`（progress.md 已交付）
- `cached_macro_defs`（已交付）
- `LayoutVersion` 合并（已交付）
- `FunctionSig` 深克隆 + 重映射（已交付）

**仍需要**：
- `(function_sha, contract_sha, deps_sha)` 缓存键
- 单函数 emit CLI（§4.3）
- 增量链接 driver

工程量见 `kernel_improvement_evaluation_cn.md`。

### 8.4 与并行 emit 的关系

P0.4 的声明级并行 emit 在**单进程内**跨函数并行。本协议在**多进程 / 多 Agent** 间跨函数并行。两者协同：
- 单进程：本地 sprint 用 P0.4
- 跨进程：本协议适合大型分布式 sprint 或多 LLM 协同

---

## 9. 边界 / 不能解决的问题

| 想消除 | 能不能 | 为什么 |
|--------|--------|--------|
| 所有 A → B 依赖 | ❌ | 接口本质上是依赖 |
| 阶段 0 串行 | ❌（但可极短） | 接口要先有人定 |
| 跨层并发 | ❌ | 拓扑序物理约束 |
| 契约 drift 时 Agent 不返工 | ❌ | 但可最小化 drift 频率 |
| 层内 N→∞ 线性扩展 | ⚠️ 部分 | 受 Amdahl 限制，每层 50-100 Agent 实际够用 |
| 函数粒度小于"一个 SA 函数" | ❌ | SA 的最小验证单元就是函数 |
| 业务语义冲突自动消解 | ❌ | 这是协调者智能水平的事，不是协议事 |

**真正能消除的是"伪同步点"**——类型推导、lifetime 推导、trait coherence 求解——SA 本来就没有这些。

---

## 10. 推荐落地顺序

### 10.1 不动 Zig 内核就能先做的（"立刻可跑"）

| 优先级 | 任务 | 工程量 |
|--------|------|--------|
| ⭐⭐⭐⭐⭐ | 把本协议文档化（已完成本文档） | — |
| ⭐⭐⭐⭐ | 实现 `sa coordinate` 脚本（Bash / Python） | 1-2 周 |
| ⭐⭐⭐⭐ | 定义并写一个手动 contract.lock 模板 | 1 周 |
| ⭐⭐⭐ | 写 3-5 个示例工程：协调者输出 + 4-8 个 Agent 实现 | 1-2 周 |

**这一波完成后**：协议可以在现有 SA 上以"约定"形式运转，不强依赖内核改动。性能不是最优，但流程能跑通。

### 10.2 需要 Zig 内核新增的（"工业可用"）

| 优先级 | 任务 | 工程量 | 在哪 |
|--------|------|--------|------|
| ⭐⭐⭐⭐⭐ | 函数级增量编译缓存 | 2-3 周 | 见 `kernel_improvement_evaluation_cn.md` §⭐⭐⭐⭐⭐ 1 |
| ⭐⭐⭐⭐ | `sa contract freeze` / `diff` 命令 | 2 周 | `src/cli.zig` + 新 `src/contract.zig` |
| ⭐⭐⭐⭐ | `sa func verify` / `emit` 命令 | 2 周 | `src/cli.zig` + 复用现有 flatten/verify |
| ⭐⭐⭐ | `sa link --contract` 命令 | 1 周 | 复用 `driver/zigcc.zig` |
| ⭐⭐⭐ | `@reserved` / `@stub` 语法 | 1 周 | `src/flattener.zig` + `src/verifier.zig` |
| ⭐⭐ | `sa coordinate` CLI 包装（Zig 版） | 2 周 | 新 `src/coordinate.zig` |

**总计**：约 2.5 个月，分布在 CLI 层（不动 Flattener / Referee 核心算法）。

### 10.3 长期愿景（"生态级"）

- 第三方协调者 Agent 生态（不只 SA 官方一份）
- `contract.lock` 作为可发布产物的 schema 标准（类似 protobuf 的 `.proto`）
- 跨工程契约共享（"router 模式的标准 `.sai`"）
- Agent 信誉 / 历史绩效追踪（基于 commit log）
- 自动化漂移建议（基于历史 drift 模式预测）

---

## 11. 一句话总结

> **SA 多 Agent 并发开发的上限不是 Agent 数量，而是接口依赖图的拓扑层数。**
>
> 本协议通过"短串行契约 + 大并行实现 + 函数级提交 + 漂移协商"四件套，把无序并发重构为可控并发，使 SA 能在多 LLM 协作场景下达到接近理论上限的并发度，同时保持 Referee 的全部安全承诺。

---

## 附录 A：术语表

| 术语 | 含义 |
|------|------|
| **协调者 Agent** | 阶段 0 的单一 Agent，负责契约设计 |
| **实现 Agent** | 阶段 1 的并发 Agent，每个负责一个函数 |
| **契约 (contract)** | 一个工程的全部 `.sai` + `.sal` |
| **contract_sha256** | 契约的聚合哈希；所有 Agent 同时只能看到一个 |
| **拓扑层 (layer)** | 依赖图中互不依赖的函数集合 |
| **漂移 (drift)** | 阶段 1/2 中契约的非平凡变化 |
| **Rebase** | Agent 因漂移而重新实现自己的函数 |
| **stub** | 占位实现，运行即 panic，让上层可 build |
| **reserved** | 占位声明，无实现，链接前必须替换 |

## 附录 B：示例工作流（HTTP Router 工程）

**人类输入**（需求）：

> "我要一个 HTTP path router，支持精确匹配和通配符（`/users/:id`）。给定一个 URL path，返回匹配的 handler index 或 -1。"

**阶段 0（协调者 Agent，~5 分钟）**：

输出 `contracts/router/router.sai`：

```
@parse_route(s: ptr, len: u64) -> ptr
@trim_whitespace(&buf: ptr, len: u64) -> u64
@route_segments(&route: ptr) -> u64
@match_route(&router: ptr, path: ptr, path_len: u64) -> i64
@build_router(routes: ptr, count: u64) -> ptr
```

输出 `contracts/router/router.sal`：

```
#def Route_SIZE = 32
#def Route_path_ptr = +0
#def Route_path_len = +8
#def Route_handler  = +16
#def Route_flags    = +24

#def Router_SIZE = 16
#def Router_routes = +0
#def Router_count  = +8

@const VTABLE_ROUTER = vtable { ... }
```

输出 `contract.lock`：拓扑分层 = `[[parse_route, trim_whitespace], [route_segments], [match_route, build_router]]`

**阶段 1（5 个并发 Agent，~10 分钟）**：

- L₀：Agent A 实现 `parse_route`；Agent B 实现 `trim_whitespace`
- L₁：Agent C 实现 `route_segments`
- L₂：Agent D 实现 `match_route`；Agent E 实现 `build_router`

**阶段 2（顺序提交，~3 分钟）**：

每函数 verify + emit。总 wall time ≈ max(layer time) × layer count = 单函数时间 × 3 层 ≈ 15 分钟。

**对比传统单 Agent 顺序开发**：估计 5 函数 × 10 分钟 = 50 分钟。

**加速比**：~3×（受限于层数，与函数数无关）。如果工程更大（如 50 函数 / 5 层），加速比可达 ~10×。

---

## 附录 C：开放问题（待讨论）

1. **协调者 Agent 是否需要"次协调者"？** 大型工程是否需要分模块协调？
2. **`@stub` 函数能否在生产 binary 中保留？** 当前规范禁止 `--release-fast` 含 `@stub`，是否过严？
3. **contract.lock 是否进 Git？** 与 sa.lock 类似考虑——可重现 vs 仓库噪音。
4. **跨 sprint 的契约演进** 是否需要 `contract.lock` 版本链（v1 → v2 → v3 的迁移路径）？
5. **漂移协调** 能否引入投票机制？多个 Agent 都建议同方向漂移时自动批准？
6. **测试名空间** 是否要每个 Agent 自动加前缀，还是协调者预分配？
7. **Agent 性能数据** 是否回流到 `sa.lock`，供后续 sprint 的 worker 调度参考？

以上问题在 v0.2 版本前解决。
