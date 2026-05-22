# 06. 标准库 (sa_std) 入门

`sa_std` 是 SA 的官方标准库，它封装了常用的数据结构和系统调用，让汇编开发也能拥有"现代感"。

## 1. 理解 sa_std 的三位一体结构
在审计 `sa_std` 目录时，你会发现一个模块通常由三个文件组成。理解这个约定对导入非常重要：

- **`*.sai` (接口)**：包含 `@extern` 声明。它定义了你能调用哪些函数。
- **`*.sal` (布局)**：包含 `#def` 常量。它定义了内存偏移量和错误代码。
- **`*.sa` (实现)**：包含具体的 SA 代码和 `@macro`。它提供了高级封装。

**最佳实践**：
```sa
@import "sa_std/vec.sal" // 导入布局（常量）
@import "sa_std/vec.sa"        // 导入实现（宏）
// 注意：vec.sa 内部通常会自动 @import 对应的 iface
```

## 2. 动态数组 (`Vec`)
`sa_std/vec.sa` 提供了类似 C++ `std::vector` 的功能。

```sa
@import "sa_std/vec.sal"
@import "sa_std/vec.sa"

L_ENTRY:
    EXPAND VEC_NEW v
    EXPAND VEC_PUSH v, 10
    EXPAND VEC_PUSH v, 20
    len = call @sa_vec_len(v)
    // ...
    EXPAND VEC_FREE v
```

## 2. 字符串处理 (`String`)
SA 的原生字符串是 `utf8` 常量，但动态修改字符串需要 `sa_std/string.sa`。

```sa
@const GREET = utf8:"Hello"

L_ENTRY:
    s = call @sa_string_from_const(&GREET, 5)
    // 拼接字符串
    suffix = utf8:", World"
    call @sa_string_append(s, &suffix, 7)
    !s
```

## 3. 格式化输出 (IO)
使用 `PRINTLN!` 宏可以方便地输出各种类型：

```sa
@import "sa_std/io.sa"

L_ENTRY:
    x = 42
    EXPAND PRINTLN! "Value is: ", x
    !x
```

## 4. 错误处理
SA 不使用异常，而是使用**结果状态码**。大多数 `sa_std` 函数返回 `i32` 状态码：
- `SA_STD_OK (0)`：操作成功。
- `SA_STD_ERR_*`：各种错误代码。

```sa
    res = call @sa_some_op()
    is_err = ne res, 0
    br is_err -> L_HANDLE_ERROR, L_CONTINUE
```

## 为什么 `sa_std` 全是大写宏？
在 SA 中，很多基础操作（如 `VEC_PUSH`）如果作为普通函数调用，会有频繁的函数头开销。因此，`sa_std` 提供了大量**宏 (Macro)**，它们在编译阶段（Flattener）会被内联展开，从而达到极致性能。

## 练习
1. 使用 `Vec` 存储 10 个随机数，并使用 `sa_std/sort.sa` 对其进行排序。
2. 尝试读取用户输入并将其反转输出。
