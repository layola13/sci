# 194 - CFG Conditional Compilation

## 目标特性 (Target Feature)
展示平台条件分支在进入 SA 之前就已经被裁剪。

## 当前示例 (Current Demo Shape)
1. 当前 SA 成品里只保留了选中的 `x86` 字节序列，没有再把 fallback 分支带进来。
2. `main.sa` 直接验证 `x`、`8`、`6` 三个字节，再输出 `x86`。
3. 这个目录强调的是“条件编译先选枝，再发射目标代码”。

