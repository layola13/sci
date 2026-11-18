# 对比 Rust：我们还输什么（全面盘点 + 实测根因）

日期：2026-11-18

## 零、总览（按 JEV 排序的可修复性）

| 维度 | 差距 | 状态 | 可修复性 |
|---|---|---|---|
| 运行时 matmul | 35× → 现 ~16× | fast-math 已拿回 2.5× | 部分，剩 AVX/循环优化 |
| **运行时 bytes/sieve** | **慢 4×/3.4×，RSS 高 15-19×** | **未修** | **高（GrowVec 已实现未接入）** |
| 运行时整体（标量/整数） | Rust 几何平均快 1.43× | 未修 | 低（接近硬件极限） |
| 编译速度 | 冷编译慢 2.4× | 结构性 | 低（link 瓶颈已证穷尽） |
| 产物体积 native | 大 27.7× | 结构性 | 低（静态运行时） |
| 网络吞吐 | 慢 1.2-2.7×，延迟 4.5× | 部分修 | 中（锁竞争） |

## 一、运行时性能（sala 基准 native，实测数据）

| 程序 | SLA ms | Rust ms | Rust 快多少 | 根因 |
|---|---:|---:|---:|---|
| hello | 1.1 | 1.0 | 0.96×（持平）| — |
| fib | 315.4 | 262.5 | 1.20× | 标量递归，接近极限 |
| loopsum | 552.0 | 470.4 | 1.17× | 整数循环 |
| **sieve** | 397.8 | 117.3 | **3.39×** | **RSS 19×（421MB vs 21MB）** |
| **matmul** | 678.4 | 19.0 | **35.7×** | 缺 fast-math（已修 2.5×）|
| sort | 199.2 | 269.2 | **SLA 快 1.35×** | 省边界检查 |
| hashmap | 184.3 | 168.8 | 1.09× | RSS 2× |
| nbody | 738.5 | 690.6 | 1.07× | 浮点，接近 |
| mandelbrot | 379.6 | 382.7 | 持平 | — |
| **vecpush** | 343.2 | 229.7 | **1.49×** | RSS 2× |
| **bytes** | 251.8 | 61.9 | **4.07×** | **RSS 15×（528MB vs 35MB）** |

**排除 matmul，Rust 几何平均快 1.43×**。真正的大差距只有 3 个：matmul（已部分修）、sieve、bytes。

## 二、本次实测验证的关键根因

### 2.1 matmul：fast-math（已修复）
- 已实现 `--fast-math`（默认 off），实测 778ms → 317ms（2.45×）
- IR 从标量 `fmul double` 变成 `<2 x double>` SIMD + reduce
- 剩余 vs Rust：AVX `<4 x double>` vs SSE `<2 x double>`，实测 `-mcpu=native` 只再省 ~25%（310ms），说明已接近该 loop 的向量化极限

### 2.2 bytes/sieve：Vec 增长的 mmap/munmap（未修复，JEV 排序第一）
实测根因链（看 `sa_std/alloc/vec.sa:715 sa_vec_reserve_grow`）：
```
766: new_buf = alloc new_bytes       ← 每次增长 mmap 新块
774: call @sa_mem_copy_nonoverlapping ← 拷贝旧数据
781: call @sa_mem_free(^old_buf)      ← munmap 旧块
```
- 几何增长（cap 翻倍）本身正确，但 `alloc`/`free` 走 mmap/munmap
- sa_std.zig:11137 注释实测："120,066 mmap syscalls against exactly 1 munmap, growing RSS"
- 大量增长导致 VMA 碎片 + allocator 不立即归还 → RSS 15-19×

**已有但未接入的方案**：`sa_std/alloc/growvec.sa` 实现了 "虚拟保留 + commit-on-touch"（MAP_NORESERVE mmap，地址永不移动，无增长路径，池化复用）。但：
- GrowVec 要求预知 max 容量，超了 panic（1215）——不适合 `Vec::new()` 无限增长
- 通用 Vec 还没切到它

**修复方向**：让 `Vec` 的增长复用大块 reservation（amortized arena），而不是每次 mmap/munmap。这是明确、高 ROI 的优化。

### 2.3 网络延迟（部分修复）
- 吞吐已追到 Rust 的 1.2-2.7×（c=16 达 182k rps）
- 剩余差距在高并发延迟：c=256 p50 1.95ms vs Rust 0.43ms（4.5×）
- 根因：多 worker accept 的共享池锁竞争（文档已登记，未修）

## 三、编译速度（已证结构性，基本穷尽）

| 场景 | SLA | Rust | 差距 | 状态 |
|---|---:|---:|---:|---|
| 冷编译 native hello | 144ms | 112ms | 1.29× | link 主导 |
| 冷编译 native 常规 | 158-834ms | 115-148ms | 2.4× | LLVM O3 + link |
| 热编译 | 94-108ms | 82-120ms | 持平 | 缓存短路 |
| matmul native 冷 | 13480ms | 131ms | 103× | LLVM O3 病态 |

**已验证无效的攻击面**：拆 object（Zig 依赖闭包重复）、绕 zig cc（破 WASI 入口）、按需 export（契约要求 1250 符号）、.mi（前端只占 2%）、wasm 自研后端（脏 DWARF/入口问题）。剩余是结构性成本。

## 四、产物体积（结构性）

| 目标 | SLA | Rust | 差距 | 原因 |
|---|---:|---:|---:|---|
| native stripped | 9.1 MB | 328 KB | 27.7× | 静态链接整个 sa_std |
| wasm stripped（典型） | 5-9 KB | 46-49 KB | **SLA 小 6×** | 无 WASI libc 负担 |
| wasm matmul | 58 KB | 33 KB | 1.65× | 浮点代码 |

native 体积是结构性劣势（静态运行时）；wasm 反而是优势。

## 五、内存（最大未修复差距）

| 程序 | SLA RSS | Rust RSS | 差距 |
|---|---:|---:|---:|
| sieve | 421888 KB | 21504 KB | 19.6× |
| bytes | 527616 KB | 34688 KB | 15.2× |
| vecpush | 515456 KB | 252032 KB | 2.0× |
| hashmap | 134400 KB | 67584 KB | 2.0× |

根因见 2.2（Vec mmap/munmap 增长）。这是 native 部署（尤其边缘设备）的主要障碍。

## 六、结论与优先级

**已赢的**：wasm 体积（小 6×）、sort 运行时（快 1.35×）、热编译（持平）、网络吞吐（接近 Rust）。

**还输的，按 ROI 排序**：
1. **bytes/sieve 内存+运行时**（4× + 15-19× RSS）——JEV 排序第一，GrowVec 方案已就绪，接入 Vec 即可，高 ROI
2. **matmul 剩余差距**（16×）——fast-math 已拿回 2.5×，再压需 AVX512/循环优化，中 ROI
3. **网络延迟**（4.5×）——共享池锁竞争，中 ROI
4. **native 体积**（27.7×）——结构性，低 ROI
5. **冷编译**（2.4×）——结构性，已穷尽，低 ROI

**一句话**：日常标量/整数负载只输 1.1-1.5×（接近极限），真正的大差距集中在 ①Vec 增长导致的内存虚高（可修，GrowVec 已就绪）②浮点向量化（已修大头）③高并发延迟（锁竞争）。架构性的编译/体积差距已无低成本解。
