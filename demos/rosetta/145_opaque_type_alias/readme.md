# 145 - Opaque Type Alias

## 目标特性 (Target Feature)
展示 type T = impl Trait 在单态化后退化为具体布局的过程。

## 降级逻辑预演 (Expected Lowering Logic)
1. **布局先行**：DST、ZST、phantom data、opaque type alias 和 custom DST pointer 都是前端概念，SA 侧只接受已经展开好的 `#def` 字段偏移、胖指针和固定大小块。
2. **发散与占位**：`!` 类型、never fallback 和 phantom 标记不产生实际载荷；它们只影响前端的分支和单态化结果，不能变成运行时“神奇值”。
3. **对齐承诺**：`repr(transparent)`、`repr(packed)` 和 `repr(C)` 都是在告诉前端“字段如何落盘”；一旦布局定了，`load` / `store` / `ptr_add` 就必须严格按偏移和对齐发射。
