# bytes/sieve 内存差距真根因：Vec 元素固定 8 字节槽（实测确证）

日期：2026-11-18
分支：wasm

## 一、结论（推翻之前的假设）

之前我假设 bytes/sieve 的 15× RSS 是 "Vec 增长的 mmap 碎片"，并尝试改 `sa_mem_copy` → `sa_mem_copy_nonoverlapping`。**实测证明这个假设错了，改动无效（392→382ms，RSS 不变），已回滚。**

真根因：**SA 的 Vec 每个元素固定占 8 字节（pointer-sized slot），即使 `Vec<u8>` 也是 8 字节/元素**。Rust 的 `Vec<u8>` 是紧凑的 1 字节/元素。这就是 8× 差距的全部来源。

## 二、实测证据链

### 2.1 数据复现（本轮实测）
| 程序 | 时间 | RSS |
|---|---:|---:|
| 纯循环（零分配） | 47ms | 115 MB |
| 只增长不访问 | 485ms | 268 MB |
| 完整 bytes | 452ms | 268 MB |
| C 精确模拟（1字节元素 malloc+memcpy+free） | 94ms | 34 MB |
| Rust（基准文档） | 62ms | 35 MB |

### 2.2 决定性证据：生成的 .sa 代码
`bytes.sa`（SLA lower 的产物）：
```
line 36: EXPAND VEC_PUSH data, tmp_6, 8     ← Vec<u8> push 用 elem_size=8！
line 78: tmp_17 = mul j, 8                   ← 索引也用 8 字节 stride
line 80: tmp_19 = load tmp_18+0 as u8        ← 实际只读 1 字节，但槽间距是 8
```
33,554,432 个 u8 × 8 字节 = **268,435,456 字节 = 268 MB**，与观测 RSS 完全吻合。

### 2.3 编译器源码确认
`sa_plugin_sla/src/codegen.zig:4170 vecElementSlotSize()`：
```zig
// The slot stride must match the shared lowering rule (and SAB):
// aggregate elements occupy one pointer-sized slot in a Vec buffer.
// The std macros this backend expands (SLICE_GET & friends) hardcode
// an 8-byte stride, and sa_vec_push stores a single word per slot;
// using the struct's inline size here desynchronized push-built
// buffers from slice reads at index >= 1.
return lowering_rules.vecElementSlotSize(ty);
```
**这是有意设计**：所有 Vec 元素统一 8 字节槽（tagged/boxed 模型），保证 push 和 index 一致。注释明确说改成内联 size 会导致 "desynchronized push-built buffers from slice reads"。

## 三、为什么这是根因而非 mmap 碎片

1. 纯循环 RSS 115MB（静态运行时基线，与 Vec 无关）
2. push 增长额外 +153MB，但 C 同样 malloc+memcpy+free 只 +31MB
3. 差异 5×，正好对应 8 字节槽 vs 1 字节元素的比例差
4. 268MB = 33M × 8，数学完全吻合
5. 时间 452ms vs C 94ms ≈ 4.8×，同样对应 8× 数据量下的 cache/memory 带宽效应

## 四、修复难度（为什么没直接改）

要让 `Vec<u8>` 用 1 字节 stride，需同时改：
- `vecElementSlotSize()` 的返回值（按元素类型算真实 size）
- `VEC_PUSH` 宏（push 时的 write stride）
- `SLICE_GET` / index 读取的 8 字节硬编码
- `sa_vec_push` / `sa_vec_reserve_grow` / `sa_vec_extend` 的 elem_size 传递
- SAB 格式的 lowering 规则（要与 bitcode 表示一致）
- 所有 std surface 元数据

这是跨 SLA codegen + SA 运行时 + SAB 契约的**大型一致性重构**，风险极高。注释已警告：单纯改 slot size 会导致 push/index 不同步。

## 五、替代方案（如果只想优化 bytes/sieve 类场景）

1. **提供紧凑容器**：新增 `Bytes` / `RawVec<u8>` 类型，用真实的 1 字节 stride（类似 GrowVec 的思路），专门用于字节数组场景。不改通用 Vec 的语义。
2. **GrowVec 已经是雏形**：`growvec.sa` 用 mmap 虚拟保留 + commit-on-touch，且 `sa_growvec_push` 接受 `elem_size` 参数——可以让它支持 elem_size=1 的紧凑存储。
3. **基准侧规避**：用 `[u8; N]` 固定数组或 GrowVec 重写 bytes/sieve 基准，绕开通用 Vec。

## 六、对"还输什么"的修正

之前 VS_RUST_GAP_ANALYSIS.md 说 bytes/sieve 根因是 "Vec mmap/munmap 增长碎片"——**错误**，应该是 "Vec 元素固定 8 字节槽 vs Rust 紧凑 1 字节"。可修复性从"高（接入 GrowVec）"下调为"中（需新增紧凑容器或大型重构）"。

但好消息：这不是分配器 bug 或碎片问题，而是**设计取舍**（tagged slot 换来了元素地址稳定 + 简化 lowering）。在整数/指针密集型负载（sort/fib/loopsum）这个设计反而有竞争力（sort 快 1.35×）。代价只在 bytes 类小元素大数组场景。

## 七、状态

- 无效改动（sa_mem_copy → nonoverlapping）已回滚，工作区 clean
- 本轮所有实验产物在 /tmp/{bytes_exe,bytes_growonly,rss_base,test_grow2} 等
- 本仓库代码未净增有效改动（除文档）
