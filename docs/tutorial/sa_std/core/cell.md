# RefCell & Cell

用于提供“内部可变性”。在 SA 的线性所有权下，有些时候你持有不可变借用，却需要修改数据。`Cell` 提供了对按值复制的数据的无检查读写，`RefCell` 提供了具有运行时借用检查保护的读写。

## 导入
```sa
@import "sa_std/core/refcell.sa"
@import "sa_std/core/cell.sa"
```

## RefCell 核心宏

### `REFCELL_NEW %out_cell, %value`
包裹一个值。

### `REFCELL_BORROW %out_ok, %out_borrow, %cell_reg, %err_label`
不可变借用。如果没有处于可变借用中，则返回借用指针，否则跳转到 `%err_label`。

```sa
EXPAND REFCELL_BORROW ok, b_guard, cell, L_ERR
```

### `REFCELL_BORROW_MUT %out_ok, %out_borrow, %cell_reg, %err_label`
可变借用。只有在此刻没有任何其他借用时才成功，否则引发借用冲突错误。

```sa
EXPAND REFCELL_BORROW_MUT ok, mut_guard, cell, L_ERR
L_OK:
    // 修改内部数据
    store mut_guard+0, 999 as u64
    !ok
    !mut_guard
    jmp L_DONE
```

> **注意**: 在离开作用域前，务必对借用对象使用销毁操作或相应的解除借用，以恢复内部引用计数器。

---

## Cell 核心宏

由于 `Cell` 是直接对数据本身赋值而没有复杂的引用检查器，常被用来存放像布尔值等基本类型：

### `CELL_NEW %out_cell, %value`
### `CELL_GET %out_value, %cell_reg`
### `CELL_SET %cell_reg, %new_value`
### `CELL_REPLACE %out_old, %cell_reg, %new_value`

```sa
EXPAND CELL_NEW my_cell, 10
// 将 my_cell 替换成 20，并把老值(10)赋给 old_val
EXPAND CELL_REPLACE old_val, my_cell, 20
```