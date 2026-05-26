# SA-ASM Standard Library (sa_std) RFC

## 1. 概述 (Overview)

由于 SA (Symbolic Affine) 刻意移除了内置的类型系统、结构体 (struct)、数组及泛型，标准库 `sa_std` 的本质与传统语言（如 Rust 的 `std` 或 C 的 `libc`）完全不同。

在 SA 中，标准库是一套 **“内存布局契约 (Memory Layout Contracts)”** 和 **“宏与函数原语 (Macros & Functions)”** 的集合。它的构建必须从最底层的内存切片开始，利用 `#def` 和 `[MACRO]` 一层层向上搭建，最终为 LLM 和前端编译器提供开箱即用的业务积木。

### 1.1 当前实现模型：Zig-backed Facade

`sa_std/io`、`sa_std/fs`、`sa_std/net`、`sa_std/fmt`、`sa_std/process`、`sa_std/term` 当前采用真实外部标准库模型：SA 侧只提供 facade contract，具体 I/O、文件系统、网络、格式化、进程控制和终端/事件循环逻辑由 Zig-backed `libsa_std` 实现并在链接期提供符号。

*   **`.sa`**：只包含 `@import`，作为模块入口。
*   **`.sai`**：只包含 `@extern` 签名，声明 Zig-backed C-ABI 符号。
*   **`.sal`**：包含 `#def` 布局/常量，供 SA 代码显式读取；`#version` 元数据等待 R29 落地后再启用。

`process` 的 SA 侧约定单独补充 `SaProcessArgv` 布局常量：调用方构造 `SaProcessArgv` 数组，再把数组首地址和元素个数传给 `sa_std_process_run` / `sa_std_process_spawn`。当需要把子进程输出接入 `epoll` 时，改用 `sa_std_process_spawn_stream`，它会返回 live 的 stdout/stderr 句柄。

`term` 侧补充 `SaTermWinsize` 与 `SaTermEpollEvent` 两个布局常量：前者用于读取窗口大小，后者用于承载 `epoll_wait` 的事件数组。raw mode 会通过 `sa_term_raw_enter` / `sa_term_raw_leave` 形成显式 session 对象，避免把终端状态隐式散落在调用栈里。

仓库内已经附带静态归档 `artifacts/sa_std/libsa_std.a`，可直接用于链接或分发。它由 `zig build sa-std-static -Doptimize=Debug` 生成，对应实现源码位于 `src/runtime/sa_std.zig`，C ABI 头文件位于 `src/runtime/sa_std.h`。

公共 API 保持 Rust-like 命名与行为，但遵守 SA 约束：没有 trait/generic，句柄都是显式 `ptr`，拥有的句柄或缓冲区必须显式 `close` / `free`，写入端必须显式 `flush`。已有 demo 使用的 `sa_print_bytes(&msg, len)` 继续保留，语义等价于 `stdout().write_all(bytes)` 的兼容入口。

Rust 核心语义的最小闭环按布局契约和宏层落地：

- `Option<T>` / `Result<T, E>` 只提供 tag + payload 布局常量和宏包装，不在 SA 源码层复刻 Rust trait/generic。
- `panic` / `panic_msg` 只提供统一终结路径包装，真正的终止语义由 builtin/runtime 处理。
- `iter` 只提供 slice/cursor 级遍历约定，不尝试在 SA 中实现完整 `Iterator` trait。
- `trait` / `generic` 仍然是前端 lowering 责任，SA 侧只承认具体 monomorphized ABI 和具体布局。

这条闭环已由以下文件和冒烟测试覆盖：

- `sa_std/core/option.sa` / `.sal`
- `sa_std/core/result.sa` / `.sal`
- `sa_std/core/panic.sa`
- `sa_std/core/iter.sa` / `.sal`
- `sa_std/rust_core.sa` / `.sal`
- `tests/rust_core_fixture.sa`

本 RFC 规划了 `sa_std` 的四个演进阶段。

---

## 2. 第一阶段：内存基石 (Core Primitives)

目标：定义 SA 世界中最基础的指针形态和内存拷贝操作。

### 2.1 胖指针 / 切片 (Slice)
SA 没有原生数组长度的概念，必须通过胖指针 (Fat Pointer) 约定来传递安全的一维视图。

*   **布局契约：`sa_std/core/slice.sal`**
    ```sa
    #def Slice_SIZE = 16
    #def Slice_ptr  = +0
    #def Slice_len  = +8
    ```

*   **宏与原语：`sa_std/core/slice.sa`**
    ```sa
    // 在栈上或预分配寄存器中初始化 Slice
    [MACRO] SLICE_NEW %slice_reg, %data_ptr, %length
        store %slice_reg+Slice_ptr, %data_ptr as ptr
        store %slice_reg+Slice_len, %length as u64
    [END_MACRO]

    [MACRO] SLICE_GET_PTR %out_ptr, %slice_reg
        %out_ptr = load %slice_reg+Slice_ptr as ptr
    [END_MACRO]

    [MACRO] SLICE_GET_LEN %out_len, %slice_reg
        %out_len = load %slice_reg+Slice_len as u64
    [END_MACRO]
    ```

### 2.2 内存操作 (Mem Ops)
*   **函数：`sa_std/core/mem.sa`**
    提供类似 `memcpy` 和 `memset` 的底层原语，供上层集合复用。
    ```sa
    // 基础内存拷贝
    @export sa_mem_copy(dst: &ptr, src: &ptr, count: u64):
    // ... 内部通过循环 load/store 实现，后期可优化为 LLVM llvm.memcpy intrinsic ...
    
    // 基础内存填充
    @export sa_mem_set(dst: &ptr, val: u8, count: u64):
    // ...
    ```

---

## 3. 第二阶段：动态分配 (Allocations & Smart Pointers)

目标：封装原生 `alloc`，提供类似 Rust `alloc` crate 的堆内存管理结构。

### 3.1 动态数组 (Vector)
*   **布局契约：`sa_std/alloc/vec.sal`**
    ```sa
    #def Vec_SIZE = 24
    #def Vec_ptr  = +0
    #def Vec_cap  = +8
    #def Vec_len  = +16
    ```

*   **函数：`sa_std/alloc/vec.sa`**
    ```sa
    @export sa_vec_new() -> ^ptr:
        // 分配 24 字节外壳，内部 ptr 为空
        // ...

    @export sa_vec_with_capacity(cap: u64, elem_size: u64) -> ^ptr:
        // ...

    // Vec 扩容可能会改变指针，严格体现 SA ^ 所有权转移语义
    @export sa_vec_push(^vec: ptr, elem_ptr: &ptr, elem_size: u64) -> ^ptr:
        // 1. 检查 len == cap
        // 2. 如果满，执行扩容，释放旧内存，转移到新内存
        // 3. 执行 memcpy 放入 elem
        // 4. 返回拥有所有权的新/旧 vec

    @export sa_vec_free(^vec: ptr):
        // 1. 读取 Vec_ptr 并 ! 释放 (如果是合法的话)
        // 2. 释放外壳 !vec
    ```

### 3.2 字符串 (String)
由于 SA 没有原生字符串字面量推导，`String` 本质上是内容为 UTF-8 的 `Vec`。
复用 `Vec` 布局，提供额外宏用于静态只读字符串的绑定。
*   **宏：`sa_std/alloc/string.sa`**
    ```sa
    // 将 @const 声明绑定为动态只读 Slice
    [MACRO] STR_FROM_CONST %out_slice, %const_label, %const_len
        EXPAND SLICE_NEW %out_slice, &%const_label, %const_len
    [END_MACRO]
    ```

### 3.3 引用计数 (Rc)
*   **布局契约：`sa_std/alloc/rc.sal`**
    ```sa
    #def RcBox_refs = +0   // i64 计数器
    #def RcBox_data = +8   // 实际负载起始点
    ```

*   **函数：`sa_std/alloc/rc.sa`**
    ```sa
    @export sa_rc_clone(rc_ptr: &ptr):
        // load -> add 1 -> store

    @export sa_rc_drop(^rc_ptr: ptr):
        // 递减计数。如果减到 0，执行物理 !rc_ptr
        // 若不为 0，则仅通过接收 ^ 所有权来消耗当前上下文的追踪记录
    ```

---

## 4. 第三阶段：并发安全 (Concurrency)

目标：在单线程基础上引入安全的跨线程共享，对标 Rust `std::sync`。此阶段强依赖编译器底层的原子操作 (Atomics) 指令。

### 4.1 互斥锁 (Mutex)
标准库基于底层的 `cmpxchg` 手写轻量级自旋锁 (Spinlock) 或 Futex 桥接。
*   **布局契约：`sa_std/sync/mutex.sal`**
    ```sa
    #def Mutex_SIZE = 8
    #def Mutex_lock = +0   // 0=unlocked, 1=locked
    #def Mutex_data = +8   // 数据载荷 (概念偏移)
    ```

*   **宏：`sa_std/sync/mutex.sa`**
    ```sa
    [MACRO] MUTEX_LOCK %lock_ptr
        // 生成基于 cmpxchg seq_cst 的轮询 jmp 死循环
    [END_MACRO]

    [MACRO] MUTEX_UNLOCK %lock_ptr
        // atomic_store 0 release
    [END_MACRO]
    ```

### 4.2 原子引用计数 (Arc)
与 `Rc` 布局一致，但内部计数器的增减强制使用 `atomic_rmw_add` 和 `atomic_rmw_sub seq_cst`。

---

## 5. 第四阶段：复杂集合与外围生态 (Ecosystem)

目标：支持真正的业务逻辑开发。

### 5.1 哈希表 (HashMap)
*   **实现思路：** 采用开放寻址法 (Open Addressing)。因为链表法需要频繁且琐碎的 `alloc`，不利于扁平的内存管理和局部性。
*   **实现文件：`sa_std/collections/hashmap.sa`**
    *   内置 FNV-1a 或简化版 SipHash。
    *   提供 `sa_map_new`, `sa_map_put`, `sa_map_get`, `sa_map_free` 原语。
*   **哈希集合：** `sa_std/hashset.sa` 在同一张表上复用 `HashMap` 的探针、删除和扩容逻辑，值字段固定为非零哨兵，提供 `sa_set_new`, `sa_set_insert`, `sa_set_contains`, `sa_set_remove`, `sa_set_free`。
    *   对外入口为 `sa_std/collections/hashset.sa`。

### 5.2 缓冲 I/O (BufIO)
*   **实现思路：** 封装 `@sys_read_file` 和 `@sys_write_file`。内部维护 4KB 缓冲，减少系统调用频次，提升读取大文件的吞吐量。
*   **实现文件：`sa_std/io/bufio.sa`**

### 5.3 终端与事件循环 (Terminal & Event Loop)
*   **实现思路：** Linux-first，直接围绕 `termios`、`ioctl` 和 `epoll` 建模。raw mode session 负责保存/恢复终端状态；窗口大小通过 `TIOCGWINSZ` 读取；事件循环通过 `epoll_create1` / `epoll_ctl` / `epoll_wait` 驱动。
*   **实现文件：`sa_std/term.sa`**
    *   `sa_term_raw_enter` / `sa_term_raw_leave` 管理 raw mode session。
    *   `sa_term_winsize` 读取 `SaTermWinsize`。
    *   `sa_term_epoll_create` / `sa_term_epoll_ctl` / `sa_term_epoll_wait` / `sa_term_epoll_close` 组成最小事件循环面。
    *   `sa_std_process_spawn_stream` 返回 live stdout/stderr 句柄，可直接注册到 `epoll`。

### 5.4 重型计算与序列化 (Heavy Compute & Serialization via FFI)
*   **实现思路：** 对于像 JSON 解析、正则表达式匹配等涉及复杂抽象语法树 (AST) 或极高计算密度的任务，**绝对不使用纯 `.sa` 汇编硬搓**。由于 SA 缺乏标签联合 (Enum) 和高级反射系统，用汇编维护一棵动态类型的结构树成本极高且容易出错。
*   **架构解法 (Zig-backed FFI 策略)：** 我们复用 `fs` 和 `net` 的 Facade 模型。将这些“脏活累活”交给底层处理。SA 侧仅通过 `.sai` 暴露一组不透明句柄 (Opaque Handle) 和 Getter/Setter 的 C-ABI 原语。
    *   **JSON:** 作为 Web 生态的最基础血液，**JSON 是唯一被内置进 `sa_std` 核心的序列化格式**。它直接对接现成的 Zig 标准库（`std.json`），并同时提供 DOM 和流式（Streaming）两套解析 API 以应对不同体量的数据。
    *   **Regex (正则表达式):** 由于 Zig `std` 原生不带正则引擎，底层通过 Zig 的零成本 C 互操作性，桥接 POSIX `<regex.h>` 或轻量级 PCRE2。
*   **严格边界约束 (YAML/XML/TOML 下放策略)：**
    *   为了保持 `sa_std` 核心的极度纯粹和体积精简，**YAML、XML、TOML 等格式严禁放入标准库**。
    *   因为 Zig 原生不包含这些引擎，强行塞入 `sa_std` 会导致底层必须打包臃肿的 C 库（如 libyaml、expat）。
    *   **解决方案：** 它们将被移出核心，做成独立的官方扩展包（Ecosystem Packages / Runtime Plugins）。当用户需要时，通过依赖声明单独引入。
*   **示例 1 (JSON 核心模块设计)：`sa_std/encoding/json.sai`**
    针对不同场景，JSON 模块暴露两种 FFI 范式：

    **(A) DOM 树模型 (适合小文件，便捷查询)**
    ```sa
    // 解析返回不透明的树句柄，内存由 Zig 侧 Arena 管理
    @extern sa_json_parse(json_bytes: &ptr, len: u64) -> ^ptr
    @extern sa_json_object_get(node: &ptr, key: &ptr, key_len: u64) -> &ptr
    @extern sa_json_as_f64(node: &ptr) -> f64
    @extern sa_json_free(^node: ptr)
    ```

    **(B) 流式游标模型 / Streaming (针对 100MB+ 大文件，极低内存，零拷贝)**
    ```sa
    // 初始化流式解析器，仅维护底层 Scanner 状态机，不生成树
    @extern sa_json_stream_new(json_bytes: &ptr, len: u64) -> ^ptr

    // 拉取下一个 Token (如 1=ObjectBegin, 5=String, 6=Number)
    @extern sa_json_stream_next(stream: &ptr) -> u32

    // 零拷贝提取 Token 内容 (直接返回指向原 json_bytes 的切片信息)
    @extern sa_json_stream_get_slice_ptr(stream: &ptr) -> &ptr
    @extern sa_json_stream_get_slice_len(stream: &ptr) -> u64

    @extern sa_json_stream_free(^stream: ptr)
    ```
*   **示例 2 (Regex 核心模块)：`sa_std/text/regex.sai`**
    ```sa
    // 编译正则表达式，返回不透明的 Regex 句柄
    @extern sa_regex_compile(pattern: &ptr, pattern_len: u64) -> ^ptr

    // 执行匹配，返回匹配结果句柄 (Match Handle)
    @extern sa_regex_match(regex: &ptr, text: &ptr, text_len: u64) -> ^ptr

    // 提取特定捕获组的内存指针和长度 (索引 0 为全量匹配)
    @extern sa_regex_group_ptr(match: &ptr, group_idx: u32) -> &ptr
    @extern sa_regex_group_len(match: &ptr, group_idx: u32) -> u64

    // 释放句柄
    @extern sa_regex_free(^regex: ptr)
    @extern sa_regex_match_free(^match: ptr)
    ```
*   **优势：** 使得 SA 拥有极高的运行时性能，极大丰富了 Web/文本生态能力，同时避免了编译器过度膨胀，保持了标准库边界的纯粹性。

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

当前 `sa_std` 的最小可持续路线不是继续把 Rust `std` 逐项硬补进 `.sa`，而是把能力边界切成三层，并冻结跨层契约。

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
*   只保留布局契约、稳定的入口函数和极少量兼容宏
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
*   SAASM 侧只保留轻量 `.sai` 和 smoke tests

### 7.6 迁移顺序

1. 冻结 `libsa_runtime` 的 C ABI，先把 allocator / buffer / fs / net / process / env / time / atomics 归拢。
2. 将 JSON streaming parser / serializer 一并下沉到 runtime，避免继续在 SAASM 中扩散复杂状态机。
3. 在 Rust facade 层重建 `Vec` / `String` / `HashMap` / `BTreeMap` / iterator / async / error chain。
4. 将现有 `sa_std/*.sa` 收缩为薄封装和 smoke tests，停止继续扩展为完整标准库。

---

## 8. HTTP Client FFI 补充规划 (OpenAI 中转网关支持)

为了支撑高性能 Web API 中转（如 OpenAI 协议转发）场景，标准库将补充出站（Outbound）HTTPS 请求能力。

### 8.1 示例 3 (HTTP Client 核心模块)：sa_std/net/http_client.sai
采用不透明句柄 (Opaque Handle) + Builder 模式，支持流式 Chunked 返回：

```sa
// 初始化客户端（含 HTTPS/TLS 连接池管理）
@extern sa_http_client_new(use_tls: u8, &out_client: ptr) -> i32!

// 构造请求：组装 URL、Headers 和 Body
@extern sa_http_client_req_new(client: ptr, method: u8, &url: ptr, url_len: u64, &out_req: ptr) -> i32!
@extern sa_http_client_req_add_header(req: ptr, &key: ptr, k_len: u64, &val: ptr, v_len: u64) -> i32!
@extern sa_http_client_req_set_body(req: ptr, &body: ptr, body_len: u64) -> i32!

// 执行并接收：支持流式读取响应体（SSE 打字机模式）
@extern sa_http_client_req_send(req: ptr, &out_resp: ptr) -> i32!
@extern sa_http_client_resp_status(resp: ptr) -> u32
@extern sa_http_client_resp_read_chunk(resp: ptr, &buf: ptr, cap: u64, &out_len: ptr) -> i32!

// 清理
@extern sa_http_client_resp_free(^resp: ptr) -> i32!
@extern sa_http_client_free(^client: ptr) -> i32!
```

### 8.2 核心设计要点
- **原生 TLS 支持**：由底层 Zig `std.http.Client` 利用系统的证书存储完成加密通信，SA 侧无需处理证书握手。
- **SSE 流式支持**：通过 `sa_http_client_resp_read_chunk` 配合 `sa_json_stream`，中转站可以实现“边收边解边发”，达到极致的低延迟和低内存占用。
