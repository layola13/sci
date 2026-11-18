# native 二进制编译速度实测（不对比 WASM）

日期：2026-11-18
分支：wasm

## 一、结论

改用 native 二进制（`sa build-exe`，LLVM-C 后端）实测：

| 程序 | 手写 .sa native（实测） | sala 文档 SLA native 冷编译 | Rust native 冷编译 |
|---|---:|---:|---:|
| hello | **141 ms** | 144 ms | 112 ms |
| arith | 140 ms | — | — |
| loop | 142 ms | — | — |
| funcs（2函数） | 146 ms | — | — |
| funcs100（100函数） | **234 ms** | — | — |
| sort | — | 834 ms | 148 ms |
| matmul | — | 13480 ms | 131 ms |

**关键发现**：手写 .sa（141ms）与 SLA 完整前端（144ms）的 native 编译时间几乎一样——**SLA 前端（契约加载等）在 native 冷编译总时间里占比极小**，LLVM-C emit + link 才是绝对主导。这决定性证明：抄 .mi（优化前端契约加载）对 native 编译速度几乎无收益。

## 二、native 阶段分解（profile）

| 程序 | flatten | verify | emit | link | total |
|---|---:|---:|---:|---:|---:|
| hello（O1） | 1 | 1 | 3 | **102** | 111 ms |
| funcs100（O1） | 30 | **58** | 8 | 99 | 199 ms |
| funcs100（O3） | 30 | **61** | 12 | 111 | 216 ms |

- 小程序：link（zig cc 链接 14MB native sa_std archive）占 90%+
- 100 函数：verify（Referee 位掩码校验）从 1ms 涨到 58ms，成第二瓶颈
- O3 vs O1：link 只多 ~12ms（native 不像 wasm 那样 O3 爆炸，除了 matmul 病态输入）

## 三、产物

- native exe 恒 ~13.7 MB（静态 sa_std 运行时主导，与源码大小无关）
- 全部正常运行（hello exit 7 正确）

## 四、O1 vs O3 对比（best-of-9）

| 程序 | 默认 O1 | release-fast O3 |
|---|---:|---:|
| hello | 141 ms | 150 ms |
| funcs100 | 234 ms | 251 ms |

O3 只慢 ~7%，native 路径的 LLVM 优化不是主要矛盾（与 wasm 结论一致，除了 matmul 异常点）。

## 五、与 Rust 的差距（native 编译）

sala 文档数据：Rust native 冷编译 hello 112ms，常规 115-148ms；SLA native 冷编译 hello 144ms，常规 158-834ms。
- **hello**：SA 141ms vs Rust 112ms → SA 慢 ~1.3×（差距不大）
- **大程序/病态输入**：SA 会被 LLVM O3 拖垮（matmul 13.5s vs Rust 0.13s，100×）

我的手写 SA 实测 141ms 处于 SLA(144ms) / Rust(112ms) 之间，符合预期。

## 六、对 .mi 决策的最终影响（决定性）

三条独立证据链都指向 ".mi 对编译速度无实质帮助"：
1. 手写 .sa 无契约加载，native 编译仍 141ms（link 主导）
2. SLA 完整前端 144ms ≈ 手写 SA 141ms（前端占比 ~3ms）
3. SLA 契约加载热态已 10ms（现有缓存）

**抄 .mi 优化的那段（前端契约 parse）在 native 编译总时间里只占 ~2%**。放弃。

## 七、真正剩下的瓶颈（如果要继续优化 native）

1. **link 102ms（主导）**：zig cc 链接 14MB native archive —— 与 wasm 路径同源问题，且 native archive 更大（66MB）
2. **verify 58ms（100函数时）**：Referee 线性扫描，LLM 大代码场景相关
3. **matmul 的 LLVM O3 爆炸**：病态输入，13.5s vs 0.13s

前两个是结构性的（link），第三个是特定 pattern。都不是 .mi 能解决的。

## 八、状态

测试源在 /tmp/sa_test/，全部编译+运行正常。数据已提交到本分支。
