基于对 tasks.md、docs/std_rfc.md 以及当前 sa_std/ 源码目录的深度挖掘，目前 v0.5
  阶段的基础集合和时间模块虽然已经建立，但距离一个完备的、能让 LLM 高效产出复杂业务逻辑的“标准库”还有不少空白。

  以下是为你整理的 SA-ASM 标准库 (sa_std) 补完计划完整 TODO 列表，按架构重要性和 LLM 生成的痛点优先级排序：

  ---

  🔴 优先级 1：核心并发与同步 (Priority: High)
  LLM 极难直接写对无锁算法或正确的自旋锁，标准库必须提供开箱即用的宏。

   - [x] sa_std/sync/mutex.saasm (互斥锁)
     - 实现基于 atomic_rmw_xchg 和 sa_time_sleep_ns (用于 yield) 的自旋锁 / 互斥锁。
     - 提供 MUTEX_NEW, MUTEX_LOCK, MUTEX_UNLOCK 宏。
   - [x] sa_std/sync/once.saasm (单次初始化)
     - 实现 OnceCell 语义，用于全局单例的懒加载初始化，避免多线程初始化竞态。
     - 提供 ONCE_NEW, ONCE_IS_READY, ONCE_TRY_CLAIM, ONCE_WAIT_READY, ONCE_PUBLISH, ONCE_GET, ONCE_GET_OR_INIT 宏。
   - [x] sa_std/sync/mpsc.saasm (通道)
     - 基于内联环形缓冲区 + 原子头尾指针 + ready 标志实现多生产者单消费者（MPSC）队列。
     - 提供 MPSC_NEW, MPSC_FREE, MPSC_TRY_SEND, MPSC_SEND, MPSC_TRY_RECV, MPSC_RECV 宏。

  🟡 优先级 2：高级集合与数据结构 (Priority: Medium-High)
  目前只有 Vec 和 HashMap，缺乏特定场景下的高性能容器。

   - [ ] sa_std/collections/hashset.saasm (哈希集合)
     - 基于现有的 HashMap 封装，值类型设为 void (0 字节)。提供 SET_INSERT, SET_CONTAINS, SET_REMOVE 宏。
   - [ ] sa_std/collections/vec_deque.saasm (双端队列)
     - 基于环形数组实现，支持 O(1) 的头尾插入删除。这对实现任务队列、BFS 搜索至关重要。
   - [ ] sa_std/collections/binary_heap.saasm (优先队列)
     - 基于 Vec 实现最大/最小堆，提供 HEAP_PUSH, HEAP_POP 宏。用于定时器调度、A* 寻路等算法。
   - [ ] sa_std/collections/btree_map.saasm (有序映射)
     - 实现基础的 B 树或红黑树。虽然 LLM 很少主动写 B 树，但在需要范围查询（Range Query）时是不可替代的。

  🟡 优先级 3：高级 I/O 与缓冲区管理 (Priority: Medium)
  目前的 fs 和 net 是裸系统调用，频繁调用会导致极高的上下文切换开销。

   - [ ] sa_std/io/buf_reader.saasm (缓冲读)
     - 维护一个内部 alloc 的 buffer，批量执行 sa_fs_file_read，对外提供 BUF_READ_LINE, BUF_READ_EXACT 宏。
   - [ ] sa_std/io/buf_writer.saasm (缓冲写)
     - 聚合零碎的写操作，达到阈值或显式 FLUSH 时才调用系统写，极大提升文件和网络写入性能。
   - [ ] sa_std/path.saasm (路径操作)
     - 提供跨平台的路径拼接 (PATH_JOIN)、父目录获取 (PATH_DIRNAME)、扩展名提取等字符串操作。

  🟢 优先级 4：生态辅助与运行时增强 (Priority: Medium-Low)
  完善开发体验，对齐现代系统语言的标配能力。

   - [ ] sa_std/env.saasm (环境变量)
     - 通过 FFI 或系统原语，暴露 GET_ENV 宏，支持按名称查询环境变量（如读取 PATH 或配置）。
   - [ ] sa_std/math.saasm (数学库)
     - 暴露 C 标准库 libm 的 @extern 接口（sin, cos, sqrt, pow, abs 等），并提供宏包装，解决 SA-ASM ISA 中只有基础算术指令的问题。
   - [ ] sa_std/string_format.saasm (高级字符串构建)
     - 基于现有的 sa_fmt_buffer，提供类似 format! 的高级拼装宏 FORMAT_STR %out_ptr, %fmt_string, %arg1, %arg2。
   - [ ] 包装与发布 (sa_std/sa.pkg)
     - （对应 Tasks 37.6）完成标准库的打包配置，使其能通过 saasm pkg fetch 或构建系统作为独立依赖被第三方项目引入。

  ---

  💡 核心建议与切入点：

  你刚刚完成了 HashMap 和 Time 这两块硬骨头。接下来的破局点应该放在 同步原语 (sa_std/sync) 上。

  为什么？
  因为你之前提到过用 SA-ASM 重写 llama.cpp，或者构建类似 AutoBevy 的高性能框架。这些场景高度依赖多线程。如果没有 Mutex 和 Channel
  这种标准库级别的防呆封装，LLM 生成的并发代码 100% 会触发 Referee 的所有权 Trap，或者在运行时产生死锁。

  你可以从写一个基于 cmpxchg 的 SPIN_LOCK 宏开始，这将填补 SA-ASM 并发编程的最后一块关键拼图。

  ## 🔴 优先级 1.5：异步状态机宏模板 (Task 29: libsa_async)
*解决异步代码直接展平导致 40x 膨胀的问题，将样板代码压缩至 10x 左右，这是 v0.3 的核心交付物。*

  - [x] **`ASYNC_CTX_DEF`**
  - 自动生成状态机的结构体偏移量字典。
- [x] **`ASYNC_POLL_PROLOGUE`**
  - 生成轮询入口，根据状态 ID 使用 `jmp` 分发到对应的恢复路径 (`L_RESUME_%i`)。
- [x] **`ASYNC_AWAIT_POINT`**
  - 核心挂起宏。打包以下逻辑：保存上下文寄存器、返回 `PENDING`、定义下一次唤醒的 Label、从上下文中恢复寄存器并释放。
- [x] **`ASYNC_RETURN_PENDING` / `ASYNC_READY`**
  - 标准化状态机退出点。
- [x] **`ASYNC_AWAIT_POINT_FINAL`**
  - 最终 await 分支的对称收尾宏。
- [x] **`ASYNC_INVALID_STATE`**
  - 非法状态统一 `panic(102)`。


  > 是否有必要将async,await 用宏封装？现在直接展平很长代码                                                                           
▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
✦ 非常有必要，而且这正是路线图（v0.3）中明确规划的核心任务。

  在 docs/faq.md 和 tasks.md 中，这被称为 “Task 29: libsa_async 异步状态机宏模板 (R26)”。

  由于 SA-ASM 拒绝引入隐藏控制流的内建关键字（如 Rust 的 async/await），所有的异步逻辑必须由前端或开发者手动进行
  CPS（Continuation-Passing Style，连续传递风格）转换，也就是手动写一个基于结构体的状态机。

  如果直接展平，代码膨胀率会达到惊人的 40x。这对于人类阅读是灾难，对于 LLM 更是严重浪费 Token 上下文并极易产生逻辑断裂。

  为什么必须用宏封装？

   1. 状态机样板代码过重：
      每个 async 函数都需要定义一个状态枚举、一个保存局部变量的结构体环境（Context）、一个 poll
  分发函数。这些代码在每次挂起（Suspend）和恢复（Resume）时高度重复。
   2. 所有权转移极易出错：
      在 await 点挂起时，所有的 Active 寄存器必须被保存到 Context 结构体中并释放（!reg）；在唤醒时，又需要从结构体中 load
  出来重新绑定。只要漏掉一个寄存器，Referee 就会立刻报 MemoryLeak 或 UseAfterMove。用宏封装可以保证保存和恢复动作的对称性。
   3. 标准化 Poll 契约：
      异步运行时（Executor）需要一套统一的唤醒机制。宏可以确保每个异步函数返回的 Pending 或 Ready 状态标志是一致的。

  计划中的 libsa_async.saasm 会长什么样？

  根据你的 tasks.md，这套宏主要包含四个核心组件。以下是它们的作用演示：

  1. 定义异步上下文 (ASYNC_CTX_DEF)
  自动生成状态机的结构体偏移量。

   1 // 宏内部处理 #def 的拼装
   2 EXPAND ASYNC_CTX_DEF MyTask, "socket:ptr, buf:ptr, bytes_read:u64"

  2. 轮询入口与恢复 (ASYNC_POLL_PROLOGUE)
  根据状态机当前的状态，使用 jmp 直接跳转到上一次挂起的地方。

   1 @my_task_poll(ctx: &ptr) -> i32:
   2 L_ENTRY:
   3     // 自动取出 state_id，并生成多路分支跳转到对应的 L_RESUME_%i
   4     EXPAND ASYNC_POLL_PROLOGUE ctx, L_FINISH

  3. 挂起与等待 (ASYNC_AWAIT_POINT)
  这是最核心的宏，它将“保存状态、返回 Pending、定义恢复标签”三件事打包。

    1     // 发起异步读
    2     call @async_read(socket, buf)
    3     
    4     // 宏展开：
    5     // 1. state_id = 1, store ctx+State, 1
    6     // 2. store ctx+Socket, socket; store ctx+Buf, buf
    7     // 3. !socket, !buf
    8     // 4. return PENDING
    9     // 5. L_RESUME_1: (下一次 poll 进来的地方)
   10     // 6. socket = load ctx+Socket; buf = load ctx+Buf
   11     EXPAND ASYNC_AWAIT_POINT ctx, 1, "socket, buf"
   12     
   13     // 醒来后继续执行...

  4. 异步返回 (ASYNC_RETURN_PENDING / READY)
  标准化退出点。

   1 L_FINISH:
   2     EXPAND ASYNC_READY ctx, 0  // 返回成功

  总结

  引入 libsa_async.saasm 宏可以将异步代码的膨胀率从 40x 压缩到约 10x-13x。
  你现在的编译器核心（Flattener 的嵌套宏展开和深度栈能力）已经完全能够支撑这种复杂度的宏了。如果你目前正在处理带有 I/O
  阻塞或并发调度的 Demo（例如 135_async_streams），现在立刻着手实现这套异步宏，将是最能提升开发体验的一步。


为了让 LLM 能更高效地编写 SA-ASM，我们需要构建的是一个 “编译器 $\rightarrow$ LLM” 的闭环反馈系统。以下是比插件重要 100 倍的开发方向：

  #### 1. 结构化错误报告 (LLM-Readable Traps)

  目前 Referee 抛出的 Trap 可能是简单的 Trap: UseAfterMove。对于人类这足够了，但对于 LLM，它需要上下文。

  - 目标：将 Trap 升级为类似这样的 JSON 报告：

    {
      "trap": "UseAfterMove",
      "register": "ptr_01",
      "location": "file.saasm:42:10",
      "history": {
        "allocated": "line 10",
        "consumed": "line 35 (via ^ operator)",
        "attempted_access": "line 42"
      },
      "suggestion": "The register 'ptr_01' was moved at line 35. Please release it or avoid using it after that point."
    }

  #### 2. 自动化测试套件 (The "Oracle" Test-bed)

  LLM 需要一个快速验证其生成的代码是否正确的“裁判”。

  - 目标：构建一套自动化的 saasm run $\rightarrow$ check output $\rightarrow$ feedback 的 Pipeline。
  - 价值：让 LLM 在提交代码前，先在沙箱里跑 10 组测试用例，只有全部通过才输出最终结果。

  #### 3. 宏展开可视化 (Macro Expansion Trace)

  由于异步宏 (libsa_async) 会导致代码大幅膨胀，LLM 很难在脑中模拟展开后的所有权状态。

  - 目标：提供一个 saasm expand <file> 命令，将宏展开后的完整线性代码输出，并标注每个指令是由哪个宏生成的。
  - 价值：当 Referee 报错在展开后的代码中时，LLM 可以通过这个 Trace 快速定位到是哪个宏调用导致的所有权冲突。

  #### 4. 针对 LLM 的“标准库文档” (The LLM-Context-Guide)

  LLM 不需要精美的 HTML 文档，它需要的是一个高信息密度的 Markdown 索引。

  - 目标：为 sa_std 的每个宏提供：签名 $\rightarrow$ 所有权转移清单 (Inputs/Outputs) $\rightarrow$ 最小可运行示例。
  - 价值：直接作为 System Prompt 的一部分，让 LLM 瞬间掌握 Mutex 或 Channel 的正确用法。

  ### 结论

  放弃 VSCode 插件 $\rightarrow$ 转向构建 LLM 闭环。

  我们要做的不是一个“编辑器”，而是一个**“能够给 LLM 提供精确诊断信息的编译器”**。只要 saasm 的报错足够清晰、测试足够快、宏展开足够透明，LLM 就能在没有任何 IDE 的情况
  下，写出工业级的 SA-ASM 代码。

  为了将这个目标转化为具体的执行计划，我建议将接下来的开发重点量化为以下三个具体的技术突破点：

  目前的 Trap 是给人类看的“警告”，我们需要将其升级为给 LLM 看的“调试指令”。

  - 具体动作：修改 src/referee/verifier.zig，在触发 Trap 时，不再仅仅返回错误码，而是记录该寄存器的生命周期轨迹 (Life-cycle Trace)。
  - 预期效果：当 LLM 触发 UseAfterMove 时，编译器会告诉它：reg X 在第 10 行分配 $\rightarrow$ 在第 20 行被 ^ 转移 $\rightarrow$ 在第 30 行被非法访问。LLM 看到这个轨迹
    后，修复率将从 50% 提升到 90% 以上。

  ### 2. 构建 sa_std 的“所有权契约”索引

  LLM 写错标准库宏的原因通常是不知道宏内部偷偷做了什么（例如：某个宏是否在内部执行了 !reg）。

  - 具体动作：为 sa_std 中的每个核心宏编写一份 Ownership Manifest。
      - 输入状态 $\rightarrow$ 输出状态。
      - 例如 MUTEX_LOCK(%lock, %guard)：%lock (Active) $\rightarrow$ %lock (Locked_Read), %guard (Active)。
  - 预期效果：将这些契约直接喂给 LLM，使其在调用宏之前就已经在脑中完成了所有权预演，从而实现“一次性写对”。

  ### 3. 完善 libsa_async 的自动化验证链路

  异步代码是目前最容易产生 MemoryLeak 的地方，必须建立一套严格的验证闭环。

  - 具体动作：
      - 实现 saasm expand 功能，允许 LLM 查看宏展开后的线性指令流。
      - 编写一组针对异步状态机的“压力测试” Demo，覆盖所有可能的挂起/恢复路径。
  - 预期效果：确保异步宏模板在任何极端路径下都不会导致所有权泄露，为构建高性能异步框架提供绝对可靠的底层。
