# SA-ASM 原生单元测试框架设计 (Native Unit Test Framework)

## 1. 痛点与现状

当前 SA (Symbolic Affine) 项目在 v0.1 至 v0.5 的路线图中，主要依赖外部的测试手段：
- 依靠 Bash 脚本 `test_all_300.sh` 批量执行示例代码并校验 Exit Code 和 Stdout。
- 依靠 Zig 测试套件（`tests/cli_smoke.zig` 等）利用子进程拉起 `saasm` 进行回归测试。
- 虽然 `sa_std/core/sa_core.saasm` 中存在基础的 `ASSERT_EQ` / `ASSERT_TRUE` 断言宏，但它们在失败时会立即触发 `panic(PANIC_ASSERT)` 导致进程结束（Fail-Fast），并且没有提供隔离机制。

为了提供现代语言标准（类似 `cargo test` 或 `zig test`）的开发体验，SA 必须拥有原生的单元测试框架，实现用例隔离、详细失败报告及测试集自动收集。

## 2. 核心设计原则

1. **零运行时侵入**：测试元数据仅存在于编译期，不污染 Release 产物。
2. **显示优于隐式**：不魔改控制流。用例与环境设置保持纯粹的线性和清晰度。
3. **基于现有原语**：尽可能复用 Flattener、Referee 和现有的 `panic_msg` 机制，降低实现复杂度。
4. **多进程隔离 (Process Isolation)**：由于 SA 秉持“panic 即终止”原则，单个测试用例失败不应中断其他测试。测试引擎将通过 Spawn 机制执行测试进程来捕获 Trap / Exit Code 103。

## 3. 架构设计与阶段规划

原生单元测试框架分为四个主要阶段（对应 Tasks 中的 Version 0.7）。

### 3.1. 阶段一：编译器前端支持与元数据收集

**目标**：允许开发者在 `.saasm` 源码中标记测试用例，并在 Flattener 中提取这些符号。

- **语法扩展**：
  引入顶层标记 `@test "description"()`（或者利用特定的宏）。
  ```saasm
  @test "hashmap handles collisions correctly"():
  L_ENTRY:
      // 测试逻辑
      return
  ```
- **签名校验**：所有 `@test` 函数必须是无参无返回值的（`() -> void`）。
- **元数据收集**：`src/flattener.zig` 在扫描时，将遇到 `@test` 声明的函数登记到全局内存表 `TestRegistry`，记录其名称、原始源文件、行号和生成的内部指令地址。

### 3.2. 阶段二：CLI 原生指令与测试运行器 (Test Runner)

**目标**：提供 `saasm test` 命令，自动编排、执行测试并生成报告。

- **新增命令**：在 `src/cli.zig` 中新增 `saasm test` 命令，支持指定文件或目录，并允许通过 `--filter` 参数模糊匹配测试名称。
- **动态入口生成**：
  如果用户执行了 `saasm test`，编译器内部在展开完毕后，不使用常规的 `@main`。取而代之的是生成一个动态的虚拟 `@main` 驱动器，该驱动器负责查表调用 `TestRegistry` 中的函数。
- **进程隔离执行 (Process-based Isolation)**：
  - 测试 Runner（通常是主 `saasm` 进程自身作为协调者）会以子进程方式运行测试驱动程序。
  - 对于给定的测试列表，主进程逐一（或并发）通过传递环境变量或特殊参数给子进程，使其仅执行某个对应的测试用例。
  - 主进程监听子进程退出码。退出码为 `0` 记作 Pass；退出码为 `103` (AssertionFailed) 记作 Fail；其他非零退出码或 Trap JSON 记录为 Crash/Error。
- **报告输出**：
  控制台输出类似 Rust 的绿色/红色格式：
  ```
  [PASS] hashmap handles collisions correctly
  [FAIL] string format handles negative numbers
         AssertionFailed at fs.saasm:42: expected -10, got 10
  ```

### 3.3. 阶段三：标准库断言与诊断强化

**目标**：使得 `ASSERT_*` 宏的失败能够携带足够上下文（文件、行号、预期值与实际值）。

- **升级宏定义**：
  修改 `sa_std/core/sa_core.saasm`：
  ```saasm
  [MACRO] ASSERT_EQ %cond, %actual, %expected, %ok_label, %fail_label
      %cond = eq %actual, %expected
      br %cond -> %ok_label, %fail_label
  %fail_label:
      // 利用编译器自带的 #loc 获取当前文件与行号字符串
      // 调用 panic_msg(PANIC_ASSERT, "assertion failed: expected X, got Y", len)
      panic_msg(...)
  %ok_label:
  [END_MACRO]
  ```
- 依赖于 Flattener 阶段将源文件信息作为静态字符串池常量注入，使得 `panic_msg` 能直接引用。

### 3.4. 阶段四：测试替身 (Mocks) 与生态集成

**目标**：为涉及底层 I/O、网络的逻辑提供可测试性。

- **内存 Mock 原语**：在 `sa_std` 建立独立的 `test/mock.saasm`。
  由于 SA 的接口由契约（Contract 和 `@extern`）保证，可以通过注入不同版本的 `.saasm-iface` 实现，来实现脱离物理宿主机的虚拟文件系统和网络收发。
- **持续集成 (CI)**：将原先 `test_all_300.sh` 的验证步骤逐步整合至 `saasm test` 管线，利用零信任包管理体系，直接测试从本地到云端的全量代码。

## 4. 预期产出

1. **`saasm test` 命令**：全功能、带色彩高亮与隔离的测试执行器。
2. **`@test` 语法**：一种 SA-ASM 的内建用例声明标准。
3. **更强的诊断信息**：当断言失败时不再是冰冷的 exit code 103，而是包含上下文字符串的精准定位。