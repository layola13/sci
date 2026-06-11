# Num (防溢出的安全算术宏)

由于硬件算数寄存器的固定位宽属性，如果在代码里盲目使用原生的 `add`, `mul`, `sub`，很可能遇到整型绕回、上溢和下溢等严重隐患。例如，黑客可能会提交超出预期的高额数字让你的总计数回归成为很小的数字，甚至骗过检查直接操作原本无权的堆内存（内存访问截断）。

SA 特别在 `sa_std/num.sa` 为此封装了具有防御特性的条件安全计算宏，并且 SA 编译器底层也已经全部迁移到这个体系上。

## 导入
```sa
@import "sa_std/num.sa"
```

## 核心宏与用法

这套宏的共同特点是带有 `%out_ok` 参数：如果检测到溢出、下溢或者非法除 0 等数学错误，则返回 `0` 并且终止计算；成功的话返回 `1`。

### 加法与乘法保护

#### `NUM_U64_CHECKED_ADD %out_ok, %out_res, %lhs, %rhs`
#### `NUM_U64_CHECKED_MUL %out_ok, %out_res, %lhs, %rhs`

```sa
    // 假设进行非常庞大的计算
    a = add 0, NUM_U64_MAX_MINUS_ONE
    b = add 0, 10
    
    // a + b 铁定会引发 u64 的整数上溢出！
    EXPAND NUM_U64_CHECKED_ADD ok, res, a, b
    
    // 下方的判定会自动走到 L_OVERFLOW
    br ok -> L_SUCCESS, L_OVERFLOW
L_OVERFLOW:
    // ... 在这里捕捉到非法计算
```

### 减法与除法保护

#### `NUM_U64_CHECKED_SUB %out_ok, %out_res, %lhs, %rhs`
#### `NUM_U64_CHECKED_DIV %out_ok, %out_res, %lhs, %rhs`

```sa
    a = add 0, 5
    b = add 0, 100
    
    // 5 - 100 必然产生下溢！
    EXPAND NUM_U64_CHECKED_SUB ok, res, a, b
    br ok -> L_OK, L_UNDERFLOW
    
L_UNDERFLOW:
    // ...捕获到防下溢！
```