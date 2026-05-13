# SA-ASM Standard Library (sa_std) RFC

## 1. 概述 (Overview)

由于 SA (Symbolic Affine) 刻意移除了内置的类型系统、结构体 (struct)、数组及泛型，标准库 `sa_std` 的本质与传统语言（如 Rust 的 `std` 或 C 的 `libc`）完全不同。

在 SA 中，标准库是一套 **“内存布局契约 (Memory Layout Contracts)”** 和 **“宏与函数原语 (Macros & Functions)”** 的集合。它的构建必须从最底层的内存切片开始，利用 `#def` 和 `[MACRO]` 一层层向上搭建，最终为 LLM 和前端编译器提供开箱即用的业务积木。

### 1.1 当前实现模型：Zig-backed Facade

`sa_std/io`、`sa_std/fs`、`sa_std/net`、`sa_std/fmt`、`sa_std/process`、`sa_std/term` 当前采用真实外部标准库模型：SA 侧只提供 facade contract，具体 I/O、文件系统、网络、格式化、进程控制和终端/事件循环逻辑由 Zig-backed `libsa_std` 实现并在链接期提供符号。

*   **`.saasm`**：只包含 `@import`，作为模块入口。
*   **`.saasm-iface`**：只包含 `@extern` 签名，声明 Zig-backed C-ABI 符号。
*   **`.saasm-layout`**：包含 `#def` 布局/常量，供 SA 代码显式读取；`#version` 元数据等待 R29 落地后再启用。

`process` 的 SA 侧约定单独补充 `SaProcessArgv` 布局常量：调用方构造 `SaProcessArgv` 数组，再把数组首地址和元素个数传给 `sa_std_process_run` / `sa_std_process_spawn`。当需要把子进程输出接入 `epoll` 时，改用 `sa_std_process_spawn_stream`，它会返回 live 的 stdout/stderr 句柄。

`term` 侧补充 `SaTermWinsize` 与 `SaTermEpollEvent` 两个布局常量：前者用于读取窗口大小，后者用于承载 `epoll_wait` 的事件数组。raw mode 会通过 `sa_term_raw_enter` / `sa_term_raw_leave` 形成显式 session 对象，避免把终端状态隐式散落在调用栈里。

仓库内已经附带静态归档 `artifacts/sa_std/libsa_std.a`，可直接用于链接或分发。它由 `zig build sa-std-static -Doptimize=Debug` 生成，对应实现源码位于 `src/runtime/sa_std.zig`，C ABI 头文件位于 `src/runtime/sa_std.h`。

公共 API 保持 Rust-like 命名与行为，但遵守 SA 约束：没有 trait/generic，句柄都是显式 `ptr`，拥有的句柄或缓冲区必须显式 `close` / `free`，写入端必须显式 `flush`。已有 demo 使用的 `sa_print_bytes(&msg, len)` 继续保留，语义等价于 `stdout().write_all(bytes)` 的兼容入口。

本 RFC 规划了 `sa_std` 的四个演进阶段。

---

## 2. 第一阶段：内存基石 (Core Primitives)

目标：定义 SA 世界中最基础的指针形态和内存拷贝操作。

### 2.1 胖指针 / 切片 (Slice)
SA 没有原生数组长度的概念，必须通过胖指针 (Fat Pointer) 约定来传递安全的一维视图。

*   **布局契约：`sa_std/core/slice.saasm-layout`**
    ```saasm
    #def Slice_SIZE = 16
    #def Slice_ptr  = +0
    #def Slice_len  = +8
    ```

*   **宏与原语：`sa_std/core/slice.saasm`**
    ```saasm
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
*   **函数：`sa_std/core/mem.saasm`**
    提供类似 `memcpy` 和 `memset` 的底层原语，供上层集合复用。
    ```saasm
    // 基础内存拷贝
    @export sa_mem_copy(dst: &ptr, src: &ptr, count: u64) -> void:
    // ... 内部通过循环 load/store 实现，后期可优化为 LLVM llvm.memcpy intrinsic ...
    
    // 基础内存填充
    @export sa_mem_set(dst: &ptr, val: u8, count: u64) -> void:
    // ...
    ```

---

## 3. 第二阶段：动态分配 (Allocations & Smart Pointers)

目标：封装原生 `alloc`，提供类似 Rust `alloc` crate 的堆内存管理结构。

### 3.1 动态数组 (Vector)
*   **布局契约：`sa_std/alloc/vec.saasm-layout`**
    ```saasm
    #def Vec_SIZE = 24
    #def Vec_ptr  = +0
    #def Vec_cap  = +8
    #def Vec_len  = +16
    ```

*   **函数：`sa_std/alloc/vec.saasm`**
    ```saasm
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

    @export sa_vec_free(^vec: ptr) -> void:
        // 1. 读取 Vec_ptr 并 ! 释放 (如果是合法的话)
        // 2. 释放外壳 !vec
    ```

### 3.2 字符串 (String)
由于 SA 没有原生字符串字面量推导，`String` 本质上是内容为 UTF-8 的 `Vec`。
复用 `Vec` 布局，提供额外宏用于静态只读字符串的绑定。
*   **宏：`sa_std/alloc/string.saasm`**
    ```saasm
    // 将 @const 声明绑定为动态只读 Slice
    [MACRO] STR_FROM_CONST %out_slice, %const_label, %const_len
        EXPAND SLICE_NEW %out_slice, &%const_label, %const_len
    [END_MACRO]
    ```

### 3.3 引用计数 (Rc)
*   **布局契约：`sa_std/alloc/rc.saasm-layout`**
    ```saasm
    #def RcBox_refs = +0   // i64 计数器
    #def RcBox_data = +8   // 实际负载起始点
    ```

*   **函数：`sa_std/alloc/rc.saasm`**
    ```saasm
    @export sa_rc_clone(rc_ptr: &ptr) -> void:
        // load -> add 1 -> store

    @export sa_rc_drop(^rc_ptr: ptr) -> void:
        // 递减计数。如果减到 0，执行物理 !rc_ptr
        // 若不为 0，则仅通过接收 ^ 所有权来消耗当前上下文的追踪记录
    ```

---

## 4. 第三阶段：并发安全 (Concurrency)

目标：在单线程基础上引入安全的跨线程共享，对标 Rust `std::sync`。此阶段强依赖编译器底层的原子操作 (Atomics) 指令。

### 4.1 互斥锁 (Mutex)
标准库基于底层的 `cmpxchg` 手写轻量级自旋锁 (Spinlock) 或 Futex 桥接。
*   **布局契约：`sa_std/sync/mutex.saasm-layout`**
    ```saasm
    #def Mutex_SIZE = 8
    #def Mutex_lock = +0   // 0=unlocked, 1=locked
    #def Mutex_data = +8   // 数据载荷 (概念偏移)
    ```

*   **宏：`sa_std/sync/mutex.saasm`**
    ```saasm
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
*   **实现文件：`sa_std/collections/hashmap.saasm`**
    *   内置 FNV-1a 或简化版 SipHash。
    *   提供 `sa_map_new`, `sa_map_put`, `sa_map_get`, `sa_map_free` 原语。

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

---

## 6. 路线图价值与推进建议

通过这种基于宏和字典的手搓方式，标准库将充当 SA 编译器的**极限试金石**：
1. **倒逼底层：** 在实现 `Vec_push` 时，如果遇到指针更新的所有权问题，将立即测试出 Referee 对 `^` Move 流转校验是否完备。
2. **倒逼原子特性：** 编写 `Arc` 和 `Mutex` 是检验尚未落地的 `atomic_*` 指令的最佳场景。
3. **LLM 友好性：** LLM 几乎不可能直接写对无缺陷的 `HashMap` 扩容逻辑。提供标准库后，LLM 仅需拼接高层宏调用，大幅降低代码生成的废品率。

**下一步建议：**
先在编译器层面实现完整的 9-bit `CapabilityMask` 扩展和原子指令解析，再开启 `sa_std` 第一阶段的代码编写。
