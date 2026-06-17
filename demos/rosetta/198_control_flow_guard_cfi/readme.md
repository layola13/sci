# 198 - Control Flow Guard (CFI)

## 目标特性 (Target Feature)
展示间接调用前的目标校验如何被外显成普通比较与分支。

## 当前示例 (Current Demo Shape)
1. 函数指针不是裸传递，而是放在带 `vtable` 槽位的结构里，再从中取出 `call_slot`。
2. SA 版本会先把 `call_slot` 和 `TARGET_VT` 里的预期入口做比较，匹配后才 `call_indirect`。
3. 成功路径调用 `guarded_target(1)` 得到 `2`，说明这个目录的核心是“调用前校验”。

