# 200 - SA-ASM Quine

## 目标特性 (Target Feature)
展示“程序把自己的源码文本作为数据再次输出”的自举边界。

## 当前示例 (Current Demo Shape)
1. 当前 `main.sa` 直接把一段 SA 源码文本保存在 `SOURCE` 常量里，再把它原样打印出来。
2. 这意味着当前 quine 讨论的是 SA 文本级自描述，而不是 Rust 前端源码的逐字回显。
3. 目录重点是“源码作为常量进入程序之后，如何再次被输出”。
