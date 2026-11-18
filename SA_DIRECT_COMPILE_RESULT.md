# 手写 .sa 直接编译 wasm — 实测结果

日期：2026-11-18
分支：wasm（sci 隔离副本）

## 一、结论

手写 SA 源（不经过 SLA 前端的契约加载）编译 wasm：
- **小/中程序**：~125ms，与源码大小无关，全是固定开销（宿主启动 + link）
- **100 函数程序**：~243ms，前端 verify 成为新瓶颈
- 对比 MoonBit：hello 16ms（SA 慢 ~8×），100 函数 117ms（SA 慢 ~2×）

**关键洞察**：手写 .sa 绕开了 SLA 前端的 93ms 契约加载，但**仍然慢**——因为瓶颈在 link（81ms）+ 宿主启动，不在前端。这再次证明抄 .mi（优化前端契约加载）对"手写 SA 编译 wasm"路径毫无帮助。

## 二、实测数据（best-of-11，当前机器有负载）

### 手写 .sa → wasm（sci-wasm 的 sa build-wasm --no-incremental）
| 程序 | 源码 | 编译时间 | wasm 大小 |
|---|---:|---:|---:|
| hello | 27 B | 125.1 ms | 1962 B |
| arith | 74 B | 124.5 ms | 2013 B |
| loop | 496 B | 129.2 ms | 2226 B |
| funcs（2函数） | 181 B | 138.8 ms | 2071 B |
| funcs100（100函数） | 5450 B | 242.6 ms | 2072 B |

全部 wasmtime 运行正常。

### 阶段分解（profile）
- hello: `flatten 1 + verify 1 + emit 1 + link 81 = 86ms`（前端 3ms，link 占 94%）
- funcs100: `flatten 34 + verify 64 + emit 5 + link 89 = 195ms`（verify 成新瓶颈）

### MoonBit 对照
| 程序 | 源码 | 编译时间 |
|---|---:|---:|
| hello | 24 B | 16.0 ms |
| scale_100（100函数） | 13009 B | 117.3 ms |

## 三、关键分析

### 1. 固定开销主导小程序
hello→funcs（源码 27B→181B）编译时间几乎不变（125→139ms），因为：
- 宿主启动 + plugin 加载：~15-22ms
- **link（zig cc 静态链接 sa_std）：~81ms**

### 2. 规模上去后 verify 成瓶颈
funcs100 的 verify 从 1ms 涨到 64ms——Referee 的 O(N) 位掩码校验在 100 函数时开始显现。但这是次要问题（大程序才触发）。

### 3. 对 .mi 决策的影响（决定性）
用户想"抄 MoonBit .mi"解决前端契约加载（SLA 插件里 93ms）。但实测：
- **手写 .sa 路径根本没有契约加载**（不经过 SLA 前端），编译仍要 125ms（主要是 link）
- 即使 .mi 把 SLA 前端契约加载从 93ms 降到 0，编译时间也要经过 link 81ms

所以 .mi 的收益只体现在"SLA 编译路径"（.sla → .sa → wasm），对"手写 .sa 直接编译"路径无效。而且 SLA 路径热态契约加载已经 10ms（见 MI_PLAN_AND_ROI.md）。

## 四、.verify 瓶颈（潜在新方向）
funcs100 的 verify 64ms 值得注意——如果目标是编译大量生成代码（LLM 场景），Referee 的线性扫描可能成为瓶颈。但这是另一回事，与 .mi / link 无关。

## 五、结论与建议
1. 手写 .sa 路径的瓶颈是 link（81ms 固定），抄 .mi 对此无效
2. 100 函数时 verify（64ms）成新瓶颈，但属 LLM 大代码场景，非日常
3. 若继续追编译速度，应回到 link 优化（已证穷尽）或接受结构性差距
4. .mi 仅在 SLA 路径有理论收益，但热态已 10ms，ROI 低

## 六、产物
测试源在 /tmp/sa_test/（hello/arith/loop_small/funcs/funcs100.sa + 对应 wasm），全部 wasmtime 运行正常。
