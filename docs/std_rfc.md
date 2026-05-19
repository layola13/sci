# SA-ASM Standard Library (sa_std) RFC

## 1. 概述 (Overview)

由于 SA (Symbolic Affine) 刻意移除了内置的类型系统、结构体 (struct)、数组及泛型，标准库 `sa_std` 的本质与传统语言（如 Rust 的 `std` 或 C 的 `libc`）完全不同。

在 SA 中，标准库是一套 **“内存布局契约 (Memory Layout Contracts)”** 和 **“寄存器状态转移宏 (Macro-based State Machine Transfers)”**。它的核心目标是：
1.  **降低 LLM 生成成本**：提供高度封装的 `VEC_PUSH`, `MAP_GET` 等宏，避免 LLM 手算字节偏移量。
2.  **强制所有权安全**：通过宏内置 `^` (move) 和 `!` (release) 符号，确保符合 Referee 的静态检查。
3.  **零运行时开销**：绝大多数标准库逻辑在 Flattener 阶段被完全展开为扁平指令。

---

## 2. 第一阶段：基础内存与字符串 (Memory & String)

### 2.1 动态数组 (Vec)
*   **布局契约：`sa_std/collections/vec.saasm-layout`**
    ```saasm
    #def Vec_SIZE = 24
    #def Vec_ptr  = +0   // 指向堆内存的裸指针
    #def Vec_len  = +8   // 当前元素数量
    #def Vec_cap  = +16  // 已分配容量
    ```
*   **核心宏：** `VEC_NEW`, `VEC_PUSH`, `VEC_POP`, `VEC_GET`, `VEC_FREE`。
*   **实现要点：** `VEC_PUSH` 内部通过 `ge len, cap` 判断并调用 `@sa_alloc_grow`。

### 2.2 字符串 (String)
*   **布局契约：** 复用 `Vec` 布局，元素固定为 `u8`。
*   **核心宏：** `STR_FROM_CONST`, `STR_CONCAT`, `STR_SLICE`。

---

## 3. 第二阶段：系统调用与 I/O (OS & IO)

### 3.1 文件系统 (FileSystem)
*   **核心原语封装：** `@sys_read_file`, `@sys_write_file`。
*   **FFI 模式：** 采用不透明句柄 (Opaque Handle) 模式。
    ```saasm
    @extern sa_fs_open(&path: ptr) -> ^handle
    @extern sa_fs_close(^h: handle) -> void
    ```

### 3.2 网络 (Networking)
*   **同步模式：** 基于阻塞 Socket。
*   **异步模式（路线图）：** 配合 `libsa_async` 宏，实现非阻塞 `epoll` 桥接。

---

## 4. 第三阶段：并发与引用计数 (Concurrency & Pointers)

### 4.1 引用计数 (Rc)
*   **布局契约：** `[strong_count: u64 | weak_count: u64 | data: T]`。
*   **核心宏：** `RC_CLONE` (加计数), `RC_DROP` (减计数并条件释放)。

### 4.2 原子引用计数 (Arc)
与 `Rc` 布局一致，但内部计数器的增减强制使用 `atomic_rmw_add` 和 `atomic_rmw_sub seq_cst`。

---

## 5. 第四阶段：复杂集合与外围生态 (Ecosystem)

目标：支持真正的业务逻辑开发。

### 5.1 哈希表 (HashMap)
*   **实现思路：** 采用开放寻址法 (Open Addressing)。因为链表法需要频繁且琐碎的 `alloc`，不利于扁平的内存管理和局部性。
*   **实现文件：`sa_std/collections/hashmap.saasm`**
    *   内置 FNV-1a 或简化版 SipHash。
    *   提供 `sa_map_new`, `sa_map_put`, `sa_map_get`, `sa_map_free` 原语。
*   **哈希集合：** `sa_std/hashset.saasm` 在同一张表上复用 `HashMap` 的探针、删除和扩容逻辑，值字段固定为非零哨兵，提供 `sa_set_new`, `sa_set_insert`, `sa_set_contains`, `sa_set_remove`, `sa_set_free`。
    *   对外入口为 `sa_std/collections/hashset.saasm`。

### 5.2 缓冲 I/O (BufIO)
*   **实现思路：** 封装 `@sys_read_file` 和 `@sys_write_file`。内部维护 4KB 缓冲，减少系统调用频次，提升读取大文件的吞吐量。
*   **实现文件：`sa_std/io/bufio.saasm`**

### 5.3 终端与事件循环 (Terminal & Event Loop)
*   **实现思路：** Linux-first，直接围绕 `termios`、`ioctl` 和 `epoll` 建模。raw mode session 负责保存/恢复终端状态；窗口大小通过 `TIOCGWINSZ` 读取；事件循环通过 `epoll_create1` / `epoll_ctl` / `epoll_wait` 驱动。
*   **实现文件：`sa_std/term.saasm`**
    *   `sa_term_raw_enter` / `sa_term_raw_leave` 管理 raw mode session。
    *   `sa_term_winsize` 读取 `SaTermWinsize`。
    *   `sa_term_epoll_create` / `sa_term_epoll_ctl` / `sa_term_epoll_wait` / `sa_term_epoll_close` 组成最小事件循环面。
    *   `sa_std_process_spawn_stream` 返回 live stdout/stderr 句柄，可直接注册到 `epoll`。

### 5.4 重型计算与序列化 (Heavy Compute & Serialization via FFI)
*   **实现思路：** 对于像 JSON 解析、正则表达式匹配等涉及复杂抽象语法树 (AST) 或极高计算密度的任务，**绝对不使用纯 `.saasm` 汇编硬搓**。由于 SA 缺乏标签联合 (Enum) 和高级反射系统，用汇编维护一棵动态类型的结构树成本极高且容易出错。
*   **架构解法 (Zig-backed FFI 策略)：** 我们复用 `fs` 和 `net` 的 Facade 模型。将这些“脏活累活”交给底层处理。SA 侧仅通过 `.saasm-iface` 暴露一组不透明句柄 (Opaque Handle) 和 Getter/Setter 的 C-ABI 原语。
    *   **JSON:** 作为 Web 生态的最基础血液，**JSON 是唯一被内置进 `sa_std` 核心的序列化格式**。它直接对接现成的 Zig 标准库（`std.json`），并同时提供 DOM 和流式（Streaming）两套解析 API 以应对不同体量的数据。
    *   **Regex (正则表达式):** 由于 Zig `std` 原生不带正则引擎，底层通过 Zig 的零成本 C 互操作性，桥接 POSIX `<regex.h>` 或轻量级 PCRE2。
    *   **HTTP Client (HTTPS 客户端):** 为了支持 OpenAI 等现代 Web API 中转需求，标准库将内置基于 Zig `std.http.Client` 的高性能 FFI 接口，原生支持 HTTPS/TLS 和流式响应（SSE）。
*   **严格边界约束 (YAML/XML/TOML 下放策略)：**
    *   为了保持 `sa_std` 核心的极度纯粹和体积精简，**YAML、XML、TOML 等格式严禁放入标准库**。
    *   因为 Zig 原生不包含这些引擎，强行塞入 `sa_std` 会导致底层必须打包臃肿的 C 库（如 libyaml、expat）。
    *   **解决方案：** 它们将被移出核心，做成独立的官方扩展包（Ecosystem Packages / Runtime Plugins）。当用户需要时，通过依赖声明单独引入。
*   **示例 1 (JSON 核心模块设计)：`sa_std/encoding/json.saasm-iface`**
    针对不同场景，JSON 模块暴露两种 FFI 范式：

    **(A) DOM 树模型 (适合小文件，便捷查询)**
    ```saasm
    // 解析返回不透明的树句柄，内存由 Zig 侧 Arena 管理
    @extern sa_json_parse(json_bytes: &ptr, len: u64) -> ^ptr
    @extern sa_json_object_get(node: &ptr, key: &ptr, key_len: u64) -> &ptr
    @extern sa_json_as_f64(node: &ptr) -> f64
    @extern sa_json_free(^node: ptr) -> void
    ```

    **(B) 流式游标模型 / Streaming (针对 100MB+ 大文件，极低内存，零拷贝)**
    ```saasm
    // 初始化流式解析器，仅维护底层 Scanner 状态机，不生成树
    @extern sa_json_stream_new(json_bytes: &ptr, len: u64) -> ^ptr

    // 拉取下一个 Token (如 1=ObjectBegin, 5=String, 6=Number)
    @extern sa_json_stream_next(stream: &ptr) -> u32

    // 零拷贝提取 Token 内容 (直接返回指向原 json_bytes 的切片信息)
    @extern sa_json_stream_get_slice_ptr(stream: &ptr) -> &ptr
    @extern sa_json_stream_get_slice_len(stream: &ptr) -> u64

    @extern sa_json_stream_free(^stream: ptr) -> void
    ```
*   **示例 2 (Regex 核心模块)：`sa_std/text/regex.saasm-iface`**
    ```saasm
    // 编译正则表达式，返回不透明的 Regex 句柄
    @extern sa_regex_compile(pattern: &ptr, pattern_len: u64) -> ^ptr

    // 执行匹配，返回匹配结果句柄 (Match Handle)
    @extern sa_regex_match(regex: &ptr, text: &ptr, text_len: u64) -> ^ptr

    // 提取特定捕获组的内存指针和长度 (索引 0 为全量匹配)
    @extern sa_regex_group_ptr(match: &ptr, group_idx: u32) -> &ptr
    @extern sa_regex_group_len(match: &ptr, group_idx: u32) -> u64

    // 释放句柄
    @extern sa_regex_free(^regex: ptr) -> void
    @extern sa_regex_match_free(^match: ptr) -> void
    ```
*   **示例 3 (HTTP Client 核心模块)：`sa_std/net/http_client.saasm-iface`**
    采用不透明句柄 (Opaque Handle) + Builder 模式，支持流式 Chunked 返回：
    ```saasm
    // 初始化客户端（含 HTTPS/TLS 连接池管理）
    @extern sa_http_client_new(use_tls: u8, &out_client: ptr) -> i32!
    
    // 构造请求：组装 URL、Headers 和 Body
    @extern sa_http_req_new(client: ptr, method: u8, &url: ptr, url_len: u64, &out_req: ptr) -> i32!
    @extern sa_http_req_add_header(req: ptr, &key: ptr, k_len: u64, &val: ptr, v_len: u64) -> i32!
    @extern sa_http_req_set_body(req: ptr, &body: ptr, body_len: u64) -> i32!
    
    // 执行并接收：支持流式读取响应体（SSE 打字机模式）
    @extern sa_http_req_send(req: ptr, &out_resp: ptr) -> i32!
    @extern sa_http_resp_status(resp: ptr) -> u32
    @extern sa_http_resp_read_chunk(resp: ptr, &buf: ptr, cap: u64, &out_len: ptr) -> i32!
    
    // 清理
    @extern sa_http_resp_free(^resp: ptr) -> i32!
    @extern sa_http_client_free(^client: ptr) -> i32!
    ```

---

## 6. 路线图价值与推进建议

通过这种基于宏和字典的手搓方式，标准库将充当 SA 编译器的**极限试金石**：
1. **倒逼底层：** 在实现 `Vec_push` 时，如果遇到指针更新的所有权问题，将立即测试出 Referee 对 `^` Move 流转校验是否完备。
2. **倒逼原子特性：** 编写 `Arc` 和 `Mutex` 是检验尚未落地的 `atomic_*` 指令的最佳场景。
3. **LLM 友好性：** LLM 几乎不可能直接写对无缺陷的 `HashMap` 扩容逻辑。提供标准库后，LLM 仅需拼接高层宏调用，大幅降低代码生成的废品率。

**下一步建议：**
先在编译器层面实现完整的 9-bit `CapabilityMask` 扩展和原子指令解析，再开启 `sa_std` 第一阶段的代码编写。

---

## 7. Runtime-First Split (当前执行方向)

当前 `sa_std` 的最小可持续路线不是继续把 Rust `std` 逐项硬补进 `.saasm`，而是把能力边界切成三层，并冻结跨层契约。

### 7.1 Zig `libsa_runtime`

这一层承载最重、最不适合 SAASM 手写的基础件，目标是稳定 C ABI，不暴露泛型、trait 或复杂的 SA 级 ownership 语义。

*   allocator
*   byte buffer
*   `fs` / `net` / `process` / `env` / `time` / `atomics`
*   JSON streaming parser / serializer
*   其它重型基础件，例如正则、散列、压缩、复杂解析器

### 7.2 Rust facade

这一层负责把 runtime 重新组织成 Rust 风格 API，补齐 SA 不擅长承担的抽象面。

*   `Option` / `Result`
*   `Vec` / `String` / `HashMap` / `BTreeMap`
*   iterator / async / error chain
*   JSON 高层 API

### 7.3 SAASM

这一层只保留薄封装，不再承担重语义实现。

*   只做 import / macro / ABI glue / smoke tests
*   只保留布局契约、稳定的入口函数 and 极少量兼容宏
*   不再把完整数据结构、重解析器、复杂状态机继续压在 SAASM 上

### 7.4 模块归位规则

*   低层系统能力和重型解析器进入 `libsa_runtime`
*   容器、迭代器和错误链优先进入 Rust facade
*   SAASM 只保留跨层桥接和验证样例

### 7.5 JSON 的位置

JSON 不再作为 SAASM 里需要手写完整树结构的目标，而是优先下沉到 runtime。

*   runtime 负责 streaming parse / serialize
*   runtime 暴露 opaque handle、token getter、writer sink
*   Rust facade 提供 serde-like 访问和错误封装
*   SAASM 侧只保留轻量 `.saasm-iface` 和 smoke tests

### 7.6 迁移顺序

1. 冻结 `libsa_runtime` 的 C ABI，先把 allocator / buffer / fs / net / process / env / time / atomics 归拢。
2. 将 JSON streaming parser / serializer 一并下沉到 runtime，避免继续在 SAASM 中扩散复杂状态机。
3. 在 Rust facade 层重建 `Vec` / `String` / `HashMap` / `BTreeMap` / iterator / async / error chain。
4. 将现有 `sa_std/*.saasm` 收缩为薄封装和 smoke tests，停止继续扩展为完整标准库。
