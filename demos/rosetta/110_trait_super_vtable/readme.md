# 110 - Trait Super Traits VTable

## 目标特性 (Target Feature)
展示 Rust 中的 Super Trait（如 `trait B: A`）的虚表是如何排布的。

## 降级逻辑预演 (Expected Lowering Logic)
1. **多重 VTable / 展平 VTable**：在 SA-ASM 层面，虚表本质上就是 `alloc` 出来或者定义在 `@const` 中的函数指针数组。
2. **向上转型 (Upcasting)**：当前端将 `&dyn B` 转换为 `&dyn A` 时，由于 SA 没有类型系统，前端在发射指令时，仅需将 VTable 指针偏移（如果虚表是被级联存放的），或者直接传递完全相同的胖指针（如果子类虚表兼容父类排布）。
3. **严格调用约束**：调用时依靠 `#def` 计算偏移量取出对应的 `@func`，然后执行 `call_indirect`。