# Option 与 Result

用于替代传统语言里的 NULL 和异常 (Exception) 机制，安全表达结果的存在或失败。

## 导入
```sa
@import "sa_std/core/option.sa"
@import "sa_std/core/result.sa"
```

## Option 核心宏

由于 SA 不使用传统的面向对象结构体，所以 `Option` 和 `Result` 主要借由条件分支结合寄存器操作展开：

### `OPTION_IS_SOME %out_bool, %opt_reg`
### `OPTION_IS_NONE %out_bool, %opt_reg`

## Result 核心宏

### `RESULT_IS_OK %out_bool, %res_reg`
### `RESULT_IS_ERR %out_bool, %res_reg`

在 SA 汇编中，常常直接通过整型的 `0` 来代替成功的 Result (即 `SA_STD_OK`)，错误则分配相应的状态码常量如 `SA_STD_ERR_INVALID_ARGUMENT`。