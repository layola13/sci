# 197 - PGO Profile Guided Opt

## 目标特性 (Target Feature)
展示热点路径和冷路径在源码层面如何形成明显的执行频率差。

## 当前示例 (Current Demo Shape)
1. 当前循环固定执行三次 hot path，再执行一次 cold path，总计结果是 `10`。
2. SA 版本把累加器和循环索引显式拆成槽位，说明 PGO 讨论的前提仍然是普通控制流图。
3. 这个 demo 关注“热点形状可见”，不是在 SA 里新增 profile 专用语法。

