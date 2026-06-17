# 191 - Macro Rules AST Emission

## 目标特性 (Target Feature)
展示前端宏展开后，算术节点如何以具体 SSA/CFG 形式落地。

## 当前示例 (Current Demo Shape)
1. SA 版本用 `CAPTURE`、`SUM3`、`BUILD` 三层宏，把 `1 + 2 + 3` 的结果再镜像一份，总计得到 `12`。
2. 这个目录不是在讲运行时宏系统，而是在讲“展开之后剩下什么代码形状”。
3. 成功路径输出 `6` 的镜像求和结果 `12`，对应的是“宏先展开，再发射 SA”。

