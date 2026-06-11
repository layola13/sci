# Rc (Reference Counting)

`Rc` 提供了单线程的共享所有权。不同于 `Arc`，`Rc` 内部的引用计数并不是原子操作，因此它的开销更低，但**绝对不能跨线程共享**。

## 导入
```sa
@import "sa_std/core/rc.sa"
```

## 核心宏与用法

### `RC_NEW %out_rc, %value`
分配一个新的 `Rc`。

```sa
EXPAND RC_NEW rc_ptr, 2048
```

### `RC_CLONE %rc_reg`
增加强引用计数。

```sa
EXPAND RC_CLONE rc_ptr
```

### `RC_GET %out_value, %rc_reg`
获取值。

```sa
EXPAND RC_GET val, rc_ptr
```

### `RC_DECREMENT_STRONG_COUNT %rc_reg`
递减引用，当所有引用消失时自动销毁内存。

```sa
EXPAND RC_DECREMENT_STRONG_COUNT rc_ptr
```

### `RC_TRY_UNWRAP %out_ok, %out_value, %rc_reg`
当确信只有一个所有者时，提取内部数据并销毁外壳。

```sa
EXPAND RC_TRY_UNWRAP ok, val, rc_ptr
br ok -> L_OK, L_FAIL
```