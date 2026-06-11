# Box

`Box` 提供最简单的堆分配（Heap Allocation）。当对象需要在不同函数中移交且占用空间过大不适合使用寄存器或栈分配时使用。

## 导入
```sa
@import "sa_std/core/box.sa"
```

## 核心宏与用法

### `BOX_NEW %out_box, %value`
分配堆内存并放入值。

```sa
EXPAND BOX_NEW b, 999
```

### `BOX_INTO_RAW %out_ptr, %box_reg`
释放包装，获取底层的裸指针（此时你需要手动确保释放内存以防止泄露）。

```sa
EXPAND BOX_INTO_RAW raw_ptr, b
```

### `BOX_FROM_RAW %out_box, %raw_ptr`
接收一个裸指针的所有权重新恢复为一个被 `Box` 管理的包裹。

```sa
EXPAND BOX_FROM_RAW new_box, raw_ptr
```

### `BOX_FREE %box_reg`
释放分配的内存。

```sa
EXPAND BOX_FREE b
```