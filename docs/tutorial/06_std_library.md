# 06. 标准库 (sa_std) 入门

`sa_std` 是 SA 的官方标准库，它封装了常用的数据结构和系统调用，让汇编开发也能拥有"现代感"。

## 1. 理解 sa_std 的三位一体结构
在审计 `sa_std` 目录时，你会发现一个模块通常由三个文件组成。理解这个约定对导入非常重要：

- **`*.sai` (接口)**：包含 `@extern` 声明。它定义了你能调用哪些函数。
- **`*.sal` (布局)**：包含 `#def` 常量。它定义了内存偏移量和错误代码。
- **`*.sa` (实现)**：包含具体的 SA 代码和 `[MACRO]`。它提供了高级封装。

**最佳实践**：
```sa
@import "sa_std/vec.sa"
```

## 2. 动态数组 (`Vec`)
`sa_std/vec.sa` 提供了类似 C++ `std::vector` 的功能。

```sa
@import "sa_std/vec.sa"

@main() -> i32:
L_ENTRY:
    EXPAND VEC_NEW v
    EXPAND VEC_PUSH v, 10, 8
    EXPAND VEC_PUSH v, 20, 8
    EXPAND VEC_LEN len, v
    !len
    EXPAND VEC_FREE v
    return 0
```

## 3. 打印输出 (IO)
使用 `sa_std/io.sa` 中的 `PRINT` / `PRINTLN` 宏可以输出静态字节串：

```sa
@import "sa_std/io.sa"

@const MSG = utf8:"Value"

@main() -> i32:
L_ENTRY:
    EXPAND PRINTLN MSG, 5
    return 0
```

## 4. 格式化
数值格式化目前以 `sa_std/fmt.sai` 的 ABI 暴露出来，但这部分接口对入门教程来说更偏底层。这里先记住两点：它是可失败的返回接口，且返回的缓冲区需要按 ABI 规则释放。

## 5. 错误处理
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
