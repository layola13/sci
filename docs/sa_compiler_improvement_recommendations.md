# SA 编译器改进建议

评估日期：2026-06-22
评估范围：`sci/` 下的 SA 编译器前端、缓存链路、构建命令与文档呈现。
约束：本文件只给建议，不改任何代码。

## 一、当前可观察到的速度瓶颈

1. 前端重复成本仍是主因
- `unit-framework`、`wasm-matrix` 等阶段的耗时主要不是 Zig 编译，而是重复的 SA 展开/验证/测试产物工作。
- 证据：`docs/test_performance.md:50` 明确列出 `unit-framework` 和 `wasm-matrix` 是主瓶颈；`docs/test_performance.md:119` 给出大组用例的逐文件耗时。
- 这意味着“只加速 LLVM 后端”收益有限，前端缓存和构建切片 ROI 更高。

2. 大测试矩阵没有充分切分
- `tests/unit_framework/std_string_vec_macro_surface.sa` 曾被整体跑，导致单一组耗时很高。
- 证据：`docs/test_performance.md:197` 与 `sci/build.zig:462` 说明 `std-smoke` 会串起核心/容器两组 smoke；`docs/test_performance.md:206` 显示拆分后仍有进一步并行空间。
- 如果继续把所有逻辑塞进单个 `.sa` 测试文件，Zig 的 build graph 并行和测试缓存都会受限。

3. 项目缓存只部分接入前端流程
- `sa build-obj --incremental` 已经按函数粒度产出 `.o`，并写入 `.sa_cache/build-obj-incremental/<project_hash>/functions/<function_hash>.o`。
- 证据：`src/cli.zig:5276`、`src/cli.zig:5931`、`src/cli.zig:5427`。
- 但 `sa build` / `sa build-exe` / `sa build-wasm` / `sa test` 仍会完整跑 Flattener/Referee，即使 project cache 命中也只能省掉后续 emit/link；项目级 `.sa_cache` 仍存在无效/过期项风险。
- 证据：`docs/test_performance.md:233` 与 `src/cli.zig:1228`。

4. 文档对当前能力存在“失真”
- README 仍然把 SA 定位为“Zig-level compile speed”，并只列出基础 quick start。
- 证据：`readme.md:39`、`readme.md:127`、`readme.md:130`。
- CLI 已支持 `--incremental`、`--profile`、`--json`、`sa cache`，但文档索引只提到 design/requirements/FAQ 等，没把这些能力放入快速路径。
- 证据：`src/cli.zig:1159`、`src/cli.zig:1179`、`src/cli.zig:1228`、`readme.md:151`。

## 二、改进建议（按 ROI 排序）

### ⭐⭐⭐⭐⭐ 1. 优先补齐“文档对齐当前缓存/并行能力”

理由
- 这是成本最低、见效最快的改进；很多用户和 Agent 仍按旧叙事使用工具链。
- 当前真实状态是：已具备 project cache、manifest 校验、incremental `.o` cache、parallel pre-push、focused profiles，但 README 和 docs index 没有形成可执行心智模型。

建议
- 在 `docs/` 新增 `sa_compiler_performance_and_caching.md`，把以下内容结构化：
  - 什么时候会命中 project cache；
  - 什么时候只会命中 partial cache；
  - `sa build-obj --incremental` 的目录和 manifest 布局；
  - 推荐的工作流：普通改 `sa_std` 用 `fast` profile，发布边界用 `full` profile。
- 在 `readme.md` 的 Quick start 后补一段“推荐开发流程”：
  - 本地快速迭代：`zig build fast` 或 `tools/pre_push_timed.sh`；
  - 缓存验证：`sa cache clean --dry-run`；
  - 性能分析：`sa build <file> --profile --json`。
- 在 `docs/README.md` 增加性能/缓存入口：
  - 将新建文档和 `docs/test_performance.md` 放入显眼位置。

预期收益
- 减少“明明已经支持却不被使用”的能力浪费；
- Agent/LLM 更容易按当前真实 CLI 行为生成正确命令；
- 实施成本极低，2–4 小时可完成。

### ⭐⭐⭐⭐ 2. 把“前端缓存可见性”做到用户可观测

理由
- 现在 caching 已落地，但 CLI help 只写“Inspect and clean project-local caches”，没有告诉用户如何确认命中、失败、失效原因。
- 证据：`src/cli.zig:1232`、`src/cli.zig:1240`、`src/cli.zig:1241`。

建议
- 增加 `sa cache status` / `sa cache why <file>` 的轻量信息命令，或至少在 `sa cache clean --help` 文档中补 `sa cache inspect` 的说明。
- 输出至少包括：
  - `.sa_cache/build-*` / `.sa_cache/test` / `.sa_cache/build-obj-incremental` 各目录条目数；
  - manifest 有效/无效/过期比例；
  - 最近一次 project cache hit 的 key 摘要。
- 在 JSON 构建报告中强化 `metrics.cache`：
  - 当前 `metrics.cache.kind` / `metrics.cache.hit` 已存在；
  - 建议增加 `metrics.cache.key_truncated`、`metrics.cache.reason`、`metrics.cache.manifest_valid`。

预期收益
- 大幅降低“为什么没更快”的排障成本；
- 让 incremental 策略从“隐式行为”变成“可解释构建”。

### ⭐⭐⭐⭐ 3. 为并行测试进一步做“SA 级制品缓存”

理由
- 当前 `unit-framework` 仍有大量重复编译；即使 Zig test 二进制缓存，SA 文件级 compile/link 仍会重复发生。
- 证据：`docs/test_performance.md:54`、`docs/test_performance.md:115`、`docs/test_performance.md:136`。

建议
- 对 `sa test` 做两级缓存：
  1. test discovery/filter 元数据缓存；
  2. SA frontend result 缓存，保留已有 manifest 校验和 sha256 校验思路。
- 对 `wasm-matrix` 做 per-demo 缓存：
  - 允许单个 demo 在缓存有效时跳过 verify + emit + run；
  - 不在默认 profile 强制全量 rerun。
- 保留 cache-on/cache-off 的等价性测试门禁，防止导出缓存语义漂移。

预期收益
- `unit-framework` 和 `wasm-matrix` 在代码不变时能进入“秒级到分钟级”；
- 避免把时间浪费在重复依赖解析和重复宏展开。

### ⭐⭐⭐ 4. 明确“模块化 @import 与增量对象”的边界

理由
- 网上常见建议是“按 sla 分布生成多个 `.sa`，让 `main.sa` 很小”；但这在语义上只是 source-level module，不是 binary cache 策略。
- 当前 `Flattener` 已经把 package identity、line-level package hash、import source cache 都做出来了；真正的增量编译根因是“产物级复用”不足，而不是文件分布不足。
- 证据：`docs/issue6.md:86`、`docs/issue6.md:99`、`docs/test_performance.md:59`。

建议
- 继续保持“每个入口文件统一 flatten 为单个 IR 视图”的模型，不强行拆分成一个函数/文件对应一个 cache key；
- 增量对象缓存保留在 `.sa_cache/build-obj-incremental/.../functions/<hash>.o` 这一层；
- 让文档和用户心智对齐：模块拆分帮助可读性和团队分工，但不等于二进制缓存。

预期收益
- 避免错误的架构摇摆；
- 把工程精力集中到真正有收益的 function-level artifact cache 和 test cache。

### ⭐⭐⭐ 5. 建议把 Release 路径的默认后端策略显式文档化

理由
- 公开叙事仍偏向“Zig-level compile speed”，但当前 release-fast 实际依赖 LLVM O1–O3，大文件容易退化成秒级到十秒级。
- 证据：`docs/requirements.md:896` 已承认 “R7：LLVM O3 在中等规模代码库下仍为秒级到十秒级瓶颈”。
- 这会影响用户对 SA 速度的预期管理，也会影响 CI 性能预算设置。

建议
- 在文档中区分三类路径：
  - `sa run` / dev：快速迭代；
  - `sa build-obj` / incremental：复用函数对象；
  - `sa build-exe --release-fast`：发布性能优先，允许更长编译。
- 若后续引入第二 codegen backend，建议默认关闭，只在 `--dev` 启用，避免 CI 成本线性膨胀。

预期收益
- 建立更真实的性能预期；
- 减少“宣传速度 vs 实际速度”的落差。

## 三、建议的近期动作清单（建议 1 为第一步）

1. 新建文档并补齐 README/docs index 中的缓存/并行描述。
2. 增加 `sa cache status` 或等效可观测性输出，以及 richer JSON cache telemetry。
3. 落地 `sa test` 和 demo 矩阵的 frontend/test artifact cache。
4. 维护一个性能预算表：把 `docs/test_performance.md` 的 timing 改成“目标门禁 + 当前值”。
5. 在 release 文档中显式说明 LLVM backend 对 compile-time 的定价。

## 四、结论

当前 `sci` 的最大机会不是“再发明一层模块拆分”，而是：
- 把已有 cache/incremental/parallel 能力文档化、可观测化；
- 把 project cache 和 test cache 从“半透明实现”变成“用户可感知的第一类构建特性”；
- 让文档叙事与 CLI 真实能力对齐，避免用户继续按过时心智使用工具链。

这样做后，编译器速度、迭代体验和 Agent 可编程性都会同步提升。
