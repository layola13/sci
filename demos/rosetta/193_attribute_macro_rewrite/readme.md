# 193 - Attribute Macro Rewrite

## 目标特性 (Target Feature)
展示 attribute 风格前端改写如何收束成普通 wrapper 调用。

## 当前示例 (Current Demo Shape)
1. 当前 SA 结构体 `Value` 同时保留 `raw` 和 `shadow` 两个字段，wrapper 会读取两者并回写 `raw`。
2. 这个版本的改写结果是“值保持不变”：`raw == 2`、`shadow == 7`、返回值也是 `2`。
3. 目录重点是“rewrite 发生在发射前”，不是运行时再发明一套 attribute 解释器。

