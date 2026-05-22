# 04. 线性所有权系统

这是 SA 语言最核心的篇章。理解了所有权，你就理解了 SA。

## 什么是线性所有权？
在线性逻辑中，资源**必须且只能被使用一次**。
在 SA 中，这意味着每一个非平凡类型（如指针、句柄）在任何时刻都只有一个明确的所有者。

## 所有权的三个状态
1.  **持有 (Held)**：寄存器拥有该资源。
2.  **移动 (Moved)**：资源被传递给函数或另一个寄存器，原寄存器失效。
3.  **销毁 (Destroyed)**：资源被释放。

## 移动语义示例
当你把一个寄存器作为参数传递给函数时，所有权就发生了转移：

```sa
@process_data(data: ptr) -> void:
L_ENTRY:
    // 此处 process_data 拥有了 data
    !data
    return

@main() -> i32:
L_ENTRY:
    p = alloc 64
    call @process_data(p)
    // 此时 p 已失效！
    // 再次使用 p 会触发编译器错误：Use-after-move
    return 0
```

## 借用 (Borrowing) 与 指针
SA 支持通过 `&` 符号进行借用。借用不会转移所有权，但会受到 Referee 的严格生命周期检查。

```sa
    p = alloc 64
    ptr_to_p = &p   // 借用 p 的地址
    // 只要 ptr_to_p 还在使用，p 就不能被销毁或移动
    !ptr_to_p
    !p              // 现在可以安全销毁 p 了
```

## 为什么这么做？
- **零成本安全**：不需要运行时引用计数，不需要 GC 扫描。
- **并发安全**：因为一个资源只有一个所有者，所以不存在 Data Race。
- **显式管理**：迫使开发者思考内存的生命周期，从而写出最高效的代码。

## 高级模式：所有权流转 (Ownership Patterns)

### 1. 往返模式 (Round-trip)
如果你需要函数修改数据并还给你：
```sa
@modify(p: ptr) -> ptr:
    store p+0, 1 as i32
    return p // 还回所有权

@main() -> i32:
    p = alloc 4
    p = call @modify(p) // 重新接管所有权
    !p
    return 0
```

### 2. 借用检查器的限制
SA 的 Referee 不允许"交叉借用"。即如果你借用了 `A` 给 `B`，在 `B` 销毁前，你不能再次借用 `A` 给 `C`。这确保了引用的单一性。

## 常见陷阱：僵尸寄存器 (Zombie Registers)
如果你在分支中漏掉了销毁指令：
```sa
    br cond -> L_TRUE, L_FALSE
L_TRUE:
    !p
    return 1
L_FALSE:
    // 漏掉了 !p！
    return 0 // Referee 报错：L_FALSE 路径泄露了 p
```

## 练习
1. 编写一个函数，接收一个指针，修改其内容，并将其**返回**给调用者（还回所有权）。
2. 尝试故意制造一个 Use-after-move 错误，并阅读编译器的反馈。
