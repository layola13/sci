# SA 标准库 (sa_std) 全景指南

在编写实际的 SA (Safe Assembly) 应用程序时，`sa_std` 提供了开箱即用的标准能力。与传统高级语言不同，SA 的标准库以宏 (Macro) 和底层 ABI 函数为主要暴露形式。

这篇指南将分类梳理 `sa_std` 中的核心模块、常见用法以及最佳实践。由于 SA 在近期版本对底层进行了深度的内存越界、溢出保护以及原子化并发优化，使用标准库（尤其是安全的宏封装）将比你直接书写裸汇编要安全得多。

## 目录
1. [基础核心类型 (Core/Primitives)](#1-基础核心类型-coreprimitives)
2. [动态容器 (Collections)](#2-动态容器-collections)
3. [并发与同步 (Sync & Concurrency)](#3-并发与同步-sync--concurrency)
4. [IO 与网络 (I/O & Network)](#4-io-与网络-io--network)
5. [安全算术运算 (Checked Arithmetic)](#5-安全算术运算-checked-arithmetic)

---

## 1. 基础核心类型 (Core/Primitives)

SA 线性所有权系统的基石。它们提供堆分配的数据包裹、共享指针与内部可变性。

### `Arc` (线程安全的原子引用计数)
`Arc` (Atomic Reference Counting) 提供了针对单实例的线程安全多重持有能力。内部已经对强/弱引用绕回溢出进行了 `panic(1501)` 等严格的安全防护。

```sa
@import "sa_std/core/arc.sa"

@main() -> i32:
L_ENTRY:
    // 创建一个新的 Arc 智能指针封装数字 42
    EXPAND ARC_NEW arc_ptr, 42
    
    // 增加引用计数 (克隆)
    EXPAND ARC_CLONE arc_ptr

    // 获取内部数值
    EXPAND ARC_GET val, arc_ptr
    !val

    // 递减强引用计数，如果计数降为 0 将释放资源 (宏会自动处理)
    EXPAND ARC_DECREMENT_STRONG_COUNT arc_ptr
    EXPAND ARC_DECREMENT_STRONG_COUNT arc_ptr
    return 0
```

### `RefCell` (内部可变性)
用于单线程环境下的借用检查。若被并发修改，请改用 `RwLock` 或 `Mutex`。

```sa
@import "sa_std/core/refcell.sa"

@main() -> i32:
L_ENTRY:
    EXPAND REFCELL_NEW cell, 100

    // 不可变借用
    EXPAND REFCELL_BORROW ok, b_guard, cell, L_ERR
    !b_guard
    !ok
    
    !cell
    return 0
    
L_ERR:
    !cell
    return 1
```

---

## 2. 动态容器 (Collections)

SA 为开发者提供了极为高效且具备底层内存防御机制的容器实现。在发生内存乘法计算溢出等极端状况时会安全中止。

### `Vec` (动态数组)
`Vec` 内部实现了均摊 `O(1)` 的基于两倍容量的扩容机制，并在容量计算溢出时主动断言退出。

```sa
@import "sa_std/vec.sa"

@main() -> i32:
L_ENTRY:
    EXPAND VEC_NEW v
    
    // 压入元素：容器寄存器，值，元素字节大小
    EXPAND VEC_PUSH v, 10, 8
    EXPAND VEC_PUSH v, 20, 8

    // 安全获取索引为 1 的元素。如果索引越界，`ok` 为 0
    EXPAND VEC_TRY_GET_U64 ok, val, v, 1
    br ok -> L_GET_OK, L_GET_FAIL

L_GET_OK:
    // val 将是 20
    !val
    !ok
    jmp L_CLEANUP

L_GET_FAIL:
    !ok
    !val
    jmp L_CLEANUP

L_CLEANUP:
    EXPAND VEC_FREE v
    return 0
```

### `HashMap` (哈希表)
支持键值对存储的字典，底层散列具有完整的插槽和探针分配保护。

```sa
@import "sa_std/hashmap.sa"

@main() -> i32:
L_ENTRY:
    EXPAND HASHMAP_NEW map

    // 插入键值对
    key = utf8:"user_id"
    EXPAND HASHMAP_INSERT map, &key, 1024

    // 获取元素
    EXPAND HASHMAP_GET ok, val, map, &key
    !ok
    !val

    EXPAND HASHMAP_FREE map
    return 0
```

---

## 3. 并发与同步 (Sync & Concurrency)

SA 运行时完全释放了物理所有权的限制。当需要共享状态进行多线程操作时，以下同步原语可以确保你的数据操作完全无数据竞争 (Data Race Free)。

### `RwLock` (读写锁)
支持多读单写。近期底层经过重构，其核心状态的读者计算采用了真正的硬件级原子累加 `atomic_rmw_add`，从机制上杜绝了数据竞争下溢的发生。

```sa
@import "sa_std/sync/rwlock.sa"

@main() -> i32:
L_ENTRY:
    EXPAND RWLOCK_NEW lock

    // 尝试获取读锁
    EXPAND RWLOCK_TRY_READ ok, guard, lock, L_ERR
    !ok
    
    // 释放读锁
    EXPAND RWLOCK_RELEASE_READ lock
    !guard

    !lock
    return 0

L_ERR:
    !lock
    return 1
```

### `Mutex` (互斥锁)
排他性锁。它会在高度竞争下执行指令级指数退避 (Exponential Backoff) 算法以及轻微的挂起，以大幅降低 CPU 自旋负担。

```sa
@import "sa_std/sync/mutex.sa"

@main() -> i32:
L_ENTRY:
    EXPAND MUTEX_NEW mtx
    
    // 阻塞式获取锁
    EXPAND MUTEX_LOCK mtx
    
    // 执行临界区业务代码...
    
    // 释放锁
    EXPAND MUTEX_UNLOCK mtx
    !mtx
    return 0
```

---

## 4. IO 与网络 (I/O & Network)

### `IO` 基础打印
处理标准输出。

```sa
@import "sa_std/io.sa"

@const HELLO_MSG = utf8:"Hello, IO!"

@main() -> i32:
L_ENTRY:
    EXPAND PRINTLN HELLO_MSG, 10
    return 0
```

### `Netx` (高性能并发网络)
深度结合 Linux `io_uring`，极速网络引擎。需要通过 `TicketQueue` 的出列入列机制实现事件驱动机制。该引擎已修复大量有关数据包头部大小伪造导致的截断型 Dos 漏洞。

```sa
@import "sa_std/netx.sai"

@main() -> i32:
L_ENTRY:
    // 初始化 Netx 引擎 (例如：最大并发 10000，使用 4 条专用的内核通讯线程)
    res = call @sa_netx_init(10000, 4)
    !res
    
    host = utf8:"0.0.0.0"
    res = call @sa_netx_listen(&host, 7, 8080)
    !res
    return 0
```

---

## 5. 安全算术运算 (Checked Arithmetic)

直接使用 `add`, `mul` 会导致潜在的硬件位溢出截断。`sa_std/num.sa` 为此提供了具有运行时安全性以及判定分支的分发宏。**凡涉及业务计数、金融计算与内存大小估算，请务必使用此类宏。**

```sa
@import "sa_std/num.sa"

@main() -> i32:
L_ENTRY:
    a = add 0, 100
    b = add 0, 50
    
    // a + b，如果溢出，ok = 0
    EXPAND NUM_U64_CHECKED_ADD ok, res, a, b
    br ok -> L_MATH_OK, L_MATH_OVERFLOW

L_MATH_OK:
    !ok
    !res
    !a
    !b
    return 0

L_MATH_OVERFLOW:
    // 如果走到这里意味着数字计算过大，产生了 u64 溢出截断
    !ok
    !res
    !a
    !b
    return 1
```

---

这只是 `sa_std` 的冰山一角，更多像 `std_ffi_cstr`、`std_time` 等高级宏同样存在于对应的文件中。深入阅读对应的 `.sa` 文件，是进阶 SA 大师之路的必经途径！