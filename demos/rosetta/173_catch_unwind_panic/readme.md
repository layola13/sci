# 173 - Catch Unwind Panic

## 目标特性 (Target Feature)
展示 SA-ASM 目前不支持异常展开，panic 将直接结束进程。

## 降级逻辑预演 (Expected Lowering Logic)
1. **错误载荷外显**：`anyhow` / `eyre` / `thiserror` 这类错误包装都要展开成显式 payload、消息和可选 backtrace，SA 只负责把这些数据装进普通内存。
2. **显式失败路径**：`catch_unwind`、`panic_hook`、`assert!`、`unwrap` / `unwrap_err` 和 `Try Trait V2` 都应该降级成分支跳转、`panic_msg` 和 cleanup block，不能把失败藏在隐式控制流里。
3. **结果扁平化**：`Result` flattening 的意义是把多层 fallible 状态展开成可见 CFG；一旦前端没把每个错误出口画清楚，Referee 就没法保证资源回收。
