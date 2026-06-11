# 5. 安全算术运算 (Checked Arithmetic)

使用原生 SA 指令（如 `add`, `mul`）直接运算可能会导致硬件溢出截断（例如，计算容量、处理用户传入的大数值时）。`sa_std/num.sa` 为此提供了运行时安全检查的宏。发生溢出时，它们会返回 `0`（通过带有失败分支的模式）而不是导致逻辑漏洞。

**凡涉及业务计数、金融计算与分配内存大小估算，请务必采用此类宏以实现“防御性编程”。**

## `NUM_U64_CHECKED_ADD` / `NUM_U64_CHECKED_MUL`
执行加法与乘法，如果溢出，控制流可以通过标志位跳转至错误处理逻辑。SA 编译器自身（如 `Vec` 扩容或通道预分配）正是大量使用该宏对系统安全性进行的兜底。

```sa
@import "sa_std/num.sa"

@main() -> i32:
L_ENTRY:
    a = add 0, 100
    b = add 0, 50
    
    // a + b，如果发生无符号整数溢出（超过 U64 MAX），ok 将等于 0
    EXPAND NUM_U64_CHECKED_ADD ok, res, a, b
    br ok -> L_MATH_OK, L_MATH_OVERFLOW

L_MATH_OK:
    // 计算成功
    !ok
    !res
    !a
    !b
    return 0

L_MATH_OVERFLOW:
    // 发生了溢出计算，在这里可以调用 panic 或者向上冒泡错误
    !ok
    !res
    !a
    !b
    return 1
```

## `NUM_U64_CHECKED_SUB` / `NUM_U64_CHECKED_DIV`
除了加法与乘法外，也提供了减法防下溢出和除法防零异常的宏。

```sa
@import "sa_std/num.sa"

@main() -> i32:
L_ENTRY:
    a = add 0, 50
    b = add 0, 100
    
    // a - b，50 - 100 必然产生下溢，ok 为 0
    EXPAND NUM_U64_CHECKED_SUB ok, res, a, b
    br ok -> L_MATH_OK, L_MATH_OVERFLOW
    
L_MATH_OK:
    !ok
    !res
    !a
    !b
    return 0

L_MATH_OVERFLOW:
    // 下溢阻截
    !ok
    !res
    !a
    !b
    return 1
```

---

使用这些经过良好测试的标准库功能，可以保证程序始终运行在可被推导的确切安全边界内，使得底层 SA 开发具有比肩现代高级系统语言（Rust、Zig）的安全体验。