# 195 - Build Script CodeGen

## 目标特性 (Target Feature)
展示 build script 生成物被主程序消费之后，最终目标代码里实际保留下来的只是物化常量。

## 当前示例 (Current Demo Shape)
1. Rust 侧用 `include!(concat!(env!("OUT_DIR"), "/generated.rs"))` 表示“构建期注入的符号”。
2. 当前 SA 产物已经把这个符号物化成 `build output` 这串字节，不再保留构建脚本语义。
3. 目录重点是构建期边界，而不是在 SA 里重放 `build.rs`。

