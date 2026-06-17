# 188 - WebSocket Frame Parse

## 目标特性 (Target Feature)
展示 WebSocket 首部位字段如何拆解成显式标志位与长度字段。

## 当前示例 (Current Demo Shape)
1. 当前样本是一个 `FIN=1`、`opcode=1`、`mask=0`、`payload_len=3` 的 text frame。
2. SA 版本会把 `fin`、`opcode`、`masked`、`len` 和 `payload_sum` 都写回 `Frame` 结构，说明这不是只读判断题。
3. 成功路径输出 `1`，关注点是协议位运算和派生字段落盘。

