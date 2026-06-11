# Mutex (互斥锁)

用于多线程保护的底层互斥锁原语。它能够有效避免 Data Race（数据竞争）。

SA 标准库近期对 `Mutex` 做了针对性的算法优化，由原来的激进“纯轮询占用 CPU”方案，更新成了基于 **指数退避自旋 (Exponential Backoff)** 加系统休眠的混合算法。在保证低延迟竞争锁获取的前提下，极大降低了长期无法获取锁时的无效 CPU 使用。

## 导入
```sa
@import "sa_std/sync/mutex.sa"
```

## 核心宏与用法

### `MUTEX_NEW %out_mutex`
分配并在堆上建立一个被保护的锁定块状态机。

```sa
EXPAND MUTEX_NEW my_mtx
```

### `MUTEX_LOCK %lock_ptr`
尝试获取锁的所有权。如果已有其他线程获取，当前线程将会进入“自旋 -> 增长间隙退避 -> 系统指令休眠等待唤醒”的智能等待期。

```sa
EXPAND MUTEX_LOCK my_mtx
```

### `MUTEX_TRY_LOCK %out_ok, %lock_ptr`
不阻塞。如果立刻获取锁成功 `ok` 为 1，否则为 0。

### `MUTEX_UNLOCK %lock_ptr`
在所有操作执行结束，安全边界之外，务必解锁释放给其他人。

```sa
EXPAND MUTEX_UNLOCK my_mtx
```