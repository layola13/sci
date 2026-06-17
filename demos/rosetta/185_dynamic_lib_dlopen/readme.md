# 185 - Dynamic Lib dlopen

## 目标特性 (Target Feature)
展示动态库句柄和符号地址如何以“打开、查找、关闭”的顺序流动。

## 当前示例 (Current Demo Shape)
1. 目录里的成功链路固定为 `dlopen("libdemo.so") -> dlsym("demo_entry") -> dlclose(handle)`。
2. SA 版本把 `dlopen` 和 `dlsym` 的原始返回值都先投影成借用视图，再写入 `Lib` 结构中的 `handle` / `symbol` 槽位。
3. 成功条件是句柄非空、符号非空且 `dlclose` 返回 0，最终输出 `1`。

