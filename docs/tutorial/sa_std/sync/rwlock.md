# RwLock (读写锁)

当数据存在“绝大部分是多方同时读取，偶发单方写入”的场景下，使用读写锁 (Read-Write Lock) 将比全局互斥锁拥有极高的并发效率。

SA 的 `RwLock` 也通过重构修复了读者下溢以及通过真正的 `atomic_rmw_add` 原语修复了之前并发增加读计数时由于不是纯原子执行产生的状态机丢失漏洞，现在的底层状态是**极致安全的**。

## 导入
```sa
@import "sa_std/sync/rwlock.sa"
```

## 核心宏与用法

### `RWLOCK_NEW %out_lock`

```sa
EXPAND RWLOCK_NEW my_rw_lock
```

### 读者 (读取者)
多个人可以并发读取。

#### `RWLOCK_TRY_READ %out_ok, %out_guard, %lock_reg, %err_label`
带有错误跳出的安全读者获取：
```sa
EXPAND RWLOCK_TRY_READ ok, read_guard, my_rw_lock, L_LOCK_FAIL
// 获取成功，进行共享读取！
...

// 读取结束，释放
EXPAND RWLOCK_RELEASE_READ my_rw_lock
!ok
!read_guard
```

### 写者 (独占更改)
同一时刻只能有一个写入者。且写入时不许有任何正在持有的读取者。

#### `RWLOCK_TRY_WRITE %out_ok, %out_guard, %lock_reg, %err_label`

```sa
EXPAND RWLOCK_TRY_WRITE w_ok, write_guard, my_rw_lock, L_W_FAIL
// 获取成功，具有独占修改权限

...
// 操作完毕
EXPAND RWLOCK_RELEASE_WRITE my_rw_lock
```