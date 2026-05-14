# 194 - CFG Conditional Compilation

## 目标特性 (Target Feature)
展示前端根据平台切除代码。

## 降级逻辑预演 (Expected Lowering Logic)
1. **前端先展开**：macro rules、proc macro、attribute rewrite 和 cfg selection 都发生在 SA 之前；SA 看到的应该是已经材料化的代码，而不是宏语言本身。
2. **构建链外移**：build script、LTO、PGO、CFI 和 ASAN 属于宿主编译链或运行时防护层，文档应描述它们如何影响最终 SA 形态，而不是伪造新的 SA 语法。
3. **自举但不自嗨**：quine 只能在“前端已把源码展开成自描述 SA 程序”之后成立；若展开后仍有泄漏、悬挂指针或未收敛的宏递归，就必须在发射前截断。
