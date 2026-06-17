# 187 - OpenGL Context Swap

## 目标特性 (Target Feature)
展示图形上下文的阶段状态如何通过 host 风格调用推进。

## 当前示例 (Current Demo Shape)
1. `Ctx` 结构把 `ready`、`swapped`、`phase` 和 `swap_count` 全部摊平，当前状态机是 `0 -> 1 -> 2`。
2. 成功路径要求先 `gl_make_current`，再 `gl_swap_buffers`，并验证 `swap_count == 1`。
3. 这个目录强调的是“上下文状态转移被显式编码”，不是 OpenGL API 面覆盖率。

