SA 项目全面评估与改进计划

 Context

 SA（Safe Assembly）是一个低级安全汇编语言工具链，包含两个仓库：
 - /home/vscode/projects/sci — 核心工具链：编译器（Zig 实现，26K 行）、sa_std 标准库（91 个 SA 模块）、运行时
 - /home/vscode/projects/sa_plugins — 官方插件生态（15 个插件：http-client/server、db、vm、deno、node 等）

 本评估目标：系统梳理安全、性能、正确性三个维度的问题并给出优先级排序的改进计划。

 ---
 第一部分：安全问题（Security）

 🔴 高危

 S1：插件系统无 OS 级沙箱（sa_plugins 全体）

 插件通过 dlopen 加载为普通动态库，与宿主 SA 运行时共享同一进程地址空间。插件可直接访问宿主内存、文件描述符和系统调用——声明的权限（allow_read
 等）仅为约定，无内核级强制。

 修复方向：评估引入 seccomp-bpf（Linux）或 pledge/unveil（OpenBSD）对插件子进程进行系统调用过滤；或将插件迁移到独立进程 + IPC 消息传递模型。

 S2：VM 插件 FFI 逃逸——dlopen(NULL) 加载全局符号表

 sa_plugin_vm/src/ffi.zig:130-132 — 当 --allow-ffi 未设置时，VM 内置 shim 仍允许通过 dlopen(NULL, 2) 加载全局命名空间，可访问 SA
 运行时及所有已链接库中的任意符号，绕过 FFI 限制。

 修复：dlopen(NULL, ...) 调用必须无论 allow_ffi 状态如何均被拦截，返回"permission denied"错误。

 S3：HTTP Client SSRF——URL scheme 无白名单

 sa_plugin_http_client/src/http_saasm_api.zig:272 — std.Uri.parse(req.url) 无 scheme 过滤，允许 file://、data://、内网地址（127.x、169.254.x、10.x
 等）发起请求。

 修复：仅允许 http:// 和 https://；拒绝 loopback 和链路本地地址；有需要时提供 IP 白名单配置。

 S4：容量乘法溢出导致堆分配大小错误（sa_std 标准库）

 受影响文件：
 - sa_std/alloc/vec.sa:140 — next_cap_bytes = mul next_cap, elem_size
 - sa_std/hashmap.sa:203-204 — new_bytes = mul new_cap, HashMapSlot_SIZE
 - sa_std/sync/mpsc.sa:123-124 — __mpsc_data_bytes = mul cap, Mpsc_SLOT_SIZE

 溢出后传给 alloc，实际分配远小于预期，后续写入造成堆越界。

 修复：改用 NUM_U64_CHECKED_MUL（已有实现：sa_std/num.sa），溢出时返回 OOM 错误。

 S5：RwLock 读者计数 load-add-store 非原子

 sa_std/sync/rwlock.sa:38-40 — 多线程并发加读锁时存在数据竞争，读者计数可能丢失更新。

 修复：改为 atomic_rmw_add（与 core/arc.sa 保持一致的模式）。

 ---
 🟡 中危

 S6：HTTP Server 固定栈缓冲区

 sa_plugin_http_server/src/plugin.zig:135,145
 - 请求解析：4KB 固定栈缓冲区（超长 Header 被截断/静默拒绝）
 - 响应缓冲：2KB 固定栈缓冲区
 RFC 7230 建议最低支持 8KB 请求头。

 修复：改为动态分配缓冲区，上限可配置（建议默认 16KB 请求头，可调）。

 S7：HTTP Client/Server 响应体限制不一致

 - CLI 路径：plugin.zig:119 限制 2MB
 - API 路径：http_saasm_api.zig:290 限制 16MB

 修复：统一为同一常量并在文档中明确说明，避免用户预期与实际行为不符。

 S8：TLS 证书验证存在降级风险

 sa_plugin_http_client/src/plugin.zig:89-96
 1. 全局 disable_tls flag 可将 HTTPS 降级为 HTTP
 2. next_https_rescan_certs = false 导致证书更新后不重新扫描

 修复：生产路径移除 disable_tls 检查；添加证书定时重扫（建议 1 小时）。

 S9：DB 插件路径遍历

 sa_plugin_db/src/plugin.zig:232,269 — 表名直接用于文件路径拼接，未过滤 ../。
 table.verifyTable(allocator, ".", table_name) 若 table_name = "../../etc/passwd" 则越界访问。

 修复：对 table_name 执行 validateIdentity()（参考 src/pkg/fetch.zig:29-43 的现有实现）。

 S10：HTTP Server Header 数量无限制

 sa_plugin_http_server/src/http_saasm_api.zig:92-98 — Header 迭代无计数上限，攻击者可发送大量微型 Header 耗尽内存。

 修复：设置 Header 数量上限（建议 100）。

 S11：WebSocket 帧 max_len 未验证

 sa_plugin_http_server/src/http_saasm_api.zig:336-345 — max_len 参数在分配前未检查 > 0 且 < MAX，传入 USIZE_MAX 时触发 OOM。

 修复：分配前验证 0 < max_len <= 合理上限（如 16MB）。

 S12：Arc 引用计数无溢出保护

 sa_std/core/arc.sa:10,33 — atomic_rmw_add 无 u64::MAX 检查，极端场景下引用计数绕回 0 导致 UAF。

 修复：clone 时使用 checked_add，溢出则 trap。

 S13：DB JSON Schema 无深度限制

 sa_plugin_db/src/table.zig:115-120 — JSON 解析无嵌套深度限制，恶意构造的 Schema 可耗尽栈/堆（类"十亿笑"攻击）。

 修复：解析前预验证 JSON 大小上限；或在 Zig 侧限制 max_value_len 参数。

 ---
 🟢 低危

 S14：VM 解析缓存无版本绑定

 sa_plugin_vm/src/plugin.zig:104-142 — 缓存 key 仅基于输入内容指纹，未绑定解析器构建哈希。更新解析器后旧缓存可能执行不兼容字节码。

 修复：将编译器版本/构建哈希混入缓存 key；添加 TTL 或 LRU 淘汰（当前 PARSE_CACHE_MAX_ENTRIES = 8 硬编码）。

 S15：RefCell 无线程安全标注

 sa_std/core/refcell.sa:10-15 — 借用计数非原子操作，未以任何形式标注「不可跨线程使用」（对比 Rust !Send/!Sync）。

 修复：添加文档注释；考虑在 verifier 中为 RefCell 添加 capability 检查阻止跨线程使用。

 ---
 第二部分：性能问题（Performance）

 P1：Vec 线性扩容 O(n²)

 sa_std/alloc/vec.sa:139 — next_cap = add cap, 1，每次超容量 push 均触发 realloc，均摊 O(n²)。

 修复：改为倍增策略：next_cap = max(cap * 2, cap + 1)（参考 hashmap.sa:183 的倍增实现）。

 P2：Mutex 无退让自旋

 sa_std/sync/mutex.sa:6-20 — 纯自旋 + 1ns sleep，高竞争下严重浪费 CPU。

 修复：实现指数退避；短自旋后调用 futex_wait（Linux）/ WaitOnAddress（Windows）进入休眠。

 P3：HTTP Client 流式读取缓冲区过小

 sa_plugin_http_client/src/plugin.zig:164-173 — 1KB 栈缓冲循环读取，每次写 stdout 一个系统调用。

 修复：包裹 std.io.bufferedWriter，减少 syscall 次数。

 P4：HTTP Server Chunked 响应硬编码延迟

 sa_plugin_http_server/src/plugin.zig:64-69 — 两个 chunk 之间固定 sleep(10ms)，SSE 场景下响应延迟不可调。

 修复：将延迟改为可配置参数；考虑事件驱动替代 sleep。

 P5：Flattener 热路径逐行动态分配

 src/flattener.zig — 约 4500 行文本处理，每行调用 allocator.alloc/allocator.dupe。

 修复：引入 Arena Allocator，单文件处理的所有临时分配归入同一 arena，编译完成后一次性释放。

 P6：DB 表元数据无流式加载

 sa_plugin_db/src/table.zig:15-75 — 整张表描述符一次性加载入内存，无懒加载/迭代器接口。

 修复：对大表（1000+ segments）实现迭代器 API，按需加载 segment 元数据。

 ---
 第三部分：正确性 / 代码质量（Correctness & Quality）

 Q1：Vec 越界访问无保护默认路径

 sa_std/vec.sa:39-49 — VEC_GET 无边界检查，VEC_TRY_GET（55-63）才有，命名未区分。

 修复：VEC_GET 默认执行边界检查；无检查版本重命名为 VEC_GET_UNCHECKED。

 Q2：HTTP Client 异步操作静默丢弃错误

 sa_plugin_http_client/src/http_saasm_api.zig:204-209 — 网络错误被 catch null 静默丢弃，调用方无法区分"失败"与"尚未完成"。

 修复：单独存储错误码字段，暴露 sa_http_client_async_error() 查询接口。

 Q3：VM 解析缓存 OOM 时内存泄漏

 sa_plugin_vm/src/plugin.zig:145-157 — clone 失败时缓存条目未释放；缓存无淘汰策略。

 修复：实现 LRU 淘汰；cache full 时驱逐最旧条目再插入。

 Q4：CI 缺少安全模式构建与依赖审计

 .github/workflows/release.yml — 仅构建 + 发布，缺少：
 - zig build test -Drelease-safe（启用运行时安全检查）
 - audit.zig 依赖审计作为 CI gate（代码已有，未接入流水线）
 - Fuzz 测试入口

 修复：CI 增加 release-safe 测试 job；将 audit 作为必通关卡。

 Q5：RwLock 读者计数下溢

 sa_std/sync/rwlock.sa:139-142 — 计数减少前未断言 >= 1。

 修复：添加 assert readers > 0 防护。

 Q6：Broker IPC 裸指针无类型安全

 sa_plugin_db/src/plugin_api.zig:43 — broker callback 使用 ?*anyopaque 传递请求/响应，无类型校验。

 修复：定义 tagged union 或带版本前缀的消息头，在 dispatch 前验证消息类型。

 ---
 四、优先级汇总

 ┌────────┬──────┬───────────────────────────────────┬──────────────────────────────────────────┐
 │ 优先级 │ 编号 │               问题                │                 关键文件                 │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🔴 P0  │ S1   │ 插件无 OS 沙箱                    │ sa_plugins 全体                          │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🔴 P0  │ S2   │ VM FFI dlopen(NULL) 逃逸          │ vm/ffi.zig:130                           │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🔴 P0  │ S3   │ HTTP Client SSRF                  │ http_saasm_api.zig:272                   │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🔴 P0  │ S4   │ 容量乘法溢出 → 堆越界             │ vec.sa:140, hashmap.sa:203, mpsc.sa:123  │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🔴 P0  │ S5   │ RwLock 非原子读者计数（数据竞争） │ sync/rwlock.sa:38                        │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🔴 P0  │ P1   │ Vec 线性扩容 O(n²)                │ alloc/vec.sa:139                         │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟡 P1  │ S6   │ HTTP Server 固定 4KB 缓冲区       │ http_server/plugin.zig:135               │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟡 P1  │ S9   │ DB 路径遍历                       │ db/plugin.zig:232,269                    │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟡 P1  │ S11  │ WebSocket max_len 未验证          │ http_saasm_api.zig:336                   │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟡 P1  │ Q1   │ Vec_GET 命名歧义致误用越界        │ vec.sa:39                                │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟡 P1  │ Q4   │ CI 缺安全模式 + 审计              │ release.yml                              │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟡 P1  │ P2   │ Mutex 无退让自旋                  │ sync/mutex.sa:6                          │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P2  │ S7   │ HTTP 响应体限制不一致             │ plugin.zig:119 vs http_saasm_api.zig:290 │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P2  │ S8   │ TLS 证书降级风险                  │ http_client/plugin.zig:89                │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P2  │ S10  │ Header 数量无限制                 │ http_saasm_api.zig:92                    │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P2  │ S12  │ Arc 引用计数无溢出保护            │ core/arc.sa:10                           │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P2  │ S13  │ DB JSON 无深度限制                │ db/table.zig:115                         │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P2  │ Q2   │ HTTP 异步错误静默丢弃             │ http_saasm_api.zig:204                   │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P2  │ P3   │ HTTP Client 读缓冲太小            │ http_client/plugin.zig:164               │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P3  │ S14  │ VM 缓存无版本绑定                 │ vm/plugin.zig:104                        │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P3  │ S15  │ RefCell 无线程安全标注            │ core/refcell.sa:10                       │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P3  │ Q3   │ VM 缓存 OOM 泄漏 + 无淘汰         │ vm/plugin.zig:145                        │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P3  │ Q5   │ RwLock 读者计数下溢               │ sync/rwlock.sa:139                       │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P3  │ Q6   │ Broker IPC 裸指针无类型安全       │ plugin_api.zig:43                        │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P3  │ P4   │ HTTP Server chunk 延迟硬编码      │ http_server/plugin.zig:64                │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P3  │ P5   │ Flattener 热路径逐行分配          │ src/flattener.zig                        │
 ├────────┼──────┼───────────────────────────────────┼──────────────────────────────────────────┤
 │ 🟢 P3  │ P6   │ DB 表元数据无流式加载             │ db/table.zig:15                          │
 └────────┴──────┴───────────────────────────────────┴──────────────────────────────────────────┘

 ---
 五、验证方法

 # 1. 核心工具链：安全模式构建 + 全量测试
 cd /home/vscode/projects/sci
 zig build -Drelease-safe
 zig build test

 # 2. 专项容器/并发测试
 zig build test --filter std_smoke_containers
 zig build test --filter sa_std_runtime

 # 3. 插件构建
 cd /home/vscode/projects/sa_plugins
 ./build-all.sh

 # 4. S3 SSRF 验证（修复后应返回错误而非发起请求）
 # 构造 url = "file:///etc/passwd" 调用 http-client

 # 5. S4 溢出修复验证
 # 构造 elem_size=0x8000000000000001, cap=2 调用 Vec::push
 # 修复前：mul 溢出为 2，alloc 2 字节；修复后：返回 OOM 错误

 # 6. S9 路径遍历验证（修复后应被拒绝）
 # sa db ingest "../../etc/passwd" csv

 # 7. S2 VM FFI 逃逸验证（修复后应返回 permission denied）
 # 在 VM 中调用 dlopen(NULL, 2) 且 --allow-ffi 未设置
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌