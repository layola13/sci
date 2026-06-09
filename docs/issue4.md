SA 项目全面评估与改进计划（性能优先版）

 Context

 SA（Safe Assembly）是一个低级安全汇编语言工具链，包含两个仓库：
 - /home/vscode/projects/sci — 核心工具链：编译器（Zig，26K 行）、sa_std 标准库（91 个 SA 模块）、运行时
 - /home/vscode/projects/sa_plugins — 官方插件生态（15 个插件）

 当前处于快速开发阶段，本计划以性能为第一优先级，安全问题列为 P2/P3 供后续跟进。

 ---
 第一优先级：性能改进（Performance）

 ⚡ PERF-1：导入编译结果持久化缓存（最高价值）

 现状：src/flattener.zig 单次编译内通过 seen_paths（StringHashMap，line
 110）对重复导入去重，但跨编译无任何持久化缓存。每次构建都从磁盘重新读取并完整处理所有导入文件，包括整个 sa_std（91 个模块）。

 基础设施已半就位：FlattenResult（line 137）已为每个包记录 package_source_sha256: ?[32]u8，但仅用于元数据追踪，未用于跳过重新处理。

 改进方案：增量 Flatten 缓存

 缓存键：file_path + source_sha256（内容寻址，自动感知文件变更）
 缓存值：序列化的 FlattenResult（指令列表、符号表、签名等）
 缓存位置：$SA_CACHE_DIR/<sha256[:2]>/<sha256[2:]>.flat.bin（类似 ccache 布局）

 实现步骤：
 1. 在 flattenWithPackages() 入口处，计算入口文件 source_sha256
 2. 查找缓存：命中则反序列化直接返回 FlattenResult，跳过展开+解析
 3. 未命中：正常处理后将结果序列化写入缓存
 4. 对 sa_std 包尤其收益显著（内容稳定，几乎永远命中）

 关键文件：
 - src/flattener.zig — 主入口 expandImports()（line 3111）、flattenWithPackages()
 - src/flattener/def_dict.zig、src/flattener/symbol.zig — 需实现 serialize/deserialize
 - 新建 src/flatten_cache.zig — 缓存读写逻辑

 预期收益：对中大型项目（导入 sa_std + 多个包），编译时间可减少 60-80%。

 ---
 ⚡ PERF-2：Vec 线性扩容 → 倍增策略

 现状：sa_std/alloc/vec.sa:139 — next_cap = add cap, 1
 每次超容量 push 都触发 realloc，均摊复杂度 O(n²)。

 修复：
 ; 修复前
 next_cap = add cap, 1

 ; 修复后（参考 hashmap.sa:183 的倍增实现）
 doubled = mul cap, 2
 next_cap = max doubled, 1   ; 处理 cap=0 边界

 关键文件：sa_std/alloc/vec.sa:139

 ---
 ⚡ PERF-3：Mutex 无退让自旋 → 指数退避

 现状：sa_std/sync/mutex.sa:6-20 — 纯自旋 + 1ns sleep，高竞争下持续占用 CPU。

 修复：实现三阶段退避：
 1. 短自旋（~10 次）— L1 cache 热的情况快速获取
 2. yield（~100 次）— 放出时间片
 3. futex_wait（Linux）/ WaitOnAddress（Windows）— 真正休眠，等待唤醒

 关键文件：sa_std/sync/mutex.sa

 ---
 ⚡ PERF-4：Flattener 热路径 Arena 化

 现状：src/flattener.zig 约 4500 行文本处理，每行调用 allocator.alloc/allocator.dupe，大量小分配导致 allocator 压力大。

 修复：在 flattenInternal() 入口处创建 ArenaAllocator，所有临时字符串分配使用 arena allocator，函数返回前调用 arena.deinit()
 一次性释放。长期存活的结果（FlattenResult 字段）保留使用父 allocator。

 关键文件：src/flattener.zig:flattenInternal()

 ---
 ⚡ PERF-5：HTTP Client 流式读取缓冲区

 现状：sa_plugin_http_client/src/plugin.zig:164-173 — 1KB 栈缓冲逐块读写 stdout，每块一次系统调用。

 修复：包裹 std.io.bufferedWriter（默认 4KB），减少 syscall 次数约 4×。

 关键文件：sa_plugin_http_client/src/plugin.zig:164

 ---
 ⚡ PERF-6：HTTP Server Chunk 响应硬编码延迟可配置化

 现状：sa_plugin_http_server/src/plugin.zig:64-69 — chunk 间固定 sleep(10ms)，不可调。

 修复：将延迟改为 ChunkedResponseConfig.delay_ms 参数（默认 0，用户可配置）。

 ---
 ⚡ PERF-7：DB 表元数据流式加载

 现状：sa_plugin_db/src/table.zig:15-75 — 整张表描述符一次性加载入内存。

 修复：对 segment 列表实现迭代器 API，按需加载，大表（1000+ segments）场景内存占用大幅下降。

 ---
 第二优先级：正确性（Correctness）

 Q1：容量乘法溢出 → 堆越界（高危，但为正确性问题）

 - sa_std/alloc/vec.sa:140、sa_std/hashmap.sa:203、sa_std/sync/mpsc.sa:123
 - 修复：乘法改用 NUM_U64_CHECKED_MUL（sa_std/num.sa 已有实现），溢出返回 OOM

 Q2：RwLock 读者计数非原子

 - sa_std/sync/rwlock.sa:38-40 — load-add-store 存在数据竞争
 - 修复：改为 atomic_rmw_add

 Q3：Vec_GET 命名歧义

 - sa_std/vec.sa:39-49 — VEC_GET 无边界检查，易被误用
 - 修复：VEC_GET 默认有检查；无检查版本重命名 VEC_GET_UNCHECKED

 Q4：HTTP Client 异步错误静默丢弃

 - sa_plugin_http_client/src/http_saasm_api.zig:204-209 — 网络错误被 catch null 吞掉
 - 修复：增加独立错误码字段

 Q5：DB 路径遍历

 - sa_plugin_db/src/plugin.zig:232,269 — 表名未过滤 ../
 - 修复：复用 src/pkg/fetch.zig:validateIdentity() 的现有实现

 Q6：VM 解析缓存 OOM 泄漏 + 无淘汰

 - sa_plugin_vm/src/plugin.zig:145-157 — OOM 时缓存条目未释放；无 LRU
 - 修复：实现 LRU 淘汰（8 条目上限时驱逐最旧）

 Q7：CI 接入安全模式构建

 - .github/workflows/release.yml — 缺少 zig build test -Drelease-safe 步骤
 - 修复：增加 CI job；将 audit.zig 接入流水线

 ---
 第三优先级：安全（Security，快速开发期后处理）

 ┌──────┬──────────────────────────────────┬────────────────────────────┐
 │ 编号 │               问题               │          关键文件          │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S1   │ 插件无 OS 沙箱（设计层面，长期） │ sa_plugins 全体            │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S2   │ VM FFI dlopen(NULL) 逃逸         │ vm/ffi.zig:130             │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S3   │ HTTP Client SSRF                 │ http_saasm_api.zig:272     │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S4   │ HTTP Server 固定 4KB 缓冲区      │ http_server/plugin.zig:135 │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S5   │ TLS 证书降级风险                 │ http_client/plugin.zig:89  │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S6   │ WebSocket max_len 未验证         │ http_saasm_api.zig:336     │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S7   │ DB JSON 无深度限制               │ db/table.zig:115           │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S8   │ Arc 引用计数无溢出保护           │ core/arc.sa:10             │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S9   │ Header 数量无限制                │ http_saasm_api.zig:92      │
 ├──────┼──────────────────────────────────┼────────────────────────────┤
 │ S10  │ RefCell 无线程安全标注           │ core/refcell.sa:10         │
 └──────┴──────────────────────────────────┴────────────────────────────┘

 ---
 执行顺序建议

 Sprint 1（立竿见影）：PERF-1 导入缓存 + PERF-2 Vec 扩容 + Q1 乘法溢出
 Sprint 2（稳定性）：PERF-3 Mutex 退避 + Q2 RwLock + Q3 Vec 命名 + Q5 DB 路径
 Sprint 3（插件性能）：PERF-4 Arena + PERF-5/6/7 插件优化 + Q4/Q6/Q7
 Sprint 4（安全加固）：S2/S3/S4（优先网络相关）→ 其余安全项

 ---
 验证方法

 # PERF-1 验证：二次编译时间应显著缩短
 time sa build main.sa   # 冷启动（建立缓存）
 time sa build main.sa   # 热启动（命中缓存），预期缩短 60%+

 # PERF-2 验证：大量 push 性能基准
 # 构造 10M 次 push 测试，修复后均摊时间应从 O(n²) 降至 O(n)

 # Q1 溢出修复验证
 # elem_size=0x8000000000000001, cap=2 → push 应返回 OOM 而非堆越界

 # Q5 路径遍历验证
 # sa db ingest "../../etc/passwd" csv → 应被拒绝

 # 全量回归
 cd /home/vscode/projects/sci && zig build test
 cd /home/vscode/projects/sa_plugins && ./build-all.sh