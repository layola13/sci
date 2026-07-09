# `--profile --json` — 编译阶段指标收集

## 用途

`--profile` 标志可以在编译命令中启用阶段计时和内存指标收集。结合 `--json`，输出机器可读的编译性能数据，供 Agent 进行优化反馈。

## 命令签名

```bash
sa build <file> [--profile] [--json] [--mem-report]
sa build-obj <file> [--profile] [--json] [--mem-report]
sa run <file> [--profile] [--json]
sa test <file> [--profile] [--json]
```

## 参数

| 参数 | 说明 |
|---|---|
| `--profile` | 包含编译阶段计时（纳秒精度）在 JSON metrics 中 |
| `--mem-report` | 打印编译各阶段的 RSS 内存采样；JSON 模式下包含在 metrics 中 |
| `--json` | 以 JSON 格式输出诊断和指标 |

## 输出指标

### compile_tokens

编译期 Tokens：记录 Flattener（展开器）和 Referee（验证器）处理代码消耗的内部步数总和。

```
compile_tokens = instructions.len + const_decls.len + function_sigs.len + test_sigs.len + annotated.len
```

宏嵌套越深，`compile_tokens` 越高。

### instruction_count

执行期预估 Tokens：统计验证通过的指令数（`.annotated.len`），Agent 可以用于博弈寻找 `instruction_count` 更低的等价代码写法。

### phases_ns

| 阶段 | 说明 |
|---|---|
| `load` | 源码加载 |
| `setup` | 环境设置 |
| `flatten` | 线性化（展开宏、解析导入） |
| `verify` | 语义验证（Referee） |
| `emit` | LLVM IR 发射 |
| `link` | 链接 |
| `total` | 总耗时 |

### memory / rss_bytes

各阶段结束时的 RSS（Resident Set Size）采样点。

### backend_ir

LLVM 后端 IR 统计（functions、blocks、instructions、alloca_slots、loads、stores）。

## 示例

### 文本模式 — Mem Report

```bash
$ sa build demo.sa --profile --mem-report
memory report (RSS)
  start            5.2 MiB
  after_load      12.8 MiB  delta +7.6 MiB
  after_setup     13.1 MiB  delta +0.3 MiB
  after_flatten   18.4 MiB  delta +5.3 MiB
  after_verify    24.7 MiB  delta +6.3 MiB
  after_emit      26.2 MiB  delta +1.5 MiB
  after_link      28.0 MiB  delta +1.8 MiB
  end             28.0 MiB  delta +0.0 MiB
  peak            28.0 MiB
```

### JSON 模式（完整输出）

```bash
$ sa build demo.sa --profile --json
{"status":"ok","metrics":{"compile_tokens":12050,"instruction_count":842,"phases_ns":{"load":123456,"setup":45678,"flatten":2345678,"verify":5678901,"emit":345678,"link":1234567,"total":12345678},"memory":{"rss_bytes":{"start":5452592,"after_load":13369344,"after_setup":13811712,"after_flatten":19293798,"after_verify":25952256,"after_emit":27472691,"after_link":29360128,"end":29360128},"verifier_rss_bytes":{"start":25952256,"after_classify":26173456,"after_metadata":26306560,"after_chunks":26439680,"parallel_start":26607616,"parallel_after_worker_allocators":26773504,"parallel_after_body":27037696,"parallel_merge":27205632,"after_body":27373568,"after_finalize":25952256,"empty":25952256},"peak_rss_bytes":29360128},"backend":{"ir":{"functions":12,"blocks":48,"instructions":620,"alloca_slots":36,"loads":240,"stores":160}}}}
```

## Agent 使用模式

```bash
# 比较两次编译的指标
$ sa build v1.sa --profile --json | jq '.metrics.compile_tokens, .metrics.instruction_count'
12050
842

$ sa build v2.sa --profile --json | jq '.metrics.compile_tokens, .metrics.instruction_count'
8450
610
# Agent 判断 v2 更优（compile_tokens 降低 30%）

# 检查内存峰值
$ sa build big.sa --profile --json | jq '.metrics.memory.peak_rss_bytes'
52428800  # ~50 MiB
```
