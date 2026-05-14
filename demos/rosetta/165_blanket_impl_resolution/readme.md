# 165 - Blanket Impl Resolution

## 目标特性 (Target Feature)
展示覆盖实现在 AST 阶段已经被静态解析为具体函数调用。

## 降级逻辑预演 (Expected Lowering Logic)
1. **先单态化，再落地**：GAT、const generics、TAIT、blanket impl、specialization、negative impl 和 marker trait 都应在前端解决，SA 里只留下具体实例化后的函数和布局。
2. **对象安全与上转型**：trait object、object safety 和 upcasting 最终还是函数指针表和 `call_indirect`；任何不能被明确排成槽位的接口，就不该伪装成运行时能力。
3. **约束即合同**：`Send` / `Sync` / marker trait 这类约束更多是编译期合同，决定代码能否发射、走哪条实现路径，而不是 SA 运行时再去猜类型。
