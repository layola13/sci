---
 一、安全问题（Security）

 🔴 高危

 S1：整数乘法溢出导致堆分配大小错误

 受影响文件（均为 sa_std 标准库）：
 - sa_std/alloc/vec.sa:140 — next_cap_bytes = mul next_cap, elem_size（线性扩容后乘以元素大小无溢出检查）
 - sa_std/hashmap.sa:203-204 — new_bytes = mul new_cap, HashMapSlot_SIZE（倍增扩容后乘以槽大小无溢出检查）
 - sa_std/sync/mpsc.sa:123-124 — __mpsc_data_bytes = mul cap, Mpsc_SLOT_SIZE

 风险：乘法结果溢出后传给 alloc 指令，实际分配远小于预期，后续写入造成堆越界。

 修复：在所有 mul capacity, element_size 之前改用 NUM_U64_CHECKED_MUL（已有实现：sa_std/num.sa），溢出时立即返回 OOM 错误。

 S2：RwLock 读锁 load-add-store 非原子

 sa_std/sync/rwlock.sa:38-40

 readers = load lock+RwLock_readers as i32   ; 非原子
 next = add readers, 1
 store lock+RwLock_readers, next             ; 非原子
 风险：多线程并发加读锁，两个线程可能读到相同的 readers 值，最终只增加 1，破坏读者计数。应改为 atomic_rmw_add（与 mutex/arc 保持一致）。

 🟡 中危

 S3：Arc 引用计数无溢出保护

 sa_std/core/arc.sa:10,33 — 使用 atomic_rmw_add，但无 u64::MAX 检查。
 理论上在极端场景（大量克隆）可发生引用计数绕回为 0 导致提前释放（use-after-free）。修复：在 clone 时加 checked_add，溢出则 abort/trap。

 S4：RefCell 非线程安全但未标记

 sa_std/core/refcell.sa:10-15 — 借用计数使用非原子 load/store。文档和 API 未明确禁止跨线程使用（对比 Rust 的 !Send/!Sync
 标注）。建议在文档注释中明确「RefCell 不可跨线程使用」，并在验证器（verifier.zig）添加对应 capability 检查。

 S5：RwLock 读者计数下溢

 sa_std/sync/rwlock.sa:139-142 — 读者计数减少前未验证 >= 1，若锁实现出 bug 可能下溢为负。修复：assert readers > 0 before decrement。

 S6：sa_mem_copy 无边界检查

 sa_std/mem.sa — sa_mem_copy(dst, src, count) 裸指针拷贝，无 src/dst null 检查，无缓冲区大小验证。虽然内部工具函数，但调用方职责不明确，建议加
 @debug_assert(dst != null) 等运行时断言。

 🟢 低危

 S7：包拉取路径验证完整性

 src/pkg/fetch.zig:29-43 — validateIdentity() 已拒绝 ../ 和 null 字节，现状良好。建议补充：规范化后路径须严格在预期目录前缀内（std.fs.path.relative +
 前缀检查），防止 unicode 或双重编码绕过。

 ---
 二、性能问题（Performance）

 P1：Vec 线性扩容策略

 sa_std/alloc/vec.sa:139 — next_cap = add cap, 1（每次扩容只增加 1）。
 标准做法是倍增（max(cap*2, cap+1)）。当前实现在频繁 push 时，每次 push 超容量都触发 realloc，均摊复杂度 O(n²)。
 修复：改为 next_cap = max(mul cap, 2, add cap, 1) 的倍增策略（参考 hashmap.sa:183 的倍增实现）。

 P2：Mutex 自旋无退让

 sa_std/sync/mutex.sa:6-20 — 纯自旋锁，1ns sleep 间隔在高竞争下严重浪费 CPU。
 修复：实现指数退避（exponential backoff）或短自旋后 yield，在 OS 支持时可调用 futex/WaitOnAddress 等系统调用。

 P3：编译器 Flattener 热路径内的动态分配

 src/flattener.zig — 约 4500 行的文本处理，每行都在热路径中执行 allocator.alloc / allocator.dupe / string 拼接。
 建议：引入 Arena Allocator，将单文件处理的所有临时分配归入同一 arena，编译完成后一次性释放，减少系统调用次数。

 P4：Verifier 指令注释循环

 src/verifier.zig — 5374 行验证逻辑，每条指令逐一遍历并计算寄存器状态增量（gas cost）。
 建议：对不改变寄存器状态的纯指令（如 nop、常量加载）做快速路径跳过；对大函数考虑增量验证（仅重新验证修改段）。

 P5：HashMap 哈希函数未指定

 sa_std/hashmap.sa — 当前哈希函数未见加盐（seed）或 SipHash 等防 Hash-flooding 设计。
 建议：针对安全敏感场景（如用户控制输入作 key），提供 HashMap::with_seed(seed) 接口；默认可用固定高速哈希。

 ---
 三、正确性 / 代码质量（Correctness & Quality）

 Q1：Vec 越界访问无保护默认路径

 sa_std/vec.sa:39-49 — VEC_GET 直接索引无边界检查，VEC_TRY_GET（55-63）才有。函数命名未区分 safe/unsafe，极易被调用方误用。
 修复：将无检查版本重命名为 VEC_GET_UNCHECKED，VEC_GET 默认执行边界检查（与 SLICE_TRY_GET_U64 保持一致）。

 Q2：MPSC 尾指针下溢

 sa_std/sync/mpsc.sa:147 — used = sub tail, head 在 tail < head（理论上可能在极端竞态下出现）时下溢。建议加 assert tail >= head。

 Q3：测试覆盖缺口

 - sa_std/sync/rwlock.sa 并发压力测试缺失（只有基本功能测试）
 - sa_std/alloc/vec.sa 大容量扩容（触发多次 realloc）路径未充分覆盖
 - 整数溢出边界 (u64::MAX) 场景

 建议：在 tests/std_smoke_containers.zig 和 tests/sa_std_runtime.zig 中补充并发/边界测试。

 Q4：CI 流水线缺少静态安全扫描

 .github/workflows/release.yml 仅构建 + 发布，无：
 - Zig build with --release-safe（启用运行时安全检查）的 CI job
 - 依赖审计（src/pkg/audit.zig 有实现但未接入 CI）
 - Fuzz 测试入口

 修复：在 CI 中增加 zig build test -Drelease-safe 步骤；将 audit.zig 作为 CI gate 自动运行。

 ---
 四、优先级汇总

 ┌────────┬──────┬───────────────────────────────────┬───────────────────────────────┐
 │ 优先级 │ 编号 │               问题                │           影响文件            │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🔴 P0  │ S1   │ 容量乘法溢出 → 堆越界             │ vec.sa, hashmap.sa, mpsc.sa   │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🔴 P0  │ P1   │ Vec 线性扩容 O(n²)                │ alloc/vec.sa                  │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🔴 P0  │ S2   │ RwLock 非原子读者计数（数据竞争） │ sync/rwlock.sa                │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟡 P1  │ S3   │ Arc 引用计数无溢出保护            │ core/arc.sa                   │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟡 P1  │ Q1   │ Vec_GET 命名歧义导致误用越界      │ vec.sa                        │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟡 P1  │ P2   │ Mutex 无退让自旋                  │ sync/mutex.sa                 │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟡 P1  │ Q4   │ CI 缺少安全模式测试 + 依赖审计    │ .github/workflows/release.yml │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟢 P2  │ S4   │ RefCell 无线程安全标注            │ core/refcell.sa               │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟢 P2  │ S5   │ RwLock 读者计数下溢               │ sync/rwlock.sa                │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟢 P2  │ P3   │ Flattener 热路径分配              │ src/flattener.zig             │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟢 P2  │ Q3   │ 并发/边界测试覆盖缺口             │ tests/                        │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟢 P3  │ S6   │ sa_mem_copy 无断言                │ mem.sa                        │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
 │ 🟢 P3  │ P4   │ Verifier 逐指令验证无快速路径     │ src/verifier.zig              │
 ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟡 P1  │ S3   │ Arc 引用计数无溢出保护            │ core/arc.sa                   │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟡 P1  │ Q1   │ Vec_GET 命名歧义导致误用越界      │ vec.sa                        │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟡 P1  │ P2   │ Mutex 无退让自旋                  │ sync/mutex.sa                 │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟡 P1  │ Q4   │ CI 缺少安全模式测试 + 依赖审计    │ .github/workflows/release.yml │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟢 P2  │ S4   │ RefCell 无线程安全标注            │ core/refcell.sa               │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟢 P2  │ S5   │ RwLock 读者计数下溢               │ sync/rwlock.sa                │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟢 P2  │ P3   │ Flattener 热路径分配              │ src/flattener.zig             │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟢 P2  │ Q3   │ 并发/边界测试覆盖缺口             │ tests/                        │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟢 P3  │ S6   │ sa_mem_copy 无断言                │ mem.sa                        │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟢 P3  │ P4   │ Verifier 逐指令验证无快速路径     │ src/verifier.zig              │                                                              │
     │ ├────────┼──────┼───────────────────────────────────┼───────────────────────────────┤                                                              │
     │ │ 🟢 P3  │ P5   │ HashMap 无哈希防 Flood            │ hashmap.sa                    │                                                              │
     │ └────────┴──────┴───────────────────────────────────┴───────────────────────────────┘                                                              │
     │                                                                                                                                                    │
     │ ---                                                                                                                                                │
     │ 五、验证方法                                                                                                                                       │
     │                                                                                                                                                    │
     │ # 1. 构建（含安全检查）                                                                                                                            │
     │ zig build -Drelease-safe                                                                                                                           │
     │                                                                                                                                                    │
     │ # 2. 运行完整测试套件                                                                                                                              │
     │ zig build test                                                                                                                                     │
     │                                                                                                                                                    │
     │ # 3. 专项：标准库容器测试                                                                                                                          │
     │ zig build test --filter std_smoke_containers                                                                                                       │
     │                                                                                                                                                    │
     │ # 4. 专项：并发运行时测试                                                                                                                          │
     │ zig build test --filter sa_std_runtime                                                                                                             │
     │                                                                                                                                                    │
     │ # 5. 包依赖审计                                                                                                                                    │
     │ zig build audit   # 待 CI 接入后                                                                                                                   │
     │                                                                                                                                                    │
     │ # 6. 手动验证溢出修复                                                                                                                              │
     │ # 构造 elem_size=0x8000000000000001, cap=2 调用 Vec::push，                                                                                        │
     │ # 修复前：mul 溢出为 2，alloc 2 字节；修复后：返回 OOM 错误                                                                                        │
     ╰──────────────────────────────────────────────────────────────────────────