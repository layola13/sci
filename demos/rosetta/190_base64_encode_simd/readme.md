# 190 - Base64 Encode SIMD

## 目标特性 (Target Feature)
展示 3-byte block 如何通过手工索引 Base64 字母表得到 4-byte 输出。

## 当前示例 (Current Demo Shape)
1. 当前输入固定为 `Man`，输出必须是 `TWFu`。
2. SA 版本没有调用现成库，而是显式计算四个 6-bit 分组，再到 Base64 字母表里查表取字符。
3. 这个目录关注编码表驱动和分组算术；“SIMD” 目前体现在题目方向，不在现有实现里伪造额外指令。

