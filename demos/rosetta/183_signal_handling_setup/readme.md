# 183 - Signal Handling Setup

## 目标特性 (Target Feature)
展示信号编号和处理函数指针如何一起交给宿主注册。

## 当前示例 (Current Demo Shape)
1. 当前目录把 signal handler 放进 `Signal` 结构，显式保存 `num` 和 `handler` 两个槽位。
2. SA 版本通过 `register_signal` 调用 `signal(2, handler)`，并要求注册返回值和保存下来的信号值都等于 `2`。
3. 这个 demo 的重点是函数指针交接和注册边界，不是异步信号处理逻辑本身。

