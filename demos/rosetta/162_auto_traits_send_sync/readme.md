# 162 - Auto Traits (Send/Sync)

## 目标特性 (Target Feature)
展示 Send/Sync 只是前端的类型标记，对降级后的 SA-ASM 透明。

## 降级逻辑预演 (Expected Lowering Logic)
1. **纯粹的前端责任**：SA-ASM 是一个无 AST、无全局类型推导的物理执行验证机。像 Auto Traits (Send/Sync) 这样的高级语义或外部抽象，100% 由前端（如 Rustc, TypeScript Compiler 或大语言模型）在降级期间展开。
2. **物理映射**：无论是复杂的并发原语、不安全的 FFI 边界、还是宏展平，进入 SA-ASM 后全部化为裸内存的 `alloc`、O(1) 验证的所有权锁（`Active`, `Locked_*`, `BorrowView` 等）、扁平的标签跳转（`jmp` / `br`）以及气闸舱隔离的系统调用。
3. **架构纪律**：如果逻辑中存在内存泄漏或悬挂指针，SA-ASM 编译器在验证期通过 O(1) 线性扫描便能无情截断，拒绝发射恶意或残缺的 LLVM IR。
