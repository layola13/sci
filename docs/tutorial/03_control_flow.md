# 03. 控制流：分支与循环

高性能程序离不开逻辑判断。在 SA 中，控制流通过**标签 (Label)** 和 **跳转 (Branch)** 实现。

## 标签 (Labels)
标签是代码中的锚点，以冒号结尾：

```saasm
L_MY_LABEL:
    x = 1
```

## 无条件跳转
使用 `jump` 指令直接跳到某个标签：

```saasm
    jump L_DEST
```

## 条件跳转 (`br`)
这是最常用的分支指令。它根据一个布尔值决定走向：

```saasm
    is_ok = eq x, 10
    br is_ok -> L_TRUE, L_FALSE
```

### 示例：If-Else 结构
```saasm
@main() -> i32:
L_ENTRY:
    x = 15
    limit = 10
    is_greater = gt x, limit
    br is_greater -> L_GREATER, L_LESS

L_GREATER:
    !is_greater
    !x
    !limit
    return 1

L_LESS:
    !is_greater
    !x
    !limit
    return 0
```

## 循环的实现
SA 没有 `for` 或 `while` 关键字，循环通过**回跳**实现：

```saasm
@main() -> i32:
L_ENTRY:
    i = 0
    max = 10
    jump L_LOOP_CHECK

L_LOOP_CHECK:
    cond = lt i, max
    br cond -> L_LOOP_BODY, L_DONE

L_LOOP_BODY:
    !cond
    i = add i, 1   // 递增
    jump L_LOOP_CHECK

L_DONE:
    !cond
    !i
    !max
    return 0
```

## 关键规则
- **Referee 验证**：在跳转之前，SA 的验证器会检查当前生命周期内的所有寄存器。如果一个寄存器在 `L_TRUE` 分支被销毁，但在 `L_FALSE` 分支没被销毁，编译器将拒绝编译。这保证了无论代码走哪条路径，内存状态都是确定的。

## 练习
1. 编写一个程序，计算 1 到 100 的累加和。
2. 尝试编写一个死循环，并理解为什么 SA 允许无限循环但不允许悬空指针。
