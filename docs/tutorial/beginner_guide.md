# SA (Symbolic Affine) 语言入门全阶指南

欢迎来到 SA (Linear Ownership & Zero-Trust Assembly) 的世界！

SA 是一门**面向机器验证与 LLM 代码生成的线性所有权汇编语言**。它看起来像汇编，但通过其独特的“5 符号所有权系统”，在编译期就能实现像 Rust 一样的内存安全（没有 Use-After-Free，没有 Double-Free，没有内存泄漏）。它**没有垃圾回收 (GC)**，也不依赖任何庞大的运行时，可以直接编译为极速的 Native 机器码（`.exe`）或 WebAssembly（`.wasm`）。

本教程将带你从零开始，深入理解 SA 的设计哲学与实战语法。

---

## 第一章：安装与验证

SA 工具链的设计极其轻量，默认安装在你的用户目录下，不会污染全局系统环境。

### 1.1 一键安装
在 Linux 或 macOS 终端中运行：
```bash
sh tools/install.sh
```

**自定义安装**：如果你想看它到底会做什么而不真实修改文件，可以加 `--dry-run`；如果你想安装到全局目录，可以使用 `--dir`：
```bash
# 测试安装流程（不写文件）
sh tools/install.sh --dry-run

# 全局安装 (需要管理员权限)
sudo sh tools/install.sh --dir /opt/sa --no-shell
```

### 1.2 验证环境
安装完成后，重新加载终端配置：
```bash
source ~/.bashrc
```
然后测试命令行工具：
```bash
sa version
# 输出类似于: sa 0.0.0

sa --help
# 输出完整的命令列表
```

---

## 第二章：第一个程序 (Hello World)

SA 没有复杂的工程结构，一切从单个 `.sa` 文件开始。新建一个 `hello.sa`：

```sa
@func main() -> i32 {
    // 1. 分配 12 字节内存
    msg = alloc 12
    
    // 2. 写入 "Hello World\n" (分 3 个 4 字节的 i32 写入)
    store msg+0, 0x6c6c6548 as i32  # "Hell"
    store msg+4, 0x6f57 206f as i32 # "o Wo"
    store msg+8, 0x0a64 6c72 as i32 # "rld\n"
    
    // 3. 调用系统原语打印
    _ = call @sys_print(msg, 12)
    
    // 4. 显式释放内存！(如果不写这句，编译器会报错 MemoryLeak)
    ! msg
    
    return 0
}
```

### 2.1 运行与编译
SA CLI 提供了四种极其强大的执行模式：

1. **直接解释执行 (Interpreter)**：开发期秒级验证
   ```bash
   sa run hello.sa
   ```
2. **构建本地可执行文件 (Native)**：调用底层的 LLVM/zig cc 生成极速二进制
   ```bash
   sa build-exe hello.sa -o hello
   ./hello
   ```
3. **构建 WebAssembly (WASM)**：无缝跨平台
   ```bash
   sa build-wasm hello.sa -o hello.wasm
   ```
4. **构建目标文件 (Object)**：用于和 C/C++/Rust 混编
   ```bash
   sa build-obj hello.sa -o hello.o
   ```

---

## 第三章：核心哲学 —— 5 符号线性所有权

SA 为什么能做到极速的安全检查？因为它将繁杂的所有权规则收敛到了**5 个标点符号**上。编译器（Referee）通过单遍扫描这些符号就能证明内存安全。

### `1. =` (绑定 / 分配)
当一个变量被分配或初始化时，它处于 `Active` 状态。
```sa
p = alloc 8
```

### `2. &` (借用 Borrow)
当你需要把变量传给别的函数读取或修改，但**不想交出所有权**时，使用借用。编译器会自动推导它是共享读 (`Locked_Read`) 还是独占写 (`Locked_Mut`)。
```sa
ref = &p
```

### `3. !` (释放 Release)
这是 SA 最严格的规定：**所有 Active 的变量或借用，在离开作用域前必须显式用 `!` 释放**。SA 编译器不会像 Rust 那样悄悄帮你插入 `drop`。
```sa
! ref   // 结束借用，p 重新可用
! p     // 物理释放堆内存，p 被销毁
```

### `4. ^` (移动 Consume)
把变量的所有权“移交”给别的函数。一旦移交，当前函数就不能再碰它了。
```sa
call @take_ownership(^p)
// 如果在这里再写一行 `! p`，编译器会直接报错 UseAfterMove (移动后使用)！
```

### `5. *` (逃逸 Raw Pointer)
用于脱离安全检查，得到一个裸指针（`Untracked`）。**注意：它只能用在特殊的 `@ffi_wrapper` 函数里**。

---

## 第四章：数据结构与内存布局

**Q: SA 为什么没有 `struct` 或 `class` 关键字？**
**A**: SA 是汇编语言！在底层，`struct` 只是“给一块连续内存的不同偏移量起个名字”。

在 SA 中，我们使用宏定义 `#def` 来模拟结构体：

```sa
#def Point_x = +0
#def Point_y = +4
#def Point_SIZE = 8

@func create_point() -> ^ptr {
    // 按照大小分配内存
    p = alloc Point_SIZE
    
    // 利用 #def 的偏移量进行读写
    store p+Point_x, 100 as i32
    store p+Point_y, 200 as i32
    
    // 把所有权移交给调用者
    return ^p
}
```
*提示：将来可以使用 `sa layout` 命令行工具来自动帮你生成这些 `#def` 偏移量。*

---

## 第五章：展平的控制流 (Flat Control Flow)

**Q: SA 为什么没有 `if/else`、`while`、`for` 和 `{}` 大括号？**
**A**: 大括号很容易导致嵌套过深，对 LLM 代码生成极其不友好。SA 将所有控制流“展平”，你只能使用 `jmp` (无条件跳转) 和 `br` (条件跳转)。

### 5.1 替代 `if/else`
```sa
@func abs(x: i32) -> i32 {
    cond = sgt x, 0
    br cond -> L_POS, L_NEG
    
L_POS:
    return x
    
L_NEG:
    ans = sub 0, x
    return ans
}
```

### 5.2 替代 `while` 循环
循环只是回边（向回跳转）的 `jmp` 组合：
```sa
@func count_to_ten() {
    i = add 0, 0
L_LOOP:
    cond = slt i, 10
    br cond -> L_BODY, L_END
    
L_BODY:
    // 循环体...
    i = add i, 1
    jmp L_LOOP
    
L_END:
    return
}
```

---

## 第六章：优雅的错误处理

SA 摒弃了沉重的 `try-catch` 异常展开机制，使用显式的错误返回值，并通过极其优雅的 `?` 语法糖来处理。

### 6.1 声明可能失败的函数 (Fallible ABI)
在函数返回类型后加 `!`，表示这是一个可能失败的函数：
```sa
@func read_file(*path: ptr) -> ptr! {
    // 失败时直接 panic，或返回约定的错误元组
    // ...
}
```

### 6.2 早期返回 (`?` 运算符)
调用失败时，`?` 会自动展开为一段 `if err return err` 的跳转逻辑。
```sa
@func process_file() -> i32! {
    res = call @read_file(...)
    
    // 如果 res 是错误，这里会直接让当前函数结束并返回错误
    // 如果 res 成功，file_ptr 就会拿到真实的值
    file_ptr = ? res  
    
    // 继续正常处理
    // ...
    return 0
}
```
**安全警报**：如果你的函数在调用 `?` 之前分配了内存（处于 Active 状态），你必须在 `?` 之前处理好它，否则 `?` 发生早退时，编译器会抛出 `EarlyReturnLeak`！

---

## 第七章：与 C/Rust 的安全边界 (FFI 气闸舱)

SA 将所有不安全的内存操作严格隔离在气闸舱（Airlock）内。如果你想调用 C 语言的函数，或者操作外部的裸指针，你必须：

1. 使用 `@extern` 声明外部函数。
2. 将危险逻辑写在 `@ffi_wrapper` 修饰的包装函数中。

```sa
// 声明外部的 C 函数
@extern puts(*str: ptr) -> i32

// 气闸舱函数：只有在这里，你才能使用 * 剥离所有权
@ffi_wrapper safe_puts(&msg: ptr) {
    // 剥离安全类型，得到裸指针 (Untracked)
    raw = *msg
    
    // 调用 C 函数
    _ = call puts(raw)
    return
}
```
**注意**：在普通的 `@func` 里面写 `*msg` 会直接触发 `IllegalUnsafeContext` 编译错误。

---

## 第八章：常见陷阱速查 (Traps)

当你编写 SA 代码时，你经常会遇到编译器的善意阻挡，请牢记以下常见报错：

1. **`MemoryLeak`**：函数 `return` 之前，你忘了写 `! var` 释放内存或借用。
2. **`UseAfterMove`**：你把变量 `^var` 传给了别人，下一行又试图读取它。
3. **`DoubleMutableBorrow`**：你对同一个变量发起了两次独占借用。
4. **`PhiStateConflict`**：当你 `jmp` 汇聚到一个标签时，不同分支对同一个变量的所有权状态不一致（比如一个分支释放了它，另一个分支没释放）。

---

## 第九章：插件生态系统 (HTTP 与 网络)

SA 不仅仅是一个语言核心，它还可以通过**外部插件工程**扩展出额外能力。
所有的网络能力、数据库交互等，都不是写死在编译器主线程里的，而是通过独立的 `.so` / `.dll` 动态库在运行时按需加载。

### 9.1 HTTP 客户端插件
如果你需要在 SA 中发起网络请求，可以调用 `sa_http_client` 插件：

```sa
// 1. 初始化 HTTP Client
res = call @sa_http_client_new(1, &client)
_ = ? res

// 2. 创建 GET 请求
url = alloc 20
// ... 往 url 里写地址 ...
res = call @sa_http_client_req_new(&client, 1, &url, 20, &req)

// 3. 发送请求
res = call @sa_http_client_req_send(&req, &empty_body, 0, &resp)
```
*HTTP 插件支持零拷贝透传和 SSE 流式读取，这对于对接大模型 (如 OpenAI API) 非常高效！*

### 9.2 插件的安全性
在 SA 的零信任设计下，调用网络插件受到极严格的管控：
- **热重载 (Hot Reload)**：插件可以在不停止主进程的情况下热更新版本。
- **能力限制**：你必须在包管理的 `grants` 权限表中显式声明需要 `net_tx` (网络发送) 权限，甚至限制具体的域名。如果未经授权，运行时会直接阻断调用。

祝你在 SA 的零信任安全世界中编码愉快！如需更多实战案例，请查阅源码目录下的 `demos/rosetta/` 文件夹。
