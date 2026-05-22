# SA-ASM 原生单元测试框架 (Native Unit Test Framework)

SA-ASM 拥有内置的、零运行时开销的单元测试框架。它允许你在汇编级别直接编写断言和隔离测试，无需借助外部 bash 脚本或繁重的宿主环境。

## 1. 如何编写与运行测试

### 1.1 编写 `@test` 用例
在 `.sa` 源码中，你可以使用 `@test` 关键字直接声明一个无参无返回值的测试块。

```sa
// math_test.sa

@test "addition handles negative numbers" {
    // 1. 执行被测逻辑
    a = add -5, 10
    
    // 2. 调用断言宏
    EXPAND ASSERT_EQ a, 5
    
    return
}

@test "memory correctly freed prevents leaks" {
    p = alloc 16
    ! p
    
    // 如果忘记写 ! p，测试框架会自动探测到 MemoryLeak 并标记测试失败
    return
}
```

### 1.2 运行测试 (`sa test`)
使用 `sa test` 命令行可以直接发现并执行目录下所有的 `@test`：

```bash
# 运行当前目录下的所有测试
sa test ./

# 模糊匹配测试名 (只运行带有 "addition" 的测试)
sa test ./ --filter "addition"
```

**测试报告输出示例：**
```text
[PASS] memory correctly freed prevents leaks (2ms)
[FAIL] addition handles negative numbers (1ms)
       => AssertionFailed at math_test.sa:6: expected 5, got -5
       
Test Summary: 1 passed, 1 failed, 0 skipped.
```

## 2. 断言宏的底层原理 (ASSERT_*)

在 `sa_std/core/sa_core.sa` 中，断言是通过宏展开来实现的，它们在底层会被展开为极其高效的分支语句。

```sa
[MACRO] ASSERT_EQ %actual, %expected
    %cond = eq %actual, %expected
    br %cond -> %L_ok, %L_fail
%L_fail:
    // 触发 103 Panic 陷阱，向外抛出 AssertionFailed 报告
    panic(103)
%L_ok:
[END_MACRO]
```
当你在代码中使用 `EXPAND ASSERT_EQ a, 5` 时，编译器 (Flattener) 会自动注入当前行的 `#loc` 信息，使得 `panic` 能够精准抓取失败的文件和行号。

## 3. 测试隔离架构 (Process Isolation)

由于 SA 的设计哲学是 **Fail-Fast (Panic 即终止)**，如果一个测试断言失败或触发了非法内存访问，整个解释器通常应该崩溃。

为了让测试“失败而不中断执行列表”，`sa test` 实现了一种多进程隔离机制：
1. 主进程（Test Runner）解析出所有的 `@test` 符号，形成一张内存映射表 (`TestRegistry`)。
2. 针对每一个测试，主进程通过 `fork` / `spawn` 拉起一个孤立的子进程。
3. 主进程监听子进程的 Exit Code：
   - 如果 Exit Code == `0`，标记为 **PASS**。
   - 如果 Exit Code == `103` (AssertionFailed)，标记为 **FAIL** 并提取 stderr 日志。
   - 如果触发了 `UseAfterMove` / `MemoryLeak` 等 Trap，记录为 **ERROR**。

这种隔离机制确保了即便某个测试严重违规导致内存段错误，其余的测试依旧会正常排队执行，为你提供最完整的安全体检报告。