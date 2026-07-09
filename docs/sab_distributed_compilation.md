# SAB 分布式编译：可行性分析与方案设计

> 文档版本: 2026-07-01  
> 状态: 设计草案  
> 关联: `sab_evaluation.md`, `design.md` §3.2b, `package_management.md`

---

## 一、问题背景

SA 当前采用**扁平化单体编译模型**：`@import` 在 Flattener 阶段被递归展开，所有模块合并成一个巨大的指令流，然后整体送入 Referee 验证。这种模型在大型项目中面临三个核心瓶颈：

1. **重复 flatten**：如果 N 个模块依赖 M 个库，每个消费者都要重新 flatten 所有依赖 → O(N × M) 次 flatten
2. **无法并行验证**：所有代码合并成单一流后才能验证 → 无法利用多核
3. **增量粒度粗**：修改一个底层库，所有依赖它的模块都要重新编译

**目标**：设计一个基于 SAB 的分布式编译架构，实现模块级独立编译、并行验证、细粒度增量。

---

## 二、可行性分析

### 2.1 SAB 作为模块交换格式的适配性

| 维度 | SAB 能力 | 分布式编译需求 | 适配度 |
|---|---|---|---|
| **自包含** | 含完整 symbols + function_sigs + const_decls + instructions | 模块可独立编译 | ✅ 完全适配 |
| **结构化接口** | function_sigs 携带参数类型、capability 前缀 | 跨模块调用签名验证 | ✅ 完全适配 |
| **宏已展开** | cached_macro_defs 不需要 | 无需跨模块传播宏定义 | ✅ 天然解决 |
| **二进制紧凑** | ULEB128 编码，0.3-0.5x 文本大小 | 网络传输高效 | ✅ 完全适配 |
| **版本化** | magic + version_major/minor | 格式兼容性管理 | ✅ 已有 v1-v4 |
| **predecoded Referee** | skip text parsing, use structured operands | 并行验证更快 | ✅ 已实现 |

**结论：SAB 天然适配分布式编译，无需格式修改。**

### 2.2 当前缺失的能力

| 缺失能力 | 重要性 | 说明 |
|---|---|---|
| `--emit-sab` CLI flag | **P0** | 编译管线无法产出 .sab 文件 |
| 跨模块 Referee 验证 | **P0** | 无法验证模块间调用签名一致性 |
| SAB 模块链接器 | **P0** | 无法合并多个 .sab 为统一编译单元 |
| 模块缓存失效 | P1 | 无法检测 .sab 是否需要重新编译 |
| 调试信息保留 | P2 | v4 移除了 raw_text，诊断信息降级 |

---

## 三、架构设计

### 3.1 编译管线总览

```
                    ┌───────────────────────────────────────┐
                    │          开发者编写 .sa 源码           │
                    └───────────────┬───────────────────────┘
                                    │
                    ┌───────────────▼───────────────────────┐
                    │     阶段 1: 模块依赖分析               │
                    │     解析 sa.mod → 构建依赖图            │
                    │     检测变更模块 → 确定重编译范围        │
                    └───────────────┬───────────────────────┘
                                    │
                    ┌───────────────▼───────────────────────┐
                    │     阶段 2: 并行 Flatten + Encode      │
                    │     每个变更的 .sa → Flattener          │
                    │     → encodeSabFromFlat → .sab         │
                    │     (未变更模块使用缓存 .sab)            │
                    └───────────────┬───────────────────────┘
                                    │
                    ┌───────────────▼───────────────────────┐
                    │     阶段 3: 并行 Referee 验证          │
                    │     每个 .sab → decodeModule            │
                    │     → verifyWithOptions (predecoded)   │
                    │     → AnnotatedInstruction[]           │
                    └───────────────┬───────────────────────┘
                                    │
                    ┌───────────────▼───────────────────────┐
                    │     阶段 4: 跨模块一致性验证            │
                    │     检查 @export / @extern 签名匹配     │
                    │     检查 Capability Mask 跨模块传播     │
                    └───────────────┬───────────────────────┘
                                    │
                    ┌───────────────▼───────────────────────┐
                    │     阶段 5: 链接                       │
                    │     合并所有 AnnotatedInstruction[]     │
                    │     → LLVM emission → 最终二进制        │
                    └───────────────────────────────────────┘
```

### 3.2 缓存策略

```
project/
├── sa.mod                    # 包清单（依赖图）
├── .sa_cache/
│   ├── math.sab              # 模块级 SAB 缓存
│   ├── math.sab.meta         # 缓存元数据（hash, mtime）
│   ├── render.sab
│   ├── render.sab.meta
│   └── ...
└── src/
    ├── math.sa
    ├── render.sa
    └── main.sa
```

**缓存键计算**:
```
cache_key = SHA256(source_content + sa_mod_hash + compiler_version)
```

**缓存失效条件**:
- 源文件内容变更
- `sa.mod` 依赖图变更
- 编译器版本升级（SAB format version 变更）

### 3.3 跨模块验证协议

#### 3.3.1 接口声明层

每个模块的 `.sai` 文件声明 public 接口：

```
// math.sai
@export add(a: i32, b: i32) -> i32
@export multiply(a: i32, b: i32) -> i32
```

#### 3.3.2 实现匹配验证

跨模块 Referee 检查：

1. **函数签名匹配**：调用方的 `@extern` 声明与被调用方的 `@export` 签名一致
2. **Capability 一致性**：调用方请求的 capability 在被调用方的 grants 范围内
3. **类型兼容性**：参数类型和返回类型在 32/64 位目标下一致

#### 3.3.3 验证流程

```
对每个模块 M:
  1. 读取 M.sab → decodeModule
  2. 读取 M.sai → 提取 @export 列表
  3. verifyWithOptions(predecoded) → AnnotatedInstruction[]

对每个调用边 (A → B):
  1. 从 A 的 annotated 中提取 call 指令
  2. 从 B 的 .sai 中查找被调用函数签名
  3. 比较参数类型、capability、返回类型
  4. 不匹配 → trap with upstream_loc
```

### 3.4 链接策略

链接阶段合并多个模块的 `AnnotatedInstruction[]`：

```
输入: [math_annotated, render_annotated, main_annotated]
输出: merged_annotated (统一函数 ID 空间)

步骤:
1. 分配全局函数 ID: main 的函数从 0 开始, render 从 N 开始, math 从 N+M 开始
2. 重映射 call 指令的目标函数 ID
3. 合并符号表（去重）
4. 合并 const_decls（去重）
5. 合并指令数组（保持模块顺序）
```

---

## 四、CLI 接口设计

### 4.1 模块级编译

```bash
# 编译单个模块为 SAB（生成缓存）
sa build --emit-sab src/math.sa -o .sa_cache/math.sab

# 编译整个 workspace（增量）
sa build-workspace --distributed

# 强制全量重编
sa build-workspace --distributed --force
```

### 4.2 增量检测

```bash
# 检查哪些模块需要重编译
sa build-workspace --dry-run

# 输出:
# changed: src/render.sa (source modified)
# changed: src/main.sa (dependency changed)
# cached:  src/math.sa → .sa_cache/math.sab (hash match)
```

### 4.3 并行度控制

```bash
# 自动并行
sa build-workspace --distributed --jobs auto

# 指定并行度
sa build-workspace --distributed --jobs 8
```

---

## 五、与现有架构的兼容性

### 5.1 向后兼容

| 场景 | 行为 |
|---|---|
| `sa build main.sa`（无 --distributed） | 传统单体编译，不受影响 |
| `sa build main.sab` | 直接从 SAB 编译，跳过 Flattener |
| `sa build-workspace --distributed` | 新增分布式路径 |
| `.sa_cache/` 已存在 | 自动识别 SAB 缓存 |

### 5.2 与前端缓存的关系

分布式编译不替代前端缓存（`expanded_import_cache`），而是提供更高层级的缓存：

```
前端缓存 (细粒度): 缓存展开后的文本片段 → 加速单文件 flatten
SAB 缓存 (粗粒度): 缓存完整的模块编译结果 → 跳过整个 flatten
```

两级缓存可以共存：
1. 首先检查 SAB 模块缓存（命中 → 直接 decode）
2. SAB 缓存未命中 → 使用前端缓存加速 flatten
3. 前端缓存也未命中 → 完整 flatten

---

## 六、实现路线图

### Phase 1: 基础设施 (1-2 周)

```
1. 实现 --emit-sab CLI flag                    # 解锁 SAB 产出
2. 实现模块级缓存 (hash 校验 + .sa_cache)       # 解锁增量
3. 实现 sa build-workspace --distributed       # 入口命令
```

### Phase 2: 并行编译 (2-3 周)

```
4. 实现并行 flatten (多 worker 进程)            # 阶段 2 并行
5. 实现并行 Referee (predecoded 路径)           # 阶段 3 并行
6. 实现模块链接器 (AnnotatedInstruction 合并)    # 阶段 5
```

### Phase 3: 跨模块验证 (3-4 周)

```
7. 设计并实现跨模块 Referee 协议                # 阶段 4
8. 实现 .sai 接口一致性检查                     # 签名匹配
9. 实现 Capability Mask 跨模块传播              # 权限验证
```

### Phase 4: 优化与生态 (持续)

```
10. 调试信息保留 (upstream_loc → 源码映射)
11. 分布式编译支持 (网络传输 .sab)
12. CI/CD 集成 (Docker + 分布式构建)
```

---

## 七、性能预估

### 7.1 三条管线的逐阶段对比

#### 管线 A: 单 `.sa` 编译

```
① loadSource()                    ← 磁盘读取文本
② expandImports()                 ← 递归解析 @import，读取多个文件，文本拼接
③ collectMacroDefinitions()       ← 遍历所有行，收集 [MACRO] 定义
④ expandMacros()                  ← EXPAND 递归展开，卫生重命名 (__sa_hygN)
⑤ def_dict.foldText()             ← #def 常量字典替换
⑥ classifyLine() × N 行          ← 逐行分类（关键字匹配、模式识别）
⑦ emitParsedLine() × N 行        ← 操作数从文本解析，符号 intern
⑧ FlattenResult
⑨ collectMetadata()               ← 再次遍历指令：intern 符号、解析函数签名文本
⑩ classifyStructuredInstruction() × N 指令 ← 从文本重建 ClassifiedLine
⑪ verifyBody() × 函数数           ← Capability Mask 校验
⑫ LLVM emission
```

#### 管线 B: 单 `.sab` 编译

```
① loadSabFlat()                   ← sab.decodeModule() (ULEB128 解码)
② FlattenResult
③ collectPredecodedMetadata()     ← 直接使用已解码的 symbol_names 和 function_sigs
④ classifyStructuredInstruction() × N 指令 ← 从结构化 operand 重建（无需文本）
⑤ verifyBody() × 函数数           ← Capability Mask 校验（相同）
⑥ LLVM emission
```

#### 管线 C: 分布式 SAB（模块级并行）

```
阶段 1: 依赖分析                           ← 确定重编译范围
阶段 2: 并行 Flatten + Encode              ← 每个变更的 .sa → .sab
阶段 3: 并行 Referee (predecoded)          ← 每个 .sab → AnnotatedInstruction
阶段 4: 跨模块一致性验证                    ← 检查 @export/@extern 签名匹配
阶段 5: 链接 + LLVM emission
```

### 7.2 逐阶段耗时分析

| 阶段 | 单 SA | 单 SAB | 分布式 SAB |
|---|---|---|---|
| **文件 I/O** | 文本读取 (较大) | 二进制读取 (更紧凑) | 并行读取多个 .sab |
| **expandImports** | **高** — 递归解析多文件 | **跳过** | 仅对变更模块执行 |
| **宏展开** | **高** — 递归 EXPAND + 卫生重命名 | **跳过** | 仅对变更模块执行 |
| **#def 替换** | **中** — 逐行扫描 | **跳过** | 仅对变更模块执行 |
| **行分类 + 指令生成** | **中** — 逐行 classifyLine | **跳过** | 仅对变更模块执行 |
| **元数据收集** | **中** — collectMetadata (文本解析) | **低** — collectPredecodedMetadata (直接使用) | 并行 predecoded |
| **Referee 验证** | **中-高** — verifyBody | **中-高** — verifyBody | **并行** verifyBody |
| **LLVM emission** | **中-高** | **中-高** | **中-高** (链接后) |

### 7.3 性能倍数预估

#### 场景 1: 宏重度单文件（如 sa_std 模块）

| 管线 | 相对耗时 | 加速比 |
|---|---|---|
| 单 SA | **100%** | 基准 |
| 单 SAB | **20-30%** | **3-5x** |
| 分布式 SAB | **20-30%** | **3-5x** (单文件无分布式收益) |

**核心原因**：SAB 跳过了最大的性能瓶颈 — 宏展开（占 30-50%）和导入解析（占 20-35%）。

#### 场景 2: 多文件项目（100 个模块，每个 500 行，5 个依赖）

| 管线 | 相对耗时 | 加速比 |
|---|---|---|
| 单 SA（全量） | **100%** | 基准 |
| 单 SAB（逐个编译） | **60-70%** | **1.4-1.7x** |
| 分布式 SAB（全量） | **40-50%** | **2-2.5x** |
| 分布式 SAB（增量，改 1 个模块） | **5-10%** | **10-20x** |
| 分布式 SAB（增量，改底层库） | **15-20%** | **5-7x** |

#### 场景 3: 无变更重编

| 管线 | 相对耗时 | 加速比 |
|---|---|---|
| 单 SA | **30-50%** (前端缓存部分命中) | 基准 |
| 单 SAB | **1-2%** | **15-50x** |
| 分布式 SAB | **1-2%** | **15-50x** |

### 7.4 加速来源分解

| 加速来源 | 贡献占比 | 说明 |
|---|---|---|
| **消除宏展开** | **30-50%** | SAB 最大收益 — 宏重度代码的编译瓶颈 |
| **消除递归导入** | **20-35%** | 多文件项目的核心开销 |
| **消除重复 flatten** | **15-20%** | 分布式独有 — O(N×M) → O(M) |
| **predecoded Referee** | **10-15%** | 跳过文本分类和元数据收集 |
| **并行化** | **5-10%** | 多核利用（受 Amdahl 定律限制） |
| **缓存命中** | **5-10%** | 增量场景的核心加速 |

### 7.5 关键洞察

1. **单 SAB 比单 SA 快 3-5x** — 核心原因是消除整个 Flattener 阶段（宏展开 + 导入解析 + 文本处理）
2. **分布式 SAB 比单 SAB 快 1.5-2x（首次全量）** — 核心原因是消除 N 对 1 的重复 flatten + 并行化
3. **分布式 SAB 的真正价值在增量场景** — 改 1 个模块只需重编译该模块（5-10%），而不是整个项目（80-100%），加速 10-20x
4. **分布式 SAB 不会比单 SAB 慢** — 即使没有并行化，分布式路径也至少等于单 SAB 性能（因为模块级缓存跳过未变更模块的 flatten）
5. **最大的性能瓶颈不在二进制格式本身**，而在 Flattener 的文本处理工作。SAB 的价值正是把 Flattener 的输出持久化，让后续编译完全跳过这个最重的阶段

---

## 八、风险与缓解

| 风险 | 影响 | 缓解措施 |
|---|---|---|
| SAB 格式升级导致缓存失效 | 中 | 已支持 v1-v4 前向兼容 |
| 跨模块验证误报 | 高 | 渐进式验证：先单模块，再跨模块 |
| 内存压力（多个 AnnotatedInstruction 合并） | 中 | 流式合并，不同时加载所有模块 |
| 并行 flatten 的宏定义冲突 | 低 | SAB 不携带宏定义，已天然隔离 |
| 调试体验降级 | 低 | 保留 upstream_loc 映射回源码 |

---

## 九、与 JS/TS 生态的类比

| | JS/TS 生态 | SA/SAB 生态 |
|---|---|---|
| **源码** | `.ts` | `.sa` |
| **编译产物** | `.js` | `.sab` |
| **类型声明** | `.d.ts` | `.sai` |
| **增量缓存** | `.tsbuildinfo` | `.sa_cache/*.sab.meta` |
| **打包器** | webpack/esbuild | `sa build-workspace --distributed` |
| **模块边界** | `import/export` | `@import/@export/@extern` |
| **类型检查** | `tsc --noEmit` | `sa verify` (跨模块 Referee) |
| **Tree Shaking** | dead code elimination | `--dce full` |

### 9.2 WASM 编译兼容性

SAB 分布式编译对 WASM 目标**完全适用**，性能改进幅度与 Native 一致。

**代码证据**：`compileSource` (cli.zig:4228) 是所有编译命令的共享入口，`.sab` 后缀识别已内置：

```
sa build-exe  main.sab  →  compileSource → loadSabFlat → Referee → LLVM → zig cc
sa build-wasm main.sab  →  compileSource → loadSabFlat → Referee → LLVM (wasm_compat) → zig cc -target wasm32-wasi
sa build-obj  main.sab  →  compileSource → loadSabFlat → Referee → LLVM → zig cc -c
```

**管线对比**：

| 阶段 | WASM 路径 | 与 Native 的差异 |
|---|---|---|
| 输入识别 | `compileSource` 检测 `.sab` 后缀 → `loadSabFlat` | **完全相同** |
| 解码 | `sab.decodeModule` → `FlattenResult` | **完全相同** |
| Referee | `verifyWithOptions(predecoded)` | **完全相同** |
| LLVM emission | `emitLlvmcToFile(... wasm_compat: true ...)` | 仅 `wasm_compat` 标志 |
| 链接 | `compileWasm(... wasm32-wasi ...)` | `compileExe` → `compileWasm` |

**WASM 性能预估**：

| 场景 | WASM SA | WASM SAB | 加速比 |
|---|---|---|---|
| 宏重度单文件 | 100% | 20-30% | **3-5x** |
| 多文件全量 | 100% | 60-70% | **1.4-1.7x** |
| 增量（改 1 模块） | 80-100% | 5-10% | **10-20x** |
| 无变更重编 | 30-50% | 1-2% | **15-50x** |

**结论**：WASM 编译的加速来源（跳过 Flattener、predecoded Referee、并行化）都发生在 emission 之前的共享管线中，与目标平台无关。唯一的差异在 emission 阶段（LLVM bitcode with `wasm_compat` flag），占总编译时间 10-15%，不影响 SAB 带来的核心加速。

---

*本设计基于 2026-07-01 的 `sab.zig` v4.0 实现和 `cli.zig` 分布式编译接口。*
