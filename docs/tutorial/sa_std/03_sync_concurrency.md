# 3. 并发与同步 (Sync & Concurrency)

SA 运行时完全释放了物理所有权的限制。当需要共享状态进行多线程操作时，以下同步原语可以确保你的数据操作完全无数据竞争 (Data Race Free)。

## `RwLock` (读写锁)
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

## `Mutex` (互斥锁)
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

## `Mpsc` (多生产者单消费者通道)
用于跨线程消息传递。通道的底层分配已被全面安全加固，在处理大容量边界时可有效防止乘法溢出与越界写。

```sa
@import "sa_std/sync/mpsc.sa"

@main() -> i32:
L_ENTRY:
    // 创建一个容量为 100 的 MPSC 通道
    EXPAND MPSC_NEW chan, 100
    
    // 发送消息
    EXPAND MPSC_SEND ok, chan, 42
    !ok
    
    // 接收消息
    EXPAND MPSC_TRY_RECV ok, msg, chan
    !msg
    !ok
    
    EXPAND MPSC_FREE chan
    return 0
```