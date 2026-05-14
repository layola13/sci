# 108 - Atomic Spin Lock

## 目标特性 (Target Feature)
展示如何利用 SA-ASM 新增的原子指令实现一个自旋锁（Spin Lock）。

## 降级逻辑预演 (Expected Lowering Logic)
1. **CAS 循环**：使用 `cmpxchg` 指令。如果期望值为 0，则尝试替换为 1。
2. **Ordering**：前端必须明确指定 `acquire` 和 `release` 内存序。SA-ASM 在验证器层面白名单放行这些内存序。
3. **自旋跳跃**：通过 `jmp` 实现 `while` 轮询。为了避免 `has_unbounded_loop` 告警或 Gas 超限，这类自旋往往需要标记特殊的循环上限或者被系统明确豁免。